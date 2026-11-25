extends SceneTree
const Controller := preload("res://modules/audio/audio_controller.gd")
const Builder := preload("res://modules/audio/recorded_runtime/mix/bus_layout_builder.gd")

func _initialize() -> void:
	Builder.apply_to_audio_server(true)
	var ok := true
	var groups := {"exhaust": ["Engine_Exhaust"], "nonengine": ["Tires", "Wind_Chassis", "Ambience", "Music", "UI"], "tires": ["Tires"], "reflection": ["Exhaust_Reflection"]}
	for mode in groups:
		ok = Controller.apply_audio_isolation(mode) and ok
		for bus in ["Engine_Exhaust", "Engine_Intake", "Exhaust_Reflection", "Tires", "Wind_Chassis", "Ambience", "Music", "UI"]:
			var idx := AudioServer.get_bus_index(bus)
			ok = ok and idx >= 0
			if idx >= 0:
				ok = ok and AudioServer.is_bus_mute(idx) == not groups[mode].has(bus)
	ok = ok and not Controller.apply_audio_isolation("invalid")
	for bus in ["Master", "SFX"]:
		var idx := AudioServer.get_bus_index(bus)
		ok = ok and idx >= 0 and not AudioServer.is_bus_mute(idx)
	print("Audio isolation modes: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
