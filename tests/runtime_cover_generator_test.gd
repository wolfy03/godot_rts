extends Node3D

const BASE_UNIT: PackedScene = preload("res://scenes/units/base_units/base_unit.tscn")
const COVER_SCENE: PackedScene = preload("res://scenes/units/cover.tscn")

var _failed: bool = false
var _generator: RuntimeCoverCandidateGenerator = RuntimeCoverCandidateGenerator.new()

func _ready() -> void:
	await _test_sampling_transforms_and_limits()
	await _test_projection_and_unsupported_geometry()
	await _test_cache_merge_revision_and_lifetime()
	await _test_generated_combat_e2e()
	print("runtime_cover_generator_test: %s" % ["FAIL" if _failed else "PASS"])
	get_tree().quit(1 if _failed else 0)

func _test_sampling_transforms_and_limits() -> void:
	var world: Node3D = _make_world()
	_make_region(world, Rect2(-80.0, -80.0, 160.0, 160.0))
	await _wait_surface(world)
	var source: RuntimeCoverSource = _make_source(world, Vector3.ZERO, Vector3(4.0, 3.0, 6.0))
	var map: RID = world.get_world_3d().navigation_map
	var candidates: Array[CoverCandidate] = _generator.generate_candidates(source, map)
	_expect(candidates.size() == 20, "spacing 1m must give 6+6+4+4 side samples")
	_check_geometry_candidates(source, candidates)
	var sides: Dictionary[int, int] = _side_counts(candidates)
	_expect(sides.size() == 4, "all four transformed faces must have candidates")
	var repeated: Array[CoverCandidate] = _generator.generate_candidates(source, map)
	_expect(_keys(candidates) == _keys(repeated), "same source/revision/geometry must generate deterministic key sequence")
	source.rotation.y = 0.37
	var geometry: CollisionShape3D = source.get_geometry_shape()
	geometry.rotation.y = 0.63
	geometry.position.x = 1.2
	source.scale = Vector3.ONE * 1.4
	geometry.scale = Vector3(1.2, 1.0, 0.8)
	candidates = _generator.generate_candidates(source, map)
	_check_geometry_candidates(source, candidates)
	_expect(_side_counts(candidates).size() == 4, "composed source/shape yaw and uniform parent scale must preserve four sides")
	# Non-uniform scaling with orthogonal global box axes is supported.
	geometry.rotation.y = 0.0
	source.scale = Vector3(1.5, 1.0, 0.75)
	candidates = _generator.generate_candidates(source, map)
	_check_geometry_candidates(source, candidates)
	_expect(not candidates.is_empty(), "orthogonal non-uniform scale must be supported")
	source.scale = Vector3.ONE
	source.rotation = Vector3.ZERO
	geometry.transform = Transform3D(Basis(), Vector3(0.0, 1.5, 0.0))
	(geometry.shape as BoxShape3D).size = Vector3(100.0, 3.0, 2.0)
	source.sample_spacing = 0.25
	source.max_samples_per_side = 3
	candidates = _generator.generate_candidates(source, map)
	_expect(candidates.size() == 12, "long wall must be capped to three samples per side")
	for count: int in _side_counts(candidates).values():
		_expect(count <= 3, "side cap must hold independently on every side")
	(geometry.shape as BoxShape3D).size = Vector3(4.0, 3.0, 6.0)
	source.max_samples_per_side = 16
	source.sample_spacing = 1.0
	source.minimum_candidate_separation = 4.0
	candidates = _generator.generate_candidates(source, map)
	_expect(not candidates.is_empty() and candidates.size() < 20, "source-local duplicate removal must reduce close samples")
	for a: int in candidates.size():
		for b: int in range(a + 1, candidates.size()):
			_expect(candidates[a].position.distance_to(candidates[b].position) >= 3.999,
				"projected candidates must satisfy minimum separation")
	(geometry.shape as BoxShape3D).size.y = 1.0
	geometry.position.y = 0.5
	source.minimum_candidate_separation = 0.4
	for candidate: CoverCandidate in _generator.generate_candidates(source, map):
		_expect(candidate.stance == CoverStance.Type.CROUCHING, "low boxes must use crouching metadata")
	world.get_parent().free()
	_report("four sides / world transforms / spacing / cap / separation / stance / stable identity")

