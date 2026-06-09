extends Resource
class_name InventoryGridPlacement

@export var stack: Resource
@export var position: Vector2i = Vector2i.ZERO
@export var rotated: bool = false

func get_size() -> Vector2i:
	if stack == null or stack.item == null:
		return Vector2i.ZERO
	return stack.item.get_grid_size(rotated)

func get_rect() -> Rect2i:
	return Rect2i(position, get_size())

func contains_cell(cell: Vector2i) -> bool:
	var rect := get_rect()
	return cell.x >= rect.position.x \
		and cell.y >= rect.position.y \
		and cell.x < rect.position.x + rect.size.x \
		and cell.y < rect.position.y + rect.size.y
