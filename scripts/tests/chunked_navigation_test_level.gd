extends Node3D
class_name ChunkedNavigationTestLevel

const TILE_COUNT := Vector2i(3, 3)
const CHUNKS_PER_TILE := Vector2i(5, 5)
const CHUNK_SIZE_METERS := 4.0
const TILE_OVERLAP_METERS := 1.0
const TILE_THICKNESS := 0.2
const NAVIGATION_Y := 1.0

@onready var _tiles_root: Node3D = $MapTiles
@onready var _navigation: Variant = $ChunkedNavigation
@onready var _camera: Variant = $Input/Camera
@onready var _unit: Variant = $UnitsContainer/TestAIUnit

func _ready() -> void:
	_build_map_tiles()
	_configure_chunked_navigation()
	_configure_test_unit()
	_configure_camera()

func _build_map_tiles() -> void:
	var tile_stride := _get_tile_stride()
	var tile_visual_size := _get_tile_visual_size()
	var origin_offset := _get_total_navigation_size() * 0.5

	for z in range(TILE_COUNT.y):
		for x in range(TILE_COUNT.x):
			var tile := _create_tile(Vector2i(x, z), tile_visual_size)
			tile.position = Vector3(
				float(x) * tile_stride.x + tile_stride.x * 0.5 - origin_offset.x,
				-TILE_THICKNESS * 0.5,
				float(z) * tile_stride.y + tile_stride.y * 0.5 - origin_offset.y
			)
			_tiles_root.add_child(tile)

func _configure_chunked_navigation() -> void:
	_navigation.auto_initialize = false
	_navigation.map_chunk_count = TILE_COUNT * CHUNKS_PER_TILE
	_navigation.chunk_size = Vector2(CHUNK_SIZE_METERS, CHUNK_SIZE_METERS)
	_navigation.world_origin = Vector3(-_get_total_navigation_size().x * 0.5, NAVIGATION_Y, -_get_total_navigation_size().y * 0.5)
	_navigation.flat_navigation_overlap = 0.0
	_navigation.use_region_edge_connections = true
	_navigation.initialize_chunks()
	_navigation.build_flat_chunk_navigation_meshes(NAVIGATION_Y, _navigation.flat_navigation_overlap, true)
	NavigationServer3D.map_force_update(get_world_3d().navigation_map)

func _configure_test_unit() -> void:
	_unit.global_position = Vector3(0.0, 1.0, 0.0)
	_unit.navigation_agent.avoidance_enabled = false
	_unit.navigation_agent.target_position = _unit.global_position

func _configure_camera() -> void:
	_camera.current = true
	_camera.follow_enabled = false
	_camera.set_focus_position(Vector3.ZERO)
	_camera.set_zoom_distance(42.0)
	_camera.set_pitch_degrees(58.0)

func _create_tile(coords: Vector2i, tile_visual_size: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "MapTile_%d_%d" % [coords.x, coords.y]

	var material := StandardMaterial3D.new()
	material.albedo_color = _get_tile_color(coords)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(tile_visual_size.x, TILE_THICKNESS, tile_visual_size.y)
	mesh.material = material

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	mesh_instance.mesh = mesh
	root.add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)

	var shape := BoxShape3D.new()
	shape.size = Vector3(tile_visual_size.x, TILE_THICKNESS, tile_visual_size.y)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.shape = shape
	body.add_child(collision_shape)

	return root

func _get_tile_color(coords: Vector2i) -> Color:
	var even := (coords.x + coords.y) % 2 == 0
	if even:
		return Color(0.18, 0.36, 0.24, 1.0)
	return Color(0.22, 0.42, 0.28, 1.0)

func _get_tile_stride() -> Vector2:
	return Vector2(
		float(CHUNKS_PER_TILE.x) * CHUNK_SIZE_METERS,
		float(CHUNKS_PER_TILE.y) * CHUNK_SIZE_METERS
	)

func _get_tile_visual_size() -> Vector2:
	var stride := _get_tile_stride()
	return stride + Vector2.ONE * TILE_OVERLAP_METERS

func _get_total_navigation_size() -> Vector2:
	return Vector2(
		float(TILE_COUNT.x * CHUNKS_PER_TILE.x) * CHUNK_SIZE_METERS,
		float(TILE_COUNT.y * CHUNKS_PER_TILE.y) * CHUNK_SIZE_METERS
	)
