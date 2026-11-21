class_name AsterAudioController
extends Node
## Self-contained 2D player-vehicle audio mixer. No global buses or autoloads required.
## Bind a GEVP vehicle, or call update_telemetry() with normalized telemetry.

const PROFILES := {
	"vela_gt": {"prefix": "vela", "idle": 950.0, "redline": 7100.0, "gain": 0.84},
	"orion_rs": {"prefix": "orion", "idle": 1100.0, "redline": 8600.0, "gain": 0.78},
	"kestrel_xr": {"prefix": "kestrel", "idle": 800.0, "redline": 6900.0, "gain": 0.94},
}
const ENGINE_BANDS := ["low", "mid", "high"]
const SURFACES := ["asphalt", "gravel", "grass"]
const LOOP_NAMES := ["roll_asphalt", "roll_gravel", "roll_grass", "tire_squeal", "tire_skid", "wind", "countryside", "overrun"]

@export_range(0.0, 1.0, 0.01) var master_gain := 0.80
@export_range(0.0, 1.0, 0.01) var ambient_gain := 0.32
@export var car_profile := "vela_gt"

var _players: Dictionary = {}
var _event_players: Array[AudioStreamPlayer] = []
var _event_index := 0
var _current_profile := ""
var _telemetry: Dictionary = {"rpm": 950.0, "throttle": 0.0, "speed_mps": 0.0, "gear": 1, "surface": "asphalt", "grip": 1.0}
var _gains: Dictionary = {}
var _bound_vehicle: Node3D
var _last_gear := -999
var _last_throttle := 0.0
var _shift_timer := 0.0
var _overrun_timer := 0.0
var _suspension_cooldown := 0.0
var _previous_springs: Dictionary = {}


func _ready() -> void:
	for band in ENGINE_BANDS:
		_players["engine_" + band] = _make_player("Engine " + band)
	for name in LOOP_NAMES:
		_players[name] = _make_player(name)
		_set_loop(_players[name], name)
	for i in range(4):
		_event_players.append(_make_player("Event %d" % i))
	set_profile(car_profile)


func set_profile(profile: String) -> void:
	if not PROFILES.has(profile):
		push_warning("Unknown Aster audio profile: " + profile)
		return
	car_profile = profile
	if _players.is_empty() or _current_profile == profile:
		return
	_current_profile = profile
	var prefix: String = PROFILES[profile]["prefix"]
	for band in ENGINE_BANDS:
		_set_loop(_players["engine_" + band], "engine_%s_%s" % [prefix, band])
	_last_gear = -999


func bind_gevp_vehicle(vehicle: Node3D) -> void:
	if is_instance_valid(_bound_vehicle) and _bound_vehicle is RigidBody3D:
		var old_body: RigidBody3D = _bound_vehicle as RigidBody3D
		if old_body.body_entered.is_connected(_on_body_entered):
			old_body.body_entered.disconnect(_on_body_entered)
	_bound_vehicle = vehicle
	_previous_springs.clear()
	if vehicle is RigidBody3D:
		var body := vehicle as RigidBody3D
		if not body.body_entered.is_connected(_on_body_entered):
			body.body_entered.connect(_on_body_entered)


func update_telemetry(telemetry: Dictionary) -> void:
	## keys: rpm, idle_rpm, max_rpm, throttle, load, speed_mps,
	## lateral_slip [0..1], grip [0..1], handbrake, on_ground,
	## gear (int), surface (asphalt/gravel/grass), engine_braking.
	var gear := int(telemetry.get("gear", 1))
	if _last_gear != -999 and gear != _last_gear and gear > 0 and _last_gear > 0:
		_shift_timer = 0.23
		_play_event("gearshift", 0.55)
	_last_gear = gear
	var throttle := clampf(float(telemetry.get("throttle", 0.0)), 0.0, 1.0)
	if _last_throttle > 0.48 and throttle < 0.16 and float(telemetry.get("rpm", 0.0)) > 2500.0:
		_overrun_timer = 0.75
	_last_throttle = throttle
	_telemetry = telemetry.duplicate()


func trigger_impact(strength: float = 1.0) -> void:
	_play_event("collision", clampf(strength, 0.0, 1.0))


func trigger_collision(strength: float = 1.0) -> void:
	trigger_impact(strength)


func trigger_suspension(strength: float = 1.0) -> void:
	_play_event("suspension", clampf(strength, 0.0, 1.0))


func _physics_process(_delta: float) -> void:
	if is_instance_valid(_bound_vehicle):
		update_telemetry(AsterAudioTelemetry.from_gevp(_bound_vehicle))
		_monitor_suspension()


