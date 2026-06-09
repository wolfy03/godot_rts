extends Node3D

const PROJECTILE_SCENE := preload("res://scenes/projectiles/bullet_projectile.tscn")

class FakePlayerSource:
	extends Node3D

	func is_player_agent() -> bool:
		return true

class FakeAttackData:
	extends RefCounted

	var has_incendiary_trail: bool = false
	var source: Object

	func _init(attack_source: Object) -> void:
		source = attack_source

	func get_valid_source() -> Object:
		return source

var _failed := false

func _ready() -> void:
	var source := FakePlayerSource.new()
	add_child(source)

	var projectile := PROJECTILE_SCENE.instantiate()
	add_child(projectile)
	projectile.setup_direction(FakeAttackData.new(source), Vector3.FORWARD)

	var impact_position := Vector3(2.0, 1.0, -3.0)
	var impact_normal := Vector3.UP
	projectile._spawn_player_impact_debug_marker(impact_position, impact_normal)

	var marker := get_node_or_null("PlayerImpactDebugMarker") as MeshInstance3D
	if marker == null:
		_fail("Player impact debug marker should be added to the current scene.")
	else:
		var expected_position := impact_position + impact_normal * 0.08
		if marker.global_position.distance_to(expected_position) > 0.001:
			_fail("Player impact debug marker should keep the requested world position after entering the tree.")

	projectile.queue_free()
	source.queue_free()
	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("projectile_impact_debug_marker_test: PASS")
		get_tree().quit(0)

func _fail(message: String) -> void:
	_failed = true
	push_error(message)
