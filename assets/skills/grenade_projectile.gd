extends Node3D
class_name GrenadeProjectile

@export var speed: float = 11.0
@export var min_duration: float = 0.35
@export var min_arc_height: float = 0.8
@export var max_arc_height: float = 3.2

var _caster_ref: WeakRef
var _caster_team_mask: int = 0
var _skill: UnitSkill
var _start_position: Vector3
var _target_position: Vector3
var _duration: float = 1.0
var _elapsed: float = 0.0
var _arc_height: float = 1.0

func setup(caster: Unit, skill: UnitSkill, target_position: Vector3) -> void:
	_caster_ref = weakref(caster)
	if caster != null:
		_caster_team_mask = caster.get_team_mask()
	_skill = skill
	_start_position = caster.global_position + Vector3.UP * 0.9
	_target_position = target_position
	global_position = _start_position
	
	var distance := _get_horizontal_distance(_start_position, _target_position)
	_duration = maxf(min_duration, distance / maxf(speed, 0.1))
	var range_ratio := clampf(distance / maxf(_skill.cast_range, 0.1), 0.0, 1.0)
	_arc_height = lerpf(max_arc_height, min_arc_height, range_ratio)

func _process(delta: float) -> void:
	if _skill == null:
		queue_free()
		return
	
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	global_position = _get_arc_position(t)
	
	if t >= 1.0:
		_detonate()
		queue_free()

func _get_arc_position(t: float) -> Vector3:
	var arc_position := _start_position.lerp(_target_position, t)
	arc_position.y += sin(t * PI) * _arc_height
	return arc_position

func _detonate() -> void:
	if _skill == null:
		return
	
	var source := _get_valid_caster()
	var radius := float(_skill.radius)
	var radius_sq := radius * radius
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or not is_instance_valid(unit) or unit._is_dead:
			continue
		if _get_horizontal_distance_squared(unit.global_position, _target_position) > radius_sq:
			continue
		if not _can_affect_unit(unit, source):
			continue
		
		if _skill.damage > 0:
			unit.receive_damage(_skill.damage, source)
		if _skill.heal_amount > 0:
			unit.heal(_skill.heal_amount)
		if _skill.effect != null:
			unit.apply_effect(_skill.effect)

func _get_valid_caster() -> Unit:
	if _caster_ref == null:
		return null
	
	var caster := _caster_ref.get_ref() as Unit
	if caster != null and is_instance_valid(caster):
		return caster
	return null

func _can_affect_unit(unit: Unit, source: Unit) -> bool:
	var unit_team_mask := unit.get_team_mask()
	if source != null and unit == source:
		return bool(_skill.affects_allies)
	if _caster_team_mask != 0 and unit_team_mask == _caster_team_mask:
		return bool(_skill.affects_allies)
	if _caster_team_mask != 0 and unit_team_mask != 0 and unit_team_mask != _caster_team_mask:
		return bool(_skill.affects_enemies)
	return false

func _get_horizontal_distance(from: Vector3, to: Vector3) -> float:
	var flat_from := Vector3(from.x, 0.0, from.z)
	var flat_to := Vector3(to.x, 0.0, to.z)
	return flat_from.distance_to(flat_to)

func _get_horizontal_distance_squared(from: Vector3, to: Vector3) -> float:
	var flat_from := Vector2(from.x, from.z)
	var flat_to := Vector2(to.x, to.z)
	return flat_from.distance_squared_to(flat_to)
