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

signal health_changed(current_health: int, max_health: int)
signal effects_changed

@onready var colission_shape: CollisionShape3D = %CollisionShape3D
@onready var navigation_agent: NavigationAgent3D = %NavigationAgent
@onready var unit_selected_sprite: Node3D = %UnitSelectedSprite
@onready var state_machine: StateMachine = %StateMachine
@onready var attack_range_area: Area3D = %AttackRangeArea
@onready var attack_leash_range_area: Area3D = %AttackLeashRangeArea
@onready var enemy_detection_area: Area3D = %EnemyDetectionArea
@onready var status_indicator_space: Node3D = %StatusIndicatorSpace
@onready var cover_indicator: Sprite3D = %CoverIndicator

@export var max_health: int = 100
@export var defense: int = 0
@export_range(0.0, 1.0, 0.01) var ranged_accuracy: float = 0.5
@export_range(0.0, 1.0, 0.01) var melee_accuracy: float = 1.0
@export_range(0.0, 1.0, 0.01) var evasion_chance: float = 0.0
@export_file("*.png") var portrait_image_path: String = "res://assets/unit/portraits/infantry_portrait.png"
@export var melee_range: float = 3.0
@export var melee_damage: int = 40
@export var melee_cooldown: float = 1.0
@export var equipment: Array[Equipment] = []
@export var equipped_weapon: WeaponEquipment
@export var status_indicator_right_offset: float = 0.42
@export var status_indicator_up_offset: float = 1.08
@export var status_indicator_slot_spacing: float = 0.14
@export var status_indicator_icon_pixel_size: float = 0.0001
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

var _nearest_position_to_target: Vector3 = Vector3.INF
var _current_health: int
var _is_dead: bool = false
var _base_navigation_max_speed: float = 0.0
var _portrait_texture: Texture2D = null
var _active_effects: Array[ActiveUnitEffect] = []
var _next_effect_instance_id: int = 1
var _cover_effect_instance_id: int = 0
var _active_effects_need_processing: bool = false
var _effect_indicator_sprites: Dictionary = {}
var reserved_cover: Cover = null
var reserved_cover_slot: Marker3D = null
var current_cover: Cover = null

func _ready():
	if collision_layer & 0b10:
		add_to_group("selectable_units")
	navigation_agent.velocity_computed.connect(_on_nav_velocity_computed)
	_apply_equipment()
	_base_navigation_max_speed = navigation_agent.max_speed
	_sync_combat_ranges()
	_current_health = get_max_health()
	_emit_health_changed()
	_setup_status_indicator_space()

func on_selection_changed(selected: bool):
	unit_selected_sprite.visible = selected

func attack_nearest_unit_in_range() -> Unit:
	if !enemy_detection_area:
		return null
	
	var enemies = enemy_detection_area.get_overlapping_bodies()
	
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

func get_max_health() -> int:
	return maxi(1, max_health + _get_effect_max_health_bonus())

func get_current_health() -> int:
	return _current_health

func get_defense() -> int:
	return defense

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
	if !is_instance_valid(target) or target._is_dead:
		return false
	
	return get_distance_to_unit(target) <= get_attack_range()

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
	return maxi(0, equipped_weapon.get_damage(equipment_attack_damage_bonus + _get_effect_attack_damage_bonus() + _get_effect_ranged_damage_bonus()))

func perform_attack(target: Unit) -> void:
	if !is_instance_valid(target) or target._is_dead:
		return
	
	if _should_melee_attack(target):
		if _roll_attack_hit(target, true):
			target.receive_damage(get_melee_damage())
		return
	
	if equipped_weapon:
		_fire_projectile(target, get_ranged_damage(), _roll_attack_hit(target, false))

func _should_melee_attack(target: Unit) -> bool:
	return get_distance_to_unit(target) <= get_melee_range()

func should_prioritize_cover_against(target: Unit) -> bool:
	if not should_auto_take_cover():
		return false
	if not is_instance_valid(target) or target._is_dead:
		return false
	if equipped_weapon == null:
		return false
	
	return get_distance_to_unit(target) > melee_range

