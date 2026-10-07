# Source-independent cover execution (Godot 4.6.2, Stage 2/1)

Authored, manually created and Box-generated runtime snapshots use the same
`CoverCandidate` or `TakeCoverState.CoverCommandData` command. The Stage 2/1 manual
execution tests remain; Stage 2/2 adds [Runtime generation](runtime_cover_generation.md)
and query caches with real geometry/AI end-to-end tests.

## Reservation backends

| Candidate source | Backend | Route |
| --- | --- | --- |
| Live legacy `Cover` | `Cover.reserve_candidate()` exact Marker slot | Legacy Cover route helper |
| No source, or live non-Cover Node3D | `CoverSystem.reserve_candidate()` runtime key | One final NavigationAgent target |

The runtime backend is level-local, with one CoverSystem per World3D. Activation
resolves the same-world service once, independently of AIBrain's bounded lookup
retry. Unit keeps a WeakRef to the acquiring backend so release never goes to a
new replacement service. Missing, detached, queued or foreign-world backends fail
the active travel command and clear its target. Runtime sources, when bound, must
be alive, in-tree, nonqueued and in the same World3D at acquisition. A previously
bound freed source cannot be reinterpreted as source-less. Execution/occupied
state also clears on bound-source lifetime loss. Revision-only invalidation of
an already executing candidate does not force release in this stage.

`_runtime_reservations: Dictionary[StringName, WeakRef]` maps a key to a Unit.
`reserve_candidate(unit, candidate)` requires a live same-world Unit, valid finite
candidate data and a nonempty key. Self re-reservation succeeds. Another Unit's
ownership fails without fallback. `is_candidate_available()` is read-only.
`get_runtime_candidate_occupant()` exposes ownership for execution/debug checks.
All are runtime-only; they reject legacy Cover candidates instead of intercepting
Marker reservation identities. Legacy slot API ownership remains in Cover.

`release_candidate()` is owner-only and idempotent. It accepts an existing runtime
record even if the candidate's explicit validity has changed. Access prunes dead,
freed, queued, tree-exited and foreign-world Unit owners. Spatial query and debug
snapshot also prune records. Reserved and occupied keys use the same registry:
both are unavailable to other Units.

Keys identify logical locations, not world coordinates. Test producers use names
such as `runtime:arrival`; identical keys compete even in distinct snapshot
objects with different positions. Different keys at the same position are not
spatially deduplicated. Keys are not save-game, multiplayer or cross-level IDs.
All runtime candidates are immutable snapshots. Do not change source, key,
position or source_revision during execution. Generation cache invalidation may
only set valid=false; keys of new revisions identify fresh snapshots. Coordinated
active snapshot invalidation/recovery arrives in Stage 2/3.

## Unit state and lifecycle

Runtime execution uses `reserved_cover_candidate` and `current_cover_candidate`;
legacy `reserved_cover`, `reserved_cover_slot` and `current_cover` stay empty.
The reserved snapshot remains set after arrival while current marks occupation,
matching the existing legacy reserved/current convention.

`reserve_runtime_cover_candidate(candidate, system)` validates availability,
clears previous cover state and acquires the key. `occupy_runtime_cover_candidate()`
checks ownership and arrival before setting current. `clear_cover()` releases both
backends via their existing owner, clears all state and is idempotent. A Unit tree
exit also releases runtime ownership. Switching legacy/runtime commands, including
same-state reactivation and direct legacy reserve APIs, releases the old backend.

TakeCoverState manages acquisition and travel cancellation/stuck failure. An
unoccupied runtime reservation is released on deactivation. Occupied cover survives
the arrival-to-Attack handoff as legacy cover does; Unit owns cleanup after that
handoff. Attack completion/out-of-range returns to the current runtime candidate.
Manual clear, player-command overwrite, death, tree exit and normal Move command
activation release it. No service lookup is performed during cleanup. Low-level
CoverSystem reservation calls only manage registry ownership, not Unit state;
command callers should use TakeCoverState/Unit helpers.

`is_cover_travel_in_progress()` recognizes both backends, so AIBrain decisions
cannot replace a selected runtime move before arrival. `should_auto_take_cover()`
also checks both reserved/current runtime fields. Idle availability can check
generated runtime keys; it still performs no scoring or acquisition. AIBrain
prefilters other runtime owners before combat evaluation, with acquisition
resolving any later ownership race. Geometry scoring policy is unchanged.

## Movement, arrival and failure

Runtime commands set `_route_waypoint = Vector3.INF` and submit only
`navigation_agent.target_position = candidate.position`. No chunk portals, path
queries or legacy route helpers are used. NavigationAgent/NavigationServer own the
path and avoidance as before.

Arrival requires XZ distance <= `cover_slot_hold_radius` (default 0.65m) and
absolute Y difference <= NavigationAgent height (minimum tolerance 0.1m).
Occupation disables movement and zeros velocity. The arrival callback resumes
AI decisions, including Attack. Runtime cover never grants CoverGrade buffs or a
grade-based indicator; tactical geometry protection and gameplay evasion are
separate.

Stuck tracking measures the final candidate position using the existing configured
near-target distance and duration. A stuck or contested runtime command releases
ownership, clears runtime state, stops the old target and returns Idle. It never
selects a nearest legacy Cover. Far-away unreachable target timeout/replanning is
not added here; the existing near-target stuck policy remains the current limit.
Runtime revision-driven invalidation during execution is not implemented.

## Verification and next stage

```powershell
godot --headless --path . res://tests/runtime_cover_execution_test.tscn
```

Tests cover key competition, self re-reservation, owner-only release, invalid data,
freed/tree-exited/queued owners, live non-Cover sources, World3D isolation, actual
AI commands, height-aware arrival, repeated travel decisions, combat resumption
with retained occupation, no grade buff, reservation races after evaluation,
stuck release, state cancellation, manual clear, player overwrite, death, backend
loss/missing service, same-state backend switching and exact legacy slots. Real
NavigationAgent movement reaches/occupies runtime snapshots with avoidance off
and on.

Box generation and revision caches now sit behind the spatial query API.
Automatic destruction revisions, active invalidation, Navigation topology revision
tracking, spatial indexing, physical stance/AimPoint changes, multi-threat scoring,
suppression, Utility AI and network authority remain unimplemented.
