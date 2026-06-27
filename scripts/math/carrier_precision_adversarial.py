"""
Adversarial precision optimizer: finds worst-case geometry configurations
for each precision-sensitive calculation in the tracer pipeline.

Uses scipy.optimize.differential_evolution for global optimization,
with numpy-only LHS+Nelder-Mead as fallback.
"""

import sys
import os
import argparse
import csv
import time
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carrier_precision_poc import (
    Mobius, Circle, conformal_inversion, translation,
    transform_carrier_geometric, inversive_pullback,
    circle_circle_intersect, ray_circle_intersect_cr,
    hdet, cross_ratio_containment, normalize_vec, angle_between,
    cmul, cdiv, cconj,
)

try:
    from scipy.optimize import differential_evolution
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False


# ── Parameter bounds ──

GEOM_BOUNDS_2 = [
    (100, 1800),   # cx1
    (100, 1000),   # cy1
    (5, 500),      # r1
    (100, 1800),   # cx2
    (100, 1000),   # cy2
    (5, 500),      # r2
    (-2000, 2000), # tx
    (-2000, 2000), # ty
]
GEOM_NAMES_2 = ['cx1', 'cy1', 'r1', 'cx2', 'cy2', 'r2', 'tx', 'ty']


def geom_bounds_for_depth(n_inv):
    bounds = []
    names = []
    for k in range(n_inv):
        bounds.extend([(100, 1800), (100, 1000), (5, 500)])
        names.extend([f'cx{k+1}', f'cy{k+1}', f'r{k+1}'])
    bounds.extend([(-2000, 2000), (-2000, 2000)])
    names.extend(['tx', 'ty'])
    return bounds, names


# ── Frame construction ──

def build_frame(x, n_inv=2):
    inversions = []
    geo_steps = []
    idx = 0
    for k in range(n_inv):
        cx, cy, r = x[idx], x[idx+1], x[idx+2]
        inversions.append(conformal_inversion(cx, cy, r))
        idx += 3
    tx, ty = x[idx], x[idx+1]
    portal = translation(tx, ty)

    f = portal
    for inv in reversed(inversions):
        f = f.compose(inv)
    fi = f.invert()

    # geo_steps for frame_inv: portal^-1, then inversions in reverse
    geo_steps.append(('translation', -tx, -ty))
    for k in range(n_inv - 1, -1, -1):
        cx, cy, r = x[k*3], x[k*3+1], x[k*3+2]
        geo_steps.append(('inversion', cx, cy, r))

    # visual carrier = last inversion's circle
    last_idx = (n_inv - 1) * 3
    vis_cx, vis_cy, vis_r = x[last_idx], x[last_idx+1], x[last_idx+2]

    return f, fi, geo_steps, inversions, portal, vis_cx, vis_cy, vis_r


def get_normalized_carrier(x, n_inv=2):
    _, _, geo_steps, _, _, vis_cx, vis_cy, vis_r = build_frame(x, n_inv)
    ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
    return ng


# ── Validity check ──

def is_valid(x, n_inv=2):
    try:
        f, fi, geo_steps, _, _, vis_cx, vis_cy, vis_r = build_frame(x, n_inv)
        ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
        ngr = ng.radius()
        if np.isnan(ngr) or ngr <= 0:
            return False
        ngc = ng.center()
        amp = f.amplification_at(ngc)
        if np.isnan(amp) or np.isinf(amp) or amp <= 1.0:
            return False
        return True
    except Exception:
        return False


# ── Objective functions ──
# Each takes a flat parameter vector x and returns a scalar to MINIMIZE
# (differential_evolution minimizes, so we negate the error to maximize it).

