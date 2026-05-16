extends StateMachine.State
class_name HoldPositionState

@onready var navigation_agent: NavigationAgent3D = %NavigationAgent

const ID = "HOLD_POSITION_STATE"

func _get_id() -> String:
	return ID

func _activate(data):
	super._activate(data)
	_unit.movement_enabled = false
	navigation_agent.target_position = global_position

func _deactivate():
	super._deactivate()
	if is_instance_valid(_unit):
		_unit.movement_enabled = true
