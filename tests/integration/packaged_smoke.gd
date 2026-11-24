extends SceneTree
## Run with the editor binary, --main-pack and this script's absolute path.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	const ENGINE_BANK := "res://assets/audio/recorded/payload/engines/kestrel_xr/"
	for path in ["res://data/world/road_graph_v1.json", "res://content/scenery/manifest.json", "res://docs/ASSET_LICENSES.md", ENGINE_BANK + "manifest.json"]:
		if not FileAccess.file_exists(path):
			print("PACK_MISSING ", path)
			quit(1)
			return
	if FileAccess.file_exists("res://assets/premium_world/payload/LICENSES_AND_HASHES.json") or FileAccess.file_exists("res://assets/audio/recorded/payload/LICENSES_AND_HASHES.json"):
		print("PACK_INCLUDES_SOURCE_PAYLOAD")
		quit(1)
		return
	var engine: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ENGINE_BANK + "manifest.json"))
	if not ResourceLoader.exists(ENGINE_BANK + str(engine["loops"][0]["file"]), "AudioStreamWAV"):
		print("PACK_MISSING_RECORDED_STREAM")
		quit(1)
		return
	var packed := load("res://scenes/bootstrap/game.tscn") as PackedScene
	var game := packed.instantiate()
	var shell = game.get_node("GameShell")
	shell.save_path = "user://offline-package-qa-%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	shell.open_garage()
	shell._inspect("aventador_svj")
	await process_frame
	var lamborghini: Node = shell.find_child("CuratedCar", true, false)
	if lamborghini == null or not lamborghini.scene_file_path.ends_with("/aventador_svj.glb"):
		print("PACK_MISSING_AVENTADOR")
		quit(1)
		return
	shell._inspect("mclaren_senna")
	shell._choose_car()
	shell.enter_free_roam()
	for i in 300:
		await physics_frame
		if shell.drive.vehicle_body != null:
			break
	var drive = shell.drive
	if drive.vehicle_body == null or drive.active_vehicle_id != "mclaren_senna" or drive.scenery == null:
		print("PACK_BOOT_FAILED")
		quit(1)
		return
	Input.action_press("drive_throttle", 0.72)
	for i in 170:
		await physics_frame
	Input.action_release("drive_throttle")
	var mixer: Node = drive.vehicle_body.get_node("VehicleAudio")
	var voices: Dictionary = mixer.recorded_engine._exhaust_players
	var audio_active := voices.values().any(func(player: AudioStreamPlayer) -> bool: return player.playing)
	var ok: bool = drive.vehicle_body.has_node("CuratedCar") and drive.adapter.get_speed_mps() > 3.0 and audio_active
	print("PACK_FREE_ROAM ok=", ok, " speed=", drive.adapter.get_speed_mps(), " recorded_audio_active=", audio_active)
	quit(0 if ok else 1)
