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
## Explicit root containing ground and static/dynamic bake geometry, not regions.
@export var source_geometry_root_path: NodePath
@export var navigation_mesh_template: NavigationMesh
@export var bake_filter_height: float = 64.0
@export var navigation_border_size: float = 0.5
@export var edge_connection_margin: float = 0.05
@export_flags_3d_navigation var obstacle_avoidance_layers: int = 3
@export var debug_logging: bool = false
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
	var dirty_revision: int = 0
	var baking_revision: int = 0
	var bake_request_count: int = 0
	var bake_finished_count: int = 0

	func _init(chunk_coords: Vector2i, chunk_bounds: Rect2) -> void:
		coords = chunk_coords
		bounds = chunk_bounds

var _chunks: Dictionary = {}
var _astar: AStarGrid2D = AStarGrid2D.new()
var _dirty_queue: Array[Vector2i] = []
var _bake_timer: SceneTreeTimer
var _initialized: bool = false
var _bake_active: bool = false
var _generation: int = 0
var _dynamic_geometry_bounds: Dictionary[int, AABB] = {}
var _solid_blocker_bounds: Dictionary[int, AABB] = {}

func _ready() -> void:
	add_to_group("chunked_unit_navigation")
	if auto_initialize:
		initialize_chunks()

func initialize_chunks() -> void:
	clear_chunks()
	if not _validate_chunk_settings() or not _validate_navigation_voxel_settings():
		return
	_warn_source_root_transform()
	_configure_astar()
	var navigation_map: RID = get_viewport().world_3d.navigation_map
	NavigationServer3D.map_set_edge_connection_margin(navigation_map, edge_connection_margin)

	for z in range(map_chunk_count.y):
		for x in range(map_chunk_count.x):
			var coords := Vector2i(x, z)
			var data := ChunkData.new(coords, _get_bounds_for_chunk(coords))
			if auto_create_regions:
				data.region = _create_navigation_region(coords)
			_chunks[_chunk_key(coords)] = data

	_initialized = true

func _validate_chunk_settings() -> bool:
	if map_chunk_count.x <= 0 or map_chunk_count.y <= 0:
		push_error("[NAV] map_chunk_count must be positive. count=%s" % map_chunk_count)
		return false
	if not chunk_size.is_finite() or chunk_size.x <= 0.0 or chunk_size.y <= 0.0:
		push_error("[NAV] chunk_size must be finite and positive. size=%s" % chunk_size)
		return false
	return true

func _validate_navigation_voxel_settings() -> bool:
	var mesh: NavigationMesh = _new_navigation_mesh()
	var navigation_map: RID = get_viewport().world_3d.navigation_map
	var map_cell_size: float = NavigationServer3D.map_get_cell_size(navigation_map)
	var map_cell_height: float = NavigationServer3D.map_get_cell_height(navigation_map)
	var matches: bool = true
	if not is_equal_approx(mesh.cell_size, map_cell_size):
		push_error("[NAV] NavigationMesh cell_size mismatch. mesh=%f map=%f" % [mesh.cell_size, map_cell_size])
		matches = false
	if not is_equal_approx(mesh.cell_height, map_cell_height):
		push_error("[NAV] NavigationMesh cell_height mismatch. mesh=%f map=%f" % [mesh.cell_height, map_cell_height])
		matches = false
	return matches

func _warn_source_root_transform() -> void:
	var root: Node3D = get_node_or_null(source_geometry_root_path) as Node3D if source_geometry_root_path != NodePath() else null
	if root == null:
		return
	var basis: Basis = root.global_basis
	if not basis.y.normalized().is_equal_approx(Vector3.UP):
		push_warning("[NAV] Source geometry root is tilted. Projected XZ obstructions require an upright root.")
	var scale: Vector3 = basis.get_scale().abs()
	if not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.y, scale.z):
		push_warning("[NAV] Source geometry root has non-uniform scale. Projected XZ obstructions may not match geometry.")

