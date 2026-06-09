extends Node

const HEAL_INJECTION := preload("res://assets/inventory/items/heal_injection.tres")
const GRENADE := preload("res://assets/inventory/items/grenade.tres")
const RIFLE := preload("res://assets/inventory/items/rifle.tres")
const MACHINE_GUN := preload("res://assets/inventory/items/machine_gun.tres")
const MAGAZINE := preload("res://assets/inventory/items/magazine.tres")
const GRENADE_THROW_SKILL := preload("res://assets/skills/grenade_throw.tres")
const RIFLE_EQUIPMENT := preload("res://assets/equipment/rifle.tres")
const MACHINE_GUN_EQUIPMENT := preload("res://assets/equipment/machine_gun.tres")
const InventoryItemStackScript := preload("res://scripts/inventory/inventory_item_stack.gd")
const InventoryPanelScript := preload("res://scripts/ui/hud/inventory_panel.gd")
const TEST_LEVEL := preload("res://scenes/levels/test_level/test_level.tscn")

var _failed := false

func _ready() -> void:
	_expect_item(HEAL_INJECTION, &"heal_injection", Vector2i(1, 1))
	_expect_item(GRENADE, &"grenade", Vector2i(1, 1))
	_expect_item(RIFLE, &"rifle", Vector2i(3, 2))
	_expect_item(MACHINE_GUN, &"machine_gun", Vector2i(4, 2))
	_expect_item(MAGAZINE, &"magazine", Vector2i(2, 1))
	_expect(GRENADE.linked_skill == GRENADE_THROW_SKILL, "grenade item should link to the grenade throw skill resource")
	_expect(RIFLE.equipment == RIFLE_EQUIPMENT, "rifle item should link to the rifle equipment resource")
	_expect(MACHINE_GUN.equipment == MACHINE_GUN_EQUIPMENT, "machine gun item should link to the machine gun equipment resource")
	_expect_test_level_items()
	_expect_test_level_agent_equipped_weapon_inventory()
	_expect_agent_weapon_updates_after_inventory_equipment_swap()
	_expect_pickup_then_prompt_update_does_not_keep_freed_item()

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("inventory_items_test: PASS")
		get_tree().quit(0)

func _expect_item(item: Resource, expected_id: StringName, expected_size: Vector2i) -> void:
	_expect(item != null, "item resource %s should load" % String(expected_id))
	if item == null:
		return
	_expect(item.id == expected_id, "item id should be %s" % String(expected_id))
	_expect(item.grid_size == expected_size, "%s should have grid size %s" % [String(expected_id), expected_size])

func _expect_test_level_items() -> void:
	var level := TEST_LEVEL.instantiate()
	add_child(level)
	var container := level.get_node_or_null("ItemsContainer")
	_expect(container != null, "TestLevel should contain ItemsContainer")
	if container == null:
		level.queue_free()
		return
	_expect(container.get_child_count() >= 5, "TestLevel should place the requested test inventory items")
	for child in container.get_children():
		_expect(child.get("item") != null, "world inventory item should have an item resource")
		_expect(child.has_method("create_stack"), "world inventory item should be able to create an inventory stack")
	level.queue_free()

func _expect_test_level_agent_equipped_weapon_inventory() -> void:
	var level := TEST_LEVEL.instantiate()
	add_child(level)
	var agent = level.get_node_or_null("UnitsContainer/Agent")
	_expect(agent != null, "TestLevel should contain player Agent")
	if agent == null:
		level.queue_free()
		return

	var inventory: Resource = agent.get_inventory()
	var equipment_slots: Resource = inventory.get("equipment_slots")
	var weapon_stack: Resource = equipment_slots.get_equipped_stack(&"weapon")
	_expect(weapon_stack != null, "player agent inventory weapon slot should show the currently equipped weapon")
	_expect(weapon_stack.item == MACHINE_GUN, "player agent weapon slot should use the machine gun inventory item")
	level.queue_free()

func _expect_agent_weapon_updates_after_inventory_equipment_swap() -> void:
	var level := TEST_LEVEL.instantiate()
	add_child(level)
	var agent = level.get_node_or_null("UnitsContainer/Agent")
	_expect(agent != null, "weapon swap test should find player Agent")
	if agent == null:
		level.queue_free()
		return

	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory: Resource = agent.get_inventory()
	var backpack: Resource = inventory.get_grid(&"backpack")
	var machine_gun_stack: Resource = inventory.equipment_slots.get_equipped_stack(&"weapon")
	var rifle_stack: Resource = InventoryItemStackScript.new()
	rifle_stack.item = RIFLE
	var rifle_placement: Resource = backpack.place(rifle_stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	var machine_gun_drag: Dictionary = panel.make_equipment_drag_data(&"weapon")
	_expect(panel.drop_data_on_grid(machine_gun_drag, &"backpack", Vector2i(3, 0)), "machine gun should move from weapon slot to backpack")
	var rifle_drag: Dictionary = panel.make_drag_data(&"backpack", Vector2i(0, 0), rifle_placement)
	_expect(panel.drop_data_on_equipment_slot(rifle_drag, &"weapon"), "rifle should move from backpack to weapon slot")

	_expect(inventory.equipment_slots.get_equipped_stack(&"weapon").item == RIFLE, "inventory weapon slot should contain rifle after swap")
	_expect(agent.equipped_weapon == RIFLE_EQUIPMENT, "player agent should use the rifle equipment after inventory weapon swap")
	_expect(agent.perform_direct_ranged_attack_at(agent.global_position + Vector3(3.0, 0.7, 0.0)), "player agent should still fire after swapping weapons in inventory")
	panel.queue_free()
	level.queue_free()

func _expect_pickup_then_prompt_update_does_not_keep_freed_item() -> void:
	var level := TEST_LEVEL.instantiate()
	add_child(level)
	var agent = level.get_node_or_null("UnitsContainer/Agent")
	var item_node = level.get_node_or_null("ItemsContainer/HealInjection")
	_expect(agent != null and item_node != null, "pickup test should find agent and a world item")
	if agent == null or item_node == null:
		level.queue_free()
		return

	agent.global_position = item_node.global_position
	_expect(agent.try_pickup_nearest_item(), "agent should pick up a nearby item")
	agent.call("_update_nearby_pickup_prompt")
	level.queue_free()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	_failed = true
	push_error(message)
