extends Node

const UnitEffectManagerScript := preload("res://scripts/effects/unit_effect_manager.gd")

var _failed := false
var _health_delta_total := 0

func _ready() -> void:
	_test_effect_stats_are_cached_and_removed()
	_test_health_delta_and_expiration()
	_test_cover_evasion_queries()

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("unit_effect_manager_test: PASS")
		get_tree().quit(0)

func _test_effect_stats_are_cached_and_removed() -> void:
	var manager = UnitEffectManagerScript.new()
	var damage_effect := _make_effect(&"damage")
	damage_effect.attack_damage_bonus = 4
	damage_effect.ranged_damage_bonus = 3
	damage_effect.attack_speed_multiplier = 0.5
	damage_effect.projectile_evasion_chance = 0.2

	var speed_effect := _make_effect(&"speed")
	speed_effect.move_speed_bonus = 1.5
	speed_effect.vision_range_bonus = 2.0
	speed_effect.attack_speed_multiplier = 2.0

	var damage_instance_id: int = manager.apply(damage_effect)
	manager.apply(speed_effect)

	_expect(manager.get_attack_damage_bonus() == 4, "attack damage bonus should be aggregated")
	_expect(manager.get_ranged_damage_bonus() == 3, "ranged damage bonus should be aggregated")
	_expect(is_equal_approx(manager.get_move_speed_bonus(), 1.5), "move speed bonus should be aggregated")
	_expect(is_equal_approx(manager.get_vision_range_bonus(), 2.0), "vision range bonus should be aggregated")
	_expect(is_equal_approx(manager.get_attack_speed_multiplier(), 1.0), "attack speed multipliers should be multiplied")
	_expect(is_equal_approx(manager.get_projectile_evasion_chance(), 0.2), "projectile evasion should use highest active effect value")

	manager.remove_instance(damage_instance_id)
	_expect(manager.get_attack_damage_bonus() == 0, "removed effects should update cached attack damage")
	_expect(manager.get_ranged_damage_bonus() == 0, "removed effects should update cached ranged damage")
	_expect(is_equal_approx(manager.get_attack_speed_multiplier(), 2.0), "removed effects should update cached attack speed")

func _test_health_delta_and_expiration() -> void:
	var manager = UnitEffectManagerScript.new()
	_health_delta_total = 0

	var effect := _make_effect(&"burn")
	effect.duration = 0.5
	effect.instant_health_delta = -3
	effect.health_delta_per_second = -4.0

	var instance_id: int = manager.apply(effect, _record_health_delta)
	_expect(instance_id != 0, "timed health delta effects should create an active instance")
	_expect(_health_delta_total == -3, "instant health delta should be emitted on apply")

	manager.process(0.25, _record_health_delta)
	_expect(_health_delta_total == -4, "fractional health delta should accumulate to whole values")
	_expect(manager.has(&"burn"), "effect should remain active before duration expires")

	_expect(manager.process(0.25, _record_health_delta), "process should report when an effect expires")
	_expect(not manager.has(&"burn"), "expired effects should be removed")

func _test_cover_evasion_queries() -> void:
	var manager = UnitEffectManagerScript.new()
	var cover_effect := _make_effect(&"cover")
	cover_effect.projectile_evasion_chance = 0.4
	var buff_effect := _make_effect(&"buff")
	buff_effect.projectile_evasion_chance = 0.25

	manager.apply(cover_effect)
	manager.apply(buff_effect)

	_expect(is_equal_approx(manager.get_cover_projectile_evasion_chance([&"cover"]), 0.4), "cover evasion should include cover effects")
	_expect(is_equal_approx(manager.get_non_cover_projectile_evasion_chance([&"cover"]), 0.25), "non-cover evasion should exclude cover effects")

func _make_effect(effect_id: StringName) -> UnitEffect:
	var effect := UnitEffect.new()
	effect.id = effect_id
	effect.display_name = String(effect_id)
	return effect

func _record_health_delta(amount: int) -> void:
	_health_delta_total += amount

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
