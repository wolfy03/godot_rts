extends Equipment
class_name WeaponEquipment

@export var ranged_damage: int = 20
@export var ranged_cooldown: float = 0.8
@export var attack_range: float = 10.0
@export var attacks_per_second: float = 0.0
@export var projectile_scene: PackedScene

func _init() -> void:
	slot = Slot.WEAPON

func get_damage(damage_bonus: int = 0) -> int:
	return max(0, ranged_damage + damage_bonus)

func get_attack_range(range_bonus: float = 0.0) -> float:
	return maxf(0.0, attack_range + range_bonus)

func get_attack_cooldown(speed_multiplier: float = 1.0) -> float:
	var effective_speed_multiplier = maxf(speed_multiplier, 0.01)

	if attacks_per_second > 0.0:
		return 1.0 / (attacks_per_second * effective_speed_multiplier)

	return ranged_cooldown / effective_speed_multiplier
