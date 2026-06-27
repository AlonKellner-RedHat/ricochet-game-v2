# Numerical Precision of Circle Transforms Under Composed Mobius Maps

## The Problem

Given a circle C in the complex plane (e.g., center (1500, 750), radius 50), and a composed Mobius transformation M = M_n . ... . M_1 built from conformal inversions and translations, compute the **image circle** C' = M^{-1}(C) to sub-pixel accuracy (~0.01 units), even when M has extreme amplification (|det(M)| / |cz+d|^2 ~ 10^5 to 10^7 at the image).

### Why it's hard

The image circle C' is geometrically tiny (radius ~10^{-4} to 10^{-6}), located in a region where M's Jacobian magnifies distances by a factor of 10^5 to 10^7. Any error epsilon in C' is amplified to epsilon * amplification in visual space. With amplification = 250,000, we need epsilon < 4e-8 to stay under 0.01 visual pixels.

### What we've tried

**Approach 1: Pointwise (3-point circle fit)**
Sample 3 points on C, map each through M^{-1}, fit a circle through the 3 image points.

Result: Catastrophic failure. The 3 image points collapse into a cluster of diameter ~3.6e-4. The 3-point circle fit (via cofactor determinants of a 3x4 matrix) is computing the area of a nearly-degenerate triangle. The fitted radius is off by 10-14x, giving ~400 pixel visual error.

**Approach 2: N-point SVD least-squares fit**
Sample N points on C, map through M^{-1}, fit a circle via SVD of the N x 4 design matrix [x^2+y^2, x, y, 1].

Result: Significant improvement over 3-point (4-point SVD matches the algebraic approach at 10^5 amplification). But all N points still collapse into the same ~10^{-4} cluster, so the design matrix condition number depends on spread, not N. At 10^6+ amplification, results become noisy and unreliable regardless of N.

**Approach 3: Algebraic Hermitian transform (one-shot)**
Represent C as a Hermitian matrix H = [[a, conj(w)], [w, d]] where the circle equation is a|z|^2 + 2*Re(conj(w)*z) + d = 0. The image of C under Mobius M with matrix A is:

    H' = N^dagger * H * N,   where N = adj(A) = [[d, -b], [-c, a]]

This is a 2x2 matrix congruence — no points, no fitting, no geometry.

Result: Much better than pointwise. At amplification 250,000: 0.08 px error (vs 397 px for 3-point). But at amplification 2,000,000: 1.26 px error. The issue is that adj(M_composed) has entries ~O(10^6), so the product N^dagger * H * N has intermediate values ~O(10^12) that cancel to give small final values — losing ~12 digits of the available 16.

**Approach 4: Stepwise Hermitian transform**
Instead of composing M first, apply the Hermitian transform for each M_k individually:

    H_0 = H
    H_{k+1} = adj(M_k)^dagger * H_k * adj(M_k),   then renormalize H_{k+1}

Each adj(M_k) has entries ~O(10^3), so each step loses only ~6 digits. Renormalization (dividing by max entry) keeps intermediate values bounded.

Result: Best so far. At amplification 250,000: 0.02 px. At amplification 2,000,000: 0.156 px. But still limited by float64 precision at higher amplification.

**Approach 5: Subdivide each transform via matrix N-th root**
Decompose each M_k = (M_k^{1/N})^N via eigendecomposition, apply the Hermitian transform N times per stack entry.

Result: Fails. The eigendecomposition introduces its own numerical error, and accumulating N sub-steps makes things worse, not better. Consistent with literature on instability of iterative matrix root methods (Higham 1997).

## The Core Question

Is there a method to compute H' = adj(M)^dagger * H * adj(M) for a 2x2 Hermitian congruence transformation that achieves better-than-float64-naive accuracy, given that:

1. M is a product of K known 2x2 matrices (individual transforms are available)
2. The individual transforms have moderate condition numbers (~10^3), but their composition has extreme condition number (~10^6+)
3. The result H' has entries that are much smaller than the intermediate products (catastrophic cancellation)
4. We're working in float64 (no access to float128 in the target environment)
5. K is small (typically 2-6), so O(K^2) or even O(K^3) work is acceptable

Possible directions we haven't explored:
- Compensated (error-free) matrix multiplication for the 2x2 case
- Residual-based iterative refinement (compute in float64, correct via residual)
- Exploiting the specific structure of conformal inversions (their matrices have special symmetries)
- Representing the Hermitian matrix in a different basis that's better conditioned for this specific composition

## Numerical Data

At amplification = 251,000 (the actual case that produces visual bugs):

| Method                  | Visual error (px) |
|-------------------------|-------------------|
| 3-point fit (current)   | 397               |
| 4-point SVD             | 0.07              |
| 1000-point SVD          | 0.006             |
| Algebraic (one-shot)    | 0.083             |
| Algebraic (stepwise)    | 0.020             |

At amplification = 1,930,000:

| Method                  | Visual error (px) |
|-------------------------|-------------------|
| 3-point fit             | NO HIT            |
| 1000-point SVD          | 0.11              |
| Algebraic (one-shot)    | 1.26              |
| Algebraic (stepwise)    | 0.156             |

At amplification = 9,780,000:

| Method                  | Visual error (px) |
|-------------------------|-------------------|
| All methods             | 10-80 px          |

## Context

This arises in a 2D game where a laser beam bounces between reflective curved surfaces. Each reflection is a Mobius transformation (circle inversion). After K bounces, the composed transform M = M_K . ... . M_1 maps visual coordinates to "normalized" coordinates where intersection calculations happen. The beam must find where it hits the next surface in normalized space, and the surface's curved carrier (a circle) must be accurately represented in that space.

The current code uses Approach 1 (3-point fit), which fails catastrophically when the transform stack contains both portal (translation) and reflection (inversion) transforms, producing 800-2200 pixel visual gaps.

## Reproduction

The file `scripts/math/carrier_precision_poc.py` contains a self-contained Python script (~400 lines) that reproduces all results above. Run with `python3 carrier_precision_poc.py`.
