# Runtime Box candidates (Godot 4.6.2, Stage 2/2)

```text
RuntimeCoverSource -> RuntimeCoverCandidateGenerator -> revision cache
                  -> CoverSystem spatial query (+ legacy Marker snapshots)
                  -> AIBrain availability preflight -> CoverEvaluator
                  -> TakeCoverState -> runtime reservation -> move -> occupy
```

Sources configure geometry; the generator only produces positions, posture
metadata and identities. CoverSystem owns registration/cache/query/reservation.
Threats, exposure rays and quality scores remain in CoverEvaluator. Commands and
movement remain in TakeCoverState. No Navigation production implementation is
changed and the generator accepts only a Navigation map RID, not a chunk manager.

## Source and geometry contract

RuntimeCoverSource is a level-local Node3D. `source_revision` starts at zero and
is changed explicitly by the caller after geometry/transform/configuration edits.
There is no automatic destruction detection, revision increment or Navigation
dirty event subscription.

`geometry_shape_path` defaults to the named direct child `CollisionShape3D`.
An explicit path may select one descendant CollisionShape3D; external geometry,
disabled/queued shapes and unsupported shapes produce zero candidates. No scene
search picks a different shape implicitly. Only BoxShape3D is supported. For real
collision, use a CollisionObject3D parent for the shape, for example:

```text
WorldGeometry
└ RuntimeCoverSource                 (Node3D, runtime_cover_source.gd)
  └ Body                            (StaticBody3D, collision_layer = 1)
    └ CollisionShape3D              (BoxShape3D)
```

Set `geometry_shape_path = NodePath("Body/CollisionShape3D")`. A bare shape under
Node3D describes generation geometry but does not itself create a physics body.
Configure its collider mask/layer and the level's existing NavMesh bake geometry
so candidate exposure rays and agent movement see the same obstacle. Attaching
this source does not register Navigation obstacles or rebake the map.

The source joins `runtime_cover_sources` on ready. CoverSystem bootstraps that
group once alongside `covers`, accepting only live same-World3D sources. Place
authored sources before the system in a scene. After startup, spawn and register
explicitly with `register_runtime_cover_source(source)`. Duplicate registration
is harmless; unregister and one-shot tree exit invalidate/drop the cache. Queued,
freed, detached and foreign-world sources are also pruned on query/debug access.

Defaults: spacing 1m, clearance 0.7m, maximum 16 samples per side (hard ceiling
64), maximum projection distance 1.5m, minimum separation 0.4m and standing-height
threshold 1.8m. Warnings are off unless `debug_generation` is enabled.

## Sampling and transforms

Generation order is +local X, -local X, +local Z, -local Z. Each transformed side
length determines `ceil(world_length / sample_spacing)`, capped per side. Samples
are evenly spaced bin centers across the face, excluding exact corner endpoints;
a 6m side at 1.5m spacing produces four samples. The cap can increase actual
spacing on long faces. No more than 256 raw samples are considered per box.

Positions use the CollisionShape3D global transform, including source, body,
shape-local translation, yaw and scale. Outward normals use inverse-transpose
basis and normalization, making clearance a world-space distance even with
orthogonal non-uniform/negative scale. Sampling starts at the box bottom and
offsets outside its side plane; final Y comes from Navigation projection.

Tilted, sheared and singular global transforms are rejected, rather than sampled
as an axis-aligned world AABB. This includes non-uniform parent scale combined
with child rotation when it creates nonorthogonal box axes. Positive orthogonal
non-uniform scaling is covered by tests; the collider's engine scale limitations
still apply when setting up physical geometry. Mesh/concave analysis is absent.

World box height >= 1.8m gives STANDING, otherwise CROUCHING. This is approximate
metadata relative to the current standing Unit dimensions, not a physical pose.
Animations, AimPoints and character collider height do not change. The level's
navigation surface/Unit vertical reference must still be configured consistently.

## Navigation projection

