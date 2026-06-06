extends GutTest
## Tests for StepTreeMerge — §14.5 merge algorithm (frame-only comparison).

func _step(start: Vector2, end_v: Vector2, frame_id: int = 0) -> Tracer.Step:
	return Tracer.Step.new(start, end_v, frame_id, null)

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
	var m0: StepTreeMerge.MergedStep = merged[0]
	assert_eq(m0.type, StepTypes.Type.ALIGNED, "Step 0 aligned (same frame)")
	assert_eq(merged[1].type, StepTypes.Type.DIVERGED_PLANNED, "Different frame = diverged planned")
	assert_eq(merged[2].type, StepTypes.Type.DIVERGED_PHYSICAL, "Different frame = diverged physical")

func test_merge_post_divergence_different_lengths() -> void:
	# After divergence, arrays may have different lengths
	var planned: Array = [
		_step(Vector2(0, 0), Vector2(100, 0), 0),
		_step(Vector2(100, 0), Vector2(200, 0), 5),
		_step(Vector2(200, 0), Vector2(300, 0), 5),
		_step(Vector2(300, 0), Vector2(400, 0), 5),
	]
	var physical: Array = [
		_step(Vector2(0, 0), Vector2(100, 0), 0),
		_step(Vector2(100, 0), Vector2(150, 0), 7),
	]
	var merged := StepTreeMerge.merge(planned, physical, 4)
	# Step 0: aligned; Steps 1: diverged pair; Steps 2-3: remaining planned only
	assert_eq(merged[0].type, StepTypes.Type.ALIGNED, "Step 0 aligned")
	var div_planned_count := 0
	var div_physical_count := 0
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.DIVERGED_PLANNED:
			div_planned_count += 1
		if ms.type == StepTypes.Type.DIVERGED_PHYSICAL:
			div_physical_count += 1
	assert_eq(div_planned_count, 3, "3 diverged planned steps (indices 1-3)")
	assert_eq(div_physical_count, 1, "1 diverged physical step (index 1)")

func test_merge_empty_plan_all_post_planned() -> void:
	# Both arrays identical, cursor_index = 0 → all post-cursor
	var steps: Array = [
		_step(Vector2(0, 0), Vector2(100, 0)),
		_step(Vector2(100, 0), Vector2(200, 0)),
	]
	var merged := StepTreeMerge.merge(steps, steps, 0)
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		assert_eq(ms.type, StepTypes.Type.ALIGNED_POST_PLANNED, "All post-cursor = ALIGNED_POST_PLANNED at step %d" % i)

func test_merge_monotonic_divergence() -> void:
	# Once frames diverge, they stay diverged
	var planned: Array = [
		_step(Vector2(0, 0), Vector2(100, 0), 0),
		_step(Vector2(100, 0), Vector2(200, 0), 5),
		_step(Vector2(200, 0), Vector2(300, 0), 5),
	]
	var physical: Array = [
		_step(Vector2(0, 0), Vector2(100, 0), 0),
		_step(Vector2(100, 0), Vector2(200, 0), 7),
		_step(Vector2(200, 0), Vector2(300, 0), 7),
	]
	var merged := StepTreeMerge.merge(planned, physical, 3)
	var diverged := false
	var found_aligned_after_diverge := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.DIVERGED_PLANNED or ms.type == StepTypes.Type.DIVERGED_PHYSICAL:
			diverged = true
		elif diverged and ms.type == StepTypes.Type.ALIGNED:
			found_aligned_after_diverge = true
	assert_false(found_aligned_after_diverge, "S4: No ALIGNED after divergence (monotonic)")

func test_merge_diverged_post_cursor() -> void:
	# Divergence after cursor: different geometry → DIVERGED_POST_PLANNED
	var planned: Array = [
		_step(Vector2(0, 0), Vector2(100, 0), 0),
		_step(Vector2(100, 0), Vector2(200, 50), 5),
	]
	var physical: Array = [
		_step(Vector2(0, 0), Vector2(100, 0), 0),
		_step(Vector2(100, 0), Vector2(200, -50), 7),
	]
	var merged := StepTreeMerge.merge(planned, physical, 1)
	assert_eq(merged[0].type, StepTypes.Type.ALIGNED, "Pre-cursor aligned")
	assert_eq(merged[1].type, StepTypes.Type.DIVERGED_POST_PLANNED, "Post-cursor diverged planned")
	assert_eq(merged[2].type, StepTypes.Type.DIVERGED_PHYSICAL, "Post-cursor diverged physical")
	assert_eq(merged[2].type, StepTypes.Type.DIVERGED_PHYSICAL, "Post-cursor diverged physical")
