extends Node3D
class_name Projectile

@export var speed: float = 18.0
@export var hit_distance: float = 0.25

var _target: Unit
var _damage: int

func setup(target: Unit, damage: int) -> void:
	_target = target
	_damage = damage

func _process(delta: float) -> void:
	if !is_instance_valid(_target) or _target._is_dead:
		queue_free()
		return
	
	var target_position = _target.global_position + Vector3.UP * 0.6
	var to_target = target_position - global_position
	var distance = to_target.length()
	
	if distance <= hit_distance:
		_target.receive_damage(_damage)
		queue_free()
		return
	
	global_position += to_target.normalized() * minf(speed * delta, distance)
	look_at(target_position, Vector3.UP)