func _fire_projectile(target: Unit, damage: int, will_hit: bool) -> void:
	if equipped_weapon.projectile_scene == null:
		if will_hit:
			target.receive_damage(damage)
		return
	
	var projectile := equipped_weapon.projectile_scene.instantiate() as Projectile
	if projectile == null:
		if will_hit:
			target.receive_damage(damage)
		return
	
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + Vector3.UP * 0.7
	projectile.setup(target, damage, will_hit, _get_projectile_impact_position(target, will_hit))

func _roll_attack_hit(target: Unit, is_melee: bool) -> bool:
	return randf() < get_attack_hit_chance(target, is_melee)

func get_attack_hit_chance(target: Unit, is_melee: bool = false) -> float:
	if target == null:
		return 0.0
	
	return clampf(get_accuracy(is_melee) - target.get_evasion_chance(), 0.0, 1.0)

func _get_projectile_impact_position(target: Unit, will_hit: bool) -> Vector3:
	var target_position := target.global_position + Vector3.UP * 0.6
	if will_hit:
		return target_position
	
	var miss_distance := randf_range(0.75, 1.8)
	var miss_angle := randf() * TAU
	var miss_offset := Vector3(cos(miss_angle) * miss_distance, 0.0, sin(miss_angle) * miss_distance)
	return target_position + miss_offset

func apply_effect(effect: Resource) -> int:
	if effect == null or _is_dead:
		return 0
	
	var runtime_effect := effect.duplicate(true)
	if runtime_effect == null:
		return 0
	if not runtime_effect.has_method("has_stat_modifiers"):
		push_warning("apply_effect expected a UnitEffect resource.")
		return 0
	
	if runtime_effect.instant_health_delta != 0:
		_apply_health_delta(runtime_effect.instant_health_delta)
	
	if not runtime_effect.has_stat_modifiers():
		return 0
	
	var instance := ActiveUnitEffect.new(_next_effect_instance_id, runtime_effect)
	_next_effect_instance_id += 1
	_active_effects.append(instance)
	_refresh_active_effect_processing_state()
	_sync_effect_derived_stats()
	_update_effect_indicators()
	effects_changed.emit()
	return instance.instance_id

func remove_effect_instance(instance_id: int) -> void:
	for index in range(_active_effects.size() - 1, -1, -1):
		if _active_effects[index].instance_id == instance_id:
			_active_effects.remove_at(index)
			_refresh_active_effect_processing_state()
			_sync_effect_derived_stats()
			_update_effect_indicators()
			effects_changed.emit()
			return

func remove_effect_id(effect_id: StringName) -> void:
	var removed := false
	for index in range(_active_effects.size() - 1, -1, -1):
		if _active_effects[index].effect.id == effect_id:
			_active_effects.remove_at(index)
			removed = true
	
	if removed:
		_refresh_active_effect_processing_state()
		_sync_effect_derived_stats()
		_update_effect_indicators()
		effects_changed.emit()

func has_effect(effect_id: StringName) -> bool:
	for active_effect in _active_effects:
		if active_effect.effect.id == effect_id:
			return true
	
	return false

func get_active_effects() -> Array[ActiveUnitEffect]:
	return _active_effects.duplicate()

func _get_effect_projectile_evasion_chance() -> float:
	var effect_evasion_chance := 0.0
	for active_effect in _active_effects:
		effect_evasion_chance = maxf(effect_evasion_chance, active_effect.effect.projectile_evasion_chance)
	
	return effect_evasion_chance

func get_projectile_evasion_chance() -> float:
	return clampf(_get_effect_projectile_evasion_chance(), 0.0, 1.0)

func try_evade_projectile_attack() -> bool:
	var projectile_evasion_chance := get_projectile_evasion_chance()
	return projectile_evasion_chance > 0.0 and randf() < projectile_evasion_chance

func heal(amount: int) -> void:
	if amount <= 0 or _is_dead:
		return
	
	_current_health = mini(get_max_health(), _current_health + amount)
	_emit_health_changed()

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

func _sync_combat_ranges() -> void:
	var attack_range = get_attack_range()
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

