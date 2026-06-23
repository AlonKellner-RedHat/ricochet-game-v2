# TDD Document 1: Foundation

**Stages 1–8** | Project bootstrap, empty room, player, cursor, math primitives, first straight-line preview

**Fractional stage ordering:** Stages 2.5, 42.5, and 49.5 were inserted after the initial plan. They are ordered between their integer neighbors: Stage 2 → Stage 2.5 → Stage 3. The regression test policy includes fractional stages in sequence.

### Stage Status
| Stage | Topic | Status |
|-------|-------|--------|
| 1 | Godot Project Skeleton | Done |
| 2 | Empty Room with Player | Done |
| 2.5 | Gravity-Aware Movement and Jump | Done |
| 3 | Cursor Tracking | Done |
| 4 | Direction and Ray Data Classes | Done |
| 5 | Straight-Line Preview (Player to Cursor) | Done |
| 6 | GeneralizedCircle Data Class | Done |
| 7 | Segment Data Class with Via Point | Done |
| 8 | Computation Cache (Provenance System) | Done |

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

**Note on regression items:** Interactive tests like "Press Play, game still runs" and "Run GUT, all tests pass" are implicit in the regression test policy. They appear in early stages for clarity but should be treated as covered by the automated test suite in later stages. Focus manual testing on behaviors that require visual or tactile judgment.

**Deferred Test Tracking:** Some tests are documented in early stages but deferred to later stages. Verify at each target stage that the deferred test was implemented.

| Test | Documented In | Deferred To | Status |
|------|--------------|-------------|--------|
| Arrow unaffected by gravity | Stage 2.5 | Stage 17 | [ ] |
| Collision body not in surfaces | Stage 2.5 | Stage 15 | [ ] |
| Camera bounds during arc flight | Stage 31 | Stage 42+ | [ ] |
| Escape ray during flight animation | Stage 15 | Stage 67 | [ ] |

---

## Stage 1: Godot Project Skeleton

### Overview
Initialize the Godot 4.6 project with the correct directory structure and testing framework. This stage produces a runnable project that shows a colored background and can execute (empty) test suites. No game logic yet — just the skeleton. All subsequent stages should use the command-line runner for regression testing, not manual GUT panel clicks.

### Prerequisites
None (first stage).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Project file | `project.godot` (Godot 4.6 project configuration) | §20.1 |
| Directory | `scripts/math/` | §20.2 |
| Directory | `scripts/math/effects/` | §20.2 |
| Directory | `scripts/visual/` | §20.2 |
| Directory | `scripts/game/` | §20.2 |
| Directory | `scenes/` | §20.2 |
| Directory | `scenes/levels/` | §20.2 |
| Directory | `scenes/ui/` | §20.2 |
| Directory | `scenes/editor/` | §20.2 |
| Directory | `resources/levels/` | §20.2 |
| Directory | `tests/` | §29 |
| Test framework | GUT (Godot Unit Test) installed and configured | §29 |
| Scene | `scenes/main.tscn` — minimal scene with a ColorRect background | §20.2 |
| Convention | Error handling policy: debug builds assert+crash on invariant violations, release builds log+recover gracefully | §31.8 |
| Tooling | GUT command-line runner: `godot --headless --script addons/gut/gut_cmdln.gd`. All subsequent stages use this for regression testing. | §29 |

### Unit Tests Added

1. **`test_stage1_gut_runs`**: Run the GUT test suite. Input: no test files. Expected: GUT reports 0 tests, 0 failures, exits cleanly. Validates: test infrastructure is functional.
2. **`test_stage1_gut_cmdline_runs`**: Run GUT from command line (headless mode). Expected: exits with code 0, reports 0 tests. Validates: automated test runner works without the editor.
3. **`test_stage1_math_layer_no_node_dependencies`**: Scan all files in `scripts/math/`. Verify none extend `Node`, `Node2D`, `Node3D`, `Control`, or any scene-tree-dependent type. Only `RefCounted`, `Object`, or no `extends` allowed. Validates: §20.1 "The math layer has zero Godot engine dependencies beyond Vector2."

### Interactive User Tests

- [ ] Open the project in Godot 4.6 editor. It loads without errors.
- [ ] Press Play (F5). A window appears with a solid colored background (e.g., dark gray or black).
- [ ] Close the game window. Godot returns to the editor without errors.
- [ ] Run GUT from the editor (Scene > Run GUT). GUT panel shows "0 tests ran, 0 failed."

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| (none) | No gameplay invariants yet — bootstrap stage | — | — |

### Regression Checklist

No prior stages — nothing to regress.

### Expected Visual State

