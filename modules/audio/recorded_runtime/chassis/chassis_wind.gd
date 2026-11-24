class_name ChassisWind
extends Node
## Wind noise and environment ambient wind bed controller.
##
## Wind noise has onset at ~22 m/s with exponential volume curve and lowpass shaping.
## Ambient wind bed plays continuously from mountain_wind_bed.wav on Ambience bus.

const ChassisWavLoader = preload("wav_loader.gd")

@export var wind_bus: StringName = &"Wind_Chassis"
@export var ambience_bus: StringName = &"Ambience"
@export var onset_speed_mps: float = 22.0
@export var max_speed_mps: float = 70.0
@export var wind_exponent: float = 1.8
@export var lpf_min_hz: float = 800.0
@export var lpf_max_hz: float = 14000.0
@export_range(0.0, 1.5, 0.01) var wind_max_gain: float = 0.90
@export_range(0.0, 1.5, 0.01) var ambience_gain: float = 1.0

@export var wind_asset_path: String = "res://modules/audio/assets/wind.wav"
@export var ambience_asset_path: String = "res://assets/audio/recorded/payload/ambience/mountain_wind_bed.wav"

var _player_wind: AudioStreamPlayer
var _player_ambience: AudioStreamPlayer
var _wind_lpf: AudioEffectLowPassFilter
var _owns_lpf := false

var _current_wind_gain: float = 0.0
var _current_cutoff_hz: float = 800.0
var _current_pitch: float = 1.0
var _target_wind_gain: float = 0.0
var _target_cutoff_hz: float = 800.0
var _target_pitch: float = 1.0
var _speed_mps: float = 0.0


func _ready() -> void:
	_setup_ambience_player()
	_setup_wind_player()
	_setup_lowpass_filter()


func _exit_tree() -> void:
	# Clean up any effect we added to the audio bus
	if _owns_lpf and is_instance_valid(_wind_lpf):
		var bus_idx := AudioServer.get_bus_index(wind_bus)
		if bus_idx >= 0:
			for i in range(AudioServer.get_bus_effect_count(bus_idx)):
				if AudioServer.get_bus_effect(bus_idx, i) == _wind_lpf:
					AudioServer.remove_bus_effect(bus_idx, i)
					break
		_wind_lpf = null
		_owns_lpf = false


func _setup_ambience_player() -> void:
	_player_ambience = AudioStreamPlayer.new()
	_player_ambience.name = "AmbienceWindBed"
	var bus_name := ambience_bus if AudioServer.get_bus_index(ambience_bus) >= 0 else &"Master"
	_player_ambience.bus = bus_name

	var stream := ChassisWavLoader.load_wav(ambience_asset_path)
	if stream != null:
		ChassisWavLoader.configure_loop(stream, true)
		_player_ambience.stream = stream
		_player_ambience.volume_db = linear_to_db(maxf(0.0001, ambience_gain))
		add_child(_player_ambience)
		_player_ambience.play()
	else:
		push_warning("ChassisWind: Ambience stream could not be loaded: " + ambience_asset_path)
		add_child(_player_ambience)


func _setup_wind_player() -> void:
	_player_wind = AudioStreamPlayer.new()
	_player_wind.name = "DynamicWindNoise"
	var bus_name := wind_bus if AudioServer.get_bus_index(wind_bus) >= 0 else &"Master"
	_player_wind.bus = bus_name

	var stream := ChassisWavLoader.load_wav(wind_asset_path)
	if stream == null:
		# Fallback to ambience bed if wind asset is missing
		stream = ChassisWavLoader.load_wav(ambience_asset_path)

	if stream != null:
		ChassisWavLoader.configure_loop(stream, true)
		_player_wind.stream = stream
		_player_wind.volume_db = -80.0
		add_child(_player_wind)
		_player_wind.play()
	else:
		push_warning("ChassisWind: Wind stream could not be loaded: " + wind_asset_path)
		add_child(_player_wind)


func _setup_lowpass_filter() -> void:
	var bus_idx := AudioServer.get_bus_index(wind_bus)
	if bus_idx < 0:
		return

	# Separate speed shaping from the camera's existing cabin lowpass.
	# Cascaded filters retain both effects instead of fighting every frame.
	_wind_lpf = AudioEffectLowPassFilter.new()
	_wind_lpf.cutoff_hz = lpf_min_hz
	_wind_lpf.resonance = 0.5
	AudioServer.add_bus_effect(bus_idx, _wind_lpf)
	_owns_lpf = true


func update_telemetry(telemetry: Dictionary) -> void:
	var speed: float = float(telemetry.get("speed_mps", 0.0))
	set_speed(speed)


func set_speed(speed: float) -> void:
	_speed_mps = maxf(0.0, speed)
	var targets: Dictionary = compute_wind_targets(
		_speed_mps,
		onset_speed_mps,
		max_speed_mps,
		wind_exponent,
		lpf_min_hz,
		lpf_max_hz,
		wind_max_gain
	)
	_target_wind_gain = float(targets.get("gain", 0.0))
	_target_cutoff_hz = float(targets.get("cutoff_hz", lpf_min_hz))
	_target_pitch = float(targets.get("pitch_scale", 1.0))


func _process(delta: float) -> void:
	var step: float = maxf(delta, 0.001)
	var alpha: float = 1.0 - exp(-step * 10.0)

	_current_wind_gain = lerpf(_current_wind_gain, _target_wind_gain, alpha)
	_current_cutoff_hz = lerpf(_current_cutoff_hz, _target_cutoff_hz, alpha)
	_current_pitch = lerpf(_current_pitch, _target_pitch, alpha)

	if is_instance_valid(_player_wind):
		if _current_wind_gain <= 0.0005:
			_player_wind.volume_db = -80.0
		else:
			_player_wind.volume_db = linear_to_db(clampf(_current_wind_gain, 0.0001, 1.5))
		_player_wind.pitch_scale = _current_pitch

	if is_instance_valid(_wind_lpf):
		_wind_lpf.cutoff_hz = clampf(_current_cutoff_hz, 200.0, 20500.0)


## Pure functional target computation for deterministic testing and analysis
static func compute_wind_targets(
	speed_mps: float,
	onset: float = 22.0,
	max_speed: float = 70.0,
	exponent: float = 1.8,
	lpf_min: float = 800.0,
	lpf_max: float = 14000.0,
	max_gain: float = 0.90
) -> Dictionary:
	var speed: float = maxf(0.0, speed_mps)
	if speed < onset:
		return {
			"gain": 0.0,
			"volume_db": -80.0,
			"cutoff_hz": lpf_min,
			"pitch_scale": 0.90,
			"is_active": false
		}

	var span: float = maxf(1.0, max_speed - onset)
	var excess: float = speed - onset
	var norm_speed: float = clampf(excess / span, 0.0, 1.5)
	var exp_factor: float = pow(norm_speed, exponent)
	var gain: float = clampf(exp_factor * max_gain, 0.0, 1.5)
	var cutoff_hz: float = lerpf(lpf_min, lpf_max, clampf(norm_speed, 0.0, 1.0))
	var pitch_scale: float = lerpf(0.92, 1.25, clampf(norm_speed, 0.0, 1.0))

	return {
		"gain": gain,
		"volume_db": linear_to_db(maxf(0.0001, gain)),
		"cutoff_hz": cutoff_hz,
		"pitch_scale": pitch_scale,
		"is_active": true
	}
