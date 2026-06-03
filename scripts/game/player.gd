extends CharacterBody2D

const SPEED := 200.0
const COLLISION_RADIUS := 12.0

func _physics_process(_delta: float) -> void:
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"),
	)
	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()
	velocity = input_dir * SPEED
	move_and_slide()
