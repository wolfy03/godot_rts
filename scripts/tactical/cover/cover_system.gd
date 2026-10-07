class_name CoverSystem
extends Node3D

## Level-local spatial query and runtime reservation boundary. No tactical scoring.
## Each query returns fresh legacy snapshots; there is no candidate cache.
var _cover_sources: Dictionary[int, WeakRef] = {}
## Runtime keys identify logical locations, not positions or persistent save IDs.
## Legacy Cover candidates retain their separate exact-slot reservation backend.
var _runtime_reservations: Dictionary[StringName, WeakRef] = {}
var _last_query_source_count: int = 0
var _last_query_candidate_count: int = 0

func _ready() -> void:
	add_to_group("cover_system")
	# One startup scan. Runtime spawners must explicitly register new sources.
	for node: Node in get_tree().get_nodes_in_group("covers"):
		register_cover_source(node as Cover)

func register_cover_source(cover: Cover) -> void:
	if not _is_live_source(cover):
		return
	var source_id: int = cover.get_instance_id()
	if _cover_sources.has(source_id):
		return
	_cover_sources[source_id] = weakref(cover)
	var callback: Callable = _unregister_cover_source_by_id.bind(source_id)
	# Manual unregister/re-register before tree exit must not duplicate callbacks.
	if not cover.tree_exiting.is_connected(callback):
		cover.tree_exiting.connect(callback, CONNECT_ONE_SHOT)

func unregister_cover_source(cover: Cover) -> void:
	if is_instance_valid(cover):
		_unregister_cover_source_by_id(cover.get_instance_id())

func query_candidates(origin: Vector3, radius: float) -> Array[CoverCandidate]:
	var candidates: Array[CoverCandidate] = []
	_last_query_source_count = 0
	_last_query_candidate_count = 0
	_prune_runtime_reservations()
	if not is_inside_tree() or not origin.is_finite() or not is_finite(radius) or radius <= 0.0:
		return candidates
	_prune_invalid_sources()
	var radius_sq: float = radius * radius
	var source_ids: Array[int] = []
	source_ids.assign(_cover_sources.keys())
	source_ids.sort()
	for source_id: int in source_ids:
		var cover: Cover = _cover_sources[source_id].get_ref() as Cover
		_last_query_source_count += 1
		# No strict center filter: a large Cover can have nearby distant slots.
		# Keep Cover's authored slot order within sorted runtime source identities.
		for candidate: CoverCandidate in cover.get_cover_candidates():
			if candidate.position.is_finite() and origin.distance_squared_to(candidate.position) <= radius_sq:
				candidates.append(candidate)
	_last_query_candidate_count = candidates.size()
	return candidates

func get_debug_snapshot() -> Dictionary:
	_prune_invalid_sources()
	_prune_runtime_reservations()
	return {
		"registered_source_count": _cover_sources.size(),
		"runtime_reservation_count": _runtime_reservations.size(),
		"last_query_source_count": _last_query_source_count,
		"last_query_candidate_count": _last_query_candidate_count,
	}

## Runtime-only backend: never intercept legacy Cover reservation identities.
## This claims ownership; TakeCoverState/Unit separately track travel/occupation.
func reserve_candidate(unit: Unit, candidate: CoverCandidate) -> bool:
	if not is_candidate_available(unit, candidate):
		return false
	_runtime_reservations[candidate.reservation_key] = weakref(unit)
	return true

func release_candidate(unit: Unit, candidate: CoverCandidate) -> void:
	_prune_runtime_reservations()
	# Release still works after explicit invalidation; validity is an acquisition
	# requirement, not a reason to strand an existing ownership record.
	if not is_instance_valid(unit) or candidate == null or candidate.get_source() is Cover:
		return
	var occupant: Unit = get_runtime_candidate_occupant(candidate)
	if occupant == unit:
		_runtime_reservations.erase(candidate.reservation_key)

func is_candidate_available(unit: Unit, candidate: CoverCandidate) -> bool:
	_prune_runtime_reservations()
	if not _is_live_runtime_unit(unit) or candidate == null or not candidate.is_valid_candidate() \
			or not candidate.position.is_finite() or candidate.reservation_key == &"":
		return false
	var source: Node3D = candidate.get_source()
	if source is Cover:
		return false
	if source != null and (source.is_queued_for_deletion() or not source.is_inside_tree() \
			or source.get_world_3d() != get_world_3d()):
		return false
	var occupant: Unit = get_runtime_candidate_occupant(candidate)
	return occupant == null or occupant == unit

func get_runtime_candidate_occupant(candidate: CoverCandidate) -> Unit:
	_prune_runtime_reservations()
	if candidate == null or candidate.get_source() is Cover:
		return null
	var occupant_ref: WeakRef = _runtime_reservations.get(candidate.reservation_key) as WeakRef
	return occupant_ref.get_ref() as Unit if occupant_ref != null else null

func _is_live_runtime_unit(unit: Unit) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(unit) \
		and unit.is_inside_tree() and not unit.is_queued_for_deletion() and not unit._is_dead \
		and unit.get_current_health() > 0 and unit.get_world_3d() == get_world_3d()

func _prune_runtime_reservations() -> void:
	for key: StringName in _runtime_reservations.keys():
		var occupant: Unit = _runtime_reservations[key].get_ref() as Unit
		if not _is_live_runtime_unit(occupant):
			_runtime_reservations.erase(key)

func _is_live_source(cover: Cover) -> bool:
	return is_inside_tree() and is_instance_valid(cover) and not cover.is_queued_for_deletion() \
		and cover.is_inside_tree() and cover.get_world_3d() == get_world_3d()

func _prune_invalid_sources() -> void:
	for source_id: int in _cover_sources.keys():
		var cover: Cover = _cover_sources[source_id].get_ref() as Cover
		if not _is_live_source(cover):
			_unregister_cover_source_by_id(source_id)

func _unregister_cover_source_by_id(source_id: int) -> void:
	_cover_sources.erase(source_id)
