extends Node3D
class_name Projectile

@export var speed: float = 18.0
@export var hit_distance: float = 0.25
@export var max_lifetime: float = 4.0
@export_flags_3d_physics var obstacle_collision_mask: int = 1
@export_flags_3d_physics var unit_collision_mask: int = 6

var _target: Unit
var _attack_data: AttackData
var _miss_direction: Vector3 = Vector3.ZERO
var _lifetime: float = 0.0

func setup(target: Unit, attack_data: AttackData, miss_position: Vector3 = Vector3.INF) -> void:
	_target = target
	_attack_data = attack_data
	if _is_aimed_miss() and miss_position != Vector3.INF:
		_miss_direction = (miss_position - global_position).normalized()

func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= max_lifetime:
		queue_free()
		return

	if _is_aimed_miss():
		_process_miss(delta)
		return

	var target_position := _get_current_target_position()
	if target_position == Vector3.INF:
		queue_free()
		return

	var to_target := target_position - global_position
	var distance := to_target.length()
	var next_position := global_position + to_target.normalized() * minf(speed * delta, distance)

	if _process_collision_between(global_position, next_position):
		return

	if distance <= hit_distance:
		_apply_impact_to(_target)
		queue_free()
		return

	global_position = next_position
	if global_position.distance_squared_to(target_position) > 0.0001:
		look_at(target_position, Vector3.UP)

func _process_miss(delta: float) -> void:
	if _miss_direction == Vector3.ZERO:
		queue_free()
		return

	var next_position := global_position + _miss_direction * speed * delta
	if _process_collision_between(global_position, next_position):
		return

	global_position = next_position
	look_at(global_position + _miss_direction, Vector3.UP)

func _is_aimed_miss() -> bool:
	return _attack_data != null and _attack_data.has_resolved_aim and not _attack_data.aim_hits_target

func _process_collision_between(from: Vector3, to: Vector3) -> bool:
	var collision := _get_collision_between(from, to)
	if collision.is_empty():
		return false

	var unit := collision.get("collider") as Unit
	if unit != null:
		_apply_impact_to(unit)

	queue_free()
	return true

func _get_collision_between(from: Vector3, to: Vector3) -> Dictionary:
	var collision_mask := obstacle_collision_mask | unit_collision_mask
	if collision_mask == 0:
		return {}

	var world := get_world_3d()
	if world == null:
		return {}

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = collision_mask
	query.exclude = _get_collision_exclusions()
	return world.direct_space_state.intersect_ray(query)

func _get_collision_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []
	if _attack_data == null:
		return exclusions

	var source := _attack_data.get_valid_source()
	if source != null:
		exclusions.append(source.get_rid())

	return exclusions

func _get_current_target_position() -> Vector3:
	if not is_instance_valid(_target) or _target._is_dead:
		return Vector3.INF

	return _target.global_position + Vector3.UP * 0.6

func _apply_impact_to(unit: Unit) -> void:
	if not is_instance_valid(unit) or unit._is_dead:
		return

	unit.receive_projectile_impact(_attack_data)
