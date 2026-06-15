extends Node3D

const SceneObjectPoolScript := preload("res://scripts/pooling/scene_object_pool.gd")
const PROJECTILE_SCENE := preload("res://scenes/projectiles/bullet_projectile.tscn")

class FakeAttackData:
	var has_resolved_aim: bool = false
	var aim_hits_target: bool = true
	var has_incendiary_trail: bool = true

	func get_valid_source():
		return null

var _failed := false

func _ready() -> void:
	var pool = SceneObjectPoolScript.new()
	add_child(pool)

	var projectile := pool.acquire(PROJECTILE_SCENE, self)
	projectile.setup_direction(FakeAttackData.new(), Vector3.FORWARD)
	_expect(projectile.get_node_or_null("IncendiaryTrail") != null, "test setup should create a transient projectile trail")
	projectile.set("_lifetime", projectile.max_lifetime)
	projectile.call("_process", 0.0)
	_expect(is_instance_valid(projectile), "expired pooled projectiles should not be freed")
	_expect(projectile.get_parent() == pool, "expired projectiles should return to their pool")

	var reused := pool.acquire(PROJECTILE_SCENE, self)
	_expect(reused == projectile, "weapon projectiles should reuse released instances")
	_expect(is_zero_approx(float(reused.get("_lifetime"))), "reused projectiles should reset lifetime")
	_expect(reused.get("_attack_data") == null, "reused projectiles should reset attack data")
	_expect(reused.get("_direct_direction") == Vector3.ZERO, "reused projectiles should reset direct direction")
	_expect(reused.get_node_or_null("IncendiaryTrail") == null, "reused projectiles should remove transient trails")

	pool.release(reused)
	await get_tree().process_frame
	if _failed:
		get_tree().quit(1)
	else:
		print("projectile_pooling_test: PASS")
		get_tree().quit(0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
