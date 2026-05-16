extends StateMachine.State
class_name MoveState

const ID = "MOVE_STATE"

var _attack_move: bool

func _get_id() -> String:
	return ID

func _activate(data: MoveCommandData):
	super._activate(data)
	_attack_move = data.attack_move
	
	if _unit == null :
		print("unit is null")
	_unit.navigation_agent.target_position = data.target_position
	_unit.last_move_command_data = data
	
	if _attack_move && _unit.attack_nearest_unit_in_range():
		_deactivate()

func _process_state(_delta: float):
	if _unit.navigation_agent.is_navigation_finished():
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)

func _on_enemy_detection_area_body_entered(body: Node3D):
	if _is_active && _attack_move:
		_deactivate()
		transition_to_state.emit(ChaseState.ID, body)

class MoveCommandData:
	var target_position: Vector3
	var attack_move: bool
