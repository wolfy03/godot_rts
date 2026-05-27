extends StateMachine.State
class_name MoveState

const ID = "MOVE_STATE"

var _attack_move: bool

func _get_id() -> String:
	return ID

func _activate(data: MoveCommandData) -> void:
	super._activate(data)
	if not _is_active:
		return
	
	_attack_move = data.attack_move
	_unit.clear_cover()
		
	var target_cover := _unit.find_nearest_cover_to(data.target_position, 2.0)
	if target_cover != null:
		_deactivate()
		transition_to_state.emit(TakeCoverState.ID, target_cover)
		return
	
	_unit.navigation_agent.target_position = data.target_position
	_unit.last_move_command_data = data
	
	if _attack_move and _unit.attack_nearest_unit_in_range():
		_deactivate()

func _process_state(_delta: float) -> void:
	if _unit.navigation_agent.is_navigation_finished():
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)

func _on_enemy_detection_area_body_entered(body: Node3D) -> void:
	if _is_active and _attack_move:
		_deactivate()
		transition_to_state.emit(ChaseState.ID, body)

class MoveCommandData:
	var target_position: Vector3
	var attack_move: bool
