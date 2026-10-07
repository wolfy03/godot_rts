extends Node3D

const BASE_UNIT: PackedScene = preload("res://scenes/units/base_units/base_unit.tscn")
const COVER_SCENE: PackedScene = preload("res://scenes/units/cover.tscn")

var _failed: bool = false
var _evaluator: CoverEvaluator = CoverEvaluator.new()
var _unit: Unit
var _threat: Unit
var _cover_system: CoverSystem

func _ready() -> void:
	_cover_system = CoverSystem.new()
	add_child(_cover_system)
	_unit = _make_unit(Vector3(-6.0, 1.0, -4.0))
	_threat = _make_unit(Vector3(0.0, 1.0, 8.0), true)
	await _sync_physics()
	_test_batch_context_and_empty_candidates()
	await _test_geometry_scores()
	await _test_improvement_aware_selection()
	_test_virtual_points_and_side_effects()
	await _test_invalid_and_reserved_candidates()
	await _test_ai_threat_and_exact_reservation()
	await _test_take_cover_interruption_and_arrival()
	await _test_candidate_position_stuck()
	print("cover_evaluator_test: %s" % ["FAIL" if _failed else "PASS"])
	get_tree().quit(1 if _failed else 0)

func _test_batch_context_and_empty_candidates() -> void:
	var evaluator: ExposureCountingEvaluator = ExposureCountingEvaluator.new()
	var candidates: Array[CoverCandidate] = [_candidate(_unit.global_position + Vector3.RIGHT)]
	_expect(evaluator.find_best_candidate(null, candidates, _threat).reason == &"invalid_context"
		and evaluator.find_best_candidate(_unit, candidates, null).reason == &"invalid_context",
		"null Unit and threat must report invalid_context in batch evaluation")
	var health: int = _unit._current_health
	_unit._current_health = 0
	_expect(evaluator.find_best_candidate(_unit, candidates, _threat).reason == &"invalid_context",
		"dead Unit must report invalid_context before any exposure rays")
	_unit._current_health = health
	var empty: CoverEvaluationResult = evaluator.find_best_candidate(_unit, [], _threat)
	_expect(not empty.valid and empty.reason == &"no_valid_candidate" and evaluator.exposure_measurements == 0,
		"invalid context and an empty batch must not measure exposure")

func _test_geometry_scores() -> void:
	var exposed: CoverCandidate = _candidate(Vector3(-5.0, 1.0, -4.0))
	var open_result: CoverEvaluationResult = _evaluator.evaluate(_unit, exposed, _threat)
	_expect(open_result.valid and open_result.exposure_ratio > 0.99 and open_result.protection_score < 0.01,
		"unobstructed candidate must be fully exposed")
	_expect(open_result.can_fire_at_threat and is_equal_approx(open_result.travel_distance, 1.0),
		"open candidate must see the threat and use Euclidean travel distance")
	_expect(is_equal_approx(open_result.travel_score, 0.95), "travel score must use the configured 20m distance")
	var cover: Cover = _make_cover(Vector3.ZERO, 4.0, [Vector3(0.0, 1.0, -1.0)])
	await _sync_physics()
	var protected: CoverCandidate = cover.get_cover_candidates()[0]
	var full: CoverEvaluationResult = _evaluator.evaluate(_unit, protected, _threat)
	_expect(full.valid and full.protected_from_threat and full.exposure_ratio < 0.01 and full.protection_score > 0.99,
		"real tall collider must shield the virtual AimPoints")
	_expect(not full.can_fire_at_threat and full.firing_score == 0.0,
		"strong protection may also prevent outgoing fire")
	_expect(full.improves_current_position and full.current_exposure_score > 0.99,
		"shielded candidate must improve on the exposed actual position")
	_unit.evasion_chance = 1.0
	cover.grade = Cover.CoverGrade.HIGH
	var gameplay_changed: CoverEvaluationResult = _evaluator.evaluate(_unit, cover.get_cover_candidates()[0], _threat)
	_expect(is_equal_approx(gameplay_changed.score, full.score), "CoverGrade and gameplay evasion must not alter geometry quality")
	_unit.evasion_chance = 0.0
	var candidates: Array[CoverCandidate] = [exposed, protected]
	var best: CoverEvaluationResult = _evaluator.find_best_candidate(_unit, candidates, _threat)
	_expect(best.valid and best.candidate == protected and full.score > open_result.score,
		"default weights must prefer the farther shielded candidate")
	var expected_score: float = full.protection_score * 0.5 + full.firing_score * 0.25 + full.travel_score * 0.25
	_expect(is_equal_approx(full.score, expected_score), "scoring must use the evaluator's centralized weights")
	_set_cover_height(cover, 1.6)
	await _sync_physics()
	var partial: CoverEvaluationResult = _evaluator.evaluate(_unit, protected, _threat)
	_expect(partial.valid and partial.exposure_ratio > 0.0 and partial.exposure_ratio < 1.0,
		"partial cover must block only some weighted AimPoints")
	_expect(is_equal_approx(partial.exposure_ratio, 0.4) and partial.can_fire_at_threat,
		"head/arms may remain visible while chest/stomach/legs are blocked")
	_expect(partial.protection_score > open_result.protection_score and partial.protection_score < full.protection_score,
		"partial protection must fall between open and fully shielded scores")
	var same_position: CoverCandidate = _candidate(_unit.global_position)
	_expect(not _evaluator.evaluate(_unit, same_position, _threat).improves_current_position,
		"current position must not be presented as a tactical improvement")
	cover.free()
	await _sync_physics()
	print("cover evaluator / open, full, partial, outgoing fire, scoring: %s" % ["FAIL" if _failed else "PASS"])

