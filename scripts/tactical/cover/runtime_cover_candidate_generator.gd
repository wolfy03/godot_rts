class_name RuntimeCoverCandidateGenerator
extends RefCounted

const INDEX_STRIDE: int = 64

## No tactical context, registry or reservation dependency. Yaw and orthogonal
## positive/negative scale are supported; tilted/sheared/singular boxes are not.
func generate_candidates(source: RuntimeCoverSource, navigation_map: RID) -> Array[CoverCandidate]:
	var candidates: Array[CoverCandidate] = []
	if not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion() \
			or not is_navigation_map_ready(navigation_map):
		return candidates
	var geometry: CollisionShape3D = source.get_geometry_shape()
	if geometry == null or not (geometry.shape is BoxShape3D):
		_warn(source, "Only an enabled descendant BoxShape3D is supported.")
		return candidates
	var box: BoxShape3D = geometry.shape as BoxShape3D
	var transform: Transform3D = geometry.global_transform
	if not _has_supported_transform(transform) or not box.size.is_finite() or box.size.x <= 0.0 \
			or box.size.y <= 0.0 or box.size.z <= 0.0 or not _has_valid_settings(source):
		_warn(source, "Box/configuration must be finite and positive; tilt, shear and singular transforms are unsupported.")
		return candidates
	var half: Vector3 = box.size * 0.5
	var bottom_y: float = -half.y if transform.basis.y.y > 0.0 else half.y
	var normal_basis: Basis = transform.basis.inverse().transposed()
	var world_height: float = absf(transform.basis.y.y) * box.size.y
	var stance: CoverStance.Type = CoverStance.Type.STANDING if world_height >= source.standing_height_threshold \
		else CoverStance.Type.CROUCHING
	for side: int in 4:
		# Stable order: +X, -X, +Z, -Z. Bin centers avoid exact corner endpoints.
		var x_face: bool = side < 2
		var sign_value: float = 1.0 if side % 2 == 0 else -1.0
		var local_normal: Vector3 = Vector3.RIGHT * sign_value if x_face else Vector3.BACK * sign_value
		var normal: Vector3 = (normal_basis * local_normal).normalized()
		var tangent_half: float = half.z if x_face else half.x
		var side_length: float = box.size.z * transform.basis.z.length() if x_face else box.size.x * transform.basis.x.length()
		var sample_count: int = clampi(ceili(side_length / source.sample_spacing), 1, mini(source.max_samples_per_side, INDEX_STRIDE))
		for sample: int in sample_count:
			var tangent: float = lerpf(-tangent_half, tangent_half, (float(sample) + 0.5) / float(sample_count))
			var local_face: Vector3 = Vector3(sign_value * half.x, bottom_y, tangent) if x_face \
				else Vector3(tangent, bottom_y, sign_value * half.z)
			var face_position: Vector3 = transform * local_face
			var raw_position: Vector3 = face_position + normal * source.candidate_clearance
			var projected: Vector3 = NavigationServer3D.map_get_closest_point(navigation_map, raw_position)
			if not projected.is_finite() or raw_position.distance_to(projected) > source.max_navigation_projection_distance:
				continue
			# Projection must preserve at least half the outward clearance. This
			# rejects points inside the box or snapped to its opposite side.
			if (projected - face_position).dot(normal) < source.candidate_clearance * 0.5:
				continue
			if _is_duplicate(candidates, projected, source.minimum_candidate_separation):
				continue
			var candidate: CoverCandidate = CoverCandidate.new()
			candidate.source = source
			candidate.source_revision = source.source_revision
			candidate.position = projected
			candidate.stance = stance
			# Rejection/dedup never renumbers surviving samples. Session-local ID.
			candidate.reservation_key = StringName("runtime:%d:%d:%d" % [source.get_instance_id(),
				source.source_revision, side * INDEX_STRIDE + sample])
			candidates.append(candidate)
	return candidates

static func is_navigation_map_ready(navigation_map: RID) -> bool:
	# A freed RID can still be nonzero. Verify it belongs to NavigationServer.
	if not navigation_map.is_valid() or not NavigationServer3D.get_maps().has(navigation_map):
		return false
	return NavigationServer3D.map_is_active(navigation_map) \
		and NavigationServer3D.map_get_iteration_id(navigation_map) > 0 \
		and NavigationServer3D.map_get_closest_point_owner(navigation_map, Vector3.ZERO).is_valid()

func _has_supported_transform(transform: Transform3D) -> bool:
	var basis: Basis = transform.basis
	if not transform.origin.is_finite() or not basis.is_finite() or absf(basis.determinant()) < 0.000001:
		return false
	var x: Vector3 = basis.x.normalized()
	var y: Vector3 = basis.y.normalized()
	var z: Vector3 = basis.z.normalized()
	return absf(y.dot(Vector3.UP)) > 0.9999 and absf(x.y) < 0.0001 and absf(z.y) < 0.0001 \
		and absf(x.dot(z)) < 0.0001

func _has_valid_settings(source: RuntimeCoverSource) -> bool:
	return is_finite(source.sample_spacing) and source.sample_spacing > 0.0 \
		and is_finite(source.candidate_clearance) and source.candidate_clearance > 0.0 \
		and source.max_samples_per_side > 0 and is_finite(source.max_navigation_projection_distance) \
		and source.max_navigation_projection_distance > 0.0 and is_finite(source.minimum_candidate_separation) \
		and source.minimum_candidate_separation >= 0.0 and is_finite(source.standing_height_threshold) \
		and source.standing_height_threshold > 0.0

func _is_duplicate(candidates: Array[CoverCandidate], position: Vector3, separation: float) -> bool:
	for candidate: CoverCandidate in candidates:
		if candidate.position.distance_squared_to(position) < separation * separation:
			return true
	return false

func _warn(source: RuntimeCoverSource, message: String) -> void:
	if source.debug_generation:
		push_warning("[COVER] Runtime source %s: %s" % [source.name, message])
