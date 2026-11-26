extends SceneTree
const Preview := preload("../terrain_preview.gd")
const Mask := preload("../biome_mask.gd")
const Band := preload("../roadside_band.gd")
const RockGate := preload("../rock_bank_recipe.gd")
const Fixture := preload("fixture_world.gd")
const Runtime := preload("res://modules/world_runtime/src/world_runtime.gd")
const ValleyEnvironment := preload("res://scripts/integration/aster_valley_environment.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL " + label)
	else:
		print("PASS " + label)

func run() -> void:
	var world := Fixture.new()
	root.add_child(world)
	world.build_fixture()
	var original := world.ground.get_active_material(0) as ShaderMaterial
	if original == null or original.shader == null:
		check(false, "fixture source material loaded")
		world.free()
		quit(1)
		return
	var mesh := world.ground.mesh
	var collision := world.collision.shape
	var road := world.road.mesh
	var clearance := world.road_clearance
	var preview := Preview.new()
	var region := Rect2(-24, -24, 48, 56)
	var missing := "user://terrain_missing_%d" % Time.get_ticks_usec()
	check(not preview.apply_candidate(null), "null world rejected")
	var unknown := Node3D.new()
	root.add_child(unknown)
	check(not preview.apply_candidate(unknown), "unsupported node rejected")
	check(Band.new().build_image(unknown, region) == null, "unsupported clearance world rejected")
	unknown.free()
	world.metadata_override = "not metadata"
	check(not preview.apply_candidate(world), "malformed metadata rejected")
	world.metadata_override = {"bounds": []}
	check(not preview.apply_candidate(world), "malformed bounds rejected")
	world.metadata_override = null
	world.position.x = 1.0
	check(not preview.apply_candidate(world), "shifted world rejected")
	check(Band.new().build_image(world, region) == null, "shifted clearance world rejected")
	world.position.x = 0.0
	check(not preview.apply_candidate(world, {"roadside_bounds": Rect2(-200, -200, 400, 400)}), "oversized roadside request rejected")
	check(not preview.apply_candidate(world, {"pilot_bounds": region, "tuning": {"grass_scale": 0.3}}), "global tuning cannot leak outside a pilot")
	check(not preview.apply_candidate(world, {"typo": true}), "unknown option rejected")
	check(preview.apply_candidate(world, {"mask_dir": "", "tuning": {"slope_threshold": 0.9, "slope_blend_margin": 0.02, "macro_luminance_mod": 0.5}}), "documented exact numeric endpoints accepted")
	preview.restore()
	check(not preview.apply_candidate(world, {"tuning": {"normal_strength": NAN}}), "nonfinite tuning rejected")
	check(not preview.apply_candidate(world, {"pilot_bounds": Rect2(999, 999, 10, 10)}), "out-of-bounds pilot rejected")
	check(world.ground.get_active_material(0) == original, "rejection leaves material untouched")
	var gate := RockGate.new()
	var local_box := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	check(not gate.accepts(Transform3D.IDENTITY, local_box), "unprepared rock gate fails closed")
	check(gate.prepare(world), "water and road rock gate prepares")
	check(not gate.accepts(Transform3D(Basis.IDENTITY, Vector3(0, 30, 0)), local_box), "rock over pavement rejected")
	check(not gate.accepts(Transform3D(Basis.IDENTITY, Vector3(0, 30, 20)), local_box), "rock below bridge rejected")
	check(not gate.accepts(Transform3D(Basis.IDENTITY, Vector3(14, 30, 14)), local_box), "rock in crossing water rejected")
	check(gate.accepts(Transform3D(Basis.IDENTITY, Vector3(-15, 30, -18)), local_box), "dry clear bank footprint accepted")
	check(not gate.accepts(Transform3D(Basis.IDENTITY, Vector3(17, 30, 14)), local_box), "water margin touching prior grid cell rejected")
	check(not gate.accepts(Transform3D(Basis.from_scale(Vector3(1, 0, 1)), Vector3(-15, 30, -18)), local_box), "singular rock transform rejected")
	world.roadworks.waters.append({"height": 30.0, "cells": [[246, 245]]})
	check(not gate.accepts(Transform3D(Basis.IDENTITY, Vector3(-15, 30, -18)), local_box), "mutated water invalidates prepared gate")
	world.roadworks.waters.pop_back()
	check(gate.prepare(world), "rock gate can reprepare")
	check(not gate.accepts(Transform3D(Basis(Vector3.UP, PI / 4.0), Vector3(0, 30, 7.0)), local_box), "rotated rock footprint and setback rejected at shoulder")
	var band := Band.new()
	var image := band.build_image(world, region)
	check(image != null, "roadside CPU raster builds")
	if image != null:
		check(image.get_width() == 48 and image.get_height() == 56, "raster dimensions")
		check(image.get_pixel(24, 24).r == 0.0, "pavement protected")
		check(image.get_pixel(24, 29).r == 0.0, "shoulder protected")
		check(image.get_pixel(24, 44).r == 0.0, "elevated deck column protected")
		check(image.get_pixel(24, 32).r > 0.0, "outside shoulder has transition")
		check(image.get_pixel(24, 6).r == 0.0, "distant ground unaffected")
		check(_protected_bilinear(image, region), "interpolated raster is zero across paved, shoulder and bridge footprints")
		check(band.stats.clearance_queries <= 48 * 56 * 5, "bounded query count")
		var second := band.build_image(world, region)
		check(second != null and second.get_data() == image.get_data(), "deterministic raster")
	check(band.build_image(world, Rect2(-200, -200, 400, 400)) == null, "oversized raster rejected")
	check(preview.apply_candidate(world, {"mask_dir": missing, "pilot_bounds": region, "roadside_bounds": region}), "candidate applies without optional mask")
	var candidate := world.ground.get_active_material(0) as ShaderMaterial
	check(candidate != null, "candidate material exists")
	if candidate != null:
		check(candidate != original and candidate.shader == Preview.Candidate, "distinct candidate shader/material")
		check(candidate.get_shader_parameter("use_biome_mask") == false, "missing mask disables sampling")
		check(candidate.get_shader_parameter("use_roadside") == true, "roadside mask enabled")
		for key in Preview.TEXTURES:
			var texture: Variant = candidate.get_shader_parameter(key)
			check(texture is Texture2D and texture == original.get_shader_parameter(key), "PBR texture preserved: " + key)
		for key in Preview.BASE_VALUES:
			var value: Variant = candidate.get_shader_parameter(key)
			check(value != null and preview._finite(value), "finite binding: " + key)
	check(world.ground.mesh == mesh and world.collision.shape == collision and world.road.mesh == road and world.road_clearance == clearance, "geometry, collision and clearance identities unchanged")
	check(not preview.apply_candidate(world), "second apply requires explicit restore")
	preview.restore()
	check(world.ground.get_active_material(0) == original and world.ground.get_surface_override_material(0) == null, "exact original surface restored")
	preview.restore()
	check(preview.get_stats().state == "inactive", "restore idempotent")
	var explicit := _copy_source(original)
	world.ground.material_override = explicit
	check(preview.apply_candidate(world, {"mask_dir": missing}), "global material override supported")
	preview.restore()
	check(world.ground.material_override == explicit, "global override reference restored")
	check(preview.apply_candidate(world, {"mask_dir": missing}), "second override transaction")
	world.ground.material_override = original
	preview.restore()
	check(world.ground.material_override == original, "external material change is preserved on restore")
	var arm_only := _copy_source(original)
	arm_only.set_shader_parameter("rock_roughness", null)
	arm_only.set_shader_parameter("rock_ao", null)
	world.ground.material_override = arm_only
	check(preview.apply_candidate(world, {"mask_dir": missing}), "packed rock ARM does not require inactive textures")
	preview.restore()
	var separate := _copy_source(original)
	separate.set_shader_parameter("use_rock_arm", false)
	separate.set_shader_parameter("rock_arm", null)
	world.ground.material_override = separate
	check(preview.apply_candidate(world, {"mask_dir": missing}), "separate rock maps do not require inactive ARM")
	preview.restore()
	separate.set_shader_parameter("rock_ao", null)
	check(not preview.apply_candidate(world, {"mask_dir": missing}), "missing active rock AO rejects")
	var invalid := _copy_source(original)
	invalid.set_shader_parameter("water_level_m", 10.0)
	invalid.set_shader_parameter("shore_height_m", 9.0)
	world.ground.material_override = invalid
	check(not preview.apply_candidate(world, {"mask_dir": missing}), "invalid shore height order rejects")
	var defaulted := _copy_source(original)
	defaulted.set_shader_parameter("grass_scale", null)
	world.ground.material_override = defaulted
	check(preview.apply_candidate(world, {"mask_dir": missing}), "unset base parameter uses actual shader default")
	var default_candidate := world.ground.get_active_material(0) as ShaderMaterial
	if default_candidate != null:
		check(absf(float(default_candidate.get_shader_parameter("grass_scale")) - 0.22) < 0.000001, "default grass scale preserved")
	preview.restore()
	var bad := ShaderMaterial.new()
	bad.shader = original.shader
	world.ground.material_override = bad
	check(not preview.apply_candidate(world, {"mask_dir": missing}), "missing textures fail closed")
	check(world.ground.material_override == bad, "failed material left untouched")
	world.ground.material_override = null
	_test_mask(world, preview, region)
	check(preview.apply_candidate(world, {"mask_dir": missing}), "apply before world rebuild")
	world.build_fixture()
	check(not gate.accepts(Transform3D(Basis.IDENTITY, Vector3(-15, 30, -18)), local_box), "rebuild invalidates old rock gate")
	check(preview.get_stats().state == "inactive", "destroyed transaction pruned")
	check(preview.apply_candidate(world, {"mask_dir": missing}), "same adapter can apply after rebuild")
	preview.restore()
	world.free()
	if "--production" in OS.get_cmdline_user_args():
		_test_production()
	print("[EnvironmentTerrain] %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _copy_source(source: ShaderMaterial) -> ShaderMaterial:
	var copy := ShaderMaterial.new()
	copy.shader = source.shader
	for key in Preview.TEXTURES + Preview.BASE_VALUES:
		var value: Variant = source.get_shader_parameter(key)
		if value != null:
			copy.set_shader_parameter(key, value)
	return copy

func _sample_bilinear(image: Image, region: Rect2, point: Vector2) -> float:
	var dimensions := Vector2(image.get_width(), image.get_height())
	var pixel := (point - region.position) / region.size * dimensions - Vector2(0.5, 0.5)
	var x := floori(pixel.x)
	var z := floori(pixel.y)
	var fraction := pixel - Vector2(x, z)
	var a := image.get_pixel(clampi(x, 0, image.get_width() - 1), clampi(z, 0, image.get_height() - 1)).r
	var b := image.get_pixel(clampi(x + 1, 0, image.get_width() - 1), clampi(z, 0, image.get_height() - 1)).r
	var c := image.get_pixel(clampi(x, 0, image.get_width() - 1), clampi(z + 1, 0, image.get_height() - 1)).r
	var d := image.get_pixel(clampi(x + 1, 0, image.get_width() - 1), clampi(z + 1, 0, image.get_height() - 1)).r
	return lerpf(lerpf(a, b, fraction.x), lerpf(c, d, fraction.x), fraction.y)

func _protected_bilinear(image: Image, region: Rect2) -> bool:
	for x in range(-94, 95):
		for z in range(-24, 25):
			if _sample_bilinear(image, region, Vector2(x, z) * 0.25) > 0.000001:
				return false
	for x in range(-12, 13):
		for z in range(60, 101):
			if _sample_bilinear(image, region, Vector2(x, z) * 0.25) > 0.000001:
				return false
	return true

func _test_mask(world, preview, region: Rect2) -> void:
	var dir := "user://terrain_mask_%d" % Time.get_ticks_usec()
	var absolute := ProjectSettings.globalize_path(dir)
	check(DirAccess.make_dir_recursive_absolute(absolute) == OK, "mask fixture directory")
	var bytes := PackedByteArray()
	bytes.resize(4000000)
	bytes.fill(127)
	bytes[0] = 255
	bytes[1] = 64
	bytes[2] = 32
	bytes[3] = 16
	bytes[4000] = 0
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	var digest := hasher.finish().hex_encode()
	var manifest := {"schema_version": 1, "width": 1000, "height": 1000, "cell_size_m": 2,
		"origin_x": -1000, "origin_z": -1000, "channels": Mask.CHANNELS,
		"byte_order": "RGBA", "sha256": digest, "source_hashes": {"fixture": digest}, "seed": 1}
	var manifest_file := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	var raw_file := FileAccess.open(dir.path_join("biome_rgba8.bin"), FileAccess.WRITE)
	if manifest_file == null or raw_file == null:
		check(false, "mask fixture files writable")
		return
	manifest_file.store_string(JSON.stringify(manifest))
	manifest_file.close()
	raw_file.store_buffer(bytes)
	raw_file.close()
	var reader := Mask.new()
	var cpu_mask := reader.load_image(dir)
	check(cpu_mask != null, "valid RGBA mask accepted")
	if cpu_mask != null:
		var first := cpu_mask.get_pixel(0, 0)
		check(first.r == 1.0 and absf(first.g - 64.0 / 255.0) < 0.001 and absf(first.b - 32.0 / 255.0) < 0.001 and absf(first.a - 16.0 / 255.0) < 0.001, "RGBA channel ordering preserved")
		check(cpu_mask.get_pixel(0, 1).r == 0.0 and cpu_mask.get_pixel(1, 0).r > 0.0, "X-fastest Z-ascending row order preserved")
	check(preview.apply_candidate(world, {"mask_dir": dir, "pilot_bounds": region}), "valid mask applies")
	var mat: ShaderMaterial = world.ground.get_active_material(0)
	check(mat.get_shader_parameter("use_biome_mask") == true and mat.get_shader_parameter("biome_mask") is Texture2D, "biome texture bound")
	preview.restore()
	bytes[0] = 42
	raw_file = FileAccess.open(dir.path_join("biome_rgba8.bin"), FileAccess.WRITE)
	raw_file.store_buffer(bytes)
	raw_file.close()
	check(reader.load_mask(dir) == null and reader.status == "mask checksum mismatch", "corrupt same-size mask rejected")
	raw_file = FileAccess.open(dir.path_join("biome_rgba8.bin"), FileAccess.WRITE)
	raw_file.store_8(1)
	raw_file.close()
	check(reader.load_mask(dir) == null, "truncated mask rejected")
	raw_file = FileAccess.open(dir.path_join("biome_rgba8.bin"), FileAccess.WRITE)
	bytes[0] = 255
	raw_file.store_buffer(bytes)
	raw_file.close()
	manifest.seed = "wrong"
	manifest_file = FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(manifest))
	manifest_file.close()
	check(reader.load_image(dir) == null, "invalid seed rejected")
	manifest.seed = 1
	manifest.source_hashes = {"fixture": "not a digest"}
	manifest_file = FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(manifest))
	manifest_file.close()
	check(reader.load_image(dir) == null, "invalid source hash rejected")
	manifest_file = FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	manifest_file.store_string("{")
	manifest_file.close()
	check(reader.load_image(dir) == null, "malformed JSON rejected without loading texture")
	check(preview.apply_candidate(world, {"mask_dir": dir}), "corrupt optional mask falls back safely")
	var fallback := world.ground.get_active_material(0) as ShaderMaterial
	if fallback != null:
		check(fallback.get_shader_parameter("use_biome_mask") == false, "corrupt mask sampling disabled")
	preview.restore()
	DirAccess.remove_absolute(absolute.path_join("manifest.json"))
	DirAccess.remove_absolute(absolute.path_join("biome_rgba8.bin"))
	DirAccess.remove_absolute(absolute)