A full-screen window with a solid dark background. No sprites, no UI, no text. The window is 1920×1080 (project setting) or windowed at a smaller default size.

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
| `project.godot` | Create | Godot project configuration (viewport 1920×1080, GUT plugin enabled) |
| `scenes/main.tscn` | Create | Main scene with ColorRect background |
| `scripts/math/` | Create dir | Math layer directory |
| `scripts/math/effects/` | Create dir | Effects subdirectory |
| `scripts/visual/` | Create dir | Visual layer directory |
| `scripts/game/` | Create dir | Game layer directory |
| `scenes/levels/` | Create dir | Level scenes |
| `scenes/ui/` | Create dir | UI scenes |
| `scenes/editor/` | Create dir | Editor scenes |
| `resources/levels/` | Create dir | Level data resources |
| `tests/` | Create dir | Test scripts |
| `addons/gut/` | Install | GUT testing framework plugin |
| `run_tests.sh` | Create | Shell script for headless GUT test execution |

---

## Stage 2: Empty Room with Player

### Overview
Add a player character that can move freely with WASD in a gravity-free space. The player is a `CharacterBody2D` with a small circle collision shape and a triangle visual. There are no room boundaries yet — the player can walk off screen. This is the first "playable" state.

### Prerequisites
Stage 1 (project skeleton).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Scene | `scenes/player.tscn` — CharacterBody2D with CircleShape2D and triangle visual | §25.1, §25.4 |
| Script | `scripts/game/player.gd` — WASD movement, zero gravity, 200 u/s, instant response | §25.2 |
| Constant | `Player.SPEED = 200` | §25.2 |
| Constant | `Player.COLLISION_RADIUS = 12` | §25.1 |
| Scene update | `scenes/main.tscn` — instantiates player at center (960, 540) | §25.3 |

### Unit Tests Added

1. **`test_stage2_player_speed_constant`**: `Player.SPEED == 200`. Validates: §25.2 default speed.
2. **`test_stage2_player_collision_radius`**: `Player.collision_shape.radius == 12`. Validates: §25.1 collision shape.
3. **`test_stage2_player_initial_position`**: Player spawns at the configured spawn point. Input: spawn at (960, 540). Expected: `player.position == Vector2(960, 540)`.
4. **`test_stage2_player_moves_on_input`**: Simulate WASD input. Expected: position changes by `SPEED * delta` in the correct direction per frame. No acceleration ramp (instant response).
5. **`test_stage2_simultaneous_movement`**: Simulate W+D simultaneously. Expected: diagonal movement at correct speed (normalized diagonal vector × SPEED).
6. **`test_stage2_gamepad_movement`**: Simulate left stick input. Expected: player moves in the corresponding direction at 200 u/s. Validates: §4.1 gamepad movement.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Press Play. A small triangle (the player) appears at the center of the screen.
- [ ] Press W. Player moves up. Movement is instant (no acceleration ramp).
- [ ] Press S. Player moves down.
- [ ] Press A. Player moves left.
- [ ] Press D. Player moves right.
- [ ] Press W+D simultaneously. Player moves diagonally up-right at consistent speed.
- [ ] Release all keys. Player stops immediately (no deceleration/momentum).
- [ ] Hold W for several seconds. Player moves off the top of the screen (no boundaries yet — this is expected).

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| P16-partial | Movement does not lock any other system | Manual (no other systems yet) | Yes |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 1 | Project loads without errors | Open in Godot editor |
| Stage 1 | GUT runs with 0 failures | Run GUT suite |

### Expected Visual State

Dark background. A small white/light triangle at the center of the screen. Triangle moves smoothly in response to WASD input. No room boundaries, no cursor, no lines.

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
| `scenes/player.tscn` | Create | Player scene (CharacterBody2D + CollisionShape2D + visual) |
| `scripts/game/player.gd` | Create | Player movement script |
| `scenes/main.tscn` | Modify | Add player instance at (960, 540) |
| `tests/test_stage2_player.gd` | Create | Player unit tests |

---

## Stage 2.5: Gravity-Aware Movement and Jump

### Overview
Implement gravity-aware movement mode. When `LevelData.gravity != Vector2(0, 0)`, player movement switches from 4-directional WASD to horizontal-only AD with jump (W/Up). Jump velocity is 400 u/s upward, single jump only, no coyote time, no double jump. The arrow is NEVER affected by gravity — it follows pure geometric ray tracing regardless of the level's gravity setting.

This stage also introduces **collision bodies** (`StaticBody2D` + `CollisionShape2D`) — plain Godot physics nodes for player collision. These are NOT Surfaces — they are invisible to arrow/visibility systems (which do not exist yet). A floor collision body is placed at the bottom of the test scene for gravity testing.

**Note:** This stage references `LevelData.gravity` but the formal `LevelData` resource class is not created until Stage 57. At this stage, gravity is configured via a temporary mechanism (e.g., a project setting, an export variable on the main scene, or a simple dictionary). The formal LevelData integration happens at Stage 57.

