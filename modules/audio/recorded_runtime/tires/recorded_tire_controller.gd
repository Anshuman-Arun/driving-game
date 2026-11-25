class_name RecordedTireController
extends Node
## Recorded Tire Audio Subsystem for Aster Valley.
## Owns surface roll loops (asphalt, gravel, grass), tire scrub, and screech.

const AsterTireTelemetryScript := preload("tire_telemetry.gd")
const EngineWavLoaderScript := preload("../engine/engine_wav_loader.gd")

# --- Thresholds and Tuning Constants ---
const SCRUB_MIN_SLIP := 0.15
const SCRUB_MAX_SLIP := 0.45
const SCREECH_ENTER_THRESHOLD := 0.45
const SCREECH_EXIT_THRESHOLD := 0.38 # Hysteresis exit

const MIN_SPEED_GATE := 1.5 # m/s (~5.4 km/h) below which squeal is gated
const FULL_SPEED_GATE := 3.5 # m/s (~12.6 km/h) where gating reaches 1.0

const ATTACK_TIME_S := 0.080 # ~80ms attack
const RELEASE_TIME_S := 0.180 # ~180ms release
const AIRBORNE_FADE_S := 0.100 # ~100ms loss of ground fade
const SURFACE_BLEND_S := 0.120 # ~120ms surface crossfade

const DEFAULT_BUS := "Tires"

# --- Asset Paths ---
const PATH_ROLL_GRAVEL_RECORDED := "res://assets/audio/recorded/payload/tires/roll_gravel.wav"
const PATH_ROLL_GRAVEL_FALLBACK := "res://modules/audio/assets/roll_gravel.wav"
const PATH_ROLL_ASPHALT_RECORDED := "res://assets/audio/recorded/payload/tires/roll_asphalt.wav"
const PATH_ROLL_ASPHALT_FALLBACK := "res://modules/audio/assets/roll_asphalt.wav"
const PATH_ROLL_GRASS_RECORDED := "res://assets/audio/recorded/payload/tires/roll_grass.wav"
const PATH_ROLL_GRASS_FALLBACK := "res://modules/audio/assets/roll_grass.wav"

const PATH_SCREECH_RECORDED := "res://assets/audio/recorded/payload/tires/screech.wav"
const PATH_SCREECH_FALLBACK := "res://modules/audio/assets/tire_squeal.wav"
const PATH_SCRUB_FALLBACK := "res://modules/audio/assets/tire_skid.wav"

# --- Export Properties ---
@export_range(0.0, 2.0, 0.05) var master_tire_gain: float = 1.0
@export_range(0.0, 2.0, 0.05) var roll_gain: float = 0.85
@export_range(0.0, 2.0, 0.05) var scrub_gain: float = 0.70
@export_range(0.0, 2.0, 0.05) var screech_gain: float = 0.85
@export var is_enabled: bool = true

# --- State Variables ---
var _bound_vehicle: Node = null
var _telemetry: Dictionary = {}
var _is_screeching: bool = false
var clean_native_mix := false
var _severe_slip_time := 0.0
var _is_scrubbing: bool = false

var _ground_factor: float = 1.0
var _scrub_envelope: float = 0.0
var _screech_envelope: float = 0.0
var _speed_gate: float = 0.0

var _surface_weights: Dictionary = {
	AsterTireTelemetryScript.SURFACE_ASPHALT: 1.0,
	AsterTireTelemetryScript.SURFACE_GRAVEL: 0.0,
	AsterTireTelemetryScript.SURFACE_GRASS: 0.0,
}

# --- Audio Players ---
var _roll_asphalt_player: AudioStreamPlayer
var _roll_gravel_player: AudioStreamPlayer
var _roll_grass_player: AudioStreamPlayer
var _scrub_player: AudioStreamPlayer
var _screech_player: AudioStreamPlayer
var _players: Array[AudioStreamPlayer] = []
var _resolved_bus: String = DEFAULT_BUS


func _ready() -> void:
	_init_audio_bus()
	if _players.is_empty():
		_create_players()
	_start_all_players()
	if _telemetry.is_empty():
		_telemetry = AsterTireTelemetryScript.fallback()


func _enter_tree() -> void:
	_init_audio_bus()
	if _players.is_empty():
		_create_players()
	_start_all_players()


func _exit_tree() -> void:
	unbind_vehicle()


func _start_all_players() -> void:
	for player in _players:
		if is_instance_valid(player) and player.is_inside_tree() and player.stream != null and not player.playing:
			player.play()


