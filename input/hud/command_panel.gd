extends PanelContainer
class_name CommandPanel

const COMMAND_NONE := ""
const COMMAND_MOVE := "move"
const COMMAND_ATTACK := "attack"
const COMMAND_SKILL_PREFIX := "skill:"
const SKILL_BUTTON_COUNT := 4

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

func _ready() -> void:
	add_to_group("command_panel_ui")
	visible = false

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

		command_grid.add_child(button)
		command_grid.move_child(button, start_index + index)
		if old_slot != null:
			old_slot.queue_free()
		_skill_buttons.append(button)

func _copy_button_style(source: Button, target: Button, style_name: String) -> void:
	var style := source.get_theme_stylebox(style_name)
	if style != null:
		target.add_theme_stylebox_override(style_name, style)

func _update_skill_buttons() -> void:
	_shown_skills = _get_first_selected_active_skills()
	for index in _skill_buttons.size():
		var button := _skill_buttons[index]
		var skill: UnitSkill = _shown_skills[index] if index < _shown_skills.size() else null
		if skill == null:
			button.text = ""
			button.tooltip_text = ""
			button.disabled = true
			button.button_pressed = false
			continue

		button.text = skill.display_name
		button.tooltip_text = skill.description
		button.disabled = false
		button.button_pressed = _is_skill_toggled(skill.id) if skill.is_toggle() else false

func _get_first_selected_active_skills() -> Array[UnitSkill]:
	for unit in _selected_units.values():
		var selected_unit := unit as Unit
		if selected_unit != null and is_instance_valid(selected_unit):
			return selected_unit.get_active_skills()
	return []

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
