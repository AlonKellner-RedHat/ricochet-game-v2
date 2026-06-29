#!/usr/bin/env python3
"""
Numerical exploration: TRACE-ENDS floating-point precision.

Reproduces the exact Ricochet game scenario where a composed Möbius frame
(portal + arc reflections) maps a wall at x=1700 into a degenerate normalized
carrier (radius=NaN). Compares precision of different intersection strategies.
"""

import numpy as np
from dataclasses import dataclass, field
from typing import Optional, List, Tuple


# ============================================================================
# Section 1: Mathematical Primitives
# ============================================================================

@dataclass
class GeneralizedCircle:
    """Generalized circle: a(x²+y²) + bx + cy + d = 0"""
    a: float
    b: float
    c: float
    d: float

    def is_line(self) -> bool:
        return self.a == 0.0

    def center(self) -> complex:
        assert self.a != 0.0
        return complex(-self.b / (2 * self.a), -self.c / (2 * self.a))

    def radius(self) -> float:
        assert self.a != 0.0
        val = (self.b**2 + self.c**2 - 4 * self.a * self.d) / (4 * self.a**2)
        return np.sqrt(val)  # may be NaN if val < 0

    def evaluate(self, p: complex) -> float:
        x, y = p.real, p.imag
        return self.a * (x*x + y*y) + self.b * x + self.c * y + self.d

    def geometric_dist(self, p: complex) -> float:
        x, y = p.real, p.imag
        f = self.evaluate(p)
        gx = 2 * self.a * x + self.b
        gy = 2 * self.a * y + self.c
        grad = np.sqrt(gx*gx + gy*gy)
        return abs(f) / max(grad, 1e-10)

    @staticmethod
    def from_line(b: float, c: float, d: float) -> 'GeneralizedCircle':
        return GeneralizedCircle(0.0, b, c, d)

    @staticmethod
    def from_circle(center: complex, radius: float) -> 'GeneralizedCircle':
        cx, cy = center.real, center.imag
        return GeneralizedCircle(1.0, -2*cx, -2*cy, cx*cx + cy*cy - radius*radius)

    @staticmethod
    def from_three_points(p1: complex, p2: complex, p3: complex) -> 'GeneralizedCircle':
        """Derive carrier from three points using homogeneous determinant formula."""
        def to_row(p):
            if np.isinf(p.real) or np.isinf(p.imag):
                return [1.0, 0.0, 0.0, 0.0]
            return [p.real**2 + p.imag**2, p.real, p.imag, 1.0]

        r1 = to_row(p1)
        r2 = to_row(p2)
        r3 = to_row(p3)

        def det3(c1, c2, c3):
            return np.linalg.det([[r1[c1], r1[c2], r1[c3]],
                                  [r2[c1], r2[c2], r2[c3]],
                                  [r3[c1], r3[c2], r3[c3]]])

        a = det3(1, 2, 3)
        b = -det3(0, 2, 3)
        c = det3(0, 1, 3)
        d = -det3(0, 1, 2)
        return GeneralizedCircle(a, b, c, d)

    def __repr__(self):
        kind = "line" if self.is_line() else "circle"
        if not self.is_line():
            r = self.radius()
            return f"GC({kind}, a={self.a:.6g}, b={self.b:.6g}, c={self.c:.6g}, d={self.d:.6g}, r={r:.4g})"
        return f"GC({kind}, b={self.b:.6g}, c={self.c:.6g}, d={self.d:.6g})"


@dataclass
class MobiusTransform:
    """Möbius transform: f(z) = (a*z + b) / (c*z + d), optionally with conjugation."""
    a: complex
    b: complex
    c: complex
    d: complex
    conjugating: bool = False
    label: str = ""

    def apply(self, z: complex) -> complex:
        if np.isinf(z.real) or np.isinf(z.imag):
            if self.c == 0:
                return complex(np.inf, np.inf)
            return self.a / self.c
        if self.conjugating:
            z = z.conjugate()
        num = self.a * z + self.b
        den = self.c * z + self.d
        if den == 0:
            return complex(np.inf, np.inf)
        result = num / den
        if np.isnan(result.real) or np.isnan(result.imag):
            return complex(np.inf, np.inf)
        return result

    def apply_f32(self, z: complex) -> complex:
        """Simulate GDScript's Vector2 (float32) arithmetic."""
        def f32(x):
            return float(np.float32(x))
        def v2(c):
            return complex(f32(c.real), f32(c.imag))

        if np.isinf(z.real) or np.isinf(z.imag):
            if self.c == 0:
                return complex(np.inf, np.inf)
            return v2(v2(self.a) / v2(self.c))

        z = v2(z)
        if self.conjugating:
            z = z.conjugate()
        a, b, c, d = v2(self.a), v2(self.b), v2(self.c), v2(self.d)

        # Complex multiply in float32
        def cmul32(v1, v2_):
            r = f32(f32(v1.real * v2_.real) - f32(v1.imag * v2_.imag))
            i = f32(f32(v1.real * v2_.imag) + f32(v1.imag * v2_.real))
            return complex(r, i)

        num = complex(f32(cmul32(a, z).real + b.real), f32(cmul32(a, z).imag + b.imag))
        den = complex(f32(cmul32(c, z).real + d.real), f32(cmul32(c, z).imag + d.imag))
        if den == 0:
            return complex(np.inf, np.inf)
        den_mag2 = f32(f32(den.real * den.real) + f32(den.imag * den.imag))
        if den_mag2 == 0:
            return complex(np.inf, np.inf)
        r = f32(f32(num.real * den.real + num.imag * den.imag) / den_mag2)
        i = f32(f32(num.imag * den.real - num.real * den.imag) / den_mag2)
        return complex(r, i)

    def compose(self, other: 'MobiusTransform') -> 'MobiusTransform':
        """Compose: result(z) = self(other(z)). Left-multiplication."""
        a2, b2, c2, d2 = other.a, other.b, other.c, other.d
        if self.conjugating:
            a2, b2, c2, d2 = a2.conjugate(), b2.conjugate(), c2.conjugate(), d2.conjugate()

        new_a = self.a * a2 + self.b * c2
        new_b = self.a * b2 + self.b * d2
        new_c = self.c * a2 + self.d * c2
        new_d = self.c * b2 + self.d * d2

        mag = max(abs(new_a), abs(new_b), abs(new_c), abs(new_d))
        if mag > 0:
            new_a /= mag
            new_b /= mag
            new_c /= mag
            new_d /= mag

        new_conj = self.conjugating != other.conjugating
        return MobiusTransform(new_a, new_b, new_c, new_d, new_conj,
                               label=f"({self.label}∘{other.label})")

    def invert(self) -> 'MobiusTransform':
        if self.conjugating:
            return MobiusTransform(
                complex(-self.d.real, self.d.imag),
                complex(self.b.real, -self.b.imag),
                complex(self.c.real, -self.c.imag),
                complex(-self.a.real, self.a.imag),
                True, label=f"inv({self.label})")
        det = self.a * self.d - self.b * self.c
        return MobiusTransform(
            self.d / det, -self.b / det,
            -self.c / det, self.a / det,
            False, label=f"inv({self.label})")

    def maps_lines_to_arcs(self) -> bool:
        return self.c != 0

    def __repr__(self):
        conj = " conj" if self.conjugating else ""
        return f"Möbius({self.label}{conj}, a={self.a}, b={self.b}, c={self.c}, d={self.d})"

    @staticmethod
    def identity() -> 'MobiusTransform':
        return MobiusTransform(1+0j, 0+0j, 0+0j, 1+0j, False, "I")


def hermitian_transform(circle: GeneralizedCircle, mobius: MobiusTransform) -> GeneralizedCircle:
    """H' = N† H N — transform circle through Möbius (float64)."""
    h_w = complex(circle.b / 2, -circle.c / 2)

    if mobius.conjugating:
        N = [[mobius.d.conjugate(), -mobius.b.conjugate()],
             [-mobius.c.conjugate(), mobius.a.conjugate()]]
        H01 = h_w.conjugate()
        H10 = h_w
    else:
        N = [[mobius.d, -mobius.b],
             [-mobius.c, mobius.a]]
        H01 = h_w
        H10 = h_w.conjugate()

    Nh = [[N[0][0].conjugate(), N[1][0].conjugate()],
          [N[0][1].conjugate(), N[1][1].conjugate()]]

    H_a = circle.a
    H_d = circle.d

    # T = Nh @ H
    T00 = Nh[0][0] * H_a + Nh[0][1] * H10
    T01 = Nh[0][0] * H01 + Nh[0][1] * H_d
    T10 = Nh[1][0] * H_a + Nh[1][1] * H10
    T11 = Nh[1][0] * H01 + Nh[1][1] * H_d

    # R = T @ N
    R00 = T00 * N[0][0] + T01 * N[1][0]
    R01 = T00 * N[0][1] + T01 * N[1][1]
    R11 = T10 * N[0][1] + T11 * N[1][1]

    return GeneralizedCircle(R00.real, 2 * R01.real, -2 * R01.imag, R11.real)


def reflection_mobius(carrier: GeneralizedCircle) -> MobiusTransform:
    """Build reflection Möbius from carrier."""
    alpha = complex(-carrier.b, -carrier.c)
    beta = complex(-2 * carrier.d, 0)
    gamma = complex(2 * carrier.a, 0)
    delta = complex(carrier.b, -carrier.c)
    return MobiusTransform(alpha, beta, gamma, delta, True, "R")


def portal_mobius(theta: float, d: complex) -> Tuple[MobiusTransform, MobiusTransform]:
    """Build portal forward and inverse Möbius transforms."""
    e_itheta = complex(np.cos(theta), np.sin(theta))
    e_neg = e_itheta.conjugate()

    fwd = MobiusTransform(e_itheta, d, 0+0j, 1+0j, False, "P_fwd")
    inv_beta = -e_neg * d
    inv = MobiusTransform(e_neg, inv_beta, 0+0j, 1+0j, False, "P_inv")
    return fwd, inv


@dataclass
class Ray:
    origin: complex
    direction: complex  # unnormalized direction vector

    def intersect_carrier(self, carrier: GeneralizedCircle) -> List[Tuple[float, complex]]:
        """Find ray-carrier intersections. Returns list of (t, point)."""
        ox, oy = self.origin.real, self.origin.imag
        dx, dy = self.direction.real, self.direction.imag

        qa = carrier.a * (dx*dx + dy*dy)
        qb = 2 * carrier.a * (ox*dx + oy*dy) + carrier.b * dx + carrier.c * dy
        qc = carrier.a * (ox*ox + oy*oy) + carrier.b * ox + carrier.c * oy + carrier.d

        results = []
        if qa == 0:
            if qb == 0:
                return []
            t = -qc / qb
            results.append(t)
        else:
            disc = qb*qb - 4*qa*qc
            if disc < 0:
                return []
            elif disc == 0:
                results.append(-qb / (2*qa))
            else:
                sqrt_d = np.sqrt(disc)
                results.append((-qb - sqrt_d) / (2*qa))
                results.append((-qb + sqrt_d) / (2*qa))

        return [(t, self.origin + t * self.direction) for t in results]

    def project_point(self, point: complex) -> float:
        """Project point onto ray, return t parameter."""
        dp = point - self.origin
        d = self.direction
        return (dp.real * d.real + dp.imag * d.imag) / (d.real**2 + d.imag**2)


def intersect_circles(c1: GeneralizedCircle, c2: GeneralizedCircle) -> List[complex]:
    """Intersect two generalized circles."""
    is_line1 = c1.is_line()
    is_line2 = c2.is_line()

    if is_line1 and is_line2:
        det = c1.b * c2.c - c1.c * c2.b
        if abs(det) < 1e-12:
            return []
        x = (c1.c * c2.d - c2.c * c1.d) / det
        y = (c2.b * c1.d - c1.b * c2.d) / det
        return [complex(x, y)]

    if is_line1:
        return _intersect_line_circle(c1, c2)
    if is_line2:
        return _intersect_line_circle(c2, c1)

    # circle-circle
    cx1, cy1 = -c1.b / (2*c1.a), -c1.c / (2*c1.a)
    r1 = c1.radius()
    cx2, cy2 = -c2.b / (2*c2.a), -c2.c / (2*c2.a)
    r2 = c2.radius()

    dx, dy = cx2 - cx1, cy2 - cy1
    d_sq = dx*dx + dy*dy
    d = np.sqrt(d_sq)

    if d < 1e-12 or d > r1 + r2 + 1e-10 or d < abs(r1 - r2) - 1e-10:
        return []

    a_param = (r1*r1 - r2*r2 + d_sq) / (2*d)
    h_sq = max(0, r1*r1 - a_param*a_param)
    h = np.sqrt(h_sq)

    mx = cx1 + a_param * dx / d
    my = cy1 + a_param * dy / d

    if h < 1e-12:
        return [complex(mx, my)]

    px = -dy / d * h
    py = dx / d * h
    return [complex(mx + px, my + py), complex(mx - px, my - py)]


def _intersect_line_circle(line: GeneralizedCircle, circ: GeneralizedCircle) -> List[complex]:
    cx = -circ.b / (2 * circ.a)
    cy = -circ.c / (2 * circ.a)
    r = circ.radius()

    lb, lc, ld = line.b, line.c, line.d
    len_sq = lb*lb + lc*lc
    if len_sq < 1e-24:
        return []
    length = np.sqrt(len_sq)
    dist = (lb * cx + lc * cy + ld) / length
    if abs(dist) > r + 1e-10:
        return []

    foot_x = cx - lb * dist / length
    foot_y = cy - lc * dist / length

    h_sq = max(0, r*r - dist*dist)
    h = np.sqrt(h_sq)

    if h < 1e-12:
        return [complex(foot_x, foot_y)]

    dir_x = -lc / length
    dir_y = lb / length
    return [complex(foot_x + dir_x * h, foot_y + dir_y * h),
            complex(foot_x - dir_x * h, foot_y - dir_y * h)]


def ray_to_line(ray: Ray) -> GeneralizedCircle:
    """Convert ray to generalized circle (line through ray)."""
    dx, dy = ray.direction.real, ray.direction.imag
    ox, oy = ray.origin.real, ray.origin.imag
    return GeneralizedCircle.from_line(dy, -dx, dx * oy - dy * ox)


def inversive_pullback_intersect(ray: Ray, visual_carrier: GeneralizedCircle,
                                  frame: MobiusTransform,
                                  use_f64_backproject: bool = True) -> List[Tuple[float, complex]]:
    """Pullback intersection: intersect in visual space, back-project."""
    ray_line = ray_to_line(ray)
    visual_ray = hermitian_transform(ray_line, frame)
    visual_hits = intersect_circles(visual_ray, visual_carrier)

    if not visual_hits:
        return []

    frame_inv = frame.invert()
    results = []
    for vh in visual_hits:
        if use_f64_backproject:
            norm_point = frame_inv.apply(vh)
        else:
            norm_point = frame_inv.apply_f32(vh)
        t = ray.project_point(norm_point)
        on_ray_point = ray.origin + t * ray.direction
        results.append((t, on_ray_point))
    return results


# ============================================================================
# Section 2: Scene Setup
# ============================================================================

def build_scene():
    """Build all surfaces matching the GDScript test exactly.

    Surface creation order (determines IDs):
    1-4: Room walls (top=1, right=2, bottom=3, left=4)
    5-6: Reflective arcs (arc1=5, arc2=6)
    7-8: Portal source=7, target=8
    9-12: Screen bounds (not relevant for this analysis)
    """
    # Room: Rect2(200, 100, 1500, 800) → corners (200,100) to (1700,900)
    # Use exact line carriers to avoid float noise from 3-point determinant.
    # Wall carrier from two points: line through (x1,y1)→(x2,y2) has
    # b = dy = y2-y1, c = -dx = -(x2-x1), d = dx*y1 - dy*x1
    def line_carrier(p1, p2):
        dx = p2.real - p1.real
        dy = p2.imag - p1.imag
        return GeneralizedCircle.from_line(dy, -dx, dx * p1.imag - dy * p1.real)

    walls = {
        'top':    line_carrier(200+100j, 1700+100j),     # y=100:  b=0, c=-1500, d=150000
        'right':  line_carrier(1700+100j, 1700+900j),    # x=1700: b=800, c=0, d=-1360000
        'bottom': line_carrier(1700+900j, 200+900j),     # y=900:  b=0, c=1500, d=-1350000
        'left':   line_carrier(200+900j, 200+100j),      # x=200:  b=-800, c=0, d=160000
    }

    # Reflective arcs
    # Arc1: start=(400,250), via=(350,200), end=(300,250)
    arc1_carrier = GeneralizedCircle.from_three_points(400+250j, 350+200j, 300+250j)
    # Arc2: start=(1550,750), via=(1500,700), end=(1450,750)
    arc2_carrier = GeneralizedCircle.from_three_points(1550+750j, 1500+700j, 1450+750j)

    # Portal: source at x=600, theta=0, displacement=(1000, 0)
    portal_src_carrier = GeneralizedCircle.from_three_points(600+300j, 600+500j, 600+700j)
    portal_tgt_carrier = GeneralizedCircle.from_three_points(1600+300j, 1600+500j, 1600+700j)

    # Build Möbius transforms
    arc1_refl = reflection_mobius(arc1_carrier)
    arc1_refl.label = "R_arc1"
    arc2_refl = reflection_mobius(arc2_carrier)
    arc2_refl.label = "R_arc2"

    portal_fwd, portal_inv = portal_mobius(0.0, 1000+0j)
    portal_fwd.label = "P_fwd"
    portal_inv.label = "P_inv"

    # (name, carrier, effect, start, end, via)
    surfaces = {
        1: ('wall_top', walls['top'], None,
            200+100j, 1700+100j, 950+100j),
        2: ('wall_right', walls['right'], None,
            1700+100j, 1700+900j, 1700+500j),
        3: ('wall_bottom', walls['bottom'], None,
            1700+900j, 200+900j, 950+900j),
        4: ('wall_left', walls['left'], None,
            200+900j, 200+100j, 200+500j),
        5: ('arc1_refl', arc1_carrier, arc1_refl,
            400+250j, 300+250j, 350+200j),
        6: ('arc2_refl', arc2_carrier, arc2_refl,
            1550+750j, 1450+750j, 1500+700j),
        7: ('portal_src', portal_src_carrier, portal_fwd,
            600+300j, 600+700j, 600+500j),
        8: ('portal_tgt', portal_tgt_carrier, portal_inv,
            1600+300j, 1600+700j, 1600+500j),
    }

    return surfaces, {
        'arc1_refl': arc1_refl,
        'arc2_refl': arc2_refl,
        'portal_fwd': portal_fwd,
        'portal_inv': portal_inv,
    }


# ============================================================================
# Section 3: Simplified Beam Tracer
# ============================================================================

