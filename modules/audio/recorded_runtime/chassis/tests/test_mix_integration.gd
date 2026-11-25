extends SceneTree

const AsterAudioBusBuilder = preload("res://modules/audio/recorded_runtime/mix/bus_layout_builder.gd")
const ChassisAudioController = preload("res://modules/audio/recorded_runtime/chassis/chassis_audio_controller.gd")

func _initialize() -> void:
	print("Testing ChassisAudioController on top of AsterAudioBusBuilder...")
	AsterAudioBusBuilder.apply_to_audio_server(true)

	var controller := ChassisAudioController.new()
	root.add_child(controller)

	# Verify buses are resolved
	var wind_idx := AudioServer.get_bus_index("Wind_Chassis")
	var amb_idx := AudioServer.get_bus_index("Ambience")
	var refl_idx := AudioServer.get_bus_index("Exhaust_Reflection")
	print("Buses found: Wind_Chassis=", wind_idx, " Ambience=", amb_idx, " Exhaust_Reflection=", refl_idx)
	assert(wind_idx >= 0, "Wind_Chassis bus must exist")
	assert(amb_idx >= 0, "Ambience bus must exist")
	assert(refl_idx >= 0, "Exhaust_Reflection bus must exist")

	# Test near wall reflection
	var near_res: Dictionary = controller.simulate_acoustics(2.0, 15.0, 8.0)
	print("Near wall acoustics: ", near_res)
	assert(float(near_res["delay_ms"]) >= 15.0 and float(near_res["delay_ms"]) <= 30.0)
	assert(not bool(near_res["is_open_terrain"]))

	# Test open terrain
	var open_res: Dictionary = controller.simulate_acoustics(25.0, 30.0, 50.0)
	print("Open terrain acoustics: ", open_res)
	assert(bool(open_res["is_open_terrain"]))
	assert(float(open_res["wet_gain"]) == 0.0)

	# Test wind speed sweep
	controller.update_telemetry({"speed_mps": 55.0, "on_ground": true})
	controller._physics_process(0.016)
	controller._process(0.016)

	print("Chassis + Mix integration verified successfully!")
	controller.free()
	quit(0)
