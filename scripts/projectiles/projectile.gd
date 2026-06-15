extends Node3D
class_name Projectile

const SceneObjectPoolScript := preload("res://scripts/pooling/scene_object_pool.gd")

@export var speed: float = 18.0
@export var hit_distance: float = 0.25
@export var max_lifetime: float = 4.0
@export_flags_3d_physics var obstacle_collision_mask: int = 1
@export_flags_3d_physics var unit_collision_mask: int = 6
@export var player_impact_debug_duration: float = 1.25

var _target = null
var _attack_data = null
var _miss_direction: Vector3 = Vector3.ZERO
var _direct_direction: Vector3 = Vector3.ZERO
var _lifetime: float = 0.0
var _incendiary_trail: GPUParticles3D

func on_pool_acquired() -> void:
	_reset_runtime_state()

func on_pool_released() -> void:
	_reset_runtime_state()

func setup(target, attack_data, miss_position: Vector3 = Vector3.INF) -> void:
	_target = target
	_attack_data = attack_data
	if _attack_data != null and _attack_data.has_incendiary_trail:
		_add_incendiary_trail()
	if _is_aimed_miss() and miss_position != Vector3.INF:
		_miss_direction = (miss_position - global_position).normalized()

func setup_direction(attack_data, direction: Vector3) -> void:
	_target = null
	_attack_data = attack_data
	_direct_direction = direction.normalized()
	if _attack_data != null and _attack_data.has_incendiary_trail:
		_add_incendiary_trail()

func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= max_lifetime:
		_release_to_pool()
		return

	if _is_aimed_miss():
		_process_miss(delta)
		return
	if _direct_direction != Vector3.ZERO:
		_process_direct(delta)
		return

	var target_position := _get_current_target_position()
	if target_position == Vector3.INF:
		_release_to_pool()
		return

	var to_target := target_position - global_position
	var distance := to_target.length()
	var next_position := global_position + to_target.normalized() * minf(speed * delta, distance)

	if _process_collision_between(global_position, next_position):
		return

	if distance <= hit_distance:
		_apply_impact_to(_target)
		_release_to_pool()
		return

	global_position = next_position
	if global_position.distance_squared_to(target_position) > 0.0001:
		look_at(target_position, Vector3.UP)

func _process_miss(delta: float) -> void:
	if _miss_direction == Vector3.ZERO:
		_release_to_pool()
		return

	var next_position := global_position + _miss_direction * speed * delta
	if _process_collision_between(global_position, next_position):
		return

	global_position = next_position
	look_at(global_position + _miss_direction, Vector3.UP)

func _process_direct(delta: float) -> void:
	var next_position := global_position + _direct_direction * speed * delta
	if _process_collision_between(global_position, next_position):
		return

	global_position = next_position
	look_at(global_position + _direct_direction, Vector3.UP)

func _is_aimed_miss() -> bool:
	return _attack_data != null and _attack_data.has_resolved_aim and not _attack_data.aim_hits_target

func _process_collision_between(from: Vector3, to: Vector3) -> bool:
	var collision := _get_collision_between(from, to)
	if collision.is_empty():
		return false

	var unit: Object = collision.get("collider")
	_spawn_player_impact_debug_marker(
		collision.get("position", to),
		collision.get("normal", Vector3.UP)
	)
	if unit != null:
		_apply_impact_to(unit)

	_release_to_pool()
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

	var source = _attack_data.get_valid_source()
	if source is CollisionObject3D:
		exclusions.append(source.get_rid())

	return exclusions

func _get_current_target_position() -> Vector3:
	if not _is_valid_unit_target(_target):
		return Vector3.INF
	if not (_target is Node3D):
		return Vector3.INF

	return _target.global_position + Vector3.UP * 0.6

func _apply_impact_to(unit) -> void:
	if not _is_valid_unit_target(unit):
		return
	if not unit.has_method("receive_projectile_impact"):
		return

	unit.receive_projectile_impact(_attack_data)

func _is_valid_unit_target(unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var is_dead = unit.get("_is_dead")
	if is_dead is bool:
		return not is_dead
	return unit.has_method("receive_projectile_impact")

func _spawn_player_impact_debug_marker(impact_position: Vector3, normal: Vector3 = Vector3.UP) -> void:
	if _attack_data == null:
		return
	var source = _attack_data.get_valid_source()
	if not _is_player_agent_source(source):
		return

	var marker := MeshInstance3D.new()
	marker.name = "PlayerImpactDebugMarker"
	var marker_normal := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := SphereMesh.new()
	mesh.radius = 0.14
	mesh.height = 0.28
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(1.0, 0.0, 0.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.0, 0.0, 1.0)
	material.emission_energy_multiplier = 2.5
	mesh.material = material
	marker.mesh = mesh

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	scene_root.add_child(marker)
	marker.global_position = impact_position + marker_normal * 0.08

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = player_impact_debug_duration
	timer.timeout.connect(marker.queue_free)
	marker.add_child(timer)
	timer.start()

func _is_player_agent_source(source) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if source.has_method("is_player_agent"):
		return source.is_player_agent()
	return source.is_in_group("player_agent") if source is Node else false

func _add_incendiary_trail() -> void:
	_remove_incendiary_trail()
	var particles := GPUParticles3D.new()
	particles.name = "IncendiaryTrail"
	particles.position = Vector3(0.0, 0.0, 0.18)
	particles.amount = 96
	particles.lifetime = 0.55
	particles.preprocess = 0.35
	particles.draw_passes = 1
	particles.local_coords = false
	particles.emitting = true
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(16.0, 16.0, 16.0))

	var particle_material := ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_material.emission_sphere_radius = 0.09
	particle_material.direction = Vector3(0.0, 0.0, 1.0)
	particle_material.spread = 38.0
	particle_material.initial_velocity_min = 0.6
	particle_material.initial_velocity_max = 2.2
	particle_material.angular_velocity_min = -90.0
	particle_material.angular_velocity_max = 90.0
	particle_material.gravity = Vector3(0.0, 0.15, 0.0)
	particle_material.damping_min = 0.15
	particle_material.damping_max = 0.35
	particle_material.scale_min = 0.08
	particle_material.scale_max = 0.18
	particle_material.color = Color(1.0, 0.46, 0.04, 0.95)
	particles.process_material = particle_material

	var draw_material := StandardMaterial3D.new()
	draw_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_material.albedo_color = Color(1.0, 0.34, 0.04, 0.9)
	draw_material.emission_enabled = true
	draw_material.emission = Color(1.0, 0.22, 0.02, 1.0)
	draw_material.emission_energy_multiplier = 3.0

	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.08
	particle_mesh.height = 0.16
	particle_mesh.material = draw_material
	particles.draw_pass_1 = particle_mesh
	add_child(particles)
	_incendiary_trail = particles

func _release_to_pool() -> void:
	SceneObjectPoolScript.release_instance(self)

func _reset_runtime_state() -> void:
	_target = null
	_attack_data = null
	_miss_direction = Vector3.ZERO
	_direct_direction = Vector3.ZERO
	_lifetime = 0.0
	_remove_incendiary_trail()

func _remove_incendiary_trail() -> void:
	if _incendiary_trail != null and is_instance_valid(_incendiary_trail):
		_incendiary_trail.free()
	_incendiary_trail = null
