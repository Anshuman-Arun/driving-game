class_name ChassisSuspension
extends Node
## Chassis suspension travel, landing thump, and collision impact audio controller.
##
## Features:
## - Suspension travel/compression audio driven by (spring delta / delta time).
## - Contact / landing thump when touching down after airborne state.
## - Suspension cooldown ~0.16s to prevent machine-gunning.
## - Collision impact audio with velocity-scaled volume and cooldown ~0.12s.
## - Routed to Wind_Chassis or Master bus.

const ChassisWavLoader = preload("wav_loader.gd")

@export var sfx_bus: StringName = &"Wind_Chassis"
@export var suspension_cooldown: float = 0.16
@export var impact_cooldown: float = 0.12
@export var compression_threshold: float = 1.0 # m/s
@export var min_impact_speed: float = 1.5 # m/s
@export var max_impact_speed: float = 30.0 # m/s
@export_range(0.0, 1.5, 0.01) var suspension_gain: float = 0.85
@export_range(0.0, 1.5, 0.01) var impact_gain: float = 0.95

@export var suspension_asset_path: String = "res://modules/audio/assets/suspension.wav"
@export var impact_asset_path: String = "res://modules/audio/assets/collision.wav"

var _suspension_players: Array[AudioStreamPlayer] = []
var _impact_players: Array[AudioStreamPlayer] = []
var _suspension_idx: int = 0
var _impact_idx: int = 0
var _suspension_stream: AudioStreamWAV
var _impact_stream: AudioStreamWAV

var _suspension_cooldown_timer: float = 0.0
var _impact_cooldown_timer: float = 0.0

var _previous_springs: Dictionary = {} # int -> float
var _was_airborne: bool = false
var _airborne_timer: float = 0.0
var _previous_velocity: Vector3 = Vector3.ZERO


func _init() -> void:
	_init_voice_pools()


func _ready() -> void:
	_init_voice_pools()


func _init_voice_pools() -> void:
	if not _suspension_players.is_empty():
		return
	var bus_name := sfx_bus if AudioServer.get_bus_index(sfx_bus) >= 0 else &"Master"

	_suspension_stream = ChassisWavLoader.load_wav(suspension_asset_path)
	if _suspension_stream != null:
		ChassisWavLoader.configure_loop(_suspension_stream, false)

	for i in range(3):
		var p := AudioStreamPlayer.new()
		p.name = "SuspensionVoice%d" % i
		p.bus = bus_name
		p.stream = _suspension_stream
		add_child(p)
		_suspension_players.append(p)

	_impact_stream = ChassisWavLoader.load_wav(impact_asset_path)
	if _impact_stream != null:
		ChassisWavLoader.configure_loop(_impact_stream, false)

	for i in range(3):
		var p := AudioStreamPlayer.new()
		p.name = "ImpactVoice%d" % i
		p.bus = bus_name
		p.stream = _impact_stream
		add_child(p)
		_impact_players.append(p)


func _process(delta: float) -> void:
	if _suspension_cooldown_timer > 0.0:
		_suspension_cooldown_timer = maxf(0.0, _suspension_cooldown_timer - delta)
	if _impact_cooldown_timer > 0.0:
		_impact_cooldown_timer = maxf(0.0, _impact_cooldown_timer - delta)


func process_physics(delta: float, vehicle: Node3D, telemetry: Dictionary) -> void:
	var dt: float = maxf(delta, 0.001)

	# 1. Update cooldown timers
	if _suspension_cooldown_timer > 0.0:
		_suspension_cooldown_timer = maxf(0.0, _suspension_cooldown_timer - dt)
	if _impact_cooldown_timer > 0.0:
		_impact_cooldown_timer = maxf(0.0, _impact_cooldown_timer - dt)

	# 2. Check suspension compression via GEVP wheels
	if is_instance_valid(vehicle):
		_monitor_wheel_suspension(vehicle, dt)

	# 3. Check airborne state and contact/landing thump
	var on_ground: bool = bool(telemetry.get("on_ground", true))
	var velocity: Vector3 = Vector3.ZERO
	if is_instance_valid(vehicle) and "linear_velocity" in vehicle:
		var raw_vel: Variant = vehicle.get("linear_velocity")
		if raw_vel is Vector3:
			velocity = raw_vel

	if not on_ground:
		_airborne_timer += dt
		if _airborne_timer >= 0.10:
			_was_airborne = true
	else:
		if _was_airborne:
			var landing_speed: float = maxf(absf(velocity.y), 3.0)
			trigger_landing(landing_speed)
			_was_airborne = false
		_airborne_timer = 0.0

	_previous_velocity = velocity