func _test_improvement_aware_selection() -> void:
	var original_position: Vector3 = _unit.global_position
	_unit.global_position = Vector3(-0.6, 1.0, -1.0)
	var partial_cover: Cover = _make_cover(Vector3.ZERO, 1.6, [Vector3(0.6, 1.0, -1.0)])
	var full_cover: Cover = _make_cover(Vector3(5.0, 0.0, -3.0), 4.0, [Vector3(0.0, 1.0, -1.0)])
	await _sync_physics()
	var nearby: CoverCandidate = partial_cover.get_cover_candidates()[0]
	var improving: CoverCandidate = full_cover.get_cover_candidates()[0]
	var high_score: CoverEvaluationResult = _evaluator.evaluate(_unit, nearby, _threat)
	var lower_score: CoverEvaluationResult = _evaluator.evaluate(_unit, improving, _threat)
	_expect(high_score.valid and high_score.protected_from_threat and high_score.can_fire_at_threat
		and not high_score.improves_current_position, "nearby partial cover must be usable but provide no protection gain")
	_expect(lower_score.valid and lower_score.improves_current_position and high_score.score > lower_score.score,
		"fixture must give the non-improving candidate a higher score than the improving candidate")
	_expect(is_equal_approx(high_score.current_exposure_score, lower_score.current_exposure_score)
		and is_equal_approx(high_score.protection_improvement, 0.0), "standalone evaluations must retain their current-position baseline")
	var best: CoverEvaluationResult = _evaluator.find_best_candidate(_unit, [nearby, improving], _threat)
	_expect(best.valid and best.candidate == improving and best.improves_current_position,
		"best selection must not lose an improving candidate behind a higher non-improving score")
	_expect(is_equal_approx(best.current_exposure_score, lower_score.current_exposure_score)
		and is_equal_approx(best.protection_improvement, lower_score.protection_improvement),
		"batch selection must apply the same baseline as standalone evaluation")
	var none: CoverEvaluationResult = _evaluator.find_best_candidate(_unit, [nearby], _threat)
	_expect(not none.valid and none.candidate == null and none.reason == &"no_improving_candidate",
		"valid but non-improving candidates must report no_improving_candidate")
	nearby.valid = false
	_expect(_evaluator.find_best_candidate(_unit, [nearby], _threat).reason == &"no_valid_candidate",
		"all invalid candidates must still report no_valid_candidate")
	_expect(not _evaluator.find_best_candidate(null, [improving], _threat).valid
		and not _evaluator.find_best_candidate(_unit, [improving], null).valid,
		"batch baseline must not dereference an invalid Unit or threat")
	partial_cover.free()
	full_cover.free()
	_unit.global_position = original_position
	await _sync_physics()
	print("cover evaluator / improvement-aware selection: %s" % ["FAIL" if _failed else "PASS"])

