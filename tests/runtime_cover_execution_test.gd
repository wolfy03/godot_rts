extends Node3D

const BASE_UNIT: PackedScene = preload("res://scenes/units/base_units/base_unit.tscn")
const COVER_SCENE: PackedScene = preload("res://scenes/units/cover.tscn")

var _failed: bool = false
var _system: CoverSystem

func _ready() -> void:
	_system = CoverSystem.new()
	add_child(_system)
	_test_reservation_contract()
	_test_invalid_and_world_context()
	await _test_runtime_activation_arrival_and_ai()
	_test_competition_and_stuck()
	_test_cancel_clear_death_and_backend_loss()
	_test_legacy_backend_switching()
	await _test_real_agent_movement(false)
	await _test_real_agent_movement(true)
	print("runtime_cover_execution_test: %s" % ["FAIL" if _failed else "PASS"])
	get_tree().quit(1 if _failed else 0)

func _test_reservation_contract() -> void:
	var a: Unit = _make_unit(Vector3(-10.0, 1.0, 0.0))
	var b: Unit = _make_unit(Vector3(10.0, 1.0, 0.0))
	var candidate: CoverCandidate = _candidate(&"runtime:ownership", Vector3(0.0, 1.0, 0.0))
	var same_key: CoverCandidate = _candidate(candidate.reservation_key, Vector3(4.0, 1.0, 0.0))
	_expect(_system.reserve_candidate(a, candidate) and _system.reserve_candidate(a, candidate),
		"runtime acquisition and self re-reservation must succeed")
	_expect(_system.is_candidate_available(a, candidate), "an owner's runtime key remains available to itself")
	_expect(not _system.reserve_candidate(b, same_key) and not _system.is_candidate_available(b, candidate),
		"key, not position or snapshot object identity, must prevent competing ownership")
	_system.release_candidate(b, candidate)
	_expect(_system.get_runtime_candidate_occupant(candidate) == a, "a non-owner cannot release another unit's key")
	candidate.valid = false
	_system.release_candidate(a, candidate)
	candidate.valid = true
	_expect(_system.reserve_candidate(b, candidate), "release must work even after explicit candidate invalidation")
	_system.release_candidate(b, candidate)
	_system.reserve_candidate(a, candidate)
	a.free()
	_expect(_system.reserve_candidate(b, candidate), "freed Unit weak references must be pruned on reserve")
	remove_child(b)
	_expect(_system.get_debug_snapshot().runtime_reservation_count == 0, "tree-exited Units cannot retain registry ownership")
	add_child(b)
	_system.reserve_candidate(b, candidate)
	b.queue_free()
	_expect(_system.get_debug_snapshot().runtime_reservation_count == 0, "queued Unit ownership must also be pruned")
	b.free()
	_report("reservation / competition / idempotence / release / stale WeakRef")

func _test_invalid_and_world_context() -> void:
	var unit: Unit = _make_unit(Vector3(-10.0, 1.0, 0.0))
	var invalid: CoverCandidate = _candidate(&"runtime:invalid", Vector3.ZERO)
	invalid.valid = false
	_expect(not _system.reserve_candidate(unit, invalid), "invalid candidates must not acquire ownership")
	invalid.valid = true
	invalid.position = Vector3.INF
	_expect(not _system.reserve_candidate(unit, invalid), "non-finite positions must be rejected")
	invalid.position = Vector3.ZERO
	invalid.reservation_key = &""
	_expect(not _system.reserve_candidate(unit, invalid) and not _system.reserve_candidate(null, invalid),
		"missing identity and missing Unit must be rejected")
	var source: Node3D = Node3D.new()
	add_child(source)
	var bound: CoverCandidate = _candidate(&"runtime:non_cover_source", Vector3(0.0, 1.0, 0.0))
	bound.source = source
	unit.state_machine.transition_to_state(TakeCoverState.ID, bound)
	_expect(unit.reserved_cover_candidate == bound and unit.reserved_cover == null,
		"a live non-Cover source may execute through the runtime backend")
	unit.clear_cover()
	unit.state_machine.transition_to_state(IdleState.ID, null)
	source.free()
	_expect(not _system.reserve_candidate(unit, bound), "a deleted bound source is not a source-less candidate")
	var viewport: SubViewport = SubViewport.new()
	viewport.world_3d = World3D.new()
	add_child(viewport)
	var foreign: CoverSystem = CoverSystem.new()
	viewport.add_child(foreign)
	_expect(not foreign.reserve_candidate(unit, _candidate(&"runtime:foreign", Vector3.ZERO)),
		"runtime ownership must reject a Unit in another World3D")
	unit.free()
	viewport.free()
	_report("validation / non-Cover source / World3D isolation")

