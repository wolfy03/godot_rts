extends Resource
class_name InventoryItemStack

signal inventory_changed

@export var item: Resource
@export var quantity: int = 1
@export var rotated: bool = false

func get_grid_size() -> Vector2i:
	if item == null:
		return Vector2i.ZERO
	return item.get_grid_size(rotated)

func get_max_stack_size() -> int:
	if item == null:
		return 0
	return maxi(1, item.max_stack_size)

func can_stack_with(other: Resource) -> bool:
	return other != null and item != null and item == other.item

func can_add_quantity(amount: int) -> bool:
	return amount >= 0 and quantity + amount <= get_max_stack_size()

func add_quantity(amount: int) -> int:
	if amount <= 0 or item == null:
		return amount

	var free_space := get_max_stack_size() - quantity
	var added := mini(amount, free_space)
	quantity += added
	inventory_changed.emit()
	return amount - added

func remove_quantity(amount: int) -> int:
	if amount <= 0:
		return 0

	var removed := mini(amount, quantity)
	quantity -= removed
	inventory_changed.emit()
	return removed

func is_empty() -> bool:
	return item == null or quantity <= 0