func _test_virtual_points_and_side_effects() -> void:
	_unit.rotation.y = 0.65
	var parent: Node3D = _unit.get_node("AimPoints") as Node3D
	parent.position = Vector3(0.1, 0.1, -0.2)
	parent.rotation.y = 0.2
	parent.scale = Vector3(1.2, 0.8, 0.9)
	var position: Vector3 = Vector3(3.0, 2.0, -4.0)
	var markers: Array[Marker3D] = _unit.get_aim_points()
	var samples: Array[Unit.AimPointData] = _evaluator._get_virtual_aim_points(_unit, position)
	_expect(samples.size() == markers.size(), "virtual samples must retain all known AimPoints")
	for index in samples.size():
		_expect(samples[index].position.is_equal_approx(position + markers[index].global_position - _unit.global_position),
			"virtual points must include nested rotation/scale and world offsets")
		_expect(is_equal_approx(samples[index].weight, _unit.get_aim_point_weight(StringName(markers[index].name))),
			"tactical weights must come from Unit's attack weight definition")
	var transform: Transform3D = _unit.global_transform
	var marker_transform: Transform3D = markers[0].global_transform
	var target: Vector3 = _unit.navigation_agent.target_position
	var state: String = _unit.state_machine.get_current_state_id()
	var result: CoverEvaluationResult = _evaluator.evaluate(_unit, _candidate(position), _threat)
	_expect(result.valid and _unit.global_transform == transform and markers[0].global_transform == marker_transform,
		"evaluation must never teleport the Unit or its AimPoints")
	_expect(_unit.reserved_cover == null and _unit.current_cover == null
		and _unit.navigation_agent.target_position == target and _unit.state_machine.get_current_state_id() == state,
		"evaluation must not reserve, navigate, or transition AI states")
	_unit.rotation = Vector3.ZERO
	parent.transform = Transform3D.IDENTITY

func _test_invalid_and_reserved_candidates() -> void:
	var cover: Cover = _make_cover(Vector3.ZERO, 4.0, [Vector3(0.0, 1.0, -1.0)])
	await _sync_physics()
	var candidate: CoverCandidate = cover.get_cover_candidates()[0]
	var other: Unit = _make_unit(Vector3(6.0, 1.0, -4.0))
	_expect(cover.reserve_candidate(other, candidate) != null, "another unit must be able to reserve the selected slot")
	_expect(_evaluator.evaluate(_unit, candidate, _threat).reason == &"reserved", "another unit's reservation must reject evaluation")
	_expect(_evaluator.evaluate(other, candidate, _threat).valid, "a unit's own reservation must remain eligible")
	other.occupy_reserved_cover()
	_expect(_evaluator.evaluate(_unit, candidate, _threat).reason == &"occupied", "occupied candidates must also be rejected")
	other.clear_cover()
	var navigation: ChunkedUnitNavigation = ChunkedUnitNavigation.new()
	navigation.auto_initialize = false
	navigation.bake_on_dirty = false
	navigation.world_origin = Vector3(-20.0, 0.0, -20.0)
	add_child(navigation)
	navigation.initialize_chunks()
	navigation.set_chunk_walkable(navigation.get_chunk_coords(candidate.position), false)
	_expect(_evaluator.evaluate(_unit, candidate, _threat, navigation).reason == &"unreachable",
		"coarse navigation preflight must reject blocked chunks without querying paths")
	navigation.free()
	_expect(not _evaluator.evaluate(_unit, null, _threat).valid, "null candidate must be invalid")
	candidate.valid = false
	_expect(_evaluator.evaluate(_unit, candidate, _threat).reason == &"invalid_candidate", "explicit invalidity must be honored")
	candidate.valid = true
	var nonfinite: CoverCandidate = _candidate(Vector3(INF, 1.0, 0.0))
	_expect(_evaluator.evaluate(_unit, nonfinite, _threat).reason == &"non_finite_position", "nonfinite positions must be rejected")
	_expect(_evaluator.evaluate(_unit, _candidate(Vector3(100.0, 1.0, 0.0)), _threat).reason == &"too_far", "far candidates must be filtered")
	var same_side: Unit = _make_unit(Vector3(0.0, 1.0, -8.0))
	_expect(_evaluator.evaluate(_unit, candidate, same_side).reason == &"no_protection", "wrong threat direction must be rejected cheaply")
	var blocker: StaticBody3D = _box(candidate.position, Vector3.ONE)
	await _sync_physics()
	_expect(_evaluator.evaluate(_unit, candidate, _threat).reason == &"blocked", "blocked legacy slots must be rejected")
	blocker.free()
	cover.get_cover_slots()[0].position.x = 0.2
	_expect(_evaluator.evaluate(_unit, candidate, _threat).reason == &"stale_slot_position", "moved slots must not use stale snapshots")
	cover.get_cover_slots()[0].free()
	_expect(_evaluator.evaluate(_unit, candidate, _threat).reason == &"missing_slot", "deleted markers must be rejected safely")
	cover.free()
	_expect(_evaluator.evaluate(_unit, candidate, _threat).reason == &"invalid_source", "freed sources must be rejected safely")
	var none: CoverEvaluationResult = _evaluator.find_best_candidate(_unit, [candidate], _threat)
	_expect(not none.valid and none.candidate == null, "no valid candidates must not invent a selection")
	other.free()
	same_side.free()
	await _sync_physics()
	print("cover evaluator / validity, reservation, navigation preflight: %s" % ["FAIL" if _failed else "PASS"])

