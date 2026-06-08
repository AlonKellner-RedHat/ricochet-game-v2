# TDD Document 4: Arrow Flight and Checkpoints

**Stages 31--33** | Arrow flight with plans, checkpoints, plan retention

### Stage Status

| Stage | Topic | Status |
|-------|-------|--------|
| 31 | Arrow Flight with Plan | Done |
| 32 | Checkpoint System | Todo |
| 33 | Plan Retained After Shot | Done |

**Regression Test Policy:** After implementing Stage N, run ALL tests from Stages 1 through N. The full test suite must pass before proceeding to Stage N+1. No exceptions.

**Feedback Loop Protocol (applies to every stage):**
1. AI implements the stage (code + unit tests).
2. AI runs all unit tests (new + all prior). All must pass.
3. User performs interactive tests from the checklist.
4. User provides feedback (pass/fail per item + notes on unexpected behavior).
5. AI converts any failing interactive tests into automated tests.
6. AI applies fixes and re-runs all tests.
7. Repeat steps 3--6 until all checks pass.
8. Stage is marked complete. Proceed to next stage.

**USER VALIDATION GATE (MANDATORY)**

No stage is complete until the user has personally verified every interactive test item and provided explicit sign-off. After every behavioral feature (not just infrastructure), the user must SEE the behavior working in the running game before the stage is marked complete.

1. User MUST test every interactive test item marked with `[ ]`.
2. User MUST provide written pass/fail feedback for EACH item.
3. Any "fail" or "unexpected behavior" becomes a NEW automated test before proceeding.
4. AI MUST NOT proceed to the next stage until ALL interactive items are `[x]`.
5. The user's word is final. If the user says it doesn't look right, it doesn't ship.

---

## Stage 31: Arrow Flight with Plan

### Overview
When the player fires with a valid plan, the arrow follows the physical trace -- bouncing off planned mirrors as expected. If the plan is aligned with the physical outcome, the arrow faithfully reproduces the planned trajectory. The camera tracks the arrow tip during flight using Godot's built-in smoothing, clamped to level bounds, and smoothly returns to the player after the shot completes.

### Prerequisites
Stages 1--30 (complete math layer, surfaces, physical trace loop, preview rendering, arrow shooting with freeze/animation/skip, room boundaries, plan construction/removal, planned trace with image chains, step tree merge with divergence detection).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Behavior | Arrow follows physical trace when plan is present | §4.4 |
| Behavior | Aligned plan: physical trace matches planned trace -- arrow bounces off mirrors as planned | §4.4, §4.5 |
| Behavior | Camera tracks arrow tip during flight (`Camera2D`, `position_smoothing_enabled=true`, `position_smoothing_speed=5.0`) | §4.5, §21.1 |
| Behavior | Camera clamped to `LevelData.bounds` during flight | §4.5 |
| Behavior | Camera smoothly returns to player after shot completes | §4.5 |
| Behavior | Preview hidden during arrow flight, reappears after | §21.1 |
| Behavior | Arrow flight uses same physical trace as preview (UX3 guarantee) | §4.4, Principle 2 |

### Unit Tests Added

