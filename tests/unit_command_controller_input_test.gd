extends Node

const UnitCommandControllerScript := preload("res://scripts/input/unit_commands/unit_command_controller.gd")

var _failed := false

func _ready() -> void:
	var controller := UnitCommandControllerScript.new()
	add_child(controller)

	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false

	_expect(controller._is_move_command_event(right_release), "right mouse release should issue a move command")

	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true

	_expect(not controller._is_move_command_event(right_press), "raw right mouse press should not duplicate release based move commands")

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("unit_command_controller_input_test: PASS")
		get_tree().quit(0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
