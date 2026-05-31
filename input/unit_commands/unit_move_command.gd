extends Node
class_name UnitMoveCommand

const COMMAND_NONE := ""
const COMMAND_MOVE := "move"
const COMMAND_ATTACK := "attack"
const COMMAND_SKILL_PREFIX := "skill:"
const UNIT_COLLISION_MASK := 0b110
const ENEMY_UNIT_COLLISION_MASK := 0b100
const MOUSE_RAY_LENGTH := 1000.0
const PREVIEW_CIRCLE_SEGMENTS := 96
const PREVIEW_TRAJECTORY_SEGMENTS := 24
const PREVIEW_MIN_ARC_HEIGHT := 0.8
const PREVIEW_MAX_ARC_HEIGHT := 3.2
const ACTION_UNIT_MOVE := "Unit Move Command"
const ACTION_UNIT_ATTACK := "Unit Attack Command"
const ACTION_UNIT_HOLD_POSITION := "Unit Hold Position Command"

signal command_targeting_changed(command_id: String)

@export var move_command_handle_scene: PackedScene

var _selected_units: Dictionary = {}
var _pending_command_id: String = COMMAND_NONE
var _range_preview: MeshInstance3D
var _trajectory_preview: MeshInstance3D
var _impact_preview: MeshInstance3D
var _range_preview_material: StandardMaterial3D
var _trajectory_preview_material: StandardMaterial3D
var _impact_preview_material: StandardMaterial3D

func unit_selection_changed(selected_units: Dictionary) -> void:
	_selected_units = selected_units
	if _selected_units.is_empty():
		_set_pending_command(COMMAND_NONE)

func _process(_delta: float) -> void:
	_update_skill_preview()

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
		if _is_pending_skill_command():
			_issue_skill_command(_get_pending_skill_id())
		else:
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

func begin_skill_command(skill_id: StringName) -> void:
	_toggle_pending_command(_get_skill_command_id(skill_id))

func issue_stop_command() -> void:
	_set_pending_command(COMMAND_NONE)
	for unit: Unit in _selected_units.values():
		if not is_instance_valid(unit):
			continue

		unit.clear_player_command()
		_reset_unit_command_state(unit)
		_stop_unit_movement(unit)
		unit.state_machine.transition_to_state(IdleState.ID, null)

func issue_hold_position_command() -> void:
	_set_pending_command(COMMAND_NONE)
	for unit: Unit in _selected_units.values():
		if not is_instance_valid(unit):
			continue

		unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
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

		unit.begin_player_command(Unit.PlayerCommandMode.ATTACK_TARGET)
		_reset_unit_command_state(unit)
		unit.state_machine.transition_to_state(ChaseState.ID, target_unit)

func _issue_skill_command(skill_id: StringName) -> void:
	var click_position = _get_ground_mouse_position()
	var target_unit := _get_unit_under_mouse(UNIT_COLLISION_MASK)

	for unit: Unit in _selected_units.values():
		if not is_instance_valid(unit) or not unit.has_skill(skill_id):
			continue

		var skill := unit.get_skill(skill_id)
		if skill == null:
			continue

		match skill.target_type:
			UnitSkill.TargetType.NONE, UnitSkill.TargetType.SELF:
				unit.begin_player_command(Unit.PlayerCommandMode.SKILL)
				unit.use_skill(skill_id, unit, unit.global_position)
				unit.finish_player_command(Unit.PlayerCommandMode.SKILL)
			UnitSkill.TargetType.POSITION:
				if click_position != null:
					unit.begin_player_command(Unit.PlayerCommandMode.SKILL)
					if not unit.issue_skill_command(skill_id, target_unit, click_position):
						unit.finish_player_command(Unit.PlayerCommandMode.SKILL)
			UnitSkill.TargetType.ALLY_UNIT, UnitSkill.TargetType.ENEMY_UNIT, UnitSkill.TargetType.ANY_UNIT:
				if target_unit != null:
					unit.begin_player_command(Unit.PlayerCommandMode.SKILL)
					if not unit.issue_skill_command(skill_id, target_unit, target_unit.global_position):
						unit.finish_player_command(Unit.PlayerCommandMode.SKILL)

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
	if not _is_pending_skill_command():
		_hide_skill_preview()
	command_targeting_changed.emit(_pending_command_id)

func _is_pending_skill_command() -> bool:
	return _pending_command_id.begins_with(COMMAND_SKILL_PREFIX)

func _get_pending_skill_id() -> StringName:
	if not _is_pending_skill_command():
		return &""
	return StringName(_pending_command_id.substr(COMMAND_SKILL_PREFIX.length()))

func _get_skill_command_id(skill_id: StringName) -> String:
	return COMMAND_SKILL_PREFIX + String(skill_id)

func _update_skill_preview() -> void:
	var skill := _get_pending_preview_skill()
	var caster := _get_preview_caster(skill)
	if skill == null or caster == null:
		_hide_skill_preview()
		return

	_ensure_preview_nodes()
	_update_range_preview(caster.global_position, skill.cast_range)

	var target_position_value: Variant = _get_ground_mouse_position()
	if target_position_value == null:
		_trajectory_preview.visible = false
		_impact_preview.visible = false
		return

	var target_position: Vector3 = target_position_value
	var in_range: bool = _get_horizontal_distance(caster.global_position, target_position) <= skill.cast_range + 0.05
	_trajectory_preview.visible = in_range
	_impact_preview.visible = in_range
	if in_range:
		_update_trajectory_preview(caster.global_position + Vector3.UP * 0.9, target_position, skill.cast_range)
		_update_impact_preview(target_position, skill.radius)

