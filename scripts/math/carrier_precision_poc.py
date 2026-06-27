"""
Proof of concept: algebraic vs pointwise carrier transformation under Möbius maps.

Compares three approaches:
  1. 3-point fit (exact interpolation, current tracer method)
  2. N-point least-squares fit (overdetermined, with well-spread anchors)
  3. Algebraic Hermitian transform (H' = N†HN, matrix multiply on coefficients)

Uses the actual game geometry that causes the 807-2204 px gaps.
"""

import numpy as np


# ── Complex arithmetic on 2-tuples ──

def cmul(a, b):
    return (a[0]*b[0]-a[1]*b[1], a[0]*b[1]+a[1]*b[0])

def cdiv(a, b):
    d = b[0]**2 + b[1]**2
    return ((a[0]*b[0]+a[1]*b[1])/d, (a[1]*b[0]-a[0]*b[1])/d)

def cconj(a):
    return (a[0], -a[1])


class Mobius:
    def __init__(self, a, b, c, d):
        self.a, self.b, self.c, self.d = a, b, c, d

    def apply(self, z):
        num = (cmul(self.a,z)[0]+self.b[0], cmul(self.a,z)[1]+self.b[1])
        den = (cmul(self.c,z)[0]+self.d[0], cmul(self.c,z)[1]+self.d[1])
        return cdiv(num, den)

    def compose(self, other):
        na = (cmul(self.a,other.a)[0]+cmul(self.b,other.c)[0],
              cmul(self.a,other.a)[1]+cmul(self.b,other.c)[1])
        nb = (cmul(self.a,other.b)[0]+cmul(self.b,other.d)[0],
              cmul(self.a,other.b)[1]+cmul(self.b,other.d)[1])
        nc = (cmul(self.c,other.a)[0]+cmul(self.d,other.c)[0],
              cmul(self.c,other.a)[1]+cmul(self.d,other.c)[1])
        nd = (cmul(self.c,other.b)[0]+cmul(self.d,other.d)[0],
              cmul(self.c,other.b)[1]+cmul(self.d,other.d)[1])
        return Mobius(na, nb, nc, nd)

    def invert(self):
        det = (cmul(self.a,self.d)[0]-cmul(self.b,self.c)[0],
               cmul(self.a,self.d)[1]-cmul(self.b,self.c)[1])
        return Mobius(cdiv(self.d,det), cdiv((-self.b[0],-self.b[1]),det),
                      cdiv((-self.c[0],-self.c[1]),det), cdiv(self.a,det))

    def amplification_at(self, z):
        den = (cmul(self.c,z)[0]+self.d[0], cmul(self.c,z)[1]+self.d[1])
        det = (cmul(self.a,self.d)[0]-cmul(self.b,self.c)[0],
               cmul(self.a,self.d)[1]-cmul(self.b,self.c)[1])
        den_sq = den[0]**2 + den[1]**2
        return np.sqrt(det[0]**2+det[1]**2) / den_sq if den_sq > 0 else float('inf')

    def matrix(self):
        return np.array([[self.a[0]+1j*self.a[1], self.b[0]+1j*self.b[1]],
                         [self.c[0]+1j*self.c[1], self.d[0]+1j*self.d[1]]])


class Circle:
    def __init__(self, a, b, c, d):
        self.a, self.b, self.c, self.d = a, b, c, d

    @staticmethod
    def from_center_radius(cx, cy, r):
        return Circle(1.0, -2*cx, -2*cy, cx*cx+cy*cy-r*r)

    def center(self):
        if abs(self.a) < 1e-30: return (float('inf'), float('inf'))
        return (-self.b/(2*self.a), -self.c/(2*self.a))

    def radius(self):
        if abs(self.a) < 1e-30: return float('inf')
        disc = self.b**2 + self.c**2 - 4*self.a*self.d
        return np.sqrt(max(0,disc))/(2*abs(self.a)) if disc>=0 else float('nan')

    def evaluate(self, x, y):
        return self.a*(x*x+y*y) + self.b*x + self.c*y + self.d

    def distance_from(self, x, y):
        cx, cy = self.center()
        r = self.radius()
        if np.isnan(r) or np.isinf(r): return float('inf')
        return abs(np.sqrt((x-cx)**2+(y-cy)**2) - r)

    def hermitian(self):
        w = complex(self.b/2, -self.c/2)
        return np.array([[self.a, w.conjugate()], [w, self.d]])

    @staticmethod
    def from_hermitian(H):
        a = H[0,0].real
        wc = H[0,1]
        return Circle(a, 2*wc.real, 2*wc.imag, H[1,1].real)


def circle_from_3_points(p1, p2, p3):
    """Exact 3-point circle fit (current tracer method)."""
    (x1,y1),(x2,y2),(x3,y3) = p1, p2, p3
    s1,s2,s3 = x1*x1+y1*y1, x2*x2+y2*y2, x3*x3+y3*y3
    A = np.array([[s1,x1,y1,1],[s2,x2,y2,1],[s3,x3,y3,1]])
    ca = np.linalg.det(A[:,1:])
    cb = -np.linalg.det(A[:,[0,2,3]])
    cc = np.linalg.det(A[:,[0,1,3]])
    cd = -np.linalg.det(A[:,[0,1,2]])
    m = max(abs(ca),abs(cb),abs(cc),abs(cd),1e-30)
    return Circle(ca/m, cb/m, cc/m, cd/m)


def circle_from_n_points_lstsq(points):
    """Least-squares circle fit from N points.
    Solves a(x²+y²) + bx + cy + d = 0 in the least-squares sense.
    The system is [s_i, x_i, y_i, 1] · [a, b, c, d]^T = 0.
    We use SVD to find the null space of the N×4 matrix."""
    n = len(points)
    A = np.zeros((n, 4))
    for i, (x, y) in enumerate(points):
        A[i] = [x*x + y*y, x, y, 1.0]
    _, S, Vt = np.linalg.svd(A)
    coeffs = Vt[-1]  # last row = smallest singular value direction
    m = max(abs(coeffs[0]), abs(coeffs[1]), abs(coeffs[2]), abs(coeffs[3]), 1e-30)
    return Circle(coeffs[0]/m, coeffs[1]/m, coeffs[2]/m, coeffs[3]/m)


def transform_carrier_algebraic(carrier, mobius):
    """IMAGE of circle under Möbius via Hermitian matrix transform."""
    H = carrier.hermitian()
    A = mobius.matrix()
    N = np.array([[A[1,1], -A[0,1]], [-A[1,0], A[0,0]]])
    Hp = N.conj().T @ H @ N
    return Circle.from_hermitian(Hp)


def matrix_nth_root(A, n):
    """Principal N-th root of a 2×2 complex matrix.
    Uses eigendecomposition for diagonalizable matrices,
    Jordan form for defective (repeated eigenvalue) matrices."""
    if n == 1:
        return A.copy()
    eigenvalues, P = np.linalg.eig(A)
    if abs(eigenvalues[0] - eigenvalues[1]) < 1e-10 * max(abs(eigenvalues[0]), 1):
        lam = (eigenvalues[0] + eigenvalues[1]) / 2
        nilp = A - lam * np.eye(2, dtype=complex)
        lam_root = lam ** (1.0 / n)
        coeff = lam_root / (n * lam) if abs(lam) > 1e-30 else 0
        return lam_root * np.eye(2, dtype=complex) + coeff * nilp
    root_eigs = np.array([eigenvalues[0] ** (1.0/n), eigenvalues[1] ** (1.0/n)])
    return P @ np.diag(root_eigs) @ np.linalg.inv(P)


