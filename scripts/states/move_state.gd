extends StateMachine.State
class_name MoveState

const ID = "MOVE_STATE"

var _attack_move: bool
var _chunked_navigation: ChunkedUnitNavigation = null

func _get_id() -> String:
	return ID

func _activate(data: MoveCommandData) -> void:
	super._activate(data)
	if not _is_active:
		return

	_attack_move = data.attack_move
	_unit.clear_cover()

	if not _unit.blocks_auto_cover():
		var target_cover := _unit.find_nearest_cover_to(data.target_position, 2.0)
		if target_cover != null:
			_deactivate()
			transition_to_state.emit(TakeCoverState.ID, target_cover)
			return

	_chunked_navigation = _get_chunked_navigation()
	if _chunked_navigation != null:
		_chunked_navigation.assign_agent_path(_unit.navigation_agent, _unit.global_position, data.target_position)
	else:
		_unit.navigation_agent.target_position = data.target_position
	_unit.last_move_command_data = data

	if _attack_move and _unit.ai_brain != null:
		_unit.ai_brain.request_decision(true)

func _process_state(_delta: float) -> void:
	if _chunked_navigation != null and _chunked_navigation.update_agent_waypoint_if_reached(_unit.navigation_agent):
		return

	if _unit.navigation_agent.is_navigation_finished():
		if _attack_move:
			_unit.finish_player_command(Unit.PlayerCommandMode.ATTACK_MOVE)
		else:
			_unit.finish_player_command(Unit.PlayerCommandMode.MOVE)
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)

func _on_enemy_detection_area_body_entered(_body: Node3D) -> void:
	if _is_active and _attack_move:
		if _unit.ai_brain != null:
			_unit.ai_brain.request_decision(true)

func _get_chunked_navigation() -> ChunkedUnitNavigation:
	for node in _unit.get_tree().get_nodes_in_group("chunked_unit_navigation"):
		var navigation := node as ChunkedUnitNavigation
		if navigation != null and is_instance_valid(navigation):
			return navigation
	return null

class MoveCommandData:
	var target_position: Vector3
	var attack_move: bool