func _test_projection_and_unsupported_geometry() -> void:
	var world: Node3D = _make_world()
	_make_region(world, Rect2(3.0, -8.0, 1.0, 16.0))
	await _wait_surface(world)
	var source: RuntimeCoverSource = _make_source(world, Vector3.ZERO, Vector3(4.0, 3.0, 2.0))
	var map: RID = world.get_world_3d().navigation_map
	source.max_navigation_projection_distance = 10.0
	var candidates: Array[CoverCandidate] = _generator.generate_candidates(source, map)
	_expect(not candidates.is_empty() and not _side_counts(candidates).has(1),
		"projection onto opposite-side-only navigation must reject the -X face")
	_expect(_side_counts(candidates).has(2), "surviving samples must retain original side indices instead of being renumbered")
	for candidate: CoverCandidate in candidates:
		_expect(candidate.position.x >= 3.0 and is_equal_approx(candidate.position.y, 1.0),
			"positions must use NavigationServer projection including surface height")
	source.max_navigation_projection_distance = 0.1
	_expect(_generator.generate_candidates(source, map).is_empty(), "distant projections must be rejected")
	_expect(_generator.generate_candidates(source, RID()).is_empty(), "invalid map must fail without server errors")
	var freed_map: RID = NavigationServer3D.map_create()
	NavigationServer3D.free_rid(freed_map)
	_expect(_generator.generate_candidates(source, freed_map).is_empty(), "freed nonzero map RID must also be rejected")
	var geometry: CollisionShape3D = source.get_geometry_shape()
	geometry.shape = SphereShape3D.new()
	_expect(_generator.generate_candidates(source, map).is_empty(), "unsupported sphere must return zero candidates")
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 2.0)
	geometry.shape = box
	source.max_navigation_projection_distance = 10.0
	source.rotation.x = 0.2
	_expect(_generator.generate_candidates(source, map).is_empty(), "tilted Box sampling is explicitly unsupported")
	source.rotation = Vector3.ZERO
	source.scale = Vector3(2.0, 1.0, 1.0)
	geometry.rotation.y = 0.4
	_expect(_generator.generate_candidates(source, map).is_empty(), "composed scale/yaw producing shear must reject safely")
	world.get_parent().free()
	_report("navigation projection / outward-side guard / distance / invalid RID / unsupported geometry")

