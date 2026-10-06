extends Node3D

const BASE_UNIT: PackedScene = preload("res://scenes/units/base_units/base_unit.tscn")
const ORIGIN: Vector3 = Vector3(10.0, 2.0, -8.0)
const START: Vector3 = Vector3(12.0, 2.5, -3.0)
const TARGET: Vector3 = Vector3(32.0, 2.5, -3.0)

var _navigation: ChunkedUnitNavigation
var _geometry: Node3D
var _unit: Unit
var _failed: bool = false
var _redirty_once: bool = false
var _max_detour: float = 0.0

func _ready() -> void:
	_build_fixture()
	# Invalidate twice AFTER parsing the first snapshot, before async completion.
	_navigation.chunk_bake_requested.connect(_redirty_during_bake)
	_dirty_all()
	if not await _wait_for_bakes(_server_connects_regions):
		_finish()
		return
	_expect(_stats(Vector2i(1, 0)).bake_finished_count == 2,
		"bake-time dirties must trigger exactly one additional bake")
	_expect(_navigation.get_debug_snapshot().queued_count == 0, "queue must drain without duplicates")
	_verify_region_meshes()
	_report("bake queue revisions")

	_unit = BASE_UNIT.instantiate() as Unit
	add_child(_unit)
	_unit.navigation_agent.target_desired_distance = 0.45
	_unit.navigation_agent.radius = 0.45
	_expect(not _unit.navigation_agent.use_3d_avoidance, "ground agent must use 2D avoidance")
	_expect(await _travel(false), "one target must traverse four baked regions without avoidance")
	_report("multi-region traversal / seam radius 0.45 / avoidance off")
	_expect(await _travel(true), "one target must traverse four baked regions with avoidance")
	_report("multi-region traversal / avoidance on")
	_expect(await _travel(false, TARGET - Vector3.UP * 0.5), "ground clicks below agent centers must remain reachable")
	_report("ground click height compatibility")

	# This box crosses the boundary of chunks 1 and 2. Its top is too steep to
	# climb onto; colliders parsed from a sibling root must cut the floor mesh.
	var obstacle: StaticBody3D = _box(Vector3(22.0, 3.0, -3.0), Vector3(2.0, 2.0, 3.0))
	var before_a: int = _stats(Vector2i(1, 0)).bake_finished_count
	var before_b: int = _stats(Vector2i(2, 0)).bake_finished_count
	_navigation.register_dynamic_obstacle(obstacle, true, 1.7, 2.0)
	_expect(_navigation.is_chunk_dirty(Vector2i(1, 0)) and _navigation.is_chunk_dirty(Vector2i(2, 0)),
		"boundary obstacle must dirty both chunks")
	var temporary: NavigationObstacle3D = obstacle.get_node("TemporaryNavigationObstacle3D") as NavigationObstacle3D
	_expect(not temporary.use_3d_avoidance and temporary.avoidance_layers == _unit.navigation_agent.avoidance_mask,
		"temporary obstacle must use the same ground avoidance layers")
	_expect(not temporary.affect_navigation_mesh, "temporary avoidance must not supply duplicate bake geometry")
	await _wait_for_bakes(_server_floor_matches.bind(false))
	_expect(_stats(Vector2i(1, 0)).bake_finished_count > before_a and _stats(Vector2i(2, 0)).bake_finished_count > before_b,
		"both boundary region meshes must be rebaked")
	var obstacle_floor: Vector3 = Vector3(22.0, 2.25, -3.0)
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, obstacle_floor)
	# A disconnected roof polygon can be the closest surface in 3D. It is not
	# ground navigation: test both horizontal clearance and elevation.
	_expect(_horizontal_distance(closest, obstacle_floor) > 1.0 or absf(closest.y - obstacle_floor.y) > 1.0,
		"bake must remove floor under the collider")
	_report("chunk boundary obstacle")
	_expect(await _travel(false), "unit must detour around added collider with avoidance off")
	_expect(_max_detour > 1.7, "actual movement must detour, not pass through obstacle bounds")
	_report("dynamic obstacle add")
	_expect(await _travel(true), "unit must detour with ground avoidance on")
	_report("dynamic obstacle add / avoidance on")

	_navigation.unregister_dynamic_obstacle(obstacle, true)
	obstacle.free()
	_expect(_navigation.is_chunk_dirty(Vector2i(1, 0)) and _navigation.is_chunk_dirty(Vector2i(2, 0)),
		"removal must dirty both registered bounds chunks")
	await _wait_for_bakes(_server_floor_matches.bind(true))
	closest = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, obstacle_floor)
	_expect(_horizontal_distance(closest, obstacle_floor) < 0.1 and absf(closest.y - obstacle_floor.y) < 0.5,
		"removed obstacle floor must be restored")
	_expect(await _travel(false), "unit must arrive after obstacle removal")
	_expect(_max_detour < 0.5, "restored navmesh must allow the direct path again")
	_report("dynamic obstacle remove")
	await _test_live_repath()
	_report("automatic repath during movement")
	await _test_move_failures()
	_report("invalid / blocked / unreachable / empty-map moves")
	_finish()