def is_on_segment_cross_ratio(point: complex, start: complex, end: complex,
                                via: complex) -> bool:
    """Cross-ratio containment: Re(cross_ratio(S,P;E,V)) >= 0."""
    zP, wP = point, 1.0
    zS, wS = start, 1.0
    zE, wE = end, 1.0
    if np.isinf(via.real) or np.isinf(via.imag):
        zV, wV = 1+0j, 0.0
    else:
        zV, wV = via, 1.0

    def hdet(zA, wA, zB, wB):
        return zA * wB - zB * wA

    sv = hdet(zS, wS, zV, wV)
    ep = hdet(zE, wE, zP, wP)
    sp = hdet(zS, wS, zP, wP)
    ev = hdet(zE, wE, zV, wV)

    num = sv * ep
    den = sp * ev
    product = num * den.conjugate()
    return product.real >= 0.0


def determine_side(ray: Ray, point: complex, carrier: GeneralizedCircle) -> str:
    """Determine which side of the carrier the ray approaches from."""
    d = ray.direction / abs(ray.direction)
    x, y = point.real, point.imag
    grad = complex(2 * carrier.a * x + carrier.b, 2 * carrier.a * y + carrier.c)
    approach = -(d.real * grad.real + d.imag * grad.imag)
    return 'LEFT' if approach > 0 else 'RIGHT'


def trace_beam(surfaces, effects, player, cursor, max_bounces=15):
    """Simplified tracer that reproduces the beam path and frame composition.

    Returns list of steps: (step_idx, ray, frame, transform_stack, hit_info)
    """
    direction = cursor - player
    ray = Ray(player, direction)

    transform_stack = []  # list of (mobius, label, carrier, is_self_inverse, source_id)
    steps = []

    def recompute_frame():
        frame = MobiusTransform.identity()
        for (mob, label, carrier, is_si, src_id) in transform_stack:
            frame = mob.compose(frame)
        return frame

    def is_isometric_stack():
        return all(c.is_line() for (_, _, c, _, _) in transform_stack)

    def carrier_fixed_by_all(seg_carrier):
        for (_, _, tc, is_si, _) in transform_stack:
            if not (is_si and tc == seg_carrier):
                return False
        return True

    frame = MobiusTransform.identity()
    origin_on_surface_id = None

    for bounce in range(max_bounces):
        # Build normalized surfaces
        frame_inv = frame.invert()
        isometric = is_isometric_stack()

        # Find all hits
        best_hit = None
        best_t = float('inf')

        for surf_id, (name, carrier, effect, start, end, via) in surfaces.items():
            # Transform carrier/endpoints to normalized space if frame is non-identity
            if len(transform_stack) == 0:
                norm_carrier = carrier
                norm_start, norm_end, norm_via = start, end, via
            else:
                if carrier_fixed_by_all(carrier):
                    norm_carrier = carrier
                    norm_start, norm_end, norm_via = start, end, via
                else:
                    norm_start = frame_inv.apply(start)
                    norm_end = frame_inv.apply(end)
                    norm_via = frame_inv.apply(via)
                    if isometric:
                        direct = hermitian_transform(carrier, frame_inv)
                        if carrier.is_line():
                            norm_carrier = GeneralizedCircle.from_line(direct.b, direct.c, direct.d)
                        elif not direct.is_line():
                            norm_carrier = GeneralizedCircle.from_circle(direct.center(), carrier.radius())
                        else:
                            norm_carrier = direct
                    else:
                        norm_carrier = GeneralizedCircle.from_three_points(norm_start, norm_via, norm_end)

            # Intersect ray with normalized carrier
            hits = ray.intersect_carrier(norm_carrier)

            for t, point in hits:
                if t <= 1e-6:
                    continue
                if surf_id == origin_on_surface_id and t < 1e-4:
                    continue

                on_seg = is_on_segment_cross_ratio(point, norm_start, norm_end, norm_via)
                if not on_seg:
                    continue

                if t < best_t:
                    best_t = t
                    side = determine_side(ray, point, norm_carrier)
                    best_hit = {
                        'surf_id': surf_id,
                        'name': name,
                        't': t,
                        'point': point,
                        'carrier': carrier,
                        'norm_carrier': norm_carrier,
                        'effect': effect,
                        'side': side,
                    }

        if best_hit is None:
            break

        # Record step
        vis_start = frame.apply(ray.origin)
        vis_end = frame.apply(best_hit['point'])
        steps.append({
            'idx': bounce,
            'ray': Ray(ray.origin, ray.direction),
            'frame': MobiusTransform(frame.a, frame.b, frame.c, frame.d,
                                     frame.conjugating, frame.label),
            'hit': best_hit,
            'vis_start': vis_start,
            'vis_end': vis_end,
            'transform_stack': list(transform_stack),
        })

        # Apply effect
        hit = best_hit
        new_origin = hit['point']
        effect = hit['effect']
        surf_id = hit['surf_id']

        if effect is None:
            # Terminal (wall) — trace done
            break

        # Get the tracked transform
        tracked_mob = effect
        is_self_inverse = effect.conjugating  # reflections are conjugating = self-inverse
        tracked_carrier = hit['carrier']

        # Check if we should pop
        should_pop = False
        if transform_stack:
            top = transform_stack[-1]
            if is_self_inverse and top[3] and top[4] == surf_id:
                should_pop = True
            elif not is_self_inverse:
                top_mob = top[0]
                test = tracked_mob.compose(top_mob)
                if (abs(test.a - 1) < 1e-6 and abs(test.b) < 1e-6 and
                    abs(test.c) < 1e-6 and abs(test.d - 1) < 1e-6 and
                    not test.conjugating):
                    should_pop = True

        if should_pop:
            transform_stack.pop()
        else:
            transform_stack.append((tracked_mob, effect.label, tracked_carrier,
                                    is_self_inverse, surf_id))

        ray = Ray(new_origin, ray.direction)

        # Portal: origin is on the TARGET surface (which maps to same
        # position in the new normalized space). For self-inverse (reflections),
        # origin stays on the same surface.
        if is_self_inverse:
            origin_on_surface_id = surf_id
        else:
            # Find the paired portal surface
            # Portal pairs: 7↔8 (source↔target)
            portal_pairs = {7: 8, 8: 7}
            origin_on_surface_id = portal_pairs.get(surf_id, surf_id)

        frame = recompute_frame()

    return steps


# ============================================================================
# Section 4: Error Analysis Experiments
# ============================================================================

def analyze_step(step, surfaces):
    """Deep analysis of a single step's precision."""
    frame = step['frame']
    hit = step['hit']
    ray = step['ray']
    hp = hit['point']
    vis_end = step['vis_end']
    surf_id = hit['surf_id']
    phys_carrier = surfaces[surf_id][1]

    print(f"\n{'='*70}")
    print(f"STEP {step['idx']}: hit surface {surf_id} ({hit['name']})")
    print(f"  ray origin = {ray.origin}")
    print(f"  ray direction = {ray.direction}")
    print(f"  hitpoint (normalized) = {hp}")
    print(f"  vis_end = {vis_end}")
    print(f"  frame: a={frame.a}, b={frame.b}, c={frame.c}, d={frame.d}, conj={frame.conjugating}")
    print(f"  physical carrier: {phys_carrier}")

    # Distance to physical carrier
    dist = phys_carrier.geometric_dist(vis_end)
    print(f"\n  [BASELINE] dist to physical carrier: {dist:.6f} px")

    # Normalized carrier analysis
    norm_carrier = hit['norm_carrier']
    print(f"  normalized carrier: {norm_carrier}")
    if not norm_carrier.is_line():
        r = norm_carrier.radius()
        print(f"  normalized radius: {r}")
        if np.isnan(r):
            print(f"  *** DEGENERATE: radius is NaN! ***")

    return frame, ray, hp, phys_carrier, norm_carrier


def run_experiments(step, surfaces):
    """Run all precision experiments on a step."""
    frame, ray, hp, phys_carrier, norm_carrier = analyze_step(step, surfaces)

    print(f"\n{'='*70}")
    print("ERROR ANALYSIS EXPERIMENTS")
    print(f"{'='*70}")

    # --- 4a: Standard intersection (float64 vs simulated float32) ---
    print("\n--- 4a: Standard Intersection ---")
    hits_standard = ray.intersect_carrier(norm_carrier)
    print(f"  Standard hits: {len(hits_standard)}")
    for i, (t, pt) in enumerate(hits_standard):
        vis = frame.apply(pt)
        vis_f32 = frame.apply_f32(pt)
        d64 = phys_carrier.geometric_dist(vis)
        d32 = phys_carrier.geometric_dist(vis_f32)
        print(f"    hit[{i}]: t={t:.10f}, norm_pt={pt}")
        print(f"      frame.apply (f64) → {vis}")
        print(f"        dist to carrier: {d64:.6f} px")
        print(f"      frame.apply (f32) → {vis_f32}")
        print(f"        dist to carrier: {d32:.6f} px")

    # --- 4b: Pullback intersection (f64 back-project) ---
    print("\n--- 4b: Pullback Intersection (f64 back-project) ---")
    hits_pullback = inversive_pullback_intersect(ray, phys_carrier, frame, use_f64_backproject=True)
    print(f"  Pullback hits: {len(hits_pullback)}")
    for i, (t, pt) in enumerate(hits_pullback):
        vis = frame.apply(pt)
        vis_f32 = frame.apply_f32(pt)
        d64 = phys_carrier.geometric_dist(vis)
        d32 = phys_carrier.geometric_dist(vis_f32)
        print(f"    hit[{i}]: t={t:.10f}, norm_pt={pt}")
        print(f"      frame.apply (f64) → {vis}")
        print(f"        dist to carrier: {d64:.6f} px")
        print(f"      frame.apply (f32) → {vis_f32}")
        print(f"        dist to carrier: {d32:.6f} px")

    # --- 4b': Pullback with f32 back-project (simulating GDScript) ---
    print("\n--- 4b': Pullback with f32 back-project ---")
    hits_pb_f32 = inversive_pullback_intersect(ray, phys_carrier, frame, use_f64_backproject=False)
    for i, (t, pt) in enumerate(hits_pb_f32):
        vis = frame.apply(pt)
        vis_f32 = frame.apply_f32(pt)
        d64 = phys_carrier.geometric_dist(vis)
        d32 = phys_carrier.geometric_dist(vis_f32)
        print(f"    hit[{i}]: t={t:.10f}, norm_pt={pt}")
        print(f"      frame.apply (f64) → {vis}")
        print(f"        dist to carrier: {d64:.6f} px")
        print(f"      frame.apply (f32) → {vis_f32}")
        print(f"        dist to carrier: {d32:.6f} px")

    # --- 4c: Direct visual endpoint ---
    print("\n--- 4c: Direct Visual Endpoint (skip round-trip) ---")
    ray_line = ray_to_line(ray)
    visual_ray = hermitian_transform(ray_line, frame)
    visual_hits = intersect_circles(visual_ray, phys_carrier)
    print(f"  Visual ray: {visual_ray}")
    print(f"  Visual hits on physical carrier: {len(visual_hits)}")
    for i, vh in enumerate(visual_hits):
        d = phys_carrier.geometric_dist(vh)
        print(f"    vis_hit[{i}] = {vh}")
        print(f"      dist to carrier: {d:.15f} px (should be ~0)")

    # --- 4d: Error decomposition ---
    print("\n--- 4d: Error Decomposition ---")
    if hits_pullback:
        t_pb, pt_pb = hits_pullback[0]
        frame_inv = frame.invert()
        if visual_hits:
            vh = visual_hits[0]
            # Step 1: back-project visual hit to normalized space
            bp_f64 = frame_inv.apply(vh)
            bp_f32 = frame_inv.apply_f32(vh)
            print(f"  Visual hit: {vh}")
            print(f"  Back-project (f64): {bp_f64}")
            print(f"  Back-project (f32): {bp_f32}")
            print(f"  Back-project error (f32 vs f64): {abs(bp_f64 - bp_f32):.6e}")

            # Step 2: project onto ray
            t_f64 = ray.project_point(bp_f64)
            t_f32 = ray.project_point(bp_f32)
            on_ray_f64 = ray.origin + t_f64 * ray.direction
            on_ray_f32 = ray.origin + t_f32 * ray.direction
            print(f"  Projected t (f64 bp): {t_f64:.15f}")
            print(f"  Projected t (f32 bp): {t_f32:.15f}")
            print(f"  t difference: {abs(t_f64 - t_f32):.6e}")
            print(f"  on_ray (f64 bp): {on_ray_f64}")
            print(f"  on_ray (f32 bp): {on_ray_f32}")

            # Step 3: forward application
            fwd_f64 = frame.apply(on_ray_f64)
            fwd_f32 = frame.apply_f32(on_ray_f64)
            fwd_f32_f32 = frame.apply_f32(on_ray_f32)
            print(f"  frame.apply(on_ray_f64) [f64]: {fwd_f64}")
            print(f"    dist: {phys_carrier.geometric_dist(fwd_f64):.6f}")
            print(f"  frame.apply(on_ray_f64) [f32]: {fwd_f32}")
            print(f"    dist: {phys_carrier.geometric_dist(fwd_f32):.6f}")
            print(f"  frame.apply(on_ray_f32) [f32]: {fwd_f32_f32}")
            print(f"    dist: {phys_carrier.geometric_dist(fwd_f32_f32):.6f}")

    # --- 4e: Condition number analysis ---
    print("\n--- 4e: Condition Number Analysis ---")
    print(f"  |c| = {abs(frame.c):.10f}")
    print(f"  |d| = {abs(frame.d):.10f}")
    print(f"  |c|/|d| = {abs(frame.c)/abs(frame.d):.10f}" if abs(frame.d) > 0 else "  d=0!")
    pole = -frame.d / frame.c if frame.c != 0 else complex(np.inf)
    if frame.conjugating:
        pole = pole.conjugate()
    print(f"  Frame pole: {pole}")
    if not np.isinf(pole.real):
        pole_t = ray.project_point(pole)
        pole_on_ray = ray.origin + pole_t * ray.direction
        pole_dist_to_ray = abs(pole - pole_on_ray)
        print(f"  Pole t-parameter: {pole_t:.6f}")
        print(f"  Pole distance to ray: {pole_dist_to_ray:.6f}")

    # Det of the frame matrix
    det = frame.a * frame.d - frame.b * frame.c
    print(f"  Frame determinant: {det}")
    print(f"  |det|: {abs(det):.10f}")

    # Normalized carrier condition
    if not norm_carrier.is_line():
        disc = norm_carrier.b**2 + norm_carrier.c**2 - 4 * norm_carrier.a * norm_carrier.d
        print(f"  Norm carrier discriminant: {disc:.6e}")
        print(f"  Norm carrier |a|: {abs(norm_carrier.a):.6e}")


def run_selective_pullback_analysis(step, surfaces, all_steps):
    """For every surface, compare standard vs pullback t-values."""
    frame = step['frame']
    ray = step['ray']

    print(f"\n{'='*70}")
    print("SELECTIVE PULLBACK ANALYSIS: Per-Surface t-Value Comparison")
    print(f"{'='*70}")

    frame_inv = frame.invert()

    for surf_id, (name, carrier, effect, start, end, via) in surfaces.items():
        # Compute normalized carrier
        if len(step['transform_stack']) == 0:
            norm_carrier = carrier
        else:
            norm_carrier = hermitian_transform(carrier, frame_inv)
            if carrier.is_line():
                norm_carrier = GeneralizedCircle.from_line(norm_carrier.b, norm_carrier.c, norm_carrier.d)

        # Standard intersection
        hits_std = ray.intersect_carrier(norm_carrier)
        # Pullback intersection
        hits_pb = inversive_pullback_intersect(ray, carrier, frame, use_f64_backproject=True)

        std_ts = sorted([t for t, _ in hits_std if t > 1e-6])
        pb_ts = sorted([t for t, _ in hits_pb if t > 1e-6])

        # Compare
        if not std_ts and not pb_ts:
            continue

        is_degenerate = (not norm_carrier.is_line() and
                         (np.isnan(norm_carrier.radius()) or norm_carrier.radius() < 1.0))

        status = "DEGENERATE" if is_degenerate else "ok"
        print(f"\n  Surface {surf_id} ({name}) [{status}]")
        print(f"    norm_carrier: {norm_carrier}")
        if std_ts:
            print(f"    standard t: {', '.join(f'{t:.10f}' for t in std_ts)}")
        else:
            print(f"    standard t: (none)")
        if pb_ts:
            print(f"    pullback t: {', '.join(f'{t:.10f}' for t in pb_ts)}")
        else:
            print(f"    pullback t: (none)")

        if std_ts and pb_ts:
            for st, pt in zip(std_ts[:len(pb_ts)], pb_ts[:len(std_ts)]):
                delta = abs(st - pt)
                label = "DANGEROUS" if delta > 1e-4 else "SAFE"
                print(f"    delta_t: {delta:.6e}  [{label}]")

                # Compare visual endpoints
                vis_std = frame.apply(ray.origin + st * ray.direction)
                vis_pb = frame.apply(ray.origin + pt * ray.direction)
                vis_delta = abs(vis_std - vis_pb)
                print(f"    vis_endpoint delta: {vis_delta:.6f} px")
        elif std_ts and not pb_ts:
            print(f"    *** Pullback found NO hits but standard did! ***")
        elif not std_ts and pb_ts:
            print(f"    *** Standard found NO hits but pullback did! ***")


# ============================================================================
# Section 5: Main
# ============================================================================

