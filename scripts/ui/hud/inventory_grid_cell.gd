extends PanelContainer

var inventory_panel: Control
var grid_id: StringName = &""
var cell_position: Vector2i = Vector2i.ZERO
var placement: Resource
var _hovered: bool = false

func _gui_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode != KEY_R:
		return

	if inventory_panel != null and is_instance_valid(inventory_panel) and inventory_panel.has_method("rotate_active_drag"):
		if inventory_panel.call("rotate_active_drag"):
			_update_drag_preview_from_panel()
			accept_event()
			return

	if _hovered and inventory_panel != null and is_instance_valid(inventory_panel) and placement != null:
		if inventory_panel.has_method("rotate_hovered_placement"):
			inventory_panel.call("rotate_hovered_placement", placement)
			accept_event()
			return

func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode != KEY_R:
		return

	if inventory_panel != null and is_instance_valid(inventory_panel) and inventory_panel.has_method("rotate_active_drag"):
		if inventory_panel.call("rotate_active_drag"):
			_update_drag_preview_from_panel()
			accept_event()
			return

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false

func _get_drag_data(_at_position: Vector2) -> Variant:
	if inventory_panel == null or placement == null:
		return null
	if not is_instance_valid(inventory_panel):
		return null
	if not inventory_panel.has_method("make_drag_data"):
		return null

	var drag_data: Dictionary = inventory_panel.call("make_drag_data", grid_id, cell_position, placement)
	if drag_data.is_empty():
		return null

	set_drag_preview(_make_drag_preview(drag_data))
	return drag_data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if inventory_panel == null or not is_instance_valid(inventory_panel):
		return false
	if not inventory_panel.has_method("can_drop_data_on_grid"):
		return false
	return inventory_panel.call("can_drop_data_on_grid", data, grid_id, cell_position)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if inventory_panel == null or not is_instance_valid(inventory_panel):
		return
	if inventory_panel.has_method("drop_data_on_grid"):
		inventory_panel.call("drop_data_on_grid", data, grid_id, cell_position)

func _update_drag_preview_from_panel() -> void:
	if inventory_panel == null or not is_instance_valid(inventory_panel):
		return
	if not inventory_panel.has_method("get_active_drag_data"):
		return
	var drag_data: Dictionary = inventory_panel.call("get_active_drag_data")
	if drag_data.is_empty():
		return
	set_drag_preview(_make_drag_preview(drag_data))

func _make_drag_preview(drag_data: Dictionary) -> Control:
	var preview := PanelContainer.new()
	var footprint: Vector2i = drag_data.get("footprint", Vector2i.ONE)
	var cell_size: Vector2 = drag_data.get("cell_size", Vector2(28, 28))
	var rotated := bool(drag_data.get("rotated", false))
	var grab_offset: Vector2i = drag_data.get("grab_offset", Vector2i.ZERO)
	if rotated:
		footprint = Vector2i(footprint.y, footprint.x)
	var preview_size := Vector2(
		maxf(cell_size.x, cell_size.x * float(footprint.x)),
		maxf(cell_size.y, cell_size.y * float(footprint.y))
	)
	preview.custom_minimum_size = preview_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.25, 0.22, 0.92)
	style.border_color = Color(0.7, 0.86, 0.72, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	preview.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = String(drag_data.get("display_name", "Item"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.92, 0.98, 0.92, 1.0))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(label)

	# Wrap in a transparent Control so the mouse cursor appears at the grab point
	var wrapper := Control.new()
	wrapper.custom_minimum_size = preview_size
	var offset := Vector2(float(grab_offset.x) * cell_size.x, float(grab_offset.y) * cell_size.y)
	preview.position = - offset
	wrapper.add_child(preview)
	return wrapper
