extends SceneTree
## Comprehensive integration test suite for Track B recorded engine runtime.
## Run: godot --headless --path wt-audio-swarm-pass1 --script res://modules/audio/recorded_runtime/engine/tests/test_recorded_engine.gd

const EngineWavLoader = preload("../engine_wav_loader.gd")
const EngineProfileManifest = preload("../engine_profile_manifest.gd")
const RecordedEngineController = preload("../recorded_engine_controller.gd")

const PROFILES := ["vela_gt", "kestrel_xr", "orion_rs"]

func _initialize() -> void:
	print("==================================================")
	print("   Aster Valley · Recorded Engine Runtime Tests   ")
	print("==================================================")

	var success := true
	success = test_manifest_loading() and success
	success = test_wav_loader_and_loop_config() and success
	success = test_pcm_loop_conditioning() and success
	success = test_constant_power_blending() and success
	success = test_load_layer_blending() and success
	success = test_low_rpm_coast_fallback() and success
	success = test_pitch_matched_crossfade() and success
	success = test_controller_lifecycle_and_smoothing() and success
	success = test_rev_limiter_stutter() and success
	success = test_gear_shift_envelope() and success
	success = test_overrun_backfire() and success
	success = test_profile_switching() and success

	print("==================================================")
	if success:
		print("  ALL TRACK B ENGINE TESTS PASSED SUCCESSFULLY!   ")
		print("==================================================")
		quit(0)
	else:
		push_error("  SOME TRACK B ENGINE TESTS FAILED!   ")
		print("==================================================")
		quit(1)


func test_manifest_loading() -> bool:
	print("\n[TEST 1] Testing manifest loading and parsing...")
	for prof in PROFILES:
		var manifest := EngineProfileManifest.load_for_profile(prof)
		if manifest == null:
			push_error("Failed to load manifest for " + prof)
			return false

		print("  Profile: %s | Loops: %d (On: %d, Off: %d) | RPM: %.0f..%.0f" % [
			manifest.profile_name,
			manifest.loops.size(),
			manifest.on_anchors.size(),
			manifest.off_anchors.size(),
			manifest.min_rpm,
			manifest.max_rpm
		])

		# Verify sorting
		for i in range(manifest.on_anchors.size() - 1):
			var r0: float = float(manifest.on_anchors[i]["rpm"])
			var r1: float = float(manifest.on_anchors[i + 1]["rpm"])
			if r0 > r1:
				push_error("On anchors not sorted ascending in " + prof)
				return false

		for i in range(manifest.off_anchors.size() - 1):
			var r0: float = float(manifest.off_anchors[i]["rpm"])
			var r1: float = float(manifest.off_anchors[i + 1]["rpm"])
			if r0 > r1:
				push_error("Off anchors not sorted ascending in " + prof)
				return false

		if prof == "vela_gt":
			assert(manifest.on_anchors.size() == 7, "Vela GT must have 7 on anchors")
			assert(manifest.off_anchors.size() == 7, "Vela GT must have 7 off anchors")
			assert(manifest.has_off_layer == true, "Vela GT must have off layer")
		elif prof == "kestrel_xr":
			assert(manifest.on_anchors.size() == 7, "Kestrel XR must have 7 on anchors")
			assert(manifest.off_anchors.size() == 5, "Kestrel XR must have 5 off anchors")
			assert(manifest.has_off_layer == true, "Kestrel XR must have off layer")
		elif prof == "orion_rs":
			assert(manifest.on_anchors.size() == 6, "Orion RS must have 6 on anchors")
			assert(manifest.off_anchors.size() == 0, "Orion RS has no off anchors")
			assert(manifest.has_off_layer == false, "Orion RS single-layer fallback")

	print("  -> Manifest loading PASS")
	return true


