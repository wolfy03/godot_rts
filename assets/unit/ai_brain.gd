extends Node
class_name AIBrain

const STATE_IDLE := "IDLE_STATE"
const STATE_MOVE := "MOVE_STATE"
const STATE_ATTACK := "ATTACK_STATE"
const STATE_CHASE := "CHASE_STATE"
const STATE_HOLD_POSITION := "HOLD_POSITION_STATE"
const STATE_TAKE_COVER := "TAKE_COVER_STATE"
const STATE_HEAL := "HEAL_STATE"

@export var decision_interval: float = 0.25
@export var medic_heal_search_radius: float = 12.0

var _unit: Unit
var _decision_timer: float = 0.0

func _ready() -> void:
	_unit = owner as Unit
	if _unit == null:
		_unit = get_parent() as Unit
	
	if _unit == null:
		push_error("AIBrain must be owned by Unit or child of Unit.")
		set_process(false)

func _process(delta: float) -> void:
	if _unit == null:
		return
	
	_decision_timer -= delta
	if _decision_timer > 0.0:
		return
	
	_decision_timer = decision_interval
	request_decision()

func request_decision(allow_move_interrupt: bool = false) -> bool:
	if not _can_think():
		return false
	
	var current_state_id := _unit.state_machine.get_current_state_id()
	if current_state_id == STATE_HOLD_POSITION:
		return false
	if current_state_id == STATE_HEAL:
		return false
	if current_state_id == STATE_MOVE and not allow_move_interrupt:
		return false
	
	if _unit.unit_class == Unit.UnitClass.MEDIC:
		var wounded_ally := _unit.get_nearest_wounded_ally(medic_heal_search_radius)
		if wounded_ally != null:
			_issue_heal(wounded_ally)
			return true
	
	return _request_combat_decision(current_state_id, allow_move_interrupt)

func _can_think() -> bool:
	if not is_instance_valid(_unit) or _unit._is_dead:
		return false
	if _unit.state_machine == null:
		return false
	if _unit.blocks_autonomous_ai():
		return false
	
	return true

func _request_combat_decision(current_state_id: String, allow_move_interrupt: bool) -> bool:
	var detected_enemy := _unit.get_nearest_detected_enemy()
	if detected_enemy != null:
		var cover := _get_cover_against(detected_enemy)
		if cover != null and current_state_id != STATE_TAKE_COVER:
			_issue_cover(cover)
			return true
	
	if _unit.try_use_ai_skill():
		return true
	
	if current_state_id == STATE_ATTACK or current_state_id == STATE_CHASE:
		return false
	
	var attackable_target := _unit.get_nearest_attackable_unit_in_range()
	if attackable_target != null:
		_issue_attack(attackable_target)
		return true
	
	if detected_enemy != null and (current_state_id == STATE_IDLE or allow_move_interrupt):
		_issue_chase(detected_enemy)
		return true
	
	if current_state_id == STATE_IDLE:
		var idle_cover := _unit.get_auto_cover()
		if idle_cover != null:
			_issue_cover(idle_cover)
			return true
	
	return false

func _get_cover_against(target: Unit) -> Cover:
	if not _unit.should_prioritize_cover_against(target):
		return null
	
	return _unit.get_auto_cover()

func _issue_heal(target: Unit) -> void:
	_unit.clear_cover()
	_unit.state_machine.transition_to_state(STATE_HEAL, target)

func _issue_attack(target: Unit) -> void:
	_unit.state_machine.transition_to_state(STATE_ATTACK, target)

func _issue_chase(target: Unit) -> void:
	_unit.state_machine.transition_to_state(STATE_CHASE, target)

func _issue_cover(cover: Cover) -> void:
	_unit.state_machine.transition_to_state(STATE_TAKE_COVER, cover)
