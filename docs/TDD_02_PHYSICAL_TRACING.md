# TDD Document 2: Physical Tracing

**Stages 9-18** | Intersection, ray tracing, room boundaries, blocking surfaces, arrow shooting, animation skip

### Stage Status
| Stage | Topic | Status |
|-------|-------|--------|
| 9 | Line-Line Intersection | Done |
| 10 | Line-Circle Intersection | Done |
| 11 | HitRecord and Earliest Hit Selection | Done |
| 12 | Surface and SideConfig Data Classes | Done |
| 13 | Room Boundary Surfaces (Block Effect) | Done |
| 14 | Physical Trace (Single Step) | Done |
| 15 | Full Preview (Player to Wall) | Done |
| 16 | Multi-Hit Trace Loop | Done |
| 17 | Arrow Shooting (Fire Button) | Done |
| 18 | Animation Skip | Done |

**Regression Test Policy:** After implementing Stage N, run ALL tests from Stages 1 through N. The full test suite must pass before proceeding to Stage N+1. No exceptions.

**Feedback Loop Protocol (applies to every stage):**
1. AI implements the stage (code + unit tests).
2. AI runs all unit tests (new + all prior). All must pass.
3. User performs interactive tests from the checklist.
4. User provides feedback (pass/fail per item + notes on unexpected behavior).
5. AI converts any failing interactive tests into automated tests.
6. AI applies fixes and re-runs all tests.
7. Repeat steps 3-6 until all checks pass.
8. Stage is marked complete. Proceed to next stage.

**USER VALIDATION GATE (MANDATORY)**

No stage is complete until the user has personally verified every interactive test item and provided explicit sign-off. After every behavioral feature (not just infrastructure), the user must SEE the behavior working in the running game before the stage is marked complete.

1. User MUST test every interactive test item marked with `[ ]`.
2. User MUST provide written pass/fail feedback for EACH item.
3. Any "fail" or "unexpected behavior" becomes a NEW automated test before proceeding.
4. AI MUST NOT proceed to the next stage until ALL interactive items are `[x]`.
5. The user's word is final. If the user says it doesn't look right, it doesn't ship.

---

## Prior Art Summary (Stages 1-8)

By the end of Stage 8 the following exist and are tested:

| Component | Key Facts |
|-----------|-----------|
| **Project skeleton** | Godot 4.6+ project, GUT testing framework, all directories created |
| **Player** | `CharacterBody2D`, WASD movement at 200 u/s, zero gravity, `CircleShape2D` radius 12, spawns at (960, 540) |
| **Cursor** | World-space mouse tracking via `get_global_mouse_position()`, crosshair visual |
| **Direction** | Two-point, immutable `RefCounted`, `is_zero_length()` detection |
| **Ray** | Origin + Direction, Direction shared by reference |
| **Path renderer** | Green solid line from player to cursor via `_draw()` / `queue_redraw()`, no line when cursor == player |
| **GeneralizedCircle** | `(a, b, c, d)` coefficients, `is_line()`, `center()`, `radius()`, `evaluate()`, factory methods |
| **Segment** | `(start, end, via)`, carrier derivation (line or circle), side determination via cross-product formula (LEFT/RIGHT) |
| **TransformCache** | Provenance-keyed, bidirectional carrier-via round-trip, cache-hit on repeated lookup |
| **Point** | Unique ID (monotonic counter), position, provenance enum |
| **Tested invariants** | S1 (carrier-via round-trip), S11 (three points on carrier), S12 (side determination), S16 (no NaN/Inf), S17 (provenance IDs unique) |
| **Partially covered** | UX7 (solid path to cursor -- line only), UX11 (empty plan = fire straight -- line only) |
| **Cumulative tests** | ~50 unit tests, ~28 interactive test items |

Files from prior stages referenced in this document:

| File | Purpose |
|------|---------|
| `scripts/math/direction.gd` | Direction data class |
| `scripts/math/ray.gd` | Ray data class |
| `scripts/math/generalized_circle.gd` | GeneralizedCircle data class |
| `scripts/math/segment.gd` | Segment with carrier derivation and side determination |
| `scripts/math/side.gd` | Side enum (LEFT, RIGHT) |
| `scripts/math/point.gd` | Point with provenance and unique ID |
| `scripts/math/transform_cache.gd` | TransformCache with provenance-keyed lookup |
| `scripts/visual/path_renderer.gd` | Preview line rendering via `_draw()` |
| `scripts/game/player.gd` | Player movement script |
| `scripts/game/cursor.gd` | Cursor tracking and rendering |

---

## Stage 9: Line-Line Intersection

### Overview
Implement the `intersect_line_with_gcircle` function for the line-line case, where the surface carrier has `a = 0`. The ray (always a line in the normalized frame) and the surface carrier (also a line here) form a 2x2 linear system that produces at most one candidate intersection point. This stage handles the parallel (no hit) and coincident (no hit per section 11.4) degenerate cases, and computes the ray parameter `t` for the candidate.