### Prerequisites
Stage 2 (player with zero-gravity WASD movement).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Behavior | Gravity-aware movement: AD horizontal only when `LevelData.gravity != (0,0)` | §4.1, §25.2 |
| Behavior | Jump: W / Up / left-stick-up, 400 u/s upward, single jump | §25.2 |
| Behavior | No double jump, no coyote time | §25.2 |
| Behavior | Gravity from `LevelData.gravity` applied via `move_and_slide()` | §25.2 |
| Behavior | Zero-gravity mode (existing, unchanged): WASD 4-directional | §25.2 |
| Constant | `Player.JUMP_VELOCITY = 400` | §25.2 |
| Behavior | Arrow is never affected by gravity | §25.2 |
| Scene element | Floor collision body: `StaticBody2D` with `SegmentShape2D` at bottom of test scene | §25.1 |
| Concept | Collision bodies: plain physics nodes for player collision, independent of the Surface system | §25.1 |

### Unit Tests Added

1. **`test_stage2_5_gravity_horizontal_only`**: Set `LevelData.gravity = Vector2(0, 980)`. Simulate W press. Expected: player jumps (initial upward velocity), does NOT move upward continuously like zero-gravity W. Validates: §25.2.
2. **`test_stage2_5_jump_velocity`**: With gravity=(0,980), press W. Expected: `player.velocity.y == -400` on the frame of jump. Validates: §25.2 jump velocity constant.
3. **`test_stage2_5_single_jump_no_double`**: With gravity, jump, then press W again while airborne. Expected: no second jump. Player continues arc. Validates: §25.2 single jump.
4. **`test_stage2_5_no_coyote_time`**: Walk off a platform edge. Press W one frame after leaving the edge. Expected: no jump (already airborne). Validates: §25.2 no coyote time.
5. **`test_stage2_5_horizontal_ad_only`**: With gravity, press S. Expected: no downward movement (S is ignored with gravity). Press A/D. Expected: horizontal movement works. Validates: §4.1.
6. **`test_stage2_5_zero_gravity_unchanged`**: With `LevelData.gravity = Vector2(0, 0)`, WASD movement identical to Stage 2 behavior. All four directions work. Validates: backward compatibility.
7. **`test_stage2_5_gravity_from_level_data`**: Load level with gravity=(0, 500). Expected: player falls with acceleration 500 u/s². Validates: `LevelData.gravity` is used.
8. **`test_stage2_5_arrow_unaffected_by_gravity`**: *(Deferred to Stage 17.)* This test requires the arrow firing system, which is introduced at Stage 17. At that stage, add: with gravity=(0,980), fire arrow → follows geometric ray trace, no gravity deflection. This stage documents the ARROW-GRAV invariant but cannot test it yet.
9. **`test_stage2_5_platform_landing`**: With gravity, player falls and lands on a collision body (`StaticBody2D` with `SegmentShape2D` placed as a floor). Expected: player stops on the collision body, `velocity.y = 0`. Validates: player collision with simple geometry.
10. **`test_stage2_5_collision_body_not_in_surfaces`**: A collision body exists in the scene. It is NOT present in any surfaces array/registry. Validates: collision bodies are architecturally separate from Surfaces. *(The actual arrow-ignores-collision-bodies test is added at Stage 15 when ray tracing exists.)*

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Set gravity to (0, 980). Player falls to the floor (a collision body at the bottom of the scene).
- [ ] Press A. Player moves left (horizontal only).
- [ ] Press D. Player moves right (horizontal only).
- [ ] Press W. Player jumps upward, then falls back down due to gravity.
- [ ] Press W while airborne (mid-jump). Nothing happens — no double jump.
- [ ] Press S. Nothing happens — S is ignored when gravity is active.
- [ ] Set gravity to (0, 0). WASD works exactly as in Stage 2 — all four directions, no gravity.
- [ ] *(Arrow-gravity interactive test moved to Stage 17 where the arrow system exists. See ARROW-GRAV invariant.)*

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| P16-partial | Movement and aiming are independent | Manual: move player + mouse simultaneously | Reinforced |
| ARROW-GRAV | Arrow is never affected by gravity | Documented here, first tested Stage 17 (arrow system does not exist yet) | Yes |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 2 | Player moves with WASD in zero gravity | Set gravity to (0,0), press WASD |
| Stage 2 | Player speed is 200 u/s, instant response | Hold key, observe |
| Stage 1 | GUT runs | Run test suite |

### Expected Visual State

With gravity active: dark background, a floor collision body at the bottom of the scene. Player falls to the floor, moves horizontally with A/D, jumps with W. With zero gravity: identical to Stage 2.

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
| `scripts/game/player.gd` | Modify | Add gravity-aware movement, jump, and gravity mode detection |
| `scenes/main.tscn` | Modify | Add StaticBody2D floor collision body at bottom of viewport for gravity testing |
| `tests/test_stage2_5_gravity.gd` | Create | Gravity and jump unit tests |

