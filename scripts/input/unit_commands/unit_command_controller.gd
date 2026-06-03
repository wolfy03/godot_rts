extends Node
class_name UnitCommandController

const COMMAND_NONE := ""
const COMMAND_MOVE := "move"
const COMMAND_ATTACK := "attack"
const COMMAND_SKILL_PREFIX := "skill:"
const UnitMoveOrderCommandScript := preload("res://scripts/input/unit_commands/unit_move_order_command.gd")
const UnitAttackTargetCommandScript := preload("res://scripts/input/unit_commands/unit_attack_target_command.gd")
const UnitStopCommandScript := preload("res://scripts/input/unit_commands/unit_stop_command.gd")
const UnitHoldPositionCommandScript := preload("res://scripts/input/unit_commands/unit_hold_position_command.gd")
const UnitSkillCommandScript := preload("res://scripts/input/unit_commands/unit_skill_command.gd")
const UnitCommandPreviewScript := preload("res://scripts/input/unit_commands/unit_command_preview.gd")
const UNIT_COLLISION_MASK := 0b110
const ENEMY_UNIT_COLLISION_MASK := 0b100
const MOUSE_RAY_LENGTH := 1000.0
const ACTION_UNIT_MOVE := "Unit Move Command"
const ACTION_UNIT_ATTACK := "Unit Attack Command"
const ACTION_UNIT_HOLD_POSITION := "Unit Hold Position Command"

signal command_targeting_changed(command_id: String)

@export var move_command_handle_scene: PackedScene

var _selected_units: Dictionary = {}
var _pending_command_id: String = COMMAND_NONE
var _move_order_command := UnitMoveOrderCommandScript.new()
var _attack_target_command := UnitAttackTargetCommandScript.new()
var _stop_command := UnitStopCommandScript.new()
var _hold_position_command := UnitHoldPositionCommandScript.new()
var _skill_command := UnitSkillCommandScript.new()
var _skill_preview

func _ready() -> void:
	_skill_preview = UnitCommandPreviewScript.new()
	add_child(_skill_preview)
	set_process(false)

func unit_selection_changed(selected_units: Dictionary) -> void:
	_selected_units = selected_units
	if _selected_units.is_empty():
		_set_pending_command(COMMAND_NONE)

func _process(_delta: float) -> void:
	_update_pending_skill_preview()

func _input(event: InputEvent) -> void:
	if _is_pointer_over_command_panel(event):
		return

	if _selected_units.is_empty():
		return

	if Input.is_action_just_pressed(ACTION_UNIT_MOVE):
		_set_pending_command(COMMAND_NONE)
		var target_unit := _get_enemy_unit_under_mouse()
		if target_unit:
			_issue_attack_target_command(target_unit)
		else:
			_issue_command(false)
	elif _pending_command_id != COMMAND_NONE and _is_left_mouse_button_pressed(event):
		if _is_pending_skill_command():
			_issue_skill_command(_get_pending_skill_id())
		else:
			var target_unit := _get_enemy_unit_under_mouse()
			if target_unit:
				_issue_attack_target_command(target_unit)
			else:
				_issue_command(_pending_command_id == COMMAND_ATTACK)
		_set_pending_command(COMMAND_NONE)
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed(ACTION_UNIT_ATTACK):
		begin_attack_command()
	elif Input.is_action_just_pressed(ACTION_UNIT_HOLD_POSITION):
		issue_hold_position_command()

func begin_move_command() -> void:
	_toggle_pending_command(COMMAND_MOVE)

func begin_attack_command() -> void:
	_toggle_pending_command(COMMAND_ATTACK)

func begin_skill_command(skill_id: StringName) -> void:
	if _is_toggle_skill(skill_id):
		_set_pending_command(COMMAND_NONE)
		_skill_command.issue(_selected_units, skill_id, null, null)
		command_targeting_changed.emit(_pending_command_id)
		return
	_toggle_pending_command(_get_skill_command_id(skill_id))

func issue_stop_command() -> void:
	_set_pending_command(COMMAND_NONE)
	_stop_command.issue(_selected_units)

func issue_hold_position_command() -> void:
	_set_pending_command(COMMAND_NONE)
	_hold_position_command.issue(_selected_units)

func _issue_command(attack_move: bool) -> void:
	var click_position = _get_ground_mouse_position()
	if click_position == null:
		return

	_move_order_command.issue(self, move_command_handle_scene, _selected_units, click_position, attack_move)

func _issue_attack_target_command(target_unit: Unit) -> void:
	_attack_target_command.issue(self, _selected_units, target_unit)

func _issue_skill_command(skill_id: StringName) -> void:
	var click_position = _get_ground_mouse_position()
	var target_unit := _get_unit_under_mouse(UNIT_COLLISION_MASK)
	_skill_command.issue(_selected_units, skill_id, target_unit, click_position)

func _toggle_pending_command(command_id: String) -> void:
	if _pending_command_id == command_id:
		_set_pending_command(COMMAND_NONE)
	else:
		_set_pending_command(command_id)

func _set_pending_command(command_id: String) -> void:
	if _pending_command_id == command_id:
		return

	_pending_command_id = command_id
	var preview_enabled := _is_pending_skill_command()
	set_process(preview_enabled)
	if preview_enabled:
		_update_pending_skill_preview()
	else:
		_skill_preview.hide_preview()
	command_targeting_changed.emit(_pending_command_id)

func _is_pending_skill_command() -> bool:
	return _pending_command_id.begins_with(COMMAND_SKILL_PREFIX)

func _get_pending_skill_id() -> StringName:
	if not _is_pending_skill_command():
		return &""
	return StringName(_pending_command_id.substr(COMMAND_SKILL_PREFIX.length()))

func _get_skill_command_id(skill_id: StringName) -> String:
	return COMMAND_SKILL_PREFIX + String(skill_id)

func _is_toggle_skill(skill_id: StringName) -> bool:
	for selected_unit in _selected_units.values():
		var unit := selected_unit as Unit
		if unit == null or not is_instance_valid(unit):
			continue
		var skill := unit.get_skill(skill_id)
		if skill != null and skill.is_toggle():
			return true
	return false

func _update_pending_skill_preview() -> void:
	if not _is_pending_skill_command():
		_skill_preview.hide_preview()
		return

	_skill_preview.update_preview(_selected_units, _get_pending_skill_id(), _get_ground_mouse_position())

func _is_left_mouse_button_pressed(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false

	var mouse_button_event := event as InputEventMouseButton
	return mouse_button_event.button_index == MOUSE_BUTTON_LEFT and mouse_button_event.pressed

func _is_pointer_over_command_panel(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return false

	var hovered_control := get_viewport().gui_get_hovered_control()
	while hovered_control != null:
		if hovered_control.is_in_group("command_panel_ui"):
			return true
		hovered_control = hovered_control.get_parent() as Control

	return false

func _get_ground_mouse_position() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)

	if is_zero_approx(ray_direction.y):
		return null

	var distance := -ray_origin.y / ray_direction.y
	if distance < 0.0:
		return null

	return ray_origin + ray_direction * distance

func _get_enemy_unit_under_mouse() -> Unit:
	return _get_unit_under_mouse(ENEMY_UNIT_COLLISION_MASK)

func _get_unit_under_mouse(collision_mask: int) -> Unit:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_pos) * MOUSE_RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider := result.get("collider") as Unit
	if collider == null or not is_instance_valid(collider):
		return null

	return collider