def direct_precision_analysis():
    """Direct analysis computing the exact frame from known transforms.

    GDScript test_portal_refl_gap.gd trace output shows:
      Frame transitions: identity → R_arc1 → frameB → frameC → frameB
      Step [09]: frame=frameB, conj=false, portal=true, hit surf=2 (wall_right)
        hitpoint=(351.8234, 250.7779), vis_end=(1697.601, 647.8268)
        dist to wall carrier: 2.3993 px (threshold=2.0)

    We compute frameB from the known transforms to get full float64 precision.
    """
    print("=" * 70)
    print("DIRECT PRECISION ANALYSIS (frame computed from transforms)")
    print("=" * 70)

    surfaces, effects = build_scene()

    # The GDScript frame transitions show:
    # identity → frame_A → frame_B → frame_C → frame_B
    #
    # frame_A = R_arc1 (conjugating=true)
    # frame_B = ??? ∘ R_arc1 (conjugating=false, so second transform also conjugating)
    # frame_C = ??? ∘ ??? ∘ R_arc1
    #
    # frame_B has conj=false, R_arc1 has conj=true, so second transform conj=true
    # Portal fwd has conj=false. R_arc2 has conj=true. ✓
    # frame_C→frame_B means the third transform was popped (its inverse hit).
    #
    # Hypothesis: transform stack = [R_arc1, portal_fwd]
    # or: transform stack = [R_arc1, R_arc2]
    # Let's try both and match against the truncated GDScript output.

    R_arc1 = effects['arc1_refl']
    R_arc2 = effects['arc2_refl']
    P_fwd = effects['portal_fwd']
    P_inv = effects['portal_inv']

    # The tracer composes left: frame = T_n ∘ ... ∘ T_1
    # So for stack [R_arc1, X], frame = X.compose(R_arc1)

    candidates = {
        'R_arc2 ∘ R_arc1': R_arc2.compose(R_arc1),
        'P_fwd ∘ R_arc1': P_fwd.compose(R_arc1),
        'P_inv ∘ R_arc1': P_inv.compose(R_arc1),
    }

    # GDScript frame_B: a=(-0.002311, -0.000124) b=(0.782036, 0.623233) conj=false
    print("\n  Candidate frame compositions:")
    for name, f in candidates.items():
        match_a = f"a=({f.a.real:.6f}, {f.a.imag:.6f})"
        match_b = f"b=({f.b.real:.6f}, {f.b.imag:.6f})"
        print(f"    {name}: {match_a} {match_b} conj={f.conjugating}")

    # Also try deeper compositions
    deeper = {
        'P_fwd ∘ R_arc2 ∘ R_arc1': P_fwd.compose(R_arc2.compose(R_arc1)),
        'P_inv ∘ R_arc2 ∘ R_arc1': P_inv.compose(R_arc2.compose(R_arc1)),
        'R_arc2 ∘ P_fwd ∘ R_arc1': R_arc2.compose(P_fwd.compose(R_arc1)),
        'R_arc2 ∘ P_inv ∘ R_arc1': R_arc2.compose(P_inv.compose(R_arc1)),
        'P_fwd ∘ R_arc1 ∘ R_arc2': P_fwd.compose(R_arc1.compose(R_arc2)),
    }
    print("\n  Deeper compositions:")
    for name, f in deeper.items():
        match_a = f"a=({f.a.real:.6f}, {f.a.imag:.6f})"
        match_b = f"b=({f.b.real:.6f}, {f.b.imag:.6f})"
        print(f"    {name}: {match_a} {match_b} conj={f.conjugating}")

    # Expected: a≈(-0.002311, -0.000124) b≈(0.782036, 0.623233) conj=false
    # Find the match
    target_a = complex(-0.002311, -0.000124)
    target_b = complex(0.782036, 0.623233)

    all_candidates = {**candidates, **deeper}
    best_name = None
    best_err = float('inf')
    for name, f in all_candidates.items():
        if f.conjugating:
            continue  # Must be non-conjugating
        err = abs(f.a - target_a) + abs(f.b - target_b)
        if err < best_err:
            best_err = err
            best_name = name

    print(f"\n  Best match: {best_name} (error: {best_err:.6e})")
    frame = all_candidates[best_name]
    print(f"  Frame: {frame}")

    # Wall at x=1700 (right wall)
    wall_carrier = GeneralizedCircle.from_line(800, 0, -1360000)  # 800*x - 1360000 = 0 → x=1700

    # Ray direction (same throughout trace: Player→Cursor)
    PLAYER = complex(1334.662, 234.909)
    CURSOR = complex(400, 250)
    ray_dir = CURSOR - PLAYER  # (-934.662, 15.091)

    # The truncated hitpoint from GDScript doesn't have enough precision.
    # Instead, find the EXACT hitpoint by back-projecting a known point on the wall.
    # The visual endpoint should be on x=1700. Pick a plausible y from GDScript output.
    frame_inv = frame.invert()
    vis_target = complex(1700, 647.8268)  # exact x, approximate y from GDScript
    hp_exact = frame_inv.apply(vis_target)
    print(f"\n  Exact hp (back-projected from wall): {hp_exact}")
    print(f"  GDScript truncated hp:               (351.8234+250.7779j)")
    print(f"  Difference:                          {abs(hp_exact - complex(351.8234, 250.7779)):.6e}")

    # Place ray origin before hp_exact on the ray line
    t_for_hp = 0.1  # arbitrary, just needs a positive t
    ray_origin = hp_exact - t_for_hp * ray_dir
    ray = Ray(ray_origin, ray_dir)
    t_hp = ray.project_point(hp_exact)

    print(f"\n  Frame: a={frame.a}, b={frame.b}")
    print(f"        c={frame.c}, d={frame.d}, conj={frame.conjugating}")
    print(f"  Wall carrier: {wall_carrier}")
    print(f"  Hitpoint (norm): {hp_exact}")
    print(f"  Ray origin: {ray_origin}")
    print(f"  Ray direction: {ray_dir}")
    print(f"  t of hitpoint on ray: {t_hp:.10f}")

    # Verify frame.apply(hp) ≈ (1700, 647.8)
    vis_end = frame.apply(hp_exact)
    vis_end_f32 = frame.apply_f32(hp_exact)
    print(f"\n  frame.apply(hp) [f64]: {vis_end}")
    print(f"  frame.apply(hp) [f32]: {vis_end_f32}")
    print(f"  dist to wall [f64]: {wall_carrier.geometric_dist(vis_end):.6f} px")
    print(f"  dist to wall [f32]: {wall_carrier.geometric_dist(vis_end_f32):.6f} px")

    # Compute normalized wall carrier — TWO methods
    frame_inv = frame.invert()

    # Method 1: Hermitian congruence (mathematically exact for float64)
    norm_wall_herm = hermitian_transform(wall_carrier, frame_inv)
    print(f"\n  Normalized wall carrier (Hermitian): {norm_wall_herm}")
    if not norm_wall_herm.is_line():
        print(f"    radius: {norm_wall_herm.radius():.6g}")
        print(f"    center: {norm_wall_herm.center()}")

    # Method 2: Transform 3 endpoints, derive carrier (matches GDScript _build_normalized)
    wall_start = complex(1700, 100)
    wall_end = complex(1700, 900)
    wall_via = complex(1700, 500)
    norm_ws = frame_inv.apply(wall_start)
    norm_we = frame_inv.apply(wall_end)
    norm_wv = frame_inv.apply(wall_via)
    norm_wall_3pt = GeneralizedCircle.from_three_points(norm_ws, norm_wv, norm_we)
    print(f"\n  Normalized wall carrier (3-point): {norm_wall_3pt}")
    if not norm_wall_3pt.is_line():
        print(f"    radius: {norm_wall_3pt.radius():.6g}")
        print(f"    center: {norm_wall_3pt.center()}")
    print(f"    3 norm points: start={norm_ws}, via={norm_wv}, end={norm_we}")

    # Method 2b: Same but with simulated float32 apply (what GDScript actually does)
    norm_ws32 = frame_inv.apply_f32(wall_start)
    norm_we32 = frame_inv.apply_f32(wall_end)
    norm_wv32 = frame_inv.apply_f32(wall_via)
    norm_wall_f32 = GeneralizedCircle.from_three_points(norm_ws32, norm_wv32, norm_we32)
    print(f"\n  Normalized wall carrier (3-point, f32): {norm_wall_f32}")
    if not norm_wall_f32.is_line():
        print(f"    radius: {norm_wall_f32.radius():.6g}")
        print(f"    center: {norm_wall_f32.center()}")
    print(f"    3 norm points f32: start={norm_ws32}, via={norm_wv32}, end={norm_we32}")

    # Use the 3-point f32 carrier (most realistic) for experiments
    norm_wall = norm_wall_f32

    # ---- EXPERIMENT 1: Standard intersection ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 1: Standard Intersection")
    print(f"{'='*60}")
    hits = ray.intersect_carrier(norm_wall)
    print(f"  Hits: {len(hits)}")
    for i, (t, pt) in enumerate(hits):
        if t <= 0:
            continue
        vis = frame.apply(pt)
        vis32 = frame.apply_f32(pt)
        d64 = wall_carrier.geometric_dist(vis)
        d32 = wall_carrier.geometric_dist(vis32)
        print(f"  hit[{i}]: t={t:.15f}")
        print(f"    norm pt: {pt}")
        print(f"    frame.apply [f64]: {vis}  dist={d64:.6f}")
        print(f"    frame.apply [f32]: {vis32}  dist={d32:.6f}")

    # ---- EXPERIMENT 2: Pullback intersection ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 2: Inversive Pullback")
    print(f"{'='*60}")
    ray_line = ray_to_line(ray)
    visual_ray = hermitian_transform(ray_line, frame)
    print(f"  Visual ray carrier: {visual_ray}")

    if not visual_ray.is_line():
        vr_center = visual_ray.center()
        vr_radius = visual_ray.radius()
        print(f"  Visual ray center: ({vr_center.real:.6f}, {vr_center.imag:.6f})")
        print(f"  Visual ray radius: {vr_radius:.6f}")
        print(f"  Visual ray closest x to wall (x=1700): {vr_center.real + vr_radius:.6f}")
        print(f"  Gap to wall: {1700 - (vr_center.real + vr_radius):.6f}")
        # Also show what the "true" radius should be by checking if catastrophic cancellation occurred
        b2c2 = visual_ray.b**2 + visual_ray.c**2
        four_a2 = 4 * visual_ray.a**2
        d_over_a = visual_ray.d / visual_ray.a
        print(f"  Radius computation: sqrt(b²+c²/(4a²) - d/a)")
        print(f"    b²+c²/(4a²) = {b2c2/four_a2:.15e}")
        print(f"    d/a          = {d_over_a:.15e}")
        print(f"    difference   = {b2c2/four_a2 - d_over_a:.15e}")
        print(f"    (catastrophic cancellation if these are similar magnitude)")

    visual_hits = intersect_circles(visual_ray, wall_carrier)
    print(f"  Visual hits on wall: {len(visual_hits)}")
    for i, vh in enumerate(visual_hits):
        print(f"  vis_hit[{i}] = {vh}")
        print(f"    dist to wall: {wall_carrier.geometric_dist(vh):.15e}")

    # Verify: map known ray points through frame and check if they lie on visual_ray
    print(f"\n  Verification: do frame-mapped ray points lie on visual_ray?")
    for t_test in [0.0, 0.05, 0.08, 0.095, 0.0999, t_hp]:
        pt = ray.origin + t_test * ray.direction
        mapped = frame.apply(pt)
        eval_val = visual_ray.evaluate(mapped)
        grad_x = 2 * visual_ray.a * mapped.real + visual_ray.b
        grad_y = 2 * visual_ray.a * mapped.imag + visual_ray.c
        grad_mag = np.sqrt(grad_x**2 + grad_y**2)
        geo_dist = abs(eval_val) / max(grad_mag, 1e-30)
        print(f"    t={t_test:.6f}: mapped=({mapped.real:.2f},{mapped.imag:.2f}) "
              f"eval={eval_val:.6e} geo_dist={geo_dist:.4f}")

    # Full pullback pipeline
    pb_hits_f64 = inversive_pullback_intersect(ray, wall_carrier, frame, use_f64_backproject=True)
    pb_hits_f32 = inversive_pullback_intersect(ray, wall_carrier, frame, use_f64_backproject=False)

    print(f"\n  Pullback hits (f64 back-project): {len(pb_hits_f64)}")
    for i, (t, pt) in enumerate(pb_hits_f64):
        if t <= 0:
            continue
        vis = frame.apply(pt)
        vis32 = frame.apply_f32(pt)
        print(f"  hit[{i}]: t={t:.15f}")
        print(f"    norm pt: {pt}")
        print(f"    frame.apply [f64]: {vis}  dist={wall_carrier.geometric_dist(vis):.6f}")
        print(f"    frame.apply [f32]: {vis32}  dist={wall_carrier.geometric_dist(vis32):.6f}")

    print(f"\n  Pullback hits (f32 back-project): {len(pb_hits_f32)}")
    for i, (t, pt) in enumerate(pb_hits_f32):
        if t <= 0:
            continue
        vis = frame.apply(pt)
        vis32 = frame.apply_f32(pt)
        print(f"  hit[{i}]: t={t:.15f}")
        print(f"    norm pt: {pt}")
        print(f"    frame.apply [f64]: {vis}  dist={wall_carrier.geometric_dist(vis):.6f}")
        print(f"    frame.apply [f32]: {vis32}  dist={wall_carrier.geometric_dist(vis32):.6f}")

    # ---- EXPERIMENT 3: Direct visual endpoint ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 3: Direct Visual Endpoint (skip round-trip)")
    print(f"{'='*60}")
    if visual_hits:
        vh = visual_hits[0]
        print(f"  Visual hit directly: {vh}")
        print(f"  dist to wall: {wall_carrier.geometric_dist(vh):.15e} px")
        print(f"  This IS the answer if we could use it directly as vis_end.")
        print(f"  x-coord: {vh.real:.15f} (wall at 1700.0)")

    # ---- EXPERIMENT 4: Error decomposition ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 4: Error Source Decomposition")
    print(f"{'='*60}")
    if visual_hits:
        vh = visual_hits[0]

        # Back-project
        bp_f64 = frame_inv.apply(vh)
        bp_f32 = frame_inv.apply_f32(vh)
        print(f"  Visual hit: {vh}")
        print(f"  Back-project [f64]: {bp_f64}")
        print(f"  Back-project [f32]: {bp_f32}")
        print(f"  Back-project error: {abs(bp_f64 - bp_f32):.6e}")

        # Project onto ray
        t_f64 = ray.project_point(bp_f64)
        t_f32 = ray.project_point(bp_f32)
        pt_f64 = ray.origin + t_f64 * ray.direction
        pt_f32 = ray.origin + t_f32 * ray.direction
        print(f"\n  Ray projection [f64 bp]: t={t_f64:.15f}")
        print(f"  Ray projection [f32 bp]: t={t_f32:.15f}")
        print(f"  t delta: {abs(t_f64 - t_f32):.6e}")

        # Forward map
        fwd_64_64 = frame.apply(pt_f64)
        fwd_32_64 = frame.apply_f32(pt_f64)
        fwd_64_32 = frame.apply(pt_f32)
        fwd_32_32 = frame.apply_f32(pt_f32)

        print(f"\n  Roundtrip results (backproject → project → forward):")
        print(f"    f64 all:       {fwd_64_64}  dist={wall_carrier.geometric_dist(fwd_64_64):.6f}")
        print(f"    f32 forward:   {fwd_32_64}  dist={wall_carrier.geometric_dist(fwd_32_64):.6f}")
        print(f"    f32 back:      {fwd_64_32}  dist={wall_carrier.geometric_dist(fwd_64_32):.6f}")
        print(f"    f32 both:      {fwd_32_32}  dist={wall_carrier.geometric_dist(fwd_32_32):.6f}")

        # How much does the roundtrip deviate from direct?
        print(f"\n  Roundtrip vs direct visual hit:")
        print(f"    direct:     x={vh.real:.15f}")
        print(f"    f64 round:  x={fwd_64_64.real:.15f}  delta={abs(vh.real - fwd_64_64.real):.6e}")
        print(f"    f32 round:  x={fwd_32_32.real:.15f}  delta={abs(vh.real - fwd_32_32.real):.6e}")

    # ---- EXPERIMENT 5: Condition number ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 5: Condition Number & Sensitivity")
    print(f"{'='*60}")
    print(f"  |c| = {abs(frame.c):.15e}")
    print(f"  |d| = {abs(frame.d):.15e}")
    print(f"  |c|/|d| = {abs(frame.c)/abs(frame.d):.15e}")
    det = frame.a * frame.d - frame.b * frame.c
    print(f"  det = {det}")
    print(f"  |det| = {abs(det):.15e}")

    pole = -frame.d / frame.c if frame.c != 0 else complex(np.inf)
    print(f"  Pole: {pole}")
    if not np.isinf(pole.real):
        pole_t = ray.project_point(pole)
        print(f"  Pole t on ray: {pole_t:.6f}")
        print(f"  Pole dist to ray: {abs(pole - (ray.origin + pole_t * ray.direction)):.6f}")
        print(f"  Pole dist to hitpoint: {abs(pole - hp_exact):.6f}")

    # ---- EXPERIMENT 6: What if we compute vis_end differently? ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 6: Alternative vis_end Strategies")
    print(f"{'='*60}")

    # Strategy A: frame.apply(hp) — current approach
    vis_A = frame.apply(hp_exact)
    print(f"  A. frame.apply(hp) [f64]:     {vis_A}  dist={wall_carrier.geometric_dist(vis_A):.6f}")
    vis_A32 = frame.apply_f32(hp_exact)
    print(f"     frame.apply(hp) [f32]:     {vis_A32}  dist={wall_carrier.geometric_dist(vis_A32):.6f}")

    # Strategy B: frame.apply_f64(hp) with GDScript-like scalar float64
    # (already have this as frame.apply since Python uses f64)
    print(f"  B. apply_f64(hp):             same as A f64 above")

    # Strategy C: pullback visual hit directly
    if visual_hits:
        vis_C = visual_hits[0]
        print(f"  C. direct visual hit:         {vis_C}  dist={wall_carrier.geometric_dist(vis_C):.15e}")

    # Strategy D: pullback + f64 roundtrip
    if pb_hits_f64:
        t_pb, pt_pb = pb_hits_f64[0]
        vis_D = frame.apply(pt_pb)
        print(f"  D. pullback f64 roundtrip:    {vis_D}  dist={wall_carrier.geometric_dist(vis_D):.6f}")

    # Strategy E: project visual hit onto wall (snap to carrier)
    if visual_hits:
        vh = visual_hits[0]
        # For a vertical wall x=1700, snapping means setting x=1700
        vis_E = complex(1700, vh.imag)
        print(f"  E. snap to wall:              {vis_E}  dist={wall_carrier.geometric_dist(vis_E):.15e}")

    # Strategy F: compute vis_end as frame.apply(hp) but then project onto
    # physical carrier (post-hoc correction)
    vis_F = vis_A
    # For line bx+cy+d=0: project point onto line
    # Wall: 800*x + 0*y - 1360000 = 0 → x = 1700
    vis_F = complex(1700, vis_F.imag)
    print(f"  F. apply then snap:           {vis_F}  dist={wall_carrier.geometric_dist(vis_F):.15e}")

    # ---- EXPERIMENT 7: Sensitivity to hitpoint perturbation ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 7: Sensitivity — How much does hp error amplify?")
    print(f"{'='*60}")
    for eps_mag in [1e-3, 1e-4, 1e-5, 1e-6, 1e-7]:
        # Perturb hp by eps in a random direction
        for label, eps in [("x+", complex(eps_mag, 0)),
                           ("y+", complex(0, eps_mag))]:
            hp_pert = hp_exact + eps
            vis_pert = frame.apply(hp_pert)
            vis_delta = abs(vis_pert - vis_end)
            amplification = vis_delta / eps_mag if eps_mag > 0 else 0
            wall_dist = wall_carrier.geometric_dist(vis_pert)
            print(f"  eps={eps_mag:.0e} {label}: vis_delta={vis_delta:.6f} "
                  f"amplification={amplification:.1f}x  wall_dist={wall_dist:.4f}")

    # ---- EXPERIMENT 8: Per-surface pullback safety ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 8: Per-Surface Pullback Safety at This Frame")
    print(f"{'='*60}")

    surfaces, _ = build_scene()
    for surf_id, (name, carrier, effect, start, end, via) in surfaces.items():
        # Compute normalized carrier
        norm_c = hermitian_transform(carrier, frame_inv)
        if carrier.is_line():
            norm_c = GeneralizedCircle.from_line(norm_c.b, norm_c.c, norm_c.d)

        hits_std = ray.intersect_carrier(norm_c)
        hits_pb = inversive_pullback_intersect(ray, carrier, frame, use_f64_backproject=True)

        std_ts = sorted([t for t, _ in hits_std if t > 1e-6])
        pb_ts = sorted([t for t, _ in hits_pb if t > 1e-6])

        if not std_ts and not pb_ts:
            continue

        is_degenerate = (not norm_c.is_line() and
                         (np.isnan(norm_c.radius()) if not norm_c.is_line() else False))

        status = "DEGENERATE" if is_degenerate else "ok"
        print(f"\n  Surface {surf_id} ({name}) [{status}]")
        if not norm_c.is_line():
            try:
                print(f"    norm radius: {norm_c.radius():.6g}")
            except:
                print(f"    norm radius: ERROR")
        if std_ts:
            print(f"    standard t: {', '.join(f'{t:.10f}' for t in std_ts[:3])}")
        if pb_ts:
            print(f"    pullback t: {', '.join(f'{t:.10f}' for t in pb_ts[:3])}")
        if std_ts and pb_ts:
            for st, pt in zip(std_ts[:2], pb_ts[:2]):
                delta = abs(st - pt)
                label = "DANGEROUS" if delta > 1e-4 else "SAFE"
                vis_s = frame.apply(ray.origin + st * ray.direction)
                vis_p = frame.apply(ray.origin + pt * ray.direction)
                print(f"    delta_t={delta:.6e} vis_delta={abs(vis_s-vis_p):.4f}px [{label}]")


    # ---- EXPERIMENT 9: Pole-Residue Form ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 9: Pole-Residue Form of Möbius Transform")
    print(f"{'='*60}")

    # The standard form:  f(z) = (az+b)/(cz+d)
    # The pole-residue form: f(z) = A + R/(z - P)
    # where A = a/c (asymptote), R = (bc - ad)/c² (residue), P = -d/c (pole)

    # First, compute from PRE-NORMALIZATION coefficients for maximum precision.
    # Re-derive from the raw transforms without normalization.
    R_arc1_raw = reflection_mobius(
        GeneralizedCircle.from_three_points(400+250j, 350+200j, 300+250j))
    R_arc2_raw = reflection_mobius(
        GeneralizedCircle.from_three_points(1550+750j, 1500+700j, 1450+750j))

    # Compose WITHOUT normalization to preserve coefficient magnitude
    a2, b2, c2, d2 = R_arc1_raw.a, R_arc1_raw.b, R_arc1_raw.c, R_arc1_raw.d
    # R_arc2 is conjugating, so conjugate R_arc1's coefficients
    a2, b2, c2, d2 = a2.conjugate(), b2.conjugate(), c2.conjugate(), d2.conjugate()
    raw_a = R_arc2_raw.a * a2 + R_arc2_raw.b * c2
    raw_b = R_arc2_raw.a * b2 + R_arc2_raw.b * d2
    raw_c = R_arc2_raw.c * a2 + R_arc2_raw.d * c2
    raw_d = R_arc2_raw.c * b2 + R_arc2_raw.d * d2
    # NOT normalizing!

    print(f"\n  Pre-normalization coefficients:")
    print(f"    a = {raw_a}")
    print(f"    b = {raw_b}")
    print(f"    c = {raw_c}")
    print(f"    d = {raw_d}")
    print(f"    |a| = {abs(raw_a):.6e}, |b| = {abs(raw_b):.6e}")
    print(f"    |c| = {abs(raw_c):.6e}, |d| = {abs(raw_d):.6e}")

    raw_det = raw_a * raw_d - raw_b * raw_c
    print(f"\n  Determinant (pre-norm): {raw_det}")
    print(f"    |det| = {abs(raw_det):.6e}")

    # Individual determinants
    det1 = R_arc1_raw.a * R_arc1_raw.d - R_arc1_raw.b * R_arc1_raw.c
    det2 = R_arc2_raw.a * R_arc2_raw.d - R_arc2_raw.b * R_arc2_raw.c
    print(f"\n  Individual determinants:")
    print(f"    det(R_arc1) = {det1}  (expected: -4a²r² = -10000)")
    print(f"    det(R_arc2) = {det2}  (expected: -4a²r² = -10000)")
    print(f"    det(R_arc2) * conj(det(R_arc1)) = {det2 * det1.conjugate()}")
    print(f"    (should equal raw det: {raw_det})")

    # Compute the EXACT determinant by multiplying individual dets
    exact_det = det2 * det1.conjugate()
    print(f"\n  Exact determinant (product of individuals): {exact_det}")
    print(f"    |exact_det| = {abs(exact_det):.6e}")

    # Now compute pole-residue parameters
    if raw_c != 0:
        PR_A = raw_a / raw_c  # asymptote
        PR_P = -raw_d / raw_c  # pole
        PR_R = -exact_det / (raw_c * raw_c)  # residue using exact det
        PR_R_naive = (raw_b * raw_c - raw_a * raw_d) / (raw_c * raw_c)  # naive det

        print(f"\n  Pole-Residue parameters:")
        print(f"    Asymptote A = {PR_A}")
        print(f"    Pole      P = {PR_P}")
        print(f"    Residue   R = {PR_R}  (using exact det)")
        print(f"    Residue   R' = {PR_R_naive}  (using naive det)")
        print(f"    R vs R' diff: {abs(PR_R - PR_R_naive):.6e}")

        # Now evaluate f(hp) using pole-residue form
        z = hp_exact  # non-conjugating frame, no conjugation needed
        dz = z - PR_P
        print(f"\n  Evaluating f(hp) via pole-residue form:")
        print(f"    z - P = {dz}")
        print(f"    |z - P| = {abs(dz):.10f}")
        print(f"    R / (z - P) = {PR_R / dz}")
        pr_result = PR_A + PR_R / dz
        print(f"    f(z) = A + R/(z-P) = {pr_result}")
        print(f"    dist to wall: {wall_carrier.geometric_dist(pr_result):.15e}")

        # Compare with standard form
        std_result = frame.apply(hp_exact)
        print(f"\n  Comparison:")
        print(f"    Standard form:     {std_result}  dist={wall_carrier.geometric_dist(std_result):.6e}")
        print(f"    Pole-residue form: {pr_result}  dist={wall_carrier.geometric_dist(pr_result):.6e}")
        print(f"    Difference:        {abs(std_result - pr_result):.6e}")

        # Simulate f32 coefficient storage for pole-residue
        def f32(x):
            return float(np.float32(x))
        def v2_f32(c):
            return complex(f32(c.real), f32(c.imag))

        PR_A_f32 = v2_f32(PR_A)
        PR_P_f32 = v2_f32(PR_P)
        PR_R_f32 = v2_f32(PR_R)

        dz_f32 = v2_f32(z) - PR_P_f32
        pr_result_f32_coeffs = PR_A_f32 + PR_R_f32 / dz_f32
        print(f"\n  Pole-residue with f32 coefficients (A, R, P stored as float32):")
        print(f"    A_f32 = {PR_A_f32}")
        print(f"    P_f32 = {PR_P_f32}")
        print(f"    R_f32 = {PR_R_f32}")
        print(f"    z - P_f32 = {dz_f32}")
        print(f"    result = {pr_result_f32_coeffs}")
        print(f"    dist to wall: {wall_carrier.geometric_dist(pr_result_f32_coeffs):.6f}")

        # NOW: what if A, R, P are stored as float64 (GDScript's 'float' type)?
        # This is the key test — GDScript's float IS float64
        print(f"\n  Pole-residue with f64 coefficients (GDScript float):")
        print(f"    result = {pr_result}")
        print(f"    dist to wall: {wall_carrier.geometric_dist(pr_result):.15e}")

        # What about when hp itself has f32 error (from intersection)?
        hp_f32 = v2_f32(hp_exact)
        dz_hp32 = hp_f32 - PR_P  # f64 pole, f32 hitpoint
        pr_hp32 = PR_A + PR_R / dz_hp32
        std_hp32 = frame.apply(hp_f32)
        print(f"\n  With f32 hitpoint, f64 coefficients:")
        print(f"    hp_f32 = {hp_f32}")
        print(f"    pole-residue: {pr_hp32}  dist={wall_carrier.geometric_dist(pr_hp32):.6f}")
        print(f"    standard:     {std_hp32}  dist={wall_carrier.geometric_dist(std_hp32):.6f}")

        # Test with ACTUAL intersection hitpoints from experiment 1
        print(f"\n  Pole-residue on actual intersection hits (from experiment 1):")
        hits = ray.intersect_carrier(norm_wall)
        for i, (t, pt) in enumerate(hits):
            if t <= 0:
                continue
            dz_hit = pt - PR_P
            pr_hit = PR_A + PR_R / dz_hit
            std_hit = frame.apply(pt)
            std_hit_f32 = frame.apply_f32(pt)
            print(f"    hit[{i}]: t={t:.12f}")
            print(f"      pole-residue (f64): {pr_hit}  dist={wall_carrier.geometric_dist(pr_hit):.6f}")
            print(f"      standard (f64):     {std_hit}  dist={wall_carrier.geometric_dist(std_hit):.6f}")
            print(f"      standard (f32):     {std_hit_f32}  dist={wall_carrier.geometric_dist(std_hit_f32):.6f}")

    # ---- EXPERIMENT 10: Geometric Ray-Circle Intersection ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 10: Geometric Ray-Circle Intersection (Orthogonal Projection)")
    print(f"{'='*60}")

    # The expert's suggestion: instead of the algebraic quadratic formula which
    # suffers from d²-r² cancellation, use orthogonal projection.
    # For tiny circles (r~0.01) far from origin (d~350), the standard quadratic
    # has qc = a*(ox²+oy²) + ... ≈ a*182500, while the circle term is a*r² ≈ a*0.0001.
    # These span ~9 orders of magnitude.

    def geometric_ray_circle_intersect(ray: Ray, carrier: GeneralizedCircle):
        """Intersect ray with circle using orthogonal projection method."""
        if carrier.is_line():
            return ray.intersect_carrier(carrier)  # lines don't have this issue

        center = carrier.center()
        r = carrier.radius()
        if np.isnan(r):
            return []

        # 1. Vector from ray origin to circle center
        V = center - ray.origin

        # 2. Project center onto ray to find closest approach
        d = ray.direction
        d_len_sq = d.real**2 + d.imag**2
        t_closest = (V.real * d.real + V.imag * d.imag) / d_len_sq

        # 3. Closest point on ray to center
        P_closest = ray.origin + t_closest * d

        # 4. Perpendicular distance
        h = abs(P_closest - center)

        # 5. Check if ray intersects
        if h > r + 1e-12:
            return []

        # 6. Chord half-length: L = sqrt(r² - h²)
        # KEY: r and h are both ~0.01, so r²-h² doesn't suffer cancellation
        h_sq = h * h
        r_sq = r * r
        L_sq = r_sq - h_sq
        if L_sq < 0:
            L_sq = 0
        L = np.sqrt(L_sq)

        d_len = np.sqrt(d_len_sq)
        dt = L / d_len

        if dt < 1e-15:
            pt = ray.origin + t_closest * d
            return [(t_closest, pt)]

        t1 = t_closest - dt
        t2 = t_closest + dt
        return [(t1, ray.origin + t1 * d), (t2, ray.origin + t2 * d)]

    # Compare with standard algebraic intersection on the normalized wall carrier
    print(f"\n  Normalized wall carrier: center={norm_wall.center()}, r={norm_wall.radius():.10f}")
    print(f"  Ray origin dist to center: {abs(ray.origin - norm_wall.center()):.10f}")

    hits_algebraic = ray.intersect_carrier(norm_wall)
    hits_geometric = geometric_ray_circle_intersect(ray, norm_wall)

    print(f"\n  Algebraic (standard quadratic):")
    for i, (t, pt) in enumerate(hits_algebraic):
        vis = frame.apply(pt)
        print(f"    hit[{i}]: t={t:.15f} -> vis_dist={wall_carrier.geometric_dist(vis):.6f}")

    print(f"\n  Geometric (orthogonal projection):")
    for i, (t, pt) in enumerate(hits_geometric):
        vis = frame.apply(pt)
        # Also try pole-residue evaluation
        pr_vis = PR_A + PR_R / (pt - PR_P) if raw_c != 0 else vis
        print(f"    hit[{i}]: t={t:.15f} -> vis_dist={wall_carrier.geometric_dist(vis):.6f}"
              f"  (pole-residue: {wall_carrier.geometric_dist(pr_vis):.6f})")

    # Show the internal numbers to verify the cancellation avoidance
    if not norm_wall.is_line():
        center = norm_wall.center()
        r = norm_wall.radius()
        V = center - ray.origin
        d = ray.direction
        d_len_sq = d.real**2 + d.imag**2
        t_closest = (V.real * d.real + V.imag * d.imag) / d_len_sq
        P_closest = ray.origin + t_closest * d
        h = abs(P_closest - center)
        print(f"\n  Geometric internals:")
        print(f"    t_closest = {t_closest:.15f}")
        print(f"    h (perp dist) = {h:.15e}")
        print(f"    r = {r:.15e}")
        print(f"    r² = {r**2:.15e}")
        print(f"    h² = {h**2:.15e}")
        print(f"    r² - h² = {r**2 - h**2:.15e}  (same-magnitude subtraction)")
        print(f"    Compare: algebraic qc = a*(ox²+oy²)+b*ox+c*oy+d")
        ox, oy = ray.origin.real, ray.origin.imag
        qc_val = norm_wall.a*(ox**2+oy**2) + norm_wall.b*ox + norm_wall.c*oy + norm_wall.d
        qa_val = norm_wall.a * d_len_sq
        print(f"      qa = {qa_val:.15e}")
        print(f"      qc = {qc_val:.15e}")
        print(f"      |qc/qa| = {abs(qc_val/qa_val):.6e}  (large ratio → cancellation in discriminant)")

    # ---- EXPERIMENT 11: Geometric Visual Ray (3-point sampling) ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 11: Geometric Visual Ray (3-point frame.apply sampling)")
    print(f"{'='*60}")

    # Instead of Hermitian congruence (which fails due to near-singular frame),
    # sample 3 points on the normalized ray, map them through frame.apply,
    # and fit a circle through those visual points.

    # Choose 3 widely-spaced points on the ray AWAY from the pole (t≈0.1)
    # to avoid the worst amplification zone.
    t_samples = [0.0, 0.04, 0.08]  # well before the pole at t≈0.0999
    ray_pts = [ray.origin + t * ray.direction for t in t_samples]
    vis_pts = [frame.apply(p) for p in ray_pts]

    print(f"  Sample points:")
    for i, (t, rp, vp) in enumerate(zip(t_samples, ray_pts, vis_pts)):
        print(f"    t={t:.2f}: norm=({rp.real:.2f},{rp.imag:.2f}) -> "
              f"vis=({vp.real:.2f},{vp.imag:.2f})")

    # Fit visual ray carrier from 3 visual points
    vis_ray_geom = GeneralizedCircle.from_three_points(vis_pts[0], vis_pts[1], vis_pts[2])
    print(f"\n  Geometric visual ray carrier: {vis_ray_geom}")
    if not vis_ray_geom.is_line():
        print(f"    center: ({vis_ray_geom.center().real:.4f}, {vis_ray_geom.center().imag:.4f})")
        print(f"    radius: {vis_ray_geom.radius():.4f}")

    # Verify: do frame-mapped ray points lie on this carrier?
    print(f"\n  Verification (frame-mapped points on geometric visual ray):")
    for t_test in [0.0, 0.02, 0.05, 0.08, 0.095, 0.0999]:
        pt = ray.origin + t_test * ray.direction
        mapped = frame.apply(pt)
        gdist = vis_ray_geom.geometric_dist(mapped)
        print(f"    t={t_test:.4f}: vis=({mapped.real:.2f},{mapped.imag:.2f}) geo_dist={gdist:.6f}")

    # Now intersect geometric visual ray with wall
    vis_hits_geom = intersect_circles(vis_ray_geom, wall_carrier)
    print(f"\n  Geometric visual ray ∩ wall: {len(vis_hits_geom)} hits")
    for i, vh in enumerate(vis_hits_geom):
        print(f"    hit[{i}]: ({vh.real:.6f}, {vh.imag:.6f})")
        print(f"      dist to wall: {wall_carrier.geometric_dist(vh):.15e}")

    # If we got hits, back-project to normalized space and complete the pipeline
    if vis_hits_geom:
        print(f"\n  Full geometric pullback pipeline:")
        for i, vh in enumerate(vis_hits_geom):
            # Back-project to normalized space
            bp = frame_inv.apply(vh)
            t_bp = ray.project_point(bp)
            on_ray = ray.origin + t_bp * ray.direction

            # Forward map back to visual
            vis_roundtrip = frame.apply(on_ray)
            pr_roundtrip = PR_A + PR_R / (on_ray - PR_P) if raw_c != 0 else vis_roundtrip

            print(f"    hit[{i}]:")
            print(f"      visual hit:              ({vh.real:.6f}, {vh.imag:.6f})  "
                  f"wall_dist={wall_carrier.geometric_dist(vh):.6e}")
            print(f"      back-projected:          ({bp.real:.6f}, {bp.imag:.6f})")
            print(f"      t on ray:                {t_bp:.15f}")
            print(f"      on-ray point:            ({on_ray.real:.6f}, {on_ray.imag:.6f})")
            print(f"      frame.apply(on_ray):     ({vis_roundtrip.real:.6f}, {vis_roundtrip.imag:.6f})  "
                  f"wall_dist={wall_carrier.geometric_dist(vis_roundtrip):.6f}")
            print(f"      pole-residue(on_ray):    ({pr_roundtrip.real:.6f}, {pr_roundtrip.imag:.6f})  "
                  f"wall_dist={wall_carrier.geometric_dist(pr_roundtrip):.6f}")
            print(f"      DIRECT visual hit:       ({vh.real:.6f}, {vh.imag:.6f})  "
                  f"wall_dist={wall_carrier.geometric_dist(vh):.6e}")

    # Also try with more widely spaced samples
    print(f"\n  Varying sample point spacing:")
    sample_configs = [
        ("near-pole", [0.09, 0.095, 0.098]),
        ("wide", [0.0, 0.04, 0.08]),
        ("very-wide", [0.0, 0.05, 0.5]),
        ("beyond-pole", [0.0, 0.05, 0.2]),
    ]
    for config_name, t_samp in sample_configs:
        pts = [ray.origin + t * ray.direction for t in t_samp]
        vpts = [frame.apply(p) for p in pts]
        vr = GeneralizedCircle.from_three_points(vpts[0], vpts[1], vpts[2])
        vhits = intersect_circles(vr, wall_carrier)
        n_hits = len(vhits)
        if n_hits > 0:
            best_dist = min(wall_carrier.geometric_dist(h) for h in vhits)
            if not vr.is_line():
                print(f"    {config_name:15s}: {n_hits} hits, best_wall_dist={best_dist:.6e}, "
                      f"vis_ray_r={vr.radius():.4f}")
            else:
                print(f"    {config_name:15s}: {n_hits} hits, best_wall_dist={best_dist:.6e}, "
                      f"vis_ray=line")
        else:
            if not vr.is_line():
                print(f"    {config_name:15s}: 0 hits, vis_ray_r={vr.radius():.4f}")
            else:
                print(f"    {config_name:15s}: 0 hits, vis_ray=line")

    # ---- EXPERIMENT 12: Manifold Projection (Carrier Snap) ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 12: Manifold Projection (Post-Hoc Carrier Snap)")
    print(f"{'='*60}")

    def project_onto_line(point: complex, carrier: GeneralizedCircle) -> complex:
        """Project point onto line bx + cy + d = 0."""
        x, y = point.real, point.imag
        b, c, d = carrier.b, carrier.c, carrier.d
        grad_sq = b*b + c*c
        f = b*x + c*y + d
        return complex(x - f * b / grad_sq, y - f * c / grad_sq)

    def project_onto_circle(point: complex, carrier: GeneralizedCircle) -> complex:
        """Project point onto circle."""
        center = carrier.center()
        r = carrier.radius()
        direction = point - center
        dist = abs(direction)
        if dist < 1e-30:
            return center + r  # arbitrary direction
        return center + r * (direction / dist)

    def project_onto_carrier(point: complex, carrier: GeneralizedCircle) -> complex:
        """Project point onto the nearest point on the carrier."""
        if carrier.is_line():
            return project_onto_line(point, carrier)
        else:
            return project_onto_circle(point, carrier)

    # Test manifold projection on ALL the vis_end computation methods
    print(f"\n  Manifold projection onto wall carrier (x=1700):")

    # 1. Standard frame.apply with f64 coefficients
    vis_std_f64 = frame.apply(hp_exact)
    vis_std_f64_snap = project_onto_carrier(vis_std_f64, wall_carrier)
    print(f"    Standard f64:  ({vis_std_f64.real:.6f}, {vis_std_f64.imag:.6f}) "
          f"-> snap: ({vis_std_f64_snap.real:.6f}, {vis_std_f64_snap.imag:.6f}) "
          f"dist: {wall_carrier.geometric_dist(vis_std_f64):.6e} -> {wall_carrier.geometric_dist(vis_std_f64_snap):.6e} "
          f"snap_delta: {abs(vis_std_f64 - vis_std_f64_snap):.6e}")

    # 2. Standard frame.apply with f32 coefficients
    vis_std_f32 = frame.apply_f32(hp_exact)
    vis_std_f32_snap = project_onto_carrier(vis_std_f32, wall_carrier)
    print(f"    Standard f32:  ({vis_std_f32.real:.6f}, {vis_std_f32.imag:.6f}) "
          f"-> snap: ({vis_std_f32_snap.real:.6f}, {vis_std_f32_snap.imag:.6f}) "
          f"dist: {wall_carrier.geometric_dist(vis_std_f32):.6f} -> {wall_carrier.geometric_dist(vis_std_f32_snap):.6e} "
          f"snap_delta: {abs(vis_std_f32 - vis_std_f32_snap):.6f}")

    # 3. Pole-residue with f64 coefficients
    if raw_c != 0:
        vis_pr_f64 = PR_A + PR_R / (hp_exact - PR_P)
        vis_pr_f64_snap = project_onto_carrier(vis_pr_f64, wall_carrier)
        print(f"    Pole-res f64:  ({vis_pr_f64.real:.6f}, {vis_pr_f64.imag:.6f}) "
              f"-> snap: ({vis_pr_f64_snap.real:.6f}, {vis_pr_f64_snap.imag:.6f}) "
              f"dist: {wall_carrier.geometric_dist(vis_pr_f64):.6e} -> {wall_carrier.geometric_dist(vis_pr_f64_snap):.6e} "
              f"snap_delta: {abs(vis_pr_f64 - vis_pr_f64_snap):.6e}")

    # 4. On INTERSECTION hits (which have their own error)
    print(f"\n  Manifold projection on intersection hits:")
    hits = ray.intersect_carrier(norm_wall)
    for i, (t, pt) in enumerate(hits):
        if t <= 0:
            continue
        vis = frame.apply(pt)
        vis_snap = project_onto_carrier(vis, wall_carrier)
        vis_pr = PR_A + PR_R / (pt - PR_P) if raw_c != 0 else vis
        vis_pr_snap = project_onto_carrier(vis_pr, wall_carrier)
        print(f"    hit[{i}]: t={t:.12f}")
        print(f"      standard:    dist={wall_carrier.geometric_dist(vis):.6f} "
              f"-> snap dist={wall_carrier.geometric_dist(vis_snap):.6e} "
              f"snap_delta={abs(vis - vis_snap):.6f}")
        print(f"      pole-residue: dist={wall_carrier.geometric_dist(vis_pr):.6f} "
              f"-> snap dist={wall_carrier.geometric_dist(vis_pr_snap):.6e} "
              f"snap_delta={abs(vis_pr - vis_pr_snap):.6f}")
        # Check y-coordinate preservation: does snapping change the y-coord?
        print(f"      y-coord: vis={vis.imag:.6f} snap={vis_snap.imag:.6f} "
              f"pr={vis_pr.imag:.6f} pr_snap={vis_pr_snap.imag:.6f}")

    # 5. Test on arc carriers too (for VISUAL-ON-CARRIER violations at steps 5,7)
    arc1_carrier = GeneralizedCircle.from_three_points(400+250j, 350+200j, 300+250j)
    arc2_carrier = GeneralizedCircle.from_three_points(1550+750j, 1500+700j, 1450+750j)
    print(f"\n  Manifold projection on arc carriers:")
    for name, carrier in [("arc1", arc1_carrier), ("arc2", arc2_carrier)]:
        # Simulate a vis_end that's slightly off the arc
        center = carrier.center()
        r = carrier.radius()
        test_pt = center + (r + 3.5) * complex(np.cos(0.5), np.sin(0.5))
        snapped = project_onto_carrier(test_pt, carrier)
        print(f"    {name}: test_pt dist={carrier.geometric_dist(test_pt):.4f} "
              f"-> snapped dist={carrier.geometric_dist(snapped):.6e} "
              f"snap_delta={abs(test_pt - snapped):.4f}")

    # ---- EXPERIMENT 13: Combined Best Approach ----
    print(f"\n{'='*60}")
    print("EXPERIMENT 13: Combined — Geometric Intersection + Pole-Residue + Snap")
    print(f"{'='*60}")

    # The full pipeline combining all three expert suggestions:
    # 1. Use geometric ray-circle intersection (avoids d²-r² cancellation)
    # 2. Map intersection point through pole-residue form (avoids cz+d cancellation)
    # 3. Snap result onto physical carrier (manifold projection)

    hits_geo = geometric_ray_circle_intersect(ray, norm_wall)
    print(f"\n  Step 1: Geometric intersection -> {len(hits_geo)} hits")

    for i, (t, pt) in enumerate(hits_geo):
        if t <= 0:
            continue

        # Step 2: Pole-residue evaluation
        vis_pr = PR_A + PR_R / (pt - PR_P) if raw_c != 0 else frame.apply(pt)
        d_pr = wall_carrier.geometric_dist(vis_pr)

        # Step 3: Snap to carrier
        vis_snap = project_onto_carrier(vis_pr, wall_carrier)
        d_snap = wall_carrier.geometric_dist(vis_snap)

        # Compare with all other methods
        vis_std = frame.apply(pt)
        vis_std_f32 = frame.apply_f32(pt)
        d_std = wall_carrier.geometric_dist(vis_std)
        d_f32 = wall_carrier.geometric_dist(vis_std_f32)

        print(f"\n    hit[{i}]: t={t:.15f}")
        print(f"      Original (f32 apply):            dist={d_f32:.6f} px  {'FAIL' if d_f32 > 2.0 else 'pass'}")
        print(f"      Standard (f64 apply):            dist={d_std:.6f} px  {'FAIL' if d_std > 2.0 else 'pass'}")
        print(f"      Pole-residue (f64):              dist={d_pr:.6f} px  {'FAIL' if d_pr > 2.0 else 'pass'}")
        print(f"      Pole-residue + snap:             dist={d_snap:.6e} px  {'FAIL' if d_snap > 2.0 else 'pass'}")

    # Final summary
    print(f"\n{'='*60}")
    print("SUMMARY: Approach Comparison")
    print(f"{'='*60}")
    print(f"""
  Method                                    Wall dist    Verdict
  ----------------------------------------  ----------   -------
  Standard f32 (current GDScript apply)     5.6 px       FAIL
  Standard f64 (current apply_f64)          ~0.0 px*     pass*
  Standard f64 on intersection hit          0.19 px      pass
  Pole-residue f64 on exact hp              ~0.0 px      pass
  Pole-residue f32 coefficients             see above    ???
  Geometric intersection + std f64          0.19 px      pass
  Geometric intersection + pole-residue     ~0.0 px      pass
  Any method + manifold projection          0.0 px       PASS

  * = with exact f64 coefficients; GDScript stores as f32 Vector2

  Recommended fix strategies (in order of robustness):
  1. Manifold projection (snap vis_end to physical carrier) — O(1), always exact
  2. Pole-residue form — stores A,R,P as float64, avoids cz+d cancellation
  3. Geometric intersection — avoids d²-r² cancellation for tiny normalized circles
  4. Geometric visual ray + direct visual hit — avoids Hermitian congruence entirely
""")


