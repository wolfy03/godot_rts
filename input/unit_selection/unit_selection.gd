extends Node2D

class_name UnitSelection

const MAX_UNIT_SELECTION_COUNT = 300
const SELECT_UNIT_ACTION = 'Select Units'
const KEEP_UNITS_SELECTED = 'Keep Units Selected'

const UNIT_SELECTION_CHANGED = 'unit_selection_changed'

signal unit_selection_changed(selected_units: Array[Unit])

var dragging: bool
var start_position: Vector2
var end_position: Vector2

var _selected_unit: Dictionary = {}

func _input(_event: InputEvent):
	if Input.is_action_just_pressed(SELECT_UNIT_ACTION):
		_start_selection()
	elif Input.is_action_pressed(SELECT_UNIT_ACTION):
		end_position = _get_mouse_pos()
		_select_units_in_rect()
	elif Input.is_action_just_released(SELECT_UNIT_ACTION):
		_select_units_in_rect()
		dragging = false

func _start_selection():
	start_position = _get_mouse_pos()
	end_position = _get_mouse_pos()
	
	if !Input.is_action_pressed(KEEP_UNITS_SELECTED):
		_clear_selected_units()
		_emit_unit_selection_changed()
	
	dragging = true

func _get_mouse_pos() -> Vector2:
	return get_global_mouse_position()

func _clear_selected_units():
	for unit: Unit in _selected_unit.values():
		unit.on_selection_changed(false)
	
	_selected_unit = {}

func _emit_unit_selection_changed():
	emit_signal(UNIT_SELECTION_CHANGED, _selected_unit)

func _process(_delta: float):
	queue_redraw()

func _draw():
	if dragging:
		_drawBox()

func _drawBox():
	var rect = Rect2(start_position, end_position - start_position)
	draw_rect(rect, Color.GREEN, false, 2)

func _select_units_in_rect():
	if !Input.is_action_pressed(KEEP_UNITS_SELECTED):
		_clear_selected_units()
	
	for result_item: Dictionary in _get_selection_results():
		if !result_item.collider is Unit:
			continue;
		
		var unit: Unit = result_item.collider
		var unit_id = unit.get_instance_id()
		
		if _selected_unit.has(unit_id):
			continue;
		
		_selected_unit[unit_id] = unit
		
		if !unit.tree_exiting.is_connected(_remove_dead_unit.bind(unit)):
			unit.tree_exiting.connect(_remove_dead_unit.bind(unit))
		
		unit.on_selection_changed(true)
	
	_emit_unit_selection_changed()

func _get_selection_results() -> Array[Dictionary]:
	var query = PhysicsShapeQueryParameters2D.new()
	query.collision_mask = 0b10
	
	var diff = end_position - start_position
	query.transform = Transform2D(0, start_position + (diff / 2))
	
	var selection_rect = RectangleShape2D.new()
	selection_rect.size = abs(diff)
	query.shape = selection_rect
	
	var space = get_world_2d().direct_space_state
	return space.intersect_shape(query, MAX_UNIT_SELECTION_COUNT)

func _remove_dead_unit(unit: Unit):
	_selected_unit.erase(unit.get_instance_id())
