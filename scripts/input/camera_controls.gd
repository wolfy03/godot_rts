extends Camera3D
class_name CameraControls

const ACTION_MOVE_LEFT := "Move Camera Left"
const ACTION_MOVE_RIGHT := "Move Camera Right"
const ACTION_MOVE_UP := "Move Camera Up"
const ACTION_MOVE_DOWN := "Move Camera Down"

@export var camera_move_speed: float = 18
@export var mouse_screen_edge_threshold_percentage: float = 0.01
@export var follow_target_path: NodePath
@export var follow_enabled: bool = true
@export var follow_margin: float = 3.0
@export var follow_smooth_speed: float = 6.0
@export var zoom_step: float = 2.0
@export var min_zoom_distance: float = 7.0
@export var max_zoom_distance: float = 28.0
@export var rotation_sensitivity: float = 0.005
@export var min_pitch_degrees: float = 30.0
@export var max_pitch_degrees: float = 75.0

var _keyboard_move_direction: Vector2 = Vector2.ZERO
var _keyboard_camera_controls_enabled: bool = true
var _mouse_edge_camera_controls_enabled: bool = true
var _follow_camera_controls_enabled: bool = true
var _focus_position: Vector3 = Vector3.ZERO
var _zoom_distance: float = 12.0
var _yaw: float = 0.0
var _pitch: float = deg_to_rad(55.0)
var _is_orbit_rotating: bool = false
var _follow_target: Node3D = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	_initialize_orbit_from_current_transform()
	_resolve_follow_target()
	_apply_camera_transform()

func _input(event: InputEvent) -> void:
	_keyboard_move_direction = _get_keyboard_move_direction()
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _is_orbit_rotating:
		rotate_orbit(event.relative)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var move_direction := _keyboard_move_direction
	if _mouse_edge_camera_controls_enabled:
		move_direction += _get_mouse_edge_move_direction()
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()

	_focus_position += _get_world_move_direction(move_direction) * camera_move_speed * delta
	_update_follow_focus(delta)
	_apply_camera_transform()

func adjust_zoom(steps: float) -> void:
	_zoom_distance = clampf(_zoom_distance - steps * zoom_step, min_zoom_distance, max_zoom_distance)
	_apply_camera_transform()

func rotate_orbit(relative_motion: Vector2) -> void:
	_yaw -= relative_motion.x * rotation_sensitivity
	_pitch = clampf(
		_pitch - relative_motion.y * rotation_sensitivity,
		deg_to_rad(min_pitch_degrees),
		deg_to_rad(max_pitch_degrees)
	)
	_apply_camera_transform()

func set_focus_position(focus_position: Vector3) -> void:
	_focus_position = focus_position
	_apply_camera_transform()

func get_focus_position() -> Vector3:
	return _focus_position

func set_zoom_distance(distance: float) -> void:
	_zoom_distance = clampf(distance, min_zoom_distance, max_zoom_distance)
	_apply_camera_transform()

func get_zoom_distance() -> float:
	return _zoom_distance

