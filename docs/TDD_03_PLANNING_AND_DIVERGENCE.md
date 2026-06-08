# TDD Document 3: Planning and Divergence

**Stages 19–30** | Surfaces with effects, plan construction, image chains, step tree merge, divergence, all 5 step types

### Stage Status

| Stage | Topic | Status |
|-------|-------|--------|
| 19 | Single non-interactive pass-through surface | Done |
| 20a | MobiusTransform full implementation | Done |
| 20b | Reflective surface (one side) | Done |
| 21 | Multi-bounce physical trace | Done |
| 22 | Plan construction UI (click to add) | Done |
| 23 | Plan removal UI (right-click/clear) | Done |
| 24 | Planned trace (single reflection) | Done |
| 25 | Step tree merge (aligned case) | Done |
| 26 | Divergence detection | Done |
| 27 | Internal blocking surface | Done |
| 28 | All five step types rendered | Done |
| 29 | ~~Bypass computation~~ | Removed |
| 30 | Multi-surface reflection chain | Done |

**Regression Test Policy:** After implementing Stage N, run ALL tests from Stages 1 through N. The full test suite must pass before proceeding to Stage N+1. No exceptions.

**Feedback Loop Protocol (applies to every stage):**
1. AI implements the stage (code + unit tests).
2. AI runs all unit tests (new + all prior). All must pass.
3. User performs interactive tests from the checklist.
4. User provides feedback (pass/fail per item + notes on unexpected behavior).
5. AI converts any failing interactive tests into automated tests.
6. AI applies fixes and re-runs all tests.
7. Repeat steps 3–6 until all checks pass.
8. Stage is marked complete. Proceed to next stage.

**USER VALIDATION GATE (MANDATORY)**

No stage is complete until the user has personally verified every interactive test item and provided explicit sign-off. After every behavioral feature (not just infrastructure), the user must SEE the behavior working in the running game before the stage is marked complete.

1. User MUST test every interactive test item marked with `[ ]`.
2. User MUST provide written pass/fail feedback for EACH item.
3. Any "fail" or "unexpected behavior" becomes a NEW automated test before proceeding.
4. AI MUST NOT proceed to the next stage until ALL interactive items are `[x]`.
5. The user's word is final. If the user says it doesn't look right, it doesn't ship.

---

## Prior-Stage Summary (Stages 1–18)

By Stage 18, the following systems exist and are tested:

- **Project skeleton:** Godot 4.6 project with GUT testing framework, directory structure (`scripts/math/`, `scripts/visual/`, `scripts/game/`, `tests/`).
- **Player:** `CharacterBody2D` with WASD movement at 200 u/s, instant response, no gravity. Spawns at (960, 540).
- **Cursor:** World-space mouse tracking via `get_global_mouse_position()`.
- **Math layer:** `Direction`, `Ray`, `GeneralizedCircle`, `Segment` (three-point with carrier derivation and side determination), `Point` (with provenance and unique ID), `TransformCache` (provenance-keyed bidirectional store).
- **Intersection system:** `intersect_line_with_gcircle` (line-line and line-circle cases), segment bounds filtering, side determination at hit point.
- **Hit selection:** `HitRecord`, `find_earliest_hit` (forward/beyond partition, tie-breaking by surface ID, exclusion via `excluded_surfaces`).
- **Surface system:** `Surface` (segment + policy), `SideConfig` (effect + state_change + interactive flag), `FixedResolver`.
- **Effects:** `TerminalEffect` (block) — stops the ray.
- **Room boundaries:** 4 block surfaces forming a rectangular room (red, terminal both sides).
- **Physical trace loop:** Up to 256 hits, pass-through handling (null effect advances ray, adds to exclusion set), block terminates.
- **Preview rendering:** Green solid line from player to cursor, green dashed line from cursor to wall (physical continuation).
- **Arrow shooting:** Spacebar fires, game freeze (`get_tree().paused`), arrow animates at 800 u/s along traced path, skip via any non-movement key.
- **Tested invariants:** S1, S3, S8, S9, S11, S12, S16, S17, UX3, UX4, UX7 (partial), UX9, UX11 (partial).

---

## Stage 19: Single Non-Interactive Pass-Through Surface

### Overview
Add the first interior surface — a pass-through surface placed inside the room with null effect on both sides. This establishes surface rendering for non-boundary surfaces, the gray pass-through color per §22.2, and confirms that the trace loop handles interior pass-through surfaces correctly (the arrow passes through, the hit is recorded, and tracing continues). Both sides are non-interactive, meaning the surface cannot be added to a plan.

### Prerequisites
Stage 18 (physical trace loop with pass-through handling, room boundaries, arrow shooting).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Surface | Interior pass-through surface with null effect both sides | §9.1, §10.1 |
| Rendering | Gray surface color for pass-through type | §22.2 |
| Rendering | Two-tone surface rendering (both sides gray for pass-through) | §22.3 |
| Behavior | `interactive=false` on both sides (cannot be added to plan) | §9.1 |
| Behavior | Arrow passes through interior surface, trace records hit, continues | §10.1, §12.1 |

### Unit Tests Added

1. **`test_stage19_passthrough_surface_construction`**: Create a surface with null effect on both sides. Input: segment inside room bounds. Expected: `left.effect == null`, `right.effect == null`, `left.interactive == false`, `right.interactive == false`. Validates: §9.1 pass-through defaults.
2. **`test_stage19_trace_through_passthrough`**: Trace a ray that intersects the pass-through surface. Input: player at (100, 300), cursor at (800, 300), pass-through surface at x=400. Expected: trace produces at least 2 steps — one ending at the pass-through (x=400), one continuing past it. The trace does NOT stop at the pass-through. Validates: §10.1 null effect behavior.
3. **`test_stage19_passthrough_hit_recorded`**: The hit at the pass-through surface is recorded in the trace's step array. Input: same as test 2. Expected: one of the steps has `hit.surface` matching the pass-through surface. Validates: pass-through produces a step (not silently skipped).
4. **`test_stage19_passthrough_exclusion`**: After passing through the surface, the ray does not immediately re-hit the same surface. Input: ray perpendicular to the surface. Expected: the surface appears exactly once in the hit sequence for that traversal. Validates: §12.1 exclusion mechanism (S9).
5. **`test_stage19_passthrough_not_interactive`**: Both sides of the pass-through surface have `interactive == false`. Validates: §9.1 — null-effect sides must be non-interactive.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Press Play. A gray line/arc appears inside the room, distinct from the red boundary walls.
- [ ] Aim the cursor so the green preview line crosses the gray surface. The green line passes through the gray surface without stopping — both the solid line (to cursor) and dashed line (past cursor) are visible through it.
- [ ] Fire an arrow through the pass-through surface. The arrow passes through without stopping, continuing to the far wall.
- [ ] Observe that the arrow animation shows a brief pass through the gray surface (no bounce event, just smooth continuation).
- [ ] Confirm the gray surface has two parallel lines (left and right side indicators per §22.3), both gray.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S9 | Exclusion respected — pass-through surface excluded after traversal | Unit test: surface not re-hit immediately | Inherited |
| UX9 | Block surfaces stop the arrow (boundary walls still block) | Fire at wall, observe stop | Inherited |
| S8 | Forward-first hit ordering | Unit test: pass-through hit has correct t ordering | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 18 | Arrow shooting: fire, freeze, animate, skip | Press Spacebar, observe |
| Stage 17 | Preview: green solid to cursor, green dashed past cursor | Move mouse |
| Stage 15 | Physical trace loop handles pass-through and block | GUT tests |
| Stage 13 | Room boundaries block the arrow | Fire at wall |
| Stage 8 | Cache round-trip (S1) | GUT tests |
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

Dark background. Red rectangular room boundaries. A gray interior surface (two parallel gray lines with 2px offset per §22.3) positioned inside the room. Player triangle. Crosshair cursor. Green solid line from player to cursor; green dashed line from cursor to the far wall. If the preview line crosses the gray surface, it passes through without interruption.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/game/level_setup.gd` | Modify | Add interior pass-through surface to the scene |
| `scripts/visual/surface_renderer.gd` | Modify | Add gray color rendering for pass-through surfaces, two-tone side indicator |
| `tests/test_stage19_passthrough.gd` | Create | Pass-through surface unit tests |

---

## Stage 20a: MobiusTransform Full Implementation

### Overview
Implement the complete MobiusTransform class — the most mathematically complex class in the project. This includes the struct definition, complex number helpers, point application (conformal and anti-conformal), the 4-case composition table, matrix inversion, carrier transformation, and globally unique transform IDs. This deserves its own testable increment before any effects use it.

### Prerequisites
Stage 19 (pass-through surface exists, providing context for future effects).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/mobius_transform.gd` — MobiusTransform class with alpha, beta, gamma, delta, conjugating flag | §5.2 |
| Script | `scripts/math/mobius_transform.gd` — Full MobiusTransform: struct with a_re/a_im/b_re/b_im/c_re/c_im/d_re/d_im/conjugating | §5.2 |
| Method | `MobiusTransform.apply(point) -> Vector2` — conformal and anti-conformal application | §5.2 |
| Method | `MobiusTransform.compose(other) -> MobiusTransform` — 4-case composition table | §5.2 |
| Method | `MobiusTransform.invert() -> MobiusTransform` — matrix inversion, conjugating preserved | §5.2 |
| Method | `MobiusTransform.transform_carrier(carrier) -> GeneralizedCircle` — Hermitian form | §5.2 |
| Static | Complex helpers: `cmul`, `cconj`, `cdiv`, `cmod2` | §5.3 |
| Property | Transform IDs via global counter, identity ID=0 | §17.3 |
| Constant | `MobiusTransform.IDENTITY` — identity transform | §5.2 |

### Unit Tests Added

