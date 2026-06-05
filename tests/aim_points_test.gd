extends SceneTree

const BASE_UNIT_SCENE := preload("res://scenes/units/base_units/base_unit.tscn")
const REQUIRED_AIM_POINTS := [
	"Head",
	"Chest",
	"Stomach",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
]

func _init() -> void:
	var unit := BASE_UNIT_SCENE.instantiate()
	root.add_child(unit)
	var aim_points := unit.get_node_or_null("AimPoints")
	if aim_points == null:
		_fail("Base unit must expose an AimPoints node.")
		return
	for point_name in REQUIRED_AIM_POINTS:
		var point := aim_points.get_node_or_null(point_name)
		if not (point is Marker3D):
			_fail("Aim point %s must be a Marker3D." % point_name)
			return
	unit.queue_free()
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
