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
	var bake_ready: bool = false
	for frame in range(2400):
		await get_tree().physics_frame
		var snapshot: Dictionary = navigation.get_debug_snapshot()
		if snapshot.queued_count == 0 and not snapshot.bake_active:
			bake_ready = true
			break
	if not bake_ready:
		push_error("long move must wait for real level bake")
		get_tree().quit(1)
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	var start_position := unit.global_position
	var start_chunk := navigation.get_chunk_coords(start_position)
	var target: Vector3 = Vector3(20.0, unit.global_position.y, 20.0)
	unit.navigation_agent.target_desired_distance = 0.5
	unit.navigation_agent.target_position = target
	var visited: Array[Vector2i] = []
	for frame in range(900):
		await get_tree().physics_frame
		var coords: Vector2i = navigation.get_chunk_coords(unit.global_position)
		if not visited.has(coords):
			visited.append(coords)
		if Vector2(unit.global_position.x, unit.global_position.z).distance_to(Vector2(20.0, 20.0)) < 0.6:
			break
	if visited.size() < 5 or Vector2(unit.global_position.x, unit.global_position.z).distance_to(Vector2(20.0, 20.0)) >= 0.6:
		_failed = true
		push_error("single-target long move must cross multiple regions and arrive, visited=%s final_position=%s" % [visited, unit.global_position])

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
