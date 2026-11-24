class_name RecordedEngineController
extends Node
## Recorded engine sound controller driven by manifest.json.
## Supports vela_gt (flat-six), kestrel_xr (V8), and orion_rs (four-cylinder fallback).
## Features constant-power cos/sin anchor blending, ON/OFF load blending,
## RPM (30-60ms) and throttle (80ms) smoothing, rev limiter stutter,
## gear shift torque-cut envelope (80-140ms) & clunk, and overrun backfire.

const EngineWavLoaderScript := preload("engine_wav_loader.gd")
const EngineProfileManifestScript := preload("engine_profile_manifest.gd")

# Profile defaults
const PROFILE_CONFIGS := {
	"vela_gt": {
		"label": "Vela GT (Flat-Six)",
		"idle_rpm": 950.0,
		"redline_rpm": 8500.0,
		"gain": 0.85,
		"intake_ratio": 0.55
	},
	"kestrel_xr": {
		"label": "Kestrel XR (V8)",
		"idle_rpm": 800.0,
		"redline_rpm": 7800.0,
		"gain": 0.90,
		"intake_ratio": 0.60
	},
	"orion_rs": {
		"label": "Orion RS (Four-Cylinder Fallback)",
		"idle_rpm": 1000.0,
		"redline_rpm": 8500.0,
		"gain": 0.80,
		"intake_ratio": 0.50
	}
}

const HALF_PI := PI * 0.5

@export var car_profile: String = "vela_gt"
@export var exhaust_bus: StringName = &"Engine_Exhaust"
@export var intake_bus: StringName = &"Engine_Intake"
@export_range(0.0, 2.0, 0.05) var master_gain: float = 1.0

# Smoothing constants (30-60ms for RPM, 80ms for throttle)
@export_range(20.0, 100.0, 1.0) var rpm_smoothing_ms: float = 45.0
@export_range(40.0, 150.0, 1.0) var throttle_smoothing_ms: float = 80.0

# Pitch scaling limits
@export var min_pitch_clamp: float = 0.75
@export var max_pitch_clamp: float = 1.35
@export var sub_idle_min_pitch: float = 0.45

# Rev limiter settings
@export var limiter_frequency: float = 20.0 # 20 Hz stutter
@export var limiter_cut_ratio: float = 0.45 # 45% cut, 55% fire
@export var limiter_cut_gain: float = 0.12 # -18 dB during spark cut

# Gear shift torque cut envelope (80-140ms)
@export_range(80.0, 140.0, 5.0) var torque_cut_duration_ms: float = 110.0
@export var torque_cut_depth: float = 0.20 # -14 dB

# Overrun backfire settings
@export var overrun_rpm_threshold: float = 0.65 # > 65% RPM
@export var overrun_cooldown_s: float = 1.2 # Cooldown in seconds

# Runtime state
var _manifest: RefCounted = null
var _manifest_cache: Dictionary = {}
var _exhaust_players: Dictionary = {} # filename -> AudioStreamPlayer
var _intake_players: Dictionary = {} # filename -> AudioStreamPlayer
var _shift_player: AudioStreamPlayer = null
var _overrun_player: AudioStreamPlayer = null
var _overrun_burst_players: Array[AudioStreamPlayer] = []

var _target_rpm: float = 950.0
var _smoothed_rpm: float = 950.0
var _target_throttle: float = 0.0
var _smoothed_throttle: float = 0.0
var _last_raw_throttle: float = 0.0

var _current_gear: int = 1
var _last_gear: int = 1
var _idle_rpm: float = 950.0
var _redline_rpm: float = 8500.0

# Envelopes
var _shift_timer: float = 0.0
var _shift_envelope: float = 1.0
var _is_on_limiter: bool = false
var _limiter_phase: float = 0.0
var _limiter_envelope: float = 1.0
var _overrun_cooldown_timer: float = 0.0
var _active_overrun_burst: Array[Dictionary] = [] # pending delayed pops


func _ready() -> void:
	if _manifest == null:
		setup(car_profile)
	else:
		_apply_audio_blend()


func setup(profile_name: String = "") -> void:
	_init_auxiliary_players()
	if profile_name != "":
		car_profile = profile_name
	set_profile(car_profile)
	snap_to_idle()


