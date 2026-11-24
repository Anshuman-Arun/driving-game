class_name ChassisAudioController
extends Node3D
## Aster Valley Chassis, Environment, and Acoustics Controller (Track D).
##
## Orchestrates:
## 1. Wind noise with ~22 m/s onset, exponential volume curve, and lowpass filter shaping.
## 2. Ambient wind bed using mountain_wind_bed.wav on Ambience bus.
## 3. Suspension travel / compression audio (spring delta / delta time) with ~0.16s cooldown.
## 4. Contact / landing thump when touching down after airborne state.
## 5. Collision impact audio with velocity-scaled volume and ~0.12s cooldown.
## 6. Acoustic raycast reflection: left/right/up (~20m) raycasts every 4 physics ticks,
##    mapping wall distance to delay (15-120ms) and wet gain on Exhaust_Reflection bus.
##    Clamped and bypassed in open terrain.

const ChassisWind = preload("chassis_wind.gd")
const ChassisSuspension = preload("chassis_suspension.gd")
const ChassisAcoustics = preload("chassis_acoustics.gd")

@export_group("Buses")
@export var wind_bus: StringName = &"Wind_Chassis"
@export var ambience_bus: StringName = &"Ambience"
@export var reflection_bus: StringName = &"Exhaust_Reflection"
@export var sfx_bus: StringName = &"Wind_Chassis"

@export_group("Subsystems Enabled")
@export var wind_enabled: bool = true
@export var ambience_enabled: bool = true
@export var suspension_enabled: bool = true
@export var impact_enabled: bool = true
@export var acoustics_enabled: bool = true

@export_group("Wind Tuning")
@export var wind_onset_mps: float = 22.0
@export var wind_max_mps: float = 70.0
@export var wind_exponent: float = 1.8
@export var wind_lpf_min_hz: float = 800.0
@export var wind_lpf_max_hz: float = 14000.0
@export_range(0.0, 1.5, 0.01) var wind_gain: float = 0.90
@export_range(0.0, 1.5, 0.01) var ambience_gain: float = 1.0

@export_group("Suspension & Impact Tuning")
@export var suspension_cooldown: float = 0.16
@export var impact_cooldown: float = 0.12
@export var compression_threshold: float = 1.0
@export_range(0.0, 1.5, 0.01) var suspension_gain: float = 0.85
@export_range(0.0, 1.5, 0.01) var impact_gain: float = 0.95

@export_group("Acoustics Tuning")
@export var raycast_distance: float = 20.0
@export var raycast_interval: int = 4
@export var delay_min_ms: float = 15.0
@export var delay_max_ms: float = 120.0

var _wind: Node
var _suspension: Node
var _acoustics: Node

var _bound_vehicle: Node3D
var _tracking_vehicle: bool = false
var _telemetry: Dictionary = {}


func _init() -> void:
	_init_subsystems()


func _ready() -> void:
	if _wind == null:
		_init_subsystems()
	if _bound_vehicle != null:
		bind_vehicle(_bound_vehicle)


func _init_subsystems() -> void:
	if _wind != null:
		return
	# 1. Wind & Ambience Subsystem
	_wind = ChassisWind.new()
	_wind.name = "WindSubsystem"
	_wind.set("wind_bus", wind_bus)
	_wind.set("ambience_bus", ambience_bus)
	_wind.set("onset_speed_mps", wind_onset_mps)
	_wind.set("max_speed_mps", wind_max_mps)
	_wind.set("wind_exponent", wind_exponent)
	_wind.set("lpf_min_hz", wind_lpf_min_hz)
	_wind.set("lpf_max_hz", wind_lpf_max_hz)
	_wind.set("wind_max_gain", wind_gain if wind_enabled else 0.0)
	_wind.set("ambience_gain", ambience_gain if ambience_enabled else 0.0)
	add_child(_wind)

	# 2. Suspension & Impact Subsystem
	_suspension = ChassisSuspension.new()
	_suspension.name = "SuspensionSubsystem"
	_suspension.set("sfx_bus", sfx_bus)
	_suspension.set("suspension_cooldown", suspension_cooldown)
	_suspension.set("impact_cooldown", impact_cooldown)
	_suspension.set("compression_threshold", compression_threshold)
	_suspension.set("suspension_gain", suspension_gain if suspension_enabled else 0.0)
	_suspension.set("impact_gain", impact_gain if impact_enabled else 0.0)
	add_child(_suspension)

	# 3. Acoustic Reflection Subsystem
	_acoustics = ChassisAcoustics.new()
	_acoustics.name = "AcousticsSubsystem"
	_acoustics.set("reflection_bus", reflection_bus)
	_acoustics.set("raycast_distance", raycast_distance)
	_acoustics.set("physics_tick_interval", raycast_interval)
	_acoustics.set("delay_min_ms", delay_min_ms)
	_acoustics.set("delay_max_ms", delay_max_ms)
	add_child(_acoustics)


