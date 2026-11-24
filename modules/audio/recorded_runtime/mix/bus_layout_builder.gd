class_name AsterAudioBusBuilder
extends RefCounted
## Builds, configures, and exports the canonical Godot AudioBusLayout for Aster Valley.
##
## Features:
## - Master bus with gentle compressor (threshold -16 dB, ratio 2:1, attack 15ms, release 120ms) and limiter (-1 dB ceiling).
## - Dedicated sub-buses with calibrated start gains:
##   * Engine_Exhaust: -6 dB (with dynamic lowpass for cockpit muffling)
##   * Engine_Intake: -12 dB (clean induction roar, emphasized in cockpit)
##   * Exhaust_Reflection: -18 dB (wet-only reflection delay bus)
##   * Tires: -10 dB (highpass ~120 Hz to clear rumble)
##   * Wind_Chassis: -14 dB (highpass ~80 Hz & EQ shaping)
##   * Ambience: -20 dB
##   * Music: -18 dB
##   * UI: -12 dB
##   * SFX: 0 dB (master effects bus for UI settings sliders)
## - Supports both direct Master sends and intermediate SFX submix routing.

# --- Bus Name Constants ---
const BUS_MASTER := &"Master"
const BUS_SFX := &"SFX"
const BUS_ENGINE_EXHAUST := &"Engine_Exhaust"
const BUS_ENGINE_INTAKE := &"Engine_Intake"
const BUS_EXHAUST_REFLECTION := &"Exhaust_Reflection"
const BUS_TIRES := &"Tires"
const BUS_WIND_CHASSIS := &"Wind_Chassis"
const BUS_AMBIENCE := &"Ambience"
const BUS_MUSIC := &"Music"
const BUS_UI := &"UI"

# --- Calibrated Start Gains (dB) ---
const START_GAINS := {
	BUS_MASTER: 0.0,
	BUS_SFX: 0.0,
	BUS_ENGINE_EXHAUST: -6.0,
	BUS_ENGINE_INTAKE: -12.0,
	BUS_EXHAUST_REFLECTION: -18.0,
	BUS_TIRES: -10.0,
	BUS_WIND_CHASSIS: -14.0,
	BUS_AMBIENCE: -20.0,
	BUS_MUSIC: -18.0,
	BUS_UI: -12.0,
}

# --- Master Dynamic Processing Specs ---
const COMPRESSOR_THRESHOLD_DB := -16.0
const COMPRESSOR_RATIO := 2.0
const COMPRESSOR_ATTACK_US := 15000.0  # 15 ms
const COMPRESSOR_RELEASE_MS := 120.0  # 120 ms
const COMPRESSOR_GAIN_DB := 0.0

const LIMITER_CEILING_DB := -1.0
const LIMITER_THRESHOLD_DB := 0.0
const LIMITER_SOFT_CLIP_DB := 2.0
const LIMITER_SOFT_CLIP_RATIO := 10.0

# --- Bus Filtering & Acoustic Specs ---
const TIRES_HIGHPASS_CUTOFF_HZ := 120.0
const TIRES_HIGHPASS_RESONANCE := 0.5

const WIND_HIGHPASS_CUTOFF_HZ := 80.0
const WIND_HIGHPASS_RESONANCE := 0.5

const REFLECTION_INITIAL_DELAY_MS := 40.0
const REFLECTION_LOWPASS_CUTOFF_HZ := 12000.0

const LPF_WIDE_OPEN_CUTOFF_HZ := 20500.0
const LPF_COCKPIT_CUTOFF_HZ := 1800.0

# --- Bus Definitions Table ---
# Order defines the AudioServer bus hierarchy.
const BUS_SPECS: Array[Dictionary] = [
	{"name": BUS_MASTER, "default_send": &"", "default_gain": 0.0},
	{"name": BUS_SFX, "default_send": BUS_MASTER, "default_gain": 0.0},
	{"name": BUS_ENGINE_EXHAUST, "default_send": BUS_MASTER, "sfx_send": BUS_SFX, "default_gain": -6.0},
	{"name": BUS_ENGINE_INTAKE, "default_send": BUS_MASTER, "sfx_send": BUS_SFX, "default_gain": -12.0},
	{"name": BUS_EXHAUST_REFLECTION, "default_send": BUS_MASTER, "sfx_send": BUS_SFX, "default_gain": -18.0},
	{"name": BUS_TIRES, "default_send": BUS_MASTER, "sfx_send": BUS_SFX, "default_gain": -10.0},
	{"name": BUS_WIND_CHASSIS, "default_send": BUS_MASTER, "sfx_send": BUS_SFX, "default_gain": -14.0},
	{"name": BUS_AMBIENCE, "default_send": BUS_MASTER, "sfx_send": BUS_MASTER, "default_gain": -20.0},
	{"name": BUS_MUSIC, "default_send": BUS_MASTER, "sfx_send": BUS_MASTER, "default_gain": -18.0},
	{"name": BUS_UI, "default_send": BUS_MASTER, "sfx_send": BUS_SFX, "default_gain": -12.0},
]