func _test_cache_merge_revision_and_lifetime() -> void:
	var world: Node3D = _make_world()
	var source: RuntimeCoverSource = _make_source(world, Vector3.ZERO, Vector3(4.0, 4.0, 1.0))
	var legacy: Cover = _make_legacy(world, Vector3(-5.0, 0.0, -4.0))
	var system: CoverSystem = CoverSystem.new()
	var counter: CountingGenerator = CountingGenerator.new()
	system._runtime_generator = counter
	world.add_child(system)
	_expect(system.get_debug_snapshot().runtime_source_count == 1, "ready bootstrap must register existing runtime sources")
	var region: NavigationRegion3D = NavigationRegion3D.new()
	world.add_child(region)
	# Even an already synchronized map with an empty Region is not ready.
	await _sync_physics()
	var first: Array[CoverCandidate] = system.query_candidates(Vector3.ZERO, 30.0)
	_expect(counter.calls == 0 and _runtime_only(first).is_empty(), "startup with no navigation surface must not freeze an empty cache")
	region.navigation_mesh = _flat_mesh(Rect2(-12.0, -12.0, 24.0, 24.0))
	await _wait_surface(world)
	first = system.query_candidates(Vector3.ZERO, 30.0)
	var runtime: Array[CoverCandidate] = _runtime_only(first)
	_expect(not runtime.is_empty() and counter.calls == 1 and first[0].get_source() == legacy,
		"query must merge legacy first and generated runtime candidates after navigation becomes ready")
	system.register_runtime_cover_source(source)
	system.register_runtime_cover_source(source)
	_expect(system.get_debug_snapshot().runtime_source_count == 1, "duplicate runtime registration must be idempotent")
	for index in 10:
		var repeated: Array[CoverCandidate] = _runtime_only(system.query_candidates(Vector3.ZERO, 30.0))
		_expect(repeated[0] == runtime[0], "same-revision query must reuse cached snapshot objects")
	_expect(counter.calls == 1, "ten unchanged queries must not regenerate geometry")
	first.clear()
	_expect(_runtime_only(system.query_candidates(Vector3.ZERO, 30.0)).size() == runtime.size(),
		"query result array mutation must not mutate the cache array")
	var narrow: Array[CoverCandidate] = system.query_candidates(runtime[0].position, 0.05)
	_expect(narrow.size() == 1 and narrow[0] == runtime[0], "runtime radius filtering must use candidate position")
	var unit: Unit = _make_unit(world, Vector3(-6.0, 1.0, -4.0))
	var threat: Unit = _make_unit(world, Vector3(0.0, 1.0, 6.0), true)
	var old: CoverCandidate = runtime[0]
	var old_position: Vector3 = old.position
	var old_key: StringName = old.reservation_key
	source.source_revision += 1
	var evaluator: CoverEvaluator = CoverEvaluator.new()
	_expect(evaluator.evaluate(unit, old, threat).reason == &"stale_source_revision"
		and not system.reserve_candidate(unit, old), "out-of-cache stale snapshots must reject evaluation and new acquisition")
	var regenerated: Array[CoverCandidate] = _runtime_only(system.query_candidates(Vector3.ZERO, 30.0))
	_expect(counter.calls == 2 and regenerated[0] != old and regenerated[0].reservation_key != old_key,
		"revision change must produce new objects and new keys exactly once")
	_expect(not old.valid and old.position == old_position and old.reservation_key == old_key and old.source_revision == 0,
		"regeneration may invalidate only valid, never mutate published identity/position/revision")
	for fresh: CoverCandidate in regenerated:
		_expect(fresh.source_revision == 1, "new snapshots must capture the new source revision")
	var distant: RuntimeCoverSource = _make_source(world, Vector3(50.0, 0.0, 0.0), Vector3.ONE)
	system.register_runtime_cover_source(distant)
	var before_empty: int = counter.calls
	for index in 3:
		system.query_candidates(Vector3(50.0, 0.0, 0.0), 5.0)
	_expect(counter.calls == before_empty + 1 and system._runtime_candidate_revisions.has(distant.get_instance_id())
		and system._runtime_candidates_by_source[distant.get_instance_id()].is_empty(),
		"supported geometry with all projections rejected is a valid cached empty result")
	distant.free()
	var newcomer: RuntimeCoverSource = _make_source(world, Vector3(7.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0))
	_expect(system.get_debug_snapshot().runtime_source_count == 1, "post-ready runtime sources need explicit registration")
	system.register_runtime_cover_source(newcomer)
	system.query_candidates(Vector3.ZERO, 30.0)
	system.unregister_runtime_cover_source(newcomer)
	system.unregister_runtime_cover_source(newcomer)
	system.register_runtime_cover_source(newcomer)
	_expect(newcomer.tree_exiting.get_connections().size() == 1, "manual unregister/re-register must not duplicate exit callbacks")
	newcomer.free()
	var viewport: SubViewport = SubViewport.new()
	viewport.world_3d = World3D.new()
	add_child(viewport)
	var foreign: RuntimeCoverSource = RuntimeCoverSource.new()
	viewport.add_child(foreign)
	system.register_runtime_cover_source(foreign)
	_expect(system.get_debug_snapshot().runtime_source_count == 1, "runtime source registration must enforce World3D isolation")
	viewport.free()
	# Reserved snapshots still appear spatially; only the AI preflight excludes them.
	var chosen: CoverCandidate = regenerated[0]
	system.reserve_candidate(unit, chosen)
	var filtered: Array[CoverCandidate] = threat.ai_brain._query_cover_candidates(30.0)
	_expect(system.query_candidates(Vector3.ZERO, 30.0).has(chosen) and not filtered.has(chosen)
		and _runtime_only(filtered).size() > 0, "AI must prefilter someone else's runtime key without filtering the spatial query")
	legacy.slot_blocked_check_enabled = false
	legacy.reserve_candidate(unit, legacy.get_cover_candidates()[0])
	_expect(threat.ai_brain._query_cover_candidates(30.0)[0].get_source() == legacy,
		"AI prefilter must leave reserved legacy candidates for evaluator eligibility")
	unit.clear_cover()
	system.release_candidate(unit, chosen)
	# Idle can now discover actual generated candidates and issue the same command.
	system.unregister_cover_source(legacy)
	unit.global_position = Vector3(-4.0, 1.0, -3.0)
	unit.clear_player_command()
	var idle: CoverCandidate = unit.ai_brain._get_idle_cover_candidate()
	_expect(idle != null and idle.get_source() == source, "idle selection must accept generated runtime candidates")
	if idle == null:
		world.get_parent().free()
		return
	unit.ai_brain._issue_cover(idle)
	_expect(unit.reserved_cover_candidate == idle, "generated idle command must acquire its runtime key")
	unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
	unit.state_machine.transition_to_state(IdleState.ID, null)
	# Occupied old snapshots retain execution ownership on revision-only changes.
	unit.global_position = idle.position
	unit.state_machine.transition_to_state(TakeCoverState.ID, idle)
	source.source_revision += 1
	system.query_candidates(Vector3.ZERO, 30.0)
	var take: TakeCoverState = unit.state_machine.get_node("TakeCoverState") as TakeCoverState
	take._process_state(0.0)
	_expect(not idle.valid and unit.current_cover_candidate == idle and system.get_runtime_candidate_occupant(idle) == unit,
		"revision invalidation must not forcibly release already occupied old snapshot in this stage")
	source.queue_free()
	system.query_candidates(Vector3.ZERO, 30.0)
	take._process_state(0.0)
	_expect(not chosen.valid and system.get_debug_snapshot().runtime_source_count == 0
		and system.get_debug_snapshot().runtime_cached_candidate_count == 0 and unit.reserved_cover_candidate == null,
		"source removal must invalidate/drop cache and fail execution on source lifetime loss")
	source.free()
	world.get_parent().free()
	_report("startup retry / cache reuse / merge / revision / snapshot ownership / source lifecycle / AI availability / idle")

