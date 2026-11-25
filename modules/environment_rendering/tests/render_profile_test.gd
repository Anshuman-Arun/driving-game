extends SceneTree
## Run from repository root with --headless --script; no world/LFS assets required.
const Profile = preload("res://modules/environment_rendering/render_profile.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL ", message)

func _run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var adapter := Profile.new()
	check(not adapter.apply_candidate(fixture, "medium"), "missing nodes rejected")
	check(not adapter.apply_candidate(null, "medium"), "null root rejected")
	adapter.restore()
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var original := Environment.new()
	original.sky = Sky.new()
	original.sky.sky_material = ProceduralSkyMaterial.new()
	original.background_mode = Environment.BG_SKY
	original.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	original.tonemap_exposure = 0.91
	original.ssao_enabled = false
	world_env.environment = original
	fixture.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.92
	sun.rotation = Vector3(-0.66, -1.96, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 270.0
	fixture.add_child(sun)
	var observer := WorldEnvironment.new()
	observer.environment = original
	# Deliberately outside the tree; don't install two environments in one World3D.
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	var paint := StandardMaterial3D.new()
	paint.roughness = 0.4
	paint.metallic = 0.2
	box.material = paint
	mesh.mesh = box
	fixture.add_child(mesh)
	var other_mesh := MeshInstance3D.new()
	other_mesh.mesh = box
	fixture.add_child(other_mesh)
	var original_rotation := sun.rotation
	var original_scale := root.scaling_3d_scale
	var original_msaa := root.msaa_3d
	var original_taa := root.use_taa
	var shadow_before: Dictionary = {}
	for property in Profile.SUN_PROPERTIES:
		shadow_before[property] = sun.get(property)
	var project_shadow_key := "rendering/lights_and_shadows/directional_shadow/size"
	var project_shadow_value: Variant = ProjectSettings.get_setting(project_shadow_key)
	var valid := Profile.validate_profile("Medium")
	check(valid["ok"], "case insensitive preset")
	check(not Profile.validate_profile("ultra")["ok"], "unknown preset")
	for options in [{"exposure": NAN}, {"sun_energy": INF}, {"shadow_distance": 0}, {"ssao": 1}, {"split_1": 0.24, "split_2": 0.20}, {"ssr_steps": 32.5}, {"unexpected": true}]:
		check(not Profile.validate_profile("medium", options)["ok"], "invalid option: " + str(options))
	for preset in ["low", "medium", "high"]:
		check(adapter.apply_candidate(fixture, preset), "apply " + preset)
		check(world_env.environment != original, "environment copied")
		check(world_env.environment.sky == original.sky, "sky preserved read-only")
		check(world_env.environment.reflected_light_source == original.reflected_light_source, "reflection source preserved")
		check(is_equal_approx(original.tonemap_exposure, 0.91), "original exposure unchanged")
		check(observer.environment == original, "shared reference unchanged")
		check(is_equal_approx(sun.directional_shadow_max_distance, Profile.PRESETS[preset]["shadow_distance"]), "shadow distance for " + preset)
		check(sun.rotation.is_equal_approx(original_rotation), "sun orientation preserved")
		check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "cascade count preserved")
		check(not world_env.environment.ssr_enabled and not world_env.environment.ssil_enabled and not world_env.environment.sdfgi_enabled and not world_env.environment.volumetric_fog_enabled, "expensive features disabled")
		var status := adapter.get_status()
		check(status["active"] and status["preset"] == preset, "status preset")
		var expected_ao: bool = preset == "high" and not status["headless"] and status["renderer"] == "forward_plus"
		check(world_env.environment.ssao_enabled == expected_ao, "AO capability gate")
		check(mesh.get_surface_override_material(0) == null, "no implicit paint edits")
	adapter.restore()
	check(world_env.environment == original, "restore original environment identity after repeated apply")
	for property in shadow_before:
		check(sun.get(property) == shadow_before[property], "restore sun " + property)
	var options := {"paint_surfaces": [{"mesh": mesh, "surface": 0}], "ssr": true, "ssao": true}
	check(adapter.apply_candidate(fixture, "medium", options), "explicit paint and effects")
	var first := mesh.get_surface_override_material(0) as StandardMaterial3D
	check(first != null and first != paint, "paint copied")
	if first != null:
		check(is_equal_approx(first.roughness, 0.24) and first.clearcoat_enabled, "paint tuning")
	check(is_equal_approx(paint.roughness, 0.4) and not paint.clearcoat_enabled, "asset unchanged")
	check(other_mesh.get_active_material(0) == paint, "shared mesh unaffected")
	var preview := world_env.environment
	check(not adapter.apply_candidate(fixture, "high", {"paint_surfaces": [{"mesh": mesh, "surface": 9}]}), "bad surface rejected")
	check(world_env.environment == preview and mesh.get_surface_override_material(0) == first, "invalid reapply atomic")
	check(not adapter.apply_candidate(fixture, "high", {"paint_surfaces": [options["paint_surfaces"][0], options["paint_surfaces"][0]]}), "duplicate target rejected")
	check(not adapter.apply_candidate(fixture, "high", {"world_environment": observer}), "outside root rejected")
	var status := adapter.get_status()
	if status["headless"] or status["renderer"] != "forward_plus":
		check(not preview.ssr_enabled and not preview.ssao_enabled, "unsupported effects skipped")
		check(status["unavailable"].size() >= 2, "unsupported features reported")
	else:
		check(preview.ssr_enabled and preview.ssao_enabled, "explicit effects enabled")
	check(adapter.apply_candidate(fixture, "high", options), "reapply same paint")
	check(mesh.get_surface_override_material(0) != first, "fresh copy on reapply")
	adapter.restore()
	adapter.restore()
	check(mesh.get_surface_override_material(0) == null, "restore absent override")
	check(world_env.environment == original, "restore env")
	var explicit := StandardMaterial3D.new()
	mesh.set_surface_override_material(0, explicit)
	check(adapter.apply_candidate(fixture, "low", options), "existing override preview")
	adapter.restore()
	check(mesh.get_surface_override_material(0) == explicit, "restore existing override identity")
	# Paint shader path uses the actual project shader, not an invented implementation.
	var shader_paint := ShaderMaterial.new()
	shader_paint.shader = preload("res://shaders/car_paint.gdshader")
	shader_paint.set_shader_parameter("roughness", 0.31)
	mesh.set_surface_override_material(0, shader_paint)
	check(adapter.apply_candidate(fixture, "medium", options), "existing shader paint preview")
	var shader_copy := mesh.get_surface_override_material(0) as ShaderMaterial
	check(shader_copy != null and shader_copy != shader_paint, "shader material copied")
	if shader_copy != null:
		check(is_equal_approx(shader_copy.get_shader_parameter("roughness"), 0.24), "shader parameter applied")
		check(shader_copy.shader == shader_paint.shader, "shader resource unchanged")
	check(is_equal_approx(shader_paint.get_shader_parameter("roughness"), 0.31), "shader original unchanged")
	adapter.restore()
	check(mesh.get_surface_override_material(0) == shader_paint, "shader override restored")
	sun.shadow_enabled = false
	check(adapter.apply_candidate(fixture, "high"), "shadowless preview")
	check(not sun.shadow_enabled, "no implicit shadow activation")
	adapter.restore()
	check(not sun.shadow_enabled, "shadowless restoration")
	check(root.scaling_3d_scale == original_scale and root.msaa_3d == original_msaa and root.use_taa == original_taa, "viewport unchanged")
	check(ProjectSettings.get_setting(project_shadow_key) == project_shadow_value, "project settings unchanged")
	check(adapter.apply_candidate(fixture, "medium", options), "lifecycle preview")
	fixture.free()
	adapter.restore()
	check(not adapter.get_status()["active"], "restore after root destruction")
	observer.free()
	print("Render profile: ", checks - failures, "/", checks, " checks passed")
	quit(1 if failures else 0)
