extends PanelContainer
class_name InventoryPanel

signal inventory_visibility_changed(is_open: bool)

const CELL_SIZE := Vector2(28, 28)
const CELL_GAP := 2
const InventoryGridCellScript := preload("res://scripts/ui/hud/inventory_grid_cell.gd")
const InventoryEquipmentSlotCellScript := preload("res://scripts/ui/hud/inventory_equipment_slot_cell.gd")

var _inventory: Resource
var _content_root: VBoxContainer
var _grids_root: VBoxContainer
var _equipment_root: VBoxContainer
var _placement_grid_ids: Dictionary = {}
var _active_drag_data: Dictionary = {}
var _grid_cells: Dictionary = {}
var _drop_preview_cell_keys: Array[String] = []
var _last_drop_preview_grid_id: StringName = &""
var _last_drop_preview_target_position: Vector2i = Vector2i.ZERO

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode == KEY_R and rotate_active_drag():
		get_viewport().set_input_as_handled()

func _ready() -> void:
	add_to_group("command_panel_ui")
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_finish_drag_feedback()

func set_inventory(inventory: Resource) -> void:
	if _inventory == inventory:
		_refresh()
		return

	_disconnect_inventory_changed(_inventory)
	_inventory = inventory
	_connect_inventory_changed(_inventory)
	_refresh()

func toggle_inventory() -> bool:
	set_inventory_open(not visible)
	return visible

func set_inventory_open(is_open: bool) -> void:
	if visible == is_open:
		return
	visible = is_open
	inventory_visibility_changed.emit(visible)

func is_inventory_open() -> bool:
	return visible

func _build_ui() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.052, 0.057, 0.96)
	panel_style.border_color = Color(0.42, 0.48, 0.52, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	_content_root = VBoxContainer.new()
	_content_root.add_theme_constant_override("separation", 10)
	margin.add_child(_content_root)

	var title := Label.new()
	title.text = "인벤토리"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.96, 0.92, 1.0))
	_content_root.add_child(title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	_content_root.add_child(body)

	_grids_root = VBoxContainer.new()
	_grids_root.add_theme_constant_override("separation", 10)
	body.add_child(_grids_root)

	_equipment_root = VBoxContainer.new()
	_equipment_root.custom_minimum_size = Vector2(180, 0)
	_equipment_root.add_theme_constant_override("separation", 8)
	body.add_child(_equipment_root)

func _refresh() -> void:
	if _grids_root == null or _equipment_root == null:
		return

	_clear_children(_grids_root)
	_clear_children(_equipment_root)
	_placement_grid_ids.clear()
	_grid_cells.clear()
	_drop_preview_cell_keys.clear()
	_last_drop_preview_grid_id = &""
	if _inventory == null:
		_grids_root.add_child(_make_label("인벤토리 없음"))
		return

	for grid_id in _inventory.get_grid_ids():
		var grid: Resource = _inventory.get_grid(grid_id)
		if grid != null:
			_grids_root.add_child(_make_grid_view(grid_id, grid))

	_equipment_root.add_child(_make_label("장착 슬롯", 15))
	if _inventory.equipment_slots != null:
		for slot_id in _inventory.equipment_slots.slot_ids:
			_equipment_root.add_child(_make_equipment_slot(slot_id))

func _make_grid_view(grid_id: StringName, grid: Resource) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 4)
	wrapper.add_child(_make_label("%s  %dx%d" % [String(grid_id), grid.grid_size.x, grid.grid_size.y], 14))

	# Use a Control as a layered container so we can overlay item panels on top of the grid
	var grid_layer := Control.new()
	var grid_pixel_w: int = grid.grid_size.x * int(CELL_SIZE.x) + (grid.grid_size.x - 1) * CELL_GAP
	var grid_pixel_h: int = grid.grid_size.y * int(CELL_SIZE.y) + (grid.grid_size.y - 1) * CELL_GAP
	grid_layer.custom_minimum_size = Vector2(grid_pixel_w, grid_pixel_h)
	wrapper.add_child(grid_layer)

	var cells := GridContainer.new()
	cells.columns = grid.grid_size.x
	cells.add_theme_constant_override("h_separation", CELL_GAP)
	cells.add_theme_constant_override("v_separation", CELL_GAP)
	grid_layer.add_child(cells)

	var seen_placements: Dictionary = {}

	for y in range(grid.grid_size.y):
		for x in range(grid.grid_size.x):
			var cell := _make_grid_cell(grid_id, Vector2i(x, y))
			var placement: Resource = grid.get_placement_at(Vector2i(x, y))
			if placement != null and placement.stack != null and placement.stack.item != null:
				_placement_grid_ids[placement] = grid_id
				cell.placement = placement
				# Make item cells visually transparent (the overlay handles rendering)
				cell.add_theme_stylebox_override("panel", _make_cell_style(Color(0.0, 0.0, 0.0, 0.0)))
				if not seen_placements.has(placement):
					seen_placements[placement] = true
			cells.add_child(cell)

	# Add a single overlay panel per item on top of the grid
	for placement in seen_placements:
		var overlay := _make_item_overlay(placement)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid_layer.add_child(overlay)

	return wrapper

