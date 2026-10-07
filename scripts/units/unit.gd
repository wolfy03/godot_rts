extends CharacterBody3D
class_name Unit

const COVER_HIGH_EFFECT := preload("res://assets/effects/cover_high_buff.tres")
const COVER_MEDIUM_EFFECT := preload("res://assets/effects/cover_medium_buff.tres")
const COVER_LOW_EFFECT := preload("res://assets/effects/cover_low_buff.tres")
const COVER_EFFECT_IDS := [
	&"cover_high_buff",
	&"cover_medium_buff",
	&"cover_low_buff",
]
const RIFLEMAN_SKILL := preload("res://assets/skills/grenade_throw.tres")
const MEDIC_SKILL := preload("res://assets/skills/stimulant_injection.tres")
const MACHINE_GUNNER_SKILL := preload("res://assets/skills/incendiary_round.tres")
const SNIPER_SKILL := preload("res://assets/skills/weak_point_shot.tres")
const GameTeamData := preload("res://scripts/team/game_team.gd")
const UnitEffectManagerScript := preload("res://scripts/effects/unit_effect_manager.gd")
const SceneObjectPoolScript := preload("res://scripts/pooling/scene_object_pool.gd")
const PLAYER_UNIT_MASK := 0b10
const ENEMY_UNIT_MASK := 0b100
const AIM_POINT_WEIGHTS := {
	&"Head": 0.2,
	&"Chest": 0.2,
	&"Stomach": 0.2,
	&"LeftArm": 0.1,
	&"RightArm": 0.1,
	&"LeftLeg": 0.1,
	&"RightLeg": 0.1,
}
const MUZZLE_HEIGHT := 0.7
const OVERHEAD_HEALTH_BAR_TEXTURE_SIZE := Vector2i(64, 8)

enum UnitClass {
	RIFLEMAN,
	MEDIC,
	MACHINE_GUNNER,
	SNIPER,
}

enum PlayerCommandMode {
	NONE,
	MOVE,
	ATTACK_MOVE,
	ATTACK_TARGET,
	SKILL,
	HOLD_POSITION,
}

signal health_changed(current_health: int, max_health: int)
signal effects_changed
signal veterancy_changed(veterancy: int, experience: int, next_required_experience: int)
signal agent_level_changed(agent_level: int, agent_experience: int, next_required_experience: int)
signal skills_changed

@onready var navigation_agent: NavigationAgent3D = %NavigationAgent
@onready var unit_selected_sprite: Node3D = %UnitSelectedSprite
@onready var state_machine: StateMachine = %StateMachine
@onready var ai_brain = %AIBrain
@onready var attack_range_area: Area3D = %AttackRangeArea
@onready var attack_leash_range_area: Area3D = %AttackLeashRangeArea
@onready var enemy_detection_area: Area3D = %EnemyDetectionArea
@onready var status_indicator_space: Node3D = %StatusIndicatorSpace
@onready var cover_indicator: Sprite3D = %CoverIndicator

@export var unit_class: UnitClass = UnitClass.RIFLEMAN
@export var team_id: int = GameTeamData.AUTO
@export var is_agent: bool = false
@export var is_player_controllable: bool = false
@export var experience_per_veterancy_rank: int = 100
@export var agent_experience_per_level: int = 100
@export var max_agent_level: int = 10
@export var skill_experience_reward: int = 10
@export var max_health: int = 100
@export var defense: int = 0
@export_range(0.0, 1.0, 0.01) var ranged_accuracy: float = 0.5
@export_range(0.0, 1.0, 0.01) var melee_accuracy: float = 1.0
@export_range(0.0, 1.0, 0.01) var evasion_chance: float = 0.0
@export var recoil_control: float = 1.0
@export_file("*.png") var portrait_image_path: String = "res://assets/unit/portraits/infantry_portrait.png"
@export var melee_range: float = 3.0
@export var melee_damage: int = 40
@export var melee_cooldown: float = 1.0
@export var ranged_field_of_view_degrees: float = 90.0
@export var ranged_max_spread_radius: float = 1.8
@export_flags_3d_physics var ranged_aim_obstacle_mask: int = 1
@export var equipment: Array[Equipment] = []
@export var equipped_weapon: WeaponEquipment
@export var common_skills: Array[UnitSkill] = []
@export var extra_skills: Array[UnitSkill] = []
@export var status_indicator_right_offset: float = 0.42
@export var status_indicator_up_offset: float = 1.08
@export var status_indicator_slot_spacing: float = 0.14
@export var status_indicator_icon_pixel_size: float = 0.0001
@export var overhead_health_bar_up_offset: float = 1.18
@export var overhead_health_bar_pixel_size: float = 0.001
@export var overhead_health_bar_width_scale: float = 0.72
@export var cover_slot_hold_radius: float = 0.65
@export var auto_cover_search_radius: float = 5.0
@export var base_vision_extra_range: float = 2.0

var last_move_command_data: MoveState.MoveCommandData
var movement_enabled: bool = true
var hold_position_enabled: bool = false
var equipment_attack_damage_bonus: int = 0
var equipment_attack_range_bonus: float = 0.0
var equipment_attack_speed_multiplier: float = 1.0
var equipment_accuracy_bonus: float = 0.0
var equipment_evasion_bonus: float = 0.0
var current_recoil_degrees: float = 0.0
var _ai_recoil_recovering: bool = false

var veterancy: int = 0
var experience: int = 0
var agent_level: int = 1
var agent_experience: int = 0
var _current_health: int
var _is_dead: bool = false
var _base_navigation_max_speed: float = 0.0
var _portrait_texture: Texture2D = null
var _effect_manager := UnitEffectManagerScript.new()
var _cover_effect_instance_id: int = 0
var _effect_indicator_sprites: Dictionary = {}
var _overhead_health_bar_space: Node3D
var _overhead_health_bar_sprite: Sprite3D
var _overhead_health_bar_percent: float = 1.0
var _skills: Array[UnitSkill] = []
var _skill_cooldowns: Dictionary = {}
var _toggled_skill_ids: Dictionary = {}
var _manual_toggle_skill_ids: Dictionary = {}
var _passive_skill_effect_instances: Dictionary = {}
var _player_command_mode: PlayerCommandMode = PlayerCommandMode.NONE
var _queued_skill_id: StringName = &""
var _queued_skill_target_position: Vector3 = Vector3.INF
var _queued_skill_target_ref: WeakRef
var reserved_cover: Cover = null
var reserved_cover_slot: Marker3D = null
var current_cover: Cover = null
var reserved_cover_candidate: CoverCandidate = null
var current_cover_candidate: CoverCandidate = null
## Remember the acquiring backend, so clear/death/command cancellation never
## release against a replacement service or perform a new SceneTree lookup.
var _runtime_cover_system_ref: WeakRef = null

func _ready():
	add_to_group("units")
	add_to_group(GameTeamData.get_group_name(get_team_id()))
	if is_player_controllable or (get_team_id() == GameTeamData.PLAYER and not is_player_agent()):
		add_to_group("selectable_units")
	navigation_agent.velocity_computed.connect(_on_nav_velocity_computed)
	_apply_equipment()
	_base_navigation_max_speed = navigation_agent.max_speed
	_build_skill_loadout()
	_sync_combat_ranges()
	_current_health = get_max_health()
	_apply_passive_skills()
	_emit_health_changed()
	_emit_veterancy_changed()
	_emit_agent_level_changed()
	_setup_status_indicator_space()
	_setup_overhead_health_bar()

func on_selection_changed(selected: bool):
	unit_selected_sprite.visible = selected

