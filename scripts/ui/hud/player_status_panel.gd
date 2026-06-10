extends PanelContainer
class_name PlayerStatusPanel

const BODY_TEXTURE: Texture2D = preload("res://assets/sprites/Human_body_template.png")
const BODY_TEXTURE_REGION := Rect2(1180.0, 30.0, 1240.0, 2110.0)
const BODY_VIEW_SIZE := Vector2(208.0, 428.0)

class BodyHealthView:
	extends Control

	var body_texture: Texture2D
	var body_region: Rect2
	var health_percent: float = 0.0
	var health_color: Color = Color(0.22, 0.95, 0.48, 0.96)

	func _init(texture: Texture2D, region: Rect2, view_size: Vector2) -> void:
		body_texture = texture
		body_region = region
		custom_minimum_size = view_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_health_percent(percent: float, fill_color: Color) -> void:
		var next_percent := clampf(percent, 0.0, 1.0)
		if is_equal_approx(health_percent, next_percent) and health_color.is_equal_approx(fill_color):
			return
		health_percent = next_percent
		health_color = fill_color
		queue_redraw()

	func _draw() -> void:
		if body_texture == null:
			return
		var target_rect := Rect2(Vector2.ZERO, size)
		draw_texture_rect_region(body_texture, target_rect, body_region, Color(0.32, 0.07, 0.06, 0.84))
		if health_percent <= 0.0:
			return
		var fill_height := size.y * health_percent
		var source_height := body_region.size.y * health_percent
		var fill_target := Rect2(Vector2(0.0, size.y - fill_height), Vector2(size.x, fill_height))
		var fill_source := Rect2(
			Vector2(body_region.position.x, body_region.position.y + body_region.size.y - source_height),
			Vector2(body_region.size.x, source_height)
		)
		draw_texture_rect_region(body_texture, fill_target, fill_source, health_color)

var _player_agent: Object
var _health_label: Label
var _level_label: Label
var _effects_label: Label
var _body_health_view: BodyHealthView
var _body_health_percent: float = 0.0
var _agent_signals_connected: bool = false

func _ready() -> void:
	add_to_group("command_panel_ui")
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()
	_refresh()

func set_player_agent(agent: Object) -> void:
	if _player_agent == agent:
		if visible:
			_refresh()
		return

	_disconnect_agent()
	_player_agent = agent
	if visible:
		_connect_agent()
		_refresh()

func toggle() -> bool:
	set_open(not visible)
	return visible

func set_open(is_open: bool) -> void:
	if visible == is_open:
		return
	visible = is_open
	if visible:
		_connect_agent()
		_refresh()
	else:
		_disconnect_agent()

func get_health_text() -> String:
	return _health_label.text if _health_label != null else ""

func get_level_text() -> String:
	return _level_label.text if _level_label != null else ""

func get_effects_text() -> String:
	return _effects_label.text if _effects_label != null else ""

func get_body_health_texture() -> Texture2D:
	return _body_health_view.body_texture if _body_health_view != null else null

func get_body_health_percent() -> float:
	return _body_health_percent

func get_body_health_view_size() -> Vector2:
	return BODY_VIEW_SIZE

