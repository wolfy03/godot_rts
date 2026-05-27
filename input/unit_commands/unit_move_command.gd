extends Node
class_name UnitMoveCommand

const COMMAND_NONE := ""
const COMMAND_MOVE := "move"
const COMMAND_ATTACK := "attack"
const ENEMY_UNIT_COLLISION_MASK := 0b100
const MOUSE_RAY_LENGTH := 1000.0
const ACTION_UNIT_MOVE := "Unit Move Command"
const ACTION_UNIT_ATTACK := "Unit Attack Command"
const ACTION_UNIT_HOLD_POSITION := "Unit Hold Position Command"

signal command_targeting_changed(command_id: String)

@export var move_command_handle_scene: PackedScene

var _selected_units: Dictionary = {}
var _pending_command_id: String = COMMAND_NONE

func unit_selection_changed(selected_units: Dictionary) -> void:
	_selected_units = selected_units
	if _selected_units.is_empty():
		_set_pending_command(COMMAND_NONE)

func _input(event: InputEvent) -> void:
	if _is_pointer_over_command_panel(event):
		return
	
	if _selected_units.is_empty():
		return
	
	if Input.is_action_just_pressed(ACTION_UNIT_MOVE):
		_set_pending_command(COMMAND_NONE)
		var target_unit := _get_enemy_unit_under_mouse()
		if target_unit:
			_issue_attack_target_command(target_unit)
		else:
			_issue_command(false)
	elif _pending_command_id != COMMAND_NONE and _is_left_mouse_button_pressed(event):
		var target_unit := _get_enemy_unit_under_mouse()
		if target_unit:
			_issue_attack_target_command(target_unit)
		else:
			_issue_command(_pending_command_id == COMMAND_ATTACK)
		_set_pending_command(COMMAND_NONE)
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed(ACTION_UNIT_ATTACK):
		begin_attack_command()
	elif Input.is_action_just_pressed(ACTION_UNIT_HOLD_POSITION):
		issue_hold_position_command()

func begin_move_command() -> void:
	_toggle_pending_command(COMMAND_MOVE)

func begin_attack_command() -> void:
	_toggle_pending_command(COMMAND_ATTACK)

func issue_stop_command() -> void:
	_set_pending_command(COMMAND_NONE)
	for unit: Unit in _selected_units.values():
		if not is_instance_valid(unit):
			continue
		
		_reset_unit_command_state(unit)
		_stop_unit_movement(unit)
		unit.state_machine.transition_to_state(IdleState.ID, null)

func issue_hold_position_command() -> void:
	_set_pending_command(COMMAND_NONE)
	for unit: Unit in _selected_units.values():
		if not is_instance_valid(unit):
			continue
		
		unit.last_move_command_data = null
		unit.state_machine.transition_to_state(HoldPositionState.ID, null)

func _issue_command(attack_move: bool) -> void:
	var click_position = _get_ground_mouse_position()
	if click_position == null:
		return
	
	_remove_active_command_handles()
	
	var handle: MoveCommandHandle = move_command_handle_scene.instantiate()
	_clear_hold_position_command()
	handle.move_selected_units(_selected_units, click_position, attack_move)
	add_child(handle)

func _issue_attack_target_command(target_unit: Unit) -> void:
	if not is_instance_valid(target_unit):
		return
	
	_remove_active_command_handles()
	
	for unit: Unit in _selected_units.values():
		if not is_instance_valid(unit):
			continue
		
		_reset_unit_command_state(unit)
		unit.state_machine.transition_to_state(ChaseState.ID, target_unit)

func _remove_active_command_handles() -> void:
	var active_handles: Array[Node] = find_children("", "MoveCommandHandle", true, false)
	
	for active_handle: MoveCommandHandle in active_handles:
		active_handle.remove_units(_selected_units)

func _clear_hold_position_command() -> void:
	for unit: Unit in _selected_units.values():
		if is_instance_valid(unit):
			unit.hold_position_enabled = false
			unit.clear_cover()

func _reset_unit_command_state(unit: Unit) -> void:
	unit.last_move_command_data = null
	unit.hold_position_enabled = false
	unit.clear_cover()

func _stop_unit_movement(unit: Unit) -> void:
	unit.movement_enabled = true
	unit.velocity = Vector3.ZERO
	if unit.navigation_agent == null:
		return
	
	unit.navigation_agent.velocity = Vector3.ZERO
	unit.navigation_agent.target_position = unit.global_position

func _toggle_pending_command(command_id: String) -> void:
	if _pending_command_id == command_id:
		_set_pending_command(COMMAND_NONE)
	else:
		_set_pending_command(command_id)

func _set_pending_command(command_id: String) -> void:
	if _pending_command_id == command_id:
		return
	
	_pending_command_id = command_id
	command_targeting_changed.emit(_pending_command_id)

func _is_left_mouse_button_pressed(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	
	var mouse_button_event := event as InputEventMouseButton
	return mouse_button_event.button_index == MOUSE_BUTTON_LEFT and mouse_button_event.pressed

func _is_pointer_over_command_panel(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return false
	
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

func _get_enemy_unit_under_mouse() -> Unit:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_pos) * MOUSE_RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, ENEMY_UNIT_COLLISION_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	
	var collider := result.get("collider") as Unit
	if collider == null or not is_instance_valid(collider):
		return null
	
	return collider
