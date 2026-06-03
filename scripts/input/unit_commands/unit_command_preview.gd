extends Node
class_name UnitCommandPreview

const CIRCLE_SEGMENTS := 96
const TRAJECTORY_SEGMENTS := 24
const MIN_ARC_HEIGHT := 0.8
const MAX_ARC_HEIGHT := 3.2

var _range_preview: MeshInstance3D
var _trajectory_preview: MeshInstance3D
var _impact_preview: MeshInstance3D
var _range_preview_material: StandardMaterial3D
var _trajectory_preview_material: StandardMaterial3D
var _impact_preview_material: StandardMaterial3D

func _exit_tree() -> void:
	_free_preview_node(_range_preview)
	_free_preview_node(_trajectory_preview)
	_free_preview_node(_impact_preview)

func update_preview(selected_units: Dictionary, skill_id: StringName, target_position_value: Variant) -> void:
	var skill := _get_preview_skill(selected_units, skill_id)
	var caster := _get_preview_caster(selected_units, skill)
	if skill == null or caster == null:
		hide_preview()
		return

	_ensure_preview_nodes()
	_update_range_preview(caster.global_position, skill.cast_range)

	if target_position_value == null:
		_set_target_preview_visible(false)
		return

	var target_position: Vector3 = target_position_value
	var in_range := _get_horizontal_distance(caster.global_position, target_position) <= skill.cast_range + 0.05
	_set_target_preview_visible(in_range)
	if in_range:
		_update_trajectory_preview(caster.global_position + Vector3.UP * 0.9, target_position, skill.cast_range)
		_update_impact_preview(target_position, skill.radius)

func hide_preview() -> void:
	if _range_preview != null and is_instance_valid(_range_preview):
		_range_preview.visible = false
	_set_target_preview_visible(false)

func _get_preview_skill(selected_units: Dictionary, skill_id: StringName) -> UnitSkill:
	if skill_id == &"":
		return null

	for selected_unit in selected_units.values():
		var unit := selected_unit as Unit
		if unit == null or not is_instance_valid(unit):
			continue

		var skill := unit.get_skill(skill_id)
		if _can_preview_skill(skill):
			return skill

	return null

func _can_preview_skill(skill: UnitSkill) -> bool:
	return skill != null \
		and skill.target_type == UnitSkill.TargetType.POSITION \
		and skill.delivery_type == UnitSkill.DeliveryType.ARC_PROJECTILE

func _get_preview_caster(selected_units: Dictionary, skill: UnitSkill) -> Unit:
	if skill == null:
		return null

	for selected_unit in selected_units.values():
		var unit := selected_unit as Unit
		if unit != null and is_instance_valid(unit) and unit.has_skill(skill.id):
			return unit

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

	var preview_parent: Node = get_tree().current_scene
	if preview_parent == null:
		preview_parent = self

	preview_parent.add_child(_range_preview)
	preview_parent.add_child(_trajectory_preview)
	preview_parent.add_child(_impact_preview)

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
	for index in CIRCLE_SEGMENTS:
		var angle_a := TAU * float(index) / float(CIRCLE_SEGMENTS)
		var angle_b := TAU * float(index + 1) / float(CIRCLE_SEGMENTS)
		mesh.surface_add_vertex(center + Vector3(cos(angle_a) * radius, y_offset, sin(angle_a) * radius))
		mesh.surface_add_vertex(center + Vector3(cos(angle_b) * radius, y_offset, sin(angle_b) * radius))
	mesh.surface_end()

	mesh_instance.mesh = mesh
	mesh_instance.visible = true

func _update_trajectory_preview(start_position: Vector3, target_position: Vector3, cast_range: float) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _trajectory_preview_material)
	var previous := start_position
	for index in range(1, TRAJECTORY_SEGMENTS + 1):
		var t := float(index) / float(TRAJECTORY_SEGMENTS)
		var current := _get_arc_position(start_position, target_position, cast_range, t)
		mesh.surface_add_vertex(previous)
		mesh.surface_add_vertex(current)
		previous = current
	mesh.surface_end()

	_trajectory_preview.mesh = mesh
	_trajectory_preview.visible = true

func _get_arc_position(start_position: Vector3, target_position: Vector3, cast_range: float, t: float) -> Vector3:
	var position := start_position.lerp(target_position, t)
	var distance := _get_horizontal_distance(start_position, target_position)
	var range_ratio := clampf(distance / maxf(cast_range, 0.1), 0.0, 1.0)
	var arc_height := lerpf(MAX_ARC_HEIGHT, MIN_ARC_HEIGHT, range_ratio)
	position.y += sin(t * PI) * arc_height
	return position

func _get_horizontal_distance(from: Vector3, to: Vector3) -> float:
	var flat_from := Vector3(from.x, 0.0, from.z)
	var flat_to := Vector3(to.x, 0.0, to.z)
	return flat_from.distance_to(flat_to)

func _set_target_preview_visible(is_visible: bool) -> void:
	if _trajectory_preview != null and is_instance_valid(_trajectory_preview):
		_trajectory_preview.visible = is_visible
	if _impact_preview != null and is_instance_valid(_impact_preview):
		_impact_preview.visible = is_visible

func _free_preview_node(preview_node: MeshInstance3D) -> void:
	if preview_node != null and is_instance_valid(preview_node):
		preview_node.queue_free()
