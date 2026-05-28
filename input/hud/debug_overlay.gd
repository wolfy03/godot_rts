extends Control
class_name DebugOverlay

const TEST_MODE_COMMAND := "TEST_MODE"

const EFFECTS := [
	{
		"label": "Buff Damage",
		"path": "res://assets/effects/attack_damage_buff.tres",
	},
	{
		"label": "Buff Heal",
		"path": "res://assets/effects/health_recovery_buff.tres",
	},
	{
		"label": "Buff Range",
		"path": "res://assets/effects/attack_range_buff.tres",
	},
	{
		"label": "Poison",
		"path": "res://assets/effects/poison_debuff.tres",
	},
	{
		"label": "Smoke",
		"path": "res://assets/effects/smoke_debuff.tres",
	},
]

var _selected_units: Dictionary = {}
var _console_panel: PanelContainer
var _console_input: LineEdit
var _debug_panel: PanelContainer
var _selected_label: Label
var _status_label: Label

func _ready() -> void:
	add_to_group("command_panel_ui")
	set_process_unhandled_input(true)
	_build_console()
	_build_debug_panel()

func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	
	if key_event.keycode == KEY_QUOTELEFT or key_event.physical_keycode == KEY_QUOTELEFT:
		_toggle_console()
		get_viewport().set_input_as_handled()

func unit_selection_changed(selected_units: Dictionary) -> void:
	_selected_units = selected_units
	_update_selected_label()

func _toggle_console() -> void:
	_console_panel.visible = not _console_panel.visible
	if _console_panel.visible:
		_console_input.text = ""
		_console_input.grab_focus()
	else:
		_console_input.release_focus()

func _submit_console_command(command: String) -> void:
	var normalized_command := command.strip_edges().to_upper()
	_console_input.text = ""
	
	if normalized_command == TEST_MODE_COMMAND:
		_debug_panel.visible = true
		_console_panel.visible = false
		_console_input.release_focus()
		_status_label.text = "TEST_MODE enabled."
	else:
		_status_label.text = "Unknown command: %s" % command

func _apply_effect_to_selected(effect_path: String, label: String) -> void:
	var effect := load(effect_path) as Resource
	if effect == null:
		_status_label.text = "Failed to load %s." % effect_path
		return
	
	var applied_count := 0
	for unit in _selected_units.values():
		if not is_instance_valid(unit):
			continue
		
		unit.apply_effect(effect)
		applied_count += 1
	
	_status_label.text = "%s applied to %d unit(s)." % [label, applied_count]

func _build_console() -> void:
	_console_panel = PanelContainer.new()
	_console_panel.visible = false
	_console_panel.custom_minimum_size = Vector2(420, 42)
	_console_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_console_panel.offset_left = 16
	_console_panel.offset_top = 16
	_console_panel.offset_right = 436
	_console_panel.offset_bottom = 58
	add_child(_console_panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	_console_panel.add_child(margin)
	
	_console_input = LineEdit.new()
	_console_input.placeholder_text = "Enter command"
	_console_input.text_submitted.connect(_submit_console_command)
	margin.add_child(_console_input)

func _build_debug_panel() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.visible = false
	_debug_panel.custom_minimum_size = Vector2(260, 0)
	_debug_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_panel.offset_left = -276
	_debug_panel.offset_top = 48
	_debug_panel.offset_right = -16
	_debug_panel.offset_bottom = 330
	add_child(_debug_panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_debug_panel.add_child(margin)
	
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	margin.add_child(container)
	
	var title := Label.new()
	title.text = "Debug Effects"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)
	
	_selected_label = Label.new()
	container.add_child(_selected_label)
	
	for effect_data in EFFECTS:
		var button := Button.new()
		button.text = effect_data["label"]
		button.pressed.connect(_apply_effect_to_selected.bind(effect_data["path"], effect_data["label"]))
		container.add_child(button)
	
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): _debug_panel.visible = false)
	container.add_child(close_button)
	
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(_status_label)
	_update_selected_label()

func _update_selected_label() -> void:
	if _selected_label == null:
		return
	
	_selected_label.text = "Selected: %d" % _selected_units.size()