1. **`test_stage20a_cmul`**: Complex multiply `(3+4i)(1+2i) = -5+10i`. Validates: §5.3.
2. **`test_stage20a_cconj`**: `conj(3+4i) = 3-4i`. Validates: §5.3.
3. **`test_stage20a_cdiv`**: `(3+4i)/(1+2i) = 2.2-0.4i`. Validates: §5.3.
4. **`test_stage20a_cmod2`**: `|3+4i|² = 25`. Validates: §5.3.
5. **`test_stage20a_apply_conformal`**: Identity transform applied to (5, 3) returns (5, 3). Rotation by π/2 applied to (1, 0) returns (0, 1). Validates: §5.2.
6. **`test_stage20a_apply_anticonformal`**: Reflection across x-axis applied to (3, 4) returns (3, -4). Validates: §5.2.
7. **`test_stage20a_compose_conformal_conformal`**: Two rotations compose correctly. Result is conformal. Validates: §5.2 composition table row 1.
8. **`test_stage20a_compose_conformal_anticonformal`**: Rotation composed with reflection. Result is anti-conformal. Validates: §5.2 composition table row 2.
9. **`test_stage20a_compose_anticonformal_conformal`**: Reflection composed with rotation (M1 × conj(M2)). Result is anti-conformal. Validates: §5.2 composition table row 3.
10. **`test_stage20a_compose_anticonformal_anticonformal`**: Two reflections compose. Result is conformal. Validates: §5.2 composition table row 4.
11. **`test_stage20a_invert_identity`**: Inverse of identity is identity. Validates: §5.2.
12. **`test_stage20a_compose_with_inverse`**: `compose(M, M.invert())` produces identity (transform ID matches). Validates: §5.2.
13. **`test_stage20a_S18_determinant_nonzero`**: For the reflection Möbius matrix: `|αδ - βγ|² > 0`. Validates: S18.
14. **`test_stage20a_transform_id_unique`**: Create 100 MobiusTransforms. All IDs are distinct. Validates: S17.
15. **`test_stage20a_identity_id_preserved`**: After full MobiusTransform implementation, verify `MobiusTransform.IDENTITY.id == 0`. This is a contract test ensuring Stages 14-19's assumption (frame_id=0 means identity) is preserved. Validates: forward dependency from Stage 14.
16. **`test_stage20a_composition_drift_cycle`**: Compose N reflections in a cycle (reflecting across 4 lines forming a rectangle, cycling back to start). Measure deviation from identity for N=4 (expect < 1e-10), N=16 (bounded drift), N=64 (finite, non-NaN). Validates: §31.5 frame composition stability for long chains.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] No visual change expected. Press Play and verify the game still runs identically to Stage 19.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S18 | Frame determinant non-zero — `|αδ - βγ|² > 0` for reflection Möbius matrix | Unit test | Yes |
| S16 | No NaN/Inf in output | Unit test | Inherited |
| S1 | Cache: carrier round-trip | GUT tests | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 19 | Pass-through surface: gray rendering, arrow passes through | Visual + fire through |
| Stage 18 | Arrow shooting works | Press Spacebar |
| Stage 17 | Preview rendering (green solid + green dashed) | Move mouse |
| Stage 15 | Physical trace loop handles pass-through and block | GUT tests |
| Stage 13 | Room boundaries block the arrow | Fire at wall |
| Stage 8 | Cache S1 round-trip | GUT tests |
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

No visual change from Stage 19. Dark background. Red rectangular room boundaries. Gray interior pass-through surface. Player triangle. Crosshair cursor. Green preview lines. The MobiusTransform class is implemented but not yet used by any effect or renderer.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/math/mobius_transform.gd` | Modify (full implementation) | MobiusTransform class (alpha, beta, gamma, delta, conjugating, apply, compose, invert, transform_carrier, complex helpers, IDENTITY, transform IDs) |
| `tests/test_stage20a_mobius_transform.gd` | Create | MobiusTransform unit tests |

---

## Stage 20b: Reflective Surface (One Side)

### Overview
Add a surface with left=Reflection, right=null(pass-through). Implement ReflectionEffect using the MobiusTransform class from Stage 20a. This introduces `ReflectionEffect` with its Mobius matrix (§10.8), two-tone surface rendering (blue for reflection side, gray for pass-through side with 50% opacity for the non-interactive side), and physical trace behavior where approaching from the left causes a bounce while approaching from the right passes through. This is the foundational transformative effect upon which all planning depends.

### Prerequisites
Stage 20a (full MobiusTransform).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/effects/reflection_effect.gd` — ReflectionEffect implementing TransformativeEffect | §10.2, §10.8 |
| Interface | `TransformativeEffect` — `get_mobius()`, `get_inverse_mobius()` | §10.1 |
| Surface | Interior surface with left=Reflection, right=null | §9.1 |
| Rendering | Two-tone surface: blue (left/reflection) + gray (right/pass-through) with 2px offset | §22.2, §22.3 |
| Rendering | Non-interactive side at 50% opacity | §22.3 |
| Behavior | `interactive=true` on left (reflection side), `interactive=false` on right (pass-through side) | §9.1 |
| Behavior | Physical trace: left approach bounces, right approach passes through | §10.2, §12.1 |

### Unit Tests Added

1. **`test_stage20b_reflection_mobius_construction`**: For carrier `x=200` (coefficients b=1, c=0, d=-200), construct the reflection Mobius matrix. Let `n = 1 + 0i = 1`, `norm² = 1`. Expected: `alpha = -conj(n) = -1`, `beta = -2*(-200)*conj(n)/1 = 400`, `gamma = 0`, `delta = n = 1`, `conjugating = true`. Validates: §10.8 formula.
2. **`test_stage20b_reflection_self_inverse`**: Apply reflection Mobius to a point P, then apply it again. Expected: result equals P (same position). Reflection is self-inverse. Validates: §10.8 self-inverse property.
3. **`test_stage20b_S2_transform_roundtrip`**: Create a Point, transform via `get_mobius()`, then transform via `get_inverse_mobius()`. Expected: result has same Point ID as original (exact round-trip via cache). Validates: S2.
4. **`test_stage20b_reflection_known_point`**: Reflect point (300, 250) across line x=200. Expected: (100, 250). Validates: reflection produces correct geometric result.
5. **`test_stage20b_reflection_on_carrier`**: Reflect a point that lies on the carrier line (200, 300) across x=200. Expected: (200, 300) — point maps to itself. Validates: fixed point of reflection.
6. **`test_stage20b_trace_bounces_from_left`**: Trace a ray approaching the reflective surface from the left side. Input: player at (100, 300), cursor at (300, 300), mirror at x=200. Expected: trace hits the mirror and the next step starts from the reflected point. The ray changes direction. Validates: §10.2 reflection behavior.
7. **`test_stage20b_trace_passes_through_from_right`**: Trace a ray approaching the reflective surface from the right side (the pass-through side). Expected: ray passes through without bouncing. Validates: right side is null effect.
8. **`test_stage20b_side_config_interactive`**: The left side (reflection) has `interactive=true`. The right side (null) has `interactive=false`. Validates: §9.1 defaults.
9. **`test_stage20b_S12_side_at_hit`**: The hit record from a left-side approach records `side == LEFT`. A right-side approach records `side == RIGHT`. Validates: S12 consistency.
10. **`test_stage20b_conjugating_flag`**: `ReflectionEffect.get_mobius().conjugating == true`. Validates: §10.8 anti-conformal property.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Press Play. A two-tone surface appears inside the room: one side blue (reflection), other side gray (pass-through).
- [ ] The gray side appears dimmer than the blue side (50% opacity per §22.3).
- [ ] Aim from the blue (left/reflection) side. The dashed preview line past the cursor shows the reflected direction — it bounces off the surface.
- [ ] Aim from the gray (right/pass-through) side. The dashed preview line passes through the surface without bouncing.
- [ ] Fire an arrow from the blue side. The arrow bounces off the surface and continues in the reflected direction.
- [ ] Fire an arrow from the gray side. The arrow passes through the surface without bouncing.
- [ ] Move the player so it is between the pass-through surface from Stage 19 and the reflective surface. Fire through both. The arrow passes through the gray surface and bounces off the blue side of the mirror.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S2 | Transform round-trip — reflection is self-inverse, cache returns exact original Point | Unit test | Yes |
| S12 | Side determination consistent at hit point | Unit test | Inherited |
| S9 | Exclusion respected (pass-through side) | Unit test | Inherited |
| UX9 | Block surfaces stop the arrow (boundaries) | Fire at wall | Inherited |
| S16 | No NaN/Inf in output | Unit test: reflection of finite points produces finite results | Inherited |
| S1 | Cache: carrier round-trip | GUT tests | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 20a | MobiusTransform: complex helpers, apply, compose, invert, transform_carrier, IDs | GUT tests |
| Stage 19 | Pass-through surface: gray rendering, arrow passes through | Visual + fire through |
| Stage 18 | Arrow shooting works | Press Spacebar |
| Stage 17 | Preview rendering (green solid + green dashed) | Move mouse |
| Stage 15 | Physical trace loop handles pass-through and block | GUT tests |
| Stage 13 | Room boundaries block the arrow | Fire at wall |
| Stage 8 | Cache S1 round-trip | GUT tests |
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

Dark background. Red boundary walls. Gray pass-through surface (from Stage 19). A new two-tone surface: blue on the reflection side, gray (dimmed) on the pass-through side, with 2px offset between them. Green preview line. When aiming from the blue side, the dashed continuation bounces off the mirror.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/math/effects/reflection_effect.gd` | Create | ReflectionEffect implementing TransformativeEffect interface |
| `scripts/math/effects/transformative_effect.gd` | Create | TransformativeEffect interface (get_mobius, get_inverse_mobius) |
| `scripts/game/level_setup.gd` | Modify | Add reflective surface to the scene |
| `scripts/visual/surface_renderer.gd` | Modify | Add blue color for reflection, 50% opacity for non-interactive side |
| `tests/test_stage20b_reflection.gd` | Create | Reflection and surface behavior unit tests |

---

## Stage 21: Multi-Bounce Physical Trace

### Overview
Extend the physical trace loop to handle reflection as a transformative effect: after a reflection hit, the Mobius frame composes with the reflection's Mobius matrix, the ray origin advances to `T_inverse(hit_point)`, and tracing continues with the updated frame. Since reflection is self-inverse, `T_inverse(hit_point) = reflect(hit_point)`. The Direction stays the same through transformative effects (§10.7). Multiple bounces are now visible in the dashed preview past the cursor.

### Prerequisites
Stage 20b (ReflectionEffect, MobiusTransform with compose and apply).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Behavior | Trace loop: transformative effect branch — frame composition `M' = M.compose(T)` | §12.1, §12.4 |
| Behavior | Origin advance: `origin = T_inverse(hit_point)` after transformative hit | §12.4 |
| Behavior | Direction unchanged through transformative effects | §10.7 |
| Behavior | Multiple reflections visible in dashed preview | §12.1 |
| Function | `transform_all(surfaces: Array[Surface], frame_inverse: MobiusTransform) -> Array[Surface]` — transforms each surface's segment into the normalized frame | §12.1 |

