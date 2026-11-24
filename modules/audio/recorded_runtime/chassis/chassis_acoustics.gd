class_name ChassisAcoustics
extends Node
## Acoustic raycast reflection controller for Aster Valley.
##
## Measures wall proximity via left, right, and up raycasts (~20m) every 4 physics ticks.
## Maps wall distance to reflection delay (15-120ms) and wet gain on Exhaust_Reflection bus.
## Clamps and bypasses reflection in open terrain.

@export var reflection_bus: StringName = &"Exhaust_Reflection"
@export var raycast_distance: float = 20.0
@export var physics_tick_interval: int = 4
@export var delay_min_ms: float = 15.0
@export var delay_max_ms: float = 120.0
@export var open_terrain_threshold_m: float = 20.0
@export var collision_mask: int = 1 | 2
@export_range(0.0, 1.0, 0.01) var wet_gain_max: float = 0.85
@export_range(0.0, 1.0, 0.01) var wet_gain_min: float = 0.08

var _physics_tick_counter: int = 0
var _delay_effect: AudioEffectDelay
var _effect_bus_idx: int = -1
var _effect_idx: int = -1
var _owns_delay_effect: bool = false

var _current_delay_ms: float = 120.0
var _current_wet_gain: float = 0.0
var _target_delay_ms: float = 120.0
var _target_wet_gain: float = 0.0
var _is_open_terrain: bool = true
var _closest_wall_dist: float = 20.0

var _dist_left: float = INF
var _dist_right: float = INF
var _dist_up: float = INF


func _ready() -> void:
	_setup_delay_effect()


func _exit_tree() -> void:
	if _owns_delay_effect and _effect_bus_idx >= 0 and _effect_idx >= 0:
		if _effect_bus_idx < AudioServer.bus_count:
			if _effect_idx < AudioServer.get_bus_effect_count(_effect_bus_idx):
				if AudioServer.get_bus_effect(_effect_bus_idx, _effect_idx) == _delay_effect:
					AudioServer.remove_bus_effect(_effect_bus_idx, _effect_idx)
		_delay_effect = null
		_owns_delay_effect = false


func _setup_delay_effect() -> void:
	_effect_bus_idx = AudioServer.get_bus_index(reflection_bus)
	if _effect_bus_idx < 0:
		return

	# Search for existing AudioEffectDelay on Exhaust_Reflection bus
	for i in range(AudioServer.get_bus_effect_count(_effect_bus_idx)):
		var effect := AudioServer.get_bus_effect(_effect_bus_idx, i)
		if effect is AudioEffectDelay:
			_delay_effect = effect as AudioEffectDelay
			_effect_idx = i
			_owns_delay_effect = false
			_configure_delay_parameters(_delay_effect)
			return

	# If none found, create and configure a new AudioEffectDelay
	_delay_effect = AudioEffectDelay.new()
	_configure_delay_parameters(_delay_effect)
	AudioServer.add_bus_effect(_effect_bus_idx, _delay_effect)
	_effect_idx = AudioServer.get_bus_effect_count(_effect_bus_idx) - 1
	_owns_delay_effect = true


func _configure_delay_parameters(delay: AudioEffectDelay) -> void:
	delay.dry = 0.0 # Wet-only reflection bus routing per spec
	delay.tap1_active = true
	delay.tap1_delay_ms = delay_max_ms
	delay.tap1_level_db = -80.0
	delay.tap2_active = false
	delay.feedback_active = false


func process_physics_acoustics(vehicle: Node3D) -> void:
	_physics_tick_counter += 1
	if _physics_tick_counter % physics_tick_interval != 0:
		return

	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree():
		return

	var world_3d := vehicle.get_world_3d()
	if not world_3d:
		return

	var space_state := world_3d.direct_space_state
	if not space_state:
		return

	# Raycast origin: vehicle position raised 0.6m to clear undercarriage
	var origin: Vector3 = vehicle.global_position + vehicle.global_basis.y * 0.6
	var basis: Basis = vehicle.global_basis

	var target_left: Vector3 = origin - basis.x * raycast_distance
	var target_right: Vector3 = origin + basis.x * raycast_distance
	var target_up: Vector3 = origin + basis.y * raycast_distance

	var exclude: Array[RID] = []
	if vehicle is CollisionObject3D:
		exclude.append((vehicle as CollisionObject3D).get_rid())

	_dist_left = _cast_ray(space_state, origin, target_left, exclude)
	_dist_right = _cast_ray(space_state, origin, target_right, exclude)
	_dist_up = _cast_ray(space_state, origin, target_up, exclude)

	apply_wall_distances(_dist_left, _dist_right, _dist_up)


