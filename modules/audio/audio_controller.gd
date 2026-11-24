class_name AsterAudioController
extends Node
## Integrated vehicle audio controller for Aster Valley.
## Coordinates modular recorded audio subsystems (Mix, Engine, Tires, Chassis)
## with fallback to listener-centered 2D synthetic loops.

const RecordedEngineScript := preload("res://modules/audio/recorded_runtime/engine/recorded_engine_controller.gd")
const RecordedTireScript := preload("res://modules/audio/recorded_runtime/tires/recorded_tire_controller.gd")
const ChassisControllerScript := preload("res://modules/audio/recorded_runtime/chassis/chassis_audio_controller.gd")
const CameraMixScript := preload("res://modules/audio/recorded_runtime/mix/camera_mix_controller.gd")
const BusBuilderScript := preload("res://modules/audio/recorded_runtime/mix/bus_layout_builder.gd")
const AsterAudioTelemetryScript := preload("res://modules/audio/telemetry_bridge.gd")

const PROFILES := {
	"vela_gt": {"prefix": "vela", "idle": 950.0, "redline": 7100.0, "gain": 0.84},
	"orion_rs": {"prefix": "orion", "idle": 1000.0, "redline": 8500.0, "gain": 0.78},
	"kestrel_xr": {"prefix": "kestrel", "idle": 800.0, "redline": 6900.0, "gain": 0.94},
}
const ENGINE_BANDS: Array[String] = ["low", "mid", "high"]
const SURFACES: Array[String] = ["asphalt", "gravel", "grass"]
const LOOP_NAMES: Array[String] = ["roll_asphalt", "roll_gravel", "roll_grass", "tire_squeal", "tire_skid", "wind", "countryside", "overrun"]
const EVENT_NAMES: Array[String] = ["gearshift", "collision", "suspension"]
const EVENT_COOLDOWNS := {"gearshift": 0.18, "collision": 0.12, "suspension": 0.16}
const PROFILE_FADE_SECONDS := 0.28
const LOOP_PEAK_BUDGET := 0.51
const EVENT_VOICE_GAIN := 0.17

@export var use_recorded_runtime: bool = true
@export_range(0.0, 1.0, 0.01) var master_gain := 0.80
@export_range(0.0, 1.0, 0.01) var ambient_gain := 0.32

var _car_profile: String = "vela_gt"
@export var car_profile: String:
	get:
		return _car_profile
	set(val):
		set_profile(val)

# Recorded runtime subsystems
var recorded_engine: Node = null
var recorded_tires: Node = null
var recorded_chassis: Node = null
var camera_mix: Node = null
var _bound_camera: Camera3D = null

# Legacy players for fallback & regression test verification
var _players: Dictionary = {}
var _alternate_engines: Dictionary = {}
var _event_players: Array[AudioStreamPlayer] = []
var _event_streams: Dictionary = {}
var _event_index := 0
var _event_ready_at: Dictionary = {}
var _clock := 0.0
var _current_profile := ""
var _profile_fading := false
var _profile_fade := 1.0
var _queued_profile := ""
var _outgoing_gains: Dictionary = {}
var _telemetry: Dictionary = {"rpm": 950.0, "throttle": 0.0, "speed_mps": 0.0, "gear": 1, "surface": "asphalt", "grip": 1.0}
var _mix_targets: Dictionary = {}
var _gains: Dictionary = {}
var _bound_vehicle: Node3D
var _tracking_vehicle := false
var _last_gear := -999
var _last_throttle := 0.0
var _shift_timer := 0.0
var _overrun_timer := 0.0
var _suspension_cooldown := 0.0
var _previous_springs: Dictionary = {}


func _ready() -> void:
	if use_recorded_runtime:
		_setup_recorded_runtime()
	else:
		_setup_legacy_players()
		set_profile(car_profile)


