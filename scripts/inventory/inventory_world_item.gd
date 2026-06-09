extends Area3D
class_name InventoryWorldItem

const InventoryItemStackScript := preload("res://scripts/inventory/inventory_item_stack.gd")

@export var item: Resource
@export var quantity: int = 1

@onready var _label: Label3D = $Label3D
@onready var _pickup_prompt_label: Label3D = $PickupPromptLabel

func _ready() -> void:
	add_to_group("inventory_world_items")
	set_pickup_prompt_visible(false)
	_update_label()

func create_stack() -> Resource:
	if item == null:
		return null
	var stack: Resource = InventoryItemStackScript.new()
	stack.item = item
	stack.quantity = maxi(1, quantity)
	return stack

func set_pickup_prompt_visible(should_show: bool) -> void:
	if _pickup_prompt_label != null:
		_pickup_prompt_label.visible = should_show

func get_item_size() -> Vector2i:
	if item == null:
		return Vector2i.ZERO
	var size = item.get("grid_size")
	return size if size is Vector2i else Vector2i.ZERO

func _update_label() -> void:
	if _label == null:
		return
	if item == null:
		_label.text = "Item"
		return

	var size := get_item_size()
	var display_name = item.get("display_name")
	var item_name := String(display_name) if display_name != null else item.resource_path.get_file().get_basename()
	_label.text = "%s\n%dx%d" % [item_name, size.x, size.y]
