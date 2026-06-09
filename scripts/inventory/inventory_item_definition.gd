extends Resource
class_name InventoryItemDefinition

const InventoryEquipmentSlotsScript := preload("res://scripts/inventory/inventory_equipment_slots.gd")

@export var id: StringName = &"item"
@export var display_name: String = "Item"
@export var description: String = ""
@export var grid_size: Vector2i = Vector2i.ONE
@export var max_stack_size: int = 1
@export var can_rotate: bool = true
@export var equipment: Resource
@export var linked_skill: Resource
@export var allowed_equipment_slot_ids: Array[StringName] = []

func get_grid_size(rotated: bool = false) -> Vector2i:
	var safe_size := Vector2i(maxi(1, grid_size.x), maxi(1, grid_size.y))
	if rotated and can_rotate:
		return Vector2i(safe_size.y, safe_size.x)
	return safe_size

func is_stackable() -> bool:
	return max_stack_size > 1

func can_equip_to_slot(slot_id: StringName) -> bool:
	if equipment == null:
		return false
	if not allowed_equipment_slot_ids.is_empty():
		return allowed_equipment_slot_ids.has(slot_id)
	return InventoryEquipmentSlotsScript.get_default_slot_id_for_equipment(equipment) == slot_id
