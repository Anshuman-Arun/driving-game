extends SceneTree
## Deterministic regression and verification test suite for Track D:
## Chassis, Environment, and Acoustics Controller.

const ChassisAudioControllerScript = preload("res://modules/audio/recorded_runtime/chassis/chassis_audio_controller.gd")
const ChassisWindScript = preload("res://modules/audio/recorded_runtime/chassis/chassis_wind.gd")
const ChassisSuspensionScript = preload("res://modules/audio/recorded_runtime/chassis/chassis_suspension.gd")
const ChassisAcousticsScript = preload("res://modules/audio/recorded_runtime/chassis/chassis_acoustics.gd")
const ChassisWavLoaderScript = preload("res://modules/audio/recorded_runtime/chassis/wav_loader.gd")

func _initialize() -> void:
	print("==================================================")
	print("STARTING TRACK D CHASSIS AUDIO VERIFICATION TESTS")
	print("==================================================")

	_test_wav_loader()
	_test_wind_onset_and_exponential_curve()
	_test_suspension_compression_and_cooldown()
	_test_landing_thump()
	_test_impact_velocity_scaling_and_cooldown()
	_test_acoustic_raycast_reflection_and_open_terrain()
	_test_chassis_audio_controller_orchestration()

	print("==================================================")
	print("ALL TRACK D CHASSIS AUDIO TESTS PASSED!")
	print("==================================================")
	quit(0)


