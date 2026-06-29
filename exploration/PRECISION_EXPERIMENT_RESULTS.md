# Precision Experiment Results: Testing the Three Proposed Approaches

Follow-up to [NEAR_POLE_AMPLIFICATION.md](NEAR_POLE_AMPLIFICATION.md). We implemented and tested all four expert-suggested approaches in Python (`trace_ends_precision.py`, Experiments 9–14). This document reports what works, what doesn't, and why.

## Background

The composed Möbius frame `R_arc2 ∘ R_arc1` has pole distance 0.017 from the ray, creating ~12,835x error amplification. The 2.0px TRACE-ENDS threshold is violated with both f32 apply (3.85 px) and f64-from-f32 apply (2.12 px).

GDScript stores Möbius coefficients in `Vector2` (float32). Composition uses `Vector2` arithmetic (float32). The `apply_f64()` method reads f32 values into f64 scalars for arithmetic — but the coefficients are already truncated.

## The Three Improvements Tested

### 1. Float64 Composition

Store and compose Möbius coefficients as GDScript `float` (which is float64) instead of `Vector2` (float32).

In the Python experiment, we simulated GDScript's f32 composition: all multiplies, adds, and normalization through `np.float32()` truncation. Compared against native Python f64 composition (which is what we'd get with GDScript `float` scalars).

**Coefficient differences (f64 vs f32 composition):**
```
a: relative diff = 4.6e-08
b: relative diff = 6.1e-08
c: relative diff = 3.2e-08
d: relative diff = 5.7e-08
```

These are ~50 nanoradians of relative error — but near the pole, the 12,835x amplification turns them into pixels.

### 2. Pole-Residue Form

`f(z) = A + R/(z - P)` where `A = a/c`, `P = -d/c`, `R = -(ad-bc)/c²`.

Isolates the singularity into the `z - P` subtraction, avoiding the `cz + d` denominator computation where catastrophic cancellation occurs.

### 3. Manifold Projection

After computing `vis_end = frame.apply(hp)`, project `vis_end` onto the physical carrier:
- Line carrier: `p - f(p) * (b,c)/(b²+c²)`
- Circle carrier: `center + r * normalize(p - center)`

## Results

### On intersection hitpoints (what GDScript actually computes)

| Method | Carrier dist (px) | Verdict |
|--------|-------------------|---------|
| f32 compose + f32 apply **(current GDScript)** | **3.85** | **FAIL** |
| f32 compose + f64 apply (current `apply_f64`) | 2.12 | FAIL |
| **[1] f64 compose + f64 apply** | **0.68** | **pass** |
| [2a] pole-residue (f32 coefficients) | 2.12 | FAIL |
| **[2b] pole-residue (f64 coefficients)** | **0.68** | **pass** |
| **[3] snap alone (on baseline)** | **0.0** | **pass** |
| [1+3] f64 compose + snap | 0.0 | pass |
| [2a+3] pole-residue f32 + snap | 0.0 | pass |
| [1+2+3] all three | 0.0 | pass |

### On exact hitpoints (no intersection error)

| Method | Carrier dist (px) |
|--------|-------------------|
| f32 compose + f32 apply | 4.28 |
| f32 compose + f64 apply | 2.77 |
| **[1] f64 compose + f64 apply** | **6.4e-09** |
| [2a] pole-residue (f32 coefficients) | 2.77 |
| **[2b] pole-residue (f64 coefficients)** | **4.3e-09** |

## Key Findings

### 1. f64 composition is the critical improvement

The biggest single improvement: **3.85 → 0.68 px (6x better)**. It brings the result well under the 2.0px threshold even without the other two fixes.

With exact hitpoints, f64 composition gives 6.4e-9 px — essentially exact. The remaining 0.68 px on intersection hitpoints comes from the intersection itself: the hitpoint differs from exact by 3.0e-4 units, amplified by 12,835x to ~3.8 px in the unimproved direction (Y coordinate, which the carrier distance formula also captures partially via the gradient).

