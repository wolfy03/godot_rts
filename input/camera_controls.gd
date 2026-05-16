extends Camera3D

@export var camera_move_speed: float = 18
@export var mouse_screen_edge_threshold_percentage: float = 0.01

var _cam_move_direction_keys: Vector2

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED

func _input(_event: InputEvent):
	_cam_move_direction_keys = Vector2.ZERO
	
	if Input.is_action_pressed('Move Camera Left'):
		_cam_move_direction_keys.x = -1
	elif Input.is_action_pressed('Move Camera Right'):
		_cam_move_direction_keys.x = 1

	if Input.is_action_pressed('Move Camera Up'):
		_cam_move_direction_keys.y = -1
	elif Input.is_action_pressed('Move Camera Down'):
		_cam_move_direction_keys.y = 1

func _process(delta: float):
	var view_port_size = get_viewport().size
	var threshold = view_port_size.x * mouse_screen_edge_threshold_percentage
	var mouse_pos = get_viewport().get_mouse_position()
	
	# var half_size = view_port_size / 2
	var cam_move_direction_mouse = Vector2.ZERO
	
	if mouse_pos.x < threshold:
		cam_move_direction_mouse.x -= 1
	elif mouse_pos.x > view_port_size.x - threshold:
		cam_move_direction_mouse.x += 1
	
	if mouse_pos.y < threshold:
		cam_move_direction_mouse.y -= 1
	elif mouse_pos.y > view_port_size.y - threshold:
		cam_move_direction_mouse.y += 1
	
	var move_dir = _cam_move_direction_keys + cam_move_direction_mouse
	if move_dir.length_squared() > 1.0:
		move_dir = move_dir.normalized()
	
	var right := global_transform.basis.x
	var forward := -global_transform.basis.z
	right.y = 0
	forward.y = 0
	right = right.normalized()
	forward = forward.normalized()
	
	global_position += (right * move_dir.x + forward * -move_dir.y) * delta * camera_move_speed
