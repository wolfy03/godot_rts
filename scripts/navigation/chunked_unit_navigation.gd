extends Node
class_name ChunkedUnitNavigation

signal chunk_dirty_changed(coords: Vector2i, dirty: bool)
signal chunk_bake_requested(coords: Vector2i, region: NavigationRegion3D)
signal chunk_bake_finished(coords: Vector2i, region: NavigationRegion3D)
signal chunk_walkable_changed(coords: Vector2i, walkable: bool)

const DEFAULT_CHUNK_COUNT := Vector2i(5, 5)
const DEFAULT_CHUNK_SIZE := Vector2(20.0, 20.0)
const META_WAYPOINTS := &"chunked_unit_navigation_waypoints"
const META_WAYPOINT_INDEX := &"chunked_unit_navigation_waypoint_index"

@export var map_chunk_count: Vector2i = DEFAULT_CHUNK_COUNT
@export var chunk_size: Vector2 = DEFAULT_CHUNK_SIZE
@export var world_origin: Vector3 = Vector3.ZERO
@export var auto_initialize: bool = true
@export var auto_create_regions: bool = true
@export var bake_delay_seconds: float = 0.1
@export var navigation_region_parent_path: NodePath
@export var obstacle_parent_path: NodePath
@export var navigation_mesh_template: NavigationMesh
@export var bake_filter_height: float = 64.0
@export var flat_navigation_overlap: float = 0.0
@export var use_region_edge_connections: bool = true
@export var use_start_height_for_path_waypoints: bool = true
@export var default_agent_target_reached_distance: float = 0.5
@export var default_obstacle_radius: float = 1.0
@export var default_obstacle_height: float = 2.0
@export var bake_on_dirty: bool = true

class ChunkData:
	var coords: Vector2i
	var bounds: Rect2
	var region: NavigationRegion3D
	var dirty: bool = false
	var baking: bool = false
	var walkable: bool = true

	func _init(chunk_coords: Vector2i, chunk_bounds: Rect2) -> void:
		coords = chunk_coords
		bounds = chunk_bounds

var _chunks: Dictionary = {}
var _astar: AStarGrid2D = AStarGrid2D.new()
var _dirty_queue: Array[Vector2i] = []
var _bake_timer: SceneTreeTimer
var _initialized: bool = false

func _ready() -> void:
	add_to_group("chunked_unit_navigation")
	if auto_initialize:
		initialize_chunks()

func initialize_chunks() -> void:
	_chunks.clear()
	_dirty_queue.clear()
	_configure_astar()

	for z in range(map_chunk_count.y):
		for x in range(map_chunk_count.x):
			var coords := Vector2i(x, z)
			var data := ChunkData.new(coords, _get_bounds_for_chunk(coords))
			if auto_create_regions:
				data.region = _create_navigation_region(coords)
			_chunks[_chunk_key(coords)] = data

	_initialized = true

func clear_chunks() -> void:
	_chunks.clear()
	_dirty_queue.clear()
	_initialized = false

func get_chunk_count() -> int:
	return _chunks.size()

func get_chunk_coords(world_position: Vector3) -> Vector2i:
	var local_x := world_position.x - world_origin.x
	var local_z := world_position.z - world_origin.z
	return Vector2i(floori(local_x / chunk_size.x), floori(local_z / chunk_size.y))

func is_chunk_coords_valid(coords: Vector2i) -> bool:
	return coords.x >= 0 and coords.y >= 0 and coords.x < map_chunk_count.x and coords.y < map_chunk_count.y

func get_chunk_center(coords: Vector2i) -> Vector3:
	var x := world_origin.x + (float(coords.x) + 0.5) * chunk_size.x
	var z := world_origin.z + (float(coords.y) + 0.5) * chunk_size.y
	return Vector3(x, world_origin.y, z)

func get_chunk_region(coords: Vector2i) -> NavigationRegion3D:
	var data := _get_chunk_data(coords)
	if data == null:
		return null
	return data.region

func get_chunk_bounds(coords: Vector2i) -> Rect2:
	var data := _get_chunk_data(coords)
	if data == null:
		return Rect2()
	return data.bounds

func is_chunk_dirty(coords: Vector2i) -> bool:
	var data := _get_chunk_data(coords)
	return data != null and data.dirty

func is_chunk_baking(coords: Vector2i) -> bool:
	var data := _get_chunk_data(coords)
	return data != null and data.baking

func is_chunk_walkable(coords: Vector2i) -> bool:
	var data := _get_chunk_data(coords)
	return data != null and data.walkable

