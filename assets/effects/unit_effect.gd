extends Resource
class_name UnitEffect

enum EffectType {
	BUFF,
	DEBUFF,
	NEUTRAL,
}

@export var id: StringName = &"effect"
@export var display_name: String = "Effect"
@export var effect_type: EffectType = EffectType.NEUTRAL
@export var duration: float = 0.0
@export var icon: Texture2D
@export var indicator_color: Color = Color.WHITE

@export_group("Health")
@export var instant_health_delta: int = 0
@export var health_delta_per_second: float = 0.0
@export var max_health_bonus: int = 0

@export_group("Attack")
@export var attack_damage_bonus: int = 0
@export var melee_damage_bonus: int = 0
@export var ranged_damage_bonus: int = 0
@export var melee_range_bonus: float = 0.0
@export var ranged_range_bonus: float = 0.0
@export var attack_range_bonus: float = 0.0
@export var attack_speed_multiplier: float = 1.0

@export_group("Movement")
@export var move_speed_bonus: float = 0.0

@export_group("Vision")
@export var vision_range_bonus: float = 0.0

@export_group("Defense")
@export_range(0.0, 1.0, 0.01) var projectile_evasion_chance: float = 0.0

func is_timed() -> bool:
	return duration > 0.0

func is_permanent() -> bool:
	return duration <= 0.0

func has_stat_modifiers() -> bool:
	return max_health_bonus != 0 \
		or attack_damage_bonus != 0 \
		or melee_damage_bonus != 0 \
		or ranged_damage_bonus != 0 \
		or !is_zero_approx(melee_range_bonus) \
		or !is_zero_approx(ranged_range_bonus) \
		or !is_zero_approx(attack_range_bonus) \
		or !is_equal_approx(attack_speed_multiplier, 1.0) \
		or !is_zero_approx(move_speed_bonus) \
		or !is_zero_approx(vision_range_bonus) \
		or !is_zero_approx(projectile_evasion_chance) \
		or !is_zero_approx(health_delta_per_second)
