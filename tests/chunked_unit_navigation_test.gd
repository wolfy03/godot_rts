extends Node

const ChunkedUnitNavigationScript := preload("res://scripts/navigation/chunked_unit_navigation.gd")

var _failed := false

func _ready() -> void:
	_test_creates_5_by_5_chunks()
	await _test_voxel_settings_validation()
	await _test_chunk_settings_validation()
	_test_world_position_to_chunk_coords()
	_test_dirty_chunk_tracking()
	_test_astar_avoids_blocked_chunks()
	_test_world_waypoints_end_at_target()
	_test_world_waypoints_use_chunk_transition_portals()
	_test_world_waypoints_use_start_height()
	_test_solid_blocker_marks_chunk_and_adds_temporary_obstacle()
	await _test_local_flat_meshes_and_reinitialization()
	await _test_solid_blocker_bounds_and_removal()
	await _test_dynamic_geometry_registration()

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("chunked_unit_navigation_test: PASS")
		get_tree().quit(0)

func _make_navigation() -> Variant:
	var navigation: Variant = ChunkedUnitNavigationScript.new()
	navigation.auto_initialize = false
	navigation.bake_on_dirty = false
	navigation.map_chunk_count = Vector2i(5, 5)
	navigation.chunk_size = Vector2(10.0, 10.0)
	navigation.world_origin = Vector3.ZERO
	add_child(navigation)
	navigation.initialize_chunks()
	return navigation

func _test_creates_5_by_5_chunks() -> void:
	var navigation: Variant = _make_navigation()
	_expect(navigation.get_chunk_count() == 25, "navigation should create 25 chunks for a 5x5 map")
	_expect(navigation.get_chunk_region(Vector2i(4, 4)) != null, "navigation should create a NavigationRegion3D per chunk")
	navigation.queue_free()

func _test_world_position_to_chunk_coords() -> void:
	var navigation: Variant = _make_navigation()
	_expect(navigation.get_chunk_coords(Vector3(0.0, 0.0, 0.0)) == Vector2i(0, 0), "origin should be in chunk 0,0")
	_expect(navigation.get_chunk_coords(Vector3(12.0, 0.0, 23.0)) == Vector2i(1, 2), "world x/z should map to chunk x/y")
	_expect(navigation.get_chunk_center(Vector2i(2, 3)) == Vector3(25.0, 0.0, 35.0), "chunk center should use x/z chunk size")
	navigation.queue_free()

func _test_dirty_chunk_tracking() -> void:
	var navigation: Variant = _make_navigation()
	navigation.mark_chunk_dirty_for_world_position(Vector3(12.0, 0.0, 23.0))
	_expect(navigation.is_chunk_dirty(Vector2i(1, 2)), "dirty tracking should mark only the touched chunk")
	_expect(not navigation.is_chunk_dirty(Vector2i(0, 0)), "untouched chunks should remain clean")
	navigation.queue_free()

func _test_astar_avoids_blocked_chunks() -> void:
	var navigation: Variant = _make_navigation()
	navigation.set_chunk_walkable(Vector2i(1, 0), false)

	var path: Array[Vector2i] = navigation.get_chunk_path(Vector3(5.0, 0.0, 5.0), Vector3(45.0, 0.0, 5.0))
	_expect(not path.is_empty(), "A* should find an alternate route around a blocked chunk")
	_expect(not path.has(Vector2i(1, 0)), "A* path should not include blocked chunks")
	_expect(path[0] == Vector2i(0, 0), "A* path should start in the source chunk")
	_expect(path[path.size() - 1] == Vector2i(4, 0), "A* path should end in the target chunk")
	navigation.queue_free()

func _test_world_waypoints_end_at_target() -> void:
	var navigation: Variant = _make_navigation()
	var target := Vector3(42.0, 0.0, 12.0)
	var waypoints: Array[Vector3] = navigation.get_world_path_waypoints(Vector3(1.0, 0.0, 1.0), target)

	_expect(not waypoints.is_empty(), "world waypoints should be generated from the chunk path")
	_expect(waypoints[waypoints.size() - 1] == target, "final waypoint should be the requested target position")
	navigation.queue_free()