func _test_ai_threat_and_exact_reservation() -> void:
	_unit.global_position = Vector3(-6.0, 1.0, 0.0)
	var cover: Cover = _make_cover(Vector3.ZERO, 4.0, [Vector3(0.0, 1.0, -1.0), Vector3(0.0, 1.0, 1.0)])
	var nearby: Cover = _make_cover(Vector3(-5.0, 0.0, 0.0), 0.2, [Vector3(0.0, 1.0, -1.0)])
	var opposite: Unit = _make_unit(Vector3(0.0, 1.0, -8.0), true)
	await _sync_physics()
	_unit.clear_player_command()
	_expect(_unit.is_enemy_unit(_threat) and _unit.is_enemy_unit(opposite), "AI fixture must contain two real enemy Units")
	_expect(_unit.get_auto_cover() == nearby, "legacy nearest query must prefer the close unprotective cover in this fixture")
	var nearby_result: CoverEvaluationResult = _evaluator.evaluate(_unit, nearby.get_cover_candidates()[0], _threat)
	_expect(nearby_result.valid and not nearby_result.protected_from_threat,
		"direction alone must not claim protection when all virtual AimPoints are visible")
	var against_a: CoverCandidate = _unit.ai_brain._get_cover_against(_threat)
	var against_b: CoverCandidate = _unit.ai_brain._get_cover_against(opposite)
	_expect(_unit.ai_brain._cover_system == _cover_system
		and _cover_system.get_debug_snapshot()["last_query_candidate_count"] > 0,
		"AI must use the level-local CoverSystem query rather than the legacy collector")
	_cover_system.unregister_cover_source(cover)
	_cover_system.unregister_cover_source(nearby)
	_expect(not _unit.get_legacy_cover_candidates_nearby(20.0).is_empty()
		and _unit.ai_brain._get_cover_against(_threat) == null
		and _cover_system.get_debug_snapshot()["last_query_candidate_count"] == 0,
		"an empty CoverSystem must not leak unregistered covers from the legacy group")
	_cover_system.register_cover_source(cover)
	_cover_system.register_cover_source(nearby)
	_expect(against_a != null and against_b != null, "AI must find protective candidates for both actual threats")
	if against_a != null and against_b != null:
		_expect(against_a.get_source() == cover and against_b.get_source() == cover,
			"AI must prefer geometry quality over target-independent nearest cover")
		_expect(against_a.position.z < 0.0 and against_b.position.z > 0.0
			and against_a.reservation_key != against_b.reservation_key, "opposite threats must select opposite cover slots")
		_unit.ai_brain._issue_cover(against_b)
		_expect(_unit.state_machine.is_current_state(TakeCoverState.ID)
			and _unit.reserved_cover_slot == cover.get_candidate_slot(against_b), "AI must reserve the exact evaluated slot")
		var take_cover: TakeCoverState = _unit.state_machine.get_node("TakeCoverState") as TakeCoverState
		_expect(take_cover._cover_position == against_b.position, "candidate snapshot must supply the movement destination")
		_unit.global_position = against_b.position
		_unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
		take_cover._process_state(0.0)
		_expect(_unit.current_cover == cover and not _unit.movement_enabled, "candidate arrival must retain legacy occupancy behavior")
		_unit.clear_cover()
		# Another unit wins after evaluation: TakeCoverState must not fall back to
		# the still-free opposite slot, which would undo the tactical selection.
		var other: Unit = _make_unit(Vector3(6.0, 1.0, 0.0))
		cover.reserve_candidate(other, against_b)
		_unit.state_machine.transition_to_state(TakeCoverState.ID, against_b)
		_expect(_unit.state_machine.is_current_state(IdleState.ID) and _unit.reserved_cover_slot == null,
			"reservation races must fail safely without switching to a different slot")
		other.clear_cover()
		_unit.state_machine.transition_to_state(TakeCoverState.ID, TakeCoverState.CoverCommandData.new(against_a))
		_expect(_unit.reserved_cover_slot == cover.get_candidate_slot(against_a), "command wrapper must accept a candidate")
		take_cover._switch_to_alternate_cover()
		_expect(_unit.state_machine.is_current_state(IdleState.ID) and _unit.reserved_cover_slot == null,
			"stuck candidate commands must release for re-evaluation instead of choosing a nearest Cover")
		_unit.clear_cover()
		other.free()
	nearby.free()
	cover.free()
	opposite.free()
	await _sync_physics()
	print("cover evaluator / threat-based AI and exact reservation: %s" % ["FAIL" if _failed else "PASS"])

