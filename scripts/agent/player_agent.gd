extends Unit
class_name PlayerAgent

var _agent_control_enabled: bool = false
var _agent_command_locked: bool = false
var _move_direction: Vector3 = Vector3.ZERO
var _aim_position: Vector3 = Vector3.INF
var _fire_requested: bool = false
var _attack_timer: float = 0.0

func _ready() -> void:
	is_agent = true
	is_player_controllable = false
	super._ready()
	add_to_group("player_agent")
	remove_from_group("selectable_units")
	_disable_npc_brain()

func is_player_agent() -> bool:
	return true

func set_agent_control_enabled(enabled: bool) -> void:
	if _agent_control_enabled == enabled:
		return

	_agent_control_enabled = enabled
	if _agent_control_enabled:
		set_agent_command_locked(false)
		_prepare_for_player_control()
	else:
		_stop_agent_motion()

func set_agent_command_locked(locked: bool) -> void:
	_agent_command_locked = locked
	if _agent_command_locked:
		_agent_control_enabled = false
		_prepare_for_player_control()
		_stop_agent_motion()

func set_agent_control_input(move_direction: Vector3, aim_position: Vector3, fire_requested: bool) -> void:
	_move_direction = move_direction
	_move_direction.y = 0.0
	if _move_direction.length_squared() > 1.0:
		_move_direction = _move_direction.normalized()
	_aim_position = aim_position
	_fire_requested = fire_requested

func _physics_process(delta: float) -> void:
	_process_active_effects(delta)
	_process_skill_cooldowns(delta)
	_process_recoil_recovery(delta)
	if status_indicator_space != null and status_indicator_space.visible:
		_update_status_indicator_space_position()

	if _agent_command_locked:
		_stop_agent_motion()
		move_and_slide()
		return

	if _agent_control_enabled:
		_process_agent_control(delta)
		return

	_stop_agent_motion()
	move_and_slide()

func _process_agent_control(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_face_mouse_aim_position()

	var move_speed := navigation_agent.max_speed if navigation_agent != null else _base_navigation_max_speed
	velocity = _move_direction * move_speed
	if navigation_agent != null:
		navigation_agent.velocity = velocity
		navigation_agent.target_position = global_position
	move_and_slide()

	if _fire_requested and _attack_timer <= 0.0:
		if perform_direct_ranged_attack_at(_aim_position):
			_attack_timer = _get_agent_attack_cooldown()

func _face_mouse_aim_position() -> void:
	if _aim_position == Vector3.INF:
		return

	var face_direction := _aim_position - global_position
	face_direction.y = 0.0
	if face_direction.length_squared() < 0.001:
		return

	look_at(global_position + face_direction, Vector3.UP)

func perform_direct_ranged_attack_at(target_position: Vector3) -> bool:
	if equipped_weapon == null or equipped_weapon.projectile_scene == null:
		return false
	if target_position == Vector3.INF:
		return false

	var fire_origin := global_position + Vector3.UP * 0.7
	var fire_direction := target_position - fire_origin
	if fire_direction.length_squared() < 0.001:
		return false

	var attack_data := _create_ranged_attack_data().with_resolved_aim(true)
	if _spawn_weapon_projectiles(fire_origin, fire_direction.normalized(), attack_data) == 0:
		return false
	_apply_weapon_recoil()
	return true

func _get_agent_attack_cooldown() -> float:
	if equipped_weapon != null:
		return equipped_weapon.get_attack_cooldown(equipment_attack_speed_multiplier * _get_effect_attack_speed_multiplier())
	return melee_cooldown

func _prepare_for_player_control() -> void:
	clear_player_command()
	hold_position_enabled = false
	movement_enabled = true
	clear_cover(false)
	if state_machine != null:
		state_machine.stop()
	_disable_npc_brain()

func _stop_agent_motion() -> void:
	_move_direction = Vector3.ZERO
	_fire_requested = false
	velocity = Vector3.ZERO
	if navigation_agent != null:
		navigation_agent.velocity = Vector3.ZERO
		navigation_agent.target_position = global_position

func _disable_npc_brain() -> void:
	if ai_brain != null:
		ai_brain.set_process(false)
		ai_brain.set_physics_process(false)
		if ai_brain.has_method("set_enabled"):
			ai_brain.set_enabled(false)
