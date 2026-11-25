extends SceneTree
const Preview := preload("../terrain_preview.gd")
const Mask := preload("../biome_mask.gd")
const Band := preload("../roadside_band.gd")
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
	var mesh := world.ground.mesh
	var collision := world.collision.shape
	var road := world.road.mesh
	var clearance := world.road_clearance
	var preview := Preview.new()
	var region := Rect2(-24, -24, 48, 56)
	var missing := "user://terrain_missing_%d" % Time.get_ticks_usec()
	check(not preview.apply_candidate(null), "null world rejected")
	check(not preview.apply_candidate(world, {"tuning": {"normal_strength": NAN}}), "nonfinite tuning rejected")
	check(not preview.apply_candidate(world, {"pilot_bounds": Rect2(999, 999, 10, 10)}), "out-of-bounds pilot rejected")
	check(world.ground.get_active_material(0) == original, "rejection leaves material untouched")
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
		check(band.stats.clearance_queries <= 48 * 56 * 5, "bounded query count")
		var second := band.build_image(world, region)
		check(second != null and second.get_data() == image.get_data(), "deterministic raster")
	check(band.build_image(world, Rect2(-200, -200, 400, 400)) == null, "oversized raster rejected")
	check(preview.apply_candidate(world, {"mask_dir": missing, "pilot_bounds": region, "roadside_bounds": region}), "candidate applies without optional mask")
	var candidate := world.ground.get_active_material(0) as ShaderMaterial
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
	var explicit := original.duplicate() as ShaderMaterial
	world.ground.material_override = explicit
	check(preview.apply_candidate(world, {"mask_dir": missing}), "global material override supported")
	preview.restore()
	check(world.ground.material_override == explicit, "global override reference restored")
	var bad := ShaderMaterial.new()
	bad.shader = original.shader
	world.ground.material_override = bad
	check(not preview.apply_candidate(world, {"mask_dir": missing}), "missing textures fail closed")
	check(world.ground.material_override == bad, "failed material left untouched")
	world.ground.material_override = null
	_test_mask(world, preview, region)
	world.free()
	if "--production" in OS.get_cmdline_user_args():
		_test_production()
	print("[EnvironmentTerrain] %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _test_mask(world, preview, region: Rect2) -> void:
	var dir := "user://terrain_mask_%d" % Time.get_ticks_usec()
	var absolute := ProjectSettings.globalize_path(dir)
	check(DirAccess.make_dir_recursive_absolute(absolute) == OK, "mask fixture directory")
	var bytes := PackedByteArray()
	bytes.resize(4000000)
	bytes.fill(127)
	bytes[0] = 255
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	var manifest := {"schema_version": 1, "width": 1000, "height": 1000, "cell_size_m": 2,
		"origin_x": -1000, "origin_z": -1000, "channels": Mask.CHANNELS,
		"byte_order": "RGBA", "sha256": hasher.finish().hex_encode(), "source_hashes": {}, "seed": 1}
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
	check(reader.load_mask(dir) is Texture2D, "valid RGBA mask accepted")
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
	var preview := Preview.new()
	var region := Rect2(-810, -450, 220, 220)
	check(preview.apply_candidate(world, {"pilot_bounds": region, "roadside_bounds": region}), "real generated world material adapter")
	check(preview.get_stats().get("chunks", 0) == originals.size(), "all real terrain chunks covered")
	check(JSON.stringify(world.get_road_graph()) == graph and world.get_surface_height_at(-700.0, -320.0) == surface and world.road_clearance.triangle_count == triangles and world.report == report, "production graph, surface, clearance and build report unchanged")
	preview.restore()
	for child in originals:
		check(child.get_active_material(0) == originals[child], "real terrain original restored " + str(child.name))
	world.free()
