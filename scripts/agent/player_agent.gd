extends Unit
class_name PlayerAgent

const InventoryContainerScript := preload("res://scripts/inventory/inventory_container.gd")
const InventoryItemStackScript := preload("res://scripts/inventory/inventory_item_stack.gd")
const RIFLE_ITEM := preload("res://assets/inventory/items/rifle.tres")
const MACHINE_GUN_ITEM := preload("res://assets/inventory/items/machine_gun.tres")
const SNIPER_RIFLE_EQUIPMENT := preload("res://assets/equipment/sniper_rifle.tres")

var _agent_control_enabled: bool = false
var _agent_command_locked: bool = false
var _move_direction: Vector3 = Vector3.ZERO
var _aim_position: Vector3 = Vector3.INF
var _fire_requested: bool = false
var _attack_timer: float = 0.0
var _nearest_pickup_item = null
var _pickup_feedback_label: Label3D
var _pickup_feedback_time_remaining: float = 0.0
var _connected_inventory: Resource

@export var inventory: Resource
@export var pickup_interaction_radius: float = 1.6
@export var pickup_feedback_duration: float = 1.4

func _init() -> void:
	if inventory == null:
		inventory = InventoryContainerScript.new()

func _ready() -> void:
	is_agent = true
	is_player_controllable = false
	_ensure_default_inventory()
	super._ready()
	_sync_equipped_weapon_inventory()
	_connect_inventory_changed()
	_setup_pickup_feedback_label()
	add_to_group("player_agent")
	remove_from_group("selectable_units")
	_disable_npc_brain()

func is_player_agent() -> bool:
	return true

func get_inventory() -> Resource:
	_ensure_default_inventory()
	_connect_inventory_changed()
	return inventory

func set_agent_control_enabled(enabled: bool) -> void:
	if _agent_control_enabled == enabled:
		return

	_agent_control_enabled = enabled
	if _agent_control_enabled:
		set_agent_command_locked(false)
		_prepare_for_player_control()
	else:
		_stop_agent_motion()

func set_agent_command_locked(locked: bool) -> void:
	_agent_command_locked = locked
	if _agent_command_locked:
		_agent_control_enabled = false
		_prepare_for_player_control()
		_stop_agent_motion()

func set_agent_control_input(move_direction: Vector3, aim_position: Vector3, fire_requested: bool) -> void:
	_move_direction = move_direction
	_move_direction.y = 0.0
	if _move_direction.length_squared() > 1.0:
		_move_direction = _move_direction.normalized()
	_aim_position = aim_position
	_fire_requested = fire_requested

func _physics_process(delta: float) -> void:
	_process_active_effects(delta)
	_process_skill_cooldowns(delta)
	_process_recoil_recovery(delta)
	if status_indicator_space != null and status_indicator_space.visible:
		_update_status_indicator_space_position()
	_update_nearby_pickup_prompt()
	_process_pickup_feedback(delta)

	if _agent_command_locked:
		_stop_agent_motion()
		move_and_slide()
		return

	if _agent_control_enabled:
		_process_agent_control(delta)
		return

	_stop_agent_motion()
	move_and_slide()

