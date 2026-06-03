extends StateMachine.State
class_name HoldPositionState

@onready var navigation_agent: NavigationAgent3D = %NavigationAgent

const ID = "HOLD_POSITION_STATE"

func _get_id() -> String:
	return ID

func _activate(data) -> void:
	super._activate(data)
	if not _is_active:
		return

	_unit.hold_position_enabled = true
	_unit.movement_enabled = false
	navigation_agent.target_position = _unit.global_position
	navigation_agent.velocity = Vector3.ZERO

func _process_state(_delta: float) -> void:
	var target := _unit.get_nearest_attackable_unit_in_range()
	if target == null:
		return

	_deactivate()
	transition_to_state.emit(AttackState.ID, target)

func _deactivate() -> void:
	super._deactivate()
	if is_instance_valid(_unit):
		_unit.movement_enabled = true