def obj_inversive_pullback(x, n_inv=2):
    """Maximize visual-space distance of inversive pullback hit from carrier."""
    try:
        f, fi, geo_steps, inversions, portal, vis_cx, vis_cy, vis_r = build_frame(x, n_inv)
        ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
        ngc = ng.center()
        ngr = ng.radius()
        if np.isnan(ngr) or ngr <= 0:
            return 0.0

        angle = x[-1] if len(x) > n_inv * 3 + 2 else 0.0
        ray_ox = ngc[0] + ngr * 3 * np.cos(angle + np.pi)
        ray_oy = ngc[1] + ngr * 3 * np.sin(angle + np.pi)
        rd = normalize_vec((ngc[0] - ray_ox, ngc[1] - ray_oy))
        if rd[0] == 0 and rd[1] == 0:
            return 0.0

        f_steps = list(inversions) + [portal]
        ip_hits = inversive_pullback(ray_ox, ray_oy, rd[0], rd[1],
                                     vis_cx, vis_cy, vis_r, f, fi,
                                     frame_steps=f_steps)
        if not ip_hits:
            return 0.0

        hit = ip_hits[0]
        vis_pt = f.apply((hit[1], hit[2]))
        arc2 = Circle.from_center_radius(vis_cx, vis_cy, vis_r)
        err = arc2.distance_from(vis_pt[0], vis_pt[1])
        if np.isnan(err) or np.isinf(err):
            return 0.0
        return -err  # negate for minimization
    except Exception:
        return 0.0


def obj_cross_ratio(x, n_inv=2):
    """Minimize |product_x| to find near-sign-flip cases for cross-ratio."""
    try:
        f, fi, geo_steps, _, _, vis_cx, vis_cy, vis_r = build_frame(x, n_inv)
        ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
        ngc = ng.center()
        ngr = ng.radius()
        if np.isnan(ngr) or ngr <= 0:
            return 1e30
        amp = f.amplification_at(ngc)
        if np.isnan(amp) or np.isinf(amp) or amp <= 10.0:
            return 1e30

        n_geom = n_inv * 3 + 2
        arc_start = x[n_geom] if len(x) > n_geom + 1 else 0.0
        arc_end = x[n_geom + 1] if len(x) > n_geom + 1 else np.pi
        # Ensure arc has reasonable span (at least 30 degrees)
        if abs(arc_end - arc_start) < 0.5 or abs(arc_end - arc_start) > 5.8:
            return 1e30

        S_vis = (vis_cx + vis_r * np.cos(arc_start), vis_cy + vis_r * np.sin(arc_start))
        E_vis = (vis_cx + vis_r * np.cos(arc_end), vis_cy + vis_r * np.sin(arc_end))
        mid_angle = (arc_start + arc_end) / 2
        V_vis = (vis_cx + vis_r * np.cos(mid_angle), vis_cy + vis_r * np.sin(mid_angle))

        S_norm = fi.apply(S_vis)
        E_norm = fi.apply(E_vis)
        V_norm = fi.apply(V_vis)

        mismatches = 0
        min_abs_px = float('inf')
        for i in range(32):
            angle = 2 * np.pi * i / 32
            P_vis = (vis_cx + vis_r * np.cos(angle), vis_cy + vis_r * np.sin(angle))
            P_norm = fi.apply(P_vis)
            norm_result, norm_px = cross_ratio_containment(S_norm, P_norm, E_norm, V_norm)
            vis_result, _ = cross_ratio_containment(S_vis, P_vis, E_vis, V_vis)
            if norm_result != vis_result:
                mismatches += 1
            if abs(norm_px) > 0:
                min_abs_px = min(min_abs_px, abs(norm_px))

        if mismatches > 0:
            return -(1e6 + mismatches)
        if min_abs_px == float('inf') or min_abs_px == 0:
            return 1e30
        return min_abs_px  # minimize = find smallest |product_x|
    except Exception:
        return 1e30


