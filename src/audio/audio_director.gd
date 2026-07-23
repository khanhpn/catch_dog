class_name AudioDirector
extends Node


const GuardDirectorRule = preload("res://src/guards/guard_director.gd")
const PlayerVehicleRule = preload("res://src/vehicle/player_vehicle.gd")

signal chase_intensity_changed(value: float)

@export var player: PlayerVehicleRule
@export var guard_director: GuardDirectorRule
var _engine_phase := 0.0
var _wind_phase := 0.0
var _chase_phase := 0.0
var _last_chase_intensity := -1.0


func _ready() -> void:
	_ensure_buses()
	for audio_player in [$Engine, $Wind, $Chase]:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = 22050.0
		generator.buffer_length = 0.2
		audio_player.stream = generator
		audio_player.play()


func _process(_delta: float) -> void:
	var speed_ratio := player.speed_ratio() if is_instance_valid(player) else 0.0
	var guard_count := guard_director.threat_directions().size() if is_instance_valid(guard_director) else 0
	var chase_intensity := clampf(float(guard_count) / 3.0, 0.0, 1.0)
	if not is_equal_approx(chase_intensity, _last_chase_intensity):
		_last_chase_intensity = chase_intensity
		chase_intensity_changed.emit(chase_intensity)
	_fill_tone($Engine, 72.0 + speed_ratio * 115.0, 0.035 + speed_ratio * 0.06, "_engine_phase")
	_fill_tone($Wind, 185.0 + speed_ratio * 90.0, speed_ratio * 0.025, "_wind_phase")
	_fill_tone($Chase, 110.0 + chase_intensity * 35.0, chase_intensity * 0.045, "_chase_phase")


func _fill_tone(
	audio_player: AudioStreamPlayer,
	frequency: float,
	amplitude: float,
	phase_property: StringName,
) -> void:
	var playback := audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var phase := float(get(phase_property))
	var frames := playback.get_frames_available()
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	for frame in range(frames):
		var sample := sin(phase) * amplitude
		buffer[frame] = Vector2(sample, sample)
		phase = fmod(phase + TAU * frequency / 22050.0, TAU)
	set(phase_property, phase)
	if not buffer.is_empty():
		playback.push_buffer(buffer)


func _ensure_buses() -> void:
	for bus_name in [&"Music", &"Effects"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
