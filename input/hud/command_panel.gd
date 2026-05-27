extends PanelContainer
class_name CommandPanel

const COMMAND_NONE := ""
const COMMAND_MOVE := "move"
const COMMAND_ATTACK := "attack"

signal move_command_requested
signal attack_command_requested
signal stop_command_requested
signal hold_position_command_requested

@onready var _selection_label: Label = %SelectionLabel
@onready var _move_button: Button = %MoveButton
@onready var _attack_button: Button = %AttackButton
@onready var _stop_button: Button = %StopButton
@onready var _hold_button: Button = %HoldButton

func _ready() -> void:
	add_to_group("command_panel_ui")
	visible = false
	
	_move_button.toggle_mode = true
	_attack_button.toggle_mode = true
	
	_move_button.pressed.connect(func(): move_command_requested.emit())
	_attack_button.pressed.connect(func(): attack_command_requested.emit())
	_stop_button.pressed.connect(func(): stop_command_requested.emit())
	_hold_button.pressed.connect(func(): hold_position_command_requested.emit())

func unit_selection_changed(selected_units: Dictionary) -> void:
	var selected_count := selected_units.size()
	visible = selected_count > 0
	_selection_label.text = "선택 유닛 %d" % selected_count
	
	if selected_count == 0:
		command_targeting_changed(COMMAND_NONE)

func command_targeting_changed(command_id: String) -> void:
	_move_button.button_pressed = command_id == COMMAND_MOVE
	_attack_button.button_pressed = command_id == COMMAND_ATTACK
