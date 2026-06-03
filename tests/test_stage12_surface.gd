extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

func _make_block_surface(start: Vector2, end_v: Vector2) -> Surface:
	var seg := Segment.new(start, end_v, (start + end_v) / 2.0)
	var terminal := TerminalEffect.new()
	var left := SideConfig.new(terminal)
	var right := SideConfig.new(terminal)
	return Surface.new(seg, left, right)

func test_stage12_surface_construction() -> void:
	var surf := _make_block_surface(Vector2(0, 0), Vector2(100, 0))
	assert_gt(surf.id, 0, "Surface should have a positive ID")
	assert_not_null(surf.segment, "Surface should have a segment")
	assert_eq(surf.is_target, false, "Default is_target should be false")
	assert_eq(surf.player_solid, true, "Default player_solid should be true")

func test_stage12_surface_id_unique() -> void:
	var ids: Dictionary = {}
	for i in 50:
		var surf := _make_block_surface(Vector2(i, 0), Vector2(i + 10, 0))
		assert_false(ids.has(surf.id), "Surface ID %d should be unique" % surf.id)
		ids[surf.id] = true

func test_stage12_surface_id_never_reused() -> void:
	var first_ids: Dictionary = {}
	for i in 10:
		var surf := _make_block_surface(Vector2(i, 0), Vector2(i + 10, 0))
		first_ids[surf.id] = true
	for i in 10:
		var surf := _make_block_surface(Vector2(i + 100, 0), Vector2(i + 110, 0))
		assert_false(first_ids.has(surf.id), "Second batch ID should not reuse first batch IDs")

func test_stage12_side_config_null_effect() -> void:
	var config := SideConfig.new(null, false)
	assert_null(config.effect, "Null effect is pass-through")
	assert_eq(config.interactive, false, "Pass-through should not be interactive")

func test_stage12_side_config_terminal() -> void:
	var config := SideConfig.new(TerminalEffect.new())
	assert_true(config.effect is TerminalEffect, "Effect should be TerminalEffect")

func test_stage12_fixed_resolver_left() -> void:
	var left := SideConfig.new(TerminalEffect.new())
	var right := SideConfig.new(null)
	var resolver := ConfigResolver.FixedResolver.new(left, right)
	var result := resolver.resolve(Side.Value.LEFT, GameState.new())
	assert_eq(result, left, "LEFT should return left config")

func test_stage12_fixed_resolver_right() -> void:
	var left := SideConfig.new(TerminalEffect.new())
	var right := SideConfig.new(null)
	var resolver := ConfigResolver.FixedResolver.new(left, right)
	var result := resolver.resolve(Side.Value.RIGHT, GameState.new())
	assert_eq(result, right, "RIGHT should return right config")

func test_stage12_active_side_config_delegates() -> void:
	var surf := _make_block_surface(Vector2(0, 0), Vector2(100, 0))
	var state := GameState.new()
	var left_config := surf.active_side_config(Side.Value.LEFT, state)
	var right_config := surf.active_side_config(Side.Value.RIGHT, state)
	assert_not_null(left_config, "LEFT config should not be null")
	assert_not_null(right_config, "RIGHT config should not be null")
	assert_true(left_config.effect is TerminalEffect, "Block surface LEFT should be terminal")
	assert_true(right_config.effect is TerminalEffect, "Block surface RIGHT should be terminal")

func test_stage12_game_state_construction() -> void:
	var state := GameState.new({"wall_intact": true})
	assert_eq(state.flags["wall_intact"], true, "Flag should be stored")

func test_stage12_game_state_copy_isolation() -> void:
	var state := GameState.new({"wall_intact": true})
	var copy := state.copy()
	state.flags["wall_intact"] = false
	assert_eq(copy.flags["wall_intact"], true, "Copy should be isolated from original")