func set_profile(profile_name: String) -> void:
	if not PROFILE_CONFIGS.has(profile_name):
		push_warning("RecordedEngineController: Unknown car profile: " + profile_name + ", defaulting to vela_gt")
		profile_name = "vela_gt"

	car_profile = profile_name
	var cfg: Dictionary = PROFILE_CONFIGS[profile_name]
	_idle_rpm = float(cfg["idle_rpm"])
	_redline_rpm = float(cfg["redline_rpm"])
	if _manifest != null and _manifest.profile_name == profile_name:
		return

	var manifest: RefCounted = null
	if _manifest_cache.has(profile_name):
		manifest = _manifest_cache[profile_name]
	else:
		manifest = EngineProfileManifestScript.load_for_profile(profile_name)
		if manifest != null:
			_manifest_cache[profile_name] = manifest

	if manifest == null:
		push_error("RecordedEngineController: Failed to load manifest for " + profile_name)
		return

	_manifest = manifest
	_rebuild_loop_players()


func snap_to_idle() -> void:
	_target_rpm = _idle_rpm
	_smoothed_rpm = _idle_rpm
	_target_throttle = 0.0
	_smoothed_throttle = 0.0
	_last_raw_throttle = 0.0
	_shift_timer = 0.0
	_shift_envelope = 1.0
	_is_on_limiter = false
	_limiter_phase = 0.0
	_limiter_envelope = 1.0
	_overrun_cooldown_timer = 0.0
	_active_overrun_burst.clear()
	_apply_audio_blend()


func update_telemetry(t: Dictionary) -> void:
	var raw_rpm := float(t.get("rpm", _idle_rpm))
	var raw_throttle := clampf(float(t.get("throttle", 0.0)), 0.0, 1.0)
	var gear := int(t.get("gear", _current_gear))

	if t.has("idle_rpm"):
		_idle_rpm = float(t["idle_rpm"])
	if t.has("max_rpm"):
		_redline_rpm = float(t["max_rpm"])
	elif t.has("redline"):
		_redline_rpm = float(t["redline"])

	_target_rpm = maxf(100.0, raw_rpm)
	_target_throttle = raw_throttle

	# Check for gear shift
	if _last_gear != -999 and gear != 0 and _last_gear != 0 and gear != _last_gear:
		trigger_gear_shift(_last_gear, gear)
	_last_gear = gear
	_current_gear = gear

	# Check for overrun backfire on rapid lift-off above 65% RPM
	_check_overrun(_target_rpm, _redline_rpm, raw_throttle)


func trigger_gear_shift(_from_gear: int = 1, _to_gear: int = 2) -> void:
	_shift_timer = torque_cut_duration_ms * 0.001
	_play_shift_clunk()


func trigger_overrun_backfire() -> void:
	if _overrun_player != null and _overrun_player.stream != null:
		var pitch := randf_range(0.92, 1.15)
		var vol := randf_range(0.70, 1.0) * master_gain
		_overrun_player.pitch_scale = pitch
		_overrun_player.volume_db = linear_to_db(maxf(0.0001, vol))
		if _overrun_player.is_inside_tree():
			_overrun_player.play()

	# Schedule 1-3 delayed pops for authentic backfire crackle
	_active_overrun_burst.clear()
	var pop_count := randi_range(1, 3)
	var cumulative_delay := 0.0
	for i in range(pop_count):
		cumulative_delay += randf_range(0.06, 0.13)
		_active_overrun_burst.append({
			"delay": cumulative_delay,
			"pitch": randf_range(0.85, 1.30),
			"gain": randf_range(0.40, 0.85)
		})


func _check_overrun(rpm: float, redline: float, raw_throttle: float) -> void:
	var rpm_ratio := rpm / maxf(1.0, redline)
	# Rapid lift-off: throttle was above 55% and dropped below 15%
	if _last_raw_throttle > 0.55 and raw_throttle < 0.15:
		if rpm_ratio >= overrun_rpm_threshold and _overrun_cooldown_timer <= 0.0:
			trigger_overrun_backfire()
			_overrun_cooldown_timer = overrun_cooldown_s

	_last_raw_throttle = raw_throttle