## Clears generated navigation chunks and bake state only.
## Registered world geometry intentionally persists so reinitializing regions
## does not lose runtime geometry tracking or temporary avoidance helpers.
func clear_chunks() -> void:
	_generation += 1
	for data: ChunkData in _chunks.values():
		if is_instance_valid(data.region):
			data.region.enabled = false
			data.region.queue_free()
	_chunks.clear()
	_dirty_queue.clear()
	_initialized = false
	_bake_active = false

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
	if is_instance_valid(data.region):
		data.region.enabled = walkable
	chunk_walkable_changed.emit(coords, walkable)

## Coarse preflight only. The NavigationAgent verifies the actual polygon path.
func is_world_position_navigable(world_position: Vector3) -> bool:
	return _initialized and world_position.is_finite() and is_chunk_walkable(get_chunk_coords(world_position))

func mark_chunk_dirty(coords: Vector2i) -> void:
	var data := _get_chunk_data(coords)
	if data == null:
		return

	data.dirty_revision += 1
	var was_dirty: bool = data.dirty
	data.dirty = true
	if not data.baking and not _dirty_queue.has(coords):
		_dirty_queue.append(coords)
	if not was_dirty:
		chunk_dirty_changed.emit(coords, true)
		_log("Dirty chunk: %s (revision %d)" % [coords, data.dirty_revision])

	if bake_on_dirty:
		_schedule_dirty_bake()

func mark_chunk_dirty_for_world_position(world_position: Vector3) -> void:
	mark_chunk_dirty(get_chunk_coords(world_position))

func mark_chunks_dirty_for_bounds(world_bounds: AABB) -> void:
	mark_world_bounds_dirty(world_bounds)

## Geometry changes affect neighboring bake halos as well as the touched chunk.
func mark_world_bounds_dirty(world_bounds: AABB) -> void:
	if not _initialized:
		return
	var halo: float = _get_bake_border(_new_navigation_mesh())
	var min_coords: Vector2i = get_chunk_coords(world_bounds.position - Vector3(halo, 0.0, halo))
	var max_coords: Vector2i = get_chunk_coords(world_bounds.end + Vector3(halo, 0.0, halo))
	min_coords = min_coords.max(Vector2i.ZERO)
	max_coords = max_coords.min(map_chunk_count - Vector2i.ONE)

	for z in range(min_coords.y, max_coords.y + 1):
		for x in range(min_coords.x, max_coords.x + 1):
			mark_chunk_dirty(Vector2i(x, z))

## Actual collider geometry is parsed from the source root; openings stay open.
## Every registration reapplies temporary avoidance: true ensures an enabled
## helper; false disables and queues any existing helper for deletion.
func register_dynamic_geometry(
	geometry_node: Node3D,
	add_temporary_navigation_obstacle: bool = true,
	avoidance_radius: float = -1.0,
	avoidance_height: float = -1.0
) -> Vector2i:
	return _register_navigation_geometry(geometry_node, false, add_temporary_navigation_obstacle, avoidance_radius, avoidance_height)

## Explicit opt-in for objects whose entire world AABB is unwalkable.
## Temporary avoidance follows the same registration contract as dynamic geometry.
func register_solid_blocker(
	blocker_node: Node3D,
	add_temporary_navigation_obstacle: bool = true,
	avoidance_radius: float = -1.0,
	avoidance_height: float = -1.0
) -> Vector2i:
	return _register_navigation_geometry(blocker_node, true, add_temporary_navigation_obstacle, avoidance_radius, avoidance_height)