func _test_world_waypoints_use_chunk_transition_portals() -> void:
	var navigation: Variant = _make_navigation()
	var waypoints: Array[Vector3] = navigation.get_world_path_waypoints(Vector3(1.0, 0.0, 1.0), Vector3(22.0, 0.0, 1.0))

	_expect(waypoints.size() >= 3, "cross-chunk movement should include transition portals before the final target")
	_expect(waypoints[0] == Vector3(10.0, 0.0, 5.0), "first portal should be on the boundary between chunk 0,0 and 1,0")
	_expect(waypoints[1] == Vector3(20.0, 0.0, 5.0), "second portal should be on the boundary between chunk 1,0 and 2,0")
	_expect(waypoints[waypoints.size() - 1] == Vector3(22.0, 0.0, 1.0), "portal path should still end at the requested target")
	navigation.queue_free()

func _test_world_waypoints_use_start_height() -> void:
	var navigation: Variant = _make_navigation()
	var waypoints: Array[Vector3] = navigation.get_world_path_waypoints(Vector3(1.0, 1.5, 1.0), Vector3(22.0, 0.0, 1.0))

	_expect(not waypoints.is_empty(), "height-normalized waypoint path should not be empty")
	for waypoint in waypoints:
		_expect(is_equal_approx(waypoint.y, 1.5), "waypoints should use the moving unit height when height normalization is enabled")
	navigation.queue_free()

func _test_solid_blocker_marks_chunk_and_adds_temporary_obstacle() -> void:
	var navigation: Variant = _make_navigation()
	var obstacle := Node3D.new()
	add_child(obstacle)
	obstacle.global_position = Vector3(22.0, 0.0, 31.0)

	var coords: Vector2i = navigation.register_solid_blocker(obstacle, true, 1.5, 2.5)
	_expect(coords == Vector2i(2, 3), "dynamic obstacle should report its chunk")
	_expect(navigation.is_chunk_dirty(Vector2i(2, 3)), "dynamic obstacle should mark its chunk dirty")
	_expect(obstacle.get_node_or_null("TemporaryNavigationObstacle3D") is NavigationObstacle3D, "dynamic obstacle should receive a temporary NavigationObstacle3D")
	var temporary: NavigationObstacle3D = obstacle.get_node("TemporaryNavigationObstacle3D") as NavigationObstacle3D
	_expect(not temporary.use_3d_avoidance and not temporary.affect_navigation_mesh, "temporary obstacle must use ground avoidance only")

	obstacle.queue_free()
	navigation.queue_free()

func _test_local_flat_meshes_and_reinitialization() -> void:
	var navigation: ChunkedUnitNavigation = _make_navigation() as ChunkedUnitNavigation
	navigation.world_origin = Vector3(40.0, 3.0, -20.0)
	navigation.initialize_chunks()
	await get_tree().process_frame
	_expect(navigation.get_children().size() == 25, "reinitialization must remove old regions")
	navigation.build_flat_chunk_navigation_meshes(0.75)
	var region: NavigationRegion3D = navigation.get_chunk_region(Vector2i(2, 3))
	_expect(region.global_position == Vector3(60.0, 3.0, 10.0), "flat helper must preserve region world origin")
	for vertex: Vector3 in region.navigation_mesh.vertices:
		_expect(vertex.x >= 0.0 and vertex.x <= 10.0 and vertex.z >= 0.0 and vertex.z <= 10.0,
			"flat mesh vertices must be region-local")
		_expect(is_equal_approx(vertex.y, 0.75), "flat y_offset must be local")
	navigation.set_chunk_walkable(Vector2i(2, 3), false)
	_expect(not region.enabled and not navigation.is_world_position_navigable(region.global_position + Vector3.ONE),
		"coarse blocked chunk must also disable its region")
	navigation.queue_free()