func set_pitch_degrees(degrees: float) -> void:
	_pitch = clampf(deg_to_rad(degrees), deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	_apply_camera_transform()

func get_pitch_degrees() -> float:
	return rad_to_deg(_pitch)

func get_focus_for_follow_target(current_focus: Vector3, target_position: Vector3) -> Vector3:
	var focus_xz := Vector2(current_focus.x, current_focus.z)
	var target_xz := Vector2(target_position.x, target_position.z)
	var target_offset := target_xz - focus_xz
	var next_focus := Vector3(current_focus.x, target_position.y, current_focus.z)
	if target_offset.length() <= follow_margin:
		return next_focus

	var margin_offset := target_offset.normalized() * follow_margin
	var next_focus_xz := target_xz - margin_offset
	next_focus.x = next_focus_xz.x
	next_focus.z = next_focus_xz.y
	return next_focus

func _get_keyboard_move_direction() -> Vector2:
	if not _keyboard_camera_controls_enabled:
		return Vector2.ZERO

	var direction := Vector2.ZERO

	if Input.is_action_pressed(ACTION_MOVE_LEFT):
		direction.x = -1.0
	elif Input.is_action_pressed(ACTION_MOVE_RIGHT):
		direction.x = 1.0

	if Input.is_action_pressed(ACTION_MOVE_UP):
		direction.y = -1.0
	elif Input.is_action_pressed(ACTION_MOVE_DOWN):
		direction.y = 1.0

	return direction

func set_keyboard_camera_controls_enabled(enabled: bool) -> void:
	_keyboard_camera_controls_enabled = enabled
	if not _keyboard_camera_controls_enabled:
		_keyboard_move_direction = Vector2.ZERO

func set_mouse_edge_camera_controls_enabled(enabled: bool) -> void:
	_mouse_edge_camera_controls_enabled = enabled

func set_follow_camera_controls_enabled(enabled: bool) -> void:
	_follow_camera_controls_enabled = enabled

func _get_mouse_edge_move_direction() -> Vector2:
	var viewport_size: Vector2 = get_viewport().size
	var threshold := viewport_size.x * mouse_screen_edge_threshold_percentage
	var mouse_position := get_viewport().get_mouse_position()

	var direction := Vector2.ZERO

	if mouse_position.x < threshold:
		direction.x = -1.0
	elif mouse_position.x > viewport_size.x - threshold:
		direction.x = 1.0

	if mouse_position.y < threshold:
		direction.y = -1.0
	elif mouse_position.y > viewport_size.y - threshold:
		direction.y = 1.0

	return direction

func _get_world_move_direction(screen_direction: Vector2) -> Vector3:
	if screen_direction == Vector2.ZERO:
		return Vector3.ZERO

	var camera_right := global_transform.basis.x
	var camera_forward := -global_transform.basis.z

	camera_right.y = 0.0
	camera_forward.y = 0.0

	return camera_right.normalized() * screen_direction.x + camera_forward.normalized() * -screen_direction.y

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		adjust_zoom(maxf(1.0, event.factor))
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		adjust_zoom(-maxf(1.0, event.factor))
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		_is_orbit_rotating = event.pressed
		get_viewport().set_input_as_handled()

func _initialize_orbit_from_current_transform() -> void:
	var ground_focus := _get_ground_focus_from_current_view()
	if ground_focus != Vector3.INF:
		_focus_position = ground_focus
	else:
		_focus_position = Vector3(global_position.x, 0.0, global_position.z)

	var offset := global_position - _focus_position
	var distance := offset.length()
	if distance > 0.001:
		_zoom_distance = clampf(distance, min_zoom_distance, max_zoom_distance)
		_yaw = atan2(offset.x, offset.z)
		_pitch = clampf(asin(clampf(offset.y / distance, -1.0, 1.0)), deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))

func _get_ground_focus_from_current_view() -> Vector3:
	var viewport := get_viewport()
	if viewport == null:
		return Vector3.INF

	var viewport_center := Vector2(viewport.size) * 0.5
	var ray_origin := project_ray_origin(viewport_center)
	var ray_direction := project_ray_normal(viewport_center)
	if absf(ray_direction.y) < 0.001:
		return Vector3.INF

	var distance := -ray_origin.y / ray_direction.y
	if distance <= 0.0:
		return Vector3.INF
	return ray_origin + ray_direction * distance

func _resolve_follow_target() -> void:
	_follow_target = null
	if not follow_target_path.is_empty():
		_follow_target = get_node_or_null(follow_target_path) as Node3D
	if _follow_target != null:
		return

	for node in get_tree().get_nodes_in_group("player_agent"):
		var agent := node as Node3D
		if agent != null and is_instance_valid(agent):
			_follow_target = agent
			return

func _update_follow_focus(delta: float) -> void:
	if not follow_enabled or not _follow_camera_controls_enabled:
		return
	if _follow_target == null or not is_instance_valid(_follow_target):
		_resolve_follow_target()
	if _follow_target == null:
		return

	var target_focus := get_focus_for_follow_target(_focus_position, _follow_target.global_position)
	var follow_weight := clampf(follow_smooth_speed * delta, 0.0, 1.0)
	_focus_position = _focus_position.lerp(target_focus, follow_weight)

func _apply_camera_transform() -> void:
	var pitch := clampf(_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	var horizontal_distance := cos(pitch) * _zoom_distance
	var offset := Vector3(
		sin(_yaw) * horizontal_distance,
		sin(pitch) * _zoom_distance,
		cos(_yaw) * horizontal_distance
	)
	global_position = _focus_position + offset
	look_at(_focus_position, Vector3.UP)