def obj_evaluate_sign(x, n_inv=2):
    """Maximize sign mismatch count for carrier.evaluate()."""
    try:
        f, fi, geo_steps, _, _, vis_cx, vis_cy, vis_r = build_frame(x, n_inv)
        ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
        ngc = ng.center()
        ngr = ng.radius()
        if np.isnan(ngr) or ngr <= 0:
            return 0.0
        amp = f.amplification_at(ngc)
        if np.isnan(amp) or np.isinf(amp) or amp <= 1.0:
            return 0.0
        arc2 = Circle.from_center_radius(vis_cx, vis_cy, vis_r)

        mismatches = 0
        for i in range(16):
            angle = 2 * np.pi * i / 16
            for frac in [0.999, 1.001]:
                Px = ngc[0] + frac * ngr * np.cos(angle)
                Py = ngc[1] + frac * ngr * np.sin(angle)
                norm_eval = ng.evaluate(Px, Py)
                P_vis = f.apply((Px, Py))
                vis_eval = arc2.evaluate(P_vis[0], P_vis[1])
                if (norm_eval > 0) != (vis_eval > 0):
                    mismatches += 1
        return -mismatches  # negate for minimization
    except Exception:
        return 0.0


def obj_reflection_normal(x, n_inv=2):
    """Maximize angular error of reflection normal direction (in pixels)."""
    try:
        f, fi, geo_steps, _, _, vis_cx, vis_cy, vis_r = build_frame(x, n_inv)
        ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
        ngc = ng.center()
        ngr = ng.radius()
        if np.isnan(ngr) or ngr <= 0:
            return 0.0
        amp = f.amplification_at(ngc)
        if np.isnan(amp) or np.isinf(amp) or amp <= 1.0:
            return 0.0

        angle = x[-1] if len(x) > n_inv * 3 + 2 else 0.0
        hit_norm = (ngc[0] + ngr * np.cos(angle), ngc[1] + ngr * np.sin(angle))
        normal_norm = normalize_vec((hit_norm[0] - ngc[0], hit_norm[1] - ngc[1]))

        hit_vis = f.apply(hit_norm)
        normal_vis = normalize_vec((hit_vis[0] - vis_cx, hit_vis[1] - vis_cy))

        det_f = (cmul(f.a, f.d)[0] - cmul(f.b, f.c)[0],
                 cmul(f.a, f.d)[1] - cmul(f.b, f.c)[1])
        den_z = (cmul(f.c, hit_norm)[0] + f.d[0],
                 cmul(f.c, hit_norm)[1] + f.d[1])
        den_sq = cmul(den_z, den_z)
        deriv = cdiv(det_f, den_sq)
        mapped = cmul(deriv, normal_norm)
        mapped_dir = normalize_vec(mapped)
        if mapped_dir[0] == 0 and mapped_dir[1] == 0:
            return 0.0

        ang_err = angle_between(mapped_dir, normal_vis)
        # Conformal inversions reverse orientation — an odd number of
        # inversions flips the normal direction. This is expected, not
        # a precision error. Take the minimum to handle both cases.
        ang_err = min(ang_err, np.pi - ang_err)
        vis_err_px = ang_err * vis_r
        if np.isnan(vis_err_px) or np.isinf(vis_err_px):
            return 0.0
        return -vis_err_px
    except Exception:
        return 0.0


def obj_roundtrip(x, n_inv=2):
    """Maximize |f(fi(p)) - p| roundtrip error."""
    try:
        f, fi, geo_steps, _, _, vis_cx, vis_cy, vis_r = build_frame(x, n_inv)
        ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
        ngr = ng.radius()
        if np.isnan(ngr) or ngr <= 0:
            return 0.0
        amp = f.amplification_at(ng.center())
        if np.isnan(amp) or np.isinf(amp) or amp <= 1.0:
            return 0.0

        angle = x[-1] if len(x) > n_inv * 3 + 2 else 0.0
        p = (vis_cx + vis_r * np.cos(angle), vis_cy + vis_r * np.sin(angle))
        rt = f.apply(fi.apply(p))
        err = np.sqrt((rt[0] - p[0])**2 + (rt[1] - p[1])**2)
        if np.isnan(err) or np.isinf(err):
            return 0.0
        return -err
    except Exception:
        return 0.0