### Prerequisites
Stage 8 (TransformCache, Point, Segment with carrier derivation, GeneralizedCircle, Ray, Direction).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/intersection.gd` -- intersection functions | §11.1 |
| Function | `intersect_line_with_gcircle(ray, segment) -> Array[HitCandidate]` (line-line case) | §11.1 |
| Data class | `HitCandidate` -- `{ t: float, point: Vector2, segment: Segment }` | §11.1 |
| Algorithm | 2x2 linear system solver for two lines | §11.1 |
| Behavior | Ray parameter `t` computation: `point = origin + t * (direction.end - direction.start)` | §11.1 |
| Behavior | Parallel lines: determinant == 0, no intersection returned | §11.4 |
| Behavior | Coincident lines: ray carrier equals surface carrier, no intersection (ray travels along the surface) | §11.4 |
| Behavior | Segment bounds filter: candidate must lie between start and end (finite line), or outside start-end range (line through infinity with `via = INF`) | §11.1 |

### Unit Tests Added

1. **`test_stage9_line_line_perpendicular`**: Ray along y-axis from (0, 0) toward (0, 100). Surface is horizontal segment `start=(−50, 50), end=(50, 50), via=(0, 50)`. Expected: one candidate at `t > 0` with point = (0, 50). Validates: basic line-line intersection.

2. **`test_stage9_line_line_oblique`**: Ray from (0, 0) toward (100, 100). Surface is vertical segment `start=(50, 0), end=(50, 100), via=(50, 50)`. Expected: one candidate at point = (50, 50). Validates: non-axis-aligned intersection.

3. **`test_stage9_line_line_parallel`**: Ray along y-axis. Surface is a parallel vertical segment (different x). Expected: empty array (no intersection). Validates: parallel degenerate case.

4. **`test_stage9_line_line_coincident`**: Ray along x-axis from (0, 0) toward (100, 0). Surface on the same line: `start=(50, 0), end=(150, 0), via=(100, 0)`. Expected: empty array (coincident = no hit per §11.4). Validates: coincident degenerate case.

5. **`test_stage9_line_line_outside_segment`**: Ray from (0, 0) toward (0, 100). Surface is short horizontal segment `start=(10, 50), end=(20, 50), via=(15, 50)`. Expected: empty array (intersection point (0, 50) is outside segment bounds). Validates: segment bounds filter.

6. **`test_stage9_line_line_at_segment_endpoint`**: Ray intersects surface exactly at its start or end point. Expected: candidate returned (endpoints are inclusive). Validates: boundary condition.

7. **`test_stage9_line_line_negative_t`**: Ray from (0, 100) toward (0, 200). Surface is horizontal at y=50 (behind the ray). Expected: one candidate with `t < 0`. Validates: beyond-infinity hits are returned (filtering happens in `find_all_hits`, not here).

8. **`test_stage9_line_line_via_inf`**: Surface with `via = Vector2(INF, INF)` (line through infinity). Ray intersects the carrier but the hit point is between start and end (the finite portion). Expected: empty array (the segment through infinity excludes the finite portion). Validates: infinity segment bounds.

9. **`test_stage9_S8_forward_first`**: Two surfaces: one in front of the ray (`t > 0`) and one behind (`t < 0`). Process both. Expected: both candidates returned with correct `t` values, forward hit has smaller positive `t`. Validates: S8 data correctness (selection logic is in `find_all_hits`, Stage 11).

### Interactive User Tests

- [ ] No visual change expected. Press Play and verify the game still runs identically to Stage 8 (player moves, cursor tracks, green line draws).
- [ ] Run GUT. All tests from Stages 1-9 pass.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S8-infra | Forward-first hit ordering -- data structure support (t values correct) | Unit test: correct t values returned | Yes (infrastructure) |
| S16 | No NaN/Inf in output | Unit test: all intersection results have finite coordinates | Inherited |
| S1 | Cache: carrier-via round-trip | GUT (inherited) | Inherited |
| S11 | Three points on carrier | GUT (inherited) | Inherited |
| S12 | Side determination consistent | GUT (inherited) | Inherited |
| S17 | Provenance IDs unique | GUT (inherited) | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 8 | TransformCache round-trip (S1), Point IDs unique (S17) | GUT tests |
| Stage 7 | Segment carrier derivation, side determination (S11, S12) | GUT tests |
| Stage 6 | GeneralizedCircle methods correct | GUT tests |
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 4 | Direction/Ray construction, zero-length detection | GUT tests |
| Stage 3 | Cursor follows mouse in world space | Move mouse |
| Stage 2 | Player moves with WASD at 200 u/s, instant response | Press WASD |
| Stage 1 | GUT runs, project loads | Run GUT |

### Expected Visual State

Identical to Stage 8. No visual changes -- this stage is pure math layer (intersection algorithm).

### Feedback Loop Protocol

AI implements -> runs tests -> user tests -> feedback -> automate -> fix -> repeat (standard protocol).

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
| `scripts/math/intersection.gd` | Create | Intersection functions (line-line case) |
| `tests/test_stage9_intersection_line_line.gd` | Create | Line-line intersection unit tests |

---

## Stage 10: Line-Circle Intersection

### Overview
Extend `intersect_line_with_gcircle` to handle the line-circle case, where the surface carrier has `a != 0`. The ray's parametric form is substituted into the circle equation, producing a quadratic in `t` that yields 0, 1, or 2 candidate intersection points. Arc containment filtering uses the cross-product test from §11.1 (not angle-based) to determine whether each candidate lies on the intended arc defined by the segment's start, end, and via points.

### Prerequisites
Stage 9 (intersection infrastructure, HitCandidate, line-line case).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Function | `intersect_line_with_gcircle` extended: line-circle case (`a != 0`) | §11.1 |
| Algorithm | Quadratic formula: substitute `P(t) = origin + t * dir` into `a(x^2+y^2) + bx + cy + d = 0` | §11.1 |
| Behavior | Discriminant < 0: no intersection (0 candidates) | §11.1 |
| Behavior | Discriminant == 0: tangent (1 candidate) | §11.1 |
| Behavior | Discriminant > 0: secant (2 candidates) | §11.1 |
| Algorithm | Arc containment via cross-product test: candidate is on arc if `cross(start - center, candidate - center)` has same sign as `cross(start - center, via - center)` AND `cross(via - center, candidate - center)` has same sign as `cross(via - center, end - center)` | §11.1 |
| Behavior | Full-circle segments (start == end after full traversal): all carrier points are contained | §11.1 |

### Unit Tests Added

1. **`test_stage10_line_circle_secant`**: Ray from (0, 200) toward (400, 200). Circle carrier centered at (200, 200), radius 100. Arc segment covers right semicircle: `start=(200, 100), end=(200, 300), via=(300, 200)`. Expected: 2 candidates at (300, 200) and (100, 200). After arc containment filter: 1 candidate at (300, 200) (the other is on the opposite arc). Validates: secant with arc filter.

2. **`test_stage10_line_circle_tangent`**: Ray from (0, 100) toward (400, 100). Circle centered at (200, 200), radius 100. Expected: 1 candidate at (200, 100). Validates: tangent case.

3. **`test_stage10_line_circle_miss`**: Ray from (0, 0) toward (400, 0). Circle centered at (200, 200), radius 100. Expected: empty array (ray misses circle entirely). Validates: discriminant < 0.

4. **`test_stage10_arc_containment_major_arc`**: Circle centered at (200, 200), radius 100. Major arc (> 180 degrees) from `start=(200, 100)` to `end=(200, 300)` with `via=(100, 200)` (left semicircle, major arc going the long way). Ray intersects at a point on the major arc. Expected: candidate returned. Validates: cross-product test works for major arcs.

5. **`test_stage10_arc_containment_excludes_wrong_arc`**: Same circle. Minor arc from `start=(200, 100)` to `end=(200, 300)` with `via=(300, 200)` (right semicircle). Ray hits at (100, 200) which is on the opposite arc. Expected: filtered out. Validates: arc exclusion.

6. **`test_stage10_line_circle_two_hits_both_on_arc`**: Full-circle segment (or arc spanning > 180 degrees) where both quadratic roots fall on the intended arc. Expected: 2 candidates returned. Validates: both roots can survive the filter.

7. **`test_stage10_line_circle_negative_t`**: Ray origin inside the circle. One intersection is behind (`t < 0`), one ahead (`t > 0`). Expected: both candidates returned with correct `t` signs. Validates: beyond-infinity candidates preserved.

8. **`test_stage10_S8_line_circle_t_values`**: Verify that `t` values are correctly computed and that a closer intersection has a smaller `t` than a farther one. Validates: S8 data correctness for the line-circle case.

9. **`test_stage10_cross_product_containment_matches_spec`**: For the worked example from §16.2 -- circle centered at (200, 200), radius 100, arc from `(200, 100)` to `(200, 300)` via `(300, 200)` -- verify that (300, 200) is contained and (100, 200) is not. Validates: cross-product test matches spec example.

10. **`test_stage10_near_tangent_intersection`**: Ray nearly tangent to a circle (discriminant near 0 but positive). Expected: returns valid intersection result with correct point. No NaN. Validates: §31 numerical stability for near-tangent cases.

11. **`test_stage10_near_parallel_ray`**: Ray nearly parallel to a line surface (direction vector within 1e-10 of the surface normal). Expected: returns no intersection or a very distant intersection. No NaN. Validates: §31 numerical stability for near-parallel cases.

### Interactive User Tests

- [ ] No visual change expected. Press Play and verify the game still runs identically to Stage 8.
- [ ] Run GUT. All tests from Stages 1-10 pass.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S8-infra | Forward-first ordering data (line-circle t values correct) | Unit test | Reinforced |
| S16 | No NaN/Inf in output | Unit test: discriminant edge cases produce finite results or empty arrays | Inherited |
| S1 | Cache: carrier-via round-trip | GUT (inherited) | Inherited |
| S11 | Three points on carrier | GUT (inherited) | Inherited |
| S12 | Side determination consistent | GUT (inherited) | Inherited |
| S17 | Provenance IDs unique | GUT (inherited) | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 9 | Line-line intersection: perpendicular, parallel, coincident, bounds | GUT tests |
| Stage 8 | TransformCache round-trip (S1), Point IDs unique (S17) | GUT tests |
| Stage 7 | Segment carrier derivation, side determination | GUT tests |
| Stage 6 | GeneralizedCircle methods correct | GUT tests |
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 4 | Direction/Ray construction | GUT tests |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run GUT |

### Expected Visual State

Identical to Stage 8. No visual changes -- this stage is pure math layer.

### Feedback Loop Protocol

AI implements -> runs tests -> user tests -> feedback -> automate -> fix -> repeat (standard protocol).

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
| `scripts/math/intersection.gd` | Modify | Add line-circle intersection case |
| `tests/test_stage10_intersection_line_circle.gd` | Create | Line-circle intersection unit tests |

---

## Stage 11: HitRecord and Hit Selection

### Overview
Implement the `HitRecord` data structure and the `find_all_hits` function that scans all segments, collects intersection candidates, and returns them all (selection/sorting is handled by `projective_sort` in the tracer). This stage also implements three-tier provenance endpoint detection (no epsilon) and the `origin_on_seg`/`origin_carrier` parameters for origin-segment handling.

> **Implementation note:** The original design planned a `find_earliest_hit(ray, surfaces, excluded_surfaces)` function that selected a single winner. The actual implementation uses `find_all_hits(ray, segments, origin_on_seg, origin_carrier)` which returns ALL hits, with `projective_sort` handling ordering in the tracer. The `excluded_surfaces` set was replaced by `skip_segment` (single segment) in the tracer. Origin-on-surface exclusion uses three-tier provenance endpoint detection instead of epsilon-based `t ≈ 0` filtering.

### Prerequisites
Stage 10 (full `intersect_line_with_gcircle` for both line and circle carriers).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Data class | `HitRecord` -- `t`, `point`, `segment`, `side`, `provenance` | §11.2 |
| Function | `find_all_hits(ray, segments, origin_on_seg, origin_carrier) -> Array[HitRecord]` | §11.3 |
| Algorithm | Returns all hits; ordering handled by `projective_sort` in the tracer | §11.3 |
| Behavior | Three-tier provenance endpoint detection (no epsilon): exact coord match, ray-defining-point match, cross-product collinearity | §11.4, §31.3.1 |
| Behavior | `origin_on_seg: Segment` parameter identifies the segment the ray originates from; `origin_carrier` provides its carrier | §11.4, §12.1 |
| Behavior | Side determination at hit point: evaluate carrier at a point slightly before hit along ray, determine LEFT/RIGHT | §9.2 |

### Unit Tests Added

1. **`test_stage11_hit_record_construction`**: Create a HitRecord with all fields. Verify fields are accessible and correct. Validates: data structure integrity.

2. **`test_stage11_earliest_hit_single_surface`**: Ray with one surface in front. Expected: HitRecord returned with correct t, point, surface, side. Validates: basic selection.

3. **`test_stage11_earliest_hit_two_surfaces_forward`**: Ray with two surfaces at `t=5` and `t=10`. Expected: surface at `t=5` wins. Validates: S8 forward-first ordering.

4. **`test_stage11_earliest_hit_only_behind`**: Ray with all surfaces behind (`t < 0`). Two surfaces at `t=-10` and `t=-5`. Expected: surface at `t=-10` wins (most negative = closest to infinity from back). Validates: S8 beyond-infinity selection.

5. **`test_stage11_earliest_hit_mixed`**: Ray with one surface at `t=50` (forward) and one at `t=-5` (behind). Expected: forward surface wins (t=50). Validates: S8 forward takes priority over beyond.

6. **`test_stage11_origin_exclusion`**: Ray origin exactly on a surface. Expected: that surface excluded from results (t approximately 0 hit ignored). Another surface further away is selected. Validates: §11.4 origin exclusion.

7. **`test_stage11_excluded_surfaces`**: Ray with two surfaces. One is in the `excluded_surfaces` set. Expected: excluded surface not in results; other surface selected. Validates: S9 exclusion respected.

8. **`test_stage11_no_hit_returns_null`**: Ray with no surfaces (empty scene) or all surfaces parallel. Expected: null returned. Validates: escape case.

9. **`test_stage11_tie_break_surface_id`**: Two surfaces at identical `t`. Surface with lower ID should win. Expected: lower-ID surface selected. Validates: deterministic tie-breaking.

10. **`test_stage11_side_determination_at_hit`**: Ray hits a vertical surface from the left. Expected: HitRecord.side == LEFT (or RIGHT, depending on segment traversal direction). Verify by computing side with a point slightly before hit along the ray. Validates: S12 side stored in hit record.

11. **`test_stage11_S9_double_exclusion`**: Both origin-exclusion and explicit `excluded_surfaces` active simultaneously. A surface is in `excluded_surfaces` AND the ray origin is on another surface. Expected: both excluded; third surface (if any) selected. Validates: S9 both mechanisms work together.

12. **`test_stage11_beyond_infinity_winning_hit`**: Scene where ALL surfaces are behind the ray (all t < 0). The closest-past-infinity surface (most negative t) is selected as the winner. Expected: HitRecord returned with negative t, correct surface. Validates: §11.3 beyond-infinity selection as winning hit.

### Interactive User Tests

- [ ] No visual change expected. Press Play and verify the game still runs identically to Stage 8.
- [ ] Run GUT. All tests from Stages 1-11 pass.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S8 | Forward-first hit ordering | Unit test: forward beats beyond; smallest positive t wins; most negative t wins among beyond | Yes (fully testable) |
| S9 | Exclusion respected | Unit test: excluded surfaces never in result | Yes (infrastructure) |
| S12 | Side determination consistent | Unit test: side in HitRecord matches cross-product formula | Reinforced |
| S16 | No NaN/Inf in output | Unit test | Inherited |
| S1 | Cache: carrier-via round-trip | GUT (inherited) | Inherited |
| S11 | Three points on carrier | GUT (inherited) | Inherited |
| S17 | Provenance IDs unique | GUT (inherited) | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 10 | Line-circle intersection: secant, tangent, miss, arc containment | GUT tests |
| Stage 9 | Line-line intersection: perpendicular, parallel, coincident, bounds | GUT tests |
| Stage 8 | TransformCache round-trip (S1), Point IDs unique (S17) | GUT tests |
| Stage 7 | Segment carrier derivation, side determination (S11, S12) | GUT tests |
| Stage 6 | GeneralizedCircle methods correct | GUT tests |
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 4 | Direction/Ray construction | GUT tests |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run GUT |

### Expected Visual State

Identical to Stage 8. No visual changes -- this stage is pure math layer.

### Feedback Loop Protocol

AI implements -> runs tests -> user tests -> feedback -> automate -> fix -> repeat (standard protocol).

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
| `scripts/math/intersection.gd` | Modify | Add HitRecord, find_all_hits, side determination at hit |
| `tests/test_stage11_hit_selection.gd` | Create | HitRecord and earliest-hit selection unit tests |

---

## Stage 12: Surface and SideConfig Data Classes

### Overview
Implement the `Surface` and `SideConfig` data classes that combine geometry (Segment) with policy (effects per side). A Surface has a stable unique ID (never reused), a Segment, left and right SideConfig objects, a ConfigResolver (defaulting to FixedResolver), `is_target`, and `player_solid` flags. SideConfig holds an effect (TransformativeEffect, ProjectiveEffect, TerminalEffect, or null for pass-through), an optional StateChange, and an `interactive` flag. This stage also introduces the FixedResolver and the `active_side_config` method.

### Prerequisites
Stage 11 (HitRecord, which references Surface; side determination, which references SideConfig).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/game/surface.gd` -- Surface data class | §9.1 |
| Script | `scripts/game/side_config.gd` -- SideConfig data class | §9.1 |
| Script | `scripts/game/config_resolver.gd` -- ConfigResolver base, FixedResolver | §9.4 |
| Property | `Surface.id: int` -- stable, unique, never reused | §9.3 |
| Property | `Surface.segment: Segment` | §9.1 |
| Property | `Surface.left: SideConfig` | §9.1 |
| Property | `Surface.right: SideConfig` | §9.1 |
| Property | `Surface.resolver: ConfigResolver` (default: FixedResolver) | §9.4 |
| Property | `Surface.is_target: bool` | §9.1 |
| Property | `Surface.player_solid: bool` (default: true) | §9.1, §25.1 |
| Property | `SideConfig.effect` -- one of TransformativeEffect, ProjectiveEffect, TerminalEffect, or null | §9.1 |
| Property | `SideConfig.state_change: StateChange or null` | §9.1, §10.6 |
| Property | `SideConfig.interactive: bool` | §9.1 |
| Method | `Surface.active_side_config(side, game_state) -> SideConfig` | §9.4 |
| Class | `FixedResolver` -- returns left if side==LEFT else right, ignores game_state | §9.4 |
| Script | `scripts/game/game_state.gd` -- GameState class with `flags: Dictionary[StringName, Variant]` and `copy() -> GameState` | §18.2 |
| Method | `GameState.copy() -> GameState` -- deep copy of all flags | §18.2 |

