extends StateMachine.State
class_name HoldPositionState

@onready var navigation_agent: NavigationAgent2D = %NavigationAgent

const ID = "HOLD_POSITION_STATE"

func _get_id() -> String:
	return ID

func _activate(data):
	super._activate(data)
	_unit.set_deferred("freeze", true)
	navigation_agent.target_position = global_position

func _deactivate():
	super._deactivate()
	_unit.set_deferred("freeze", false)
