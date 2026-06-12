# Design: Provenance-Based Point and Transform Primitives

## 1. Problem Statement

The current math layer represents all geometric positions as raw `Vector2` values. When a Möbius transformation is applied to a point, the result is a new `Vector2` that has lost all connection to its origin. This causes three classes of bugs that cannot be cleanly fixed within the current architecture:

### 1.1 The aim_point Frame Mismatch (2 failing tests)

In `tracer.gd`, `aim_point = direction.end` is set once in visual (world) coordinates. When the tracer applies an effect (e.g., circle inversion), the ray moves into a **normalized frame** — but `aim_point` remains in visual coords. The virtual hitpoint competition calls `_try_virtual_hit(ray, aim_point, ...)`, which projects a visual-frame point onto a normalized-frame ray, producing a wrong t-value. The aim virtual hit wins the competition incorrectly, causing the trace to skip surfaces.

**Root cause**: A raw `Vector2` doesn't know which frame it belongs to. The tracer has no structural way to detect the mismatch.

**Why ad-hoc fixes fail**: Two attempts were made:
1. Mutating the `origin` parameter — broke reflections
2. Local `aim_norm`/`origin_norm` variables — interacted badly with `plan_matched = false` for empty plans

Both failed because the fix was local patching on a system that lacks frame awareness at the point level.

### 1.2 Bidirectional Cache Pollution

`TransformCache.apply_point_cached()` stores both forward (`T(p) = q`) and reverse (`T(q) = p`) entries under the same transform ID. This is correct for self-inverse transforms (reflections, circle inversions), but wrong for composed frames.

After two reflections `M1` then `M2`, the composed frame `F = M1 ∘ M2` is generally NOT self-inverse. But `_build_normalized` uses the inverse `F⁻¹` to transform surface endpoints. If `apply_point_cached` is used, it stores `F⁻¹(p) = q` forward AND `F⁻¹(q) = p` reverse. A later call `F⁻¹(q)` hits the reverse entry and returns `p` — the wrong answer because `F⁻¹(F⁻¹(q)) ≠ p` when `F` is not self-inverse.

**Current workaround**: `_build_normalized` uses `apply_point_forward()` (no reverse entry). This works but is fragile — any future code that uses `apply_point_cached` with a non-self-inverse transform will silently produce wrong results.

**Root cause**: The cache tries to infer inverse relationships from transform IDs, but transform IDs don't encode whether a transform is self-inverse.

### 1.3 Floating-Point Drift on Round-Trips

When a point passes through a self-inverse transform twice (reflect → reflect on same surface), the mathematical result should be exactly the original point. With raw `Vector2` and `MobiusTransform.apply()`, the result drifts by floating-point error. The current `apply_point_cached` fixes this for single transforms, but the fix doesn't compose: after `M1(M2(M2⁻¹(M1⁻¹(p))))`, the intermediate cached values don't chain to produce exact `p`.

**Root cause**: Exactness is attempted at the cache level (matching intermediate results) rather than at the algebraic level (recognizing that the transform sequence cancels to identity).

## 2. Design Principles

This redesign is grounded in the game's core principles from GAME_SPEC.md:

- **Principle 5 — Provenance over re-guessing**: Decisions must be remembered and reused, not recomputed from coordinates.
- **Principle 22 — Exact reversal by construction**: Round-trips must be exact by algebraic structure, not by approximate floating-point comparison.
- **Principle 7 — Data classes are immutable value types**: Points and transforms are created once and never mutated.

Additional design principles for this change:

- **Frame awareness is structural, not contextual**: A point knows its frame by construction, not by which variable holds it.
- **Shapes are defined by points**: Any geometric shape (Segment, Direction, etc.) that is currently defined by `Vector2` values will instead hold `Point` objects. Transforming a shape means transforming its defining points.
- **Algebraic simplification over numerical approximation**: Transform sequences are simplified symbolically (inverse cancellation) before any floating-point arithmetic happens.
- **The visual layer extracts coordinates**: The rendering pipeline needs `Vector2` for draw calls. It extracts `.coords` from `Point` objects at the boundary. No `Point` logic leaks into Godot draw calls.

