# Chunked navigation (Godot 4.6)

Chunks own the spatial scope of NavigationMesh updates. NavigationAgent3D owns
the final movement path through the connected NavigationServer3D map.
MoveState never follows chunk portals. AStarGrid2D and the legacy waypoint
helpers remain optional coarse strategic/debug tools.

## Scene setup

```text
Level
  WorldGeometry           # ground and static/dynamic collider geometry
  NavigationRegions       # manager-owned region nodes
  ChunkedUnitNavigation
  Units
```

Configure `source_geometry_root_path = ../WorldGeometry` and
`navigation_region_parent_path = ../NavigationRegions`. Both are resolved from
the manager. The source root must be a Node3D. By default parsing includes
StaticBody3D collision geometry on physics layer 1, avoiding duplicate visual
meshes and GPU reads. A NavigationMesh template can override geometry type,
collision mask, agent dimensions and voxel settings. The root and region parent
may be translated/yaw-rotated: parsed root-local vertices are transformed into
region-local vertices before baking. Projected XZ obstructions require an
upright source root.

Each region has an identity global basis and world origin:

```gdscript
world_origin + Vector3(coords.x * chunk_size.x, 0.0, coords.y * chunk_size.y)
```

Its mesh uses local XZ coordinates `[0, chunk_size]`. The flat helper uses this
same convention; its `y_offset` is local to the region. It is for tests, not a
replacement for runtime baking.

Keep chunk dimensions multiples of the template's `cell_size`, and match the
mesh `cell_size` / `cell_height` to the navigation map's voxel settings. Configure
one chunk manager per World3D navigation map; its edge margin is a map-wide
setting. The default edge connection margin is only 0.05m. Seam alignment comes
from an expanded local bake AABB and an inward, voxel-aligned border, not from
large overlaps or a large edge margin. The default bake radius is 0.5m, a
conservative voxel-aligned clearance for a 0.45m ground agent. Ledge filtering
requires an extra cell of border beyond radius erosion.

## Geometry updates

Call `mark_world_bounds_dirty(world_aabb)` for changed geometry, or
`mark_chunk_dirty(coords)` for a specific chunk. Bounds-based changes also dirty
neighbors whose bake halo overlaps the changed geometry. Initial bake requires
marking the initial chunks dirty. Automatic baking is controlled by
`bake_on_dirty`; `request_bake_dirty_chunks()` can start the pending queue
explicitly.

For a solid blocker, call `register_dynamic_obstacle(node)` after adding it to
the scene. Put its collider/mesh under the source root so normal geometry parsing
includes it. Registration stores the combined world AABB of its shapes/meshes;
without geometry, explicit/default avoidance dimensions supply fallback bounds.
These registered bounds also become conservative projected bake obstructions.
This removes enclosed interior floor islands that closed collider surface
rasterization can otherwise leave near chunk boundaries. Irregular geometry
that should retain openings, such as arches, should use geometry parsing plus
`mark_world_bounds_dirty()` rather than solid-blocker registration.

After moving/resizing a registered blocker, register it again. Both old and new
bounds are dirtied and the existing avoidance helper is refreshed. Before
removal, call `unregister_dynamic_obstacle(node, true)` and remove, reparent out
of the source root, or disable its bake geometry before the next parse. Removal
uses stored bounds, not the current center. `tree_exiting` also unregisters
automatically; the instance-ID API supports a source whose node has already
been freed.

The temporary NavigationObstacle3D is 2D avoidance on layers 3 (matching the
base ground agent's mask). It does not supply bake geometry. The collider/source
data and registered bounds supply that geometry independently. Explicit
avoidance radius/height override its automatic bounds-based dimensions.

## Queue and synchronization

Scene parsing runs on the main thread, then
`NavigationServer3D.bake_from_source_geometry_data_async()` bakes a separate
mesh. The old mesh stays active until completion. The manager applies the
completed mesh to its region; NavigationServer synchronization and agent
repathing follow on subsequent physics frames.

`dirty_revision` increases for every change. A bake captures `baking_revision`.
Completion clears dirty only when they still match; otherwise it queues one
additional bake. Only one manager bake is active at a time. Reinitialization
disables/removes old regions and ignores stale completions by generation.
`chunk_bake_finished` means mesh assignment finished, not that the navigation
map has synchronized. Region and map iterations are separate asynchronous
snapshots. Integration tests wait for queue completion, region iteration changes
and the scenario's observable map state (connected final path or changed obstacle
floor) with a bounded timeout. They do not assume two physics frames guarantee
that the new polygons are queryable. Level and long-move tests also wait for a
connected server path before issuing their single final target.

MoveState allows physics frames for target/path updates, then cancels invalid,
blocked, empty or unreachable paths and returns to Idle. Floor clicks may differ
in height from agent centers; XZ reachability is checked with an agent-height
vertical tolerance. Unit advances its path once per physics frame before the
finished check, and faces the next path point while moving. Attack-state aiming
remains unchanged.

`get_debug_snapshot()` reports coords, dirty/baking/walkable state, revisions,
queue size, and request/completion counts. Enable `debug_logging` for state
transition logs.

## Tests

Run from the repository with a Godot 4.6 console executable:

```powershell
godot --headless --path . res://tests/chunked_unit_navigation_test.tscn
godot --headless --path . res://tests/chunked_navigation_runtime_bake_test.tscn
godot --headless --path . res://tests/chunked_navigation_level_navigation_test.tscn
godot --headless --path . res://tests/chunked_navigation_long_move_probe.tscn
```

The runtime test uses real ground/blocker colliders, sibling geometry and
region roots with different transforms, and actual base Unit scenes. It checks
four-region traversal, positive-radius seams, avoidance on/off, floor-click
height compatibility, blocker add/remove, boundary dirtying/rebakes, bake-time
invalidation, automatic repathing during movement, and failed command recovery.
No runtime integration test uses manual chunk portals.

Current limits: parsing scans the configured root per chunk and runs on the main
thread; it has no spatial source cache. Initial baking and the queue are serial.
Registered blockers use conservative AABBs, and movement remains ground XZ
movement. Streaming, hierarchical pathfinding, destructive geometry, and Cover
invalidation are not implemented here.
