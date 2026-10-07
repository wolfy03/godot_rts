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
handles combat eligibility; AIBrain's idle compatibility helper checks availability
without a threat or protection score. Moving/deleting a Marker changes subsequent
queries without mutating old snapshots. Existing evaluator checks for stale slots,
missing slots and freed sources remain unchanged. No candidate cache is retained.

`get_debug_snapshot()` reports `registered_source_count`,
`last_query_source_count` and `last_query_candidate_count`.

## AI compatibility

AIBrain's combat and idle paths share the candidate query boundary at its existing
decision interval. A resolved system with an empty registry does not fall back to
the legacy group. While no service is resolved, the old Unit candidate collector
remains a temporary compatibility fallback.

Only a successful same-World3D reference is cached. A missing lookup sets a
monotonic retry deadline using `cover_system_lookup_retry_interval` (default 1s,
minimum 0.01s). Calls before the deadline skip group lookup, and the next needed
query after it retries. Late-created services can therefore be found without a
setup reset API or permanent failure cache. Discovery can take up to the retry
interval plus the next AI decision. A freed, queued, detached or foreign-world
cached service is invalidated and permits a new lookup; subsequent misses again
use the bounded retry. Debug logging is off by default and logs once per missing
period rather than on every retry. Prototype policy remains one service per world.

Combat queries feed CoverEvaluator's threat protection, improvement and score.
No-threat idle queries use `auto_cover_search_radius` (default 5m), filter currently
executable legacy candidates, then choose the nearest candidate world position
by squared 3D distance. Availability requires a live same-world Cover, its exact
live slot at the snapshot position, no other reservation/occupant, and no blocker.
The helper performs no reservation. Ties retain query order. Both service-backed
and no-service idle paths pass the exact CoverCandidate command to TakeCoverState.
`Unit.get_auto_cover()` and nearest-Cover APIs remain public legacy compatibility
paths, but production idle AI no longer calls them.

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
main-level setup, combat/idle registry preference, idle exact-slot reservation,
missing-service fallback, late discovery and replacement, bounded retry, detached
and queued services, and cached World3D changes. Retry tests manipulate deadlines
deterministically instead of waiting real seconds.

## Stage 2 execution constraint

CoverCandidate allows source-less data, and CoverEvaluator can evaluate and choose
it when supplied. This does not imply that it can execute. TakeCoverState currently
casts the source to legacy Cover, then relies on its Marker reservation and route
helpers plus Unit's legacy occupancy state. It cannot reserve, move to or occupy
a source-less/runtime candidate through a cover command. Idle explicitly excludes
such candidates until this execution path exists.

| Capability | Current status |
| --- | --- |
| Runtime geometry generation | Not implemented |
| Query | Stable API prepared; currently emits legacy snapshots only |
| Evaluation | Source-less candidates supported |
| Selection | Combat result selection supported when supplied; idle legacy only |
| Reservation | Legacy Cover only |
| Cover movement | Legacy Cover only |
| Occupation | Legacy Cover only |

Stage 2 must support this conceptual path:

```text
Runtime candidate -> CoverSystem query -> CoverEvaluator -> AIBrain
                  -> reservation provider -> TakeCoverState
```

Keep `query_candidates(origin, radius)` stable while adding legacy sources plus
future runtime producers/cache inside the system. Decide the minimal
source-independent reservation/execution interface after a real producer exists;
no ReservationProvider, execution adapter or runtime registry is implemented here.

Only legacy Marker candidates exist. Runtime geometry sampling, candidate caches,
spatial indexes, runtime reservation, source-independent TakeCover, destruction
revisions, multi-threat evaluation and suppression
remain outside this stage. Navigation code is unchanged. The stable spatial query
boundary can later merge new producers without changing the AI query signature;
runtime execution will also need a compatible reservation/source implementation.
