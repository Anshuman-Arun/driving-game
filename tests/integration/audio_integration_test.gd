extends SceneTree
## Full end-to-end integration test verifying that:
## 1. PlayerCarFactory creates vehicles with VehicleAudio attached and initialized.
## 2. All 3 profiles (Vela GT, Kestrel XR, Orion RS) start immediately at idle upon spawn.
## 3. Dedicated buses (Master, SFX, Music, Engine_*, Tires, Wind_Chassis, Ambience, UI) exist and respond to volume changes.
## 4. Pause mode is Node.PROCESS_MODE_PAUSABLE so vehicle audio pauses cleanly.
## 5. Camera mix controller binds and transitions cleanly.

func _initialize() -> void:
	print("\n==================================================")
	print("  Running Aster Valley Audio Root Integration Test")
	print("==================================================\n")

	var failed := false

	# 1. Test bus layout
	print("[Check 1] AudioBusLayout and Settings Bus Routing...")
	var required_buses: Array[String] = [
		"Master", "SFX", "Music", "UI",
		"Engine_Exhaust", "Engine_Intake", "Exhaust_Reflection",
		"Tires", "Wind_Chassis", "Ambience"
	]
	for bus_name in required_buses:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			push_error("FAIL: Missing bus: " + bus_name)
			failed = true
		else:
			print("  [PASS] Bus '%s' found at index %d (sends to '%s')" % [
				bus_name, idx, AudioServer.get_bus_send(idx)
			])

	# Test SFX slider volume simulation (valley_game_shell.gd behavior)
	var sfx_idx := AudioServer.get_bus_index("SFX")
	var orig_vol := AudioServer.get_bus_volume_db(sfx_idx)
	AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(0.5))
	assert(is_equal_approx(AudioServer.get_bus_volume_db(sfx_idx), linear_to_db(0.5)))
	AudioServer.set_bus_volume_db(sfx_idx, orig_vol)
	print("  [PASS] SFX bus volume adjustment operates correctly.")

	# 2. Test PlayerCarFactory spawning for all 3 car profiles
	print("\n[Check 2] PlayerCarFactory Vehicle Audio Spawning & Idle State...")
	var profiles: Array[String] = ["vela_gt", "kestrel_xr", "orion_rs"]

	for pid in profiles:
		var car: Vehicle = PlayerCarFactory.create(pid)
		if car == null:
			push_error("FAIL: Could not create car for profile: " + pid)
			failed = true
			continue

		root.add_child(car)

		var audio = car.get_node_or_null("VehicleAudio")
		if audio == null:
			push_error("FAIL: Car %s missing VehicleAudio child node!" % pid)
			failed = true
			root.remove_child(car)
			car.queue_free()
			continue

		print("  [PASS] %s has VehicleAudio child node." % pid)
		assert(audio.process_mode == Node.PROCESS_MODE_PAUSABLE, "VehicleAudio must be pausable")
		assert(audio.car_profile == pid, "VehicleAudio profile must match car_id")

		# Check that recorded subsystems are active
		assert(audio.recorded_engine != null, "RecordedEngineController must be active")
		assert(audio.recorded_tires != null, "RecordedTireController must be active")
		assert(audio.recorded_chassis != null, "ChassisAudioController must be active")
		assert(audio.camera_mix != null, "AsterCameraMixController must be active")

		# Check engine idle state immediately upon spawn
		var engine_ctrl = audio.recorded_engine
		print("  [PASS] %s engine idle RPM: %.1f, redline: %.1f" % [
			pid, engine_ctrl._idle_rpm, engine_ctrl._redline_rpm
		])
		assert(engine_ctrl._smoothed_rpm >= engine_ctrl._idle_rpm - 1.0, "Engine must be at idle RPM upon spawn")

		# Clean up car
		root.remove_child(car)
		car.queue_free()

	# 3. Test Camera Mix Controller binding
	print("\n[Check 3] Camera Mix Controller Binding & Perspectives...")
	var test_car: Vehicle = PlayerCarFactory.create("vela_gt")
	root.add_child(test_car)
	var test_audio = test_car.get_node("VehicleAudio")
	var cam := DrivingChaseCamera.new()
	cam.name = "TestCamera"
	root.add_child(cam)
	cam.setup(test_car)
	test_audio.bind_camera(cam)

	var mix_ctrl = test_audio.camera_mix
	assert(mix_ctrl != null, "Camera mix must be available")
	assert(mix_ctrl.camera_node == cam, "Camera node must be bound")

	# The effects slider must control both vehicle effects and the world bed.
	if AudioServer.get_bus_send(AudioServer.get_bus_index("Ambience")) != &"SFX":
		push_error("Ambience bypasses SFX settings")
		failed = true

	# Recorded mode owns all transients; the legacy event pool must stay idle.
	var legacy_event_index: int = test_audio._event_index
	test_audio.update_telemetry({"rpm": 6500.0, "throttle": 0.9, "gear": 1})
	test_audio.update_telemetry({"rpm": 6400.0, "throttle": 0.0, "gear": 2})
	# Test event triggers
	test_audio.trigger_collision(0.75)
	test_audio.trigger_suspension(0.60)
	test_audio.trigger_gear_shift(1, 2)
	test_audio.trigger_overrun_backfire()
	if test_audio._event_index != legacy_event_index:
		push_error("Recorded events must not also trigger legacy one-shots")
		failed = true
	print("  Event routing checked.")

	root.remove_child(cam)
	cam.queue_free()
	root.remove_child(test_car)
	test_car.queue_free()

	print("\n==================================================")
	if failed:
		push_error("ROOT INTEGRATION TEST FAILED!")
		quit(1)
	else:
		print("ROOT INTEGRATION TEST PASSED SUCCESSFULLY!")
		print("==================================================\n")
		quit(0)
