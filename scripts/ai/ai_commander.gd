extends Node3D
class_name AICommander

const GameTeamData := preload("res://scripts/team/game_team.gd")

const STATE_MOVE := "MOVE_STATE"
const STATE_CHASE := "CHASE_STATE"

enum CommanderMode {
	DISABLED,
	ANNIHILATE,
	GUARD_AREA,
}

enum EconomicStrategy {
	DISABLED,
	AUTO_BUILD_AND_EXPAND,
}

@export var team_id: int = GameTeamData.ENEMY
@export var mode: CommanderMode = CommanderMode.DISABLED
@export var issue_interval: float = 1.0
@export var economic_strategy: EconomicStrategy = EconomicStrategy.DISABLED
@export var economic_issue_interval: float = 3.0
@export var guard_radius: float = 8.0
@export var guard_engagement_radius: float = 8.0
@export var formation_spacing: float = 1.6
@export var override_player_commands: bool = false
@export var mission_area_path: NodePath

var _mission_position: Vector3 = Vector3.INF
var _last_order_keys: Dictionary = {}
var _last_economic_plan: EconomicPlan = null
var _tactical_timer: Timer
var _economic_timer: Timer

func _ready() -> void:
	add_to_group("ai_commanders")
	add_to_group("ai_commanders_%d" % team_id)
	_setup_timers()

func _setup_timers() -> void:
	_tactical_timer = Timer.new()
	_tactical_timer.name = "TacticalDecisionTimer"
	_tactical_timer.wait_time = maxf(0.1, issue_interval)
	_tactical_timer.autostart = true
	_tactical_timer.timeout.connect(_on_tactical_timer_timeout)
	add_child(_tactical_timer)

	_economic_timer = Timer.new()
	_economic_timer.name = "EconomicDecisionTimer"
	_economic_timer.wait_time = maxf(0.1, economic_issue_interval)
	_economic_timer.autostart = true
	_economic_timer.timeout.connect(_on_economic_timer_timeout)
	add_child(_economic_timer)

func _on_tactical_timer_timeout() -> void:
	if mode == CommanderMode.DISABLED:
		return

	_issue_orders()

func _on_economic_timer_timeout() -> void:
	if economic_strategy == EconomicStrategy.DISABLED:
		return

	_issue_economic_orders()

func set_mode(new_mode: CommanderMode) -> void:
	if mode != new_mode:
		_clear_commander_tactical_memory()
	mode = new_mode
	_last_order_keys.clear()
	if _tactical_timer != null:
		_tactical_timer.wait_time = maxf(0.1, issue_interval)
		_tactical_timer.start()

func set_economic_strategy(new_strategy: EconomicStrategy) -> void:
	economic_strategy = new_strategy
	_last_economic_plan = null
	if _economic_timer != null:
		_economic_timer.wait_time = maxf(0.1, economic_issue_interval)
		_economic_timer.start()

func set_mission_area(area_position: Vector3, radius: float = -1.0) -> void:
	_mission_position = area_position
	if radius > 0.0:
		guard_radius = radius
	_last_order_keys.clear()
	if _tactical_timer != null:
		_tactical_timer.start()

func set_guard_area(area_position: Vector3, radius: float = -1.0) -> void:
	set_mission_area(area_position, radius)
	set_mode(CommanderMode.GUARD_AREA)

func get_mission_position() -> Vector3:
	var mission_area := _get_mission_area()
	if mission_area != null:
		return mission_area.global_position
	if _mission_position != Vector3.INF:
		return _mission_position
	return global_position

func get_status_summary() -> String:
	return "%s commander: %s, economy=%s, units=%d" % [
		GameTeamData.get_display_name(team_id),
		_get_mode_name(),
		_get_economic_strategy_name(),
		_get_team_units().size(),
	]

func _issue_orders() -> void:
	var units := _get_team_units()
	if units.is_empty():
		return

	match mode:
		CommanderMode.ANNIHILATE:
			_issue_annihilate_orders(units)
		CommanderMode.GUARD_AREA:
			_issue_guard_area_orders(units)

func _issue_annihilate_orders(units: Array[Unit]) -> void:
	var enemies := _get_enemy_units()
	if enemies.is_empty():
		return

	for unit in units:
		var target := _get_nearest_unit(unit.global_position, enemies)
		if target != null:
			_issue_attack_order(unit, target)

func _issue_guard_area_orders(units: Array[Unit]) -> void:
	var mission_position := get_mission_position()
	var enemies := _get_enemies_near_position(mission_position, guard_radius + guard_engagement_radius)

	for index in range(units.size()):
		var unit := units[index]
		var nearby_target := _get_nearest_unit(unit.global_position, enemies)
		if nearby_target != null:
			_issue_attack_order(unit, nearby_target)
			continue

		var guard_position := mission_position + _get_guard_offset(index, units.size())
		if unit.global_position.distance_to(guard_position) > formation_spacing:
			_issue_move_order(unit, guard_position, false)

