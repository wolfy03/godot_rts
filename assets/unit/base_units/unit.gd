extends CharacterBody3D
class_name Unit

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
@export var melee_range: float = 3.0
@export var melee_damage: int = 40
@export var melee_cooldown: float = 1.0
@export var equipment: Array[Equipment] = []
@export var equipped_weapon: WeaponEquipment
@export var status_indicator_right_offset: float = 0.42
@export var status_indicator_up_offset: float = 1.08
@export var cover_slot_hold_radius: float = 0.65
@export var auto_cover_search_radius: float = 5.0

var last_move_command_data: MoveState.MoveCommandData
var movement_enabled: bool = true
var hold_position_enabled: bool = false
var equipment_attack_damage_bonus: int = 0
var equipment_attack_range_bonus: float = 0.0
var equipment_attack_speed_multiplier: float = 1.0

var _nearest_position_to_target: Vector3 = Vector3.INF
var _current_health: int
var _is_dead: bool = false
var _base_navigation_max_speed: float = 0.0
var _active_effects: Array[ActiveUnitEffect] = []
var _next_effect_instance_id: int = 1
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
		target.receive_damage(get_melee_damage())
		return
	
	if equipped_weapon:
		_fire_projectile(target, get_ranged_damage())

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

func _fire_projectile(target: Unit, damage: int) -> void:
	if equipped_weapon.projectile_scene == null:
		target.receive_damage(damage)
		return
	
	var projectile := equipped_weapon.projectile_scene.instantiate() as Projectile
	if projectile == null:
		target.receive_damage(damage)
		return
	
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + Vector3.UP * 0.7
	projectile.setup(target, damage)

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
	_sync_effect_derived_stats()
	effects_changed.emit()
	return instance.instance_id

func remove_effect_instance(instance_id: int) -> void:
	for index in range(_active_effects.size() - 1, -1, -1):
		if _active_effects[index].instance_id == instance_id:
			_active_effects.remove_at(index)
			_sync_effect_derived_stats()
			effects_changed.emit()
			return

func remove_effect_id(effect_id: StringName) -> void:
	var removed := false
	for index in range(_active_effects.size() - 1, -1, -1):
		if _active_effects[index].effect.id == effect_id:
			_active_effects.remove_at(index)
			removed = true
	
	if removed:
		_sync_effect_derived_stats()
		effects_changed.emit()

func has_effect(effect_id: StringName) -> bool:
	for active_effect in _active_effects:
		if active_effect.effect.id == effect_id:
			return true
	
	return false

func get_active_effects() -> Array[ActiveUnitEffect]:
	return _active_effects.duplicate()

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
	for item in equipment:
		if item == null:
			continue
		
		item.apply_to(self)
		
		if item is WeaponEquipment and equipped_weapon == null:
			equipped_weapon = item

func _sync_combat_ranges() -> void:
	var attack_range = get_attack_range()
	_set_area_radius(attack_range_area, attack_range)
	_set_area_radius(attack_leash_range_area, attack_range + 3.0)
	_set_area_radius(enemy_detection_area, attack_range + 2.0)

func _sync_effect_derived_stats() -> void:
	if navigation_agent:
		navigation_agent.max_speed = maxf(0.0, _base_navigation_max_speed + _get_effect_move_speed_bonus())
	
	var effective_max_health := get_max_health()
	if _current_health > effective_max_health:
		_current_health = effective_max_health
	_emit_health_changed()
	_sync_combat_ranges()

func _process_active_effects(delta: float) -> void:
	if _active_effects.is_empty():
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
		_sync_effect_derived_stats()
		effects_changed.emit()

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
	_update_status_indicator_space_position()

func _update_status_indicator_space_visibility():
	if status_indicator_space == null:
		return
	
	status_indicator_space.visible = cover_indicator.visible

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
	
	reserved_cover = null
	reserved_cover_slot = null
	current_cover = null
	if restore_movement:
		movement_enabled = true
	update_cover_indicator()

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
