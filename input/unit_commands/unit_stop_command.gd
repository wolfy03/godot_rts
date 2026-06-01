extends RefCounted
class_name UnitStopCommand

const Utils := preload("res://input/unit_commands/unit_command_utils.gd")

func issue(selected_units: Dictionary) -> void:
	for selected_unit in selected_units.values():
		var unit := selected_unit as Unit
		if unit == null or not is_instance_valid(unit):
			continue

		unit.clear_player_command()
		Utils.reset_unit_command_state(unit)
		Utils.stop_unit_movement(unit)
		unit.state_machine.transition_to_state(IdleState.ID, null)
