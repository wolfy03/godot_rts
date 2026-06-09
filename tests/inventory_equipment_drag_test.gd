extends Node

const InventoryContainerScript := preload("res://scripts/inventory/inventory_container.gd")
const InventoryItemDefinitionScript := preload("res://scripts/inventory/inventory_item_definition.gd")
const InventoryItemStackScript := preload("res://scripts/inventory/inventory_item_stack.gd")
const InventoryPanelScript := preload("res://scripts/ui/hud/inventory_panel.gd")

var _failed := false

func _ready() -> void:
	_test_equipped_stack_moves_to_grid()
	_test_matching_grid_stack_equips()
	_test_wrong_slot_rejects_stack()
	_test_equipment_slot_changes_emit_inventory_changed()
	_test_drop_preview_cells_follow_drag_footprint()
	_test_active_drag_rotation_keeps_grab_offset()

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("inventory_equipment_drag_test: PASS")
		get_tree().quit(0)

func _test_equipped_stack_moves_to_grid() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var stack: Resource = _make_equipment_stack(&"rifle", Vector2i(3, 2), [&"weapon"])
	_expect(inventory.equip(&"weapon", stack), "setup should equip weapon")
	panel.set_inventory(inventory)

	var drag_data: Dictionary = panel.make_equipment_drag_data(&"weapon")
	_expect(panel.drop_data_on_grid(drag_data, &"backpack", Vector2i(0, 0)), "equipped stack should move to grid")
	_expect(inventory.equipment_slots.get_equipped_stack(&"weapon") == null, "weapon slot should be empty")
	_expect(backpack.get_placement_for_stack(stack) != null, "backpack should contain unequipped stack")
	panel.queue_free()

func _test_matching_grid_stack_equips() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var stack: Resource = _make_equipment_stack(&"rifle", Vector2i(3, 2), [&"weapon"])
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	var drag_data: Dictionary = panel.make_drag_data(&"backpack", Vector2i(0, 0), placement)
	_expect(panel.drop_data_on_equipment_slot(drag_data, &"weapon"), "matching grid stack should equip")
	_expect(backpack.get_placement_for_stack(stack) == null, "equipped stack should leave grid")
	_expect(inventory.equipment_slots.get_equipped_stack(&"weapon") == stack, "weapon slot should hold stack")
	panel.queue_free()

func _test_wrong_slot_rejects_stack() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var stack: Resource = _make_equipment_stack(&"tool", Vector2i(1, 1), [&"utility"])
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	var drag_data: Dictionary = panel.make_drag_data(&"backpack", Vector2i(0, 0), placement)
	_expect(not panel.drop_data_on_equipment_slot(drag_data, &"weapon"), "wrong slot should reject stack")
	_expect(backpack.get_placement_for_stack(stack) == placement, "rejected stack should remain in grid")
	_expect(inventory.equipment_slots.get_equipped_stack(&"weapon") == null, "wrong slot should stay empty")
	panel.queue_free()

func _test_equipment_slot_changes_emit_inventory_changed() -> void:
	var inventory := InventoryContainerScript.new()
	var stack: Resource = _make_equipment_stack(&"rifle", Vector2i(3, 2), [&"weapon"])
	var signal_state := {"changed_count": 0}
	inventory.inventory_changed.connect(func() -> void:
		signal_state["changed_count"] = int(signal_state["changed_count"]) + 1
	)

	_expect(inventory.equip(&"weapon", stack), "container equip should accept matching weapon stack")
	_expect(inventory.unequip(&"weapon") == stack, "container unequip should return equipped stack")
	_expect(int(signal_state["changed_count"]) >= 2, "container should emit inventory_changed for equipment equip and unequip")

func _test_drop_preview_cells_follow_drag_footprint() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(5, 4))
	var stack: Resource = _make_equipment_stack(&"rifle", Vector2i(3, 2), [&"weapon"])
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	var drag_data: Dictionary = panel.make_drag_data(&"backpack", Vector2i(1, 0), placement)
	var cells: Array = panel.get_drop_preview_cells_for_data(drag_data, &"backpack", Vector2i(3, 1))
	_expect(cells.has(Vector2i(2, 1)), "drop preview should include adjusted footprint top-left cell")
	_expect(cells.has(Vector2i(4, 2)), "drop preview should include adjusted footprint bottom-right cell")
	_expect(cells.size() == 6, "drop preview should cover the dragged item's footprint")
	panel.queue_free()

func _test_active_drag_rotation_keeps_grab_offset() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(5, 5))
	var stack: Resource = _make_equipment_stack(&"rifle", Vector2i(3, 2), [&"weapon"])
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	panel.make_drag_data(&"backpack", Vector2i(1, 0), placement)
	_expect(panel.rotate_active_drag(), "active drag should rotate when the item can rotate")
	var drag_data: Dictionary = panel.get_active_drag_data()
	_expect(drag_data.get("grab_offset") == Vector2i(1, 0), "drag rotation should not move the mouse grab offset to a new cell")
	panel.queue_free()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)

func _make_equipment_stack(id: StringName, size: Vector2i, slot_ids: Array[StringName]) -> Resource:
	var item := InventoryItemDefinitionScript.new()
	item.id = id
	item.display_name = String(id)
	item.grid_size = size
	item.equipment = Resource.new()
	item.allowed_equipment_slot_ids = slot_ids

	var stack := InventoryItemStackScript.new()
	stack.item = item
	return stack
