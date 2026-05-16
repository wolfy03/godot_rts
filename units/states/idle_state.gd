extends StateMachine.State
class_name IdleState

const ID = "IDLE_STATE"

func _get_id() -> String:
	return ID

func _activate(data):
	super._activate(data)
	
	if _unit.attack_nearest_unit_in_range():
		_deactivate()

func _on_enemy_detection_area_body_entered(body: Node3D):
	if _is_active:
		_deactivate()
		transition_to_state.emit(ChaseState.ID, body)
