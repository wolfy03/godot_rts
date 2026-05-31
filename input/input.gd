extends Node

@onready var _unit_move_command: UnitMoveCommand = $UnitMoveCommand
@onready var _unit_selection: UnitSelection = $UnitSelection
@onready var _command_panel = $HUD/CommandPanel
@onready var _unit_status_panel = $HUD/UnitStatusPanel
@onready var _debug_overlay = $HUD/DebugOverlay

func _ready():
	_connect_if_needed(_unit_selection.unit_selection_changed, _unit_move_command.unit_selection_changed)
	_connect_if_needed(_unit_selection.unit_selection_changed, _command_panel.unit_selection_changed)
	_connect_if_needed(_unit_selection.unit_selection_changed, _unit_status_panel.unit_selection_changed)
	_connect_if_needed(_unit_selection.unit_selection_changed, _debug_overlay.unit_selection_changed)
	_connect_if_needed(_unit_move_command.command_targeting_changed, _unit_selection.command_targeting_changed)
	_connect_if_needed(_unit_move_command.command_targeting_changed, _command_panel.command_targeting_changed)
	_connect_if_needed(_command_panel.move_command_requested, _unit_move_command.begin_move_command)
	_connect_if_needed(_command_panel.attack_command_requested, _unit_move_command.begin_attack_command)
	_connect_if_needed(_command_panel.stop_command_requested, _unit_move_command.issue_stop_command)
	_connect_if_needed(_command_panel.hold_position_command_requested, _unit_move_command.issue_hold_position_command)
	_connect_if_needed(_command_panel.skill_command_requested, _unit_move_command.begin_skill_command)

func _connect_if_needed(source_signal: Signal, callable: Callable):
	if not source_signal.is_connected(callable):
		source_signal.connect(callable)