func bind_vehicle(vehicle: Node3D) -> void:
	_disconnect_vehicle()
	_bound_vehicle = vehicle if is_instance_valid(vehicle) else null
	_tracking_vehicle = _bound_vehicle != null
	if _suspension and _suspension.has_method("reset_state"):
		_suspension.call("reset_state")

	if not _tracking_vehicle:
		_telemetry.clear()
		return

	if _bound_vehicle is RigidBody3D:
		var body := _bound_vehicle as RigidBody3D
		if not body.body_entered.is_connected(_on_body_entered):
			body.body_entered.connect(_on_body_entered)


func unbind_vehicle() -> void:
	bind_vehicle(null)


func _exit_tree() -> void:
	_disconnect_vehicle()
	_bound_vehicle = null
	_tracking_vehicle = false


func _disconnect_vehicle() -> void:
	if is_instance_valid(_bound_vehicle) and _bound_vehicle is RigidBody3D:
		var body := _bound_vehicle as RigidBody3D
		if body.body_entered.is_connected(_on_body_entered):
			body.body_entered.disconnect(_on_body_entered)


func update_telemetry(telemetry: Dictionary) -> void:
	_telemetry.clear()
	for k in telemetry:
		_telemetry[k] = telemetry[k]

	if _wind and wind_enabled and _wind.has_method("update_telemetry"):
		_wind.call("update_telemetry", _telemetry)


func _process(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	var target_node: Node3D = _bound_vehicle if is_instance_valid(_bound_vehicle) else (self if is_inside_tree() else null)

	# 1. Suspension processing
	if _suspension and suspension_enabled and _suspension.has_method("process_physics"):
		_suspension.call("process_physics", delta, target_node, _telemetry)

	# 2. Acoustic raycast reflection processing
	if _acoustics and acoustics_enabled and is_instance_valid(_bound_vehicle) and _acoustics.has_method("process_physics_acoustics"):
		_acoustics.call("process_physics_acoustics", _bound_vehicle)


func _on_body_entered(_body: Node) -> void:
	if not impact_enabled or not _suspension:
		return
	var speed: float = float(_telemetry.get("speed_mps", 0.0))
	if is_instance_valid(_bound_vehicle) and "linear_velocity" in _bound_vehicle:
		var vel: Variant = _bound_vehicle.get("linear_velocity")
		if vel is Vector3:
			speed = maxf(speed, (vel as Vector3).length())
	if speed > 1.5:
		trigger_impact(speed, 1.0)


## Triggers collision impact audio with velocity-scaled volume.
func trigger_impact(velocity: float = 10.0, strength: float = 1.0) -> bool:
	if not impact_enabled or _suspension == null:
		return false
	return bool(_suspension.call("trigger_impact", velocity, strength))


## Convenience alias for collision impact.
func trigger_collision(strength: float = 1.0) -> bool:
	return trigger_impact(10.0 * clampf(strength, 0.1, 2.0), strength)


## Triggers suspension compression audio.
func trigger_suspension(strength: float = 1.0) -> bool:
	if not suspension_enabled or _suspension == null:
		return false
	return bool(_suspension.call("trigger_suspension", strength, 1.0))


## Triggers landing thump audio.
func trigger_landing(landing_speed: float) -> bool:
	if not suspension_enabled or _suspension == null:
		return false
	return bool(_suspension.call("trigger_landing", landing_speed))


## Simulates acoustic reflections deterministically (for tests/QA).
func simulate_acoustics(dist_left: float, dist_right: float, dist_up: float) -> Dictionary:
	if _acoustics == null or not _acoustics.has_method("apply_wall_distances"):
		return {}
	return _acoustics.call("apply_wall_distances", dist_left, dist_right, dist_up)


func get_wind() -> Node:
	return _wind


func get_suspension() -> Node:
	return _suspension


func get_acoustics() -> Node:
	return _acoustics