## 3. New Primitives

### 3.1 TrackedTransform

A wrapper around `MobiusTransform` that carries a reference to its algebraic inverse.

```gdscript
class_name TrackedTransform
extends RefCounted

var mobius: MobiusTransform       # The actual matrix coefficients
var inverse: TrackedTransform     # Reference to inverse (could be self)

static func from_self_inverse(m: MobiusTransform) -> TrackedTransform:
    # For reflections, circle inversions: inverse is self
    var t := TrackedTransform.new()
    t.mobius = m
    t.inverse = t
    return t

static func from_pair(forward: MobiusTransform, backward: MobiusTransform) -> TrackedTransform:
    # For general transforms: forward and backward are linked
    var f := TrackedTransform.new()
    var b := TrackedTransform.new()
    f.mobius = forward
    f.inverse = b
    b.mobius = backward
    b.inverse = f
    return f

static func identity() -> TrackedTransform:
    var t := TrackedTransform.new()
    t.mobius = MobiusTransform.identity()
    t.inverse = t  # Identity is self-inverse
    return t
```

**Key property**: `t.inverse.inverse == t` always holds (algebraically, by construction).

**What it replaces**: The current `MobiusTransform` is not replaced — it remains the coefficient container. `TrackedTransform` wraps it with inverse linkage. The cache methods `invert_cached()` and `compose_cached()` are replaced by structural inverse references and sequence-based aggregation.

### 3.2 Point

A provenance-aware point that carries its full transformation history.

```gdscript
class_name Point
extends RefCounted

var original: Vector2              # The source coordinates (immutable after creation)
var coords: Vector2                # Current position after all transforms
var transforms: Array              # Array[TrackedTransform] — ordered sequence applied
var frame: MobiusTransform         # Aggregated transform (product of sequence)
                                   # Invariant: frame.apply(original) == coords
                                   # (exact when sequence simplification removes all pairs)
```

**Construction**:

```gdscript
# A point born in world coordinates (no transforms applied)
static func at(position: Vector2) -> Point:
    var p := Point.new()
    p.original = position
    p.coords = position
    p.transforms = []
    p.frame = MobiusTransform.identity()
    return p

# Transform this point, returning a NEW point with extended history
func transformed(t: TrackedTransform) -> Point:
    var p := Point.new()
    p.original = original
    p.transforms = _simplify(transforms + [t])
    p.frame = _aggregate(p.transforms)
    if p.transforms.is_empty():
        p.coords = original  # Exact identity — no floating-point involved
    else:
        p.coords = p.frame.apply(original)
    return p
```

**Equality semantics**:

```gdscript
# Provenance equality: same geometric origin
func same_origin(other: Point) -> bool:
    return original == other.original

# Coordinate equality: same current position (for intersection math)
func same_position(other: Point) -> bool:
    return coords == other.coords
```

**Immutability**: `Point` is a value type. `transformed()` returns a new `Point`; it never mutates `self`. This aligns with Principle 7.

### 3.3 Inverse-Aware Sequence Simplification

The core algorithm that makes round-trips exact.

**Rule**: When appending transform `T` to sequence `[..., S]`, if `S.inverse == T` (reference equality, not matrix comparison), the two cancel and both are removed. This removal is applied iteratively from the tail.

```gdscript
static func _simplify(seq: Array) -> Array:
    var result: Array = []
    for t in seq:
        if result.size() > 0 and result.back().inverse == t:
            result.pop_back()  # Cancel inverse pair
        else:
            result.append(t)
    return result
```

**Examples** (using uppercase for transforms, lowercase for their inverses):

| Input sequence | After simplification | Reasoning |
|---|---|---|
| `[A, a]` | `[]` | Direct inverse cancellation |
| `[A, B, b, a]` | `[]` | `B,b` cancel → `[A,a]` → `A,a` cancel → `[]` |
| `[A, B, a]` | `[A, B, a]` | `B` and `a` are not inverses; no cancellation |
| `[A, A]` (self-inverse) | `[]` | `A.inverse == A`, so `A,A` cancels |
| `[A, B, C, c, b, a]` | `[]` | Three nested cancellations |
| `[A, B, C, c, b, D]` | `[A, D]` | Inner three cancel, `A` and `D` don't |

