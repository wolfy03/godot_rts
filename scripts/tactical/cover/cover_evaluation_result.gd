class_name CoverEvaluationResult
extends RefCounted

## Result for one candidate in a specific Unit / Threat context. No evaluation
## is performed here; the future evaluator owns scoring and context freshness.
var candidate: CoverCandidate = null
var valid: bool = false

## All scores contractually use [0.0, 1.0]; the evaluator must normalize them.
## Final desirability: 0 = worst, 1 = best. No aggregation rule is defined yet.
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
