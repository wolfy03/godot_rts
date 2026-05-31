extends StateMachine.State
class_name IdleState

const ID = "IDLE_STATE"

func _get_id() -> String:
	return ID

func _activate(data) -> void:
	super._activate(data)
	if not _is_active:
		return
	
	if _unit.ai_brain != null:
		_unit.ai_brain.request_decision()

func _on_enemy_detection_area_body_entered(_body: Node3D) -> void:
	if _is_active and _unit.ai_brain != null:
		_unit.ai_brain.request_decision()