func attack_nearest_unit_in_range() -> Unit:
	if enemy_detection_area == null:
		return null

	var enemies: Array[Unit] = []
	for body in enemy_detection_area.get_overlapping_bodies():
		var detected_enemy := body as Unit
		if detected_enemy != null and is_enemy_unit(detected_enemy):
			enemies.append(detected_enemy)

	if enemies.is_empty():
		return null

	enemies.sort_custom(_sort_nearest)

	var enemy: Unit = enemies[0]
	state_machine.transition_to_state(ChaseState.ID, enemy)
	return enemy

func get_nearest_attackable_unit_in_range() -> Unit:
	if attack_range_area == null:
		return null

	var nearest_target: Unit = null
	var nearest_distance := INF

	for body in attack_range_area.get_overlapping_bodies():
		var target := body as Unit
		if target == null or not can_attack_unit(target):
			continue

		var distance := get_distance_to_unit(target)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_target = target

	return nearest_target

func get_nearest_detected_enemy() -> Unit:
	if enemy_detection_area == null:
		return null

	var nearest_target: Unit = null
	var nearest_distance := INF

	for body in enemy_detection_area.get_overlapping_bodies():
		var target := body as Unit
		if target == null or not is_enemy_unit(target):
			continue

		var distance := get_distance_to_unit(target)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_target = target

	return nearest_target

func get_nearest_wounded_ally(radius: float, include_self: bool = false) -> Unit:
	var nearest_ally: Unit = null
	var nearest_distance := radius

	for node in get_tree().get_nodes_in_group("units"):
		var ally := node as Unit
		if ally == null or not is_instance_valid(ally):
			continue
		if ally == self and not include_self:
			continue
		if not can_heal_unit(ally):
			continue

		var distance := get_distance_to_unit(ally)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_ally = ally

	return nearest_ally

func get_max_health() -> int:
	return maxi(1, max_health + _get_effect_max_health_bonus())

func get_current_health() -> int:
	return _current_health

func get_team_id() -> int:
	if team_id != GameTeamData.AUTO:
		return team_id
	if collision_layer & PLAYER_UNIT_MASK:
		return GameTeamData.PLAYER
	if collision_layer & ENEMY_UNIT_MASK:
		return GameTeamData.ENEMY
	return GameTeamData.NEUTRAL

func get_team_mask() -> int:
	var team_mask := GameTeamData.get_collision_mask(get_team_id())
	if team_mask != 0:
		return team_mask
	return int(collision_layer)

func is_agent_unit() -> bool:
	return is_agent

func is_player_agent() -> bool:
	return false

func is_ally_unit(other: Unit) -> bool:
	if not is_instance_valid(other) or other._is_dead:
		return false

	var current_team_id := get_team_id()
	return current_team_id != GameTeamData.NEUTRAL and current_team_id == other.get_team_id()

func is_enemy_unit(other: Unit) -> bool:
	if not is_instance_valid(other) or other._is_dead:
		return false

	var current_team_id := get_team_id()
	var other_team_id := other.get_team_id()
	return current_team_id != GameTeamData.NEUTRAL and other_team_id != GameTeamData.NEUTRAL and current_team_id != other_team_id

func can_heal_unit(target: Unit) -> bool:
	if unit_class != UnitClass.MEDIC:
		return false
	if not is_ally_unit(target):
		return false

	return target.get_current_health() < target.get_max_health()

func get_defense() -> int:
	return defense

func get_unit_class_name() -> String:
	match unit_class:
		UnitClass.RIFLEMAN:
			return "소총수"
		UnitClass.MEDIC:
			return "의무병"
		UnitClass.MACHINE_GUNNER:
			return "기관총사수"
		UnitClass.SNIPER:
			return "저격수"
		_:
			return "소총수"

func get_veterancy_name() -> String:
	match veterancy:
		0:
			return "징집됨"
		1:
			return "신병"
		2:
			return "훈련됨"
		3:
			return "단련됨"
		4:
			return "정예"
		5:
			return "베테랑"
		_:
			return "징집됨"

func get_next_veterancy_experience() -> int:
	if veterancy >= 5:
		return 5 * experience_per_veterancy_rank

	return (veterancy + 1) * experience_per_veterancy_rank

func get_next_agent_level_experience() -> int:
	if agent_level >= max_agent_level:
		return max_agent_level * agent_experience_per_level

	return agent_level * agent_experience_per_level

func gain_experience(amount: int) -> void:
	if amount <= 0 or _is_dead:
		return

	experience += amount
	if is_agent:
		_gain_agent_experience(amount)
	var previous_veterancy := veterancy
	veterancy = clampi(floori(float(experience) / float(maxi(1, experience_per_veterancy_rank))), 0, 5)
	if veterancy != previous_veterancy:
		_emit_veterancy_changed()
		return

	_emit_veterancy_changed()

func _gain_agent_experience(amount: int) -> void:
	agent_experience += amount
	var previous_agent_level := agent_level
	agent_level = clampi(floori(float(agent_experience) / float(maxi(1, agent_experience_per_level))) + 1, 1, maxi(1, max_agent_level))
	if agent_level != previous_agent_level:
		_emit_agent_level_changed()
		return

	_emit_agent_level_changed()

func grant_skill_experience(amount: int = -1) -> void:
	var reward := skill_experience_reward if amount < 0 else amount
	gain_experience(reward)

func get_skills() -> Array[UnitSkill]:
	return _skills.duplicate()

func get_active_skills() -> Array[UnitSkill]:
	var active_skills: Array[UnitSkill] = []
	for skill in _skills:
		if skill != null and skill.is_active():
			active_skills.append(skill)
	return active_skills

func get_skill(skill_id: StringName) -> UnitSkill:
	for skill in _skills:
		if skill != null and skill.id == skill_id:
			return skill
	return null

func has_skill(skill_id: StringName) -> bool:
	return get_skill(skill_id) != null

func get_skill_cooldown_remaining(skill_id: StringName) -> float:
	return float(_skill_cooldowns.get(skill_id, 0.0))

func can_use_skill(skill_id: StringName, target_unit: Unit = null, target_position: Vector3 = Vector3.INF) -> bool:
	var skill := get_skill(skill_id)
	if skill == null or not skill.is_active():
		return false
	if get_skill_cooldown_remaining(skill_id) > 0.0:
		return false
	return skill.can_activate(self, target_unit, target_position)

func use_skill(skill_id: StringName, target_unit: Unit = null, target_position: Vector3 = Vector3.INF) -> bool:
	var skill := get_skill(skill_id)
	if skill == null or not skill.is_active():
		return false
	if skill.is_toggle():
		toggle_skill(skill_id)
		return true
	if get_skill_cooldown_remaining(skill.id) > 0.0:
		return false
	if not skill.activate(self, target_unit, target_position):
		return false

	_skill_cooldowns[skill.id] = skill.cooldown
	skills_changed.emit()
	return true

func toggle_skill(skill_id: StringName) -> void:
	var skill := get_skill(skill_id)
	if skill == null or not skill.is_toggle():
		return
	if _toggled_skill_ids.has(skill_id):
		_toggled_skill_ids.erase(skill_id)
	else:
		_toggled_skill_ids[skill_id] = true
	if _player_command_mode == PlayerCommandMode.SKILL:
		_manual_toggle_skill_ids[skill_id] = true
	skills_changed.emit()

func is_skill_toggled(skill_id: StringName) -> bool:
	return _toggled_skill_ids.has(skill_id)

