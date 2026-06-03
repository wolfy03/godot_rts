extends Node3D
class_name MissionArea

@export var radius: float:
	get:
		return _radius
	set(value):
		_radius = maxf(0.5, value)
		_refresh_visual()

var _visual: MeshInstance3D
var _radius: float = 8.0

func _ready() -> void:
	add_to_group("mission_areas")
	_ensure_visual()
	_refresh_visual()

func set_area(area_position: Vector3, new_radius: float) -> void:
	global_position = area_position
	radius = new_radius

func _ensure_visual() -> void:
	if _visual != null:
		return
	
	_visual = MeshInstance3D.new()
	_visual.name = "MissionAreaVisual"
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)

func _refresh_visual() -> void:
	if not is_inside_tree():
		return
	
	_ensure_visual()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.08
	mesh.radial_segments = 48
	_visual.mesh = mesh
	_visual.position = Vector3(0.0, 0.08, 0.0)
	
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.75, 1.0, 0.22)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_visual.material_override = material
