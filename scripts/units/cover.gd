extends Node3D
class_name Cover

enum CoverGrade {
	LOW,
	MEDIUM,
	HIGH
}

@export var grade: CoverGrade = CoverGrade.MEDIUM
@export var protection_margin: float = 0.35
@export_range(-1.0, 1.0, 0.01) var protection_opposite_side_dot_threshold: float = -0.45
@export var navigation_obstacle_padding: float = 0.2
@export var navigation_obstacle_height_padding: float = 0.5
@export_flags_3d_navigation var navigation_obstacle_layers: int = 3
@export var navigation_route_clearance: float = 0.8
@export var slot_blocked_check_enabled: bool = true
@export var slot_blocked_check_radius: float = 0.32
@export_flags_3d_physics var slot_blocked_collision_mask: int = 1

var _slot_occupants: Dictionary = {}

func _ready():
	add_to_group("covers")
	_configure_navigation_obstacle()

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
		if is_slot_blocked(slot):
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
		if not _slot_occupants.has(_get_slot_key(slot)) and not is_slot_blocked(slot):
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

## Compatibility view of every existing slot, including occupied/blocked slots.
## This does not reserve slots or evaluate candidates. Each call makes snapshots.
func get_cover_candidates() -> Array[CoverCandidate]:
	var candidates: Array[CoverCandidate] = []
	for slot in get_cover_slots():
		var candidate: CoverCandidate = create_candidate_from_slot(slot)
		if candidate != null:
			candidates.append(candidate)
	return candidates

## Convert only this Cover's direct Marker slots. Call with the Cover in-tree
## so the snapshot captures the slot's world position.
func create_candidate_from_slot(slot: Marker3D) -> CoverCandidate:
	if not is_instance_valid(slot):
		return null
	var slots_parent: Node = get_node_or_null("CoverSlots")
	if slots_parent == null or slot.get_parent() != slots_parent:
		return null

	var candidate: CoverCandidate = CoverCandidate.new()
	candidate.position = slot.global_position
	candidate.source = self
	# Temporary compatibility rule: geometry analysis will eventually determine
	# stance instead of CoverGrade. LOW/MEDIUM crouch; HIGH stands.
	match grade:
		CoverGrade.LOW, CoverGrade.MEDIUM:
			candidate.stance = CoverStance.Type.CROUCHING
		CoverGrade.HIGH:
			candidate.stance = CoverStance.Type.STANDING
	# Instance ID isolates covers; relative slot path distinguishes their slots
	# and keeps keys stable when the Cover is renamed or reparented.
	candidate.reservation_key = StringName("%d:%s" % [get_instance_id(), get_path_to(slot)])
	return candidate

func is_slot_blocked(slot: Marker3D) -> bool:
	if not slot_blocked_check_enabled or slot == null:
		return false
	if slot_blocked_collision_mask == 0:
		return false

	var world := get_world_3d()
	if world == null:
		return false

	var shape := SphereShape3D.new()
	shape.radius = slot_blocked_check_radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), slot.global_position)
	query.collision_mask = slot_blocked_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = _get_slot_blocked_query_exclusions()

	return not world.direct_space_state.intersect_shape(query, 1).is_empty()

func is_protecting_against(attack_origin: Vector3, protected_position: Vector3) -> bool:
	if attack_origin == Vector3.INF or protected_position == Vector3.INF:
		return false

	var local_attack := to_local(attack_origin)
	var local_protected := to_local(protected_position)
	var from := Vector2(local_attack.x, local_attack.z)
	var to := Vector2(local_protected.x, local_protected.z)
	if from.distance_squared_to(to) < 0.001:
		return false
	if not _is_attack_from_opposite_cover_side(from, to):
		return false

	var bounds := _get_horizontal_protection_bounds()
	return _does_segment_intersect_rect(from, to, bounds)

func get_navigation_route_waypoint(from_position: Vector3, to_position: Vector3) -> Vector3:
	var local_from := to_local(from_position)
	var local_to := to_local(to_position)
	var from := Vector2(local_from.x, local_from.z)
	var to := Vector2(local_to.x, local_to.z)
	var bounds := _get_navigation_obstacle_bounds()

	if not _does_segment_intersect_rect(from, to, bounds):
		return Vector3.INF

	var best_candidate := Vector2.INF
	var best_distance := INF
	for candidate in _get_route_corner_candidates(bounds):
		if _does_segment_intersect_rect(from, candidate, bounds):
			continue
		if _does_segment_intersect_rect(candidate, to, bounds):
			continue

		var distance := from.distance_to(candidate) + candidate.distance_to(to)
		if distance < best_distance:
			best_distance = distance
			best_candidate = candidate

	if best_candidate == Vector2.INF:
		return Vector3.INF

	return to_global(Vector3(best_candidate.x, local_to.y, best_candidate.y))

func _prune_invalid_occupants() -> void:
	for slot_key in _slot_occupants.keys():
		var unit := _slot_occupants[slot_key] as Unit
		if not is_instance_valid(unit):
			_slot_occupants.erase(slot_key)

