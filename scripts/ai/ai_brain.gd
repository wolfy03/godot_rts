extends Node
class_name AIBrain

const STATE_IDLE := "IDLE_STATE"
const STATE_MOVE := "MOVE_STATE"
const STATE_ATTACK := "ATTACK_STATE"
const STATE_CHASE := "CHASE_STATE"
const STATE_HOLD_POSITION := "HOLD_POSITION_STATE"
const STATE_TAKE_COVER := "TAKE_COVER_STATE"
const STATE_HEAL := "HEAL_STATE"

@export var decision_interval: float = 0.25
@export var medic_heal_search_radius: float = 12.0
@export var max_cover_search_radius: float = 20.0
@export_range(0.01, 60.0, 0.01) var cover_system_lookup_retry_interval: float = 1.0
@export var debug_cover_evaluation: bool = false

var _unit: Unit
var _decision_timer: Timer
var _cover_evaluator: CoverEvaluator = CoverEvaluator.new()
var _cover_system: CoverSystem = null
var _cover_system_retry_after_msec: int = 0
var _cover_system_fallback_logged: bool = false

func _ready() -> void:
	_unit = owner as Unit
	if _unit == null:
		_unit = get_parent() as Unit

	if _unit == null:
		push_error("AIBrain must be owned by Unit or child of Unit.")
		return

	_decision_timer = Timer.new()
	_decision_timer.wait_time = maxf(decision_interval, 0.01)
	_decision_timer.timeout.connect(_on_decision_timer_timeout)
	add_child(_decision_timer)
	_decision_timer.start()
	call_deferred("_on_decision_timer_timeout")

func _on_decision_timer_timeout() -> void:
	request_decision()

func request_decision(allow_move_interrupt: bool = false) -> bool:
	if not _can_think():
		return false

	var current_state_id := _unit.state_machine.get_current_state_id()
	# Preserve the selected reservation until arrival. Once occupied, cover's
	# arrival callback may resume combat/healing/skill decisions normally.
	if current_state_id == STATE_TAKE_COVER and _unit.reserved_cover != null and _unit.current_cover == null:
		return false
	if current_state_id == STATE_HOLD_POSITION:
		return false
	if current_state_id == STATE_HEAL:
		return false
	if current_state_id == STATE_MOVE and not allow_move_interrupt:
		return false

	if _unit.unit_class == Unit.UnitClass.MEDIC:
		var wounded_ally := _unit.get_nearest_wounded_ally(medic_heal_search_radius)
		if wounded_ally != null:
			_issue_heal(wounded_ally)
			return true

	return _request_combat_decision(current_state_id, allow_move_interrupt)

func _can_think() -> bool:
	if not is_instance_valid(_unit) or _unit._is_dead:
		return false
	if _unit.is_player_agent():
		return false
	if _unit.state_machine == null:
		return false
	if _unit.blocks_autonomous_ai():
		return false

	return true

func _request_combat_decision(current_state_id: String, allow_move_interrupt: bool) -> bool:
	var detected_enemy := _unit.get_nearest_detected_enemy()
	if detected_enemy != null:
		var cover := _get_cover_against(detected_enemy)
		if cover != null and current_state_id != STATE_TAKE_COVER:
			_issue_cover(cover)
			return true

	if _unit.try_use_ai_skill():
		return true

	if current_state_id == STATE_ATTACK or current_state_id == STATE_CHASE:
		return false

	var attackable_target := _unit.get_nearest_attackable_unit_in_range()
	if attackable_target != null:
		_issue_attack(attackable_target)
		return true

	if detected_enemy != null and (current_state_id == STATE_IDLE or allow_move_interrupt):
		_issue_chase(detected_enemy)
		return true

	if current_state_id == STATE_IDLE:
		var idle_cover: CoverCandidate = _get_idle_cover_candidate()
		if idle_cover != null:
			_issue_cover(idle_cover)
			return true

	return false

func _get_cover_against(target: Unit) -> CoverCandidate:
	if not _unit.should_prioritize_cover_against(target):
		return null

	_cover_evaluator.max_travel_distance = max_cover_search_radius
	var result: CoverEvaluationResult = _cover_evaluator.find_best_candidate(_unit,
		_query_cover_candidates(max_cover_search_radius), target, _get_cover_navigation_context())
	if debug_cover_evaluation:
		print("[COVER] valid=%s score=%.3f exposure=%.3f improvement=%.3f reason=%s"
			% [result.valid, result.final_score, result.exposure_score, result.protection_improvement, result.reason])
	return result.candidate if result.valid else null