func _register_navigation_geometry(
	geometry_node: Node3D,
	solid_blocker: bool,
	add_temporary_navigation_obstacle: bool = true,
	avoidance_radius: float = -1.0,
	avoidance_height: float = -1.0
) -> Vector2i:
	if not _initialized or not is_instance_valid(geometry_node):
		return Vector2i(-1, -1)

	_warn_if_geometry_outside_source_root(geometry_node, solid_blocker)
	var coords := get_chunk_coords(geometry_node.global_position)
	var instance_id: int = geometry_node.get_instance_id()
	# Re-registration can also change the role. Dirty old bounds and keep the
	# registries disjoint so a former solid blocker cannot keep carving openings.
	_unregister_navigation_geometry_by_id(instance_id)
	var bounds: AABB = get_obstacle_world_bounds(geometry_node, avoidance_radius, avoidance_height)
	if solid_blocker:
		_solid_blocker_bounds[instance_id] = bounds
	else:
		_dynamic_geometry_bounds[instance_id] = bounds
	mark_world_bounds_dirty(bounds)
	var on_exit: Callable = _unregister_navigation_geometry_by_id.bind(instance_id)
	if not geometry_node.tree_exiting.is_connected(on_exit):
		geometry_node.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)

	if add_temporary_navigation_obstacle:
		_ensure_navigation_obstacle(geometry_node, avoidance_radius, avoidance_height)
	else:
		_remove_temporary_navigation_obstacle(geometry_node)

	return coords

func unregister_navigation_geometry(geometry_node: Node3D, remove_temporary_navigation_obstacle: bool = true) -> void:
	if not is_instance_valid(geometry_node):
		return

	_unregister_navigation_geometry_by_id(geometry_node.get_instance_id())
	if remove_temporary_navigation_obstacle:
		_remove_temporary_navigation_obstacle(geometry_node)

func _warn_if_geometry_outside_source_root(geometry_node: Node3D, solid_blocker: bool) -> void:
	if source_geometry_root_path == NodePath():
		return
	var source_root: Node3D = get_node_or_null(source_geometry_root_path) as Node3D
	if source_root == null or geometry_node == source_root or source_root.is_ancestor_of(geometry_node):
		return
	var consequence: String = "It will dirty navigation chunks, but its actual collider/mesh geometry will not be parsed during runtime bake."
	if solid_blocker:
		consequence = "Its source geometry will not be parsed during runtime bake; only registered projected AABB blocking will be available."
	push_warning("[NAV] Registered navigation geometry is outside source_geometry_root. node=%s source_root=%s. %s"
		% [geometry_node.get_path(), source_root.get_path(), consequence])

## Removal uses the registered bounds even if the obstacle has moved or freed.
## Remove its bake geometry before the scheduled parse (free/reparent/disable).
func _unregister_navigation_geometry_by_id(instance_id: int) -> void:
	if _dynamic_geometry_bounds.has(instance_id):
		mark_world_bounds_dirty(_dynamic_geometry_bounds[instance_id])
		_dynamic_geometry_bounds.erase(instance_id)
	if _solid_blocker_bounds.has(instance_id):
		mark_world_bounds_dirty(_solid_blocker_bounds[instance_id])
		_solid_blocker_bounds.erase(instance_id)

func get_obstacle_world_bounds(obstacle_node: Node3D, radius: float = -1.0, height: float = -1.0) -> AABB:
	var bounds: Array[AABB] = []
	_collect_geometry_bounds(obstacle_node, bounds)
	if not bounds.is_empty():
		var combined: AABB = bounds[0]
		for index in range(1, bounds.size()):
			combined = combined.merge(bounds[index])
		return combined
	var resolved_radius: float = default_obstacle_radius if radius < 0.0 else radius
	var resolved_height: float = default_obstacle_height if height < 0.0 else height
	return AABB(obstacle_node.global_position - Vector3(resolved_radius, 0.0, resolved_radius),
		Vector3(resolved_radius * 2.0, resolved_height, resolved_radius * 2.0))

func _collect_geometry_bounds(node: Node, bounds: Array[AABB]) -> void:
	# TODO: Replace debug-mesh extraction with shape-specific bounds before
	# large-scale destructible environments.
	var shape_node: CollisionShape3D = node as CollisionShape3D
	if shape_node != null and not shape_node.disabled and shape_node.shape != null:
		bounds.append(shape_node.global_transform * shape_node.shape.get_debug_mesh().get_aabb())
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		bounds.append(mesh_node.global_transform * mesh_node.mesh.get_aabb())
	for child: Node in node.get_children():
		_collect_geometry_bounds(child, bounds)

