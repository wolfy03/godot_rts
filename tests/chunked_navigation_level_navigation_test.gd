extends Node

const TEST_LEVEL := preload("res://scenes/levels/chunked_navigation_test_level.tscn")

var _failed := false

func _ready() -> void:
	var level := TEST_LEVEL.instantiate()
	add_child(level)

	await get_tree().process_frame

	var unit := level.get_node("UnitsContainer/TestAIUnit") as Unit
	_expect(unit != null, "test unit should exist")
	var navigation := level.get_node("ChunkedNavigation") as ChunkedUnitNavigation
	_expect(navigation != null, "chunked navigation manager should exist")
	var target_position := Vector3(20.0, unit.global_position.y, 20.0)
	var navigation_map: RID = unit.navigation_agent.get_navigation_map()
	var bake_ready: bool = false
	for frame in range(2400):
		await get_tree().physics_frame
		var snapshot: Dictionary = navigation.get_debug_snapshot()
		if snapshot.queued_count == 0 and not snapshot.bake_active and NavigationServer3D.map_get_iteration_id(navigation_map) != 0:
			# A finished region bake does not guarantee the map snapshot is current.
			var path: PackedVector3Array = NavigationServer3D.map_get_path(navigation_map, unit.global_position, target_position, true)
			if not path.is_empty() and Vector2(path[-1].x, path[-1].z).distance_to(Vector2(target_position.x, target_position.z)) < 0.1:
				bake_ready = true
				break
	_expect(bake_ready, "real level ground bake and connected server path must finish")
	if not bake_ready:
		get_tree().quit(1)
		return
	var unit_start_position := unit.global_position
	var start_chunk: Vector2i = navigation.get_chunk_coords(unit_start_position)

	unit.navigation_agent.target_desired_distance = 0.5
	var command: MoveState.MoveCommandData = MoveState.MoveCommandData.new()
	command.target_position = target_position
	command.attack_move = false
	unit.begin_player_command(Unit.PlayerCommandMode.MOVE)
	unit.state_machine.transition_to_state(MoveState.ID, command)
	_expect(unit.navigation_agent.target_position == target_position, "MoveState must assign the final target directly")
	for frame in range(900):
		await get_tree().physics_frame
		if Vector2(unit.global_position.x, unit.global_position.z).distance_to(Vector2(20.0, 20.0)) < 0.6:
			break
	_expect(navigation.get_chunk_coords(unit.global_position) != start_chunk, "unit must traverse actual region boundaries")
	_expect(Vector2(unit.global_position.x, unit.global_position.z).distance_to(Vector2(20.0, 20.0)) < 0.6,
		"unit must arrive at the final destination")
	_expect(not unit.navigation_agent.has_meta(ChunkedUnitNavigation.META_WAYPOINTS), "ordinary move must not use portals")

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