**Why reference equality**: Two `TrackedTransform` objects are inverses if and only if they were created as inverse pairs (via `from_self_inverse` or `from_pair`). This is algebraic identity, not numerical approximation. No epsilon, no floating-point comparison.

### 3.4 Aggregated Frame Computation

After simplification, the `frame` is computed by composing the remaining transforms:

```gdscript
static func _aggregate(seq: Array) -> MobiusTransform:
    if seq.is_empty():
        return MobiusTransform.identity()
    var result: MobiusTransform = seq[0].mobius
    for i in range(1, seq.size()):
        result = result.compose(seq[i].mobius)
    return result
```

When the sequence is empty (all transforms cancelled), `frame` is exactly `MobiusTransform.identity()` — not a numerically-close-to-identity matrix, but the actual identity singleton with `IDENTITY_ID`. This means `coords = original` with zero floating-point error.

## 4. Shapes Defined by Points

All geometric shapes currently defined by `Vector2` fields will instead hold `Point` objects. Transforming a shape means transforming each of its defining points.

### 4.1 Segment

**Current** (raw Vector2):
```gdscript
class Segment extends RefCounted:
    var start: Vector2
    var end: Vector2
    var via: Vector2
```

**New** (Point-based):
```gdscript
class Segment extends RefCounted:
    var start: Point
    var end: Point
    var via: Point
```

The carrier derivation (`get_carrier()`) uses `.coords` to compute the `GeneralizedCircle`:
```gdscript
func get_carrier() -> GeneralizedCircle:
    if _carrier == null:
        _carrier = derive_carrier(start.coords, end.coords, via.coords)
    return _carrier
```

**Transforming a Segment** is transforming its three points:
```gdscript
func transformed(t: TrackedTransform) -> Segment:
    return Segment.new(
        start.transformed(t),
        end.transformed(t),
        via.transformed(t) if not _is_inf_via() else via
    )
```

This replaces the manual point-by-point transformation in `_build_normalized` (tracer.gd lines 267-274).

**Construction sites** (all create `Point.at(...)` from raw coordinates):
- `room_builder.gd`: `Segment.new(Point.at(start), Point.at(end_v), Point.at(via))`
- `level_settings.gd`: Same pattern for all surface types
- `visual_converter.gd`: `Segment.new(Point.at(start), Point.at(end_v), Point.at(via))`

### 4.2 Direction

**Current**:
```gdscript
class Direction extends RefCounted:
    var start: Vector2
    var end: Vector2
```

**New**:
```gdscript
class Direction extends RefCounted:
    var start: Point
    var end: Point

    func to_vector() -> Vector2:
        return end.coords - start.coords
```

### 4.3 Ray

**Current**:
```gdscript
class Ray extends RefCounted:
    var origin: Vector2
    var direction: Direction
```

**New**:
```gdscript
class Ray extends RefCounted:
    var origin: Point
    var direction: Direction
```

Intersection math uses `origin.coords` and `direction.to_vector()` — the raw `Vector2` values needed for the quadratic solver don't change.

### 4.4 HitRecord

**Current**:
```gdscript
class HitRecord extends RefCounted:
    var point: Vector2
    ...
```

**New**:
```gdscript
class HitRecord extends RefCounted:
    var point: Point    # Born in current frame (original = coords, empty transforms)
    ...
```

Intersection points are "born" in whatever frame the ray is in. Their `original` equals their `coords`, and their transform sequence is empty. They gain provenance when the tracer transforms them for visualization.

### 4.5 Step (Tracer output)

**Current**:
```gdscript
class Step extends RefCounted:
    var start: Vector2
    var end: Vector2
    var via: Vector2
    ...
```

**New**:
```gdscript
class Step extends RefCounted:
    var start: Point
    var end: Point
    var via: Point
    ...
```

The visual layer extracts `.coords` for rendering.

## 5. What This Replaces

### 5.1 TransformCache — Largely Eliminated

