extends Node3D

const COVER_SCENE: PackedScene = preload("res://scenes/units/cover.tscn")
const BASE_UNIT: PackedScene = preload("res://scenes/units/base_units/base_unit.tscn")
const MAIN_LEVEL: PackedScene = preload("res://scenes/levels/test_level/test_level.tscn")

var _failed: bool = false

func _ready() -> void:
	_test_registration_query_and_snapshots()
	_test_world_isolation()
	await _test_legacy_ai_fallback()
	_test_main_level_bootstrap()
	print("cover_system_test: %s" % ["FAIL" if _failed else "PASS"])
	get_tree().quit(1 if _failed else 0)

func _test_registration_query_and_snapshots() -> void:
	var a: Cover = _make_cover(self, Vector3.ZERO,
		[Vector3(-1.0, 1.0, 0.0), Vector3(2.0, 1.0, 0.0), Vector3(7.0, 1.0, 0.0)])
	# A distant source origin must not hide its nearby authored slot.
	var b: Cover = _make_cover(self, Vector3(30.0, 0.0, 0.0),
		[Vector3(-29.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0)])
	var system: CoverSystem = CoverSystem.new()
	add_child(system)
	_expect(system.get_debug_snapshot()["registered_source_count"] == 2,
		"one-time bootstrap must register pre-existing covers")
	system.register_cover_source(a)
	system.register_cover_source(a)
	system.register_cover_source(null)
	_expect(system.get_debug_snapshot()["registered_source_count"] == 2, "duplicate/null registration must be harmless")
	var origin: Vector3 = Vector3(0.0, 1.0, 0.0)
	var candidates: Array[CoverCandidate] = system.query_candidates(origin, 3.0)
	_expect(candidates.size() == 3, "query must filter individual slots, including nearby slots of distant sources")
	var keys: Array[StringName] = []
	var last_source_id: int = 0
	for candidate: CoverCandidate in candidates:
		_expect(candidate.position.distance_squared_to(origin) <= 9.0, "every returned candidate must be in radius")
		_expect(not keys.has(candidate.reservation_key), "registration must not create duplicate candidates")
		_expect(candidate.source_instance_id >= last_source_id, "sources must have deterministic instance-ID order")
		keys.append(candidate.reservation_key)
		last_source_id = candidate.source_instance_id
	var repeated: Array[CoverCandidate] = system.query_candidates(origin, 3.0)
	for index in candidates.size():
		_expect(repeated[index] != candidates[index] and repeated[index].reservation_key == keys[index],
			"repeated queries must keep stable order and identity but return fresh snapshots")
	_expect(system.query_candidates(origin, 0.0).is_empty() and system.query_candidates(origin, -1.0).is_empty()
		and system.query_candidates(origin, INF).is_empty() and system.query_candidates(Vector3.INF, 3.0).is_empty(),
		"nonpositive/nonfinite query inputs must return no candidates")
	var slot: Marker3D = a.get_cover_slots()[0]
	var old: CoverCandidate = a.create_candidate_from_slot(slot)
	var snapshot: CoverCandidate = _find_by_key(candidates, old.reservation_key)
	slot.position.x = -2.0
	var fresh: CoverCandidate = _find_by_key(system.query_candidates(origin, 3.0), old.reservation_key)
	_expect(snapshot != null and fresh != null and snapshot.position == old.position
		and fresh.position == slot.global_position and fresh.position != snapshot.position,
		"moving a marker must update the next query without mutating earlier snapshots")
	var occupant: Unit = _make_unit(self, Vector3(15.0, 1.0, 15.0))
	a.slot_blocked_check_enabled = false
	a.reserve_candidate(occupant, fresh)
	_expect(_find_by_key(system.query_candidates(origin, 3.0), fresh.reservation_key) != null,
		"spatial query must include reserved candidates")
	occupant.occupy_reserved_cover()
	_expect(_find_by_key(system.query_candidates(origin, 3.0), fresh.reservation_key) != null
		and a.get_slot_occupant(slot) == occupant, "query must include occupied slots without changing reservation")
	occupant.clear_cover()
	occupant.free()
	var runtime: Cover = _make_cover(self, Vector3.ZERO, [Vector3(0.0, 1.0, 2.0)])
	_expect(system.query_candidates(origin, 3.0).size() == 3,
		"query must not rescan the covers group for unregistered runtime sources")
	system.register_cover_source(runtime)
	_expect(system.get_debug_snapshot()["registered_source_count"] == 3
		and system.query_candidates(origin, 3.0).size() == 4, "explicit runtime registration must be visible immediately")
	var deleted_source_id: int = a.get_instance_id()
	a.free()
	_expect(system.get_debug_snapshot()["registered_source_count"] == 2, "source tree exit must unregister it")
	for candidate: CoverCandidate in system.query_candidates(origin, 3.0):
		_expect(candidate.source_instance_id != deleted_source_id, "deleted source must never be returned")
	_expect(snapshot.get_source() == null, "old snapshots must safely outlive deleted sources")
	b.queue_free()
	_expect(system.query_candidates(origin, 3.0).size() == 1
		and system.get_debug_snapshot()["registered_source_count"] == 1,
		"pruning must exclude queued sources before deferred deletion")
	system.unregister_cover_source(runtime)
	system.unregister_cover_source(runtime)
	system.register_cover_source(runtime)
	_expect(system.get_debug_snapshot()["registered_source_count"] == 1
		and runtime.tree_exiting.get_connections().size() == 1, "re-register must keep a single exit callback")
	remove_child(runtime)
	_expect(system.get_debug_snapshot()["registered_source_count"] == 0, "tree removal must unregister live sources too")
	add_child(runtime)
	system.register_cover_source(runtime)
	_expect(system.query_candidates(origin, 3.0).size() == 1, "re-entering sources can explicitly register again")
	system.free()
	runtime.free()
	print("cover system / bootstrap, radius, snapshots, lifecycle: %s" % ["FAIL" if _failed else "PASS"])