func test_wav_loader_and_loop_config() -> bool:
	print("\n[TEST 2] Testing WAV loading and loop configuration...")
	var total_checked := 0
	for prof in PROFILES:
		var manifest := EngineProfileManifest.load_for_profile(prof)
		for entry in manifest.loops:
			var path: String = str(entry["full_path"])
			var wav := EngineWavLoader.load_wav(path)
			if wav == null:
				push_error("Failed to load WAV: " + path)
				return false

			if wav.mix_rate != 48000:
				push_error("Expected 48000 Hz, got %d for %s" % [wav.mix_rate, path])
				return false

			if wav.stereo:
				push_error("Expected mono WAV, got stereo for %s" % path)
				return false

			if wav.data.is_empty():
				push_error("WAV has empty PCM data: " + path)
				return false

			EngineWavLoader.configure_loop(wav, true)
			if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD:
				push_error("Expected loop_mode LOOP_FORWARD for %s" % path)
				return false

			if wav.loop_begin != 0:
				push_error("Expected loop_begin 0 for %s" % path)
				return false

			var expected_end := int(round(wav.get_length() * float(wav.mix_rate)))
			if wav.loop_end != expected_end:
				push_error("Loop end mismatch: got %d, expected %d for %s" % [wav.loop_end, expected_end, path])
				return false

			total_checked += 1

	print("  -> Verified %d WAV files (all 48kHz mono, loop configured) PASS" % total_checked)
	return true


func test_pcm_loop_conditioning() -> bool:
	var path := "res://assets/audio/recorded/payload/engines/kestrel_xr/on_1000.wav"
	var source := EngineWavLoader.load_wav(path)
	var conditioned := EngineWavLoader.load_engine_loop(path)
	if source == null or conditioned == null:
		push_error("Missing source/conditioned engine stream")
		return false
	if source == conditioned or not is_equal_approx(source.get_length(), conditioned.get_length()):
		push_error("Conditioning must not mutate source stream or duration")
		return false
	# Verify a synthetic discontinuity independently of Godot WAV import settings.
	var pcm := PackedByteArray()
	pcm.resize(480 * 2)
	for i in range(480):
		pcm.encode_s16(i * 2, 4000 if i < 240 else -2000)
	var repaired := EngineWavLoader.condition_pcm16_seam(pcm, 48000)
	if repaired.size() != pcm.size() or repaired.decode_s16(0) != repaired.decode_s16(958):
		push_error("PCM seam was not joined")
		return false
	if pcm.decode_s16(0) != 4000 or pcm.decode_s16(958) != -2000 or repaired.decode_s16(200 * 2) != 4000:
		push_error("Conditioning changed source or interior samples")
		return false
	# The committed candidate bank is PCM16 mono at 48 kHz.
	if conditioned.format == AudioStreamWAV.FORMAT_16_BITS and not conditioned.stereo:
		var data := conditioned.data
		if absi(data.decode_s16(0) - data.decode_s16(data.size() - 2)) >= 128:
			push_error("Conditioned real engine seam remains discontinuous")
			return false
	return true


func test_constant_power_blending() -> bool:
	print("\n[TEST 3] Testing constant-power cos/sin anchor blend math...")
	for prof in PROFILES:
		var manifest := EngineProfileManifest.load_for_profile(prof)
		var manifest_dict := {
			"profile": manifest.profile_name,
			"loops": manifest.loops
		}

		# Sweep RPM across profile range
		var rpm_start := 1200.0
		var rpm_end := 7800.0
		var steps := 25

		for i in range(steps):
			var rpm := lerpf(rpm_start, rpm_end, float(i) / float(steps - 1))
			var state := RecordedEngineController.compute_blend_state(rpm, 0.7, manifest_dict)

			# Verify ON power sum = 1.0 (error < 0.001)
			var on_pwr: float = float(state["on_power_sum"])
			if absf(on_pwr - 1.0) > 0.001:
				push_error("[%s] RPM %.1f ON power sum = %f (expected 1.0)" % [prof, rpm, on_pwr])
				return false

			# If profile has off layer, verify OFF power sum = 1.0
			if manifest.has_off_layer and rpm >= float(manifest.off_anchors[0]["rpm"]):
				var off_pwr: float = float(state["off_power_sum"])
				if absf(off_pwr - 1.0) > 0.001:
					push_error("[%s] RPM %.1f OFF power sum = %f (expected 1.0)" % [prof, rpm, off_pwr])
					return false

			# Verify pitch scaling clamp ranges
			for p in (state["on_pitches"] as Dictionary).values():
				var pitch := float(p)
				if pitch < 0.40 or pitch > 1.56:
					push_error("[%s] RPM %.1f pitch scale out of range: %f" % [prof, rpm, pitch])
					return false

	print("  -> Constant-power cos/sin anchor blend sweeps PASS")
	return true