func issue_skill_command(skill_id: StringName, target_unit: Unit = null, target_position: Vector3 = Vector3.INF) -> bool:
	var skill := get_skill(skill_id)
	if skill == null or not skill.is_active():
		return false
	if target_position == Vector3.INF and target_unit != null:
		target_position = target_unit.global_position
	if target_position == Vector3.INF:
		target_position = global_position
	if can_use_skill(skill_id, target_unit, target_position):
		return use_skill(skill_id, target_unit, target_position)

	if skill.target_type != UnitSkill.TargetType.POSITION:
		return false

	_queue_position_skill(skill_id, target_unit, target_position)
	return true

func begin_player_command(command_mode: PlayerCommandMode) -> void:
	if command_mode != PlayerCommandMode.NONE and reserved_cover_candidate != null:
		clear_cover()
	_player_command_mode = command_mode

func finish_player_command(command_mode: PlayerCommandMode) -> void:
	if _player_command_mode == command_mode:
		_player_command_mode = PlayerCommandMode.NONE

func clear_player_command() -> void:
	_player_command_mode = PlayerCommandMode.NONE

func blocks_autonomous_ai() -> bool:
	return _player_command_mode != PlayerCommandMode.NONE and _player_command_mode != PlayerCommandMode.ATTACK_MOVE

func blocks_auto_cover() -> bool:
	return _player_command_mode != PlayerCommandMode.NONE and _player_command_mode != PlayerCommandMode.ATTACK_MOVE

func _queue_position_skill(skill_id: StringName, target_unit: Unit, target_position: Vector3) -> void:
	var skill := get_skill(skill_id)
	if skill == null:
		return

	_queued_skill_id = skill_id
	_queued_skill_target_position = target_position
	_queued_skill_target_ref = weakref(target_unit) if target_unit != null else null
	clear_cover()
	_move_to_skill_cast_position(target_position, skill.cast_range)

func _move_to_skill_cast_position(target_position: Vector3, cast_range: float) -> void:
	var cast_position := _get_skill_cast_position(target_position, cast_range)

	var move_data := MoveState.MoveCommandData.new()
	move_data.target_position = cast_position
	move_data.attack_move = false
	last_move_command_data = move_data
	if state_machine != null:
		state_machine.transition_to_state(MoveState.ID, move_data)
	elif navigation_agent != null:
		navigation_agent.target_position = cast_position

func try_use_ai_skill() -> bool:
	for skill in get_active_skills():
		if get_skill_cooldown_remaining(skill.id) > 0.0:
			continue
		if skill.is_toggle():
			if _manual_toggle_skill_ids.has(skill.id):
				continue
			if not is_skill_toggled(skill.id):
				use_skill(skill.id, self, global_position)
				return true
			continue

		match skill.target_type:
			UnitSkill.TargetType.ALLY_UNIT:
				var ally := get_nearest_wounded_ally(skill.cast_range, true)
				if ally != null and use_skill(skill.id, ally, ally.global_position):
					return true
			UnitSkill.TargetType.ENEMY_UNIT:
				var enemy := get_nearest_detected_enemy()
				if enemy != null and use_skill(skill.id, enemy, enemy.global_position):
					return true
			UnitSkill.TargetType.POSITION:
				var target := get_nearest_detected_enemy()
				if target != null and use_skill(skill.id, target, target.global_position):
					return true
			UnitSkill.TargetType.SELF, UnitSkill.TargetType.NONE:
				if use_skill(skill.id, self, global_position):
					return true

	return false

func get_accuracy(is_melee: bool = false) -> float:
	var base_accuracy := melee_accuracy if is_melee else ranged_accuracy
	return clampf(base_accuracy + equipment_accuracy_bonus, 0.0, 1.0)

func get_evasion_chance() -> float:
	var total_evasion := evasion_chance + equipment_evasion_bonus
	return clampf(total_evasion, 0.0, 1.0)

func get_portrait_texture() -> Texture2D:
	if _portrait_texture != null:
		return _portrait_texture

	if portrait_image_path.is_empty():
		return null

	var texture := load(portrait_image_path) as Texture2D
	if texture != null:
		_portrait_texture = texture
		return _portrait_texture

	var image := Image.new()
	if image.load(portrait_image_path) != OK:
		return null

	_portrait_texture = ImageTexture.create_from_image(image)
	return _portrait_texture

func can_attack_unit(target: Unit) -> bool:
	if not is_instance_valid(target) or target._is_dead:
		return false
	if not is_enemy_unit(target):
		return false
	if equipped_weapon != null and not _is_target_in_attack_area(target):
		return false

	return get_distance_to_unit(target) <= get_attack_range()

func _is_target_in_attack_area(target: Unit) -> bool:
	if attack_range_area == null:
		return true
	return attack_range_area.get_overlapping_bodies().has(target)

func get_attack_range() -> float:
	var melee_attack_range := get_melee_range()
	if equipped_weapon:
		var ranged_bonus := equipment_attack_range_bonus + _get_effect_ranged_range_bonus() + _get_effect_attack_range_bonus()
		return maxf(melee_attack_range, equipped_weapon.get_attack_range(ranged_bonus))

	return melee_attack_range

func get_melee_range() -> float:
	return maxf(0.0, melee_range + _get_effect_melee_range_bonus() + _get_effect_attack_range_bonus())

func get_distance_to_unit(target: Unit) -> float:
	var from = Vector3(global_position.x, 0.0, global_position.z)
	var to = Vector3(target.global_position.x, 0.0, target.global_position.z)
	return from.distance_to(to)

func get_attack_cooldown_for(target: Unit) -> float:
	if _should_melee_attack(target):
		return melee_cooldown

	if equipped_weapon:
		return equipped_weapon.get_attack_cooldown(equipment_attack_speed_multiplier * _get_effect_attack_speed_multiplier())

	return melee_cooldown

func get_melee_damage() -> int:
	return maxi(0, melee_damage + _get_effect_attack_damage_bonus() + _get_effect_melee_damage_bonus())

func get_ranged_damage() -> int:
	if equipped_weapon == null:
		return 0

	return maxi(0, equipped_weapon.get_damage(equipment_attack_damage_bonus + _get_effect_attack_damage_bonus() + _get_effect_ranged_damage_bonus() + _get_toggled_ranged_damage_bonus()))

func perform_attack(target: Unit) -> void:
	if not is_instance_valid(target) or target._is_dead:
		return

	if _should_melee_attack(target):
		target.receive_attack(_create_melee_attack_data())
		return

	if equipped_weapon:
		_fire_projectile(target, _create_ranged_attack_data())

func _should_melee_attack(target: Unit) -> bool:
	return get_distance_to_unit(target) <= get_melee_range()

func should_prioritize_cover_against(target: Unit) -> bool:
	if blocks_auto_cover():
		return false
	if not should_auto_take_cover():
		return false
	if not is_instance_valid(target) or target._is_dead:
		return false
	if equipped_weapon == null:
		return false

	return get_distance_to_unit(target) > melee_range

func _fire_projectile(target: Unit, attack_data: AttackData) -> void:
	var aim_solution := _build_ranged_aim_solution(target)
	if aim_solution == null:
		return

	var resolved_attack_data := attack_data.with_resolved_aim(true)
	if equipped_weapon.projectile_scene == null:
		if aim_solution.hit_quality >= 1.0:
			target.receive_projectile_impact(resolved_attack_data)
		return

	var muzzle_position := get_muzzle_position()
	var projectile_direction := aim_solution.impact_position - muzzle_position
	if projectile_direction.length_squared() < 0.001:
		return

	var fired_count := _spawn_weapon_projectiles(muzzle_position, projectile_direction.normalized(), resolved_attack_data)
	if fired_count == 0 and aim_solution.hit_quality >= 1.0:
		target.receive_projectile_impact(resolved_attack_data)
	_apply_weapon_recoil()