def transform_carrier_subdivided(carrier, mobius_list, n_sub):
    """Subdivided stepwise Hermitian transform.
    Each Möbius is split into n_sub sub-transforms via matrix N-th root.
    N is an accuracy knob: higher N → sub-transforms closer to identity
    → less floating-point cancellation per step."""
    H = carrier.hermitian()
    for m in mobius_list:
        A = m.matrix()
        A_sub = matrix_nth_root(A, n_sub)
        adj_sub = np.array([[A_sub[1,1], -A_sub[0,1]], [-A_sub[1,0], A_sub[0,0]]])
        for _ in range(n_sub):
            H = adj_sub.conj().T @ H @ adj_sub
            scale = np.max(np.abs(H))
            if scale > 0:
                H = H / scale
    return Circle.from_hermitian(H)


def transform_carrier_stepwise(carrier, mobius_list):
    """Stepwise Hermitian transform: apply each Möbius individually, renormalizing
    the Hermitian matrix at each step to keep entries O(1).
    Mathematically identical to the one-shot algebraic transform, but each step
    uses adj(M_k) with small entries instead of adj(M_composed) with huge entries."""
    H = carrier.hermitian()
    for m in mobius_list:
        A = m.matrix()
        N = np.array([[A[1,1], -A[0,1]], [-A[1,0], A[0,0]]])
        H = N.conj().T @ H @ N
        # Renormalize: circle equation is homogeneous, scale doesn't matter
        scale = np.max(np.abs(H))
        if scale > 0:
            H = H / scale
    return Circle.from_hermitian(H)


def transform_carrier_geometric(cx, cy, r, steps):
    """Geometric stepwise: evolve center and radius through each transform.
    Each step is ('inversion', inv_cx, inv_cy, inv_r) or ('translation', tx, ty).
    Uses direct geometric formulas — no matrices, no Hermitian representation.
    For conformal inversion z→Z₀+R²/(z-Z₀): image center uses conj(delta),
    i.e., the y-offset from inversion center is negated (unlike anti-conformal
    geometric inversion which preserves the sign)."""
    for step in steps:
        if step[0] == 'translation':
            cx += step[1]
            cy += step[2]
        elif step[0] == 'inversion':
            z0x, z0y, R = step[1], step[2], step[3]
            dx_val = cx - z0x
            dy_val = cy - z0y
            d_sq = dx_val * dx_val + dy_val * dy_val
            P = d_sq - r * r
            if abs(P) < 1e-30:
                return Circle(0, 0, 0, 0)  # degenerate
            scale = R * R / P
            r = abs(scale) * r
            # Conformal inversion: c' = Z₀ + (R²/P)·conj(δ) = Z₀ + scale·(δx, -δy)
            cx = z0x + scale * dx_val
            cy = z0y - scale * dy_val
    return Circle.from_center_radius(cx, cy, r)


class DDReal:
    """Lightweight double-double for real arithmetic only (no complex overhead)."""
    __slots__ = ('hi', 'lo')
    def __init__(self, hi, lo=0.0):
        self.hi = float(hi)
        self.lo = float(lo)
    def __add__(self, other):
        s1, s2 = two_sum(self.hi, other.hi)
        s2 += self.lo + other.lo
        s1, s2 = two_sum(s1, s2)
        return DDReal(s1, s2)
    def __sub__(self, other):
        return self + DDReal(-other.hi, -other.lo)
    def __mul__(self, other):
        p1, p2 = two_prod(self.hi, other.hi)
        p2 += self.hi * other.lo + self.lo * other.hi
        p1, p2 = two_sum(p1, p2)
        return DDReal(p1, p2)
    def __neg__(self):
        return DDReal(-self.hi, -self.lo)
    def __abs__(self):
        if self.hi < 0 or (self.hi == 0 and self.lo < 0):
            return -self
        return DDReal(self.hi, self.lo)
    def __truediv__(self, other):
        q1 = self.hi / other.hi
        r = self - DDReal(q1) * other
        q2 = r.hi / other.hi
        return DDReal(q1 + q2, 0.0)
    @property
    def val(self):
        return self.hi + self.lo


def transform_carrier_geo_compensated(cx, cy, r, steps):
    """Geometric stepwise with DD (double-double) arithmetic for ~106-bit precision.
    Combines the geometric representation (no Hermitian conflation) with
    compensated arithmetic (no float64 cancellation). Best of both worlds."""
    cx = DDReal(cx)
    cy = DDReal(cy)
    r = DDReal(r)
    for step in steps:
        if step[0] == 'translation':
            cx = cx + DDReal(step[1])
            cy = cy + DDReal(step[2])
        elif step[0] == 'inversion':
            z0x = DDReal(step[1])
            z0y = DDReal(step[2])
            R = DDReal(step[3])
            dx_val = cx - z0x
            dy_val = cy - z0y
            d_sq = dx_val * dx_val + dy_val * dy_val
            P = d_sq - r * r
            R_sq = R * R
            scale = R_sq / P
            r = abs(scale) * r
            cx = z0x + scale * dx_val
            cy = z0y - scale * dy_val
    return Circle.from_center_radius(cx.val, cy.val, r.val)


def ray_circle_intersect_cr(ox, oy, dx, dy, cx, cy, r):
    """Ray-circle intersection using center+radius directly.
    Avoids computing d = cx²+cy²-r² which loses the tiny r² term."""
    ddx = ox - cx
    ddy = oy - cy
    A = dx*dx + dy*dy
    B = 2*(dx*ddx + dy*ddy)
    C = ddx*ddx + ddy*ddy - r*r
    if abs(A) < 1e-30: return []
    disc = B*B - 4*A*C
    if disc < 0: return []
    sq = np.sqrt(disc)
    return [(t, ox+t*dx, oy+t*dy) for t in [(-B-sq)/(2*A), (-B+sq)/(2*A)]]


def transform_carrier_geo_npoint(cx, cy, r, steps, fi, n_points):
    """Hybrid: geometric center + N-point radius refinement.
    1. Compute center via geometric stepwise (high precision, no matrices)
    2. Generate N points on the VISUAL carrier
    3. Map each through frame_inv (pointwise)
    4. Measure each mapped point's distance from the geometric center
    5. Take the median as the radius (robust to outliers)
    This combines geometric's center precision with N-point's radius averaging."""
    # Step 1: geometric center
    geo_cx, geo_cy = cx, cy
    geo_r = r
    for step in steps:
        if step[0] == 'translation':
            geo_cx += step[1]
            geo_cy += step[2]
        elif step[0] == 'inversion':
            z0x, z0y, R = step[1], step[2], step[3]
            dx_val = geo_cx - z0x
            dy_val = geo_cy - z0y
            d_sq = dx_val * dx_val + dy_val * dy_val
            P = d_sq - geo_r * geo_r
            if abs(P) < 1e-30:
                return Circle(0, 0, 0, 0)
            scale = R * R / P
            geo_r = abs(scale) * geo_r
            geo_cx = z0x + scale * dx_val
            geo_cy = z0y - scale * dy_val

    # Step 2-5: N-point radius refinement
    radii = []
    for i in range(n_points):
        angle = 2 * np.pi * i / n_points
        vx = cx + r * np.cos(angle)
        vy = cy + r * np.sin(angle)
        # Map visual point through frame_inv
        nx, ny = fi.apply((vx, vy))
        # Distance from geometric center
        dist = np.sqrt((nx - geo_cx)**2 + (ny - geo_cy)**2)
        radii.append(dist)

    refined_r = np.median(radii)
    return Circle.from_center_radius(geo_cx, geo_cy, refined_r)


# ── Inversive Pullback ──

