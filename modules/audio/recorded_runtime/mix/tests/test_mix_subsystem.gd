extends SceneTree
## Self-contained test bench for Aster Valley Audio Bus Layout & Mix Subsystem.

const AsterAudioBusBuilder = preload("../bus_layout_builder.gd")
const AsterCameraMixController = preload("../camera_mix_controller.gd")

func _initialize() -> void:
	print("==================================================")
	print("Starting Aster Valley Mix Subsystem Test Bench...")
	print("==================================================")
	
	var results := {"passed": 0, "failed": 0}

	var check := func(condition: bool, description: String) -> void:
		if condition:
			print("  [PASS] ", description)
			results["passed"] += 1
		else:
			printerr("  [FAIL] ", description)
			results["failed"] += 1

	# ----------------------------------------------------
	# Test 1: Bus Layout Builder with Direct Master Sends
	# ----------------------------------------------------
	print("\n--- Test 1: AudioBusLayout Builder (Direct Sends) ---")
	AsterAudioBusBuilder.apply_to_audio_server(false)

	check.call(AudioServer.get_bus_count() == 10, "Bus count is 10")
	check.call(AudioServer.get_bus_index(&"Master") == 0, "Master bus is index 0")
	check.call(AudioServer.get_bus_index(&"SFX") >= 0, "SFX bus exists")
	check.call(AudioServer.get_bus_index(&"Engine_Exhaust") >= 0, "Engine_Exhaust bus exists")
	check.call(AudioServer.get_bus_index(&"Engine_Intake") >= 0, "Engine_Intake bus exists")
	check.call(AudioServer.get_bus_index(&"Exhaust_Reflection") >= 0, "Exhaust_Reflection bus exists")
	check.call(AudioServer.get_bus_index(&"Tires") >= 0, "Tires bus exists")
	check.call(AudioServer.get_bus_index(&"Wind_Chassis") >= 0, "Wind_Chassis bus exists")
	check.call(AudioServer.get_bus_index(&"Ambience") >= 0, "Ambience bus exists")
	check.call(AudioServer.get_bus_index(&"Music") >= 0, "Music bus exists")
	check.call(AudioServer.get_bus_index(&"UI") >= 0, "UI bus exists")

	# Check Start Gains
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Engine_Exhaust")), -6.0), "Engine_Exhaust gain is -6 dB")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Engine_Intake")), -12.0), "Engine_Intake gain is -12 dB")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Exhaust_Reflection")), -18.0), "Exhaust_Reflection gain is -18 dB")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Tires")), -10.0), "Tires gain is -10 dB")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Wind_Chassis")), -14.0), "Wind_Chassis gain is -14 dB")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Ambience")), -20.0), "Ambience gain is -20 dB")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), -18.0), "Music gain is -18 dB")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"UI")), -12.0), "UI gain is -12 dB")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")), 0.0), "SFX gain is 0 dB")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(0), 0.0), "Master gain is 0 dB")

	# Check Direct Sends
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Engine_Exhaust")) == &"Master", "Engine_Exhaust sends to Master")
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Engine_Intake")) == &"Master", "Engine_Intake sends to Master")
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Exhaust_Reflection")) == &"Master", "Exhaust_Reflection sends to Master")
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Tires")) == &"Master", "Tires sends to Master")
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Wind_Chassis")) == &"Master", "Wind_Chassis sends to Master")
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Ambience")) == &"Master", "Ambience sends to Master")
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Music")) == &"Master", "Music sends to Master")
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"UI")) == &"Master", "UI sends to Master")

	# Check Master Effects
	var comp: AudioEffectCompressor = AudioServer.get_bus_effect(0, 0) as AudioEffectCompressor
	check.call(comp != null, "Master effect 0 is AudioEffectCompressor")
	if comp:
		check.call(is_equal_approx(comp.threshold, -16.0), "Compressor threshold is -16 dB")
		check.call(is_equal_approx(comp.ratio, 2.0), "Compressor ratio is 2:1")
		check.call(is_equal_approx(comp.attack_us, 15000.0), "Compressor attack is 15ms (15000 us)")
		check.call(is_equal_approx(comp.release_ms, 120.0), "Compressor release is 120ms")

	var lim: AudioEffectLimiter = AudioServer.get_bus_effect(0, 1) as AudioEffectLimiter
	check.call(lim != null, "Master effect 1 is AudioEffectLimiter")
	if lim:
		check.call(is_equal_approx(lim.ceiling_db, -1.0), "Limiter ceiling is -1 dB")

	# Check Tires Effects
	var tires_idx := AudioServer.get_bus_index(&"Tires")
	var tires_hp: AudioEffectHighPassFilter = AudioServer.get_bus_effect(tires_idx, 0) as AudioEffectHighPassFilter
	check.call(tires_hp != null and is_equal_approx(tires_hp.cutoff_hz, 120.0), "Tires has highpass filter at ~120 Hz")

	# Check Wind Effects
	var wind_idx := AudioServer.get_bus_index(&"Wind_Chassis")
	var wind_hp: AudioEffectHighPassFilter = AudioServer.get_bus_effect(wind_idx, 0) as AudioEffectHighPassFilter
	var wind_eq: AudioEffectEQ6 = AudioServer.get_bus_effect(wind_idx, 1) as AudioEffectEQ6
	check.call(wind_hp != null and is_equal_approx(wind_hp.cutoff_hz, 80.0), "Wind_Chassis has highpass filter at ~80 Hz")
	check.call(wind_eq != null, "Wind_Chassis has EQ6 shaping")

	# Check Exhaust_Reflection Wet-only Delay
	var refl_idx := AudioServer.get_bus_index(&"Exhaust_Reflection")
	var refl_delay: AudioEffectDelay = AudioServer.get_bus_effect(refl_idx, 0) as AudioEffectDelay
	check.call(refl_delay != null, "Exhaust_Reflection has AudioEffectDelay")
	if refl_delay:
		check.call(is_equal_approx(refl_delay.dry, 0.0), "Exhaust_Reflection delay is 100% wet (dry = 0.0)")
		check.call(refl_delay.tap1_active, "Exhaust_Reflection tap1 is active")
		check.call(refl_delay.tap1_delay_ms >= 15.0 and refl_delay.tap1_delay_ms <= 120.0, "Exhaust_Reflection tap1 delay in 15-120ms range")

	# ----------------------------------------------------
	# Test 2: SFX Submix Routing Mode
	# ----------------------------------------------------
	print("\n--- Test 2: AudioBusLayout Builder (SFX Submix Mode) ---")
	AsterAudioBusBuilder.apply_to_audio_server(true)
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Engine_Exhaust")) == &"SFX", "Engine_Exhaust sends to SFX")
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Tires")) == &"SFX", "Tires sends to SFX")
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Wind_Chassis")) == &"SFX", "Wind_Chassis sends to SFX")
	check.call(AudioServer.get_bus_send(AudioServer.get_bus_index(&"SFX")) == &"Master", "SFX sends to Master")

	# ----------------------------------------------------
	# Test 3: Save and Load .tres Resources
	# ----------------------------------------------------
	print("\n--- Test 3: Resource Serialization ---")
	var base_dir := (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var path_direct := base_dir.path_join("aster_bus_layout.tres")
	var err1 := AsterAudioBusBuilder.save_bus_layout(path_direct, false)
	check.call(err1 == OK, "Saved aster_bus_layout.tres successfully to %s" % path_direct)

	var path_sfx := base_dir.path_join("aster_bus_layout_sfx.tres")
	var err2 := AsterAudioBusBuilder.save_bus_layout(path_sfx, true)
	check.call(err2 == OK, "Saved aster_bus_layout_sfx.tres successfully to %s" % path_sfx)

	# Verify loading saved resources
	var loaded_layout: AudioBusLayout = ResourceLoader.load(path_direct)
	check.call(loaded_layout != null, "ResourceLoader loaded aster_bus_layout.tres")

	# Re-apply direct layout as the primary active layout
	AsterAudioBusBuilder.apply_to_audio_server(false)

	# ----------------------------------------------------
	# Test 4: Camera Mix Controller (Smoothing & Acoustics)
	# ----------------------------------------------------
	print("\n--- Test 4: AsterCameraMixController ---")
	var mix_ctrl := AsterCameraMixController.new()
	root.add_child(mix_ctrl)
	mix_ctrl.refresh_bus_cache()

	# Exterior view test (Chase cam: weight 0.0)
	mix_ctrl.set_interior_weight(0.0, true)
	check.call(is_equal_approx(mix_ctrl.get_interior_weight(), 0.0), "Chase view: interior weight is 0.0")
	var exh_idx := AudioServer.get_bus_index(&"Engine_Exhaust")
	var intake_idx := AudioServer.get_bus_index(&"Engine_Intake")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(exh_idx), -6.0), "Chase view: Engine_Exhaust volume is -6 dB")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(intake_idx), -12.0), "Chase view: Engine_Intake volume is -12 dB")
	var exh_lpf: AudioEffectLowPassFilter = AudioServer.get_bus_effect(exh_idx, 0) as AudioEffectLowPassFilter
	if exh_lpf:
		check.call(exh_lpf.cutoff_hz >= 20000.0, "Chase view: Engine_Exhaust LPF cutoff is wide open (~20500 Hz)")

	# Interior view test (Cockpit cam: weight 1.0)
	mix_ctrl.set_interior_weight(1.0, true)
	check.call(is_equal_approx(mix_ctrl.get_interior_weight(), 1.0), "Cockpit view: interior weight is 1.0")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(exh_idx), -10.0), "Cockpit view: Engine_Exhaust muffled (-10 dB)")
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(intake_idx), -6.0), "Cockpit view: Engine_Intake emphasized (-6 dB, +6 dB boost)")
	if exh_lpf:
		check.call(is_equal_approx(exh_lpf.cutoff_hz, 1800.0), "Cockpit view: Engine_Exhaust LPF muffled down to 1800 Hz")

	# Smoothing test over time
	mix_ctrl.smoothing_time = 0.20
	mix_ctrl.set_interior_weight(0.0, false) # target 0.0, smoothing active
	check.call(is_equal_approx(mix_ctrl.get_interior_weight(), 1.0), "Immediately after target change, weight remains 1.0")
	# Step 100ms
	mix_ctrl._process(0.10)
	var mid_weight := mix_ctrl.get_interior_weight()
	check.call(mid_weight < 0.95 and mid_weight > 0.30, "After 100ms, weight smoothed partially (got %0.3f)" % mid_weight)
	# Step another 400ms
	mix_ctrl._process(0.40)
	check.call(mix_ctrl.get_interior_weight() < 0.10, "After 500ms total, weight settled near target (got %0.3f)" % mix_ctrl.get_interior_weight())

	# Reset back to exterior clear view for game start
	mix_ctrl.set_interior_weight(0.0, true)
	mix_ctrl.queue_free()

	print("\n==================================================")
	print("Mix Subsystem Test Results: %d PASSED, %d FAILED" % [results["passed"], results["failed"]])
	print("==================================================")
	quit(results["failed"])