1. **`test_stage31_arrow_follows_physical_trace_with_plan`**: Set up a scene with one reflective surface. Create a plan targeting that surface. Fire. Expected: arrow visits the same hit points as the physical trace steps, in order. Invariant validated: UX3 (preview matches flight).
2. **`test_stage31_aligned_plan_matches_physical`**: Set up a scene with one mirror (simple reflection from §16.1). Create a valid plan. Compute planned trace and physical trace. Expected: both traces produce the same hit points (same surface ID, same side, same point within machine precision). Invariant validated: UX4 (determinism), UX3 (preview matches flight).
3. **`test_stage31_camera_smoothing_enabled`**: During arrow flight, verify `Camera2D.position_smoothing_enabled == true` and `Camera2D.position_smoothing_speed == 5.0`. Expected: both properties hold. Invariant validated: §4.5 camera spec.
4. **`test_stage31_camera_clamped_to_bounds`**: Create a level with small bounds. Fire an arrow toward the edge. Expected: camera position stays within `LevelData.bounds` at all frames during flight. Invariant validated: §4.5 camera clamping.
5. **`test_stage31_camera_returns_to_player`**: Fire arrow, wait for flight to complete. Expected: camera target position equals player position after flight ends. Invariant validated: §4.5 post-flight camera.
6. **`test_stage31_preview_hidden_during_flight`**: Fire arrow. Expected: path renderer `visible == false` during flight, `visible == true` after flight ends. Invariant validated: §21.1.
7. **`test_stage31_determinism_with_plan`**: Fire the same shot (same position, cursor, plan, game state) twice. Expected: identical step trees (same step count, same step types, same Point IDs). Invariant validated: UX4 (determinism).
8. **`test_stage31_camera_bounds_arc_flight`**: Fire arrow through an inversion surface producing an arc flight path. Arc curves near level boundary. Expected: camera position stays within `LevelData.bounds` at all frames. Validates: §4.5. *(Forward placeholder — arc flight paths are introduced in Stage 42. At Stage 31 this test passes vacuously since no arc flights are possible. It becomes meaningful after Stage 42.)*
9. **`test_stage31_camera_returns_after_escape_flight`**: Fire an arrow that escapes (no hit on any surface). Arrow flies to viewport edge and disappears. Expected: camera smoothly returns to the player after the arrow disappears. No crash, no camera stuck at edge. Validates: §4.5 camera behavior during escape.

### Interactive User Tests **[BEHAVIORAL -- USER SIGN-OFF REQUIRED]**

- [ ] Place a reflective surface in the room. Add it to the plan (left-click). Aim so the preview shows an aligned (green) bounce. Press Spacebar. The arrow follows the bounce path exactly as the preview showed.
- [ ] During arrow flight, observe the camera: it smoothly follows the arrow tip. The camera does not jerk or jump.
- [ ] Fire a long shot that traverses most of the room. The camera stays within the room bounds (does not show empty space beyond walls).
- [ ] After the arrow completes its flight, the camera smoothly pans back to the player position.
- [ ] During flight, the green/red preview lines are hidden. After the shot, they reappear.
- [ ] Fire the same shot twice (undo, reposition identically, fire again). The arrow follows the exact same path both times.
- [ ] Fire a shot where the plan diverges (e.g., a wall blocks the arrow before the planned mirror). The arrow follows the physical (yellow) path, not the planned (red) path.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| UX3 | Physical preview matches arrow flight | Unit test: arrow visits same hit points as physical trace | Reinforced (first test with plan) |
| UX4 | Same shot = same result (determinism) | Unit test: two identical fires produce identical step trees | Reinforced (first test with plan) |
| UX7 | Solid path leads from player to cursor | Visual: green line during preview | Inherited |
| UX9 | Block stops arrow | Visual: arrow stops at block surface | Inherited |
| UX11 | Empty plan = fire straight | Unit test from prior stages | Inherited |

### Regression Checklist

| Category | Prior Stage | Behavior | How to Verify |
|----------|-------------|----------|---------------|
| **Math** | Stages 4--8 | Direction, Ray, GeneralizedCircle, Segment, TransformCache all correct | Run GUT math tests |
| **Math** | Stages 9--12 | Intersection system: line-line, line-circle, find_earliest_hit | Run GUT intersection tests |
| **Math** | Stages 13--16 | Surface effects: FixedResolver, SideConfig, TerminalEffect, ReflectionEffect | Run GUT effect tests |
| **Math** | Stages 17--20 | Physical trace loop (256 limit, pass-through) | Run GUT trace tests |
| **Visual** | Stage 5 | Green solid preview line from player to cursor | Move mouse, observe |
| **Visual** | Stages 21--24 | Preview: green solid to cursor, green dashed past cursor | Move mouse with/without plan |
| **Visual** | Stages 25--30 | Step tree rendering with 5 step types in correct colors/styles | Create diverging plan, observe |
| **Interaction** | Stage 3 | Cursor follows mouse | Move mouse |
| **Interaction** | Stage 2 | Player moves with WASD | Press WASD |
| **Interaction** | Stages 25--26 | Plan add (left-click) and remove (right-click/C) | Click surfaces |
| **Interaction** | Stage 27 | Arrow shooting: Spacebar fires, freeze, animation, skip | Fire arrow |

