extends PanelContainer
class_name PlayerQuickSlotPanel

const SLOT_KEYS: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

var _slot_labels: Array[Label] = []

func _ready() -> void:
	add_to_group("command_panel_ui")
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

func get_slot_count() -> int:
	return _slot_labels.size()

func get_slot_key_label(index: int) -> String:
	if index < 0 or index >= _slot_labels.size():
		return ""
	return _slot_labels[index].text

func _build_ui() -> void:
	add_theme_stylebox_override("panel", _make_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	for key_label in SLOT_KEYS:
		row.add_child(_make_slot(key_label))

func _make_slot(key_label: String) -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(48, 48)
	slot.add_theme_stylebox_override("panel", _make_slot_style())

	var label := Label.new()
	label.text = key_label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.86, 0.93, 0.9, 1.0))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.add_child(label)
	_slot_labels.append(label)
	return slot

func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.052, 0.057, 0.86)
	style.border_color = Color(0.36, 0.42, 0.44, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style

func _make_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.105, 0.115, 0.96)
	style.border_color = Color(0.34, 0.39, 0.41, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style
