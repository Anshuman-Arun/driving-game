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
	var env := drive.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := drive.get_node_or_null("Sun") as DirectionalLight3D
	if env == null or env.environment == null or sun == null:
		check(false, "production environment nodes missing")
		drive.queue_free()
		quit(1)
		return
	var original := env.environment
	var energy := sun.light_energy
	var vehicle: Node = drive.vehicle_body
	check(vehicle.get_meta("vehicle_id") == "mclaren_senna", "actual Senna selected")
	var paint_targets: Array[Dictionary] = []
	var paint_originals: Array[Material] = []
	var uniform_originals: Array[Dictionary] = []
	var other_surfaces: Array[Dictionary] = []
	for node in vehicle.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.material_override != null:
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material != null and material.shader != null and material.shader.resource_path == Profile.PAINT_SHADER:
				paint_targets.append({"mesh": mesh, "surface": surface})
				paint_originals.append(mesh.get_surface_override_material(surface))
				var saved: Dictionary = {}
				for uniform in Profile.PAINT_UNIFORMS:
					var value: Variant = material.get_shader_parameter(uniform)
					if value != null:
						saved[uniform] = value
				uniform_originals.append(saved)
			else:
				other_surfaces.append({"mesh": mesh, "surface": surface, "material": mesh.get_active_material(surface)})
	check(not paint_targets.is_empty(), "real imported Senna paint surfaces found")
	check(not other_surfaces.is_empty(), "non-paint surfaces available for isolation check")
	var profile := Profile.new()
	var camera: Camera3D = drive.camera
	var viewport_scale := root.scaling_3d_scale
	var camera_far := camera.far
	var camera_fov := camera.fov
	var camera_transform := camera.transform
	if not profile.apply_candidate(drive, "medium", {"paint_surfaces": paint_targets}):
		check(false, "real root apply: " + str(profile.get_status()))
		drive.queue_free()
		quit(1)
		return
	check(env.environment != original and env.environment.sky == original.sky, "real environment isolated")
	check(is_equal_approx(sun.light_energy, 1.75), "candidate light applied")
	check(root.scaling_3d_scale == viewport_scale and camera.far == camera_far and camera.fov == camera_fov and camera.transform == camera_transform, "camera and viewport unchanged")
	check(not env.environment.ssr_enabled and not env.environment.ssao_enabled, "Medium default avoids screen-space effects")
	check(profile.get_status()["paint_surfaces_attached"] == paint_targets.size(), "all paint targets attached")
	for i in range(paint_targets.size()):
		var item := paint_targets[i]
		var mesh: MeshInstance3D = item["mesh"]
		var candidate := mesh.get_surface_override_material(item["surface"]) as ShaderMaterial
		check(candidate != null and candidate != paint_originals[i], "paint copied")
		if candidate != null:
			for uniform in ["roughness", "metallic", "clearcoat", "clearcoat_roughness"]:
				check(is_equal_approx(float(candidate.get_shader_parameter(uniform)), float(Profile.DEFAULTS["paint_" + uniform])), "real paint uniform applied: " + uniform)
			for uniform in uniform_originals[i]:
				if uniform not in ["roughness", "metallic", "clearcoat", "clearcoat_roughness"]:
					check(candidate.get_shader_parameter(uniform) == uniform_originals[i][uniform], "untuned real paint parameter preserved: " + uniform)
	for item in other_surfaces:
		var mesh: MeshInstance3D = item["mesh"]
		check(mesh.get_active_material(item["surface"]) == item["material"], "non-paint surface unchanged")
	await process_frame
	profile.restore()
	check(env.environment == original and is_equal_approx(sun.light_energy, energy), "real environment restored")
	for i in range(paint_targets.size()):
		var item := paint_targets[i]
		var mesh: MeshInstance3D = item["mesh"]
		check(mesh.get_surface_override_material(item["surface"]) == paint_originals[i], "real paint restored")
		var restored := mesh.get_active_material(item["surface"]) as ShaderMaterial
		check(restored != null, "original shader material present after restore")
		if restored != null:
			for uniform in uniform_originals[i]:
				check(restored.get_shader_parameter(uniform) == uniform_originals[i][uniform], "original paint uniform unchanged: " + uniform)
	for item in other_surfaces:
		var mesh: MeshInstance3D = item["mesh"]
		check(mesh.get_active_material(item["surface"]) == item["material"], "non-paint surface unchanged after restore")
	drive.queue_free()
	await process_frame
	print("LIVE_RENDER_PROFILE_RESULT failures=", failures, " paint_surfaces=", paint_targets.size())
	quit(1 if failures else 0)