def obj_back_propagation(x, n_inv=2):
    """Maximize visual error of normalized-space back-propagation quadratic."""
    try:
        f, fi, geo_steps, _, _, vis_cx, vis_cy, vis_r = build_frame(x, n_inv)
        ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
        ngc = ng.center()
        ngr = ng.radius()
        if np.isnan(ngr) or ngr <= 0:
            return 0.0
        arc2 = Circle.from_center_radius(vis_cx, vis_cy, vis_r)

        angle = x[-1] if len(x) > n_inv * 3 + 2 else 0.0
        target = (ngc[0] + 1.5 * ngr * np.cos(angle),
                  ngc[1] + 1.5 * ngr * np.sin(angle))
        normal = (np.cos(angle), np.sin(angle))

        v = (target[0] - ngc[0], target[1] - ngc[1])
        b_coeff = 2 * (v[0] * normal[0] + v[1] * normal[1])
        c_coeff = v[0]**2 + v[1]**2 - ngr**2
        disc = b_coeff**2 - 4 * c_coeff
        if disc < 0:
            return 0.0
        t = (-b_coeff - np.sqrt(disc)) / 2
        hit = (target[0] + t * normal[0], target[1] + t * normal[1])
        hit_vis = f.apply(hit)
        err = arc2.distance_from(hit_vis[0], hit_vis[1])
        if np.isnan(err) or np.isinf(err):
            return 0.0
        return -err
    except Exception:
        return 0.0


# ── Numpy-only optimizers (fallback) ──

def latin_hypercube(n_samples, bounds, rng):
    n_dims = len(bounds)
    samples = np.zeros((n_samples, n_dims))
    for d in range(n_dims):
        perm = rng.permutation(n_samples)
        intervals = np.linspace(0, 1, n_samples + 1)
        for i in range(n_samples):
            lo = intervals[perm[i]]
            hi = intervals[perm[i] + 1]
            u = rng.uniform(lo, hi)
            samples[i, d] = bounds[d][0] + (bounds[d][1] - bounds[d][0]) * u
    return samples


def nelder_mead(objective, x0, bounds, maxiter=300):
    n = len(x0)
    lo = np.array([b[0] for b in bounds])
    hi = np.array([b[1] for b in bounds])

    simplex = np.zeros((n + 1, n))
    simplex[0] = x0
    for i in range(n):
        simplex[i + 1] = x0.copy()
        simplex[i + 1][i] += 0.05 * (hi[i] - lo[i])
        simplex[i + 1] = np.clip(simplex[i + 1], lo, hi)

    values = np.array([objective(s) for s in simplex])

    for _ in range(maxiter):
        order = np.argsort(values)
        simplex = simplex[order]
        values = values[order]

        centroid = simplex[:-1].mean(axis=0)

        # Reflect
        xr = np.clip(centroid + (centroid - simplex[-1]), lo, hi)
        fr = objective(xr)
        if values[0] <= fr < values[-2]:
            simplex[-1] = xr
            values[-1] = fr
            continue

        # Expand
        if fr < values[0]:
            xe = np.clip(centroid + 2 * (xr - centroid), lo, hi)
            fe = objective(xe)
            if fe < fr:
                simplex[-1] = xe
                values[-1] = fe
            else:
                simplex[-1] = xr
                values[-1] = fr
            continue

        # Contract
        xc = np.clip(centroid + 0.5 * (simplex[-1] - centroid), lo, hi)
        fc = objective(xc)
        if fc < values[-1]:
            simplex[-1] = xc
            values[-1] = fc
            continue

        # Shrink
        for i in range(1, n + 1):
            simplex[i] = np.clip(simplex[0] + 0.5 * (simplex[i] - simplex[0]), lo, hi)
            values[i] = objective(simplex[i])

    best_idx = np.argmin(values)
    return simplex[best_idx], values[best_idx]