### Unit Tests Added

1. **`test_stage12_surface_construction`**: Create Surface with all fields. Verify `id`, `segment`, `left`, `right`, `is_target`, `player_solid` are accessible. Validates: data structure.

2. **`test_stage12_surface_id_unique`**: Create 50 surfaces. All IDs are distinct. Validates: ID uniqueness.

3. **`test_stage12_surface_id_never_reused`**: Create surfaces, store IDs, create more. No ID from the second batch matches any from the first. Validates: §9.3 never reused.

4. **`test_stage12_side_config_with_null_effect`**: SideConfig with `effect = null` (pass-through). `interactive` defaults to false. Validates: null effect is pass-through.

5. **`test_stage12_side_config_with_terminal`**: SideConfig with a TerminalEffect (stub). `interactive` defaults to false. Validates: terminal default.

6. **`test_stage12_fixed_resolver_left`**: FixedResolver with left config = X, right config = Y. `resolve(LEFT, any_state)` returns X. Validates: §9.4.

7. **`test_stage12_fixed_resolver_right`**: Same resolver. `resolve(RIGHT, any_state)` returns Y. Validates: §9.4.

8. **`test_stage12_active_side_config_delegates`**: Surface with FixedResolver. `active_side_config(LEFT, state)` returns left SideConfig. `active_side_config(RIGHT, state)` returns right SideConfig. Validates: delegation chain.

9. **`test_stage12_S12_surface_side_at_point`**: Create a Surface with a known segment. Determine side at a test point. Verify it matches the cross-product formula from §9.2. Validates: S12 through the Surface abstraction.

10. **`test_stage12_game_state_construction`**: Create GameState with flags `{"wall_intact": true}`. Expected: `flags["wall_intact"] == true`. Validates: §18.2 data structure.

11. **`test_stage12_game_state_copy_isolation`**: Create GameState, copy it, modify the original's flags. Expected: copy is unchanged. Validates: deep copy semantics for trace isolation.

### Interactive User Tests

- [ ] No visual change expected. Press Play and verify the game still runs identically to Stage 8.
- [ ] Run GUT. All tests from Stages 1-12 pass.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S12 | Side determination consistent through Surface abstraction | Unit test: active_side_config returns correct config for LEFT/RIGHT | Reinforced |
| S16 | No NaN/Inf in output | Unit test | Inherited |
| S8 | Forward-first hit ordering | GUT (inherited from Stage 11) | Inherited |
| S9 | Exclusion respected | GUT (inherited from Stage 11) | Inherited |
| S1 | Cache: carrier-via round-trip | GUT (inherited) | Inherited |
| S11 | Three points on carrier | GUT (inherited) | Inherited |
| S17 | Provenance IDs unique | GUT (inherited) | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 11 | HitRecord construction, earliest hit selection, exclusion | GUT tests |
| Stage 10 | Line-circle intersection | GUT tests |
| Stage 9 | Line-line intersection | GUT tests |
| Stage 8 | TransformCache round-trip (S1), Point IDs unique (S17) | GUT tests |
| Stage 7 | Segment carrier derivation, side determination (S11, S12) | GUT tests |
| Stage 6 | GeneralizedCircle methods correct | GUT tests |
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 4 | Direction/Ray construction | GUT tests |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run GUT |

### Expected Visual State

Identical to Stage 8. No visual changes -- this stage introduces data classes only.

### Feedback Loop Protocol

AI implements -> runs tests -> user tests -> feedback -> automate -> fix -> repeat (standard protocol).

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
| `scripts/game/surface.gd` | Create | Surface data class with ID, segment, configs, resolver |
| `scripts/game/side_config.gd` | Create | SideConfig data class |
| `scripts/game/config_resolver.gd` | Create | ConfigResolver base class and FixedResolver |
| `scripts/math/effects/terminal.gd` | Create | TerminalEffect stub (marker class, no logic yet) |
| `scripts/game/game_state.gd` | Create | GameState data class with flags dictionary and deep copy |
| `tests/test_stage12_surface.gd` | Create | Surface and SideConfig unit tests |

---

## Stage 13: Room Boundary Surfaces (Block Effect)

### Overview
Create four block surfaces forming a rectangular room boundary (e.g., 800x600) and render them as red lines. The `TerminalEffect` (block) stops the ray with no outgoing ray and no frame update. Surfaces with `player_solid = true` get `SegmentShape2D` collision shapes so the player cannot walk through walls. This is the first stage with visible surface geometry beyond the preview line. The player was already physically constrained by collision bodies (Stage 2.5); this stage adds Surfaces that constrain both the player AND the arrow. Surfaces with `player_solid = true` generate `SegmentShape2D` collision shapes that coexist with the collision bodies from Stage 2.5.

**Relationship to collision bodies (Stage 2.5):** Collision bodies remain functional. Surfaces with `player_solid = true` add additional collision shapes that also block the player. The key difference: Surfaces interact with the arrow tracing system (the ray stops at a TerminalEffect); collision bodies do not.

