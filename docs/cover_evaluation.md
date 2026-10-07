# Legacy candidate evaluation (Godot 4.6.2)

`CoverEvaluator` is runtime data (`RefCounted`). It compares candidate quality;
it does not collect scene nodes, reserve slots, move units, or change states.
The combat path is:

```text
AIBrain decision -> CoverSystem spatial query -> CoverEvaluator
                -> CoverEvaluationResult -> CoverCommandData
                -> TakeCoverState -> Cover exact slots / CoverSystem runtime keys
```

## Inputs and result contract

`evaluate(unit, candidate, threat, navigation = null)` returns one evaluation.
`find_best_candidate(unit, candidates, threat, navigation = null)` compares valid
results that provide physical protection and improve on current exposure. It
applies these eligibility checks before choosing the highest score, so a higher
non-improving score cannot hide a usable lower-scoring candidate.
Optional navigation context is supplied by the caller; the
evaluator never searches the SceneTree. It checks coarse chunk walkability only,
not a NavigationAgent path or path length.

Existing `final_score`, `exposure_score`, `fire_opportunity_score`, and `reason`
remain canonical. `score`, `exposure_ratio`, `firing_score`, and `rejection_reason`
are aliases, not duplicate data. Scores remain normalized to [0, 1]; an invalid
result is excluded by its `valid` flag, not a negative sentinel score.
Travel/threat distances use world units. Stance is candidate metadata only;
flank safety remains unevaluated.

Filtering runs before visibility rays: explicit validity, finite position,
source lifetime, Unit/threat context, travel radius, exact legacy slot identity,
reservation, source direction/protection rectangle, and coarse navigation.
Eligible unreserved slots also use the existing blocked-slot physics check.
Reasons include `invalid_candidate`, `invalid_source`, `non_finite_position`,
`too_far`, `missing_slot`, `stale_slot_position`, `reserved`, `occupied`,
`no_protection`, `unreachable`, and `blocked`. No valid batch result returns
`no_valid_candidate`. Invalid Unit/threat context consistently returns
`invalid_context` in both APIs. An empty batch with valid context returns
`no_valid_candidate` without exposure rays. Valid results without protective improvement return
`no_improving_candidate`. A source-less candidate is allowed; a previously bound,
freed source is rejected. Automatic geometry change detection is not implemented.
RuntimeCoverSource snapshots with a different source_revision also reject as
`stale_source_revision`, even before cache invalidation. Legacy revisions are not
checked. See [Runtime generation](runtime_cover_generation.md) for cache policy.

## Visibility and scoring

Virtual AimPoint positions are `candidate.position + marker.global_position -
unit.global_position`. The world offset preserves current root rotation/scale
and nested AimPoints transforms without teleporting the Unit or its Markers.
Weights come from `Unit.get_aim_point_weight()`, also used by ranged attacks.
The usual seven samples sum to one. Exposure is visible weight / available
weight; missing all samples conservatively yields full exposure.

Incoming rays use the threat's actual muzzle and obstacle mask. Outgoing fire
uses a virtual Unit muzzle and one ray to the threat's Chest, falling back to
its muzzle if Chest is absent. `Unit.has_clear_ranged_aim_to()` supplies the same
body-only, area-excluding query and shooter/target RID exclusions as ranged aim.
Outgoing fire means geometry line of sight; range, facing, recoil, spread and
projectile trajectories are not simulated by the evaluator.

Default weights, defined only in the evaluator, are:

```text
protection = 1 - exposure
firing     = 1 if outgoing line of sight is clear, otherwise 0
travel     = clamp(1 - Euclidean distance / max_travel_distance, 0, 1)
score      = protection * 0.50 + firing * 0.25 + travel * 0.25
```

Custom nonnegative weights are normalized by their sum. The default distance
limit is 20m. CoverGrade does not add score, and gameplay evasion/buffs are never
part of this calculation. Legacy source direction is a cheap eligibility gate;
physical ray visibility determines protection quality.

