extends RefCounted
class_name GameTeam

const AUTO := -1
const NEUTRAL := 0
const PLAYER := 1
const ENEMY := 2

const PLAYER_COLLISION_MASK := 0b10
const ENEMY_COLLISION_MASK := 0b100

static func get_group_name(team_id: int) -> String:
	return "team_%d" % team_id

static func get_collision_mask(team_id: int) -> int:
	match team_id:
		PLAYER:
			return PLAYER_COLLISION_MASK
		ENEMY:
			return ENEMY_COLLISION_MASK
		_:
			return 0

static func get_display_name(team_id: int) -> String:
	match team_id:
		PLAYER:
			return "Player"
		ENEMY:
			return "Enemy"
		NEUTRAL:
			return "Neutral"
		_:
			return "Auto"