---

## Stage 3: Cursor Tracking

### Overview
Add a crosshair that follows the mouse position in world space. The cursor uses `get_global_mouse_position()` to ensure world-space coordinates regardless of camera offset. The cursor is a simple visual indicator (crosshair or dot) that updates every frame.

### Prerequisites
Stage 2 (player exists to provide spatial context).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/game/cursor.gd` — tracks mouse in world space, renders crosshair | §4.1 |
| Scene element | Cursor node added to main scene (Node2D child) | §22.1 |
| Behavior | `get_global_mouse_position()` for world-space conversion | §4.1 |

### Unit Tests Added

1. **`test_stage3_cursor_world_space`**: Simulate mouse at screen position. Expected: cursor position matches `get_global_mouse_position()` result, not raw screen coordinates.
2. **`test_stage3_cursor_updates_every_frame`**: Cursor position changes when mouse moves between frames.
3. **`test_stage3_initial_cursor_at_spawn`**: If the mouse hasn't moved since level load, cursor defaults to the player's spawn position. If the mouse has moved, cursor is at the mouse world position. Validates: §3.4 "If the mouse hasn't moved, the cursor defaults to the player's spawn position."
4. **`test_stage3_player_triangle_faces_cursor`**: Player visual (triangle) rotates to point toward the cursor position. Move cursor to player's right → triangle points right. Move cursor above → triangle points up. Validates: §25.4 "triangle pointing toward cursor."
5. **`test_stage3_gamepad_aim`**: Simulate right stick input. Expected: cursor/aim position updates accordingly. Validates: §4.1 gamepad aiming.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Press Play. A crosshair/dot appears at the current mouse position.
- [ ] Move the mouse. The crosshair follows the mouse precisely, with no lag.
- [ ] Move the player with WASD while moving the mouse. Both player and crosshair move independently and simultaneously (Principle 16).
- [ ] Move the mouse to the edge of the screen. Crosshair is visible at the edge.
- [ ] Move the mouse around the player. The player triangle rotates to always point toward the cursor.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| P16-partial | Movement and aiming are independent | Manual: move player + mouse simultaneously | Reinforced |
| CURSOR-WORLD | Cursor is always in world coordinates | Unit test | Yes |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 2 | Player moves with WASD | Press WASD, observe movement |
| Stage 2 | Player speed is 200 u/s, instant response | Hold key, observe |
| Stage 1 | GUT runs | Run test suite |

### Expected Visual State

Dark background. Triangle (player) at center. Crosshair/dot at the mouse position. Both respond to their respective inputs. No lines, no surfaces.

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
| `scripts/game/cursor.gd` | Create | Cursor tracking and rendering |
| `scenes/main.tscn` | Modify | Add cursor node |
| `tests/test_stage3_cursor.gd` | Create | Cursor unit tests |

---

## Stage 4: Direction and Ray Data Classes

### Overview
Implement the two core geometric primitives for ray tracing: `Direction` (an immutable two-point line orientation) and `Ray` (an origin point + a Direction). These are pure math-layer classes with zero Godot engine dependencies beyond `Vector2`. This stage also implements zero-length Direction detection for the degenerate case where cursor equals player position.

### Prerequisites
Stage 3 (cursor exists, providing the use case for Direction from player to cursor).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/direction.gd` — Direction class (two-point, immutable, RefCounted) | §8.2 |
| Script | `scripts/math/ray.gd` — Ray class (origin + Direction) | §8.3 |
| Property | `Direction.start: Vector2` | §8.2 |
| Property | `Direction.end: Vector2` | §8.2 |
| Property | `Ray.origin: Vector2` | §8.3 |
| Property | `Ray.direction: Direction` | §8.3 |
| Method | `Direction.is_zero_length() -> bool` | §8.3 |

### Unit Tests Added

1. **`test_stage4_direction_construction`**: `Direction.new(Vector2(0,0), Vector2(1,0))` creates valid Direction with correct start/end. Validates: §8.2.
2. **`test_stage4_direction_immutability`**: Direction properties cannot be modified after creation (RefCounted, no setters). Validates: §8.2 "Immutable once created."
3. **`test_stage4_direction_zero_length`**: `Direction.new(Vector2(5,5), Vector2(5,5)).is_zero_length() == true`. Validates: §8.3 degenerate case.
4. **`test_stage4_direction_nonzero`**: `Direction.new(Vector2(0,0), Vector2(1,0)).is_zero_length() == false`. Validates: normal case.
5. **`test_stage4_ray_construction`**: `Ray.new(origin, direction)` stores origin and direction correctly.
6. **`test_stage4_ray_preserves_direction_reference`**: Two Rays sharing the same Direction hold the same reference (not a copy). Validates: §8.2 "Shared across all ray propagation steps."