func _test_generated_combat_e2e() -> void:
	var world: Node3D = _make_world()
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.navigation_mesh = _hole_mesh()
	world.add_child(region)
	var source: RuntimeCoverSource = _make_source(world, Vector3.ZERO, Vector3(4.0, 4.0, 1.0))
	var legacy: Cover = _make_legacy(world, Vector3(-4.5, 0.0, -4.0))
	var system: CoverSystem = CoverSystem.new()
	world.add_child(system)
	var unit: Unit = _make_unit(world, Vector3(-5.0, 1.0, -4.0))
	var threat: Unit = _make_unit(world, Vector3(0.0, 1.0, 6.0), true)
	await _wait_surface(world)
	await _sync_physics()
	unit.clear_player_command()
	var spatial: Array[CoverCandidate] = system.query_candidates(unit.global_position, 20.0)
	_expect(not _runtime_only(spatial).is_empty() and unit.get_nearest_detected_enemy() == threat,
		"combat E2E must have generated candidates and a real detected threat")
	var evaluator: CoverEvaluator = CoverEvaluator.new()
	var legacy_result: CoverEvaluationResult = evaluator.evaluate(unit, legacy.get_cover_candidates()[0], threat)
	_expect(legacy_result.valid and not legacy_result.protected_from_threat,
		"nearby low legacy collider must provide no actual AimPoint protection")
	var best: CoverCandidate = unit.ai_brain._get_cover_against(threat)
	_expect(best != null and best.get_source() == source and spatial.has(best),
		"real threat-based AI must prefer generated geometry protection over closer authored cover")
	if best == null:
		world.get_parent().free()
		return
	var evaluated: CoverEvaluationResult = evaluator.evaluate(unit, best, threat)
	_expect(evaluated.valid and evaluated.exposure_score < 0.01 and evaluated.protection_score > 0.99
		and evaluated.improves_current_position, "actual StaticBody box must block candidate's virtual AimPoint rays")
	_expect(unit.ai_brain.request_decision() and unit.state_machine.is_current_state(TakeCoverState.ID)
		and unit.reserved_cover_candidate == best and unit.reserved_cover == null
		and unit.navigation_agent.target_position == best.position,
		"production decision must query/evaluate/reserve the generated snapshot and submit its final target")
	var start: Vector3 = unit.global_position
	unit.process_mode = Node.PROCESS_MODE_INHERIT
	var arrived: bool = false
	for frame in 600:
		await get_tree().physics_frame
		if unit.current_cover_candidate == best:
			arrived = true
			break
	_expect(arrived and unit.global_position.distance_to(start) > 1.0 and unit.is_in_runtime_cover_candidate()
		and not unit.movement_enabled and system.get_runtime_candidate_occupant(best) == unit,
		"AI must actually navigate around collider geometry and occupy its generated candidate")
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
	unit.clear_cover()
	world.get_parent().free()
	_report("Box collider -> generator -> query -> evaluator -> AI -> reservation -> real movement -> occupation")