func _physics_process(delta: float) -> void:
	if not is_enabled:
		_silence_all()
		return

	if is_instance_valid(_bound_vehicle):
		var t := AsterTireTelemetryScript.from_vehicle(_bound_vehicle)
		update_telemetry(t, delta)
	elif not _telemetry.is_empty():
		_process_tires(delta)


## Bind a vehicle (such as a GEVP Vehicle Node3D) for automatic per-physics-tick telemetry polling.
func bind_vehicle(vehicle: Node) -> void:
	unbind_vehicle()
	_bound_vehicle = vehicle if is_instance_valid(vehicle) else null
	if _bound_vehicle == null:
		_telemetry = AsterTireTelemetryScript.fallback()


## Unbind current vehicle.
func unbind_vehicle() -> void:
	_bound_vehicle = null


## Store the root controller's single telemetry sample; envelopes advance once
## in _physics_process using the real physics delta.
func queue_telemetry(t: Dictionary) -> void:
	_telemetry = AsterTireTelemetryScript.from_dictionary(t)


## Update tire audio directly from a telemetry dictionary (e.g. from AsterAudioTelemetry or QA test harness).
func update_telemetry(t: Dictionary, delta: float = 0.0167) -> void:
	_telemetry = AsterTireTelemetryScript.from_dictionary(t)
	_process_tires(delta)


# --- Core DSP / Synthesis Processing ---
func _process_tires(delta: float) -> void:
	var dt := maxf(delta, 0.0001)

	var speed: float = float(_telemetry.get("speed_mps", 0.0))
	var slip: float = float(_telemetry.get("slip_amount", 0.0))
	var on_ground: bool = bool(_telemetry.get("on_ground", true))
	var target_surface_weights: Dictionary = _telemetry.get("surface_weights", {})

	# 1. Ground Contact / Airborne Envelope
	var target_ground := 1.0 if on_ground else 0.0
	var ground_tau := ATTACK_TIME_S if target_ground > _ground_factor else AIRBORNE_FADE_S
	_ground_factor = lerpf(_ground_factor, target_ground, 1.0 - exp(-dt / ground_tau))

	# 2. Surface Weights Smooth Crossfade
	var surface_rate := 1.0 - exp(-dt / SURFACE_BLEND_S)
	for s in _surface_weights.keys():
		var target_w := float(target_surface_weights.get(s, 0.0))
		_surface_weights[s] = lerpf(float(_surface_weights[s]), target_w, surface_rate)

	# Normalize weights sum
	var w_sum: float = float(_surface_weights[AsterTireTelemetryScript.SURFACE_ASPHALT]) + \
		float(_surface_weights[AsterTireTelemetryScript.SURFACE_GRAVEL]) + \
		float(_surface_weights[AsterTireTelemetryScript.SURFACE_GRASS])
	if w_sum > 0.001:
		for s in _surface_weights.keys():
			_surface_weights[s] = float(_surface_weights[s]) / w_sum

	# 3. Minimum Speed Gate (prevents stationary squeal)
	_speed_gate = clampf((speed - MIN_SPEED_GATE) / (FULL_SPEED_GATE - MIN_SPEED_GATE), 0.0, 1.0)

	# 4. Hysteresis on Screech (>0.45 enter, <0.38 exit)
	if not _is_screeching:
		if slip >= SCREECH_ENTER_THRESHOLD:
			_is_screeching = true
	else:
		if slip < SCREECH_EXIT_THRESHOLD:
			_is_screeching = false

	# 5. Scrub and Screech Raw Intensities
	var scrub_raw := 0.0
	if slip >= SCRUB_MIN_SLIP:
		if slip <= SCRUB_MAX_SLIP:
			scrub_raw = smoothstep(SCRUB_MIN_SLIP, SCRUB_MAX_SLIP, slip)
		else:
			# High slip: maintain rubber scrub friction underneath screech
			scrub_raw = 0.75
	_is_scrubbing = scrub_raw > 0.05

	var screech_raw := 0.0
	if _is_screeching:
		screech_raw = clampf(0.35 + 0.65 * ((slip - SCREECH_EXIT_THRESHOLD) / (1.0 - SCREECH_EXIT_THRESHOLD)), 0.0, 1.0)

	if clean_native_mix:
		# The asphalt/grass and scrub fallback WAVs are procedural, not
		# recordings. Only audible real squeal during sustained heavy slip.
		if on_ground and speed > 8.0 and slip > 0.80:
			_severe_slip_time = minf(1.0,_severe_slip_time+dt)
		else:
			_severe_slip_time = 0.0
		scrub_raw = 0.0
		screech_raw *= smoothstep(0.18,0.38,_severe_slip_time)

	# Gate by minimum speed and ground contact
	var target_scrub := scrub_raw * _speed_gate * _ground_factor
	# Rubber squeal is principally an asphalt sound; loose surfaces churn instead.
	var paved_fraction := float(_surface_weights[AsterTireTelemetryScript.SURFACE_ASPHALT])
	var target_screech := screech_raw * _speed_gate * _ground_factor * paved_fraction

	# 6. Attack (~80ms) and Release (~180ms) Envelopes
	var scrub_tau := ATTACK_TIME_S if target_scrub > _scrub_envelope else RELEASE_TIME_S
	_scrub_envelope = lerpf(_scrub_envelope, target_scrub, 1.0 - exp(-dt / scrub_tau))

	var screech_tau := ATTACK_TIME_S if target_screech > _screech_envelope else RELEASE_TIME_S
	_screech_envelope = lerpf(_screech_envelope, target_screech, 1.0 - exp(-dt / screech_tau))

	# 7. Speed-Dependent Roll Pitch & Gains
	var roll_vol := smoothstep(0.5, 30.0, speed) * _ground_factor * roll_gain
	var roll_pitch := clampf(0.70 + (speed / 35.0) * 0.65, 0.65, 1.55)

	# Gains per surface
	var asphalt_gain := roll_vol * 0.45 * float(_surface_weights[AsterTireTelemetryScript.SURFACE_ASPHALT])
	var gravel_gain := roll_vol * 0.65 * float(_surface_weights[AsterTireTelemetryScript.SURFACE_GRAVEL])
	var grass_gain := roll_vol * 0.50 * float(_surface_weights[AsterTireTelemetryScript.SURFACE_GRASS])
	if clean_native_mix:
		asphalt_gain = 0.0
		grass_gain = 0.0

	# Boost gravel texture during slip / churn
	if slip > 0.15:
		gravel_gain += smoothstep(0.15, 0.8, slip) * 0.35 * _ground_factor * _speed_gate * float(_surface_weights[AsterTireTelemetryScript.SURFACE_GRAVEL])

	# 8. Pitch Modulation for Scrub and Screech
	var scrub_pitch := clampf(0.72 + (speed / 40.0) * 0.18 + slip * 0.10, 0.65, 0.95)
	var screech_pitch := clampf(0.98 + (speed / 35.0) * 0.20 + (slip - 0.45) * 0.30, 0.90, 1.40)

	# 9. Apply to AudioStreamPlayers
	var master := clampf(master_tire_gain, 0.0, 2.0)
	_apply_stream(_roll_asphalt_player, asphalt_gain * master, roll_pitch, dt)
	_apply_stream(_roll_gravel_player, gravel_gain * master, roll_pitch, dt)
	_apply_stream(_roll_grass_player, grass_gain * master, roll_pitch, dt)

	_apply_stream(_scrub_player, _scrub_envelope * scrub_gain * master, scrub_pitch, dt)
	_apply_stream(_screech_player, _screech_envelope * screech_gain * master, screech_pitch, dt)