def find_worst_case_numpy(objective, bounds, n_global=2000, n_local_starts=10,
                          n_local_iter=300, rng=None):
    if rng is None:
        rng = np.random.default_rng(42)
    samples = latin_hypercube(n_global, bounds, rng)
    scores = np.array([objective(s) for s in samples])

    order = np.argsort(scores)
    top_k = order[:n_local_starts]

    best_score = float('inf')
    best_x = None
    for idx in top_k:
        x_opt, score = nelder_mead(objective, samples[idx], bounds, n_local_iter)
        if score < best_score:
            best_score = score
            best_x = x_opt

    return best_x, best_score


# ── Amplification-constrained optimization ──

def make_amp_constrained(objective, n_inv, target_log_amp):
    def constrained(x):
        try:
            f, fi, geo_steps, _, _, vis_cx, vis_cy, vis_r = build_frame(x, n_inv)
            ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
            ngc = ng.center()
            ngr = ng.radius()
            if np.isnan(ngr) or ngr <= 0:
                return 0.0
            amp = f.amplification_at(ngc)
            if np.isnan(amp) or np.isinf(amp) or amp <= 1.0:
                return 0.0
            log_amp = np.log10(amp)
            penalty = abs(log_amp - target_log_amp)
            if penalty > 0.5:
                return 0.0
            raw = objective(x)
            return raw - 100 * penalty
        except Exception:
            return 0.0
    return constrained


# ── Main optimization driver ──

TEST_DEFS = [
    {
        'name': 'inversive_pullback',
        'func': obj_inversive_pullback,
        'extra_bounds': [(0, 2 * np.pi)],  # point_angle
        'extra_names': ['angle'],
        'unit': 'px',
    },
    {
        'name': 'cross_ratio',
        'func': obj_cross_ratio,
        'extra_bounds': [(0, 2 * np.pi), (0, 2 * np.pi)],  # arc_start, arc_end
        'extra_names': ['arc_start', 'arc_end'],
        'unit': 'product_x',
    },
    {
        'name': 'evaluate_sign',
        'func': obj_evaluate_sign,
        'extra_bounds': [],
        'extra_names': [],
        'unit': 'mismatches/32',
    },
    {
        'name': 'reflection_normal',
        'func': obj_reflection_normal,
        'extra_bounds': [(0, 2 * np.pi)],
        'extra_names': ['angle'],
        'unit': 'px',
    },
    {
        'name': 'roundtrip',
        'func': obj_roundtrip,
        'extra_bounds': [(0, 2 * np.pi)],
        'extra_names': ['angle'],
        'unit': 'px',
    },
    {
        'name': 'back_propagation',
        'func': obj_back_propagation,
        'extra_bounds': [(0, 2 * np.pi)],
        'extra_names': ['angle'],
        'unit': 'px',
    },
]


def run_test(test_def, n_inv, n_samples, seed):
    geom_bounds, geom_names = geom_bounds_for_depth(n_inv)
    bounds = geom_bounds + test_def['extra_bounds']
    names = geom_names + test_def['extra_names']

    obj = lambda x: test_def['func'](x, n_inv=n_inv)

    rng = np.random.default_rng(seed)
    t0 = time.time()

    if HAS_SCIPY:
        result = differential_evolution(
            obj, bounds, seed=seed, maxiter=200, popsize=30,
            tol=1e-10, polish=True, disp=False
        )
        best_x = result.x
        best_score = result.fun
    else:
        best_x, best_score = find_worst_case_numpy(
            obj, bounds, n_global=n_samples, n_local_starts=10, rng=rng
        )

    elapsed = time.time() - t0

    # Extract results
    f, fi, geo_steps, _, _, vis_cx, vis_cy, vis_r = build_frame(best_x, n_inv)
    ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
    ngc = ng.center()
    ngr = ng.radius()
    amp = f.amplification_at(ngc) if ngr > 0 and not np.isnan(ngr) else float('nan')

    error = -best_score  # un-negate
    if test_def['name'] == 'cross_ratio':
        if best_score < -1e5:
            error = int(-best_score - 1e6)  # mismatch count
        else:
            error = best_score  # min |product_x| (already positive)

    return {
        'test': test_def['name'],
        'depth': n_inv,
        'error': error,
        'amp': amp,
        'params': dict(zip(names, best_x)),
        'elapsed': elapsed,
        'unit': test_def['unit'],
    }