func _make_equipment_slot(slot_id: StringName) -> Control:
	var slot_panel := PanelContainer.new()
	slot_panel.set_script(InventoryEquipmentSlotCellScript)
	slot_panel.custom_minimum_size = Vector2(176, 34)
	slot_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	slot_panel.inventory_panel = self
	slot_panel.slot_id = slot_id
	slot_panel.add_theme_stylebox_override("panel", _make_cell_style(Color(0.085, 0.1, 0.105, 1.0)))

	var label := _make_label("%s: %s" % [String(slot_id), _get_equipped_name(slot_id)], 12)
	slot_panel.add_child(label)
	return slot_panel

func _get_equipped_name(slot_id: StringName) -> String:
	if _inventory == null or _inventory.equipment_slots == null:
		return "-"
	var stack: Resource = _inventory.equipment_slots.get_equipped_stack(slot_id)
	if stack == null or stack.item == null:
		return "-"
	return stack.item.display_name

func _make_item_overlay(placement: Resource) -> PanelContainer:
	var grid_placement := placement as InventoryGridPlacement
	var item_size: Vector2i = grid_placement.get_size()
	var step_x := int(CELL_SIZE.x) + CELL_GAP
	var step_y := int(CELL_SIZE.y) + CELL_GAP

	var overlay := PanelContainer.new()
	overlay.position = Vector2(grid_placement.position.x * step_x, grid_placement.position.y * step_y)
	var overlay_w := item_size.x * int(CELL_SIZE.x) + (item_size.x - 1) * CELL_GAP
	var overlay_h := item_size.y * int(CELL_SIZE.y) + (item_size.y - 1) * CELL_GAP
	overlay.size = Vector2(overlay_w, overlay_h)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.28, 0.24, 1.0)
	style.border_color = Color(0.72, 0.86, 0.7, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	overlay.add_theme_stylebox_override("panel", style)

	var label := _make_label(placement.stack.item.display_name, 11)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.add_child(label)

	return overlay

func make_drag_data(source_grid_id: StringName, source_cell_position: Vector2i, placement: Resource) -> Dictionary:
	if placement == null or placement.stack == null or placement.stack.item == null:
		return {}
	var grab_offset: Vector2i = source_cell_position - placement.position
	_active_drag_data = {
		"type": "inventory_stack",
		"source_type": "grid",
		"source_grid_id": source_grid_id,
		"source_cell_position": source_cell_position,
		"placement": placement,
		"stack": placement.stack,
		"display_name": placement.stack.item.display_name,
		"footprint": placement.stack.item.get_grid_size(false),
		"rotated": placement.rotated,
		"cell_size": CELL_SIZE,
		"grab_offset": grab_offset,
	}
	return _active_drag_data.duplicate()

func make_equipment_drag_data(source_slot_id: StringName) -> Dictionary:
	if _inventory == null or _inventory.equipment_slots == null:
		return {}
	var stack: Resource = _inventory.equipment_slots.get_equipped_stack(source_slot_id)
	if stack == null or stack.item == null:
		return {}

	_active_drag_data = {
		"type": "inventory_stack",
		"source_type": "equipment_slot",
		"source_slot_id": source_slot_id,
		"placement": null,
		"stack": stack,
		"display_name": stack.item.display_name,
		"footprint": stack.item.get_grid_size(false),
		"rotated": bool(stack.get("rotated")),
		"cell_size": CELL_SIZE,
		"grab_offset": Vector2i.ZERO,
	}
	return _active_drag_data.duplicate()

func get_active_drag_data() -> Dictionary:
	return _active_drag_data.duplicate()

func get_drop_preview_cell_count() -> int:
	return _drop_preview_cell_keys.size()

func rotate_active_drag() -> bool:
	if _active_drag_data.is_empty():
		return false
	var placement: Resource = _active_drag_data.get("placement")
	if placement == null or placement.stack == null or placement.stack.item == null:
		return false
	if not bool(placement.stack.item.get("can_rotate")):
		return false

	# Transform grab_offset so the mouse stays at the same visual point after rotation
	var old_offset: Vector2i = _active_drag_data.get("grab_offset", Vector2i.ZERO)
	var was_rotated := bool(_active_drag_data.get("rotated", false))
	var footprint: Vector2i = _active_drag_data.get("footprint", Vector2i.ONE)
	var current_size: Vector2i = Vector2i(footprint.y, footprint.x) if was_rotated else footprint
	# 90° CW rotation: (ox, oy) -> (current_h - 1 - oy, ox)
	_active_drag_data["grab_offset"] = Vector2i(current_size.y - 1 - old_offset.y, old_offset.x)
	_active_drag_data["grab_offset"] = old_offset
	_active_drag_data["rotated"] = not was_rotated
	if _last_drop_preview_grid_id != &"":
		_update_drop_preview_for_data(_active_drag_data, _last_drop_preview_grid_id, _last_drop_preview_target_position)
	return true

func can_drop_data_on_grid(data: Variant, target_grid_id: StringName, target_position: Vector2i) -> bool:
	if not (data is Dictionary):
		return false
	var drag_data := _get_effective_drag_data(data as Dictionary)
	if drag_data.get("type", "") != "inventory_stack":
		return false
	var source_type := String(drag_data.get("source_type", "grid"))
	var placement: Resource = drag_data.get("placement")
	var rotated := bool(drag_data.get("rotated", placement.rotated if placement != null else false))
	var grab_offset: Vector2i = drag_data.get("grab_offset", Vector2i.ZERO)
	var adjusted_position := target_position - grab_offset
	_update_drop_preview_for_data(drag_data, target_grid_id, target_position)
	if source_type == "equipment_slot":
		var stack: Resource = drag_data.get("stack")
		return can_drop_equipped_stack_on_grid(target_grid_id, adjusted_position, stack, rotated)
	return can_drop_stack_on_grid(target_grid_id, adjusted_position, placement, rotated)

func drop_data_on_grid(data: Variant, target_grid_id: StringName, target_position: Vector2i) -> bool:
	if not (data is Dictionary):
		_finish_drag_feedback()
		return false
	var drag_data := _get_effective_drag_data(data as Dictionary)
	var source_type := String(drag_data.get("source_type", "grid"))
	var placement: Resource = drag_data.get("placement")
	var rotated := bool(drag_data.get("rotated", placement.rotated if placement != null else false))
	var grab_offset: Vector2i = drag_data.get("grab_offset", Vector2i.ZERO)
	var adjusted_position := target_position - grab_offset
	var dropped := false
	if source_type == "equipment_slot":
		var source_slot_id: StringName = drag_data.get("source_slot_id", &"")
		var stack: Resource = drag_data.get("stack")
		dropped = drop_equipped_stack_on_grid(source_slot_id, target_grid_id, adjusted_position, stack, rotated)
	else:
		dropped = drop_stack_on_grid(target_grid_id, adjusted_position, placement, rotated)
	if not dropped:
		_finish_drag_feedback()
	return dropped

func get_drop_preview_cells_for_data(data: Variant, _target_grid_id: StringName, target_position: Vector2i) -> Array:
	if not (data is Dictionary):
		return []
	var drag_data := _get_effective_drag_data(data as Dictionary)
	if drag_data.get("type", "") != "inventory_stack":
		return []
	var stack: Resource = drag_data.get("stack")
	if stack == null or stack.item == null:
		return []
	var placement: Resource = drag_data.get("placement")
	var rotated := bool(drag_data.get("rotated", placement.rotated if placement != null else false))
	var grab_offset: Vector2i = drag_data.get("grab_offset", Vector2i.ZERO)
	var adjusted_position := target_position - grab_offset
	var item_size: Vector2i = stack.item.get_grid_size(rotated)
	var cells: Array = []
	for y in range(item_size.y):
		for x in range(item_size.x):
			cells.append(adjusted_position + Vector2i(x, y))
	return cells

func _update_drop_preview_for_data(drag_data: Dictionary, target_grid_id: StringName, target_position: Vector2i) -> void:
	_last_drop_preview_grid_id = target_grid_id
	_last_drop_preview_target_position = target_position
	var cells: Array = get_drop_preview_cells_for_data(drag_data, target_grid_id, target_position)
	var placement: Resource = drag_data.get("placement")
	var rotated := bool(drag_data.get("rotated", placement.rotated if placement != null else false))
	var grab_offset: Vector2i = drag_data.get("grab_offset", Vector2i.ZERO)
	var adjusted_position := target_position - grab_offset
	var source_type := String(drag_data.get("source_type", "grid"))
	var is_valid := false
	if source_type == "equipment_slot":
		var stack: Resource = drag_data.get("stack")
		is_valid = can_drop_equipped_stack_on_grid(target_grid_id, adjusted_position, stack, rotated)
	else:
		is_valid = can_drop_stack_on_grid(target_grid_id, adjusted_position, placement, rotated)
	_set_drop_preview_cells(target_grid_id, cells, is_valid)

func clear_drop_preview() -> void:
	_last_drop_preview_grid_id = &""
	_set_drop_preview_cells(&"", [], false)

func _finish_drag_feedback() -> void:
	_active_drag_data.clear()
	clear_drop_preview()

func _set_drop_preview_cells(grid_id: StringName, cells: Array, is_valid: bool) -> void:
	for key in _drop_preview_cell_keys:
		if _grid_cells.has(key):
			_apply_grid_cell_default_style(_grid_cells[key])
	_drop_preview_cell_keys.clear()

	for cell_position in cells:
		var preview_cell_position: Vector2i = cell_position
		var key := _cell_key(grid_id, preview_cell_position)
		if not _grid_cells.has(key):
			continue
		var cell := _grid_cells[key] as PanelContainer
		cell.add_theme_stylebox_override("panel", _make_drop_preview_style(is_valid))
		_drop_preview_cell_keys.append(key)

func _get_effective_drag_data(drag_data: Dictionary) -> Dictionary:
	if _active_drag_data.is_empty():
		return drag_data
	if _active_drag_data.get("placement") != drag_data.get("placement"):
		return drag_data
	if _active_drag_data.get("stack") != drag_data.get("stack"):
		return drag_data
	return _active_drag_data

func can_drop_equipped_stack_on_grid(target_grid_id: StringName, target_position: Vector2i, stack: Resource, rotated: bool = false) -> bool:
	if _inventory == null or stack == null or stack.item == null:
		return false
	var target_grid: Resource = _inventory.get_grid(target_grid_id)
	if target_grid == null:
		return false
	return target_grid.can_place(stack, target_position, rotated)

func drop_equipped_stack_on_grid(source_slot_id: StringName, target_grid_id: StringName, target_position: Vector2i, stack: Resource, rotated: bool = false) -> bool:
	if _inventory == null or _inventory.equipment_slots == null:
		return false
	if not can_drop_equipped_stack_on_grid(target_grid_id, target_position, stack, rotated):
		return false
	if _inventory.equipment_slots.get_equipped_stack(source_slot_id) != stack:
		return false

	var target_grid: Resource = _inventory.get_grid(target_grid_id)
	if target_grid == null:
		return false

	var unequipped_stack: Resource = _unequip_stack_from_slot(source_slot_id)
	if unequipped_stack != stack:
		if unequipped_stack != null:
			_equip_stack_to_slot(source_slot_id, unequipped_stack)
		return false

	if target_grid.place(stack, target_position, rotated) == null:
		_equip_stack_to_slot(source_slot_id, stack)
		return false

	_active_drag_data.clear()
	clear_drop_preview()
	_refresh()
	return true

func can_drop_stack_on_grid(target_grid_id: StringName, target_position: Vector2i, placement: Resource, rotated: bool = false) -> bool:
	if _inventory == null or placement == null or placement.stack == null:
		return false

	var target_grid: Resource = _inventory.get_grid(target_grid_id)
	if target_grid == null:
		return false

	var source_grid_id: StringName = _get_grid_id_for_placement(placement)
	if source_grid_id == target_grid_id:
		return target_grid.can_place(placement.stack, target_position, rotated, placement)
	return target_grid.can_place(placement.stack, target_position, rotated)

func drop_stack_on_grid(target_grid_id: StringName, target_position: Vector2i, placement: Resource, rotated: bool = false) -> bool:
	if _inventory == null or not can_drop_stack_on_grid(target_grid_id, target_position, placement, rotated):
		return false

	var source_grid_id: StringName = _get_grid_id_for_placement(placement)
	if source_grid_id == &"":
		return false

	var moved := false
	if source_grid_id == target_grid_id:
		var source_grid: Resource = _inventory.get_grid(source_grid_id)
		moved = source_grid != null and source_grid.move(placement, target_position, rotated)
	else:
		moved = _inventory.move_between_grids(source_grid_id, placement, target_grid_id, target_position, rotated)

	if moved:
		_active_drag_data.clear()
		clear_drop_preview()
		_refresh()
	return moved

func can_drop_data_on_equipment_slot(data: Variant, target_slot_id: StringName) -> bool:
	if not (data is Dictionary):
		return false
	var drag_data := _get_effective_drag_data(data as Dictionary)
	if drag_data.get("type", "") != "inventory_stack":
		return false
	var stack: Resource = drag_data.get("stack")
	return can_equip_stack_to_slot(target_slot_id, stack)

func drop_data_on_equipment_slot(data: Variant, target_slot_id: StringName) -> bool:
	if _inventory == null or _inventory.equipment_slots == null:
		return false
	if not (data is Dictionary):
		return false
	var drag_data := _get_effective_drag_data(data as Dictionary)
	var source_type := String(drag_data.get("source_type", "grid"))
	var stack: Resource = drag_data.get("stack")
	if not can_equip_stack_to_slot(target_slot_id, stack):
		return false

	if source_type == "grid":
		var placement: Resource = drag_data.get("placement")
		var source_grid_id: StringName = _get_grid_id_for_placement(placement)
		if source_grid_id == &"":
			return false
		var source_grid: Resource = _inventory.get_grid(source_grid_id)
		if source_grid == null or source_grid.get_placement_for_stack(stack) != placement:
			return false
		if not source_grid.remove(placement):
			return false
		if not _equip_stack_to_slot(target_slot_id, stack):
			source_grid.place(stack, placement.position, placement.rotated)
			return false
	elif source_type == "equipment_slot":
		var source_slot_id: StringName = drag_data.get("source_slot_id", &"")
		if source_slot_id == target_slot_id:
			return false
		if _inventory.equipment_slots.get_equipped_stack(source_slot_id) != stack:
			return false
		var unequipped_stack: Resource = _unequip_stack_from_slot(source_slot_id)
		if unequipped_stack != stack:
			return false
		if not _equip_stack_to_slot(target_slot_id, stack):
			_equip_stack_to_slot(source_slot_id, stack)
			return false
	else:
		return false

	_active_drag_data.clear()
	clear_drop_preview()
	_refresh()
	return true

func can_equip_stack_to_slot(target_slot_id: StringName, stack: Resource) -> bool:
	if _inventory == null or _inventory.equipment_slots == null:
		return false
	if stack == null or stack.item == null:
		return false
	var occupied_stack: Resource = _inventory.equipment_slots.get_equipped_stack(target_slot_id)
	if occupied_stack != null and occupied_stack != stack:
		return false
	return _inventory.equipment_slots.can_equip(target_slot_id, stack)

func _equip_stack_to_slot(slot_id: StringName, stack: Resource) -> bool:
	if _inventory == null:
		return false
	if _inventory.has_method("equip"):
		return bool(_inventory.call("equip", slot_id, stack))
	if _inventory.equipment_slots == null:
		return false
	return _inventory.equipment_slots.equip(slot_id, stack)

func _unequip_stack_from_slot(slot_id: StringName) -> Resource:
	if _inventory == null:
		return null
	if _inventory.has_method("unequip"):
		var stack: Resource = _inventory.call("unequip", slot_id)
		return stack
	if _inventory.equipment_slots == null:
		return null
	return _inventory.equipment_slots.unequip(slot_id)

func rotate_hovered_placement(placement: Resource) -> bool:
	if placement == null or placement.stack == null or placement.stack.item == null:
		return false
	if not bool(placement.stack.item.get("can_rotate")):
		return false

	var grid_id: StringName = _get_grid_id_for_placement(placement)
	if grid_id == &"":
		return false
	var grid: Resource = _inventory.get_grid(grid_id)
	if grid == null:
		return false

	var rotated := not bool(placement.rotated)
	if not grid.can_place(placement.stack, placement.position, rotated, placement):
		return false

	if grid.move(placement, placement.position, rotated):
		_refresh()
		return true
	return false

func _get_grid_id_for_placement(placement: Resource) -> StringName:
	if placement == null:
		return &""
	if _placement_grid_ids.has(placement):
		return _placement_grid_ids[placement]
	if _inventory == null or placement.stack == null:
		return &""

	for grid_id in _inventory.get_grid_ids():
		var grid: Resource = _inventory.get_grid(grid_id)
		if grid != null and grid.get_placement_for_stack(placement.stack) == placement:
			_placement_grid_ids[placement] = grid_id
			return grid_id
	return &""

func is_item_border_cell(placement: Resource, cell_position: Vector2i) -> bool:
	if placement == null:
		return false
	var rect: Rect2i = placement.get_rect()
	if not rect.has_point(cell_position):
		return false
	return cell_position.x == rect.position.x \
		or cell_position.y == rect.position.y \
		or cell_position.x == rect.position.x + rect.size.x - 1 \
		or cell_position.y == rect.position.y + rect.size.y - 1

func _make_grid_cell(grid_id: StringName, cell_position: Vector2i) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.set_script(InventoryGridCellScript)
	cell.custom_minimum_size = CELL_SIZE
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.inventory_panel = self
	cell.grid_id = grid_id
	cell.cell_position = cell_position
	cell.add_theme_stylebox_override("panel", _make_cell_style(Color(0.075, 0.087, 0.094, 1.0)))
	_grid_cells[_cell_key(grid_id, cell_position)] = cell
	return cell

func _make_cell_label(text_value: String) -> Label:
	var label := _make_label(text_value.substr(0, 2), 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return label

func _make_label(text_value: String, font_size: int = 13) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.82, 1.0))
	return label

