extends Area2D
class_name MoveCommandHandle

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _selected_units: Dictionary

var _click_is_inside: bool
var _circle: CircleShape2D
var _arrived_units: Dictionary = {}

func _ready():
	_circle = collision_shape.shape
	_circle.radius = 8
	
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	if !_click_is_inside:
		return
	
	if !body is Unit || !_selected_units.has(body.get_instance_id()):
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
		_circle.radius += 1
	
func _not_all_units_fully_enclosed() -> bool:
	for unit: Unit in _arrived_units.values():
		var unit_circle: CircleShape2D = unit.colission_shape.shape
		var dist = position.distance_to(unit.global_position)
		
		if dist + unit_circle.radius > _circle.radius:
			return true
			
	return false

func move_selected_units(
	selected_units: Dictionary, 
	click_position: Vector2,
	attack_move: bool
):
	position = click_position
	_selected_units = selected_units.duplicate()
	
	var top_left: Vector2 = Vector2.INF
	var bottom_right: Vector2 = -Vector2.INF
	
	for unit: Unit in _selected_units.values():
		unit.tree_exiting.connect(_remove_dead_unit.bind(unit))
		
		var pos = unit.global_position
		
		if pos.x < top_left.x:
			top_left.x = pos.x
		if pos.x > bottom_right.x:
			bottom_right.x = pos.x
		if pos.y < top_left.y:
			top_left.y = pos.y
		if pos.y > bottom_right.y:
			bottom_right.y = pos.y

	var selection_center = (bottom_right + top_left) / 2
	var center_click_diff = (selection_center - position).length()
	_click_is_inside = center_click_diff < (bottom_right - top_left).length()
	
	for unit: Unit in _selected_units.values():
		var target_unit_pos: Vector2
		
		if _click_is_inside:
			target_unit_pos = position
		else:
			target_unit_pos = position + unit.global_position - selection_center
		
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