There are at most seven exposure rays and one outgoing ray per eligible legacy
candidate, plus seven current-position exposure rays once per batch. The shared
baseline is applied to each valid result before selection. Standalone `evaluate()`
still measures its own current-position baseline and reports a valid evaluation
even when that candidate does not improve the current position.
`improves_current_position` requires a move over 0.05m and at least 0.05 exposure
reduction by default. Batch selection excludes results below this threshold;
AIBrain consumes the eligible best result. Quality evaluation is performed on
AI decisions, not Attack/Chase frames.

## AI and reservation compatibility

AIBrain searches candidate positions within `max_cover_search_radius` (20m by
default), supplies the actual threat and optional chunk manager, and issues the
best protective candidate that improves on current exposure. It caches a
same-World3D CoverSystem on successful lookup; queries use its registered sources, even
when its registry is empty. See [CoverSystem](cover_system.md) for registration
and snapshot policy. Scenes without the service retain the temporary
`Unit.get_legacy_cover_candidates_nearby()` fallback while lookup misses retry
at a configurable interval (default 1s). Debug output is
off unless `debug_cover_evaluation` is enabled. Attack/Chase no longer run their
own per-frame nearest-cover selection. No-threat idle also queries CoverSystem,
then chooses the nearest available executable candidate without invoking
the threat-based evaluator. Both paths issue exact candidate commands;
MoveState/player Cover input and legacy public queries remain compatible.

While TakeCoverState has a legacy or runtime reservation but no matching occupancy,
`request_decision()` defers all autonomous decisions before healing, skills or
combat can interrupt that move. This policy is independent of MoveState's
`allow_move_interrupt`. Once arrival sets `current_cover` or
`current_cover_candidate`, TakeCoverState's AI callback can resume normal
decisions, including AttackState.

`Cover.get_candidate_slot()` resolves opaque reservation identity inside the
source. `reserve_candidate()` rechecks that exact slot, position and availability
at activation, preserving Marker-based ownership. It never substitutes a nearer
slot after a reservation race. Source-less and live non-Cover candidates execute
through the CoverSystem key backend and a direct final target. Runtime reservation
competition is rechecked at activation. AIBrain prefilters non-Cover runtime
availability before evaluation; the evaluator does not query the runtime registry.
Geometry scoring remains unchanged. See [Runtime execution](runtime_cover_execution.md)
and [the capability matrix](cover_system.md#stage-2-execution-contract).
`TakeCoverState` accepts a Cover, a candidate,
or `CoverCommandData(candidate)`. Candidate commands move toward the snapshot
position using the legacy Cover route helper or the runtime direct target. Stuck
tracking measures horizontal distance to this final slot/candidate position,
not to the Cover origin; remote route waypoints reset the tracking timer. If a
candidate move gets stuck, it releases the command for AI re-evaluation instead
of choosing an unrelated nearest Cover. Legacy commands keep their old fallback.

## Tests and limits

```powershell
godot --headless --path . res://tests/cover_evaluator_test.tscn
```

Real collider tests cover open/full/partial visibility, protection without fire,
weighted candidate comparison, own/other reservations and occupancy, invalid or
removed snapshots, coarse navigation rejection, two opposite threats, exact
selected-slot activation, reservation races, and virtual transform/no-side-effect
behavior. Regressions also cover a higher-score/non-improving candidate versus
a lower-score/improving candidate, repeated AI decisions during reserved cover
travel and resumed combat after arrival, and stuck handling near a slot far from
its Cover origin. Existing candidate, direction, aim point and navigation tests
remain.

Production collection merges authored Markers and Box-generated revision-cached
runtime candidates. Automatic destruction/active invalidation, suppression,
multi-threat scoring, or squad allocation do not exist yet. Current pose is preserved: CROUCHING
metadata does not lower AimPoints or alter animation. Legacy slot heights can
therefore leave a low wall physically unprotective, despite its direction and
CoverGrade. Legacy grade-based gameplay buffs remain unchanged.