func _build_fixture() -> void:
	_geometry = Node3D.new()
	_geometry.name = "WorldGeometry"
	add_child(_geometry)
	_geometry.position = Vector3(4.0, 0.0, -5.0)
	_geometry.rotation.y = 0.2
	_box(Vector3(22.0, 1.9, -3.0), Vector3(26.0, 0.2, 12.0))
	var regions: Node3D = Node3D.new()
	regions.name = "NavigationRegions"
	add_child(regions)
	regions.position = Vector3(-3.0, 1.0, 2.0)
	regions.rotation.y = -0.3
	_navigation = ChunkedUnitNavigation.new()
	_navigation.name = "ChunkedNavigation"
	_navigation.auto_initialize = false
	_navigation.map_chunk_count = Vector2i(4, 1)
	_navigation.chunk_size = Vector2(6.0, 10.0)
	_navigation.world_origin = ORIGIN
	_navigation.bake_delay_seconds = 0.0
	_navigation.source_geometry_root_path = NodePath("../WorldGeometry")
	_navigation.navigation_region_parent_path = NodePath("../NavigationRegions")
	add_child(_navigation)
	_navigation.initialize_chunks()

func _box(world_position: Vector3, size: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	_geometry.add_child(body)
	body.global_transform = Transform3D(Basis.IDENTITY, world_position)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body

func _dirty_all() -> void:
	for x in range(4):
		_navigation.mark_chunk_dirty(Vector2i(x, 0))

func _redirty_during_bake(coords: Vector2i, _region: NavigationRegion3D) -> void:
	if coords == Vector2i(1, 0) and not _redirty_once:
		_redirty_once = true
		_navigation.mark_chunk_dirty(coords)
		_navigation.mark_chunk_dirty(coords)

func _wait_for_bakes(map_condition: Callable) -> bool:
	var previous_iterations: Dictionary[Vector2i, int] = {}
	for chunk: Dictionary in _navigation.get_debug_snapshot().chunks:
		if chunk.dirty or chunk.baking:
			var region: NavigationRegion3D = _navigation.get_chunk_region(chunk.coords)
			previous_iterations[chunk.coords] = NavigationServer3D.region_get_iteration_id(region.get_rid())
	for frame in range(2400):
		await get_tree().physics_frame
		var snapshot: Dictionary = _navigation.get_debug_snapshot()
		var done: bool = not snapshot.bake_active and snapshot.queued_count == 0
		for chunk: Dictionary in snapshot.chunks:
			done = done and not chunk.dirty and not chunk.baking
		for coords: Vector2i in previous_iterations:
			var region: NavigationRegion3D = _navigation.get_chunk_region(coords)
			done = done and NavigationServer3D.region_get_iteration_id(region.get_rid()) > previous_iterations[coords]
		# Region iteration and map iteration are separate asynchronous snapshots.
		# Queue completion plus a fixed frame count can still query an older map.
		# Wait for the scenario's observable map state, with a bounded timeout.
		if done and NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) != 0 and map_condition.call():
			return true
	_expect(false, "runtime bake queue or map synchronization timed out")
	return false

