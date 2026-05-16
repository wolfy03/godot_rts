extends StateMachine.State
class_name ChaseState

@onready var attack_range_area: Area2D = %AttackRangeArea

const ID = "CHASE_STATE"

var _attack_target: Unit

func _get_id() -> String:
	return ID

func _activate(data):
	super._activate(data)
	_attack_target = data
	
	if attack_range_area.overlaps_body(_attack_target):
		_deactivate()
		_unit.navigation_agent.target_position = global_position
		transition_to_state.emit(AttackState.ID, _attack_target)

func _process_state(_delta: float):
	if _attack_target == null:
		_deactivate()
		
		if _unit.last_move_command_data:
			transition_to_state.emit(MoveState.ID, _unit.last_move_command_data)
		else:
			transition_to_state.emit(IdleState.ID, null)
		return
	
	_unit.navigation_agent.target_position = _attack_target.global_position
	look_at(_attack_target.global_position)

func _on_attack_range_area_body_entered(body: Node2D):
	if _is_active && body == _attack_target:
		_deactivate()
		_unit.navigation_agent.target_position = global_position
		transition_to_state.emit(AttackState.ID, _attack_target)