### Unit Tests Added

1. **`test_stage21_frame_composes_on_reflection`**: After one reflection hit, the trace's active frame is `IDENTITY.compose(reflection_mobius)`, not IDENTITY. Input: trace through a single mirror. Expected: frame after the reflection step is the reflection's Mobius matrix. Validates: §12.4.
2. **`test_stage21_origin_advances_to_inverse_hit`**: After reflection, the new ray origin is `reflect(hit_point)` across the carrier. Input: hit at (200, 300) on mirror x=200. Expected: new origin = reflect((200, 300)) = (200, 300) (point on the mirror maps to itself). For a hit at (200, 300) with ray continuing, the post-reflection ray origin is `T_inverse(200, 300)`. Validates: §12.4.
3. **`test_stage21_direction_unchanged`**: After a transformative hit, `ray.direction` is the same Direction object as before the hit. Validates: §10.7.
4. **`test_stage21_double_bounce`**: Place two parallel mirrors. Trace a ray that bounces off both. Input: mirrors at x=200 and x=600, player at (100, 300), cursor past both. Expected: trace has at least 3 segments (origin→mirror1, mirror1→mirror2, mirror2→wall). Validates: multi-bounce trace loop.
5. **`test_stage21_bounce_angles_correct`**: For a ray hitting mirror x=200 at 45 degrees, the reflected ray continues at 45 degrees on the other side. Input: player at (100, 200), ray direction toward (200, 300). Expected: after reflection, the ray proceeds toward (100, 400) (symmetric reflection). Validates: geometric correctness of reflection.
6. **`test_stage21_preview_shows_multi_bounce`**: The dashed preview past the cursor shows the bounced path through multiple reflections, not just a straight line. Validates: visual system correctly renders post-reflection trace.
7. **`test_stage21_transform_all_identity`**: `transform_all` with identity frame returns surfaces with unchanged geometry. Validates: baseline.
8. **`test_stage21_transform_all_reflection`**: `transform_all` with reflection frame transforms each surface's three points (start, end, via) through the reflection. Carrier is recomputed. Validates: §12.1.
9. **`test_stage21_transform_all_preserves_cache`**: After `transform_all`, deriving via from the transformed carrier returns a point with the correct provenance chain back to the original. Validates: S1 through transformation.
10. **`test_stage21_transform_all_line_stays_line`**: Line carrier transformed by conformal transform (rotation) stays a line. Validates: carrier type preservation under conformal transforms.
11. **`test_stage21_transform_all_line_stays_line_reflection`**: Line carrier transformed by anti-conformal transform (reflection) stays a line. Validates: reflection preserves line carriers. *(The line-becomes-circle test under inversion is moved to Stage 42 where CircleInversionEffect exists.)*
12. **`test_stage21_transform_all_via_consistent`**: After `transform_all`, the transformed `via` point lies on the transformed carrier (S11 holds on transformed geometry). Validates: via consistency through transformation.
13. **`test_stage21_direction_shared_within_subchain`**: Trace through two consecutive reflective surfaces. Expected: the Direction object (by reference identity) is the SAME across all steps within the transformative sub-chain. Validates: §8.2 "Shared across all ray propagation steps within a transformative sub-chain."
14. **`test_stage21_multi_bounce_perf_gate`**: Set up a room with 6 surfaces. Compute a 3-bounce trace + preview. Measure time via `Time.get_ticks_usec()`. Expected: < 10ms. This is a HARD pass/fail — if it fails, the trace architecture has an O(N^2) or worse problem that must be fixed before adding more complexity. Validates: architectural viability for §30.1 performance budget.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Place cursor between the player and the mirror. The dashed preview past the cursor shows the ray bouncing off the mirror and continuing.
- [ ] Place cursor on the far side of the mirror. The green solid preview bends at the mirror (this may not work yet since planned trace is not implemented — the physical trace handles this). The green dashed continuation past the cursor shows further bounces.
- [ ] With two mirrors in the scene, aim so the ray bounces between them. Multiple bounce segments are visible in the dashed preview.
- [ ] Fire an arrow that bounces off one mirror. The arrow visually changes direction at the bounce point.
- [ ] Fire an arrow that bounces off two mirrors in sequence. Both bounces are animated correctly.
- [ ] Confirm boundary walls still block the arrow after all bounces.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S2 | Transform round-trip (through composed frames) | Unit test | Inherited |
| S12 | Side determination at each bounce | Unit test | Inherited |
| UX9 | Block surfaces stop the arrow after bounces | Fire through mirrors toward wall | Inherited |
| S3 | Determinism: same input → same multi-bounce trace | Fire same shot twice | Inherited |
| S16 | No NaN/Inf in output after multiple reflections | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 20b | Single reflection: blue side bounces, gray side passes through | Fire from each side |
| Stage 19 | Pass-through surface works | Fire through gray surface |
| Stage 18 | Arrow shooting (fire, freeze, animate, skip) | Press Spacebar |
| Stage 17 | Preview: green solid + green dashed | Move mouse |
| Stage 13 | Room boundaries block | Fire at wall |
| Stage 8 | Cache S1 round-trip | GUT tests |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

Same as Stage 20b, but now the dashed green preview line past the cursor bends at mirror surfaces — each bounce is visible as a change in direction. When a ray bounces between two mirrors, the dashed line zigzags. The arrow animation follows these bounces.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/math/tracer.gd` | Modify | Add TransformativeEffect branch to trace loop (frame compose, origin advance, direction unchanged) |
| `scripts/visual/path_renderer.gd` | Modify | Render multi-segment dashed preview with frame-transformed segments |
| `tests/test_stage21_multi_bounce.gd` | Create | Multi-bounce trace unit tests |

---

## Stage 22: Plan Construction UI (Click to Add)

### Overview
Implement plan construction via left-click on interactive surface sides. The player can click near an interactive surface side (within 8px tolerance) to append `{surface_id, side}` to the plan array. Side is determined by which side of the carrier the cursor is on. Non-interactive sides cannot be clicked. Planned surfaces show numbered overlays ("1", "2", ...) and the plan is displayed in the HUD as a simple text list. This is the first step toward the full planning system.

### Prerequisites
Stage 21 (reflective surfaces exist with interactive sides to click on).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/game/plan_manager.gd` — manages the plan array, add/remove/clear operations | §4.2 |
| Behavior | Left-click on interactive surface side: append `{surface_id, side}` to plan | §4.2 |
| Behavior | Click detection within 8px tolerance (UI-layer) | §4.2 |
| Behavior | Side determined by cursor position relative to surface carrier | §4.2, §9.2 |
| Behavior | When multiple surfaces within tolerance, nearest wins | §4.2 |
| Behavior | Non-interactive sides cannot be clicked (filtered) | §4.2 |
| Behavior | Plan entries reference surface by ID, not object reference | §4.2, §9.3 |
| Rendering | Numbered overlay on planned surfaces ("1", "2", ...) | §22.2 |
| Rendering | Plan list in HUD (simple text list) | §4.2 |
| Behavior | When cursor hovers within 8px of an interactive surface side, that side highlights | §4.2 |
| Behavior | When cursor is exactly on the surface carrier (`f(P) = 0`), side determined by previous cursor position; default LEFT if no previous | §4.2 |
| Behavior | When multiple surfaces coincide geometrically within tolerance, repeated clicks cycle through them by surface ID order | §4.2 |
| Behavior | For arc segments, nearest click point found by projecting cursor onto carrier circle, then clamping to arc bounds (§11.1) | §4.2 |

### Unit Tests Added

