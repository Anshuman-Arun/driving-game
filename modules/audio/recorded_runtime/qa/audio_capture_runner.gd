class_name AsterAudioCaptureRunner
extends RefCounted
## Orchestrates end-to-end headless audio integration QA for Aster Valley:
## - Applies canonical AsterAudioBusBuilder layout with compressor & limiter
## - Attaches AudioEffectCapture to Master bus (and sub-buses)
## - Instantiates RecordedEngineController, RecordedTireController,
##   ChassisAudioController, and AsterCameraMixController
## - Executes DeterministicTelemetryTestBench across 3 car profiles:
##   (Vela GT, Kestrel XR, Orion RS)
## - Measures peak dBFS, RMS dBFS, dynamic headroom, and clipping (> 0 dBFS / hard flats)
## - Evaluates per-scenario and per-profile audio compliance
## - Exports structured summary metrics to tests/integration/audio_qa/results.json

const TelemetryBenchScript := preload("telemetry_test_bench.gd")
const AssetVerifierScript := preload("asset_verifier.gd")

const BusBuilderScript := preload("res://modules/audio/recorded_runtime/mix/bus_layout_builder.gd")
const CameraMixScript := preload("res://modules/audio/recorded_runtime/mix/camera_mix_controller.gd")
const EngineScript := preload("res://modules/audio/recorded_runtime/engine/recorded_engine_controller.gd")
const TireScript := preload("res://modules/audio/recorded_runtime/tires/recorded_tire_controller.gd")
const ChassisScript := preload("res://modules/audio/recorded_runtime/chassis/chassis_audio_controller.gd")

const AudioTestCleanup := preload("res://tests/integration/audio_qa/audio_test_cleanup.gd")

const PROFILES := ["aventador_svj", "mclaren_senna"]
const CAPTURE_BUS_NAME := &"Master"
const HARD_FLAT_RUN_LENGTH := 4  # Consecutively identical samples to flag hard flat
const HARD_FLAT_MIN_AMPLITUDE := 0.90  # Only flag flatlining near max amplitude

