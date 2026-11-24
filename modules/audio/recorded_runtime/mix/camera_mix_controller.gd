class_name AsterCameraMixController
extends Node
## Camera-aware interior/exterior acoustic mix controller for Aster Valley.
##
## Smoothly transitions vehicle audio between exterior (chase camera) clarity
## and interior (cockpit) acoustic muffling with 150-300ms smoothing.
##
## Acoustic characteristics:
## - Cockpit view (interior_weight = 1.0):
##   * Muffles exterior buses (Engine_Exhaust, Tires, Wind_Chassis, Ambience)
##     via dynamic lowpass filtering down to ~1800 Hz and -4 dB attenuation.
##   * Emphasizes Engine_Intake (+6 dB boost) to deliver cabin induction roar.
## - Chase camera (interior_weight = 0.0):
##   * Wide-open filter clarity (20500 Hz cutoff) and full exterior presence.
##   * Intake returns to nominal calibrated balance (-12 dB).

const AsterAudioBusBuilder = preload("bus_layout_builder.gd")

signal interior_weight_changed(current_weight: float)

# --- Configuration Exports ---
## Smoothing time constant tau in seconds (150ms to 300ms range, default 200ms).
@export_range(0.05, 0.50, 0.01) var smoothing_time: float = 0.20

## If true, automatically samples camera position/mode every frame.
@export var auto_camera_tracking: bool = true

## Camera node to monitor for interior/exterior perspective.
@export var camera_node: Camera3D

## Vehicle root node containing CameraMounts/Cockpit marker.
@export var vehicle_node: Node3D

## Distance in meters from Cockpit mount below which view is fully interior.
@export var cockpit_threshold_dist: float = 0.65

## Distance in meters from Cockpit mount above which view is fully exterior.
@export var chase_threshold_dist: float = 1.60

## Intake emphasis boost in dB when in cockpit view.
@export_range(0.0, 12.0, 0.5) var intake_emphasis_db: float = 6.0

## Exterior bus attenuation in dB when in cockpit view.
@export_range(0.0, 12.0, 0.5) var exterior_attenuation_db: float = 4.0

## Lowpass cutoff in Hz for muffled exterior sounds inside cockpit.
@export_range(500.0, 5000.0, 50.0) var cockpit_lpf_cutoff_hz: float = 1800.0

## Lowpass cutoff in Hz for wide-open exterior clarity in chase camera.
@export_range(15000.0, 22000.0, 100.0) var exterior_lpf_cutoff_hz: float = 20500.0

# --- Runtime State ---
var target_interior_weight: float = 0.0:
	set(val):
		target_interior_weight = clampf(val, 0.0, 1.0)

var current_interior_weight: float = 0.0:
	set(val):
		current_interior_weight = clampf(val, 0.0, 1.0)

var _manual_override: bool = false
var _cached_bus_indices: Dictionary = {}
var _cached_filters: Dictionary = {}
var _base_gains: Dictionary = {}


func _ready() -> void:
	refresh_bus_cache()
	_apply_mix_instant(current_interior_weight)


func _process(delta: float) -> void:
	if auto_camera_tracking and not _manual_override:
		_update_camera_tracking()

	if absf(current_interior_weight - target_interior_weight) > 0.0005:
		var alpha: float = 1.0 - exp(-delta / maxf(0.001, smoothing_time))
		current_interior_weight = lerpf(current_interior_weight, target_interior_weight, alpha)
		_apply_mix(current_interior_weight)
		interior_weight_changed.emit(current_interior_weight)
	elif current_interior_weight != target_interior_weight:
		current_interior_weight = target_interior_weight
		_apply_mix(current_interior_weight)
		interior_weight_changed.emit(current_interior_weight)


## Sets manual interior weight [0.0 = full chase clarity, 1.0 = full cockpit muffled].
func set_interior_weight(weight: float, immediate: bool = false) -> void:
	_manual_override = true
	target_interior_weight = clampf(weight, 0.0, 1.0)
	if immediate:
		current_interior_weight = target_interior_weight
		_apply_mix_instant(current_interior_weight)
		interior_weight_changed.emit(current_interior_weight)


## Toggles cockpit view directly.
func set_cockpit_view(is_cockpit: bool, immediate: bool = false) -> void:
	set_interior_weight(1.0 if is_cockpit else 0.0, immediate)


## Releases manual override so auto tracking resumes.
func resume_auto_tracking() -> void:
	_manual_override = false


