extends RefCounted
class_name UnitCommandUtils

static func remove_active_command_handles(command_owner: Node, selected_units: Dictionary) -> void:
	var active_handles: Array[Node] = command_owner.find_children("", "MoveCommandHandle", true, false)

	for active_handle: MoveCommandHandle in active_handles:
		active_handle.remove_units(selected_units)

static func clear_hold_position(selected_units: Dictionary) -> void:
	for selected_unit in selected_units.values():
		var unit := selected_unit as Unit
		if unit != null and is_instance_valid(unit):
			unit.hold_position_enabled = false
			unit.clear_cover()

static func reset_unit_command_state(unit: Unit) -> void:
	unit.last_move_command_data = null
	unit.hold_position_enabled = false
	unit.clear_cover()

static func stop_unit_movement(unit: Unit) -> void:
	unit.movement_enabled = true
	unit.velocity = Vector3.ZERO
	if unit.navigation_agent == null:
		return

	unit.navigation_agent.velocity = Vector3.ZERO
	unit.navigation_agent.target_position = unit.global_position