func _test_runtime_activation_arrival_and_ai() -> void:
	var unit: Unit = _make_unit(Vector3(-4.0, 1.0, -1.0))
	var threat: Unit = _make_unit(Vector3(0.0, 1.0, 6.0), true)
	var candidate: CoverCandidate = _candidate(&"runtime:arrival", Vector3(0.0, 1.0, -1.0))
	await _sync_physics()
	unit.clear_player_command()
	unit.ai_brain._issue_cover(candidate)
	var take: TakeCoverState = unit.state_machine.get_node("TakeCoverState") as TakeCoverState
	_expect(take._is_active and unit.state_machine.is_current_state(TakeCoverState.ID)
		and unit.reserved_cover_candidate == candidate and unit.current_cover_candidate == null,
		"AI candidate command must activate runtime travel and reserve its identity")
	_expect(unit.reserved_cover == null and unit.reserved_cover_slot == null and unit.current_cover == null
		and take._route_waypoint == Vector3.INF and unit.navigation_agent.target_position == candidate.position,
		"runtime activation must use the final target without legacy Cover/Marker/route state")
	for index in 6:
		_expect(not unit.ai_brain.request_decision(index % 2 == 0)
			and unit.state_machine.is_current_state(TakeCoverState.ID), "AI must not interrupt reserved runtime travel")
	_expect(unit.is_cover_travel_in_progress() and not unit.should_auto_take_cover(),
		"runtime travel must block duplicate autonomous cover commands")
	unit.global_position = candidate.position + Vector3.UP * (unit.navigation_agent.height + 1.0)
	take._process_state(0.0)
	_expect(unit.current_cover_candidate == null, "same XZ on a different floor must not count as arrival")
	unit.global_position = candidate.position
	await _sync_physics()
	take._process_state(0.0)
	_expect(unit.current_cover_candidate == candidate and not unit.movement_enabled
		and not unit.is_cover_travel_in_progress() and not unit.should_auto_take_cover(),
		"arrival must mark occupancy, stop movement and unblock the travel guard")
	_expect(unit.state_machine.is_current_state(AttackState.ID)
		and _system.get_runtime_candidate_occupant(candidate) == unit,
		"arrival callback must resume real combat while retaining occupied key ownership")
	_expect(unit._cover_effect_instance_id == 0 and unit.current_cover == null,
		"runtime geometry cover must not receive a legacy grade buff")
	var attack: AttackState = unit.state_machine.get_node("AttackState") as AttackState
	attack._exit()
	_expect(unit.state_machine.is_current_state(TakeCoverState.ID) and unit.current_cover_candidate == candidate,
		"combat completion must return to the occupied runtime candidate")
	unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
	unit.clear_cover()
	unit.clear_cover()
	_expect(_system.get_runtime_candidate_occupant(candidate) == null and unit.reserved_cover_candidate == null
		and unit.current_cover_candidate == null, "clear_cover must release runtime occupancy idempotently")
	unit.free()
	threat.free()
	_report("AI command / final target / height / arrival / combat guard / occupation / no grade buff")

func _test_competition_and_stuck() -> void:
	var a: Unit = _make_unit(Vector3(-4.0, 1.0, 0.0))
	var b: Unit = _make_unit(Vector3(4.0, 1.0, 0.0))
	var candidate: CoverCandidate = _candidate(&"runtime:race", Vector3(0.0, 1.0, 0.0))
	var evaluator: CoverEvaluator = CoverEvaluator.new()
	_expect(evaluator.evaluate(a, candidate, b).valid, "source-less candidate must remain evaluable before acquisition")
	_system.reserve_candidate(b, candidate)
	a.state_machine.transition_to_state(TakeCoverState.ID, candidate)
	_expect(a.state_machine.is_current_state(IdleState.ID) and a.reserved_cover_candidate == null
		and _system.get_runtime_candidate_occupant(candidate) == b,
		"lost reservation race must return Idle without stealing or substituting a target")
	_system.release_candidate(b, candidate)
	a.cover_slot_hold_radius = 0.2
	a.global_position = candidate.position + Vector3.RIGHT * 0.5
	a.state_machine.transition_to_state(TakeCoverState.ID, TakeCoverState.CoverCommandData.new(candidate))
	var take: TakeCoverState = a.state_machine.get_node("TakeCoverState") as TakeCoverState
	for index in 3:
		take._process_state(0.25)
	_expect(a.reserved_cover_candidate == candidate, "runtime stuck must wait for the configured duration")
	take._process_state(0.25)
	_expect(a.state_machine.is_current_state(IdleState.ID) and a.reserved_cover_candidate == null
		and a.current_cover_candidate == null and _system.get_runtime_candidate_occupant(candidate) == null,
		"candidate-position stuck must clear state and release the key without legacy fallback")
	a.free()
	b.free()
	_report("post-evaluation reservation race / candidate-position stuck release")

