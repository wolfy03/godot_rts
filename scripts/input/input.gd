extends Node

const ACTION_TOGGLE_AGENT_COMMAND_MODE := "Toggle Agent Command Mode"

@onready var _unit_command_controller: Node = $UnitCommandController
@onready var _unit_selection: UnitSelection = $UnitSelection
@onready var _agent_direct_controller: AgentDirectController = $AgentDirectController
@onready var _camera_controls: Camera3D = $Camera
@onready var _command_panel = $HUD/CommandPanel
@onready var _unit_status_panel = $HUD/UnitStatusPanel
@onready var _debug_overlay = $HUD/DebugOverlay

@export var agent_command_mode_enabled: bool = false

func _ready():
	_connect_if_needed(_unit_selection.unit_selection_changed, _unit_command_controller.unit_selection_changed)
	_connect_if_needed(_unit_selection.unit_selection_changed, _command_panel.unit_selection_changed)
	_connect_if_needed(_unit_selection.unit_selection_changed, _unit_status_panel.unit_selection_changed)
	_connect_if_needed(_unit_selection.unit_selection_changed, _debug_overlay.unit_selection_changed)
	_connect_if_needed(_unit_command_controller.command_targeting_changed, _unit_selection.command_targeting_changed)
	_connect_if_needed(_unit_command_controller.command_targeting_changed, _command_panel.command_targeting_changed)
	_connect_if_needed(_command_panel.move_command_requested, _unit_command_controller.begin_move_command)
	_connect_if_needed(_command_panel.attack_command_requested, _unit_command_controller.begin_attack_command)
	_connect_if_needed(_command_panel.stop_command_requested, _unit_command_controller.issue_stop_command)
	_connect_if_needed(_command_panel.hold_position_command_requested, _unit_command_controller.issue_hold_position_command)
	_connect_if_needed(_command_panel.skill_command_requested, _unit_command_controller.begin_skill_command)
	_set_agent_command_mode_enabled(agent_command_mode_enabled)

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed(ACTION_TOGGLE_AGENT_COMMAND_MODE):
		_set_agent_command_mode_enabled(not agent_command_mode_enabled)

func _connect_if_needed(source_signal: Signal, callable: Callable):
	if not source_signal.is_connected(callable):
		source_signal.connect(callable)

func _set_agent_command_mode_enabled(enabled: bool) -> void:
	agent_command_mode_enabled = enabled
	_unit_selection.set_command_mode_enabled(enabled)
	_unit_command_controller.set_command_mode_enabled(enabled)
	_command_panel.set_command_mode_enabled(enabled)
	_agent_direct_controller.set_command_mode_enabled(enabled)
	if _camera_controls.has_method("set_keyboard_camera_controls_enabled"):
		_camera_controls.set_keyboard_camera_controls_enabled(enabled)
	if _camera_controls.has_method("set_mouse_edge_camera_controls_enabled"):
		_camera_controls.set_mouse_edge_camera_controls_enabled(enabled)
