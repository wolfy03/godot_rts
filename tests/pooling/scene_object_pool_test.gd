extends Node

const SceneObjectPoolScript := preload("res://scripts/pooling/scene_object_pool.gd")
const TEST_OBJECT_SCENE := preload("res://tests/pooling/fixtures/pool_test_object.tscn")

var _failed := false

func _ready() -> void:
	var pool = SceneObjectPoolScript.new()
	add_child(pool)

	var first := pool.acquire(TEST_OBJECT_SCENE, self)
	var second := pool.acquire(TEST_OBJECT_SCENE, self)
	_expect(first != null and second != null, "pool should acquire valid instances")
	_expect(first != second, "pool should auto-expand while all instances are active")
	_expect(first.acquired_count == 1, "acquire hook should run for new instances")
	_expect(first.process_mode == Node.PROCESS_MODE_INHERIT, "acquired instances should process normally")
	_expect(first.get_node("Visual").visible, "acquired visual nodes should be visible")

	pool.release(first)
	_expect(first.released_count == 1, "release hook should run")
	_expect(first.process_mode == Node.PROCESS_MODE_DISABLED, "released instances should stop processing")
	_expect(not first.get_node("Visual").visible, "released visual nodes should be hidden")

	var reused := pool.acquire(TEST_OBJECT_SCENE, self)
	_expect(reused == first, "released instances should be reused before expanding")
	_expect(reused.acquired_count == 2, "acquire hook should run again on reuse")
	_expect(pool.get_created_count(TEST_OBJECT_SCENE) == 2, "pool should track automatically expanded instance count")
	_expect(pool.get_available_count(TEST_OBJECT_SCENE) == 0, "reacquired instances should leave the available queue")

	pool.release(reused)
	pool.release(second)
	_expect(pool.get_available_count(TEST_OBJECT_SCENE) == 2, "released instances should return to the scene queue")

	var default_instance := SceneObjectPoolScript.acquire_default(self, TEST_OBJECT_SCENE, self)
	_expect(default_instance != null, "default pool access should acquire from the registered autoload")
	SceneObjectPoolScript.release_instance(default_instance)
	var default_pool := get_node_or_null("/root/SceneObjectPoolService")
	_expect(default_instance.get_parent() == default_pool, "static release should return instances to their owning pool")

	await get_tree().process_frame
	if _failed:
		get_tree().quit(1)
	else:
		print("scene_object_pool_test: PASS")
		get_tree().quit(0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
