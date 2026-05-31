extends RefCounted
class_name AttackData

enum AttackKind {
	MELEE,
	RANGED,
}

var damage: int
var accuracy: float
var kind: AttackKind
var has_resolved_aim: bool = false
var aim_hits_target: bool = true
var _source_ref: WeakRef

func _init(
	attack_source: Unit = null,
	attack_damage: int = 0,
	attack_accuracy: float = 1.0,
	attack_kind: AttackKind = AttackKind.RANGED,
	attack_has_resolved_aim: bool = false,
	attack_aim_hits_target: bool = true
) -> void:
	if attack_source != null:
		_source_ref = weakref(attack_source)
	damage = attack_damage
	accuracy = attack_accuracy
	kind = attack_kind
	has_resolved_aim = attack_has_resolved_aim
	aim_hits_target = attack_aim_hits_target

func get_valid_source() -> Unit:
	if _source_ref == null:
		return null
	
	var source := _source_ref.get_ref() as Unit
	if source != null and is_instance_valid(source):
		return source
	
	return null

func with_resolved_aim(hit: bool) -> AttackData:
	return AttackData.new(get_valid_source(), damage, accuracy, kind, true, hit)
