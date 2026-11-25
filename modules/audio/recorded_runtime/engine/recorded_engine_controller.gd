class_name RecordedEngineController
extends Node
## Recorded engine sound controller driven by manifest.json.
## Supports vela_gt (flat-six), kestrel_xr (V8), and orion_rs (four-cylinder fallback).
## Features constant-power cos/sin anchor blending, ON/OFF load blending,
## RPM (30-60ms) and throttle (80ms) smoothing, rev limiter stutter,
## gear shift torque-cut envelope (80-140ms) & clunk, and overrun backfire.

const EngineWavLoaderScript := preload("engine_wav_loader.gd")
const EngineProfileManifestScript := preload("engine_profile_manifest.gd")
const PhaseGrainEngineScript := preload("phase_grain_engine.gd")

# Profile defaults
const PROFILE_CONFIGS := {
	# Dedicated hero-car voicings. Banks are explicitly provisional until a
	# source-cleared V12 / twin-turbo V8 recording set is available.
	"aventador_svj": {
		"label": "Aventador SVJ (recorded V12 family audition)",
		"fallback_bank": "vela_gt", "idle_rpm": 900.0, "redline_rpm": 8700.0,
		"gain": 0.98, "intake_ratio": 0.0, "rpm_ms": 35.0,
		"throttle_ms": 60.0, "shift_ms": 125.0, "shift_depth": 0.22,
		"shift_gain": 0.0, "overrun_gain": 0.0, "synthetic_events": false, "intake_lag_ms": 60.0,
		"load_curve": 0.85, "idle_gain": 0.58, "firing_order": 6.0
	},
	"mclaren_senna": {
		"label": "McLaren Senna (recorded McLaren V8 family audition)",
		"fallback_bank": "kestrel_xr", "idle_rpm": 980.0, "redline_rpm": 8000.0,
		"gain": 0.94, "intake_ratio": 0.0, "rpm_ms": 42.0,
		"throttle_ms": 75.0, "shift_ms": 85.0, "shift_depth": 0.42,
		"shift_gain": 0.0, "overrun_gain": 0.0, "synthetic_events": false, "intake_lag_ms": 165.0,
		"load_curve": 1.12, "idle_gain": 0.60, "firing_order": 4.0
	},
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
@export var min_pitch_clamp: float = 0.65
@export var max_pitch_clamp: float = 1.55
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
var _reflection_players: Dictionary = {} # wet-only mirrors of active exhaust loops
var _prepared_loops: Dictionary = {}
var _shift_player: AudioStreamPlayer = null
var _overrun_player: AudioStreamPlayer = null
var _overrun_burst_players: Array[AudioStreamPlayer] = []

var _target_rpm: float = 950.0
var _smoothed_rpm: float = 950.0
var _target_throttle: float = 0.0
var _smoothed_throttle: float = 0.0
var _last_raw_throttle: float = 0.0
var _intake_load: float = 0.0
var _active_bank: String = ""
var _grain_engine: PhaseGrainEngine
@export var use_phase_grains := true

var _current_gear: int = 1
var _last_gear: int = -999
var _live_shift: bool = false
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
	set_profile(profile_name if profile_name != "" else car_profile)
	snap_to_idle()


func set_profile(profile_name: String) -> void:
	if not PROFILE_CONFIGS.has(profile_name):
		push_warning("RecordedEngineController: Unknown car profile: " + profile_name + ", defaulting to vela_gt")
		profile_name = "vela_gt"

	if _manifest != null and car_profile == profile_name:
		return
	car_profile = profile_name
	var cfg: Dictionary = PROFILE_CONFIGS[profile_name]
	_idle_rpm = float(cfg["idle_rpm"])
	_redline_rpm = float(cfg["redline_rpm"])
	rpm_smoothing_ms = float(cfg.get("rpm_ms", 45.0))
	throttle_smoothing_ms = float(cfg.get("throttle_ms", 80.0))
	torque_cut_duration_ms = float(cfg.get("shift_ms", 110.0))
	torque_cut_depth = float(cfg.get("shift_depth", 0.20))
	# Prefer a real dedicated bank when installed. Existing proxies remain
	# explicit, and their original manifests and attribution are unchanged.
	var bank := profile_name
	var manifest_path := "res://assets/audio/recorded/payload/engines/%s/manifest.json" % profile_name
	if not FileAccess.file_exists(manifest_path):
		bank = str(cfg.get("fallback_bank", profile_name))
	var manifest: RefCounted = null
	if _manifest_cache.has(bank):
		manifest = _manifest_cache[bank]
	else:
		manifest = EngineProfileManifestScript.load_for_profile(bank)
		if manifest != null:
			_manifest_cache[bank] = manifest

	if manifest == null:
		push_error("RecordedEngineController: Failed to load manifest for " + profile_name)
		return

	_manifest = manifest
	_active_bank = bank
	# Local-only professional recordings: opt in per process, never replace
	# the bundled bank or silently publish restricted source files.
	if use_phase_grains and cfg.has("firing_order") and OS.get_environment("ASTER_NATIVE_AUDIO") == "1":
		var native: RefCounted = EngineProfileManifestScript.load_native_bank(profile_name)
		if native != null:
			_manifest = native
			_active_bank = profile_name
	_rebuild_loop_players()
	if _manifest.bank_status == "local_source_native_audition":
		if not is_instance_valid(_grain_engine):
			push_warning("Native bank preparation failed; using bundled audition bank")
			_manifest = manifest
			_active_bank = bank
			_rebuild_loop_players()
		else:
			print("Source-native local audio active: ", profile_name)


func snap_to_idle() -> void:
	_target_rpm = _idle_rpm
	_smoothed_rpm = _idle_rpm
	_target_throttle = 0.0
	_smoothed_throttle = 0.0
	_intake_load = 0.0
	_last_raw_throttle = 0.0
	_last_gear = -999
	_live_shift = false
	_shift_timer = 0.0
	_shift_envelope = 1.0
	_is_on_limiter = false
	_limiter_phase = 0.0
	_limiter_envelope = 1.0
	_overrun_cooldown_timer = 0.0
	_active_overrun_burst.clear()
	if is_instance_valid(_grain_engine):
		_grain_engine.reset(_idle_rpm)
	# Reset all active one-shots, not just pending bursts. A previous car's
	# exhaust crackle or gear clunk must never bleed into the next car's idle.
	for voice in [_shift_player, _overrun_player]:
		if is_instance_valid(voice):
			voice.stop()
	for voice in _overrun_burst_players:
		voice.stop()
	_apply_audio_blend()


func update_telemetry(t: Dictionary) -> void:
	var raw_rpm := float(t.get("rpm", _idle_rpm))
	var raw_throttle := clampf(float(t.get("engine_throttle", t.get("throttle", 0.0))), 0.0, 1.0)
	var gear := int(t.get("gear", _current_gear))

	if t.has("idle_rpm"):
		_idle_rpm = float(t["idle_rpm"])
	if t.has("max_rpm"):
		_redline_rpm = float(t["max_rpm"])
	elif t.has("redline"):
		_redline_rpm = float(t["redline"])

	_target_rpm = maxf(100.0, raw_rpm)
	_target_throttle = raw_throttle

	# GEVP cuts torque before current_gear changes. Start the audio cut at
	# that actual shift edge, and do not play another clunk on completion.
	var requested := int(t.get("requested_gear", gear))
	var live_shift := bool(t.get("shift_active", false)) and gear > 0 and requested > 0
	if live_shift and not _live_shift:
		trigger_gear_shift(gear, requested)
	elif not live_shift and not _live_shift and _last_gear > 0 and gear > 0 and gear != _last_gear:
		# Fallback for external telemetry producers without shift state.
		trigger_gear_shift(_last_gear, gear)
	_live_shift = live_shift
	_last_gear = gear
	_current_gear = gear

	# Check for overrun backfire on rapid lift-off above 65% RPM
	_check_overrun(_target_rpm, _redline_rpm, raw_throttle)


func trigger_gear_shift(_from_gear: int = 1, _to_gear: int = 2) -> void:
	_shift_timer = torque_cut_duration_ms * 0.001
	_play_shift_clunk()


func trigger_overrun_backfire() -> void:
	# Hero exhaust banks already contain recorded coast character. Generic
	# synthesized pops obscure that detail; restore only real dedicated events.
	if not bool(PROFILE_CONFIGS[car_profile].get("synthetic_events", true)):
		return
	if _overrun_player != null and _overrun_player.stream != null:
		var pitch := randf_range(0.92, 1.15)
		var event_gain := float(PROFILE_CONFIGS[car_profile].get("overrun_gain", 0.40))
		var vol := randf_range(0.8, 1.15) * event_gain * master_gain
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
			"gain": randf_range(0.15, 0.35)
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
	var cfg: Dictionary = PROFILE_CONFIGS[car_profile]
	var lag := float(cfg.get("intake_lag_ms", 80.0)) * 0.001
	var intake_tau := lag if _target_throttle > _intake_load else 0.055
	_intake_load = lerpf(_intake_load, _target_throttle, 1.0 - exp(-dt / maxf(0.001, intake_tau)))

	# 2. Update gear shift torque-cut envelope
	if _live_shift:
		_shift_timer = 0.0
		_shift_envelope = lerpf(_shift_envelope, torque_cut_depth, 1.0 - exp(-dt / 0.015))
	elif _shift_timer > 0.0:
		_shift_timer = maxf(0.0, _shift_timer - dt)
		var dur := maxf(0.001, torque_cut_duration_ms * 0.001)
		var progress := 1.0 - (_shift_timer / dur)
		_shift_envelope = lerpf(torque_cut_depth, 1.0, smoothstep(0.10, 1.0, progress))
	else:
		_shift_envelope = lerpf(_shift_envelope, 1.0, 1.0 - exp(-dt / 0.050))
		if _shift_envelope > 0.999:
			_shift_envelope = 1.0

	# 3. Legacy-only limiter stutter. Hero audio follows the physical motor RPM;
	# an extra 20 Hz amplitude gate near redline made sustained high RPM quiver.
	if not cfg.has("firing_order") and _smoothed_rpm >= _redline_rpm * 0.985 and _smoothed_throttle > 0.55 and not _live_shift:
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

	# Shared with the diagnostic helper so the tested curve is the live curve.
	var shaped_load := pow(_smoothed_throttle, float(cfg.get("load_curve", 1.0)))
	if use_phase_grains and is_instance_valid(_grain_engine) and _grain_engine.prepared:
		_grain_engine.pump(_smoothed_rpm, shaped_load, overall_gain, _resolve_bus(exhaust_bus), &"Exhaust_Reflection")
		return
	var load_gains := compute_load_gains(_smoothed_rpm, shaped_load, _manifest.off_anchors, float(cfg.get("idle_gain", 0.40)))
	# ON/OFF waveforms from different field sessions do not share phase.
	# Do not duplicate the same sample as "intake" until independent material exists.
	var on_layer_gain := load_gains.x
	var off_layer_gain := load_gains.y

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
		var nominal_pitch := clampf(_smoothed_rpm / maxf(1.0, float(loop_entry["rpm"])), sub_idle_min_pitch, max_pitch_clamp)
		var anchor_pitch: float = float(anchor_data.get("pitches", {}).get(fname, nominal_pitch))
		# Inaudible loops still track the engine clock. This keeps the
		# filtered intake copy and its exhaust counterpart in step.
		player.pitch_scale = anchor_pitch

		var final_gain := anchor_gain * layer_weight * file_gain * overall_gain
		_set_anchor_voice(player, final_gain, anchor_pitch)
		_update_reflection_voice(fname, player, final_gain, anchor_pitch)

	# 2. Update Intake Players (induction roar on ON loops, scaled by throttle)
	var intake_throttle_boost := pow(_intake_load, 1.2) * intake_ratio
	for anchor in _manifest.on_anchors:
		var fname: String = str(anchor["file"])
		if not _intake_players.has(fname):
			continue
		var player: AudioStreamPlayer = _intake_players[fname]
		var file_gain: float = float(anchor.get("gain", 1.0))

		var anchor_gain: float = float(on_data.get("gains", {}).get(fname, 0.0))
		var nominal_pitch := clampf(_smoothed_rpm / maxf(1.0, float(anchor["rpm"])), sub_idle_min_pitch, max_pitch_clamp)
		var anchor_pitch: float = float(on_data.get("pitches", {}).get(fname, nominal_pitch))
		player.pitch_scale = anchor_pitch

		# The current intake is derived from the same ON recording, not an
		# independent microphone. Keep it subordinate to the exhaust layer.
		var intake_gain := anchor_gain * intake_throttle_boost * on_layer_gain * file_gain * overall_gain
		var direct: AudioStreamPlayer = _exhaust_players.get(fname)
		var offset := direct.get_playback_position() if is_instance_valid(direct) and direct.playing else 0.0
		_set_anchor_voice(player, intake_gain, anchor_pitch, offset)

# Keep the scenic branch's active-loop optimization: never run every decoder.
# Start the filtered intake copy at the direct exhaust playback position.
func _set_anchor_voice(player: AudioStreamPlayer, gain: float, pitch: float, offset: float = 0.0) -> void:
	player.pitch_scale = pitch
	if gain <= 0.0001:
		player.volume_db = -80.0
		if player.playing:
			player.stop()
		return
	player.volume_db = linear_to_db(gain)
	if player.is_inside_tree() and not player.playing:
		player.play(offset)


func _compute_layer_anchors(layer: String, rpm: float) -> Dictionary:
	return compute_anchor_pair(_manifest.find_bracketing_anchors(layer, rpm), rpm,
		min_pitch_clamp, max_pitch_clamp, sub_idle_min_pitch)


# Crossfade only where both recordings can be pitched to the same nominal RPM.
# Broad linear blends outside this overlap produce two different firing frequencies.
static func compute_anchor_pair(bracket: Dictionary, rpm: float, min_pitch: float = 0.65,
		max_pitch: float = 1.55, idle_pitch: float = 0.45) -> Dictionary:
	var gains := {}
	var pitches := {}
	if bracket.is_empty():
		return {"gains": gains, "pitches": pitches}
	var low: Dictionary = bracket["low"]
	var high: Dictionary = bracket["high"]
	var low_file := str(low["file"])
	var high_file := str(high["file"])
	var low_rpm := maxf(1.0, float(low["rpm"]))
	var high_rpm := maxf(1.0, float(high["rpm"]))
	if bool(bracket.get("is_single", false)) or low_file == high_file:
		gains[low_file] = 1.0
		pitches[low_file] = clampf(rpm / low_rpm, idle_pitch if rpm < low_rpm else min_pitch, max_pitch)
	else:
		var start := maxf(low_rpm, high_rpm * min_pitch)
		var finish := minf(high_rpm, low_rpm * max_pitch)
		var blend := smoothstep(start, finish, rpm) if finish > start else float(bracket.get("t", 0.0))
		gains[low_file] = cos(blend * HALF_PI)
		gains[high_file] = sin(blend * HALF_PI)
		pitches[low_file] = clampf(rpm / low_rpm, min_pitch, max_pitch)
		pitches[high_file] = clampf(rpm / high_rpm, min_pitch, max_pitch)
	return {"gains": gains, "pitches": pitches}


func _update_reflection_voice(fname: String, direct: AudioStreamPlayer, gain: float, pitch: float) -> void:
	if not _reflection_players.has(fname):
		return
	var mirror: AudioStreamPlayer = _reflection_players[fname]
	mirror.pitch_scale = pitch
	mirror.volume_db = linear_to_db(maxf(0.0001, gain))
	if gain > 0.001 and direct.playing and not mirror.playing:
		mirror.play(direct.get_playback_position())
	elif gain <= 0.001 and mirror.playing:
		mirror.stop()


func _rebuild_loop_players() -> void:
	if is_instance_valid(_grain_engine):
		_grain_engine.stop_audio()
		remove_child(_grain_engine)
		_grain_engine.queue_free()
		_grain_engine = null
	for mirror in _reflection_players.values():
		if is_instance_valid(mirror):
			mirror.stop()
			remove_child(mirror)
			mirror.queue_free()
	_reflection_players.clear()
	_prepared_loops.clear()
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
		var wav := EngineWavLoaderScript.load_engine_loop(full_path)
		if wav != null:
			_prepared_loops[fname] = wav
			var player := AudioStreamPlayer.new()
			player.name = "Exhaust_" + fname.get_basename()
			player.bus = safe_exhaust_bus
			player.stream = wav
			player.volume_db = -80.0
			add_child(player)
			_exhaust_players[fname] = player
			if AudioServer.get_bus_index(&"Exhaust_Reflection") >= 0:
				var mirror := AudioStreamPlayer.new()
				mirror.name = "Reflection_" + fname.get_basename()
				mirror.bus = &"Exhaust_Reflection"
				mirror.stream = wav
				mirror.volume_db = -80.0
				add_child(mirror)
				_reflection_players[fname] = mirror
		else:
			push_warning("RecordedEngineController: Could not load exhaust loop: " + full_path)

	# Create Intake players for ON loops in manifest
	for anchor in _manifest.on_anchors:
		var fname: String = str(anchor["file"])
		var wav: AudioStreamWAV = _prepared_loops.get(fname)
		if wav != null:
			var player := AudioStreamPlayer.new()
			player.name = "Intake_" + fname.get_basename()
			player.bus = safe_intake_bus
			player.stream = wav
			player.volume_db = -80.0
			add_child(player)
			_intake_players[fname] = player
		else:
			push_warning("RecordedEngineController: Could not load intake loop: " + fname)

	# Legacy voices remain available for explicit A/B, not concurrently mixed.
	var cfg: Dictionary = PROFILE_CONFIGS[car_profile]
	if use_phase_grains and cfg.has("firing_order") and _active_bank == car_profile:
		var renderer := PhaseGrainEngineScript.new()
		renderer.name = "PhaseGrainEngine"
		if renderer.prepare(_manifest.loops,_prepared_loops,float(cfg["firing_order"]),_idle_rpm,float(cfg.get("idle_gain",0.58)),car_profile == "mclaren_senna" and _manifest.bank_status != "local_source_native_audition"):
			_grain_engine = renderer
			add_child(renderer)
		else:
			renderer.free()
			if _manifest.bank_status == "local_source_native_audition":
				push_warning("Native phase-grain source preparation failed: "+car_profile)
			else:
				push_error("Hero phase-grain source preparation failed: "+car_profile)


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
	if not bool(PROFILE_CONFIGS[car_profile].get("synthetic_events", true)):
		return
	if _shift_player != null and _shift_player.stream != null:
		_shift_player.pitch_scale = randf_range(0.95, 1.05)
		_shift_player.volume_db = linear_to_db(maxf(0.0001, float(PROFILE_CONFIGS[car_profile].get("shift_gain", 0.30)) * master_gain))
		if _shift_player.is_inside_tree():
			_shift_player.play()


func _resolve_bus(bus_name: StringName) -> StringName:
	if AudioServer.get_bus_index(bus_name) != -1:
		return bus_name
	return &"Master"


# Avoid forcing a coasting recording to extreme pitch at idle. Below the first
# usable OFF anchor, use the low ON recording at restrained volume. Blend back
# into the actual coast bank before reaching its lowest recorded RPM.
static func compute_load_gains(rpm: float, throttle: float, off_anchors: Array, idle_gain: float = 0.40) -> Vector2:
	var load := clampf(throttle, 0.0, 1.0)
	var fallback := lerpf(clampf(idle_gain, 0.0, 1.0), 1.0, load)
	if off_anchors.is_empty():
		return Vector2(fallback, 0.0)
	var first_off := maxf(1.0, float(off_anchors[0]["rpm"]))
	var availability := smoothstep(first_off * 0.75, first_off, rpm)
	var angle := (1.0 - load) * HALF_PI * availability
	var level := lerpf(fallback, 1.0, availability)
	return Vector2(0.0 if angle >= HALF_PI else cos(angle), sin(angle)) * level


# Pure calculation helper for deterministic testing and analysis
static func compute_blend_state(rpm: float, throttle: float, manifest_data: Dictionary) -> Dictionary:
	var manifest := EngineProfileManifestScript.new()
	manifest.parse_dictionary(manifest_data)

	var load_gains := compute_load_gains(rpm, throttle, manifest.off_anchors)
	var on_layer_gain := load_gains.x
	var off_layer_gain := load_gains.y

	var on_state := compute_anchor_pair(manifest.find_bracketing_anchors("on", rpm), rpm)
	var off_state := compute_anchor_pair(manifest.find_bracketing_anchors("off", rpm), rpm) if manifest.has_off_layer else {"gains": {}, "pitches": {}}
	var on_gains: Dictionary = on_state["gains"]
	var on_pitches: Dictionary = on_state["pitches"]
	var off_gains: Dictionary = off_state["gains"]
	var off_pitches: Dictionary = off_state["pitches"]

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