def run_amp_sweep(test_def, n_inv, seed):
    geom_bounds, geom_names = geom_bounds_for_depth(n_inv)
    bounds = geom_bounds + test_def['extra_bounds']
    names = geom_names + test_def['extra_names']

    amp_targets = [3, 4, 5, 6, 7]  # log10
    results = []
    for target_log in amp_targets:
        obj = make_amp_constrained(
            lambda x: test_def['func'](x, n_inv=n_inv),
            n_inv, target_log
        )

        if HAS_SCIPY:
            result = differential_evolution(
                obj, bounds, seed=seed, maxiter=150, popsize=20,
                tol=1e-10, polish=True, disp=False
            )
            best_x, best_score = result.x, result.fun
        else:
            rng = np.random.default_rng(seed)
            best_x, best_score = find_worst_case_numpy(
                obj, bounds, n_global=1000, n_local_starts=5, rng=rng
            )

        f, fi, geo_steps, _, _, vis_cx, vis_cy, vis_r = build_frame(best_x, n_inv)
        ng = transform_carrier_geometric(vis_cx, vis_cy, vis_r, geo_steps)
        ngc = ng.center()
        ngr = ng.radius()
        amp = f.amplification_at(ngc) if ngr > 0 else float('nan')

        raw_error = test_def['func'](best_x, n_inv=n_inv)
        error = -raw_error if test_def['name'] != 'cross_ratio' else raw_error

        results.append({
            'target_amp': 10**target_log,
            'actual_amp': amp,
            'error': error,
            'params': dict(zip(names, best_x)),
        })

    return results


# ── Reporting ──

def print_result(r):
    print(f"\n  === {r['test']} (depth={r['depth']}) ===")
    if r['test'] == 'cross_ratio':
        if isinstance(r['error'], int) and r['error'] > 0:
            print(f"  Worst case: {r['error']} mismatches  amp={r['amp']:.2e}")
        else:
            print(f"  Min |product_x|: {r['error']:.2e}  amp={r['amp']:.2e}")
    elif r['test'] == 'evaluate_sign':
        print(f"  Worst case: {r['error']:.0f} mismatches/32  amp={r['amp']:.2e}")
    else:
        print(f"  Worst case: {r['error']:.4e} {r['unit']}  amp={r['amp']:.2e}")
    print(f"  Time: {r['elapsed']:.1f}s")
    p = r['params']
    geom = '  '.join(f"{k}={v:.1f}" for k, v in p.items()
                      if k not in ('angle', 'arc_start', 'arc_end'))
    print(f"  Geometry: {geom}")
    extras = '  '.join(f"{k}={v:.3f}" for k, v in p.items()
                        if k in ('angle', 'arc_start', 'arc_end'))
    if extras:
        print(f"  Test params: {extras}")


def print_sweep(test_name, sweep_results):
    print(f"\n  ── Amplification sweep: {test_name} ──")
    print(f"  {'target_amp':>12s}  {'actual_amp':>12s}  {'error':>12s}")
    for r in sweep_results:
        print(f"  {r['target_amp']:>12.0e}  {r['actual_amp']:>12.2e}  {r['error']:>12.4e}")


