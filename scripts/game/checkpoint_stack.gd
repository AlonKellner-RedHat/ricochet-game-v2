class_name CheckpointStack
extends RefCounted

var _stack: Array = []
var _initial: CheckpointData = null

func set_initial(data: CheckpointData) -> void:
	_initial = data

func push(data: CheckpointData) -> void:
	_stack.append(data)

func pop() -> CheckpointData:
	if _stack.is_empty():
		return null
	return _stack.pop_back()

func reset() -> CheckpointData:
	_stack.clear()
	return _initial

func is_empty() -> bool:
	return _stack.is_empty()

func depth() -> int:
	return _stack.size()