### 2. Pole-residue form is redundant when f64 composition is present

**Pole-residue with f32 coefficients gives identical results to plain f64 apply (both 2.12 px)**. The pole-residue form doesn't help because the A, P, R parameters are computed from the f32-truncated coefficients — the precision is already lost.

**Pole-residue with f64 coefficients gives identical results to f64 compose + f64 apply (both 0.68 px)**. They're mathematically the same transform evaluated with the same precision. The pole-residue form isolates the singularity, but when you have enough precision in the coefficients, the standard form handles the denominator fine.

The pole-residue form would outperform the standard form if both had to use the same (limited) precision but the standard form suffered from denominator cancellation. In practice, the `cz + d` computation in float64 has enough precision for this case — the near-pole amplification is large (12,835x) but not catastrophic for float64's 15-digit precision.

### 3. Manifold projection always gives 0.0 px carrier distance

But it only corrects the component perpendicular to the carrier (X for a vertical wall). The component parallel to the carrier (Y) retains whatever error the apply method introduced.

**Y-coordinate accuracy:**
```
True Y:                          647.8268
f32 compose + f32 apply:         654.8092  (Y error: 6.98 px)
f32 compose + f64 apply:         653.7572  (Y error: 5.93 px)
f64 compose + f64 apply:         651.5735  (Y error: 3.75 px)
pole-residue (f32 coeffs):       653.7572  (Y error: 5.93 px)
pole-residue (f64 coeffs):       651.5735  (Y error: 3.75 px)
```

So f64 composition + manifold projection gives: carrier distance = 0.0 px, Y error = 3.75 px. The Y error is a visual artifact (endpoint slides along the carrier) but doesn't violate the TRACE-ENDS invariant since that only measures carrier distance.

### 4. The remaining Y error comes from intersection precision

The intersection hitpoint differs from the exact hitpoint by 3.0e-4 units (the intersection is with a tiny normalized circle of radius ~0.01). This 3.0e-4 error, amplified 12,835x, gives ~3.75 px of Y displacement. Only a more precise intersection (or working in visual space directly) would fix this.

## What about the Geometric Visual Ray?

The Hermitian congruence `H' = N† H N` produces garbage for this near-singular frame (visual ray center 200+ px from the wall, 0 intersection hits). The geometric visual ray (sample 3 points, map through frame, fit circle) correctly produces the visual ray carrier and finds 2 wall hits.

However, the geometric visual ray is solving a different problem: making the *pullback intersection* work. It doesn't directly affect the `frame.apply(hp)` precision. It would be useful if we wanted to intersect directly in visual space, but that introduces its own back-projection errors.

We plan to implement geometric visual ray as a replacement for Hermitian congruence in the pullback, making the pullback robust for near-singular frames. This is independent of (and complementary to) the f64 composition + manifold projection improvements.

## Implementation Plan

We will implement all three improvements in the GDScript codebase:

1. **f64 composition** — Already implemented: `MobiusTransform` now stores `a_re, a_im, ...` float64 fields alongside the Vector2 fields. `compose()` computes both f32 (Vector2) and f64 results. `apply_f64()` reads the f64 fields.

2. **Manifold projection** — `Intersection.project_onto_carrier(point, carrier)` will snap `vis_end` onto the physical carrier after `frame.apply_f64()`.

3. **Geometric visual ray** — Will replace the Hermitian congruence in `inversive_pullback_intersect()` with 3-point sampling through `frame.apply_f64()`.

### Complication: trace topology sensitivity

Changing `apply()` to `apply_f64()` in the tracer alters the visual endpoints, which affects the zero-length step check (`vis_start == vis_end`). This changes trace topology in some test scenes. Our solution: keep `apply()` (f32) for all control-flow decisions (zero-length check, infinity check), compute `apply_f64()` values separately, and use them only for Step.end/Step.start storage.

## Open Questions

