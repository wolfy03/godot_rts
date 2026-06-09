extends Resource
class_name InventoryContainer

const InventoryGridScript := preload("res://scripts/inventory/inventory_grid.gd")
const InventoryEquipmentSlotsScript := preload("res://scripts/inventory/inventory_equipment_slots.gd")

signal inventory_changed

@export var equipment_slots: Resource

var _grids: Dictionary = {}

func _init() -> void:
	if equipment_slots == null:
		equipment_slots = InventoryEquipmentSlotsScript.new()
	_connect_inventory_changed(equipment_slots)

func add_grid(id: StringName, size: Vector2i) -> Resource:
	if id == &"":
		return null
	if _grids.has(id):
		return _grids[id]

	var grid = InventoryGridScript.new()
	grid.configure(size)
	_connect_inventory_changed(grid)
	_grids[id] = grid
	inventory_changed.emit()
	return grid

func remove_grid(id: StringName) -> bool:
	if not _grids.has(id):
		return false

	var grid = _grids[id]
	_disconnect_inventory_changed(grid)
	_grids.erase(id)
	inventory_changed.emit()
	return true

func get_grid(id: StringName) -> Resource:
	return _grids.get(id)

func get_grid_ids() -> Array:
	var ids: Array = []
	for id in _grids.keys():
		ids.append(id)
	return ids

func auto_place(stack: Resource, preferred_grid_ids: Array = []) -> Resource:
	var search_ids := preferred_grid_ids
	if search_ids.is_empty():
		search_ids = get_grid_ids()

	for id in search_ids:
		var grid = get_grid(id)
		if grid == null:
			continue
		var placement = grid.auto_place(stack)
		if placement != null:
			return placement

	return null

func move_between_grids(from_grid_id: StringName, placement: Resource, to_grid_id: StringName, position: Vector2i, rotated: bool = false) -> bool:
	var from_grid: Resource = get_grid(from_grid_id)
	var to_grid: Resource = get_grid(to_grid_id)
	if from_grid == null or to_grid == null or placement == null:
		return false

	if from_grid == to_grid:
		return from_grid.move(placement, position, rotated)

	if from_grid.get_placement_for_stack(placement.stack) != placement:
		return false
	if not to_grid.can_place(placement.stack, position, rotated):
		return false

	var stack: Resource = placement.stack
	if not from_grid.remove(placement):
		return false
	return to_grid.place(stack, position, rotated) != null

func equip(slot_id: StringName, stack: Resource) -> bool:
	if equipment_slots == null:
		return false
	_connect_inventory_changed(equipment_slots)
	return equipment_slots.equip(slot_id, stack)

func unequip(slot_id: StringName) -> Resource:
	if equipment_slots == null:
		return null
	_connect_inventory_changed(equipment_slots)
	return equipment_slots.unequip(slot_id)

func get_equipped_equipment() -> Array:
	if equipment_slots == null:
		return []
	return equipment_slots.get_equipped_equipment()

func get_equipped_weapon() -> Resource:
	if equipment_slots == null:
		return null
	return equipment_slots.get_equipped_weapon()

func _on_child_changed() -> void:
	inventory_changed.emit()

func _connect_inventory_changed(source: Object) -> void:
	if source == null or not source.has_signal("inventory_changed"):
		return
	if not source.is_connected("inventory_changed", _on_child_changed):
		source.connect("inventory_changed", _on_child_changed)

func _disconnect_inventory_changed(source: Object) -> void:
	if source == null or not source.has_signal("inventory_changed"):
		return
	if source.is_connected("inventory_changed", _on_child_changed):
		source.disconnect("inventory_changed", _on_child_changed)
