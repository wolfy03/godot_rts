extends RefCounted
class_name UnitHoldPositionCommand

func issue(selected_units: Dictionary) -> void:
	for selected_unit in selected_units.values():
		var unit := selected_unit as Unit
		if unit == null or not is_instance_valid(unit):
			continue

		unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
		unit.last_move_command_data = null
		unit.state_machine.transition_to_state(HoldPositionState.ID, null)