func _server_connects_regions() -> bool:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(get_world_3d().navigation_map, START, TARGET, true)
	return not path.is_empty() and _horizontal_distance(path[path.size() - 1], TARGET) < 0.1

func _server_floor_matches(present: bool) -> bool:
	var floor_position: Vector3 = Vector3(22.0, 2.25, -3.0)
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, floor_position)
	if present:
		return _horizontal_distance(closest, floor_position) < 0.1 and absf(closest.y - floor_position.y) < 0.5
	return _horizontal_distance(closest, floor_position) > 1.0 or absf(closest.y - floor_position.y) > 1.0

func _verify_region_meshes() -> void:
	for x in range(4):
		var region: NavigationRegion3D = _navigation.get_chunk_region(Vector2i(x, 0))
		_expect(region.global_position.is_equal_approx(ORIGIN + Vector3(x * 6.0, 0.0, 0.0)), "region origin must stay in world space")
		_expect(region.global_basis.is_equal_approx(Basis.IDENTITY), "parent transform must not rotate chunk mesh")
		var mesh: NavigationMesh = region.navigation_mesh
		_expect(mesh.get_polygon_count() > 0, "real ground geometry must produce polygons")
		_expect(mesh.border_size >= mesh.agent_radius and mesh.agent_radius > 0.0, "positive radius must be protected by bake border")
		for vertex: Vector3 in mesh.vertices:
			_expect(vertex.x >= -0.001 and vertex.x <= 6.001 and vertex.z >= -0.001 and vertex.z <= 10.001,
				"baked vertices must remain in region-local chunk bounds")
	var path: PackedVector3Array = NavigationServer3D.map_get_path(get_world_3d().navigation_map, START, TARGET, true)
	_expect(not path.is_empty() and _horizontal_distance(path[path.size() - 1], TARGET) < 0.1,
		"server path must connect all four regions with a small edge margin")

func _travel(avoidance: bool, final_target: Vector3 = TARGET) -> bool:
	_unit.global_position = START
	_unit.velocity = Vector3.ZERO
	_unit.navigation_agent.avoidance_enabled = avoidance
	_unit.navigation_agent.set_velocity_forced(Vector3.ZERO)
	_unit.begin_player_command(Unit.PlayerCommandMode.MOVE)
	var command: MoveState.MoveCommandData = MoveState.MoveCommandData.new()
	command.target_position = final_target
	command.attack_move = false
	_unit.state_machine.transition_to_state(MoveState.ID, command)
	_expect(_unit.navigation_agent.target_position == final_target, "MoveState must assign only the final target")
	_expect(not _unit.navigation_agent.has_meta(ChunkedUnitNavigation.META_WAYPOINTS), "movement must not use portal metadata")
	var visited: Array[Vector2i] = []
	var stationary_frames: int = 0
	var previous: Vector3 = START
	_max_detour = 0.0
	for frame in range(900):
		await get_tree().physics_frame
		var position: Vector3 = _unit.global_position
		var coords: Vector2i = _navigation.get_chunk_coords(position)
		if not visited.has(coords):
			visited.append(coords)
		_max_detour = maxf(_max_detour, absf(position.z - START.z))
		if _horizontal_distance(position, TARGET) <= 0.5:
			_expect(visited.size() == 4, "actual unit must visit four regions")
			await get_tree().physics_frame
			await get_tree().process_frame
			return visited.size() == 4
		stationary_frames = stationary_frames + 1 if _horizontal_distance(position, previous) < 0.005 else 0
		if stationary_frames > 120:
			push_error("Movement stalled at %s; path=%s" % [position, _unit.navigation_agent.get_current_navigation_path()])
			return false
		previous = position
	return false

