extends Node2D
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
	var existing_handles: Array[Node] = find_children("", "MoveCommandHandle", true, false)
	
	for active_handle: MoveCommandHandle in existing_handles:
		active_handle.remove_units(_selected_units)
	
	var handle: MoveCommandHandle = move_command_handle_scene.instantiate()
	handle.move_selected_units(_selected_units, get_local_mouse_position(), attack_move)
	add_child(handle)

func _issue_hold_position_command():
	for unit: Unit in _selected_units.values():
		unit.last_move_command_data = null
		unit.state_machine.transition_to_state(HoldPositionState.ID, null)