### Prerequisites
Stage 12 (Surface, SideConfig, TerminalEffect stub, player_solid flag).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/effects/terminal.gd` -- TerminalEffect (full implementation: marker class that stops the ray) | §10.5 |
| Scene element | 4 block surfaces forming room boundary (e.g., 800x600 centered on viewport) | §18.1 (Principle 7) |
| Script | `scripts/game/surface_node.gd` -- Node2D that holds a Surface and renders it via `_draw()` | §20.4 |
| Rendering | Surfaces drawn as colored lines: block = Red, 3px width | §22.2, §22.4 |
| Collision | `SegmentShape2D` for line surfaces with `player_solid = true` | §25.1 |
| Behavior | Player `move_and_slide()` collides with room walls | §25.1 |
| Behavior | TerminalEffect: stops the ray, no outgoing ray, no frame update | §10.5 |

### Unit Tests Added

1. **`test_stage13_terminal_effect_exists`**: TerminalEffect can be instantiated. It has no `get_mobius()` method (it is not transformative). Validates: correct interface.

2. **`test_stage13_room_has_four_surfaces`**: The room scene contains exactly 4 surfaces. Validates: room boundary setup.

3. **`test_stage13_all_room_surfaces_are_block`**: Each room surface has TerminalEffect on both sides (left and right). Validates: block on all sides.

4. **`test_stage13_room_surfaces_player_solid`**: Each room surface has `player_solid == true`. Validates: player collision enabled.

5. **`test_stage13_room_forms_closed_rectangle`**: The four surfaces form a closed rectangle. Each surface's end connects to the next surface's start (or the surfaces tile to enclose a rectangular area). Validates: no gaps in the boundary.

6. **`test_stage13_surface_rendered_red`**: SurfaceNode for a block surface uses Red color for drawing. Validates: §22.2 color scheme.

7. **`test_stage13_surface_line_width`**: SurfaceNode draws with 3px line width. Validates: §22.4.

8. **`test_stage13_player_collision_with_wall`**: Simulate player moving toward a wall surface. After `move_and_slide()`, player position does not pass through the wall. Validates: UX9 (block stops player) and collision.

9. **`test_stage13_UX9_block_stops_ray`**: Create a ray aimed at a block surface. Call `find_all_hits`. The hit's surface has a TerminalEffect. The trace should stop at this hit (trace loop integration tested in Stage 14, but the data is verifiable here). Validates: UX9.

10. **`test_stage13_player_solid_false`**: Create a surface with `player_solid = false`. Player walks through it (no collision). Arrow tracing still interacts with it (`find_all_hits` returns it as a hit). Validates: §9.1, §25.1.

11. **`test_stage13_terminal_does_not_reset_frame`**: Trace through a transformative effect then hit a terminal surface. Expected: frame at terminal step is the composed frame (not identity). Terminal simply ends the path without resetting. Validates: §10.7. *(Forward placeholder — becomes meaningful at Stage 20b when transformative effects exist.)*

### Interactive User Tests **[BEHAVIORAL -- USER SIGN-OFF REQUIRED]**

- [ ] Press Play. Four red lines appear forming a rectangular room boundary.
- [ ] Move the player with WASD. The player cannot walk through any of the four walls.
- [ ] Move the player to each wall. The player slides along the wall (does not stick or jitter).
- [ ] The green preview line from player to cursor is still visible inside the room.
- [ ] Move the cursor outside the room boundary. The green line extends to (and stops at or crosses) the wall, but the player remains inside.
- [ ] Verify the red lines have visible thickness (not hairline).
- [ ] Place a surface with player_solid=false. Walk through it -- player passes through. Fire arrow at it -- arrow interacts normally (blocks/reflects based on effect).
- [ ] Verify collision bodies from Stage 2.5 still work -- player collides with them, but the arrow preview passes through them (the preview line does not stop at collision bodies).

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| UX9 | Block stops arrow (and player) | Unit test: ray hits block surface; interactive test: player cannot pass through walls | Yes |
| S12 | Side determination consistent | GUT (inherited) | Inherited |
| S8 | Forward-first hit ordering | GUT (inherited) | Inherited |
| S9 | Exclusion respected | GUT (inherited) | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |
| S1 | Cache: carrier-via round-trip | GUT (inherited) | Inherited |
| S11 | Three points on carrier | GUT (inherited) | Inherited |
| S17 | Provenance IDs unique | GUT (inherited) | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 12 | Surface/SideConfig construction, FixedResolver | GUT tests |
| Stage 11 | HitRecord, earliest hit selection, exclusion | GUT tests |
| Stage 10 | Line-circle intersection | GUT tests |
| Stage 9 | Line-line intersection | GUT tests |
| Stage 8 | TransformCache round-trip (S1), Point IDs unique (S17) | GUT tests |
| Stage 7 | Segment carrier derivation, side determination (S11, S12) | GUT tests |
| Stage 6 | GeneralizedCircle methods correct | GUT tests |
| Stage 5 | Green line from player to cursor | Move mouse, verify line still visible |
| Stage 4 | Direction/Ray construction | GUT tests |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run GUT |

### Expected Visual State

Dark background. Four red lines forming a rectangular room. Player (triangle) inside the room at center. Crosshair at mouse position. Green solid line from player to cursor. Player cannot walk outside the red boundary. This is the first time the player is spatially constrained.

### Feedback Loop Protocol

AI implements -> runs tests -> user tests -> feedback -> automate -> fix -> repeat (standard protocol).

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
| `scripts/math/effects/terminal.gd` | Modify | Full TerminalEffect implementation (marker class) |
| `scripts/game/surface_node.gd` | Create | Surface rendering via `_draw()` with effect-based coloring |
| `scenes/main.tscn` | Modify | Add 4 room boundary surface nodes with SegmentShape2D collision |
| `scripts/game/player.gd` | Modify | Ensure `move_and_slide()` interacts with surface collision shapes |
| `tests/test_stage13_room_boundary.gd` | Create | Room boundary and block effect unit tests |

---

## Stage 14: Physical Trace (Single Step)

### Overview
Implement the `trace()` function from §12.1, but initially limited to a single iteration: find the first hit, record a Step, and stop. This introduces the Step data structure (start, end, frame, hit), TracedPath (steps array, targets_hit set), and the critical rule that `trace()` operates on a COPY of game state so mutations within the trace do not affect the caller's state. The Mobius frame is identity for now (no transformative effects yet). The Step data class stores `frame_id: int` (referencing the identity constant id=0 for now). Full MobiusTransform operations (apply, compose, invert) are introduced in Stage 20.

The trace loop at this stage implements ONLY the terminal/block and null/pass-through branches. The TransformativeEffect branch (which calls `frame.compose()`) and the ProjectiveEffect branch are **deferred to Stage 21** when the full MobiusTransform exists. The loop should contain `assert(false, 'TransformativeEffect/ProjectiveEffect branch not implemented until Stage 20b/73. This surface has an unexpected effect type at this stage.')` in the TransformativeEffect and ProjectiveEffect branches — a hard error rather than silent pass-through. This catches accidental early use of unimplemented effects. The asserts are removed when Stage 20b implements transformative handling and Stage 73+ implements projective handling.

**Forward dependency:** Step records store `frame_id: int` referencing the IDENTITY constant (id=0). Stage 20's full MobiusTransform implementation must preserve id=0 as the identity transform. Tests in Stages 14-19 depend on this.

### Prerequisites
Stage 13 (room boundary surfaces exist, TerminalEffect stops the ray, `find_all_hits` functional).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/tracer.gd` -- `trace()` function (single-step initial version) | §12.1 |
| Data class | `Step` -- `start: Vector2, end: Vector2, frame: MobiusTransform, hit: HitRecord or null` | §12.2, §14.7 |
| Data class | `TracedPath` -- `steps: Array[Step], targets_hit: Set[int]` | §14.7 |
| Behavior | `trace()` operates on a COPY of game_state | §12.1 |
| Behavior | Single iteration: find first hit, create Step, stop | §12.1 (limited) |
| Behavior | Frame is `MobiusTransform.IDENTITY` (placeholder -- no transforms yet) | §12.1 |
| Behavior | Target tracking: if hit surface is_target, add to targets_hit | §12.1, §24.2 |
| Script | `scripts/math/mobius_transform.gd` -- IDENTITY constant only (id=0, conformal, [[1,0],[0,1]]). Full implementation deferred to Stage 20. | §5.2 |

### Unit Tests Added

1. **`test_stage14_trace_single_step_hits_wall`**: Player at (400, 300), cursor at (800, 300). Room has right wall at x=800. Expected: TracedPath with 1 step, step.start=(400,300), step.end on right wall, step.hit is not null, step.hit.surface is the right wall. Validates: basic trace.

2. **`test_stage14_trace_returns_traced_path`**: Verify return type is TracedPath with `steps` array and `targets_hit` set. Validates: data structure.

3. **`test_stage14_step_has_identity_frame`**: The step's frame is the identity MobiusTransform. Validates: frame initialization.

4. **`test_stage14_trace_copies_game_state`**: Pass a GameState to `trace()`. Modify the GameState inside a surface's state_change. After trace returns, the original GameState is unchanged. Validates: §12.1 copy semantics, S19 (trace preserves real state -- partially testable).

5. **`test_stage14_trace_target_tracking`**: Scene with a target surface (pass-through, `is_target=true`). Ray hits it. Expected: `targets_hit` contains the target surface's ID. Validates: §24.2.

6. **`test_stage14_trace_no_hit_escape`**: Scene with no surfaces (or ray aimed at a gap). Expected: TracedPath with 1 step, step.end = Vector2(INF, INF), step.hit = null. Validates: escape case.

7. **`test_stage14_S3_determinism`**: Call `trace()` twice with identical inputs. Expected: both TracedPaths have identical step counts, step start/end points, and hit surface IDs. Validates: S3 (determinism).

8. **`test_stage14_trace_terminal_stops`**: Ray hits a TerminalEffect surface. Expected: TracedPath has exactly 1 step; no further steps beyond the terminal. Validates: block stops trace.

9. **`test_stage14_S16_no_nan_in_trace`**: Trace result has no NaN or Inf in any step's start or end (except the INF escape sentinel). Validates: S16.

10. **`test_stage14_trace_game_state_nested_copy`**: GameState.flags contains `{"config": {"nested": [1, 2]}}`. Run trace. During trace, a state change modifies `config.nested`. After trace, verify the original GameState's nested array is unchanged (still `[1, 2]`). Validates: trace operates on a true deep copy, not a shallow copy with aliased nested structures.