func _setup_recorded_runtime() -> void:
	# Ensure audio bus layout has required buses
	if AudioServer.get_bus_index("SFX") < 0 or AudioServer.get_bus_index("Engine_Exhaust") < 0:
		BusBuilderScript.apply_to_audio_server(true)

	if recorded_engine == null:
		recorded_engine = RecordedEngineScript.new()
		recorded_engine.name = "RecordedEngine"
		recorded_engine.set("car_profile", car_profile)
		recorded_engine.process_mode = Node.PROCESS_MODE_INHERIT
		add_child(recorded_engine)

	if recorded_tires == null:
		recorded_tires = RecordedTireScript.new()
		recorded_tires.name = "RecordedTires"
		recorded_tires.process_mode = Node.PROCESS_MODE_INHERIT
		add_child(recorded_tires)

	if recorded_chassis == null:
		recorded_chassis = ChassisControllerScript.new()
		recorded_chassis.name = "RecordedChassis"
		recorded_chassis.process_mode = Node.PROCESS_MODE_INHERIT
		add_child(recorded_chassis)
		if is_instance_valid(_bound_vehicle) and recorded_chassis.has_method("bind_vehicle"):
			recorded_chassis.call("bind_vehicle", _bound_vehicle)

	if camera_mix == null:
		camera_mix = CameraMixScript.new()
		camera_mix.name = "CameraMix"
		camera_mix.process_mode = Node.PROCESS_MODE_INHERIT
		add_child(camera_mix)
		if is_instance_valid(_bound_vehicle) and camera_mix.has_method("bind_vehicle"):
			camera_mix.call("bind_vehicle", _bound_vehicle)
		if is_instance_valid(_bound_camera) and camera_mix.has_method("bind_camera"):
			camera_mix.call("bind_camera", _bound_camera)


func _setup_legacy_players() -> void:
	for band in ENGINE_BANDS:
		_players["engine_" + band] = _make_player("Engine " + band)
		_alternate_engines[band] = _make_player("Engine alternate " + band)
	for name in LOOP_NAMES:
		_players[name] = _make_player(name)
		_set_loop(_players[name], name)
	for i in range(3):
		_event_players.append(_make_player("Event %d" % i))
	for name in EVENT_NAMES:
		var wav := _asset(name)
		if wav != null:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
			_event_streams[name] = wav
	var prefix: String = str(PROFILES.get(_car_profile, {}).get("prefix", "vela"))
	for band in ENGINE_BANDS:
		_set_loop(_players["engine_" + band], "engine_%s_%s" % [prefix, band])
	_current_profile = _car_profile


func set_profile(profile: String) -> void:
	if not PROFILES.has(profile):
		push_warning("Unknown Aster audio profile: " + profile)
		return

	_car_profile = profile

	if use_recorded_runtime and is_instance_valid(recorded_engine):
		if recorded_engine.has_method("set_profile"):
			recorded_engine.call("set_profile", profile)
		if recorded_engine.has_method("snap_to_idle"):
			recorded_engine.call("snap_to_idle")

	# Legacy crossfade state machine
	if _profile_fading:
		_queued_profile = "" if profile == _current_profile else profile
		return
	if _players.is_empty() or _current_profile == profile:
		return
	var prefix: String = PROFILES[profile]["prefix"]
	if _current_profile == "":
		for band in ENGINE_BANDS:
			_set_loop(_players["engine_" + band], "engine_%s_%s" % [prefix, band])
	else:
		for band in ENGINE_BANDS:
			var key: String = "engine_" + band
			_outgoing_gains[key] = float(_gains.get(key, 0.0))
			var previous: AudioStreamPlayer = _players[key]
			var incoming: AudioStreamPlayer = _alternate_engines[band]
			_players[key] = incoming
			_alternate_engines[band] = previous
			incoming.volume_db = -80.0
			_set_loop(incoming, "engine_%s_%s" % [prefix, band])
		_profile_fading = true
		_profile_fade = 0.0
	_current_profile = profile
	_last_gear = -999
	_last_throttle = 0.0
	_shift_timer = 0.0
	_overrun_timer = 0.0


