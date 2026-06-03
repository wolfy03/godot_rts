extends RefCounted
class_name UnitAttackTargetCommand

const Utils := preload("res://scripts/input/unit_commands/unit_command_utils.gd")

func issue(command_owner: Node, selected_units: Dictionary, target_unit: Unit) -> void:
	if not is_instance_valid(target_unit):
		return

	Utils.remove_active_command_handles(command_owner, selected_units)

	for selected_unit in selected_units.values():
		var unit := selected_unit as Unit
		if unit == null or not is_instance_valid(unit):
			continue

		unit.begin_player_command(Unit.PlayerCommandMode.ATTACK_TARGET)
		Utils.reset_unit_command_state(unit)
		unit.state_machine.transition_to_state(ChaseState.ID, target_unit)
