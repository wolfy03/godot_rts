extends Node

const TEST_LEVEL := preload("res://scenes/levels/chunked_navigation_test_level.tscn")

var _failed := false

func _ready() -> void:
	var level := TEST_LEVEL.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var unit := level.get_node("UnitsContainer/TestAIUnit") as Unit
	var navigation := level.get_node("ChunkedNavigation") as ChunkedUnitNavigation
	var start_position := unit.global_position
	var start_chunk := navigation.get_chunk_coords(start_position)
	var waypoints := navigation.assign_agent_path(unit.navigation_agent, unit.global_position, Vector3(20.0, 0.0, 20.0))
	if waypoints.size() <= 1:
		_failed = true
		push_error("long move should use multiple chunk transition waypoints")
	await get_tree().create_timer(5.0).timeout

	var moved_distance := unit.global_position.distance_to(start_position)
	var final_chunk := navigation.get_chunk_coords(unit.global_position)
	if moved_distance < 10.0:
		_failed = true
		push_error("unit should move several meters, moved_distance=%f final_position=%s" % [moved_distance, unit.global_position])
	if final_chunk == start_chunk:
		_failed = true
		push_error("unit should leave the start chunk during a long move, start_chunk=%s final_chunk=%s final_position=%s" % [start_chunk, final_chunk, unit.global_position])
	if unit.global_position.distance_to(Vector3.ZERO) < 1.0:
		_failed = true
		push_error("unit should not remain vibrating near center, final_position=%s" % [unit.global_position])

	if not _failed:
		print("chunked_navigation_long_move_probe: PASS")
	get_tree().quit(1 if _failed else 0)