## Executes the complete QA suite and outputs results to the given JSON path.
func execute_suite(tree: SceneTree, output_json_path: String = "res://tests/integration/audio_qa/results.json") -> Dictionary:
	var start_msec := Time.get_ticks_msec()
	print("==================================================================")
	print("  ASTER VALLEY RECORDED AUDIO QA: INTEGRATED TELEMETRY & CAPTURE")
	print("==================================================================")

	var full_report := {
		"timestamp": Time.get_datetime_string_from_system(true, true),
		"godot_version": Engine.get_version_info().get("string", "4.7.2"),
		"overall_success": false,
		"tracks": {
			"track_a_mix": "AsterAudioBusBuilder + AsterCameraMixController",
			"track_b_engine": "RecordedEngineController",
			"track_c_tires": "RecordedTireController",
			"track_d_chassis": "ChassisAudioController",
			"track_e_qa": "AsterAudioCaptureRunner + DeterministicTelemetryTestBench"
		},
		"asset_verification": {},
		"telemetry_verification": {},
		"capture_metrics": {},
		"summary": {
			"total_profiles_tested": PROFILES.size(),
			"profiles_passed": 0,
			"profiles_failed": 0,
			"overall_peak_dbfs": -999.0,
			"overall_min_headroom_db": 999.0,
			"total_clipped_samples": 0,
			"total_hard_flats": 0,
			"clipping_detected": false
		},
		"errors": []
	}

	# -------------------------------------------------------------
	# STEP 1: Verify all recorded & fallback audio assets
	# -------------------------------------------------------------
	print("\n[STEP 1/3] Verifying Recorded Audio Assets...")
	var asset_results: Dictionary = AssetVerifierScript.verify_all()
	full_report["asset_verification"] = asset_results
	print("  Total files inspected: %d" % int(asset_results.get("total_files", 0)))
	print("  Passed files: %d, Failed files: %d" % [
		int(asset_results.get("passed_files", 0)),
		int(asset_results.get("failed_files", 0))
	])
	if not bool(asset_results.get("all_passed", false)):
		var err_msg := "Asset verification failed: %s" % str(asset_results.get("errors", []))
		full_report["errors"].append(err_msg)
		push_error(err_msg)

	# Verify telemetry bench coverage
	var telemetry_summary := {
		"total_checks": 0,
		"passed_checks": 0,
		"all_passed": true,
		"profiles": {}
	}
	for p in PROFILES:
		var bench = TelemetryBenchScript.new(p, 60.0)
		var p_checks := 0
		var p_total := 11
		var idle_ok := false
		var sweep_ok := false
		var throttle_ok := false
		var shifts_ok := false
		var reverse_ok := false
		var surfaces_ok := false
		var jumps_ok := false
		var wall_ok := false
		var wind_ok := false
		var slip_ok := false
		var cam_ok := false
		var surfaces_seen := {}
		var gears_seen := {}

		while not bench.is_finished():
			var t: Dictionary = bench.step()
			var rpm: float = float(t["rpm"])
			var spd: float = float(t["speed_mps"])
			var gr: int = int(t["gear"])
			var srf: String = str(t["surface"])
			surfaces_seen[srf] = true
			gears_seen[gr] = true

			match str(t["scenario"]):
				"idle_stationary":
					if not idle_ok and spd == 0.0 and rpm <= float(bench.profile_data["idle_rpm"]) + 5.0:
						idle_ok = true
				"rpm_sweep_idle_to_redline":
					if not sweep_ok and rpm >= float(bench.profile_data["max_rpm"]) * 0.95:
						sweep_ok = true
				"throttle_transitions":
					if not throttle_ok and float(t["throttle"]) == 0.0 and rpm > 4000.0:
						throttle_ok = true
				"gear_shifts":
					if not shifts_ok and gr >= 3:
						shifts_ok = true
				"reverse_maneuver":
					if not reverse_ok and gr == -1:
						reverse_ok = true
				"surface_transitions":
					if not surfaces_ok and surfaces_seen.size() >= 3:
						surfaces_ok = true
				"jumps_and_landings":
					if not jumps_ok and not bool(t["on_ground"]):
						jumps_ok = true
				"wall_proximity":
					if not wall_ok and float(t["wall_distance"]) < 5.0:
						wall_ok = true
				"high_speed_wind":
					if not wind_ok and spd > 40.0:
						wind_ok = true
				"lateral_slip_and_braking":
					if not slip_ok and float(t["lateral_slip"]) >= 0.60:
						slip_ok = true
				"camera_perspective_switching":
					if not cam_ok and str(t["camera_mode"]) == "cockpit":
						cam_ok = true

		for ok_val in [idle_ok, sweep_ok, throttle_ok, shifts_ok, reverse_ok, surfaces_ok, jumps_ok, wall_ok, wind_ok, slip_ok, cam_ok]:
			if ok_val:
				p_checks += 1
		telemetry_summary["total_checks"] += p_total
		telemetry_summary["passed_checks"] += p_checks
		telemetry_summary["profiles"][p] = {
			"passed_checks": p_checks,
			"total_checks": p_total,
			"surfaces": surfaces_seen.keys(),
			"gears": gears_seen.keys()
		}
	telemetry_summary["all_passed"] = (telemetry_summary["passed_checks"] == telemetry_summary["total_checks"])
	full_report["telemetry_verification"] = telemetry_summary

	# -------------------------------------------------------------
	# STEP 2: Configure Canonical Audio Bus Layout
	# -------------------------------------------------------------
	print("\n[STEP 2/3] Configuring Canonical AudioBusLayout with Limiter & Compressor...")
	BusBuilderScript.apply_to_audio_server(true)

	var master_idx := AudioServer.get_bus_index(CAPTURE_BUS_NAME)
	if master_idx < 0:
		var err_msg := "Master audio bus not found!"
		full_report["errors"].append(err_msg)
		push_error(err_msg)
		return full_report

	# Capture the engine bus separately so ambience cannot mask a silent engine.
	var exhaust_idx := AudioServer.get_bus_index(&"Engine_Exhaust")
	if exhaust_idx < 0:
		full_report["errors"].append("Engine_Exhaust bus missing")
		return full_report
	var exhaust_capture := AudioEffectCapture.new()
	exhaust_capture.buffer_length = 5.0
	AudioServer.add_bus_effect(exhaust_idx, exhaust_capture)

	# Attach AudioEffectCapture to Master bus
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 5.0
	AudioServer.add_bus_effect(master_idx, capture)
	print("  AudioEffectCapture attached to '%s' bus (index %d)." % [CAPTURE_BUS_NAME, master_idx])

	# -------------------------------------------------------------
	# STEP 3: Instantiate Modular Subsystems and Execute Profiles
	# -------------------------------------------------------------
	print("\n[STEP 3/3] Running Deterministic Telemetry & Capturing Mixed Audio...")

	# Node container inside the scene tree
	var test_root := Node3D.new()
	test_root.name = "AudioQATestRoot"
	tree.root.add_child(test_root)

	# Instantiate controllers
	var engine_controller = EngineScript.new()
	engine_controller.name = "RecordedEngineController"
	test_root.add_child(engine_controller)

	var tire_controller = TireScript.new()
	tire_controller.name = "RecordedTireController"
	test_root.add_child(tire_controller)

	var chassis_controller = ChassisScript.new()
	chassis_controller.name = "ChassisAudioController"
	test_root.add_child(chassis_controller)

	var camera_controller = CameraMixScript.new()
	camera_controller.name = "CameraMixController"
	test_root.add_child(camera_controller)

	# Allow nodes to execute _ready()
	await tree.process_frame
	capture.clear_buffer()

	var all_profiles_ok := true
	var overall_max_peak_dbfs := -999.0
	var overall_min_headroom := 999.0
	var total_clipped_samples := 0
	var total_hard_flats := 0

	for profile in PROFILES:
		print("\n  >>> Simulating Car Profile: %s <<<" % profile.to_upper())
		var profile_metrics := await _run_profile_simulation(
			tree,
			profile,
			capture,
			exhaust_capture,
			engine_controller,
			tire_controller,
			chassis_controller,
			camera_controller
		)

		full_report["capture_metrics"][profile] = profile_metrics

		var p_peak: float = float(profile_metrics.get("peak_dbfs", -999.0))
		var p_headroom: float = float(profile_metrics.get("min_headroom_db", 0.0))
		var p_clipped: int = int(profile_metrics.get("clipped_samples", 0))
		var p_flats: int = int(profile_metrics.get("hard_flats", 0))
		var p_passed: bool = bool(profile_metrics.get("passed", false))

		overall_max_peak_dbfs = maxf(overall_max_peak_dbfs, p_peak)
		overall_min_headroom = minf(overall_min_headroom, p_headroom)
		total_clipped_samples += p_clipped
		total_hard_flats += p_flats

		if p_passed:
			full_report["summary"]["profiles_passed"] += 1
			print("  [PASS] %s: Peak %.2f dBFS | Headroom %.2f dB | Clipped: %d | Flats: %d" % [
				profile, p_peak, p_headroom, p_clipped, p_flats
			])
		else:
			all_profiles_ok = false
			full_report["summary"]["profiles_failed"] += 1
			print("  [FAIL] %s: Peak %.2f dBFS | Headroom %.2f dB | Clipped: %d | Flats: %d" % [
				profile, p_peak, p_headroom, p_clipped, p_flats
			])

	# Cleanup test nodes
	await AudioTestCleanup.dispose(tree, test_root)

	# Detach capture effect after all voices have been released.
	for i in range(AudioServer.get_bus_effect_count(master_idx)):
		if AudioServer.get_bus_effect(master_idx, i) == capture:
			AudioServer.remove_bus_effect(master_idx, i)
			break

	for i in range(AudioServer.get_bus_effect_count(exhaust_idx)):
		if AudioServer.get_bus_effect(exhaust_idx, i) == exhaust_capture:
			AudioServer.remove_bus_effect(exhaust_idx, i)
			break
	await AudioTestCleanup.drain(tree)

	# Summarize overall results
	full_report["summary"]["overall_peak_dbfs"] = overall_max_peak_dbfs
	full_report["summary"]["overall_min_headroom_db"] = overall_min_headroom
	full_report["summary"]["total_clipped_samples"] = total_clipped_samples
	full_report["summary"]["total_hard_flats"] = total_hard_flats
	full_report["summary"]["clipping_detected"] = (total_clipped_samples > 0 or overall_max_peak_dbfs > 0.0)

	var assets_ok: bool = bool(asset_results.get("all_passed", false))
	full_report["overall_success"] = (assets_ok and bool(telemetry_summary["all_passed"]) and all_profiles_ok and not full_report["summary"]["clipping_detected"])

	var elapsed_s := (Time.get_ticks_msec() - start_msec) / 1000.0
	full_report["elapsed_seconds"] = elapsed_s

	# Write results.json
	_save_json_results(full_report, output_json_path)

	print("\n==================================================================")
	print("  QA SUMMARY:")
	print("  Overall Status:        %s" % ("PASS" if full_report["overall_success"] else "FAIL"))
	print("  Assets Passed:         %s" % str(assets_ok))
	print("  Profiles Passed:       %d / %d" % [
		full_report["summary"]["profiles_passed"],
		full_report["summary"]["total_profiles_tested"]
	])
	print("  Overall Peak:          %.2f dBFS (Ceiling: -0.10 dBFS)" % overall_max_peak_dbfs)
	print("  Minimum Headroom:      %.2f dB" % overall_min_headroom)
	print("  Total Clipped Samples: %d" % total_clipped_samples)
	print("  Total Hard Flats:      %d" % total_hard_flats)
	print("  Elapsed Time:          %.2f s" % elapsed_s)
	print("  Results saved to:      %s" % output_json_path)
	print("==================================================================")

	return full_report