### Interactive User Tests

- [ ] No visual change expected. Press Play and verify the game still runs identically to Stage 3 (player moves, cursor tracks).

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S16 | No NaN/Inf in output | Unit test: Direction with finite inputs produces finite outputs | Yes |
| DIR-IMMUT | Direction is immutable after creation | Unit test | Yes |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 3 | Cursor follows mouse in world space | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run test suite |

### Expected Visual State

Identical to Stage 3. No visual changes — this stage is pure math layer.

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
| `scripts/math/direction.gd` | Create | Direction data class |
| `scripts/math/ray.gd` | Create | Ray data class |
| `tests/test_stage4_direction_ray.gd` | Create | Direction and Ray unit tests |

---

## Stage 5: Straight-Line Preview (Player to Cursor)

### Overview
Draw a single green solid line from the player position to the cursor position using Godot's `_draw()` API. This is the first visual connection between the player and the cursor — the beginning of the trajectory preview system. The line updates every frame via `queue_redraw()`. When the cursor is at the player position (zero-length Direction), no line is drawn.

### Prerequisites
Stage 4 (Direction class, zero-length detection).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/visual/path_renderer.gd` — draws preview paths via `_draw()` | §20.4 |
| Behavior | Green solid line from player to cursor, 2px width | §22.2 (ALIGNED = green, solid), §22.4 |
| Behavior | `queue_redraw()` every frame cursor moves | §20.4 |
| Behavior | No line drawn when cursor == player (zero-length Direction) | §8.3 |

### Unit Tests Added

1. **`test_stage5_preview_exists_when_cursor_differs`**: When cursor != player, the renderer has draw data (at least one line segment). Validates: preview draws.
2. **`test_stage5_preview_absent_when_cursor_equals_player`**: When cursor == player, the renderer has no draw data. Validates: §8.3 degenerate case.
3. **`test_stage5_preview_color_green`**: Line color is green (`Color.GREEN` or the ALIGNED color constant). Validates: §22.2.
4. **`test_stage5_preview_endpoints`**: Line starts at player position and ends at cursor position. Validates: correct geometry.

### Interactive User Tests **[BEHAVIORAL — USER SIGN-OFF REQUIRED]**

- [ ] Press Play. Move the mouse away from the player. A green solid line appears from the player to the cursor.
- [ ] Move the mouse around. The line follows the cursor in real time with no visible lag.
- [ ] Move the cursor very close to the player. The line gets very short.
- [ ] Move the cursor exactly onto the player (or as close as possible). The line disappears.
- [ ] Move the cursor away again. The line reappears.
- [ ] Move the player with WASD while the mouse is stationary. The line's start point follows the player.
- [ ] Move both player (WASD) and cursor (mouse) simultaneously. Both ends of the line update smoothly.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| UX11-partial | Empty plan = fire straight (line shows the straight direction) | Visual: green line points from player toward cursor | Yes |
| UX7-partial | Solid path leads from player toward cursor | Visual: line is solid green | Yes |
| S16 | No NaN/Inf in output | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run test suite |

### Expected Visual State

Dark background. Triangle (player) at center. Crosshair at mouse position. Green solid line connecting the player to the crosshair. Line updates in real time. No surfaces, no room boundaries.

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
| `scripts/visual/path_renderer.gd` | Create | Preview line rendering via _draw() |
| `scenes/main.tscn` | Modify | Add path renderer node (z_index=20) |
| `tests/test_stage5_preview.gd` | Create | Preview unit tests |

---

## Stage 6: GeneralizedCircle Data Class

### Overview
Implement the `GeneralizedCircle` class — the unified representation for both lines and circles, defined by four coefficients `(a, b, c, d)` in the equation `a(x² + y²) + bx + cy + d = 0`. When `a = 0`, it represents a line; when `a ≠ 0`, a circle. This is a foundational math-layer class used by all subsequent geometry systems.

### Prerequisites
Stage 4 (Direction/Ray exist, providing context for how GeneralizedCircle fits into the geometry pipeline).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/generalized_circle.gd` — GeneralizedCircle class | §5.1 |
| Property | `a, b, c, d: float` — carrier equation coefficients | §5.1 |
| Method | `is_line() -> bool` — returns `a == 0` | §5.1 |
| Method | `center() -> Vector2` — returns `(-b/2a, -c/2a)` (only valid when `a ≠ 0`) | §5.1 |
| Method | `radius() -> float` — returns `sqrt((b²+c²-4ad)/(4a²))` | §5.1 |
| Method | `evaluate(point: Vector2) -> float` — returns `a(x²+y²) + bx + cy + d` | §9.2 |
| Static | `from_line(b, c, d) -> GeneralizedCircle` — convenience for line construction | §5.1 |
| Static | `from_circle(center, radius) -> GeneralizedCircle` — convenience for circle construction | §5.1 |