func _apply_stream(player: AudioStreamPlayer, gain: float, pitch: float, dt: float) -> void:
	if player == null:
		return
	if gain <= 0.0001:
		player.volume_db = -80.0
	else:
		player.volume_db = linear_to_db(clampf(gain, 0.0001, 2.0))

	var pitch_rate := 1.0 - exp(-dt / 0.050)
	player.pitch_scale = lerpf(player.pitch_scale, clampf(pitch, 0.2, 4.0), pitch_rate)


func _silence_all() -> void:
	for player in _players:
		if is_instance_valid(player):
			player.volume_db = -80.0


# --- Player Construction & Audio Setup ---
func _init_audio_bus() -> void:
	if AudioServer.get_bus_index(DEFAULT_BUS) != -1:
		_resolved_bus = DEFAULT_BUS
	elif AudioServer.get_bus_index("SFX") != -1:
		_resolved_bus = "SFX"
	else:
		_resolved_bus = "Master"


func _create_players() -> void:
	if not _players.is_empty():
		return
	_roll_asphalt_player = _build_player("RollAsphalt", [PATH_ROLL_ASPHALT_RECORDED, PATH_ROLL_ASPHALT_FALLBACK])
	_roll_gravel_player = _build_player("RollGravel", [PATH_ROLL_GRAVEL_RECORDED, PATH_ROLL_GRAVEL_FALLBACK])
	_roll_grass_player = _build_player("RollGrass", [PATH_ROLL_GRASS_RECORDED, PATH_ROLL_GRASS_FALLBACK])

	# Use a separate friction texture rather than doubling the same squeal recording.
	_scrub_player = _build_player("TireScrub", [PATH_SCRUB_FALLBACK, PATH_SCREECH_RECORDED])
	# Screech uses screech.wav for high-slip screech
	_screech_player = _build_player("TireScreech", [PATH_SCREECH_RECORDED, PATH_SCREECH_FALLBACK])

	_players = [
		_roll_asphalt_player,
		_roll_gravel_player,
		_roll_grass_player,
		_scrub_player,
		_screech_player,
	]


