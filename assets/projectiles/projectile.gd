extends Node3D
class_name Projectile

@export var speed: float = 18.0
@export var hit_distance: float = 0.25

var _target: Unit
var _damage: int
var _will_hit: bool = true
var _impact_position: Vector3 = Vector3.INF

func setup(target: Unit, damage: int, will_hit: bool = true, impact_position: Vector3 = Vector3.INF) -> void:
	_target = target
	_damage = damage
	_will_hit = will_hit
	_impact_position = impact_position

func _process(delta: float) -> void:
	if _will_hit and (!is_instance_valid(_target) or _target._is_dead):
		queue_free()
		return
	
	var target_position := _impact_position
	if _will_hit:
		target_position = _target.global_position + Vector3.UP * 0.6
	elif target_position == Vector3.INF:
		queue_free()
		return
	
	var to_target = target_position - global_position
	var distance = to_target.length()
	
	if distance <= hit_distance:
		if _will_hit and is_instance_valid(_target) and not _target._is_dead:
			if _target.try_evade_projectile_attack():
				queue_free()
				return
			
			_target.receive_damage(_damage)
		queue_free()
		return
	
	global_position += to_target.normalized() * minf(speed * delta, distance)
	if global_position.distance_squared_to(target_position) > 0.0001:
		look_at(target_position, Vector3.UP)
