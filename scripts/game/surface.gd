class_name Surface
extends RefCounted

static var _next_id: int = 1

var id: int
var segment: Segment
var _left_config: SideConfig
var _right_config: SideConfig
var is_target: bool
var player_solid: bool

func _init(p_segment: Segment, p_left: SideConfig, p_right: SideConfig, p_is_target: bool = false, p_player_solid: bool = true) -> void:
	id = _next_id
	_next_id += 1
	segment = p_segment
	_left_config = p_left
	_right_config = p_right
	is_target = p_is_target
	player_solid = p_player_solid

func active_side_config(side: Side.Value, _game_state: GameState) -> SideConfig:
	return _left_config if side == Side.Value.LEFT else _right_config

static func reset_id_counter() -> void:
	_next_id = 1
