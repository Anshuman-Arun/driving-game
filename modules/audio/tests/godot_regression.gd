extends SceneTree
## Run after the editor import:
## godot --headless --path modules/audio --script res://tests/godot_regression.gd
## Uses mock GEVP-shaped objects, without requiring Core PR #6.

class TestWheel:
	extends RefCounted
	var surface_type := "Road"
	var slip_vector := Vector2.ZERO
	var spring_current_length := 0.30
	var touching := true

	func is_colliding() -> bool:
		return touching


class TestVehicle:
	extends RigidBody3D
	var wheel_array: Array = []
	var motor_rpm := 950.0
	var idle_rpm := 950.0
	var max_rpm := 7100.0
	var throttle_input := 0.0
	var brake_input := 0.0
	var handbrake_input := 0.0
	var current_gear := 1


var failures := 0


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("Aster audio regression: " + message)


func _initialize() -> void:
	var script_resource = load("res://modules/audio/audio_controller.gd") if ResourceLoader.exists("res://modules/audio/audio_controller.gd") else load("res://audio_controller.gd")
	var audio = script_resource.new()
	audio.use_recorded_runtime = false
	root.add_child.call_deferred(audio)
	call_deferred("_test", audio)


func _test(audio) -> void:
	var script_resource = load("res://modules/audio/telemetry_bridge.gd") if ResourceLoader.exists("res://modules/audio/telemetry_bridge.gd") else load("res://telemetry_bridge.gd")
	_expect(audio._players.size() == 11, "eleven loop players created")
	_expect(audio._alternate_engines.size() == 3, "three crossfade voices created")
	_expect(audio._event_players.size() == 3, "three bounded event voices created")
	_expect(audio._event_streams.size() == 3, "one-shot WAVs cached")
	for key in audio._players:
		_expect(is_instance_valid(audio._players[key]), "valid loop player " + key)
		_expect(audio._players[key].stream != null, "loaded loop stream " + key)
	_expect(audio._current_profile == "vela_gt", "default car profile")
	_expect(audio._event_index == 0, "no event at startup")
	for name in ["engine_low", "engine_mid", "engine_high", "roll_asphalt", "wind"]:
		var wav: AudioStreamWAV = audio._players[name].stream
		var decoded_frames := int(round(wav.get_length() * float(wav.mix_rate)))
		_expect(abs(wav.loop_end - decoded_frames) <= 1, "loop endpoint uses decoded frames: " + name)

	var idle: Dictionary = audio.compute_targets({"rpm": 950.0, "speed_mps": 0.0})
	var full: Dictionary = audio.compute_targets({"rpm": 6800.0, "throttle": 1.0, "load": 1.0, "speed_mps": 40.0})
	_expect(float(idle["engine_low"]) > float(idle["engine_high"]), "idle uses low band")
	_expect(float(full["engine_high"]) > float(full["engine_low"]), "high RPM uses high band")
	_expect(float(full["wind"]) > float(idle["wind"]), "wind rises with speed")
	var roll_a: Dictionary = audio.compute_targets({"speed_mps": 20.0, "surface": "asphalt"})
	var roll_g: Dictionary = audio.compute_targets({"speed_mps": 20.0, "surface": "gravel"})
	var roll_gr: Dictionary = audio.compute_targets({"speed_mps": 20.0, "surface": "grass"})
	_expect(roll_a["roll_asphalt"] > 0.0 and roll_a["roll_gravel"] == 0.0, "asphalt rolling")
	_expect(roll_g["roll_gravel"] > 0.0 and roll_g["roll_asphalt"] == 0.0, "gravel rolling")
	_expect(roll_gr["roll_grass"] > 0.0 and roll_gr["roll_asphalt"] == 0.0, "grass rolling")
	var sliding: Dictionary = audio.compute_targets({"speed_mps": 25.0, "lateral_slip": 0.9, "grip": 0.2})
	var handbrake: Dictionary = audio.compute_targets({"speed_mps": 25.0, "handbrake": true})
	var airborne: Dictionary = audio.compute_targets({"speed_mps": 25.0, "lateral_slip": 0.9, "on_ground": false})
	_expect(sliding["tire_squeal"] > 0.2, "lateral slip generates squeal")
	_expect(handbrake["tire_squeal"] > 0.0, "handbrake squeal")
	_expect(airborne["roll_asphalt"] == 0.0 and airborne["tire_squeal"] == 0.0, "airborne tires are silent")
	var overrun: Dictionary = audio.compute_targets({"rpm": 5500.0, "throttle": 0.0, "engine_braking": true})
	var powered: Dictionary = audio.compute_targets({"rpm": 5500.0, "throttle": 0.9, "engine_braking": false})
	_expect(overrun["overrun"] > powered["overrun"], "engine braking overrun louder than powered travel")

	var missing: Dictionary = script_resource.from_gevp(null)
	_expect(missing["speed_mps"] == 0.0 and not missing["on_ground"], "null vehicle safely produces stationary telemetry")
	var plain := Node3D.new()
	var incomplete: Dictionary = script_resource.from_gevp(plain)
	_expect(incomplete["speed_mps"] == 0.0 and not incomplete["on_ground"], "missing GEVP fields safe")
	plain.free()

	var car := TestVehicle.new()
	var wheel := TestWheel.new()
	car.wheel_array = [wheel]
	root.add_child(car)
	car.linear_velocity = Vector3(0, 0, -20)
	car.throttle_input = 0.7
	var driving: Dictionary = script_resource.from_gevp(car)
	_expect(driving["speed_mps"] > 19.0 and driving["forward_speed_mps"] > 19.0, "positive forward speed")
	_expect(driving["throttle"] > 0.69 and driving["on_ground"], "forward pedal and contact")
	wheel.surface_type = "Dirt"
	wheel.slip_vector = Vector2(0.0, 0.65)
	var dirt: Dictionary = script_resource.from_gevp(car)
	_expect(dirt["surface"] == "gravel", "GEVP Dirt maps to gravel")
	_expect(dirt["lateral_slip"] > 0.8 and dirt["grip"] < 0.5, "GEVP longitudinal wheel slip reaches audio")
	wheel.surface_type = "Grass"
	_expect(script_resource.from_gevp(car)["surface"] == "grass", "GEVP Grass maps to grass")
	wheel.touching = false
	_expect(not script_resource.from_gevp(car)["on_ground"], "lost wheel contact")
	wheel.touching = true

	car.current_gear = -1
	car.linear_velocity = Vector3(0, 0, 12)
	car.throttle_input = 0.0
	car.brake_input = 0.8
	var reversing: Dictionary = script_resource.from_gevp(car)
	_expect(reversing["forward_speed_mps"] < -11.9, "reverse direction signed")
	_expect(reversing["throttle"] > 0.79, "reverse pedal swap honors Core VehicleAdapter")
	car.current_gear = 3
	audio.bind_gevp_vehicle(car)
	audio._physics_process(0.016)
	_expect(audio._shift_timer == 0.0, "binding a vehicle does not create a false shift")
	_expect(audio._telemetry["gear"] == 3, "bound GEVP gear is sampled")
	wheel.spring_current_length = 0.12
	audio._physics_process(0.016)
	_expect(audio._suspension_cooldown > 0.0, "suspension compression fires transient")
	var event_after_bump: int = audio._event_index
	audio.trigger_suspension(1.0)
	_expect(audio._event_index == event_after_bump, "suspension event cooldown blocks bursts")
	audio._process(0.25)
	audio.trigger_suspension(1.0)
	_expect(audio._event_index != event_after_bump, "suspension retriggers after cooldown")

	audio.unbind_gevp_vehicle()
	_expect(not audio._tracking_vehicle, "explicit unbind clears reference")
	_expect(audio._telemetry["speed_mps"] == 0.0, "unbind clears stale speed")
	audio.update_telemetry({"rpm": 4600.0, "throttle": 0.9, "gear": 2, "speed_mps": 20.0})
	audio.update_telemetry({"rpm": 3200.0, "throttle": 0.1, "gear": 3, "speed_mps": 23.0})
	_expect(audio._shift_timer > 0.0 and audio._overrun_timer > 0.0, "gearshift + throttle-lift transients")
	var shift_event_index: int = audio._event_index
	audio.update_telemetry({"gear": 4, "rpm": 2900.0})
	_expect(audio._event_index == shift_event_index, "no repeated gearshift one-shot within cooldown")

	for profile in ["orion_rs", "kestrel_xr", "vela_gt"]:
		audio.set_profile(profile)
		_expect(audio.car_profile == profile and audio._profile_fading, "profile crossfade starts: " + profile)
		audio._process(0.1)
		_expect(audio._profile_fade > 0.0 and audio._profile_fade < 1.0, "profile crossfade is gradual")
		audio._process(0.3)
		_expect(not audio._profile_fading, "profile crossfade terminates")
		for band in ["low", "mid", "high"]:
			_expect(audio._players["engine_" + band].playing, "new profile loop playing")
			_expect(not audio._alternate_engines[band].playing, "old profile loop stopped")

	# Rapid selector changes must finish the first fade rather than cut off
	# the old loops in the middle of a waveform.
	audio.set_profile("orion_rs")
	audio.set_profile("kestrel_xr")
	_expect(audio._queued_profile == "kestrel_xr", "rapid profile switch queued")
	_expect(audio._current_profile == "orion_rs", "current crossfade preserved")
	audio._process(0.30)
	_expect(audio._current_profile == "kestrel_xr" and audio._profile_fading, "queued profile transition begins")
	audio._process(0.30)
	_expect(not audio._profile_fading and audio._queued_profile == "", "queued profile transition ends")

	# Collision bursts must be limited and use cached one-shots.
	audio._process(0.20)
	var collision_stream = audio._event_streams["collision"]
	var before_collision: int = audio._event_index
	audio.trigger_collision(1.0)
	_expect(audio._event_index != before_collision, "first collision event played")
	var after_collision: int = audio._event_index
	audio.trigger_collision(1.0)
	_expect(audio._event_index == after_collision, "immediate duplicate collision suppressed")
	_expect(audio._event_streams["collision"] == collision_stream, "collision stream reused")

	# Bound the worst-case simultaneous steady loop gain.
	audio.update_telemetry({"rpm": 6800.0, "speed_mps": 50.0, "throttle": 1.0,
		"load": 1.0, "lateral_slip": 1.0, "grip": 0.0, "surface": "asphalt", "on_ground": true})
	for i in range(8):
		audio._process(0.2)
	var weighted_peak := 0.0
	for band in ["low", "mid", "high"]:
		weighted_peak += db_to_linear(audio._players["engine_" + band].volume_db) * 0.80
	for name in audio.LOOP_NAMES:
		weighted_peak += db_to_linear(audio._players[name].volume_db) * 0.60
	_expect(weighted_peak <= 0.52, "loop sum constrained under conservative peak budget")

	audio.bind_gevp_vehicle(car)
	audio._physics_process(0.016)
	car.free()
	audio._physics_process(0.016)
	_expect(not audio._tracking_vehicle and audio._telemetry["speed_mps"] == 0.0, "destroyed bound car recovers without stale playback")
	audio.queue_free()

	if failures > 0:
		print("Aster audio Godot regression FAILED: ", failures, " checks")
		quit(1)
	else:
		print("Aster audio Godot regression PASS")
		quit(0)
