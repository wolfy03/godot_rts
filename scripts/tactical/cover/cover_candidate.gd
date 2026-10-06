class_name CoverCandidate
extends RefCounted

## A world-position snapshot, independent of scene nodes and tactical evaluation.
var position: Vector3 = Vector3.ZERO

var _source_ref: WeakRef = null

## Access through a weak reference so a freed source is always returned as null.
## Assigning null explicitly creates a source-less candidate (e.g. terrain).
var source: Node3D:
	get:
		return get_source()
	set(value):
		_source_ref = weakref(value) if is_instance_valid(value) else null
		source_instance_id = value.get_instance_id() if is_instance_valid(value) else 0

## Runtime identity retained after source deletion; not a persistent save-game ID.
var source_instance_id: int = 0
## Reserved for future geometry revisions; no revision tracking in this adapter.
var source_revision: int = 0

var stance: CoverStance.Type = CoverStance.Type.UNKNOWN

## Explicit data validity, separate from whether a bound source is still alive.
## Slot deletion/movement does not update this snapshot or invalidate it yet.
var valid: bool = true

## Opaque runtime reservation identity. Producers may later use candidate IDs or
## quantized positions; consumers must not interpret this as a Marker node path.
var reservation_key: StringName = &""

func get_source() -> Node3D:
	if _source_ref == null:
		return null
	var source_node: Node3D = _source_ref.get_ref() as Node3D
	if not is_instance_valid(source_node):
		return null
	return source_node

func has_valid_source() -> bool:
	return get_source() != null

## Unbound candidates are allowed. A previously bound, freed source makes a
## candidate unusable without mutating its explicit valid flag or source ID.
## This does not certify navigation, protection, availability, or slot existence.
func is_valid_candidate() -> bool:
	return valid and (source_instance_id == 0 or has_valid_source())
