extends StateMachine.State
class_name IdleState

const ID = "IDLE_STATE"

func _get_id() -> String:
	return ID

func _activate(data) -> void:
	super._activate(data)
	if not _is_active:
		return
	
	var cover := _unit.get_auto_cover()
	if cover != null:
		_deactivate()
		transition_to_state.emit(TakeCoverState.ID, cover)
		return
	
	if _unit.attack_nearest_unit_in_range():
		_deactivate()
		return

func _on_enemy_detection_area_body_entered(body: Node3D) -> void:
	if _is_active:
		var cover := _unit.get_auto_cover()
		if cover != null:
			_deactivate()
			transition_to_state.emit(TakeCoverState.ID, cover)
			return
		
		_deactivate()
		transition_to_state.emit(ChaseState.ID, body)
