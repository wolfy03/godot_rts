class_name CoverSystem
extends Node3D

## Level-local spatial query boundary. No scoring, threats or reservations.
## Each query returns fresh legacy snapshots; there is no candidate cache.
var _cover_sources: Dictionary[int, WeakRef] = {}
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
	return {
		"registered_source_count": _cover_sources.size(),
		"last_query_source_count": _last_query_source_count,
		"last_query_candidate_count": _last_query_candidate_count,
	}

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