### Interactive User Tests

- [ ] No visual change expected yet (the trace is computed but not rendered -- that comes in Stage 15). Press Play and verify the game still looks like Stage 13 (red walls, player, green line).
- [ ] Run GUT. All tests from Stages 1-14 pass.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S3 | Determinism: same inputs produce identical step trees | Unit test: two identical trace calls produce identical results | Yes |
| S16 | No NaN/Inf in output | Unit test: trace results checked | Reinforced |
| UX9 | Block stops arrow | Unit test: terminal effect stops trace | Reinforced |
| S8 | Forward-first hit ordering | GUT (inherited) | Inherited |
| S9 | Exclusion respected | GUT (inherited) | Inherited |
| S12 | Side determination consistent | GUT (inherited) | Inherited |
| S1 | Cache: carrier-via round-trip | GUT (inherited) | Inherited |
| S11 | Three points on carrier | GUT (inherited) | Inherited |
| S17 | Provenance IDs unique | GUT (inherited) | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 13 | Room boundary: 4 red walls, player collision, block effect | Interactive: player cannot leave room |
| Stage 12 | Surface/SideConfig construction, FixedResolver | GUT tests |
| Stage 11 | HitRecord, earliest hit selection, exclusion | GUT tests |
| Stage 10 | Line-circle intersection | GUT tests |
| Stage 9 | Line-line intersection | GUT tests |
| Stage 8 | TransformCache round-trip (S1), Point IDs unique (S17) | GUT tests |
| Stage 7 | Segment carrier derivation, side determination | GUT tests |
| Stage 6 | GeneralizedCircle methods correct | GUT tests |
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 4 | Direction/Ray construction | GUT tests |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run GUT |

### Expected Visual State

Identical to Stage 13. The trace is computed internally but not yet rendered (Stage 15 replaces the simple green line with the trace-based preview). Red walls, player, green line, cursor.

### Feedback Loop Protocol

AI implements -> runs tests -> user tests -> feedback -> automate -> fix -> repeat (standard protocol).

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
| `scripts/math/tracer.gd` | Create | `trace()` function (single-step version) |
| `scripts/math/mobius_transform.gd` | Create | IDENTITY constant stub only -- full class in Stage 20 |
| `tests/test_stage14_trace.gd` | Create | Physical trace unit tests |

---

## Stage 15: Full Preview (Player to Wall)

### Overview
Replace the Stage 5 simple green line with a real traced preview. The preview now consists of two parts: a green solid line from the player to the cursor (ALIGNED segment for an empty plan), and a green dashed line from the cursor to the first wall hit (ALIGNED_POST_PLANNED with empty plan, per §14.9). This stage implements dashed line rendering (alternating 10px on / 5px off segments) and connects the path renderer to the trace system.

**Performance visibility:** Starting from this stage, the trace computation runs every frame. While formal performance testing is deferred to Stage 66, implementers should log trace computation time (via `Time.get_ticks_usec()`) during development to catch early signs of performance problems. A trace that takes >5ms at this stage (with only 4 surfaces) would indicate a fundamental efficiency problem.

**Cache lifecycle during preview:** The preview runs `trace()` every frame. The TransformCache should be cleared at the start of each preview frame (before the planned + physical traces run) to avoid stale entries from the previous cursor position. This is distinct from the per-shot cache clearing (§17.5). Preview-frame clearing is necessary for correctness when the cursor moves — cached transform results from the old cursor position are invalid for the new one.

### Prerequisites
Stage 14 (trace produces Steps and TracedPath).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Rendering | Traced preview replaces simple green line | §4.3, §14.9 |
| Rendering | Green solid line: player to cursor (ALIGNED) | §4.3, §22.2 |
| Rendering | Green dashed line: cursor to first wall hit (ALIGNED_POST_PLANNED) | §4.3, §14.9 |
| Algorithm | Dashed line rendering: alternating 10px on / 5px off | §22.2 |
| Behavior | Empty plan: all physical trace steps classified as ALIGNED_POST_PLANNED per §14.9 | §14.9 |
| Behavior | Preview solid portion: player to cursor (the aim direction) | §4.3 |
| Behavior | Preview dashed portion: cursor to first hit (continuation) | §4.3 |
| Behavior | Escape ray rendering: step with `end = Vector2(INF, INF)` renders as line from start toward viewport edge -- never passes INF to `draw_line()` | §12.3 |

### Unit Tests Added

1. **`test_stage15_preview_has_solid_and_dashed`**: With an empty plan, the preview contains at least one solid segment (player to cursor) and at least one dashed segment (cursor to wall). Validates: two-part preview.

2. **`test_stage15_solid_line_player_to_cursor`**: The solid portion starts at the player position and ends at (or near) the cursor position. Color is green. Validates: UX7 (solid path to cursor).

3. **`test_stage15_dashed_line_cursor_to_wall`**: The dashed portion starts at the cursor position and ends at the first wall hit. Color is green. Validates: post-planned continuation.

4. **`test_stage15_dashed_pattern`**: The dashed rendering produces alternating on/off segments. Verify at least one gap exists in the dashed portion for a sufficiently long line. Validates: dashed style is visually distinguishable.

5. **`test_stage15_UX11_empty_plan_fires_straight`**: With no plan, the preview shows a straight line from the player through the cursor to the wall. No bends, no curves. The direction is player->cursor extended. Validates: UX11 (empty plan = fire straight).

6. **`test_stage15_UX7_solid_path_leads_to_cursor`**: The solid-colored path forms a continuous line from the player to the cursor. Validates: UX7.

7. **`test_stage15_preview_updates_on_cursor_move`**: Move the cursor. The preview (both solid and dashed) updates to reflect the new direction. Validates: real-time update.

8. **`test_stage15_preview_absent_when_zero_length`**: Cursor at player position. No preview drawn (no solid, no dashed). Validates: §8.3 degenerate case.

9. **`test_stage15_escape_ray_rendering`**: Trace in an open scene where the ray escapes (no hit on any surface). The visual path renders the escape step as a line from the last point in the direction of travel, extending to the viewport edge. Validates: §12.3.

10. **`test_stage15_escape_ray_no_inf_in_draw`**: The path renderer never calls `draw_line()` with INF coordinates. Escape steps are converted to viewport-edge-clipped line segments before drawing. Validates: S16 (no NaN/Inf in rendering output).

11. **`test_stage15_arrow_ignores_collision_bodies`**: Place a collision body (`StaticBody2D` with `CollisionShape2D`) between the player and a wall Surface. Trace a ray. Expected: the ray passes through the collision body and hits the wall Surface. The collision body is not in the `surfaces` array and is not returned by `find_all_hits`. Validates: collision bodies are invisible to the arrow system.