func set_chunk_walkable(coords: Vector2i, walkable: bool) -> void:
	var data := _get_chunk_data(coords)
	if data == null or data.walkable == walkable:
		return

	data.walkable = walkable
	_astar.set_point_solid(coords, not walkable)
	chunk_walkable_changed.emit(coords, walkable)

func mark_chunk_dirty(coords: Vector2i) -> void:
	var data := _get_chunk_data(coords)
	if data == null:
		return

	data.dirty = true
	if not _dirty_queue.has(coords):
		_dirty_queue.append(coords)
	chunk_dirty_changed.emit(coords, true)

	if bake_on_dirty:
		_schedule_dirty_bake()

func mark_chunk_dirty_for_world_position(world_position: Vector3) -> void:
	mark_chunk_dirty(get_chunk_coords(world_position))

func mark_chunks_dirty_for_bounds(world_bounds: AABB) -> void:
	var min_coords := get_chunk_coords(world_bounds.position)
	var max_position := world_bounds.position + world_bounds.size
	var max_coords := get_chunk_coords(max_position)

	for z in range(min_coords.y, max_coords.y + 1):
		for x in range(min_coords.x, max_coords.x + 1):
			mark_chunk_dirty(Vector2i(x, z))

func register_dynamic_obstacle(
	obstacle_node: Node3D,
	add_temporary_navigation_obstacle: bool = true,
	avoidance_radius: float = -1.0,
	avoidance_height: float = -1.0
) -> Vector2i:
	if obstacle_node == null:
		return Vector2i(-1, -1)

	var coords := get_chunk_coords(obstacle_node.global_position)
	mark_chunk_dirty(coords)

	if add_temporary_navigation_obstacle:
		_ensure_navigation_obstacle(obstacle_node, avoidance_radius, avoidance_height)

	return coords

func unregister_dynamic_obstacle(obstacle_node: Node3D, remove_temporary_navigation_obstacle: bool = false) -> void:
	if obstacle_node == null:
		return

	mark_chunk_dirty_for_world_position(obstacle_node.global_position)
	if remove_temporary_navigation_obstacle:
		var existing := obstacle_node.get_node_or_null("TemporaryNavigationObstacle3D")
		if existing != null:
			existing.queue_free()

func request_bake_dirty_chunks() -> void:
	_schedule_dirty_bake()

func build_flat_chunk_navigation_meshes(y_offset: float = 0.0, overlap: float = -1.0, use_world_space_vertices: bool = false) -> void:
	if not _initialized:
		initialize_chunks()

	var resolved_overlap := flat_navigation_overlap if overlap < 0.0 else overlap
	for data_variant in _chunks.values():
		var data := data_variant as ChunkData
		if data == null or data.region == null:
			continue
		var mesh_origin := Vector2.ZERO
		if use_world_space_vertices:
			data.region.global_position = Vector3.ZERO
			mesh_origin = data.bounds.position
		data.region.navigation_mesh = _create_flat_chunk_navigation_mesh(y_offset, resolved_overlap, mesh_origin)

func get_chunk_path(from_world_position: Vector3, to_world_position: Vector3) -> Array[Vector2i]:
	if not _initialized:
		initialize_chunks()

	var start := get_chunk_coords(from_world_position)
	var goal := get_chunk_coords(to_world_position)
	if not is_chunk_coords_valid(start) or not is_chunk_coords_valid(goal):
		return []
	if _astar.is_point_solid(start) or _astar.is_point_solid(goal):
		return []

	var raw_path: Array = _astar.get_id_path(start, goal)
	var path: Array[Vector2i] = []
	for raw_coords in raw_path:
		path.append(raw_coords as Vector2i)
	return path

func get_world_path_waypoints(from_world_position: Vector3, to_world_position: Vector3) -> Array[Vector3]:
	var chunk_path := get_chunk_path(from_world_position, to_world_position)
	var waypoints: Array[Vector3] = []
	if chunk_path.is_empty():
		return waypoints

	var waypoint_y := from_world_position.y if use_start_height_for_path_waypoints else world_origin.y
	var final_target := _normalize_waypoint_height(to_world_position, waypoint_y)
	for i in range(1, chunk_path.size()):
		var previous_coords := chunk_path[i - 1]
		var coords := chunk_path[i]
		waypoints.append(_get_chunk_transition_waypoint(previous_coords, coords, waypoint_y))

	if waypoints.is_empty():
		waypoints.append(final_target)
	elif not waypoints[waypoints.size() - 1].is_equal_approx(final_target):
		waypoints.append(final_target)

	return waypoints

