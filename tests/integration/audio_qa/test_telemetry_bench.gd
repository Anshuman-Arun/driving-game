extends SceneTree
## Unit test verifying DeterministicTelemetryTestBench across all 3 profiles:
## - vela_gt, kestrel_xr, orion_rs
## - RPM idle to redline coverage
## - Throttle transitions, gear shifts, reverse, surfaces, jumps, wall proximity

func _initialize() -> void:
	print("--- Running DeterministicTelemetryTestBench Verification ---")
	var bench_script = load("res://modules/audio/recorded_runtime/qa/telemetry_test_bench.gd")
	var profiles := ["vela_gt", "kestrel_xr", "orion_rs"]
	var total_checks := 0
	var passed_checks := 0

	for p in profiles:
		var bench = bench_script.new(p, 60.0)
		assert(bench != null)
		print("Testing profile: %s" % p)

		var idle_checked := false
		var redline_checked := false
		var throttle_transition_checked := false
		var gear_shift_checked := false
		var reverse_checked := false
		var surface_checked := false
		var jump_checked := false
		var wall_checked := false
		var wind_checked := false
		var slip_checked := false
		var camera_checked := false

		var min_rpm := 999999.0
		var max_rpm := -1.0
		var max_speed := 0.0
		var surfaces_seen := {}
		var gears_seen := {}

		var step_count := 0
		while not bench.is_finished():
			var t: Dictionary = bench.step()
			step_count += 1
			var rpm: float = float(t["rpm"])
			var speed: float = float(t["speed_mps"])
			var gear: int = int(t["gear"])
			var surface: String = str(t["surface"])
			var scenario: String = str(t["scenario"])

			min_rpm = minf(min_rpm, rpm)
			max_rpm = maxf(max_rpm, rpm)
			max_speed = maxf(max_speed, speed)
			surfaces_seen[surface] = true
			gears_seen[gear] = true

			match scenario:
				"idle_stationary":
					if not idle_checked and speed == 0.0 and rpm <= float(bench.profile_data["idle_rpm"]) + 5.0:
						idle_checked = true
				"rpm_sweep_idle_to_redline":
					if not redline_checked and rpm >= float(bench.profile_data["max_rpm"]) * 0.95:
						redline_checked = true
				"throttle_transitions":
					if not throttle_transition_checked and float(t["throttle"]) == 0.0 and rpm > 4000.0:
						throttle_transition_checked = true
				"gear_shifts":
					if not gear_shift_checked and gear >= 3:
						gear_shift_checked = true
				"reverse_maneuver":
					if not reverse_checked and gear == -1 and float(t["forward_speed_mps"]) < 0.0:
						reverse_checked = true
				"surface_transitions":
					if not surface_checked and surfaces_seen.size() >= 3:
						surface_checked = true
				"jumps_and_landings":
					if not jump_checked and not bool(t["on_ground"]):
						jump_checked = true
				"wall_proximity":
					if not wall_checked and float(t["wall_distance"]) < 5.0:
						wall_checked = true
				"high_speed_wind":
					if not wind_checked and speed > 40.0:
						wind_checked = true
				"lateral_slip_and_braking":
					if not slip_checked and float(t["lateral_slip"]) >= 0.60:
						slip_checked = true
				"camera_perspective_switching":
					if not camera_checked and str(t["camera_mode"]) == "cockpit":
						camera_checked = true

		print("  Steps executed: %d, RPM range: [%.0f, %.0f], Max speed: %.1f m/s" % [step_count, min_rpm, max_rpm, max_speed])
		print("  Surfaces: %s, Gears: %s" % [surfaces_seen.keys(), gears_seen.keys()])

		var checks := [
			["idle_checked", idle_checked],
			["redline_checked", redline_checked],
			["throttle_transition_checked", throttle_transition_checked],
			["gear_shift_checked", gear_shift_checked],
			["reverse_checked", reverse_checked],
			["surface_checked", surface_checked],
			["jump_checked", jump_checked],
			["wall_checked", wall_checked],
			["wind_checked", wind_checked],
			["slip_checked", slip_checked],
			["camera_checked", camera_checked]
		]

		for c in checks:
			total_checks += 1
			if c[1]:
				passed_checks += 1
			else:
				push_error("Profile %s failed check: %s" % [p, c[0]])

	print("DeterministicTelemetryTestBench results: %d / %d checks passed." % [passed_checks, total_checks])
	quit(0 if passed_checks == total_checks else 1)