| Current cache method | Replacement | Why |
|---|---|---|
| `apply_point_cached(transform, point)` | `point.transformed(tracked_transform)` | Sequence simplification gives exact round-trips structurally |
| `apply_point_forward(transform, point)` | `point.transformed(tracked_transform)` | No distinction needed — there's no bidirectional cache to pollute |
| `compose_cached(a, b)` | `_aggregate(sequence)` | Composition happens inside Point, driven by the simplified sequence |
| `invert_cached(t)` | `tracked_transform.inverse` | Inverse is a reference, not a computation |
| `get_normalized / set_normalized` | **Kept** | Performance cache for normalized surfaces per frame — still useful, no correctness issue |
| `derive_carrier_cached` | **Kept** | Carrier derivation from point IDs — orthogonal to this change |
| `derive_via_cached` | **Kept** | Via-point recovery — orthogonal |
| `_point_cache` | **Removed** | Replaced by sequence simplification |
| `_compose_cache` | **Removed** | Replaced by per-Point aggregation |
| `_inverse_cache` | **Removed** | Replaced by TrackedTransform.inverse reference |

### 5.2 Frame Tracking in Tracer — Simplified

**Current**: The tracer maintains a `frame: MobiusTransform` that accumulates composed transforms. When an effect is applied:
```gdscript
frame = cache.compose_cached(frame, mobius)
var new_origin := cache.apply_point_cached(inv_mobius, hit.point)
```

**New**: The tracer maintains a `transform_stack: Array[TrackedTransform]`. When an effect is applied:
```gdscript
transform_stack.append(tracked_effect)
# hit.point is already a Point born in the current normalized frame
# Transform it with the inverse to get the new normalized origin:
var new_origin: Point = hit.point.transformed(tracked_effect.inverse)
```

The frame for visualization is derived from the stack:
```gdscript
var frame: MobiusTransform = Point._aggregate(transform_stack)
```

Or more precisely — each Point in the tracer carries its own frame via its transform sequence. When creating a Step for visualization, the step's start/end Points already know their visual coordinates via `.coords` (if born in visual frame) or can be transformed to visual frame by applying the remaining stack transforms.

### 5.3 Virtual Hitpoint Frame Normalization — Solved Structurally

**Current problem**: `aim_point` is a `Vector2` in visual coords. After an effect, the ray is in normalized coords. The projection `_try_virtual_hit(ray, aim_point, ...)` mixes frames.

**New solution**: `aim_point` is a `Point` with `original = cursor_position, transforms = []`. When the tracer needs to project it onto a normalized-frame ray, it transforms it into the normalized frame:

```gdscript
var aim_in_frame: Point = aim_point.transformed(frame_inverse_tracked)
# aim_in_frame.coords is now in the normalized frame
# aim_in_frame.original is still the cursor position
var t := Intersection.project_point_on_ray(ray, aim_in_frame.coords)
```

For step creation (visualization), the visual position is:
```gdscript
# If aim_point has transforms [], it's already in visual coords
# step.end = aim_point  →  step.end.coords = cursor_position  ✓
```

The frame mismatch is impossible because every Point knows its frame.

### 5.4 _build_normalized — Simplified

**Current** (tracer.gd lines 253-281):
```gdscript
static func _build_normalized(surfaces, frame, out_mapping, cache):
    var inv = cache.invert_cached(frame)
    for surf in surfaces:
        var s := cache.apply_point_forward(inv, surf.segment.start)
        var e := cache.apply_point_forward(inv, surf.segment.end)
        var v := cache.apply_point_forward(inv, surf.segment.via)
        var new_seg := Segment.new(s, e, v)
        ...
```

**New**:
```gdscript
static func _build_normalized(surfaces, frame_inv: TrackedTransform, out_mapping):
    for surf in surfaces:
        var new_seg := surf.segment.transformed(frame_inv)
        ...
```

Each point in the new segment carries its full transform history. If the frame later reverts (e.g., exit the same inversion), the points' sequences simplify back to `[]` and their `.coords` return to the original values exactly.

## 6. Effect Integration

Effects currently return raw `MobiusTransform` objects:

```gdscript
# Current
func get_mobius() -> MobiusTransform
func get_inverse_mobius() -> MobiusTransform
```