func _test_solid_blocker_bounds_and_removal() -> void:
	var navigation: ChunkedUnitNavigation = _make_navigation() as ChunkedUnitNavigation
	var obstacle: StaticBody3D = StaticBody3D.new()
	add_child(obstacle)
	obstacle.global_position = Vector3(10.0, 1.0, 15.0)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(8.0, 2.0, 2.0)
	collider.shape = shape
	obstacle.add_child(collider)
	navigation.register_solid_blocker(obstacle, true)
	var temporary: NavigationObstacle3D = obstacle.get_node("TemporaryNavigationObstacle3D") as NavigationObstacle3D
	_expect(temporary.radius >= 4.0 and temporary.global_position == Vector3(10.0, 0.0, 15.0),
		"default avoidance must cover a wide collider from its ground elevation")
	_expect(navigation.is_chunk_dirty(Vector2i(0, 1)) and navigation.is_chunk_dirty(Vector2i(1, 1)),
		"wide collider must dirty all overlapping chunks")
	# Compare revision increments to prove removal uses OLD registered bounds,
	# even after the object is moved into a completely different chunk.
	var previous: int = _debug_chunk(navigation, Vector2i(0, 1)).dirty_revision
	obstacle.global_position = Vector3(45.0, 1.0, 45.0)
	navigation.unregister_navigation_geometry(obstacle)
	_expect(not temporary.avoidance_enabled, "unregister must disable avoidance immediately")
	_expect(_debug_chunk(navigation, Vector2i(0, 1)).dirty_revision == previous + 1,
		"unregister must dirty stored bounds rather than the current center")
	_expect(not navigation.is_chunk_dirty(Vector2i(4, 4)), "unregister alone must not dirty unrelated new position")
	navigation.unregister_navigation_geometry(obstacle)
	_expect(_debug_chunk(navigation, Vector2i(0, 1)).dirty_revision == previous + 1,
		"duplicate unregister must not dirty bounds again")
	await get_tree().process_frame
	_expect(obstacle.get_node_or_null("TemporaryNavigationObstacle3D") == null,
		"unregister must remove temporary avoidance by the next frame")
	_expect(navigation.get_debug_snapshot().solid_blocker_count == 0, "unregister must remove the solid registry entry")
	navigation.register_solid_blocker(obstacle, true)
	temporary = obstacle.get_node("TemporaryNavigationObstacle3D") as NavigationObstacle3D
	_expect(temporary.global_position == Vector3(45.0, 0.0, 45.0), "re-register must refresh the avoidance helper")
	var old_helper_id: int = temporary.get_instance_id()
	navigation.unregister_navigation_geometry(obstacle)
	navigation.register_solid_blocker(obstacle, true)
	temporary = obstacle.get_node("TemporaryNavigationObstacle3D") as NavigationObstacle3D
	_expect(temporary.get_instance_id() != old_helper_id and temporary.avoidance_enabled,
		"same-frame re-registration must create a fresh helper instead of reusing a queued node")
	await get_tree().process_frame
	_expect(obstacle.get_node_or_null("TemporaryNavigationObstacle3D") == temporary,
		"fresh avoidance helper must survive deletion of the previous helper")
	previous = _debug_chunk(navigation, Vector2i(4, 4)).dirty_revision
	obstacle.free()
	_expect(_debug_chunk(navigation, Vector2i(4, 4)).dirty_revision == previous + 1,
		"source deletion must automatically dirty registered bounds")
	navigation.queue_free()

func _test_voxel_settings_validation() -> void:
	var navigation: ChunkedUnitNavigation = _make_navigation() as ChunkedUnitNavigation
	var navigation_map: RID = get_viewport().world_3d.navigation_map
	var cell_size: float = NavigationServer3D.map_get_cell_size(navigation_map)
	var cell_height: float = NavigationServer3D.map_get_cell_height(navigation_map)
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.cell_size = cell_size
	mesh.cell_height = cell_height
	navigation.navigation_mesh_template = mesh
	navigation.initialize_chunks()
	_expect(navigation.get_debug_snapshot().initialized and navigation.get_chunk_count() == 25,
		"matching map and mesh voxel settings must initialize")
	for property: StringName in [&"cell_size", &"cell_height"]:
		mesh.set(property, float(mesh.get(property)) * 2.0)
		print("voxel validation: expected error for %s mismatch" % property)
		navigation.initialize_chunks()
		await get_tree().process_frame
		_expect(not navigation.get_debug_snapshot().initialized and navigation.get_chunk_count() == 0,
			"voxel mismatch must stop initialization without creating regions")
		_expect(navigation.get_children().is_empty(), "failed initialization must remove old regions")
		_expect(not navigation.is_world_position_navigable(Vector3.ONE), "failed manager must reject preflight")
		_expect(is_equal_approx(NavigationServer3D.map_get_cell_size(navigation_map), cell_size)
			and is_equal_approx(NavigationServer3D.map_get_cell_height(navigation_map), cell_height),
			"validation must not overwrite shared map voxel settings")
		mesh.cell_size = cell_size
		mesh.cell_height = cell_height
	navigation.queue_free()

