# Projectile Object Pooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route every weapon and skill projectile through an automatically expanding reusable `PackedScene` object pool.

**Architecture:** Add a project-independent `SceneObjectPool` service that manages `Node` instances by source scene and optional lifecycle hooks. Register one project autoload, then adapt standard and grenade projectiles to reset themselves when acquired or released.

**Tech Stack:** Godot 4.6, GDScript, PackedScene, Node lifecycle hooks, headless scene tests

---

### Task 1: Generic scene object pool

**Files:**
- Create: `scripts/pooling/scene_object_pool.gd`
- Create: `tests/pooling/scene_object_pool_test.gd`
- Create: `tests/pooling/scene_object_pool_test.tscn`
- Create: `tests/pooling/fixtures/pool_test_object.gd`
- Create: `tests/pooling/fixtures/pool_test_object.tscn`

- [ ] Write a failing test that acquires two simultaneous objects, verifies automatic expansion, releases one, and verifies the same instance is reused.
- [ ] Run `Godot_v4.6.2-stable_win64.exe --headless --path . tests/pooling/scene_object_pool_test.tscn` and confirm the API is missing.
- [ ] Implement `acquire`, `release`, lifecycle hooks, process/visibility control, and per-scene inactive queues.
- [ ] Re-run the pool test and confirm `scene_object_pool_test: PASS`.

### Task 2: Standard projectile lifecycle

**Files:**
- Modify: `scripts/projectiles/projectile.gd`
- Modify: `scripts/units/unit.gd`
- Test: `tests/projectile_pooling_test.gd`
- Test: `tests/projectile_pooling_test.tscn`

- [ ] Write a failing test proving a released standard projectile is reused with lifetime, direction, attack data, and transient trails reset.
- [ ] Run the test and confirm it fails because projectiles still free themselves.
- [ ] Add pool lifecycle hooks and replace every standard projectile `queue_free()` termination with pool release.
- [ ] Change weapon projectile spawning to acquire from `SceneObjectPool`.
- [ ] Re-run the standard projectile pooling test and existing projectile tests.

### Task 3: Skill projectile lifecycle

**Files:**
- Modify: `scripts/skills/grenade_projectile.gd`
- Modify: `scripts/skills/unit_skill.gd`
- Modify: `tests/grenade_projectile_test.gd`

- [ ] Extend the grenade test to prove fuse, detonation, velocities, and references reset after release and reacquisition.
- [ ] Run the test and confirm it fails with the current destruction behavior.
- [ ] Add grenade pool lifecycle hooks and replace termination with pool release.
- [ ] Change skill projectile spawning to acquire from `SceneObjectPool`.
- [ ] Re-run grenade and skill-related tests.

### Task 4: Project integration and verification

**Files:**
- Modify: `project.godot`
- Verify: `scenes/levels/test_level/test_level.tscn`

- [ ] Register `SceneObjectPool` as an autoload.
- [ ] Search projectile spawn and termination paths to ensure no projectile `instantiate()` or `queue_free()` remains outside tests and pool fallback handling.
- [ ] Run all focused pooling/projectile tests.
- [ ] Load the test level headlessly and inspect output for parser/runtime errors.
- [ ] Run `git diff --check` on all changed files.