They will return `TrackedTransform` instead:

```gdscript
# New
func get_tracked_transform() -> TrackedTransform
```

For self-inverse effects (ReflectionEffect, CircleInversionEffect):
```gdscript
func get_tracked_transform() -> TrackedTransform:
    return TrackedTransform.from_self_inverse(_mobius)
```

For future non-self-inverse effects:
```gdscript
func get_tracked_transform() -> TrackedTransform:
    return TrackedTransform.from_pair(_forward_mobius, _inverse_mobius)
```

**Normalized effects**: `effect.normalized(carrier)` creates a new effect with a new carrier. The `TrackedTransform` it returns is a **different object** from the original effect's transform — it has different matrix coefficients (for the normalized carrier). This is correct: the normalized effect's transform is NOT the inverse of the original effect's transform. They operate in different frames.

## 7. Detailed Mechanism: How a Trace Works With Provenance

### Step-by-step walkthrough: Ray hits mirror, then inversion circle

**Setup**:
```
Player at (800, 500), cursor at (700, 500)
Mirror at x=500 (reflection, self-inverse)
Inversion circle centered at (300, 400) radius 100
```

**Initialization**:
```
aim_point = Point.at(Vector2(700, 500))
    → original=(700,500), coords=(700,500), transforms=[], frame=Identity
origin_point = Point.at(Vector2(800, 500))
    → original=(800,500), coords=(800,500), transforms=[], frame=Identity
ray.origin = Point.at(Vector2(800, 500))
transform_stack = []
```

**Iteration 1 — ray hits mirror**:
```
hit.point = Point.at(Vector2(500, 500))  ← born in current frame (identity)
Effect: ReflectionEffect → tracked_R = TrackedTransform.from_self_inverse(R_mobius)
  tracked_R.inverse == tracked_R  (self-inverse)

transform_stack = [tracked_R]

Step created:
  start = ray.origin  →  .coords = (800, 500)  ← visual coords ✓
  end   = hit.point    →  .coords = (500, 500)  ← visual coords ✓

New ray origin = hit.point.transformed(tracked_R.inverse)
  = hit.point.transformed(tracked_R)  (since self-inverse)
  → original=(500,500), transforms=[R], frame=R
  → coords = R.apply((500,500)) = reflected point
```

**Iteration 2 — normalize surfaces**:
```
frame_inv = TrackedTransform from inverse of aggregate [tracked_R]
  = tracked_R.inverse = tracked_R  (self-inverse)

Normalized surfaces: each segment.transformed(tracked_R)
  e.g., inversion circle start: Point.at((some_x, some_y)).transformed(tracked_R)
  → original=(some_x,some_y), transforms=[R], coords=R.apply(original)
```

**Virtual hitpoint check — aim_point in normalized frame**:
```
aim_in_frame = aim_point.transformed(tracked_R)
  → original=(700,500), transforms=[R], coords=R.apply((700,500))
  → coords is now in the normalized (reflected) frame  ✓

t = project_point_on_ray(ray, aim_in_frame.coords)
  → correct projection because both are in the same frame  ✓
```

**Iteration 2 — ray hits inversion circle**:
```
hit.point = Point.at(intersection_coords)  ← born in normalized frame
Effect: CircleInversionEffect → tracked_I = TrackedTransform.from_self_inverse(I_mobius)

transform_stack = [tracked_R, tracked_I]

Step created: start/end use frame.apply() to get visual coords
  frame = _aggregate([tracked_R, tracked_I])  → R ∘ I
  start.coords and end.coords transformed to visual space

New ray origin = hit.point.transformed(tracked_I.inverse)
  = hit.point.transformed(tracked_I)
  → transforms=[I], frame=I, coords=I.apply(hit_coords)
```

