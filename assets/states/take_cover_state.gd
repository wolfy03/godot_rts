extends StateMachine.State
class_name TakeCoverState

const ID = "TAKE_COVER_STATE"

var _cover: Cover
var _cover_position: Vector3
var _cover_slot: Marker3D

func _get_id() -> String:
	return ID

func _activate(data) -> void:
	super._activate(data)
	if not _is_active:
		return
	
	_unit.movement_enabled = true
	
	_cover = data as Cover
	_cover_slot = null
	if _cover == null:
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)
		return
	
	if _unit.current_cover != null and _unit.current_cover != _cover:
		_unit.clear_cover()
	
	_cover_slot = _cover.reserve_slot(_unit)
	if _cover_slot == null:
		_unit.clear_cover()
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)
		return
	
	_cover_position = _cover_slot.global_position
	_unit.navigation_agent.target_position = _cover_position
	
	if _unit.is_in_reserved_cover_slot():
		_unit.occupy_reserved_cover()

func _deactivate() -> void:
	super._deactivate()

func _process_state(_delta: float) -> void:
	if _cover == null:
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)
		return
	
	if _unit.current_cover == null and _unit.reserved_cover == null and _cover_slot != null:
		_cover_slot = null
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)
		return
	
	if _cover_slot == null:
		_cover_slot = _cover.get_reserved_slot(_unit)
		if _cover_slot != null:
			_cover_position = _cover_slot.global_position
		else:
			_deactivate()
			transition_to_state.emit(IdleState.ID, null)
			return
	
	if _unit.navigation_agent.is_navigation_finished() or _unit.is_in_reserved_cover_slot():
		if _unit.current_cover != _cover:
			_unit.occupy_reserved_cover()
		
		var target := _unit.get_nearest_attackable_unit_in_range()
		if target:
			_deactivate()
			transition_to_state.emit(AttackState.ID, target)
			return

func _on_enemy_detection_area_body_entered(body: Node3D) -> void:
	if _is_active and _unit.can_attack_unit(body as Unit):
		_deactivate()
		transition_to_state.emit(AttackState.ID, body)
