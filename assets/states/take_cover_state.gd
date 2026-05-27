extends StateMachine.State
class_name TakeCoverState

const ID = "TAKE_COVER_STATE"

var _cover: Cover
var _cover_position: Vector3

func _get_id() -> String:
	return ID

func _activate(data) -> void:
	super._activate(data)
	if not _is_active:
		return
	
	_unit.movement_enabled = true
	
	_cover = data as Cover
	if _cover == null:
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)
		return
	
	var agent_radius := 0.45
	if _unit.navigation_agent:
		agent_radius = _unit.navigation_agent.radius
	
	_cover_position = _cover.get_cover_position(_unit.global_position, agent_radius)
	_unit.navigation_agent.target_position = _cover_position

func _deactivate() -> void:
	super._deactivate()

func _process_state(_delta: float) -> void:
	if _cover == null:
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)
		return
	
	if _unit.navigation_agent.is_navigation_finished() or _unit.global_position.distance_to(_cover_position) <= 0.75:
		if _unit.current_cover != _cover:
			_unit.current_cover = _cover
			_unit.update_cover_indicator()
			_unit.navigation_agent.target_position = _unit.global_position
		
		var target := _unit.get_nearest_attackable_unit_in_range()
		if target:
			_deactivate()
			transition_to_state.emit(AttackState.ID, target)
			return

func _on_enemy_detection_area_body_entered(body: Node3D) -> void:
	if _is_active and _unit.can_attack_unit(body as Unit):
		_deactivate()
		transition_to_state.emit(AttackState.ID, body)