func assign_agent_path(
	agent: NavigationAgent3D,
	from_world_position: Vector3,
	to_world_position: Vector3,
	target_reached_distance: float = -1.0
) -> Array[Vector3]:
	var waypoints := get_world_path_waypoints(from_world_position, to_world_position)
	if agent == null or waypoints.is_empty():
		return waypoints

	if target_reached_distance >= 0.0:
		agent.target_desired_distance = target_reached_distance
	elif default_agent_target_reached_distance >= 0.0:
		agent.target_desired_distance = default_agent_target_reached_distance

	agent.set_meta(META_WAYPOINTS, waypoints)
	agent.set_meta(META_WAYPOINT_INDEX, 0)
	agent.target_position = waypoints[0]
	return waypoints

func advance_agent_waypoint(agent: NavigationAgent3D) -> bool:
	if agent == null or not agent.has_meta(META_WAYPOINTS):
		return false

	var waypoints: Array = agent.get_meta(META_WAYPOINTS)
	var current_index: int = int(agent.get_meta(META_WAYPOINT_INDEX, 0))
	if current_index >= waypoints.size() - 1:
		agent.remove_meta(META_WAYPOINTS)
		agent.remove_meta(META_WAYPOINT_INDEX)
		return false

	current_index += 1
	agent.set_meta(META_WAYPOINT_INDEX, current_index)
	agent.target_position = waypoints[current_index] as Vector3
	return true

func update_agent_waypoint_if_reached(agent: NavigationAgent3D) -> bool:
	if agent == null or not agent.is_target_reached():
		return false
	return advance_agent_waypoint(agent)

func _configure_astar() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(Vector2i.ZERO, map_chunk_count)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

func _get_bounds_for_chunk(coords: Vector2i) -> Rect2:
	var position := Vector2(
		world_origin.x + float(coords.x) * chunk_size.x,
		world_origin.z + float(coords.y) * chunk_size.y
	)
	return Rect2(position, chunk_size)

func _get_chunk_transition_waypoint(from_coords: Vector2i, to_coords: Vector2i, waypoint_y: float) -> Vector3:
	var from_bounds := get_chunk_bounds(from_coords)
	var to_bounds := get_chunk_bounds(to_coords)
	var shared_center := from_bounds.get_center().lerp(to_bounds.get_center(), 0.5)

	if to_coords.x > from_coords.x:
		return Vector3(from_bounds.position.x + from_bounds.size.x, waypoint_y, shared_center.y)
	if to_coords.x < from_coords.x:
		return Vector3(from_bounds.position.x, waypoint_y, shared_center.y)
	if to_coords.y > from_coords.y:
		return Vector3(shared_center.x, waypoint_y, from_bounds.position.y + from_bounds.size.y)
	if to_coords.y < from_coords.y:
		return Vector3(shared_center.x, waypoint_y, from_bounds.position.y)

	return _normalize_waypoint_height(get_chunk_center(to_coords), waypoint_y)

func _normalize_waypoint_height(position: Vector3, waypoint_y: float) -> Vector3:
	if not use_start_height_for_path_waypoints:
		return position
	return Vector3(position.x, waypoint_y, position.z)

func _create_navigation_region(coords: Vector2i) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D_%d_%d" % [coords.x, coords.y]

	var mesh: NavigationMesh
	if navigation_mesh_template != null:
		mesh = navigation_mesh_template.duplicate(true)
	else:
		mesh = NavigationMesh.new()

	_configure_chunk_navigation_mesh(mesh)
	if _object_has_property(region, "use_edge_connections"):
		region.set("use_edge_connections", use_region_edge_connections)

	_get_navigation_region_parent().add_child(region)
	region.global_position = Vector3(
		world_origin.x + float(coords.x) * chunk_size.x,
		world_origin.y,
		world_origin.z + float(coords.y) * chunk_size.y
	)
	region.navigation_mesh = mesh
	return region

func _configure_chunk_navigation_mesh(mesh: NavigationMesh) -> void:
	if mesh == null:
		return

	if _object_has_property(mesh, "filter_baking_aabb"):
		var height := maxf(bake_filter_height, 1.0)
		var filter := AABB(
			Vector3(0.0, -height * 0.5, 0.0),
			Vector3(chunk_size.x, height, chunk_size.y)
		)
		mesh.set("filter_baking_aabb", filter)

	if _object_has_property(mesh, "filter_baking_aabb_offset"):
		mesh.set("filter_baking_aabb_offset", Vector3.ZERO)