func _build_player(player_name: String, candidate_paths: Array) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = _resolved_bus
	player.volume_db = -80.0
	add_child(player)

	var stream: AudioStreamWAV = null
	for path in candidate_paths:
		if not FileAccess.file_exists(str(path)) and not ResourceLoader.exists(str(path)):
			continue
		stream = EngineWavLoaderScript.load_engine_loop(str(path))
		if stream != null:
			break

	if stream != null:
		_setup_seamless_loop(stream)
		player.stream = stream
		if player.is_inside_tree():
			player.play()
	else:
		push_warning("RecordedTireController: Could not find audio asset for " + player_name)

	return player


static func _setup_seamless_loop(wav: AudioStreamWAV) -> void:
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	var sample_frames := int(round(wav.get_length() * float(wav.mix_rate)))
	wav.loop_end = maxi(1, sample_frames)


## Robust WAV loader supporting both imported resources and direct filesystem PCM16 WAV buffers.
static func _load_wav_stream(path: String) -> AudioStreamWAV:
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is AudioStreamWAV:
			return res as AudioStreamWAV

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	return _parse_wav(bytes)


static func _parse_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44:
		return null
	var riff := bytes.slice(0, 4).get_string_from_ascii()
	var wave := bytes.slice(8, 12).get_string_from_ascii()
	if riff != "RIFF" or wave != "WAVE":
		return null

	var wav := AudioStreamWAV.new()
	var pos := 12
	var channels := 1
	var sample_rate := 44100
	var bits_per_sample := 16

	while pos + 8 <= bytes.size():
		var chunk_id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size := bytes.decode_u32(pos + 4)
		pos += 8
		if chunk_id == "fmt ":
			if pos + 16 > bytes.size():
				return null
			channels = bytes.decode_u16(pos + 2)
			sample_rate = bytes.decode_u32(pos + 4)
			bits_per_sample = bytes.decode_u16(pos + 14)
			pos += chunk_size
		elif chunk_id == "data":
			var data_len := mini(chunk_size, bytes.size() - pos)
			wav.data = bytes.slice(pos, pos + data_len)
			wav.mix_rate = sample_rate
			wav.stereo = (channels == 2)
			if bits_per_sample == 16:
				wav.format = AudioStreamWAV.FORMAT_16_BITS
			elif bits_per_sample == 8:
				wav.format = AudioStreamWAV.FORMAT_8_BITS
			else:
				wav.format = AudioStreamWAV.FORMAT_16_BITS
			pos += chunk_size
			return wav
		else:
			pos += chunk_size
	return null


