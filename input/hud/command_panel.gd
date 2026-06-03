extends PanelContainer
class_name CommandPanel

const COMMAND_NONE := ""
const COMMAND_MOVE := "move"
const COMMAND_ATTACK := "attack"
const COMMAND_SKILL_PREFIX := "skill:"
const SKILL_BUTTON_COUNT := 4
const SKILL_COOLDOWN_REFRESH_INTERVAL := 0.1

signal move_command_requested
signal attack_command_requested
signal stop_command_requested
signal hold_position_command_requested
signal skill_command_requested(skill_id: StringName)

@onready var _selection_label: Label = %SelectionLabel
@onready var _move_button: Button = %MoveButton
@onready var _attack_button: Button = %AttackButton
@onready var _stop_button: Button = %StopButton
@onready var _hold_button: Button = %HoldButton

var _selected_units: Dictionary = {}
var _shown_skills: Array[UnitSkill] = []
var _skill_buttons: Array[Button] = []
var _skill_cooldown_labels: Array[Label] = []
var _primary_skill_unit: Unit = null
var _cooldown_refresh_timer: Timer

func _ready() -> void:
	add_to_group("command_panel_ui")
	visible = false
	_setup_cooldown_refresh_timer()

	_move_button.toggle_mode = true
	_attack_button.toggle_mode = true
	_setup_skill_buttons()

	_move_button.pressed.connect(func(): move_command_requested.emit())
	_attack_button.pressed.connect(func(): attack_command_requested.emit())
	_stop_button.pressed.connect(func(): stop_command_requested.emit())
	_hold_button.pressed.connect(func(): hold_position_command_requested.emit())

func unit_selection_changed(selected_units: Dictionary) -> void:
	_selected_units = selected_units
	var selected_count := selected_units.size()
	visible = selected_count > 0
	_selection_label.text = "선택 유닛 %d" % selected_count
	_update_skill_buttons()
	_update_cooldown_refresh_timer()

	if selected_count == 0:
		command_targeting_changed(COMMAND_NONE)

func command_targeting_changed(command_id: String) -> void:
	_move_button.button_pressed = command_id == COMMAND_MOVE
	_attack_button.button_pressed = command_id == COMMAND_ATTACK
	for index in _skill_buttons.size():
		var button := _skill_buttons[index]
		var skill: UnitSkill = _shown_skills[index] if index < _shown_skills.size() else null
		if skill == null:
			button.button_pressed = false
		elif skill.is_toggle():
			button.button_pressed = _is_skill_toggled(skill.id)
		else:
			button.button_pressed = command_id == _get_skill_command_id(skill.id)

func _setup_cooldown_refresh_timer() -> void:
	_cooldown_refresh_timer = Timer.new()
	_cooldown_refresh_timer.wait_time = SKILL_COOLDOWN_REFRESH_INTERVAL
	_cooldown_refresh_timer.timeout.connect(_refresh_skill_button_states)
	add_child(_cooldown_refresh_timer)

func _update_cooldown_refresh_timer() -> void:
	if visible and _has_refreshable_skill():
		if _cooldown_refresh_timer.is_stopped():
			_cooldown_refresh_timer.start()
	else:
		_cooldown_refresh_timer.stop()

func _has_refreshable_skill() -> bool:
	for skill in _shown_skills:
		if skill != null and (skill.cooldown > 0.0 or skill.is_toggle()):
			return true
	return false

func _setup_skill_buttons() -> void:
	var command_grid := _move_button.get_parent() as GridContainer
	if command_grid == null:
		return

	var children := command_grid.get_children()
	if children.size() < SKILL_BUTTON_COUNT:
		return

	var start_index := maxi(0, children.size() - SKILL_BUTTON_COUNT)
	for index in SKILL_BUTTON_COUNT:
		var old_slot := children[start_index + index] as Control
		var button := Button.new()
		button.custom_minimum_size = Vector2(94, 46)
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.disabled = true
		button.add_theme_color_override("font_color", _move_button.get_theme_color("font_color"))
		button.add_theme_font_size_override("font_size", 12)
		_copy_button_style(_move_button, button, "normal")
		_copy_button_style(_move_button, button, "pressed")
		_copy_button_style(_move_button, button, "hover")
		_copy_button_style(_move_button, button, "disabled")
		button.pressed.connect(_on_skill_button_pressed.bind(index))

		var cooldown_label := _make_cooldown_label()
		button.add_child(cooldown_label)

		command_grid.add_child(button)
		command_grid.move_child(button, start_index + index)
		if old_slot != null:
			old_slot.queue_free()
		_skill_buttons.append(button)
		_skill_cooldown_labels.append(cooldown_label)