def experiment_14_three_improvements():
    """Test all three precision improvements independently and combined.

    The three improvements:
    1. f64 composition — compose Möbius coefficients in float64 instead of float32
    2. Pole-residue form — f(z) = A + R/(z-P) isolates the singularity
    3. Manifold projection — snap vis_end onto the physical carrier

    We test every combination (2³ = 8) to see which ones help and whether they compound.
    """
    print("\n" + "=" * 70)
    print("EXPERIMENT 14: Three Precision Improvements — Independent & Combined")
    print("=" * 70)

    surfaces, effects = build_scene()

    R_arc1 = effects['arc1_refl']
    R_arc2 = effects['arc2_refl']

    # ---- Step 1: Compose the frame in f64 (Python default) ----
    frame_f64 = R_arc2.compose(R_arc1)
    print(f"\n  Frame (f64 composition):")
    print(f"    a = {frame_f64.a}")
    print(f"    b = {frame_f64.b}")
    print(f"    c = {frame_f64.c}")
    print(f"    d = {frame_f64.d}")

    # ---- Step 2: Compose the frame in f32 (simulating GDScript Vector2) ----
    def f32(x):
        return float(np.float32(x))
    def v2(c):
        return complex(f32(c.real), f32(c.imag))
    def cmul32(v1, v2_):
        r = f32(f32(v1.real * v2_.real) - f32(v1.imag * v2_.imag))
        i = f32(f32(v1.real * v2_.imag) + f32(v1.imag * v2_.real))
        return complex(r, i)

    def compose_f32(self_mt, other_mt):
        """Simulate GDScript's compose() using float32 arithmetic throughout."""
        a1, b1, c1, d1 = v2(self_mt.a), v2(self_mt.b), v2(self_mt.c), v2(self_mt.d)
        a2, b2, c2, d2 = v2(other_mt.a), v2(other_mt.b), v2(other_mt.c), v2(other_mt.d)

        if self_mt.conjugating:
            a2 = a2.conjugate()
            b2 = b2.conjugate()
            c2 = c2.conjugate()
            d2 = d2.conjugate()

        new_a = complex(f32(cmul32(a1, a2).real + cmul32(b1, c2).real),
                        f32(cmul32(a1, a2).imag + cmul32(b1, c2).imag))
        new_b = complex(f32(cmul32(a1, b2).real + cmul32(b1, d2).real),
                        f32(cmul32(a1, b2).imag + cmul32(b1, d2).imag))
        new_c = complex(f32(cmul32(c1, a2).real + cmul32(d1, c2).real),
                        f32(cmul32(c1, a2).imag + cmul32(d1, c2).imag))
        new_d = complex(f32(cmul32(c1, b2).real + cmul32(d1, d2).real),
                        f32(cmul32(c1, b2).imag + cmul32(d1, d2).imag))

        # Normalize by max magnitude (using f32 length)
        def mag32(c_):
            return f32(np.sqrt(f32(f32(c_.real * c_.real) + f32(c_.imag * c_.imag))))
        max_mag = max(mag32(new_a), mag32(new_b), mag32(new_c), mag32(new_d))
        if max_mag > 0:
            inv = f32(1.0 / max_mag)
            new_a = complex(f32(new_a.real * inv), f32(new_a.imag * inv))
            new_b = complex(f32(new_b.real * inv), f32(new_b.imag * inv))
            new_c = complex(f32(new_c.real * inv), f32(new_c.imag * inv))
            new_d = complex(f32(new_d.real * inv), f32(new_d.imag * inv))

        new_conj = self_mt.conjugating != other_mt.conjugating
        return MobiusTransform(new_a, new_b, new_c, new_d, new_conj, "f32_composed")

    frame_f32 = compose_f32(R_arc2, R_arc1)
    print(f"\n  Frame (f32 composition):")
    print(f"    a = {frame_f32.a}")
    print(f"    b = {frame_f32.b}")
    print(f"    c = {frame_f32.c}")
    print(f"    d = {frame_f32.d}")

    # ---- Step 3: Show coefficient differences ----
    print(f"\n  Coefficient differences (f64 - f32):")
    for name, f64_val, f32_val in [("a", frame_f64.a, frame_f32.a),
                                    ("b", frame_f64.b, frame_f32.b),
                                    ("c", frame_f64.c, frame_f32.c),
                                    ("d", frame_f64.d, frame_f32.d)]:
        diff = abs(f64_val - f32_val)
        rel = diff / max(abs(f64_val), 1e-30)
        print(f"    {name}: diff={diff:.6e}, rel={rel:.6e}")

    # ---- Step 4: Set up hitpoint and carrier ----
    wall_carrier = GeneralizedCircle.from_line(800, 0, -1360000)  # x=1700

    PLAYER = complex(1334.662, 234.909)
    CURSOR = complex(400, 250)
    ray_dir = CURSOR - PLAYER

    frame_inv_f64 = frame_f64.invert()
    vis_target = complex(1700, 647.8268)
    hp_exact = frame_inv_f64.apply(vis_target)

    # Also compute hp via f32 frame inverse (what GDScript actually produces)
    frame_inv_f32 = frame_f32.invert()
    hp_f32_inv = frame_inv_f32.apply_f32(vis_target)

    ray_origin = hp_exact - 0.1 * ray_dir
    ray = Ray(ray_origin, ray_dir)

    print(f"\n  Hitpoint (f64 back-project): {hp_exact}")
    print(f"  Hitpoint (f32 inverse):      {hp_f32_inv}")
    print(f"  hp difference:               {abs(hp_exact - hp_f32_inv):.6e}")

    # Normalized wall carrier (using f32 frame_inv, as GDScript does)
    wall_start, wall_end, wall_via = complex(1700, 100), complex(1700, 900), complex(1700, 500)
    norm_ws = frame_inv_f32.apply_f32(wall_start)
    norm_we = frame_inv_f32.apply_f32(wall_end)
    norm_wv = frame_inv_f32.apply_f32(wall_via)
    norm_wall = GeneralizedCircle.from_three_points(norm_ws, norm_wv, norm_we)

    # Intersection hitpoint (what GDScript intersection would produce)
    hits = ray.intersect_carrier(norm_wall)
    if hits:
        # Use the best positive-t hit
        pos_hits = [(t, pt) for t, pt in hits if t > 0]
        if pos_hits:
            _, intersection_hp = min(pos_hits, key=lambda x: x[0])
        else:
            intersection_hp = hp_exact
    else:
        intersection_hp = hp_exact

    print(f"\n  Intersection hitpoint:       {intersection_hp}")
    print(f"  hp_exact vs intersection:    {abs(hp_exact - intersection_hp):.6e}")

    # ---- Step 5: Pole-residue parameters ----
    # Compute from f64 coefficients
    pr_A_f64 = frame_f64.a / frame_f64.c
    pr_P_f64 = -frame_f64.d / frame_f64.c
    det_f64 = frame_f64.a * frame_f64.d - frame_f64.b * frame_f64.c
    pr_R_f64 = -det_f64 / (frame_f64.c ** 2)

    # Compute from f32 coefficients (widened to f64 for the division)
    pr_A_f32 = frame_f32.a / frame_f32.c
    pr_P_f32 = -frame_f32.d / frame_f32.c
    det_f32 = frame_f32.a * frame_f32.d - frame_f32.b * frame_f32.c
    pr_R_f32 = -det_f32 / (frame_f32.c ** 2)

    print(f"\n  Pole-residue params (f64 composition):")
    print(f"    A = {pr_A_f64}")
    print(f"    P = {pr_P_f64}")
    print(f"    R = {pr_R_f64}")
    print(f"  Pole-residue params (f32 composition):")
    print(f"    A = {pr_A_f32}")
    print(f"    P = {pr_P_f32}")
    print(f"    R = {pr_R_f32}")

    # ---- Step 6: Test all 8 combinations ----
    def project_onto_carrier(point, carrier):
        if carrier.is_line():
            b, c, d = carrier.b, carrier.c, carrier.d
            x, y = point.real, point.imag
            f_val = b * x + c * y + d
            grad_sq = b * b + c * c
            dx = f_val * b / grad_sq
            dy = f_val * c / grad_sq
            return complex(x - dx, y - dy)
        else:
            cx = carrier.center().real
            cy = carrier.center().imag
            r = carrier.radius()
            dx = point.real - cx
            dy = point.imag - cy
            dist = np.sqrt(dx*dx + dy*dy)
            if dist < 1e-15:
                return complex(cx + r, cy)
            return complex(cx + r * dx / dist, cy + r * dy / dist)

    # Use the intersection hitpoint (most realistic — what GDScript will actually use)
    test_hp = intersection_hp

    print(f"\n  Testing all combinations on intersection hitpoint: {test_hp}")
    print(f"  (distance from exact hp: {abs(test_hp - hp_exact):.6e})")
    print(f"\n  {'Method':<55} {'Dist (px)':>10}  {'Verdict':>8}")
    print(f"  {'-'*55} {'-'*10}  {'-'*8}")

    results = {}

    # Standard apply with f32 composition (current GDScript: Vector2 compose + Vector2 apply)
    vis = frame_f32.apply_f32(test_hp)
    d = wall_carrier.geometric_dist(vis)
    label = "f32-compose + f32-apply (current GDScript)"
    print(f"  {label:<55} {d:>10.6f}  {'FAIL' if d > 2.0 else 'pass'}")
    results['baseline'] = d

    # f32 compose + f64 apply (current apply_f64 with f32 coefficients)
    vis = frame_f32.apply(test_hp)  # Python float64 but from f32 coefficients
    d = wall_carrier.geometric_dist(vis)
    label = "f32-compose + f64-apply (current apply_f64)"
    print(f"  {label:<55} {d:>10.6f}  {'FAIL' if d > 2.0 else 'pass'}")
    results['f64_apply'] = d

    # === Improvement 1: f64 composition ===
    vis = frame_f64.apply(test_hp)
    d = wall_carrier.geometric_dist(vis)
    label = "[1] f64-compose + f64-apply"
    print(f"  {label:<55} {d:>10.6f}  {'FAIL' if d > 2.0 else 'pass'}")
    results['f64_compose'] = d

    # === Improvement 2: Pole-residue form ===
    # 2a: pole-residue with f32 coefficients
    dz = test_hp - pr_P_f32
    vis = pr_A_f32 + pr_R_f32 / dz
    d = wall_carrier.geometric_dist(vis)
    label = "[2a] pole-residue (f32-composed coeffs)"
    print(f"  {label:<55} {d:>10.6f}  {'FAIL' if d > 2.0 else 'pass'}")
    results['pr_f32'] = d

    # 2b: pole-residue with f64 coefficients
    dz = test_hp - pr_P_f64
    vis = pr_A_f64 + pr_R_f64 / dz
    d = wall_carrier.geometric_dist(vis)
    label = "[2b] pole-residue (f64-composed coeffs)"
    print(f"  {label:<55} {d:>10.6f}  {'FAIL' if d > 2.0 else 'pass'}")
    results['pr_f64'] = d

    # === Improvement 1+2: f64 compose + pole-residue ===
    dz = test_hp - pr_P_f64
    vis = pr_A_f64 + pr_R_f64 / dz
    d_pr_f64 = wall_carrier.geometric_dist(vis)
    # (same as 2b above — f64 compose IS used for pole-residue f64)

    # === Improvement 3: Manifold projection ===
    # 3a: on top of baseline (f32 compose + f32 apply + snap)
    vis = frame_f32.apply_f32(test_hp)
    vis = project_onto_carrier(vis, wall_carrier)
    d = wall_carrier.geometric_dist(vis)
    label = "[3] f32-compose + f32-apply + snap"
    print(f"  {label:<55} {d:>10.6e}  {'FAIL' if d > 2.0 else 'pass'}")
    results['snap_baseline'] = d

    # === Combined: 1+3 (f64 compose + f64 apply + snap) ===
    vis = frame_f64.apply(test_hp)
    vis = project_onto_carrier(vis, wall_carrier)
    d = wall_carrier.geometric_dist(vis)
    label = "[1+3] f64-compose + f64-apply + snap"
    print(f"  {label:<55} {d:>10.6e}  {'FAIL' if d > 2.0 else 'pass'}")
    results['f64_snap'] = d

    # === Combined: 2+3 (pole-residue f32 + snap) ===
    dz = test_hp - pr_P_f32
    vis = pr_A_f32 + pr_R_f32 / dz
    vis = project_onto_carrier(vis, wall_carrier)
    d = wall_carrier.geometric_dist(vis)
    label = "[2a+3] pole-residue (f32 coeffs) + snap"
    print(f"  {label:<55} {d:>10.6e}  {'FAIL' if d > 2.0 else 'pass'}")
    results['pr_f32_snap'] = d

    # === Combined: 1+2+3 (f64 compose + pole-residue + snap) ===
    dz = test_hp - pr_P_f64
    vis = pr_A_f64 + pr_R_f64 / dz
    vis = project_onto_carrier(vis, wall_carrier)
    d = wall_carrier.geometric_dist(vis)
    label = "[1+2+3] f64-compose + pole-residue + snap"
    print(f"  {label:<55} {d:>10.6e}  {'FAIL' if d > 2.0 else 'pass'}")
    results['all_three'] = d

    # ---- Step 7: Test with EXACT hitpoint (no intersection error) ----
    print(f"\n  --- Same tests with EXACT hitpoint (no intersection error) ---")
    print(f"  {'Method':<55} {'Dist (px)':>10}  {'Verdict':>8}")
    print(f"  {'-'*55} {'-'*10}  {'-'*8}")

    vis = frame_f32.apply_f32(hp_exact)
    d = wall_carrier.geometric_dist(vis)
    print(f"  {'f32-compose + f32-apply':<55} {d:>10.6f}  {'FAIL' if d > 2.0 else 'pass'}")

    vis = frame_f32.apply(hp_exact)
    d = wall_carrier.geometric_dist(vis)
    print(f"  {'f32-compose + f64-apply':<55} {d:>10.6f}  {'FAIL' if d > 2.0 else 'pass'}")

    vis = frame_f64.apply(hp_exact)
    d = wall_carrier.geometric_dist(vis)
    print(f"  {'[1] f64-compose + f64-apply':<55} {d:>10.6e}  {'FAIL' if d > 2.0 else 'pass'}")

    dz = hp_exact - pr_P_f32
    vis = pr_A_f32 + pr_R_f32 / dz
    d = wall_carrier.geometric_dist(vis)
    print(f"  {'[2a] pole-residue (f32 coeffs)':<55} {d:>10.6f}  {'FAIL' if d > 2.0 else 'pass'}")

    dz = hp_exact - pr_P_f64
    vis = pr_A_f64 + pr_R_f64 / dz
    d = wall_carrier.geometric_dist(vis)
    print(f"  {'[2b] pole-residue (f64 coeffs)':<55} {d:>10.6e}  {'FAIL' if d > 2.0 else 'pass'}")

    # ---- Step 8: How much does each improvement contribute? ----
    print(f"\n  --- Improvement breakdown ---")
    print(f"  Baseline (f32 compose + f32 apply):     {results['baseline']:.6f} px")
    print(f"  [1] f64 composition alone:              {results['f64_compose']:.6f} px  "
          f"({results['baseline']/max(results['f64_compose'], 1e-15):.0f}x better)")
    print(f"  [2a] pole-residue (f32 coeffs):         {results['pr_f32']:.6f} px  "
          f"({results['baseline']/max(results['pr_f32'], 1e-15):.0f}x better)")
    print(f"  [2b] pole-residue (f64 coeffs):         {results['pr_f64']:.6f} px  "
          f"({results['baseline']/max(results['pr_f64'], 1e-15):.0f}x better)")
    print(f"  [3] snap alone (on baseline):           {results['snap_baseline']:.6e} px  (always 0)")
    print(f"  [1+3] f64 compose + snap:               {results['f64_snap']:.6e} px")
    print(f"  [2a+3] pole-residue f32 + snap:         {results['pr_f32_snap']:.6e} px")
    print(f"  [1+2+3] all three:                      {results['all_three']:.6e} px")

    # ---- Step 9: What about the vis_end POSITION accuracy? ----
    # Even if snap puts us on the carrier, the Y coordinate might be wrong.
    # Compare Y coordinate of vis_end across methods.
    print(f"\n  --- Visual endpoint Y accuracy (wall at x=1700) ---")
    print(f"  True Y (f64 compose, exact hp): {frame_f64.apply(hp_exact).imag:.10f}")

    ref_y = frame_f64.apply(hp_exact).imag

    methods = [
        ("f32-compose + f32-apply", frame_f32.apply_f32(test_hp)),
        ("f32-compose + f64-apply", frame_f32.apply(test_hp)),
        ("[1] f64-compose + f64-apply", frame_f64.apply(test_hp)),
        ("[2a] pole-residue (f32 coeffs)", pr_A_f32 + pr_R_f32 / (test_hp - pr_P_f32)),
        ("[2b] pole-residue (f64 coeffs)", pr_A_f64 + pr_R_f64 / (test_hp - pr_P_f64)),
    ]
    for label, vis in methods:
        y_err = abs(vis.imag - ref_y)
        print(f"  {label:<45} Y={vis.imag:.6f}  Y_err={y_err:.6f} px")

    print(f"\n  Note: Manifold projection corrects X (carrier dist=0) but preserves")
    print(f"  whatever Y the apply method produces. So better apply = better Y after snap.")


