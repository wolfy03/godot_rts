extends RefCounted
class_name ActiveUnitEffect

var instance_id: int
var effect: UnitEffect
var remaining_duration: float
var health_delta_remainder: float = 0.0

func _init(effect_instance_id: int, unit_effect: UnitEffect) -> void:
	instance_id = effect_instance_id
	effect = unit_effect
	remaining_duration = unit_effect.duration
