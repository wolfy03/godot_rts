extends StateMachine.State
class_name TakeCoverState

const ID = "TAKE_COVER_STATE"

@export var stuck_cover_distance: float = 1.0
@export var stuck_duration: float = 1.0
@export var stuck_sample_interval: float = 0.25
@export var stuck_min_sample_distance: float = 0.03

var _cover: Cover
var _cover_position: Vector3
var _cover_slot: Marker3D
var _candidate: CoverCandidate
var _uses_runtime_reservation: bool = false
var _route_waypoint: Vector3 = Vector3.INF
var _last_sample_position: Vector3 = Vector3.INF
var _stuck_sample_timer := 0.0
var _stuck_timer := 0.0

func _get_id() -> String:
	return ID

func _activate(data) -> void:
	super._activate(data)
	if not _is_active:
		return

	_unit.movement_enabled = true

	# Same-state activation can replace a runtime command without _deactivate().
	# Clear the old acquisition before switching reservation backends.
	if _unit.reserved_cover_candidate != null:
		_unit.clear_cover()
	_candidate = data.candidate if data is CoverCommandData else data as CoverCandidate
	_cover = _candidate.get_source() as Cover if _candidate != null else data as Cover
	_cover_slot = null
	_route_waypoint = Vector3.INF
	_uses_runtime_reservation = _candidate != null and _cover == null
	if _uses_runtime_reservation:
		_activate_runtime_candidate()
		return
	if not is_instance_valid(_cover):
		_fail_cover_command()
		return
	_activate_legacy_cover()

func _activate_runtime_candidate() -> void:
	var system: CoverSystem = _resolve_runtime_cover_system()
	if system == null or not _unit.reserve_runtime_cover_candidate(_candidate, system):
		_fail_cover_command()
		return
	_cover_position = _candidate.position
	# Runtime execution always submits one final target to NavigationAgent.
	_route_waypoint = Vector3.INF
	_reset_stuck_tracking()
	_update_navigation_target()
	if _unit.is_in_runtime_cover_candidate():
		_unit.occupy_runtime_cover_candidate()

func _activate_legacy_cover() -> void:

	if _candidate == null and _unit.current_cover != null and _unit.current_cover != _cover:
		_unit.clear_cover()

	_cover_slot = _cover.reserve_candidate(_unit, _candidate) if _candidate != null else _cover.reserve_slot(_unit)
	if _cover_slot == null:
		_unit.clear_cover()
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)
		return

	_cover_position = _candidate.position if _candidate != null else _cover_slot.global_position
	_route_waypoint = _cover.get_navigation_route_waypoint(_unit.global_position, _cover_position)
	_reset_stuck_tracking()
	_update_navigation_target()

	if _unit.is_in_reserved_cover_slot():
		_unit.occupy_reserved_cover()

func _deactivate() -> void:
	# Occupied cover survives the arrival -> Attack handoff, just like legacy
	# cover. Unit.clear_cover() owns release once the state is no longer active.
	if _uses_runtime_reservation and is_instance_valid(_unit) \
			and _unit.reserved_cover_candidate != null and _unit.current_cover_candidate == null:
		_unit.clear_cover()
		_stop_runtime_movement()
	super._deactivate()

func _process_state(_delta: float) -> void:
	if _uses_runtime_reservation:
		_process_runtime_candidate(_delta)
		return
	if not is_instance_valid(_cover):
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)
		return

	if _unit.current_cover == null and _unit.reserved_cover == null and _cover_slot != null:
		_cover_slot = null
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)
		return

	if _cover_slot == null:
		_cover_slot = _cover.get_reserved_slot(_unit)
		if _cover_slot != null:
			_cover_position = _cover_slot.global_position
			if _route_waypoint == Vector3.INF:
				_route_waypoint = _cover.get_navigation_route_waypoint(_unit.global_position, _cover_position)
			_reset_stuck_tracking()
			_update_navigation_target()
		else:
			_deactivate()
			transition_to_state.emit(IdleState.ID, null)
			return

	if _unit.is_in_reserved_cover_slot():
		if _unit.current_cover != _cover:
			_unit.occupy_reserved_cover()
			_unit.finish_player_command(Unit.PlayerCommandMode.MOVE)

		if _unit.ai_brain != null:
			_unit.ai_brain.request_decision()
		return

	if _unit.navigation_agent.is_navigation_finished():
		if _route_waypoint != Vector3.INF:
			_route_waypoint = Vector3.INF
			_reset_stuck_tracking()
			_update_navigation_target()
			return

	if _process_stuck_near_cover(_delta):
		return

