extends Resource
class_name UnitSkill

enum SkillType {
	ACTIVE,
	PASSIVE,
}

enum TargetType {
	NONE,
	SELF,
	POSITION,
	ALLY_UNIT,
	ENEMY_UNIT,
	ANY_UNIT,
}

enum DeliveryType {
	INSTANT,
	ARC_PROJECTILE,
}

@export var id: StringName = &"skill"
@export var display_name: String = "Skill"
@export var description: String = ""
@export var skill_type: SkillType = SkillType.ACTIVE
@export var target_type: TargetType = TargetType.NONE
@export var delivery_type: DeliveryType = DeliveryType.INSTANT
@export var cooldown: float = 0.0
@export var cast_range: float = 0.0
@export var radius: float = 0.0
@export var damage: int = 0
@export var heal_amount: int = 0
@export var effect: UnitEffect
@export var projectile_scene: PackedScene
@export var affects_enemies: bool = true
@export var affects_allies: bool = false
@export var grant_experience_on_use: bool = true

func is_active() -> bool:
	return skill_type == SkillType.ACTIVE

func is_passive() -> bool:
	return skill_type == SkillType.PASSIVE

func can_activate(caster: Unit, target_unit: Unit = null, target_position: Vector3 = Vector3.INF) -> bool:
	if caster == null or not is_instance_valid(caster) or caster._is_dead:
		return false
	
	match target_type:
		TargetType.NONE, TargetType.SELF:
			return true
		TargetType.POSITION:
			return target_position != Vector3.INF and _is_position_in_range(caster, target_position)
		TargetType.ALLY_UNIT:
			return _is_valid_target_unit(caster, target_unit, true, false)
		TargetType.ENEMY_UNIT:
			return _is_valid_target_unit(caster, target_unit, false, true)
		TargetType.ANY_UNIT:
			return _is_valid_target_unit(caster, target_unit, true, true)
		_:
			return false

func activate(caster: Unit, target_unit: Unit = null, target_position: Vector3 = Vector3.INF) -> bool:
	if not can_activate(caster, target_unit, target_position):
		return false
	
	if delivery_type == DeliveryType.ARC_PROJECTILE:
		var spawned := _spawn_arc_projectile(caster, target_position)
		if spawned and grant_experience_on_use:
			caster.grant_skill_experience()
		return spawned
	
	var affected := apply_at_position(caster, target_unit, target_position)
	if affected and grant_experience_on_use:
		caster.grant_skill_experience()
	
	return affected

func apply_at_position(caster: Unit, target_unit: Unit = null, target_position: Vector3 = Vector3.INF) -> bool:
	var affected := false
	if target_type == TargetType.SELF:
		affected = _apply_to_unit(caster, caster)
	elif radius > 0.0:
		var center := target_position
		if center == Vector3.INF and target_unit != null:
			center = target_unit.global_position
		affected = _apply_to_units_in_radius(caster, center)
	elif target_unit != null:
		affected = _apply_to_unit(caster, target_unit)
	else:
		affected = true
	
	return affected

func _spawn_arc_projectile(caster: Unit, target_position: Vector3) -> bool:
	if projectile_scene == null or target_position == Vector3.INF:
		return false
	
	var projectile := projectile_scene.instantiate()
	if projectile == null:
		return false
	
	var scene_root: Node = caster.get_tree().current_scene
	if scene_root == null:
		return false
	
	scene_root.add_child(projectile)
	if projectile.has_method("setup"):
		projectile.setup(caster, self, target_position)
	return true

func _apply_to_units_in_radius(caster: Unit, center: Vector3) -> bool:
	if center == Vector3.INF:
		return false
	
	var affected := false
	var radius_sq := radius * radius
	for node in caster.get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or not is_instance_valid(unit) or unit._is_dead:
			continue
		if _get_horizontal_distance_squared(unit.global_position, center) > radius_sq:
			continue
		if not _can_affect_unit(caster, unit):
			continue
		
		affected = _apply_to_unit(caster, unit) or affected
	
	return affected

func _apply_to_unit(caster: Unit, unit: Unit) -> bool:
	if not _can_affect_unit(caster, unit):
		return false
	
	var affected := false
	if damage > 0:
		affected = unit.receive_damage(damage, caster) > 0 or affected
	if heal_amount > 0:
		affected = unit.heal(heal_amount) > 0 or affected
	if effect != null:
		unit.apply_effect(effect)
		affected = true
	
	return affected

func _can_affect_unit(caster: Unit, unit: Unit) -> bool:
	if not is_instance_valid(unit) or unit._is_dead:
		return false
	if unit == caster:
		return affects_allies
	if caster.is_enemy_unit(unit):
		return affects_enemies
	if caster.is_ally_unit(unit):
		return affects_allies
	return false

func _is_valid_target_unit(caster: Unit, target_unit: Unit, allow_ally: bool, allow_enemy: bool) -> bool:
	if target_unit == null or not is_instance_valid(target_unit) or target_unit._is_dead:
		return false
	if not _is_position_in_range(caster, target_unit.global_position):
		return false
	if allow_ally and (target_unit == caster or caster.is_ally_unit(target_unit)):
		return true
	if allow_enemy and caster.is_enemy_unit(target_unit):
		return true
	return false

func _is_position_in_range(caster: Unit, target_position: Vector3) -> bool:
	if cast_range <= 0.0:
		return true
	return _get_horizontal_distance(caster.global_position, target_position) <= cast_range + 0.05

func _get_horizontal_distance(from: Vector3, to: Vector3) -> float:
	return sqrt(_get_horizontal_distance_squared(from, to))

func _get_horizontal_distance_squared(from: Vector3, to: Vector3) -> float:
	var flat_from := Vector2(from.x, from.z)
	var flat_to := Vector2(to.x, to.z)
	return flat_from.distance_squared_to(flat_to)
