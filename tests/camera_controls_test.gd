extends Node

const CAMERA_CONTROLS_SCRIPT := preload("res://scripts/input/camera_controls.gd")

var _failed := false

func _ready() -> void:
	var camera := Camera3D.new()
	camera.set_script(CAMERA_CONTROLS_SCRIPT)
	add_child(camera)

	camera.min_zoom_distance = 6.0
	camera.max_zoom_distance = 20.0
	camera.zoom_step = 4.0
	camera.set_focus_position(Vector3.ZERO)
	camera.set_zoom_distance(10.0)
	camera.adjust_zoom(1.0)
	_expect_float(camera.get_zoom_distance(), 6.0, "wheel up should zoom in by reducing camera distance")
	camera.adjust_zoom(-10.0)
	_expect_float(camera.get_zoom_distance(), 20.0, "wheel down should zoom out without exceeding max distance")

	camera.min_pitch_degrees = 25.0
	camera.max_pitch_degrees = 70.0
	camera.set_pitch_degrees(45.0)
	camera.rotate_orbit(Vector2(0.0, -10000.0))
	_expect_float(camera.get_pitch_degrees(), 70.0, "orbit drag should clamp upward pitch")
	camera.rotate_orbit(Vector2(0.0, 10000.0))
	_expect_float(camera.get_pitch_degrees(), 25.0, "orbit drag should clamp downward pitch")

	camera.max_pitch_degrees = 90.0
	camera.set_pitch_degrees(90.0)
	_expect_float(camera.get_pitch_degrees(), 89.0, "pitch should stay below vertical look_at colinearity")

	camera.follow_margin = 3.0
	var next_focus: Vector3 = camera.get_focus_for_follow_target(Vector3.ZERO, Vector3(10.0, 1.0, 0.0))
	_expect_vector3(next_focus, Vector3(7.0, 1.0, 0.0), "follow target should keep configured margin")
	next_focus = camera.get_focus_for_follow_target(Vector3.ZERO, Vector3(2.0, 1.0, 0.0))
	_expect_vector3(next_focus, Vector3(0.0, 1.0, 0.0), "follow target inside margin should not pull xz focus")

	camera.set_yaw_radians(0.0)
	camera.set_manual_camera_control_cooldown(0.0)
	camera.auto_rotation_smooth_speed = 100.0
	camera.rotate_towards_follow_movement(Vector3(1.0, 0.0, 0.0), 1.0)
	_expect_float(camera.get_yaw_radians(), -PI * 0.5, "camera should rotate behind positive x movement")

	camera.set_yaw_radians(0.0)
	camera.set_manual_camera_control_cooldown(0.5)
	camera.rotate_towards_follow_movement(Vector3(1.0, 0.0, 0.0), 1.0)
	_expect_float(camera.get_yaw_radians(), 0.0, "manual camera control cooldown should suppress auto rotation")

	camera.queue_free()
	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("camera_controls_test: PASS")
		get_tree().quit(0)

func _expect_float(value: float, expected: float, message: String) -> void:
	if not is_equal_approx(value, expected):
		_failed = true
		push_error("%s. Expected %s, got %s." % [message, expected, value])

func _expect_vector3(value: Vector3, expected: Vector3, message: String) -> void:
	if not value.is_equal_approx(expected):
		_failed = true
		push_error("%s. Expected %s, got %s." % [message, expected, value])