1. **`test_stage22_plan_add_entry`**: Call `plan_manager.add_entry(surface_id, side)`. Expected: plan array has one entry with matching `surface_id` and `side`. Validates: basic plan construction.
2. **`test_stage22_plan_preserves_order`**: Add entries A, B, C in order. Expected: `plan[0]` is A, `plan[1]` is B, `plan[2]` is C. Validates: plan is ordered list.
3. **`test_stage22_non_interactive_rejected`**: Attempt to add a non-interactive side to the plan. Expected: plan remains empty (entry not added). Validates: §4.2 interactive filtering.
4. **`test_stage22_side_determination_by_cursor`**: Cursor at (150, 300) relative to mirror at x=200. Expected: side is LEFT (cursor is on the left side of the carrier). Cursor at (250, 300): side is RIGHT. Validates: §4.2 + §9.2.
5. **`test_stage22_duplicate_entries_allowed`**: Add the same surface side twice. Expected: plan has two entries with the same surface_id and side. Validates: §4.2 — duplicates are allowed.
6. **`test_stage22_entry_references_by_id`**: Plan entry stores `surface_id` (int), not a direct object reference. Validates: §4.2, §9.3.
7. **`test_stage22_nearest_surface_wins`**: Two surfaces within 8px of click position. Expected: the nearest one is selected. Validates: §4.2 multiple-surface tiebreaking.
8. **`test_stage22_click_outside_tolerance_ignored`**: Click 20px away from any surface. Expected: plan is unchanged. Validates: 8px tolerance.
9. **`test_stage22_hover_highlight`**: Move cursor within 8px of the blue (reflection) side of a surface. Expected: that side's rendering shows a highlight indicator. Move cursor away. Expected: highlight disappears. Validates: §4.2.
10. **`test_stage22_cursor_on_carrier_fallback`**: Cursor position exactly on the surface carrier (`evaluate` returns 0). Previous cursor position was on the LEFT side. Expected: side determination returns LEFT (uses previous position). Validates: §4.2.
11. **`test_stage22_cursor_on_carrier_no_previous`**: Cursor starts exactly on carrier, no previous position recorded. Expected: side defaults to LEFT. Validates: §4.2.
12. **`test_stage22_click_cycling_coincident`**: Two surfaces at the same geometric position. First click selects lower-ID surface. Second click (same position) selects higher-ID surface. Third click cycles back to the lowest-ID surface (wrap-around — after the highest-ID surface, the next click returns to the lowest-ID). Validates: §4.2.
13. **`test_stage22_arc_click_detection`**: Arc surface in scene. Click near the arc (within 8px). Expected: nearest point computed by projecting cursor onto carrier circle, clamped to arc bounds via cross-product containment test (§11.1). The correct surface is selected and added to plan. Validates: §4.2 arc click handling.
14. **`test_stage22_arc_click_outside_bounds`**: Click near the carrier circle but outside the arc segment's angular span. Expected: click does NOT select the arc surface (projection falls outside arc bounds). Validates: arc bounds clamping.
15. **`test_stage22_click_cycling_resets_on_move`**: Two coincident surfaces. Click → selects surface A. Move cursor away (>8px). Move cursor back. Click → selects surface A again (not B — cycle reset). Validates: §4.2 cycling resets when cursor leaves tolerance band.
16. **`test_stage22_fire_during_pending_arc_click`**: Start arc surface plan-click sequence (e.g., 1 of 3 clicks done for an arc). Press Spacebar (Fire). Expected: the pending click operation is cancelled and the fire action executes normally. Validates: input interaction between plan construction and fire.
17. **`test_stage22_major_arc_click_detection`**: Arc surface spanning >180 degrees (major arc). Click within 8px of the major arc. Expected: nearest point correctly computed on the major arc (not the minor arc of the same carrier circle). Validates: §4.2 + §11.1 major arc handling in click detection.
18. **`test_stage22_right_click_during_pending_arc`**: Start arc placement (1 of 3 clicks done). Right-click. Expected: pending arc placement cancelled. Right-click's normal behavior (remove/clear plan) also executes. Validates: input interaction during multi-click operations.
19. **`test_stage22_clear_during_pending_line`**: Start line placement (1 of 2 clicks done). Press C (clear plan). Expected: pending line placement cancelled. Plan cleared. Validates: C key cancels pending operations.
20. **`test_stage22_undo_during_pending_click`**: Start arc placement. Press Z (undo). Expected: pending placement cancelled. Undo applies to the last completed action. Validates: Z key during pending operations.
21. **`test_stage22_plan_add_blocked_during_flight`**: During arrow flight, left-click on an interactive surface. Expected: the surface is NOT added to the plan. Plan is unchanged. Validates: plan inputs remain blocked during flight after the plan system exists (re-validates Stage 18's vacuously passing tests).

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Left-click on the blue (reflection) side of the mirror. A "1" label appears on the surface. The HUD shows "Plan: [1. Mirror (left)]" or similar text.
- [ ] Left-click on the same surface again (from the same side). A "2" label appears. The HUD shows two entries. Validates: duplicate entries allowed.
- [ ] Attempt to left-click on the gray (pass-through) side of the mirror. Nothing happens — the side is non-interactive.
- [ ] Attempt to left-click on the gray pass-through surface from Stage 19. Nothing happens — both sides are non-interactive.
- [ ] Attempt to left-click on a red boundary wall. Nothing happens — terminal sides default to non-interactive.
- [ ] Click more than 8 pixels away from any surface. Nothing happens.
- [ ] Click close to the blue side of the mirror (within 8px). The plan entry is added with the correct side based on cursor position relative to the carrier.
- [ ] Move the cursor near the blue side of the mirror (within 8px). The side highlights to indicate clickability. Move away — highlight disappears.

**Note:** Arc click detection tests (tests 13-14) use manually constructed arc fixtures. Re-validate arc click detection interactively at Stage 42 when arc surfaces (circle inversion) become available in the scene.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S9 | Exclusion respected | GUT tests | Inherited |
| S12 | Side determination consistent (used for click side detection) | Unit test | Inherited |
| UX9 | Block surfaces still stop arrow | Fire at wall | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 21 | Multi-bounce trace and preview | Aim through mirrors, observe dashed bounces |
| Stage 20b | Reflective surface: blue side bounces, gray passes through | Fire from each side |
| Stage 19 | Pass-through surface rendering and behavior | Visual + fire through |
| Stage 18 | Arrow shooting | Press Spacebar |
| Stage 17 | Preview rendering | Move mouse |
| Stage 13 | Room boundaries | Fire at wall |
| Stage 5 | Green line to cursor | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

Same as Stage 21, plus: when a surface side is clicked, a numbered label ("1", "2", ...) appears on the surface. The HUD (top-left or similar) shows the current plan as a text list. The surface brightens or highlights when planned. No change to the preview trajectory yet — planned trace rendering comes in later stages.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/game/plan_manager.gd` | Create | Plan array management (add, get, clear, count) |
| `scripts/game/click_detector.gd` | Create | Surface click detection with 8px tolerance, nearest-surface selection |
| `scripts/visual/surface_renderer.gd` | Modify | Numbered overlay rendering for planned surfaces |
| `scenes/ui/plan_hud.tscn` | Create | HUD scene for plan display |
| `scripts/game/plan_hud.gd` | Create | Plan HUD text display script |
| `scenes/main.tscn` | Modify | Add plan HUD and connect click input |
| `tests/test_stage22_plan_construction.gd` | Create | Plan construction unit tests |

---

## Stage 23: Plan Removal UI (Right-Click/Clear)

### Overview
Implement plan removal via right-click and the C key. Right-clicking on a planned surface removes the latest instance of that surface from the plan. Right-clicking on an unplanned surface or empty space clears the entire plan. The C key clears the plan without resetting the level or player position. Plan display updates immediately after any removal.

### Prerequisites
Stage 22 (plan construction — entries must exist before they can be removed).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Behavior | Right-click on planned surface: remove latest instance from plan | §4.1, §4.2 |
| Behavior | Right-click on unplanned surface or empty space: clear entire plan | §4.1 |
| Behavior | C key: clear plan (no level/position reset) | §4.1 |
| Behavior | Plan display updates immediately on removal | §4.2 |

### Unit Tests Added

1. **`test_stage23_remove_latest_instance`**: Plan = [A, B, A]. Right-click on surface A. Expected: plan becomes [A, B] (latest instance of A removed). Validates: §4.2 — removes latest instance.
2. **`test_stage23_remove_only_instance`**: Plan = [A]. Right-click on surface A. Expected: plan is empty. Validates: removal of sole entry.
3. **`test_stage23_rightclick_unplanned_clears`**: Plan = [A, B]. Right-click on an unplanned surface C. Expected: plan is empty (full clear). Validates: §4.1.
4. **`test_stage23_rightclick_empty_space_clears`**: Plan = [A, B]. Right-click with no surface within tolerance. Expected: plan is empty (full clear). Validates: §4.1.
5. **`test_stage23_c_key_clears_plan`**: Plan = [A, B]. Press C. Expected: plan is empty. Player position unchanged. Level state unchanged. Validates: §4.1 — C key clears plan only.
6. **`test_stage23_c_key_preserves_player_position`**: Player at (200, 300). Press C. Expected: player still at (200, 300). Validates: clear does not reset position.
7. **`test_stage23_remove_from_empty_plan`**: Plan is empty. Right-click. Expected: plan remains empty (no error). Validates: graceful handling.
8. **`test_stage23_numbered_overlay_updates`**: Plan = [A, B, C]. Remove B. Expected: overlays show "1" on A and "2" on C (renumbered). Validates: display consistency.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Add three surfaces to the plan (click three times on the mirror's blue side). HUD shows 3 entries.
- [ ] Right-click on the planned mirror surface. The latest entry is removed. HUD shows 2 entries. Number overlays update.
- [ ] Right-click on the planned mirror surface again. HUD shows 1 entry.
- [ ] Right-click on empty space (far from any surface). The entire plan clears. HUD is empty.
- [ ] Add two entries to the plan. Press C. Plan clears. Player does not move. No level reset.
- [ ] Right-click on the gray pass-through surface (not in plan). The plan clears entirely (not a planned surface → full clear).
- [ ] Add an entry, then right-click on a boundary wall (not in plan). Full clear occurs.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S9 | Exclusion respected | GUT tests | Inherited |
| UX9 | Block surfaces stop arrow | Fire at wall | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 22 | Left-click adds to plan, numbered overlays, HUD display | Click to add |
| Stage 21 | Multi-bounce trace | Aim through mirrors |
| Stage 20b | Reflective surface sides (blue/gray) | Visual inspection |
| Stage 19 | Pass-through surface | Fire through |
| Stage 18 | Arrow shooting | Press Spacebar |
| Stage 17 | Preview rendering | Move mouse |
| Stage 13 | Room boundaries | Fire at wall |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

Same as Stage 22 when entries are present. After right-click removal, numbered overlays update immediately. After full clear, all overlays disappear and HUD shows an empty plan. Player and surfaces are unchanged.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/game/plan_manager.gd` | Modify | Add `remove_latest(surface_id)`, `clear()` methods |
| `scripts/game/click_detector.gd` | Modify | Handle right-click input for removal/clear |
| `scripts/game/plan_hud.gd` | Modify | Update display on removal |
| `tests/test_stage23_plan_removal.gd` | Create | Plan removal unit tests |

---

## Stage 24: Planned Trace (Single Reflection)

### Overview
Implement `plan_transformative_subchain` from §13.2 for a single reflective surface, producing the first planned trace. The backward image is computed by inverse-transforming the cursor through the planned surface's effect (for reflection: `image = reflect(cursor)` across the surface carrier). The forward bounce point is found by intersecting the aim line (player to image) with the surface's unbounded carrier via `intersect_line_with_carrier` (§11.5). The planned trace produces Steps with the same structure as the physical trace, enabling the step tree merge in later stages.

**Design foresight for Stage 50:** The `plan_transformative_subchain` function implemented here is one piece of the full `plan_mixed` algorithm (§13.4). Stage 50 will add Pass 1 (backward geometry with projective break points) and Pass 2 (forward origin fill). When implementing this stage, design the function signature and return types to accommodate Stage 50's requirements: `plan_mixed` will call `plan_transformative_subchain` as a subroutine for each transformative sub-chain between projective breaks. The current implementation must not preclude this — avoid assumptions about being the only sub-chain or having the full origin-to-cursor span.

### Prerequisites
Stage 23 (plan construction/removal — a plan must exist to compute a planned trace).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/planner.gd` — planned trace computation (image chain, bounce points) | §13.1, §13.2 |
| Method | `plan_transformative_subchain(sub_origin, sub_target, entries, initial_frame)` | §13.2 |
| Method | `intersect_line_with_carrier(ray, carrier) -> Array[HitCandidate]` — unbounded carrier intersection | §11.5 |
| Behavior | Backward image: `image = effect.get_inverse_mobius().apply(cursor)` | §13.1 |
| Behavior | Forward bounce: intersect aim line (player → image) with carrier | §13.2 |
| Behavior | Planned trace produces Steps (same structure as physical trace) | §13.9 |

### Unit Tests Added

1. **`test_stage24_backward_image_reflection`**: Reflect cursor (400, 300) across mirror at x=200. Expected: image = (0, 300). Validates: §13.1 inverse transform.
2. **`test_stage24_intersect_line_with_carrier`**: Ray from (50, 450) toward (-275, -100), carrier is vertical line x=100. Expected: intersection at (100, ~367). Validates: §11.5 unbounded carrier intersection.
3. **`test_stage24_intersect_line_with_carrier_no_bounds_filter`**: Unlike `intersect_line_with_gcircle`, this function does NOT filter by segment bounds. A hit outside the segment's start-end range is still returned. Validates: §11.5 unbounded behavior.
4. **`test_stage24_single_reflection_plan`**: Player at (50, 300), cursor at (400, 300), mirror at x=200, plan=[{mirror, left}]. Expected: planned trace has 2 steps: (50,300)→(200,300) and (200,300)→(400,300). Bounce point at (200, 300). Validates: §13.2.
5. **`test_stage24_plan_produces_steps`**: The planned trace output is an Array[Step] with correct start, end, frame, and hit fields. Each step has the same structure as physical trace steps. Validates: §13.9.
6. **`test_stage24_single_reflection_angled`**: Player at (50, 450), cursor at (475, 300), mirror at x=100, plan=[{mirror, left}]. Backward image of cursor reflected across x=100 = (-275, 300). Aim from (50,450) toward (-275, 300). Bounce at (100, ~367). Second leg from bounce to cursor. Validates: angled reflection planning.
7. **`test_stage24_plan_empty_no_crash`**: Compute planned trace with empty plan. Expected: planned trace is empty (no steps). Validates: edge case.
8. **`test_stage24_bounded_vs_unbounded_comparison`**: Same ray, same surface. The ray intersects the carrier OUTSIDE the segment bounds. `intersect_line_with_gcircle` returns no hit (filtered by bounds). `intersect_line_with_carrier` returns the hit (unbounded). Validates: the critical distinction between bounded and unbounded intersection for the planning algorithm.
9. **`test_stage24_via_inf_segment_in_plan`**: Plan includes a surface with `via = Vector2(INF, INF)` (segment through infinity). The planner's `intersect_line_with_carrier` computes the bounce point on the unbounded carrier. Expected: correct bounce point. No crash, no NaN. Validates: infinity segments work in the planning algorithm.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Add the mirror to the plan (left-click on blue side). The preview line should now show the planned path — a line from player to mirror bounce point, then from bounce point to cursor. (The rendering may still be basic at this stage; full 5-type rendering comes in Stage 28.)
- [ ] Move the cursor around. The planned bounce point on the mirror updates in real time.
- [ ] Move the cursor so the aimed line does not cross the mirror carrier at all. Observe behavior (the trace may produce degenerate results or no bounce).
- [ ] Clear the plan. Preview returns to the simple straight-line physical trace.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S2 | Transform round-trip (image computation uses inverse) | Unit test | Inherited |
| S1 | Cache round-trip | GUT tests | Inherited |
| S12 | Side determination | GUT tests | Inherited |
| S16 | No NaN/Inf in output (planned trace points) | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 23 | Plan removal (right-click, C key) | Right-click, press C |
| Stage 22 | Plan construction (left-click, numbered overlays) | Left-click on mirror |
| Stage 21 | Multi-bounce physical trace | Aim through mirrors |
| Stage 20b | Reflective surface: bounce vs pass-through | Fire from each side |
| Stage 19 | Pass-through surface | Fire through |
| Stage 18 | Arrow shooting | Press Spacebar |
| Stage 17 | Preview rendering | Move mouse |
| Stage 8 | Cache S1 round-trip | GUT tests |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

When a plan is active, the preview shows the planned path: a line from the player to the mirror bounce point, then from the bounce point toward the cursor. The preview may render as simple green lines at this stage (full 5-type color/style rendering is Stage 28). Without a plan, the preview is the simple straight-line physical trace. Numbered overlays on planned surfaces.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/math/planner.gd` | Create | Planned trace computation (plan_transformative_subchain, backward image, forward bounce) |
| `scripts/math/intersection.gd` | Modify | Add `intersect_line_with_carrier` (unbounded carrier intersection) |
| `scripts/visual/path_renderer.gd` | Modify | Render planned trace steps (basic — full 5-type rendering in Stage 28) |
| `tests/test_stage24_planned_trace.gd` | Create | Planned trace unit tests |

---

## Stage 25: Step Tree Merge (Aligned Case)

### Overview
Implement the StepTree data structure and the merge algorithm from §14.5 for the case where planned and physical traces fully agree. The StepTree holds `planned_steps`, `physical_steps`, `divergence_index`, and `merged_steps`. The merge walks both traces by index, comparing start point provenance IDs and frame IDs. When all steps agree, pre-cursor steps are classified as ALIGNED and post-cursor steps as ALIGNED_POST_PLANNED. The empty-plan guard classifies all physical steps as ALIGNED_POST_PLANNED (§14.9). This establishes the invariants S4, S5, and S6.

### Prerequisites
Stage 24 (planned trace produces Steps that can be merged with physical trace Steps).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/step_tree.gd` — StepTree data structure and merge algorithm | §14.4, §14.5 |
| Enum | `StepType { ALIGNED, ALIGNED_POST_PLANNED, DIVERGED_PHYSICAL, DIVERGED_PLANNED, DIVERGED_POST_PLANNED }` | §14.6 |
| Method | `StepTree.merge(planned_steps, physical_steps, cursor_index) -> Array[Step]` | §14.5 |
| Behavior | Alignment checked by provenance ID (`start.id`) and frame ID, not coordinate equality | §14.5, §14.8 |
| Behavior | Pre-cursor aligned steps → ALIGNED; post-cursor aligned steps → ALIGNED_POST_PLANNED | §14.5 |
| Behavior | Empty-plan guard: all physical steps → ALIGNED_POST_PLANNED | §14.9 |

### Unit Tests Added

1. **`test_stage25_step_tree_construction`**: Create a StepTree with planned_steps and physical_steps. Expected: fields are stored correctly. Validates: §14.4 data structure.
2. **`test_stage25_merge_fully_aligned`**: Planned and physical steps share the same provenance IDs and frame IDs at each index. cursor_index=1 (1 pre-cursor step). Expected: step 0 is ALIGNED, step 1+ is ALIGNED_POST_PLANNED. `divergence_index == null`. Validates: §14.5 aligned case.
3. **`test_stage25_merge_empty_plan`**: Planned steps is empty, physical steps has 3 entries, cursor_index=0. Expected: all 3 physical steps are ALIGNED_POST_PLANNED. Validates: §14.9 empty-plan guard.
4. **`test_stage25_S4_no_divergence_means_all_aligned`**: When divergence_index is null, every step type is ALIGNED or ALIGNED_POST_PLANNED (no DIVERGED types). Validates: S4 (monotonic — trivially satisfied when no divergence).
5. **`test_stage25_S5_aligned_provenance`**: For each ALIGNED step in the merged output, the corresponding planned and physical steps have identical `start.id` values. Validates: S5.
6. **`test_stage25_S6_aligned_match`**: For each ALIGNED step, the planned and physical steps have the same `hit.surface.id`, `hit.side`, and `frame_id`. Validates: S6.
7. **`test_stage25_cursor_index_boundary`**: With cursor_index=2 and 4 total aligned steps: steps 0-1 are ALIGNED, steps 2-3 are ALIGNED_POST_PLANNED. Validates: cursor boundary classification.
8. **`test_stage25_single_step_aligned`**: One planned step, one physical step, identical provenance, cursor_index=1. Expected: one ALIGNED step, no post-planned. Validates: minimal case.
9. **`test_stage25_alignment_by_provenance_not_position`**: Two steps with identical coordinates but different provenance IDs. Expected: treated as divergent (not aligned). Validates: §14.8 — provenance, not coordinate comparison.
10. **`test_stage25_post_cursor_continuation_planned_frame`**: Plan with a reflection. Cursor between player and mirror. The post-cursor continuation uses the PLANNED frame (identity composed with reflection), not the physical frame. Expected: dashed green continuation follows the planned frame's direction. Validates: §14.10.
11. **`test_stage25_merge_with_passthrough_steps`**: Plan includes a pass-through surface between two reflections. Both planned and physical traces produce a pass-through step at the same index. Expected: steps correctly index-aligned, no spurious divergence at the pass-through step. Validates: §14.5.
12. **`test_stage25_shared_cache_precondition`**: Construct planned and physical traces for the same scene. Verify: (a) both use the same TransformCache instance (identity comparison, not value equality), (b) both start with frame_id == 0 (IDENTITY). Validates: §14.8 precondition — shared cache guarantees bit-identical aligned results.
13. **`test_stage25_plan_read_atomically_per_frame`**: During a simulated preview computation, modify the plan (add an entry) mid-computation. Expected: the preview uses either the old plan OR the new plan consistently for that frame — not a mix. The step tree merge does not produce inconsistent step types. Validates: plan is read atomically for each computation cycle.
14. **`test_stage25_post_cursor_planned_escape`**: Plan with one reflection. Cursor positioned so the post-cursor continuation (physical trace from cursor in planned frame) escapes to infinity (no hit). Expected: an escape step with `end = Vector2(INF, INF)` appears in the post-cursor portion. Preview renders the escape correctly (line to viewport edge). Validates: §14.10 post-cursor escape.

### Interactive User Tests

- [ ] With a plan active (one mirror entry), observe the preview. The pre-cursor portion is green solid (ALIGNED) and the post-cursor portion is green dashed (ALIGNED_POST_PLANNED).
- [ ] Move the cursor. The boundary between solid and dashed green shifts based on where the cursor is.
- [ ] Clear the plan. All preview lines become green dashed (ALIGNED_POST_PLANNED per §14.9).
- [ ] With a plan, aim so the physical and planned paths agree. The entire preview is green (no red or yellow).

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S4 | Divergence monotonic — no divergence means no DIVERGED types anywhere | Unit test | Yes |
| S5 | Aligned steps share provenance — planned and physical have identical start.id | Unit test | Yes |
| S6 | Aligned steps match — same surface ID, side, frame ID | Unit test | Yes |
| S2 | Transform round-trip | GUT tests | Inherited |
| S1 | Cache round-trip | GUT tests | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 24 | Planned trace for single reflection | Add mirror to plan, observe bounce point |
| Stage 23 | Plan removal | Right-click, C key |
| Stage 22 | Plan construction | Left-click on mirror |
| Stage 21 | Multi-bounce physical trace | Aim through mirrors |
| Stage 20b | Reflective surface behavior | Fire from each side |
| Stage 19 | Pass-through surface | Fire through |
| Stage 18 | Arrow shooting | Press Spacebar |
| Stage 17 | Preview rendering | Move mouse |
| Stage 8 | Cache S1 round-trip | GUT tests |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

With a plan: green solid line from player to cursor (via bounce points) showing ALIGNED steps, green dashed line past cursor showing ALIGNED_POST_PLANNED steps. Without a plan: all green dashed (ALIGNED_POST_PLANNED). No red or yellow lines yet (divergence rendering comes later).

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/math/step_tree.gd` | Create | StepTree data structure, merge algorithm, StepType enum |
| `scripts/math/step.gd` | Modify | Add `type: StepType` field to Step record |
| `scripts/visual/path_renderer.gd` | Modify | Render ALIGNED (green solid) and ALIGNED_POST_PLANNED (green dashed) based on step type |
| `tests/test_stage25_step_tree.gd` | Create | Step tree merge unit tests |

---

## Stage 26: Divergence Detection

### Overview
Extend the merge algorithm to handle divergence case 1 (§14.2): same start point and frame, but different first hit point. The shared portion (from common start to the nearer hit point) is ALIGNED; the remainder of each trace becomes DIVERGED_PLANNED and DIVERGED_PHYSICAL respectively. Once divergence occurs, all subsequent steps are classified as diverged (monotonic, S4). Divergence case 2 (different active frame at step start) is also implemented but will not be triggered until later stages introduce frame-diverging scenarios.

### Prerequisites
Stage 25 (StepTree merge for aligned case — divergence extends this).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Behavior | Divergence case 1: same start/frame, different hit → split at nearer t | §14.2 |
| Behavior | Divergence case 2: different frame at step start → immediate divergence | §14.2 |
| Behavior | Post-divergence: all subsequent steps are DIVERGED_PLANNED or DIVERGED_PHYSICAL | §14.2 |
| Behavior | `divergence_index` set to the first diverging step index | §14.4 |
| Method | `step_truncated(step, split_t, type)` — create a step truncated at parameter t | §14.5 |
| Method | `step_remainder(step, split_t, type)` — create a step starting at the split point | §14.5 |

### Unit Tests Added

1. **`test_stage26_divergence_case1_different_hit`**: Planned step ends at t=5 (surface A), physical step ends at t=3 (surface B). Same start, same frame. Expected: ALIGNED step from start to t=3, DIVERGED_PLANNED remainder of planned step (t=3 to t=5), DIVERGED_PHYSICAL remainder of physical step (t=3 to block). `divergence_index` is set. Validates: §14.2 case 1.
2. **`test_stage26_split_at_nearer_t`**: Physical t=3, planned t=5. Expected: split at t=3 (the nearer one). The ALIGNED portion goes from start to the physical hit point. Validates: §14.5 split logic.
3. **`test_stage26_S4_monotonic`**: After divergence at index 2, all steps at index >= 2 are DIVERGED types. No ALIGNED or ALIGNED_POST_PLANNED steps appear after the divergence point. Validates: S4.
4. **`test_stage26_diverged_planned_type`**: After divergence, remaining planned steps are DIVERGED_PLANNED (pre-cursor) or DIVERGED_POST_PLANNED (post-cursor). Validates: §14.6 type classification.
5. **`test_stage26_diverged_physical_type`**: After divergence, remaining physical steps are DIVERGED_PHYSICAL. Validates: §14.6.
6. **`test_stage26_case2_different_frame`**: Planned and physical steps at index 2 have different frame IDs. Expected: immediate divergence at index 2. All steps at index >= 2 are diverged. Validates: §14.2 case 2.
7. **`test_stage26_no_reconvergence`**: After divergence, even if later steps happen to have matching coordinates (coincidental), they remain diverged (checked by provenance, not position). Validates: S4 + §14.5.
8. **`test_stage26_divergence_index_set`**: When divergence occurs at step 1, `step_tree.divergence_index == 1`. When no divergence, `divergence_index == null`. Validates: §14.4.

### Interactive User Tests

- [ ] This stage adds divergence detection but the scenario to trigger it requires an internal blocking surface (Stage 27). For now, verify that existing aligned scenarios still work correctly — all green preview, no red or yellow.
- [ ] Add a mirror to the plan and aim correctly. Preview should be fully green (ALIGNED + ALIGNED_POST_PLANNED).
- [ ] (Deferred to Stage 27) Set up a blocking surface to cause divergence.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S4 | Divergence monotonic — once diverged, stays diverged | Unit test: no ALIGNED after divergence_index | Yes (fully testable) |
| S5 | Aligned steps share provenance (pre-divergence) | Unit test | Inherited |
| S6 | Aligned steps match (pre-divergence) | Unit test | Inherited |
| S2 | Transform round-trip | GUT tests | Inherited |
| S1 | Cache round-trip | GUT tests | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 25 | Step tree merge: fully aligned case, empty-plan guard | Unit tests + visual (all green) |
| Stage 24 | Planned trace: single reflection | Add mirror to plan |
| Stage 23 | Plan removal | Right-click, C key |
| Stage 22 | Plan construction | Left-click on mirror |
| Stage 21 | Multi-bounce physical trace | Aim through mirrors |
| Stage 20b | Reflective surface | Fire from each side |
| Stage 19 | Pass-through surface | Fire through |
| Stage 18 | Arrow shooting | Press Spacebar |
| Stage 17 | Preview rendering | Move mouse |
| Stage 8 | Cache S1 round-trip | GUT tests |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

No visible change from Stage 25 at this point — divergence detection is implemented but not yet triggered visually (the scenario requires Stage 27). All existing previews remain green. The code is ready for divergence but the level geometry does not yet cause it.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/math/step_tree.gd` | Modify | Extend merge algorithm for divergence cases 1 and 2, add step_truncated/step_remainder |
| `tests/test_stage26_divergence.gd` | Create | Divergence detection unit tests |

---

## Stage 27: Internal Blocking Surface

### Overview
Add a block surface inside the room (not a boundary wall) positioned so it causes divergence with a planned reflection path. This reproduces the worked example from §16.3: Surface M is a mirror at x=200 (left=Reflection), Surface W is a block at x=150 (both sides Block), and the player plans to reflect off M. The physical ray hits W at (150, 300) before reaching M at (200, 300), causing divergence. The step tree shows ALIGNED from origin to (150, 300), DIVERGED_PLANNED from (150, 300) through the mirror to cursor, and DIVERGED_PHYSICAL terminating at (150, 300).

### Prerequisites
Stage 26 (divergence detection in step tree merge).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Surface | Interior block surface (both sides terminal) at x=150 | §10.5 |
| Scenario | Divergence worked example from §16.3 | §16.3 |
| Behavior | Physical ray blocked before planned reflection point | §16.3 |
| Behavior | Step tree with all 3 divergence-related step types produced | §14.6 |

### Unit Tests Added

1. **`test_stage27_block_surface_construction`**: Create a surface with Block on both sides. Expected: `left.effect` is TerminalEffect, `right.effect` is TerminalEffect. Validates: §10.5.
2. **`test_stage27_divergence_worked_example`**: Reproduce §16.3 exactly. Player at (50, 300), mirror M at x=200 (left=Reflection), wall W at x=150 (both=Block), plan=[{M, left}], cursor at (400, 300). Expected step tree: ALIGNED (50,300)→(150,300); DIVERGED_PLANNED (150,300)→(200,300)→cursor; DIVERGED_PHYSICAL (150,300) blocked. `divergence_index` is set. Validates: §16.3.
3. **`test_stage27_physical_trace_hits_wall_first`**: In the §16.3 setup, the physical trace hits wall W at t corresponding to x=150, which is less than t for mirror M at x=200. Expected: physical trace terminates at (150, 300). Validates: §11.3 earliest hit selection.
4. **`test_stage27_planned_trace_ignores_wall`**: The planned trace uses unbounded carrier intersection and does not check for intervening surfaces. Expected: planned trace goes through M at (200, 300) and reaches cursor. Validates: §14.1 PLANNED mode.
5. **`test_stage27_aligned_prefix`**: The portion from (50, 300) to (150, 300) is ALIGNED — both traces agree on this prefix. Validates: §14.5 partial alignment.
6. **`test_stage27_S4_after_divergence`**: After the divergence at the wall, no subsequent steps are ALIGNED. All are DIVERGED_PLANNED or DIVERGED_PHYSICAL. Validates: S4.
7. **`test_stage27_internal_block_stops_arrow`**: Fire the arrow. Arrow animation stops at the wall (150, 300). Validates: UX9 for internal block surfaces.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Press Play. A new red interior surface (block) appears at x=150, distinct from the mirror at x=200.
- [ ] Add the mirror to the plan (left-click on blue side of M).
- [ ] Aim so the planned path would go through the mirror. Observe that the preview now shows divergence: green from player to wall, then red solid showing where the plan intended to go (through the mirror), and yellow dashed showing where the physical arrow actually stops (at the wall).
- [ ] Fire the arrow. The arrow stops at the internal block wall, matching the yellow dashed preview.
- [ ] Move the cursor to different positions. The divergence point shifts based on geometry but the wall always intercepts the physical path.
- [ ] Clear the plan. Preview returns to all green (no planned trace, just physical trace hitting the wall).
- [ ] From the right side of the wall, aim past the mirror. The physical trace still respects the wall from the right side (both sides block).

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S4 | Divergence monotonic — all post-wall steps are diverged | Unit test | Inherited |
| S5 | Aligned steps share provenance (pre-wall segment) | Unit test | Inherited |
| S6 | Aligned steps match (pre-wall segment) | Unit test | Inherited |
| UX9 | Block surfaces stop the arrow (internal block) | Fire at wall, arrow stops | Inherited |
| S8 | Forward-first ordering (wall hit before mirror) | Unit test | Inherited |
| S2 | Transform round-trip | GUT tests | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 26 | Divergence detection | Unit tests |
| Stage 25 | Step tree merge: aligned case, empty-plan guard | Unit tests |
| Stage 24 | Planned trace: single reflection | Add mirror to plan |
| Stage 23 | Plan removal | Right-click, C key |
| Stage 22 | Plan construction | Left-click |
| Stage 21 | Multi-bounce physical trace | Aim through mirrors |
| Stage 20b | Reflective surface | Fire from each side |
| Stage 19 | Pass-through surface | Fire through |
| Stage 18 | Arrow shooting | Press Spacebar |
| Stage 13 | Room boundaries block | Fire at outer wall |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

Red boundary walls. Gray pass-through surface. Blue/gray mirror at x=200. New red interior block surface at x=150. With the mirror planned: green solid line from player to wall (ALIGNED), red solid line continuing through the mirror to cursor (DIVERGED_PLANNED), yellow dashed at the wall showing the physical stop (DIVERGED_PHYSICAL). Without a plan: green dashed line from player to wall (physical trace terminates at block). This is the first time all three divergence-related step types are visible.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/game/level_setup.gd` | Modify | Add interior block surface at x=150 |
| `tests/test_stage27_divergence_scenario.gd` | Create | Divergence worked example (§16.3) unit tests |

---

## Stage 28: All Five Step Types Rendered

### Overview
Implement rendering for all 5 step types with correct colors, line styles, and z-order. ALIGNED is green solid, ALIGNED_POST_PLANNED is green dashed, DIVERGED_PHYSICAL is yellow dashed, DIVERGED_PLANNED is red solid, and DIVERGED_POST_PLANNED is red dashed. Z-order within the step tree (back to front): DIVERGED_PLANNED, DIVERGED_POST_PLANNED, ALIGNED, ALIGNED_POST_PLANNED, DIVERGED_PHYSICAL — ensuring the physical path (green + yellow) always renders on top of the planned path (red). This is the visual backbone of the game's feedback system.

### Prerequisites
Stage 27 (all 3 divergence-related step types are produced, providing content to render).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Rendering | ALIGNED: green solid, 2px | §4.3, §22.2 |
| Rendering | ALIGNED_POST_PLANNED: green dashed, 2px | §4.3, §22.2 |
| Rendering | DIVERGED_PHYSICAL: yellow dashed, 2px | §4.3, §22.2 |
| Rendering | DIVERGED_PLANNED: red solid, 2px | §4.3, §22.2 |
| Rendering | DIVERGED_POST_PLANNED: red dashed, 2px | §4.3, §22.2 |
| Rendering | Z-order: DIVERGED_PLANNED → DIVERGED_POST_PLANNED → ALIGNED → ALIGNED_POST_PLANNED → DIVERGED_PHYSICAL | §20.4 |
| Behavior | Physical path (green + yellow) always on top of planned path (red) | §20.4 |

### Unit Tests Added

1. **`test_stage28_step_type_colors`**: Each step type maps to the correct color. ALIGNED → green, ALIGNED_POST_PLANNED → green, DIVERGED_PHYSICAL → yellow, DIVERGED_PLANNED → red, DIVERGED_POST_PLANNED → red. Validates: §22.2.
2. **`test_stage28_step_type_styles`**: Each step type maps to the correct line style. ALIGNED → solid, ALIGNED_POST_PLANNED → dashed, DIVERGED_PHYSICAL → dashed, DIVERGED_PLANNED → solid, DIVERGED_POST_PLANNED → dashed. Validates: §4.3.
3. **`test_stage28_z_order`**: Render order array for the 5 types. Expected: DIVERGED_PLANNED (back), DIVERGED_POST_PLANNED, ALIGNED, ALIGNED_POST_PLANNED, DIVERGED_PHYSICAL (front). Validates: §20.4.
4. **`test_stage28_UX7_solid_path_to_cursor`**: In any merged step tree, the solid-colored steps (ALIGNED + DIVERGED_PLANNED) form a continuous path from player toward cursor. Validates: UX7.
5. **`test_stage28_physical_never_red`**: In any merged step tree, no step with type DIVERGED_PHYSICAL or ALIGNED or ALIGNED_POST_PLANNED has red color. Physical path is always green or yellow. Validates: §14.6 visual invariant.
6. **`test_stage28_all_five_types_present`**: Using the §16.3 scenario: the merged step tree contains ALIGNED, DIVERGED_PLANNED, and DIVERGED_PHYSICAL types. With post-cursor continuation: ALIGNED_POST_PLANNED is also present. DIVERGED_POST_PLANNED is present when the planned path continues past the cursor into diverged territory. Validates: all 5 types can be produced.
7. **`test_stage28_post_cursor_both_continuations_rendered`**: Set up a divergence scenario. After divergence, both the planned continuation (red dashed, using planned frame) and the physical continuation (yellow dashed, using physical frame) are rendered simultaneously. Expected: two different dashed paths visible — the red one showing where the plan would go, the yellow showing where the arrow actually goes. Each uses its own frame for computation. Validates: §14.5 + §14.10 post-divergence rendering.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] With the §16.3 scenario (mirror planned, wall intercepting): observe green solid line from player to wall (ALIGNED), red solid line from wall through mirror to cursor (DIVERGED_PLANNED), yellow dashed at the wall where the arrow actually stops (DIVERGED_PHYSICAL).
- [ ] Verify the green/yellow path draws ON TOP of the red path (z-order). Where they overlap, green/yellow is visible.
- [ ] Move the cursor past the mirror. Observe red dashed lines past the cursor (DIVERGED_POST_PLANNED) showing where the plan would continue.
- [ ] Clear the plan. All lines become green (ALIGNED_POST_PLANNED per empty-plan guard).
- [ ] Add the mirror to the plan and aim so there is no divergence (e.g., no wall in the path). Preview is all green (ALIGNED + ALIGNED_POST_PLANNED). No red or yellow.
- [ ] Verify line widths are 2px for all step types (per §22.4).

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| UX7 | Solid path leads from player toward cursor (ALIGNED + DIVERGED_PLANNED continuous) | Unit test + visual | Yes (fully testable) |
| S4 | Divergence monotonic | Unit test | Inherited |
| S5 | Aligned steps share provenance | Unit test | Inherited |
| S6 | Aligned steps match | Unit test | Inherited |
| S2 | Transform round-trip | GUT tests | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 27 | Internal block causes divergence | Plan mirror, observe divergence |
| Stage 26 | Divergence detection | Unit tests |
| Stage 25 | Step tree merge (aligned case) | Clear plan, observe all green |
| Stage 24 | Planned trace | Add mirror to plan |
| Stage 23 | Plan removal | Right-click, C key |
| Stage 22 | Plan construction | Left-click |
| Stage 21 | Multi-bounce physical trace | Aim through mirrors |
| Stage 20b | Reflective surface | Fire from each side |
| Stage 19 | Pass-through surface | Fire through |
| Stage 18 | Arrow shooting | Press Spacebar |
| Stage 13 | Room boundaries | Fire at wall |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