func _test_wav_loader() -> void:
	print("[TEST] 1. Testing ChassisWavLoader...")
	var ambience_path := "res://assets/audio/recorded/payload/ambience/mountain_wind_bed.wav"
	var wind_path := "res://modules/audio/assets/wind.wav"
	var suspension_path := "res://modules/audio/assets/suspension.wav"
	var collision_path := "res://modules/audio/assets/collision.wav"

	var s_ambience: AudioStreamWAV = ChassisWavLoaderScript.load_wav(ambience_path)
	var s_wind: AudioStreamWAV = ChassisWavLoaderScript.load_wav(wind_path)
	var s_suspension: AudioStreamWAV = ChassisWavLoaderScript.load_wav(suspension_path)
	var s_collision: AudioStreamWAV = ChassisWavLoaderScript.load_wav(collision_path)

	assert(s_ambience != null, "Ambience stream must load")
	assert(s_wind != null, "Wind stream must load")
	assert(s_suspension != null, "Suspension stream must load")
	assert(s_collision != null, "Collision stream must load")

	assert(s_ambience.mix_rate == 48000, "Mountain wind bed should be 48kHz")
	assert(s_ambience.get_length() > 19.0, "Ambience duration should be ~20s")

	# Test loop configuration
	ChassisWavLoaderScript.configure_loop(s_ambience, true)
	assert(s_ambience.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Loop mode should be forward")
	assert(s_ambience.loop_end > 0, "Loop end should be valid frame")

	print("  -> WAV loading and loop configuration verified.")


func _test_wind_onset_and_exponential_curve() -> void:
	print("[TEST] 2. Testing Wind Onset (~22 m/s), Exponential Curve & Lowpass Shaping...")

	# Below onset: speed = 0, 10, 21.9 m/s
	var t_zero: Dictionary = ChassisWindScript.compute_wind_targets(0.0)
	var t_sub: Dictionary = ChassisWindScript.compute_wind_targets(15.0)
	var t_just_below: Dictionary = ChassisWindScript.compute_wind_targets(21.9)

	assert(float(t_zero["gain"]) == 0.0, "Wind gain at 0 m/s must be 0")
	assert(float(t_sub["gain"]) == 0.0, "Wind gain at 15 m/s must be 0")
	assert(float(t_just_below["gain"]) == 0.0, "Wind gain below 22 m/s must be 0")
	assert(float(t_sub["volume_db"]) == -80.0, "Wind volume below 22 m/s must be -80 dB")
	assert(not bool(t_sub["is_active"]), "Wind should be inactive below 22 m/s")

	# Above onset: 25, 45, 70 m/s
	var t_onset: Dictionary = ChassisWindScript.compute_wind_targets(23.0)
	var t_mid: Dictionary = ChassisWindScript.compute_wind_targets(45.0)
	var t_top: Dictionary = ChassisWindScript.compute_wind_targets(70.0)

	assert(bool(t_onset["is_active"]), "Wind must be active above 22 m/s")
	assert(float(t_onset["gain"]) > 0.0, "Wind gain must be positive above 22 m/s")
	assert(float(t_mid["gain"]) > float(t_onset["gain"]), "Wind gain must increase with speed")
	assert(float(t_top["gain"]) > float(t_mid["gain"]), "Wind gain must peak at top speed")

	# Verify exponential volume curve: rate of growth accelerates
	# norm_mid = (45 - 22) / 48 = 0.479; pow(0.479, 1.8) ~ 0.267
	# Check pow(0.479, 1.8) is less than linear 0.479 (exponential behavior)
	var norm_mid: float = (45.0 - 22.0) / (70.0 - 22.0)
	var gain_norm: float = float(t_mid["gain"]) / float(t_top["gain"])
	assert(gain_norm < norm_mid, "Curve must be exponential (sub-linear below 1.0 norm)")

	# Verify lowpass filter shaping: cutoff scales up from 800 Hz to 14000 Hz
	assert(float(t_onset["cutoff_hz"]) < float(t_mid["cutoff_hz"]), "Cutoff must increase with speed")
	assert(float(t_mid["cutoff_hz"]) < float(t_top["cutoff_hz"]), "Cutoff must increase towards top speed")
	assert(is_equal_approx(float(t_top["cutoff_hz"]), 14000.0), "Cutoff at top speed should reach 14000 Hz")

	print("  -> Wind onset (22 m/s), exponential curve, and lowpass shaping verified.")


func _test_suspension_compression_and_cooldown() -> void:
	print("[TEST] 3. Testing Suspension Travel Compression (delta / dt) and Cooldown (~0.16s)...")

	var suspension: Node = ChassisSuspensionScript.new()
	root.add_child(suspension)

	# 1. Formula check: spring delta / delta time
	var rate1: float = ChassisSuspensionScript.compute_suspension_compression_rate(0.05, 0.016)
	assert(is_equal_approx(rate1, 3.125), "Compression rate should be 0.05 / 0.016 = 3.125 m/s")

	var rate2: float = ChassisSuspensionScript.compute_suspension_compression_rate(0.0, 0.016)
	assert(is_equal_approx(rate2, 0.0), "Zero spring delta should yield 0 rate")

	# 2. Cooldown check: first trigger succeeds
	var triggered1: bool = bool(suspension.call("trigger_suspension", 0.8, 1.0))
	assert(triggered1, "First suspension trigger should succeed")
	assert(float(suspension.get("_suspension_cooldown_timer")) > 0.15, "Suspension cooldown timer should be ~0.16s")

	# Immediate second trigger during cooldown must fail
	var triggered2: bool = bool(suspension.call("trigger_suspension", 0.8, 1.0))
	assert(not triggered2, "Trigger during 0.16s cooldown must be suppressed")

	# Advance time by 0.10s (still within 0.16s cooldown)
	suspension._process(0.10)
	var triggered3: bool = bool(suspension.call("trigger_suspension", 0.8, 1.0))
	assert(not triggered3, "Trigger at 0.10s must still be suppressed")

	# Advance time past 0.16s cooldown
	suspension._process(0.07)
	assert(float(suspension.get("_suspension_cooldown_timer")) == 0.0, "Cooldown timer should have expired")
	var triggered4: bool = bool(suspension.call("trigger_suspension", 0.8, 1.0))
	assert(triggered4, "Trigger after cooldown expiration must succeed")

	suspension.free()
	print("  -> Suspension compression rate and 0.16s cooldown verified.")


func _test_landing_thump() -> void:
	print("[TEST] 4. Testing Contact/Landing Thump on Touchdown...")

	var suspension: Node = ChassisSuspensionScript.new()
	root.add_child(suspension)

	# Simulate airborne flight
	var dt: float = 0.016
	for i in range(10): # 10 frames = 0.16s in air
		suspension.call("process_physics", dt, null, {"on_ground": false})

	assert(bool(suspension.get("_was_airborne")), "Vehicle must be flagged as airborne")

	# Simulate touchdown with downward speed
	var mock_vehicle := Node3D.new()
	mock_vehicle.set("linear_velocity", Vector3(10.0, -6.5, 0.0))
	root.add_child(mock_vehicle)

	suspension.call("process_physics", dt, mock_vehicle, {"on_ground": true})
	assert(not bool(suspension.get("_was_airborne")), "Airborne flag must clear upon touchdown")
	assert(float(suspension.get("_suspension_cooldown_timer")) > 0.14, "Landing thump must set cooldown timer ~0.16s")

	mock_vehicle.free()
	suspension.free()
	print("  -> Contact / landing thump verified.")


func _test_impact_velocity_scaling_and_cooldown() -> void:
	print("[TEST] 5. Testing Impact Audio Velocity-Scaled Volume and Cooldown (~0.12s)...")

	var suspension: Node = ChassisSuspensionScript.new()
	root.add_child(suspension)

	# 1. Velocity scaling calculation
	var gain_parking: float = ChassisSuspensionScript.compute_impact_gain(1.0)
	assert(gain_parking == 0.0, "Speed < 1.5 m/s should have zero impact gain")

	var gain_light: float = ChassisSuspensionScript.compute_impact_gain(5.0)
	var gain_medium: float = ChassisSuspensionScript.compute_impact_gain(15.0)
	var gain_heavy: float = ChassisSuspensionScript.compute_impact_gain(30.0)

	assert(gain_light > 0.0, "Light impact must produce positive gain")
	assert(gain_medium > gain_light, "Medium impact gain must exceed light impact")
	assert(gain_heavy > gain_medium, "Heavy impact gain must exceed medium impact")

	# 2. Cooldown check (~0.12s)
	var hit1: bool = bool(suspension.call("trigger_impact", 12.0, 1.0))
	assert(hit1, "First impact trigger must succeed")
	assert(float(suspension.get("_impact_cooldown_timer")) > 0.11, "Impact cooldown timer should be ~0.12s")

	# Second trigger during 0.12s cooldown must be suppressed
	var hit2: bool = bool(suspension.call("trigger_impact", 15.0, 1.0))
	assert(not hit2, "Impact during 0.12s cooldown must be suppressed")

	# Advance time past 0.12s
	suspension._process(0.13)
	assert(float(suspension.get("_impact_cooldown_timer")) == 0.0, "Impact cooldown should expire")
	var hit3: bool = bool(suspension.call("trigger_impact", 15.0, 1.0))
	assert(hit3, "Impact after cooldown expiration must succeed")

	suspension.free()
	print("  -> Velocity-scaled impact audio and 0.12s cooldown verified.")


func _test_acoustic_raycast_reflection_and_open_terrain() -> void:
	print("[TEST] 6. Testing Acoustic Raycast Reflection (15-120ms) and Open Terrain Bypass...")

	# 1. Open terrain: all rays miss or distance >= 20m
	var open1: Dictionary = ChassisAcousticsScript.compute_acoustic_reflection(INF, INF, INF)
	assert(bool(open1["is_open_terrain"]), "INF distance must be open terrain")
	assert(bool(open1["is_bypassed"]), "Open terrain must be bypassed")
	assert(float(open1["wet_gain"]) == 0.0, "Open terrain wet gain must be 0.0")
	assert(float(open1["wet_db"]) == -80.0, "Open terrain wet dB must be -80.0")

	var open2: Dictionary = ChassisAcousticsScript.compute_acoustic_reflection(25.0, 30.0, 50.0)
	assert(bool(open2["is_open_terrain"]), "Distance > 20m must be open terrain")
	assert(float(open2["wet_gain"]) == 0.0, "Distance > 20m wet gain must be 0.0")

	# 2. Wall proximity: closest wall at 1.0m (tight tunnel or rock wall)
	var close_wall: Dictionary = ChassisAcousticsScript.compute_acoustic_reflection(1.0, 15.0, INF)
	assert(not bool(close_wall["is_open_terrain"]), "Wall at 1m must not be open terrain")
	assert(is_equal_approx(float(close_wall["delay_ms"]), 15.0), "Wall at 1.0m should map to minimum delay 15ms")
	assert(is_equal_approx(float(close_wall["wet_gain"]), 0.85), "Wall at 1.0m should have high wet gain ~0.85")

	# 3. Wall at max reflection range: 20.0m
	var far_wall: Dictionary = ChassisAcousticsScript.compute_acoustic_reflection(20.0, 20.0, 20.0)
	assert(not bool(far_wall["is_open_terrain"]), "Wall at 20.0m is in range")
	assert(is_equal_approx(float(far_wall["delay_ms"]), 120.0), "Wall at 20.0m should map to maximum delay 120ms")
	assert(is_equal_approx(float(far_wall["wet_gain"]), 0.08), "Wall at 20.0m should have low wet gain ~0.08")

	# 4. Mid-range wall: ~10.5m
	var mid_wall: Dictionary = ChassisAcousticsScript.compute_acoustic_reflection(INF, 10.5, INF)
	var expected_delay: float = lerpf(15.0, 120.0, (10.5 - 1.0) / 19.0)
	assert(absf(float(mid_wall["delay_ms"]) - expected_delay) < 0.1, "Mid-range delay should map linearly")
	assert(float(mid_wall["wet_gain"]) > 0.08 and float(mid_wall["wet_gain"]) < 0.85, "Wet gain should be intermediate")

	print("  -> Acoustic reflection distance mapping (15-120ms) and open terrain bypass verified.")


func _test_chassis_audio_controller_orchestration() -> void:
	print("[TEST] 7. Testing ChassisAudioController Unified Orchestration...")

	var controller: Node3D = ChassisAudioControllerScript.new()
	root.add_child(controller)

	var wind_sub: Node = controller.call("get_wind")
	var susp_sub: Node = controller.call("get_suspension")
	var acou_sub: Node = controller.call("get_acoustics")

	assert(wind_sub != null, "Wind subsystem must be instantiated")
	assert(susp_sub != null, "Suspension subsystem must be instantiated")
	assert(acou_sub != null, "Acoustics subsystem must be instantiated")

	# Test telemetry dispatch
	controller.call("update_telemetry", {"speed_mps": 40.0, "on_ground": true})
	assert(float(wind_sub.get("_speed_mps")) == 40.0, "Wind speed should be updated via telemetry")

	# Test acoustics simulation via controller
	var sim: Dictionary = controller.call("simulate_acoustics", 3.0, 18.0, 12.0)
	assert(float(sim["min_distance"]) == 3.0, "Min distance should be 3.0m")
	assert(float(sim["delay_ms"]) > 15.0 and float(sim["delay_ms"]) < 120.0, "Delay should be within 15-120ms")

	# Test trigger delegation
	var susp_ok: bool = bool(controller.call("trigger_suspension", 0.7))
	assert(susp_ok, "Controller trigger_suspension must succeed")

	var imp_ok: bool = bool(controller.call("trigger_impact", 14.0, 0.9))
	assert(imp_ok, "Controller trigger_impact must succeed")

	controller.free()
	print("  -> ChassisAudioController orchestration verified.")