### Expected Visual State

Room with walls (red block surfaces). Internal surfaces (mirrors, etc.) visible. Player at spawn. Cursor at mouse. Preview shows planned trajectory. On fire: preview disappears, arrow animates along the physical path, camera follows arrow. After shot: preview reappears, camera returns to player. If plan is aligned, arrow follows the green path exactly; if diverged, arrow follows the yellow (physical) path.

### Feedback Loop Protocol

See standard protocol at top of document.

### Validation Summary (filled in after implementation)

| Check | Status | Notes |
|-------|--------|-------|
| All unit tests pass | [ ] | |
| All prior regression tests pass | [ ] | |
| User interactive sign-off | [ ] | |
| Failing interactive tests automated | [ ] | |
| Stage complete | [ ] | |

### Files Modified/Created

| File | Action | Purpose |
|------|--------|---------|
| `scripts/game/arrow_animator.gd` | Modify | Support arrow flight along physical trace with plan present |
| `scripts/game/game_manager.gd` | Modify | Integrate plan into shot lifecycle, hide/show preview |
| `scripts/visual/path_renderer.gd` | Modify | Add visibility toggle for flight hiding |
| `scenes/main.tscn` | Modify | Camera2D smoothing configuration |
| `tests/test_stage31_arrow_flight_plan.gd` | Create | Arrow flight with plan tests |

---

## Stage 32: Checkpoint System

### Overview
Implement the checkpoint system that saves game state just before each shot and allows the player to undo (Z key) or fully reset (R key). CheckpointData captures player position, velocity, game state (deep copy), plan, and targets hit. Checkpoints accumulate on a stack, allowing the player to step back through multiple shots one at a time.

### Prerequisites
Stage 31 (arrow flight with plan -- the checkpoint is saved before the shot, so the shot lifecycle must exist).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Data structure | `CheckpointData`: player_position (Vector2), player_velocity (Vector2), game_state (GameState deep copy), plan (Array[{surface_id, side}]), targets_hit (Set[int]) | §3.3 |
| Behavior | Checkpoint saved just BEFORE each shot | §3.3 |
| Behavior | Undo (Z key): revert to pre-shot state (all fields restored) | §3.3, §4.1 |
| Behavior | Full reset (R key): revert to level's initial state (all surfaces restored, player at spawn, checkpoint stack cleared) | §3.3, §4.1 |
| Behavior | Checkpoint stack: checkpoints accumulate per shot, player can step back one at a time | §3.3 |
| Script | `scripts/game/checkpoint.gd` -- CheckpointData class and stack management | §3.3 |

### Unit Tests Added

