extends Resource
class_name InventoryEquipmentSlots

signal inventory_changed

const SLOT_WEAPON := &"weapon"
const SLOT_ARMOR := &"armor"
const SLOT_UTILITY := &"utility"

@export var slot_ids: Array[StringName] = [SLOT_WEAPON, SLOT_ARMOR, SLOT_UTILITY]

var _equipped_stacks: Dictionary = {}

static func get_default_slot_id_for_equipment(equipment) -> StringName:
	if equipment == null:
		return &""

	match int(equipment.slot):
		0:
			return SLOT_WEAPON
		1:
			return SLOT_ARMOR
		2:
			return SLOT_UTILITY
		_:
			return &""

func configure_slots(new_slot_ids: Array[StringName]) -> void:
	slot_ids = new_slot_ids.duplicate()
	for slot_id in _equipped_stacks.keys():
		if not slot_ids.has(slot_id):
			_equipped_stacks.erase(slot_id)
	inventory_changed.emit()

func can_equip(slot_id: StringName, stack: Resource) -> bool:
	if not slot_ids.has(slot_id):
		return false
	if stack == null or stack.item == null or stack.quantity <= 0:
		return false
	return stack.item.can_equip_to_slot(slot_id)

func equip(slot_id: StringName, stack: Resource) -> bool:
	if not can_equip(slot_id, stack):
		return false

	_equipped_stacks[slot_id] = stack
	inventory_changed.emit()
	return true

func unequip(slot_id: StringName) -> Resource:
	if not _equipped_stacks.has(slot_id):
		return null

	var stack = _equipped_stacks[slot_id]
	_equipped_stacks.erase(slot_id)
	inventory_changed.emit()
	return stack

func get_equipped_stack(slot_id: StringName) -> Resource:
	return _equipped_stacks.get(slot_id)

func get_equipped_equipment() -> Array:
	var equipment_items: Array = []
	for stack in _equipped_stacks.values():
		var item_stack := stack as Resource
		if item_stack == null or item_stack.item == null or item_stack.item.equipment == null:
			continue
		equipment_items.append(item_stack.item.equipment)
	return equipment_items

func get_equipped_weapon() -> Resource:
	for equipment in get_equipped_equipment():
		if equipment != null and equipment.has_method("get_attack_cooldown"):
			return equipment
	return null
