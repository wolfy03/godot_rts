extends Area3D
class_name MoveCommandHandle

const COVER_SEARCH_RADIUS := 2.5
const FORMATION_SPACING_MULTIPLIER := 1.5
const DEFAULT_UNIT_RADIUS := 0.45
const GOLDEN_ANGLE_RADIANS := 2.39996

var _selected_units: Dictionary = {}

func move_selected_units(selected_units: Dictionary,
						 click_position: Vector3,
						 attack_move: bool) -> void:
	position = click_position
	_selected_units = selected_units.duplicate()

	var clicked_cover := _find_cover_near(click_position)
	if clicked_cover != null:
		_send_units_to_cover(clicked_cover)
		queue_free()
		return

	var selection_bounds := _get_selection_bounds()
	var selection_center := (selection_bounds.min_position + selection_bounds.max_position) * 0.5
	selection_center.y = click_position.y

	var click_is_inside_selection := _is_click_inside_selection(selection_bounds, selection_center, click_position)
	var formation_index := 0

	for unit: Unit in _selected_units.values():
		if not is_instance_valid(unit):
			continue

		var target_position := _get_target_position_for_unit(
			unit,
			click_position,
			selection_center,
			click_is_inside_selection,
			formation_index
		)

		_issue_move_order(unit, target_position, attack_move)
		if click_is_inside_selection:
			formation_index += 1

	queue_free()

func remove_units(units: Dictionary) -> void:
	if not is_instance_valid(self):
		return

	for unit_id in units.keys():
		_selected_units.erase(unit_id)

func _remove_dead_unit(unit: Unit) -> void:
	if not is_instance_valid(self):
		return

	_selected_units.erase(unit.get_instance_id())

func _find_cover_near(target_position: Vector3) -> Cover:
	for unit: Unit in _selected_units.values():
		if is_instance_valid(unit):
			return unit.find_nearest_cover_to(target_position, COVER_SEARCH_RADIUS)

	return null

func _send_units_to_cover(cover: Cover) -> void:
	for unit: Unit in _selected_units.values():
		if not is_instance_valid(unit):
			continue

		_clear_unit_command_state(unit)
		unit.begin_player_command(Unit.PlayerCommandMode.MOVE)
		unit.state_machine.transition_to_state(TakeCoverState.ID, cover)

func _get_selection_bounds() -> SelectionBounds:
	var bounds := SelectionBounds.new()

	for unit: Unit in _selected_units.values():
		if not is_instance_valid(unit):
			continue

		bounds.include_position(unit.global_position)
		_connect_unit_exit_signal(unit)

	return bounds

func _connect_unit_exit_signal(unit: Unit) -> void:
	var remove_dead_unit := _remove_dead_unit.bind(unit)
	if not unit.tree_exiting.is_connected(remove_dead_unit):
		unit.tree_exiting.connect(remove_dead_unit)

func _is_click_inside_selection(bounds: SelectionBounds, selection_center: Vector3, click_position: Vector3) -> bool:
	if not bounds.has_position:
		return false

	var selection_size := bounds.max_position - bounds.min_position
	var selection_radius := selection_size.length()
	var click_distance := selection_center.distance_to(click_position)
	return click_distance < selection_radius

func _get_target_position_for_unit(
	unit: Unit,
	click_position: Vector3,
	selection_center: Vector3,
	click_is_inside_selection: bool,
	formation_index: int
) -> Vector3:
	var target_position: Vector3

	if click_is_inside_selection:
		target_position = click_position + _get_vogel_spiral_offset(unit, formation_index)
	else:
		target_position = click_position + unit.global_position - selection_center

	target_position.y = click_position.y
	return target_position

func _get_vogel_spiral_offset(unit: Unit, formation_index: int) -> Vector3:
	if formation_index == 0:
		return Vector3.ZERO

	var unit_radius := DEFAULT_UNIT_RADIUS
	if is_instance_valid(unit.navigation_agent):
		unit_radius = unit.navigation_agent.radius

	var theta := float(formation_index) * GOLDEN_ANGLE_RADIANS
	var radius := sqrt(float(formation_index)) * unit_radius * FORMATION_SPACING_MULTIPLIER
	return Vector3(cos(theta), 0.0, sin(theta)) * radius

func _issue_move_order(unit: Unit, target_position: Vector3, attack_move: bool) -> void:
	var data := MoveState.MoveCommandData.new()
	data.target_position = target_position
	data.attack_move = attack_move
	unit.begin_player_command(Unit.PlayerCommandMode.ATTACK_MOVE if attack_move else Unit.PlayerCommandMode.MOVE)
	unit.state_machine.transition_to_state(MoveState.ID, data)

func _clear_unit_command_state(unit: Unit) -> void:
	unit.last_move_command_data = null
	unit.hold_position_enabled = false
	unit.clear_cover()

class SelectionBounds:
	var min_position: Vector3 = Vector3.ZERO
	var max_position: Vector3 = Vector3.ZERO
	var has_position: bool = false

	func include_position(position: Vector3) -> void:
		if not has_position:
			min_position = position
			max_position = position
			has_position = true
			return

		min_position.x = minf(min_position.x, position.x)
		min_position.z = minf(min_position.z, position.z)
		max_position.x = maxf(max_position.x, position.x)
		max_position.z = maxf(max_position.z, position.z)