## Creates a master gentle compressor effect.
static func create_master_compressor() -> AudioEffectCompressor:
	var comp := AudioEffectCompressor.new()
	comp.threshold = COMPRESSOR_THRESHOLD_DB
	comp.ratio = COMPRESSOR_RATIO
	comp.attack_us = COMPRESSOR_ATTACK_US
	comp.release_ms = COMPRESSOR_RELEASE_MS
	comp.gain = COMPRESSOR_GAIN_DB
	comp.mix = 1.0
	return comp


## Creates a master ceiling limiter effect.
static func create_master_limiter() -> AudioEffectLimiter:
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = LIMITER_CEILING_DB
	lim.threshold_db = LIMITER_THRESHOLD_DB
	lim.soft_clip_db = LIMITER_SOFT_CLIP_DB
	lim.soft_clip_ratio = LIMITER_SOFT_CLIP_RATIO
	return lim


## Creates tires highpass filter (~120 Hz).
static func create_tires_highpass() -> AudioEffectHighPassFilter:
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = TIRES_HIGHPASS_CUTOFF_HZ
	hp.resonance = TIRES_HIGHPASS_RESONANCE
	return hp


## Creates wind chassis highpass filter (~80 Hz).
static func create_wind_highpass() -> AudioEffectHighPassFilter:
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = WIND_HIGHPASS_CUTOFF_HZ
	hp.resonance = WIND_HIGHPASS_RESONANCE
	return hp


## Creates wind chassis aerodynamic EQ shaping.
static func create_wind_eq() -> AudioEffectEQ6:
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(0, -6.0)   # 32 Hz sub-rumble cut
	eq.set_band_gain_db(1, 0.0)    # 100 Hz
	eq.set_band_gain_db(2, 0.0)    # 320 Hz
	eq.set_band_gain_db(3, 0.0)    # 1000 Hz
	eq.set_band_gain_db(4, 1.0)    # 3200 Hz subtle air presence
	eq.set_band_gain_db(5, 0.0)    # 10000 Hz
	return eq


## Creates wet-only delay effect for Exhaust_Reflection bus.
## dry = 0.0 guarantees 100% wet acoustic reflection.
static func create_reflection_delay(initial_delay_ms: float = REFLECTION_INITIAL_DELAY_MS) -> AudioEffectDelay:
	var delay := AudioEffectDelay.new()
	delay.dry = 0.0  # Wet-only!
	delay.tap1_active = true
	delay.tap1_delay_ms = clampf(initial_delay_ms, 15.0, 120.0)
	delay.tap1_level_db = 0.0
	delay.tap1_pan = 0.0
	delay.tap2_active = false
	delay.feedback_active = false
	return delay


## Creates a dynamic lowpass filter for interior/exterior camera mixing.
## Default cutoff is 20500 Hz (wide open, transparent clarity).
static func create_camera_lpf(initial_cutoff_hz: float = LPF_WIDE_OPEN_CUTOFF_HZ) -> AudioEffectLowPassFilter:
	var lpf := AudioEffectLowPassFilter.new()
	lpf.cutoff_hz = initial_cutoff_hz
	lpf.resonance = 0.5
	return lpf


