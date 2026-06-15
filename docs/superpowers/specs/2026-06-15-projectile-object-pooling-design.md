# Projectile Object Pooling Design

## Goal

Replace per-shot projectile instantiation and destruction with an automatically expanding, reusable scene object pool. The pooling module must remain independent of RTS combat classes so it can be copied into another Godot project.

## Architecture

`SceneObjectPool` is a generic `Node` service keyed by `PackedScene`. It exposes `acquire(scene, parent)` and `release(instance)`, expands only when no inactive instance is available, and stores inactive instances below itself. It never imports `Projectile`, `Unit`, `AttackData`, or skill classes.

Pooled nodes may implement `on_pool_acquired()` and `on_pool_released()` lifecycle methods. The pool handles ownership, process state, and recursive visual visibility; each projectile resets only its own runtime fields and physics state.

The project registers one `SceneObjectPool` autoload. Weapon and skill spawning code requests instances from this service. Projectile termination paths return instances to the service instead of calling `queue_free()`.

## Lifecycle

1. A caller requests a node for a `PackedScene` and parent.
2. The pool reuses an inactive node or instantiates a new one when empty.
3. The pool reparents and activates the node, then invokes `on_pool_acquired()` when present.
4. The caller positions and configures the projectile through its existing `setup` method.
5. Collision, expiry, invalid setup, or detonation calls the pool release API.
6. The pool invokes `on_pool_released()`, disables processing and visibility, and stores the node for reuse.

## Projectile Reset Rules

Standard projectiles reset target references, attack data, movement directions, elapsed lifetime, transform-dependent transient data, and dynamically created incendiary trails. Grenades reset caster references, skill data, fuse state, detonation state, linear velocity, angular velocity, sleeping/freeze state, and collision state.

## Failure Handling

Null scenes, invalid parents, and failed scene instantiation return `null`. Releasing an object that did not originate from the pool falls back to `queue_free()` so callers do not leak nodes. Releasing an already inactive object is a no-op.

## Testing

Tests cover reuse, automatic expansion, scene isolation, lifecycle hooks, and projectile state reset. Existing projectile and grenade tests remain valid, and the test level must load without parser or runtime errors.