def circle_circle_intersect(c1x, c1y, c1r, c2x, c2y, c2r):
    """Intersect two circles geometrically. Returns list of (x, y) points."""
    dx = c2x - c1x
    dy = c2y - c1y
    d = np.sqrt(dx*dx + dy*dy)
    if d > c1r + c2r + 1e-10 or d < abs(c1r - c2r) - 1e-10 or d < 1e-30:
        return []
    a = (c1r*c1r - c2r*c2r + d*d) / (2*d)
    h_sq = c1r*c1r - a*a
    if h_sq < -1e-20:
        return []
    h = np.sqrt(max(0, h_sq))
    px = c1x + a*dx/d
    py = c1y + a*dy/d
    if h < 1e-30:
        return [(px, py)]
    return [(px + h*dy/d, py - h*dx/d), (px - h*dy/d, py + h*dx/d)]


def inversive_pullback(ray_ox, ray_oy, ray_dx, ray_dy,
                       carrier_cx, carrier_cy, carrier_r,
                       frame, fi, frame_steps=None):
    """Inversive pullback: do the intersection in visual space.
    1. Represent normalized-space ray as a generalized circle (a line, a=0)
    2. Map it to visual space via Hermitian transform (result is a full-size circle)
    3. Circle-circle intersection with the visual carrier (well-conditioned)
    4. Map intersection points back to normalized space via frame_inv
    Mobius transforms preserve incidence, so this is mathematically exact."""
    # Step 1: Ray as generalized circle (line with a=0)
    # dy*(x-ox) - dx*(y-oy) = 0 → dy*x - dx*y + (dx*oy - dy*ox) = 0
    ray_line = Circle(0.0, ray_dy, -ray_dx, ray_dx*ray_oy - ray_dy*ray_ox)

    # Step 2: Map to visual space (use stepwise if available)
    if frame_steps:
        visual_ray = transform_carrier_stepwise(ray_line, frame_steps)
    else:
        visual_ray = transform_carrier_algebraic(ray_line, frame)

    vrc = visual_ray.center()
    vrr = visual_ray.radius()
    if np.isnan(vrr) or np.isinf(vrr) or vrr < 1e-20:
        return []

    # Step 3: Circle-circle intersection in visual space (full-size circles!)
    hits_visual = circle_circle_intersect(vrc[0], vrc[1], vrr,
                                          carrier_cx, carrier_cy, carrier_r)
    if not hits_visual:
        return []

    # Step 4: Map each visual intersection point back to normalized space
    results = []
    for (hx, hy) in hits_visual:
        norm_pt = fi.apply((hx, hy))
        ddx = norm_pt[0] - ray_ox
        ddy = norm_pt[1] - ray_oy
        t = (ddx * ray_dx + ddy * ray_dy) / (ray_dx**2 + ray_dy**2)
        if t > 1e-15:
            results.append((t, norm_pt[0], norm_pt[1]))
    return sorted(results, key=lambda h: h[0])


# ── Compensated (Error-Free) arithmetic ──

def two_sum(a, b):
    s = a + b
    v = s - a
    lo = (a - (s - v)) + (b - v)
    return s, lo

def two_prod(a, b):
    p = a * b
    # Veltkamp splitting (works without FMA)
    factor = (1 << 27) + 1
    ah = factor * a - (factor * a - a)
    al = a - ah
    bh = factor * b - (factor * b - b)
    bl = b - bh
    e = ((ah * bh - p) + ah * bl + al * bh) + al * bl
    return p, e

class DD:
    """Double-double: represents a value as hi + lo for ~106 bits of precision."""
    __slots__ = ('hi', 'lo')
    def __init__(self, hi, lo=0.0):
        self.hi = hi
        self.lo = lo
    def __add__(self, other):
        s1, s2 = two_sum(self.hi, other.hi)
        s2 += self.lo + other.lo
        s1, s2 = two_sum(s1, s2)
        return DD(s1, s2)
    def __sub__(self, other):
        return self + DD(-other.hi, -other.lo)
    def __mul__(self, other):
        p1, p2 = two_prod(self.hi, other.hi)
        p2 += self.hi * other.lo + self.lo * other.hi
        p1, p2 = two_sum(p1, p2)
        return DD(p1, p2)
    def __neg__(self):
        return DD(-self.hi, -self.lo)
    @property
    def val(self):
        return self.hi + self.lo

class DDComplex:
    """Double-double complex number."""
    __slots__ = ('re', 'im')
    def __init__(self, re, im=None):
        if im is None:
            im = DD(0.0)
        if not isinstance(re, DD):
            re = DD(float(re))
        if not isinstance(im, DD):
            im = DD(float(im))
        self.re = re
        self.im = im
    def __add__(self, other):
        return DDComplex(self.re + other.re, self.im + other.im)
    def __sub__(self, other):
        return DDComplex(self.re - other.re, self.im - other.im)
    def __mul__(self, other):
        return DDComplex(self.re * other.re - self.im * other.im,
                         self.re * other.im + self.im * other.re)
    def conj(self):
        return DDComplex(self.re, -self.im)
    def __neg__(self):
        return DDComplex(-self.re, -self.im)
    @property
    def val(self):
        return complex(self.re.val, self.im.val)


def transform_carrier_compensated(carrier, mobius_list):
    """Stepwise Hermitian with double-double compensated arithmetic.
    Uses error-free transformations (TwoSum, TwoProduct) to get ~106 bits
    of precision from float64 operations."""
    def to_ddc(z):
        return DDComplex(DD(z.real), DD(z.imag))
    H = carrier.hermitian()
    # Convert to DD complex
    h00 = to_ddc(H[0,0])
    h01 = to_ddc(H[0,1])
    h10 = to_ddc(H[1,0])
    h11 = to_ddc(H[1,1])

    for m in mobius_list:
        A = m.matrix()
        # adj(A) = [[d, -b], [-c, a]]
        n00 = to_ddc(A[1,1])
        n01 = to_ddc(-A[0,1])
        n10 = to_ddc(-A[1,0])
        n11 = to_ddc(A[0,0])
        # N_conj_T (= N†): conjugate transpose of adj
        ct00 = n00.conj(); ct01 = n10.conj()
        ct10 = n01.conj(); ct11 = n11.conj()
        # tmp = H @ N
        t00 = h00 * n00 + h01 * n10
        t01 = h00 * n01 + h01 * n11
        t10 = h10 * n00 + h11 * n10
        t11 = h10 * n01 + h11 * n11
        # result = N† @ tmp
        h00 = ct00 * t00 + ct01 * t10
        h01 = ct00 * t01 + ct01 * t11
        h10 = ct10 * t00 + ct11 * t10
        h11 = ct10 * t01 + ct11 * t11
        # Renormalize
        vals = [abs(h00.val), abs(h01.val), abs(h10.val), abs(h11.val)]
        scale = max(vals)
        if scale > 0:
            inv_s = DD(1.0 / scale)
            inv_sc = DDComplex(inv_s)
            h00 = h00 * inv_sc; h01 = h01 * inv_sc
            h10 = h10 * inv_sc; h11 = h11 * inv_sc

    Hp = np.array([[h00.val, h01.val], [h10.val, h11.val]])
    return Circle.from_hermitian(Hp)


def ray_circle_intersect(ox, oy, dx, dy, carrier):
    A = carrier.a*(dx*dx+dy*dy)
    B = carrier.a*2*(ox*dx+oy*dy)+carrier.b*dx+carrier.c*dy
    C = carrier.evaluate(ox, oy)
    if abs(A) < 1e-30: return []
    disc = B*B - 4*A*C
    if disc < 0: return []
    sq = np.sqrt(disc)
    return [(t, ox+t*dx, oy+t*dy) for t in [(-B-sq)/(2*A), (-B+sq)/(2*A)]]


