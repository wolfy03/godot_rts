extends Node

const QuickSlotPanelScript := preload("res://scripts/ui/hud/player_quick_slot_panel.gd")
const PlayerStatusPanelScript := preload("res://scripts/ui/hud/player_status_panel.gd")
const InputControllerScript := preload("res://scripts/input/input.gd")

class FakeEffect:
	var effect_type: int = 0
	var display_name: String = "Effect"

class FakeActiveEffect:
	var effect

class FakeAgent:
	signal health_changed(current_health: int, max_health: int)
	signal effects_changed
	signal agent_level_changed(agent_level: int, agent_experience: int, next_required_experience: int)
	signal tree_exiting

	var agent_level: int = 3
	var agent_experience: int = 240
	var current_health_call_count: int = 0
	var active_effects_call_count: int = 0

	func get_current_health() -> int:
		current_health_call_count += 1
		return 72

	func get_max_health() -> int:
		return 100

	func get_next_agent_level_experience() -> int:
		return 300

	func get_active_effects() -> Array:
		active_effects_call_count += 1
		var buff := FakeEffect.new()
		buff.effect_type = 0
		buff.display_name = "Power"
		var debuff := FakeEffect.new()
		debuff.effect_type = 1
		debuff.display_name = "Poison"

		var active_buff := FakeActiveEffect.new()
		active_buff.effect = buff
		var active_debuff := FakeActiveEffect.new()
		active_debuff.effect = debuff
		return [active_buff, active_debuff]

var _failed := false

func _ready() -> void:
	_test_quick_slot_panel_builds_number_slots()
	_test_player_status_panel_toggles_and_formats_agent_state()
	_test_player_status_panel_uses_body_texture_for_health()
	_test_player_status_panel_fits_hud_status_window()
	_test_input_controller_accepts_tab_keycode_for_player_status()

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("player_hud_panel_test: PASS")
		get_tree().quit(0)

func _test_quick_slot_panel_builds_number_slots() -> void:
	var panel := PanelContainer.new()
	panel.set_script(QuickSlotPanelScript)
	add_child(panel)

	_expect(panel.get_slot_count() == 10, "quick slot panel should expose 10 number slots")
	_expect(panel.get_slot_key_label(0) == "1", "first quick slot should be bound to 1")
	_expect(panel.get_slot_key_label(8) == "9", "ninth quick slot should be bound to 9")
	_expect(panel.get_slot_key_label(9) == "0", "last quick slot should be bound to 0")
	panel.queue_free()

func _test_player_status_panel_toggles_and_formats_agent_state() -> void:
	var panel := PanelContainer.new()
	panel.set_script(PlayerStatusPanelScript)
	add_child(panel)

	var agent := FakeAgent.new()
	panel.set_player_agent(agent)
	_expect(not panel.visible, "player status panel should start hidden")
	panel.toggle()
	_expect(panel.visible, "player status panel should open on toggle")
	_expect(panel.get_health_text() == "체력: 72 / 100", "player status panel should show health")
	_expect(panel.get_level_text() == "레벨: 3 (240 / 300)", "player status panel should show agent level and experience")
	_expect(panel.get_effects_text().contains("Power"), "player status panel should show buffs")
	_expect(panel.get_effects_text().contains("Poison"), "player status panel should show debuffs")
	var effect_calls_after_open := agent.active_effects_call_count
	agent.health_changed.emit(72, 100)
	_expect(
		agent.active_effects_call_count == effect_calls_after_open,
		"health updates should not rebuild the player status effect summary"
	)
	panel.toggle()
	_expect(not panel.visible, "player status panel should close on second toggle")
	var health_calls_after_close := agent.current_health_call_count
	agent.health_changed.emit(72, 100)
	_expect(
		agent.current_health_call_count == health_calls_after_close,
		"closed player status panel should not refresh on agent signals"
	)
	panel.queue_free()

func _test_player_status_panel_uses_body_texture_for_health() -> void:
	var panel := PanelContainer.new()
	panel.set_script(PlayerStatusPanelScript)
	add_child(panel)

	var agent := FakeAgent.new()
	panel.set_player_agent(agent)
	panel.toggle()
	_expect(panel.get_body_health_texture() != null, "player status panel should use the human body template texture")
	_expect(is_equal_approx(panel.get_body_health_percent(), 0.72), "player status panel should expose current health as body fill percent")
	panel.queue_free()

func _test_player_status_panel_fits_hud_status_window() -> void:
	var panel := PanelContainer.new()
	panel.set_script(PlayerStatusPanelScript)
	add_child(panel)

	var agent := FakeAgent.new()
	panel.set_player_agent(agent)
	panel.toggle()
	var body_size: Vector2 = panel.get_body_health_view_size()
	var panel_minimum := panel.get_combined_minimum_size()
	_expect(body_size.x <= 120.0 and body_size.y <= 220.0, "body health view should stay small enough for the status window")
	_expect(
		panel_minimum.x <= 460.0 and panel_minimum.y <= 300.0,
		"player status panel minimum size should fit the HUD status window: %s" % panel_minimum
	)
	panel.queue_free()

func _test_input_controller_accepts_tab_keycode_for_player_status() -> void:
	var controller := Node.new()
	controller.set_script(InputControllerScript)

	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_TAB
	event.physical_keycode = 0
	_expect(controller._is_player_status_toggle_event(event), "player status toggle should accept KEY_TAB keycode events")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
