extends Node

const ChunkedUnitNavigationScript := preload("res://scripts/navigation/chunked_unit_navigation.gd")

var _failed := false

func _ready() -> void:
	_test_creates_5_by_5_chunks()
	_test_world_position_to_chunk_coords()
	_test_dirty_chunk_tracking()
	_test_astar_avoids_blocked_chunks()
	_test_world_waypoints_end_at_target()
	_test_world_waypoints_use_chunk_transition_portals()
	_test_world_waypoints_use_start_height()
	_test_dynamic_obstacle_marks_chunk_and_adds_temporary_obstacle()

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

func _test_dynamic_obstacle_marks_chunk_and_adds_temporary_obstacle() -> void:
	var navigation: Variant = _make_navigation()
	var obstacle := Node3D.new()
	add_child(obstacle)
	obstacle.global_position = Vector3(22.0, 0.0, 31.0)

	var coords: Vector2i = navigation.register_dynamic_obstacle(obstacle, true, 1.5, 2.5)
	_expect(coords == Vector2i(2, 3), "dynamic obstacle should report its chunk")
	_expect(navigation.is_chunk_dirty(Vector2i(2, 3)), "dynamic obstacle should mark its chunk dirty")
	_expect(obstacle.get_node_or_null("TemporaryNavigationObstacle3D") is NavigationObstacle3D, "dynamic obstacle should receive a temporary NavigationObstacle3D")

	obstacle.queue_free()
	navigation.queue_free()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	_failed = true
	push_error(message)
