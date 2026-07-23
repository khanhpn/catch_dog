extends "res://tests/test_case.gd"


const MainScene = preload("res://src/app/main.tscn")


func test_main_menu_routes_to_gameplay_settings_and_tutorial() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	check(main.has_method("show_main_menu"), "Main must expose menu routing")
	check(main.get_node("ScreenRoot").get_child_count() == 1, "Main must launch exactly one initial screen")
	check(main.get_node("ScreenRoot").get_child(0).name == &"MainMenu", "The initial screen must be MainMenu")
	main.start_game()
	check(main.get_node("ScreenRoot").get_child_count() == 1 and main.get_node("ScreenRoot").get_child(0).name == &"Gameplay", "Play must route to Gameplay")
	main.show_settings()
	check(main.get_node("ScreenRoot").get_child(0).name == &"SettingsMenu", "Settings must route to SettingsMenu")
	main.show_tutorial()
	check(main.get_node("ScreenRoot").get_child(0).name == &"TutorialScreen", "Tutorial must route to TutorialScreen")
	main.free()


func test_corrupt_settings_fields_reset_independently() -> void:
	var script := load("res://src/app/settings_store.gd") as Script
	check(script != null, "SettingsStore script must load")
	if script == null:
		return
	var path := "res://.godot/test_settings_store.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Test settings file must be writable")
	if file == null:
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"master_volume": "broken",
		"music_volume": 0.25,
		"effects_volume": 0.75,
		"fullscreen": false,
		"resolution": "1280x720",
		"graphics_preset": 1,
		"camera_shake": 0.4,
		"reduced_motion": true,
	}))
	file.close()
	var store = script.new(path)
	store.load_settings()
	check(is_equal_approx(store.master_volume, 0.8), "Only invalid master volume must reset to default")
	check(is_equal_approx(store.music_volume, 0.25), "Valid neighboring music volume must survive")
	check(store.reduced_motion, "Valid reduced-motion setting must survive")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_pause_resume_is_idempotent() -> void:
	var gameplay := (load("res://src/session/gameplay.tscn") as PackedScene).instantiate()
	add_child(gameplay)
	check(gameplay.has_method("set_paused"), "Gameplay must expose pause ownership")
	if gameplay.has_method("set_paused"):
		gameplay.set_paused(true)
		gameplay.set_paused(true)
		check(get_tree().paused, "Repeated pause must remain paused")
		gameplay.set_paused(false)
		gameplay.set_paused(false)
		check(not get_tree().paused, "Repeated resume must remain resumed")
	gameplay.free()