12. **`test_stage15_cache_fresh_each_preview_frame`**: Compute preview at cursor position A (populates cache). Move cursor to position B. Compute preview again. Expected: results at B are correct (not contaminated by A's cached values). Validates: cache clearing between preview frames.

13. **`test_stage15_manual_overrides_survive_preview_clearing`**: Add a manual cache override. Compute preview (clears non-override entries). Expected: override entry is still in the cache. Validates: §17.4 overrides persist across preview frames.

### Interactive User Tests **[BEHAVIORAL -- USER SIGN-OFF REQUIRED]**

- [ ] Press Play. Move the mouse away from the player. A green solid line extends from the player to the cursor, and a green dashed line continues from the cursor to the nearest wall.
- [ ] Move the mouse around. Both solid and dashed lines update in real time.
- [ ] The solid line is clearly solid (continuous). The dashed line has visible gaps (alternating on/off pattern).
- [ ] Move the cursor close to the player. The solid line becomes very short; the dashed line becomes very long.
- [ ] Move the cursor exactly onto the player. All lines disappear.
- [ ] Move the cursor toward a corner of the room. The dashed line should extend to the corner wall.
- [ ] Move the player with WASD while the mouse is stationary. Both solid and dashed lines adjust as the player moves.
- [ ] The red room boundary walls are still visible and the player still cannot walk through them.
- [ ] Fire toward an open area (if no room boundaries exist yet, the ray escapes). The dashed green line extends to the viewport edge and stops cleanly. No crash or visual artifact.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| UX7 | Solid path from player to cursor | Unit test + interactive: solid green line connects player to cursor | Enhanced (now trace-based) |
| UX11 | Empty plan = fire straight | Unit test + interactive: straight line through cursor to wall | Enhanced (now trace-based) |
| S3 | Determinism | GUT (inherited) | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |
| UX9 | Block stops arrow | Interactive: dashed line stops at wall | Reinforced |
| S8 | Forward-first hit ordering | GUT (inherited) | Inherited |
| S9 | Exclusion respected | GUT (inherited) | Inherited |
| S12 | Side determination consistent | GUT (inherited) | Inherited |
| S1 | Cache: carrier-via round-trip | GUT (inherited) | Inherited |
| S11 | Three points on carrier | GUT (inherited) | Inherited |
| S17 | Provenance IDs unique | GUT (inherited) | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 14 | trace() produces correct TracedPath with Steps | GUT tests |
| Stage 13 | Room boundary: 4 red walls, player collision | Interactive: walls visible, player constrained |
| Stage 12 | Surface/SideConfig construction | GUT tests |
| Stage 11 | HitRecord, earliest hit selection | GUT tests |
| Stage 10 | Line-circle intersection | GUT tests |
| Stage 9 | Line-line intersection | GUT tests |
| Stage 8 | TransformCache round-trip (S1) | GUT tests |
| Stage 7 | Segment carrier derivation, side determination | GUT tests |
| Stage 6 | GeneralizedCircle methods | GUT tests |
| Stage 5 | (Replaced) Simple green line is now replaced by trace-based preview | N/A -- superseded by this stage |
| Stage 4 | Direction/Ray construction | GUT tests |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run GUT |

### Expected Visual State

Dark background. Four red walls forming a rectangular room. Player (triangle) at center. Crosshair at mouse position. Green solid line from player to cursor. Green dashed line from cursor to the nearest wall. Both lines update in real time. This is the first time the preview shows post-cursor continuation.

### Feedback Loop Protocol

AI implements -> runs tests -> user tests -> feedback -> automate -> fix -> repeat (standard protocol).

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
| `scripts/visual/path_renderer.gd` | Modify | Replace simple line with trace-based preview (solid + dashed) |
| `scripts/visual/path_renderer.gd` | Modify | Add dashed line rendering function |
| `scripts/math/tracer.gd` | Modify | Expose trace for preview use (cursor split point) |
| `tests/test_stage15_preview.gd` | Create | Trace-based preview unit tests |

---

## Stage 16: Multi-Hit Trace Loop

### Overview
Extend `trace()` from a single-step function to a full loop: while `hit_count < 32`, keep finding hits. This stage implements the stage-based hitpoint walk where all carrier intersections are precomputed per "stage" and walked in projective order. Pass-through handling continues the ray from the hit point with the same direction. The TerminalEffect causes the trace to stop.

> **Implementation note:** The original design planned an `excluded_surfaces` set that accumulated pass-through surfaces and reset after non-pass-through hits. The actual implementation uses a stage-based hitpoint walk with `skip_segment` (single segment, reference equality) — only the most recently hit segment is skipped, and the next stage clears it. See GAME_SPEC.md §12.1 for the current architecture.

### Prerequisites
Stage 15 (single-step trace works, preview renders traced path).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Algorithm | Stage-based hitpoint walk: `while hit_count < 32` | §12.1, §12.6 |
| Behavior | Pass-through handling: ray continues from hit point with same direction | §12.1 |
| Behavior | `skip_segment` (single segment) replaces `excluded_surfaces` set | §12.1 |
| Behavior | All hits count toward 32 limit including pass-through | §12.6 |
| Behavior | TerminalEffect stops the trace | §12.1 |
| Behavior | Null effect (pass-through): no frame change, no direction change, ray continues from hit point | §10.7 |
| Constant | `MAX_HITS = 32` | §12.6 |

### Unit Tests Added

1. **`test_stage16_trace_multiple_walls`**: Room with additional interior pass-through surface. Ray passes through the pass-through surface and then hits a wall. Expected: TracedPath with 2 steps (pass-through + wall hit). Validates: multi-hit loop.

2. **`test_stage16_pass_through_excluded_then_reset`**: Ray hits a pass-through surface. On the next iteration, that surface is in `excluded_surfaces` (ray does not re-hit it). After hitting a non-pass-through surface, `excluded_surfaces` is cleared. Validates: S9 exclusion mechanics.

3. **`test_stage16_pass_through_counts_toward_limit`**: Scene with many overlapping pass-through surfaces. Verify that pass-through hits increment `hit_count`. After 32 total hits (all pass-through), the trace terminates. Validates: §12.6.

4. **`test_stage16_terminal_stops_loop`**: Ray hits a block surface on its second step (first step is pass-through). Expected: TracedPath has exactly 2 steps; loop did not continue past the terminal. Validates: TerminalEffect breaks loop.

5. **`test_stage16_max_32_hits`**: Construct a scenario with many overlapping pass-through surfaces. Expected: trace stops at exactly 32 hits. Validates: 32 limit enforced.

6. **`test_stage16_S9_excluded_surfaces_not_in_results`**: After a pass-through hit, the next `find_all_hits` call does not return the just-passed-through surface. Validates: S9.

7. **`test_stage16_escape_after_pass_through`**: Pass-through surface with no wall behind it. Ray passes through and escapes. Expected: 2 steps (pass-through hit + escape step with end=INF). Validates: escape after pass-through.

8. **`test_stage16_multiple_consecutive_pass_throughs`**: Three pass-through surfaces in a row. Ray passes through all three, then hits a wall. Expected: 4 steps. `excluded_surfaces` grows with each pass-through (surfaces 1, 1+2, 1+2+3). Validates: cumulative exclusion for consecutive pass-throughs.

9. **`test_stage16_S3_determinism_multi_step`**: Call multi-step trace twice with identical inputs. Results are identical. Validates: S3 for multi-step traces.

10. **`test_stage16_excluded_reset_sequence`**: Three surfaces in ray path: A (pass-through), B (pass-through), C (reflection). Ray passes through A (A added to excluded). Passes through B (A+B excluded). Hits C (reflection, non-pass-through -- excluded_surfaces reset to empty). Ray continues and encounters A again. Expected: A appears twice in the trace (no longer excluded after C's hit reset). Validates: §12.1 exclusion reset on non-pass-through.

11. **`test_stage16_ray_wraps_through_infinity`**: Create a scene with a gap in the room boundaries (e.g., only 3 walls, open on one side). A surface exists on the "other side" of infinity (behind the ray origin). Fire a ray toward the open side. Expected: ray escapes forward, wraps through infinity, and hits the surface behind the origin (negative t is the winning hit per §11.3). The traced path includes this beyond-infinity hit. Validates: §6.3 lines through infinity behavior in an actual trace.

12. **`test_stage16_three_surfaces_same_t`**: Three surfaces positioned so the ray hits all three at the same parameter t. Expected: tie-breaking by surface ID selects the lowest ID. Other two are ignored for this cast. Validates: §11.3 multi-way ties.

13. **`test_stage16_ray_through_segment_endpoint`**: Ray passes exactly through a segment's start or end point. Expected: hit recorded at the endpoint. Side determination is well-defined. Validates: §11.1 endpoint inclusion in trace context.

14. **`test_stage16_full_circle_segment_in_trace`**: Surface with a full-circle segment (start == end after full traversal). Trace hits it. Expected: all points on the carrier are valid hits (§11.1 full-circle containment). Validates: full-circle trace behavior.

15. **`test_stage16_beyond_infinity_identity_frame_visual`**: Ray escapes with M=I (identity frame). Expected: the preview extends to the viewport edge and renders cleanly. No crash, no NaN in the rendering path. Validates: §12.5 case 1 (M=I) visual behavior.

### Interactive User Tests

- [ ] Press Play. The preview (solid + dashed green lines) should still render correctly from player to cursor to wall.
- [ ] If an interior pass-through surface is added to the scene for testing: the dashed preview line should pass through it without stopping and continue to the wall behind it.
- [ ] The red walls still stop the preview (dashed line ends at the wall).
- [ ] Run GUT. All tests from Stages 1-16 pass.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S9 | Exclusion respected (pass-through surfaces excluded then reset) | Unit test: excluded surfaces never re-hit within same pass-through chain | Enhanced (fully testable) |
| S3 | Determinism | Unit test: multi-step traces are deterministic | Reinforced |
| S8 | Forward-first hit ordering | GUT (inherited) | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |
| UX9 | Block stops arrow | Unit test: terminal breaks loop | Reinforced |
| S12 | Side determination consistent | GUT (inherited) | Inherited |
| S1 | Cache: carrier-via round-trip | GUT (inherited) | Inherited |
| S11 | Three points on carrier | GUT (inherited) | Inherited |
| S17 | Provenance IDs unique | GUT (inherited) | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 15 | Preview: solid player-to-cursor + dashed cursor-to-wall | Interactive: both segments visible |
| Stage 14 | Single-step trace produces correct TracedPath | GUT tests |
| Stage 13 | Room boundary: 4 red walls, player collision | Interactive: walls visible, player constrained |
| Stage 12 | Surface/SideConfig construction | GUT tests |
| Stage 11 | HitRecord, earliest hit selection | GUT tests |
| Stage 10 | Line-circle intersection | GUT tests |
| Stage 9 | Line-line intersection | GUT tests |
| Stage 8 | TransformCache round-trip (S1) | GUT tests |
| Stage 7 | Segment carrier derivation, side determination | GUT tests |
| Stage 6 | GeneralizedCircle methods | GUT tests |
| Stage 4 | Direction/Ray construction | GUT tests |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run GUT |

### Expected Visual State

Identical to Stage 15 (preview behavior is the same for the room-only scene). The multi-hit loop is exercised internally but produces the same visual result in a scene with only block walls. If a pass-through surface is added for testing, the preview line passes through it seamlessly.

### Feedback Loop Protocol

AI implements -> runs tests -> user tests -> feedback -> automate -> fix -> repeat (standard protocol).

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
| `scripts/math/tracer.gd` | Modify | Extend trace() to multi-hit loop with pass-through handling |
| `tests/test_stage16_multi_hit.gd` | Create | Multi-hit trace loop unit tests |

---

## Stage 17: Arrow Shooting (Fire Button)

### Overview
Implement the fire action (Spacebar). When fired, game time freezes (`get_tree().paused = true`), the physical trace is computed, and an arrow is animated along the traced path. The arrow is a line segment (~40u) with a triangular head (30 degree angle, ~16u), rotating to follow the path tangent. The arrow lerps from start to end per step at 1600 u/s constant speed. After animation, the arrow disappears (no fade), game time unfreezes, and the preview reappears. Fire is a no-op if cursor == player (zero-length Direction). The arrow animator has `process_mode = PROCESS_MODE_ALWAYS` to run during pause.

### Prerequisites
Stage 16 (full multi-hit trace loop produces TracedPath).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Input | Fire action: Spacebar | §4.1 |
| Behavior | Game time freeze: `get_tree().paused = true` | §21.1, Principle 25 |
| Script | `scripts/game/arrow_animator.gd` -- arrow flight animation | §21.2 |
| Rendering | Arrow visual: line segment (~40u) + triangular head (30 degree, ~16u) | §22.1 |
| Behavior | Arrow lerps along traced path at 1600 u/s constant speed | §21.2 |
| Behavior | Arrow rotates to follow tangent direction | §22.1 |
| Behavior | Arrow disappears after animation (no fade) | §21.4 |
| Behavior | Game time unfreeze after animation complete | §21.1 |
| Behavior | `process_mode = PROCESS_MODE_ALWAYS` on arrow animator | §21.1 |
| Behavior | No-op if cursor == player (zero-length Direction) | §4.1, §8.3 |
| Behavior | Preview hidden during flight, reappears after | §21.1 |
| Constant | `ARROW_SPEED = 1600` u/s | §21.2 |
| Constant | `ARROW_LENGTH = 40` units | §22.1 |
| Constant | `ARROW_HEAD_ANGLE = 30` degrees | §22.1 |
| Constant | `ARROW_HEAD_LENGTH = 16` units | §22.1 |

### Unit Tests Added

1. **`test_stage17_fire_pauses_tree`**: Simulate fire action. Expected: `get_tree().paused == true` after fire and before animation completes. Validates: Principle 25.

2. **`test_stage17_fire_unpauses_after_animation`**: After arrow animation completes, `get_tree().paused == false`. Validates: game time unfreezes.

3. **`test_stage17_fire_noop_zero_length`**: Cursor at player position. Fire action. Expected: no arrow spawned, game not paused, no trace computed. Validates: §8.3 degenerate case.

4. **`test_stage17_arrow_speed_constant`**: Arrow travels at 1600 u/s. For a step of length 1600u, the animation takes approximately 1 second. Validates: §21.2.

5. **`test_stage17_arrow_follows_traced_path`**: Fire the arrow. Record the arrow's positions during animation. Expected: positions lie on the traced path (start to end of each step in sequence). Validates: UX3 (preview matches flight).

6. **`test_stage17_arrow_disappears_after_flight`**: After animation completes, the arrow node is no longer visible or is removed. Validates: §21.4.

7. **`test_stage17_preview_hidden_during_flight`**: During arrow animation, the preview (solid + dashed lines) is not drawn. Validates: §21.1.

8. **`test_stage17_preview_reappears_after_flight`**: After arrow animation completes and game unfreezes, the preview reappears. Validates: §21.1.

9. **`test_stage17_arrow_animator_process_mode`**: Arrow animator node has `process_mode == PROCESS_MODE_ALWAYS`. Validates: runs during pause.

10. **`test_stage17_UX4_same_shot_same_result`**: Fire from the same position/cursor twice (after reset). Both produce identical traced paths. Validates: UX4 (same shot = same result).

11. **`test_stage17_UX9_arrow_stops_at_block`**: Fire toward a block wall. Arrow animation ends at the wall hit point. Arrow does not pass through. Validates: UX9.

12. **`test_stage17_UX3_preview_matches_flight`**: Compare the preview's rendered path (pre-fire) with the arrow's actual flight path (during fire). They follow the same geometric path. Validates: UX3.

13. **`test_stage17_arrow_rotates_to_tangent`**: Arrow visual rotates to match the direction of travel at each point along the path. Validates: §22.1 tangent rotation.

14. **`test_stage17_arrow_unaffected_by_gravity`**: With `LevelData.gravity = (0, 980)`, fire arrow. Expected: arrow follows geometric ray trace with no gravity deflection — straight line to wall, no curve. Validates: §25.2 "The arrow is never affected by gravity." *(Deferred from Stage 2.5 where the arrow system did not exist.)*

15. **`test_stage17_arrow_origin_at_collision_center`**: Fire arrow. Expected: the initial ray origin equals the center of the player's CircleShape2D collision shape (`player.position`, since the shape is centered). Validates: §25.1 "arrow originates from center of player's collision shape."

16. **`test_stage17_flight_active_nodes_process_mode`**: During arrow flight (game paused), verify ALL nodes that must run have `process_mode = PROCESS_MODE_ALWAYS`: arrow animator, camera (for tracking). Validates: correct pause behavior for all flight-time-active nodes.

17. **`test_stage17_gamepad_fire`**: Simulate trigger input (gamepad). Expected: arrow fires identically to Spacebar. Validates: §4.1 gamepad fire.

### Interactive User Tests **[BEHAVIORAL -- USER SIGN-OFF REQUIRED]**

- [ ] Press Play. Move the cursor away from the player. Press Spacebar.
- [ ] Game freezes (player stops responding to WASD, cursor may or may not track -- but player movement is paused).
- [ ] An arrow appears and flies from the player toward the cursor and then continues to the wall.
- [ ] The arrow has a visible line body and a triangular head.
- [ ] The arrow rotates to point in the direction of travel.
- [ ] The arrow hits the red wall and stops. The arrow disappears.
- [ ] Game unfreezes. Player can move again with WASD.
- [ ] The preview (solid green + dashed green) reappears after the shot.
- [ ] During arrow flight, the preview lines are hidden.
- [ ] Move the cursor to the player position. Press Spacebar. Nothing happens (no-op).
- [ ] Fire multiple times from different positions. Each shot is consistent (arrow follows the preview path).
- [ ] Set gravity to (0, 980). Fire arrow. Arrow flies in a straight line (no gravity curve). Validates: ARROW-GRAV invariant (documented Stage 2.5, first testable here).

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| UX3 | Preview matches flight | Unit test + interactive: arrow follows the same path as the preview | Yes |
| UX4 | Same shot = same result | Unit test: identical inputs produce identical traces | Yes |
| UX9 | Block stops arrow | Unit test + interactive: arrow stops at block wall | Reinforced |
| Principle 25 | Simulation instantaneous, presentation animated | Unit test: tree paused during flight, unpaused after | Yes |
| S3 | Determinism | GUT (inherited) | Inherited |
| S8 | Forward-first hit ordering | GUT (inherited) | Inherited |
| S9 | Exclusion respected | GUT (inherited) | Inherited |
| S16 | No NaN/Inf in output | GUT (inherited) | Inherited |
| S12 | Side determination consistent | GUT (inherited) | Inherited |
| S1 | Cache: carrier-via round-trip | GUT (inherited) | Inherited |
| S11 | Three points on carrier | GUT (inherited) | Inherited |
| S17 | Provenance IDs unique | GUT (inherited) | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 16 | Multi-hit trace loop, pass-through, 32 limit | GUT tests |
| Stage 15 | Preview: solid player-to-cursor + dashed cursor-to-wall | Interactive: preview reappears after shot |
| Stage 14 | Single-step trace, TracedPath structure | GUT tests |
| Stage 13 | Room boundary: 4 red walls, player collision | Interactive: walls visible, player constrained |
| Stage 12 | Surface/SideConfig construction | GUT tests |
| Stage 11 | HitRecord, earliest hit selection | GUT tests |
| Stage 10 | Line-circle intersection | GUT tests |
| Stage 9 | Line-line intersection | GUT tests |
| Stage 8 | TransformCache round-trip (S1) | GUT tests |
| Stage 7 | Segment carrier derivation, side determination | GUT tests |
| Stage 6 | GeneralizedCircle methods | GUT tests |
| Stage 4 | Direction/Ray construction | GUT tests |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run GUT |

### Expected Visual State

Dark background. Four red walls. Player inside room. Cursor and preview lines as before. When Spacebar is pressed: preview disappears, an arrow (line + triangular head) flies from the player through the cursor direction to the wall, stops, disappears. Preview reappears. Player can move again. This is the first "playable" firing mechanic.

### Feedback Loop Protocol

AI implements -> runs tests -> user tests -> feedback -> automate -> fix -> repeat (standard protocol).

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
| `scripts/game/arrow_animator.gd` | Create | Arrow flight animation (lerp along traced path, visual rendering) |
| `scripts/game/player.gd` | Modify | Add fire input handling (Spacebar), trigger trace and animation |
| `scripts/game/game_manager.gd` | Create | Shot lifecycle: freeze, trace, animate, unfreeze |
| `scripts/visual/path_renderer.gd` | Modify | Support hiding/showing preview during flight |
| `scenes/main.tscn` | Modify | Add arrow animator node, wire up game manager |
| `tests/test_stage17_arrow.gd` | Create | Arrow shooting and flight animation unit tests |

---

## Stage 18: Animation Skip

### Overview
Implement animation skip: any non-movement key pressed during arrow flight instantly completes the animation, applies all remaining state changes, and returns the camera to the player. WASD during flight is ignored (no movement, no skip). Fire (Spacebar) during flight only skips the animation -- it does not queue a new shot. A new shot requires a separate Fire press after the animation completes and game time unfreezes.

### Prerequisites
Stage 17 (arrow flight animation, game time freeze/unfreeze).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Behavior | Skip animation: any non-movement key during flight completes instantly | §21.1 |
| Behavior | WASD during flight: ignored (no movement, no skip) | §21.1 |
| Behavior | Fire during flight: skips animation only (does not queue new shot) | §21.1 |
| Behavior | Skip applies all remaining state changes immediately | §21.1 |
| Behavior | After skip, game time unfreezes normally | §21.1 |
| Behavior | New shot requires separate Fire press after animation completes | §21.1 |

### Unit Tests Added

1. **`test_stage18_skip_with_non_movement_key`**: During flight, simulate pressing a non-movement key (e.g., Enter, E, Q). Expected: animation completes immediately. Arrow disappears. Game unfreezes. Validates: skip behavior.

2. **`test_stage18_wasd_ignored_during_flight`**: During flight, simulate pressing W. Expected: animation continues (not skipped). Player does not move. Validates: WASD ignored.

3. **`test_stage18_fire_during_flight_skips`**: During flight, simulate pressing Spacebar. Expected: animation skips (completes immediately). No new shot is queued or fired. Validates: fire-as-skip.

4. **`test_stage18_new_shot_requires_separate_press`**: After animation completes (via skip or natural end), verify that a new Spacebar press is required to fire again. The skip press does not trigger a second shot. Validates: no shot queuing.

5. **`test_stage18_skip_applies_state_changes`**: Arrow has a traced path with state changes (e.g., a pass-through surface with a state_change). Skip during flight. Expected: all state changes from the full trace are applied. Validates: complete state promotion on skip.

6. **`test_stage18_skip_unfreezes_game`**: After skip, `get_tree().paused == false`. Player can move. Validates: unfreeze after skip.

7. **`test_stage18_skip_hides_arrow`**: After skip, arrow is no longer visible. Validates: arrow disappears on skip.

8. **`test_stage18_preview_reappears_after_skip`**: After skip and unfreeze, preview reappears. Validates: preview restoration.

9. **`test_stage18_Principle25_skip_consistent`**: Skip at any point during the animation produces the same final game state as letting the animation complete naturally. Validates: Principle 25 (simulation is instantaneous; skip does not alter outcome).

10. **`test_stage18_left_click_ignored_during_flight`**: Simulate left-click (add to plan) during arrow flight. Expected: plan unchanged. Validates: plan inputs locked during flight.

11. **`test_stage18_right_click_ignored_during_flight`**: Simulate right-click during arrow flight. Expected: plan unchanged (no removal, no clear). Validates: plan inputs locked during flight.

12. **`test_stage18_clear_key_ignored_during_flight`**: Simulate C key during arrow flight. Expected: plan unchanged. Validates: plan inputs locked during flight.

13. **`test_stage18_escape_ignored_during_flight`**: Press Escape during arrow flight. Expected: pause menu does NOT open (game is already paused via `get_tree().paused`). The Escape key is ignored during flight. Validates: flight-pause and menu-pause don't conflict.

### Interactive User Tests **[BEHAVIORAL -- USER SIGN-OFF REQUIRED]**

- [ ] Press Play. Fire the arrow (Spacebar). While the arrow is in flight, press Enter (or any non-WASD key). The arrow animation instantly completes -- the arrow disappears and the game unfreezes.
- [ ] Fire again. While in flight, press W. The animation continues. The player does not move. The arrow does not skip.
- [ ] Fire again. While in flight, press Spacebar. The animation skips. No second shot fires automatically.
- [ ] After the skip, press Spacebar again. A new shot fires normally.
- [ ] Fire again. Let the animation complete naturally (do not press any key). Verify the game unfreezes and the preview reappears -- same as after a skip.
- [ ] Verify that WASD works normally after the animation completes (whether skipped or natural).

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| Principle 25 | Skip produces same outcome as natural completion | Unit test: state after skip == state after natural completion | Reinforced |
| UX3 | Preview matches flight | GUT (inherited) | Inherited |
| UX4 | Same shot = same result | GUT (inherited) | Inherited |
| UX9 | Block stops arrow | GUT (inherited) | Inherited |
| S3 | Determinism | GUT (inherited) | Inherited |
| S8 | Forward-first hit ordering | GUT (inherited) | Inherited |
| S9 | Exclusion respected | GUT (inherited) | Inherited |
| S16 | No NaN/Inf in output | GUT (inherited) | Inherited |
| S12 | Side determination consistent | GUT (inherited) | Inherited |
| S1 | Cache: carrier-via round-trip | GUT (inherited) | Inherited |
| S11 | Three points on carrier | GUT (inherited) | Inherited |
| S17 | Provenance IDs unique | GUT (inherited) | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 17 | Arrow fires on Spacebar, flies along trace, disappears, unfreezes | Interactive: fire and observe |
| Stage 16 | Multi-hit trace loop, pass-through, 32 limit | GUT tests |
| Stage 15 | Preview: solid + dashed green lines | Interactive: preview visible before and after shot |
| Stage 14 | Single-step trace, TracedPath | GUT tests |
| Stage 13 | Room boundary: 4 red walls, player collision | Interactive: walls visible, player constrained |
| Stage 12 | Surface/SideConfig construction | GUT tests |
| Stage 11 | HitRecord, earliest hit selection | GUT tests |
| Stage 10 | Line-circle intersection | GUT tests |
| Stage 9 | Line-line intersection | GUT tests |
| Stage 8 | TransformCache round-trip (S1) | GUT tests |
| Stage 7 | Segment carrier derivation, side determination | GUT tests |
| Stage 6 | GeneralizedCircle methods | GUT tests |
| Stage 4 | Direction/Ray construction | GUT tests |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run GUT |

### Expected Visual State

Same as Stage 17 during normal play. When fire is pressed and immediately skipped, the arrow appears briefly (or not at all if skip is fast enough) and disappears. Game returns to normal play state. Preview reappears. Red walls, player, cursor, green preview lines all present and functional.

### Feedback Loop Protocol

AI implements -> runs tests -> user tests -> feedback -> automate -> fix -> repeat (standard protocol).

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
| `scripts/game/arrow_animator.gd` | Modify | Add skip logic (complete immediately on non-movement key) |
| `scripts/game/game_manager.gd` | Modify | Handle skip input, prevent shot queuing |
| `tests/test_stage18_skip.gd` | Create | Animation skip unit tests |

---

## Appendix A: Invariant Introduction Map (Stages 1-18)

This table tracks all 30 invariants. Columns show when each was introduced, when it first became testable, and its status after Stage 18.

| Invariant | Full ID | Introduced | First Testable | Status After Stage 18 |
|-----------|---------|-----------|----------------|----------------------|
| Carrier-via round-trip | S1 | Stage 8 | Stage 8 | Tested (line + circle) |
| Transform round-trip | S2 | -- | -- | Not yet introduced |
| Determinism | S3 | Stage 14 | Stage 14 | Tested (single + multi-step) |
| Divergence monotonic | S4 | -- | -- | Not yet introduced |
| Aligned provenance | S5 | -- | -- | Not yet introduced |
| Aligned match | S6 | -- | -- | Not yet introduced |
| Per-entry state | S7 | -- | -- | Not yet introduced |
| Forward-first ordering | S8 | Stage 9 (infra) | Stage 11 (fully) | Tested |
| Exclusion respected | S9 | Stage 11 (infra) | Stage 16 (fully) | Tested |
| Projective resets frame | S10 | -- | -- | Not yet introduced |
| Three points on carrier | S11 | Stage 7 | Stage 7 | Tested |
| Side determination | S12 | Stage 7 | Stage 7 | Tested (through Surface abstraction) |
| Visibility no self-intersect | S13 | -- | -- | Not yet introduced |
| Visibility edges on geometry | S14 | -- | -- | Not yet introduced |
| Visibility non-overlapping | S15 | -- | -- | Not yet introduced |
| No NaN/Inf in output | S16 | Stage 4 | Stage 4 | Tested (Direction, Ray, intersection, trace) |
| Provenance IDs unique | S17 | Stage 8 | Stage 8 | Tested |
| Frame determinant non-zero | S18 | -- | -- | Not yet introduced |
| Trace preserves real state | S19 | Stage 14 (partial) | Stage 14 | Partially tested (copy semantics verified) |
| Visibility predicts non-div. | UX1 | -- | -- | Not yet introduced |
| Divergence implies outside vis. | UX2 | -- | -- | Not yet introduced |
| Preview matches flight | UX3 | Stage 17 | Stage 17 | Tested |
| Same shot = same result | UX4 | Stage 17 | Stage 17 | Tested |
| Undo fully restores | UX5 | -- | -- | Not yet introduced |
| All targets reachable | UX6 | -- | -- | Not yet introduced |
| Solid path to cursor | UX7 | Stage 5 (partial) | Stage 15 (enhanced) | Tested (trace-based) |
| Block stops arrow | UX9 | Stage 13 | Stage 13 | Tested (player + arrow) |
| State changes visible | UX10 | -- | -- | Not yet introduced |
| Empty plan = fire straight | UX11 | Stage 5 (partial) | Stage 15 (enhanced) | Tested (trace-based) |

**Summary after Stage 18:**
- **Actively tested:** S1, S3, S8, S9, S11, S12, S16, S17, UX3, UX4, UX7, UX9, UX11 (13 invariants)
- **Partially tested:** S19 (1 invariant)
- **Not yet introduced:** S2, S4, S5, S6, S7, S10, S13, S14, S15, S18, UX1, UX2, UX5, UX6, UX8, UX10 (16 invariants)

---

## Appendix B: Cumulative Test Count After Stage 18

| Stage | Unit Tests Added | Interactive Tests Added | Running Unit Total | Running Interactive Total |
|-------|-----------------|------------------------|--------------------|--------------------------|
| 1 | 1 | 4 | 1 | 4 |
| 2 | 5 | 8 | 6 | 12 |
| 3 | 2 | 4 | 8 | 16 |
| 4 | 6 | 1 | 14 | 17 |
| 5 | 4 | 7 | 18 | 24 |
| 6 | 7 | 1 | 25 | 25 |
| 7 | 9 | 1 | 34 | 26 |
| 8 | 16 | 2 | 50 | 28 |
| **9** | **9** | **2** | **59** | **30** |
| **10** | **11** | **2** | **70** | **32** |
| **11** | **12** | **2** | **82** | **34** |
| **12** | **11** | **2** | **93** | **36** |
| **13** | **11** | **7** | **104** | **43** |
| **14** | **9** | **2** | **113** | **45** |
| **15** | **10** | **9** | **123** | **54** |
| **16** | **15** | **4** | **138** | **58** |
| **17** | **16** | **11** | **154** | **69** |
| **18** | **12** | **6** | **166** | **75** |

| Category | Count After Stage 18 |
|----------|---------------------|
| Unit tests | ~166 |
| Interactive test items | ~75 |
| Invariants actively tested | 13 (S1, S3, S8, S9, S11, S12, S16, S17, UX3, UX4, UX7, UX9, UX11) |
| Invariants partially covered | 1 (S19) |
| Invariants not yet introduced | 16 |

**Note on Stages 1-8 counts:** The unit test counts from prior stages (Stages 1-8: ~50 total) reflect the updated baseline from TDD Document 1 (41 original + 9 from the gravity stage). The figures above use these as the starting point. Stages 9-18 add approximately 116 new unit tests and 47 new interactive test items.
