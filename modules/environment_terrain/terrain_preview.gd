extends RefCounted
## Reversible post-build material adapter. Own one instance per world.
const Candidate := preload("terrain_candidate.gdshader")
const BiomeMask := preload("biome_mask.gd")
const RoadsideBand := preload("roadside_band.gd")
const PRIMARY := "res://shaders/terrain_triplanar.gdshader"
const FALLBACK := "res://assets/forza_env/shaders/terrain_forza.gdshader"
const PRIMARY_MATERIAL := "res://assets/forza_env/materials/terrain_triplanar_pbr.tres"
const TEXTURES := ["rock_albedo", "rock_normal", "rock_arm", "rock_roughness", "rock_ao",
	"grass_albedo", "grass_normal", "grass_roughness", "grass_ao",
	"dirt_albedo", "dirt_normal", "dirt_roughness", "dirt_ao",
	"shore_albedo", "shore_normal", "shore_roughness"]
const BASE_VALUES := ["slope_threshold", "slope_blend_margin", "normal_strength",
	"rock_scale", "rock_tint", "rock_strata_strength", "rock_strata_freq",
	"triplanar_sharpness", "use_rock_arm", "grass_scale", "grass_tint",
	"dirt_scale", "dirt_tint", "shore_scale", "shore_tint",
	"water_level_m", "shore_height_m", "macro_scale", "macro_luminance_mod"]
const LIMITS := {
	"biome_strength": Vector2(0.0, 1.0), "meadow_micro_strength": Vector2(0.0, 0.3),
	"moss_strength": Vector2(0.0, 0.5), "roughness_bias": Vector2(-0.2, 0.2),
	"roadside_strength": Vector2(0.0, 1.0), "normal_strength": Vector2(0.0, 2.0),
	"grass_scale": Vector2(0.02, 0.5), "dirt_scale": Vector2(0.02, 0.5),
	"rock_scale": Vector2(0.01, 0.5), "shore_scale": Vector2(0.02, 0.5),
	"slope_threshold": Vector2(0.3, 0.9), "slope_blend_margin": Vector2(0.02, 0.3),
	"macro_scale": Vector2(0.001, 0.05), "macro_luminance_mod": Vector2(0.0, 0.5)}
var _entries: Array[Dictionary] = []
var _stats: Dictionary = {"state": "inactive"}

func get_stats() -> Dictionary:
	return _stats.duplicate(true)

func _fail(reason: String) -> bool:
	_stats = {"state": "rejected", "reason": reason}
	return false

func _rect_vector(rect: Rect2) -> Vector4:
	return Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)

func _valid_rect(rect: Rect2) -> bool:
	return rect.position.is_finite() and rect.size.is_finite() and rect.size.x > 0.0 and rect.size.y > 0.0 and rect.position.x >= -1000.0 and rect.position.y >= -1000.0 and rect.end.x <= 1000.0 and rect.end.y <= 1000.0

func _finite(value: Variant) -> bool:
	if value is float or value is int:
		return is_finite(float(value))
	if value is Color:
		return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	if value is Vector3:
		return value.is_finite()
	return value is bool

func _make_candidate(original: ShaderMaterial, tuning: Dictionary, pilot: Variant, biome: Texture2D, roadside: Texture2D, roadside_region: Rect2) -> ShaderMaterial:
	if original.shader == null:
		return null
	var source_path := original.shader.resource_path
	# Unknown shader schemas and legacy fallback remain untouched rather than silently
	# replacing their textures/lighting with incompatible defaults.
	if source_path != PRIMARY:
		return null
	var result := ShaderMaterial.new()
	result.shader = Candidate
	result.render_priority = original.render_priority
	result.next_pass = original.next_pass
	for key in TEXTURES:
		var texture: Variant = original.get_shader_parameter(key)
		if not texture is Texture2D:
			return null
		result.set_shader_parameter(key, texture)
	for key in BASE_VALUES:
		var value: Variant = original.get_shader_parameter(key)
		if value == null:
			continue # The candidate retains the original shader's defaults.
		if not _finite(value):
			return null
		result.set_shader_parameter(key, value)
	for key in tuning:
		result.set_shader_parameter(key, tuning[key])
	result.set_shader_parameter("use_biome_mask", biome != null)
	if biome != null:
		result.set_shader_parameter("biome_mask", biome)
	result.set_shader_parameter("use_roadside", roadside != null)
	if roadside != null:
		result.set_shader_parameter("roadside_mask", roadside)
		result.set_shader_parameter("roadside_rect", _rect_vector(roadside_region))
	result.set_shader_parameter("limit_pilot", pilot is Rect2)
	if pilot is Rect2:
		result.set_shader_parameter("pilot_rect", _rect_vector(pilot))
	return result

