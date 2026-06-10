extends Node

const DebugOverlayScript := preload("res://scripts/ui/hud/debug_overlay.gd")
const TEST_EFFECT_PATH := "res://assets/effects/health_recovery_buff.tres"

class FakePlayer:
	extends Node

	var applied_effect_count: int = 0

	func _ready() -> void:
		add_to_group("player_agent")

	func apply_effect(effect: Resource) -> int:
		if effect != null:
			applied_effect_count += 1
		return applied_effect_count

var _failed := false

func _ready() -> void:
	_test_debug_overlay_applies_effect_to_player_when_no_unit_selected()

	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
	else:
		print("debug_overlay_test: PASS")
		get_tree().quit(0)

func _test_debug_overlay_applies_effect_to_player_when_no_unit_selected() -> void:
	var player := FakePlayer.new()
	add_child(player)
	await get_tree().process_frame

	var overlay := Control.new()
	overlay.set_script(DebugOverlayScript)
	add_child(overlay)
	await get_tree().process_frame

	overlay.unit_selection_changed({})
	overlay._apply_effect_to_selected(TEST_EFFECT_PATH, "Buff Damage")
	_expect(player.applied_effect_count == 1, "debug overlay should apply effects to the player when no units are selected")
	overlay.queue_free()
	player.queue_free()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