## Configures the active AudioServer buses with the Aster Valley audio hierarchy.
## If [param route_through_sfx] is true, effects buses send to SFX -> Master.
## If false, effects buses send directly to Master.
static func apply_to_audio_server(route_through_sfx: bool = false) -> void:
	# Build bus hierarchy
	AudioServer.set_bus_count(BUS_SPECS.size())
	for i in range(BUS_SPECS.size()):
		var spec: Dictionary = BUS_SPECS[i]
		var bus_name: StringName = spec["name"]
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_volume_db(i, float(spec["default_gain"]))
		AudioServer.set_bus_solo(i, false)
		AudioServer.set_bus_mute(i, false)
		AudioServer.set_bus_bypass_effects(i, false)
		
		# Clear existing effects on this bus slot
		var eff_count := AudioServer.get_bus_effect_count(i)
		for _k in range(eff_count):
			AudioServer.remove_bus_effect(i, 0)

	# Configure bus sends
	for i in range(BUS_SPECS.size()):
		var spec: Dictionary = BUS_SPECS[i]
		var send_name: StringName = spec["sfx_send"] if route_through_sfx and spec.has("sfx_send") else spec["default_send"]
		if send_name != &"":
			AudioServer.set_bus_send(i, send_name)

	# Configure bus effects
	# 1. Master: Compressor + Limiter
	var master_idx := AudioServer.get_bus_index(BUS_MASTER)
	if master_idx >= 0:
		AudioServer.add_bus_effect(master_idx, create_master_compressor())
		AudioServer.add_bus_effect(master_idx, create_master_limiter())

	# 2. Engine_Exhaust: Dynamic LPF for cockpit muffling
	var exhaust_idx := AudioServer.get_bus_index(BUS_ENGINE_EXHAUST)
	if exhaust_idx >= 0:
		AudioServer.add_bus_effect(exhaust_idx, create_camera_lpf())

	# 3. Exhaust_Reflection: Wet-only delay + wall acoustic absorption LPF
	var refl_idx := AudioServer.get_bus_index(BUS_EXHAUST_REFLECTION)
	if refl_idx >= 0:
		AudioServer.add_bus_effect(refl_idx, create_reflection_delay())
		AudioServer.add_bus_effect(refl_idx, create_camera_lpf(REFLECTION_LOWPASS_CUTOFF_HZ))

	# 4. Tires: Highpass ~120 Hz + Dynamic LPF for cockpit muffling
	var tires_idx := AudioServer.get_bus_index(BUS_TIRES)
	if tires_idx >= 0:
		AudioServer.add_bus_effect(tires_idx, create_tires_highpass())
		AudioServer.add_bus_effect(tires_idx, create_camera_lpf())

	# 5. Wind_Chassis: Highpass ~80 Hz + EQ + Dynamic LPF for cockpit muffling
	var wind_idx := AudioServer.get_bus_index(BUS_WIND_CHASSIS)
	if wind_idx >= 0:
		AudioServer.add_bus_effect(wind_idx, create_wind_highpass())
		AudioServer.add_bus_effect(wind_idx, create_wind_eq())
		AudioServer.add_bus_effect(wind_idx, create_camera_lpf())

	# 6. Ambience: Dynamic LPF for cockpit muffling
	var amb_idx := AudioServer.get_bus_index(BUS_AMBIENCE)
	if amb_idx >= 0:
		AudioServer.add_bus_effect(amb_idx, create_camera_lpf())


## Generates an AudioBusLayout resource programmatically.
## Restores the previous AudioServer layout afterwards unless [param keep_applied] is true.
static func build_bus_layout(route_through_sfx: bool = false, keep_applied: bool = false) -> AudioBusLayout:
	var prev_layout: AudioBusLayout = null
	if not keep_applied:
		prev_layout = AudioServer.generate_bus_layout()
	
	apply_to_audio_server(route_through_sfx)
	var layout := AudioServer.generate_bus_layout()
	
	if not keep_applied and prev_layout != null:
		AudioServer.set_bus_layout(prev_layout)
	
	return layout


## Builds and saves the AudioBusLayout resource to disk.
static func save_bus_layout(target_path: String, route_through_sfx: bool = false) -> Error:
	var layout := build_bus_layout(route_through_sfx)
	var err := ResourceSaver.save(layout, target_path)
	if err != OK:
		push_error("Failed to save AudioBusLayout to '%s': error %d" % [target_path, err])
	return err


## Returns the default start gain in dB for a known bus.
static func get_bus_start_gain(bus_name: StringName) -> float:
	return float(START_GAINS.get(bus_name, 0.0))


## Returns true if the bus is part of the canonical Aster Valley bus architecture.
static func is_valid_bus(bus_name: StringName) -> bool:
	return START_GAINS.has(bus_name)