func snap_to_idle() -> void:
	if use_recorded_runtime and is_instance_valid(recorded_engine):
		if recorded_engine.has_method("snap_to_idle"):
			recorded_engine.call("snap_to_idle")
	_shift_timer = 0.0
	_overrun_timer = 0.0


func bind_camera(camera: Camera3D) -> void:
	_bound_camera = camera
	if use_recorded_runtime and is_instance_valid(camera_mix):
		if camera_mix.has_method("bind_camera"):
			camera_mix.call("bind_camera", camera)


func bind_gevp_vehicle(vehicle: Node3D) -> void:
	_disconnect_vehicle()
	_bound_vehicle = vehicle if is_instance_valid(vehicle) else null
	_tracking_vehicle = _bound_vehicle != null
	_previous_springs.clear()
	_reset_transition_state()

	if use_recorded_runtime:
		if is_instance_valid(recorded_chassis) and recorded_chassis.has_method("bind_vehicle"):
			recorded_chassis.call("bind_vehicle", _bound_vehicle)
		if is_instance_valid(camera_mix) and camera_mix.has_method("bind_vehicle"):
			camera_mix.call("bind_vehicle", _bound_vehicle)

	if not _tracking_vehicle:
		_reset_telemetry()
		return
	if not use_recorded_runtime and _bound_vehicle is RigidBody3D:
		var body := _bound_vehicle as RigidBody3D
		if not body.body_entered.is_connected(_on_body_entered):
			body.body_entered.connect(_on_body_entered)


func unbind_gevp_vehicle() -> void:
	bind_gevp_vehicle(null)


func _exit_tree() -> void:
	_disconnect_vehicle()
	_bound_vehicle = null
	_bound_camera = null
	_tracking_vehicle = false


func _disconnect_vehicle() -> void:
	if is_instance_valid(_bound_vehicle) and _bound_vehicle is RigidBody3D:
		var body := _bound_vehicle as RigidBody3D
		if body.body_entered.is_connected(_on_body_entered):
			body.body_entered.disconnect(_on_body_entered)


func _reset_transition_state() -> void:
	_last_gear = -999
	_last_throttle = 0.0
	_shift_timer = 0.0
	_overrun_timer = 0.0
	_suspension_cooldown = 0.0


func _reset_telemetry() -> void:
	update_telemetry(AsterAudioTelemetryScript.from_gevp(null))


func update_telemetry(telemetry: Dictionary) -> void:
	var gear := int(telemetry.get("gear", 1))
	if not use_recorded_runtime and _last_gear > 0 and gear > 0 and gear != _last_gear:
		if _play_event("gearshift", 0.55):
			_shift_timer = 0.23
	_last_gear = gear

	var throttle := clampf(float(telemetry.get("throttle", 0.0)), 0.0, 1.0)
	if not use_recorded_runtime and _last_throttle > 0.48 and throttle < 0.16 and float(telemetry.get("rpm", 0.0)) > 2500.0:
		_overrun_timer = 0.75
	_last_throttle = throttle

	_telemetry.clear()
	for k in telemetry.keys():
		_telemetry[k] = telemetry[k]

	if use_recorded_runtime:
		if is_instance_valid(recorded_engine) and recorded_engine.has_method("update_telemetry"):
			recorded_engine.call("update_telemetry", telemetry)
		if is_instance_valid(recorded_tires) and recorded_tires.has_method("update_telemetry"):
			recorded_tires.call("queue_telemetry", telemetry)
		if is_instance_valid(recorded_chassis) and recorded_chassis.has_method("update_telemetry"):
			recorded_chassis.call("update_telemetry", telemetry)


