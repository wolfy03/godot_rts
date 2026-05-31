extends Node
class_name StateMachine

@export var initial_state_id: String

var _states: Dictionary = Dictionary()
var _current_state_id: String = ""
var _unit: Unit
var _is_running: bool = true

func _ready():
	_unit = owner as Unit
	
	if _unit == null:
		_unit = get_parent() as Unit
	
	if _unit == null:
		push_error("StateMachine must be owned by Unit or child of Unit.")
		_is_running = false
		return
		
	var states: Array[Node] = find_children("*State", "", true, false)
	
	for node in states:
		var state := node as State
		if state == null:
			continue
		
		var id := state._get_id()
		if id == "":
			push_warning("%s has empty state id." % state.name)
			continue
		
		if _states.has(id):
			push_warning("Duplicated state id: %s" % id)
			continue
		
		state.setup(_unit, self)
		_states[id] = state
		state.transition_to_state.connect(transition_to_state)
	
	if initial_state_id != "":
		transition_to_state(initial_state_id, null)

func stop():
	_is_running = false
	
	if _current_state_id != "" and _states.has(_current_state_id):
		var current_state: State = _states[_current_state_id]
		current_state._deactivate()
	
	_current_state_id = ""

func get_current_state_id() -> String:
	return _current_state_id

func is_current_state(state_id: String) -> bool:
	return _current_state_id == state_id

func transition_to_state(state_id: String, data):
	if !_is_running:
		return
	
	if !is_instance_valid(_unit) or _unit._is_dead:
		stop()
		return
	
	if !_states.has(state_id):
		push_warning("State not found: %s" % state_id)
		return
	
	if _current_state_id == state_id:
		var same_state: State = _states[state_id]
		same_state._activate(data)
		return
	
	if _current_state_id != "" and _states.has(_current_state_id):
		var current_state: State = _states[_current_state_id]
		current_state._deactivate()
	
	_current_state_id = state_id
	
	var state: State = _states[_current_state_id]
	state._activate(data)

class State extends Node3D:
	signal transition_to_state(state_id: String, data)
	
	var _is_active: bool = false
	var _unit: Unit
	var _state_machine: StateMachine
	
	func setup(unit: Unit, state_machine: StateMachine):
		_unit = unit
		_state_machine = state_machine
	
	func _get_id() -> String:
		return ""
	
	func _activate(_data):
		if !is_instance_valid(_unit) or _unit._is_dead:
			_is_active = false
			return
		
		_is_active = true
	
	func _deactivate():
		_is_active = false
	
	func _process(delta: float):
		if !_is_active:
			return
		
		if !is_instance_valid(_unit) or _unit._is_dead:
			_deactivate()
			return
		
		_process_state(delta)
	
	func _process_state(_delta: float):
		pass