func _test_cancel_clear_death_and_backend_loss() -> void:
	var unit: Unit = _make_unit(Vector3(-4.0, 1.0, 0.0))
	var candidate: CoverCandidate = _candidate(&"runtime:cleanup", Vector3(0.0, 1.0, 0.0))
	unit.state_machine.transition_to_state(TakeCoverState.ID, candidate)
	unit.state_machine.transition_to_state(HoldPositionState.ID, null)
	_expect(_system.get_runtime_candidate_occupant(candidate) == null and unit.reserved_cover_candidate == null,
		"cancelling travel via state transition must release ownership")
	unit.state_machine.transition_to_state(TakeCoverState.ID, candidate)
	unit.begin_player_command(Unit.PlayerCommandMode.MOVE)
	_expect(_system.get_runtime_candidate_occupant(candidate) == null and unit.reserved_cover_candidate == null,
		"player command overwrite must clear runtime reservations")
	unit.state_machine.transition_to_state(TakeCoverState.ID, candidate)
	unit.clear_cover()
	_expect(_system.get_runtime_candidate_occupant(candidate) == null, "manual clear must release during travel")
	unit.state_machine.transition_to_state(TakeCoverState.ID, candidate)
	remove_child(_system)
	var take: TakeCoverState = unit.state_machine.get_node("TakeCoverState") as TakeCoverState
	take._process_state(0.0)
	add_child(_system)
	_expect(unit.state_machine.is_current_state(IdleState.ID) and unit.reserved_cover_candidate == null
		and _system.get_runtime_candidate_occupant(candidate) == null, "lost backend must fail cleanly without resolving a substitute")
	unit.state_machine.transition_to_state(TakeCoverState.ID, candidate)
	unit.die()
	_expect(_system.get_runtime_candidate_occupant(candidate) == null and unit.reserved_cover_candidate == null,
		"death must release runtime ownership immediately")
	unit.free()
	var no_service: Unit = _make_unit(Vector3(-4.0, 1.0, 0.0))
	remove_child(_system)
	no_service.state_machine.transition_to_state(TakeCoverState.ID, candidate)
	_expect(no_service.state_machine.is_current_state(IdleState.ID) and no_service.reserved_cover_candidate == null,
		"runtime commands without a same-world backend must fail safely")
	add_child(_system)
	no_service.free()
	var freed_owner: Unit = _make_unit(Vector3(-4.0, 1.0, 0.0))
	freed_owner.state_machine.transition_to_state(TakeCoverState.ID, candidate)
	freed_owner.free()
	_expect(_system.get_runtime_candidate_occupant(candidate) == null,
		"freeing an executing Unit must not leave its runtime reservation")
	var backend: CoverSystem = CoverSystem.new()
	add_child(backend)
	var backend_owner: Unit = _make_unit(Vector3(-4.0, 1.0, 0.0))
	_expect(backend_owner.reserve_runtime_cover_candidate(candidate, backend), "backend lifetime fixture must reserve")
	backend.free()
	backend_owner.clear_cover()
	_expect(backend_owner.reserved_cover_candidate == null and backend_owner.current_cover_candidate == null,
		"manual clear must safely handle a freed acquiring backend")
	backend_owner.free()
	_report("state cancel / command overwrite / manual clear / backend loss / death / missing service")

