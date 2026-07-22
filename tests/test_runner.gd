extends SceneTree


func _init() -> void:
	var failures := 0
	var filters := OS.get_environment("CATCH_DOG_TEST_FILTER").split(",", false)
	var test_files := _test_files("res://tests")
	test_files.sort()
	for path in test_files:
		if not filters.is_empty():
			var matched := false
			for filter: String in filters:
				matched = matched or path.contains(filter)
			if not matched:
				continue
		var suite: Node = (load(path) as Script).new()
		root.add_child(suite)
		var test_methods := PackedStringArray()
		for method in suite.get_method_list():
			var name := String(method.name)
			if name.begins_with("test_"):
				test_methods.append(name)
		test_methods.sort()
		for test_method in test_methods:
			suite.call(test_method)
		var failure_messages: PackedStringArray = suite.get("failure_messages") as PackedStringArray
		failures += failure_messages.size()
		for message in failure_messages:
			printerr("FAIL %s: %s" % [path, message])
		suite.queue_free()
	quit(0 if failures == 0 else 1)


func _test_files(root_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(root_path)
	for entry in dir.get_files():
		if entry.begins_with("test_") and entry.ends_with(".gd") and entry not in ["test_runner.gd", "test_case.gd"]:
			found.append(root_path.path_join(entry))
	for child in dir.get_directories():
		found.append_array(_test_files(root_path.path_join(child)))
	return found