### Unit Tests Added

1. **`test_stage6_line_construction`**: `GeneralizedCircle.new(0, 1, 0, -5)` represents `x = 5`. `is_line() == true`.
2. **`test_stage6_circle_construction`**: `GeneralizedCircle.new(1, -4, -6, 12)` represents a circle. `is_line() == false`. Center = (2, 3). Radius = 1.
3. **`test_stage6_center_from_coefficients`**: For circle with `a=1, b=-200, c=-400, d=39900`, center = (100, 200), radius = 100. Validates: §5.1 formula.
4. **`test_stage6_evaluate_on_line`**: Point (5, 3) on line `x = 5` (coefficients `0, 1, 0, -5`): `evaluate(Vector2(5, 3)) == 0`. Point (3, 3) off line: `evaluate(Vector2(3, 3)) == -2`.
5. **`test_stage6_evaluate_on_circle`**: Point on circle of radius 100 centered at (200, 200): `evaluate` returns 0. Point inside: `evaluate` returns negative (for `a > 0`). Point outside: `evaluate` returns positive.
6. **`test_stage6_from_line_convenience`**: `GeneralizedCircle.from_line(1, 0, -100)` creates line `x = 100` with `a == 0`.
7. **`test_stage6_from_circle_convenience`**: `GeneralizedCircle.from_circle(Vector2(200, 200), 100)` creates correct circle with expected center and radius.

### Interactive User Tests

- [ ] No visual change expected. Press Play and verify the game still runs identically to Stage 5.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S11-infra | Three points on a carrier evaluate to ~0 (infrastructure — full test when Segment is available) | Partial: evaluate returns 0 for known on-carrier points | Yes |
| S16 | No NaN/Inf in output | Unit test: all methods return finite values for valid inputs | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |
| Stage 1 | GUT runs | Run test suite |

### Expected Visual State

Identical to Stage 5. No visual changes — this stage is pure math layer.

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
| `scripts/math/generalized_circle.gd` | Create | GeneralizedCircle data class |
| `tests/test_stage6_generalized_circle.gd` | Create | GeneralizedCircle unit tests |

---

## Stage 7: Segment Data Class with Via Point

### Overview
Implement the `Segment` class — the three-point definition of a bounded path: `(start, end, via)`. The via point disambiguates which arc is intended for circular carriers and also serves as the foundation for the side convention (left/right of the traversal direction). Carrier derivation from three points is implemented: collinear points produce a line carrier, non-collinear points produce a circle carrier. The `via = Vector2(INF, INF)` sentinel is supported for segments that pass through infinity.

NOTE: Whether a segment is a line or arc is determined by coordinate analysis (checking collinearity) in this stage. The spec (§31.3) specifies that this should ultimately be determined by construction provenance — a stored fact from the level editor. The construction-provenance flag will be added in Stage 62 (level editor serialization). Until then, coordinate-based derivation is used. The threshold for collinearity in the coordinate-based fallback is not specified by the spec (§31.3 says use construction provenance instead). During Stages 7-61, the implementation should use a reasonable engineering threshold (e.g., cross-product magnitude < 1e-10 for the three defining points). This is replaced by the `is_line_by_construction` flag at Stage 62.