func _test_legacy_backend_switching() -> void:
	var unit: Unit = _make_unit(Vector3(-4.0, 1.0, -1.0))
	var cover: Cover = COVER_SCENE.instantiate() as Cover
	cover.slot_blocked_check_enabled = false
	add_child(cover)
	var legacy: CoverCandidate = cover.get_cover_candidates()[0]
	var runtime: CoverCandidate = _candidate(&"runtime:switch", Vector3(8.0, 1.0, 0.0))
	_expect(not _system.reserve_candidate(unit, legacy), "CoverSystem must not intercept legacy keys")
	unit.state_machine.transition_to_state(TakeCoverState.ID, runtime)
	unit.state_machine.transition_to_state(TakeCoverState.ID, legacy)
	_expect(unit.reserved_cover_slot == cover.get_candidate_slot(legacy) and unit.reserved_cover == cover
		and unit.reserved_cover_candidate == null and _system.get_runtime_candidate_occupant(runtime) == null,
		"same-state runtime -> legacy switch must preserve exact Marker reservation and release runtime key")
	unit.state_machine.transition_to_state(TakeCoverState.ID, runtime)
	_expect(unit.reserved_cover_candidate == runtime and unit.reserved_cover == null
		and cover.get_slot_occupant(cover.get_candidate_slot(legacy)) == null,
		"legacy -> runtime switch must release the old Marker backend")
	unit.clear_cover()
	# Direct legacy APIs must also clear runtime state, not just TakeCover commands.
	unit.reserve_runtime_cover_candidate(runtime, _system)
	_expect(cover.reserve_candidate(unit, legacy) == cover.get_candidate_slot(legacy)
		and unit.reserved_cover_candidate == null and _system.get_runtime_candidate_occupant(runtime) == null,
		"direct exact legacy reservation must not strand runtime ownership")
	unit.clear_cover()
	unit.free()
	cover.free()
	_report("legacy exact-slot reservation / backend switching")

func _test_real_agent_movement(avoidance: bool) -> void:
	var region: NavigationRegion3D = NavigationRegion3D.new()
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-10.0, 1.0, -10.0), Vector3(10.0, 1.0, -10.0),
		Vector3(10.0, 1.0, 10.0), Vector3(-10.0, 1.0, 10.0)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	add_child(region)
	var unit: Unit = _make_unit(Vector3(-4.0, 1.0, -4.0))
	unit.navigation_agent.avoidance_enabled = avoidance
	var candidate: CoverCandidate = _candidate(&"runtime:movement", Vector3(4.0, 1.0, -4.0))
	var ready: bool = false
	for frame in 120:
		await get_tree().physics_frame
		var path: PackedVector3Array = NavigationServer3D.map_get_path(unit.navigation_agent.get_navigation_map(),
			unit.global_position, candidate.position, true)
		if not path.is_empty() and path[-1].distance_to(candidate.position) < 0.1:
			ready = true
			break
	_expect(ready, "actual server path must synchronize before runtime movement")
	unit.state_machine.transition_to_state(TakeCoverState.ID, candidate)
	unit.process_mode = Node.PROCESS_MODE_INHERIT
	var arrived: bool = false
	for frame in 360:
		await get_tree().physics_frame
		if unit.current_cover_candidate == candidate:
			arrived = true
			break
	_expect(arrived and unit.is_in_runtime_cover_candidate() and not unit.movement_enabled,
		"source-less command must actually move and occupy with avoidance=%s" % avoidance)
	unit.clear_cover()
	unit.free()
	region.free()
	await _sync_physics()
	_report("real NavigationAgent movement / avoidance=%s" % avoidance)

func _make_unit(position: Vector3, enemy: bool = false) -> Unit:
	var unit: Unit = BASE_UNIT.instantiate() as Unit
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	unit.position = position
	if enemy:
		unit.collision_layer = Unit.ENEMY_UNIT_MASK
	unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
	(unit.get_node("NavigationAgent") as NavigationAgent3D).avoidance_enabled = false
	(unit.get_node("EnemyDetectionArea") as Area3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	(unit.get_node("AttackRangeArea") as Area3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	add_child(unit)
	unit._skills.clear()
	return unit

func _candidate(key: StringName, position: Vector3) -> CoverCandidate:
	var candidate: CoverCandidate = CoverCandidate.new()
	candidate.reservation_key = key
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

func _report(scenario: String) -> void:
	print("runtime cover / %s: %s" % [scenario, "FAIL" if _failed else "PASS"])