func _process(delta: float) -> void:
	var dt := maxf(0.0, delta)
	if dt <= 0.0 or _manifest == null:
		return

	# 1. Exponential smoothing for RPM (30-60ms) and throttle (80ms)
	var rpm_alpha := 1.0 - exp(-dt / maxf(0.001, rpm_smoothing_ms * 0.001))
	_smoothed_rpm = lerpf(_smoothed_rpm, _target_rpm, rpm_alpha)

	var throttle_alpha := 1.0 - exp(-dt / maxf(0.001, throttle_smoothing_ms * 0.001))
	_smoothed_throttle = lerpf(_smoothed_throttle, _target_throttle, throttle_alpha)

	# 2. Update gear shift torque-cut envelope
	if _shift_timer > 0.0:
		_shift_timer = maxf(0.0, _shift_timer - dt)
		var dur := maxf(0.001, torque_cut_duration_ms * 0.001)
		var progress := 1.0 - (_shift_timer / dur)
		_shift_envelope = lerpf(torque_cut_depth, 1.0, smoothstep(0.10, 1.0, progress))
	else:
		_shift_envelope = 1.0

	# 3. Update rev limiter stutter envelope
	if _smoothed_rpm >= _redline_rpm * 0.985:
		_is_on_limiter = true
		_limiter_phase = fmod(_limiter_phase + dt * limiter_frequency, 1.0)
		var in_cut: bool = _limiter_phase < limiter_cut_ratio
		var target_limiter_gain := limiter_cut_gain if in_cut else 1.0
		var limiter_rate := 1.0 - exp(-dt / 0.008)
		_limiter_envelope = lerpf(_limiter_envelope, target_limiter_gain, limiter_rate)
	else:
		_is_on_limiter = false
		_limiter_phase = 0.0
		var limiter_recovery := 1.0 - exp(-dt / 0.030)
		_limiter_envelope = lerpf(_limiter_envelope, 1.0, limiter_recovery)

	# 4. Update overrun backfire cooldown and delayed burst pops
	if _overrun_cooldown_timer > 0.0:
		_overrun_cooldown_timer = maxf(0.0, _overrun_cooldown_timer - dt)

	_update_overrun_burst(dt)

	# 5. Compute anchor blends and apply to audio players
	_apply_audio_blend()


func _update_overrun_burst(dt: float) -> void:
	if _active_overrun_burst.is_empty():
		return

	var remaining: Array[Dictionary] = []
	for pop in _active_overrun_burst:
		var delay: float = float(pop["delay"]) - dt
		if delay <= 0.0:
			_play_burst_pop(float(pop["pitch"]), float(pop["gain"]))
		else:
			pop["delay"] = delay
			remaining.append(pop)
	_active_overrun_burst = remaining


func _play_burst_pop(pitch: float, gain: float) -> void:
	if _overrun_burst_players.is_empty():
		return
	var player: AudioStreamPlayer = _overrun_burst_players[randi() % _overrun_burst_players.size()]
	if player.stream != null:
		player.pitch_scale = pitch
		player.volume_db = linear_to_db(maxf(0.0001, gain * master_gain))
		if player.is_inside_tree():
			player.play()


