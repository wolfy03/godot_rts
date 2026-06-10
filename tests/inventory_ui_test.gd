extends Node

const InventoryContainerScript := preload("res://scripts/inventory/inventory_container.gd")
const InventoryItemDefinitionScript := preload("res://scripts/inventory/inventory_item_definition.gd")
const InventoryItemStackScript := preload("res://scripts/inventory/inventory_item_stack.gd")
const InventoryPanelScript := preload("res://scripts/ui/hud/inventory_panel.gd")
const AgentDirectControllerScript := preload("res://scripts/input/agent_direct_controller.gd")

var _failed := false

func _ready() -> void:
	_test_inventory_panel_toggles_visibility()
	_test_inventory_panel_moves_stack_between_cells()
	_test_inventory_panel_moves_stack_between_grids()
	_test_inventory_panel_rotates_hovered_stack()
	_test_inventory_panel_drag_data_exposes_footprint()
	_test_inventory_panel_rotates_active_drag_data()
	_test_inventory_panel_clears_drop_preview_after_failed_drop()
	_test_inventory_panel_clears_drop_preview_when_drag_ends()
	_test_inventory_panel_identifies_item_border_cells()
	_test_inventory_panel_moves_equipped_stack_to_grid()
	_test_inventory_panel_equips_matching_grid_stack()
	_test_inventory_panel_rejects_wrong_equipment_slot()
	_test_agent_direct_controller_blocks_input_while_inventory_is_open()
	_test_agent_direct_controller_blocks_input_while_console_is_open()

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("inventory_ui_test: PASS")
		get_tree().quit(0)

func _test_inventory_panel_toggles_visibility() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	inventory.add_grid(&"backpack", Vector2i(4, 3))
	panel.set_inventory(inventory)

	_expect(not panel.is_inventory_open(), "inventory panel should start closed")
	_expect(panel.toggle_inventory(), "inventory panel toggle should open the panel")
	_expect(panel.is_inventory_open(), "inventory panel should report open state")
	_expect(not panel.toggle_inventory(), "inventory panel toggle should close the panel")
	_expect(not panel.is_inventory_open(), "inventory panel should report closed state")
	panel.queue_free()

func _test_inventory_panel_moves_stack_between_cells() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var stack := _make_stack(&"bandage", Vector2i(1, 1))
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	_expect(panel.drop_stack_on_grid(&"backpack", Vector2i(2, 1), placement), "inventory panel should move a stack inside the same grid")
	_expect(backpack.get_placement_for_stack(stack).position == Vector2i(2, 1), "same-grid drag should update placement position")
	panel.queue_free()

func _test_inventory_panel_moves_stack_between_grids() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var pouch: Resource = inventory.add_grid(&"pouch", Vector2i(2, 2))
	var stack := _make_stack(&"grenade", Vector2i(1, 1))
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	_expect(panel.drop_stack_on_grid(&"pouch", Vector2i(1, 1), placement), "inventory panel should move a stack to another grid")
	_expect(backpack.get_placement_for_stack(stack) == null, "source grid should release dragged stack")
	_expect(pouch.get_placement_for_stack(stack) != null, "target grid should receive dragged stack")
	panel.queue_free()

func _test_inventory_panel_rotates_hovered_stack() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var stack := _make_stack(&"rifle", Vector2i(3, 2))
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	_expect(panel.rotate_hovered_placement(placement), "inventory panel should rotate a hovered item when space allows")
	_expect(placement.rotated, "hover rotation should flip placement rotation state")
	_expect(placement.get_size() == Vector2i(2, 3), "hover rotation should rotate item footprint by 90 degrees")
	panel.queue_free()

func _test_inventory_panel_drag_data_exposes_footprint() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var stack := _make_stack(&"machine_gun", Vector2i(4, 2))
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	var drag_data: Dictionary = panel.make_drag_data(&"backpack", Vector2i(0, 0), placement)
	_expect(drag_data.get("footprint") == Vector2i(4, 2), "drag data should expose item footprint for visual preview")
	_expect(drag_data.get("cell_size") == Vector2(28, 28), "drag data should expose cell size for visual preview")
	panel.queue_free()

func _test_inventory_panel_rotates_active_drag_data() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(3, 4))
	var stack := _make_stack(&"rifle", Vector2i(3, 2))
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	panel.make_drag_data(&"backpack", Vector2i(0, 0), placement)
	_expect(panel.rotate_active_drag(), "R should rotate active drag data")
	var drag_data: Dictionary = panel.get_active_drag_data()
	_expect(bool(drag_data.get("rotated")), "active drag data should remember rotated state")
	_expect(panel.drop_data_on_grid(drag_data, &"backpack", Vector2i(0, 1)), "rotated drag data should be used during drop")
	_expect(placement.rotated, "dropping rotated drag data should rotate the placement")
	panel.queue_free()

func _test_inventory_panel_clears_drop_preview_after_failed_drop() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(2, 2))
	var stack := _make_stack(&"rifle", Vector2i(2, 1))
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	var drag_data: Dictionary = panel.make_drag_data(&"backpack", Vector2i(0, 0), placement)
	_expect(not panel.can_drop_data_on_grid(drag_data, &"backpack", Vector2i(1, 1)), "test setup should preview an invalid drop")
	_expect(panel.get_drop_preview_cell_count() > 0, "invalid drop preview should still show before the drop is released")
	_expect(not panel.drop_data_on_grid(drag_data, &"backpack", Vector2i(1, 1)), "invalid drop should fail")
	_expect(panel.get_drop_preview_cell_count() == 0, "failed drop should clear the drop preview")
	panel.queue_free()