func _build_ranged_aim_solution(target: Unit) -> RangedAimSolution:
	if not is_instance_valid(target) or target._is_dead:
		return null
	if not _is_target_in_ranged_field_of_view(target):
		return null

	var visible_points := _get_visible_aim_points(target)
	if visible_points.is_empty():
		return null

	var hit_quality := 0.0
	for point_data in visible_points:
		hit_quality += float(point_data.weight)
	hit_quality = clampf(hit_quality, 0.0, 1.0)

	var selected_point := _pick_weighted_aim_point(visible_points)
	var spread_radius := ranged_max_spread_radius * (1.0 - hit_quality)
	var impact_position := selected_point.position
	if spread_radius > 0.001:
		impact_position += _get_random_spread_offset(spread_radius)

	return RangedAimSolution.new(hit_quality, impact_position)

func _is_target_in_ranged_field_of_view(target: Unit) -> bool:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		return true

	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return true

	var half_angle := deg_to_rad(maxf(0.0, ranged_field_of_view_degrees) * 0.5)
	var required_dot := cos(half_angle)
	return forward.normalized().dot(to_target.normalized()) >= required_dot

func _get_visible_aim_points(target: Unit) -> Array[AimPointData]:
	var visible_points: Array[AimPointData] = []
	var muzzle_position := get_muzzle_position()
	for marker in target.get_aim_points():
		var point_name := StringName(marker.name)
		var weight: float = target.get_aim_point_weight(point_name)
		if weight <= 0.0:
			continue
		if _has_clear_ranged_aim_to(muzzle_position, marker.global_position, target):
			visible_points.append(AimPointData.new(marker.global_position, weight))
	return visible_points

func get_aim_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	var aim_points_parent := get_node_or_null("AimPoints")
	if aim_points_parent == null:
		return points
	for child in aim_points_parent.get_children():
		var marker := child as Marker3D
		if marker != null:
			points.append(marker)
	return points

func get_muzzle_position() -> Vector3:
	return global_position + Vector3.UP * MUZZLE_HEIGHT

## Single weight definition shared by ranged attacks and tactical evaluation.
func get_aim_point_weight(point_name: StringName) -> float:
	return float(AIM_POINT_WEIGHTS.get(point_name, 0.0))

func _spawn_weapon_projectiles(muzzle_position: Vector3, base_direction: Vector3, attack_data: AttackData) -> int:
	if equipped_weapon == null or equipped_weapon.projectile_scene == null:
		return 0

	var pellet_count := maxi(1, equipped_weapon.pellet_count)
	var fired_count := 0
	for pellet_index in pellet_count:
		var projectile := SceneObjectPoolScript.acquire_default(
			self,
			equipped_weapon.projectile_scene,
			get_tree().current_scene
		) as Projectile
		if projectile == null:
			continue
		projectile.global_position = muzzle_position
		var pellet_spread := equipped_weapon.pellet_spread_angle_degrees if pellet_count > 1 else 0.0
		projectile.setup_direction(attack_data, get_weapon_spread_direction(base_direction, pellet_spread))
		fired_count += 1
	return fired_count

func _has_clear_ranged_aim_to(from: Vector3, to: Vector3, target: Unit) -> bool:
	return has_clear_ranged_aim_to(from, to, target)

