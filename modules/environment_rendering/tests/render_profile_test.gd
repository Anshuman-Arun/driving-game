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
	check(not Profile.validate_profile("medium", {42: true})["ok"], "nonstring option key")
	check(not Profile.validate_profile("medium", {"sun_color": Color(1.1, 0.8, 0.7)})["ok"], "out of range daylight color")
	check(not Profile.validate_profile("medium", {"ambient_color": Color(0.1, NAN, 0.5)})["ok"], "non-finite fill color")
	check(not Profile.validate_profile("medium", {"ambient_color": Color(0.1, 0.2, 0.3, 0.5)})["ok"], "transparent fill color")
	check(not Profile.validate_profile("medium", {"sun_color": "orange"})["ok"], "wrong color type")
	check(Profile.validate_profile("medium", {"sun_color": Color.WHITE})["ok"], "valid custom daylight color")
	# Bounds must not be rounded through Vector2/float32. In particular 0.15,
	# 0.12 and 0.001 previously risked rejecting their exact advertised values.
	for key in Profile.RANGES:
		var bounds: Array = Profile.RANGES[key]
		for bound in bounds:
			var override: Dictionary = {key: bound}
			if key == "split_1":
				override["split_2"] = 0.28
			if key == "split_2":
				override["split_1"] = 0.05
				override["split_3"] = 0.60
			if key == "split_3":
				override["split_2"] = 0.22
			check(Profile.validate_profile("medium", override)["ok"], "inclusive bound " + key + ": " + str(bound))
	var snapshot := Profile.validate_profile("medium")
	snapshot["values"]["exposure"] = 0.0
	check(Profile.validate_profile("medium")["values"]["exposure"] == 1.0, "profile values not shared")
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
		check(not status["drifted"], "fresh candidate has no drift")
	adapter.restore()
	check(world_env.environment == original, "restore original environment identity after repeated apply")
	for property in shadow_before:
		check(sun.get(property) == shadow_before[property], "restore sun " + property)
	var options := {"paint_surfaces": [{"mesh": mesh, "surface": 0}], "ssr": true, "ssao": true}
	# World ownership protects separate adapter instances, including different
	# roots in the same World3D. An independent viewport is not blocked.
	var contender := Profile.new()
	var custom_sun := Color(0.95, 0.89, 0.83)
	var custom_fill := Color(0.62, 0.75, 0.88)
	check(adapter.apply_candidate(fixture, "medium", {"sun_color": custom_sun, "ambient_color": custom_fill}), "ownership baseline")
	check(sun.light_color.is_equal_approx(custom_sun) and world_env.environment.ambient_light_color.is_equal_approx(custom_fill), "custom daylight applied")
	world_env.environment.tonemap_exposure = 1.1
	check(adapter.get_status()["drifted"], "in-place candidate environment drift reported")
	world_env.environment.tonemap_exposure = 1.0
	check(not adapter.get_status()["drifted"], "reverted in-place drift")
	var owned := world_env.environment
	check(not contender.apply_candidate(fixture, "high"), "second adapter rejected")
	check(world_env.environment == owned, "second adapter cannot alter first")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	fixture.add_child(viewport)
	var alternate := Node3D.new()
	viewport.add_child(alternate)
	var alt_env := WorldEnvironment.new()
	alt_env.environment = Environment.new()
	alternate.add_child(alt_env)
	var alt_sun := DirectionalLight3D.new()
	alternate.add_child(alt_sun)
	var alternate_options := {"world_environment": alt_env, "sun": alt_sun}
	check(not adapter.apply_candidate(fixture, "high", alternate_options), "cross viewport rejected")
	check(contender.apply_candidate(alternate, "high", alternate_options), "independent world accepted")
	contender.restore()
	viewport.free()
	adapter.restore()
	check(contender.apply_candidate(fixture, "low"), "world released after restore")
	contender.restore()
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
	check(not adapter.apply_candidate(fixture, "high", {"paint_surfaces": [{"mesh": mesh, "surface": 0, "extra": true}]}), "malformed entry rejected")
	check(not adapter.apply_candidate(fixture, "high", {"paint_surfaces": [{"mesh": mesh, "surface": 0.0}]}), "fractional surface type rejected")
	check(not adapter.apply_candidate(fixture, "high", {"paint_surfaces": [42]}), "non dictionary rejected")
	check(not adapter.apply_candidate(fixture, "high", {"paint_surfaces": "paint"}), "non array rejected")
	var doomed := MeshInstance3D.new()
	doomed.mesh = box
	fixture.add_child(doomed)
	doomed.queue_free()
	check(not adapter.apply_candidate(fixture, "high", {"paint_surfaces": [{"mesh": doomed, "surface": 0}]}), "queued deletion target rejected")
	doomed.free()
	check(not adapter.apply_candidate(fixture, "high", {"paint_surfaces": [{"mesh": doomed, "surface": 0}]}), "freed target rejected")
	check(not adapter.apply_candidate(fixture, "high", {"sun": 42}), "non node sun rejected")
	check(world_env.environment == preview, "all invalid requests preserve active preview")
	check(adapter.apply_candidate(fixture, "high", options), "reapply same paint")
	check(mesh.get_surface_override_material(0) != first, "fresh copy on reapply")
	adapter.restore()
	adapter.restore()
	check(mesh.get_surface_override_material(0) == null, "restore absent override")
	check(world_env.environment == original, "restore env")
	# A shared source gets one copied material, not one resource per surface.
	var pair := {"paint_surfaces": [{"mesh": mesh, "surface": 0}, {"mesh": other_mesh, "surface": 0}]}
	check(adapter.apply_candidate(fixture, "medium", pair), "two paint targets")
	check(mesh.get_surface_override_material(0) == other_mesh.get_surface_override_material(0), "shared preview material reused")
	check(adapter.get_status()["paint_material_count"] == 1, "one material copy")
	check(adapter.apply_candidate(fixture, "medium", options), "remove second target on reapply")
	check(other_mesh.get_surface_override_material(0) == null, "removed target restored")
	adapter.restore()
	var explicit := StandardMaterial3D.new()
	mesh.set_surface_override_material(0, explicit)
	check(adapter.apply_candidate(fixture, "low", options), "existing override preview")
	adapter.restore()
	check(mesh.get_surface_override_material(0) == explicit, "restore existing override identity")
	# Late restore must leave a replacement resource or newer sun value alone.
	check(adapter.apply_candidate(fixture, "medium", options), "external change preview")
	var external_env := Environment.new()
	var external_paint := StandardMaterial3D.new()
	world_env.environment = external_env
	mesh.set_surface_override_material(0, external_paint)
	sun.light_energy = 2.4
	check(adapter.get_status()["drifted"], "external drift visible")
	adapter.restore()
	check(world_env.environment == external_env, "external environment preserved")
	check(mesh.get_surface_override_material(0) == external_paint, "external paint preserved")
	check(is_equal_approx(sun.light_energy, 2.4), "external sun energy preserved")
	world_env.environment = original
	sun.light_energy = 1.92
	mesh.set_surface_override_material(0, explicit)
	check(adapter.apply_candidate(fixture, "medium", options), "replaced geometry preview")
	var replacement := BoxMesh.new()
	replacement.material = paint
	mesh.mesh = replacement
	adapter.restore()
	check(mesh.get_surface_override_material(0) == null, "no stale old override on replacement mesh")
	# Engine may clear overrides on mesh replacement; force a clean fixture.
	mesh.mesh = box
	mesh.set_surface_override_material(0, null)
	check(adapter.apply_candidate(fixture, "medium", {"paint_surfaces": options["paint_surfaces"], "paint_clearcoat": 0}), "zero coat accepted")
	var no_coat := mesh.get_surface_override_material(0) as StandardMaterial3D
	check(no_coat != null and not no_coat.clearcoat_enabled, "zero coat disables feature")
	adapter.restore()
	# Removing a watched target must automatically release the preview, including
	# resource and world ownership, even if the object remains alive.
	check(adapter.apply_candidate(fixture, "medium", options), "target lifecycle preview")
	fixture.remove_child(mesh)
	check(not adapter.get_status()["active"], "target exit restores immediately")
	check(world_env.environment == original, "target exit restored environment")
	check(mesh.get_surface_override_material(0) == null, "detached target restored")
	fixture.add_child(mesh)
	check(contender.apply_candidate(fixture, "medium"), "target exit released ownership")
	contender.restore()
	var temporary := Profile.new()
	check(temporary.apply_candidate(fixture, "medium"), "temporary adapter")
	temporary = null
	check(world_env.environment != original, "active lease survives dropped handle")
	check(not Profile.restore_for_root(mesh), "unrelated root cannot release lease")
	check(not contender.apply_candidate(fixture, "medium"), "lost handle still owns world")
	check(Profile.restore_for_root(fixture), "recover lease by exact owning root")
	check(world_env.environment == original, "recovery restores environment")
	check(not Profile.restore_for_root(fixture), "repeat recovery no-op")
	check(contender.apply_candidate(fixture, "medium"), "recovery releases ownership")
	contender.restore()
	# Camera-specific environments are never edited; the status warns about bypass.
	var camera := Camera3D.new()
	camera.environment = Environment.new()
	fixture.add_child(camera)
	camera.make_current()
	check(adapter.apply_candidate(fixture, "medium"), "camera override preview")
	check("Current camera has an environment override; world preview may not be visible" in adapter.get_status()["unavailable"], "camera override reported")
	check(camera.environment != world_env.environment, "camera override untouched")
	adapter.restore()
	camera.free()
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
	root.remove_child(fixture)
	check(not adapter.get_status()["active"] and world_env.environment == original, "root exit restores automatically")
	root.add_child(fixture)
	var orphan := Profile.new()
	check(orphan.apply_candidate(fixture, "medium"), "orphan lease before root destruction")
	orphan = null
	fixture.free()
	adapter.restore()
	check(not adapter.get_status()["active"], "restore after root destruction")
	# New fixture in the same World3D must be able to claim it after the orphan exited.
	var fresh := Node3D.new()
	root.add_child(fresh)
	var fresh_env := WorldEnvironment.new()
	fresh_env.name = "WorldEnvironment"
	fresh_env.environment = Environment.new()
	fresh.add_child(fresh_env)
	var fresh_sun := DirectionalLight3D.new()
	fresh_sun.name = "Sun"
	fresh.add_child(fresh_sun)
	check(contender.apply_candidate(fresh, "medium"), "orphan target exit released world")
	contender.restore()
	fresh.free()
	observer.free()
	print("RENDER_PROFILE_RESULT passed=", checks - failures, " total=", checks, " failures=", failures)
	quit(1 if failures else 0)
