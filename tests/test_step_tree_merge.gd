extends GutTest
## Tests for StepTreeMerge — §14.5 merge algorithm.

func _step(start: Vector2, end_v: Vector2, frame_id: int = 0) -> Tracer.Step:
	return Tracer.Step.new(start, end_v, frame_id, null)

func test_merge_empty_plan() -> void:
	var physical: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, 0)),
	]
	var merged := StepTreeMerge.merge([], physical, 0)
	assert_eq(merged.size(), 2, "Should have 2 steps")
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		assert_eq(ms.type, StepTypes.Type.ALIGNED_POST_PLANNED, "Empty plan: all ALIGNED_POST_PLANNED")

func test_merge_fully_aligned() -> void:
	var planned: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, 0)),
	]
	var physical: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, 0)),
	]
	var merged := StepTreeMerge.merge(planned, physical, 1)
	assert_eq(merged.size(), 2, "Should have 2 steps")
	var m0: StepTreeMerge.MergedStep = merged[0]
	var m1: StepTreeMerge.MergedStep = merged[1]
	assert_eq(m0.type, StepTypes.Type.ALIGNED, "Step 0 before cursor = ALIGNED")
	assert_eq(m1.type, StepTypes.Type.ALIGNED_POST_PLANNED, "Step 1 after cursor = POST_PLANNED")

func test_merge_diverged_different_endpoint() -> void:
	# Physical hits closer (100 units), planned goes further (150 units)
	var planned: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(250, 0)),
	]
	var physical: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, 0)),
	]
	var merged := StepTreeMerge.merge(planned, physical, 2)
	assert_eq(merged[0].type, StepTypes.Type.ALIGNED, "Step 0 aligned")
	var found_aligned_split := false
	var found_div_planned := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.ALIGNED and i > 0:
			found_aligned_split = true
		if ms.type == StepTypes.Type.DIVERGED_PLANNED:
			found_div_planned = true
	assert_true(found_aligned_split, "Should have ALIGNED split at nearer endpoint")
	assert_true(found_div_planned, "Should have DIVERGED_PLANNED remainder")

func test_merge_diverged_different_frame() -> void:
	var planned: Array = [
		_step(Vector2(0, 0), Vector2(100, 0), 0),
		_step(Vector2(100, 0), Vector2(200, 0), 5),
	]
	var physical: Array = [
		_step(Vector2(0, 0), Vector2(100, 0), 0),
		_step(Vector2(100, 0), Vector2(200, 0), 7),
	]
	var merged := StepTreeMerge.merge(planned, physical, 2)
	assert_eq(merged[0].type, StepTypes.Type.ALIGNED, "Step 0 aligned")
	assert_eq(merged[1].type, StepTypes.Type.DIVERGED_PLANNED, "Different frame = diverged planned")
	assert_eq(merged[2].type, StepTypes.Type.DIVERGED_PHYSICAL, "Different frame = diverged physical")

func test_merge_cursor_boundary() -> void:
	var steps: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, 0)),
		_step(Vector2(200, 0), Vector2(300, 0)),
	]
	var merged := StepTreeMerge.merge(steps, steps, 2)
	var m0: StepTreeMerge.MergedStep = merged[0]
	var m1: StepTreeMerge.MergedStep = merged[1]
	var m2: StepTreeMerge.MergedStep = merged[2]
	assert_eq(m0.type, StepTypes.Type.ALIGNED, "Before cursor")
	assert_eq(m1.type, StepTypes.Type.ALIGNED, "Before cursor")
	assert_eq(m2.type, StepTypes.Type.ALIGNED_POST_PLANNED, "After cursor")

func test_merge_monotonic_divergence() -> void:
	var planned: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, 50)),
		_step(Vector2(200, 50), Vector2(300, 100)),
	]
	var physical: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, -50)),
		_step(Vector2(200, -50), Vector2(300, -100)),
	]
	var merged := StepTreeMerge.merge(planned, physical, 3)
	var found_aligned_after_diverge := false
	var diverged := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.DIVERGED_PLANNED or ms.type == StepTypes.Type.DIVERGED_PHYSICAL:
			diverged = true
		elif diverged and ms.type == StepTypes.Type.ALIGNED:
			found_aligned_after_diverge = true
	assert_false(found_aligned_after_diverge, "S4: No ALIGNED after divergence (monotonic)")

func test_merge_solid_is_planned() -> void:
	var planned: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, 50)),
	]
	var physical: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, -50)),
	]
	var merged := StepTreeMerge.merge(planned, physical, 2)
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if StepTypes.is_solid(ms.type):
			var matches_planned := false
			for p in planned:
				if ms.start.distance_to(p.start) < 1.0 or ms.start.distance_to(p.end) < 1.0:
					matches_planned = true
			if ms.type == StepTypes.Type.ALIGNED:
				matches_planned = true
			assert_true(matches_planned, "Solid step should come from planned path")

func test_merge_nonred_is_physical() -> void:
	var planned: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, 50)),
	]
	var physical: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, -50)),
	]
	var merged := StepTreeMerge.merge(planned, physical, 2)
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		var is_red: bool = ms.type == StepTypes.Type.DIVERGED_PLANNED or ms.type == StepTypes.Type.DIVERGED_POST_PLANNED
		if not is_red:
			var matches_physical := false
			for r in physical:
				if ms.start.distance_to(r.start) < 1.0:
					matches_physical = true
			assert_true(matches_physical, "Non-red step should come from physical path")
