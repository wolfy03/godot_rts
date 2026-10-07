extends Node3D

const COVER_SCENE: PackedScene = preload("res://scenes/units/cover.tscn")
const BASE_UNIT_SCENE: PackedScene = preload("res://scenes/units/base_units/base_unit.tscn")

var _failed: bool = false

func _ready() -> void:
	_test_slot_adapter()
	_test_candidate_lifetime()
	_test_evaluation_defaults()
	_test_legacy_cover_flow()

	if _failed:
		get_tree().quit(1)
	else:
		print("cover_candidate_test: PASS")
		get_tree().quit(0)

func _test_slot_adapter() -> void:
	var cover_a: Cover = _make_cover(Vector3(7.0, 2.0, -4.0))
	cover_a.rotation.y = 0.7
	var cover_b: Cover = _make_cover(Vector3(-8.0, 0.0, 3.0))
	var slots: Array[Marker3D] = cover_a.get_cover_slots()
	var candidates: Array[CoverCandidate] = cover_a.get_cover_candidates()
	_expect(not slots.is_empty(), "fixture must contain slots")
	_expect(candidates.size() == slots.size(), "candidate count must match slot count")
	var keys: Array[StringName] = []
	for index in mini(slots.size(), candidates.size()):
		var candidate: CoverCandidate = candidates[index]
		_expect(candidate.position.distance_to(slots[index].global_position) < 0.0001,
			"candidate must capture transformed world position")
		var candidate_object: Object = candidate
		_expect(candidate_object is RefCounted and not (candidate_object is Node), "candidate must be runtime data")
		_expect(candidate.source == cover_a and candidate.get_source() == cover_a,
			"source property and accessor must resolve the originating Cover")
		_expect(candidate.source_instance_id == cover_a.get_instance_id(), "source ID must match Cover")
		_expect(candidate.source_revision == 0, "adapter must not invent geometry revisions")
		_expect(candidate.has_valid_source() and candidate.is_valid_candidate(), "live candidate must be valid")
		_expect(candidate.reservation_key != &"", "reservation key must not be empty")
		_expect(not keys.has(candidate.reservation_key), "keys must be unique within a Cover")
		keys.append(candidate.reservation_key)
		_expect(candidate.stance == CoverStance.Type.CROUCHING, "MEDIUM must initially crouch")

	for candidate in cover_b.get_cover_candidates():
		_expect(not keys.has(candidate.reservation_key), "identical Cover slots must not collide across covers")
	var repeated: Array[CoverCandidate] = cover_a.get_cover_candidates()
	for index in mini(candidates.size(), repeated.size()):
		_expect(repeated[index] != candidates[index], "queries must create independent snapshots")
		_expect(repeated[index].reservation_key == candidates[index].reservation_key,
			"repeated queries must preserve reservation identity")

	cover_a.grade = Cover.CoverGrade.LOW
	for candidate in cover_a.get_cover_candidates():
		_expect(candidate.stance == CoverStance.Type.CROUCHING, "LOW must initially crouch")
	cover_a.grade = Cover.CoverGrade.HIGH
	for candidate in cover_a.get_cover_candidates():
		_expect(candidate.stance == CoverStance.Type.STANDING, "HIGH must initially stand")
	_expect(cover_a.create_candidate_from_slot(null) == null, "null slot must be rejected")
	_expect(cover_a.create_candidate_from_slot(cover_b.get_cover_slots()[0]) == null,
		"another Cover's slot must be rejected")

	var container: Node3D = Node3D.new()
	add_child(container)
	cover_a.reparent(container)
	cover_a.name = "RenamedCover"
	var reparented: Array[CoverCandidate] = cover_a.get_cover_candidates()
	for index in mini(candidates.size(), reparented.size()):
		_expect(reparented[index].reservation_key == candidates[index].reservation_key,
			"renaming/reparenting Cover must preserve candidate identity")
	container.free()
	cover_b.free()

