# Level-local cover queries (Godot 4.6.2)

`CoverSystem` is a Node3D owned by the combat level, not an autoload. It registers
Cover sources and returns world-position candidate snapshots. It does not know
Unit/threat context, score candidates, test availability, raycast, reserve slots,
query navigation or change states.

```text
Unit position + radius -> CoverSystem.query_candidates()
                      -> registered Cover adapters -> candidate radius filter
                      -> Array[CoverCandidate]
AIBrain -> CoverEvaluator.find_best_candidate() -> TakeCoverState
```

## Setup and source lifetime

The main combat scene `scenes/levels/test_level/test_level.tscn` owns a CoverSystem
after its authored Cover nodes. On ready it joins `cover_system` and scans the
legacy `covers` group once, registering live sources in its own World3D. Place
the system after authored Covers so their ready-time group membership already
exists. AI resolves the service lazily, after level setup, and caches it.

Runtime spawners must explicitly register new Covers after adding them to the
tree; spawning a node into the legacy group alone does not register it:

```gdscript
world_geometry.add_child(new_cover)
cover_system.register_cover_source(new_cover)
```

`unregister_cover_source(cover)` removes it from query results without deleting
the source or touching reservations. Registration/unregistration is idempotent.
A typed instance-ID-to-WeakRef dictionary does not retain sources. One-shot
`tree_exiting` callbacks remove deleted or detached Covers; queries also prune
invalid, queued or foreign-world sources once before iterating the registry.
Re-register detached sources explicitly after adding them back to the tree.

Use one CoverSystem per combat World3D in this prototype. Registry bootstrap and
AI lookup are world-scoped, not a hierarchy-based partition of the same world.
There is no service locator or automatic runtime source discovery.

## Query contract

`query_candidates(origin: Vector3, radius: float) -> Array[CoverCandidate]` takes
world coordinates. Nonfinite origin/radius or nonpositive radius returns an empty
array. Sources are sorted by runtime instance ID and retain authored slot order,
so equal-score evaluations have stable input order within the running scene.

Each source creates fresh snapshots via `get_cover_candidates()`. Filtering uses
squared 3D distance to each candidate. A strict Cover-center filter is deliberately
omitted: a large source can have an in-radius slot far from its origin. Query cost
is currently proportional to registered sources and authored slots.

Reserved, occupied and blocked candidates remain in the query. CoverEvaluator
handles context-dependent eligibility. Moving/deleting a Marker changes subsequent
queries without mutating old snapshots. Existing evaluator checks for stale slots,
missing slots and freed sources remain unchanged. No candidate cache is retained.

`get_debug_snapshot()` reports `registered_source_count`,
`last_query_source_count` and `last_query_candidate_count`.

## AI compatibility

AIBrain queries the cached same-World3D system at its existing decision interval.
An empty registry does not fall back to the legacy group. If no service exists
on initial lookup, the old Unit query remains a temporary compatibility fallback;
missing-service lookups are not repeated every decision. Configure the level's
service before the first tactical query. Losing a cached service permits one new
lookup, then safe legacy fallback. Debug logging for fallback is off by default.

No-threat idle Cover commands and public legacy queries stay compatible.
TakeCoverState still executes through the exact legacy slot reservation adapter.
Its candidate input, travel guard, arrival callback, reservation race handling
and candidate-position stuck behavior are preserved.

## Verification and limits

```powershell
godot --headless --path . res://tests/cover_system_test.tscn
godot --headless --path . res://tests/cover_evaluator_test.tscn
```

Tests cover bootstrap, runtime/duplicate registration, radius queries including
distant-origin slots, snapshot independence, reserved/occupied query results,
source deletion/removal/re-entry, World3D isolation, cached-service deletion,
main-level setup, AI registry preference and missing-service fallback.

Only legacy Marker candidates exist. Runtime geometry sampling, candidate caches,
spatial indexes, destruction revisions, multi-threat evaluation and suppression
remain outside this stage. Navigation code is unchanged. The stable spatial query
boundary can later merge new producers without changing the AI query signature;
runtime execution will also need a compatible reservation/source implementation.
