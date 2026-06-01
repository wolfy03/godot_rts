extends RefCounted
class_name UnitMoveOrderCommand

const Utils := preload("res://input/unit_commands/unit_command_utils.gd")

func issue(command_owner: Node,
		   move_command_handle_scene: PackedScene,
		   selected_units: Dictionary,
		   click_position: Vector3,
		   attack_move: bool) -> void:
	if move_command_handle_scene == null:
		return

	Utils.remove_active_command_handles(command_owner, selected_units)

	var handle := move_command_handle_scene.instantiate() as MoveCommandHandle
	if handle == null:
		return

	Utils.clear_hold_position(selected_units)
	handle.move_selected_units(selected_units, click_position, attack_move)
	command_owner.add_child(handle)