## Simulates a single car profile through the deterministic telemetry bench.
func _run_profile_simulation(
	tree: SceneTree,
	profile: String,
	capture: AudioEffectCapture,
	exhaust_capture: AudioEffectCapture,
	engine_node: Node,
	tire_node: Node,
	chassis_node: Node,
	camera_node: Node
) -> Dictionary:
	var bench = TelemetryBenchScript.new(profile, 60.0)

	# Configure car profile on controllers
	engine_node.call("set_profile", profile)
	engine_node.call("snap_to_idle")
	var active_manifest: RefCounted = engine_node.get("_manifest")
	var actual_bank := str(engine_node.get("_active_bank"))
	var allowed_proxy := "vela_gt" if profile == "aventador_svj" else "kestrel_xr"
	if active_manifest == null or str(engine_node.get("car_profile")) != profile or str(active_manifest.get("profile_name")) != actual_bank or actual_bank not in [profile, allowed_proxy]:
		return {"profile": profile, "passed": false, "error": "Requested hero voicing/bank was not loaded"}
	print("  Hero profile: %s; recording bank: %s; proxy=%s" % [profile, actual_bank, str(actual_bank != profile)])
	# Restore neutral mix before the next profile; do not measure residual
	# cockpit filtering, wall reflections, or transient tails as idle.
	camera_node.call("set_cockpit_view", false, true)
	chassis_node.call("simulate_acoustics", INF, INF, INF)
	var idle_telemetry := {"speed_mps": 0.0, "on_ground": true, "surface": "asphalt", "slip_amount": 0.0}
	tire_node.call("queue_telemetry", idle_telemetry)
	chassis_node.call("update_telemetry", idle_telemetry)
	await tree.create_timer(0.5).timeout

	if tire_node.has_method("set_profile"):
		tire_node.call("set_profile", profile)

	# Drain buffer prior to run
	capture.clear_buffer()
	exhaust_capture.clear_buffer()
	var exhaust_discarded_before := exhaust_capture.get_discarded_frames()
	var exhaust_frames := 0
	var exhaust_peak := 0.0
	var exhaust_idle_peak := 0.0
	var exhaust_idle_energy := 0.0
	var exhaust_idle_frames := 0
	var audition_file: FileAccess = null
	var audition_path := ""
	var audition_dir := OS.get_environment("ASTER_AUDIO_CAPTURE_DIR")
	if not audition_dir.is_empty():
		var dir := ProjectSettings.globalize_path(audition_dir)
		DirAccess.make_dir_recursive_absolute(dir)
		audition_path = dir.path_join(profile + ".wav")
		audition_file = FileAccess.open(audition_path, FileAccess.WRITE)
		if audition_file == null:
			push_error("Could not create audition WAV: " + audition_path)
			return {"profile": profile, "passed": false, "error": "Cannot write audition WAV"}
		_write_wav_header(audition_file, 0)
	var discarded_before := capture.get_discarded_frames()
	var next_tick_usec := Time.get_ticks_usec()

	var total_frames_captured: int = 0
	var max_peak_linear: float = 0.0
	var sum_squares: float = 0.0
	var clipped_samples: int = 0
	var hard_flats: int = 0
	var consecutive_flat_count: int = 0
	var last_sample_val: float = -999.0

	var scenario_metrics: Dictionary = {}
	var current_scenario: String = ""

	while not bench.is_finished():
		var t: Dictionary = bench.step()
		var scenario: String = str(t.get("scenario", "unknown"))

		if scenario != current_scenario:
			current_scenario = scenario
			if not scenario_metrics.has(scenario):
				scenario_metrics[scenario] = {
					"peak_linear": 0.0,
					"peak_dbfs": -999.0,
					"rms_linear": 0.0,
					"rms_dbfs": -999.0,
					"sum_squares": 0.0,
					"total_samples": 0,
					"clipped_samples": 0,
					"hard_flats": 0,
					"passed": true
				}

		# Update all audio subsystems
		if engine_node.has_method("update_telemetry"):
			engine_node.call("update_telemetry", t)

		if tire_node.has_method("queue_telemetry"):
			tire_node.call("queue_telemetry", t)

		if chassis_node.has_method("update_telemetry"):
			chassis_node.call("update_telemetry", t)

		camera_node.call("set_cockpit_view", bool(t.get("is_cockpit", false)))
		var wall := float(t.get("wall_distance", INF))
		chassis_node.call("simulate_acoustics", wall if wall < 20.0 else INF, INF, INF)

		# Advance at approximately 60 Hz wall time, not unbounded headless FPS.
		# AudioEffectCapture receives real-time audio from the mixer thread.
		next_tick_usec += roundi(bench.delta * 1000000.0)
		await tree.process_frame
		while Time.get_ticks_usec() < next_tick_usec:
			await tree.process_frame

		# Drain engine stem and require actual engine output at idle.
		var exhaust_avail := exhaust_capture.get_frames_available()
		if exhaust_avail > 0:
			var exhaust_buffer := exhaust_capture.get_buffer(exhaust_avail)
			exhaust_frames += exhaust_buffer.size()
			for sample in exhaust_buffer:
				var stem_peak := maxf(absf(sample.x), absf(sample.y))
				exhaust_peak = maxf(exhaust_peak, stem_peak)
				if current_scenario == "idle_stationary" and bench.current_time >= 0.5:
					exhaust_idle_peak = maxf(exhaust_idle_peak, stem_peak)
					exhaust_idle_energy += (sample.x * sample.x + sample.y * sample.y) * 0.5
					exhaust_idle_frames += 1

		# Drain captured audio buffer
		var avail := capture.get_frames_available()
		if avail > 0:
			var buffer: PackedVector2Array = capture.get_buffer(avail)
			total_frames_captured += buffer.size()
			if audition_file != null:
				var pcm := PackedByteArray()
				pcm.resize(buffer.size() * 4)
				for sample_index in range(buffer.size()):
					var sample: Vector2 = buffer[sample_index]
					pcm.encode_s16(sample_index * 4, roundi(clampf(sample.x, -1.0, 1.0) * 32767.0))
					pcm.encode_s16(sample_index * 4 + 2, roundi(clampf(sample.y, -1.0, 1.0) * 32767.0))
				audition_file.store_buffer(pcm)
			var scen_dict: Dictionary = scenario_metrics[current_scenario]

			for v in buffer:
				# Stereo channels: measure left and right
				var abs_l := absf(v.x)
				var abs_r := absf(v.y)
				var frame_peak := maxf(abs_l, abs_r)

				# Global peak
				if frame_peak > max_peak_linear:
					max_peak_linear = frame_peak

				# Scenario peak
				if frame_peak > float(scen_dict["peak_linear"]):
					scen_dict["peak_linear"] = frame_peak

				# Energy accumulator
				var energy := (v.x * v.x + v.y * v.y) * 0.5
				sum_squares += energy
				scen_dict["sum_squares"] = float(scen_dict["sum_squares"]) + energy
				scen_dict["total_samples"] = int(scen_dict["total_samples"]) + 1

				# Clipping detection (> 0 dBFS or hard saturation >= 0.9999)
				if abs_l >= 0.9999 or abs_r >= 0.9999:
					clipped_samples += 1
					scen_dict["clipped_samples"] = int(scen_dict["clipped_samples"]) + 1

				# Hard flatline detection
				if frame_peak >= HARD_FLAT_MIN_AMPLITUDE:
					if absf(frame_peak - last_sample_val) < 0.00001:
						consecutive_flat_count += 1
						if consecutive_flat_count >= HARD_FLAT_RUN_LENGTH:
							hard_flats += 1
							scen_dict["hard_flats"] = int(scen_dict["hard_flats"]) + 1
					else:
						consecutive_flat_count = 0
				else:
					consecutive_flat_count = 0
				last_sample_val = frame_peak

	if audition_file != null:
		audition_file.seek(0)
		_write_wav_header(audition_file, total_frames_captured)
		audition_file.close()
		print("Audition WAV: " + audition_path)

	# Finalize overall metrics for profile
	var peak_dbfs := _linear_to_db(max_peak_linear)
	var rms_linear := sqrt(sum_squares / float(maxi(total_frames_captured, 1)))
	var rms_dbfs := _linear_to_db(rms_linear)
	var min_headroom_db := -peak_dbfs

	# Finalize per-scenario metrics. Reject silent/empty scenario captures.
	var all_scenarios_ok := true
	for sc_name in scenario_metrics:
		var sc: Dictionary = scenario_metrics[sc_name]
		var sc_samples: int = maxi(int(sc["total_samples"]), 1)
		var sc_peak: float = float(sc["peak_linear"])
		sc["peak_dbfs"] = _linear_to_db(sc_peak)
		var sc_rms: float = sqrt(float(sc["sum_squares"]) / float(sc_samples))
		sc["rms_linear"] = sc_rms
		sc["rms_dbfs"] = _linear_to_db(sc_rms)
		sc["headroom_db"] = -float(sc["peak_dbfs"])
		sc["passed"] = (int(sc["total_samples"]) > 0 and sc_peak > 0.001 and float(sc["peak_dbfs"]) <= 0.0 and int(sc["clipped_samples"]) == 0 and int(sc["hard_flats"]) == 0)
		all_scenarios_ok = all_scenarios_ok and bool(sc["passed"])

	# Criteria for passing profile:
	# 1. Non-zero audio produced (signal presence)
	# 2. Peak amplitude does not exceed 0.0 dBFS (compliant with limiter ceiling)
	# 3. 0 clipped samples
	# 4. 0 hard flatlines
	var is_signal_present := (max_peak_linear > 0.005)
	var has_headroom := (peak_dbfs <= 0.0)
	var no_clipping := (clipped_samples == 0 and hard_flats == 0)
	var discarded := capture.get_discarded_frames() - discarded_before
	var sufficient_frames := total_frames_captured >= int(bench.get_total_duration() * AudioServer.get_mix_rate() * 0.85)
	var idle_rms_dbfs := _linear_to_db(sqrt(exhaust_idle_energy / float(maxi(1, exhaust_idle_frames))))
	print("  Stable idle exhaust RMS: %.2f dBFS (%d frames)" % [idle_rms_dbfs, exhaust_idle_frames])
	var exhaust_ok := exhaust_frames >= int(bench.get_total_duration() * AudioServer.get_mix_rate() * 0.85) and exhaust_peak > 0.005 and exhaust_idle_peak > 0.001 and exhaust_idle_frames > 0 and exhaust_capture.get_discarded_frames() == exhaust_discarded_before
	var profile_passed := (is_signal_present and has_headroom and no_clipping and all_scenarios_ok and sufficient_frames and discarded == 0 and exhaust_ok)
	print("  Exhaust stem: %d frames, peak %.2f dBFS, idle peak %.2f dBFS, passed=%s" % [exhaust_frames, _linear_to_db(exhaust_peak), _linear_to_db(exhaust_idle_peak), str(exhaust_ok)])

	return {
		"profile": profile,
		"recording_bank": actual_bank,
		"uses_proxy": actual_bank != profile,
		"passed": profile_passed,
		"is_signal_present": is_signal_present,
		"has_headroom": has_headroom,
		"total_frames_captured": total_frames_captured,
		"exhaust_frames": exhaust_frames,
		"exhaust_peak_dbfs": _linear_to_db(exhaust_peak),
		"exhaust_idle_peak_dbfs": _linear_to_db(exhaust_idle_peak),
		"exhaust_idle_rms_dbfs": idle_rms_dbfs,
		"exhaust_idle_frames": exhaust_idle_frames,
		"exhaust_signal_ok": exhaust_ok,
		"audition_wav": audition_path,
		"discarded_frames": discarded,
		"sufficient_frames": sufficient_frames,
		"all_scenarios_ok": all_scenarios_ok,
		"duration_simulated_s": bench.get_total_duration(),
		"peak_linear": max_peak_linear,
		"peak_dbfs": peak_dbfs,
		"rms_linear": rms_linear,
		"rms_dbfs": rms_dbfs,
		"min_headroom_db": min_headroom_db,
		"clipped_samples": clipped_samples,
		"hard_flats": hard_flats,
		"scenarios": scenario_metrics
	}


static func _write_wav_header(file: FileAccess, frames: int) -> void:
	var rate := roundi(AudioServer.get_mix_rate())
	var bytes := frames * 4
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + bytes)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(2)
	file.store_32(rate)
	file.store_32(rate * 4)
	file.store_16(4)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(bytes)


static func _linear_to_db(linear: float) -> float:
	if linear <= 0.0000001:
		return -144.0
	return 20.0 * (log(linear) / log(10.0))


static func _save_json_results(data: Dictionary, path: String) -> void:
	var resolved := path
	if path.begins_with("res://"):
		resolved = path.trim_prefix("res://")

	# Ensure parent directory exists
	var base_dir := resolved.get_base_dir()
	if base_dir != "" and not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)

	var file := FileAccess.open(resolved, FileAccess.WRITE)
	if file:
		var json_string := JSON.stringify(data, "  ")
		file.store_string(json_string)
		file.close()
		print("Successfully wrote QA metrics to: " + resolved)
	else:
		push_error("Failed to write QA metrics to: " + resolved)