func _issue_economic_orders() -> void:
	var plan := _evaluate_economic_plan()
	_last_economic_plan = plan
	match plan.kind:
		EconomicPlan.Kind.NONE:
			return
		EconomicPlan.Kind.BUILD_BASE:
			_reserve_builder_for_base_construction(plan)
		EconomicPlan.Kind.EXPAND_BASE:
			_reserve_builder_for_base_expansion(plan)

func _evaluate_economic_plan() -> EconomicPlan:
	# Economy data is not implemented yet. This keeps base construction independent
	# from tactical modes while leaving a single place to plug resources and tech in.
	return EconomicPlan.new(EconomicPlan.Kind.NONE, Vector3.INF)

func _reserve_builder_for_base_construction(_plan: EconomicPlan) -> void:
	# Future hook: pick a builder unit, reserve the build site, then issue build orders.
	pass

func _reserve_builder_for_base_expansion(_plan: EconomicPlan) -> void:
	# Future hook: choose an expansion site and assign available builders.
	pass

func _get_team_units(respect_player_commands: bool = true) -> Array[Unit]:
	var units: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.get_team_id() != team_id:
			continue
		if unit.is_agent_unit():
			continue
		if unit.get_current_health() <= 0:
			continue
		if respect_player_commands and not override_player_commands and unit.blocks_autonomous_ai():
			continue
		units.append(unit)
	return units

func _get_enemy_units() -> Array[Unit]:
	var enemies: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.get_current_health() <= 0:
			continue
		if unit.get_team_id() != GameTeamData.NEUTRAL and unit.get_team_id() != team_id:
			enemies.append(unit)
	return enemies

func _get_enemies_near_position(search_position: Vector3, radius: float) -> Array[Unit]:
	var enemies: Array[Unit] = []
	var radius_sq := radius * radius
	for enemy in _get_enemy_units():
		if enemy.global_position.distance_squared_to(search_position) <= radius_sq:
			enemies.append(enemy)
	return enemies

func _get_nearest_unit(search_position: Vector3, units: Array[Unit]) -> Unit:
	var nearest_unit: Unit = null
	var nearest_distance_sq := INF
	for unit in units:
		var distance_sq := unit.global_position.distance_squared_to(search_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_unit = unit
	return nearest_unit

func _issue_attack_order(unit: Unit, target: Unit) -> void:
	var order_key := "attack:%d" % target.get_instance_id()
	if _last_order_keys.get(unit.get_instance_id(), "") == order_key:
		return

	_prepare_unit_for_commander_order(unit)
	unit.last_move_command_data = null
	unit.state_machine.transition_to_state(STATE_CHASE, target)
	_last_order_keys[unit.get_instance_id()] = order_key

func _issue_move_order(unit: Unit, target_position: Vector3, attack_move: bool) -> void:
	var order_key := "move:%.1f:%.1f:%s" % [target_position.x, target_position.z, str(attack_move)]
	if _last_order_keys.get(unit.get_instance_id(), "") == order_key:
		return

	_prepare_unit_for_commander_order(unit)
	var move_data := MoveState.MoveCommandData.new()
	move_data.target_position = target_position
	move_data.attack_move = attack_move
	unit.last_move_command_data = move_data
	unit.state_machine.transition_to_state(STATE_MOVE, move_data)
	_last_order_keys[unit.get_instance_id()] = order_key

func _prepare_unit_for_commander_order(unit: Unit) -> void:
	unit.clear_player_command()
	unit.hold_position_enabled = false
	unit.clear_cover()

func _clear_commander_tactical_memory() -> void:
	_last_order_keys.clear()
	for unit in _get_team_units(false):
		unit.last_move_command_data = null

func _get_guard_offset(index: int, total_count: int) -> Vector3:
	if total_count <= 1:
		return Vector3.ZERO

	var ring_radius := maxf(formation_spacing, minf(guard_radius * 0.6, formation_spacing * ceil(sqrt(total_count))))
	var angle := TAU * float(index) / float(total_count)
	return Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius)

func _get_mission_area() -> Node3D:
	if mission_area_path.is_empty():
		return null
	return get_node_or_null(mission_area_path) as Node3D

func _get_mode_name() -> String:
	match mode:
		CommanderMode.ANNIHILATE:
			return "Annihilate"
		CommanderMode.GUARD_AREA:
			return "Guard Area"
		_:
			return "Disabled"

func _get_economic_strategy_name() -> String:
	match economic_strategy:
		EconomicStrategy.AUTO_BUILD_AND_EXPAND:
			return "Auto Build/Expand"
		_:
			return "Disabled"

class EconomicPlan:
	enum Kind {
		NONE,
		BUILD_BASE,
		EXPAND_BASE,
	}

	var kind: Kind
	var target_position: Vector3
	var requested_builder_count: int

	func _init(plan_kind: Kind, plan_target_position: Vector3, builder_count: int = 1) -> void:
		kind = plan_kind
		target_position = plan_target_position
		requested_builder_count = builder_count
