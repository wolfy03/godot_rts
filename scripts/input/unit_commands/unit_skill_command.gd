extends RefCounted
class_name UnitSkillCommand

func issue(selected_units: Dictionary, skill_id: StringName, target_unit: Unit, click_position: Variant) -> void:
	for selected_unit in selected_units.values():
		var unit := selected_unit as Unit
		if unit == null or not is_instance_valid(unit) or not unit.has_skill(skill_id):
			continue

		var skill := unit.get_skill(skill_id)
		if skill == null:
			continue

		match skill.target_type:
			UnitSkill.TargetType.NONE, UnitSkill.TargetType.SELF:
				_use_immediate_skill(unit, skill_id)
			UnitSkill.TargetType.POSITION:
				_issue_position_skill(unit, skill_id, target_unit, click_position)
			UnitSkill.TargetType.ALLY_UNIT, UnitSkill.TargetType.ENEMY_UNIT, UnitSkill.TargetType.ANY_UNIT:
				_issue_unit_target_skill(unit, skill_id, target_unit)

func _use_immediate_skill(unit: Unit, skill_id: StringName) -> void:
	unit.begin_player_command(Unit.PlayerCommandMode.SKILL)
	unit.use_skill(skill_id, unit, unit.global_position)
	unit.finish_player_command(Unit.PlayerCommandMode.SKILL)

func _issue_position_skill(unit: Unit, skill_id: StringName, target_unit: Unit, click_position: Variant) -> void:
	if click_position == null:
		return

	var target_position: Vector3 = click_position
	unit.begin_player_command(Unit.PlayerCommandMode.SKILL)
	if not unit.issue_skill_command(skill_id, target_unit, target_position):
		unit.finish_player_command(Unit.PlayerCommandMode.SKILL)

func _issue_unit_target_skill(unit: Unit, skill_id: StringName, target_unit: Unit) -> void:
	if target_unit == null:
		return

	unit.begin_player_command(Unit.PlayerCommandMode.SKILL)
	if not unit.issue_skill_command(skill_id, target_unit, target_unit.global_position):
		unit.finish_player_command(Unit.PlayerCommandMode.SKILL)