func trigger_impact(strength: float = 1.0) -> void:
	if use_recorded_runtime and is_instance_valid(recorded_chassis):
		if recorded_chassis.has_method("trigger_impact"):
			recorded_chassis.call("trigger_impact", 20.0 * clampf(strength, 0.0, 1.0), strength)
		return
	_play_event("collision", clampf(strength, 0.0, 1.0))


func trigger_collision(strength: float = 1.0) -> void:
	trigger_impact(strength)


func trigger_suspension(strength: float = 1.0) -> void:
	if use_recorded_runtime and is_instance_valid(recorded_chassis):
		if recorded_chassis.has_method("trigger_suspension"):
			recorded_chassis.call("trigger_suspension", strength)
		return
	_play_event("suspension", clampf(strength, 0.0, 1.0))


func trigger_gear_shift(from_gear: int = 1, to_gear: int = 2) -> void:
	if use_recorded_runtime and is_instance_valid(recorded_engine):
		if recorded_engine.has_method("trigger_gear_shift"):
			recorded_engine.call("trigger_gear_shift", from_gear, to_gear)
		return
	_play_event("gearshift", 0.55)


func trigger_overrun_backfire() -> void:
	if use_recorded_runtime and is_instance_valid(recorded_engine):
		if recorded_engine.has_method("trigger_overrun_backfire"):
			recorded_engine.call("trigger_overrun_backfire")
	_overrun_timer = 0.75


func _physics_process(_delta: float) -> void:
	if not _tracking_vehicle:
		return
	if not is_instance_valid(_bound_vehicle):
		_bound_vehicle = null
		_tracking_vehicle = false
		_previous_springs.clear()
		_reset_transition_state()
		_reset_telemetry()
		return
	update_telemetry(AsterAudioTelemetryScript.from_gevp(_bound_vehicle))
	# Recorded chassis owns its own contact and spring events.
	if not use_recorded_runtime:
		_monitor_suspension()


func _process(delta: float) -> void:
	if use_recorded_runtime:
		# Apply the existing per-car gain control to the actual recorded mix.
		if is_instance_valid(recorded_engine):
			recorded_engine.set("master_gain", master_gain)
		if is_instance_valid(recorded_tires):
			recorded_tires.set("master_tire_gain", master_gain)
		return
	var step := maxf(delta, 0.0)
	_clock += step
	_shift_timer = maxf(0.0, _shift_timer - step)
	_overrun_timer = maxf(0.0, _overrun_timer - step)
	_suspension_cooldown = maxf(0.0, _suspension_cooldown - step)

	if _profile_fading:
		_profile_fade = minf(1.0, _profile_fade + step / PROFILE_FADE_SECONDS)
	_compute_targets_into(_telemetry, _car_profile, _mix_targets)
	var alpha := 1.0 - exp(-step * 12.0)
	for band in ENGINE_BANDS:
		var name: String = "engine_" + band
		_smooth_gain(name, float(_mix_targets[name]) * (0.36 if _shift_timer > 0.0 else 1.0), alpha)
		if _players.has(name):
			var engine: AudioStreamPlayer = _players[name]
			engine.pitch_scale = lerpf(engine.pitch_scale, float(_mix_targets["pitch_" + band]) * (0.85 if _shift_timer > 0.0 else 1.0), alpha)
	for name in LOOP_NAMES:
		var target := float(_mix_targets[name])
		if name == "overrun":
			target += 0.17 * _overrun_timer
		elif name == "countryside":
			target *= ambient_gain
		_smooth_gain(name, target, alpha)

	var peak_sum := 0.0
	for band in ENGINE_BANDS:
		var key: String = "engine_" + band
		var engine_gain := float(_gains.get(key, 0.0))
		if _profile_fading:
			engine_gain = maxf(engine_gain, float(_outgoing_gains.get(key, 0.0)))
		peak_sum += engine_gain * 0.80
	for name in LOOP_NAMES:
		peak_sum += float(_gains.get(name, 0.0)) * 0.60
	var limiter := minf(1.0, LOOP_PEAK_BUDGET / maxf(peak_sum, 0.0001))
	for band in ENGINE_BANDS:
		var key: String = "engine_" + band
		if _players.has(key):
			_apply_volume(_players[key], float(_gains[key]) * _profile_fade, limiter)
		if _profile_fading and _alternate_engines.has(band):
			_apply_volume(_alternate_engines[band], float(_outgoing_gains.get(key, 0.0)) * (1.0 - _profile_fade), limiter)
	for name in LOOP_NAMES:
		if _players.has(name):
			_apply_volume(_players[name], float(_gains[name]), limiter)
	if _profile_fading and _profile_fade >= 1.0:
		_profile_fading = false
		for band in ENGINE_BANDS:
			if _alternate_engines.has(band):
				(_alternate_engines[band] as AudioStreamPlayer).stop()
		if _queued_profile != "":
			var next_profile := _queued_profile
			_queued_profile = ""
			set_profile(next_profile)