func _test_take_cover_interruption_and_arrival() -> void:
	var unit: Unit = _make_unit(Vector3(-4.0, 1.0, -1.0))
	var cover: Cover = _make_cover(Vector3.ZERO, 4.0, [Vector3(0.0, 1.0, -1.0)])
	# Keep real detection/attack areas but isolate state changes from skill effects.
	unit._skills.clear()
	# Disabled processing freezes movement/states, but must not remove these
	# collision objects from the physics space used by real Area3D detection.
	var threat_disable_mode: int = _threat.disable_mode
	_threat.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	unit.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	unit.enemy_detection_area.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	unit.attack_range_area.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	await _sync_physics()
	unit.clear_player_command()
	_expect(unit.get_nearest_detected_enemy() == _threat and unit.get_nearest_attackable_unit_in_range() == _threat,
		"interruption fixture must offer a real detected, attackable threat")
	_expect(unit.ai_brain.request_decision() and unit.state_machine.is_current_state(TakeCoverState.ID),
		"AI must select and enter TakeCover before interruption checks")
	var slot: Marker3D = unit.reserved_cover_slot
	_expect(slot != null and unit.reserved_cover == cover and unit.current_cover == null,
		"cover command must still be travelling toward its reserved slot")
	for index in 6:
		_expect(not unit.ai_brain.request_decision(index % 2 == 0),
			"repeated decisions must defer all autonomous actions during cover travel")
		_expect(unit.state_machine.is_current_state(TakeCoverState.ID) and unit.reserved_cover == cover
			and unit.reserved_cover_slot == slot and unit.current_cover == null,
			"decision ticks must preserve TakeCover and its exact reservation")
	if slot != null:
		unit.global_position = slot.global_position
		await _sync_physics()
		var take_cover: TakeCoverState = unit.state_machine.get_node("TakeCoverState") as TakeCoverState
		take_cover._process_state(0.0)
		_expect(unit.current_cover == cover and unit.state_machine.is_current_state(AttackState.ID),
			"arrival must occupy cover and allow its AI callback to transition to Attack")
		var attack: AttackState = unit.state_machine.get_node("AttackState") as AttackState
		_expect(attack._attack_target == _threat, "resumed AI must attack the actual detected threat")
	unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
	unit.clear_cover()
	_threat.disable_mode = threat_disable_mode
	unit.free()
	cover.free()
	await _sync_physics()
	print("cover evaluator / TakeCover interruption and arrival: %s" % ["FAIL" if _failed else "PASS"])

