extends Node3D
class_name Cover

enum CoverGrade {
	LOW,
	MEDIUM,
	HIGH
}

@export var grade: CoverGrade = CoverGrade.MEDIUM

var _slot_occupants: Dictionary = {}

func _ready():
	add_to_group("covers")

func reserve_slot(unit: Unit) -> Marker3D:
	if not is_instance_valid(unit):
		return null
	
	_prune_invalid_occupants()
	
	if unit.reserved_cover != null and unit.reserved_cover != self:
		unit.clear_cover()
	
	var reserved_slot := get_reserved_slot(unit)
	if reserved_slot != null:
		return reserved_slot
	
	var slots := get_cover_slots()
	slots.sort_custom(func(a: Marker3D, b: Marker3D): return a.global_position.distance_squared_to(unit.global_position) < b.global_position.distance_squared_to(unit.global_position))
	
	for slot in slots:
		var slot_key := _get_slot_key(slot)
		if _slot_occupants.has(slot_key):
			continue
		
		_slot_occupants[slot_key] = unit
		unit.reserved_cover = self
		unit.reserved_cover_slot = slot
		return slot
	
	return null

func release_slot(unit: Unit) -> void:
	for slot_key in _slot_occupants.keys():
		if _slot_occupants[slot_key] == unit:
			_slot_occupants.erase(slot_key)
			return

func has_available_slot(unit: Unit) -> bool:
	_prune_invalid_occupants()
	if get_reserved_slot(unit) != null:
		return true
	
	for slot in get_cover_slots():
		if not _slot_occupants.has(_get_slot_key(slot)):
			return true
	
	return false

func get_reserved_slot(unit: Unit) -> Marker3D:
	for slot in get_cover_slots():
		var slot_key := _get_slot_key(slot)
		if _slot_occupants.get(slot_key) == unit:
			return slot
	
	return null

func get_cover_slots() -> Array[Marker3D]:
	var slots: Array[Marker3D] = []
	var slots_parent := get_node_or_null("CoverSlots")
	if slots_parent == null:
		return slots
	
	for child in slots_parent.get_children():
		var slot := child as Marker3D
		if slot != null:
			slots.append(slot)
	
	return slots

func _prune_invalid_occupants() -> void:
	for slot_key in _slot_occupants.keys():
		var unit := _slot_occupants[slot_key] as Unit
		if not is_instance_valid(unit):
			_slot_occupants.erase(slot_key)

func _get_slot_key(slot: Marker3D) -> String:
	return str(slot.get_path())
