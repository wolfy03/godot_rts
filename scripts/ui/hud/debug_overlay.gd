extends Control
class_name DebugOverlay

const TEST_MODE_COMMAND := "TEST_MODE"
const GameTeamData := preload("res://scripts/team/game_team.gd")
const MissionAreaScript := preload("res://scripts/commander/mission_area.gd")

const COMMANDER_MODE_DISABLED := 0
const COMMANDER_MODE_ANNIHILATE := 1
const COMMANDER_MODE_GUARD_AREA := 2

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
var _mission_team_option: OptionButton
var _mission_mode_option: OptionButton
var _mission_position_label: Label
var _mission_radius_spin: SpinBox
var _is_picking_mission_position: bool = false
var _pending_mission_position: Vector3 = Vector3.INF

func _ready() -> void:
	add_to_group("command_panel_ui")
	set_process_unhandled_input(true)
	_build_console()
	_build_debug_panel()

func _unhandled_input(event: InputEvent) -> void:
	if _is_picking_mission_position and _handle_mission_position_pick(event):
		get_viewport().set_input_as_handled()
		return

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
	var effect := load(effect_path) as UnitEffect
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
	_debug_panel.custom_minimum_size = Vector2(340, 0)
	_debug_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_panel.offset_left = -356
	_debug_panel.offset_top = 48
	_debug_panel.offset_right = -16
	_debug_panel.offset_bottom = 470
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
	title.text = "Test Mode"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	_selected_label = Label.new()
	container.add_child(_selected_label)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(310, 260)
	container.add_child(tabs)

	var effects_tab := VBoxContainer.new()
	effects_tab.name = "Effects"
	effects_tab.add_theme_constant_override("separation", 6)
	tabs.add_child(effects_tab)
	_build_effects_tab(effects_tab)

	var mission_tab := VBoxContainer.new()
	mission_tab.name = "Mission Area"
	mission_tab.add_theme_constant_override("separation", 6)
	tabs.add_child(mission_tab)
	_build_mission_area_tab(mission_tab)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): _debug_panel.visible = false)
	container.add_child(close_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(_status_label)
	_update_selected_label()
	call_deferred("_sync_mission_area_fields")

func _build_effects_tab(container: VBoxContainer) -> void:
	for effect_data in EFFECTS:
		var button := Button.new()
		button.text = effect_data["label"]
		button.pressed.connect(_apply_effect_to_selected.bind(effect_data["path"], effect_data["label"]))
		container.add_child(button)

func _build_mission_area_tab(container: VBoxContainer) -> void:
	_mission_team_option = OptionButton.new()
	_mission_team_option.add_item("Player Team", GameTeamData.PLAYER)
	_mission_team_option.add_item("Enemy Team", GameTeamData.ENEMY)
	container.add_child(_with_label("Commander", _mission_team_option))

	_mission_mode_option = OptionButton.new()
	_mission_mode_option.add_item("Disabled", COMMANDER_MODE_DISABLED)
	_mission_mode_option.add_item("Annihilate", COMMANDER_MODE_ANNIHILATE)
	_mission_mode_option.add_item("Guard Area", COMMANDER_MODE_GUARD_AREA)
	_mission_mode_option.select(0)
	container.add_child(_with_label("Mode", _mission_mode_option))

	_mission_position_label = Label.new()
	_mission_position_label.text = "Position: not set"
	container.add_child(_mission_position_label)

	_mission_radius_spin = SpinBox.new()
	_mission_radius_spin.min_value = 1.0
	_mission_radius_spin.max_value = 40.0
	_mission_radius_spin.step = 0.5
	_mission_radius_spin.value = 8.0
	container.add_child(_with_label("Radius", _mission_radius_spin))

	var pick_button := Button.new()
	pick_button.text = "Pick Area Position"
	pick_button.pressed.connect(_begin_mission_position_pick)
	container.add_child(pick_button)

	var sync_button := Button.new()
	sync_button.text = "Sync From Area"
	sync_button.pressed.connect(_sync_mission_area_fields)
	container.add_child(sync_button)

	var apply_button := Button.new()
	apply_button.text = "Apply Commander"
	apply_button.pressed.connect(_apply_commander_settings)
	container.add_child(apply_button)

func _with_label(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(92, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _begin_mission_position_pick() -> void:
	_is_picking_mission_position = true
	_status_label.text = "Click the ground to set the mission area."

func _handle_mission_position_pick(event: InputEvent) -> bool:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return false
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if _is_pointer_over_debug_ui():
		return false

	var ground_position = _get_ground_mouse_position()
	if ground_position == null:
		_status_label.text = "No valid ground position under cursor."
		return true

	var mission_position := ground_position as Vector3
	_pending_mission_position = mission_position
	_update_mission_position_label(mission_position)
	_is_picking_mission_position = false
	_status_label.text = "Mission area position picked. Apply Commander to use it."
	return true

func _sync_mission_area_fields() -> void:
	if _mission_position_label == null:
		return

	var mission_area = _get_or_create_mission_area()
	_pending_mission_position = mission_area.global_position
	_update_mission_position_label(_pending_mission_position)
	_mission_radius_spin.value = mission_area.radius

func _apply_commander_settings() -> void:
	var team_id := _mission_team_option.get_selected_id()
	var mode := _mission_mode_option.get_selected_id()
	var mission_area = _get_or_create_mission_area()
	var mission_position := _pending_mission_position
	if mission_position == Vector3.INF:
		mission_position = mission_area.global_position
	var radius := float(_mission_radius_spin.value)
	mission_area.set_area(mission_position, radius)

	var applied_count := 0
	for node in get_tree().get_nodes_in_group("ai_commanders"):
		if int(node.get("team_id")) != team_id:
			continue
		node.set_mission_area(mission_position, radius)
		node.set_mode(mode)
		applied_count += 1

	_status_label.text = "Applied %s to %d commander(s)." % [_mission_mode_option.get_item_text(_mission_mode_option.selected), applied_count]

func _update_mission_position_label(mission_position: Vector3) -> void:
	if _mission_position_label == null:
		return

	_mission_position_label.text = "Position: %.1f, %.1f" % [mission_position.x, mission_position.z]

func _is_pointer_over_debug_ui() -> bool:
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

func _get_or_create_mission_area():
	var existing_area := get_tree().get_first_node_in_group("mission_areas")
	if existing_area != null:
		return existing_area

	var area = MissionAreaScript.new()
	area.name = "MissionArea"
	get_tree().current_scene.add_child(area)
	return area

func _update_selected_label() -> void:
	if _selected_label == null:
		return

	_selected_label.text = "Selected: %d" % _selected_units.size()