func _get_slot_key(slot: Marker3D) -> String:
	return str(slot.get_path())

func _get_slot_blocked_query_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []
	var collision_object := get_node_or_null(".") as CollisionObject3D
	if collision_object != null:
		exclusions.append(collision_object.get_rid())
	return exclusions

func _configure_navigation_obstacle() -> void:
	var obstacle := get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
	if obstacle == null:
		return

	var bounds := _get_navigation_obstacle_bounds()
	var padded_position := bounds.position
	var padded_size := bounds.size

	obstacle.vertices = PackedVector3Array([
		Vector3(padded_position.x, 0.0, padded_position.y),
		Vector3(padded_position.x, 0.0, padded_position.y + padded_size.y),
		Vector3(padded_position.x + padded_size.x, 0.0, padded_position.y + padded_size.y),
		Vector3(padded_position.x + padded_size.x, 0.0, padded_position.y),
	])
	obstacle.height = _get_navigation_obstacle_height()
	obstacle.avoidance_enabled = true
	obstacle.avoidance_layers = navigation_obstacle_layers
	obstacle.radius = 0.0
	obstacle.use_3d_avoidance = false
	obstacle.affect_navigation_mesh = true
	obstacle.carve_navigation_mesh = true

func _get_horizontal_protection_bounds() -> Rect2:
	var bounds := _get_horizontal_collision_bounds()
	return Rect2(
		bounds.position - Vector2.ONE * protection_margin,
		bounds.size + Vector2.ONE * protection_margin * 2.0
	)

func _get_horizontal_collision_bounds() -> Rect2:
	for child in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null:
			continue

		var box := shape_node.shape as BoxShape3D
		if box == null:
			continue

		var half_size := Vector2(box.size.x, box.size.z) * 0.5
		var center := Vector2(shape_node.position.x, shape_node.position.z)
		var rect_position := center - half_size
		var size := half_size * 2.0
		return Rect2(rect_position, size)

	return Rect2(Vector2(-0.5, -0.5), Vector2.ONE)

func _get_navigation_obstacle_bounds() -> Rect2:
	var bounds := _get_horizontal_collision_bounds()
	return Rect2(
		bounds.position - Vector2.ONE * navigation_obstacle_padding,
		bounds.size + Vector2.ONE * navigation_obstacle_padding * 2.0
	)

func _get_navigation_obstacle_height() -> float:
	for child in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null:
			continue

		var box := shape_node.shape as BoxShape3D
		if box != null:
			return maxf(0.1, box.size.y + navigation_obstacle_height_padding)

	return 1.0 + navigation_obstacle_height_padding

func _does_segment_intersect_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	var direction := to - from
	var t_min := 0.0
	var t_max := 1.0

	var x_result := _clip_segment_axis(from.x, direction.x, rect.position.x, rect.position.x + rect.size.x, t_min, t_max)
	if not bool(x_result[0]):
		return false
	t_min = float(x_result[1])
	t_max = float(x_result[2])

	var y_result := _clip_segment_axis(from.y, direction.y, rect.position.y, rect.position.y + rect.size.y, t_min, t_max)
	if not bool(y_result[0]):
		return false
	t_min = float(y_result[1])
	t_max = float(y_result[2])

	return t_max > 0.0 and t_min < 1.0

func _get_route_corner_candidates(bounds: Rect2) -> Array[Vector2]:
	var min_x := bounds.position.x - navigation_route_clearance
	var max_x := bounds.position.x + bounds.size.x + navigation_route_clearance
	var min_y := bounds.position.y - navigation_route_clearance
	var max_y := bounds.position.y + bounds.size.y + navigation_route_clearance
	var candidates: Array[Vector2] = []
	candidates.append(Vector2(min_x, min_y))
	candidates.append(Vector2(min_x, max_y))
	candidates.append(Vector2(max_x, min_y))
	candidates.append(Vector2(max_x, max_y))
	return candidates

func _is_attack_from_opposite_cover_side(attack_position: Vector2, protected_position: Vector2) -> bool:
	var protected_side := protected_position
	var attack_side := attack_position
	if protected_side.length_squared() < 0.001 or attack_side.length_squared() < 0.001:
		return false

	return protected_side.normalized().dot(attack_side.normalized()) <= protection_opposite_side_dot_threshold

func _clip_segment_axis(start: float, direction: float, min_value: float, max_value: float, t_min: float, t_max: float) -> Array:
	if is_zero_approx(direction):
		return [start >= min_value and start <= max_value, t_min, t_max]

	var inverse_direction := 1.0 / direction
	var axis_t1 := (min_value - start) * inverse_direction
	var axis_t2 := (max_value - start) * inverse_direction
	if axis_t1 > axis_t2:
		var swap := axis_t1
		axis_t1 = axis_t2
		axis_t2 = swap

	t_min = maxf(t_min, axis_t1)
	t_max = minf(t_max, axis_t2)
	return [t_min <= t_max, t_min, t_max]