func _resolve_runtime_cover_system() -> CoverSystem:
	# Activation-only lookup; independent from AIBrain's retry/cache policy.
	for node: Node in _unit.get_tree().get_nodes_in_group("cover_system"):
		var system: CoverSystem = node as CoverSystem
		if is_instance_valid(system) and system.is_inside_tree() and not system.is_queued_for_deletion() \
				and system.get_world_3d() == _unit.get_world_3d():
			return system
	return null

func _process_runtime_candidate(delta: float) -> void:
	var system: CoverSystem = _unit.get_runtime_cover_system()
	if system == null or _unit.reserved_cover_candidate != _candidate or not _unit.has_live_runtime_cover_source() \
			or system.get_runtime_candidate_occupant(_candidate) != _unit:
		_fail_cover_command()
		return
	if _unit.is_in_runtime_cover_candidate():
		if _unit.current_cover_candidate == null:
			_unit.occupy_runtime_cover_candidate()
			_unit.finish_player_command(Unit.PlayerCommandMode.MOVE)
		if _unit.ai_brain != null:
			_unit.ai_brain.request_decision()
		return
	_process_stuck_near_cover(delta)

func _stop_runtime_movement() -> void:
	_unit.velocity = Vector3.ZERO
	if _unit.navigation_agent != null:
		_unit.navigation_agent.velocity = Vector3.ZERO
		_unit.navigation_agent.target_position = _unit.global_position

func _fail_cover_command() -> void:
	_unit.clear_cover()
	if _uses_runtime_reservation:
		_stop_runtime_movement()
	_deactivate()
	transition_to_state.emit(IdleState.ID, null)

func _update_navigation_target() -> void:
	if _unit.navigation_agent == null:
		return

	if _route_waypoint != Vector3.INF:
		_unit.navigation_agent.target_position = _route_waypoint
	else:
		_unit.navigation_agent.target_position = _cover_position

func _reset_stuck_tracking() -> void:
	_last_sample_position = _unit.global_position
	_stuck_sample_timer = 0.0
	_stuck_timer = 0.0

func _process_stuck_near_cover(delta: float) -> bool:
	var arrived: bool = _unit.is_in_runtime_cover_candidate() if _uses_runtime_reservation else _unit.is_in_reserved_cover_slot()
	if (not _uses_runtime_reservation and not is_instance_valid(_cover)) or arrived:
		_reset_stuck_tracking()
		return false
	# The reserved destination can be far from a large Cover's origin. Route
	# waypoints away from the final slot still reset tracking here.
	if _get_horizontal_distance(_unit.global_position, _cover_position) > stuck_cover_distance:
		_reset_stuck_tracking()
		return false

	_stuck_sample_timer += delta
	if _stuck_sample_timer < stuck_sample_interval:
		return false

	var sample_duration := _stuck_sample_timer
	_stuck_sample_timer = 0.0
	var moved_distance := _get_horizontal_distance(_unit.global_position, _last_sample_position)
	_last_sample_position = _unit.global_position
	if moved_distance >= stuck_min_sample_distance:
		_stuck_timer = 0.0
		return false

	_stuck_timer += sample_duration
	if _stuck_timer < stuck_duration:
		return false

	return _switch_to_alternate_cover()

func _switch_to_alternate_cover() -> bool:
	if _candidate != null:
		# A tactical command must not silently choose a target-independent Cover.
		# Release it for a fresh AI decision instead of picking another Cover here.
		_fail_cover_command()
		return true
	var stuck_cover := _cover
	var alternate_cover := _unit.find_nearest_cover_to(_unit.global_position, _unit.auto_cover_search_radius, stuck_cover)
	if alternate_cover == null:
		_reset_stuck_tracking()
		return false

	_unit.clear_cover()
	_deactivate()
	transition_to_state.emit(TakeCoverState.ID, alternate_cover)
	return true

func _get_horizontal_distance(from: Vector3, to: Vector3) -> float:
	var flat_from := Vector2(from.x, from.z)
	var flat_to := Vector2(to.x, to.z)
	return flat_from.distance_to(flat_to)

class CoverCommandData:
	var candidate: CoverCandidate

	func _init(selected_candidate: CoverCandidate = null) -> void:
		candidate = selected_candidate

func _on_enemy_detection_area_body_entered(_body: Node3D) -> void:
	if _is_active and _unit.ai_brain != null:
		_unit.ai_brain.request_decision()