func _make_world() -> Node3D:
	var viewport: SubViewport = SubViewport.new()
	viewport.world_3d = World3D.new()
	add_child(viewport)
	var world: Node3D = Node3D.new()
	viewport.add_child(world)
	return world

func _make_source(world: Node3D, position: Vector3, size: Vector3) -> RuntimeCoverSource:
	var source: RuntimeCoverSource = RuntimeCoverSource.new()
	source.position = position
	source.geometry_shape_path = ^"Body/CollisionShape3D"
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	var geometry: CollisionShape3D = CollisionShape3D.new()
	geometry.name = "CollisionShape3D"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	geometry.shape = box
	geometry.position.y = size.y * 0.5
	body.add_child(geometry)
	source.add_child(body)
	world.add_child(source)
	return source

func _make_legacy(world: Node3D, position: Vector3) -> Cover:
	var cover: Cover = COVER_SCENE.instantiate() as Cover
	cover.position = position
	var geometry: CollisionShape3D = cover.get_node("CollisionShape3D") as CollisionShape3D
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.5, 0.2, 0.5)
	geometry.shape = box
	geometry.position.y = 0.1
	var slots: Node = cover.get_node("CoverSlots")
	for child: Node in slots.get_children():
		child.free()
	var slot: Marker3D = Marker3D.new()
	slot.position = Vector3(0.0, 1.0, -1.0)
	slots.add_child(slot)
	world.add_child(cover)
	return cover

