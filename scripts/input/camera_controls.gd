extends Camera3D

const ACTION_MOVE_LEFT := "Move Camera Left"
const ACTION_MOVE_RIGHT := "Move Camera Right"
const ACTION_MOVE_UP := "Move Camera Up"
const ACTION_MOVE_DOWN := "Move Camera Down"

@export var camera_move_speed: float = 18
@export var mouse_screen_edge_threshold_percentage: float = 0.01

var _keyboard_move_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED

func _input(_event: InputEvent) -> void:
	_keyboard_move_direction = _get_keyboard_move_direction()

func _process(delta: float) -> void:
	var move_direction := _keyboard_move_direction + _get_mouse_edge_move_direction()
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()

	global_position += _get_world_move_direction(move_direction) * camera_move_speed * delta

func _get_keyboard_move_direction() -> Vector2:
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
	var camera_right := global_transform.basis.x
	var camera_forward := -global_transform.basis.z

	camera_right.y = 0.0
	camera_forward.y = 0.0

	return camera_right.normalized() * screen_direction.x + camera_forward.normalized() * -screen_direction.y
