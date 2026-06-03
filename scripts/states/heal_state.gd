extends StateMachine.State
class_name HealState

const ID = "HEAL_STATE"

@export var heal_range: float = 3.0
@export var heal_amount: int = 20
@export var heal_cooldown: float = 1.0

var _heal_target: Unit
var _heal_timer: float = 0.0

func _get_id() -> String:
	return ID

func _activate(data) -> void:
	super._activate(data)
	if not _is_active:
		return

	_heal_target = data as Unit
	_heal_timer = 0.0
	_unit.movement_enabled = true

	if not _can_continue_healing():
		_exit()
		return

	_move_or_start_healing()

func _deactivate() -> void:
	super._deactivate()
	if is_instance_valid(_unit):
		_unit.movement_enabled = true

func _process_state(delta: float) -> void:
	if not _can_continue_healing():
		_exit()
		return

	_move_or_start_healing()
	if _unit.get_distance_to_unit(_heal_target) > heal_range:
		return

	_heal_timer -= delta
	_unit._look_at_ground_position(_heal_target.global_position)

	if _heal_timer <= 0.0:
		var healed_amount := _heal_target.heal(heal_amount)
		if healed_amount > 0:
			_unit.grant_skill_experience()
		_heal_timer = heal_cooldown

		if not _can_continue_healing():
			_exit()

func _can_continue_healing() -> bool:
	if not is_instance_valid(_heal_target):
		return false
	if not _unit.can_heal_unit(_heal_target):
		return false

	return true

func _move_or_start_healing() -> void:
	if _unit.get_distance_to_unit(_heal_target) > heal_range:
		_unit.movement_enabled = true
		_unit.navigation_agent.target_position = _heal_target.global_position
		return

	_unit.movement_enabled = false
	_unit.velocity = Vector3.ZERO
	if _unit.navigation_agent:
		_unit.navigation_agent.velocity = Vector3.ZERO
		_unit.navigation_agent.target_position = _unit.global_position

func _exit() -> void:
	_deactivate()

	if _unit.hold_position_enabled:
		transition_to_state.emit(HoldPositionState.ID, null)
	elif _unit.last_move_command_data:
		transition_to_state.emit(MoveState.ID, _unit.last_move_command_data)
	else:
		transition_to_state.emit(IdleState.ID, null)
