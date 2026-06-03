extends Control
class_name Minimap

const PLAYER_UNIT_MASK := 0b10
const ENEMY_UNIT_MASK := 0b100
const GROUND_PLANE_Y := 0.0

@export var world_padding: float = 2.0
@export var map_margin: float = 8.0
@export var unit_dot_radius: float = 2.4
@export var cover_dot_radius: float = 2.0
@export var redraw_interval: float = 0.033

@export var panel_color: Color = Color(0.035, 0.045, 0.05, 0.92)
@export var terrain_color: Color = Color(0.1, 0.23, 0.12, 1.0)
@export var border_color: Color = Color(0.5, 0.62, 0.58, 1.0)
@export var cover_color: Color = Color(0.58, 0.58, 0.56, 1.0)
@export var player_color: Color = Color(0.1, 0.62, 1.0, 1.0)
@export var enemy_color: Color = Color(1.0, 0.18, 0.12, 1.0)
@export var camera_view_color: Color = Color(0.95, 1.0, 0.86, 1.0)

var _redraw_timer: Timer
var _cached_ground: CSGBox3D = null
var _cached_world_bounds: Rect2 = Rect2()
var _has_cached_world_bounds: bool = false

func _ready() -> void:
	add_to_group("command_panel_ui")
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_cache_static_world_bounds()
	_setup_redraw_timer()

func _setup_redraw_timer() -> void:
	_redraw_timer = Timer.new()
	_redraw_timer.wait_time = maxf(redraw_interval, 0.001)
	_redraw_timer.timeout.connect(queue_redraw)
	add_child(_redraw_timer)
	_redraw_timer.start()

func _draw() -> void:
	var panel_rect := Rect2(Vector2.ZERO, size)
	var map_rect := panel_rect.grow(-map_margin)
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return
	
	var world_bounds := _get_world_bounds()
	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return
	
	draw_rect(panel_rect, panel_color, true)
	draw_rect(map_rect, terrain_color, true)
	_draw_covers(map_rect, world_bounds)
	_draw_units(map_rect, world_bounds)
	_draw_camera_view(map_rect, world_bounds)
	draw_rect(map_rect, border_color, false, 2.0)

func _draw_covers(map_rect: Rect2, world_bounds: Rect2) -> void:
	for node in get_tree().get_nodes_in_group("covers"):
		var cover := node as Cover
		if cover == null:
			continue
		
		var point := _world_to_map(cover.global_position, map_rect, world_bounds)
		draw_circle(point, cover_dot_radius, cover_color)

func _draw_units(map_rect: Rect2, world_bounds: Rect2) -> void:
	for unit in _get_units():
		var point := _world_to_map(unit.global_position, map_rect, world_bounds)
		var color := player_color
		if unit.collision_layer & ENEMY_UNIT_MASK:
			color = enemy_color
		elif unit.collision_layer & PLAYER_UNIT_MASK:
			color = player_color
		
		draw_circle(point, unit_dot_radius, color)

func _draw_camera_view(map_rect: Rect2, world_bounds: Rect2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_corners := [
		Vector2.ZERO,
		Vector2(viewport_size.x, 0.0),
		viewport_size,
		Vector2(0.0, viewport_size.y),
	]
	
	var points: PackedVector2Array = []
	for screen_corner in screen_corners:
		var ground_position = _screen_to_ground(camera, screen_corner)
		if ground_position == null:
			return
		
		points.append(_world_to_map(ground_position, map_rect, world_bounds))
	
	if points.size() < 4:
		return
	
	for index in points.size():
		draw_line(points[index], points[(index + 1) % points.size()], camera_view_color, 1.6)

func _get_world_bounds() -> Rect2:
	if _has_cached_world_bounds:
		return _cached_world_bounds
	
	return _get_content_bounds().grow(world_padding)

func _cache_static_world_bounds() -> void:
	_cached_ground = get_tree().current_scene.find_child("Ground", true, false) as CSGBox3D
	if _cached_ground == null:
		return
	
	_cached_world_bounds = _get_ground_bounds(_cached_ground).grow(world_padding)
	_has_cached_world_bounds = true

func _get_ground_bounds(ground: CSGBox3D) -> Rect2:
	var half_size := ground.size * 0.5
	var corners := [
		Vector3(-half_size.x, 0.0, -half_size.z),
		Vector3(half_size.x, 0.0, -half_size.z),
		Vector3(half_size.x, 0.0, half_size.z),
		Vector3(-half_size.x, 0.0, half_size.z),
	]
	
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for corner in corners:
		var world_corner: Vector3 = ground.global_transform * corner
		min_x = minf(min_x, world_corner.x)
		max_x = maxf(max_x, world_corner.x)
		min_z = minf(min_z, world_corner.z)
		max_z = maxf(max_z, world_corner.z)
	
	return Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))

func _get_content_bounds() -> Rect2:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var has_position := false
	
	for unit in _get_units():
		min_x = minf(min_x, unit.global_position.x)
		max_x = maxf(max_x, unit.global_position.x)
		min_z = minf(min_z, unit.global_position.z)
		max_z = maxf(max_z, unit.global_position.z)
		has_position = true
	
	for node in get_tree().get_nodes_in_group("covers"):
		var cover := node as Cover
		if cover == null:
			continue
		
		min_x = minf(min_x, cover.global_position.x)
		max_x = maxf(max_x, cover.global_position.x)
		min_z = minf(min_z, cover.global_position.z)
		max_z = maxf(max_z, cover.global_position.z)
		has_position = true
	
	if not has_position:
		return Rect2(Vector2(-10.0, -10.0), Vector2(20.0, 20.0))
	
	return Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))

func _get_units() -> Array[Unit]:
	var units: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null:
			continue

		units.append(unit)
	
	return units

func _world_to_map(world_position: Vector3, map_rect: Rect2, world_bounds: Rect2) -> Vector2:
	var normalized_x := inverse_lerp(world_bounds.position.x, world_bounds.end.x, world_position.x)
	var normalized_z := inverse_lerp(world_bounds.position.y, world_bounds.end.y, world_position.z)
	return Vector2(
		map_rect.position.x + normalized_x * map_rect.size.x,
		map_rect.position.y + normalized_z * map_rect.size.y
	)

func _screen_to_ground(camera: Camera3D, screen_position: Vector2) -> Variant:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if is_zero_approx(ray_direction.y):
		return null
	
	var distance := (GROUND_PLANE_Y - ray_origin.y) / ray_direction.y
	if distance < 0.0:
		return null
	
	return ray_origin + ray_direction * distance