## Binds an active camera to monitor.
func bind_camera(cam: Camera3D) -> void:
	camera_node = cam


## Binds the vehicle node to track against.
func bind_vehicle(veh: Node3D) -> void:
	vehicle_node = veh


## Returns current smoothed interior weight.
func get_interior_weight() -> float:
	return current_interior_weight


## Returns target interior weight.
func get_target_weight() -> float:
	return target_interior_weight


## Returns true if currently leaning interior (> 0.5 weight).
func is_cockpit_view() -> bool:
	return current_interior_weight > 0.5


## Re-scans AudioServer for Aster Valley buses and cached filter effects.
func refresh_bus_cache() -> void:
	_cached_bus_indices.clear()
	_cached_filters.clear()
	_base_gains.clear()

	var bus_names: Array[StringName] = [
		AsterAudioBusBuilder.BUS_MASTER,
		AsterAudioBusBuilder.BUS_SFX,
		AsterAudioBusBuilder.BUS_ENGINE_EXHAUST,
		AsterAudioBusBuilder.BUS_ENGINE_INTAKE,
		AsterAudioBusBuilder.BUS_EXHAUST_REFLECTION,
		AsterAudioBusBuilder.BUS_TIRES,
		AsterAudioBusBuilder.BUS_WIND_CHASSIS,
		AsterAudioBusBuilder.BUS_AMBIENCE,
		AsterAudioBusBuilder.BUS_MUSIC,
		AsterAudioBusBuilder.BUS_UI,
	]

	for b_name in bus_names:
		var idx := AudioServer.get_bus_index(b_name)
		if idx >= 0:
			_cached_bus_indices[b_name] = idx
			_base_gains[b_name] = AsterAudioBusBuilder.get_bus_start_gain(b_name)
			_cached_filters[b_name] = _find_lpf_filter(idx)


func _update_camera_tracking() -> void:
	var cam := camera_node
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return

	# 1. Check for camera class inspection (e.g. DrivingChaseCamera mode)
	if cam.has_method("get_mode_name"):
		var mode_name: String = String(cam.call("get_mode_name")).to_upper()
		if mode_name.contains("COCKPIT") or mode_name.contains("INTERIOR"):
			target_interior_weight = 1.0
			return
		elif mode_name.contains("HOOD"):
			# Hood view gives full exterior roar with negligible windshield barrier
			target_interior_weight = 0.05
			return
		elif mode_name.contains("CHASE"):
			target_interior_weight = 0.0
			return

	# 2. Check camera name heuristics
	var cam_name := cam.name.to_upper()
	if cam_name.contains("COCKPIT") or cam_name.contains("INTERIOR"):
		target_interior_weight = 1.0
		return
	elif cam_name.contains("CHASE"):
		target_interior_weight = 0.0
		return

	# 3. Spatial proximity to vehicle Cockpit mount
	var veh := vehicle_node
	if veh == null or not is_instance_valid(veh):
		veh = get_parent() as Node3D
	if veh == null or not is_instance_valid(veh):
		return

	var cockpit_marker: Node3D = null
	if veh.has_node("CameraMounts/Cockpit"):
		cockpit_marker = veh.get_node("CameraMounts/Cockpit") as Node3D
	elif veh.has_node("Cockpit"):
		cockpit_marker = veh.get_node("Cockpit") as Node3D

	if cockpit_marker != null and is_instance_valid(cockpit_marker):
		var dist := cam.global_position.distance_to(cockpit_marker.global_position)
		if dist <= cockpit_threshold_dist:
			target_interior_weight = 1.0
		elif dist >= chase_threshold_dist:
			target_interior_weight = 0.0
		else:
			# Smooth hermite cubic between cockpit and chase boundaries
			var t := clampf((dist - cockpit_threshold_dist) / (chase_threshold_dist - cockpit_threshold_dist), 0.0, 1.0)
			target_interior_weight = 1.0 - (t * t * (3.0 - 2.0 * t))