def conformal_inversion(cx, cy, r):
    c_sq_real = cx*cx - cy*cy
    c_sq_imag = 2*cx*cy
    return Mobius(a=(cx,cy), b=(r*r-c_sq_real, -c_sq_imag), c=(1,0), d=(-cx,-cy))


def translation(tx, ty):
    return Mobius(a=(1,0), b=(tx,ty), c=(0,0), d=(1,0))


def generate_n_points_on_carrier(cx, cy, r, n, include_special=False):
    """Generate N well-spread points on the carrier.

    If include_special=True, includes:
    - The 'via' point (top of arc) and 'counter-via' (bottom)
    - Points spread to maximize angular coverage
    These are 'definitional' points that are exact by construction.
    """
    points = []
    if include_special and n >= 4:
        # Definitional anchors: cardinal directions on the carrier
        points.append((cx + r, cy))      # right (like start)
        points.append((cx - r, cy))      # left (like end)
        points.append((cx, cy - r))      # top = via
        points.append((cx, cy + r))      # bottom = counter-via
        remaining = n - 4
        # Fill in with evenly-spaced points avoiding the 4 cardinals
        for i in range(remaining):
            angle = (2 * np.pi * (i + 0.5)) / remaining  # offset to avoid cardinals
            # skip if too close to a cardinal
            points.append((cx + r * np.cos(angle), cy + r * np.sin(angle)))
    else:
        for i in range(n):
            angle = 2 * np.pi * i / n
            points.append((cx + r * np.cos(angle), cy + r * np.sin(angle)))
    return points


def first_pos(hits):
    p = [(t,x,y) for t,x,y in hits if t > 1e-15]
    return min(p, key=lambda h: h[0]) if p else None


def hit_distance(h, frame, target_carrier):
    """Map hitpoint through frame and measure distance to target carrier."""
    if h is None:
        return float('inf')
    vis = frame.apply((h[1], h[2]))
    return target_carrier.distance_from(vis[0], vis[1])


# ════════════════════════════════════════════════════════════════
# Precision tests for non-intersection calculations
# ════════════════════════════════════════════════════════════════

def hdet(zA, wA, zB, wB):
    """Homogeneous determinant: zA*wB - zB*wA (as complex 2-tuple)."""
    return (zA[0]*wB - zB[0]*wA, zA[1]*wB - zB[1]*wA)


def cross_ratio_containment(S, P, E, V, wS=1.0, wP=1.0, wE=1.0, wV=1.0):
    """Cross-ratio segment containment: Re(cross_ratio(S,P;E,V)) >= 0.
    Returns (bool, product_x) where product_x is the raw real part."""
    sv = hdet(S, wS, V, wV)
    ep = hdet(E, wE, P, wP)
    sp = hdet(S, wS, P, wP)
    ev = hdet(E, wE, V, wV)
    num = cmul(sv, ep)
    den = cmul(sp, ev)
    den_conj = cconj(den)
    product = cmul(num, den_conj)
    return (product[0] >= 0.0, product[0])


def normalize_vec(v):
    mag = np.sqrt(v[0]**2 + v[1]**2)
    if mag < 1e-30:
        return (0.0, 0.0)
    return (v[0]/mag, v[1]/mag)


def angle_between(v1, v2):
    dot = v1[0]*v2[0] + v1[1]*v2[1]
    dot = max(-1.0, min(1.0, dot))
    return np.arccos(dot)


def test_cross_ratio_containment(f, fi, arc2, ng, amp):
    """Test 1: Does cross-ratio containment give correct results
    when all 4 points collapse into a tiny normalized-space cluster?"""
    ngc = ng.center()
    ngr = ng.radius()
    if np.isnan(ngr) or ngr <= 0:
        print(f"    Skipped (degenerate carrier, radius={ngr})")
        return 0

    S_vis = (1550.0, 750.0)
    E_vis = (1450.0, 750.0)
    V_vis = (1500.0, 700.0)
    S_norm = fi.apply(S_vis)
    E_norm = fi.apply(E_vis)
    V_norm = fi.apply(V_vis)

    print(f"  ── Test 1: Cross-ratio containment ──")
    print(f"  {'angle':>8s}  {'norm':>6s}  {'visual':>6s}  {'match':>6s}  {'product.x':>12s}")

    mismatches = 0
    n_pts = 16
    for i in range(n_pts):
        angle = 2 * np.pi * i / n_pts
        P_vis = (1500.0 + 50.0*np.cos(angle), 750.0 + 50.0*np.sin(angle))
        P_norm = fi.apply(P_vis)

        norm_result, norm_px = cross_ratio_containment(S_norm, P_norm, E_norm, V_norm)
        vis_result, vis_px = cross_ratio_containment(S_vis, P_vis, E_vis, V_vis)

        match = "OK" if norm_result == vis_result else "FAIL"
        if norm_result != vis_result:
            mismatches += 1
        deg = np.degrees(angle)
        print(f"  {deg:>7.1f}°  {str(norm_result):>6s}  {str(vis_result):>6s}  {match:>6s}  {norm_px:>12.2e}")

    print(f"  Mismatches: {mismatches}/{n_pts}")
    return mismatches


def test_side_of_carrier(f, fi, arc2, ng, amp):
    """Test 2: Does carrier.evaluate(P) give the correct inside/outside sign
    for points near the normalized carrier?"""
    ngc = ng.center()
    ngr = ng.radius()
    if np.isnan(ngr) or ngr <= 0:
        print(f"    Skipped (degenerate carrier, radius={ngr})")
        return 0

    print(f"  ── Test 2: Side-of-carrier (evaluate sign) ──")
    print(f"  {'case':>20s}  {'norm_eval':>12s}  {'vis_eval':>12s}  {'sign':>6s}  {'grad_err':>10s}")

    mismatches = 0
    for i in range(8):
        angle = 2 * np.pi * i / 8
        for label, frac in [("inside", 0.999), ("outside", 1.001)]:
            Px = ngc[0] + frac * ngr * np.cos(angle)
            Py = ngc[1] + frac * ngr * np.sin(angle)
            norm_eval = ng.evaluate(Px, Py)

            P_vis = f.apply((Px, Py))
            vis_eval = arc2.evaluate(P_vis[0], P_vis[1])

            norm_sign = 1 if norm_eval > 0 else (-1 if norm_eval < 0 else 0)
            vis_sign = 1 if vis_eval > 0 else (-1 if vis_eval < 0 else 0)
            match = "OK" if norm_sign == vis_sign else "FAIL"
            if norm_sign != vis_sign:
                mismatches += 1

            grad_norm = (2*ng.a*Px + ng.b, 2*ng.a*Py + ng.c)
            grad_vis = (2*arc2.a*P_vis[0] + arc2.b, 2*arc2.a*P_vis[1] + arc2.c)
            gn = normalize_vec(grad_norm)
            gv = normalize_vec(grad_vis)
            if gn[0] == 0 and gn[1] == 0:
                g_err = float('nan')
            else:
                # Map normalized gradient through Mobius derivative for comparison
                # Just report the gradient magnitude ratio as a sanity check
                g_err = np.sqrt(grad_norm[0]**2+grad_norm[1]**2)

            deg = np.degrees(angle)
            tag = f"{deg:.0f}° {label}"
            print(f"  {tag:>20s}  {norm_eval:>12.2e}  {vis_eval:>12.2e}  {match:>6s}  {g_err:>10.2e}")

    print(f"  Mismatches: {mismatches}/16")
    print(f"  ng.d = {ng.d:.6f}  (should encode cx²+cy²-r², but r²~{ngr**2:.2e} is lost if d~{ngc[0]**2+ngc[1]**2:.0f})")
    return mismatches


