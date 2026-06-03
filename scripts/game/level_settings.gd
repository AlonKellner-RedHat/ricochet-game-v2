extends Node2D

@export var gravity := Vector2(0, 0)
@export var room_rect := Rect2(560, 240, 800, 600)
@export var build_room := true

var surfaces: Array[Surface] = []

func _ready() -> void:
	if build_room:
		surfaces = RoomBuilder.add_room_to_scene(self, room_rect)
