extends Node

const COVER_SCENE := preload("res://scenes/units/cover.tscn")

var _failed := false

func _ready() -> void:
	var cover := COVER_SCENE.instantiate() as Cover
	add_child(cover)

	_expect_true(
		cover.is_protecting_against(Vector3(0.0, 0.0, 4.0), Vector3(0.0, 1.0, -0.85)),
		"front slot should be protected from the opposite side"
	)
	_expect_false(
		cover.is_protecting_against(Vector3(0.0, 0.0, -4.0), Vector3(0.0, 1.0, -0.85)),
		"front slot should not be protected from the same side"
	)
	_expect_false(
		cover.is_protecting_against(Vector3(4.0, 0.0, -0.85), Vector3(0.0, 1.0, -0.85)),
		"front slot should not be protected from the exposed side"
	)
	_expect_true(
		cover.is_protecting_against(Vector3(-4.0, 0.0, 0.0), Vector3(2.35, 1.0, 0.0)),
		"right slot should be protected from the opposite side"
	)
	_expect_false(
		cover.is_protecting_against(Vector3(2.35, 0.0, -4.0), Vector3(2.35, 1.0, 0.0)),
		"right slot should not be protected from its exposed front side"
	)
	_expect_false(
		cover.is_protecting_against(Vector3(2.35, 0.0, 4.0), Vector3(2.35, 1.0, 0.0)),
		"right slot should not be protected from its exposed rear side"
	)

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("cover_direction_test: PASS")
		get_tree().quit(0)

func _expect_true(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error("Expected true: %s" % message)

func _expect_false(value: bool, message: String) -> void:
	if value:
		_failed = true
		push_error("Expected false: %s" % message)