func _test_move_failures() -> void:
	_unit.global_position = START
	await _expect_failed_command(Vector3(1000.0, 2.5, 0.0), false)
	_navigation.set_chunk_walkable(Vector2i(3, 0), false)
	await _expect_failed_command(TARGET, true)
	_navigation.set_chunk_walkable(Vector2i(3, 0), true)
	_navigation.set_chunk_walkable(Vector2i(1, 0), false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _expect_failed_command(TARGET, false)
	_navigation.set_chunk_walkable(Vector2i(1, 0), true)
	# In-map target above the actual polygons must fail agent reachability.
	await _expect_failed_command(TARGET + Vector3.UP * 20.0, false)
	for x in range(4):
		_navigation.get_chunk_region(Vector2i(x, 0)).enabled = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _expect_failed_command(TARGET, false)

func _test_live_repath() -> void:
	_unit.global_position = START
	_unit.velocity = Vector3.ZERO
	_unit.navigation_agent.avoidance_enabled = false
	_unit.begin_player_command(Unit.PlayerCommandMode.MOVE)
	var command: MoveState.MoveCommandData = MoveState.MoveCommandData.new()
	command.target_position = TARGET
	command.attack_move = false
	_unit.state_machine.transition_to_state(MoveState.ID, command)
	for frame in range(30):
		await get_tree().physics_frame
	var obstacle: StaticBody3D = _box(Vector3(22.0, 3.0, -3.0), Vector3(2.0, 2.0, 3.0))
	_navigation.register_dynamic_obstacle(obstacle, false)
	await _wait_for_bakes(_server_floor_matches.bind(false))
	var maximum_detour: float = 0.0
	for frame in range(900):
		await get_tree().physics_frame
		maximum_detour = maxf(maximum_detour, absf(_unit.global_position.z - START.z))
		if _horizontal_distance(_unit.global_position, TARGET) < 0.5:
			break
	_expect(_horizontal_distance(_unit.global_position, TARGET) < 0.5 and maximum_detour > 1.7,
		"map update must automatically repath a moving unit around the new collider")
	_expect(_unit.navigation_agent.target_position == TARGET, "repath must retain the original final target")
	_navigation.unregister_dynamic_obstacle(obstacle)
	obstacle.free()
	await _wait_for_bakes(_server_floor_matches.bind(true))

func _expect_failed_command(target: Vector3, attack_move: bool) -> void:
	var command: MoveState.MoveCommandData = MoveState.MoveCommandData.new()
	command.target_position = target
	command.attack_move = attack_move
	_unit.begin_player_command(Unit.PlayerCommandMode.ATTACK_MOVE if attack_move else Unit.PlayerCommandMode.MOVE)
	_unit.state_machine.transition_to_state(MoveState.ID, command)
	for frame in range(90):
		await get_tree().physics_frame
		if _unit.state_machine.is_current_state(IdleState.ID):
			break
	_expect(_unit.state_machine.is_current_state(IdleState.ID), "failed movement must return to Idle")
	_expect(not _unit.blocks_auto_cover() and _unit.last_move_command_data == null, "failed movement must clear command bookkeeping")
	_expect(_unit.velocity.length() < 0.01, "failed movement must stop velocity")

func _stats(coords: Vector2i) -> Dictionary:
	for chunk: Dictionary in _navigation.get_debug_snapshot().chunks:
		if chunk.coords == coords:
			return chunk
	return {}

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _report(scenario: String) -> void:
	print("runtime bake / %s: %s" % [scenario, "FAIL" if _failed else "PASS"])

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

func _finish() -> void:
	print("chunked_navigation_runtime_bake_test: %s" % ["FAIL" if _failed else "PASS"])
	get_tree().quit(1 if _failed else 0)
