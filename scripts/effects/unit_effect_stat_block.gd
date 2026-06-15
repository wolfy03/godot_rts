extends RefCounted
class_name UnitEffectStatBlock

var max_health_bonus: int = 0
var attack_damage_bonus: int = 0
var melee_damage_bonus: int = 0
var ranged_damage_bonus: int = 0
var melee_range_bonus: float = 0.0
var ranged_range_bonus: float = 0.0
var attack_range_bonus: float = 0.0
var attack_speed_multiplier: float = 1.0
var move_speed_bonus: float = 0.0
var vision_range_bonus: float = 0.0
var projectile_evasion_chance: float = 0.0

func reset() -> void:
	max_health_bonus = 0
	attack_damage_bonus = 0
	melee_damage_bonus = 0
	ranged_damage_bonus = 0
	melee_range_bonus = 0.0
	ranged_range_bonus = 0.0
	attack_range_bonus = 0.0
	attack_speed_multiplier = 1.0
	move_speed_bonus = 0.0
	vision_range_bonus = 0.0
	projectile_evasion_chance = 0.0

func rebuild(active_effects: Array) -> void:
	reset()
	for active_effect in active_effects:
		if active_effect == null:
			continue
		add_effect(active_effect.effect)
	attack_speed_multiplier = maxf(attack_speed_multiplier, 0.01)

func add_effect(effect: UnitEffect) -> void:
	if effect == null:
		return

	max_health_bonus += effect.max_health_bonus
	attack_damage_bonus += effect.attack_damage_bonus
	melee_damage_bonus += effect.melee_damage_bonus
	ranged_damage_bonus += effect.ranged_damage_bonus
	melee_range_bonus += effect.melee_range_bonus
	ranged_range_bonus += effect.ranged_range_bonus
	attack_range_bonus += effect.attack_range_bonus
	attack_speed_multiplier *= effect.attack_speed_multiplier
	move_speed_bonus += effect.move_speed_bonus
	vision_range_bonus += effect.vision_range_bonus
	projectile_evasion_chance = maxf(projectile_evasion_chance, effect.projectile_evasion_chance)