func apply_candidate(world: Node, options: Dictionary = {}) -> bool:
	if not _entries.is_empty():
		return false # Explicit restore before reapplying; preserve the active transaction.
	if not is_instance_valid(world) or not world.is_inside_tree():
		return _fail("world must be built and in tree")
	if not world.has_method("get_world_metadata"):
		return _fail("unsupported world")
	var metadata: Dictionary = world.get_world_metadata()
	var bounds: Dictionary = metadata.get("bounds", {})
	if bounds.get("min_x") != -1000 or bounds.get("max_x") != 1000 or bounds.get("min_z") != -1000 or bounds.get("max_z") != 1000:
		return _fail("unsupported world coordinate bounds")
	var generated: Variant = world.get("generated_root")
	if not generated is Node3D or not is_instance_valid(generated):
		return _fail("missing generated root")
	var terrain: Node = generated.get_node_or_null("TerrainChunks")
	if terrain == null:
		return _fail("missing terrain chunks")
	var pilot: Variant = options.get("pilot_bounds")
	if pilot != null and (not pilot is Rect2 or not _valid_rect(pilot)):
		return _fail("invalid pilot bounds")
	var tuning: Variant = options.get("tuning", {})
	if not tuning is Dictionary:
		return _fail("tuning must be a dictionary")
	for key in tuning:
		if not LIMITS.has(key) or not (tuning[key] is float or tuning[key] is int):
			return _fail("unknown or nonnumeric tuning: " + str(key))
		var value := float(tuning[key])
		var bounds_for_key: Vector2 = LIMITS[key]
		if not is_finite(value) or value < bounds_for_key.x or value > bounds_for_key.y:
			return _fail("out-of-range tuning: " + str(key))
	var mask_dir: Variant = options.get("mask_dir", BiomeMask.DEFAULT_DIR)
	if not mask_dir is String:
		return _fail("invalid mask directory")
	var mask_reader := BiomeMask.new()
	var biome := mask_reader.load_mask(mask_dir)
	var roadside_reader := RoadsideBand.new()
	var roadside: Texture2D = null
	var roadside_region := Rect2()
	if options.has("roadside_bounds"):
		var region: Variant = options["roadside_bounds"]
		if not region is Rect2 or not _valid_rect(region):
			return _fail("invalid roadside bounds")
		roadside_region = region
		roadside = roadside_reader.build(world, roadside_region)
	# Stage every material and original reference before touching any scene state.
	var staged: Array[Dictionary] = []
	var candidates: Dictionary = {}
	for child in terrain.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh_instance: MeshInstance3D = child
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() != 1:
			return _fail("unexpected terrain mesh layout")
		var original: Material = mesh_instance.get_active_material(0)
		if not original is ShaderMaterial:
			return _fail("unsupported terrain material")
		var id := original.get_instance_id()
		if not candidates.has(id):
			var candidate := _make_candidate(original, tuning, pilot, biome, roadside, roadside_region)
			if candidate == null:
				return _fail("unsupported shader or missing/invalid PBR bindings; original retained")
			candidates[id] = candidate
		var global_override := mesh_instance.material_override != null
		var prior: Material = mesh_instance.material_override if global_override else mesh_instance.get_surface_override_material(0)
		staged.append({"node": weakref(mesh_instance), "global": global_override, "prior": prior, "candidate": candidates[id]})
	if staged.is_empty():
		return _fail("no terrain mesh instances")
	for entry in staged:
		var instance: MeshInstance3D = entry.node.get_ref()
		if entry.global:
			instance.material_override = entry.candidate
		else:
			instance.set_surface_override_material(0, entry.candidate)
	_entries = staged
	_stats = {"state": "active", "chunks": staged.size(), "candidate_materials": candidates.size(),
		"biome": mask_reader.status, "roadside": roadside_reader.status, "roadside_stats": roadside_reader.stats}
	return true

func restore() -> void:
	for entry in _entries:
		var instance: MeshInstance3D = entry.node.get_ref()
		if not is_instance_valid(instance):
			continue
		# Never overwrite a material changed by another owner after our application.
		if entry.global:
			if instance.material_override == entry.candidate:
				instance.material_override = entry.prior
		elif instance.get_surface_override_material(0) == entry.candidate:
			instance.set_surface_override_material(0, entry.prior)
	_entries.clear()
	_stats = {"state": "inactive"}