func request_bake_dirty_chunks() -> void:
	_schedule_dirty_bake()

## Test/helper meshes only. y_offset and vertices are always region-local.
func build_flat_chunk_navigation_meshes(y_offset: float = 0.0, overlap: float = -1.0) -> void:
	if not _initialized:
		initialize_chunks()
	if not _initialized:
		return

	var resolved_overlap := flat_navigation_overlap if overlap < 0.0 else overlap
	for data_variant in _chunks.values():
		var data := data_variant as ChunkData
		if data == null or data.region == null:
			continue
		data.region.navigation_mesh = _create_flat_chunk_navigation_mesh(y_offset, resolved_overlap)

## Coarse strategic helper, not the primary NavigationAgent movement path.
func get_chunk_path(from_world_position: Vector3, to_world_position: Vector3) -> Array[Vector2i]:
	if not _initialized:
		initialize_chunks()
	if not _initialized:
		return []

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

## Optional strategic/debug waypoints. MoveState never follows these portals.
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

## Legacy opt-in helper only; ordinary movement passes a final target directly.
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

	var mesh: NavigationMesh = _new_navigation_mesh()
	_configure_chunk_navigation_mesh(mesh)
	region.use_edge_connections = use_region_edge_connections

	_get_navigation_region_parent().add_child(region)
	region.global_transform = Transform3D(Basis.IDENTITY, Vector3(
		world_origin.x + float(coords.x) * chunk_size.x,
		world_origin.y,
		world_origin.z + float(coords.y) * chunk_size.y
	))
	region.navigation_mesh = mesh
	return region

func _configure_chunk_navigation_mesh(mesh: NavigationMesh) -> void:
	var border: float = _get_bake_border(mesh)
	var height: float = maxf(bake_filter_height, 1.0)
	# border_size trims INSIDE the bake AABB. Include a voxel-aligned neighbor
	# halo, then trim it, leaving exactly [0, chunk_size] without radius seams.
	mesh.border_size = border
	mesh.filter_baking_aabb = AABB(Vector3(-border, -height * 0.5, -border),
		Vector3(chunk_size.x + border * 2.0, height, chunk_size.y + border * 2.0))
	mesh.filter_baking_aabb_offset = Vector3.ZERO
	mesh.edge_max_error = minf(mesh.edge_max_error, 1.0)
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN

func _get_bake_border(mesh: NavigationMesh) -> float:
	# Ledge filtering consumes an additional raster cell before radius erosion.
	var clearance: float = mesh.agent_radius + (mesh.cell_size if mesh.filter_ledge_spans else 0.0)
	return ceilf(maxf(clearance, navigation_border_size) / mesh.cell_size) * mesh.cell_size

func _new_navigation_mesh() -> NavigationMesh:
	if navigation_mesh_template != null:
		return navigation_mesh_template.duplicate(true) as NavigationMesh
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.agent_height = 1.0
	# Conservative voxel-aligned clearance for the ground unit's 0.45m radius.
	mesh.agent_radius = 0.5
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.region_min_size = 0.0
	mesh.filter_ledge_spans = true
	mesh.filter_walkable_low_height_spans = true
	return mesh