func _create_flat_chunk_navigation_mesh(y_offset: float, overlap: float, mesh_origin: Vector2 = Vector2.ZERO) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	if navigation_mesh_template != null:
		mesh = navigation_mesh_template.duplicate(true)
	else:
		mesh.agent_height = 1.0
		mesh.agent_radius = 0.45

	var max_negative_overlap := -minf(chunk_size.x, chunk_size.y) * 0.9
	var resolved_overlap := maxf(overlap, max_negative_overlap)
	var half_overlap := resolved_overlap * 0.5
	mesh.vertices = PackedVector3Array([
		Vector3(mesh_origin.x - half_overlap, y_offset, mesh_origin.y - half_overlap),
		Vector3(mesh_origin.x - half_overlap, y_offset, mesh_origin.y + chunk_size.y + half_overlap),
		Vector3(mesh_origin.x + chunk_size.x + half_overlap, y_offset, mesh_origin.y + chunk_size.y + half_overlap),
		Vector3(mesh_origin.x + chunk_size.x + half_overlap, y_offset, mesh_origin.y - half_overlap),
	])
	mesh.clear_polygons()
	mesh.add_polygon(PackedInt32Array([0, 1, 2]))
	mesh.add_polygon(PackedInt32Array([0, 2, 3]))
	_configure_chunk_navigation_mesh(mesh)
	return mesh

func _get_navigation_region_parent() -> Node:
	if navigation_region_parent_path != NodePath():
		var parent := get_node_or_null(navigation_region_parent_path)
		if parent != null:
			return parent
	return self

func _get_obstacle_parent() -> Node:
	if obstacle_parent_path != NodePath():
		var parent := get_node_or_null(obstacle_parent_path)
		if parent != null:
			return parent
	return self

func _ensure_navigation_obstacle(obstacle_node: Node3D, avoidance_radius: float, avoidance_height: float) -> NavigationObstacle3D:
	var existing := obstacle_node.get_node_or_null("TemporaryNavigationObstacle3D")
	if existing is NavigationObstacle3D:
		return existing as NavigationObstacle3D

	var navigation_obstacle := NavigationObstacle3D.new()
	navigation_obstacle.name = "TemporaryNavigationObstacle3D"
	navigation_obstacle.set("avoidance_enabled", true)
	navigation_obstacle.set("radius", default_obstacle_radius if avoidance_radius < 0.0 else avoidance_radius)
	navigation_obstacle.set("height", default_obstacle_height if avoidance_height < 0.0 else avoidance_height)
	navigation_obstacle.set("use_3d_avoidance", true)
	obstacle_node.add_child(navigation_obstacle)
	return navigation_obstacle

func _object_has_property(object: Object, property_name: String) -> bool:
	var properties: Array = object.get_property_list()
	for property_data in properties:
		var current_name := String(property_data.get("name", ""))
		if current_name == property_name:
			return true
	return false

func _schedule_dirty_bake() -> void:
	if not is_inside_tree():
		return
	if _bake_timer != null:
		return

	var delay := maxf(bake_delay_seconds, 0.0)
	_bake_timer = get_tree().create_timer(delay)
	_bake_timer.timeout.connect(_process_dirty_bake_queue, CONNECT_ONE_SHOT)

func _process_dirty_bake_queue() -> void:
	_bake_timer = null
	if _dirty_queue.is_empty():
		return

	var coords := _dirty_queue.pop_front() as Vector2i
	var data := _get_chunk_data(coords)
	if data == null:
		_process_dirty_bake_queue()
		return
	if data.region == null:
		data.dirty = false
		chunk_dirty_changed.emit(coords, false)
		_process_dirty_bake_queue()
		return

	data.baking = true
	chunk_bake_requested.emit(coords, data.region)

	if data.region.has_method("bake_navigation_mesh"):
		if data.region.has_signal("bake_finished"):
			var on_bake_finished: Callable = func() -> void:
				_finish_chunk_bake_request(coords)
			data.region.bake_finished.connect(on_bake_finished, CONNECT_ONE_SHOT)
		else:
			call_deferred("_finish_chunk_bake_request", coords)
		data.region.call_deferred("bake_navigation_mesh", true)
	else:
		call_deferred("_finish_chunk_bake_request", coords)

func _finish_chunk_bake_request(coords: Vector2i) -> void:
	var data := _get_chunk_data(coords)
	if data == null:
		return

	data.baking = false
	data.dirty = false
	chunk_dirty_changed.emit(coords, false)
	chunk_bake_finished.emit(coords, data.region)

	if not _dirty_queue.is_empty():
		_schedule_dirty_bake()

func _get_chunk_data(coords: Vector2i) -> ChunkData:
	if not is_chunk_coords_valid(coords):
		return null
	return _chunks.get(_chunk_key(coords), null) as ChunkData

func _chunk_key(coords: Vector2i) -> String:
	return "%d:%d" % [coords.x, coords.y]
