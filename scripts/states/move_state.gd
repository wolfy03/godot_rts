extends StateMachine.State
class_name MoveState

const ID = "MOVE_STATE"

@export_range(0.0, 60.0, 0.1, "or_greater") var navigation_map_ready_timeout: float = 1.0
@export_range(0.0, 60.0, 0.1, "or_greater") var navigation_path_ready_timeout: float = 1.0

var _attack_move: bool
var _chunked_navigation: ChunkedUnitNavigation = null
var _target_set_physics_frame: int = 0
var _path_wait_seconds: float = 0.0

func _get_id() -> String:
	return ID

func _activate(data: MoveCommandData) -> void:
	super._activate(data)
	if not _is_active:
		return

	_attack_move = data.attack_move
	_unit.clear_cover()
	_chunked_navigation = _get_chunked_navigation()
	if not data.target_position.is_finite() or (_chunked_navigation != null
		and not _chunked_navigation.is_world_position_navigable(data.target_position)):
		_fail_move_command()
		return

	if not _unit.blocks_auto_cover():
		var target_cover := _unit.find_nearest_cover_to(data.target_position, 2.0)
		if target_cover != null:
			_deactivate()
			transition_to_state.emit(TakeCoverState.ID, target_cover)
			return

	# Chunk AStar is strategic only. The agent owns the connected region path.
	_unit.navigation_agent.target_position = data.target_position
	_target_set_physics_frame = Engine.get_physics_frames()
	_path_wait_seconds = 0.0
	_unit.last_move_command_data = data

	if _attack_move and _unit.ai_brain != null:
		_unit.ai_brain.request_decision(true)

func _process_state(delta: float) -> void:
	# Target assignment and map synchronization are asynchronous. Unit updates
	# get_next_path_position() in physics; don't read yesterday's path this frame.
	if Engine.get_physics_frames() <= _target_set_physics_frame + 2:
		return
	var agent: NavigationAgent3D = _unit.navigation_agent
	_path_wait_seconds += delta
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		if _path_wait_seconds >= navigation_map_ready_timeout:
			_fail_move_command()
		return
	if agent.get_current_navigation_path().is_empty():
		if _path_wait_seconds >= navigation_path_ready_timeout:
			_fail_move_command()
		return
	if not agent.is_target_reachable():
		# Ground clicks use collider surface height, while existing maps and unit
		# centers can sit above it. Judge XZ reachability with one agent-height
		# vertical tolerance instead of rejecting every projected floor click.
		var final_position: Vector3 = agent.get_final_position()
		var target: Vector3 = agent.target_position
		var horizontal_error: float = Vector2(final_position.x, final_position.z).distance_to(Vector2(target.x, target.z))
		if horizontal_error > agent.target_desired_distance or absf(final_position.y - target.y) > agent.height:
			_fail_move_command()
			return

	if _unit.navigation_agent.is_navigation_finished():
		if _attack_move:
			_unit.finish_player_command(Unit.PlayerCommandMode.ATTACK_MOVE)
		else:
			_unit.finish_player_command(Unit.PlayerCommandMode.MOVE)
		_deactivate()
		transition_to_state.emit(IdleState.ID, null)

func _fail_move_command() -> void:
	_unit.finish_player_command(Unit.PlayerCommandMode.ATTACK_MOVE if _attack_move else Unit.PlayerCommandMode.MOVE)
	_unit.last_move_command_data = null
	_unit.velocity = Vector3.ZERO
	_unit.navigation_agent.velocity = Vector3.ZERO
	_unit.navigation_agent.target_position = _unit.global_position
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
