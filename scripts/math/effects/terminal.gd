class_name TerminalEffect
extends Effect

func is_terminal() -> bool:
	return true

func get_display_name() -> String:
	return "block"

func get_display_color() -> Color:
	return Color.RED