## Geometry visibility only, also usable from a virtual firing origin.
## Both real units are excluded, including the target's current body when its
## virtual AimPoints are elsewhere. Range/FOV/spread remain attack concerns.
func has_clear_ranged_aim_to(from: Vector3, to: Vector3, target: Unit) -> bool:
	if ranged_aim_obstacle_mask == 0:
		return true
	var world := get_world_3d()
	if world == null:
		return false

	var query := PhysicsRayQueryParameters3D.create(from, to, ranged_aim_obstacle_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var exclusions: Array[RID] = [get_rid()]
	if is_instance_valid(target):
		exclusions.append(target.get_rid())
	query.exclude = exclusions

	return world.direct_space_state.intersect_ray(query).is_empty()

func _pick_weighted_aim_point(points: Array[AimPointData]) -> AimPointData:
	var total_weight := 0.0
	for point_data in points:
		total_weight += point_data.weight

	var roll := randf() * total_weight
	for point_data in points:
		roll -= point_data.weight
		if roll <= 0.0:
			return point_data
	return points.back()

func _get_random_spread_offset(radius: float) -> Vector3:
	var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if offset.length_squared() < 0.001:
		offset = Vector3.RIGHT
	return offset.normalized() * randf_range(0.0, radius)

func get_weapon_spread_direction(base_direction: Vector3, extra_spread_degrees: float = 0.0) -> Vector3:
	if base_direction.length_squared() < 0.001:
		return base_direction
	if equipped_weapon == null:
		return base_direction.normalized()

	var spread_degrees := equipped_weapon.spread_angle_degrees + current_recoil_degrees + extra_spread_degrees
	if spread_degrees <= 0.001:
		return base_direction.normalized()

	return _get_random_direction_in_cone(base_direction.normalized(), deg_to_rad(spread_degrees))

func get_current_weapon_spread_angle_degrees() -> float:
	if equipped_weapon == null:
		return 0.0

	var pellet_spread := equipped_weapon.pellet_spread_angle_degrees if equipped_weapon.pellet_count > 1 else 0.0
	return maxf(0.0, equipped_weapon.spread_angle_degrees + current_recoil_degrees + pellet_spread)

func should_ai_hold_fire_for_recoil() -> bool:
	if is_player_agent() or equipped_weapon == null:
		return false

	var base_spread := maxf(equipped_weapon.spread_angle_degrees, 0.001)
	var current_spread := get_current_weapon_spread_angle_degrees()
	if _ai_recoil_recovering:
		if current_spread <= base_spread * 1.2:
			_ai_recoil_recovering = false
		return _ai_recoil_recovering

	if current_spread >= base_spread * 2.0:
		_ai_recoil_recovering = true
		return true

	return false

func _get_random_direction_in_cone(base_direction: Vector3, cone_angle: float) -> Vector3:
	var forward := base_direction.normalized()
	var reference := Vector3.UP
	if absf(forward.dot(reference)) > 0.98:
		reference = Vector3.RIGHT

	var right := forward.cross(reference).normalized()
	var up := right.cross(forward).normalized()
	var radius := tan(cone_angle)
	var angle := randf() * TAU
	var distance := sqrt(randf()) * radius
	var deviated := forward + right * cos(angle) * distance + up * sin(angle) * distance
	return deviated.normalized()

func _create_melee_attack_data() -> AttackData:
	return AttackData.new(self, get_melee_damage(), get_accuracy(true), AttackData.AttackKind.MELEE)

func _create_ranged_attack_data() -> AttackData:
	var attack_data := AttackData.new(self, get_ranged_damage(), get_accuracy(false), AttackData.AttackKind.RANGED)
	_apply_toggled_attack_modifiers(attack_data)
	return attack_data

func apply_effect(effect: UnitEffect) -> int:
	if effect == null or _is_dead:
		return 0

	var instance_id := _effect_manager.apply(effect, _apply_health_delta)
	if instance_id != 0:
		_on_effects_changed()
	return instance_id

func remove_effect_instance(instance_id: int) -> void:
	if _effect_manager.remove_instance(instance_id):
		_on_effects_changed()

func remove_effect_id(effect_id: StringName) -> void:
	if _effect_manager.remove_id(effect_id):
		_on_effects_changed()

func has_effect(effect_id: StringName) -> bool:
	return _effect_manager.has(effect_id)

func get_active_effects() -> Array:
	return _effect_manager.get_active_effects()

func _get_effect_projectile_evasion_chance() -> float:
	return _effect_manager.get_projectile_evasion_chance()

func get_projectile_evasion_chance() -> float:
	return clampf(_get_effect_projectile_evasion_chance(), 0.0, 1.0)

func _get_cover_projectile_evasion_chance() -> float:
	return _effect_manager.get_cover_projectile_evasion_chance(COVER_EFFECT_IDS)

func _get_non_cover_projectile_evasion_chance() -> float:
	return _effect_manager.get_non_cover_projectile_evasion_chance(COVER_EFFECT_IDS)

func heal(amount: int) -> int:
	if amount <= 0 or _is_dead:
		return 0

	var previous_health := _current_health
	_current_health = mini(get_max_health(), _current_health + amount)
	_emit_health_changed()
	return _current_health - previous_health

func _apply_health_delta(amount: int) -> void:
	if amount > 0:
		heal(amount)
	elif amount < 0:
		receive_damage(-amount)

func _apply_equipment() -> void:
	var equipped_weapon_applied := false
	for item in equipment:
		if item == null:
			continue

		item.apply_to(self)
		if item == equipped_weapon:
			equipped_weapon_applied = true

		if item is WeaponEquipment and equipped_weapon == null:
			equipped_weapon = item
			equipped_weapon_applied = true

	if equipped_weapon != null and not equipped_weapon_applied:
		equipped_weapon.apply_to(self)

func _build_skill_loadout() -> void:
	_skills.clear()
	_skill_cooldowns.clear()
	_toggled_skill_ids.clear()
	_manual_toggle_skill_ids.clear()
	_passive_skill_effect_instances.clear()

	for skill in common_skills:
		_add_skill(skill)
	_add_skill(_get_default_class_skill())
	for skill in extra_skills:
		_add_skill(skill)

	skills_changed.emit()

func _add_skill(skill: UnitSkill) -> void:
	if skill == null:
		return
	if has_skill(skill.id):
		return
	_skills.append(skill)

func _get_default_class_skill() -> UnitSkill:
	match unit_class:
		UnitClass.RIFLEMAN:
			return RIFLEMAN_SKILL
		UnitClass.MEDIC:
			return MEDIC_SKILL
		UnitClass.MACHINE_GUNNER:
			return MACHINE_GUNNER_SKILL
		UnitClass.SNIPER:
			return SNIPER_SKILL
		_:
			return null

func _apply_passive_skills() -> void:
	for skill in _skills:
		if skill == null or not skill.is_passive() or skill.effect == null:
			continue
		if _passive_skill_effect_instances.has(skill.id):
			continue

		var instance_id := apply_effect(skill.effect)
		if instance_id != 0:
			_passive_skill_effect_instances[skill.id] = instance_id

func _process_skill_cooldowns(delta: float) -> void:
	if _skill_cooldowns.is_empty():
		return

	var cooldown_ended := false
	for skill_id in _skill_cooldowns.keys():
		var remaining := float(_skill_cooldowns[skill_id]) - delta
		if remaining <= 0.0:
			_skill_cooldowns.erase(skill_id)
			cooldown_ended = true
		else:
			_skill_cooldowns[skill_id] = remaining

	if cooldown_ended:
		skills_changed.emit()

func _process_queued_skill_command() -> void:
	if _queued_skill_id == &"":
		return

	var skill := get_skill(_queued_skill_id)
	if skill == null:
		_clear_queued_skill_command()
		finish_player_command(PlayerCommandMode.SKILL)
		return

	var target_unit := _get_queued_skill_target_unit()
	if can_use_skill(_queued_skill_id, target_unit, _queued_skill_target_position):
		_stop_for_skill_cast()
		use_skill(_queued_skill_id, target_unit, _queued_skill_target_position)
		_clear_queued_skill_command()
		finish_player_command(PlayerCommandMode.SKILL)
		if state_machine != null:
			state_machine.transition_to_state(IdleState.ID, null)
		return

	_update_skill_cast_navigation_target(_queued_skill_target_position, skill.cast_range)

func _get_queued_skill_target_unit() -> Unit:
	if _queued_skill_target_ref == null:
		return null

	var target := _queued_skill_target_ref.get_ref() as Unit
	if target != null and is_instance_valid(target):
		return target
	return null

func _clear_queued_skill_command() -> void:
	_queued_skill_id = &""
	_queued_skill_target_position = Vector3.INF
	_queued_skill_target_ref = null

func _stop_for_skill_cast() -> void:
	movement_enabled = true
	velocity = Vector3.ZERO
	if navigation_agent != null:
		navigation_agent.velocity = Vector3.ZERO
		navigation_agent.target_position = global_position

func _update_skill_cast_navigation_target(target_position: Vector3, cast_range: float) -> void:
	if navigation_agent == null:
		return
	navigation_agent.target_position = _get_skill_cast_position(target_position, cast_range)

func _get_skill_cast_position(target_position: Vector3, cast_range: float) -> Vector3:
	var direction := global_position - target_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.RIGHT
	direction = direction.normalized()
	var stop_distance := maxf(0.1, cast_range * 0.9)
	var cast_position := target_position + direction * stop_distance
	cast_position.y = global_position.y
	return cast_position

func _sync_combat_ranges() -> void:
	var attack_range := get_attack_range()
	_set_area_radius(attack_range_area, attack_range)
	_set_area_radius(attack_leash_range_area, attack_range + 3.0)
	_set_area_radius(enemy_detection_area, get_vision_range())

func get_vision_range() -> float:
	return maxf(0.0, get_attack_range() + base_vision_extra_range + _get_effect_vision_range_bonus())

func _sync_effect_derived_stats() -> void:
	if navigation_agent:
		navigation_agent.max_speed = maxf(0.0, _base_navigation_max_speed + _get_effect_move_speed_bonus())

	var effective_max_health := get_max_health()
	if _current_health > effective_max_health:
		_current_health = effective_max_health
	_emit_health_changed()
	_sync_combat_ranges()

func _on_effects_changed() -> void:
	_sync_effect_derived_stats()
	_update_effect_indicators()
	effects_changed.emit()

func _process_active_effects(delta: float) -> void:
	if _effect_manager.process(delta, _apply_health_delta):
		_on_effects_changed()

func _get_effect_max_health_bonus() -> int:
	return _effect_manager.get_max_health_bonus()

func _get_effect_attack_damage_bonus() -> int:
	return _effect_manager.get_attack_damage_bonus()

func _get_effect_melee_damage_bonus() -> int:
	return _effect_manager.get_melee_damage_bonus()

func _get_effect_ranged_damage_bonus() -> int:
	return _effect_manager.get_ranged_damage_bonus()

func _get_toggled_ranged_damage_bonus() -> int:
	var bonus := 0
	for skill in _get_toggled_skills():
		bonus += skill.toggle_ranged_damage_bonus
	return bonus

func _apply_toggled_attack_modifiers(attack_data: AttackData) -> void:
	for skill in _get_toggled_skills():
		if skill.effect != null:
			attack_data.impact_effect = skill.effect
		if skill.toggle_projectile_trail:
			attack_data.has_incendiary_trail = true

func _get_toggled_skills() -> Array[UnitSkill]:
	var toggled_skills: Array[UnitSkill] = []
	for skill_id in _toggled_skill_ids.keys():
		var skill := get_skill(skill_id)
		if skill != null and skill.is_toggle():
			toggled_skills.append(skill)
	return toggled_skills

func _get_effect_melee_range_bonus() -> float:
	return _effect_manager.get_melee_range_bonus()

func _get_effect_ranged_range_bonus() -> float:
	return _effect_manager.get_ranged_range_bonus()

func _get_effect_attack_range_bonus() -> float:
	return _effect_manager.get_attack_range_bonus()

func _get_effect_attack_speed_multiplier() -> float:
	return _effect_manager.get_attack_speed_multiplier()

func _get_effect_move_speed_bonus() -> float:
	return _effect_manager.get_move_speed_bonus()

func _get_effect_vision_range_bonus() -> float:
	return _effect_manager.get_vision_range_bonus()

func _set_area_radius(area: Area3D, radius: float) -> void:
	if area == null:
		return

	var shape_node := area.get_child(0) as CollisionShape3D
	if shape_node == null:
		return

	var sphere := shape_node.shape as SphereShape3D
	if sphere == null:
		return

	sphere = sphere.duplicate()
	sphere.radius = radius
	shape_node.shape = sphere

func _sort_nearest(a: Node3D, b: Node3D) -> bool:
	var dist_a = global_position.distance_to(a.global_position)
	var dist_b = global_position.distance_to(b.global_position)
	return dist_a < dist_b

func update_cover_indicator() -> void:
	if current_cover == null:
		cover_indicator.visible = false
		_update_status_indicator_layout()
		_update_status_indicator_space_visibility()
		return

	cover_indicator.visible = true
	var color: Color
	match current_cover.grade:
		Cover.CoverGrade.HIGH:
			color = Color(0.0, 1.0, 0.0)
		Cover.CoverGrade.MEDIUM:
			color = Color(1.0, 0.5, 0.0)
		Cover.CoverGrade.LOW:
			color = Color(1.0, 0.0, 0.0)

	cover_indicator.modulate = color
	_update_status_indicator_layout()
	_update_status_indicator_space_visibility()

func occupy_reserved_cover() -> void:
	if reserved_cover == null or reserved_cover_slot == null:
		clear_cover()
		return

	current_cover = reserved_cover
	movement_enabled = false
	velocity = Vector3.ZERO
	if navigation_agent:
		navigation_agent.velocity = Vector3.ZERO
		navigation_agent.target_position = global_position
	_apply_cover_effect()
	update_cover_indicator()

func is_in_reserved_cover_slot() -> bool:
	if reserved_cover_slot == null:
		return false

	var from := Vector3(global_position.x, 0.0, global_position.z)
	var to := Vector3(reserved_cover_slot.global_position.x, 0.0, reserved_cover_slot.global_position.z)
	return from.distance_to(to) <= cover_slot_hold_radius

func should_auto_take_cover() -> bool:
	return not blocks_auto_cover() and current_cover == null and reserved_cover == null \
		and reserved_cover_candidate == null and current_cover_candidate == null

func is_cover_travel_in_progress() -> bool:
	return (reserved_cover != null and current_cover == null) \
		or (reserved_cover_candidate != null and current_cover_candidate == null)

func reserve_runtime_cover_candidate(candidate: CoverCandidate, system: CoverSystem) -> bool:
	if not is_instance_valid(system) or not system.is_candidate_available(self, candidate):
		return false
	# Recheck acquisition after clearing any previous target. The backend's key
	# ownership check is authoritative; no alternate candidate is selected here.
	clear_cover()
	if not system.reserve_candidate(self, candidate):
		return false
	_runtime_cover_system_ref = weakref(system)
	reserved_cover_candidate = candidate
	return true

func get_runtime_cover_system() -> CoverSystem:
	var system: CoverSystem = _runtime_cover_system_ref.get_ref() as CoverSystem if _runtime_cover_system_ref != null else null
	if not is_instance_valid(system) or not system.is_inside_tree() or system.is_queued_for_deletion() \
			or not is_inside_tree() or system.get_world_3d() != get_world_3d():
		return null
	return system

func has_live_runtime_cover_source() -> bool:
	var candidate: CoverCandidate = reserved_cover_candidate
	if candidate == null:
		return false
	if candidate.source_instance_id == 0:
		return true
	var source: Node3D = candidate.get_source()
	# Source removal is a lifetime failure. Revision/valid changes alone do not
	# force an already executing snapshot out of cover in this stage.
	return is_instance_valid(source) and source.is_inside_tree() and not source.is_queued_for_deletion() \
		and source.get_world_3d() == get_world_3d()

func is_in_runtime_cover_candidate() -> bool:
	var candidate: CoverCandidate = reserved_cover_candidate
	if candidate == null or not candidate.position.is_finite():
		return false
	var horizontal_distance: float = Vector2(global_position.x, global_position.z).distance_to(
		Vector2(candidate.position.x, candidate.position.z))
	var height_tolerance: float = maxf(navigation_agent.height, 0.1) if navigation_agent != null else 1.0
	return horizontal_distance <= cover_slot_hold_radius and absf(global_position.y - candidate.position.y) <= height_tolerance

func occupy_runtime_cover_candidate() -> void:
	var system: CoverSystem = get_runtime_cover_system()
	if system == null or system.get_runtime_candidate_occupant(reserved_cover_candidate) != self \
			or not is_in_runtime_cover_candidate():
		return
	current_cover_candidate = reserved_cover_candidate
	movement_enabled = false
	velocity = Vector3.ZERO
	if navigation_agent != null:
		navigation_agent.velocity = Vector3.ZERO
	# Geometry quality does not imply any legacy CoverGrade gameplay buff.
	_remove_cover_effect()
	update_cover_indicator()

func clear_runtime_cover_candidate(restore_movement: bool = true) -> void:
	# Do not resolve here: even a detached/queued backend can release its record.
	var system: CoverSystem = _runtime_cover_system_ref.get_ref() as CoverSystem if _runtime_cover_system_ref != null else null
	var candidate: CoverCandidate = reserved_cover_candidate if reserved_cover_candidate != null else current_cover_candidate
	if is_instance_valid(system) and candidate != null:
		system.release_candidate(self, candidate)
	reserved_cover_candidate = null
	current_cover_candidate = null
	_runtime_cover_system_ref = null
	if restore_movement:
		movement_enabled = true

func _exit_tree() -> void:
	clear_runtime_cover_candidate(false)

## Legacy compatibility path for callers that still issue a whole Cover command.
## Production AI selects exact candidates via its CoverSystem query boundary.
func get_auto_cover() -> Cover:
	if not should_auto_take_cover():
		return null

	return find_nearest_cover(auto_cover_search_radius)

func _setup_status_indicator_space() -> void:
	if status_indicator_space == null:
		return

	status_indicator_space.top_level = true
	status_indicator_space.visible = false
	cover_indicator.position = Vector3.ZERO
	cover_indicator.pixel_size = status_indicator_icon_pixel_size
	_update_status_indicator_layout()
	_update_status_indicator_space_position()

func _update_status_indicator_space_visibility() -> void:
	if status_indicator_space == null:
		return

	var any_indicator_visible := cover_indicator.visible
	for sprite in _effect_indicator_sprites.values():
		if sprite.visible:
			any_indicator_visible = true
			break

	status_indicator_space.visible = any_indicator_visible

func _update_effect_indicators() -> void:
	if status_indicator_space == null:
		return

	var active_effects_by_key := {}
	for active_effect in get_active_effects():
		var effect: UnitEffect = active_effect.effect
		if effect == null or effect.icon == null:
			continue

		var effect_key := str(effect.id)
		if active_effects_by_key.has(effect_key):
			continue

		active_effects_by_key[effect_key] = true
		var sprite := _get_or_create_effect_indicator(effect_key)
		sprite.texture = effect.icon
		sprite.modulate = Color.WHITE
		sprite.pixel_size = status_indicator_icon_pixel_size
		sprite.visible = true

	for effect_key in _effect_indicator_sprites.keys():
		if not active_effects_by_key.has(effect_key):
			_effect_indicator_sprites[effect_key].visible = false

	_update_status_indicator_layout()
	_update_status_indicator_space_visibility()

func _get_or_create_effect_indicator(effect_key: String) -> Sprite3D:
	if _effect_indicator_sprites.has(effect_key):
		return _effect_indicator_sprites[effect_key]

	var sprite := Sprite3D.new()
	sprite.name = "EffectIndicator_%s" % effect_key
	sprite.billboard = cover_indicator.billboard
	sprite.no_depth_test = true
	sprite.fixed_size = true
	sprite.pixel_size = status_indicator_icon_pixel_size
	sprite.visible = false
	status_indicator_space.add_child(sprite)
	_effect_indicator_sprites[effect_key] = sprite
	return sprite

func _update_status_indicator_layout() -> void:
	if status_indicator_space == null or cover_indicator == null:
		return

	var slot_index := 0
	if cover_indicator.visible:
		cover_indicator.position = Vector3(status_indicator_slot_spacing * slot_index, 0.0, 0.0)
		slot_index += 1
	else:
		cover_indicator.position = Vector3.ZERO

	var effect_keys := _effect_indicator_sprites.keys()
	effect_keys.sort()
	for effect_key in effect_keys:
		var sprite := _effect_indicator_sprites[effect_key] as Sprite3D
		if sprite == null:
			continue

		sprite.pixel_size = status_indicator_icon_pixel_size
		if sprite.visible:
			sprite.position = Vector3(status_indicator_slot_spacing * slot_index, 0.0, 0.0)
			slot_index += 1
		else:
			sprite.position = Vector3.ZERO

func _update_status_indicator_space_position() -> void:
	if status_indicator_space == null:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		status_indicator_space.global_position = global_position + Vector3(status_indicator_right_offset, status_indicator_up_offset, 0.0)
		return

	var camera_basis := camera.global_transform.basis.orthonormalized()
	var anchor_position := global_position
	anchor_position += camera_basis.x * status_indicator_right_offset
	anchor_position += camera_basis.y * status_indicator_up_offset
	status_indicator_space.global_transform = Transform3D(camera_basis, anchor_position)

func has_overhead_health_bar() -> bool:
	return _overhead_health_bar_space != null and is_instance_valid(_overhead_health_bar_space)

func get_overhead_health_bar_percent() -> float:
	return _overhead_health_bar_percent

func get_overhead_health_bar_sprite_count() -> int:
	if _overhead_health_bar_space == null:
		return 0

	var sprite_count := 0
	for child in _overhead_health_bar_space.get_children():
		if child is Sprite3D:
			sprite_count += 1
	return sprite_count

func is_overhead_health_bar_top_level() -> bool:
	return _overhead_health_bar_space != null and _overhead_health_bar_space.top_level

func _setup_overhead_health_bar() -> void:
	if is_player_agent():
		return

	_overhead_health_bar_space = Node3D.new()
	_overhead_health_bar_space.name = "OverheadHealthBarSpace"
	_overhead_health_bar_space.position = Vector3.UP * overhead_health_bar_up_offset
	add_child(_overhead_health_bar_space)

	_overhead_health_bar_sprite = _make_overhead_health_bar_sprite()
	_overhead_health_bar_space.add_child(_overhead_health_bar_sprite)

	_update_overhead_health_bar()

func _make_overhead_health_bar_texture(percent: float) -> Texture2D:
	var image := Image.create(
		OVERHEAD_HEALTH_BAR_TEXTURE_SIZE.x,
		OVERHEAD_HEALTH_BAR_TEXTURE_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color.TRANSPARENT)

	var width := OVERHEAD_HEALTH_BAR_TEXTURE_SIZE.x
	var height := OVERHEAD_HEALTH_BAR_TEXTURE_SIZE.y
	var fill_width := clampi(roundi(float(width - 2) * clampf(percent, 0.0, 1.0)), 0, width - 2)
	var fill_color := _get_overhead_health_bar_color(percent)
	for y in height:
		for x in width:
			var is_border := x == 0 or y == 0 or x == width - 1 or y == height - 1
			if is_border:
				image.set_pixel(x, y, Color(0.02, 0.02, 0.02, 0.95))
			elif x <= fill_width:
				image.set_pixel(x, y, fill_color)
			else:
				image.set_pixel(x, y, Color(0.16, 0.02, 0.02, 0.82))
	return ImageTexture.create_from_image(image)

func _make_overhead_health_bar_sprite() -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = "HealthBar"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.fixed_size = true
	sprite.pixel_size = overhead_health_bar_pixel_size
	sprite.scale = Vector3(overhead_health_bar_width_scale, 1.0, 1.0)
	return sprite

func _update_overhead_health_bar() -> void:
	if _overhead_health_bar_space == null:
		return

	var max_health_value := get_max_health()
	_overhead_health_bar_percent = clampf(float(_current_health) / float(max_health_value), 0.0, 1.0) if max_health_value > 0 else 0.0
	_overhead_health_bar_space.visible = not _is_dead
	if _overhead_health_bar_sprite == null:
		return

	_overhead_health_bar_sprite.texture = _make_overhead_health_bar_texture(_overhead_health_bar_percent)

func _get_overhead_health_bar_color(percent: float) -> Color:
	if percent <= 0.25:
		return Color(1.0, 0.12, 0.08, 0.95)
	if percent <= 0.55:
		return Color(1.0, 0.75, 0.16, 0.95)
	return Color(0.16, 0.95, 0.28, 0.95)

func clear_cover(restore_movement: bool = true) -> void:
	clear_runtime_cover_candidate(restore_movement)
	var cover_to_release := reserved_cover
	if cover_to_release == null:
		cover_to_release = current_cover

	if is_instance_valid(cover_to_release):
		cover_to_release.release_slot(self)

	_remove_cover_effect()
	reserved_cover = null
	reserved_cover_slot = null
	current_cover = null
	if restore_movement:
		movement_enabled = true
	update_cover_indicator()

func _apply_cover_effect() -> void:
	_remove_cover_effect()
	if current_cover == null:
		return

	var cover_effect: UnitEffect = null
	match current_cover.grade:
		Cover.CoverGrade.HIGH:
			cover_effect = COVER_HIGH_EFFECT
		Cover.CoverGrade.MEDIUM:
			cover_effect = COVER_MEDIUM_EFFECT
		Cover.CoverGrade.LOW:
			cover_effect = COVER_LOW_EFFECT

	_cover_effect_instance_id = apply_effect(cover_effect)

func _remove_cover_effect() -> void:
	if _cover_effect_instance_id != 0:
		remove_effect_instance(_cover_effect_instance_id)
		_cover_effect_instance_id = 0
		return

	for effect_id in COVER_EFFECT_IDS:
		remove_effect_id(effect_id)

## Legacy compatibility path; distances here refer to Cover origins, not slots.
func find_nearest_cover(radius: float) -> Cover:
	return find_nearest_cover_to(global_position, radius)

## Deprecated collection path: compatibility fallback for scenes without a
## CoverSystem. Production combat and idle AI query CoverSystem instead.
## Availability and tactical quality belong to the evaluator, not this query.
func get_legacy_cover_candidates_nearby(radius: float) -> Array[CoverCandidate]:
	var candidates: Array[CoverCandidate] = []
	if radius <= 0.0 or not is_inside_tree():
		return candidates
	for node: Node in get_tree().get_nodes_in_group("covers"):
		var cover: Cover = node as Cover
		if not is_instance_valid(cover) or cover.is_queued_for_deletion():
			continue
		for candidate: CoverCandidate in cover.get_cover_candidates():
			if global_position.distance_squared_to(candidate.position) <= radius * radius:
				candidates.append(candidate)
	return candidates

## Legacy compatibility path used by old commands and the legacy stuck fallback.
func find_nearest_cover_to(pos: Vector3, radius: float, excluded_cover: Cover = null) -> Cover:
	var covers = get_tree().get_nodes_in_group("covers")
	var nearest_cover: Cover = null
	var min_dist_sq = radius * radius

	for node in covers:
		var cover = node as Cover
		if cover == null:
			continue
		if cover == excluded_cover:
			continue
		if not cover.has_available_slot(self):
			continue

		var dist_sq = pos.distance_squared_to(cover.global_position)
		if dist_sq <= min_dist_sq:
			min_dist_sq = dist_sq
			nearest_cover = cover

	return nearest_cover

func receive_damage(amount: int, source: Unit = null) -> int:
	if amount <= 0 or _is_dead:
		return 0

	var previous_health := _current_health
	_current_health = maxi(0, _current_health - amount)
	var damage_dealt := previous_health - _current_health
	if damage_dealt > 0 and source != null and is_instance_valid(source) and source != self:
		source.gain_experience(damage_dealt)

	_emit_health_changed()

	if _current_health <= 0:
		die()

	return damage_dealt

func receive_attack(attack_data: AttackData) -> int:
	if attack_data == null or _is_dead:
		return 0
	if attack_data.kind == AttackData.AttackKind.RANGED:
		if attack_data.has_resolved_aim and not attack_data.aim_hits_target:
			return 0
		return receive_projectile_impact(attack_data)
	if not _does_melee_attack_hit(attack_data):
		return 0

	return receive_damage(_get_incoming_attack_damage(attack_data), attack_data.get_valid_source())

func receive_projectile_impact(attack_data: AttackData) -> int:
	if attack_data == null or _is_dead:
		return 0
	if _does_evade_projectile_impact(attack_data):
		return 0

	var damage_dealt := receive_damage(_get_incoming_attack_damage(attack_data), attack_data.get_valid_source())
	if damage_dealt > 0 and attack_data.impact_effect != null:
		apply_effect(attack_data.impact_effect)
	return damage_dealt

func _does_projectile_aim_hit(attack_data: AttackData) -> bool:
	if attack_data == null:
		return false
	return randf() < clampf(attack_data.accuracy, 0.0, 1.0)

func _does_melee_attack_hit(attack_data: AttackData) -> bool:
	return randf() < _get_melee_attack_hit_chance(attack_data)

func _get_melee_attack_hit_chance(attack_data: AttackData) -> float:
	return clampf(attack_data.accuracy - get_evasion_chance(), 0.0, 1.0)

func _does_evade_projectile_impact(attack_data: AttackData) -> bool:
	return randf() < get_projectile_impact_evasion_chance(attack_data)

func get_projectile_impact_evasion_chance(attack_data: AttackData = null) -> float:
	var stat_evasion := get_evasion_chance()
	var effect_evasion := _get_applicable_projectile_effect_evasion_chance(attack_data)
	return clampf(1.0 - ((1.0 - stat_evasion) * (1.0 - effect_evasion)), 0.0, 1.0)

func _get_applicable_projectile_effect_evasion_chance(attack_data: AttackData) -> float:
	var non_cover_evasion := _get_non_cover_projectile_evasion_chance()
	var cover_evasion := _get_cover_projectile_evasion_chance() if _is_current_cover_protecting_against(attack_data) else 0.0
	return clampf(1.0 - ((1.0 - non_cover_evasion) * (1.0 - cover_evasion)), 0.0, 1.0)

func _is_current_cover_protecting_against(attack_data: AttackData) -> bool:
	if current_cover == null or attack_data == null:
		return false
	if attack_data.kind != AttackData.AttackKind.RANGED:
		return false
	if attack_data.source_position == Vector3.INF:
		return false
	if not is_in_reserved_cover_slot():
		return false

	return current_cover.is_protecting_against(attack_data.source_position, global_position)

func _get_incoming_attack_damage(attack_data: AttackData) -> int:
	return maxi(0, attack_data.damage - get_defense())

func die() -> void:
	if _is_dead:
		return

	_is_dead = true
	if _overhead_health_bar_space != null:
		_overhead_health_bar_space.visible = false

	if state_machine:
		state_machine.stop()

	if enemy_detection_area:
		enemy_detection_area.monitoring = false
		enemy_detection_area.monitorable = false

	clear_cover()
	queue_free()

func _on_nav_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()

func _physics_process(_delta: float) -> void:
	_process_active_effects(_delta)
	_process_skill_cooldowns(_delta)
	_process_recoil_recovery(_delta)
	_process_queued_skill_command()
	if status_indicator_space != null and status_indicator_space.visible:
		_update_status_indicator_space_position()

	if current_cover != null and not is_in_reserved_cover_slot():
		clear_cover(false)
	if current_cover_candidate != null and (not is_in_runtime_cover_candidate() or get_runtime_cover_system() == null \
			or not has_live_runtime_cover_source()):
		clear_cover(false)

	if !movement_enabled:
		velocity = Vector3.ZERO
		if navigation_agent:
			navigation_agent.velocity = Vector3.ZERO
		move_and_slide()
		return

	# Advance/recompute before checking finished, including after map rebakes.
	# Keep this as the single per-physics path update for the movement agent.
	var next_path_pos: Vector3 = navigation_agent.get_next_path_position()
	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		if navigation_agent:
			navigation_agent.velocity = Vector3.ZERO
		move_and_slide()
		return

	var new_velocity: Vector3 = next_path_pos - global_position
	new_velocity.y = 0
	new_velocity = new_velocity.normalized() * navigation_agent.max_speed
	if navigation_agent.avoidance_enabled:
		navigation_agent.velocity = new_velocity
	else:
		velocity = new_velocity
		move_and_slide()

	_look_at_ground_position(next_path_pos)

func _look_at_ground_position(target_position: Vector3) -> void:
	var look_target = Vector3(target_position.x, global_position.y, target_position.z)
	if global_position.distance_squared_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)