The generator checks map RID membership, active state, nonzero iteration and at
least one owner surface. A nonzero freed RID is rejected without querying an
invalid map. Projection uses `NavigationServer3D.map_get_closest_point()`; map
surface availability uses `map_get_closest_point_owner()`. An iteration of zero
means the map has never synchronized. See the official
[Godot 4.6 NavigationServer3D API](https://docs.godotengine.org/en/4.6/classes/class_navigationserver3d.html).

Reject nonfinite projected points, projection farther than the configured limit,
or a projection that preserves less than half the outward face clearance. The
last test prevents snapping inside the box or to its opposite side. Accepted
projected positions are deduplicated in deterministic order by 3D minimum
separation. This is not a path-connectivity, navigation-layer or other-obstacle
clearance analysis; the actual agent remains the movement authority.

## Identity, snapshots and revision cache

```text
runtime:<source_instance_id>:<source_revision>:<index>
index = side * 64 + sample_number
```

The instance ID/key are session-local, not save/network IDs. World position and
the final accepted-array ordinal are not identity. Projection rejection or
deduplication leaves holes in indices and never renumbers later samples.

CoverSystem keeps weak source references, a source-ID-to-candidate-array cache
and its generated revision. First query generates; unchanged revision reuses the
same snapshot objects. Runtime result arrays are separate from cache arrays, so
callers may rearrange/clear a returned array without modifying the stored array.
Candidate source, key, position and source_revision are immutable after publishing.

On revision change the old cache snapshots get only `valid = false`, are removed,
and new objects/keys are generated. This invalidates external references to those
same objects without rewriting their reservation identity or movement destination.
Evaluator rejects stale RuntimeCoverSource revisions even before the next cache
query; new runtime acquisition also rejects stale revision snapshots.

Invalid/unready maps do not record a generated revision; subsequent queries retry.
An empty synchronized map with Regions but no polygons is also unready. Supported
geometry with all projections rejected, or unsupported geometry, is a valid empty
result and is cached until the source revision changes. Later Navigation topology
changes do not automatically refresh a same-revision cache in this stage.

Source removal invalidates/drops its snapshots. Executing commands treat actual
source lifetime loss as failure; Unit also clears occupied state after losing a
bound source. Revision-only invalidation does not forcibly release an active old
candidate. Its original key can still be released after `valid=false`. Old/new
revision keys can overlap physically while old occupation remains: coordinated
active invalidation/reservation migration is the next stage's responsibility.

## Query merge and availability

`query_candidates(origin, radius)` preserves its signature. Legacy source IDs
sorted ascending and authored slots come first, then sorted runtime source IDs
and deterministic cached sample order. Both use squared 3D candidate distance.
Invalid/nonfinite/freed runtime snapshots are excluded. Query does not filter
reserved/occupied candidates and never makes tactical decisions.

AIBrain's shared candidate helper prefilters non-Cover runtime ownership via
`is_candidate_available(unit, candidate)` before combat evaluation or idle
selection. Own ownership is permitted. Legacy candidates go through unchanged;
their occupancy/block/direction checks remain in CoverEvaluator. The prefilter
does not reserve: TakeCoverState still rechecks acquisition and a lost race returns
Idle without substituting another candidate. Idle uses the existing nearest
available policy; combat uses actual geometry AimPoint protection/improvement.

Debug snapshot adds `runtime_source_count` and `runtime_cached_candidate_count`
and retains `runtime_reservation_count`. Query is currently a linear source/cache
scan with one geometry generation per source revision, not spatial indexing.

## Verification and limits

```powershell
godot --headless --path . res://tests/runtime_cover_generator_test.tscn
godot --headless --path . res://tests/runtime_cover_execution_test.tscn
```

Generator tests cover four sides, spacing/caps, transformed clearance/outside
positions, composed yaw, orthogonal non-uniform scale, posture metadata,
projection Y/distance/opposite-side rejection, invalid/freed maps, unsupported
shape/tilt/shear, deterministic keys, startup retry, valid empty caching, counted
same-revision reuse, new revision objects/keys, immutable old fields, query merge,
runtime source lifetime/World3D, availability preflight and idle generated commands.

The combat E2E uses a real StaticBody box, NavigationRegion with an obstacle hole,
Unit, Threat and CoverSystem. AIBrain picks actual generated geometry protection
over a closer low legacy candidate, reserves, moves with NavigationAgent and
occupies. It does not inject manual runtime candidates. Revision-only occupied
ownership preservation and source-removal cleanup are tested separately.

BoxShape3D only; concave/mesh geometry, automatic destruction revision, active
revision invalidation, Navigation topology revision tracking, spatial index,
multi-threat, suppression and physical stance remain unimplemented.
