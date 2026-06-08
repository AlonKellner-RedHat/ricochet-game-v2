# Invariant Sweep Configuration

## Current Settings (commit 91134c0+)

### Empty-plan sweep (`test_sweep_all_scenes`)
- **Grid:** 5×5 = 25 positions
- **Fuzz:** 10 random positions (seed=42)
- **POI:** Surface endpoints, room corners (~19 avg per scene)
- **Total positions per scene:** ~50-59
- **Scenes:** 10 (all in `scenes/test_levels/`)
- **Combos:** ~29,686
- **Runtime:** ~53 seconds

### Plan sweep (`test_sweep_with_plans`)
- **Grid:** 5×5 = 25 positions
- **Fuzz:** 10 random positions (seed=42)
- **POI:** Surface endpoints, room corners (~21 avg for mirror scenes)
- **Total positions per scene:** ~52-59
- **Scenes:** 6 (scenes with reflective surfaces)
- **Plans per scene:** singles (each mirror) + one pair + one repeated = 2-5 plans
- **Combos:** ~59,830
- **Runtime:** ~178 seconds

### Totals
- **Total combos:** ~89,516
- **Total runtime:** ~231 seconds (~3.9 minutes)
- **Invariants checked:** 12 per combo

### Invariants
1. UX7 — preview line from player (direction check skipped with plan)
2. PREVIEW-NOGAPS — step continuity
3. S9 — no consecutive same-segment hits
4. S16 — no NaN
5. GREEN-FROM-PLAYER — first step aligned
6. ORIGIN-NOT-REHIT — no zero-length forward hits
7. SINGLE-DIVERGENCE — no re-convergence
8. PHYSICAL-PREVIEW-MATCH — non-red = physical trace
9. PHYSICAL-CONTINUITY — physical trace contiguous
10. SOLID-PATH-TO-CURSOR — solid path from player
11. TRACE-ENDS-AT-SURFACE-OR-BOUNDS — no mid-air endings
12. PLAN-EFFECTS-APPLIED — plan entries trigger frame changes