1. **`test_stage32_checkpoint_saves_player_position`**: Save a checkpoint with player at (200, 300). Move player to (500, 400). Undo. Expected: player position == (200, 300). Invariant validated: UX5 (undo fully restores).
2. **`test_stage32_checkpoint_saves_player_velocity`**: Save a checkpoint with player velocity (0, 0). Apply velocity change. Undo. Expected: player velocity == (0, 0). Invariant validated: UX5.
3. **`test_stage32_checkpoint_saves_game_state_deep_copy`**: Save checkpoint. Modify a game state flag. Undo. Expected: game state flag restored to pre-shot value. The modification after saving does NOT affect the checkpoint's copy. Invariant validated: UX5.
4. **`test_stage32_checkpoint_saves_plan`**: Save checkpoint with plan [{surface_1, LEFT}]. Clear plan. Undo. Expected: plan == [{surface_1, LEFT}]. Invariant validated: UX5.
5. **`test_stage32_checkpoint_saves_targets_hit`**: Save checkpoint with targets_hit = {1, 3}. Hit target 5. Undo. Expected: targets_hit == {1, 3}. Invariant validated: UX5.
6. **`test_stage32_undo_pops_from_stack`**: Fire 3 shots (3 checkpoints on stack). Undo once: restores state before shot 3. Undo again: restores state before shot 2. Undo again: restores state before shot 1. Undo again: no-op (stack empty). Invariant validated: UX5.
7. **`test_stage32_full_reset_clears_stack`**: Fire 3 shots. Full reset (R). Expected: player at spawn, game state == initial_flags, plan cleared, targets_hit empty, checkpoint stack empty. Subsequent undo is no-op.
8. **`test_stage32_full_reset_restores_initial_state`**: Set initial_flags = {"wall_intact": true}. Fire a shot that changes wall_intact to false. Full reset. Expected: game state has wall_intact == true. Invariant validated: UX5.
9. **`test_stage32_checkpoint_saved_before_shot`**: Register a callback on checkpoint save. Fire. Expected: checkpoint saved BEFORE the physical trace runs (checkpoint's game state matches pre-shot state, not post-shot).
10. **`test_stage32_undo_indistinguishable_from_pre_shot`**: Fire a shot. Record full game state. Undo. Compare current game state to recorded pre-shot state. Expected: identical (player position, velocity, game state flags, plan, targets_hit). Invariant validated: UX5.
11. **`test_stage32_checkpoint_deep_copy_nested`**: GameState.flags contains `{"config": {"sub_key": [1, 2, 3]}}`. Save checkpoint. Modify nested array: append 4. Undo. Expected: `flags["config"]["sub_key"] == [1, 2, 3]`. Validates: true deep copy, not shallow.
12. **`test_stage32_checkpoint_stack_depth_50`**: Fire 50 shots (each from a slightly different position). Undo all 50. Expected: final state matches initial level state exactly (player position, game state, plan, targets_hit). No crash, no memory error. Validates: §3.3 unbounded checkpoint stack.

### Interactive User Tests **[BEHAVIORAL -- USER SIGN-OFF REQUIRED]**

- [ ] Fire a shot. Press Z. Player returns to pre-shot position. Surfaces return to pre-shot state. Plan is restored.
- [ ] Fire 3 shots, each changing game state. Press Z three times. Each undo steps back one shot. After 3 undos, the game is at the initial state of the first shot.
- [ ] Press Z with no shots fired. Nothing happens (no crash, no error).
- [ ] Fire a shot that breaks a surface (state change). Press Z. The surface is restored (unbroken).
- [ ] Fire 2 shots. Press R. Player returns to spawn. All surfaces restored to initial state. Press Z. Nothing happens (checkpoint stack was cleared).
- [ ] Fire a shot, observe targets_hit increases. Press Z. targets_hit returns to pre-shot value.
- [ ] Fire a shot. Move the player with WASD. Press Z. Player returns to the position they were at when they fired, not where they walked to after.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| UX5 | Undo fully restores: game indistinguishable from pre-shot state | Unit test: all fields restored exactly | Yes |
| UX3 | Preview matches flight | Inherited | Inherited |
| UX4 | Determinism | Inherited | Inherited |
| UX9 | Block stops arrow | Inherited | Inherited |

### Regression Checklist

| Category | Prior Stage | Behavior | How to Verify |
|----------|-------------|----------|---------------|
| **Math** | Stages 4--12 | All math primitives and intersection correct | Run GUT tests |
| **Math** | Stages 13--20 | Surfaces, effects, trace loop correct | Run GUT tests |
| **Visual** | Stages 5, 21--30 | Preview rendering with all step types | Move mouse, observe preview |
| **Interaction** | Stage 31 | Arrow flight with plan, camera tracking | Fire with plan, observe |
| **Interaction** | Stage 27 | Arrow shooting basics (freeze, animation, skip) | Fire arrow |
| **Interaction** | Stages 25--26 | Plan construction and removal | Click surfaces |

### Expected Visual State

Same as Stage 31. After pressing Z: the entire scene reverts visually to the pre-shot state -- player position, surface states, plan overlay, and preview all snap back. After pressing R: everything reverts to the level's initial load state. No visual artifact or flicker during undo/reset.

### Feedback Loop Protocol

See standard protocol at top of document.

### Validation Summary (filled in after implementation)

| Check | Status | Notes |
|-------|--------|-------|
| All unit tests pass | [ ] | |
| All prior regression tests pass | [ ] | |
| User interactive sign-off | [ ] | |
| Failing interactive tests automated | [ ] | |
| Stage complete | [ ] | |

### Files Modified/Created

| File | Action | Purpose |
|------|--------|---------|
| `scripts/game/checkpoint.gd` | Create | CheckpointData class and checkpoint stack management |
| `scripts/game/game_manager.gd` | Modify | Save checkpoint before shot, handle Z (undo) and R (reset) inputs |
| `scripts/game/player.gd` | Modify | Support position/velocity restoration from checkpoint |
| `tests/test_stage32_checkpoint.gd` | Create | Checkpoint system unit tests |

---

## Stage 33: Plan Retained After Shot

### Overview
After firing, the plan is NOT cleared (per §3.4: "Plan is RETAINED"). Plan entries reference surfaces by surface_id, so when game state changes a surface's behavior, the plan entry still resolves to the current surface. The preview updates with the retained plan at the new player position after the shot completes.

### Prerequisites
Stage 32 (checkpoint system -- the retained plan is part of the checkpoint, and the plan-retention behavior interacts with the undo system).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Behavior | Plan retained after shot (not cleared) | §3.4 |
| Behavior | Plan entries reference surfaces by surface_id -- resolve to current surface state | §3.4, §4.2 |
| Behavior | Preview updates with retained plan at new player position post-shot | §3.4, §4.2 |

### Unit Tests Added

1. **`test_stage33_plan_retained_after_shot`**: Set plan = [{surface_1, LEFT}]. Fire. Expected: plan still equals [{surface_1, LEFT}] after shot completes. Validates: §3.4 "Plan is RETAINED."
2. **`test_stage33_plan_resolves_to_current_state`**: Set plan = [{surface_1, LEFT}], where surface_1 has a CategoricalResolver with state_key "mirror_intact". Fire a shot that sets mirror_intact=false (changing surface_1's effect from Reflection to null). Expected: plan still contains {surface_1, LEFT}, but resolving the side config now returns null (pass-through) instead of Reflection. Validates: §4.2 surface_id resolution.
3. **`test_stage33_preview_updates_post_shot`**: Fire a shot that moves the player (or use a shot where the player remains stationary but state changes). Expected: preview is recomputed from the new player position with the retained plan. The preview line endpoints differ from the pre-shot preview. Validates: preview recalculation.
4. **`test_stage33_plan_survives_multiple_shots`**: Fire 3 shots without modifying the plan. Expected: plan unchanged after all 3 shots.
5. **`test_stage33_cleared_plan_stays_cleared`**: Clear plan (C key). Fire. Expected: plan is still empty after shot. (The retention behavior preserves whatever the plan was, including empty.)
6. **`test_stage33_plan_entry_changed_effect`**: Test the FULL lifecycle: (1) Plan entry added when surface has Reflection. (2) Shot fired that changes state → surface now resolves to null (pass-through). (3) State promoted. (4) Plan is retained. (5) Compute preview with retained plan. Expected: the entry is treated as pass-through in the preview. (6) Fire again. Expected: the arrow ignores the now-null-effect entry. Validates: §3.4 plan retention through state changes, end to end.
7. **`test_stage33_plan_entry_invalid_surface_id`**: Plan contains an entry referencing a surface ID that does not exist in the scene (simulating a destroyed or removed surface). Expected: the entry is skipped. The planned trace ignores it. No crash. A debug warning is logged. Validates: graceful handling of invalid plan entries.
8. **`test_stage33_plan_retained_after_skip`**: Set a plan (1+ entries), fire, skip animation (press key mid-flight). Expected: after skip completes and game unfreezes, the plan is still present (same entries). Validates: §3.4 plan retention works through the skip path, not just normal completion.

### Interactive User Tests

- [ ] Add surfaces to the plan. Fire. After the shot, the plan overlay (numbered labels on surfaces) is still visible -- plan was not cleared.
- [ ] The preview updates immediately after the shot, showing the planned trajectory from the new player position.
- [ ] Fire a shot that changes a surface's state (e.g., breaks a wall). The plan still shows the surface, but the preview may now show different behavior (e.g., the planned surface is now pass-through).
- [ ] Clear the plan with C. Fire. After the shot, the plan is still empty (no spurious entries appear).
- [ ] After firing with a retained plan, move the player with WASD. The preview updates in real time using the retained plan at the new position.
- [ ] Fire a shot that breaks a planned mirror (state change → null). Observe the preview with the retained plan. The broken mirror's entry appears dimmed. Fire again. The arrow ignores the broken mirror.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| UX3 | Preview matches flight | Inherited | Inherited |
| UX4 | Determinism | Inherited | Inherited |
| UX5 | Undo fully restores (including plan) | Inherited, checkpoint includes plan | Inherited |
| UX7 | Solid path leads from player to cursor | Visual: preview after shot | Inherited |

### Regression Checklist

| Category | Prior Stage | Behavior | How to Verify |
|----------|-------------|----------|---------------|
| **Math** | Stages 4--20 | All math and trace systems | Run GUT tests |
| **Visual** | Stages 5, 21--30 | Preview rendering | Observe preview |
| **Interaction** | Stage 31 | Arrow flight with plan | Fire with plan |
| **Interaction** | Stage 32 | Checkpoint undo/reset | Press Z/R after firing |
| **Interaction** | Stages 25--26 | Plan add/remove | Click surfaces |

### Expected Visual State

After a shot, the scene updates (player may have a new position, surfaces may have changed state), but the plan overlay remains. The preview immediately shows the planned trajectory from the current player position with the current plan. If a planned surface changed behavior due to a state change, the preview reflects the new effect (e.g., a broken mirror no longer reflects).

### Feedback Loop Protocol

See standard protocol at top of document.

### Validation Summary (filled in after implementation)

| Check | Status | Notes |
|-------|--------|-------|
| All unit tests pass | [ ] | |
| All prior regression tests pass | [ ] | |
| User interactive sign-off | [ ] | |
| Failing interactive tests automated | [ ] | |
| Stage complete | [ ] | |

### Files Modified/Created

| File | Action | Purpose |
|------|--------|---------|
| `scripts/game/game_manager.gd` | Modify | Remove plan-clearing logic after shot completion |
| `scripts/visual/path_renderer.gd` | Modify | Ensure preview recalculates after shot with retained plan |
| `tests/test_stage33_plan_retained.gd` | Create | Plan retention unit tests |

---

## Appendix A: Invariant Introduction Map (Status After Stage 33)

| Invariant | Full ID | Introduced | First Testable | Fully Testable | Status After Stage 33 |
|-----------|---------|-----------|----------------|----------------|----------------------|
| Carrier <-> via round-trip | S1 | Stage 8 | Stage 8 | Stage 65 | Tested (line + circle) |
| Transform round-trip | S2 | Stage 20 | Stage 20 | Stage 65 | Tested (rotation, reflection) |
| Determinism | S3 | Stage 14 | Stage 14 | Stage 65 | Tested |
| Divergence monotonic | S4 | Stage 26 | Stage 26 | Stage 65 | Tested |
| Aligned provenance | S5 | Stage 25 | Stage 25 | Stage 65 | Tested |
| Aligned match | S6 | Stage 25 | Stage 25 | Stage 65 | Tested |
| Per-entry state | S7 | -- | -- | Stage 54+ | Not yet introduced |
| Forward-first ordering | S8 | Stage 11 | Stage 11 | Stage 65 | Tested |
| Exclusion respected | S9 | Stage 16 | Stage 16 | Stage 65 | Tested |
| Projective resets frame | S10 | -- | -- | Stage 47+ | Not yet introduced |
| Three points on carrier | S11 | Stage 7 | Stage 7 | Stage 65 | Tested |
| Side determination | S12 | Stage 7 | Stage 7 | Stage 65 | Tested |
| Visibility no self-intersect | S13 | -- | -- | Stage 34a+ | Not yet introduced |
| Visibility edges on geometry | S14 | -- | -- | Stage 34a+ | Not yet introduced |
| Visibility non-overlapping | S15 | -- | -- | Stage 34a+ | Not yet introduced |
| No NaN/Inf in output | S16 | Stage 4 | Stage 4 | Stage 65 | Tested (Direction, Ray, Mobius) |
| Provenance IDs unique | S17 | Stage 8 | Stage 8 | Stage 65 | Tested (Points + Transform IDs) |
| Frame determinant non-zero | S18 | Stage 20 | Stage 20 | Stage 65 | Tested (construction + composition) |
| Trace preserves real state | S19 | -- | -- | Stage 53+ | Not yet introduced |
| Visibility predicts non-div. | UX1 | -- | -- | Stage 36+ | Not yet introduced |
| Divergence -> outside vis. | UX2 | -- | -- | Stage 36+ | Not yet introduced |
| Preview matches flight | UX3 | Stage 17 | Stage 17 | Stage 65 | Tested (with and without plan) |
| Same shot = same result | UX4 | Stage 17 | Stage 17 | Stage 65 | Tested (with and without plan) |
| Undo fully restores | UX5 | Stage 32 | Stage 32 | Stage 65 | Tested (position, velocity, state, plan, targets_hit) |
| All targets reachable | UX6 | -- | -- | Stage 55+ | Not yet introduced |
| Solid path to cursor | UX7 | Stage 5 (partial) | Stage 5 | Stage 65 | Tested (line + reflection) |
| Block stops arrow | UX9 | Stage 13 | Stage 13 | Stage 65 | Tested |
| State changes visible | UX10 | -- | -- | Stage 57+ | Not yet introduced |
| Empty plan = fire straight | UX11 | Stage 5 (partial) | Stage 15 | Stage 65 | Tested |

---

## Appendix B: Cumulative Test Count After Stage 33

| Category | Count |
|----------|-------|
| Unit tests (Stages 1--30) | ~180 (estimated from prior documents) |
| Unit tests (Stage 31) | 9 |
| Unit tests (Stage 32) | 12 |
| Unit tests (Stage 33) | 8 |
| **Total unit tests** | **~209** |
| Interactive test items (Stages 1--30) | ~85 (estimated) |
| Interactive test items (Stages 31--33) | 20 |
| **Total interactive test items** | **~105** |
| Invariants actively tested | 14 (S1, S2, S3, S4, S5, S6, S8, S9, S11, S12, S16, S17, S18, UX5) |
| Invariants partially covered | 2 (UX7, UX11) |
| Invariants newly testable this document | 1 (UX5) |
| Invariants not yet introduced | 10 (S7, S10, S13, S14, S15, S19, UX1, UX2, UX6, UX10) |