func _apply_audio_blend() -> void:
	if _manifest == null:
		return

	var cfg: Dictionary = PROFILE_CONFIGS.get(car_profile, PROFILE_CONFIGS["vela_gt"])
	var base_profile_gain: float = float(cfg.get("gain", 0.85))
	var intake_ratio: float = float(cfg.get("intake_ratio", 0.55))

	var overall_gain := base_profile_gain * master_gain * _shift_envelope * _limiter_envelope

	# Constant-power ON vs OFF load layer blend
	var on_layer_gain: float
	var off_layer_gain: float

	if _manifest.has_off_layer:
		on_layer_gain = sin(_smoothed_throttle * HALF_PI)
		off_layer_gain = cos(_smoothed_throttle * HALF_PI)
	else:
		# Single layer fallback (e.g. Orion RS)
		on_layer_gain = lerpf(0.40, 1.0, _smoothed_throttle)
		off_layer_gain = 0.0

	# Calculate per-layer active anchor gains and pitch scales
	var on_data := _compute_layer_anchors("on", _smoothed_rpm)
	var off_data := _compute_layer_anchors("off", _smoothed_rpm) if _manifest.has_off_layer else {}

	# 1. Update Exhaust Players (plays both ON and OFF layers)
	for loop_entry in _manifest.loops:
		var fname: String = str(loop_entry["file"])
		if not _exhaust_players.has(fname):
			continue
		var player: AudioStreamPlayer = _exhaust_players[fname]
		var layer: String = str(loop_entry["layer"])
		var file_gain: float = float(loop_entry.get("gain", 1.0))

		var anchor_data: Dictionary = on_data if layer == "on" else off_data
		var layer_weight: float = on_layer_gain if layer == "on" else off_layer_gain

		var anchor_gain: float = float(anchor_data.get("gains", {}).get(fname, 0.0))
		var anchor_pitch: float = float(anchor_data.get("pitches", {}).get(fname, 1.0))

		var final_gain := anchor_gain * layer_weight * file_gain * overall_gain
		_set_anchor_voice(player, final_gain, anchor_pitch)

	# 2. Update Intake Players (induction roar on ON loops, scaled by throttle)
	var intake_throttle_boost := pow(_smoothed_throttle, 1.2) * intake_ratio
	for anchor in _manifest.on_anchors:
		var fname: String = str(anchor["file"])
		if not _intake_players.has(fname):
			continue
		var player: AudioStreamPlayer = _intake_players[fname]
		var file_gain: float = float(anchor.get("gain", 1.0))

		var anchor_gain: float = float(on_data.get("gains", {}).get(fname, 0.0))
		var anchor_pitch: float = float(on_data.get("pitches", {}).get(fname, 1.0))

		var intake_gain := anchor_gain * intake_throttle_boost * file_gain * overall_gain
		_set_anchor_voice(player, intake_gain, anchor_pitch)


func _set_anchor_voice(player: AudioStreamPlayer, gain: float, pitch: float) -> void:
	# Stop its decoder below -80 dB. The existing adjacent-anchor crossfade
	# brings each loop in at an inaudible level before it carries the engine note.
	if gain <= 0.0001:
		if player.volume_db > -80.0:
			player.volume_db = -80.0
		if player.playing:
			player.stop()
		return
	player.volume_db = linear_to_db(gain)
	player.pitch_scale = pitch
	if player.is_inside_tree() and not player.playing:
		player.play()


func _compute_layer_anchors(layer: String, rpm: float) -> Dictionary:
	var anchors: Array = _manifest.get_anchors_for_layer(layer)
	if anchors.is_empty():
		return {"gains": {}, "pitches": {}}

	var gains: Dictionary = {}
	var pitches: Dictionary = {}

	var bracket: Dictionary = _manifest.find_bracketing_anchors(layer, rpm)
	if bracket.is_empty():
		return {"gains": gains, "pitches": pitches}

	var low_anchor: Dictionary = bracket["low"]
	var high_anchor: Dictionary = bracket["high"]
	var is_single: bool = bool(bracket.get("is_single", false))
	var t: float = float(bracket.get("t", 0.0))

	var low_file: String = str(low_anchor["file"])
	var high_file: String = str(high_anchor["file"])
	var low_rpm: float = float(low_anchor["rpm"])
	var high_rpm: float = float(high_anchor["rpm"])

	var is_sub_idle := rpm < low_rpm

	if is_single or low_file == high_file:
		var target_file := high_file if t >= 1.0 else low_file
		var target_rpm := high_rpm if t >= 1.0 else low_rpm
		gains[target_file] = 1.0
		pitches[target_file] = _calc_pitch(rpm, target_rpm, is_sub_idle)
	else:
		# Constant-power cos/sin crossfade between adjacent anchors
		gains[low_file] = cos(t * HALF_PI)
		gains[high_file] = sin(t * HALF_PI)
		pitches[low_file] = _calc_pitch(rpm, low_rpm, is_sub_idle)
		pitches[high_file] = _calc_pitch(rpm, high_rpm, false)

	return {"gains": gains, "pitches": pitches}