func _test_world_isolation() -> void:
	var cover: Cover = _make_cover(self, Vector3.ZERO, [Vector3(0.0, 1.0, -1.0)])
	var system: CoverSystem = CoverSystem.new()
	add_child(system)
	var viewport: SubViewport = SubViewport.new()
	viewport.world_3d = World3D.new()
	add_child(viewport)
	var foreign_root: Node3D = Node3D.new()
	viewport.add_child(foreign_root)
	var foreign_cover: Cover = _make_cover(foreign_root, Vector3.ZERO, [Vector3(0.0, 1.0, 1.0)])
	var foreign_system: CoverSystem = CoverSystem.new()
	foreign_root.add_child(foreign_system)
	_expect(foreign_system.get_world_3d() != system.get_world_3d(), "fixture must use independent World3D instances")
	system.register_cover_source(foreign_cover)
	foreign_system.register_cover_source(cover)
	_expect(system.get_debug_snapshot()["registered_source_count"] == 1
		and foreign_system.get_debug_snapshot()["registered_source_count"] == 1,
		"bootstrap and explicit registration must reject sources from another World3D")
	_expect(system.query_candidates(Vector3.ZERO, 5.0)[0].get_source() == cover
		and foreign_system.query_candidates(Vector3.ZERO, 5.0)[0].get_source() == foreign_cover,
		"independent worlds must never mix query results")
	var unit: Unit = _make_unit(foreign_root, Vector3(-6.0, 1.0, -4.0))
	_expect(unit.ai_brain._get_cover_system() == foreign_system,
		"AI must cache the same-World3D service even if another system registered first")
	foreign_system.free()
	_expect(unit.ai_brain._get_cover_system() == null,
		"deleting a cached service must safely release it without choosing another world's service")
	viewport.free()
	system.free()
	cover.free()
	print("cover system / World3D isolation and AI lookup: %s" % ["FAIL" if _failed else "PASS"])

func _test_legacy_ai_fallback() -> void:
	var unit: Unit = _make_unit(self, Vector3(-6.0, 1.0, -4.0))
	var threat: Unit = _make_unit(self, Vector3(0.0, 1.0, 8.0), true)
	var cover: Cover = _make_cover(self, Vector3.ZERO, [Vector3(0.0, 1.0, -1.0)])
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	unit.clear_player_command()
	var candidate: CoverCandidate = unit.ai_brain._get_cover_against(threat)
	_expect(candidate != null and candidate.get_source() == cover and unit.ai_brain._cover_system == null
		and unit.ai_brain._cover_system_lookup_done, "missing CoverSystem must retain threat-based legacy fallback")
	unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
	unit.free()
	threat.free()
	cover.free()
	print("cover system / legacy AI fallback: %s" % ["FAIL" if _failed else "PASS"])

func _test_main_level_bootstrap() -> void:
	var level: Node3D = MAIN_LEVEL.instantiate() as Node3D
	level.process_mode = Node.PROCESS_MODE_DISABLED
	for body: Node in level.find_children("*", "CharacterBody3D", true, false):
		var unit: Unit = body as Unit
		if unit != null:
			unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
	add_child(level)
	var system: CoverSystem = level.get_node("CoverSystem") as CoverSystem
	_expect(system.get_debug_snapshot()["registered_source_count"] == 3
		and system.query_candidates(Vector3.ZERO, 50.0).size() == 24,
		"main combat level must bootstrap its three authored sources and 24 slots")
	var unit: Unit = level.get_node("UnitsContainer/Unit2") as Unit
	_expect(unit.ai_brain._get_cover_system() == system, "main combat AI must resolve its level's CoverSystem")
	level.free()
	print("cover system / main combat level integration: %s" % ["FAIL" if _failed else "PASS"])

func _make_cover(parent: Node, position: Vector3, slots: Array[Vector3]) -> Cover:
	var cover: Cover = COVER_SCENE.instantiate() as Cover
	cover.position = position
	var container: Node = cover.get_node("CoverSlots")
	for child: Node in container.get_children():
		child.free()
	for index in slots.size():
		var slot: Marker3D = Marker3D.new()
		slot.name = "Slot%d" % index
		slot.position = slots[index]
		container.add_child(slot)
	var collider: CollisionShape3D = cover.get_node("CollisionShape3D") as CollisionShape3D
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(4.0, 4.0, 1.0)
	collider.shape = shape
	collider.position.y = 2.0
	parent.add_child(cover)
	return cover

func _make_unit(parent: Node, position: Vector3, enemy: bool = false) -> Unit:
	var unit: Unit = BASE_UNIT.instantiate() as Unit
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.position = position
	unit.begin_player_command(Unit.PlayerCommandMode.HOLD_POSITION)
	if enemy:
		unit.collision_layer = Unit.ENEMY_UNIT_MASK
	(unit.get_node("NavigationAgent") as NavigationAgent3D).avoidance_enabled = false
	parent.add_child(unit)
	return unit

func _find_by_key(candidates: Array[CoverCandidate], key: StringName) -> CoverCandidate:
	for candidate: CoverCandidate in candidates:
		if candidate.reservation_key == key:
			return candidate
	return null

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