func test_load_layer_blending() -> bool:
	print("\n[TEST 4] Testing load layer blending (ON vs OFF)...")
	var manifest := EngineProfileManifest.load_for_profile("vela_gt")
	var manifest_dict := {"profile": "vela_gt", "loops": manifest.loops}

	# Sweep throttle from 0.0 to 1.0
	for step in range(11):
		var thr := float(step) / 10.0
		var state := RecordedEngineController.compute_blend_state(4500.0, thr, manifest_dict)
		var layer_pwr: float = float(state["layer_power_sum"])
		if absf(layer_pwr - 1.0) > 0.001:
			push_error("Throttle %.2f layer power sum = %f (expected 1.0)" % [thr, layer_pwr])
			return false

		var on_gain: float = float(state["on_layer_gain"])
		var off_gain: float = float(state["off_layer_gain"])
		if thr == 0.0:
			assert(on_gain == 0.0 and off_gain == 1.0, "At 0 throttle, OFF layer must be 1.0, ON 0.0")
		elif thr == 1.0:
			assert(is_equal_approx(on_gain, 1.0) and is_equal_approx(off_gain, 0.0), "At 1 throttle, ON layer must be 1.0, OFF 0.0")

	# Test Orion RS single layer fallback
	var orion_manifest := EngineProfileManifest.load_for_profile("orion_rs")
	var orion_dict := {"profile": "orion_rs", "loops": orion_manifest.loops}
	var orion_idle := RecordedEngineController.compute_blend_state(1000.0, 0.0, orion_dict)
	var orion_full := RecordedEngineController.compute_blend_state(1000.0, 1.0, orion_dict)
	assert(float(orion_idle["on_layer_gain"]) > 0.35, "Orion single layer idle must have audible base gain")
	assert(float(orion_full["on_layer_gain"]) == 1.0, "Orion single layer full throttle must be 1.0")

	print("  -> Load layer ON/OFF crossfading PASS")
	return true


func test_low_rpm_coast_fallback() -> bool:
	var manifest := EngineProfileManifest.load_for_profile("kestrel_xr")
	if manifest == null:
		return false
	var data := {"profile": manifest.profile_name, "loops": manifest.loops}
	var idle := RecordedEngineController.compute_blend_state(800.0, 0.0, data)
	var coast := RecordedEngineController.compute_blend_state(3000.0, 0.0, data)
	var middle := RecordedEngineController.compute_blend_state(2600.0, 0.0, data)
	if not (is_equal_approx(float(idle["on_layer_gain"]), 0.4) and is_zero_approx(float(idle["off_layer_gain"]))):
		push_error("Kestrel idle must use the actual low RPM ON recording")
		return false
	if not (is_zero_approx(float(coast["on_layer_gain"])) and is_equal_approx(float(coast["off_layer_gain"]), 1.0)):
		push_error("Coast bank must take over at its first recorded RPM")
		return false
	if not (float(middle["on_layer_gain"]) > 0.0 and float(middle["off_layer_gain"]) > 0.0):
		push_error("Coast fallback must crossfade smoothly")
		return false
	return true