func _test_production() -> void:
	var world := Runtime.new()
	world.build_on_ready = false
	world.build_full_world = true
	ValleyEnvironment.apply_world_materials(world)
	var works: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/roadworks.json"))
	if not works is Dictionary:
		check(false, "production roadworks available")
		world.free()
		return
	world.roadworks = works
	world.crossing_water_material = load("res://assets/forza_env/materials/lake_water_forza.tres")
	root.add_child(world)
	if not world.build_world():
		check(false, "production build: " + world.error_message)
		world.free()
		return
	var graph := JSON.stringify(world.get_road_graph())
	var surface := world.get_surface_height_at(-700.0, -320.0)
	var triangles: int = world.road_clearance.triangle_count
	var report := world.report.duplicate(true)
	var terrain := world.generated_root.get_node("TerrainChunks")
	var originals: Dictionary = {}
	for child in terrain.get_children():
		if child is MeshInstance3D:
			originals[child] = (child as MeshInstance3D).get_active_material(0)
	check(not originals.is_empty(), "production terrain chunks exist")
	var preview := Preview.new()
	var region := Rect2(-810, -450, 220, 220)
	check(preview.apply_candidate(world, {"pilot_bounds": region, "roadside_bounds": region}), "real generated world material adapter")
	check(preview.get_stats().get("chunks", 0) == originals.size(), "all real terrain chunks covered")
	check(JSON.stringify(world.get_road_graph()) == graph and world.get_surface_height_at(-700.0, -320.0) == surface and world.road_clearance.triangle_count == triangles and world.report == report, "production graph, surface, clearance and build report unchanged")
	preview.restore()
	for child in originals:
		check(child.get_active_material(0) == originals[child], "real terrain original restored " + str(child.name))
	world.free()