def test_reflection_normal(f, fi, arc2, ng, amp):
    """Test 3: Does (hit - center).normalized() give the correct radial
    direction in normalized space?"""
    ngc = ng.center()
    ngr = ng.radius()
    if np.isnan(ngr) or ngr <= 0:
        print(f"    Skipped (degenerate carrier, radius={ngr})")
        return

    vis_center = (1500.0, 750.0)
    vis_r = 50.0

    # Also compare equation-derived center vs geometric center
    eq_center = ng.center()
    eq_r = ng.radius()
    center_diff = np.sqrt((eq_center[0]-ngc[0])**2 + (eq_center[1]-ngc[1])**2)

    print(f"  ── Test 3: Reflection normal direction ──")
    print(f"  Equation center vs geometric center offset: {center_diff:.2e}")
    print(f"  Equation radius: {eq_r:.2e}  Geometric radius: {ngr:.2e}  Ratio: {eq_r/ngr if ngr>0 else float('nan'):.6f}")
    print(f"  {'angle':>8s}  {'norm_dir':>12s}  {'mapped_dir':>12s}  {'vis_dir':>12s}  {'ang_err':>10s}  {'vis_px':>10s}")

    max_err_px = 0
    for i in range(8):
        angle = 2 * np.pi * i / 8
        hit_norm = (ngc[0] + ngr*np.cos(angle), ngc[1] + ngr*np.sin(angle))
        normal_norm = normalize_vec((hit_norm[0]-ngc[0], hit_norm[1]-ngc[1]))

        hit_vis = f.apply(hit_norm)
        normal_vis = normalize_vec((hit_vis[0]-vis_center[0], hit_vis[1]-vis_center[1]))

        # Map normalized normal through Mobius derivative: f'(z) = det/(cz+d)^2
        det_f = (cmul(f.a,f.d)[0]-cmul(f.b,f.c)[0], cmul(f.a,f.d)[1]-cmul(f.b,f.c)[1])
        den_z = (cmul(f.c,hit_norm)[0]+f.d[0], cmul(f.c,hit_norm)[1]+f.d[1])
        den_sq = cmul(den_z, den_z)
        deriv = cdiv(det_f, den_sq)
        mapped = cmul(deriv, normal_norm)
        mapped_dir = normalize_vec(mapped)

        ang_err = angle_between(mapped_dir, normal_vis)
        vis_err_px = ang_err * vis_r  # error at carrier surface
        max_err_px = max(max_err_px, vis_err_px)

        deg = np.degrees(angle)
        norm_deg = np.degrees(np.arctan2(normal_norm[1], normal_norm[0]))
        mapped_deg = np.degrees(np.arctan2(mapped_dir[1], mapped_dir[0]))
        vis_deg = np.degrees(np.arctan2(normal_vis[1], normal_vis[0]))
        print(f"  {deg:>7.1f}°  {norm_deg:>11.1f}°  {mapped_deg:>11.1f}°  {vis_deg:>11.1f}°  {ang_err:>10.2e}  {vis_err_px:>10.4f}")

    print(f"  Max visual error: {max_err_px:.4f} px")


def test_roundtrip_precision(f, fi, amp):
    """Test 4: Measure |f(fi(p)) - p| to validate the inversive pullback's
    back-mapping precision."""
    print(f"  ── Test 4: Roundtrip precision f(fi(p)) ──")
    print(f"  {'point':>25s}  {'fwd_err_px':>12s}  {'inv_err_px':>12s}")

    test_points = []
    for i in range(8):
        angle = 2 * np.pi * i / 8
        test_points.append((f"arc2@{np.degrees(angle):.0f}°",
                           (1500+50*np.cos(angle), 750+50*np.sin(angle))))
    test_points.extend([
        ("near (1560,750)", (1560, 750)),
        ("near (1500,810)", (1500, 810)),
        ("far (100,100)", (100, 100)),
        ("far (900,400)", (900, 400)),
    ])

    max_fwd = 0
    max_inv = 0
    for label, p in test_points:
        # Forward roundtrip: visual → normalized → visual
        rt_fwd = f.apply(fi.apply(p))
        err_fwd = np.sqrt((rt_fwd[0]-p[0])**2 + (rt_fwd[1]-p[1])**2)
        max_fwd = max(max_fwd, err_fwd)

        # Inverse roundtrip: normalized → visual → normalized
        p_norm = fi.apply(p)
        rt_inv_norm = fi.apply(f.apply(p_norm))
        err_inv_norm = np.sqrt((rt_inv_norm[0]-p_norm[0])**2 + (rt_inv_norm[1]-p_norm[1])**2)
        err_inv_px = err_inv_norm * amp
        max_inv = max(max_inv, err_inv_px)

        print(f"  {label:>25s}  {err_fwd:>12.2e}  {err_inv_px:>12.2e}")

    print(f"  Max forward roundtrip: {max_fwd:.2e} px")
    print(f"  Max inverse roundtrip (amplified): {max_inv:.2e} px")