1. **Is the Y error (3.75 px) acceptable?** It doesn't violate TRACE-ENDS (which measures carrier distance), but it means the visual endpoint slides along the carrier from its true position. For a game, this is likely imperceptible, but is there a way to reduce it further?

2. **Could the intersection itself be done in f64?** The normalized carrier is computed from f32 `frame_inv.apply()` of 3 surface endpoints. Using `apply_f64()` for these would give a more precise normalized carrier, potentially reducing the intersection hitpoint error below 3.0e-4.

3. **Is there a case where pole-residue outperforms standard f64 apply?** In theory, if the denominator cancellation is severe enough to exhaust float64 precision (~15 digits), pole-residue would help. We estimate this would require pole distance < ~1e-6 units. Is such a scenario geometrically possible in the game?

## Experiment 15: Visual-Space Intersection + Kahan Robust Quadratic

Following expert feedback, we tested two additional approaches:

### Kahan Robust Quadratic Solver: No improvement

Both Kahan variants (conjugate rewrite and compensated discriminant) give **identical** hitpoint errors to the standard quadratic: `hp_err = 7.47e-5` on the f32 carrier. The quadratic solver is NOT the precision bottleneck — the *carrier itself* is imprecise (built from f32-mapped endpoints), and the solver finds the correct intersection with that carrier.

Using the f64 normalized carrier reduces hitpoint error from 7.47e-5 to 5.42e-5 (27% improvement), but Kahan still gives no additional benefit over the standard solver.

### Geometric Visual Ray: The ultimate fix

The expert's key insight — intersect directly in visual space — proved to be the definitive solution:

| Method | Carrier dist | Y error | Total error |
|--------|-------------|---------|-------------|
| Baseline (f32 everything) | 4.69 px | 1.55 px | 4.94 px |
| f64 compose + f64 apply + snap | 0.0 px | 0.94 px | 0.94 px |
| **Geometric visual ray (f64)** | **0.0 px** | **0.00004 px** | **0.00004 px** |

The geometric visual ray gives 0.00004 px total error — **100,000x better** than the baseline.

**How it works:**
1. Sample 3 points on the normalized ray (e.g., t=0, 0.04, 0.08)
2. Map through `frame.apply_f64()` to visual space
3. Fit a circle through the 3 visual points
4. Intersect with the physical wall carrier (x=1700)
5. **Use the visual hit directly as vis_end** — no frame.apply() needed

Because the intersection happens between two macroscopic objects in visual space (a circle of radius ~117 and a vertical line), the intersection is perfectly conditioned. The 12,835x amplification is completely bypassed.

**Critical requirement**: f64 composition is a **prerequisite** — f32-mapped sample points produce a degenerate visual ray with 0 wall hits. Only f64 composition + f64 apply produces valid visual ray geometry.

**Robustness**: Tested 8 different sample point configurations. All produced valid results with Y errors from 0.000012 to 0.004 px. The method is robust to sample point placement, including samples before and after the pole.

### Implementation implications

The geometric visual ray replaces the entire normalized-space pipeline for the TRACE-ENDS case:

**Current pipeline (fails near pole):**
```
normalize carrier → intersect ray × carrier → frame.apply(hp) → vis_end
                    ↑ hp error ~1e-4         ↑ amplifies by 12,835x
```

**New pipeline (pole-immune):**
```
sample 3 ray points → frame.apply_f64() → fit visual ray → intersect × wall → vis_end
                       ↑ no amplification   ↑ well-conditioned intersection
```

The key architectural change: the geometric visual ray approach should be used **selectively** for the pullback/TRACE-ENDS path where near-pole amplification matters. The regular intersection pipeline (which finds WHICH surface is hit and at what t) stays on the existing code — it doesn't need this precision because it operates in normalized space where positions are well-conditioned.

## Reproducing

```bash
python3 exploration/trace_ends_precision.py 2>&1 | grep -A 100 'EXPERIMENT 14'
python3 exploration/trace_ends_precision.py 2>&1 | grep -A 200 'EXPERIMENT 15'
```