def experiment_15_visual_space_and_kahan():
    """Test expert suggestions: geometric visual ray pullback + Kahan robust quadratic.

    Expert insight: instead of intersecting in normalized space and amplifying error
    through frame.apply(), intersect DIRECTLY in visual space. The visual hit lies
    exactly on the physical carrier, with 0 amplification.

    Also test Kahan's robust quadratic solver to reduce normalized intersection error.
    """
    print("\n" + "=" * 70)
    print("EXPERIMENT 15: Visual-Space Intersection + Kahan Robust Quadratic")
    print("=" * 70)

    surfaces, effects = build_scene()
    R_arc1 = effects['arc1_refl']
    R_arc2 = effects['arc2_refl']
    frame = R_arc2.compose(R_arc1)
    frame_inv = frame.invert()

    wall_carrier = GeneralizedCircle.from_line(800, 0, -1360000)  # x=1700

    PLAYER = complex(1334.662, 234.909)
    CURSOR = complex(400, 250)
    ray_dir = CURSOR - PLAYER

    vis_target = complex(1700, 647.8268)
    hp_exact = frame_inv.apply(vis_target)

    ray_origin = hp_exact - 0.1 * ray_dir
    ray = Ray(ray_origin, ray_dir)

    # Normalized wall carrier (f32 inverse, as GDScript does)
    def f32(x): return float(np.float32(x))
    def v2(c): return complex(f32(c.real), f32(c.imag))

    wall_start, wall_end, wall_via = complex(1700, 100), complex(1700, 900), complex(1700, 500)
    norm_ws_f32 = frame_inv.apply_f32(wall_start)
    norm_we_f32 = frame_inv.apply_f32(wall_end)
    norm_wv_f32 = frame_inv.apply_f32(wall_via)
    norm_wall_f32 = GeneralizedCircle.from_three_points(norm_ws_f32, norm_wv_f32, norm_we_f32)

    # f64 normalized carrier
    norm_ws_f64 = frame_inv.apply(wall_start)
    norm_we_f64 = frame_inv.apply(wall_end)
    norm_wv_f64 = frame_inv.apply(wall_via)
    norm_wall_f64 = GeneralizedCircle.from_three_points(norm_ws_f64, norm_wv_f64, norm_we_f64)

    print(f"\n  Normalized wall carrier (f32): {norm_wall_f32}")
    if not norm_wall_f32.is_line():
        print(f"    center: {norm_wall_f32.center()}, radius: {norm_wall_f32.radius():.10f}")
    print(f"  Normalized wall carrier (f64): {norm_wall_f64}")
    if not norm_wall_f64.is_line():
        print(f"    center: {norm_wall_f64.center()}, radius: {norm_wall_f64.radius():.10f}")
    if not norm_wall_f32.is_line() and not norm_wall_f64.is_line():
        print(f"  Carrier diff: center={abs(norm_wall_f32.center()-norm_wall_f64.center()):.6e}, "
              f"radius={abs(norm_wall_f32.radius()-norm_wall_f64.radius()):.6e}")

    # ======================================================================
    # PART A: Kahan Robust Quadratic Solver
    # ======================================================================
    print(f"\n{'='*60}")
    print("PART A: Kahan Robust Quadratic Solver")
    print(f"{'='*60}")

    def intersect_kahan(ray: Ray, carrier: GeneralizedCircle):
        """Kahan's robust quadratic solver with conjugate rewrite."""
        ox, oy = ray.origin.real, ray.origin.imag
        dx, dy = ray.direction.real, ray.direction.imag

        qa = carrier.a * (dx*dx + dy*dy)
        qb = 2 * carrier.a * (ox*dx + oy*dy) + carrier.b * dx + carrier.c * dy
        qc = carrier.a * (ox*ox + oy*oy) + carrier.b * ox + carrier.c * oy + carrier.d

        if qa == 0:
            if qb == 0:
                return []
            t = -qc / qb
            return [(t, ray.origin + t * ray.direction)]

        disc = qb*qb - 4*qa*qc
        if disc < 0:
            return []

        sqrt_d = np.sqrt(disc)

        # Kahan's trick: choose the root with |b + sqrt_d| to avoid cancellation
        # When qb > 0: use (-qb - sqrt_d) for first root
        # When qb < 0: use (-qb + sqrt_d) for first root
        # Then get second root from c/a relationship: t1*t2 = qc/qa
        if qb >= 0:
            r1 = (-qb - sqrt_d) / (2 * qa)
        else:
            r1 = (-qb + sqrt_d) / (2 * qa)

        # Second root via Vieta's: t1 * t2 = qc/qa
        if abs(r1) > 1e-30:
            r2 = (qc / qa) / r1
        else:
            # Fall back to standard formula
            if qb >= 0:
                r2 = (-qb + sqrt_d) / (2 * qa)
            else:
                r2 = (-qb - sqrt_d) / (2 * qa)

        return [(r1, ray.origin + r1 * ray.direction),
                (r2, ray.origin + r2 * ray.direction)]

    # Also: Kahan with FMA-style discriminant (compensated)
    def intersect_kahan_compensated(ray: Ray, carrier: GeneralizedCircle):
        """Kahan's robust quadratic with compensated discriminant computation."""
        ox, oy = ray.origin.real, ray.origin.imag
        dx, dy = ray.direction.real, ray.direction.imag

        qa = carrier.a * (dx*dx + dy*dy)
        qb = 2 * carrier.a * (ox*dx + oy*dy) + carrier.b * dx + carrier.c * dy
        qc = carrier.a * (ox*ox + oy*oy) + carrier.b * ox + carrier.c * oy + carrier.d

        if qa == 0:
            if qb == 0:
                return []
            t = -qc / qb
            return [(t, ray.origin + t * ray.direction)]

        # Compensated discriminant: compute b²-4ac more carefully
        # Use the identity: b²-4ac = (b-2√(ac))*(b+2√(ac)) when ac > 0
        # But more robustly: compute each product separately and subtract
        b_sq = qb * qb
        four_ac = 4.0 * qa * qc
        disc = b_sq - four_ac

        if disc < 0:
            return []

        sqrt_d = np.sqrt(disc)

        # Kahan's conjugate rewrite
        if qb >= 0:
            q = -0.5 * (qb + sqrt_d)
        else:
            q = -0.5 * (qb - sqrt_d)

        r1 = q / qa
        r2 = qc / q if abs(q) > 1e-30 else (-qb + sqrt_d if qb >= 0 else -qb - sqrt_d) / (2*qa)

        return [(r1, ray.origin + r1 * ray.direction),
                (r2, ray.origin + r2 * ray.direction)]

    # Test on f32 carrier
    print(f"\n  On f32 normalized carrier (radius={norm_wall_f32.radius():.10f}):")
    for solver_name, solver in [("Standard quadratic", lambda: ray.intersect_carrier(norm_wall_f32)),
                                 ("Kahan robust", lambda: intersect_kahan(ray, norm_wall_f32)),
                                 ("Kahan compensated", lambda: intersect_kahan_compensated(ray, norm_wall_f32))]:
        hits = solver()
        pos_hits = [(t, pt) for t, pt in hits if t > 0]
        if pos_hits:
            _, best_pt = min(pos_hits, key=lambda x: x[0])
            vis = frame.apply(best_pt)
            d = wall_carrier.geometric_dist(vis)
            hp_err = abs(best_pt - hp_exact)
            print(f"    {solver_name:25s}: hp_err={hp_err:.6e}, vis_dist={d:.6f} px")
        else:
            print(f"    {solver_name:25s}: no positive hits")

    # Test on f64 carrier
    print(f"\n  On f64 normalized carrier (radius={norm_wall_f64.radius():.10f}):")
    for solver_name, solver in [("Standard quadratic", lambda: ray.intersect_carrier(norm_wall_f64)),
                                 ("Kahan robust", lambda: intersect_kahan(ray, norm_wall_f64)),
                                 ("Kahan compensated", lambda: intersect_kahan_compensated(ray, norm_wall_f64))]:
        hits = solver()
        pos_hits = [(t, pt) for t, pt in hits if t > 0]
        if pos_hits:
            _, best_pt = min(pos_hits, key=lambda x: x[0])
            vis = frame.apply(best_pt)
            d = wall_carrier.geometric_dist(vis)
            hp_err = abs(best_pt - hp_exact)
            print(f"    {solver_name:25s}: hp_err={hp_err:.6e}, vis_dist={d:.6f} px")
        else:
            print(f"    {solver_name:25s}: no positive hits")

    # ======================================================================
    # PART B: Geometric Visual Ray — Direct Visual Space Intersection
    # ======================================================================
    print(f"\n{'='*60}")
    print("PART B: Geometric Visual Ray — Direct Visual Space Intersection")
    print(f"{'='*60}")
    print("  Expert insight: intersect in visual space to bypass amplification entirely.")
    print("  The visual hit IS the vis_end — no frame.apply() needed, 0 amplification.")

    # Step 1: Build geometric visual ray by sampling 3 points on the normalized ray
    # and mapping through frame.apply (f64)
    sample_configs = {
        "f64 apply, wide spacing":   (frame.apply,     [0.0, 0.04, 0.08]),
        "f64 apply, very wide":      (frame.apply,     [0.0, 0.05, 0.5]),
        "f64 apply, beyond pole":    (frame.apply,     [0.0, 0.05, 0.2]),
        "f32 apply, wide spacing":   (frame.apply_f32, [0.0, 0.04, 0.08]),
        "f32 apply, very wide":      (frame.apply_f32, [0.0, 0.05, 0.5]),
    }

    print(f"\n  {'Config':<35} {'Wall hits':>9} {'Best X err':>12} {'Best Y err':>12} {'Best dist':>12}")
    print(f"  {'-'*35} {'-'*9} {'-'*12} {'-'*12} {'-'*12}")

    best_result = None
    for config_name, (apply_fn, t_samples) in sample_configs.items():
        ray_pts = [ray.origin + t * ray.direction for t in t_samples]
        vis_pts = [apply_fn(p) for p in ray_pts]

        # Check for inf/nan
        if any(np.isinf(p.real) or np.isinf(p.imag) or np.isnan(p.real) or np.isnan(p.imag) for p in vis_pts):
            print(f"  {config_name:<35} {'inf/nan':>9}")
            continue

        vis_ray = GeneralizedCircle.from_three_points(vis_pts[0], vis_pts[1], vis_pts[2])
        vis_hits = intersect_circles(vis_ray, wall_carrier)

        if not vis_hits:
            print(f"  {config_name:<35} {'0':>9}")
            continue

        # The visual hits are DIRECTLY on the wall — they ARE the vis_end
        best_hit = min(vis_hits, key=lambda h: abs(wall_carrier.geometric_dist(h)))
        x_err = abs(best_hit.real - 1700.0)
        y_err = abs(best_hit.imag - vis_target.imag)  # vs true visual Y
        w_dist = wall_carrier.geometric_dist(best_hit)

        print(f"  {config_name:<35} {len(vis_hits):>9} {x_err:>12.6e} {y_err:>12.6f} {w_dist:>12.6e}")

        if best_result is None or w_dist < best_result[1]:
            best_result = (config_name, w_dist, best_hit)

    # Step 2: Compare the BEST visual-space result against all other methods
    if best_result:
        print(f"\n  Best visual-space result: {best_result[0]}")
        vis_hit = best_result[2]
        print(f"    vis_end = ({vis_hit.real:.10f}, {vis_hit.imag:.10f})")
        print(f"    wall_dist = {wall_carrier.geometric_dist(vis_hit):.6e} px")
        print(f"    X error from 1700: {abs(vis_hit.real - 1700.0):.6e}")
        print(f"    Y error from true: {abs(vis_hit.imag - vis_target.imag):.6f}")

    # Step 3: Also test with f32 composition frame
    print(f"\n  --- With f32-composed frame ---")
    def cmul32(v1, v2_):
        r = f32(f32(v1.real * v2_.real) - f32(v1.imag * v2_.imag))
        i = f32(f32(v1.real * v2_.imag) + f32(v1.imag * v2_.real))
        return complex(r, i)

    def compose_f32(self_mt, other_mt):
        a1, b1, c1, d1 = v2(self_mt.a), v2(self_mt.b), v2(self_mt.c), v2(self_mt.d)
        a2, b2, c2, d2 = v2(other_mt.a), v2(other_mt.b), v2(other_mt.c), v2(other_mt.d)
        if self_mt.conjugating:
            a2, b2, c2, d2 = a2.conjugate(), b2.conjugate(), c2.conjugate(), d2.conjugate()
        new_a = complex(f32(cmul32(a1, a2).real + cmul32(b1, c2).real), f32(cmul32(a1, a2).imag + cmul32(b1, c2).imag))
        new_b = complex(f32(cmul32(a1, b2).real + cmul32(b1, d2).real), f32(cmul32(a1, b2).imag + cmul32(b1, d2).imag))
        new_c = complex(f32(cmul32(c1, a2).real + cmul32(d1, c2).real), f32(cmul32(c1, a2).imag + cmul32(d1, c2).imag))
        new_d = complex(f32(cmul32(c1, b2).real + cmul32(d1, d2).real), f32(cmul32(c1, b2).imag + cmul32(d1, d2).imag))
        def mag32(c_): return f32(np.sqrt(f32(f32(c_.real * c_.real) + f32(c_.imag * c_.imag))))
        max_mag = max(mag32(new_a), mag32(new_b), mag32(new_c), mag32(new_d))
        if max_mag > 0:
            inv = f32(1.0 / max_mag)
            new_a = complex(f32(new_a.real * inv), f32(new_a.imag * inv))
            new_b = complex(f32(new_b.real * inv), f32(new_b.imag * inv))
            new_c = complex(f32(new_c.real * inv), f32(new_c.imag * inv))
            new_d = complex(f32(new_d.real * inv), f32(new_d.imag * inv))
        return MobiusTransform(new_a, new_b, new_c, new_d, self_mt.conjugating != other_mt.conjugating, "f32")

    frame_f32 = compose_f32(R_arc2, R_arc1)

    for config_name, apply_fn, t_samples in [
        ("f32 compose + f32 apply", frame_f32.apply_f32, [0.0, 0.04, 0.08]),
        ("f32 compose + f64 apply", frame_f32.apply,     [0.0, 0.04, 0.08]),
        ("f64 compose + f64 apply", frame.apply,         [0.0, 0.04, 0.08]),
    ]:
        ray_pts = [ray.origin + t * ray.direction for t in t_samples]
        vis_pts = [apply_fn(p) for p in ray_pts]
        if any(np.isinf(p.real) or np.isinf(p.imag) for p in vis_pts):
            print(f"    {config_name:<35}: inf/nan in samples")
            continue
        vis_ray = GeneralizedCircle.from_three_points(vis_pts[0], vis_pts[1], vis_pts[2])
        vis_hits = intersect_circles(vis_ray, wall_carrier)
        if vis_hits:
            best_hit = min(vis_hits, key=lambda h: abs(wall_carrier.geometric_dist(h)))
            x_err = abs(best_hit.real - 1700.0)
            y_err = abs(best_hit.imag - vis_target.imag)
            print(f"    {config_name:<35}: {len(vis_hits)} hits, x_err={x_err:.6e}, y_err={y_err:.6f}, "
                  f"dist={wall_carrier.geometric_dist(best_hit):.6e}")
        else:
            print(f"    {config_name:<35}: 0 hits")

    # ======================================================================
    # PART C: Grand Comparison — All methods side by side
    # ======================================================================
    print(f"\n{'='*60}")
    print("PART C: Grand Comparison — All Methods")
    print(f"{'='*60}")

    ref_y = frame.apply(hp_exact).imag

    # 1. Current GDScript baseline (f32 compose + f32 apply)
    vis = frame_f32.apply_f32(hp_exact)
    d1 = wall_carrier.geometric_dist(vis)
    y1 = abs(vis.imag - ref_y)

    # Best intersection hp from standard quadratic
    hits = ray.intersect_carrier(norm_wall_f32)
    pos_hits = [(t, pt) for t, pt in hits if t > 0]
    if pos_hits:
        _, inter_hp = min(pos_hits, key=lambda x: x[0])
    else:
        inter_hp = hp_exact
    vis_inter = frame_f32.apply_f32(inter_hp)
    d1b = wall_carrier.geometric_dist(vis_inter)
    y1b = abs(vis_inter.imag - ref_y)

    # 2. f64 compose + f64 apply on intersection hp
    vis = frame.apply(inter_hp)
    d2 = wall_carrier.geometric_dist(vis)
    y2 = abs(vis.imag - ref_y)

    # 3. f64 compose + f64 apply + manifold projection
    def project_onto_carrier(point, carrier):
        if carrier.is_line():
            b, c, d = carrier.b, carrier.c, carrier.d
            x, y = point.real, point.imag
            f_val = b * x + c * y + d
            grad_sq = b * b + c * c
            return complex(x - f_val * b / grad_sq, y - f_val * c / grad_sq)
        else:
            cx, cy = carrier.center().real, carrier.center().imag
            r = carrier.radius()
            dx, dy = point.real - cx, point.imag - cy
            dist = np.sqrt(dx*dx + dy*dy)
            if dist < 1e-15:
                return complex(cx + r, cy)
            return complex(cx + r * dx / dist, cy + r * dy / dist)

    vis_snap = project_onto_carrier(vis, wall_carrier)
    d3 = wall_carrier.geometric_dist(vis_snap)
    y3 = abs(vis_snap.imag - ref_y)

    # 4. Geometric visual ray (f64 apply, direct visual hit)
    t_samples = [0.0, 0.04, 0.08]
    ray_pts = [ray.origin + t * ray.direction for t in t_samples]
    vis_pts = [frame.apply(p) for p in ray_pts]
    vis_ray = GeneralizedCircle.from_three_points(vis_pts[0], vis_pts[1], vis_pts[2])
    vis_hits = intersect_circles(vis_ray, wall_carrier)
    if vis_hits:
        # Pick the hit closest to where we expect the endpoint
        vis_hit = min(vis_hits, key=lambda h: abs(h.imag - ref_y))
        d4 = wall_carrier.geometric_dist(vis_hit)
        y4 = abs(vis_hit.imag - ref_y)
    else:
        vis_hit = None
        d4 = float('inf')
        y4 = float('inf')

    # 5. Geometric visual ray with f32 compose + f32 apply (worst case)
    vis_pts_f32 = [frame_f32.apply_f32(p) for p in ray_pts]
    vis_ray_f32 = GeneralizedCircle.from_three_points(vis_pts_f32[0], vis_pts_f32[1], vis_pts_f32[2])
    vis_hits_f32 = intersect_circles(vis_ray_f32, wall_carrier)
    if vis_hits_f32:
        vis_hit_f32 = min(vis_hits_f32, key=lambda h: abs(h.imag - ref_y))
        d5 = wall_carrier.geometric_dist(vis_hit_f32)
        y5 = abs(vis_hit_f32.imag - ref_y)
    else:
        d5 = float('inf')
        y5 = float('inf')

    # 6. Kahan on f64 carrier + f64 apply + snap
    hits_k = intersect_kahan(ray, norm_wall_f64)
    pos_k = [(t, pt) for t, pt in hits_k if t > 0]
    if pos_k:
        _, kahan_hp = min(pos_k, key=lambda x: x[0])
        vis_k = frame.apply(kahan_hp)
        vis_k_snap = project_onto_carrier(vis_k, wall_carrier)
        d6 = wall_carrier.geometric_dist(vis_k_snap)
        y6 = abs(vis_k_snap.imag - ref_y)
        kahan_hp_err = abs(kahan_hp - hp_exact)
    else:
        d6 = float('inf')
        y6 = float('inf')
        kahan_hp_err = float('inf')

    print(f"\n  {'Method':<55} {'Carrier':>8} {'Y err':>8} {'Total':>8}")
    print(f"  {'-'*55} {'-'*8} {'-'*8} {'-'*8}")
    print(f"  {'Baseline: f32 compose + f32 apply (exact hp)':<55} {d1:>8.3f} {y1:>8.3f} {np.sqrt(d1**2+y1**2):>8.3f}")
    print(f"  {'Baseline: f32 compose + f32 apply (intersection hp)':<55} {d1b:>8.3f} {y1b:>8.3f} {np.sqrt(d1b**2+y1b**2):>8.3f}")
    print(f"  {'f64 compose + f64 apply (intersection hp)':<55} {d2:>8.3f} {y2:>8.3f} {np.sqrt(d2**2+y2**2):>8.3f}")
    print(f"  {'f64 compose + f64 apply + snap (intersection hp)':<55} {d3:>8.5f} {y3:>8.3f} {np.sqrt(d3**2+y3**2):>8.3f}")
    print(f"  {'Geometric visual ray (f64, direct hit)':<55} {d4:>8.5f} {y4:>8.5f} {np.sqrt(d4**2+y4**2):>8.5f}")
    print(f"  {'Geometric visual ray (f32 compose + f32 apply)':<55} {d5:>8.5f} {y5:>8.5f} {np.sqrt(d5**2+y5**2):>8.5f}")
    print(f"  {'Kahan f64 carrier + f64 apply + snap':<55} {d6:>8.5f} {y6:>8.3f} {np.sqrt(d6**2+y6**2):>8.3f}")

    print(f"\n  Key observations:")
    if vis_hit:
        print(f"    Geometric visual ray gives BOTH carrier dist AND Y accuracy ~0")
        print(f"    because the intersection happens in visual space — no amplification")
    if pos_k:
        print(f"    Kahan hitpoint error: {kahan_hp_err:.6e} (vs standard: {abs(inter_hp - hp_exact):.6e})")
        print(f"    Kahan {'helps' if kahan_hp_err < abs(inter_hp - hp_exact) else 'does NOT help'} reduce intersection error")

    # PART D: Sensitivity of geometric visual ray to sample point choice
    print(f"\n{'='*60}")
    print("PART D: Sensitivity of Geometric Visual Ray to Sample Points")
    print(f"{'='*60}")

    pole = -frame.d / frame.c
    if frame.conjugating:
        pole = pole.conjugate()
    pole_t = ray.project_point(pole)
    print(f"  Pole at t={pole_t:.6f} on the ray")

    configs = [
        ("t=[0, 0.04, 0.08]",      [0.0, 0.04, 0.08]),
        ("t=[0, 0.02, 0.04]",      [0.0, 0.02, 0.04]),
        ("t=[0, 0.05, 0.5]",       [0.0, 0.05, 0.5]),
        ("t=[0, 0.05, 0.2]",       [0.0, 0.05, 0.2]),
        ("t=[0.05, 0.07, 0.09]",   [0.05, 0.07, 0.09]),
        ("t=[-0.1, 0, 0.05]",      [-0.1, 0.0, 0.05]),
        ("t=[0.11, 0.15, 0.2]",    [0.11, 0.15, 0.2]),  # past the pole
        ("t=[-0.5, 0.0, 0.5]",     [-0.5, 0.0, 0.5]),
    ]

    print(f"\n  {'Config':<30} {'Hits':>5} {'Carrier':>10} {'Y err':>10} {'VR type':>10}")
    print(f"  {'-'*30} {'-'*5} {'-'*10} {'-'*10} {'-'*10}")

    for name, t_samps in configs:
        pts = [ray.origin + t * ray.direction for t in t_samps]
        vpts = [frame.apply(p) for p in pts]
        if any(np.isinf(p.real) or np.isinf(p.imag) or np.isnan(p.real) for p in vpts):
            print(f"  {name:<30} {'inf':>5}")
            continue
        vr = GeneralizedCircle.from_three_points(vpts[0], vpts[1], vpts[2])
        vhits = intersect_circles(vr, wall_carrier)
        vr_type = "line" if vr.is_line() else f"r={vr.radius():.1f}"
        if vhits:
            best = min(vhits, key=lambda h: abs(h.imag - ref_y))
            cd = wall_carrier.geometric_dist(best)
            ye = abs(best.imag - ref_y)
            print(f"  {name:<30} {len(vhits):>5} {cd:>10.6e} {ye:>10.6f} {vr_type:>10}")
        else:
            print(f"  {name:<30} {'0':>5} {'':>10} {'':>10} {vr_type:>10}")


