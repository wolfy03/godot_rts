extends Node3D
class_name Cover

enum CoverGrade {
	LOW,
	MEDIUM,
	HIGH
}

@export var grade: CoverGrade = CoverGrade.MEDIUM
@export var cover_padding: float = 0.35

func _ready():
	add_to_group("covers")

func get_cover_position(from_position: Vector3, agent_radius: float) -> Vector3:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var box := collision_shape.shape as BoxShape3D if collision_shape else null
	var padding := agent_radius + cover_padding
	
	if box == null:
		var direction := from_position - global_position
		direction.y = 0.0
		if direction.length_squared() < 0.001:
			direction = -global_transform.basis.z
		return global_position + direction.normalized() * padding
	
	var local_from := to_local(from_position)
	var half_size := box.size * 0.5
	var local_target := Vector3.ZERO
	
	if half_size.x <= 0.0 or absf(local_from.z / maxf(half_size.z, 0.001)) >= absf(local_from.x / maxf(half_size.x, 0.001)):
		local_target.x = clampf(local_from.x, -half_size.x, half_size.x)
		local_target.z = signf(local_from.z) * (half_size.z + padding)
	else:
		local_target.x = signf(local_from.x) * (half_size.x + padding)
		local_target.z = clampf(local_from.z, -half_size.z, half_size.z)
	
	if absf(local_target.x) < 0.001 and absf(local_target.z) < 0.001:
		local_target.z = half_size.z + padding
	
	var cover_position := to_global(local_target)
	cover_position.y = from_position.y
	return cover_position
