extends RefCounted
class_name UnitEffectManager

const ActiveUnitEffectScript := preload("res://scripts/effects/active_unit_effect.gd")

var _active_effects: Array = []
var _next_effect_instance_id: int = 1
var _needs_processing: bool = false

func apply(effect: UnitEffect, health_delta_callback: Callable = Callable()) -> int:
	if effect == null:
		return 0

	var runtime_effect := effect.duplicate(true) as UnitEffect
	if runtime_effect == null:
		push_warning("UnitEffectManager.apply expected a UnitEffect resource.")
		return 0

	if runtime_effect.instant_health_delta != 0:
		_call_health_delta(health_delta_callback, runtime_effect.instant_health_delta)

	if not runtime_effect.has_stat_modifiers():
		return 0

	var instance = ActiveUnitEffectScript.new(_next_effect_instance_id, runtime_effect)
	_next_effect_instance_id += 1
	_active_effects.append(instance)
	_refresh_processing_state()
	return instance.instance_id

func remove_instance(instance_id: int) -> bool:
	for index in range(_active_effects.size() - 1, -1, -1):
		if _active_effects[index].instance_id == instance_id:
			_active_effects.remove_at(index)
			_refresh_processing_state()
			return true

	return false

func remove_id(effect_id: StringName) -> bool:
	var removed := false
	for index in range(_active_effects.size() - 1, -1, -1):
		if _active_effects[index].effect.id == effect_id:
			_active_effects.remove_at(index)
			removed = true

	if removed:
		_refresh_processing_state()
	return removed

func has(effect_id: StringName) -> bool:
	for active_effect in _active_effects:
		if active_effect.effect.id == effect_id:
			return true

	return false

func get_active_effects() -> Array:
	return _active_effects.duplicate()

func process(delta: float, health_delta_callback: Callable = Callable()) -> bool:
	if not _needs_processing:
		return false

	var removed := false
	for index in range(_active_effects.size() - 1, -1, -1):
		var active_effect = _active_effects[index]
		_process_health_delta(active_effect, delta, health_delta_callback)

		if active_effect.remaining_duration > 0.0:
			active_effect.remaining_duration -= delta
			if active_effect.remaining_duration <= 0.0:
				_active_effects.remove_at(index)
				removed = true

	if removed:
		_refresh_processing_state()
	return removed

func get_projectile_evasion_chance() -> float:
	var effect_evasion_chance := 0.0
	for active_effect in _active_effects:
		effect_evasion_chance = maxf(effect_evasion_chance, active_effect.effect.projectile_evasion_chance)

	return effect_evasion_chance

func get_cover_projectile_evasion_chance(cover_effect_ids: Array) -> float:
	var effect_evasion_chance := 0.0
	for active_effect in _active_effects:
		if _is_cover_effect(active_effect.effect, cover_effect_ids):
			effect_evasion_chance = maxf(effect_evasion_chance, active_effect.effect.projectile_evasion_chance)

	return effect_evasion_chance

func get_non_cover_projectile_evasion_chance(cover_effect_ids: Array) -> float:
	var effect_evasion_chance := 0.0
	for active_effect in _active_effects:
		if not _is_cover_effect(active_effect.effect, cover_effect_ids):
			effect_evasion_chance = maxf(effect_evasion_chance, active_effect.effect.projectile_evasion_chance)

	return effect_evasion_chance

func get_max_health_bonus() -> int:
	var bonus := 0
	for active_effect in _active_effects:
		bonus += active_effect.effect.max_health_bonus
	return bonus

func get_attack_damage_bonus() -> int:
	var bonus := 0
	for active_effect in _active_effects:
		bonus += active_effect.effect.attack_damage_bonus
	return bonus

func get_melee_damage_bonus() -> int:
	var bonus := 0
	for active_effect in _active_effects:
		bonus += active_effect.effect.melee_damage_bonus
	return bonus

func get_ranged_damage_bonus() -> int:
	var bonus := 0
	for active_effect in _active_effects:
		bonus += active_effect.effect.ranged_damage_bonus
	return bonus

func get_melee_range_bonus() -> float:
	var bonus := 0.0
	for active_effect in _active_effects:
		bonus += active_effect.effect.melee_range_bonus
	return bonus

func get_ranged_range_bonus() -> float:
	var bonus := 0.0
	for active_effect in _active_effects:
		bonus += active_effect.effect.ranged_range_bonus
	return bonus

func get_attack_range_bonus() -> float:
	var bonus := 0.0
	for active_effect in _active_effects:
		bonus += active_effect.effect.attack_range_bonus
	return bonus

func get_attack_speed_multiplier() -> float:
	var multiplier := 1.0
	for active_effect in _active_effects:
		multiplier *= active_effect.effect.attack_speed_multiplier
	return maxf(multiplier, 0.01)

func get_move_speed_bonus() -> float:
	var bonus := 0.0
	for active_effect in _active_effects:
		bonus += active_effect.effect.move_speed_bonus
	return bonus

func get_vision_range_bonus() -> float:
	var bonus := 0.0
	for active_effect in _active_effects:
		bonus += active_effect.effect.vision_range_bonus
	return bonus

func _refresh_processing_state() -> void:
	_needs_processing = false
	for active_effect in _active_effects:
		if active_effect.remaining_duration > 0.0 or not is_zero_approx(active_effect.effect.health_delta_per_second):
			_needs_processing = true
			return

func _process_health_delta(active_effect, delta: float, health_delta_callback: Callable) -> void:
	if is_zero_approx(active_effect.effect.health_delta_per_second):
		return

	active_effect.health_delta_remainder += active_effect.effect.health_delta_per_second * delta
	var whole_delta := 0
	if active_effect.health_delta_remainder >= 1.0:
		whole_delta = int(floor(active_effect.health_delta_remainder))
	elif active_effect.health_delta_remainder <= -1.0:
		whole_delta = int(ceil(active_effect.health_delta_remainder))

	if whole_delta == 0:
		return

	active_effect.health_delta_remainder -= float(whole_delta)
	_call_health_delta(health_delta_callback, whole_delta)

func _call_health_delta(health_delta_callback: Callable, amount: int) -> void:
	if health_delta_callback.is_valid():
		health_delta_callback.call(amount)

func _is_cover_effect(effect: UnitEffect, cover_effect_ids: Array) -> bool:
	return effect != null and cover_effect_ids.has(effect.id)
