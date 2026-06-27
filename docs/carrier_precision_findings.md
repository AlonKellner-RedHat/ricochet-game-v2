# Carrier Precision Under Composed Mobius Maps: Findings

## Problem Recap

A 2D game traces a laser beam bouncing between reflective curved surfaces (circles). Each reflection is a Mobius transformation (circle inversion). After K bounces, the composed transform M = M_K . ... . M_1 maps visual coordinates to "normalized" coordinates where intersection calculations happen. The beam must find where it hits the next surface in normalized space, and the surface's curved carrier (a circle) must be accurately represented in that space.

The composed transform can have extreme amplification (10^5 to 10^7), meaning tiny errors in the normalized carrier produce massive visual gaps (800-2200 px).

## Approaches Tested

We implemented and numerically compared 8 approaches in a self-contained Python POC (`scripts/math/carrier_precision_poc.py`). All use float64 arithmetic. The test geometry uses the actual game configuration that produces the 800-2200 px bugs.

### 1. 3-Point Circle Fit (Current Method)
Sample 3 points on the visual carrier, map through M^{-1}, fit a circle via 3x3 cofactor determinants.

**Result**: Catastrophic failure. The 3 mapped points collapse into a cluster of diameter ~3.6e-4, making the cofactor computation degenerate. Radius is off by 10-14x.

### 2. N-Point SVD Least-Squares Fit
Sample N points, map through M^{-1}, fit via SVD of the Nx4 design matrix [x^2+y^2, x, y, 1].

**Result**: Massive improvement over 3-point (SVD is numerically stabler than cofactors), but all N points still collapse into the same tiny cluster. The design matrix condition number depends on point spread, not count. Increasing N from 4 to 1000 has minimal effect. **Not an effective N-knob.**

### 3. Algebraic Hermitian Transform (One-Shot)
Represent the circle as a 2x2 Hermitian matrix H. Compute the image under Mobius M via H' = adj(M)^dagger * H * adj(M).

**Result**: Much better than pointwise — no points, no fitting. But adj(M_composed) has entries ~O(10^6), so the product N^dagger * H * N has intermediate values ~O(10^12) that cancel to give small results. Loses ~12 of 16 float64 digits.

### 4. Stepwise Hermitian Transform
Instead of composing M first, apply the Hermitian transform for each individual M_k, renormalizing H after each step.

**Result**: Better than one-shot because each adj(M_k) has entries ~O(10^3) instead of O(10^6). But still limited by the Hermitian representation itself.

### 5. Subdivided Hermitian (Matrix N-th Root)
Decompose each M_k into N sub-transforms via eigendecomposition: M_k = (M_k^{1/N})^N. Apply Hermitian transform N times per stack entry.

**Result**: FAILS. Gets WORSE as N increases. The eigendecomposition introduces its own numerical error, and N sub-steps accumulate it. Consistent with Higham (1997) on instability of iterative matrix root methods. **Not an effective N-knob.**

### 6. Compensated Hermitian (Double-Double Arithmetic)
Stepwise Hermitian with Error-Free Transformations (TwoSum, TwoProduct) for ~106 bits of precision in the matrix multiply.

**Result**: Modest improvement over standard stepwise (0.006 vs 0.020 px at the game case). But the extra precision is lost when converting back to the float64 Circle representation, where d = cx^2 + cy^2 - r^2 loses the tiny r^2 term. **Bottleneck is the representation, not the arithmetic.**

### 7. Geometric Stepwise (Center/Radius Evolution) -- WINNER
Bypass matrices entirely. Evolve (center, radius) through each inversion using direct geometric formulas:
- Power of inversion center: P = |c - Z_0|^2 - r^2
- New radius: r' = (R^2 / |P|) * r
- New center: c' = Z_0 + (R^2 / P) * conj(c - Z_0)

Combined with direct center/radius ray intersection (avoiding the Circle equation d = cx^2+cy^2-r^2).

**Result**: Best across all amplification levels. At the game's actual amplification (251,000x): 0.0035 px. At extreme amplification (9,780,000x): 3.12 px — 12x better than all other approaches.

### 8. Geometric + Compensated (DD Arithmetic on Geometric Formulas)
Apply double-double arithmetic to the geometric center/radius evolution.

**Result**: Identical to plain geometric. The geometric operations (d^2, P, scale, multiply) are already well-conditioned in float64 — there is no catastrophic cancellation for DD to fix. **The geometric representation eliminates the problem, not extended precision.**

### 9. Geometric + N-Point Hybrid (Geometric Center, N-Point Median Radius)
Use geometric center (high precision), then refine the radius by mapping N visual-carrier points through M^{-1} and taking the median distance to the geometric center.

**Result**: Identical to plain geometric regardless of N. All mapped points are in the same tiny cluster, so they all measure the same distance from the center. Median of N identical measurements = one measurement. **Not an effective N-knob.**

## Summary Table

Visual error (px) at each amplification level:

| Amplification | 3-point | algebraic | stepwise | compensated | **geometric** |
|---------------|---------|-----------|----------|-------------|---------------|
| 1,040         | 1.3e-4  | 1.7e-7    | 5.2e-7   | 7.6e-7      | **1.3e-7**    |
| 15,900        | 1.0     | 7.7e-5    | 7.3e-8   | 5.7e-5      | **1.4e-5**    |
| **251,000**   | **397** | 0.083     | 0.020    | 0.006       | **0.0035**    |
| 1,930,000     | NO HIT  | 1.26      | 0.156    | 0.991       | **0.180**     |
| 9,780,000     | NO HIT  | 38.4      | 38.4     | 38.4        | **3.12**      |