**Iteration 3 — if ray hits inversion circle again (exit)**:
```
Effect: same tracked_I (same TrackedTransform object from same effect)

transform_stack simplified:
  [tracked_R, tracked_I, tracked_I]
  → tracked_I and tracked_I cancel (self-inverse: tracked_I.inverse == tracked_I)
  → [tracked_R]

New ray origin = hit.point.transformed(tracked_I)
  hit.point was born with transforms=[], so after .transformed(tracked_I):
  → transforms = [tracked_I]
  But wait — this is the ray origin, not the frame.
  The frame is from the stack: [tracked_R]
  So frame = R again. We're back in the reflected-only frame. ✓
```

**If the ray then exits the mirror**:
```
transform_stack = [tracked_R, tracked_R]
  → tracked_R.inverse == tracked_R (self-inverse), cancel
  → []

Frame = Identity. All points in visual coords. aim_point.coords = original = (700,500). ✓
Exact round-trip, zero floating-point error.
```

## 8. Edge Cases and Considerations

### 8.1 Points at Infinity

Segments can have `via = Vector2(INF, INF)` to indicate a line extending beyond both endpoints. `Point.at(Vector2(INF, INF))` would carry infinite coordinates. Transforming such a point via `mobius.apply()` would produce `NaN`. 

**Solution**: Infinity-via points are never transformed. `Segment.transformed()` checks `_is_inf_via()` and preserves the via point as-is. This matches current behavior (tracer.gd lines 270-271).

### 8.2 Intersection Points Are Frame-Local

When `Intersection.find_nearest_hit()` computes a hit point, that point is born in whatever frame the ray lives in. Its `Point` has `original = computed_coords, transforms = [], frame = Identity`. It doesn't carry the frame's transform history — it doesn't need to, because it's a new geometric fact discovered in the current frame.

To transform a hit point to visual coords for Step creation, the tracer applies the current frame:
```gdscript
var vis_point: Point = hit.point.transformed(frame_tracked)
# vis_point.coords = frame.apply(hit_coords)  — visual position
```

### 8.3 Non-Self-Inverse Compositions

After two different reflections (mirror A then mirror B), the composed frame `A ∘ B` is a rotation — NOT self-inverse. The transform stack is `[tracked_A, tracked_B]`.

If the ray later exits mirror B (hits it again), the stack becomes `[tracked_A, tracked_B, tracked_B]`. Since `tracked_B.inverse == tracked_B`, the last two cancel: stack = `[tracked_A]`. Frame = A. Exact.

If instead the ray hits a *different* surface C, the stack becomes `[tracked_A, tracked_B, tracked_C]`. No cancellation. Frame = A ∘ B ∘ C. This is correct — no false cancellations.

**The current cache bug**: With `apply_point_cached`, the composed frame `A ∘ B` gets an ID, and its cached reverse entries are wrong because `(A∘B)⁻¹ ≠ A∘B`. With provenance points, there is no reverse cache. The frame is `_aggregate([tracked_A, tracked_B])`, and inversion is structural: the inverse stack is `[tracked_B.inverse, tracked_A.inverse]`.

### 8.4 `plan_matched` and Empty Plans

Currently, when `plan_entries` is empty and a transformative hit occurs, `plan_matched` is set to `false`, making the cursor unreachable and forcing `player_waypoint`. This is a separate issue from the frame mismatch, but provenance points make it easier to reason about because the aim_point's frame is always explicit.

The `plan_matched` logic itself doesn't change — it's about whether the tracer's path through surfaces matches the planned sequence. But with frame-aware points, the cursor virtual hit uses correctly-framed coordinates, so it competes fairly in the t-value sort even when `plan_matched = true` after returning to identity frame.

### 8.5 Performance

**Object creation**: Each `point.transformed(t)` creates a new `Point` with a copied (and potentially shortened) transforms array. In the worst case (deep nesting, no cancellations), the sequence grows linearly with trace depth. With MAX_HITS = 256, the maximum sequence length is 256. Array copy of 256 RefCounted references is negligible.

**Aggregation**: `_aggregate()` composes N Möbius matrices. Each composition is O(1) (fixed-size matrix multiply). For a sequence of length N, this is O(N). With N ≤ 256, this is fast.

**Simplification**: `_simplify()` is O(N) — single pass with a stack.

**Comparison to current cache**: The current cache does dictionary lookups with string keys (`"%d|%s|%s"` format). String formatting and hashing is arguably more expensive than a short array copy + composition.