func _calc_pitch(current_rpm: float, anchor_rpm: float, is_sub_idle: bool) -> float:
	var ratio := current_rpm / maxf(1.0, anchor_rpm)
	if is_sub_idle:
		return clampf(ratio, sub_idle_min_pitch, max_pitch_clamp)
	return clampf(ratio, min_pitch_clamp, max_pitch_clamp)


func _rebuild_loop_players() -> void:
	# Stop and cleanup existing loop players
	for p in _exhaust_players.values():
		if is_instance_valid(p):
			p.stop()
			if p.get_parent() == self:
				remove_child(p)
			p.queue_free()
	_exhaust_players.clear()

	for p in _intake_players.values():
		if is_instance_valid(p):
			p.stop()
			if p.get_parent() == self:
				remove_child(p)
			p.queue_free()
	_intake_players.clear()

	if _manifest == null:
		return

	var safe_exhaust_bus := _resolve_bus(exhaust_bus)
	var safe_intake_bus := _resolve_bus(intake_bus)

	# Create Exhaust players for all loops in manifest
	for loop_entry in _manifest.loops:
		var fname: String = str(loop_entry["file"])
		var full_path: String = str(loop_entry["full_path"])
		var wav := EngineWavLoaderScript.load_wav(full_path)
		if wav != null:
			EngineWavLoaderScript.configure_loop(wav, true)
			var player := AudioStreamPlayer.new()
			player.name = "Exhaust_" + fname.get_basename()
			player.bus = safe_exhaust_bus
			player.stream = wav
			player.volume_db = -80.0
			add_child(player)
			_exhaust_players[fname] = player
		else:
			push_warning("RecordedEngineController: Could not load exhaust loop: " + full_path)

	# Create Intake players for ON loops in manifest
	for anchor in _manifest.on_anchors:
		var fname: String = str(anchor["file"])
		var full_path: String = str(anchor["full_path"])
		var wav := EngineWavLoaderScript.load_wav(full_path)
		if wav != null:
			EngineWavLoaderScript.configure_loop(wav, true)
			var player := AudioStreamPlayer.new()
			player.name = "Intake_" + fname.get_basename()
			player.bus = safe_intake_bus
			player.stream = wav
			player.volume_db = -80.0
			add_child(player)
			_intake_players[fname] = player
		else:
			push_warning("RecordedEngineController: Could not load intake loop: " + full_path)


func _init_auxiliary_players() -> void:
	if _shift_player != null:
		return

	var safe_exhaust_bus := _resolve_bus(exhaust_bus)

	# Gear shift player
	_shift_player = AudioStreamPlayer.new()
	_shift_player.name = "ShiftClunk"
	_shift_player.bus = safe_exhaust_bus
	var shift_wav := EngineWavLoaderScript.load_wav("res://modules/audio/assets/gearshift.wav")
	if shift_wav != null:
		EngineWavLoaderScript.configure_loop(shift_wav, false)
		_shift_player.stream = shift_wav
	add_child(_shift_player)

	# Overrun backfire primary player
	_overrun_player = AudioStreamPlayer.new()
	_overrun_player.name = "OverrunBackfire"
	_overrun_player.bus = safe_exhaust_bus
	var overrun_wav := EngineWavLoaderScript.load_wav("res://modules/audio/assets/overrun.wav")
	if overrun_wav != null:
		EngineWavLoaderScript.configure_loop(overrun_wav, false)
		_overrun_player.stream = overrun_wav
	add_child(_overrun_player)

	# Overrun burst pool for crackle pops
	for i in range(3):
		var p := AudioStreamPlayer.new()
		p.name = "OverrunBurst_%d" % i
		p.bus = safe_exhaust_bus
		if overrun_wav != null:
			p.stream = overrun_wav
		add_child(p)
		_overrun_burst_players.append(p)


func _play_shift_clunk() -> void:
	if _shift_player != null and _shift_player.stream != null:
		_shift_player.pitch_scale = randf_range(0.95, 1.05)
		_shift_player.volume_db = linear_to_db(maxf(0.0001, 0.70 * master_gain))
		if _shift_player.is_inside_tree():
			_shift_player.play()