func _create_flat_chunk_navigation_mesh(y_offset: float, overlap: float) -> NavigationMesh:
	var mesh: NavigationMesh = _new_navigation_mesh()

	var max_negative_overlap := -minf(chunk_size.x, chunk_size.y) * 0.9
	var resolved_overlap := maxf(overlap, max_negative_overlap)
	var half_overlap := resolved_overlap * 0.5
	mesh.vertices = PackedVector3Array([
		Vector3(-half_overlap, y_offset, -half_overlap),
		Vector3(-half_overlap, y_offset, chunk_size.y + half_overlap),
		Vector3(chunk_size.x + half_overlap, y_offset, chunk_size.y + half_overlap),
		Vector3(chunk_size.x + half_overlap, y_offset, -half_overlap),
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

## false registration and unregister share immediate disable / deferred removal.
func _remove_temporary_navigation_obstacle(geometry_node: Node3D) -> void:
	var obstacle: NavigationObstacle3D = geometry_node.get_node_or_null("TemporaryNavigationObstacle3D") as NavigationObstacle3D
	if obstacle == null:
		return
	obstacle.avoidance_enabled = false
	obstacle.queue_free()

func _ensure_navigation_obstacle(obstacle_node: Node3D, avoidance_radius: float, avoidance_height: float) -> NavigationObstacle3D:
	var navigation_obstacle: NavigationObstacle3D = obstacle_node.get_node_or_null("TemporaryNavigationObstacle3D") as NavigationObstacle3D
	if navigation_obstacle != null and navigation_obstacle.is_queued_for_deletion():
		# Allow unregister/register in the same frame without reusing a doomed helper.
		obstacle_node.remove_child(navigation_obstacle)
		navigation_obstacle = null
	if navigation_obstacle == null:
		navigation_obstacle = NavigationObstacle3D.new()
		navigation_obstacle.name = "TemporaryNavigationObstacle3D"
		obstacle_node.add_child(navigation_obstacle)
	var bounds: AABB = get_obstacle_world_bounds(obstacle_node, avoidance_radius, avoidance_height)
	# Immediate ground avoidance only. Collider/mesh geometry supplies the bake.
	# Refresh existing helpers as well when a moving/resized blocker re-registers.
	navigation_obstacle.avoidance_enabled = true
	navigation_obstacle.radius = maxf(default_obstacle_radius, Vector2(bounds.size.x, bounds.size.z).length() * 0.5) if avoidance_radius < 0.0 else avoidance_radius
	navigation_obstacle.height = maxf(default_obstacle_height, bounds.size.y) if avoidance_height < 0.0 else avoidance_height
	navigation_obstacle.use_3d_avoidance = false
	navigation_obstacle.avoidance_layers = obstacle_avoidance_layers
	navigation_obstacle.affect_navigation_mesh = false
	navigation_obstacle.global_position = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	return navigation_obstacle

func _schedule_dirty_bake() -> void:
	if not is_inside_tree():
		return
	if _bake_timer != null or _bake_active:
		return

	var delay := maxf(bake_delay_seconds, 0.0)
	_bake_timer = get_tree().create_timer(delay)
	_bake_timer.timeout.connect(_process_dirty_bake_queue, CONNECT_ONE_SHOT)

func _process_dirty_bake_queue() -> void:
	_bake_timer = null
	if _dirty_queue.is_empty() or _bake_active:
		return
	var root: Node3D = get_node_or_null(source_geometry_root_path) as Node3D if source_geometry_root_path != NodePath() else null
	if root == null:
		push_warning("[NAV] Set source_geometry_root_path before requesting runtime bake.")
		return # Keep dirty work for retry after configuration is fixed.

	var coords := _dirty_queue.pop_front() as Vector2i
	var data := _get_chunk_data(coords)
	if data == null:
		_process_dirty_bake_queue()
		return
	if not is_instance_valid(data.region):
		_process_dirty_bake_queue()
		return

	_bake_active = true
	data.baking = true
	data.baking_revision = data.dirty_revision
	data.bake_request_count += 1
	var mesh: NavigationMesh = _new_navigation_mesh()
	_configure_chunk_navigation_mesh(mesh)
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	# SceneTree parsing stays on the main thread. The configured root can be a
	# sibling of regions, and all geometry is converted from root to region local.
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	var local_source: NavigationMeshSourceGeometryData3D = _source_to_region_local(source, root.global_transform, data.region.global_transform)
	_append_registered_solid_blockers(local_source, data.region.global_position, mesh.filter_baking_aabb)
	var generation: int = _generation
	_log("Bake start: %s (revision %d)" % [coords, data.baking_revision])
	chunk_bake_requested.emit(coords, data.region)
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, local_source,
		_finish_chunk_bake_request.bind(coords, generation, mesh))

func _append_registered_solid_blockers(source: NavigationMeshSourceGeometryData3D, region_origin: Vector3, bake_bounds: AABB) -> void:
	for world_bounds: AABB in _solid_blocker_bounds.values():
		var bounds: AABB = AABB(world_bounds.position - region_origin, world_bounds.size)
		if not bounds.intersects(bake_bounds):
			continue
		var start: Vector3 = bounds.position
		var end: Vector3 = bounds.end
		source.add_projected_obstruction(PackedVector3Array([
			Vector3(start.x, 0.0, start.z), Vector3(start.x, 0.0, end.z),
			Vector3(end.x, 0.0, end.z), Vector3(end.x, 0.0, start.z),
		]), start.y, bounds.size.y, false) # false retains agent-radius clearance.

func _source_to_region_local(source: NavigationMeshSourceGeometryData3D, root_transform: Transform3D, region_transform: Transform3D) -> NavigationMeshSourceGeometryData3D:
	var result: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	var transform: Transform3D = region_transform.affine_inverse() * root_transform
	var vertices: PackedFloat32Array = source.get_vertices()
	for index in range(0, vertices.size(), 3):
		var vertex: Vector3 = transform * Vector3(vertices[index], vertices[index + 1], vertices[index + 2])
		vertices[index] = vertex.x
		vertices[index + 1] = vertex.y
		vertices[index + 2] = vertex.z
	result.set_vertices(vertices)
	result.set_indices(source.get_indices())
	# Support projected XZ obstructions from level geometry as well. Ground
	# source roots should not tilt their up axis (same restriction as avoidance).
	for obstruction: Dictionary in source.get_projected_obstructions():
		var outline: PackedFloat32Array = obstruction.vertices
		var points: PackedVector3Array = PackedVector3Array()
		for index in range(0, outline.size(), 3):
			points.append(transform * Vector3(outline[index], obstruction.elevation, outline[index + 2]))
		var elevation: float = (transform * Vector3(0.0, obstruction.elevation, 0.0)).y
		result.add_projected_obstruction(points, elevation,
			absf((transform.basis * Vector3.UP * float(obstruction.height)).y), obstruction.carve)
	return result

func _finish_chunk_bake_request(coords: Vector2i, generation: int, mesh: NavigationMesh) -> void:
	if generation != _generation:
		return # Ignore completions from cleared/reinitialized chunk sets.
	var data := _get_chunk_data(coords)
	if data == null:
		return

	if is_instance_valid(data.region):
		data.region.navigation_mesh = mesh
	data.baking = false
	_bake_active = false
	data.bake_finished_count += 1
	data.dirty = data.dirty_revision != data.baking_revision
	if data.dirty:
		if not _dirty_queue.has(coords):
			_dirty_queue.append(coords)
	else:
		chunk_dirty_changed.emit(coords, false)
	_log("Bake finished: %s (dirty %s)" % [coords, data.dirty])
	chunk_bake_finished.emit(coords, data.region)

	if not _dirty_queue.is_empty():
		_schedule_dirty_bake()

func get_debug_snapshot() -> Dictionary:
	var chunks: Array[Dictionary] = []
	for data: ChunkData in _chunks.values():
		chunks.append({"coords": data.coords, "dirty": data.dirty, "baking": data.baking,
			"walkable": data.walkable, "dirty_revision": data.dirty_revision,
			"baking_revision": data.baking_revision, "bake_request_count": data.bake_request_count,
			"bake_finished_count": data.bake_finished_count})
	return {"chunks": chunks, "queued_count": _dirty_queue.size(), "bake_active": _bake_active,
		"initialized": _initialized, "dynamic_geometry_count": _dynamic_geometry_bounds.size(),
		"solid_blocker_count": _solid_blocker_bounds.size()}

func _log(message: String) -> void:
	if debug_logging:
		print("[NAV] " + message)

func _get_chunk_data(coords: Vector2i) -> ChunkData:
	if not is_chunk_coords_valid(coords):
		return null
	return _chunks.get(_chunk_key(coords), null) as ChunkData

func _chunk_key(coords: Vector2i) -> String:
	return "%d:%d" % [coords.x, coords.y]
