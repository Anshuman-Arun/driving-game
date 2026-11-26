extends SceneTree
## External smoke script: run with editor binary and --main-pack on the exported PCK.
const MASK := "res://content/scenery/environment_overhaul/masks/"
const ASSETS := "res://assets/environment_overhaul/"
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)
	else:
		print("PASS ", label)

func run() -> void:
	OS.set_environment("ASTER_ENV_PILOT", "off")
	for path: String in ["manifest.json", "biome_rgba8.bin", "understory.json", "statistics.json"]:
		check(FileAccess.file_exists(MASK + path), "packed mask " + path)
	check(FileAccess.file_exists(ASSETS + "manifest.json"), "packed vegetation manifest")
	var scene := load("res://scenes/bootstrap/game.tscn") as PackedScene
	if scene == null:
		quit(1)
		return
	var game := scene.instantiate()
	var shell: Node = game.get_node("GameShell")
	shell.save_path = "user://offline-environment-qa-%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	shell.enter_free_roam()
	var drive: Node = null
	for i in 300:
		await physics_frame
		drive = shell.drive
		if drive != null and drive.vehicle_body != null:
			break
	if drive == null or drive.vehicle_body == null:
		print("FAIL packed free roam boot")
		quit(1)
		return
	for name: String in ["ASTER_ENV_GRASS", "ASTER_ENV_TERRAIN", "ASTER_ENV_UNDERSTORY", "ASTER_ENV_RENDERING"]:
		OS.set_environment(name, "1")
	OS.set_environment("ASTER_ENV_BEND", "0")
	for site: String in ["cedar", "valley"]:
		var point := Vector3(-870, 0, -154) if site == "cedar" else Vector3(72, 0, 170)
		var pose: Variant = drive.find_road_pose(point, Vector3.RIGHT)
		check(pose != null, "packed road pose " + site)
		if pose == null:
			continue
		drive._spawn_vehicle("mclaren_senna", pose)
		for i in 90:
			await physics_frame
		drive.camera.snap_to_vehicle()
		drive.vehicle_body.freeze = true
		check(drive.configure_environment_pilot(site), "packed pilot config " + site)
		var pilot: Node = drive.environment_pilot
		if pilot == null:
			continue
		for key: String in ["grass", "terrain", "understory"]:
			check(bool(pilot.status.get(key, false)), "packed " + key + " " + site)
		for i in 300:
			await process_frame
			if is_instance_valid(pilot.cover) and int(pilot.cover.get_stats().active_instances) > 0:
				break
		check(bool(pilot.status.rendering), "packed lighting " + site)
		check(is_instance_valid(pilot.cover) and int(pilot.cover.get_stats().active_instances) > 0, "packed nonempty grass " + site)
		drive.stop_environment_pilot()
		check(drive.environment_pilot == null, "packed pilot restored " + site)
		drive.vehicle_body.freeze = false
	game.queue_free()
	await process_frame
	print("PACK_ENVIRONMENT failures=", failures)
	quit(1 if failures else 0)
