extends Resource
class_name Equipment

enum Slot {
	WEAPON,
	ARMOR,
	UTILITY,
}

@export var display_name: String = "Equipment"
@export var slot: Slot = Slot.UTILITY
@export var max_health_bonus: int = 0
@export var move_speed_bonus: float = 0.0
@export var melee_range_bonus: float = 0.0
@export var ranged_range_bonus: float = 0.0
@export var attack_damage_bonus: int = 0
@export var attack_range_bonus: float = 0.0
@export var attack_speed_multiplier: float = 1.0

func apply_to(unit: Unit) -> void:
	unit.max_health += max_health_bonus
	unit.navigation_agent.max_speed += move_speed_bonus
	unit.melee_range += melee_range_bonus
	unit.equipment_attack_damage_bonus += attack_damage_bonus
	unit.equipment_attack_range_bonus += ranged_range_bonus + attack_range_bonus
	unit.equipment_attack_speed_multiplier *= attack_speed_multiplier