func _query_cover_candidates(radius: float) -> Array[CoverCandidate]:
	var candidates: Array[CoverCandidate]
	var cover_system: CoverSystem = _get_cover_system()
	if cover_system != null:
		candidates = cover_system.query_candidates(_unit.global_position, radius)
	else:
		# Temporary compatibility fallback. Remove after every combat level owns
		# a CoverSystem. An empty registry never falls back to the covers group.
		candidates = _unit.get_legacy_cover_candidates_nearby(radius)
	return candidates

func _get_idle_cover_candidate() -> CoverCandidate:
	if not _unit.should_auto_take_cover():
		return null
	var nearest: CoverCandidate = null
	var nearest_distance_sq: float = INF
	for candidate: CoverCandidate in _query_cover_candidates(_unit.auto_cover_search_radius):
		if candidate == null:
			continue
		var distance_sq: float = _unit.global_position.distance_squared_to(candidate.position)
		if distance_sq < nearest_distance_sq and _is_idle_candidate_available(candidate):
			nearest = candidate
			nearest_distance_sq = distance_sq
	return nearest

func _is_idle_candidate_available(candidate: CoverCandidate) -> bool:
	if candidate == null or not candidate.is_valid_candidate() or not candidate.position.is_finite():
		return false
	# Temporary execution constraint: Stage 2 needs source-independent reservation
	# before source-less/runtime candidates can participate in idle commands.
	var cover: Cover = candidate.get_source() as Cover
	if not is_instance_valid(cover) or not cover.is_inside_tree() or cover.is_queued_for_deletion() \
			or cover.get_world_3d() != _unit.get_world_3d():
		return false
	var slot: Marker3D = cover.get_candidate_slot(candidate)
	if slot == null or not slot.global_position.is_equal_approx(candidate.position):
		return false
	var occupant: Unit = cover.get_slot_occupant(slot)
	return occupant == _unit or (occupant == null and not cover.is_slot_blocked(slot))

func _get_cover_system() -> CoverSystem:
	if is_instance_valid(_cover_system) and _cover_system.is_inside_tree() \
			and not _cover_system.is_queued_for_deletion() and _cover_system.get_world_3d() == _unit.get_world_3d():
		return _cover_system
	if _cover_system != null:
		# A deleted, detached, queued or foreign-world service is not a valid cache.
		_cover_system = null
		_cover_system_retry_after_msec = 0
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _cover_system_retry_after_msec:
		return null
	for node: Node in _unit.get_tree().get_nodes_in_group("cover_system"):
		var system: CoverSystem = node as CoverSystem
		if is_instance_valid(system) and not system.is_queued_for_deletion() \
				and system.get_world_3d() == _unit.get_world_3d():
			_cover_system = system
			_cover_system_retry_after_msec = 0
			_cover_system_fallback_logged = false
			return system
	# A miss is temporary. Bound group lookups while allowing late level setup.
	_cover_system_retry_after_msec = now_msec + int(maxf(cover_system_lookup_retry_interval, 0.01) * 1000.0)
	if debug_cover_evaluation and not _cover_system_fallback_logged:
		print("[COVER] CoverSystem unavailable; using legacy query fallback.")
		_cover_system_fallback_logged = true
	return null

func _get_cover_navigation_context() -> ChunkedUnitNavigation:
	for node: Node in _unit.get_tree().get_nodes_in_group("chunked_unit_navigation"):
		var navigation: ChunkedUnitNavigation = node as ChunkedUnitNavigation
		if is_instance_valid(navigation):
			return navigation
	return null

func _issue_heal(target: Unit) -> void:
	_unit.clear_cover()
	_unit.state_machine.transition_to_state(STATE_HEAL, target)

func _issue_attack(target: Unit) -> void:
	_unit.state_machine.transition_to_state(STATE_ATTACK, target)

func _issue_chase(target: Unit) -> void:
	_unit.state_machine.transition_to_state(STATE_CHASE, target)

func _issue_cover(cover: Variant) -> void:
	var data: Variant = TakeCoverState.CoverCommandData.new(cover) if cover is CoverCandidate else cover
	_unit.state_machine.transition_to_state(STATE_TAKE_COVER, data)