func _test_chunk_settings_validation() -> void:
	var navigation: ChunkedUnitNavigation = _make_navigation() as ChunkedUnitNavigation
	for count: Vector2i in [Vector2i(0, 5), Vector2i(5, 0), Vector2i(-1, 5), Vector2i(5, -1)]:
		navigation.map_chunk_count = count
		print("chunk validation: expected error for count %s" % count)
		navigation.initialize_chunks()
		_expect(not navigation.get_debug_snapshot().initialized and navigation.get_chunk_count() == 0,
			"nonpositive chunk counts must stop initialization")
	navigation.map_chunk_count = Vector2i(5, 5)
	for size: Vector2 in [Vector2(0, 10), Vector2(10, 0), Vector2(-1, 10), Vector2(10, -1), Vector2(INF, 10)]:
		navigation.chunk_size = size
		print("chunk validation: expected error for size %s" % size)
		navigation.initialize_chunks()
		_expect(not navigation.get_debug_snapshot().initialized and navigation.get_chunk_count() == 0,
			"nonpositive or nonfinite chunk sizes must stop initialization")
		_expect(not navigation.is_world_position_navigable(Vector3.ONE), "invalid size must safely reject preflight")
	await get_tree().process_frame
	_expect(navigation.get_children().is_empty(), "invalid dimensions must not leave regions")
	navigation.queue_free()

func _test_dynamic_geometry_registration() -> void:
	var navigation: ChunkedUnitNavigation = _make_navigation() as ChunkedUnitNavigation
	var geometry: Node3D = Node3D.new()
	add_child(geometry)
	geometry.global_position = Vector3(10.0, 0.0, 15.0)
	navigation.register_dynamic_geometry(geometry, true, 2.0, 2.0)
	_expect(navigation.get_debug_snapshot().dynamic_geometry_count == 1
		and navigation.get_debug_snapshot().solid_blocker_count == 0, "dynamic geometry must only enter its own registry")
	_expect(navigation.is_chunk_dirty(Vector2i(0, 1)) and navigation.is_chunk_dirty(Vector2i(1, 1)),
		"dynamic geometry must dirty all touched chunks")
	var temporary: NavigationObstacle3D = geometry.get_node_or_null("TemporaryNavigationObstacle3D") as NavigationObstacle3D
	_expect(temporary != null, "dynamic geometry may request temporary avoidance")
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	var bounds: AABB = AABB(Vector3.ZERO, Vector3(50.0, 10.0, 50.0))
	navigation._append_registered_solid_blockers(source, Vector3.ZERO, bounds)
	_expect(source.get_projected_obstructions().is_empty(), "dynamic geometry must not produce an AABB projected blocker")
	var previous: int = _debug_chunk(navigation, Vector2i(0, 1)).dirty_revision
	geometry.global_position = Vector3(45.0, 0.0, 45.0)
	navigation.register_dynamic_geometry(geometry, true, 3.0, 2.0)
	_expect(_debug_chunk(navigation, Vector2i(0, 1)).dirty_revision == previous + 1
		and navigation.is_chunk_dirty(Vector2i(4, 4)), "re-registration must dirty old and new bounds")
	_expect(temporary.global_position == geometry.global_position and is_equal_approx(temporary.radius, 3.0),
		"re-registration must refresh avoidance dimensions and position")
	navigation.register_solid_blocker(geometry, false)
	_expect(navigation.get_debug_snapshot().dynamic_geometry_count == 0
		and navigation.get_debug_snapshot().solid_blocker_count == 1, "switching roles must leave disjoint registries")
	navigation._append_registered_solid_blockers(source, Vector3.ZERO, bounds)
	_expect(source.get_projected_obstructions().size() == 1, "solid blockers must project their AABB")
	navigation.register_dynamic_geometry(geometry, false)
	source.clear()
	navigation._append_registered_solid_blockers(source, Vector3.ZERO, bounds)
	_expect(source.get_projected_obstructions().is_empty(), "switching back to geometry must remove projected blocking")
	previous = _debug_chunk(navigation, Vector2i(4, 4)).dirty_revision
	navigation.unregister_navigation_geometry(geometry)
	navigation.unregister_navigation_geometry(geometry)
	await get_tree().process_frame
	_expect(geometry.get_node_or_null("TemporaryNavigationObstacle3D") == null, "geometry unregister must remove avoidance")
	geometry.free()
	_expect(_debug_chunk(navigation, Vector2i(4, 4)).dirty_revision == previous + 1,
		"manual unregister followed by tree_exiting must be idempotent")
	_expect(navigation.get_debug_snapshot().dynamic_geometry_count == 0
		and navigation.get_debug_snapshot().solid_blocker_count == 0, "unregister must clear both registries")
	navigation.queue_free()

func _debug_chunk(navigation: ChunkedUnitNavigation, coords: Vector2i) -> Dictionary:
	for chunk: Dictionary in navigation.get_debug_snapshot().chunks:
		if chunk.coords == coords:
			return chunk
	return {}

func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	_failed = true
	push_error(message)