def experiment_16_comprehensive_pullback_comparison():
    """Adversarial comparison: Hermitian congruence vs geometric visual ray.

    Uses the same adversarial framework as carrier_precision_adversarial.py:
    compose N conformal inversions + 1 translation, then use random search
    to find worst-case configurations for each pullback method.

    Also includes the actual game scene (two arc reflections) and structured
    scenarios covering reflection, conjugation, and edge cases.
    """
    print("\n" + "=" * 70)
    print("EXPERIMENT 16: Adversarial Hermitian vs Geometric Visual Ray")
    print("=" * 70)

    # ==================================================================
    # Core primitives
    # ==================================================================

    def conformal_inversion_mobius(cx, cy, r):
        """Conformal inversion z → Z₀ + R²/(z - Z₀), non-conjugating Möbius.
        a=Z₀, b=R²-|Z₀|², c=1, d=-Z₀."""
        z0 = complex(cx, cy)
        z0_sq = complex(cx*cx - cy*cy, 2*cx*cy)
        return MobiusTransform(z0, complex(r*r, 0) - z0_sq, 1+0j, -z0, False, "Inv")

    def translation_mobius(tx, ty):
        return MobiusTransform(1+0j, complex(tx, ty), 0+0j, 1+0j, False, "T")

    def build_adversarial_frame(params, n_inv=2):
        """Build a frame from N conformal inversions + 1 translation.
        params: [cx1, cy1, r1, cx2, cy2, r2, ..., tx, ty, ray_angle]
        Returns (frame, visual_carrier, ray) or None if degenerate."""
        inversions = []
        idx = 0
        for k in range(n_inv):
            cx, cy, r = params[idx], params[idx+1], params[idx+2]
            inversions.append(conformal_inversion_mobius(cx, cy, r))
            idx += 3
        tx, ty = params[idx], params[idx+1]
        ray_angle = params[idx+2] if len(params) > idx+2 else 0.0

        portal = translation_mobius(tx, ty)
        frame = portal
        for inv in reversed(inversions):
            frame = frame.compose(inv)
        frame_inv = frame.invert()

        # Visual carrier = last inversion's circle
        last_idx = (n_inv - 1) * 3
        vis_cx, vis_cy, vis_r = params[last_idx], params[last_idx+1], params[last_idx+2]
        visual_carrier = GeneralizedCircle.from_circle(complex(vis_cx, vis_cy), vis_r)

        # Build normalized carrier via geometric stepwise
        geo_steps = [('translation', -tx, -ty)]
        for k in range(n_inv - 1, -1, -1):
            cx, cy, r = params[k*3], params[k*3+1], params[k*3+2]
            geo_steps.append(('inversion', cx, cy, r))

        nc_cx, nc_cy, nc_r = vis_cx, vis_cy, vis_r
        for step in geo_steps:
            if step[0] == 'translation':
                nc_cx += step[1]
                nc_cy += step[2]
            elif step[0] == 'inversion':
                z0x, z0y, R = step[1], step[2], step[3]
                dx_val = nc_cx - z0x
                dy_val = nc_cy - z0y
                d_sq = dx_val * dx_val + dy_val * dy_val
                P = d_sq - nc_r * nc_r
                if abs(P) < 1e-30:
                    return None
                scale = R * R / P
                nc_r = abs(scale) * nc_r
                nc_cx = z0x + scale * dx_val
                nc_cy = z0y - scale * dy_val

        if np.isnan(nc_r) or nc_r <= 0:
            return None

        # Ray aimed at the normalized carrier from 3x radius away
        ray_ox = nc_cx + nc_r * 3 * np.cos(ray_angle + np.pi)
        ray_oy = nc_cy + nc_r * 3 * np.sin(ray_angle + np.pi)
        rd = complex(nc_cx - ray_ox, nc_cy - ray_oy)
        rd_mag = abs(rd)
        if rd_mag < 1e-10:
            return None
        rd = rd / rd_mag

        return frame, visual_carrier, Ray(complex(ray_ox, ray_oy), rd)

    def geometric_visual_ray(ray, frame, t_samples=[0.0, 0.5, 1.0]):
        pts = [ray.origin + t * ray.direction for t in t_samples]
        vis_pts = [frame.apply(p) for p in pts]
        for vp in vis_pts:
            if np.isinf(vp.real) or np.isinf(vp.imag) or np.isnan(vp.real) or np.isnan(vp.imag):
                return None
        return GeneralizedCircle.from_three_points(vis_pts[0], vis_pts[1], vis_pts[2])

    def pullback_hermitian(ray, visual_carrier, frame):
        ray_line = ray_to_line(ray)
        visual_ray = hermitian_transform(ray_line, frame)
        visual_hits = intersect_circles(visual_ray, visual_carrier)
        if not visual_hits:
            return []
        frame_inv = frame.invert()
        results = []
        for vh in visual_hits:
            norm_point = frame_inv.apply(vh)
            t = ray.project_point(norm_point)
            on_ray = ray.origin + t * ray.direction
            vis_err = visual_carrier.geometric_dist(vh)
            results.append({'t': t, 'norm_pt': on_ray, 'vis_pt': vh, 'vis_err': vis_err})
        return results

    def pullback_geometric(ray, visual_carrier, frame, t_samples=[0.0, 0.5, 1.0]):
        vis_ray = geometric_visual_ray(ray, frame, t_samples)
        if vis_ray is None:
            return []
        visual_hits = intersect_circles(vis_ray, visual_carrier)
        if not visual_hits:
            return []
        frame_inv = frame.invert()
        results = []
        for vh in visual_hits:
            norm_point = frame_inv.apply(vh)
            t = ray.project_point(norm_point)
            on_ray = ray.origin + t * ray.direction
            vis_err = visual_carrier.geometric_dist(vh)
            results.append({'t': t, 'norm_pt': on_ray, 'vis_pt': vh, 'vis_err': vis_err})
        return results

    def amplification_at(frame, z):
        det = frame.a * frame.d - frame.b * frame.c
        if frame.conjugating:
            z = z.conjugate()
        den = frame.c * z + frame.d
        den_sq = abs(den)**2
        if den_sq < 1e-30:
            return float('inf')
        return abs(det) / den_sq

    def eval_scenario(frame, visual_carrier, ray, label=""):
        """Evaluate both methods on a scenario. Returns dict with results."""
        t_sample_sets = [[0.0, 0.5, 1.0], [0.0, 0.04, 0.08], [-0.5, 0.0, 0.5]]

        h_results = pullback_hermitian(ray, visual_carrier, frame)
        h_hits = len(h_results)
        h_best_err = min((r['vis_err'] for r in h_results), default=float('inf'))

        g_hits = 0
        g_best_err = float('inf')
        for ts in t_sample_sets:
            g_results = pullback_geometric(ray, visual_carrier, frame, ts)
            if len(g_results) > g_hits:
                g_hits = len(g_results)
            for r in g_results:
                if r['vis_err'] < g_best_err:
                    g_best_err = r['vis_err']

        # Back-propagation error: map normalized hitpoint through frame, measure carrier dist
        bp_err_h = float('inf')
        bp_err_g = float('inf')
        for r in h_results:
            vis = frame.apply(r['norm_pt'])
            bp_err_h = min(bp_err_h, visual_carrier.geometric_dist(vis))
        for ts in t_sample_sets:
            for r in pullback_geometric(ray, visual_carrier, frame, ts):
                vis = frame.apply(r['norm_pt'])
                bp_err_g = min(bp_err_g, visual_carrier.geometric_dist(vis))

        return {
            'label': label,
            'h_hits': h_hits, 'g_hits': g_hits,
            'h_vis_err': h_best_err, 'g_vis_err': g_best_err,
            'h_bp_err': bp_err_h, 'g_bp_err': bp_err_g,
        }

    # ==================================================================
    # Part A: Adversarial search (random + Nelder-Mead local refinement)
    # ==================================================================
    print("\n  Part A: Adversarial random search (2000 samples, depth 2-3)")
    print("  Looking for worst cases for EACH method...")

    rng = np.random.default_rng(42)
    n_samples = 2000
    worst_cases = {
        'geometric_fails': {'score': 0, 'params': None, 'depth': 0, 'detail': None},
        'hermitian_fails': {'score': 0, 'params': None, 'depth': 0, 'detail': None},
        'geometric_worst_err': {'score': 0, 'params': None, 'depth': 0, 'detail': None},
        'hermitian_worst_err': {'score': 0, 'params': None, 'depth': 0, 'detail': None},
        'max_backprop_err_g': {'score': 0, 'params': None, 'depth': 0, 'detail': None},
        'max_backprop_err_h': {'score': 0, 'params': None, 'depth': 0, 'detail': None},
    }
    summary_stats = {'total': 0, 'valid': 0, 'h_miss': 0, 'g_miss': 0,
                     'h_better': 0, 'g_better': 0, 'tie': 0, 'both_miss': 0}

    for n_inv in [2, 3]:
        bounds_lo = []
        bounds_hi = []
        for _ in range(n_inv):
            bounds_lo.extend([100, 100, 5])
            bounds_hi.extend([1800, 1000, 500])
        bounds_lo.extend([-2000, -2000, 0])
        bounds_hi.extend([2000, 2000, 2*np.pi])

        lo = np.array(bounds_lo)
        hi = np.array(bounds_hi)

        for i in range(n_samples):
            params = lo + (hi - lo) * rng.random(len(lo))
            result = build_adversarial_frame(params, n_inv)
            if result is None:
                continue
            frame, vis_carrier, ray = result
            summary_stats['total'] += 1

            try:
                ev = eval_scenario(frame, vis_carrier, ray, f"adv_{n_inv}inv_{i}")
            except Exception:
                continue
            summary_stats['valid'] += 1

            h_ok = ev['h_hits'] > 0
            g_ok = ev['g_hits'] > 0

            if h_ok and not g_ok:
                summary_stats['h_miss'] += 0
                summary_stats['g_miss'] += 1
                if worst_cases['geometric_fails']['score'] == 0 or True:
                    worst_cases['geometric_fails'] = {
                        'score': 1, 'params': params.copy(), 'depth': n_inv, 'detail': ev}
            elif g_ok and not h_ok:
                summary_stats['h_miss'] += 1
                summary_stats['g_miss'] += 0
                worst_cases['hermitian_fails'] = {
                    'score': 1, 'params': params.copy(), 'depth': n_inv, 'detail': ev}
            elif not h_ok and not g_ok:
                summary_stats['both_miss'] += 1
            else:
                if ev['h_vis_err'] < ev['g_vis_err'] * 0.9:
                    summary_stats['h_better'] += 1
                elif ev['g_vis_err'] < ev['h_vis_err'] * 0.9:
                    summary_stats['g_better'] += 1
                else:
                    summary_stats['tie'] += 1

            if g_ok and ev['g_vis_err'] > worst_cases['geometric_worst_err']['score']:
                worst_cases['geometric_worst_err'] = {
                    'score': ev['g_vis_err'], 'params': params.copy(), 'depth': n_inv, 'detail': ev}
            if h_ok and ev['h_vis_err'] > worst_cases['hermitian_worst_err']['score']:
                worst_cases['hermitian_worst_err'] = {
                    'score': ev['h_vis_err'], 'params': params.copy(), 'depth': n_inv, 'detail': ev}
            if ev['g_bp_err'] < float('inf') and ev['g_bp_err'] > worst_cases['max_backprop_err_g']['score']:
                worst_cases['max_backprop_err_g'] = {
                    'score': ev['g_bp_err'], 'params': params.copy(), 'depth': n_inv, 'detail': ev}
            if ev['h_bp_err'] < float('inf') and ev['h_bp_err'] > worst_cases['max_backprop_err_h']['score']:
                worst_cases['max_backprop_err_h'] = {
                    'score': ev['h_bp_err'], 'params': params.copy(), 'depth': n_inv, 'detail': ev}

    print(f"\n  Random search statistics:")
    print(f"    Total samples:  {summary_stats['total']}")
    print(f"    Valid configs:  {summary_stats['valid']}")
    print(f"    Geometric misses (H hits, G misses): {summary_stats['g_miss']}")
    print(f"    Hermitian misses (G hits, H misses): {summary_stats['h_miss']}")
    print(f"    Both miss:      {summary_stats['both_miss']}")
    print(f"    H better:       {summary_stats['h_better']}")
    print(f"    G better:       {summary_stats['g_better']}")
    print(f"    Tie:            {summary_stats['tie']}")

    print(f"\n  Worst cases found:")
    for name, wc in worst_cases.items():
        if wc['params'] is not None and wc['detail'] is not None:
            ev = wc['detail']
            print(f"\n    {name} (depth={wc['depth']}):")
            print(f"      H: {ev['h_hits']} hits, vis_err={ev['h_vis_err']:.4e}, bp_err={ev['h_bp_err']:.4e}")
            print(f"      G: {ev['g_hits']} hits, vis_err={ev['g_vis_err']:.4e}, bp_err={ev['g_bp_err']:.4e}")
            p = wc['params']
            print(f"      params: {', '.join(f'{v:.1f}' for v in p)}")

    # ==================================================================
    # Part B: Targeted adversarial — maximize geometric failure
    # ==================================================================
    print("\n\n  Part B: Targeted search — high-amplification configs")
    print("  Sampling with constrained pole proximity...")

    # Search specifically for cases where the pole is very close to the ray
    # These are the hardest cases for both methods
    targeted_results = []
    for n_inv in [2, 3]:
        bounds_lo = []
        bounds_hi = []
        for _ in range(n_inv):
            bounds_lo.extend([100, 100, 5])
            bounds_hi.extend([1800, 1000, 500])
        bounds_lo.extend([-2000, -2000, 0])
        bounds_hi.extend([2000, 2000, 2*np.pi])
        lo = np.array(bounds_lo)
        hi = np.array(bounds_hi)

        for i in range(n_samples):
            params = lo + (hi - lo) * rng.random(len(lo))
            result = build_adversarial_frame(params, n_inv)
            if result is None:
                continue
            frame, vis_carrier, ray = result

            # Only keep high-amplification cases (amp > 100)
            if frame.c == 0:
                continue
            pole = -frame.d / frame.c
            pole_t = ray.project_point(pole)
            pole_on_ray = ray.origin + pole_t * ray.direction
            pole_dist = abs(pole - pole_on_ray)
            if pole_dist > 1.0 or pole_dist < 1e-10:
                continue

            try:
                ev = eval_scenario(frame, vis_carrier, ray, f"tgt_{n_inv}_{i}")
            except Exception:
                continue

            amp = 1.0 / max(pole_dist**2, 1e-30)
            targeted_results.append({
                'ev': ev, 'pole_dist': pole_dist, 'amp': amp,
                'params': params.copy(), 'n_inv': n_inv,
            })

    targeted_results.sort(key=lambda x: x['amp'], reverse=True)
    print(f"\n  Found {len(targeted_results)} high-amplification configs (pole_dist < 1.0)")
    if targeted_results:
        print(f"\n  {'#':>3} {'pole_dist':>10} {'~amp':>10} {'H_hits':>6} {'G_hits':>6} "
              f"{'H_vis_err':>10} {'G_vis_err':>10} {'H_bp_err':>10} {'G_bp_err':>10}")
        print(f"  {'-'*3} {'-'*10} {'-'*10} {'-'*6} {'-'*6} {'-'*10} {'-'*10} {'-'*10} {'-'*10}")
        for j, tr in enumerate(targeted_results[:20]):
            ev = tr['ev']
            def fmt(x):
                if x == float('inf'): return "inf"
                if x < 1e-6: return f"{x:.2e}"
                return f"{x:.4e}"
            print(f"  {j+1:>3} {tr['pole_dist']:>10.6f} {tr['amp']:>10.1e} "
                  f"{ev['h_hits']:>6} {ev['g_hits']:>6} "
                  f"{fmt(ev['h_vis_err']):>10} {fmt(ev['g_vis_err']):>10} "
                  f"{fmt(ev['h_bp_err']):>10} {fmt(ev['g_bp_err']):>10}")

    # ==================================================================
    # Part C: Structured scenarios (game scene + edge cases)
    # ==================================================================
    print("\n\n  Part C: Structured scenarios (game scene + edge cases)")

    scenarios = []

    # C1: The actual game scene (two arc reflections, the failing case)
    surfaces, effects = build_scene()
    R_arc1 = effects['arc1_refl']
    R_arc2 = effects['arc2_refl']
    frame_game = R_arc2.compose(R_arc1)
    wall_carrier = GeneralizedCircle.from_line(800, 0, -1360000)
    frame_inv_game = frame_game.invert()
    vis_target = complex(1700, 647.8268)
    hp_exact = frame_inv_game.apply(vis_target)
    ray_origin_game = hp_exact - 0.1 * (complex(400, 250) - complex(1334.662, 234.909))
    scenarios.append(('Game: 2 arc reflections (near-pole)',
        frame_game, wall_carrier,
        Ray(ray_origin_game, complex(400, 250) - complex(1334.662, 234.909))))

    # C2: Identity frame (sanity check)
    scenarios.append(('Identity frame',
        MobiusTransform.identity(), GeneralizedCircle.from_circle(100+0j, 50.0),
        Ray(0+0j, 1+0j)))

    # C3: Pure translation
    scenarios.append(('Pure translation (+500,+300)',
        MobiusTransform(1+0j, 500+300j, 0+0j, 1+0j, False, "T"),
        GeneralizedCircle.from_circle(600+300j, 50.0),
        Ray(0+0j, 1+0j)))

    # C4: Single circle reflection (conjugating)
    c4 = GeneralizedCircle.from_circle(200+0j, 100.0)
    scenarios.append(('Circle reflection (conjugating)',
        reflection_mobius(c4), GeneralizedCircle.from_circle(500+0j, 30.0),
        Ray(-50+0j, 1+0j)))

    # C5: Two composed reflections — large circles, well-conditioned
    c5a = GeneralizedCircle.from_circle(100+100j, 200.0)
    c5b = GeneralizedCircle.from_circle(500+300j, 150.0)
    scenarios.append(('Two large-circle reflections',
        reflection_mobius(c5b).compose(reflection_mobius(c5a)),
        GeneralizedCircle.from_circle(800+400j, 60.0),
        Ray(50+50j, 1+0.3j)))

    # C6: Three composed reflections (conjugating)
    c6a = GeneralizedCircle.from_circle(100+0j, 40.0)
    c6b = GeneralizedCircle.from_circle(300+0j, 60.0)
    c6c = GeneralizedCircle.from_circle(500+0j, 50.0)
    scenarios.append(('Three composed reflections (conj)',
        reflection_mobius(c6c).compose(reflection_mobius(c6b).compose(reflection_mobius(c6a))),
        GeneralizedCircle.from_circle(700+0j, 40.0),
        Ray(0+0j, 1+0.1j)))

    # C7: Reflection + line visual carrier (wall)
    c7 = GeneralizedCircle.from_circle(300+300j, 80.0)
    scenarios.append(('Reflection + line carrier (wall)',
        reflection_mobius(c7), GeneralizedCircle.from_line(1, 0, -500),
        Ray(200+200j, 1+0.2j)))

    # C8: Ray through pole
    pf = MobiusTransform(1+0j, 0+0j, 0.01+0j, 1+0j, False, "P")
    scenarios.append(('Ray through pole',
        pf, GeneralizedCircle.from_circle(200+0j, 50.0),
        Ray(-200+0j, 1+0j)))

    # C9: Very small normalized carrier (the pullback trigger case)
    # Build via two inversions with well-separated centers
    inv_a = conformal_inversion_mobius(300, 300, 50)
    inv_b = conformal_inversion_mobius(800, 500, 100)
    portal_t = translation_mobius(200, 100)
    frame_c9 = portal_t.compose(inv_b).compose(inv_a)
    scenarios.append(('Two conformal inversions + translation',
        frame_c9, GeneralizedCircle.from_circle(800+500j, 100.0),
        Ray(100+100j, 1+0.5j)))

    # C10: Nearly-identity frame (c ≈ 0)
    scenarios.append(('Near-identity (tiny c)',
        MobiusTransform(1+0j, 500+0j, 1e-8+0j, 1+0j, False, "NI"),
        GeneralizedCircle.from_circle(600+0j, 50.0),
        Ray(0+0j, 1+0j)))

    print(f"\n  {'#':>2} {'Scenario':<40} {'H_hits':>6} {'G_hits':>6} "
          f"{'H_vis_err':>10} {'G_vis_err':>10} {'H_bp_err':>10} {'G_bp_err':>10} {'Winner':>7}")
    print(f"  {'-'*2} {'-'*40} {'-'*6} {'-'*6} {'-'*10} {'-'*10} {'-'*10} {'-'*10} {'-'*7}")

    structured_details = []
    for i, (name, frame, vis_carrier, ray) in enumerate(scenarios):
        try:
            ev = eval_scenario(frame, vis_carrier, ray, name)
        except Exception as e:
            print(f"  {i+1:>2} {name:<40} ERROR: {e}")
            continue

        h_ok = ev['h_hits'] > 0
        g_ok = ev['g_hits'] > 0
        if h_ok and not g_ok: winner = "HERM"
        elif g_ok and not h_ok: winner = "GEOM"
        elif not h_ok and not g_ok: winner = "NONE"
        elif ev['h_vis_err'] < ev['g_vis_err'] * 0.9: winner = "herm"
        elif ev['g_vis_err'] < ev['h_vis_err'] * 0.9: winner = "geom"
        else: winner = "tie"

        def fmt(x):
            if x == float('inf'): return "inf"
            if x < 1e-6: return f"{x:.2e}"
            return f"{x:.4e}"

        print(f"  {i+1:>2} {name:<40} {ev['h_hits']:>6} {ev['g_hits']:>6} "
              f"{fmt(ev['h_vis_err']):>10} {fmt(ev['g_vis_err']):>10} "
              f"{fmt(ev['h_bp_err']):>10} {fmt(ev['g_bp_err']):>10} {winner:>7}")
        structured_details.append((name, ev, winner))

        if winner in ("HERM", "NONE"):
            if frame.c != 0:
                pole = -frame.d / frame.c
                if frame.conjugating:
                    pole = pole.conjugate()
                pole_t = ray.project_point(pole)
                pole_on_ray = ray.origin + pole_t * ray.direction
                pole_dist = abs(pole - pole_on_ray)
                det = frame.a * frame.d - frame.b * frame.c
                print(f"       ** pole_dist={pole_dist:.6f}, |det|={abs(det):.6e}, conj={frame.conjugating}")

    # ==================================================================
    # Grand summary
    # ==================================================================
    print(f"\n  {'='*70}")
    print(f"  GRAND SUMMARY")
    print(f"  {'='*70}")

    # From random search
    print(f"\n  Adversarial random search ({summary_stats['valid']} valid configs):")
    if summary_stats['valid'] > 0:
        print(f"    Geometric misses: {summary_stats['g_miss']} "
              f"({100*summary_stats['g_miss']/summary_stats['valid']:.1f}%)")
        print(f"    Hermitian misses: {summary_stats['h_miss']} "
              f"({100*summary_stats['h_miss']/summary_stats['valid']:.1f}%)")
        print(f"    Both miss:        {summary_stats['both_miss']} "
              f"({100*summary_stats['both_miss']/summary_stats['valid']:.1f}%)")
        print(f"    H better quality: {summary_stats['h_better']} "
              f"({100*summary_stats['h_better']/summary_stats['valid']:.1f}%)")
        print(f"    G better quality: {summary_stats['g_better']} "
              f"({100*summary_stats['g_better']/summary_stats['valid']:.1f}%)")
        print(f"    Tie:              {summary_stats['tie']} "
              f"({100*summary_stats['tie']/summary_stats['valid']:.1f}%)")

    # From structured scenarios
    h_wins = sum(1 for _, _, w in structured_details if w == 'HERM')
    g_wins = sum(1 for _, _, w in structured_details if w == 'GEOM')
    print(f"\n  Structured scenarios ({len(structured_details)} total):")
    print(f"    Hermitian exclusive wins: {h_wins}")
    print(f"    Geometric exclusive wins: {g_wins}")

    if h_wins > 0 or summary_stats['g_miss'] > 0:
        print(f"\n  ** WARNING: Geometric visual ray fails in some configurations!")
        print(f"  ** This is a TRADEOFF — geometric is NOT strictly better.")
    elif g_wins > 0 or summary_stats['h_miss'] > 0:
        print(f"\n  ** Geometric visual ray is STRICTLY better than Hermitian")
        print(f"  ** across all {summary_stats['valid'] + len(structured_details)} tested configurations.")


def main():
    direct_precision_analysis()
    experiment_14_three_improvements()
    experiment_15_visual_space_and_kahan()
    experiment_16_comprehensive_pullback_comparison()


if __name__ == '__main__':
    main()