func _make_cell_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.28, 0.33, 0.34, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style

func _make_drop_preview_style(is_valid: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if is_valid:
		style.bg_color = Color(0.24, 0.55, 0.34, 0.62)
		style.border_color = Color(0.82, 1.0, 0.72, 1.0)
	else:
		style.bg_color = Color(0.58, 0.18, 0.15, 0.58)
		style.border_color = Color(1.0, 0.42, 0.35, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	return style

func _apply_grid_cell_default_style(cell: PanelContainer) -> void:
	if cell == null:
		return
	if cell.placement != null:
		cell.add_theme_stylebox_override("panel", _make_cell_style(Color(0.0, 0.0, 0.0, 0.0)))
	else:
		cell.add_theme_stylebox_override("panel", _make_cell_style(Color(0.075, 0.087, 0.094, 1.0)))

func _cell_key(grid_id: StringName, cell_position: Vector2i) -> String:
	return "%s:%d:%d" % [String(grid_id), cell_position.x, cell_position.y]



func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()

func _on_inventory_changed() -> void:
	_refresh()

func _connect_inventory_changed(source: Object) -> void:
	if source == null or not source.has_signal("inventory_changed"):
		return
	if not source.is_connected("inventory_changed", _on_inventory_changed):
		source.connect("inventory_changed", _on_inventory_changed)

func _disconnect_inventory_changed(source: Object) -> void:
	if source == null or not source.has_signal("inventory_changed"):
		return
	if source.is_connected("inventory_changed", _on_inventory_changed):
		source.disconnect("inventory_changed", _on_inventory_changed)
