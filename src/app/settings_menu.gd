class_name SettingsMenu
extends Control


const SettingsStoreRule = preload("res://src/app/settings_store.gd")

signal back_requested

var store: SettingsStoreRule


func _ready() -> void:
	if store == null:
		store = SettingsStoreRule.new()
		store.load_settings()
	$Panel/Margin/Fields/Master.value = store.master_volume * 100.0
	$Panel/Margin/Fields/Music.value = store.music_volume * 100.0
	$Panel/Margin/Fields/Effects.value = store.effects_volume * 100.0
	$Panel/Margin/Fields/Fullscreen.button_pressed = store.fullscreen
	$Panel/Margin/Fields/Resolution.select(SettingsStoreRule.RESOLUTIONS.find(store.resolution))
	$Panel/Margin/Fields/Preset.select(int(store.graphics_preset))
	$Panel/Margin/Fields/CameraShake.value = store.camera_shake * 100.0
	$Panel/Margin/Fields/ReducedMotion.button_pressed = store.reduced_motion
	$Panel/Margin/Fields/Save.grab_focus()


func _on_save_pressed() -> void:
	store.master_volume = $Panel/Margin/Fields/Master.value / 100.0
	store.music_volume = $Panel/Margin/Fields/Music.value / 100.0
	store.effects_volume = $Panel/Margin/Fields/Effects.value / 100.0
	store.fullscreen = $Panel/Margin/Fields/Fullscreen.button_pressed
	store.resolution = SettingsStoreRule.RESOLUTIONS[$Panel/Margin/Fields/Resolution.selected]
	store.graphics_preset = $Panel/Margin/Fields/Preset.selected as SettingsStoreRule.Preset
	store.camera_shake = $Panel/Margin/Fields/CameraShake.value / 100.0
	store.reduced_motion = $Panel/Margin/Fields/ReducedMotion.button_pressed
	store.apply()
	store.save_settings()
	back_requested.emit()


func _on_back_pressed() -> void:
	back_requested.emit()