func test_pitch_matched_crossfade() -> bool:
	for prof in PROFILES:
		var manifest := EngineProfileManifest.load_for_profile(prof)
		if manifest == null:
			return false
		for layer in ["on", "off"]:
			if layer == "off" and not manifest.has_off_layer:
				continue
			var anchors: Array = manifest.get_anchors_for_layer(layer)
			for index in range(anchors.size() - 1):
				var a: Dictionary = anchors[index]
				var b: Dictionary = anchors[index + 1]
				for step in range(101):
					var rpm := lerpf(float(a["rpm"]), float(b["rpm"]), step / 100.0)
					var pair := RecordedEngineController.compute_anchor_pair(manifest.find_bracketing_anchors(layer, rpm), rpm)
					for anchor in [a, b]:
						var key := str(anchor["file"])
						if float(pair["gains"].get(key, 0.0)) > 0.001:
							if absf(float(pair["pitches"][key]) * float(anchor["rpm"]) - rpm) > 0.1:
								push_error("Active anchor is not pitch matched: %s %s %.1f" % [prof, key, rpm])
								return false
	return true


func test_controller_lifecycle_and_smoothing() -> bool:
	print("\n[TEST 5] Testing controller lifecycle, bus routing, and smoothing...")
	var controller := RecordedEngineController.new()
	controller.setup("vela_gt")
	root.add_child(controller)

	# Verify auxiliary players created
	assert(controller._shift_player != null, "Shift player created")
	assert(controller._overrun_player != null, "Overrun player created")
	assert(controller._exhaust_players.size() == 14, "Vela GT has 14 exhaust players")
	assert(controller._intake_players.size() == 7, "Vela GT has 7 intake players")

	# Check snap to idle
	controller.snap_to_idle()
	assert(controller._smoothed_rpm == 950.0, "Smoothed RPM initialized to idle")
	assert(controller._smoothed_throttle == 0.0, "Smoothed throttle initialized to 0")

	# Test smoothing over delta steps
	controller.update_telemetry({"rpm": 5000.0, "throttle": 1.0})
	for i in range(10):
		controller._process(0.016) # 16ms steps (~60 FPS)

	# After ~160ms:
	# RPM (45ms smoothing) should have reached > 90% of target
	assert(controller._smoothed_rpm > 4500.0, "RPM smoothed towards target: %f" % controller._smoothed_rpm)
	# Throttle (80ms smoothing) should have reached > 75% of target
	assert(controller._smoothed_throttle > 0.75, "Throttle smoothed towards target: %f" % controller._smoothed_throttle)

	controller.free()
	print("  -> Controller lifecycle, smoothing, and player setup PASS")
	return true


func test_rev_limiter_stutter() -> bool:
	print("\n[TEST 6] Testing rev limiter stutter and envelope...")
	var controller := RecordedEngineController.new()
	controller.setup("vela_gt")
	root.add_child(controller)
	controller.snap_to_idle()

	# Set RPM to redline (8500)
	controller.update_telemetry({"rpm": 8500.0, "throttle": 1.0})
	# Advance time past smoothing
	for i in range(20):
		controller._process(0.016)

	assert(controller._is_on_limiter == true, "Limiter must engage at redline")

	# Step through limiter cycle to verify stutter oscillation
	var saw_cut := false
	var saw_fire := false
	for i in range(30):
		controller._process(0.005) # fine 5ms steps
		if controller._limiter_envelope < 0.30:
			saw_cut = true
		if controller._limiter_envelope > 0.70:
			saw_fire = true

	assert(saw_cut, "Limiter must oscillate into cut phase")
	assert(saw_fire, "Limiter must oscillate into fire phase")

	# Exit limiter
	controller.update_telemetry({"rpm": 5000.0, "throttle": 0.5})
	for i in range(20):
		controller._process(0.016)
	assert(controller._is_on_limiter == false, "Limiter must disengage below redline")
	assert(controller._limiter_envelope > 0.95, "Limiter envelope must recover to 1.0")

	controller.free()
	print("  -> Rev limiter stutter bounce envelope PASS")
	return true