**Normalized surface caching**: Retained. `get_normalized(frame_id)` / `set_normalized(frame_id, ...)` still avoids redundant `_build_normalized` calls when the frame hasn't changed between iterations. The frame ID comes from the aggregated transform.

### 8.6 TrackedTransform Identity and Object Lifecycle

Each `Effect` instance creates its `TrackedTransform` once (in `_init` or lazily). The same `TrackedTransform` object is returned every time `get_tracked_transform()` is called on the same effect. This ensures that reference equality (`t.inverse == t` for self-inverse) works correctly across the trace.

Different effect instances (e.g., two different mirrors) produce different `TrackedTransform` objects. Even if they have identical matrix coefficients, they are distinct objects and will NOT cancel each other in sequence simplification. This is correct: reflecting in mirror A then reflecting in mirror B is a rotation, not identity.

**Normalized effects**: When `_build_normalized` calls `effect.normalized(new_carrier)`, it creates a new effect with a new `TrackedTransform`. This normalized transform is used for surface-local calculations (carrier-relative Möbius), not for the frame stack. The frame stack always uses the original effect's `TrackedTransform`.

## 9. Visual Layer Boundary

The visual and game layers (`scripts/visual/`, `scripts/game/`) need `Vector2` for Godot draw calls. The boundary is clean:

| Layer | Uses | Accesses |
|---|---|---|
| Math layer | `Point` objects | `.original`, `.coords`, `.transforms`, `.frame` |
| Visual layer | `Vector2` for draw calls | `point.coords` (extraction at boundary) |
| Game layer | `Vector2` for Godot API | `point.coords`, `segment.start.coords`, etc. |

**Specific extraction sites**:

- `path_renderer.gd`: `ms.start.coords`, `ms.end.coords`, `ms.via.coords` for `draw_line()` and `draw_arc()`
- `surface_node.gd`: `surface.segment.start.coords`, `.end.coords`, `.via.coords` for rendering
- `click_detector.gd`: `segment.start.coords`, `segment.end.coords` for hit testing
- `arrow_animator.gd`: `step.start.coords`, `step.end.coords` for arrow interpolation
- `visual_converter.gd`: Receives `Vector2` args (already extracted by callers), creates temporary `Segment` for carrier derivation — this can stay as-is with a local-Segment-from-coords helper, or accept `Point` args

## 10. Migration Plan

### Phase 1: New primitives (additive, no breakage) — Done
- Add `TrackedTransform` class (`scripts/math/tracked_transform.gd`)
- Add `Point` class (`scripts/math/point.gd`)
- Unit tests for Point creation, transformation, simplification, aggregation, equality
- Unit tests for TrackedTransform self-inverse, pair creation, identity

### Phase 2: Segment uses Point — Done
- Change `Segment.start/end/via` from `Vector2` to `Point`
- Add `Segment.transformed(TrackedTransform) -> Segment`
- Update `Segment._init()` to accept `Point` args
- Add convenience constructor `Segment.from_coords(s: Vector2, e: Vector2, v: Vector2)` for construction sites that start from raw coordinates
- Update `get_carrier()` to use `.coords`
- Update `is_on_segment()` in `intersection.gd` to use `.coords`
- Update all Segment construction sites (level_settings, room_builder, visual_converter, tests)
- Run tests after each file change

### Phase 3: Direction, Ray, HitRecord use Point — Done
- Change `Direction.start/end` to `Point`
- Change `Ray.origin` to `Point`
- Change `HitRecord.point` to `Point`
- Update `Intersection` methods to work with `Point.coords` for math, return `Point` in HitRecord
- Run tests

### Phase 4: Effects return TrackedTransform — Done
- Add `get_tracked_transform() -> TrackedTransform` to Effect base class
- Implement in `ReflectionEffect` (self-inverse)
- Implement in `CircleInversionEffect` (self-inverse)
- Keep `get_mobius()` / `get_inverse_mobius()` temporarily for backward compatibility
- Run tests