func _make_cooldown_label() -> Label:
	var label := Label.new()
	label.visible = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.offset_left = -26.0
	label.offset_top = 2.0
	label.offset_right = -4.0
	label.offset_bottom = 18.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.54, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	return label

func _copy_button_style(source: Button, target: Button, style_name: String) -> void:
	var style := source.get_theme_stylebox(style_name)
	if style != null:
		target.add_theme_stylebox_override(style_name, style)

func _update_skill_buttons() -> void:
	_primary_skill_unit = _get_first_selected_unit()
	_shown_skills = _get_first_selected_active_skills()
	for index in _skill_buttons.size():
		var button := _skill_buttons[index]
		var skill: UnitSkill = _shown_skills[index] if index < _shown_skills.size() else null
		if skill == null:
			button.text = ""
			button.tooltip_text = ""
			button.disabled = true
			button.button_pressed = false
			_set_cooldown_label(index, 0.0)
			_set_skill_ready_highlight(button, false)
			continue

		button.text = skill.display_name
		button.tooltip_text = skill.description
		button.disabled = false
		button.button_pressed = _is_skill_toggled(skill.id) if skill.is_toggle() else false

	_refresh_skill_button_states()

func _refresh_skill_button_states() -> void:
	for index in _skill_buttons.size():
		var button := _skill_buttons[index]
		var skill: UnitSkill = _shown_skills[index] if index < _shown_skills.size() else null
		if skill == null:
			_set_cooldown_label(index, 0.0)
			_set_skill_ready_highlight(button, false)
			continue

		var cooldown_remaining := _get_skill_cooldown_remaining(skill.id)
		var is_on_cooldown := cooldown_remaining > 0.0
		button.disabled = is_on_cooldown
		button.button_pressed = _is_skill_toggled(skill.id) if skill.is_toggle() else button.button_pressed
		_set_cooldown_label(index, cooldown_remaining)
		_set_skill_ready_highlight(button, skill.cooldown > 0.0 and not is_on_cooldown)

func _set_cooldown_label(index: int, remaining: float) -> void:
	if index < 0 or index >= _skill_cooldown_labels.size():
		return

	var label := _skill_cooldown_labels[index]
	label.visible = remaining > 0.0
	if label.visible:
		label.text = str(ceili(remaining))

func _set_skill_ready_highlight(button: Button, enabled: bool) -> void:
	if enabled:
		var ready_style: StyleBoxFlat = button.get_meta("ready_style") as StyleBoxFlat if button.has_meta("ready_style") else null
		if ready_style == null:
			var base_style := _move_button.get_theme_stylebox("normal")
			ready_style = base_style.duplicate() as StyleBoxFlat if base_style is StyleBoxFlat else StyleBoxFlat.new()
			ready_style.bg_color = Color(0.19, 0.22, 0.13, 1.0)
			ready_style.border_color = Color(0.94, 0.78, 0.32, 1.0)
			ready_style.set_border_width_all(2)
			button.set_meta("ready_style", ready_style)
		button.add_theme_stylebox_override("normal", ready_style)
		button.add_theme_color_override("font_color", Color(1.0, 0.96, 0.74, 1.0))
	else:
		_copy_button_style(_move_button, button, "normal")
		button.add_theme_color_override("font_color", _move_button.get_theme_color("font_color"))

func _get_skill_cooldown_remaining(skill_id: StringName) -> float:
	if _primary_skill_unit == null or not is_instance_valid(_primary_skill_unit):
		return 0.0
	return _primary_skill_unit.get_skill_cooldown_remaining(skill_id)

func _get_first_selected_active_skills() -> Array[UnitSkill]:
	if _primary_skill_unit != null and is_instance_valid(_primary_skill_unit):
		return _primary_skill_unit.get_active_skills()

	var active_skills: Array[UnitSkill] = []
	return active_skills

func _get_first_selected_unit() -> Unit:
	for unit in _selected_units.values():
		var selected_unit := unit as Unit
		if selected_unit != null and is_instance_valid(selected_unit):
			return selected_unit
	return null

func _on_skill_button_pressed(index: int) -> void:
	if index < 0 or index >= _shown_skills.size():
		return
	var skill := _shown_skills[index]
	if skill == null:
		return
	skill_command_requested.emit(skill.id)

func _is_skill_toggled(skill_id: StringName) -> bool:
	for unit in _selected_units.values():
		var selected_unit := unit as Unit
		if selected_unit != null and is_instance_valid(selected_unit) and selected_unit.is_skill_toggled(skill_id):
			return true
	return false

func _get_skill_command_id(skill_id: StringName) -> String:
	return COMMAND_SKILL_PREFIX + String(skill_id)
