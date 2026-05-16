extends Area3D
class_name MoveCommandHandle

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _selected_units: Dictionary

var _click_is_inside: bool
var _sphere: SphereShape3D
var _arrived_units: Dictionary = {}

func _ready():
	_sphere = collision_shape.shape
	_sphere.radius = 0.45
	
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	if !_click_is_inside:
		return
	
	if not (body is Unit) || !_selected_units.has(body.get_instance_id()):
		return
	
	var unit: Unit = body
	unit.navigation_agent.target_position = unit.global_position
	
	_arrived_units[body.get_instance_id()] = unit
	
	if _arrived_units.size() >= _selected_units.size():
		queue_free()
		return
	
	_resize_collision_circle()
	
func _resize_collision_circle():
	while _not_all_units_fully_enclosed():
		_sphere.radius += 0.1
	
func _not_all_units_fully_enclosed() -> bool:
	for unit: Unit in _arrived_units.values():
		var unit_shape: SphereShape3D = unit.colission_shape.shape
		var dist = global_position.distance_to(unit.global_position)
		
		if dist + unit_shape.radius > _sphere.radius:
			return true
			
	return false

func move_selected_units(
	selected_units: Dictionary, 
	click_position: Vector3,
	attack_move: bool
):
	global_position = click_position
	_selected_units = selected_units.duplicate()
	
	var top_left: Vector3 = Vector3.INF
	var bottom_right: Vector3 = -Vector3.INF
	
	for unit: Unit in _selected_units.values():
		unit.tree_exiting.connect(_remove_dead_unit.bind(unit))
		
		var pos = unit.global_position
		
		if pos.x < top_left.x:
			top_left.x = pos.x
		if pos.x > bottom_right.x:
			bottom_right.x = pos.x
		if pos.z < top_left.z:
			top_left.z = pos.z
		if pos.z > bottom_right.z:
			bottom_right.z = pos.z

	var selection_center = (bottom_right + top_left) / 2
	selection_center.y = global_position.y
	var center_click_diff = (selection_center - global_position).length()
	_click_is_inside = center_click_diff < (bottom_right - top_left).length()
	
	for unit: Unit in _selected_units.values():
		var target_unit_pos: Vector3
		
		if _click_is_inside:
			target_unit_pos = global_position
		else:
			target_unit_pos = global_position + unit.global_position - selection_center
			target_unit_pos.y = global_position.y
		
		var data: MoveState.MoveCommandData = MoveState.MoveCommandData.new()
		data.target_position = target_unit_pos
		data.attack_move = attack_move
		unit.state_machine.transition_to_state(MoveState.ID, data)

func remove_units(units: Dictionary):
	for unit_id in units.keys():
		_selected_units.erase(unit_id)
	
	if _selected_units.is_empty():
		queue_free()

func _remove_dead_unit(unit: Unit):
	_selected_units.erase(unit.get_instance_id())
	_arrived_units.erase(unit.get_instance_id())