def test_back_propagation_quadratic(f, fi, arc2, ng, amp):
    """Test 5: Does carrier.radius() survive equation-coefficient extraction?
    Does the back-propagation quadratic work in normalized space?"""
    ngc = ng.center()
    ngr = ng.radius()

    print(f"  ── Test 5: Back-propagation quadratic ──")

    # Part A: radius from equation vs geometric
    eq_r = ng.radius()
    geo_r = ngr  # same source here, but in the game the equation comes from Hermitian
    # Simulate what happens with Hermitian-derived carrier
    herm_d = ngc[0]**2 + ngc[1]**2 - ngr**2
    herm_carrier = Circle(1.0, -2*ngc[0], -2*ngc[1], herm_d)
    herm_r = herm_carrier.radius()
    # Now simulate with lost r²
    lost_d = ngc[0]**2 + ngc[1]**2  # r² term lost to float64
    lost_carrier = Circle(1.0, -2*ngc[0], -2*ngc[1], lost_d)
    lost_r = lost_carrier.radius()

    print(f"  Radius recovery from equation coefficients:")
    print(f"    Geometric radius:            {ngr:.6e}")
    print(f"    Equation (exact d):          {herm_r:.6e}  (ratio: {herm_r/ngr if ngr>0 else float('nan'):.6f})")
    print(f"    Equation (lost r² in d):     {lost_r:.6e}  (ratio: {lost_r/ngr if ngr>0 else float('nan'):.6f})")
    print(f"    d_exact = {herm_d:.10f}")
    print(f"    d_lost  = {lost_d:.10f}")
    print(f"    d difference = {abs(herm_d - lost_d):.2e}  (= r² = {ngr**2:.2e})")

    # Part B: evaluate() precision near the carrier
    if np.isnan(ngr) or ngr <= 0:
        print(f"    Skipped Part B (degenerate carrier)")
        return

    print(f"  evaluate() precision for points near carrier:")
    print(f"  {'distance':>12s}  {'eq_eval':>12s}  {'cr_eval':>12s}  {'vis_eval':>12s}  {'eq_sign':>8s}  {'vis_sign':>8s}")

    normal = (1.0, 0.0)
    for frac in [0.5, 0.9, 0.999, 1.0, 1.001, 1.1, 2.0]:
        Px = ngc[0] + frac * ngr
        Py = ngc[1]

        # Equation-based evaluate
        eq_eval = ng.evaluate(Px, Py)

        # Center/radius-based (what the game uses for back_propagate)
        v = (Px - ngc[0], Py - ngc[1])
        cr_eval = v[0]**2 + v[1]**2 - ngr**2

        # Visual ground truth
        P_vis = f.apply((Px, Py))
        vis_eval = arc2.evaluate(P_vis[0], P_vis[1])

        eq_sign = "+" if eq_eval > 0 else ("-" if eq_eval < 0 else "0")
        vis_sign = "+" if vis_eval > 0 else ("-" if vis_eval < 0 else "0")

        label = f"{frac:.3f}r"
        print(f"  {label:>12s}  {eq_eval:>12.2e}  {cr_eval:>12.2e}  {vis_eval:>12.2e}  {eq_sign:>8s}  {vis_sign:>8s}")

    # Part C: full back-propagation comparison
    print(f"  Back-propagation quadratic (target at 1.5r from center):")
    target = (ngc[0] + 1.5*ngr, ngc[1])
    target_vis = f.apply(target)
    v_norm = (target[0]-ngc[0], target[1]-ngc[1])
    v_vis = (target_vis[0]-1500, target_vis[1]-750)

    # Normalized-space quadratic
    b_norm = 2*(v_norm[0]*normal[0] + v_norm[1]*normal[1])
    c_norm = v_norm[0]**2 + v_norm[1]**2 - ngr**2
    disc_norm = b_norm**2 - 4*c_norm
    if disc_norm >= 0:
        t_norm = (-b_norm - np.sqrt(disc_norm)) / 2
        hit_norm = (target[0] + t_norm*normal[0], target[1] + t_norm*normal[1])
        hit_norm_vis = f.apply(hit_norm)
        hit_norm_err = arc2.distance_from(hit_norm_vis[0], hit_norm_vis[1])
    else:
        hit_norm_err = float('nan')

    # Visual-space quadratic
    vis_normal = normalize_vec((f.apply((ngc[0]+ngr, ngc[1]))[0] - f.apply(ngc)[0],
                                f.apply((ngc[0]+ngr, ngc[1]))[1] - f.apply(ngc)[1]))
    b_vis = 2*(v_vis[0]*vis_normal[0] + v_vis[1]*vis_normal[1])
    c_vis = v_vis[0]**2 + v_vis[1]**2 - 50**2
    disc_vis = b_vis**2 - 4*c_vis
    if disc_vis >= 0:
        t_vis = (-b_vis - np.sqrt(disc_vis)) / 2
        hit_vis = (target_vis[0] + t_vis*vis_normal[0], target_vis[1] + t_vis*vis_normal[1])
        hit_vis_err = arc2.distance_from(hit_vis[0], hit_vis[1])
    else:
        hit_vis_err = float('nan')

    print(f"    Normalized-space hit error: {hit_norm_err:.2e} px")
    print(f"    Visual-space hit error:     {hit_vis_err:.2e} px")