func _resolve_bus(bus_name: StringName) -> StringName:
	if AudioServer.get_bus_index(bus_name) != -1:
		return bus_name
	return &"Master"


# Pure calculation helper for deterministic testing and analysis
static func compute_blend_state(rpm: float, throttle: float, manifest_data: Dictionary) -> Dictionary:
	var manifest := EngineProfileManifestScript.new()
	manifest.parse_dictionary(manifest_data)

	var clamped_throttle := clampf(throttle, 0.0, 1.0)
	var on_layer_gain: float
	var off_layer_gain: float

	if manifest.has_off_layer:
		on_layer_gain = sin(clamped_throttle * HALF_PI)
		off_layer_gain = cos(clamped_throttle * HALF_PI)
	else:
		on_layer_gain = lerpf(0.40, 1.0, clamped_throttle)
		off_layer_gain = 0.0

	var on_anchors := manifest.on_anchors
	var off_anchors := manifest.off_anchors

	var on_gains: Dictionary = {}
	var on_pitches: Dictionary = {}
	var off_gains: Dictionary = {}
	var off_pitches: Dictionary = {}

	# On anchors
	var on_bracket := manifest.find_bracketing_anchors("on", rpm)
	if not on_bracket.is_empty():
		var low_a: Dictionary = on_bracket["low"]
		var high_a: Dictionary = on_bracket["high"]
		var is_s: bool = bool(on_bracket.get("is_single", false))
		var t: float = float(on_bracket.get("t", 0.0))
		var low_f: String = str(low_a["file"])
		var high_f: String = str(high_a["file"])
		var low_r: float = float(low_a["rpm"])
		var high_r: float = float(high_a["rpm"])

		if is_s or low_f == high_f:
			var tf := high_f if t >= 1.0 else low_f
			var tr := high_r if t >= 1.0 else low_r
			on_gains[tf] = 1.0
			on_pitches[tf] = clampf(rpm / tr, 0.45, 1.35)
		else:
			on_gains[low_f] = cos(t * HALF_PI)
			on_gains[high_f] = sin(t * HALF_PI)
			on_pitches[low_f] = clampf(rpm / low_r, 0.45, 1.35)
			on_pitches[high_f] = clampf(rpm / high_r, 0.75, 1.35)

	# Off anchors
	if manifest.has_off_layer:
		var off_bracket := manifest.find_bracketing_anchors("off", rpm)
		if not off_bracket.is_empty():
			var low_a: Dictionary = off_bracket["low"]
			var high_a: Dictionary = off_bracket["high"]
			var is_s: bool = bool(off_bracket.get("is_single", false))
			var t: float = float(off_bracket.get("t", 0.0))
			var low_f: String = str(low_a["file"])
			var high_f: String = str(high_a["file"])
			var low_r: float = float(low_a["rpm"])
			var high_r: float = float(high_a["rpm"])

			if is_s or low_f == high_f:
				var tf := high_f if t >= 1.0 else low_f
				var tr := high_r if t >= 1.0 else low_r
				off_gains[tf] = 1.0
				off_pitches[tf] = clampf(rpm / tr, 0.45, 1.35)
			else:
				off_gains[low_f] = cos(t * HALF_PI)
				off_gains[high_f] = sin(t * HALF_PI)
				off_pitches[low_f] = clampf(rpm / low_r, 0.45, 1.35)
				off_pitches[high_f] = clampf(rpm / high_r, 0.75, 1.35)

	# Calculate power sums to verify constant-power blending
	var on_power_sum := 0.0
	for g in on_gains.values():
		on_power_sum += float(g) * float(g)

	var off_power_sum := 0.0
	for g in off_gains.values():
		off_power_sum += float(g) * float(g)

	var layer_power_sum := on_layer_gain * on_layer_gain + off_layer_gain * off_layer_gain

	return {
		"on_layer_gain": on_layer_gain,
		"off_layer_gain": off_layer_gain,
		"layer_power_sum": layer_power_sum,
		"on_gains": on_gains,
		"on_pitches": on_pitches,
		"on_power_sum": on_power_sum,
		"off_gains": off_gains,
		"off_pitches": off_pitches,
		"off_power_sum": off_power_sum
	}
