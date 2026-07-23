extends Node
class_name Main


const GameplayScene = preload("res://src/session/gameplay.tscn")
const MainMenuScene = preload("res://src/app/main_menu.tscn")
const MainMenuRule = preload("res://src/app/main_menu.gd")
const SettingsMenuScene = preload("res://src/app/settings_menu.tscn")
const SettingsMenuRule = preload("res://src/app/settings_menu.gd")
const SettingsStoreRule = preload("res://src/app/settings_store.gd")
const TutorialScene = preload("res://src/app/tutorial_screen.tscn")
const TutorialRule = preload("res://src/app/tutorial_screen.gd")

@onready var screen_root: Node = $ScreenRoot
var settings := SettingsStoreRule.new()


func _ready() -> void:
	settings.load_settings()
	show_main_menu()


func change_screen(scene: PackedScene) -> void:
	for child: Node in screen_root.get_children():
		child.free()
	screen_root.add_child(scene.instantiate())


func show_main_menu() -> void:
	var menu := _replace_screen(MainMenuScene) as MainMenuRule
	menu.play_requested.connect(start_game)
	menu.tutorial_requested.connect(show_tutorial)
	menu.settings_requested.connect(show_settings)
	menu.quit_requested.connect(_quit)


func start_game() -> void:
	var gameplay := _replace_screen(GameplayScene)
	gameplay.main_menu_requested.connect(show_main_menu)
	var environment := gameplay.get_node("Neighborhood/WorldEnvironment").environment as Environment
	var sun := gameplay.get_node("Neighborhood/Sun") as DirectionalLight3D
	settings.apply_graphics_preset(settings.graphics_preset, environment, sun)
	gameplay.apply_motion_settings(settings.camera_shake, settings.reduced_motion)


func show_settings() -> void:
	var menu := SettingsMenuScene.instantiate() as SettingsMenuRule
	menu.store = settings
	_set_screen(menu)
	menu.back_requested.connect(show_main_menu)


func show_tutorial() -> void:
	var tutorial := _replace_screen(TutorialScene) as TutorialRule
	tutorial.back_requested.connect(show_main_menu)


func _replace_screen(scene: PackedScene) -> Node:
	var instance := scene.instantiate()
	_set_screen(instance)
	return instance


func _set_screen(instance: Node) -> void:
	get_tree().paused = false
	for child in screen_root.get_children():
		child.free()
	screen_root.add_child(instance)


func _quit() -> void:
	get_tree().quit()