func _get_pending_preview_skill() -> UnitSkill:
	if not _is_pending_skill_command():
		return null

	var skill_id := _get_pending_skill_id()
	for unit in _selected_units.values():
		var selected_unit := unit as Unit
		if selected_unit == null or not is_instance_valid(selected_unit):
			continue

		var skill := selected_unit.get_skill(skill_id)
		if skill == null:
			continue
		if skill.target_type == UnitSkill.TargetType.POSITION and skill.delivery_type == UnitSkill.DeliveryType.ARC_PROJECTILE:
			return skill

	return null

func _get_preview_caster(skill: UnitSkill) -> Unit:
	if skill == null:
		return null

	for unit in _selected_units.values():
		var selected_unit := unit as Unit
		if selected_unit != null and is_instance_valid(selected_unit) and selected_unit.has_skill(skill.id):
			return selected_unit

	return null

func _ensure_preview_nodes() -> void:
	if _range_preview != null and is_instance_valid(_range_preview):
		return

	_range_preview_material = _make_preview_material(Color(0.2, 0.95, 0.45, 0.72))
	_trajectory_preview_material = _make_preview_material(Color(1.0, 0.82, 0.2, 0.88))
	_impact_preview_material = _make_preview_material(Color(1.0, 0.22, 0.12, 0.9))
	_range_preview = _make_preview_mesh_instance(_range_preview_material)
	_trajectory_preview = _make_preview_mesh_instance(_trajectory_preview_material)
	_impact_preview = _make_preview_mesh_instance(_impact_preview_material)

	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		scene_root.add_child(_range_preview)
		scene_root.add_child(_trajectory_preview)
		scene_root.add_child(_impact_preview)

func _make_preview_mesh_instance(material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visible = false
	mesh_instance.material_override = material
	return mesh_instance

func _make_preview_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.no_depth_test = true
	return material

func _update_range_preview(center: Vector3, radius: float) -> void:
	_set_circle_preview(_range_preview, _range_preview_material, center, radius, 0.05)

func _update_impact_preview(center: Vector3, radius: float) -> void:
	_set_circle_preview(_impact_preview, _impact_preview_material, center, radius, 0.08)

func _set_circle_preview(mesh_instance: MeshInstance3D, material: StandardMaterial3D, center: Vector3, radius: float, y_offset: float) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in PREVIEW_CIRCLE_SEGMENTS:
		var angle_a := TAU * float(index) / float(PREVIEW_CIRCLE_SEGMENTS)
		var angle_b := TAU * float(index + 1) / float(PREVIEW_CIRCLE_SEGMENTS)
		mesh.surface_add_vertex(center + Vector3(cos(angle_a) * radius, y_offset, sin(angle_a) * radius))
		mesh.surface_add_vertex(center + Vector3(cos(angle_b) * radius, y_offset, sin(angle_b) * radius))
	mesh.surface_end()

	mesh_instance.mesh = mesh
	mesh_instance.visible = true

func _update_trajectory_preview(start_position: Vector3, target_position: Vector3, cast_range: float) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _trajectory_preview_material)
	var previous := start_position
	for index in range(1, PREVIEW_TRAJECTORY_SEGMENTS + 1):
		var t := float(index) / float(PREVIEW_TRAJECTORY_SEGMENTS)
		var current := _get_preview_arc_position(start_position, target_position, cast_range, t)
		mesh.surface_add_vertex(previous)
		mesh.surface_add_vertex(current)
		previous = current
	mesh.surface_end()

	_trajectory_preview.mesh = mesh
	_trajectory_preview.visible = true

func _get_preview_arc_position(start_position: Vector3, target_position: Vector3, cast_range: float, t: float) -> Vector3:
	var position := start_position.lerp(target_position, t)
	var distance := _get_horizontal_distance(start_position, target_position)
	var range_ratio := clampf(distance / maxf(cast_range, 0.1), 0.0, 1.0)
	var arc_height := lerpf(PREVIEW_MAX_ARC_HEIGHT, PREVIEW_MIN_ARC_HEIGHT, range_ratio)
	position.y += sin(t * PI) * arc_height
	return position

func _get_horizontal_distance(from: Vector3, to: Vector3) -> float:
	var flat_from := Vector3(from.x, 0.0, from.z)
	var flat_to := Vector3(to.x, 0.0, to.z)
	return flat_from.distance_to(flat_to)

func _hide_skill_preview() -> void:
	if _range_preview != null and is_instance_valid(_range_preview):
		_range_preview.visible = false
	if _trajectory_preview != null and is_instance_valid(_trajectory_preview):
		_trajectory_preview.visible = false
	if _impact_preview != null and is_instance_valid(_impact_preview):
		_impact_preview.visible = false

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
	return _get_unit_under_mouse(ENEMY_UNIT_COLLISION_MASK)

func _get_unit_under_mouse(collision_mask: int) -> Unit:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_pos) * MOUSE_RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider := result.get("collider") as Unit
	if collider == null or not is_instance_valid(collider):
		return null

	return collider