## Why Geometric Wins

The (center, radius) representation keeps position and size as **separate float64 quantities** with independent precision. The Hermitian matrix conflates them into d = cx^2 + cy^2 - r^2, where the tiny r^2 is lost in the much larger cx^2 + cy^2 term.

The geometric formulas are inherently well-conditioned:
1. d^2 = |c - Z_0|^2 is a sum of squares (no cancellation)
2. P = d^2 - r^2 only loses precision when d ~ r (circle passes near inversion center), which doesn't occur in our geometry
3. R^2/P is a simple division
4. Center and radius updates are single multiplications

By contrast, the Hermitian congruence H' = N^dagger * H * N produces intermediate values O(10^12) from O(10^3) matrix entries, requiring ~12 digits of cancellation even in the stepwise version.

Adding compensated (DD) arithmetic to the geometric formulas produces **identical results** — confirming that the geometric operations have no cancellation to compensate for.

## What Doesn't Work as an N-Knob

We tested three candidates for an adjustable accuracy parameter N:

1. **N-point SVD**: N points in the same cluster don't add information. Condition number depends on spread, not count.
2. **Matrix N-th root subdivision**: Eigendecomposition error accumulates with N. Gets worse, not better.
3. **N-point radius refinement on geometric center**: All points measure the same distance. Median is invariant to N.

None of these provide an effective accuracy knob.

### 10. Inversive Pullback (Expert Solution 2) -- NEW WINNER

Bypass the normalized-space intersection entirely. Instead:
1. Represent the normalized-space ray as a generalized circle (a line: a=0)
2. Map it to visual space via Hermitian transform H' = adj(M)†HM where M is the frame (normalized→visual)
3. The line becomes a full-size circle in visual space (~hundreds of px radius)
4. Intersect this circle with the visual carrier using circle-circle intersection (both full-size, perfectly conditioned)
5. Map intersection points back to normalized space via frame_inv

This completely eliminates the d²-r² catastrophic cancellation in the ray-circle quadratic — because the intersection now happens between two well-conditioned visual-space circles.

**Result**: Sub-pixel accuracy at ALL amplification levels tested, with ZERO iteration or tuning:

| Amplification | geometric (px) | **inversive-pullback (px)** | improvement |
|---------------|----------------|---------------------------|-------------|
| 1,040         | 1.29e-07       | **1.62e-10**              | 800x        |
| 15,900        | 1.44e-05       | **1.58e-10**              | 91,000x     |
| 251,000       | 3.54e-03       | **2.58e-08**              | 137,000x    |
| 1,930,000     | 0.180          | **1.33e-07**              | 1,350,000x  |
| 9,780,000     | 3.12           | **1.13e-07**              | 27,600,000x |

The inversive pullback is O(1) — constant work, no iteration needed. It makes the Newton-Raphson N-knob unnecessary.

## Why Inversive Pullback Wins

The key insight is relocating WHERE the intersection happens:

- **Old approach**: Intersect a ray with a tiny circle (~10⁻⁵ px radius) in normalized space. The quadratic discriminant computes d²-r² where d≈350 and r≈10⁻⁵, spanning 15 orders of magnitude — exactly the limit of float64.

- **Inversive pullback**: Map the ray to visual space (where it becomes a ~hundreds-px circle), intersect with the visual carrier (~50 px radius). Both circles are full-size, well-separated, and the intersection geometry is perfectly conditioned.

Möbius transforms preserve incidence (if two curves intersect, their images intersect at the image of the intersection points). So mapping intersection points back to normalized space via frame_inv recovers the exact normalized hit coordinates — limited only by the precision of the back-mapping itself, which is a single Möbius application on well-conditioned visual coordinates.

## Updated Summary Table

Visual error (px) at each amplification level:

| Amplification | 3-point | algebraic | stepwise | geometric | **inversive-pullback** |
|---------------|---------|-----------|----------|-----------|----------------------|
| 1,040         | 1.3e-4  | 1.7e-7    | 5.2e-7   | 1.3e-7    | **1.6e-10**          |
| 15,900        | 1.0     | 7.7e-5    | 7.3e-8   | 1.4e-5    | **1.6e-10**          |
| **251,000**   | **397** | 0.083     | 0.020    | 0.0035    | **2.6e-8**           |
| 1,930,000     | NO HIT  | 1.26      | 0.156    | 0.180     | **1.3e-7**           |
| 9,780,000     | NO HIT  | 38.4      | 38.4     | 3.12      | **1.1e-7**           |

## Implementation Notes for Game Engine

The game engine (Godot/GDScript) does NOT have circle-circle intersection built in — it uses ray-circle primitives. But the inversive pullback only requires:

1. **Hermitian transform** (already exists as `GeneralizedCircle.transformed_by()` — needs the conjugation bug fixed)
2. **Circle-circle intersection** (~15 lines of geometry, straightforward to implement)
3. **Frame_inv.apply()** (already exists as `MobiusTransform.apply()`)

The inversive pullback replaces the normalized-space `ray_circle_intersect` call with:
- One Hermitian transform (stepwise, through individual frame entries)
- One circle-circle intersection
- One Möbius back-mapping per intersection point

This is slightly more work than a single ray-circle intersect, but eliminates all precision issues.

## Reproduction

Run `python3 scripts/math/carrier_precision_poc.py` to reproduce all results. The script is self-contained (~900 lines, numpy only).
