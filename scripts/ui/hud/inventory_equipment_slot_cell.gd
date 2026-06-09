extends PanelContainer

var inventory_panel: Control
var slot_id: StringName = &""

func _get_drag_data(_at_position: Vector2) -> Variant:
	if inventory_panel == null or not is_instance_valid(inventory_panel):
		return null
	if not inventory_panel.has_method("make_equipment_drag_data"):
		return null

	var drag_data: Dictionary = inventory_panel.call("make_equipment_drag_data", slot_id)
	if drag_data.is_empty():
		return null

	set_drag_preview(_make_drag_preview(drag_data))
	return drag_data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if inventory_panel == null or not is_instance_valid(inventory_panel):
		return false
	if not inventory_panel.has_method("can_drop_data_on_equipment_slot"):
		return false
	return inventory_panel.call("can_drop_data_on_equipment_slot", data, slot_id)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if inventory_panel == null or not is_instance_valid(inventory_panel):
		return
	if inventory_panel.has_method("drop_data_on_equipment_slot"):
		inventory_panel.call("drop_data_on_equipment_slot", data, slot_id)

func _make_drag_preview(drag_data: Dictionary) -> Control:
	var preview := PanelContainer.new()
	var footprint: Vector2i = drag_data.get("footprint", Vector2i.ONE)
	var cell_size: Vector2 = drag_data.get("cell_size", Vector2(28, 28))
	var rotated := bool(drag_data.get("rotated", false))
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
	return preview