func _make_unit(world: Node3D, position: Vector3, enemy: bool = false) -> Unit:
	var unit: Unit = BASE_UNIT.instantiate() as Unit
	unit.position = position
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	if enemy:
		unit.collision_layer = Unit.ENEMY_UNIT_MASK
	unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
	(unit.get_node("NavigationAgent") as NavigationAgent3D).avoidance_enabled = false
	(unit.get_node("EnemyDetectionArea") as Area3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	(unit.get_node("AttackRangeArea") as Area3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	world.add_child(unit)
	unit._skills.clear()
	return unit

func _make_region(world: Node3D, bounds: Rect2) -> void:
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.navigation_mesh = _flat_mesh(bounds)
	world.add_child(region)

func _flat_mesh(bounds: Rect2) -> NavigationMesh:
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(bounds.position.x, 1.0, bounds.position.y),
		Vector3(bounds.end.x, 1.0, bounds.position.y), Vector3(bounds.end.x, 1.0, bounds.end.y),
		Vector3(bounds.position.x, 1.0, bounds.end.y)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return mesh

func _hole_mesh() -> NavigationMesh:
	# Eight connected grid quads leave a collider/agent-radius-sized central hole.
	var mesh: NavigationMesh = NavigationMesh.new()
	var cuts_x: Array[float] = [-12.0, -2.55, 2.55, 12.0]
	var cuts_z: Array[float] = [-12.0, -1.05, 1.05, 12.0]
	var vertices: PackedVector3Array = []
	for z: float in cuts_z:
		for x: float in cuts_x:
			vertices.append(Vector3(x, 1.0, z))
	mesh.vertices = vertices
	for z: int in 3:
		for x: int in 3:
			if x == 1 and z == 1:
				continue
			var index: int = z * 4 + x
			mesh.add_polygon(PackedInt32Array([index, index + 1, index + 5, index + 4]))
	return mesh

func _wait_surface(world: Node3D) -> void:
	for frame in 120:
		await get_tree().physics_frame
		if RuntimeCoverCandidateGenerator.is_navigation_map_ready(world.get_world_3d().navigation_map):
			return
	_expect(false, "fixture navigation surface must synchronize")

func _check_geometry_candidates(source: RuntimeCoverSource, candidates: Array[CoverCandidate]) -> void:
	_expect(not candidates.is_empty(), "supported transformed source must produce candidates")
	var geometry: CollisionShape3D = source.get_geometry_shape()
	var half: Vector3 = (geometry.shape as BoxShape3D).size * 0.5
	var transform: Transform3D = geometry.global_transform
	var normal_basis: Basis = transform.basis.inverse().transposed()
	for candidate: CoverCandidate in candidates:
		var side: int = int(String(candidate.reservation_key).get_slice(":", 3)) / 64
		var local: Vector3 = transform.affine_inverse() * candidate.position
		var normal: Vector3 = normal_basis * (Vector3.RIGHT if side < 2 else Vector3.BACK)
		normal = normal.normalized() * (1.0 if side % 2 == 0 else -1.0)
		var face: Vector3 = transform * (Vector3((1.0 if side == 0 else -1.0) * half.x, 0.0, 0.0) if side < 2
			else Vector3(0.0, 0.0, (1.0 if side == 2 else -1.0) * half.z))
		_expect(candidate.get_source() == source and candidate.source_revision == source.source_revision
			and String(candidate.reservation_key).begins_with("runtime:%d:%d:" % [source.get_instance_id(), source.source_revision]),
			"generated candidates must carry source/revision/session-local deterministic identity")
		_expect(candidate.position.is_finite() and is_equal_approx(candidate.position.y, 1.0)
			and (absf(local.x) > half.x or absf(local.z) > half.z), "candidate must lie on navigation surface outside box")
		_expect(is_equal_approx((candidate.position - face).dot(normal), source.candidate_clearance),
			"clearance must be world units along the actual transformed face normal")

func _side_counts(candidates: Array[CoverCandidate]) -> Dictionary[int, int]:
	var counts: Dictionary[int, int] = {}
	for candidate: CoverCandidate in candidates:
		var side: int = int(String(candidate.reservation_key).get_slice(":", 3)) / 64
		counts[side] = counts.get(side, 0) + 1
	return counts

func _keys(candidates: Array[CoverCandidate]) -> Array[StringName]:
	var keys: Array[StringName] = []
	for candidate: CoverCandidate in candidates:
		keys.append(candidate.reservation_key)
	return keys

func _runtime_only(candidates: Array[CoverCandidate]) -> Array[CoverCandidate]:
	var runtime: Array[CoverCandidate] = []
	for candidate: CoverCandidate in candidates:
		if candidate.get_source() is RuntimeCoverSource:
			runtime.append(candidate)
	return runtime

func _sync_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

func _report(scenario: String) -> void:
	print("runtime generator / %s: %s" % [scenario, "FAIL" if _failed else "PASS"])

class CountingGenerator extends RuntimeCoverCandidateGenerator:
	var calls: int = 0

	func generate_candidates(source: RuntimeCoverSource, navigation_map: RID) -> Array[CoverCandidate]:
		calls += 1
		return super.generate_candidates(source, navigation_map)