func _test_inventory_panel_clears_drop_preview_when_drag_ends() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(2, 2))
	var stack := _make_stack(&"rifle", Vector2i(2, 1))
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	var drag_data: Dictionary = panel.make_drag_data(&"backpack", Vector2i(0, 0), placement)
	_expect(panel.can_drop_data_on_grid(drag_data, &"backpack", Vector2i(0, 1)), "test setup should create a valid drop preview")
	_expect(panel.get_drop_preview_cell_count() > 0, "drop preview should be visible before drag end")
	panel.notification(Control.NOTIFICATION_DRAG_END)
	_expect(panel.get_drop_preview_cell_count() == 0, "drag end should clear stale drop preview even when no cell receives the drop")
	panel.queue_free()

func _test_inventory_panel_identifies_item_border_cells() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var stack := _make_stack(&"machine_gun", Vector2i(4, 2))
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	_expect(panel.is_item_border_cell(placement, Vector2i(0, 0)), "top-left item cell should be rendered as an item border")
	_expect(panel.is_item_border_cell(placement, Vector2i(3, 1)), "bottom-right item cell should be rendered as an item border")
	panel.queue_free()

func _test_inventory_panel_moves_equipped_stack_to_grid() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var stack: Resource = _make_equipment_stack(&"rifle", Vector2i(3, 2), [&"weapon"])
	_expect(inventory.equip(&"weapon", stack), "test setup should equip a weapon stack")
	panel.set_inventory(inventory)

	var drag_data: Dictionary = panel.make_equipment_drag_data(&"weapon")
	_expect(panel.can_drop_data_on_grid(drag_data, &"backpack", Vector2i(0, 0)), "equipped stack should be droppable into a grid")
	_expect(panel.drop_data_on_grid(drag_data, &"backpack", Vector2i(0, 0)), "inventory panel should move equipped stack into a grid")
	_expect(inventory.equipment_slots.get_equipped_stack(&"weapon") == null, "equipment slot should be empty after moving stack to grid")
	_expect(backpack.get_placement_for_stack(stack) != null, "grid should contain the unequipped stack")
	panel.queue_free()

func _test_inventory_panel_equips_matching_grid_stack() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var stack: Resource = _make_equipment_stack(&"rifle", Vector2i(3, 2), [&"weapon"])
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	var drag_data: Dictionary = panel.make_drag_data(&"backpack", Vector2i(0, 0), placement)
	_expect(panel.can_drop_data_on_equipment_slot(drag_data, &"weapon"), "matching equipment should be droppable into its slot")
	_expect(panel.drop_data_on_equipment_slot(drag_data, &"weapon"), "inventory panel should equip a matching grid stack")
	_expect(backpack.get_placement_for_stack(stack) == null, "source grid should release equipped stack")
	_expect(inventory.equipment_slots.get_equipped_stack(&"weapon") == stack, "weapon slot should contain the equipped stack")
	panel.queue_free()

func _test_inventory_panel_rejects_wrong_equipment_slot() -> void:
	var panel := PanelContainer.new()
	panel.set_script(InventoryPanelScript)
	add_child(panel)

	var inventory := InventoryContainerScript.new()
	var backpack: Resource = inventory.add_grid(&"backpack", Vector2i(4, 3))
	var stack: Resource = _make_equipment_stack(&"tool", Vector2i(1, 1), [&"utility"])
	var placement: Resource = backpack.place(stack, Vector2i(0, 0))
	panel.set_inventory(inventory)

	var drag_data: Dictionary = panel.make_drag_data(&"backpack", Vector2i(0, 0), placement)
	_expect(not panel.can_drop_data_on_equipment_slot(drag_data, &"weapon"), "wrong equipment slot should reject the stack")
	_expect(not panel.drop_data_on_equipment_slot(drag_data, &"weapon"), "wrong equipment slot should not equip the stack")
	_expect(backpack.get_placement_for_stack(stack) == placement, "rejected stack should remain in its source grid")
	_expect(inventory.equipment_slots.get_equipped_stack(&"weapon") == null, "rejected stack should not occupy the weapon slot")
	panel.queue_free()

func _test_agent_direct_controller_blocks_input_while_inventory_is_open() -> void:
	var controller := Node.new()
	controller.set_script(AgentDirectControllerScript)
	add_child(controller)

	_expect(not controller.is_input_blocked_by_inventory(), "agent direct controller should start unblocked")
	controller.set_inventory_input_blocked(true)
	_expect(controller.is_input_blocked_by_inventory(), "agent direct controller should expose inventory input block state")
	controller.set_inventory_input_blocked(false)
	_expect(not controller.is_input_blocked_by_inventory(), "agent direct controller should clear inventory input block state")
	controller.queue_free()

func _test_agent_direct_controller_blocks_input_while_console_is_open() -> void:
	var controller := Node.new()
	controller.set_script(AgentDirectControllerScript)
	add_child(controller)

	_expect(not controller.is_input_blocked_by_console(), "agent direct controller should start unblocked by console")
	controller.set_console_input_blocked(true)
	_expect(controller.is_input_blocked_by_console(), "agent direct controller should expose console input block state")
	controller.set_console_input_blocked(false)
	_expect(not controller.is_input_blocked_by_console(), "agent direct controller should clear console input block state")
	controller.queue_free()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	_failed = true
	push_error(message)

func _make_stack(id: StringName, size: Vector2i) -> Resource:
	var item := InventoryItemDefinitionScript.new()
	item.id = id
	item.display_name = String(id)
	item.grid_size = size
	var stack := InventoryItemStackScript.new()
	stack.item = item
	return stack

func _make_equipment_stack(id: StringName, size: Vector2i, slot_ids: Array[StringName]) -> Resource:
	var stack: Resource = _make_stack(id, size)
	stack.item.equipment = Resource.new()
	stack.item.allowed_equipment_slot_ids = slot_ids
	return stack