func _cast_ray(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude)
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return INF
	var hit_pos: Vector3 = hit.get("position", to)
	return from.distance_to(hit_pos)


## Apply measured or simulated wall distances to calculate acoustic reflection parameters.
func apply_wall_distances(dist_left: float, dist_right: float, dist_up: float) -> Dictionary:
	_dist_left = dist_left
	_dist_right = dist_right
	_dist_up = dist_up

	var result: Dictionary = compute_acoustic_reflection(
		dist_left,
		dist_right,
		dist_up,
		raycast_distance,
		delay_min_ms,
		delay_max_ms,
		wet_gain_max,
		wet_gain_min
	)

	_closest_wall_dist = float(result.get("min_distance", raycast_distance))
	_target_delay_ms = float(result.get("delay_ms", delay_max_ms))
	_target_wet_gain = float(result.get("wet_gain", 0.0))
	_is_open_terrain = bool(result.get("is_open_terrain", true))

	return result


func _process(delta: float) -> void:
	var step: float = maxf(delta, 0.001)
	var alpha: float = 1.0 - exp(-step * 12.0)

	_current_delay_ms = lerpf(_current_delay_ms, _target_delay_ms, alpha)
	_current_wet_gain = lerpf(_current_wet_gain, _target_wet_gain, alpha)

	if is_instance_valid(_delay_effect):
		_delay_effect.tap1_delay_ms = clampf(_current_delay_ms, delay_min_ms, delay_max_ms)

		# Keep the wet-only delay enabled even in open terrain. Bypassing
		# it would leak the unprocessed reflection input as duplicate dry audio.
		_delay_effect.tap1_level_db = linear_to_db(clampf(_current_wet_gain, 0.0001, 1.0))
		if _effect_bus_idx >= 0 and _effect_idx >= 0:
			AudioServer.set_bus_effect_enabled(_effect_bus_idx, _effect_idx, true)


## Pure static method: compute acoustic reflection parameters from distances
static func compute_acoustic_reflection(
	dist_left: float,
	dist_right: float,
	dist_up: float,
	max_distance: float = 20.0,
	min_delay: float = 15.0,
	max_delay: float = 120.0,
	wet_max: float = 0.85,
	wet_min: float = 0.08
) -> Dictionary:
	var d_min: float = minf(dist_left, minf(dist_right, dist_up))

	# Open terrain check: no hits within raycast range
	if is_inf(d_min) or d_min > max_distance:
		return {
			"min_distance": max_distance,
			"delay_ms": max_delay,
			"wet_gain": 0.0,
			"wet_db": -80.0,
			"is_open_terrain": true,
			"is_bypassed": true,
			"dist_left": dist_left,
			"dist_right": dist_right,
			"dist_up": dist_up
		}

	# Wall detected: map distance [1.0m, max_distance] -> [min_delay, max_delay]
	var norm_dist: float = clampf((d_min - 1.0) / maxf(0.1, max_distance - 1.0), 0.0, 1.0)
	var mapped_delay: float = lerpf(min_delay, max_delay, norm_dist)
	var mapped_wet: float = lerpf(wet_max, wet_min, norm_dist)

	return {
		"min_distance": d_min,
		"delay_ms": mapped_delay,
		"wet_gain": mapped_wet,
		"wet_db": linear_to_db(maxf(0.0001, mapped_wet)),
		"is_open_terrain": false,
		"is_bypassed": false,
		"dist_left": dist_left,
		"dist_right": dist_right,
		"dist_up": dist_up
	}
