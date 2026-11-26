extends RefCounted
## Reversible post-build material adapter. Own one instance per world.
const Candidate := preload("terrain_candidate.gdshader")
const BiomeMask := preload("biome_mask.gd")
const RoadsideBand := preload("roadside_band.gd")
const Contract := preload("world_contract.gd")
const PRIMARY := "res://shaders/terrain_triplanar.gdshader"
const TEXTURES := ["rock_albedo", "rock_normal", "rock_arm", "rock_roughness", "rock_ao",
	"grass_albedo", "grass_normal", "grass_roughness", "grass_ao",
	"dirt_albedo", "dirt_normal", "dirt_roughness", "dirt_ao",
	"shore_albedo", "shore_normal", "shore_roughness"]
const BASE_VALUES := ["slope_threshold", "slope_blend_margin", "normal_strength",
	"rock_scale", "rock_tint", "rock_strata_strength", "rock_strata_freq",
	"triplanar_sharpness", "use_rock_arm", "grass_scale", "grass_tint",
	"dirt_scale", "dirt_tint", "shore_scale", "shore_tint",
	"water_level_m", "shore_height_m", "macro_scale", "macro_luminance_mod"]
# Source shader defaults, used when ShaderMaterial returns null for an unset uniform.
const BASE_DEFAULTS := {
	"slope_threshold": 0.65, "slope_blend_margin": 0.12, "normal_strength": 0.85,
	"rock_scale": 0.075, "rock_tint": Color(0.85, 0.84, 0.82),
	"rock_strata_strength": 0.16, "rock_strata_freq": 0.22, "triplanar_sharpness": 6.0,
	"use_rock_arm": true, "grass_scale": 0.22, "grass_tint": Color(0.68, 0.82, 0.52),
	"dirt_scale": 0.13, "dirt_tint": Color(0.65, 0.62, 0.50),
	"shore_scale": 0.16, "shore_tint": Color(0.84, 0.80, 0.72),
	"water_level_m": 5.35, "shore_height_m": 7.4, "macro_scale": 0.0055,
	"macro_luminance_mod": 0.18}
const LIMITS := {
	"biome_strength": [0.0, 1.0], "meadow_micro_strength": [0.0, 0.3],
	"moss_strength": [0.0, 0.5], "roughness_bias": [-0.2, 0.2],
	"roadside_strength": [0.0, 1.0], "normal_strength": [0.0, 2.0],
	"grass_scale": [0.02, 0.5], "dirt_scale": [0.02, 0.5],
	"rock_scale": [0.01, 0.5], "shore_scale": [0.02, 0.5],
	"slope_threshold": [0.3, 0.9], "slope_blend_margin": [0.02, 0.3],
	"macro_scale": [0.001, 0.05], "macro_luminance_mod": [0.0, 0.5]}
const EXTRA_BASE_LIMITS := {"rock_strata_strength": [0.0, 0.6], "rock_strata_freq": [0.05, 1.0], "triplanar_sharpness": [1.0, 16.0]}
var _entries: Array[Dictionary] = []
var _world_root: WeakRef
var _stats: Dictionary = {"state": "inactive"}

func get_stats() -> Dictionary:
	_prune_destroyed_transaction()
	return _stats.duplicate(true)

func _prune_destroyed_transaction() -> void:
	if _world_root != null and not is_instance_valid(_world_root.get_ref()):
		restore()

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

func _base_value_valid(key: String, value: Variant) -> bool:
	if not _finite(value):
		return false
	if key == "use_rock_arm":
		return value is bool
	if key.ends_with("_tint"):
		return value is Color or value is Vector3
	if not (value is float or value is int):
		return false
	var limits: Array = LIMITS.get(key, EXTRA_BASE_LIMITS.get(key, []))
	if not limits.is_empty():
		# Existing shader values may have float32 endpoint rounding.
		return float(value) >= float(limits[0]) - 0.000001 and float(value) <= float(limits[1]) + 0.000001
	return true

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
	var base_values: Dictionary = {}
	for key in BASE_VALUES:
		var value: Variant = original.get_shader_parameter(key)
		if value == null:
			value = BASE_DEFAULTS[key]
		if not _base_value_valid(key, value):
			return null
		base_values[key] = value
		if value is int:
			value = float(value)
		result.set_shader_parameter(key, value)
	if float(base_values.shore_height_m) <= float(base_values.water_level_m):
		return null
	for key in TEXTURES:
		var texture: Variant = original.get_shader_parameter(key)
		var required: bool = true
		if key == "rock_arm":
			required = base_values.use_rock_arm
		elif key in ["rock_roughness", "rock_ao"]:
			required = not base_values.use_rock_arm
		if not texture is Texture2D or texture.get_width() <= 0 or texture.get_height() <= 0:
			if required:
				return null
			continue
		result.set_shader_parameter(key, texture)
	for key in tuning:
		result.set_shader_parameter(key, float(tuning[key]))
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
	_prune_destroyed_transaction()
	if not _entries.is_empty():
		_stats["last_rejection"] = "restore active transaction before reapplying"
		return false
	var generated := Contract.generated_root(world)
	if generated == null:
		return _fail("unsupported, unbuilt or transformed world")
	var terrain: Node = generated.get_node_or_null("TerrainChunks")
	if not terrain is Node3D or not (terrain as Node3D).global_transform.is_equal_approx(Transform3D.IDENTITY):
		return _fail("missing or transformed terrain chunks")
	for key in options:
		if not key in ["pilot_bounds", "roadside_bounds", "mask_dir", "tuning"]:
			return _fail("unknown option: " + str(key))
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
		var bounds_for_key: Array = LIMITS[key]
		if not is_finite(value) or value < float(bounds_for_key[0]) or value > float(bounds_for_key[1]):
			return _fail("out-of-range tuning: " + str(key))
		if pilot != null and key in BASE_VALUES:
			return _fail("base PBR tuning is global; omit pilot_bounds for: " + str(key))
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
		if not region is Rect2 or not _valid_rect(region) or region.size.x < 1.0 or region.size.y < 1.0 or region.size.x > RoadsideBand.MAX_SIDE or region.size.y > RoadsideBand.MAX_SIDE:
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
		if mesh_instance.is_queued_for_deletion() or not mesh_instance.global_transform.is_finite():
			return _fail("terrain chunk queued for deletion")
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() != 1:
			return _fail("unexpected terrain mesh layout")
		var original: Material = mesh_instance.get_active_material(0)
		if not original is ShaderMaterial:
			return _fail("unsupported terrain material")
		var id := original.get_instance_id()
		if not candidates.has(id):
			var candidate := _make_candidate(original as ShaderMaterial, tuning, pilot, biome, roadside, roadside_region)
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
	_world_root = weakref(generated)
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
		elif instance.mesh != null and instance.mesh.get_surface_count() > 0 and instance.get_surface_override_material(0) == entry.candidate:
			instance.set_surface_override_material(0, entry.prior)
	_entries.clear()
	_world_root = null
	_stats = {"state": "inactive"}