# --- Pure Targets Computation (for unit testing / deterministic verification) ---
static func compute_tire_targets(telemetry: Dictionary, state: Dictionary, delta: float = 0.0167) -> Dictionary:
	var dt := maxf(delta, 0.0001)
	var speed: float = float(telemetry.get("speed_mps", 0.0))
	var slip: float = float(telemetry.get("slip_amount", 0.0))
	var on_ground: bool = bool(telemetry.get("on_ground", true))
	var surface: String = AsterTireTelemetryScript.normalize_surface(str(telemetry.get("surface", AsterTireTelemetryScript.SURFACE_ASPHALT)))

	var ground_factor: float = float(state.get("ground_factor", 1.0))
	var is_screeching: bool = bool(state.get("is_screeching", false))
	var scrub_envelope: float = float(state.get("scrub_envelope", 0.0))
	var screech_envelope: float = float(state.get("screech_envelope", 0.0))

	# 1. Ground factor
	var target_ground := 1.0 if on_ground else 0.0
	var ground_tau := ATTACK_TIME_S if target_ground > ground_factor else AIRBORNE_FADE_S
	ground_factor = lerpf(ground_factor, target_ground, 1.0 - exp(-dt / ground_tau))

	# 2. Speed gate
	var speed_gate := clampf((speed - MIN_SPEED_GATE) / (FULL_SPEED_GATE - MIN_SPEED_GATE), 0.0, 1.0)

	# 3. Screech Hysteresis
	if not is_screeching:
		if slip >= SCREECH_ENTER_THRESHOLD:
			is_screeching = true
	else:
		if slip < SCREECH_EXIT_THRESHOLD:
			is_screeching = false

	# 4. Intensities
	var scrub_raw := 0.0
	if slip >= SCRUB_MIN_SLIP:
		if slip <= SCRUB_MAX_SLIP:
			scrub_raw = smoothstep(SCRUB_MIN_SLIP, SCRUB_MAX_SLIP, slip)
		else:
			scrub_raw = 0.75

	var screech_raw := 0.0
	if is_screeching:
		screech_raw = clampf(0.35 + 0.65 * ((slip - SCREECH_EXIT_THRESHOLD) / (1.0 - SCREECH_EXIT_THRESHOLD)), 0.0, 1.0)

	var target_scrub := scrub_raw * speed_gate * ground_factor
	var target_screech := screech_raw * speed_gate * ground_factor * (1.0 if surface == AsterTireTelemetryScript.SURFACE_ASPHALT else 0.0)

	# 5. Envelope smoothing
	var scrub_tau := ATTACK_TIME_S if target_scrub > scrub_envelope else RELEASE_TIME_S
	scrub_envelope = lerpf(scrub_envelope, target_scrub, 1.0 - exp(-dt / scrub_tau))

	var screech_tau := ATTACK_TIME_S if target_screech > screech_envelope else RELEASE_TIME_S
	screech_envelope = lerpf(screech_envelope, target_screech, 1.0 - exp(-dt / screech_tau))

	# 6. Surface Roll
	var roll_vol := smoothstep(0.5, 30.0, speed) * ground_factor * 0.85
	var roll_pitch := clampf(0.70 + (speed / 35.0) * 0.65, 0.65, 1.55)

	return {
		"speed_mps": speed,
		"slip_amount": slip,
		"on_ground": on_ground,
		"ground_factor": ground_factor,
		"speed_gate": speed_gate,
		"is_screeching": is_screeching,
		"is_scrubbing": scrub_raw > 0.05,
		"scrub_envelope": scrub_envelope,
		"screech_envelope": screech_envelope,
		"roll_pitch": roll_pitch,
		"roll_asphalt_gain": roll_vol * (0.45 if surface == AsterTireTelemetryScript.SURFACE_ASPHALT else 0.0),
		"roll_gravel_gain": roll_vol * (0.65 if surface == AsterTireTelemetryScript.SURFACE_GRAVEL else 0.0),
		"roll_grass_gain": roll_vol * (0.50 if surface == AsterTireTelemetryScript.SURFACE_GRASS else 0.0),
	}


# --- Getters for QA and Debugging ---
func get_slip_amount() -> float:
	return float(_telemetry.get("slip_amount", 0.0))

func is_screeching() -> bool:
	return _is_screeching

func is_scrubbing() -> bool:
	return _is_scrubbing

func is_grounded() -> bool:
	return bool(_telemetry.get("on_ground", true))

func get_ground_factor() -> float:
	return _ground_factor

func get_scrub_envelope() -> float:
	return _scrub_envelope

func get_screech_envelope() -> float:
	return _screech_envelope

func get_speed_gate() -> float:
	return _speed_gate

func get_current_surface() -> String:
	return str(_telemetry.get("surface", AsterTireTelemetryScript.SURFACE_ASPHALT))

func get_surface_weights() -> Dictionary:
	return _surface_weights.duplicate()

func get_bus_name() -> String:
	return _resolved_bus

func get_players() -> Dictionary:
	if _players.is_empty():
		_create_players()
	return {
		"roll_asphalt": _roll_asphalt_player,
		"roll_gravel": _roll_gravel_player,
		"roll_grass": _roll_grass_player,
		"scrub": _scrub_player,
		"screech": _screech_player,
	}

func get_debug_state() -> Dictionary:
	return {
		"speed_mps": float(_telemetry.get("speed_mps", 0.0)),
		"slip_amount": float(_telemetry.get("slip_amount", 0.0)),
		"on_ground": bool(_telemetry.get("on_ground", true)),
		"ground_factor": _ground_factor,
		"speed_gate": _speed_gate,
		"is_screeching": _is_screeching,
		"is_scrubbing": _is_scrubbing,
		"scrub_envelope": _scrub_envelope,
		"screech_envelope": _screech_envelope,
		"surface_weights": _surface_weights,
		"bus": _resolved_bus,
	}