### Prerequisites
Stage 6 (GeneralizedCircle class for carrier representation).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/segment.gd` — Segment class with start, end, via | §8.4 |
| Method | `derive_carrier(start, end, via) -> GeneralizedCircle` | §8.4, §5.1 |
| Method | `determine_side(point: Vector2) -> Side` — LEFT or RIGHT based on §9.2 formula | §9.2 |
| Enum | `Side { LEFT, RIGHT }` | §9.2 |
| Behavior | Collinear three points → line carrier | §8.4 table row 1 |
| Behavior | `via = Vector2(INF, INF)` → line carrier through infinity | §8.4 table row 2 |
| Behavior | Non-collinear three points → circle carrier | §8.4 table row 3 |
| Behavior | Side determination: `f(P)` sign + winding direction → LEFT or RIGHT | §9.2 |

### Unit Tests Added

1. **`test_stage7_collinear_produces_line`**: `Segment.new(V2(0,0), V2(10,0), V2(5,0))` → carrier `is_line() == true`. Carrier is the x-axis.
2. **`test_stage7_noncollinear_produces_circle`**: `Segment.new(V2(200,100), V2(200,300), V2(300,200))` → carrier `is_line() == false`. Carrier center = (200, 200), radius = 100 (matches §16.2).
3. **`test_stage7_via_inf_produces_line`**: `Segment.new(V2(0,0), V2(10,0), V2(INF,INF))` → line carrier (segment through infinity).
4. **`test_stage7_side_determination_line`**: For vertical line segment `start=(100,400), end=(100,200), via=(100,300)` (from §16.1 Surface A): point at (50, 300) is LEFT; point at (150, 300) is RIGHT.
5. **`test_stage7_side_determination_circle`**: For arc segment from §16.2: point outside circle is LEFT (outer); point inside is RIGHT (inner).
6. **`test_stage7_S11_three_points_on_carrier`**: For both line and circle segments: `carrier.evaluate(start)`, `carrier.evaluate(end)`, `carrier.evaluate(via)` all return values within machine epsilon of 0. Validates: S11.
7. **`test_stage7_S12_side_consistent`**: Side determination at multiple test points matches the cross-product formula in §9.2. Validates: S12.
8. **`test_stage7_winding_ccw`**: For CCW winding (positive signed area of triangle start→via→end): `f(P) > 0` maps to LEFT. Validates: §9.2.
9. **`test_stage7_winding_cw`**: For CW winding (negative signed area): mapping is reversed. Validates: §9.2.

### Interactive User Tests

- [ ] No visual change expected. Press Play and verify the game still runs identically to Stage 5.

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S11 | Three points on carrier evaluate to ~0 | Unit test | Yes |
| S12 | Side determination consistent with cross-product formula | Unit test | Yes |
| S16 | No NaN/Inf in output | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 6 | GeneralizedCircle tests pass | Run GUT |
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

Identical to Stage 5. No visual changes — this stage is pure math layer.

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
| `scripts/math/segment.gd` | Create | Segment data class with three-point definition |
| `scripts/math/side.gd` | Create | Side enum (LEFT, RIGHT) |
| `tests/test_stage7_segment.gd` | Create | Segment and side determination unit tests |

---

## Stage 8: Computation Cache (Provenance System)

### Overview
Implement the `TransformCache` — a provenance-keyed bidirectional store that ensures exact round-trip reversal of all reversible computations. Every point gets a globally unique, monotonically incrementing ID. The cache stores both forward and reverse directions of carrier derivation, guaranteeing that `derive_via(start, end, derive_carrier(start, end, via))` returns the exact original `via` (same Point ID, not a recomputed approximation). This is the infrastructure that Principle 5 ("provenance over re-guessing") and Principle 22 ("exact reversal by construction") depend on.

### Prerequisites
Stage 7 (Segment and GeneralizedCircle provide the first cached computation: carrier derivation).

### What Is Introduced

| Category | Item | Spec Reference |
|----------|------|----------------|
| Script | `scripts/math/point.gd` — Point class with position + provenance + unique ID | §8.1 |
| Script | `scripts/math/transform_cache.gd` — TransformCache with provenance-keyed lookup | §17 |
| Enum | `Provenance { ORIGIN, BOUNCE, IMAGE, CORNER, CURSOR, ... }` | §8.1 |
| Property | `Point.id: int` — globally unique, monotonically incrementing | §8.1 |
| Property | `Point.position: Vector2` | §8.1 |
| Property | `Point.provenance: Provenance` | §8.1 |
| Method | `TransformCache.derive_carrier_cached(start, end, via) -> GeneralizedCircle` | §17.2 |
| Method | `TransformCache.derive_via_cached(start, end, carrier) -> Vector2` | §17.2 |
| Behavior | Forward storage: three points → carrier | §17.2 |
| Behavior | Reverse storage: carrier + endpoints → original via (exact) | §17.2 |
| Behavior | Point ID global counter (monotonically incrementing, never reused) | §8.1 |

### Unit Tests Added

1. **`test_stage8_point_id_unique`**: Create 100 Points. All IDs are distinct. Validates: S17.
2. **`test_stage8_point_id_monotonic`**: Create Points in sequence. Each ID > previous ID.
3. **`test_stage8_S1_carrier_via_roundtrip`**: `derive_via_cached(start, end, derive_carrier_cached(start, end, via))` returns the EXACT original `via` (same Point ID). Tested for both line and circle carriers. Validates: S1.
4. **`test_stage8_cache_hit_on_second_lookup`**: Call `derive_carrier_cached` with the same inputs twice. Second call returns the same object (cache hit, no recomputation).
5. **`test_stage8_S17_provenance_unique`**: After creating multiple points with various provenances, all IDs are unique across all provenance types. Validates: S17.
6. **`test_stage8_carrier_roundtrip_line`**: Line segment: carrier derived → via recovered → matches original.
7. **`test_stage8_carrier_roundtrip_circle`**: Circle segment: carrier derived → via recovered → matches original.

### Interactive User Tests

- [ ] No visual change expected. Press Play and verify the game still runs identically to Stage 5.
- [ ] Run GUT. All tests from Stages 1–8 pass (cumulative count should be ~25+ tests).

### Invariants That Must Hold

| Invariant ID | Description | How Verified | New This Stage? |
|-------------|-------------|-------------|----------------|
| S1 | Cache: carrier ↔ via round-trip exact | Unit test: derive_via returns exact original via | Yes |
| S17 | Provenance IDs unique | Unit test: 100 Points all have distinct IDs | Yes |
| S11 | Three points on carrier | Unit test (inherited from Stage 7) | Inherited |
| S12 | Side determination consistent | Unit test (inherited from Stage 7) | Inherited |
| S16 | No NaN/Inf in output | Unit test | Inherited |

### Regression Checklist

| Prior Stage | Behavior | How to Verify |
|-------------|----------|---------------|
| Stage 7 | Segment carrier derivation correct (line and circle) | GUT tests |
| Stage 7 | Side determination correct | GUT tests |
| Stage 6 | GeneralizedCircle methods correct | GUT tests |
| Stage 5 | Green line from player to cursor | Move mouse |
| Stage 4 | Direction/Ray construction and zero-length detection | GUT tests |
| Stage 3 | Cursor follows mouse | Move mouse |
| Stage 2 | Player moves with WASD | Press WASD |

### Expected Visual State

Identical to Stage 5. No visual changes — this stage is pure infrastructure.

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
| `scripts/math/point.gd` | Create | Point class with position, provenance, unique ID |
| `scripts/math/transform_cache.gd` | Create | TransformCache with provenance-keyed bidirectional lookup |
| `tests/test_stage8_cache.gd` | Create | Cache and provenance unit tests |

---

## Appendix A: Invariant Introduction Map (Stages 1–8)

| Invariant | Full ID | Introduced | First Testable | Fully Testable | Status After Stage 8 |
|-----------|---------|-----------|----------------|----------------|---------------------|
| Carrier ↔ via round-trip | S1 | Stage 8 | Stage 8 | Stage 65 | Tested (line + circle) |
| Transform round-trip | S2 | — | — | Stage 34+ | Not yet introduced |
| Determinism | S3 | — | — | Stage 14+ | Not yet introduced |
| Divergence monotonic | S4 | — | — | Stage 26+ | Not yet introduced |
| Aligned provenance | S5 | — | — | Stage 25+ | Not yet introduced |
| Aligned match | S6 | — | — | Stage 25+ | Not yet introduced |
| Per-entry state | S7 | — | — | Stage 54+ | Not yet introduced |
| Forward-first ordering | S8 | — | — | Stage 11+ | Not yet introduced |
| Exclusion respected | S9 | — | — | Stage 16+ | Not yet introduced |
| Projective resets frame | S10 | — | — | Stage 73+ | Not yet introduced |
| Three points on carrier | S11 | Stage 7 | Stage 7 | Stage 65 | Tested |
| Side determination | S12 | Stage 7 | Stage 7 | Stage 65 | Tested |
| Visibility no self-intersect | S13 | — | — | Stage 35+ | Not yet introduced |
| Visibility edges on geometry | S14 | — | — | Stage 35+ | Not yet introduced |
| Visibility non-overlapping | S15 | — | — | Stage 35+ | Not yet introduced |
| No NaN/Inf in output | S16 | Stage 4 | Stage 4 | Stage 65 | Tested (Direction, Ray) |
| Provenance IDs unique | S17 | Stage 8 | Stage 8 | Stage 65 | Tested |
| Arrow unaffected by gravity | ARROW-GRAV | Stage 2.5 | Stage 2.5 | Stage 65 | Tested |
| Frame determinant non-zero | S18 | — | — | Stage 34+ | Not yet introduced |
| Trace preserves real state | S19 | — | — | Stage 53+ | Not yet introduced |
| Visibility predicts non-div. | UX1 | — | — | Stage 37+ | Not yet introduced |
| Divergence → outside vis. | UX2 | — | — | Stage 37+ | Not yet introduced |
| Preview matches flight | UX3 | — | — | Stage 17+ | Not yet introduced |
| Same shot = same result | UX4 | — | — | Stage 17+ | Not yet introduced |
| Undo fully restores | UX5 | — | — | Stage 32+ | Not yet introduced |
| All targets reachable | UX6 | — | — | Stage 55+ | Not yet introduced |
| Solid path to cursor | UX7 | Stage 5 (partial) | Stage 5 | Stage 65 | Partial (line only) |
| Block stops arrow | UX9 | — | — | Stage 13+ | Not yet introduced |
| State changes visible | UX10 | — | — | Stage 57+ | Not yet introduced |
| Empty plan = fire straight | UX11 | Stage 5 (partial) | Stage 15 | Stage 65 | Partial (line only) |

## Appendix B: Cumulative Test Count After Stage 8

| Category | Count |
|----------|-------|
| Unit tests (Stage 1: 2) | ~50 |
| Interactive test items | ~30 |
| Invariants actively tested | 6 (S1, S11, S12, S16, S17, ARROW-GRAV) |
| Invariants partially covered | 2 (UX7, UX11) |