func _process_active_effects(delta: float) -> void:
	if not _active_effects_need_processing:
		return
	
	var removed := false
	for index in range(_active_effects.size() - 1, -1, -1):
		var active_effect := _active_effects[index]
		_process_effect_health_delta(active_effect, delta)
		
		if active_effect.remaining_duration > 0.0:
			active_effect.remaining_duration -= delta
			if active_effect.remaining_duration <= 0.0:
				_active_effects.remove_at(index)
				removed = true
	
	if removed:
		_refresh_active_effect_processing_state()
		_sync_effect_derived_stats()
		_update_effect_indicators()
		effects_changed.emit()

func _refresh_active_effect_processing_state() -> void:
	_active_effects_need_processing = false
	for active_effect in _active_effects:
		if active_effect.remaining_duration > 0.0 or not is_zero_approx(active_effect.effect.health_delta_per_second):
			_active_effects_need_processing = true
			return

func _process_effect_health_delta(active_effect: ActiveUnitEffect, delta: float) -> void:
	if is_zero_approx(active_effect.effect.health_delta_per_second):
		return
	
	active_effect.health_delta_remainder += active_effect.effect.health_delta_per_second * delta
	var whole_delta := 0
	if active_effect.health_delta_remainder >= 1.0:
		whole_delta = int(floor(active_effect.health_delta_remainder))
	elif active_effect.health_delta_remainder <= -1.0:
		whole_delta = int(ceil(active_effect.health_delta_remainder))
	
	if whole_delta == 0:
		return
	
	active_effect.health_delta_remainder -= float(whole_delta)
	_apply_health_delta(whole_delta)

func _get_effect_max_health_bonus() -> int:
	var bonus := 0
	for active_effect in _active_effects:
		bonus += active_effect.effect.max_health_bonus
	return bonus

func _get_effect_attack_damage_bonus() -> int:
	var bonus := 0
	for active_effect in _active_effects:
		bonus += active_effect.effect.attack_damage_bonus
	return bonus

func _get_effect_melee_damage_bonus() -> int:
	var bonus := 0
	for active_effect in _active_effects:
		bonus += active_effect.effect.melee_damage_bonus
	return bonus

func _get_effect_ranged_damage_bonus() -> int:
	var bonus := 0
	for active_effect in _active_effects:
		bonus += active_effect.effect.ranged_damage_bonus
	return bonus

func _get_effect_melee_range_bonus() -> float:
	var bonus := 0.0
	for active_effect in _active_effects:
		bonus += active_effect.effect.melee_range_bonus
	return bonus

func _get_effect_ranged_range_bonus() -> float:
	var bonus := 0.0
	for active_effect in _active_effects:
		bonus += active_effect.effect.ranged_range_bonus
	return bonus

func _get_effect_attack_range_bonus() -> float:
	var bonus := 0.0
	for active_effect in _active_effects:
		bonus += active_effect.effect.attack_range_bonus
	return bonus

func _get_effect_attack_speed_multiplier() -> float:
	var multiplier := 1.0
	for active_effect in _active_effects:
		multiplier *= active_effect.effect.attack_speed_multiplier
	return maxf(multiplier, 0.01)

func _get_effect_move_speed_bonus() -> float:
	var bonus := 0.0
	for active_effect in _active_effects:
		bonus += active_effect.effect.move_speed_bonus
	return bonus

func _get_effect_vision_range_bonus() -> float:
	var bonus := 0.0
	for active_effect in _active_effects:
		bonus += active_effect.effect.vision_range_bonus
	return bonus

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
	return current_cover == null and reserved_cover == null

func get_auto_cover() -> Cover:
	if not should_auto_take_cover():
		return null
	
	return find_nearest_cover(auto_cover_search_radius)

func _setup_status_indicator_space():
	if status_indicator_space == null:
		return
	
	status_indicator_space.top_level = true
	status_indicator_space.visible = false
	cover_indicator.position = Vector3.ZERO
	cover_indicator.pixel_size = status_indicator_icon_pixel_size
	_update_status_indicator_layout()
	_update_status_indicator_space_position()

