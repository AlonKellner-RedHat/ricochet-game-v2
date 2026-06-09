class_name PlanManager
extends RefCounted

class PlanEntry extends RefCounted:
	var surface_id: int
	var side: Side.Value

	func _init(p_surface_id: int, p_side: Side.Value) -> void:
		surface_id = p_surface_id
		side = p_side

var entries: Array = []

func add_entry(surface_id: int, side: Side.Value) -> void:
	entries.append(PlanEntry.new(surface_id, side))

func remove_last_of(surface_id: int) -> void:
	for i in range(entries.size() - 1, -1, -1):
		var entry: PlanEntry = entries[i]
		if entry.surface_id == surface_id:
			entries.remove_at(i)
			return

func clear() -> void:
	entries.clear()

func size() -> int:
	return entries.size()

func get_entry(index: int) -> PlanEntry:
	return entries[index]

func is_empty() -> bool:
	return entries.size() == 0

func has_surface(surface_id: int) -> bool:
	for entry in entries:
		if entry.surface_id == surface_id:
			return true
	return false

func restore_from(p_entries: Array) -> void:
	entries.clear()
	for entry in p_entries:
		entries.append(PlanEntry.new(entry.surface_id, entry.side))