def print_summary(all_results):
    print(f"\n{'='*72}")
    print("  ADVERSARIAL SUMMARY")
    print(f"{'='*72}")
    print(f"  {'Test':<22s} | {'Depth':>5s} | {'Max Amp':>10s} | {'Max Error':>12s} | Verdict")
    print(f"  {'-'*22}-+-{'-'*5}-+-{'-'*10}-+-{'-'*12}-+--------")
    for r in all_results:
        if r['test'] == 'cross_ratio':
            if isinstance(r['error'], int) and r['error'] > 0:
                err_str = f"{r['error']} flips"
                verdict = "BROKEN"
            else:
                err_str = f"|px|={r['error']:.1e}"
                verdict = "ROBUST"
        elif r['test'] == 'evaluate_sign':
            mm = int(r['error'])
            err_str = f"{mm}/32"
            verdict = "BROKEN" if mm > 0 else "ROBUST"
        else:
            e = abs(r['error'])
            err_str = f"{e:.3e} px"
            if e > 1.0:
                verdict = "BROKEN"
            elif e > 0.1:
                verdict = "FRAGILE"
            else:
                verdict = "ROBUST"
        print(f"  {r['test']:<22s} | {r['depth']:>5d} | {r['amp']:>10.2e} | {err_str:>12s} | {verdict}")


def write_csv_results(all_results, sweep_data, filename):
    with open(filename, 'w', newline='') as csvf:
        writer = csv.writer(csvf)
        writer.writerow(['test', 'depth', 'mode', 'target_amp', 'actual_amp', 'error'])
        for r in all_results:
            writer.writerow([r['test'], r['depth'], 'worst_case', '', f"{r['amp']:.6e}",
                            f"{r['error']:.6e}" if not isinstance(r['error'], int) else r['error']])
        for test_name, sweeps in sweep_data.items():
            for s in sweeps:
                writer.writerow([test_name, 2, 'sweep', f"{s['target_amp']:.0e}",
                                f"{s['actual_amp']:.6e}", f"{s['error']:.6e}"])


# ── Main ──

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Adversarial precision optimizer')
    parser.add_argument('--tests', type=str, default='all',
                        help='Comma-separated test indices (1-6) or "all"')
    parser.add_argument('--depth', type=int, default=2,
                        help='Number of inversions in the stack (2-4)')
    parser.add_argument('--n-samples', type=int, default=2000,
                        help='LHS sample count (numpy fallback only)')
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--sweep', action='store_true',
                        help='Also run amplification sweep for each test')
    parser.add_argument('--csv', type=str, default=None,
                        help='Write results to CSV file')
    args = parser.parse_args()

    if args.tests == 'all':
        test_indices = list(range(6))
    else:
        test_indices = [int(t) - 1 for t in args.tests.split(',')]

    np.random.seed(args.seed)

    print("=" * 72)
    print("  Adversarial Precision Optimizer")
    print("=" * 72)
    print(f"  Optimizer: {'scipy differential_evolution' if HAS_SCIPY else 'numpy LHS + Nelder-Mead'}")
    print(f"  Depth: {args.depth} inversions")
    print(f"  Seed: {args.seed}")
    print(f"  Tests: {', '.join(TEST_DEFS[i]['name'] for i in test_indices)}")

    all_results = []
    sweep_data = {}
    total_t0 = time.time()

    for idx in test_indices:
        td = TEST_DEFS[idx]
        print(f"\n  Running: {td['name']}...", end='', flush=True)
        result = run_test(td, args.depth, args.n_samples, args.seed)
        all_results.append(result)
        print_result(result)

        if args.sweep:
            print(f"  Running amplification sweep for {td['name']}...", flush=True)
            sweeps = run_amp_sweep(td, args.depth, args.seed)
            sweep_data[td['name']] = sweeps
            print_sweep(td['name'], sweeps)

    print_summary(all_results)

    total_elapsed = time.time() - total_t0
    print(f"\n  Total time: {total_elapsed:.1f}s")

    if args.csv:
        write_csv_results(all_results, sweep_data, args.csv)
        print(f"  Results written to {args.csv}")
