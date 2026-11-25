extends SceneTree
## Optional full-world smoke against real production nodes and Senna paint.
## Requires imported, materialized LFS assets. No graphical acceptance claim.
const Profile = preload("res://modules/environment_rendering/render_profile.gd")
const Scene = preload("res://scenes/free_roam/aster_valley.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", message)

func _run() -> void:
	var drive = Scene.instantiate()
	drive.active_vehicle_id = "mclaren_senna"
	root.add_child(drive)
	for i in range(500):
		await physics_frame
		if is_instance_valid(drive.vehicle_body) and is_instance_valid(drive.camera):
			break
	if not is_instance_valid(drive.vehicle_body) or not is_instance_valid(drive.camera):
		check(false, "real drive did not initialize")
		quit(1)
		return
	var env := drive.get_node("WorldEnvironment") as WorldEnvironment
	var sun := drive.get_node("Sun") as DirectionalLight3D
	var original := env.environment
	var energy := sun.light_energy
	var vehicle: Node = drive.vehicle_body
	check(vehicle.get_meta("vehicle_id") == "mclaren_senna", "actual Senna selected")
	var paint_targets: Array[Dictionary] = []
	var paint_originals: Array[Material] = []
	for node in vehicle.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.material_override != null:
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material != null and material.shader != null and material.shader.resource_path == Profile.PAINT_SHADER:
				paint_targets.append({"mesh": mesh, "surface": surface})
				paint_originals.append(mesh.get_surface_override_material(surface))
	check(not paint_targets.is_empty(), "real imported Senna paint surfaces found")
	var profile := Profile.new()
	var camera: Camera3D = drive.camera
	var viewport_scale := root.scaling_3d_scale
	var camera_far := camera.far
	check(profile.apply_candidate(drive, "medium", {"paint_surfaces": paint_targets}), "real root apply")
	check(env.environment != original and env.environment.sky == original.sky, "real environment isolated")
	check(is_equal_approx(sun.light_energy, 1.75), "candidate light applied")
	check(root.scaling_3d_scale == viewport_scale and camera.far == camera_far, "camera and viewport unchanged")
	for i in range(paint_targets.size()):
		var item := paint_targets[i]
		var mesh: MeshInstance3D = item["mesh"]
		check(mesh.get_surface_override_material(item["surface"]) != paint_originals[i], "paint copied")
	await process_frame
	profile.restore()
	check(env.environment == original and is_equal_approx(sun.light_energy, energy), "real environment restored")
	for i in range(paint_targets.size()):
		var item := paint_targets[i]
		var mesh: MeshInstance3D = item["mesh"]
		check(mesh.get_surface_override_material(item["surface"]) == paint_originals[i], "real paint restored")
	print("Real root rendering profile smoke: ", failures, " failures, ", paint_targets.size(), " paint surfaces")
	drive.queue_free()
	await process_frame
	quit(1 if failures else 0)
