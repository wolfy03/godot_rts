extends CharacterBody3D
class_name Unit

@onready var colission_shape: CollisionShape3D = %CollisionShape3D
@onready var navigation_agent: NavigationAgent3D = %NavigationAgent
@onready var unit_selected_sprite: Node3D = %UnitSelectedSprite
@onready var state_machine: StateMachine = %StateMachine
@onready var enemy_detection_area: Area3D = %EnemyDetectionArea

@export var max_health: int = 100

var last_move_command_data: MoveState.MoveCommandData
var movement_enabled: bool = true

var _nearest_position_to_target: Vector3 = Vector3.INF
var _current_health: int
var _is_dead: bool = false

func _ready():
	if collision_layer & 0b10:
		add_to_group("selectable_units")
	navigation_agent.velocity_computed.connect(_on_nav_velocity_computed)
	_current_health = max_health

func on_selection_changed(selected: bool):
	unit_selected_sprite.visible = selected

func attack_nearest_unit_in_range() -> Unit:
	if !enemy_detection_area:
		return null
	
	var enemies = enemy_detection_area.get_overlapping_bodies()
	
	if enemies.is_empty():
		return null
	
	enemies.sort_custom(_sort_nearest)
	
	var enemy: Unit = enemies[0]
	state_machine.transition_to_state(ChaseState.ID, enemy)
	return enemy

func _sort_nearest(a: Node3D, b: Node3D) -> bool:
	var dist_a = global_position.distance_to(a.global_position)
	var dist_b = global_position.distance_to(b.global_position)
	return dist_a < dist_b

func receive_damage(amount: int):
	_current_health -= amount
	
	if _current_health <= 0:
		die()

func die():
	if _is_dead:
		return
	
	_is_dead = true
	
	if state_machine:
		state_machine.stop()
	
	if enemy_detection_area:
		enemy_detection_area.monitoring = false
		enemy_detection_area.monitorable = false
		
	queue_free()
	
func _on_nav_velocity_computed(safe_velocity: Vector3):
	velocity = safe_velocity
	move_and_slide()

func _physics_process(_delta: float):
	if !movement_enabled:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	if _nearest_position_to_target == Vector3.INF:
		_nearest_position_to_target = global_position
	elif navigation_agent.distance_to_target() < _nearest_position_to_target.distance_to(navigation_agent.target_position):
		_nearest_position_to_target = global_position
	
	var next_path_pos: Vector3 = navigation_agent.get_next_path_position()
	
	if next_path_pos.distance_to(navigation_agent.target_position) > _nearest_position_to_target.distance_to(navigation_agent.target_position):
		navigation_agent.target_position = navigation_agent.target_position
	
	var new_velocity: Vector3 = next_path_pos - global_position
	new_velocity.y = 0
	new_velocity = new_velocity.normalized() * navigation_agent.max_speed
	navigation_agent.velocity = new_velocity

	_look_at_ground_position(navigation_agent.target_position)

func _look_at_ground_position(target_position: Vector3):
	var look_target = Vector3(target_position.x, global_position.y, target_position.z)
	if global_position.distance_squared_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)
