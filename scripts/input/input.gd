extends Node

const ACTION_TOGGLE_AGENT_COMMAND_MODE := "Toggle Agent Command Mode"
const ACTION_TOGGLE_INVENTORY := "Toggle Inventory"
const ACTION_INTERACT := "Interact"

@onready var _unit_command_controller: Node = $UnitCommandController
@onready var _unit_selection: UnitSelection = $UnitSelection
@onready var _agent_direct_controller: AgentDirectController = $AgentDirectController
@onready var _camera_controls: Camera3D = $Camera
@onready var _command_panel = $HUD/CommandPanel
@onready var _unit_status_panel = $HUD/UnitStatusPanel
@onready var _inventory_panel = $HUD/InventoryPanel
@onready var _player_status_panel = $HUD/PlayerStatusPanel
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
	_connect_if_needed(_inventory_panel.inventory_visibility_changed, _on_inventory_visibility_changed)
	_set_agent_command_mode_enabled(agent_command_mode_enabled)

func _input(event: InputEvent) -> void:
	if _is_player_status_toggle_event(event):
		_toggle_player_status_panel()
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed(ACTION_TOGGLE_AGENT_COMMAND_MODE):
		_set_agent_command_mode_enabled(not agent_command_mode_enabled)
	elif _is_inventory_toggle_event(event):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
	elif not agent_command_mode_enabled and _is_interact_event(event):
		var agent := _get_player_agent()
		if agent != null and agent.has_method("try_pickup_nearest_item"):
			agent.try_pickup_nearest_item()
		get_viewport().set_input_as_handled()

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

func _toggle_inventory() -> void:
	var agent := _get_player_agent()
	if agent != null:
		_inventory_panel.set_inventory(agent.get_inventory())
	_inventory_panel.toggle_inventory()

func _toggle_player_status_panel() -> void:
	var agent := _get_player_agent()
	if _player_status_panel.has_method("set_player_agent"):
		_player_status_panel.set_player_agent(agent)
	if _player_status_panel.has_method("toggle"):
		_player_status_panel.toggle()

func _on_inventory_visibility_changed(is_open: bool) -> void:
	_agent_direct_controller.set_inventory_input_blocked(is_open)
	if not is_open:
		var agent := _get_player_agent()
		if agent != null and agent.has_method("sync_equipped_weapon_from_inventory"):
			agent.sync_equipped_weapon_from_inventory()

func _get_player_agent() -> PlayerAgent:
	for node in get_tree().get_nodes_in_group("player_agent"):
		var agent := node as PlayerAgent
		if agent != null and is_instance_valid(agent):
			return agent
	return null

func _is_inventory_toggle_event(event: InputEvent) -> bool:
	if event.is_action_pressed(ACTION_TOGGLE_INVENTORY):
		return true

	var key_event := event as InputEventKey
	return key_event != null \
		and key_event.pressed \
		and not key_event.echo \
		and key_event.physical_keycode == KEY_I

func _is_player_status_toggle_event(event: InputEvent) -> bool:
	var key_event := event as InputEventKey
	return key_event != null \
		and key_event.pressed \
		and not key_event.echo \
		and (key_event.physical_keycode == KEY_TAB or key_event.keycode == KEY_TAB)

func _is_interact_event(event: InputEvent) -> bool:
	if event.is_action_pressed(ACTION_INTERACT):
		return true

	var key_event := event as InputEventKey
	return key_event != null \
		and key_event.pressed \
		and not key_event.echo \
		and key_event.physical_keycode == KEY_E
