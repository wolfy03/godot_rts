extends Node

const InventoryItemDefinitionScript := preload("res://scripts/inventory/inventory_item_definition.gd")
const InventoryItemStackScript := preload("res://scripts/inventory/inventory_item_stack.gd")
const InventoryGridScript := preload("res://scripts/inventory/inventory_grid.gd")
const InventoryContainerScript := preload("res://scripts/inventory/inventory_container.gd")
const InventoryEquipmentSlotsScript := preload("res://scripts/inventory/inventory_equipment_slots.gd")
const EquipmentScript := preload("res://scripts/equipment/equipment.gd")
const WeaponEquipmentScript := preload("res://scripts/equipment/weapon_equipment.gd")

var _failed := false

func _ready() -> void:
	_test_grid_rejects_overlap_and_bounds()
	_test_grid_rotation_changes_footprint()
	_test_equipment_slots_accept_matching_equipment()
	_test_inventory_container_exposes_named_grids()
	_test_inventory_container_moves_between_grids()

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("inventory_core_test: PASS")
		get_tree().quit(0)

func _test_grid_rejects_overlap_and_bounds() -> void:
	var grid := InventoryGridScript.new()
	grid.configure(Vector2i(4, 3))

	var item := _make_item(&"medkit", Vector2i(2, 2))
	var first_stack := InventoryItemStackScript.new()
	first_stack.item = item
	var second_stack := InventoryItemStackScript.new()
	second_stack.item = item

	var first_placement := grid.place(first_stack, Vector2i(0, 0))
	_expect(first_placement != null, "grid should place a 2x2 item inside bounds")
	_expect(not grid.can_place(second_stack, Vector2i(1, 1)), "grid should reject overlapping placements")
	_expect(not grid.can_place(second_stack, Vector2i(3, 2)), "grid should reject placements outside bounds")
	_expect(grid.place(second_stack, Vector2i(2, 0)) != null, "grid should place an item in a free area")

func _test_grid_rotation_changes_footprint() -> void:
	var grid := InventoryGridScript.new()
	grid.configure(Vector2i(2, 3))

	var rifle := _make_item(&"rifle", Vector2i(3, 1))
	rifle.can_rotate = true
	var stack := InventoryItemStackScript.new()
	stack.item = rifle

	_expect(not grid.can_place(stack, Vector2i(0, 0), false), "unrotated 3x1 item should not fit in a 2-wide grid")
	_expect(grid.can_place(stack, Vector2i(0, 0), true), "rotated 1x3 item should fit in a 2x3 grid")

func _test_equipment_slots_accept_matching_equipment() -> void:
	var loadout := InventoryEquipmentSlotsScript.new()
	loadout.configure_slots([&"weapon", &"armor", &"utility"])

	var weapon := WeaponEquipmentScript.new()
	weapon.display_name = "Test Rifle"
	var weapon_item := _make_item(&"test_rifle", Vector2i(3, 1), weapon)
	var weapon_stack := InventoryItemStackScript.new()
	weapon_stack.item = weapon_item

	var utility := EquipmentScript.new()
	utility.display_name = "Utility Pouch"
	utility.slot = Equipment.Slot.UTILITY
	var utility_item := _make_item(&"utility_pouch", Vector2i(1, 1), utility)
	var utility_stack := InventoryItemStackScript.new()
	utility_stack.item = utility_item

	_expect(loadout.equip(&"weapon", weapon_stack), "weapon equipment should equip to the weapon slot")
	_expect(not loadout.equip(&"armor", weapon_stack), "weapon equipment should not equip to the armor slot")
	_expect(loadout.equip(&"utility", utility_stack), "utility equipment should equip to utility slot")
	_expect(loadout.get_equipped_equipment().has(weapon), "loadout should expose equipped Equipment resources")

func _test_inventory_container_exposes_named_grids() -> void:
	var inventory := InventoryContainerScript.new()
	var backpack := inventory.add_grid(&"backpack", Vector2i(5, 4))
	var pouch := inventory.add_grid(&"pouch", Vector2i(2, 2))

	_expect(backpack != null, "inventory container should create a named backpack grid")
	_expect(pouch != null, "inventory container should create a named pouch grid")
	_expect(inventory.get_grid(&"backpack") == backpack, "inventory container should return grids by id")
	_expect(inventory.get_grid_ids().has(&"pouch"), "inventory container should expose grid ids")

func _test_inventory_container_moves_between_grids() -> void:
	var inventory := InventoryContainerScript.new()
	var backpack := inventory.add_grid(&"backpack", Vector2i(4, 4))
	var pouch := inventory.add_grid(&"pouch", Vector2i(2, 2))

	var item := _make_item(&"bandage", Vector2i(1, 1))
	var stack := InventoryItemStackScript.new()
	stack.item = item
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))

	_expect(inventory.move_between_grids(&"backpack", placement, &"pouch", Vector2i(1, 1)), "inventory container should move placements between grids")
	_expect(backpack.get_placement_for_stack(stack) == null, "source grid should release moved stack")
	_expect(pouch.get_placement_for_stack(stack) != null, "target grid should receive moved stack")

func _make_item(id: StringName, size: Vector2i, equipment: Equipment = null) -> InventoryItemDefinition:
	var item := InventoryItemDefinitionScript.new()
	item.id = id
	item.display_name = String(id)
	item.grid_size = size
	item.equipment = equipment
	return item

func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	_failed = true
	push_error(message)
