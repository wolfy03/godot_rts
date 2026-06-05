extends Node
class_name AgentDirectController

const ACTION_MOVE_LEFT := "Move Camera Left"
const ACTION_MOVE_RIGHT := "Move Camera Right"
const ACTION_MOVE_UP := "Move Camera Up"
const ACTION_MOVE_DOWN := "Move Camera Down"
const ACTION_FIRE := "Select Units"
const ACTION_AIM := "Unit Move Command"
const AIM_RAY_LENGTH := 1000.0

@export var camera_follow_agent_in_direct_mode: bool = true
@export var camera_follow_lerp_speed: float = 12.0
@export var aim_camera_edge_scroll_speed: float = 18.0
@export var aim_camera_max_offset: float = 18.0
@export var aim_mouse_edge_threshold_percentage: float = 0.035
@export_flags_3d_physics var aim_target_collision_mask: int = 7
@export_flags_3d_physics var aim_obstacle_collision_mask: int = 1

var _command_mode_enabled: bool = true
var _active_agent: PlayerAgent = null
var _camera_height_above_focus: float = 13.0
var _aim_camera_offset: Vector3 = Vector3.ZERO
var _aim_line_instance: MeshInstance3D
var _aim_line_mesh: ImmediateMesh
var _aim_line_material: StandardMaterial3D

func _ready() -> void:
	_setup_aim_line()

func set_command_mode_enabled(enabled: bool) -> void:
	if _command_mode_enabled == enabled:
		return

	_command_mode_enabled = enabled
	_active_agent = _find_agent()
	if _active_agent != null:
		_active_agent.set_agent_command_locked(_command_mode_enabled)
		_active_agent.set_agent_control_enabled(not _command_mode_enabled)

	var camera := get_viewport().get_camera_3d()
	if camera != null and _active_agent != null:
		_camera_height_above_focus = maxf(2.0, camera.global_position.y - _active_agent.global_position.y)

	if _command_mode_enabled:
		_aim_camera_offset = Vector3.ZERO
		_set_aim_line_visible(false)

func _physics_process(delta: float) -> void:
	if _command_mode_enabled:
		return

	_active_agent = _get_valid_agent()
	if _active_agent == null:
		_set_aim_line_visible(false)
		return

	var pointer_over_ui := _is_pointer_over_ui()
	var aiming := Input.is_action_pressed(ACTION_AIM) and not pointer_over_ui
	var aim_position := _get_mouse_aim_position()
	_active_agent.set_agent_control_input(
		_get_world_move_direction(),
		aim_position,
		Input.is_action_pressed(ACTION_FIRE) and not pointer_over_ui
	)
	_update_aim_camera_offset(delta, aiming)
	_update_camera(delta)
	_update_aim_line(aiming, aim_position)

func _get_valid_agent() -> PlayerAgent:
	if _active_agent != null and is_instance_valid(_active_agent):
		return _active_agent

	_active_agent = _find_agent()
	if _active_agent != null:
		_active_agent.set_agent_command_locked(false)
		_active_agent.set_agent_control_enabled(true)
	return _active_agent

func _find_agent() -> PlayerAgent:
	for node in get_tree().get_nodes_in_group("player_agent"):
		var agent := node as PlayerAgent
		if agent != null and is_instance_valid(agent):
			return agent
	return null

func _get_world_move_direction() -> Vector3:
	var screen_direction := Vector2.ZERO
	if Input.is_action_pressed(ACTION_MOVE_LEFT):
		screen_direction.x -= 1.0
	if Input.is_action_pressed(ACTION_MOVE_RIGHT):
		screen_direction.x += 1.0
	if Input.is_action_pressed(ACTION_MOVE_UP):
		screen_direction.y -= 1.0
	if Input.is_action_pressed(ACTION_MOVE_DOWN):
		screen_direction.y += 1.0

	if screen_direction.length_squared() > 1.0:
		screen_direction = screen_direction.normalized()

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO

	var camera_right := camera.global_transform.basis.x
	var camera_forward := -camera.global_transform.basis.z
	camera_right.y = 0.0
	camera_forward.y = 0.0

	return camera_right.normalized() * screen_direction.x + camera_forward.normalized() * -screen_direction.y

func _get_mouse_aim_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.INF

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)
	var ray_end := ray_origin + ray_direction * AIM_RAY_LENGTH
	var hit_position := _get_mouse_aim_collision(ray_origin, ray_end)
	if hit_position != Vector3.INF:
		return hit_position

	if is_zero_approx(ray_direction.y):
		return Vector3.INF

	var distance := -ray_origin.y / ray_direction.y
	if distance < 0.0:
		return Vector3.INF

	return ray_origin + ray_direction * distance

func _get_mouse_aim_collision(ray_origin: Vector3, ray_end: Vector3) -> Vector3:
	var world := get_viewport().get_world_3d()
	if world == null or aim_target_collision_mask == 0:
		return Vector3.INF

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, aim_target_collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if _active_agent != null and is_instance_valid(_active_agent):
		query.exclude = [_active_agent.get_rid()]

	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return Vector3.INF

	return result.get("position", Vector3.INF)