func _process_recoil_recovery(delta: float) -> void:
	if equipped_weapon == null:
		current_recoil_degrees = 0.0
		return

	var recovery_speed := equipped_weapon.recoil_recovery_per_second * maxf(0.0, recoil_control)
	current_recoil_degrees = maxf(0.0, current_recoil_degrees - recovery_speed * delta)

func _apply_weapon_recoil() -> void:
	if equipped_weapon == null:
		return

	current_recoil_degrees = minf(
		equipped_weapon.max_recoil_degrees,
		current_recoil_degrees + maxf(0.0, equipped_weapon.recoil_per_shot_degrees)
	)
	if current_recoil_degrees <= 0.001:
		_ai_recoil_recovering = false

func _emit_health_changed() -> void:
	health_changed.emit(_current_health, get_max_health())
	_update_overhead_health_bar()

func _emit_veterancy_changed() -> void:
	veterancy_changed.emit(veterancy, experience, get_next_veterancy_experience())

func _emit_agent_level_changed() -> void:
	agent_level_changed.emit(agent_level, agent_experience, get_next_agent_level_experience())

class AimPointData:
	var position: Vector3
	var weight: float

	func _init(point_position: Vector3, point_weight: float) -> void:
		position = point_position
		weight = point_weight

class RangedAimSolution:
	var hit_quality: float
	var impact_position: Vector3

	func _init(solution_hit_quality: float, solution_impact_position: Vector3) -> void:
		hit_quality = solution_hit_quality
		impact_position = solution_impact_position