static func compute_targets(t: Dictionary, profile: String = "vela_gt") -> Dictionary:
	var result := {}
	_compute_targets_into(t, profile, result)
	return result


static func _compute_targets_into(t: Dictionary, profile: String, out: Dictionary) -> void:
	var cfg: Dictionary = PROFILES.get(profile, PROFILES["vela_gt"])
	var idle := maxf(500.0, float(t.get("idle_rpm", cfg["idle"])))
	var redline := maxf(idle + 500.0, float(t.get("max_rpm", cfg["redline"])))
	var rpm := clampf(float(t.get("rpm", idle)), idle, redline * 1.1)
	var stage := clampf((rpm - idle) / (redline - idle), 0.0, 1.0)
	var throttle := clampf(float(t.get("throttle", 0.0)), 0.0, 1.0)
	var load := clampf(float(t.get("load", throttle)), 0.0, 1.0)
	var speed := maxf(0.0, float(t.get("speed_mps", 0.0)))
	var grip := clampf(float(t.get("grip", 1.0)), 0.0, 1.0)
	var slip := clampf(float(t.get("lateral_slip", 0.0)), 0.0, 1.0)
	var ground := bool(t.get("on_ground", true))
	var handbrake := bool(t.get("handbrake", false))
	var surface := str(t.get("surface", "asphalt")).to_lower()
	if not SURFACES.has(surface):
		surface = "asphalt"
	var base := float(cfg["gain"]) * (0.24 + 0.44 * load + 0.32 * throttle)
	var low := 1.0 - smoothstep(0.13, 0.48, stage)
	var mid := smoothstep(0.11, 0.42, stage) * (1.0 - smoothstep(0.58, 0.90, stage))
	var high := smoothstep(0.56, 0.90, stage)
	var rolling := smoothstep(1.0, 35.0, speed) * (1.0 if ground else 0.0)
	var skid := clampf((slip - 0.16) * 1.6 + (0.33 if handbrake else 0.0) + (1.0 - grip) * 0.50, 0.0, 1.0)
	skid *= smoothstep(2.0, 10.0, speed) * (1.0 if ground else 0.0)
	var overrun := (1.0 - throttle) * stage * (0.40 if bool(t.get("engine_braking", throttle < 0.1)) else 0.15)
	out["engine_low"] = base * low
	out["engine_mid"] = base * mid
	out["engine_high"] = base * high
	out["pitch_low"] = clampf(rpm / 2100.0, 0.63, 1.65)
	out["pitch_mid"] = clampf(rpm / 4250.0, 0.65, 1.6)
	out["pitch_high"] = clampf(rpm / 6600.0, 0.62, 1.58)
	out["roll_asphalt"] = rolling * (0.26 if surface == "asphalt" else 0.0)
	out["roll_gravel"] = rolling * (0.43 if surface == "gravel" else 0.0)
	out["roll_grass"] = rolling * (0.30 if surface == "grass" else 0.0)
	out["tire_squeal"] = skid * (0.52 if surface == "asphalt" else 0.0)
	out["tire_skid"] = skid * (0.56 if surface != "asphalt" else 0.0)
	out["overrun"] = overrun * 0.30
	out["wind"] = clampf(pow(speed / 52.0, 1.3), 0.0, 0.88) * 0.62
	out["countryside"] = 0.20


