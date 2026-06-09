extends RigidBody3D
class_name GrenadeProjectile

@export var speed: float = 11.0
@export var fuse_time: float = 3.5
@export var min_duration: float = 0.35
@export var min_arc_height: float = 0.8
@export var max_arc_height: float = 3.2
@export var spin_strength: float = 7.0

var _caster_ref: WeakRef
var _caster_team_mask: int = 0
var _skill: Resource
var _fuse_elapsed: float = 0.0
var _detonated: bool = false

func setup(caster, skill: Resource, target_position: Vector3) -> void:
	if caster == null or skill == null or target_position == Vector3.INF:
		queue_free()
		return

	_caster_ref = weakref(caster)
	_caster_team_mask = caster.get_team_mask()
	_skill = skill

	var start_position: Vector3 = caster.global_position + Vector3.UP * 0.9
	global_position = start_position
	linear_velocity = _get_launch_velocity(start_position, target_position)
	angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * spin_strength
	sleeping = false

func _physics_process(delta: float) -> void:
	if _skill == null or _detonated:
		queue_free()
		return

	_fuse_elapsed += delta
	if _fuse_elapsed >= fuse_time:
		_detonate()

func _get_launch_velocity(start_position: Vector3, target_position: Vector3) -> Vector3:
	var gravity := maxf(0.1, float(ProjectSettings.get_setting("physics/3d/default_gravity")))
	var flat_start := Vector3(start_position.x, 0.0, start_position.z)
	var flat_target := Vector3(target_position.x, 0.0, target_position.z)
	var horizontal_displacement := flat_target - flat_start
	var distance := horizontal_displacement.length()
	var range_ratio := clampf(distance / maxf(_skill.cast_range, 0.1), 0.0, 1.0)
	var arc_height := lerpf(max_arc_height, min_arc_height, range_ratio)
	var apex_y := maxf(start_position.y, target_position.y) + arc_height
	var time_up := sqrt(maxf(0.0, 2.0 * (apex_y - start_position.y) / gravity))
	var time_down := sqrt(maxf(0.0, 2.0 * (apex_y - target_position.y) / gravity))
	var flight_time := maxf(min_duration, time_up + time_down)
	var speed_duration := distance / maxf(speed, 0.1)
	flight_time = maxf(flight_time, speed_duration)

	var horizontal_velocity := horizontal_displacement / flight_time
	var vertical_velocity := sqrt(maxf(0.0, 2.0 * gravity * (apex_y - start_position.y)))
	return horizontal_velocity + Vector3.UP * vertical_velocity

func _detonate() -> void:
	if _skill == null or _detonated:
		return

	_detonated = true
	var source: Object = _get_valid_caster()
	var explosion_center := global_position
	var radius := float(_skill.radius)
	var radius_sq := radius * radius
	for node in get_tree().get_nodes_in_group("units"):
		var unit = node
		if unit == null or not is_instance_valid(unit) or unit._is_dead:
			continue
		if unit.global_position.distance_squared_to(explosion_center) > radius_sq:
			continue
		if not _can_affect_unit(unit, source):
			continue

		if _skill.damage > 0:
			unit.receive_damage(_skill.damage, source)
		if _skill.heal_amount > 0:
			unit.heal(_skill.heal_amount)
		if _skill.effect != null:
			unit.apply_effect(_skill.effect)

	queue_free()

func _get_valid_caster():
	if _caster_ref == null:
		return null

	var caster: Object = _caster_ref.get_ref()
	if caster != null and is_instance_valid(caster):
		return caster
	return null

func _can_affect_unit(unit, source) -> bool:
	var unit_team_mask: int = unit.get_team_mask()
	if source != null and unit == source:
		return bool(_skill.affects_allies)
	if _caster_team_mask != 0 and unit_team_mask == _caster_team_mask:
		return bool(_skill.affects_allies)
	if _caster_team_mask != 0 and unit_team_mask != 0 and unit_team_mask != _caster_team_mask:
		return bool(_skill.affects_enemies)
	return false
