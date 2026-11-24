extends SceneTree
## Run with the editor binary, --main-pack and this script's absolute path.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for path in ["res://data/world/road_graph_v1.json", "res://content/scenery/manifest.json", "res://docs/ASSET_LICENSES.md"]:
		if not FileAccess.file_exists(path):
			print("PACK_MISSING ", path)
			quit(1)
			return
	if FileAccess.file_exists("res://assets/premium_world/payload/LICENSES_AND_HASHES.json") or FileAccess.file_exists("res://assets/audio/recorded/payload/LICENSES_AND_HASHES.json"):
		print("PACK_INCLUDES_SOURCE_PAYLOAD")
		quit(1)
		return
	var packed := load("res://scenes/bootstrap/game.tscn") as PackedScene
	var game := packed.instantiate()
	var shell = game.get_node("GameShell")
	shell.save_path = "user://offline-package-qa-%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	shell.open_garage()
	shell._inspect("solace_gt")
	shell._choose_car()
	shell.enter_free_roam()
	for i in 300:
		await physics_frame
		if shell.drive.vehicle_body != null:
			break
	var drive = shell.drive
	if drive.vehicle_body == null or drive.active_vehicle_id != "solace_gt" or drive.scenery == null:
		print("PACK_BOOT_FAILED")
		quit(1)
		return
	Input.action_press("drive_throttle", 0.72)
	for i in 170:
		await physics_frame
	Input.action_release("drive_throttle")
	var ok: bool = drive.vehicle_body.has_node("CuratedCar") and drive.adapter.get_speed_mps() > 3.0
	print("PACK_FREE_ROAM ok=", ok, " speed=", drive.adapter.get_speed_mps())
	quit(0 if ok else 1)
