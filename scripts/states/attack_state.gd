extends StateMachine.State
class_name AttackState

@onready var visual: MeshInstance3D = %UnitMesh

const ID = "ATTACK_STATE"

var _attack_timer: float
var _attack_target: Unit

func _get_id() -> String:
	return ID

func _activate(data) -> void:
	super._activate(data)
	if not _is_active:
		return

	_attack_target = data
	_unit._look_at_ground_position(_attack_target.global_position)
	_unit.movement_enabled = false
	visual.scale = Vector3(1.15, 1.0, 1.15)
	_attack_timer = _unit.get_attack_cooldown_for(_attack_target)

func _deactivate() -> void:
	super._deactivate()
	if is_instance_valid(_unit):
		_unit.movement_enabled = true
	if visual:
		visual.scale = Vector3.ONE

func _process_state(delta: float) -> void:
	if not is_instance_valid(_attack_target) or _attack_target._current_health <= 0:
		_exit()
		return

	# Threat-based cover selection runs at AIBrain's decision interval.

	if not _unit.can_attack_unit(_attack_target):
		_chase_or_hold_current_target()
		return

	_attack_timer -= delta
	_unit._look_at_ground_position(_attack_target.global_position)

	if _attack_timer <= 0:
		if _unit.should_ai_hold_fire_for_recoil():
			return
		_unit.perform_attack(_attack_target)
		_attack_timer = _unit.get_attack_cooldown_for(_attack_target)

		if _attack_target._current_health <= 0:
			_exit()

func _exit() -> void:
	_unit.finish_player_command(Unit.PlayerCommandMode.ATTACK_TARGET)
	_deactivate()

	if _unit.current_cover != null:
		transition_to_state.emit(TakeCoverState.ID, _unit.current_cover)
	elif _unit.hold_position_enabled:
		transition_to_state.emit(HoldPositionState.ID, null)
	elif _unit.last_move_command_data:
		transition_to_state.emit(MoveState.ID, _unit.last_move_command_data)
	else:
		transition_to_state.emit(IdleState.ID, null)

func _chase_or_hold_current_target() -> void:
	_deactivate()
	if _unit.current_cover != null:
		transition_to_state.emit(TakeCoverState.ID, _unit.current_cover)
	elif _unit.hold_position_enabled:
		transition_to_state.emit(HoldPositionState.ID, null)
	else:
		transition_to_state.emit(ChaseState.ID, _attack_target)

func _on_attack_range_area_body_exited(body: Node3D) -> void:
	if _is_active and body == _attack_target and _attack_target._current_health > 0 and not _unit.can_attack_unit(_attack_target):
		_chase_or_hold_current_target()

func _on_attack_leash_range_body_exited(body: Node3D) -> void:
	if body == _attack_target and _attack_target._current_health > 0:
		_exit()