func _follow_agent_camera(delta: float) -> void:
	if not camera_follow_agent_in_direct_mode:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var focus_position := _active_agent.global_position + _aim_camera_offset
	var target_position := _get_camera_position_for_focus(camera, focus_position)
	if _aim_camera_offset == Vector3.ZERO:
		camera.global_position = target_position
	else:
		camera.global_position = camera.global_position.lerp(target_position, clampf(camera_follow_lerp_speed * delta, 0.0, 1.0))

func _update_camera(delta: float) -> void:
	_follow_agent_camera(delta)

func _get_camera_position_for_focus(camera: Camera3D, focus_position: Vector3) -> Vector3:
	var viewport_center := Vector2(get_viewport().size) * 0.5
	var center_ray := camera.project_ray_normal(viewport_center)
	if center_ray.y >= -0.001:
		return focus_position + Vector3.UP * _camera_height_above_focus

	var distance := _camera_height_above_focus / -center_ray.y
	return focus_position - center_ray * distance

func _update_aim_camera_offset(delta: float, aiming: bool) -> void:
	if not aiming:
		_aim_camera_offset = Vector3.ZERO
		return

	var pan_direction := _get_world_edge_camera_direction()
	_aim_camera_offset += pan_direction * aim_camera_edge_scroll_speed * delta
	_aim_camera_offset.y = 0.0
	if _aim_camera_offset.length() > aim_camera_max_offset:
		_aim_camera_offset = _aim_camera_offset.normalized() * aim_camera_max_offset

func _get_world_edge_camera_direction() -> Vector3:
	var viewport_size := Vector2(get_viewport().size)
	var threshold := viewport_size.x * aim_mouse_edge_threshold_percentage
	var mouse_position := get_viewport().get_mouse_position()
	var screen_direction := Vector2.ZERO

	if mouse_position.x < threshold:
		screen_direction.x = -1.0
	elif mouse_position.x > viewport_size.x - threshold:
		screen_direction.x = 1.0

	if mouse_position.y < threshold:
		screen_direction.y = -1.0
	elif mouse_position.y > viewport_size.y - threshold:
		screen_direction.y = 1.0

	if screen_direction.length_squared() > 1.0:
		screen_direction = screen_direction.normalized()

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO

	var camera_right := camera.global_transform.basis.x
	var camera_forward := -camera.global_transform.basis.z
	camera_right.y = 0.0
	camera_forward.y = 0.0
	return camera_right.normalized() * screen_direction.x + camera_forward.normalized() * -screen_direction.y

func _setup_aim_line() -> void:
	_aim_line_mesh = ImmediateMesh.new()
	_aim_line_material = StandardMaterial3D.new()
	_aim_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_line_material.albedo_color = Color(1.0, 0.0, 0.0, 1.0)
	_aim_line_material.no_depth_test = true

	_aim_line_instance = MeshInstance3D.new()
	_aim_line_instance.name = "AgentAimLine"
	_aim_line_instance.mesh = _aim_line_mesh
	_aim_line_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_line_instance.visible = false
	add_child(_aim_line_instance)

func _update_aim_line(aiming: bool, aim_position: Vector3) -> void:
	if not aiming or aim_position == Vector3.INF or _active_agent == null:
		_set_aim_line_visible(false)
		return

	var start_position := _active_agent.global_position + Vector3.UP * 0.7
	var end_position := aim_position
	if start_position.distance_squared_to(end_position) < 0.01:
		_set_aim_line_visible(false)
		return

	end_position = _get_obstructed_aim_end(start_position, end_position)
	_aim_line_mesh.clear_surfaces()
	_aim_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _aim_line_material)
	_aim_line_mesh.surface_add_vertex(start_position)
	_aim_line_mesh.surface_add_vertex(end_position)
	_aim_line_mesh.surface_end()
	_set_aim_line_visible(true)

func _get_obstructed_aim_end(start_position: Vector3, end_position: Vector3) -> Vector3:
	var world := get_viewport().get_world_3d()
	if world == null or aim_obstacle_collision_mask == 0:
		return end_position

	var query := PhysicsRayQueryParameters3D.create(start_position, end_position, aim_obstacle_collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if _active_agent != null and is_instance_valid(_active_agent):
		query.exclude = [_active_agent.get_rid()]

	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return end_position

	return result.get("position", end_position)

func _set_aim_line_visible(is_visible: bool) -> void:
	if _aim_line_instance != null:
		_aim_line_instance.visible = is_visible

func _is_pointer_over_ui() -> bool:
	var hovered_control := get_viewport().gui_get_hovered_control()
	while hovered_control != null:
		if hovered_control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return true
		hovered_control = hovered_control.get_parent() as Control
	return false
