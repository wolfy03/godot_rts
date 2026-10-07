class_name CoverEvaluationResult
extends RefCounted

## Result for one candidate in a specific Unit / Threat context. No evaluation
## is performed here; CoverEvaluator owns scoring and context freshness.
var candidate: CoverCandidate = null
var valid: bool = false

## All scores contractually use [0.0, 1.0]; the evaluator must normalize them.
## Final desirability: 0 = worst, 1 = best. Compare only valid results.
var final_score: float = 0.0
## Protection: 0 = no protection, 1 = full protection.
var protection_score: float = 0.0
## Exposure: 0 = no exposure, 1 = fully exposed (lower is better).
var exposure_score: float = 1.0
## Travel: 0 = very poor movement option, 1 = very good movement option.
var travel_score: float = 0.0
## Fire opportunity: 0 = none, 1 = ideal opportunity to fire.
var fire_opportunity_score: float = 0.0
## Flank safety: 0 = unsafe, 1 = fully safe from flanking.
var flank_safety_score: float = 0.0

var recommended_stance: CoverStance.Type = CoverStance.Type.UNKNOWN
var reason: StringName = &""

var protected_from_threat: bool = false
var can_fire_at_threat: bool = false
var travel_distance: float = INF
var threat_distance: float = INF
var current_exposure_score: float = 1.0
var protection_improvement: float = 0.0
var improves_current_position: bool = false

## Tactical names alias the existing data contract; there is no second score.
var score: float:
	get:
		return final_score
	set(value):
		final_score = value
var exposure_ratio: float:
	get:
		return exposure_score
	set(value):
		exposure_score = value
var firing_score: float:
	get:
		return fire_opportunity_score
	set(value):
		fire_opportunity_score = value
var rejection_reason: String:
	get:
		return String(reason)
	set(value):
		reason = StringName(value)
