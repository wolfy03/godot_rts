extends Resource
class_name InventoryGrid

const InventoryGridPlacementScript := preload("res://scripts/inventory/inventory_grid_placement.gd")

signal inventory_changed

@export var grid_size: Vector2i = Vector2i(10, 6)

var _placements: Array = []

func configure(size: Vector2i) -> void:
	grid_size = Vector2i(maxi(1, size.x), maxi(1, size.y))
	inventory_changed.emit()

func clear() -> void:
	_placements.clear()
	inventory_changed.emit()

func get_placements() -> Array:
	return _placements.duplicate()

func can_place(stack: Resource, position: Vector2i, rotated: bool = false, ignored_placement: Resource = null) -> bool:
	if stack == null or stack.item == null or stack.quantity <= 0:
		return false

	var item_size: Vector2i = stack.item.get_grid_size(rotated)
	var rect := Rect2i(position, item_size)
	if not _is_rect_inside_grid(rect):
		return false

	for placement in _placements:
		if placement == null or placement == ignored_placement:
			continue
		if _rects_overlap(rect, placement.get_rect()):
			return false

	return true

func place(stack: Resource, position: Vector2i, rotated: bool = false) -> Resource:
	if not can_place(stack, position, rotated):
		return null

	var placement: Resource = InventoryGridPlacementScript.new()
	placement.stack = stack
	placement.position = position
	placement.rotated = rotated
	stack.rotated = rotated
	_placements.append(placement)
	inventory_changed.emit()
	return placement

func auto_place(stack: Resource, rotated: bool = false) -> Resource:
	var position := find_first_fit(stack, rotated)
	if position == Vector2i(-1, -1):
		return null
	return place(stack, position, rotated)

func move(placement: Resource, position: Vector2i, rotated: bool = false) -> bool:
	if placement == null or not _placements.has(placement):
		return false
	if not can_place(placement.stack, position, rotated, placement):
		return false

	placement.position = position
	placement.rotated = rotated
	if placement.stack != null:
		placement.stack.rotated = rotated
	inventory_changed.emit()
	return true

func remove(placement: Resource) -> bool:
	if placement == null:
		return false

	var index := _placements.find(placement)
	if index < 0:
		return false

	_placements.remove_at(index)
	inventory_changed.emit()
	return true

func get_placement_at(cell: Vector2i) -> Resource:
	for placement in _placements:
		if placement != null and placement.contains_cell(cell):
			return placement
	return null

func get_placement_for_stack(stack: Resource) -> Resource:
	for placement in _placements:
		if placement != null and placement.stack == stack:
			return placement
	return null

func find_first_fit(stack: Resource, rotated: bool = false) -> Vector2i:
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var position := Vector2i(x, y)
			if can_place(stack, position, rotated):
				return position
	return Vector2i(-1, -1)

func _is_rect_inside_grid(rect: Rect2i) -> bool:
	return rect.position.x >= 0 \
		and rect.position.y >= 0 \
		and rect.position.x + rect.size.x <= grid_size.x \
		and rect.position.y + rect.size.y <= grid_size.y

func _rects_overlap(a: Rect2i, b: Rect2i) -> bool:
	return a.position.x < b.position.x + b.size.x \
		and a.position.x + a.size.x > b.position.x \
		and a.position.y < b.position.y + b.size.y \
		and a.position.y + a.size.y > b.position.y