func _monitor_wheel_suspension(vehicle: Node3D, dt: float) -> void:
	if not ("wheel_array" in vehicle):
		return
	var raw_wheels: Variant = vehicle.get("wheel_array")
	if not (raw_wheels is Array):
		return

	var wheels: Array = raw_wheels
	var max_compression_rate: float = 0.0

	for item in wheels:
		if not (item is Object) or not is_instance_valid(item):
			continue
		var wheel: Object = item
		if wheel.has_method("is_colliding") and not bool(wheel.call("is_colliding")):
			continue
		if not ("spring_current_length" in wheel):
			continue

		var id: int = wheel.get_instance_id()
		var curr_len: float = float(wheel.get("spring_current_length"))
		if _previous_springs.has(id):
			var prev_len: float = float(_previous_springs[id])
			var spring_delta: float = prev_len - curr_len # positive when compressed
			var rate: float = compute_suspension_compression_rate(spring_delta, dt)
			if rate > max_compression_rate:
				max_compression_rate = rate
		_previous_springs[id] = curr_len

	if max_compression_rate >= compression_threshold:
		var strength: float = clampf(max_compression_rate / 3.5, 0.25, 1.0)
		trigger_suspension(strength, 1.0)


## Triggers suspension compression audio event (spring delta / dt).
## Subject to ~0.16s cooldown.
func trigger_suspension(strength: float = 1.0, pitch: float = 1.0) -> bool:
	if _suspension_players.is_empty():
		return false
	if _suspension_cooldown_timer > 0.0:
		return false

	_suspension_cooldown_timer = suspension_cooldown

	var player: AudioStreamPlayer = _suspension_players[_suspension_idx]
	_suspension_idx = (_suspension_idx + 1) % _suspension_players.size()

	var gain: float = clampf(strength * suspension_gain, 0.001, 1.5)
	player.volume_db = linear_to_db(gain)
	player.pitch_scale = clampf(pitch * randf_range(0.94, 1.06), 0.70, 1.40)
	if player.is_inside_tree():
		player.play()
	return true


## Triggers contact / landing thump when car touches down from airborne.
func trigger_landing(landing_speed: float) -> bool:
	var strength: float = clampf(landing_speed / 8.0, 0.35, 1.0)
	return trigger_suspension(strength, 0.90)


## Triggers collision impact audio event.
## Volume is velocity-scaled, subject to ~0.12s cooldown.
func trigger_impact(impact_velocity: float = 10.0, strength: float = 1.0) -> bool:
	if _impact_players.is_empty():
		return false
	if _impact_cooldown_timer > 0.0:
		return false
	if impact_velocity < min_impact_speed:
		return false

	_impact_cooldown_timer = impact_cooldown

	var player: AudioStreamPlayer = _impact_players[_impact_idx]
	_impact_idx = (_impact_idx + 1) % _impact_players.size()

	var gain: float = compute_impact_gain(impact_velocity, min_impact_speed, max_impact_speed, impact_gain) * clampf(strength, 0.0, 1.5)
	player.volume_db = linear_to_db(clampf(gain, 0.0001, 1.5))

	var vel_factor: float = clampf((impact_velocity - min_impact_speed) / (max_impact_speed - min_impact_speed), 0.0, 1.0)
	player.pitch_scale = clampf(lerpf(1.10, 0.88, vel_factor) * randf_range(0.96, 1.04), 0.70, 1.40)
	if player.is_inside_tree():
		player.play()
	return true


func reset_state() -> void:
	_suspension_cooldown_timer = 0.0
	_impact_cooldown_timer = 0.0
	_previous_springs.clear()
	_was_airborne = false
	_airborne_timer = 0.0
	_previous_velocity = Vector3.ZERO


## Pure static helper: compute suspension compression rate (spring delta / delta time)
static func compute_suspension_compression_rate(spring_delta: float, delta_time: float) -> float:
	var dt: float = maxf(delta_time, 0.0001)
	return maxf(0.0, spring_delta / dt)


## Pure static helper: compute velocity-scaled impact gain
static func compute_impact_gain(
	impact_speed: float,
	min_speed: float = 1.5,
	max_speed: float = 30.0,
	base_gain: float = 0.95
) -> float:
	var speed: float = maxf(0.0, impact_speed)
	if speed < min_speed:
		return 0.0
	var span: float = maxf(0.1, max_speed - min_speed)
	var factor: float = clampf((speed - min_speed) / span, 0.0, 1.0)
	var linear_scale: float = lerpf(0.20, 1.0, factor)
	return clampf(linear_scale * base_gain, 0.0, 1.5)