func _apply_mix(weight: float) -> void:
	if _cached_bus_indices.is_empty():
		refresh_bus_cache()

	# Frequency cutoff interpolation (logarithmic / exponential for human hearing)
	var log_open := log(exterior_lpf_cutoff_hz)
	var log_muffle := log(cockpit_lpf_cutoff_hz)
	var current_cutoff := exp(lerpf(log_open, log_muffle, weight))

	# 1. Engine Intake: emphasized in cockpit (+6 dB boost)
	var intake_idx: int = _cached_bus_indices.get(AsterAudioBusBuilder.BUS_ENGINE_INTAKE, -1)
	if intake_idx >= 0:
		var base_intake: float = _base_gains.get(AsterAudioBusBuilder.BUS_ENGINE_INTAKE, -12.0)
		AudioServer.set_bus_volume_db(intake_idx, base_intake + (intake_emphasis_db * weight))

	# 2. Engine Exhaust: muffled in cockpit (-4 dB cut + lowpass filter)
	var exhaust_idx: int = _cached_bus_indices.get(AsterAudioBusBuilder.BUS_ENGINE_EXHAUST, -1)
	if exhaust_idx >= 0:
		var base_exh: float = _base_gains.get(AsterAudioBusBuilder.BUS_ENGINE_EXHAUST, -6.0)
		AudioServer.set_bus_volume_db(exhaust_idx, base_exh - (exterior_attenuation_db * weight))
		var exh_lpf: AudioEffectLowPassFilter = _cached_filters.get(AsterAudioBusBuilder.BUS_ENGINE_EXHAUST, null)
		if exh_lpf:
			exh_lpf.cutoff_hz = current_cutoff

	# 3. Tires: muffled in cockpit (-4 dB cut + lowpass filter)
	var tires_idx: int = _cached_bus_indices.get(AsterAudioBusBuilder.BUS_TIRES, -1)
	if tires_idx >= 0:
		var base_tires: float = _base_gains.get(AsterAudioBusBuilder.BUS_TIRES, -10.0)
		AudioServer.set_bus_volume_db(tires_idx, base_tires - (exterior_attenuation_db * weight))
		var tires_lpf: AudioEffectLowPassFilter = _cached_filters.get(AsterAudioBusBuilder.BUS_TIRES, null)
		if tires_lpf:
			tires_lpf.cutoff_hz = maxf(current_cutoff, 2200.0)

	# 4. Wind Chassis: muffled in cockpit (-4 dB cut + lowpass filter)
	var wind_idx: int = _cached_bus_indices.get(AsterAudioBusBuilder.BUS_WIND_CHASSIS, -1)
	if wind_idx >= 0:
		var base_wind: float = _base_gains.get(AsterAudioBusBuilder.BUS_WIND_CHASSIS, -14.0)
		AudioServer.set_bus_volume_db(wind_idx, base_wind - (exterior_attenuation_db * weight))
		var wind_lpf: AudioEffectLowPassFilter = _cached_filters.get(AsterAudioBusBuilder.BUS_WIND_CHASSIS, null)
		if wind_lpf:
			wind_lpf.cutoff_hz = maxf(current_cutoff, 2000.0)

	# 5. Exhaust Reflection: muffled in cockpit (-4 dB cut)
	var refl_idx: int = _cached_bus_indices.get(AsterAudioBusBuilder.BUS_EXHAUST_REFLECTION, -1)
	if refl_idx >= 0:
		var base_refl: float = _base_gains.get(AsterAudioBusBuilder.BUS_EXHAUST_REFLECTION, -18.0)
		AudioServer.set_bus_volume_db(refl_idx, base_refl - (exterior_attenuation_db * weight))

	# 6. Ambience: muffled slightly in cockpit (-3 dB cut + lowpass filter)
	var amb_idx: int = _cached_bus_indices.get(AsterAudioBusBuilder.BUS_AMBIENCE, -1)
	if amb_idx >= 0:
		var base_amb: float = _base_gains.get(AsterAudioBusBuilder.BUS_AMBIENCE, -20.0)
		AudioServer.set_bus_volume_db(amb_idx, base_amb - (exterior_attenuation_db * 0.75 * weight))
		var amb_lpf: AudioEffectLowPassFilter = _cached_filters.get(AsterAudioBusBuilder.BUS_AMBIENCE, null)
		if amb_lpf:
			amb_lpf.cutoff_hz = maxf(current_cutoff, 2500.0)


func _apply_mix_instant(weight: float) -> void:
	current_interior_weight = weight
	target_interior_weight = weight
	_apply_mix(weight)


func _find_lpf_filter(bus_idx: int) -> AudioEffectLowPassFilter:
	var count := AudioServer.get_bus_effect_count(bus_idx)
	for i in range(count):
		var eff := AudioServer.get_bus_effect(bus_idx, i)
		if eff is AudioEffectLowPassFilter:
			return eff as AudioEffectLowPassFilter
	return null
