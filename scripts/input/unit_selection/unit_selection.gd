extends Control

class_name UnitSelection

const MAX_UNIT_SELECTION_COUNT = 300
const CLICK_SELECT_RADIUS = 18.0
const DRAG_SELECT_THRESHOLD = 4.0
const SELECT_UNIT_ACTION := "Select Units"
const KEEP_UNITS_SELECTED_ACTION := "Keep Units Selected"

signal unit_selection_changed(selected_units: Dictionary)

var dragging: bool = false
var start_position: Vector2 = Vector2.ZERO
var end_position: Vector2 = Vector2.ZERO

var _selected_units: Dictionary = {}
var _command_targeting_active: bool = false

func _input(event: InputEvent) -> void:
	if _command_targeting_active:
		return

	if Input.is_action_just_pressed(SELECT_UNIT_ACTION):
		if _is_pointer_over_command_panel(event):
			return
		_start_selection()
	elif dragging and Input.is_action_pressed(SELECT_UNIT_ACTION):
		end_position = _get_mouse_position()
		_select_units_in_rect()
		queue_redraw()
	elif dragging and Input.is_action_just_released(SELECT_UNIT_ACTION):
		end_position = _get_mouse_position()
		_select_units_in_rect()
		dragging = false
		queue_redraw()

func command_targeting_changed(command_id: String) -> void:
	_command_targeting_active = not command_id.is_empty()
	if _command_targeting_active:
		dragging = false
		queue_redraw()

func _draw() -> void:
	if dragging:
		_draw_selection_box()

func _start_selection() -> void:
	start_position = _get_mouse_position()
	end_position = start_position

	if not Input.is_action_pressed(KEEP_UNITS_SELECTED_ACTION):
		_clear_selected_units()
		_emit_unit_selection_changed()

	dragging = true
	queue_redraw()

func _clear_selected_units() -> void:
	for unit: Unit in _selected_units.values():
		unit.on_selection_changed(false)

	_selected_units.clear()

func _emit_unit_selection_changed() -> void:
	unit_selection_changed.emit(_selected_units)

func _is_pointer_over_command_panel(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return false

	var hovered_control := get_viewport().gui_get_hovered_control()
	while hovered_control != null:
		if hovered_control.is_in_group("command_panel_ui"):
			return true
		hovered_control = hovered_control.get_parent() as Control

	return false

func _draw_selection_box() -> void:
	var rect := Rect2(start_position, end_position - start_position).abs()
	draw_rect(rect, Color.GREEN, false, 2)

func _select_units_in_rect() -> void:
	if not Input.is_action_pressed(KEEP_UNITS_SELECTED_ACTION):
		_clear_selected_units()

	var selection_rect := Rect2(start_position, end_position - start_position).abs()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	for node in get_tree().get_nodes_in_group("selectable_units"):
		var unit := node as Unit
		if unit == null or camera.is_position_behind(unit.global_position):
			continue

		var screen_position := camera.unproject_position(unit.global_position)
		if not _is_screen_position_selected(selection_rect, screen_position):
			continue

		if _selected_units.size() >= MAX_UNIT_SELECTION_COUNT and not _selected_units.has(unit.get_instance_id()):
			break

		_select_unit(unit)

	_emit_unit_selection_changed()

func _select_unit(unit: Unit) -> void:
	var unit_id := unit.get_instance_id()
	if _selected_units.has(unit_id):
		return

	_selected_units[unit_id] = unit

	var remove_dead_unit := _remove_dead_unit.bind(unit)
	if not unit.tree_exiting.is_connected(remove_dead_unit):
		unit.tree_exiting.connect(remove_dead_unit)

	unit.on_selection_changed(true)

func _is_screen_position_selected(selection_rect: Rect2, screen_position: Vector2) -> bool:
	var drag_distance := start_position.distance_to(end_position)
	if drag_distance > DRAG_SELECT_THRESHOLD:
		return selection_rect.has_point(screen_position)

	return screen_position.distance_to(end_position) <= CLICK_SELECT_RADIUS

func _get_mouse_position() -> Vector2:
	return get_viewport().get_mouse_position()

func _remove_dead_unit(unit: Unit) -> void:
	_selected_units.erase(unit.get_instance_id())
	_emit_unit_selection_changed()
