extends Node
class_name SceneObjectPool

const META_POOL_KEY := &"scene_object_pool_key"
const META_POOL_OWNER_ID := &"scene_object_pool_owner_id"
const META_POOL_ACTIVE := &"scene_object_pool_active"
const METHOD_POOL_ACQUIRED := &"on_pool_acquired"
const METHOD_POOL_RELEASED := &"on_pool_released"
const DEFAULT_POOL_PATH := NodePath("/root/SceneObjectPoolService")

var _available_by_key: Dictionary = {}
var _created_count_by_key: Dictionary = {}

static func acquire_default(context: Node, scene: PackedScene, parent: Node = null) -> Node:
	if context == null or not is_instance_valid(context):
		return null
	var tree := context.get_tree()
	if tree == null:
		return null
	var pool := tree.root.get_node_or_null(DEFAULT_POOL_PATH)
	if pool == null or not pool.has_method("acquire"):
		return null
	return pool.acquire(scene, parent)

static func release_instance(instance: Node) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	var owner_id := int(instance.get_meta(META_POOL_OWNER_ID, 0))
	var pool := instance_from_id(owner_id) as Node if owner_id != 0 else null
	if pool != null and is_instance_valid(pool) and pool.has_method("release"):
		pool.release(instance)
	else:
		instance.queue_free()

func acquire(scene: PackedScene, parent: Node = null) -> Node:
	if scene == null:
		return null

	var target_parent := parent if parent != null else get_tree().current_scene
	if target_parent == null or not is_instance_valid(target_parent):
		return null

	var pool_key := _get_pool_key(scene)
	var instance := _take_available(pool_key)
	if instance == null:
		instance = scene.instantiate()
		if instance == null:
			return null
		instance.set_meta(META_POOL_KEY, pool_key)
		instance.set_meta(META_POOL_OWNER_ID, get_instance_id())
		_created_count_by_key[pool_key] = get_created_count(scene) + 1

	_move_to_parent(instance, target_parent)
	instance.set_meta(META_POOL_ACTIVE, true)
	instance.process_mode = Node.PROCESS_MODE_INHERIT
	_set_visuals_visible(instance, true)
	if instance.has_method(METHOD_POOL_ACQUIRED):
		instance.call(METHOD_POOL_ACQUIRED)
	return instance

func release(instance: Node) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	if int(instance.get_meta(META_POOL_OWNER_ID, 0)) != get_instance_id():
		instance.queue_free()
		return
	if not bool(instance.get_meta(META_POOL_ACTIVE, false)):
		return

	if instance.has_method(METHOD_POOL_RELEASED):
		instance.call(METHOD_POOL_RELEASED)
	instance.set_meta(META_POOL_ACTIVE, false)
	instance.process_mode = Node.PROCESS_MODE_DISABLED
	_set_visuals_visible(instance, false)
	_move_to_parent(instance, self)

	var pool_key: StringName = instance.get_meta(META_POOL_KEY)
	var available: Array = _available_by_key.get(pool_key, [])
	available.append(instance)
	_available_by_key[pool_key] = available

func get_created_count(scene: PackedScene) -> int:
	if scene == null:
		return 0
	return int(_created_count_by_key.get(_get_pool_key(scene), 0))

func get_available_count(scene: PackedScene) -> int:
	if scene == null:
		return 0
	var available: Array = _available_by_key.get(_get_pool_key(scene), [])
	var valid_count := 0
	for instance in available:
		if instance != null and is_instance_valid(instance):
			valid_count += 1
	return valid_count

func _take_available(pool_key: StringName) -> Node:
	var available: Array = _available_by_key.get(pool_key, [])
	while not available.is_empty():
		var instance := available.pop_back() as Node
		if instance != null and is_instance_valid(instance):
			_available_by_key[pool_key] = available
			return instance
	_available_by_key[pool_key] = available
	return null

func _get_pool_key(scene: PackedScene) -> StringName:
	if not scene.resource_path.is_empty():
		return StringName(scene.resource_path)
	return StringName("runtime_scene_%d" % scene.get_instance_id())

func _move_to_parent(instance: Node, target_parent: Node) -> void:
	if instance.get_parent() == target_parent:
		return
	var current_parent := instance.get_parent()
	if current_parent != null:
		current_parent.remove_child(instance)
	target_parent.add_child(instance)

func _set_visuals_visible(node: Node, is_visible: bool) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = is_visible
	elif node is VisualInstance3D:
		(node as VisualInstance3D).visible = is_visible
	for child in node.get_children():
		_set_visuals_visible(child, is_visible)