func _update_status_indicator_space_visibility():
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
	for active_effect in _active_effects:
		var effect := active_effect.effect
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

func _update_status_indicator_space_position():
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

func clear_cover(restore_movement: bool = true):
	var cover_to_release := reserved_cover
	if cover_to_release == null:
		cover_to_release = current_cover
	
	if cover_to_release != null:
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
	
	var cover_effect: Resource = null
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

func find_nearest_cover(radius: float) -> Cover:
	var covers = get_tree().get_nodes_in_group("covers")
	var nearest_cover: Cover = null
	var min_dist_sq = radius * radius
	
	for node in covers:
		var cover = node as Cover
		if cover == null:
			continue
		if not cover.has_available_slot(self):
			continue
			
		var dist_sq = global_position.distance_squared_to(cover.global_position)
		if dist_sq <= min_dist_sq:
			min_dist_sq = dist_sq
			nearest_cover = cover
			
	return nearest_cover

func find_nearest_cover_to(pos: Vector3, radius: float) -> Cover:
	var covers = get_tree().get_nodes_in_group("covers")
	var nearest_cover: Cover = null
	var min_dist_sq = radius * radius
	
	for node in covers:
		var cover = node as Cover
		if cover == null:
			continue
		if not cover.has_available_slot(self):
			continue
			
		var dist_sq = pos.distance_squared_to(cover.global_position)
		if dist_sq <= min_dist_sq:
			min_dist_sq = dist_sq
			nearest_cover = cover
			
	return nearest_cover

func receive_damage(amount: int):
	if amount <= 0 or _is_dead:
		return
	
	_current_health = maxi(0, _current_health - amount)
	_emit_health_changed()
	
	if _current_health <= 0:
		die()

func die():
	if _is_dead:
		return
	
	_is_dead = true
	
	if state_machine:
		state_machine.stop()
	
	if enemy_detection_area:
		enemy_detection_area.monitoring = false
		enemy_detection_area.monitorable = false
	
	clear_cover()
	queue_free()
	
func _on_nav_velocity_computed(safe_velocity: Vector3):
	velocity = safe_velocity
	move_and_slide()

func _physics_process(_delta: float):
	_process_active_effects(_delta)
	if status_indicator_space != null and status_indicator_space.visible:
		_update_status_indicator_space_position()
	
	if current_cover != null and not is_in_reserved_cover_slot():
		clear_cover(false)
	
	if !movement_enabled:
		velocity = Vector3.ZERO
		if navigation_agent:
			navigation_agent.velocity = Vector3.ZERO
		move_and_slide()
		return
	
	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		if navigation_agent:
			navigation_agent.velocity = Vector3.ZERO
		move_and_slide()
		return
	
	if _nearest_position_to_target == Vector3.INF:
		_nearest_position_to_target = global_position
	elif navigation_agent.distance_to_target() < _nearest_position_to_target.distance_to(navigation_agent.target_position):
		_nearest_position_to_target = global_position
	
	var next_path_pos: Vector3 = navigation_agent.get_next_path_position()
	
	if next_path_pos.distance_to(navigation_agent.target_position) > _nearest_position_to_target.distance_to(navigation_agent.target_position):
		navigation_agent.target_position = navigation_agent.target_position
	
	var new_velocity: Vector3 = next_path_pos - global_position
	new_velocity.y = 0
	new_velocity = new_velocity.normalized() * navigation_agent.max_speed
	navigation_agent.velocity = new_velocity

	_look_at_ground_position(navigation_agent.target_position)

func _look_at_ground_position(target_position: Vector3):
	var look_target = Vector3(target_position.x, global_position.y, target_position.z)
	if global_position.distance_squared_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)

func _emit_health_changed() -> void:
	health_changed.emit(_current_health, get_max_health())

class ActiveUnitEffect:
	var instance_id: int
	var effect: Resource
	var remaining_duration: float
	var health_delta_remainder: float = 0.0
	
	func _init(effect_instance_id: int, unit_effect: Resource) -> void:
		instance_id = effect_instance_id
		effect = unit_effect
		remaining_duration = unit_effect.duration