func _test_candidate_position_stuck() -> void:
	var cover: Cover = _make_cover(Vector3.ZERO, 4.0, [Vector3(4.0, 1.0, 0.0)])
	var candidate: CoverCandidate = cover.get_cover_candidates()[0]
	var unit: Unit = _make_unit(candidate.position + Vector3(3.0, 0.0, 0.0))
	unit.cover_slot_hold_radius = 0.2
	await _sync_physics()
	unit.state_machine.transition_to_state(TakeCoverState.ID, candidate)
	var take_cover: TakeCoverState = unit.state_machine.get_node("TakeCoverState") as TakeCoverState
	_expect(take_cover._candidate == candidate and unit.reserved_cover == cover,
		"stuck fixture must activate an exact candidate command")
	# A remote route waypoint must not accumulate final-destination stuck time.
	take_cover._route_waypoint = unit.global_position
	for index in 5:
		_expect(not take_cover._process_stuck_near_cover(0.25), "remote route waypoint must not trigger final-slot stuck handling")
	_expect(take_cover._stuck_timer == 0.0 and unit.reserved_cover == cover,
		"tracking away from the final candidate must reset without releasing its reservation")
	take_cover._route_waypoint = Vector3.INF
	unit.global_position = candidate.position + Vector3(0.5, 0.0, 0.0)
	take_cover._reset_stuck_tracking()
	_expect(not unit.is_in_reserved_cover_slot()
		and take_cover._get_horizontal_distance(unit.global_position, candidate.position) < take_cover.stuck_cover_distance
		and take_cover._get_horizontal_distance(unit.global_position, cover.global_position) > 3.0,
		"fixture must be outside arrival radius, near the candidate, and far from the Cover center")
	for index in 3:
		take_cover._process_state(0.25)
	_expect(unit.state_machine.is_current_state(TakeCoverState.ID) and unit.reserved_cover == cover,
		"stuck handling must wait for its full configured duration")
	take_cover._process_state(0.25)
	_expect(unit.state_machine.is_current_state(IdleState.ID) and unit.reserved_cover == null
		and unit.reserved_cover_slot == null and cover.get_slot_occupant(cover.get_cover_slots()[0]) == null,
		"stuck near the chosen candidate must release its reservation and return to Idle")
	unit.free()
	cover.free()
	await _sync_physics()
	print("cover evaluator / candidate-position stuck: %s" % ["FAIL" if _failed else "PASS"])

func _make_unit(position: Vector3, enemy: bool = false) -> Unit:
	var unit: Unit = BASE_UNIT.instantiate() as Unit
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.position = position
	if enemy:
		unit.collision_layer = Unit.ENEMY_UNIT_MASK
	unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
	(unit.get_node("NavigationAgent") as NavigationAgent3D).avoidance_enabled = false
	add_child(unit)
	return unit

func _make_cover(position: Vector3, height: float, slot_positions: Array[Vector3]) -> Cover:
	var cover: Cover = COVER_SCENE.instantiate() as Cover
	cover.position = position
	var slots: Node = cover.get_node("CoverSlots")
	for child: Node in slots.get_children():
		child.free()
	for index in slot_positions.size():
		var marker: Marker3D = Marker3D.new()
		marker.name = "Slot%d" % index
		marker.position = slot_positions[index]
		slots.add_child(marker)
	_set_cover_height(cover, height)
	add_child(cover)
	_cover_system.register_cover_source(cover)
	return cover

func _set_cover_height(cover: Cover, height: float) -> void:
	var collider: CollisionShape3D = cover.get_node("CollisionShape3D") as CollisionShape3D
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(4.0, height, 1.0)
	collider.shape = shape
	collider.position.y = height * 0.5

func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = position
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	return body

func _candidate(position: Vector3) -> CoverCandidate:
	var candidate: CoverCandidate = CoverCandidate.new()
	candidate.position = position
	return candidate

func _sync_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

class ExposureCountingEvaluator extends CoverEvaluator:
	var exposure_measurements: int = 0

	func _measure_exposure(unit: Unit, position: Vector3, threat: Unit) -> float:
		exposure_measurements += 1
		return super._measure_exposure(unit, position, threat)
