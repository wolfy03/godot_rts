extends Node

const GRENADE_SCENE := preload("res://scenes/skills/grenade_projectile.tscn")

var _failed := false

func _ready() -> void:
	var grenade := GRENADE_SCENE.instantiate()
	add_child(grenade)

	if not (grenade is RigidBody3D):
		_fail("Grenade projectile root must be a RigidBody3D so it can roll with physics before detonation.")

	if not grenade.has_method("setup"):
		_fail("Grenade projectile must keep the setup(caster, skill, target_position) entry point.")

	if not is_equal_approx(float(grenade.get("fuse_time")), 3.5):
		_fail("Grenade projectile fuse_time must default to 3.5 seconds.")

	var collision_shape := grenade.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		_fail("Grenade projectile must have a CollisionShape3D for physical rolling and blocking.")

	grenade.queue_free()
	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("grenade_projectile_test: PASS")
		get_tree().quit(0)

func _fail(message: String) -> void:
	_failed = true
	push_error(message)
