extends Node

const GRENADE_SCENE := preload("res://scenes/skills/grenade_projectile.tscn")
const SceneObjectPoolScript := preload("res://scripts/pooling/scene_object_pool.gd")

class FakeCaster:
	extends Node3D

	func get_team_mask() -> int:
		return 2

class FakeSkill:
	extends Resource
	var cast_range: float = 8.0
	var radius: float = 2.0
	var damage: int = 0
	var heal_amount: int = 0
	var effect = null
	var affects_allies: bool = false
	var affects_enemies: bool = true

var _failed := false

func _ready() -> void:
	var pool = SceneObjectPoolScript.new()
	add_child(pool)
	var grenade := pool.acquire(GRENADE_SCENE, self)

	if not (grenade is RigidBody3D):
		_fail("Grenade projectile root must be a RigidBody3D so it can roll with physics before detonation.")

	if not grenade.has_method("setup"):
		_fail("Grenade projectile must keep the setup(caster, skill, target_position) entry point.")

	if not is_equal_approx(float(grenade.get("fuse_time")), 3.5):
		_fail("Grenade projectile fuse_time must default to 3.5 seconds.")

	var collision_shape := grenade.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		_fail("Grenade projectile must have a CollisionShape3D for physical rolling and blocking.")

	var caster := FakeCaster.new()
	add_child(caster)
	grenade.setup(caster, FakeSkill.new(), Vector3(3.0, 0.0, 0.0))
	grenade.set("_fuse_elapsed", 1.0)
	grenade.set("_detonated", true)
	grenade.linear_velocity = Vector3.ONE
	grenade.angular_velocity = Vector3.ONE
	pool.release(grenade)

	var reused := pool.acquire(GRENADE_SCENE, self)
	if reused != grenade:
		_fail("Grenade projectiles should reuse released instances.")
	if not is_zero_approx(float(reused.get("_fuse_elapsed"))):
		_fail("Reused grenades must reset fuse progress.")
	if bool(reused.get("_detonated")):
		_fail("Reused grenades must reset detonation state.")
	if reused.get("_caster_ref") != null or reused.get("_skill") != null:
		_fail("Reused grenades must clear caster and skill references.")
	if reused.linear_velocity != Vector3.ZERO or reused.angular_velocity != Vector3.ZERO:
		_fail("Reused grenades must reset physics velocities.")

	pool.release(reused)
	caster.queue_free()
	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("grenade_projectile_test: PASS")
		get_tree().quit(0)

func _fail(message: String) -> void:
	_failed = true
	push_error(message)
