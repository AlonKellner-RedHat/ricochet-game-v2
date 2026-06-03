class_name Surface
extends RefCounted

static var _next_id: int = 1

var id: int
var segment: Segment
var resolver: ConfigResolver
var is_target: bool
var player_solid: bool

func _init(p_segment: Segment, p_left: SideConfig, p_right: SideConfig, p_is_target: bool = false, p_player_solid: bool = true) -> void:
	id = _next_id
	_next_id += 1
	segment = p_segment
	resolver = ConfigResolver.FixedResolver.new(p_left, p_right)
	is_target = p_is_target
	player_solid = p_player_solid

func active_side_config(side: Side.Value, game_state: GameState) -> SideConfig:
	return resolver.resolve(side, game_state)

static func reset_id_counter() -> void:
	_next_id = 1
