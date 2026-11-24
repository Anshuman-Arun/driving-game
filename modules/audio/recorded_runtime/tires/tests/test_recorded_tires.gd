extends SceneTree
## Comprehensive verification suite for RecordedTireController.
## Run with: godot --headless --path . --script res://modules/audio/recorded_runtime/tires/tests/test_recorded_tires.gd

const RecordedTireControllerScript := preload("res://modules/audio/recorded_runtime/tires/recorded_tire_controller.gd")
const AsterTireTelemetryScript := preload("res://modules/audio/recorded_runtime/tires/tire_telemetry.gd")

const AudioTestCleanup := preload("res://tests/integration/audio_qa/audio_test_cleanup.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print("Starting RecordedTireController Test Suite")
	print("==================================================")

	var failures := 0
	failures += _test_instantiation_and_streams()
	failures += _test_telemetry_normalization()
	failures += _test_speed_gating()
	failures += _test_scrub_and_hysteresis()
	failures += _test_envelope_attack_release()
	failures += _test_airborne_fade()
	failures += _test_surface_switching()
	failures += _test_mixed_contact_and_loose_surface()

	await AudioTestCleanup.drain(self)
	print("==================================================")
	if failures == 0:
		print("ALL RECORDED TIRE TESTS PASSED (0 failures)")
		print("==================================================")
		quit(0)
	else:
		print("RECORDED TIRE TESTS FAILED: %d errors" % failures)
		print("==================================================")
		quit(1)


func _test_instantiation_and_streams() -> int:
	print("\n[Test 1] Instantiation, audio streams, and bus routing...")
	var controller = RecordedTireControllerScript.new()
	root.add_child(controller)

	var players: Dictionary = controller.get_players()
	assert(players.size() == 5, "Expected 5 tire audio players")

	for name in ["roll_asphalt", "roll_gravel", "roll_grass", "scrub", "screech"]:
		var player: AudioStreamPlayer = players[name]
		if player == null:
			printerr("Player %s is null" % name)
			AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
			return 1
		if player.stream == null:
			printerr("Player %s stream is null" % name)
			AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
			return 1
		var wav := player.stream as AudioStreamWAV
		if wav == null:
			printerr("Player %s stream is not AudioStreamWAV" % name)
			AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
			return 1
		if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			printerr("Player %s loop_mode != LOOP_FORWARD" % name)
			AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
			return 1
		if wav.loop_end <= wav.loop_begin:
			printerr("Player %s invalid loop endpoints: begin=%d, end=%d" % [name, wav.loop_begin, wav.loop_end])
			AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
			return 1
		print("  Player %s: WAV len=%.3fs, rate=%d, loop_end=%d, bus=%s" % [name, wav.get_length(), wav.mix_rate, wav.loop_end, player.bus])

	AudioTestCleanup.stop_tree(controller)
	controller.queue_free()
	print("  PASS: Instantiation & streams verified.")
	return 0


func _test_telemetry_normalization() -> int:
	print("\n[Test 2] Telemetry normalization...")
	var t_dict: Dictionary = AsterTireTelemetryScript.from_dictionary({
		"speed_mps": 22.5,
		"lateral_slip": 0.35,
		"on_ground": true,
		"surface": "dirt",
	})
	if absf(float(t_dict["speed_mps"]) - 22.5) > 0.001:
		printerr("Speed mismatch")
		return 1
	if absf(float(t_dict["slip_amount"]) - 0.35) > 0.001:
		printerr("Slip mismatch")
		return 1
	if str(t_dict["surface"]) != "gravel":
		printerr("Surface normalization failed: expected gravel for dirt, got %s" % t_dict["surface"])
		return 1
	if not bool(t_dict["on_ground"]):
		printerr("Ground state mismatch")
		return 1

	print("  PASS: Telemetry normalization verified.")
	return 0


func _test_speed_gating() -> int:
	print("\n[Test 3] Speed gating (prevent stationary squeal)...")
	var controller = RecordedTireControllerScript.new()
	root.add_child(controller)

	# Stationary car (speed = 0.0 m/s), full slip (burnout / locked wheels / parked)
	controller.update_telemetry({
		"speed_mps": 0.0,
		"slip_amount": 0.95,
		"on_ground": true,
		"surface": "asphalt"
	}, 0.1)

	var state: Dictionary = controller.get_debug_state()
	if float(state["speed_gate"]) > 0.001:
		printerr("Speed gate should be 0.0 at speed 0, got %f" % state["speed_gate"])
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1
	if float(state["screech_envelope"]) > 0.001:
		printerr("Screech envelope should be 0.0 at speed 0, got %f" % state["screech_envelope"])
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# Crawl speed (speed = 1.0 m/s < 1.5 m/s threshold)
	controller.update_telemetry({
		"speed_mps": 1.0,
		"slip_amount": 0.95,
		"on_ground": true,
		"surface": "asphalt"
	}, 0.1)
	state = controller.get_debug_state()
	if float(state["speed_gate"]) > 0.001:
		printerr("Speed gate should be 0.0 at speed 1.0 m/s, got %f" % state["speed_gate"])
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# Driving speed (speed = 25.0 m/s)
	controller.update_telemetry({
		"speed_mps": 25.0,
		"slip_amount": 0.95,
		"on_ground": true,
		"surface": "asphalt"
	}, 0.1)
	state = controller.get_debug_state()
	if absf(float(state["speed_gate"]) - 1.0) > 0.001:
		printerr("Speed gate should be 1.0 at speed 25 m/s, got %f" % state["speed_gate"])
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	AudioTestCleanup.stop_tree(controller)
	controller.queue_free()
	print("  PASS: Stationary speed gating strictly verified.")
	return 0


func _test_scrub_and_hysteresis() -> int:
	print("\n[Test 4] Scrub range (0.15 - 0.45) and Screech Hysteresis (>0.45 enter, <0.38 exit)...")
	var controller = RecordedTireControllerScript.new()
	root.add_child(controller)

	# 1. Clean rolling (slip = 0.05)
	controller.update_telemetry({"speed_mps": 20.0, "slip_amount": 0.05, "on_ground": true}, 0.05)
	if controller.is_scrubbing() or controller.is_screeching():
		printerr("Neither scrub nor screech should be active at slip 0.05")
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# 2. Moderate slip: Scrub (slip = 0.30)
	controller.update_telemetry({"speed_mps": 20.0, "slip_amount": 0.30, "on_ground": true}, 0.05)
	if not controller.is_scrubbing():
		printerr("Scrub should be active at slip 0.30")
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1
	if controller.is_screeching():
		printerr("Screech should NOT be active at slip 0.30")
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# 3. High slip: Screech Entry (> 0.45)
	controller.update_telemetry({"speed_mps": 20.0, "slip_amount": 0.50, "on_ground": true}, 0.05)
	if not controller.is_screeching():
		printerr("Screech should be active at slip 0.50")
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# 4. Hysteresis test: Reduce slip to 0.41 (between 0.38 and 0.45)
	controller.update_telemetry({"speed_mps": 20.0, "slip_amount": 0.41, "on_ground": true}, 0.05)
	if not controller.is_screeching():
		printerr("Screech SHOULD REMAIN active at slip 0.41 due to hysteresis (exit is < 0.38)")
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# 5. Drop below hysteresis threshold (< 0.38)
	controller.update_telemetry({"speed_mps": 20.0, "slip_amount": 0.35, "on_ground": true}, 0.05)
	if controller.is_screeching():
		printerr("Screech should exit at slip 0.35")
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1
	if not controller.is_scrubbing():
		printerr("Scrub should still be active at slip 0.35")
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	AudioTestCleanup.stop_tree(controller)
	controller.queue_free()
	print("  PASS: Scrub and screech hysteresis verified.")
	return 0


func _test_envelope_attack_release() -> int:
	print("\n[Test 5] Envelope attack (~80ms) and release (~180ms)...")
	var controller = RecordedTireControllerScript.new()
	root.add_child(controller)

	# Start at clean grip
	controller.update_telemetry({"speed_mps": 20.0, "slip_amount": 0.0, "on_ground": true}, 0.01)

	# Step slip to 0.70 (target = 0.35 + 0.65 * (0.70 - 0.38) / 0.62 ~= 0.685)
	# At dt = 80ms (1 time constant tau = 80ms), envelope reaches ~63.2% of target (~0.433)
	controller.update_telemetry({"speed_mps": 20.0, "slip_amount": 0.70, "on_ground": true}, 0.080)
	var env_80ms: float = controller.get_screech_envelope()
	if env_80ms < 0.38 or env_80ms > 0.48:
		printerr("Attack envelope after 80ms expected ~0.43, got %f" % env_80ms)
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# Let it reach steady state over 500ms
	for i in range(10):
		controller.update_telemetry({"speed_mps": 20.0, "slip_amount": 0.70, "on_ground": true}, 0.05)
	var peak_env: float = controller.get_screech_envelope()
	if absf(peak_env - 0.685) > 0.03:
		printerr("Peak envelope should reach ~0.685, got %f" % peak_env)
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# Release step to 0 slip
	# After 180ms (1 time constant tau = 180ms), envelope decays to ~36.8% of peak (~0.252)
	controller.update_telemetry({"speed_mps": 20.0, "slip_amount": 0.0, "on_ground": true}, 0.180)
	var decay_180ms: float = controller.get_screech_envelope()
	var expected_decay := peak_env * exp(-1.0)
	if absf(decay_180ms - expected_decay) > 0.04:
		printerr("Release envelope after 180ms expected ~%.3f, got %.3f" % [expected_decay, decay_180ms])
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	AudioTestCleanup.stop_tree(controller)
	controller.queue_free()
	print("  PASS: Attack (80ms) and Release (180ms) envelope timing verified.")
	return 0


func _test_airborne_fade() -> int:
	print("\n[Test 6] Airborne fade out...")
	var controller = RecordedTireControllerScript.new()
	root.add_child(controller)

	# Driving on asphalt at 30 m/s
	for i in range(10):
		controller.update_telemetry({"speed_mps": 30.0, "slip_amount": 0.60, "on_ground": true, "surface": "asphalt"}, 0.05)
	if controller.get_ground_factor() < 0.95:
		printerr("Ground factor should be ~1.0 when grounded, got %f" % controller.get_ground_factor())
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# Jump into the air (on_ground = false)
	# After 500ms airborne (10 * 50ms, tau = 100ms for ground, 180ms for screech), both should drop near 0
	for i in range(10):
		controller.update_telemetry({"speed_mps": 30.0, "slip_amount": 0.60, "on_ground": false, "surface": "asphalt"}, 0.05)
	if controller.get_ground_factor() > 0.05:
		printerr("Ground factor should decay when airborne, got %f" % controller.get_ground_factor())
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1
	if controller.get_screech_envelope() > 0.05:
		printerr("Screech envelope should decay when airborne, got %f" % controller.get_screech_envelope())
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	AudioTestCleanup.stop_tree(controller)
	controller.queue_free()
	print("  PASS: Airborne fade out verified.")
	return 0


func _test_surface_switching() -> int:
	print("\n[Test 7] Surface switching and roll gains...")
	var controller = RecordedTireControllerScript.new()
	root.add_child(controller)

	# Asphalt
	for i in range(10):
		controller.update_telemetry({"speed_mps": 25.0, "surface": "asphalt", "on_ground": true}, 0.05)
	var w_asphalt: Dictionary = controller.get_surface_weights()
	if float(w_asphalt["asphalt"]) < 0.90:
		printerr("Expected asphalt weight > 0.90, got %f" % float(w_asphalt["asphalt"]))
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# Gravel
	for i in range(10):
		controller.update_telemetry({"speed_mps": 25.0, "surface": "gravel", "on_ground": true}, 0.05)
	var w_gravel: Dictionary = controller.get_surface_weights()
	if float(w_gravel["gravel"]) < 0.90:
		printerr("Expected gravel weight > 0.90, got %f" % float(w_gravel["gravel"]))
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	# Grass
	for i in range(10):
		controller.update_telemetry({"speed_mps": 25.0, "surface": "grass", "on_ground": true}, 0.05)
	var w_grass: Dictionary = controller.get_surface_weights()
	if float(w_grass["grass"]) < 0.90:
		printerr("Expected grass weight > 0.90, got %f" % float(w_grass["grass"]))
		AudioTestCleanup.stop_tree(controller)
		controller.queue_free()
		return 1

	AudioTestCleanup.stop_tree(controller)
	controller.queue_free()
	print("  PASS: Surface switching verified.")
	return 0


func _test_mixed_contact_and_loose_surface() -> int:
	var telemetry := AsterTireTelemetryScript.from_dictionary({"surface": "asphalt", "surface_counts": {"asphalt": 2, "gravel": 1, "grass": 1}})
	var weights: Dictionary = telemetry["surface_weights"]
	if not (is_equal_approx(float(weights["asphalt"]), 0.5) and is_equal_approx(float(weights["gravel"]), 0.25) and is_equal_approx(float(weights["grass"]), 0.25)):
		printerr("Mixed contact distribution lost")
		return 1
	var gravel := RecordedTireControllerScript.compute_tire_targets({"speed_mps": 25.0, "slip_amount": 0.9, "surface": "gravel", "on_ground": true}, {}, 0.2)
	var asphalt := RecordedTireControllerScript.compute_tire_targets({"speed_mps": 25.0, "slip_amount": 0.9, "surface": "asphalt", "on_ground": true}, {}, 0.2)
	if float(gravel["screech_envelope"]) > 0.001 or float(asphalt["screech_envelope"]) < 0.1:
		printerr("Paved and loose surface squeal must differ")
		return 1
	return 0