func _process_agent_control(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_face_mouse_aim_position()

	var move_speed := navigation_agent.max_speed if navigation_agent != null else _base_navigation_max_speed
	velocity = _move_direction * move_speed
	if navigation_agent != null:
		navigation_agent.velocity = velocity
		navigation_agent.target_position = global_position
	move_and_slide()

	if _fire_requested and _attack_timer <= 0.0:
		if perform_direct_ranged_attack_at(_aim_position):
			_attack_timer = _get_agent_attack_cooldown()

func _face_mouse_aim_position() -> void:
	if _aim_position == Vector3.INF:
		return

	var face_direction := _aim_position - global_position
	face_direction.y = 0.0
	if face_direction.length_squared() < 0.001:
		return

	look_at(global_position + face_direction, Vector3.UP)

func perform_direct_ranged_attack_at(target_position: Vector3) -> bool:
	if equipped_weapon == null or equipped_weapon.projectile_scene == null:
		return false
	if target_position == Vector3.INF:
		return false

	var fire_origin := global_position + Vector3.UP * 0.7
	var fire_direction := target_position - fire_origin
	if fire_direction.length_squared() < 0.001:
		return false

	var attack_data := _create_ranged_attack_data().with_resolved_aim(true)
	if _spawn_weapon_projectiles(fire_origin, fire_direction.normalized(), attack_data) == 0:
		return false
	_apply_weapon_recoil()
	return true

func _get_agent_attack_cooldown() -> float:
	if equipped_weapon != null:
		return equipped_weapon.get_attack_cooldown(equipment_attack_speed_multiplier * _get_effect_attack_speed_multiplier())
	return melee_cooldown

func _prepare_for_player_control() -> void:
	clear_player_command()
	hold_position_enabled = false
	movement_enabled = true
	clear_cover(false)
	if state_machine != null:
		state_machine.stop()
	_disable_npc_brain()

func _stop_agent_motion() -> void:
	_move_direction = Vector3.ZERO
	_fire_requested = false
	velocity = Vector3.ZERO
	if navigation_agent != null:
		navigation_agent.velocity = Vector3.ZERO
		navigation_agent.target_position = global_position

func _disable_npc_brain() -> void:
	if ai_brain != null:
		ai_brain.set_process(false)
		ai_brain.set_physics_process(false)
		if ai_brain.has_method("set_enabled"):
			ai_brain.set_enabled(false)

func try_pickup_nearest_item() -> bool:
	_update_nearby_pickup_prompt()
	if _nearest_pickup_item == null or not is_instance_valid(_nearest_pickup_item):
		return false
	if not _nearest_pickup_item.has_method("create_stack"):
		return false

	var stack: Resource = _nearest_pickup_item.call("create_stack")
	if stack == null:
		return false
	var placement: Resource = inventory.call("auto_place", stack, [&"backpack", &"pouch"])
	if placement == null:
		_show_pickup_feedback("인벤토리 공간부족!")
		return false

	var picked_item = _nearest_pickup_item
	_nearest_pickup_item = null
	_set_pickup_prompt(picked_item, false)
	if is_instance_valid(picked_item):
		picked_item.queue_free()
	return true

func _ensure_default_inventory() -> void:
	if inventory == null:
		inventory = InventoryContainerScript.new()
	if inventory.has_method("get_grid") and inventory.call("get_grid", &"backpack") == null:
		inventory.call("add_grid", &"backpack", Vector2i(10, 6))
	if inventory.has_method("get_grid") and inventory.call("get_grid", &"pouch") == null:
		inventory.call("add_grid", &"pouch", Vector2i(4, 2))

func _sync_equipped_weapon_inventory() -> void:
	if equipped_weapon == null:
		return
	_ensure_default_inventory()
	var weapon_item := _get_inventory_item_for_equipped_weapon()
	if weapon_item == null:
		return

	var equipment_slots: Resource = inventory.get("equipment_slots")
	if equipment_slots == null:
		return
	var current_stack: Resource = equipment_slots.call("get_equipped_stack", &"weapon")
	if current_stack != null and current_stack.get("item") == weapon_item:
		return

	var stack: Resource = InventoryItemStackScript.new()
	stack.item = weapon_item
	stack.quantity = 1
	equipment_slots.call("equip", &"weapon", stack)

func _sync_equipped_weapon_from_inventory() -> void:
	_ensure_default_inventory()
	if inventory == null or not inventory.has_method("get_equipped_weapon"):
		return

	var inventory_weapon: Resource = inventory.call("get_equipped_weapon")
	var next_weapon: WeaponEquipment = inventory_weapon as WeaponEquipment
	if equipped_weapon == next_weapon:
		return

	equipped_weapon = next_weapon
	current_recoil_degrees = 0.0
	_attack_timer = 0.0
	_sync_combat_ranges()

func sync_equipped_weapon_from_inventory() -> void:
	_sync_equipped_weapon_from_inventory()

func _connect_inventory_changed() -> void:
	if inventory == null or _connected_inventory == inventory:
		return

	if _connected_inventory != null \
			and _connected_inventory.has_signal("inventory_changed") \
			and _connected_inventory.is_connected("inventory_changed", _on_inventory_changed):
		_connected_inventory.disconnect("inventory_changed", _on_inventory_changed)

	_connected_inventory = inventory
	if _connected_inventory.has_signal("inventory_changed") \
			and not _connected_inventory.is_connected("inventory_changed", _on_inventory_changed):
		_connected_inventory.connect("inventory_changed", _on_inventory_changed)

func _on_inventory_changed() -> void:
	_sync_equipped_weapon_from_inventory()

func _get_inventory_item_for_equipped_weapon() -> Resource:
	if equipped_weapon == RIFLE_ITEM.equipment:
		return RIFLE_ITEM
	if equipped_weapon == MACHINE_GUN_ITEM.equipment:
		return MACHINE_GUN_ITEM
	if equipped_weapon == SNIPER_RIFLE_EQUIPMENT:
		return null
	return null

func _update_nearby_pickup_prompt() -> void:
	if _nearest_pickup_item != null and not is_instance_valid(_nearest_pickup_item):
		_nearest_pickup_item = null

	var nearest_item = null
	var nearest_distance_sq := pickup_interaction_radius * pickup_interaction_radius
	for node in get_tree().get_nodes_in_group("inventory_world_items"):
		var item_node := node as Node3D
		if item_node == null or not is_instance_valid(item_node):
			continue
		var distance_sq := global_position.distance_squared_to(item_node.global_position)
		if distance_sq > nearest_distance_sq:
			continue
		nearest_distance_sq = distance_sq
		nearest_item = item_node

	if _nearest_pickup_item != nearest_item:
		_set_pickup_prompt(_nearest_pickup_item, false)
		_nearest_pickup_item = nearest_item
		_set_pickup_prompt(_nearest_pickup_item, true)

func _set_pickup_prompt(item_node, should_show: bool) -> void:
	if item_node != null and is_instance_valid(item_node) and item_node.has_method("set_pickup_prompt_visible"):
		item_node.call("set_pickup_prompt_visible", should_show)

func _setup_pickup_feedback_label() -> void:
	_pickup_feedback_label = Label3D.new()
	_pickup_feedback_label.name = "PickupFeedbackLabel"
	_pickup_feedback_label.position = Vector3(0.0, 1.45, 0.0)
	_pickup_feedback_label.pixel_size = 0.006
	_pickup_feedback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pickup_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_feedback_label.visible = false
	add_child(_pickup_feedback_label)

func _show_pickup_feedback(text_value: String) -> void:
	if _pickup_feedback_label == null:
		return
	_pickup_feedback_label.text = text_value
	_pickup_feedback_label.visible = true
	_pickup_feedback_time_remaining = pickup_feedback_duration

func _process_pickup_feedback(delta: float) -> void:
	if _pickup_feedback_label == null or not _pickup_feedback_label.visible:
		return
	_pickup_feedback_time_remaining -= delta
	if _pickup_feedback_time_remaining <= 0.0:
		_pickup_feedback_label.visible = false
