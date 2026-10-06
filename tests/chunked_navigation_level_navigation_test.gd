extends Node

const TEST_LEVEL := preload("res://scenes/levels/chunked_navigation_test_level.tscn")

var _failed := false

func _ready() -> void:
	var level := TEST_LEVEL.instantiate()
	add_child(level)

	await get_tree().process_frame
	await get_tree().physics_frame

	var unit := level.get_node("UnitsContainer/TestAIUnit") as Unit
	_expect(unit != null, "test unit should exist")
	var navigation := level.get_node("ChunkedNavigation") as ChunkedUnitNavigation
	_expect(navigation != null, "chunked navigation manager should exist")
	var unit_start_position := unit.global_position
	var target_position := Vector3(20.0, 0.0, 20.0)

	var waypoints := navigation.assign_agent_path(unit.navigation_agent, unit.global_position, target_position)
	_expect(waypoints.size() > 1, "cross-chunk path should be split into A* transition waypoints")
	_expect(is_equal_approx(waypoints[0].y, unit.global_position.y), "first waypoint should match unit navigation height")
	await get_tree().create_timer(0.75).timeout
	var next_path_position := unit.navigation_agent.get_next_path_position()
	_expect(next_path_position.distance_squared_to(unit_start_position) > 0.01, "NavigationAgent3D should return a next path position")
	_expect(unit.global_position.distance_squared_to(unit_start_position) > 0.01, "unit should move after receiving a navigation target")

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("chunked_navigation_level_navigation_test: PASS")
		get_tree().quit(0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
