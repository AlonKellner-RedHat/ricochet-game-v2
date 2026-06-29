# Near-Pole Amplification: Why TRACE-ENDS Fails and Pullback Can't Help

## 1. Problem Statement

In a scene with two reflective arcs and a portal, a beam traced from player position (1334.662, 234.909) toward cursor (400, 250) bounces through 10 steps. The last step hits the right wall (vertical line at x=1700) after two arc reflections. The composed Mobius frame at that step maps the normalized hitpoint to a visual endpoint that should lie on the wall carrier, but lands **2.4-5.6px away** depending on float precision, violating the 2.0px TRACE-ENDS threshold.

The inversive pullback (intersect in visual space, back-project to normalized) was suggested as a fix for degenerate normalized carriers. **It produces zero hits for this case** — the visual ray carrier itself is degenerate due to the same underlying cause.

## 2. Scene Configuration

```
Room: (200, 100) to (1700, 900)
Walls: top y=100, right x=1700, bottom y=900, left x=200

Portal: source=(600,300)-(600,700), theta=0, displacement=(1000,0)
        target=(1600,300)-(1600,700)

Arc 1: start=(400,250), via=(350,200), end=(300,250)
       -> circle center=(350,250), radius=50

Arc 2: start=(1550,750), via=(1500,700), end=(1450,750)
       -> circle center=(1500,750), radius=50

Player: (1334.662, 234.909)
Cursor: (400, 250)
```

The beam's 10-step path involves bouncing off both arcs, passing through the portal, and ultimately hitting the right wall at x=1700. At the final step, the transform stack contains two arc reflections (the portal effects cancel via self-inverse), giving a composed frame of `R_arc2 . R_arc1`.

## 3. The Composed Frame

Each arc reflection builds a conjugating Mobius transform from the carrier coefficients `a(x^2+y^2) + bx + cy + d = 0`:

```
ReflectionMobius(carrier) = Mobius(
    alpha = (-b, -c),     // as complex: -b - ci
    beta  = (-2d, 0),
    gamma = (2a, 0),
    delta = (b, -c),      // as complex: b - ci
    conjugating = true
)
```

The composition `R_arc2 . R_arc1` (two conjugating transforms) produces a **non-conjugating** frame:

```
Frame coefficients (float64):
  a = -0.0023111257596905225 - 0.000123957877456582i
  b =  0.7820364757760929    + 0.623232661656711i
  c = -1.2671249695561838e-6 + 5.509238998070382e-7i
  d =  0.0005839793337954606 + 0.000123957877456582i
  conjugating = false
```

Key properties:
- **Determinant**: `|ad - bc| = 7.588e-12` (nearly singular)
- **Pole**: `z_pole = -d/c = (351.828, 250.795)` (the point where the denominator `cz + d = 0`)
- The frame is normalized so max coefficient magnitude = 1 (the `b` coefficient), which means `c` and `d` are tiny

## 4. The Hitpoint and the Pole

The beam hits the right wall at visual position (1700, 647.827). The corresponding normalized hitpoint (via `frame_inv.apply`) is:

```
hp = (351.823, 250.778)
```

The frame's pole is at:

```
pole = (351.828, 250.795)
```

**Distance from pole to hitpoint: 0.018 units.**

The pole is the singularity of `f(z) = (az+b)/(cz+d)` — the point where the denominator vanishes. Near the pole, the derivative `f'(z)` is proportional to `det/(cz+d)^2`, which blows up as `|cz+d| -> 0`.

For the hitpoint:
```
denominator cz + d at hitpoint:
  c * hp + d = (-1.267e-6 + 5.509e-7i)(351.823 + 250.778i) + (5.840e-4 + 1.240e-4i)
             ~ 1.3e-6 + 5.5e-7i  (magnitude ~ 1.4e-6)
```

The amplification factor is:
```
|f'(z)| ~ |det| / |cz+d|^2 = 7.6e-12 / (1.4e-6)^2 ~ 3.9e+0
```

But this is the *local* derivative. The actual error amplification measured empirically is **~12,835x** for perturbations of the hitpoint (measured by perturbing hp by epsilon in x and y and observing the visual displacement). This extreme amplification is because the frame maps a tiny neighborhood around the pole to a huge region in visual space.

## 5. Why `apply_f64` Isn't Enough

GDScript stores Mobius coefficients as `Vector2` (float32). The `apply_f64` function reads these into float64 scalars before doing the arithmetic:

