class_name CoverEvaluator
extends RefCounted

## Geometry quality only: no reservation, movement, state changes or tree query.
var protection_weight: float = 0.5
var firing_weight: float = 0.25
var travel_weight: float = 0.25
var max_travel_distance: float = 20.0
var minimum_protection_improvement: float = 0.05

func evaluate(unit: Unit, candidate: CoverCandidate, threat: Unit,
		navigation: ChunkedUnitNavigation = null) -> CoverEvaluationResult:
	var result: CoverEvaluationResult = _evaluate_candidate(unit, candidate, threat, navigation)
	if result.valid:
		_apply_current_position_baseline(result, _measure_exposure(unit, unit.global_position, threat))
	return result

## Up to seven exposure rays + one outgoing ray per eligible candidate.
## Current-position exposure is sampled once per batch, not once per candidate.
func find_best_candidate(unit: Unit, candidates: Array[CoverCandidate], threat: Unit,
		navigation: ChunkedUnitNavigation = null) -> CoverEvaluationResult:
	var best: CoverEvaluationResult = CoverEvaluationResult.new()
	best.reason = &"no_valid_candidate"
	if not _has_valid_context(unit, threat):
		best.reason = &"invalid_context"
		return best
	if candidates.is_empty():
		return best
	var current_exposure: float = _measure_exposure(unit, unit.global_position, threat)
	for candidate: CoverCandidate in candidates:
		var result: CoverEvaluationResult = _evaluate_candidate(unit, candidate, threat, navigation)
		if not result.valid:
			continue
		_apply_current_position_baseline(result, current_exposure)
		if not result.improves_current_position or not result.protected_from_threat:
			if not best.valid:
				best.reason = &"no_improving_candidate"
			continue
		if not best.valid or result.final_score > best.final_score:
			best = result
	return best

func _evaluate_candidate(unit: Unit, candidate: CoverCandidate, threat: Unit,
		navigation: ChunkedUnitNavigation) -> CoverEvaluationResult:
	var result: CoverEvaluationResult = CoverEvaluationResult.new()
	result.candidate = candidate
	if candidate == null or not candidate.valid:
		return _reject(result, &"invalid_candidate")
	if not candidate.position.is_finite():
		return _reject(result, &"non_finite_position")
	if not candidate.is_valid_candidate():
		return _reject(result, &"invalid_source")
	var source: Node3D = candidate.get_source()
	if source != null and (source.is_queued_for_deletion() or not source.is_inside_tree()):
		return _reject(result, &"invalid_source")
	if not _has_valid_context(unit, threat):
		return _reject(result, &"invalid_context")
	result.travel_distance = unit.global_position.distance_to(candidate.position)
	result.threat_distance = candidate.position.distance_to(threat.global_position)
	result.recommended_stance = candidate.stance
	if result.travel_distance > max_travel_distance:
		return _reject(result, &"too_far")
	var cover: Cover = source as Cover
	var slot: Marker3D = null
	var occupant: Unit = null
	if cover != null:
		slot = cover.get_candidate_slot(candidate)
		if slot == null:
			return _reject(result, &"missing_slot")
		if not slot.global_position.is_equal_approx(candidate.position):
			return _reject(result, &"stale_slot_position")
		occupant = cover.get_slot_occupant(slot)
		if occupant != null and occupant != unit:
			return _reject(result, &"occupied" if occupant.current_cover == cover else &"reserved")
		# Cheap legacy directional/protection rectangle preflight before raycasts.
		result.protected_from_threat = cover.is_protecting_against(threat.global_position, candidate.position)
		if not result.protected_from_threat:
			return _reject(result, &"no_protection")
	if navigation != null and not navigation.is_world_position_navigable(candidate.position):
		return _reject(result, &"unreachable") # Coarse only; no per-candidate path query.
	if cover != null and occupant != unit and cover.is_slot_blocked(slot):
		return _reject(result, &"blocked")
	result.exposure_score = _measure_exposure(unit, candidate.position, threat)
	result.protection_score = 1.0 - result.exposure_score
	# A directional legacy pass alone cannot claim physical protection.
	# Unbound terrain candidates are also judged by observed geometry visibility.
	result.protected_from_threat = result.protection_score > 0.0
	var firing_origin: Vector3 = candidate.position + (unit.get_muzzle_position() - unit.global_position)
	result.can_fire_at_threat = unit.has_clear_ranged_aim_to(firing_origin, _get_threat_aim_position(threat), threat)
	result.fire_opportunity_score = 1.0 if result.can_fire_at_threat else 0.0
	result.travel_score = clampf(1.0 - result.travel_distance / maxf(max_travel_distance, 0.001), 0.0, 1.0)
	var weight_sum: float = maxf(protection_weight, 0.0) + maxf(firing_weight, 0.0) + maxf(travel_weight, 0.0)
	result.final_score = clampf((result.protection_score * maxf(protection_weight, 0.0)
		+ result.fire_opportunity_score * maxf(firing_weight, 0.0)
		+ result.travel_score * maxf(travel_weight, 0.0)) / maxf(weight_sum, 0.001), 0.0, 1.0)
	result.valid = true
	return result

func _get_virtual_aim_points(unit: Unit, position: Vector3) -> Array[Unit.AimPointData]:
	var samples: Array[Unit.AimPointData] = []
	for marker: Marker3D in unit.get_aim_points():
		var weight: float = unit.get_aim_point_weight(StringName(marker.name))
		if weight > 0.0:
			# World offset includes nested transforms, rotation and scale. Only the
			# root translation changes; actual Unit/Markers are never moved.
			samples.append(Unit.AimPointData.new(position + marker.global_position - unit.global_position, weight))
	return samples

func _measure_exposure(unit: Unit, position: Vector3, threat: Unit) -> float:
	var total_weight: float = 0.0
	var visible_weight: float = 0.0
	var origin: Vector3 = threat.get_muzzle_position()
	for sample: Unit.AimPointData in _get_virtual_aim_points(unit, position):
		total_weight += sample.weight
		if threat.has_clear_ranged_aim_to(origin, sample.position, unit):
			visible_weight += sample.weight
	# The complete seven-point layout sums to 1. Missing samples cannot falsely
	# imply full protection; normalize the available weights, or assume exposure.
	return clampf(visible_weight / total_weight, 0.0, 1.0) if total_weight > 0.0 else 1.0

func _get_threat_aim_position(threat: Unit) -> Vector3:
	for marker: Marker3D in threat.get_aim_points():
		if marker.name == &"Chest":
			return marker.global_position
	return threat.get_muzzle_position()

func _has_valid_context(unit: Unit, threat: Unit) -> bool:
	if not is_instance_valid(unit) or not is_instance_valid(threat) or unit == threat:
		return false
	if not unit.is_inside_tree() or not threat.is_inside_tree() or unit.get_world_3d() != threat.get_world_3d():
		return false
	return unit.get_current_health() > 0 and threat.get_current_health() > 0 \
		and unit.global_position.is_finite() and threat.global_position.is_finite()

func _apply_current_position_baseline(result: CoverEvaluationResult, current_exposure: float) -> void:
	result.current_exposure_score = current_exposure
	result.protection_improvement = result.current_exposure_score - result.exposure_score
	result.improves_current_position = result.travel_distance > 0.05 and result.protection_improvement >= minimum_protection_improvement

func _reject(result: CoverEvaluationResult, reason: StringName) -> CoverEvaluationResult:
	result.reason = reason
	return result
