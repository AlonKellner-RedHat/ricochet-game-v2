extends GutTest

func test_stage1_math_layer_no_node_dependencies():
	var forbidden_bases = ["Node", "Node2D", "Node3D", "Control",
		"CharacterBody2D", "RigidBody2D", "StaticBody2D", "Area2D"]
	var violations: Array[String] = []

	_scan_directory("res://scripts/math/", forbidden_bases, violations)

	assert_eq(violations.size(), 0,
		"Math layer files must not extend scene-tree types. Violations: %s" % str(violations))

func _scan_directory(path: String, forbidden: Array, violations: Array[String]) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var full_path = path.path_join(file_name)
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				_scan_directory(full_path, forbidden, violations)
		elif file_name.ends_with(".gd"):
			_check_file(full_path, forbidden, violations)
		file_name = dir.get_next()
	dir.list_dir_end()

func _check_file(path: String, forbidden: Array, violations: Array[String]) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var content = file.get_as_text()
	file.close()
	for line in content.split("\n"):
		var stripped = line.strip_edges()
		if stripped.begins_with("extends "):
			var base_class = stripped.substr(8).strip_edges()
			if base_class in forbidden:
				violations.append("%s extends %s" % [path, base_class])