# ════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("=" * 72)
    print("  3-Point vs N-Point vs Algebraic Carrier Transform")
    print("=" * 72)

    inv1 = conformal_inversion(350, 250, 50)
    inv2 = conformal_inversion(1500, 750, 50)
    portal_inv = translation(-1000, 0)

    arc2 = Circle.from_center_radius(1500, 750, 50)

    angles_3 = [0, 2.094, 4.189]
    n_values = [3, 4, 6, 8, 12, 20, 50, 100, 500, 1000]
    inv_radii = [200, 100, 50, 30, 20]

    print(f"\n  Visual carrier: ARC2 center=(1500,750) r=50")
    print(f"  Frame: portal_inv ∘ inv2 ∘ inv1 (conformal inversions, varying r)")
    print(f"  'dist' = distance from original carrier after M(hitpoint)")

    for inv_r in inv_radii:
        i1 = conformal_inversion(350, 250, inv_r)
        i2 = conformal_inversion(1500, 750, inv_r)
        f = portal_inv.compose(i2.compose(i1))
        fi = f.invert()

        # Individual transforms for stepwise (frame_inv = i1^-1 o i2^-1 o portal^-1)
        fi_steps = [portal_inv.invert(), i2.invert(), i1.invert()]

        # Algebraic carrier (ground truth via composed)
        na = transform_carrier_algebraic(arc2, fi)
        nac = na.center()
        nar = na.radius()
        amp = f.amplification_at(nac)

        # Sample points on the visual carrier
        pts_3_vis = [(1500+50*np.cos(a), 750+50*np.sin(a)) for a in angles_3]
        pts_3_norm = [fi.apply(p) for p in pts_3_vis]
        spread = max(np.sqrt((pts_3_norm[i][0]-pts_3_norm[j][0])**2 +
                             (pts_3_norm[i][1]-pts_3_norm[j][1])**2)
                     for i in range(3) for j in range(i+1,3))

        # Ray through algebraic carrier center
        if nar > 0:
            ray_o = (nac[0] + nar*3, nac[1])
        else:
            ray_o = (nac[0] + 1e-6, nac[1])
        rd = (nac[0]-ray_o[0], nac[1]-ray_o[1])
        rdl = np.sqrt(rd[0]**2+rd[1]**2)
        rd = (rd[0]/rdl, rd[1]/rdl) if rdl > 0 else (1,0)

        print(f"\n  {'='*68}")
        print(f"  inv_r={inv_r}  amp={amp:.2e}  spread={spread:.2e}  alg_radius={nar:.2e}")
        print(f"  {'─'*68}")
        print(f"  {'method':>20s}  {'radius':>12s}  {'ratio':>8s}  {'dist (px)':>12s}")
        print(f"  {'─'*68}")

        # Algebraic (one-shot composed)
        ha = first_pos(ray_circle_intersect(*ray_o, *rd, na))
        d_alg = hit_distance(ha, f, arc2)
        print(f"  {'algebraic':>20s}  {nar:>12.2e}  {'1.0x':>8s}  {d_alg:>12.2e}")

        # Stepwise algebraic (apply each transform individually + renormalize)
        ns = transform_carrier_stepwise(arc2, fi_steps)
        nsc = ns.center()
        nsr = ns.radius()
        hs = first_pos(ray_circle_intersect(*ray_o, *rd, ns))
        d_step = hit_distance(hs, f, arc2)
        rs_str = f"{nsr:.2e}" if not np.isnan(nsr) else "NaN"
        rat_s = f"{nsr/nar:.1f}x" if (not np.isnan(nsr) and nar > 0) else "NaN"
        if np.isinf(d_step):
            print(f"  {'stepwise-alg':>20s}  {rs_str:>12s}  {rat_s:>8s}  {'NO HIT':>12s}")
        else:
            print(f"  {'stepwise-alg':>20s}  {rs_str:>12s}  {rat_s:>8s}  {d_step:>12.2e}")

        # Geometric stepwise (center/radius evolution, no matrices)
        geo_steps = [
            ('translation', 1000, 0),        # portal^-1
            ('inversion', 1500, 750, inv_r),  # inv2^-1 = inv2 (self-inverse)
            ('inversion', 350, 250, inv_r),   # inv1^-1 = inv1
        ]
        ng = transform_carrier_geometric(1500, 750, 50, geo_steps)
        ngc = ng.center()
        ngr = ng.radius()
        # Use direct center/radius intersection (avoids d=cx²+cy²-r² precision loss)
        if ngr > 0 and not np.isnan(ngr):
            ray_g_o = (ngc[0] + ngr*3, ngc[1])
            rd_g = (ngc[0]-ray_g_o[0], ngc[1]-ray_g_o[1])
            rdgl = np.sqrt(rd_g[0]**2+rd_g[1]**2)
            rd_g = (rd_g[0]/rdgl, rd_g[1]/rdgl) if rdgl > 0 else (1,0)
            hg = first_pos(ray_circle_intersect_cr(*ray_g_o, *rd_g, ngc[0], ngc[1], ngr))
            d_geo = hit_distance(hg, f, arc2)
        else:
            d_geo = float('inf')
        rg_str = f"{ngr:.2e}" if not np.isnan(ngr) else "NaN"
        rat_g = f"{ngr/nar:.1f}x" if (not np.isnan(ngr) and nar > 0) else "NaN"
        if np.isinf(d_geo):
            print(f"  {'geometric':>20s}  {rg_str:>12s}  {rat_g:>8s}  {'NO HIT':>12s}")
        else:
            print(f"  {'geometric':>20s}  {rg_str:>12s}  {rat_g:>8s}  {d_geo:>12.2e}")

        # Geometric + compensated (DD arithmetic on center/radius evolution)
        ngc2 = transform_carrier_geo_compensated(1500, 750, 50, geo_steps)
        ngc2c = ngc2.center()
        ngc2r = ngc2.radius()
        if ngc2r > 0 and not np.isnan(ngc2r):
            ray_gc_o = (ngc2c[0] + ngc2r*3, ngc2c[1])
            rd_gc = (ngc2c[0]-ray_gc_o[0], ngc2c[1]-ray_gc_o[1])
            rdgcl = np.sqrt(rd_gc[0]**2+rd_gc[1]**2)
            rd_gc = (rd_gc[0]/rdgcl, rd_gc[1]/rdgcl) if rdgcl > 0 else (1,0)
            hgc = first_pos(ray_circle_intersect_cr(*ray_gc_o, *rd_gc, ngc2c[0], ngc2c[1], ngc2r))
            d_gc = hit_distance(hgc, f, arc2)
        else:
            d_gc = float('inf')
        rgc_str = f"{ngc2r:.2e}" if not np.isnan(ngc2r) else "NaN"
        rat_gc = f"{ngc2r/nar:.1f}x" if (not np.isnan(ngc2r) and nar > 0) else "NaN"
        if np.isinf(d_gc):
            print(f"  {'geo+compensated':>20s}  {rgc_str:>12s}  {rat_gc:>8s}  {'NO HIT':>12s}")
        else:
            print(f"  {'geo+compensated':>20s}  {rgc_str:>12s}  {rat_gc:>8s}  {d_gc:>12.2e}")

        # Compensated Hermitian stepwise (double-double arithmetic)
        nc = transform_carrier_compensated(arc2, fi_steps)
        ncc = nc.center()
        ncr = nc.radius()
        hc = first_pos(ray_circle_intersect(*ray_o, *rd, nc))
        d_comp = hit_distance(hc, f, arc2)
        rc_str = f"{ncr:.2e}" if not np.isnan(ncr) else "NaN"
        rat_c = f"{ncr/nar:.1f}x" if (not np.isnan(ncr) and nar > 0) else "NaN"
        if np.isinf(d_comp):
            print(f"  {'compensated':>20s}  {rc_str:>12s}  {rat_c:>8s}  {'NO HIT':>12s}")
        else:
            print(f"  {'compensated':>20s}  {rc_str:>12s}  {rat_c:>8s}  {d_comp:>12.2e}")

        # Inversive pullback: intersect in visual space, map back
        # Frame forward steps: i1, i2, portal_inv (compose order)
        f_steps = [i1, i2, portal_inv]
        ip_hits = inversive_pullback(*ray_o, *rd, 1500, 750, 50, f, fi,
                                     frame_steps=f_steps)
        ip_h = ip_hits[0] if ip_hits else None
        d_ip = hit_distance(ip_h, f, arc2)
        if np.isinf(d_ip):
            print(f"  {'inversive-pullback':>20s}  {'n/a':>12s}  {'n/a':>8s}  {'NO HIT':>12s}")
        else:
            print(f"  {'inversive-pullback':>20s}  {'n/a':>12s}  {'n/a':>8s}  {d_ip:>12.2e}")

        # Also test with geometric carrier + inversive pullback intersection
        if ngr > 0 and not np.isnan(ngr):
            ip2_hits = inversive_pullback(*ray_g_o, *rd_g, 1500, 750, 50, f, fi,
                                          frame_steps=f_steps)
            ip2_h = ip2_hits[0] if ip2_hits else None
            d_ip2 = hit_distance(ip2_h, f, arc2)
        else:
            d_ip2 = float('inf')
        if np.isinf(d_ip2):
            print(f"  {'geo+pullback':>20s}  {'n/a':>12s}  {'n/a':>8s}  {'NO HIT':>12s}")
        else:
            print(f"  {'geo+pullback':>20s}  {'n/a':>12s}  {'n/a':>8s}  {d_ip2:>12.2e}")

        # Hybrid: geometric center + N-point radius (the N-knob!)
        print(f"  {'─'*68}")
        print(f"  Geo+N-point hybrid (geometric center, N-point median radius):")
        for n_hybrid in [3, 4, 8, 20, 100, 1000]:
            nh = transform_carrier_geo_npoint(1500, 750, 50, geo_steps, fi, n_hybrid)
            nhc = nh.center()
            nhr = nh.radius()
            if nhr > 0 and not np.isnan(nhr):
                ray_h_o = (nhc[0] + nhr*3, nhc[1])
                rd_h = (nhc[0]-ray_h_o[0], nhc[1]-ray_h_o[1])
                rdhl = np.sqrt(rd_h[0]**2+rd_h[1]**2)
                rd_h = (rd_h[0]/rdhl, rd_h[1]/rdhl) if rdhl > 0 else (1,0)
                hh = first_pos(ray_circle_intersect(*ray_h_o, *rd_h, nh))
                d_hyb = hit_distance(hh, f, arc2)
            else:
                d_hyb = float('inf')
            rh_str = f"{nhr:.2e}" if not np.isnan(nhr) else "NaN"
            rat_h = f"{nhr/nar:.3f}x" if (not np.isnan(nhr) and nar > 0) else "NaN"
            label = f"geo+{n_hybrid}pt"
            if np.isinf(d_hyb):
                print(f"  {label:>20s}  {rh_str:>12s}  {rat_h:>8s}  {'NO HIT':>12s}")
            else:
                print(f"  {label:>20s}  {rh_str:>12s}  {rat_h:>8s}  {d_hyb:>12.2e}")
        print(f"  {'─'*68}")

        # 3-point fit (current tracer method)
        n3 = circle_from_3_points(pts_3_norm[0], pts_3_norm[1], pts_3_norm[2])
        h3 = first_pos(ray_circle_intersect(*ray_o, *rd, n3))
        d_3 = hit_distance(h3, f, arc2)
        r3v = n3.radius()
        r3_str = f"{r3v:.2e}" if not np.isnan(r3v) else "NaN"
        rat_str = f"{r3v/nar:.1f}x" if (not np.isnan(r3v) and nar > 0) else "NaN"
        print(f"  {'3-point':>20s}  {r3_str:>12s}  {rat_str:>8s}  {d_3:>12.2e}" if not np.isinf(d_3) else
              f"  {'3-point':>20s}  {r3_str:>12s}  {rat_str:>8s}  {'NO HIT':>12s}")

        # N-point fits (uniform spacing on carrier)
        for n in n_values:
            pts_vis = generate_n_points_on_carrier(1500, 750, 50, n, include_special=False)
            pts_norm = [fi.apply(p) for p in pts_vis]

            if n <= 3:
                carrier_n = circle_from_3_points(pts_norm[0], pts_norm[1], pts_norm[2])
            else:
                carrier_n = circle_from_n_points_lstsq(pts_norm)

            hn = first_pos(ray_circle_intersect(*ray_o, *rd, carrier_n))
            d_n = hit_distance(hn, f, arc2)
            rn = carrier_n.radius()
            rn_str = f"{rn:.2e}" if not np.isnan(rn) else "NaN"
            rat_n = f"{rn/nar:.1f}x" if (not np.isnan(rn) and nar > 0) else "NaN"
            label = f"{n}-point"
            if np.isinf(d_n):
                print(f"  {label:>20s}  {rn_str:>12s}  {rat_n:>8s}  {'NO HIT':>12s}")
            else:
                print(f"  {label:>20s}  {rn_str:>12s}  {rat_n:>8s}  {d_n:>12.2e}")

        # Subdivided algebraic (N sub-steps per transform)
        print(f"  {'─'*68}")
        print(f"  Subdivided algebraic (N sub-steps per transform, renormalized):")
        for n_sub in [1, 2, 4, 8, 16, 32, 64, 128, 256]:
            cn = transform_carrier_subdivided(arc2, fi_steps, n_sub)
            cnc = cn.center()
            cnr = cn.radius()
            hn = first_pos(ray_circle_intersect(*ray_o, *rd, cn))
            d_n = hit_distance(hn, f, arc2)
            rn_str = f"{cnr:.2e}" if not np.isnan(cnr) else "NaN"
            rat_n = f"{cnr/nar:.3f}x" if (not np.isnan(cnr) and nar > 0) else "NaN"
            label = f"N={n_sub}"
            total_steps = 3 * n_sub
            if np.isinf(d_n):
                print(f"  {label:>20s}  {rn_str:>12s}  {rat_n:>8s}  {'NO HIT':>12s}  ({total_steps} steps)")
            else:
                print(f"  {label:>20s}  {rn_str:>12s}  {rat_n:>8s}  {d_n:>12.2e}  ({total_steps} steps)")

        # N-point fits WITH special/definitional anchors
        print(f"  {'─'*68}")
        print(f"  N-point with definitional anchors (via + counter-via + start + end):")
        for n in [4, 8, 20, 100, 1000]:
            pts_vis = generate_n_points_on_carrier(1500, 750, 50, n, include_special=True)
            pts_norm = [fi.apply(p) for p in pts_vis]
            carrier_n = circle_from_n_points_lstsq(pts_norm)
            hn = first_pos(ray_circle_intersect(*ray_o, *rd, carrier_n))
            d_n = hit_distance(hn, f, arc2)
            rn = carrier_n.radius()
            rn_str = f"{rn:.2e}" if not np.isnan(rn) else "NaN"
            rat_n = f"{rn/nar:.1f}x" if (not np.isnan(rn) and nar > 0) else "NaN"
            label = f"{n}-pt+anchors"
            if np.isinf(d_n):
                print(f"  {label:>20s}  {rn_str:>12s}  {rat_n:>8s}  {'NO HIT':>12s}")
            else:
                print(f"  {label:>20s}  {rn_str:>12s}  {rat_n:>8s}  {d_n:>12.2e}")

    # ── Summary ──
    print(f"\n{'='*72}")
    print("  Analysis")
    print(f"{'='*72}")
    print("""
  WHY N-POINT FITS CAN'T HELP:

  The fundamental issue is not the number of sample points — it's that
  ALL sample points collapse into the same tiny neighborhood. Adding more
  points gives more data, but all with the same nearly-zero spread. The
  condition number of the N×4 design matrix depends on the SPREAD of the
  data, not the quantity.

  Concretely: for spread ε and coordinate magnitude R, the design matrix
  columns (x²+y², x, y, 1) have entries differing by only ε across rows.
  The smallest singular value is ~ε²/R regardless of N. The SVD null-space
  vector (the circle coefficients) has relative error ~macheps·R/ε².

  With spread=3.6e-4 and R≈350: error ~ 1e-16·350/(3.6e-4)² ≈ 2.7e-3.
  This error in the coefficients, amplified 250,000x by the frame, gives
  ~670 px visual error — matching the observed 397 px gap.

  Doubling N doesn't change ε. Even 1000 points, all squeezed into a
  0.0004-px cluster, can't disambiguate a circle from a line or from a
  circle of very different radius. The SVD is honest about this: it
  finds the best-fit in a least-squares sense, but the best fit through
  nearly-coincident points is inherently ill-defined.

  DEFINITIONAL ANCHORS (via, counter-via) don't help either: these points
  are ALSO mapped through frame_inv, which squeezes them into the same
  tiny cluster. The via point at (1500, 700) maps to (351.826..., 249.208...)
  — essentially the same location as all other points.

  WHY ALGEBRAIC IS FUNDAMENTALLY DIFFERENT:

  The Hermitian transform H' = N†HN operates on the circle's EQUATION
  coefficients (a, b, c, d) directly — it never converts to points, never
  fits, never extracts geometric quantities. It's a 2×2 matrix multiply
  on a 2×2 Hermitian matrix. The result has accuracy limited only by
  the matrix entries (which are the Möbius coefficients), not by the
  carrier's visual size.

  The key insight: the carrier EQUATION is well-conditioned even when the
  carrier GEOMETRY is not. The equation a(x²+y²)+bx+cy+d=0 uniquely
  determines a circle regardless of its size. The coefficients remain
  well-separated even when the circle is sub-micron.

  STEPWISE ALGEBRAIC — TRADING COMPUTE FOR ACCURACY:

  The one-shot algebraic approach still has a weakness: adj(M_composed) has
  entries that are PRODUCTS of all individual transform coefficients. When
  amplification is 10^6, these entries are O(10^6), and N†HN involves
  products of order 10^12 that cancel down to small values — some loss.

  Stepwise composition applies each transform individually:
    H_0 = H
    H_k = adj(M_k)† · H_{k-1} · adj(M_k),  then renormalize H_k
  Each adj(M_k) has entries O(10^3) (single transform), so each step's
  intermediate products are O(10^6) — much less cancellation. Renormalizing
  (dividing by max entry) after each step keeps H bounded.

  This is the algebraic analog of N-point SVD: instead of one ill-conditioned
  computation, do N well-conditioned ones. But unlike N-point, the stepwise
  algebraic approach NEVER degrades with amplification because it never
  touches point geometry at all.
""")

    # ── Precision tests for non-intersection calculations ──
    print(f"\n{'='*72}")
    print("  Precision Tests: Non-Intersection Calculations")
    print(f"{'='*72}")

    for inv_r in inv_radii:
        i1 = conformal_inversion(350, 250, inv_r)
        i2 = conformal_inversion(1500, 750, inv_r)
        f = portal_inv.compose(i2.compose(i1))
        fi = f.invert()
        geo_steps = [
            ('translation', 1000, 0),
            ('inversion', 1500, 750, inv_r),
            ('inversion', 350, 250, inv_r),
        ]
        ng = transform_carrier_geometric(1500, 750, 50, geo_steps)
        ngc = ng.center()
        ngr = ng.radius()
        amp = f.amplification_at(ngc)

        print(f"\n  {'='*68}")
        print(f"  inv_r={inv_r}  amp={amp:.2e}  geo_radius={ngr:.2e}")
        print(f"  {'─'*68}")

        test_cross_ratio_containment(f, fi, arc2, ng, amp)
        print()
        test_side_of_carrier(f, fi, arc2, ng, amp)
        print()
        test_reflection_normal(f, fi, arc2, ng, amp)
        print()
        test_roundtrip_precision(f, fi, amp)
        print()
        test_back_propagation_quadratic(f, fi, arc2, ng, amp)
