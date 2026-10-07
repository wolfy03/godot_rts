class_name RuntimeCoverSource
extends Node3D

## Geometry/configuration only. Changes require an explicit revision increment.
@export var source_revision: int = 0
## Default is one named direct child. An explicit path may point to a descendant
## (e.g. StaticBody3D/CollisionShape3D) so the same box also blocks physics rays.
@export_node_path("CollisionShape3D") var geometry_shape_path: NodePath = ^"CollisionShape3D"
@export_range(0.25, 10.0, 0.05) var sample_spacing: float = 1.0
@export_range(0.1, 5.0, 0.05) var candidate_clearance: float = 0.7
@export_range(1, 64, 1) var max_samples_per_side: int = 16
@export_range(0.1, 5.0, 0.05) var max_navigation_projection_distance: float = 1.5
@export_range(0.0, 5.0, 0.05) var minimum_candidate_separation: float = 0.4
## Compatibility metadata; standing Unit head is about 1.75m above the floor.
@export_range(0.1, 5.0, 0.05) var standing_height_threshold: float = 1.8
@export var debug_generation: bool = false

func _ready() -> void:
	add_to_group("runtime_cover_sources")

func get_geometry_shape() -> CollisionShape3D:
	var geometry: CollisionShape3D = get_node_or_null(geometry_shape_path) as CollisionShape3D
	if not is_instance_valid(geometry) or geometry.is_queued_for_deletion() or geometry.disabled \
			or not is_ancestor_of(geometry):
		return null
	return geometry