func _process(delta: float) -> void:
	_shift_timer = maxf(0.0, _shift_timer - delta)
	_overrun_timer = maxf(0.0, _overrun_timer - delta)
	_suspension_cooldown = maxf(0.0, _suspension_cooldown - delta)
	var mix := compute_targets(_telemetry, car_profile)
	var alpha := 1.0 - exp(-maxf(delta, 0.0) * 12.0)
	for band in ENGINE_BANDS:
		var name := "engine_" + band
		var duck := 0.36 if _shift_timer > 0.0 else 1.0
		_apply_gain(name, float(mix[name]) * duck, alpha)
		(_players[name] as AudioStreamPlayer).pitch_scale = float(mix["pitch_" + band]) * (0.85 if _shift_timer > 0.0 else 1.0)
	for surface in SURFACES:
		_apply_gain("roll_" + surface, float(mix["roll_" + surface]), alpha)
	for name in ["tire_squeal", "tire_skid", "wind"]:
		_apply_gain(name, float(mix[name]), alpha)
	_apply_gain("overrun", float(mix["overrun"]) + 0.17 * _overrun_timer, alpha)
	_apply_gain("countryside", float(mix["countryside"]) * ambient_gain, alpha)


static func compute_targets(t: Dictionary, profile: String = "vela_gt") -> Dictionary:
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
	var out := {
		"engine_low": base * low,
		"engine_mid": base * mid,
		"engine_high": base * high,
		"pitch_low": clampf(rpm / 2100.0, 0.63, 1.65),
		"pitch_mid": clampf(rpm / 4250.0, 0.65, 1.6),
		"pitch_high": clampf(rpm / 6600.0, 0.62, 1.58),
		"roll_asphalt": rolling * (0.26 if surface == "asphalt" else 0.0),
		"roll_gravel": rolling * (0.43 if surface == "gravel" else 0.0),
		"roll_grass": rolling * (0.30 if surface == "grass" else 0.0),
		"tire_squeal": skid * (0.52 if surface == "asphalt" else 0.0),
		"tire_skid": skid * (0.56 if surface != "asphalt" else 0.0),
		"overrun": overrun * 0.30,
		"wind": clampf(pow(speed / 52.0, 1.3), 0.0, 0.88) * 0.62,
		"countryside": 0.20,
	}
	return out


func _apply_gain(name: String, target: float, alpha: float) -> void:
	var last := float(_gains.get(name, 0.0))
	var value := lerpf(last, target, alpha)
	_gains[name] = value
	var player: AudioStreamPlayer = _players[name]
	player.volume_db = linear_to_db(maxf(0.0001, value * master_gain))


func _make_player(label: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = label.replace(" ", "_")
	player.volume_db = -80.0
	add_child(player)
	return player


func _asset(name: String) -> AudioStreamWAV:
	var path: String = get_script().resource_path.get_base_dir().path_join("assets").path_join(name + ".wav")
	var stream := load(path) as AudioStreamWAV
	if stream == null:
		push_error("Aster audio missing/invalid WAV: " + path)
	return stream


func _set_loop(player: AudioStreamPlayer, name: String) -> void:
	var wav := _asset(name)
	if wav == null:
		return
	player.stop()
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(wav.data.size() / 2)
	player.stream = wav
	player.play()


func _play_event(name: String, strength: float) -> void:
	if _event_players.is_empty() or strength <= 0.01:
		return
	var player := _event_players[_event_index]
	_event_index = (_event_index + 1) % _event_players.size()
	var wav := _asset(name)
	if wav == null:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	player.stop()
	player.stream = wav
	player.pitch_scale = 0.96 + 0.065 * float(_event_index)
	player.volume_db = linear_to_db(maxf(0.0001, strength * master_gain * 0.68))
	player.play()


func _monitor_suspension() -> void:
	if _suspension_cooldown > 0.0:
		return
	var wheels: Array = _bound_vehicle.get("wheel_array") if _has_property(_bound_vehicle, "wheel_array") else []
	for wheel in wheels:
		if not is_instance_valid(wheel) or not wheel.is_colliding():
			continue
		var id := wheel.get_instance_id()
		var spring := float(wheel.get("spring_current_length"))
		if _previous_springs.has(id):
			var compression := float(_previous_springs[id]) - spring
			if compression > 0.055 and float(_telemetry.get("speed_mps", 0.0)) > 2.0:
				trigger_suspension(clampf(compression / 0.20, 0.2, 0.8))
				_suspension_cooldown = 0.20
		_previous_springs[id] = spring


func _on_body_entered(_body: Node) -> void:
	if is_instance_valid(_bound_vehicle):
		var speed := float(_telemetry.get("speed_mps", 0.0))
		if speed > 4.0:
			trigger_collision(clampf((speed - 4.0) / 16.0, 0.15, 1.0))


func _has_property(object: Object, property_name: String) -> bool:
	for entry in object.get_property_list():
		if str(entry.get("name", "")) == property_name:
			return true
	return false