func _build_ui() -> void:
	add_theme_stylebox_override("panel", _make_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := _make_label("플레이어 상태", 17, Color(0.92, 0.98, 0.94, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(content)

	content.add_child(_make_body_health_view())

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(stats)

	_health_label = _make_label()
	stats.add_child(_health_label)
	_level_label = _make_label()
	stats.add_child(_level_label)
	_effects_label = _make_label()
	_effects_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_effects_label.clip_text = true
	_effects_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stats.add_child(_effects_label)

func _make_body_health_view() -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(128, 234)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", _make_body_frame_style())

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(center)

	_body_health_view = BodyHealthView.new(BODY_TEXTURE, BODY_TEXTURE_REGION, BODY_VIEW_SIZE)
	center.add_child(_body_health_view)
	return frame

func _connect_agent() -> void:
	if _player_agent == null or _agent_signals_connected:
		return
	_connect_agent_signal("health_changed", _on_agent_health_changed)
	_connect_agent_signal("effects_changed", _on_agent_effects_changed)
	_connect_agent_signal("agent_level_changed", _on_agent_level_changed)
	_connect_agent_signal("tree_exiting", _on_agent_tree_exiting)
	_agent_signals_connected = true

func _disconnect_agent() -> void:
	if _player_agent == null or not _agent_signals_connected:
		return
	_disconnect_agent_signal("health_changed", _on_agent_health_changed)
	_disconnect_agent_signal("effects_changed", _on_agent_effects_changed)
	_disconnect_agent_signal("agent_level_changed", _on_agent_level_changed)
	_disconnect_agent_signal("tree_exiting", _on_agent_tree_exiting)
	_agent_signals_connected = false

func _connect_agent_signal(signal_name: StringName, target: Callable) -> void:
	if _player_agent.has_signal(signal_name) and not _player_agent.is_connected(signal_name, target):
		_player_agent.connect(signal_name, target)

func _disconnect_agent_signal(signal_name: StringName, target: Callable) -> void:
	if _player_agent.has_signal(signal_name) and _player_agent.is_connected(signal_name, target):
		_player_agent.disconnect(signal_name, target)

func _refresh() -> void:
	if _health_label == null or _level_label == null or _effects_label == null:
		return
	if _player_agent == null or not is_instance_valid(_player_agent):
		_health_label.text = "체력: - / -"
		_level_label.text = "레벨: - (- / -)"
		_effects_label.text = "효과: 버프 없음 / 디버프 없음"
		_set_body_health_percent(0.0)
		return

	var current_health := _call_int(_player_agent, "get_current_health")
	var max_health := _call_int(_player_agent, "get_max_health")
	_health_label.text = "체력: %d / %d" % [current_health, max_health]
	_level_label.text = "레벨: %d (%d / %d)" % [
		int(_player_agent.get("agent_level")),
		int(_player_agent.get("agent_experience")),
		_call_int(_player_agent, "get_next_agent_level_experience"),
	]
	_effects_label.text = "효과: %s" % _get_effect_summary()
	_set_body_health_percent(float(current_health) / float(max_health) if max_health > 0 else 0.0)

func _refresh_health() -> void:
	if _player_agent == null or not is_instance_valid(_player_agent):
		_refresh()
		return

	var current_health := _call_int(_player_agent, "get_current_health")
	var max_health := _call_int(_player_agent, "get_max_health")
	_health_label.text = _make_prefixed_text(_health_label.text, "%d / %d" % [current_health, max_health])
	_set_body_health_percent(float(current_health) / float(max_health) if max_health > 0 else 0.0)

func _refresh_level() -> void:
	if _player_agent == null or not is_instance_valid(_player_agent):
		_refresh()
		return

	var level_text := "%d (%d / %d)" % [
		int(_player_agent.get("agent_level")),
		int(_player_agent.get("agent_experience")),
		_call_int(_player_agent, "get_next_agent_level_experience"),
	]
	_level_label.text = _make_prefixed_text(_level_label.text, level_text)

func _refresh_effects() -> void:
	if _player_agent == null or not is_instance_valid(_player_agent):
		_refresh()
		return

	_effects_label.text = _make_prefixed_text(_effects_label.text, _get_effect_summary())

func _make_prefixed_text(current_text: String, value_text: String) -> String:
	var separator_index := current_text.find(":")
	if separator_index < 0:
		return value_text
	return "%s %s" % [current_text.substr(0, separator_index + 1), value_text]

func _set_body_health_percent(percent: float) -> void:
	_body_health_percent = clampf(percent, 0.0, 1.0)
	if _body_health_view != null:
		_body_health_view.set_health_percent(_body_health_percent, _get_body_health_color(_body_health_percent))

func _get_body_health_color(percent: float) -> Color:
	if percent <= 0.25:
		return Color(1.0, 0.18, 0.12, 0.96)
	if percent <= 0.55:
		return Color(1.0, 0.73, 0.18, 0.96)
	return Color(0.22, 0.95, 0.48, 0.96)

func _get_effect_summary() -> String:
	var buffs: Array[String] = []
	var debuffs: Array[String] = []
	if _player_agent == null or not _player_agent.has_method("get_active_effects"):
		return "버프 없음 / 디버프 없음"

	for active_effect in _player_agent.call("get_active_effects"):
		var effect = active_effect.get("effect") if active_effect != null else null
		if effect == null:
			continue
		var effect_name := String(effect.get("display_name"))
		var effect_type := int(effect.get("effect_type"))
		if effect_type == 0:
			buffs.append(effect_name)
		elif effect_type == 1:
			debuffs.append(effect_name)

	return "버프 %s / 디버프 %s" % [_join_or_none(buffs), _join_or_none(debuffs)]

func _call_int(source: Object, method_name: StringName) -> int:
	if source != null and source.has_method(method_name):
		return int(source.call(method_name))
	return 0

func _join_or_none(values: Array[String]) -> String:
	if values.is_empty():
		return "없음"
	return ", ".join(values)

func _make_label(text_value: String = "", font_size: int = 14, font_color: Color = Color(0.8, 0.88, 0.84, 1.0)) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.052, 0.057, 0.96)
	style.border_color = Color(0.42, 0.48, 0.52, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style

func _make_body_frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.03, 0.034, 0.7)
	style.border_color = Color(0.26, 0.32, 0.34, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style

func _on_agent_health_changed(_current_health: int, _max_health: int) -> void:
	if visible:
		_refresh_health()

func _on_agent_effects_changed() -> void:
	if visible:
		_refresh_effects()

func _on_agent_level_changed(_agent_level: int, _agent_experience: int, _next_required_experience: int) -> void:
	if visible:
		_refresh_level()

func _on_agent_tree_exiting() -> void:
	_agent_signals_connected = false
	_player_agent = null
	if visible:
		_refresh()
