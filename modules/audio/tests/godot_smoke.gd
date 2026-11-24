extends SceneTree
## Run: godot --headless --path modules/audio --script res://tests/godot_smoke.gd

const AudioTestCleanup := preload("res://tests/integration/audio_qa/audio_test_cleanup.gd")

func _initialize() -> void:
	var controller_script = load("res://modules/audio/audio_controller.gd") if ResourceLoader.exists("res://modules/audio/audio_controller.gd") else load("res://audio_controller.gd")
	var idling: Dictionary = controller_script.compute_targets({"rpm": 950.0, "speed_mps": 0.0})
	var accelerating: Dictionary = controller_script.compute_targets({"rpm": 6800.0, "throttle": 1.0, "load": 1.0, "speed_mps": 40.0})
	var slipping: Dictionary = controller_script.compute_targets({"rpm": 4000.0, "speed_mps": 25.0, "lateral_slip": 0.95, "grip": 0.2, "surface": "asphalt"})
	var gravel: Dictionary = controller_script.compute_targets({"rpm": 3000.0, "speed_mps": 25.0, "surface": "gravel"})
	var air: Dictionary = controller_script.compute_targets({"speed_mps": 25.0, "on_ground": false})
	assert(float(idling["engine_low"]) > float(idling["engine_high"]))
	assert(float(accelerating["engine_high"]) > float(accelerating["engine_low"]))
	assert(float(accelerating["wind"]) > float(idling["wind"]))
	assert(float(slipping["tire_squeal"]) > 0.2)
	assert(float(gravel["roll_gravel"]) > 0.0 and float(gravel["roll_asphalt"]) == 0.0)
	assert(float(air["roll_asphalt"]) == 0.0)
	var audio = controller_script.new()
	audio.use_recorded_runtime = false
	root.add_child.call_deferred(audio)
	call_deferred("_check_audio", audio)

func _check_audio(audio) -> void:
	assert(audio._players.size() == 11)
	audio.set_profile("orion_rs")
	assert(audio.car_profile == "orion_rs")
	audio.update_telemetry({"rpm": 4600.0, "throttle": 0.9, "gear": 2, "speed_mps": 20.0})
	audio.update_telemetry({"rpm": 3200.0, "throttle": 0.1, "gear": 3, "speed_mps": 23.0})
	assert(audio._shift_timer > 0.0)
	await AudioTestCleanup.dispose(self, audio)
	print("Aster audio Godot telemetry/mixer smoke PASS")
	quit(0)
