extends PanelContainer
class_name UnitStatusPanel

var _selected_unit: Unit = null
var _portrait: TextureRect
var _name_label: Label
var _health_label: Label
var _veterancy_label: Label
var _attack_label: Label
var _defense_label: Label
var _effects_label: Label
var _equipment_label: Label

func _ready() -> void:
	add_to_group("command_panel_ui")
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_set_selected_unit(null)

func unit_selection_changed(selected_units: Dictionary) -> void:
	var first_unit: Unit = null
	for unit in selected_units.values():
		first_unit = unit as Unit
		break

	_set_selected_unit(first_unit)

func _build_ui() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.052, 0.062, 0.072, 0.92)
	panel_style.border_color = Color(0.42, 0.48, 0.52, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(104, 156)
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color(0.08, 0.095, 0.105, 1.0)
	portrait_style.border_color = Color(0.32, 0.38, 0.4, 1.0)
	portrait_style.set_border_width_all(1)
	portrait_style.set_corner_radius_all(3)
	portrait_frame.add_theme_stylebox_override("panel", portrait_style)
	row.add_child(portrait_frame)

	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_frame.add_child(_portrait)

	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_constant_override("separation", 4)
	row.add_child(stats)

	_name_label = _make_label(15, Color(0.9, 0.96, 0.92, 1.0))
	stats.add_child(_name_label)
	_health_label = _make_label()
	stats.add_child(_health_label)
	_veterancy_label = _make_label()
	stats.add_child(_veterancy_label)
	_attack_label = _make_label()
	stats.add_child(_attack_label)
	_defense_label = _make_label()
	stats.add_child(_defense_label)
	_effects_label = _make_label()
	_effects_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_child(_effects_label)
	_equipment_label = _make_label()
	_equipment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_child(_equipment_label)

func _make_label(font_size: int = 13, font_color: Color = Color(0.78, 0.86, 0.82, 1.0)) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = false
	return label

func _set_selected_unit(unit: Unit) -> void:
	if _selected_unit == unit:
		_refresh()
		return

	_disconnect_selected_unit()
	_selected_unit = unit
	_connect_selected_unit()
	_refresh()

func _connect_selected_unit() -> void:
	if _selected_unit == null:
		return

	if not _selected_unit.health_changed.is_connected(_on_selected_unit_health_changed):
		_selected_unit.health_changed.connect(_on_selected_unit_health_changed)
	if not _selected_unit.effects_changed.is_connected(_on_selected_unit_effects_changed):
		_selected_unit.effects_changed.connect(_on_selected_unit_effects_changed)
	if not _selected_unit.veterancy_changed.is_connected(_on_selected_unit_veterancy_changed):
		_selected_unit.veterancy_changed.connect(_on_selected_unit_veterancy_changed)
	if not _selected_unit.agent_level_changed.is_connected(_on_selected_unit_agent_level_changed):
		_selected_unit.agent_level_changed.connect(_on_selected_unit_agent_level_changed)
	if not _selected_unit.tree_exiting.is_connected(_on_selected_unit_tree_exiting):
		_selected_unit.tree_exiting.connect(_on_selected_unit_tree_exiting)

func _disconnect_selected_unit() -> void:
	if _selected_unit == null:
		return

	if _selected_unit.health_changed.is_connected(_on_selected_unit_health_changed):
		_selected_unit.health_changed.disconnect(_on_selected_unit_health_changed)
	if _selected_unit.effects_changed.is_connected(_on_selected_unit_effects_changed):
		_selected_unit.effects_changed.disconnect(_on_selected_unit_effects_changed)
	if _selected_unit.veterancy_changed.is_connected(_on_selected_unit_veterancy_changed):
		_selected_unit.veterancy_changed.disconnect(_on_selected_unit_veterancy_changed)
	if _selected_unit.agent_level_changed.is_connected(_on_selected_unit_agent_level_changed):
		_selected_unit.agent_level_changed.disconnect(_on_selected_unit_agent_level_changed)
	if _selected_unit.tree_exiting.is_connected(_on_selected_unit_tree_exiting):
		_selected_unit.tree_exiting.disconnect(_on_selected_unit_tree_exiting)

func _refresh() -> void:
	visible = _selected_unit != null
	if _selected_unit == null:
		return

	_name_label.text = "%s / %s" % [_selected_unit.name, _selected_unit.get_unit_class_name()]
	_portrait.texture = _selected_unit.get_portrait_texture()
	_health_label.text = "체력: %d / %d" % [_selected_unit.get_current_health(), _selected_unit.get_max_health()]
	if _selected_unit.is_agent_unit():
		_veterancy_label.text = "요원 레벨: %d (%d / %d)" % [
			_selected_unit.agent_level,
			_selected_unit.agent_experience,
			_selected_unit.get_next_agent_level_experience(),
		]
	else:
		_veterancy_label.text = "베테런시: %s (%d / %d)" % [
			_selected_unit.get_veterancy_name(),
			_selected_unit.experience,
			_selected_unit.get_next_veterancy_experience(),
		]
	_attack_label.text = "공격력: %d / 명중률: %d%%" % [
		_get_attack_damage(_selected_unit),
		roundi(_selected_unit.get_accuracy(_selected_unit.equipped_weapon == null) * 100.0),
	]
	_defense_label.text = "방어력: %d / 회피율: %d%% / 반동제어: %.1f" % [
		_selected_unit.get_defense(),
		roundi(_selected_unit.get_evasion_chance() * 100.0),
		_selected_unit.recoil_control,
	]
	_effects_label.text = "효과: %s" % _get_effect_summary(_selected_unit)
	_equipment_label.text = "장비: %s" % _get_equipment_summary(_selected_unit)

func _get_attack_damage(unit: Unit) -> int:
	if unit.equipped_weapon != null:
		return unit.get_ranged_damage()

	return unit.get_melee_damage()

func _get_effect_summary(unit: Unit) -> String:
	var buffs: Array[String] = []
	var debuffs: Array[String] = []

	for active_effect in unit.get_active_effects():
		var effect: UnitEffect = active_effect.effect
		if effect == null:
			continue

		if effect.effect_type == UnitEffect.EffectType.BUFF:
			buffs.append(_format_effect_name(effect))
		elif effect.effect_type == UnitEffect.EffectType.DEBUFF:
			debuffs.append(_format_effect_name(effect))

	var parts: Array[String] = []
	parts.append("버프 " + _join_or_none(buffs))
	parts.append("디버프 " + _join_or_none(debuffs))
	return " / ".join(parts)

func _get_equipment_summary(unit: Unit) -> String:
	var names: Array[String] = []
	if unit.equipped_weapon != null:
		names.append(_format_equipment_name(unit.equipped_weapon))

	for item in unit.equipment:
		if item == null:
			continue
		if item == unit.equipped_weapon:
			continue

		names.append(_format_equipment_name(item))

	return _join_or_none(names)

func _format_equipment_name(item: Equipment) -> String:
	var modifiers: Array[String] = []
	if not is_zero_approx(item.accuracy_bonus):
		modifiers.append("명중%+d%%" % roundi(item.accuracy_bonus * 100.0))
	if not is_zero_approx(item.evasion_bonus):
		modifiers.append("회피%+d%%" % roundi(item.evasion_bonus * 100.0))

	if modifiers.is_empty():
		return item.display_name

	return "%s(%s)" % [item.display_name, ", ".join(modifiers)]

func _format_effect_name(effect: UnitEffect) -> String:
	if effect.projectile_evasion_chance > 0.0:
		return "%s(%d%%)" % [effect.display_name, roundi(effect.projectile_evasion_chance * 100.0)]

	return effect.display_name

func _join_or_none(values: Array[String]) -> String:
	if values.is_empty():
		return "없음"

	return ", ".join(values)

func _on_selected_unit_health_changed(_current_health: int, _max_health: int) -> void:
	_refresh()

func _on_selected_unit_effects_changed() -> void:
	_refresh()

func _on_selected_unit_veterancy_changed(_veterancy: int, _experience: int, _next_required_experience: int) -> void:
	_refresh()

func _on_selected_unit_agent_level_changed(_agent_level: int, _agent_experience: int, _next_required_experience: int) -> void:
	_refresh()

func _on_selected_unit_tree_exiting() -> void:
	_selected_unit = null
	_refresh()
