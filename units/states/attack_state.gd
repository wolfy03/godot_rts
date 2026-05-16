extends StateMachine.State
class_name AttackState
 
@onready var sprite: AnimatedSprite2D = %UnitSprite

@export var attack_damage: int = 40
@export var attack_cooldown: float = 1.0

const ID = "ATTACK_STATE"

var _attack_timer: float
var _attack_target: Unit

func _get_id() -> String:
	return ID

func _ready():
	pass

func _activate(data):
	super._activate(data)
	_attack_target = data
	_unit.look_at(_attack_target.global_position)
	_unit.set_deferred("freeze", true)
	sprite.play("Attack")
	_attack_timer = attack_cooldown

func _deactivate():
	super._deactivate()
	_unit.set_deferred("freeze", false)
	sprite.stop()

func _process_state(delta: float):
	if !_attack_target || _attack_target._current_health <= 0:
		_exit()
		return
	
	_attack_timer -= delta
	_unit.look_at(_attack_target.global_position)
	
	if _attack_timer <= 0:
		_attack_target.receive_damage(attack_damage)
		_attack_timer = attack_cooldown
		
		if _attack_target._current_health <= 0:
			_exit()

func _exit():
	_deactivate()
	
	if _unit.last_move_command_data:
		transition_to_state.emit(MoveState.ID, _unit.last_move_command_data)
	else:
		transition_to_state.emit(IdleState.ID, null)

func _on_attack_range_area_body_exited(body: Node2D):
	if _is_active && body == _attack_target && _attack_target._current_health > 0:
		_deactivate()
		transition_to_state.emit(ChaseState.ID, _attack_target)

func _on_attack_leash_range_body_exited(body: Node2D):
	if body == _attack_target && _attack_target._current_health > 0:
		_exit()