func _smooth_gain(name: String, target: float, alpha: float) -> void:
	_gains[name] = lerpf(float(_gains.get(name, 0.0)), target, alpha)


func _apply_volume(player: AudioStreamPlayer, gain: float, limiter: float) -> void:
	var final_mult: float = gain * clampf(master_gain, 0.0, 1.0) * limiter
	if use_recorded_runtime:
		final_mult *= 0.0001
	player.volume_db = linear_to_db(maxf(0.0001, final_mult))


func _make_player(label: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = label.replace(" ", "_")
	player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	player.volume_db = -80.0
	add_child(player)
	return player


func _asset(name: String) -> AudioStreamWAV:
	var path: String = "res://modules/audio/assets/".path_join(name + ".wav")
	var stream: AudioStreamWAV = RecordedEngineScript.EngineWavLoaderScript.load_wav(path)
	if stream == null:
		push_warning("Aster audio missing/invalid WAV: " + path)
	return stream


func _set_loop(player: AudioStreamPlayer, name: String) -> void:
	var wav := _asset(name)
	if wav == null:
		player.stop()
		return
	player.stop()
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	var sample_frames := int(round(wav.get_length() * float(wav.mix_rate)))
	wav.loop_end = maxi(1, sample_frames - 1)
	player.stream = wav
	player.play()


func _play_event(name: String, strength: float) -> bool:
	if _event_players.is_empty() or strength <= 0.01 or not _event_streams.has(name):
		return false
	if _clock < float(_event_ready_at.get(name, -1.0)):
		return false
	_event_ready_at[name] = _clock + float(EVENT_COOLDOWNS.get(name, 0.10))
	var player := _event_players[_event_index]
	_event_index = (_event_index + 1) % _event_players.size()
	player.stop()
	player.stream = _event_streams[name]
	player.pitch_scale = 0.96 + 0.035 * float(_event_index)
	player.volume_db = linear_to_db(maxf(0.0001, clampf(strength, 0.0, 1.0) * clampf(master_gain, 0.0, 1.0) * EVENT_VOICE_GAIN))
	player.play()
	return true


func _monitor_suspension() -> void:
	if not _has_property(_bound_vehicle, "wheel_array"):
		return
	var wheels: Variant = _bound_vehicle.get("wheel_array")
	if not (wheels is Array):
		return
	for item in (wheels as Array):
		if not (item is Object) or not is_instance_valid(item):
			continue
		var wheel: Object = item
		if not wheel.has_method("is_colliding") or not bool(wheel.call("is_colliding")):
			continue
		if not _has_property(wheel, "spring_current_length"):
			continue
		var id := wheel.get_instance_id()
		var spring := float(wheel.get("spring_current_length"))
		if _previous_springs.has(id):
			var compression := float(_previous_springs[id]) - spring
			if _suspension_cooldown <= 0.0 and compression > 0.055 and float(_telemetry.get("speed_mps", 0.0)) > 2.0:
				trigger_suspension(clampf(compression / 0.20, 0.2, 0.8))
				_suspension_cooldown = 0.20
		_previous_springs[id] = spring


func _on_body_entered(_body: Node) -> void:
	if is_instance_valid(_bound_vehicle):
		var speed := float(_telemetry.get("speed_mps", 0.0))
		if speed > 4.0:
			trigger_collision(clampf((speed - 4.0) / 16.0, 0.15, 1.0))


func _has_property(object: Object, property_name: String) -> bool:
	if not is_instance_valid(object):
		return false
	for entry in object.get_property_list():
		if str(entry.get("name", "")) == property_name:
			return true
	return false