func _test_candidate_lifetime() -> void:
	var candidate: CoverCandidate = CoverCandidate.new()
	_expect(candidate.source == null and candidate.source_instance_id == 0, "new candidate must be unbound")
	_expect(candidate.stance == CoverStance.Type.UNKNOWN, "unresolved stance must be UNKNOWN")
	_expect(not candidate.has_valid_source() and candidate.is_valid_candidate(),
		"source-less terrain candidates must remain usable")
	candidate.valid = false
	_expect(not candidate.is_valid_candidate(), "explicit invalidation must reject unbound candidates")

	var cover: Cover = _make_cover(Vector3.ZERO)
	var slot: Marker3D = cover.get_cover_slots()[0]
	candidate = cover.create_candidate_from_slot(slot)
	var original_position: Vector3 = candidate.position
	var original_key: StringName = candidate.reservation_key
	var original_source_id: int = candidate.source_instance_id
	slot.free()
	_expect(candidate.position == original_position and candidate.reservation_key == original_key,
		"deleting a Marker must leave a safe data snapshot")
	_expect(candidate.is_valid_candidate(), "slot invalidation is deferred; live source still resolves")
	_expect(cover.get_cover_candidates().size() == cover.get_cover_slots().size(),
		"fresh query must reflect removed slots")
	candidate.valid = false
	_expect(candidate.has_valid_source() and not candidate.is_valid_candidate(),
		"explicit validity must be independent of live source")
	candidate.valid = true
	cover.free()
	_expect(candidate.get_source() == null and candidate.source == null, "freed source must safely resolve to null")
	_expect(not candidate.has_valid_source(), "freed source must not be reported alive")
	_expect(candidate.valid and not candidate.is_valid_candidate(),
		"lost bound source must reject use without mutating explicit validity")
	_expect(candidate.source_instance_id == original_source_id, "lost source identity must be retained")
	_expect(candidate.position == original_position, "source deletion must not alter snapshot position")
	candidate.source = null
	_expect(candidate.source_instance_id == 0 and candidate.is_valid_candidate(),
		"explicit unbinding must allow a source-less candidate")
	var replacement: Node3D = Node3D.new()
	candidate.source = replacement
	_expect(candidate.get_source() == replacement and candidate.source_instance_id == replacement.get_instance_id(),
		"source reassignment must update both weak reference and identity")
	replacement.free()
	_expect(candidate.get_source() == null, "replacement source deletion must also be safe")

func _test_evaluation_defaults() -> void:
	var result: CoverEvaluationResult = CoverEvaluationResult.new()
	_expect(result.candidate == null and not result.valid, "result must start unevaluated")
	_expect(result.recommended_stance == CoverStance.Type.UNKNOWN and result.reason == &"",
		"unevaluated result must not claim a stance or reason")
	_expect(result.exposure_score == 1.0, "unevaluated exposure must default to fully exposed")
	_expect(result.final_score == 0.0 and result.protection_score == 0.0 and result.travel_score == 0.0
		and result.fire_opportunity_score == 0.0 and result.flank_safety_score == 0.0,
		"unevaluated scores must default to zero")
	result.candidate = CoverCandidate.new()
	_expect(not result.valid and result.candidate.is_valid_candidate(),
		"candidate validity must not imply a successful tactical evaluation")

func _test_legacy_cover_flow() -> void:
	var cover: Cover = _make_cover(Vector3.ZERO)
	# Disable physics occupancy only for this fixture to isolate reservation logic.
	cover.slot_blocked_check_enabled = false
	var unit: Unit = BASE_UNIT_SCENE.instantiate() as Unit
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.position = cover.get_cover_slots()[0].global_position
	add_child(unit)
	var threat: Unit = BASE_UNIT_SCENE.instantiate() as Unit
	threat.process_mode = Node.PROCESS_MODE_DISABLED
	threat.position = Vector3(30.0, 0.0, 0.0)
	add_child(threat)
	_expect(unit.get_auto_cover() == cover, "legacy nearest available Cover must remain selected")
	# Threat-based AI selection is tested separately by cover_evaluator_test.
	# This fixture keeps the legacy Cover input/reservation compatibility contract.
	unit.ai_brain._issue_cover(cover)
	_expect(unit.state_machine.is_current_state(TakeCoverState.ID), "AI must still activate TakeCoverState")
	var reserved_slot: Marker3D = cover.get_reserved_slot(unit)
	_expect(reserved_slot != null and reserved_slot == unit.reserved_cover_slot, "state must reserve a Marker")
	_expect(cover.reserve_slot(unit) == reserved_slot, "reservation must remain idempotent")
	_expect(unit.is_in_reserved_cover_slot() and unit.current_cover == cover, "arrival must occupy reserved Cover")
	_expect(not unit.movement_enabled, "occupancy must still stop movement")
	# The current MEDIUM resource has no stat modifiers; the existing effect
	# manager intentionally skips such effects. Preserve that behavior too.
	_expect(unit.has_effect(&"cover_medium_buff") == Unit.COVER_MEDIUM_EFFECT.has_stat_modifiers(),
		"occupancy must retain the existing grade-effect application policy")
	var candidates: Array[CoverCandidate] = cover.get_cover_candidates()
	_expect(candidates.size() == cover.get_cover_slots().size(), "occupied slots must still appear as candidates")
	_expect(cover.get_reserved_slot(unit) == reserved_slot, "candidate query must not change reservation")
	var other_slot: Marker3D = cover.reserve_slot(threat)
	_expect(other_slot != null and other_slot != reserved_slot, "units must not share a reserved Marker")
	threat.clear_cover()
	unit.clear_cover()
	_expect(cover.get_reserved_slot(unit) == null and unit.reserved_cover_slot == null and unit.current_cover == null,
		"clear_cover must release reservation and occupancy")
	_expect(unit.movement_enabled and not unit.has_effect(&"cover_medium_buff"), "clearing Cover must restore movement and remove buff")
	_expect(cover.has_available_slot(unit), "released slots must remain available")
	unit.free()
	threat.free()
	cover.free()

func _make_cover(world_position: Vector3) -> Cover:
	var cover: Cover = COVER_SCENE.instantiate() as Cover
	add_child(cover)
	cover.global_position = world_position
	return cover

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