### Phase 5: Tracer uses Point and TrackedTransform — Done
- Replace `frame: MobiusTransform` with `transform_stack: Array[TrackedTransform]`
- Replace `aim_point: Vector2` with `aim_point: Point`
- Replace `origin` usage for virtual hits with `origin_point: Point`
- Replace manual point transforms with `point.transformed(tracked)`
- Replace `_build_normalized` to use `segment.transformed(frame_inv)`
- Keep `apply_point_forward`, `compose_cached`, `invert_cached` in TransformCache (still used for normalized surface caching)
- Keep normalized surface cache
- Run tests

### Phase 6: Planner uses Point — Todo
- Update `_compute_image` to work with Points
- Update `plan_transformative_subchain` to work with Points
- Run tests

### Phase 7: Visual layer extraction — Partial
- Update `path_renderer.gd` to use `.coords` extraction
- Update `surface_node.gd` to use `.coords` extraction  
- Update `arrow_animator.gd` to use `.coords` extraction
- Update `click_detector.gd` to use `.coords` extraction
- Update `game_manager.gd` debug output to use `.coords`
- Run tests

### Phase 8: Cleanup — Todo
- Remove unused cache methods from `TransformCache`
- Remove `get_mobius()` / `get_inverse_mobius()` if fully replaced
- Run full test suite
- Interactive verification with user

## 11. Files Changed

| File | Change type | Description |
|---|---|---|
| `scripts/math/point.gd` | **New** | Point class with provenance |
| `scripts/math/tracked_transform.gd` | **New** | TrackedTransform with inverse linkage |
| `scripts/math/segment.gd` | **Modified** | Fields change to Point; add transformed() |
| `scripts/math/direction.gd` | **Modified** | Fields change to Point |
| `scripts/math/ray.gd` | **Modified** | origin changes to Point |
| `scripts/math/intersection.gd` | **Modified** | HitRecord.point → Point; use .coords for math |
| `scripts/math/tracer.gd` | **Modified** | Frame stack, Point-based virtual hitpoints |
| `scripts/math/planner.gd` | **Modified** | Point-based image computation |
| `scripts/math/transform_cache.gd` | **Modified** | Remove point/compose/inverse caches; keep norm/carrier caches |
| `scripts/math/effects/effect.gd` | **Modified** | Add get_tracked_transform() |
| `scripts/math/effects/reflection_effect.gd` | **Modified** | Return TrackedTransform.from_self_inverse |
| `scripts/math/effects/circle_inversion.gd` | **Modified** | Return TrackedTransform.from_self_inverse |
| `scripts/game/surface_node.gd` | **Modified** | .coords extraction for rendering |
| `scripts/game/room_builder.gd` | **Modified** | Point.at() at construction |
| `scripts/game/level_settings.gd` | **Modified** | Point.at() at construction |
| `scripts/game/click_detector.gd` | **Modified** | .coords extraction |
| `scripts/game/arrow_animator.gd` | **Modified** | .coords extraction |
| `scripts/game/game_manager.gd` | **Modified** | .coords in debug output |
| `scripts/visual/path_renderer.gd` | **Modified** | .coords extraction for draw calls |
| `scripts/visual/visual_converter.gd` | **Modified** | .coords or keep Vector2 interface |
| `tests/` | **Modified** | Constructor updates, new provenance tests |

## 12. What This Does NOT Change

- **GeneralizedCircle**: Remains a pure coefficient container `(a, b, c, d)`. Not point-based.
- **MobiusTransform**: Remains the matrix coefficient container. `TrackedTransform` wraps it; does not replace it.
- **Side, SideConfig, ConfigResolver**: Pure game logic, unaffected.
- **GameState, PlanManager, PlanEntry**: Pure game state, unaffected.
- **Visual rendering logic**: Draw calls, arc parameter computation, color logic — unchanged. Only the coordinate extraction adds `.coords`.
- **Intersection math**: The quadratic solver, cross-ratio containment, side determination — all work on `float`/`Vector2` extracted from `Point.coords`. The algorithms are unchanged.
- **Normalized surface caching**: Kept as a performance optimization in TransformCache.
- **Carrier caching**: `derive_carrier_cached` in TransformCache — kept, uses Point.id if added, or Point.original for keying.