Full 5-type rendering. With plan and no divergence: green solid (player→cursor) + green dashed (past cursor). With plan and divergence (wall blocks): green solid (aligned prefix) + red solid (plan through mirror) + yellow dashed (physical stop at wall) + possibly red dashed (plan past cursor). Colors are distinct and layered correctly. The physical path is always on top of the planned path where they overlap.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/visual/path_renderer.gd` | Modify | Complete 5-type rendering with correct colors, styles, and z-order |
| `scripts/visual/step_colors.gd` | Create | Color and style constants for all 5 step types |
| `tests/test_stage28_step_rendering.gd` | Create | Step type rendering unit tests |

---

## Stage 30: Multi-Surface Reflection Chain

### Overview
Extend the planned trace to handle 2 or more reflective surfaces in sequence, implementing the full image chain from §13.1 and §13.2. Each planned surface's inverse transform is applied to the image in reverse order, producing a chain of images. The forward pass intersects each aim line with the next surface's carrier to find bounce points. This reproduces the §16.1 worked example: two mirrors with the player at (50, 450) and cursor at (475, 300), producing bounces at (100, 367) and (340, 100). Chain order matters — reordering the plan changes the path.

### Prerequisites
Stage 28 (all 5 step types rendered — full visual foundation for multi-surface chains).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Behavior | Image chain for 2+ surfaces: inverse-transform cursor through each in reverse | §13.1, §13.2 |
| Behavior | Forward bounce: intersect aim line with each carrier in sequence | §13.2 |
| Behavior | Aim ray updates after each bounce (from bounce point toward remaining image) | §13.2 |
| Behavior | Chain order matters: reordering plan changes path | §13.1 |
| Scenario | §16.1 two-mirror reflection worked example | §16.1 |

### Unit Tests Added

1. **`test_stage30_two_mirror_image_chain`**: Reproduce §16.1. Surface A: vertical line x=100 (left=Reflection). Surface B: horizontal line y=100 (right=Reflection). Player at (50, 450), cursor at (475, 300). Plan: [{A, left}, {B, right}]. Backward image: reflect cursor through B (across y=100) → (475, -100). Reflect through A (across x=100) → (-275, -100). Validates: §13.1 backward image chain.
2. **`test_stage30_two_mirror_bounce_points`**: Same setup as test 1. Forward pass: aim from (50, 450) toward (-275, -100), intersect with carrier of A (x=100) → bounce1 at (100, ~367). Then aim from bounce1 toward image of cursor after A only: reflect cursor (475, 300) through B → (475, -100). Intersect with carrier of B (y=100) → bounce2 at (~340, 100). Final leg from bounce2 to cursor (475, 300). Validates: §13.2 forward bounce computation.
3. **`test_stage30_three_legs_all_aligned`**: In the §16.1 scenario, the planned and physical traces agree on all 3 legs. Expected: all steps are ALIGNED (pre-cursor) or ALIGNED_POST_PLANNED (post-cursor). `divergence_index == null`. Validates: full alignment through multi-surface chain.
4. **`test_stage30_order_matters`**: Same two mirrors, but plan: [{B, right}, {A, left}] (reversed). Expected: different bounce points, different path geometry. The path changes when the plan order changes. Validates: §13.1 order dependence.
5. **`test_stage30_three_mirror_chain`**: Add a third mirror. Plan 3 reflections. Expected: 4-leg path with 3 bounce points. Image chain applies 3 inverse transforms. Validates: scalability beyond 2 surfaces.
6. **`test_stage30_chain_aim_ray_updates`**: After each bounce, the aim ray is updated to go from the bounce point toward the remaining (partially unfolded) image. Verify the intermediate aim ray directions. Validates: §13.2 forward pass mechanics.
7. **`test_stage30_S16_no_nan_in_chain`**: Multi-mirror chain with various angles. All bounce points, images, and aim ray directions are finite (no NaN/Inf). Validates: S16.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Set up the §16.1 scenario: two mirrors (vertical at x=100, horizontal at y=100). Add both to the plan in order: [{A, left}, {B, right}].
- [ ] Observe the preview: green solid line from player (50, 450) to bounce1 on mirror A (~100, 367), then to bounce2 on mirror B (~340, 100), then to cursor (475, 300). All segments are green (fully aligned).
- [ ] Move the cursor around. The bounce points update in real time — the entire 3-leg path adjusts smoothly.
- [ ] Reverse the plan order: clear and re-add as [{B, right}, {A, left}]. The path changes visibly — different bounce points, different path geometry. This confirms order matters.
- [ ] Add a third mirror entry to the plan. The path gains a fourth leg with a third bounce point.
- [ ] Fire the arrow with the two-mirror plan. The arrow bounces off both mirrors and arrives at the cursor position, matching the green preview.
- [ ] Clear the plan. Preview returns to green dashed (empty plan).

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| UX7 | Solid path to cursor (through multi-bounce chain) | Visual: green solid from player through bounces to cursor | Inherited |
| S4 | Divergence monotonic | Unit test | Inherited |
| S5 | Aligned steps share provenance (multi-step chain) | Unit test | Inherited |
| S6 | Aligned steps match (multi-step chain) | Unit test | Inherited |
| S2 | Transform round-trip (multiple reflections) | Unit test | Inherited |
| S1 | Cache round-trip | GUT tests | Inherited |
| S3 | Determinism (same multi-mirror shot → same path) | Fire same shot twice | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |
| UX3 | Preview matches arrow flight (multi-bounce) | Fire arrow, compare to preview | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 28 | All 5 step types rendered | Plan mirror, add wall, observe colors |
| Stage 27 | Internal block causes divergence | Plan mirror with wall |
| Stage 26 | Divergence detection | Unit tests |
| Stage 25 | Step tree merge: aligned case | Clear plan, all green |
| Stage 24 | Planned trace: single reflection | Single mirror plan |
| Stage 23 | Plan removal | Right-click, C key |
| Stage 22 | Plan construction | Left-click |
| Stage 21 | Multi-bounce physical trace | Aim through mirrors |
| Stage 20b | Reflective surface (single) | Fire from each side |
| Stage 19 | Pass-through surface | Fire through |
| Stage 18 | Arrow shooting | Press Spacebar |
| Stage 13 | Room boundaries | Fire at wall |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

With a two-mirror plan: a 3-segment green solid path from player to cursor, bending at each mirror's bounce point. Green dashed continuation past cursor (reflecting further). The bounce points update smoothly as the cursor moves. With reversed plan order: a visibly different path through the same mirrors. All segments are green when aligned. If a blocking surface interferes, red solid and yellow dashed appear at the divergence point.

### Feedback Loop Protocol

Reference standard protocol (top of document).

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
| `scripts/math/planner.gd` | Modify | Extend `plan_transformative_subchain` for multi-entry chains (loop over entries) |
| `scripts/game/level_setup.gd` | Modify | Add second mirror for §16.1 scenario |
| `tests/test_stage30_multi_reflection.gd` | Create | Multi-surface reflection chain unit tests |

---

## Appendix A: Invariant Introduction Map (Stages 19–30)

| Invariant | Full ID | Introduced | First Testable | Status After Stage 30 |
|-----------|---------|-----------|----------------|----------------------|
| Carrier ↔ via round-trip | S1 | Stage 8 | Stage 8 | Tested (inherited) |
| Transform round-trip | S2 | Stage 20b | Stage 20b | Tested (reflection self-inverse, cache returns exact original Point) |
| Determinism | S3 | Stage 15 | Stage 15 | Tested (inherited) |
| Divergence monotonic | S4 | Stage 26 | Stage 26 | Tested (unit test: no ALIGNED after divergence_index) |
| Aligned provenance | S5 | Stage 25 | Stage 25 | Tested (unit test: planned and physical share start.id) |
| Aligned match | S6 | Stage 25 | Stage 25 | Tested (unit test: same surface ID, side, frame ID) |
| Per-entry state | S7 | — | Stage 54+ | Not yet introduced |
| Forward-first ordering | S8 | Stage 11 | Stage 11 | Tested (inherited) |
| Exclusion respected | S9 | Stage 15 | Stage 15 | Tested (inherited) |
| Projective resets frame | S10 | — | Stage 47+ | Not yet introduced |
| Three points on carrier | S11 | Stage 7 | Stage 7 | Tested (inherited) |
| Side determination | S12 | Stage 7 | Stage 7 | Tested (inherited, reinforced at Stage 20b) |
| Visibility no self-intersect | S13 | — | Stage 35+ | Not yet introduced |
| Visibility edges on geometry | S14 | — | Stage 35+ | Not yet introduced |
| Visibility non-overlapping | S15 | — | Stage 35+ | Not yet introduced |
| No NaN/Inf in output | S16 | Stage 4 | Stage 4 | Tested (inherited, extended through reflections and chains) |
| Provenance IDs unique | S17 | Stage 8 | Stage 8 | Tested (inherited) |
| Frame determinant non-zero | S18 | Stage 20a | Stage 20a | Tested (reflection Möbius matrix determinant non-zero) |
| Trace preserves real state | S19 | — | Stage 53+ | Not yet introduced |
| Visibility predicts non-div. | UX1 | — | Stage 37+ | Not yet introduced |
| Divergence → outside vis. | UX2 | — | Stage 37+ | Not yet introduced |
| Preview matches flight | UX3 | Stage 17 | Stage 17 | Tested (inherited, extended through multi-bounce in Stage 30) |
| Same shot = same result | UX4 | Stage 17 | Stage 17 | Tested (inherited) |
| Undo fully restores | UX5 | — | Stage 32+ | Not yet introduced |
| All targets reachable | UX6 | — | Stage 55+ | Not yet introduced |
| Solid path to cursor | UX7 | Stage 5 (partial) | Stage 28 | Tested (ALIGNED + DIVERGED_PLANNED form continuous solid path) |
| Block stops arrow | UX9 | Stage 13 | Stage 13 | Tested (inherited, extended to internal blocks in Stage 27) |
| State changes visible | UX10 | — | Stage 57+ | Not yet introduced |
| Empty plan = fire straight | UX11 | Stage 5 (partial) | Stage 15 | Tested (inherited) |

---

## Appendix B: Cumulative Test Count After Stage 30

| Stage | New Unit Tests | New Interactive Tests | Cumulative Unit | Cumulative Interactive |
|-------|---------------|----------------------|-----------------|----------------------|
| 1–18 (prior) | ~85 | ~55 | ~85 | ~55 |
| 19 | 5 | 5 | ~90 | ~60 |
| 20a | 16 | 1 | ~106 | ~61 |
| 20b | 10 | 7 | ~116 | ~68 |
| 21 | 10 | 6 | ~126 | ~74 |
| 22 | 15 | 8 | ~141 | ~82 |
| 23 | 8 | 7 | ~149 | ~89 |
| 24 | 7 | 4 | ~156 | ~93 |
| 25 | 12 | 4 | ~168 | ~97 |
| 26 | 8 | 3 | ~176 | ~100 |
| 27 | 7 | 7 | ~183 | ~107 |
| 28 | 6 | 6 | ~189 | ~113 |
| 30 | 8 | 8 | ~197 | ~121 |

| Category | Count After Stage 30 |
|----------|---------------------|
| Unit tests | ~197 |
| Interactive test items | ~121 |
| Invariants actively tested | 14 (S1, S2, S3, S4, S5, S6, S8, S9, S11, S12, S16, S17, S18, UX7) |
| Invariants partially covered | 3 (UX3, UX4, UX9) |
| Invariants fully tested | 1 (UX11) |
| Invariants not yet introduced | 7 (S7, S10, S13, S14, S15, S19, UX1, UX2, UX5, UX6, UX10) |
