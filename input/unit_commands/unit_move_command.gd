extends Node
class_name UnitMoveCommand

@export var move_command_handle_scene: PackedScene

var _selected_units: Dictionary = {};

func unit_selection_changed(selected_units: Dictionary):
	_selected_units = selected_units

func _input(_event: InputEvent):
	if _selected_units.is_empty():
		return
	
	if Input.is_action_just_pressed('Unit Move Command'):
		_issue_command(false)
	elif Input.is_action_just_pressed('Unit Attack Command'):
		_issue_command(true)
	elif Input.is_action_just_pressed('Unit Hold Position Command'):
		_issue_hold_position_command()

func _issue_command(attack_move: bool):
	var click_position = _get_ground_mouse_position()
	if click_position == null:
		return
	
	var existing_handles: Array[Node] = find_children("", "MoveCommandHandle", true, false)
	
	for active_handle: MoveCommandHandle in existing_handles:
		active_handle.remove_units(_selected_units)
	
	var handle: MoveCommandHandle = move_command_handle_scene.instantiate()
	handle.move_selected_units(_selected_units, click_position, attack_move)
	add_child(handle)

func _issue_hold_position_command():
	for unit: Unit in _selected_units.values():
		unit.last_move_command_data = null
		unit.state_machine.transition_to_state(HoldPositionState.ID, null)

func _get_ground_mouse_position():
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)
	
	if absf(ray_direction.y) < 0.001:
		return null
	
	var distance := -ray_origin.y / ray_direction.y
	if distance < 0.0:
		return null
	
	return ray_origin + ray_direction * distance
