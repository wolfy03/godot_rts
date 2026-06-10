extends Node

const BASE_ENEMY_SCENE := preload("res://scenes/units/base_units/base_enemy.tscn")

var _failed := false

func _ready() -> void:
	var enemy := BASE_ENEMY_SCENE.instantiate()
	add_child(enemy)
	await get_tree().process_frame

	if not enemy.has_method("has_overhead_health_bar"):
		_fail("AI units should expose an overhead health bar check.")
	elif not enemy.has_overhead_health_bar():
		_fail("AI units should create an overhead health bar.")
	elif not is_equal_approx(enemy.get_overhead_health_bar_percent(), 1.0):
		_fail("AI unit overhead health bar should start at 100 percent.")
	elif enemy.get_overhead_health_bar_sprite_count() != 1:
		_fail("AI unit overhead health bar should use one Sprite3D to avoid angle-dependent overlap flicker.")
	elif enemy.is_overhead_health_bar_top_level():
		_fail("AI unit overhead health bar should follow the unit as a local child instead of recalculating a top-level transform every frame.")

	enemy.receive_damage(25)
	if not is_equal_approx(enemy.get_overhead_health_bar_percent(), 0.75):
		_fail("AI unit overhead health bar should update to current health percent.")

	enemy.queue_free()
	await get_tree().process_frame
	if not _failed:
		print("unit_overhead_health_bar_test: PASS")
	get_tree().quit(1 if _failed else 0)

func _fail(message: String) -> void:
	_failed = true
	push_error(message)