```gdscript
func apply_f64(point: Vector2) -> Vector2:
    var f_ax: float = a.x   // float32 -> float64 widening
    // ... arithmetic in float64 ...
```

But the coefficients were **already truncated to float32** when stored. The coefficient `c` has magnitude ~1.4e-6, which has only ~7 significant digits in float32. The denominator `cz + d` involves products of these truncated values, and the result has ~1e-10 absolute error. With 12,835x amplification, this becomes ~1.3e-6 * 12835 ~ 0.017 units of visual error per coefficient digit lost. The total error is 2.4px — above the 2.0px threshold.

With true float64 coefficients (as in the Python script), `frame.apply(hp)` gives distance 0.000000px to the wall — proving the math is correct and the error is purely from float32 coefficient storage.

## 6. Why Standard Intersection Gets ~0.19px Error (f64)

The standard approach intersects the ray with the **normalized wall carrier** (the wall's carrier transformed by `frame_inv` via Hermitian congruence or 3-point method).

The normalized wall carrier is a **tiny circle** (radius ~0.01) centered near the pole (351.822, 250.788). The ray-circle intersection produces two hits:

```
hit[0]: t = 0.100004  -> frame.apply gives dist = 0.596px to wall
hit[1]: t = 0.099999  -> frame.apply gives dist = 0.191px to wall
```

The best hit (0.191px) is within the 2.0px threshold when using f64 `frame.apply`, but becomes 6.6px with f32. The error enters because:
1. The intersection point on the tiny circle differs from the exact hitpoint by ~7.5e-6
2. This 7.5e-6 error is amplified by 12,835x to ~0.096px, plus the f64 `frame.apply` adds its own small error
3. With f32 coefficients, the frame.apply error dominates

## 7. Why the Pullback Produces Zero Hits

The pullback transforms the **ray** to visual space via Hermitian congruence `H' = N^dag H N`, then intersects with the wall carrier (a simple vertical line at x=1700).

The visual ray carrier produced by the Hermitian transform:

```
Visual ray: a = -8.95e-7, b = 0.00268, c = -0.00134, d = -2.511
```

This has `a ~ 0` (nearly a line), but the radius computation reveals catastrophic cancellation:

```
radius = sqrt(b^2+c^2/(4a^2) - d/a)
       = sqrt(2,805,831.14119... - 2,805,831.14117...)
       = sqrt(0.0000157)
       = 0.00396
```

Two numbers of magnitude ~2.8 million are subtracted to get ~0.000016. The relative precision of the inputs is ~15 digits (float64), but after cancellation only ~5 significant digits remain in the radius.

The resulting circle has:
- Center: (1498.17, -749.20)
- Radius: 0.004

Its closest point to x=1700 is at x=1498.18 — **202px away from the wall**. The circle doesn't intersect the wall, so the pullback returns zero hits.

**Verification that the Hermitian transform is wrong for this frame**: Mapping known ray points through `frame.apply()` and evaluating them on the visual ray carrier gives geometric distances of **700-750px** — the frame-mapped points don't lie on the Hermitian-computed visual ray at all. The Hermitian congruence is numerically unreliable when the frame determinant is ~1e-11.

## 8. The Fundamental Issue

Both the standard approach and the pullback fail for the same root cause: **the frame's pole is geometrically close to the ray**, making every computation that involves the frame numerically unstable.

- **Standard path** (`intersect in norm -> frame.apply -> visual`): The `frame.apply` step amplifies intersection error by ~12,835x.
- **Pullback path** (`Hermitian transform ray -> intersect in visual -> frame_inv.apply -> project`): The Hermitian transform step involves the frame matrix, which has determinant ~1e-11, causing catastrophic cancellation in the visual ray carrier's radius. The visual ray carrier is garbage — frame-mapped ray points don't even lie on it.

The Hermitian congruence `H' = N^dag H N` involves products and sums of frame coefficients. When `|det(N)| ~ 1e-11`, the matrix products magnify rounding errors in the same way that `frame.apply` does. The pullback doesn't escape the amplification — it just encounters it at a different point in the pipeline.

## 9. Condition for This Failure

This failure occurs when the **frame's pole lies close to the ray**. Specifically, when `|c * z_ray + d|` is small compared to the coefficient magnitudes, the denominator of the Mobius transform is close to zero and the amplification blows up.

The "pole distance to ray" is a continuous quantity — the closer the pole, the worse the amplification:

```
Pole distance    Amplification    Approx f32 error
0.017            12,835x          5.6px
0.1              ~2,200x          ~1.0px
0.5              ~440x            ~0.2px
1.0              ~220x            ~0.1px
```

In this scene, the beam's path happens to pass very close to the pole because arc1 (center 350,250) is near the beam's aim line from (1334.662, 234.909) toward (400, 250), and the composition of two reflections about nearby arcs creates a frame with a pole between them.

## 10. What the 3-Point Carrier Method Does

GDScript's `_build_normalized` (for non-isometric stacks) transforms 3 endpoints of the visual surface through `frame_inv.apply()` (float32!) and derives the normalized carrier from those 3 points. This produces a tiny circle of radius ~0.01 that IS intersectable — the standard intersection finds 2 hits. The error enters later when `frame.apply()` maps those hits back to visual space.

The Hermitian congruence method produces coefficients of magnitude ~1e15 to 1e20 for the same carrier — numerically equivalent but with coefficient magnitudes that reveal the instability. Both methods give essentially the same circle (radius ~0.0098-0.0099), confirming the carrier itself is computed correctly.

## 11. Summary of What Has Been Tried

| Approach | Result | Why |
|----------|--------|-----|
| Standard + f32 apply | 5.6px | Float32 amplified 12,835x |
| Standard + f64 apply (f32 coefficients) | 2.4px | Coefficient truncation amplified |
| Standard + f64 apply (f64 coefficients) | 0.19px | Works but requires f64 storage |
| Standard + f64 everything | 0.000px | Proves math is correct |
| Pullback (Hermitian ray transform) | No hits | Hermitian congruence catastrophically cancels |
| Post-hoc carrier snap | 0.000px | Always exact, but is it mathematically principled? |

## 12. Open Questions for Discussion

1. **Is there a numerically stable way to compute the visual ray carrier** when the frame is near-singular? The Hermitian congruence fails due to catastrophic cancellation, but perhaps a different formulation could work.

2. **Can the pullback be reformulated to avoid the Hermitian transform entirely?** For example, by mapping individual ray sample points through `frame.apply` and fitting a carrier, rather than transforming the carrier algebraically.

3. **Is post-hoc carrier snap (project vis_end onto the physical carrier) mathematically sound?** It corrects the floating-point noise in `frame.apply`, but does it preserve any invariants that downstream code depends on?

4. **Could the frame composition be reformulated to avoid near-singular frames?** For example, by factoring the transform stack differently, or by using a different representation that doesn't suffer pole amplification.

5. **Is there a way to detect the near-pole condition and apply a targeted correction?** For example, computing `|c * hp + d|` and switching strategies when it's below a threshold.

## Appendix A: Reproducing the Numbers

All numbers in this document were produced by `exploration/trace_ends_precision.py`, a self-contained Python script using native float64 arithmetic and numpy. It constructs the exact scene, computes the frame from the reflection/portal effects, and runs the precision experiments.

```bash
python3 exploration/trace_ends_precision.py
```

## Appendix B: Key Formulas

**Mobius transform**: `f(z) = (az + b) / (cz + d)`, with optional conjugation `z -> conj(z)` before applying.

**Pole**: `z_pole = -d/c` (or `-conj(d/c)` if conjugating). The point where `f(z) -> infinity`.

**Amplification at z**: `|f'(z)| = |det| / |cz + d|^2` where `det = ad - bc`.

**Hermitian congruence**: For carrier `H` (as 2x2 Hermitian matrix) and Mobius matrix `N`, the transformed carrier is `H' = N^dag H N`.

**Carrier from coefficients**: `a(x^2 + y^2) + bx + cy + d = 0`. Line when `a = 0`. Circle center = `(-b/(2a), -c/(2a))`, radius = `sqrt((b^2+c^2)/(4a^2) - d/a)`.

**Reflection Mobius from carrier (a,b,c,d)**: `alpha = -b-ci, beta = -2d, gamma = 2a, delta = b-ci, conjugating = true`.

**Frame composition**: Left-associative. When composing `F . G` where `F` is conjugating, conjugate `G`'s coefficients first: `G' = conj(G)`, then multiply as `2x2` matrices.

**GDScript normalization after composition**: Divide all four coefficients by `max(|a|, |b|, |c|, |d|)`. This keeps magnitudes bounded but doesn't affect the transform.