func test_gear_shift_envelope() -> bool:
	print("\n[TEST 7] Testing gear shift torque cut envelope (80-140ms)...")
	var controller := RecordedEngineController.new()
	controller.setup("kestrel_xr")
	root.add_child(controller)
	controller.snap_to_idle()

	controller.update_telemetry({"rpm": 4000.0, "throttle": 0.8, "gear": 1})
	controller._process(0.016)

	# Shift gear 1 -> 2
	controller.update_telemetry({"rpm": 3200.0, "throttle": 0.8, "gear": 2})
	assert(controller._shift_timer > 0.0, "Shift timer started on gear change")

	# Step 20ms into shift: torque cut should be deep (~0.20)
	controller._process(0.020)
	assert(controller._shift_envelope < 0.35, "Torque cut envelope active: %f" % controller._shift_envelope)

	# Step past torque cut duration (~110ms total)
	controller._process(0.120)
	assert(controller._shift_timer == 0.0, "Shift timer expired")
	assert(is_equal_approx(controller._shift_envelope, 1.0), "Torque cut envelope fully recovered to 1.0")

	controller.free()
	print("  -> Gear shift clunk and torque cut envelope PASS")
	return true


func test_overrun_backfire() -> bool:
	print("\n[TEST 8] Testing overrun backfire on rapid lift-off above 65% RPM...")
	var controller := RecordedEngineController.new()
	controller.setup("vela_gt")
	root.add_child(controller)
	controller.snap_to_idle()

	# High RPM (> 65% of 8500 = 5525), high throttle (0.9)
	controller.update_telemetry({"rpm": 6500.0, "throttle": 0.9})
	controller._process(0.016)

	# Rapid lift-off: drop throttle to 0.0
	controller.update_telemetry({"rpm": 6400.0, "throttle": 0.0})
	assert(controller._overrun_cooldown_timer > 0.0, "Overrun cooldown timer set after backfire trigger")
	assert(controller._active_overrun_burst.size() > 0, "Backfire crackle burst scheduled")

	var cooldown_snapshot := controller._overrun_cooldown_timer

	# Attempt immediate re-trigger while on cooldown
	controller.update_telemetry({"rpm": 6400.0, "throttle": 0.9})
	controller._process(0.016)
	controller.update_telemetry({"rpm": 6300.0, "throttle": 0.0})
	# Cooldown timer should not have reset to full
	assert(controller._overrun_cooldown_timer <= cooldown_snapshot, "Cooldown prevents spam re-trigger")

	# Step through cooldown
	controller._process(1.3)
	assert(controller._overrun_cooldown_timer == 0.0, "Cooldown expired after 1.2s")

	controller.free()
	print("  -> Overrun backfire with cooldown enforcement PASS")
	return true


func test_profile_switching() -> bool:
	print("\n[TEST 9] Testing dynamic profile switching (Vela -> Kestrel -> Orion)...")
	var controller := RecordedEngineController.new()
	controller.setup("vela_gt")
	root.add_child(controller)

	# 1. Vela GT
	assert(controller.car_profile == "vela_gt")
	assert(controller._exhaust_players.size() == 14)
	assert(controller._intake_players.size() == 7)

	# 2. Switch to Kestrel XR
	controller.set_profile("kestrel_xr")
	assert(controller.car_profile == "kestrel_xr")
	assert(controller._exhaust_players.size() == 12) # 7 on + 5 off
	assert(controller._intake_players.size() == 7)

	# 3. Switch to Orion RS
	controller.set_profile("orion_rs")
	assert(controller.car_profile == "orion_rs")
	assert(controller._exhaust_players.size() == 6) # 6 on, 0 off
	assert(controller._intake_players.size() == 6)

	controller.free()
	print("  -> Dynamic profile switching PASS")
	return true
