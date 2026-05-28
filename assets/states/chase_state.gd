extends StateMachine.State
class_name ChaseState

@onready var attack_range_area: Area3D = %AttackRangeArea

const ID = "CHASE_STATE"

var _attack_target: Unit

func _get_id() -> String:
	return ID

func _activate(data) -> void:
	super._activate(data)
	if not _is_active:
		return
	
	_attack_target = data
	
	if _unit.can_attack_unit(_attack_target):
		_attack_current_target()

func _process_state(_delta: float) -> void:
	if not is_instance_valid(_attack_target):
		_deactivate()
		
		if _unit.last_move_command_data:
			transition_to_state.emit(MoveState.ID, _unit.last_move_command_data)
		else:
			transition_to_state.emit(IdleState.ID, null)
		return
	
	if _take_cover_if_available():
		return
	
	if _unit.can_attack_unit(_attack_target):
		_attack_current_target()
		return
	
	var direction_from_target := _unit.global_position - _attack_target.global_position
	direction_from_target.y = 0.0
	if direction_from_target.length_squared() > 0.001:
		direction_from_target = direction_from_target.normalized()
	
	_unit.navigation_agent.target_position = _attack_target.global_position + direction_from_target * maxf(_unit.get_attack_range() * 0.85, 0.1)
	_unit._look_at_ground_position(_attack_target.global_position)

func _attack_current_target() -> void:
	_deactivate()
	_unit.navigation_agent.target_position = _unit.global_position
	transition_to_state.emit(AttackState.ID, _attack_target)

func _take_cover_if_available() -> bool:
	if not _unit.should_prioritize_cover_against(_attack_target):
		return false
	
	var cover := _unit.get_auto_cover()
	if cover == null:
		return false
	
	_deactivate()
	transition_to_state.emit(TakeCoverState.ID, cover)
	return true

func _on_attack_range_area_body_entered(body: Node3D) -> void:
	if _is_active and body == _attack_target:
		if _take_cover_if_available():
			return
		
		_attack_current_target()
