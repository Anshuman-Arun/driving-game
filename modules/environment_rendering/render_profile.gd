extends RefCounted
## Opt-in, main-thread preview. One instance per active drive root; restore before
## external quality changes, scene/car replacement or releasing this instance.
## Only direct named nodes or explicit descendants are accepted.

const PAINT_SHADER := "res://shaders/car_paint.gdshader"
const PRESETS := {
	"low": {"shadow_distance": 135.0, "ssao": false, "glow": false},
	"medium": {"shadow_distance": 220.0, "ssao": false, "glow": true},
	"high": {"shadow_distance": 300.0, "ssao": true, "glow": true},
}
const DEFAULTS := {
	"sun_energy": 1.75, "ambient_energy": 0.60, "exposure": 1.0,
	"shadow_bias": 0.027, "shadow_normal_bias": 0.64, "shadow_blur": 1.0,
	"split_1": 0.08, "split_2": 0.23, "split_3": 0.52,
	"ao_radius": 1.0, "ao_intensity": 0.65, "fog_density": 0.00029,
	"contrast": 1.04, "saturation": 1.02, "ssr": false,
	"ssr_steps": 32, "paint_roughness": 0.24, "paint_clearcoat": 0.82,
	"paint_clearcoat_roughness": 0.12, "paint_metallic": 0.48,
}
const RANGES := {
	"sun_energy": Vector2(0.5, 3.0), "ambient_energy": Vector2(0.15, 1.0),
	"exposure": Vector2(0.6, 1.4), "shadow_distance": Vector2(50, 380),
	"shadow_bias": Vector2(0.001, 0.15), "shadow_normal_bias": Vector2(0, 2),
	"shadow_blur": Vector2(0, 2), "split_1": Vector2(0.02, 0.25),
	"split_2": Vector2(0.10, 0.55), "split_3": Vector2(0.30, 0.90),
	"ao_radius": Vector2(0.3, 2.0), "ao_intensity": Vector2(0, 1.2),
	"fog_density": Vector2(0, 0.001), "contrast": Vector2(0.9, 1.15),
	"saturation": Vector2(0.85, 1.15), "ssr_steps": Vector2(16, 48),
	"paint_roughness": Vector2(0.12, 0.5), "paint_clearcoat": Vector2(0, 1),
	"paint_clearcoat_roughness": Vector2(0.05, 0.35), "paint_metallic": Vector2(0, 0.8),
}
const SUN_PROPERTIES := [
	"light_color", "light_energy", "light_specular", "directional_shadow_max_distance",
	"directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3",
	"shadow_bias", "shadow_normal_bias", "shadow_blur",
]
var _world_env: WorldEnvironment
var _original_env: Environment
var _candidate_env: Environment
var _sun: DirectionalLight3D
var _sun_before: Dictionary = {}
var _paint_before: Array[Dictionary] = []
var _status: Dictionary = {"active": false}

static func validate_profile(preset: String, options: Dictionary = {}) -> Dictionary:
	var q := preset.to_lower()
	if not PRESETS.has(q):
		return {"ok": false, "error": "Unknown preset: " + preset}
	var p := DEFAULTS.duplicate()
	p.merge(PRESETS[q], true)
	for key in options:
		if key in ["world_environment", "sun", "paint_surfaces"]:
			continue
		if not p.has(key):
			return {"ok": false, "error": "Unknown option: " + str(key)}
		var value: Variant = options[key]
		if key in ["ssao", "ssr", "glow"]:
			if typeof(value) != TYPE_BOOL:
				return {"ok": false, "error": "Expected bool: " + str(key)}
		else:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
				return {"ok": false, "error": "Expected number: " + str(key)}
			var n := float(value)
			var bounds: Vector2 = RANGES[key]
			if not is_finite(n) or n < bounds.x or n > bounds.y:
				return {"ok": false, "error": "Out of range: " + str(key)}
			if key == "ssr_steps" and n != floor(n):
				return {"ok": false, "error": "SSR steps must be integral"}
		p[key] = value
	if not (p["split_1"] < p["split_2"] and p["split_2"] < p["split_3"]):
		return {"ok": false, "error": "Shadow splits must be strictly increasing"}
	return {"ok": true, "values": p}

static func _within(root: Node, node: Node) -> bool:
	return is_instance_valid(node) and (root == node or root.is_ancestor_of(node))

func _reject(reason: String) -> bool:
	# Failed reconfiguration leaves the currently active preview unchanged.
	_status["last_error"] = reason
	return false

func apply_candidate(root: Node, preset: String, options: Dictionary = {}) -> bool:
	var validated := validate_profile(preset, options)
	if not validated["ok"]:
		return _reject(str(validated["error"]))
	if not is_instance_valid(root) or not root.is_inside_tree():
		return _reject("Root must be a live scene node")
	var env_node: Variant = options.get("world_environment", root.get_node_or_null("WorldEnvironment"))
	var sun_node: Variant = options.get("sun", root.get_node_or_null("Sun"))
	if not env_node is WorldEnvironment or not sun_node is DirectionalLight3D:
		return _reject("Missing WorldEnvironment or directional Sun")
	var world_env := env_node as WorldEnvironment
	var sun := sun_node as DirectionalLight3D
	if not _within(root, world_env) or not _within(root, sun) or not is_instance_valid(world_env.environment):
		return _reject("Invalid environment or nodes outside preview root")
	var p: Dictionary = validated["values"]
	var requested: Variant = options.get("paint_surfaces", [])
	if not requested is Array:
		return _reject("paint_surfaces must be an array of mesh/surface dictionaries")
	var prepared: Array[Dictionary] = []
	var seen: Dictionary = {}
	# Validate the full request first, including the original material if reapplying.
	for entry in requested:
		if not entry is Dictionary:
			return _reject("Invalid paint surface entry")
		var target: Variant = entry.get("mesh")
		var index: Variant = entry.get("surface")
		if not target is MeshInstance3D or typeof(index) != TYPE_INT:
			return _reject("Paint requires MeshInstance3D and integer surface")
		var mesh := target as MeshInstance3D
		var surface := int(index)
		if not _within(root, mesh) or mesh.mesh == null or mesh.material_override != null:
			return _reject("Invalid paint mesh or whole-mesh override")
		if surface < 0 or surface >= mesh.mesh.get_surface_count():
			return _reject("Paint surface out of range")
		var key := str(mesh.get_instance_id()) + ":" + str(surface)
		if seen.has(key):
			return _reject("Duplicate paint surface")
		seen[key] = true
		var original := mesh.get_surface_override_material(surface)
		var active := mesh.get_active_material(surface)
		for previous in _paint_before:
			if previous["mesh"] == mesh and previous["surface"] == surface:
				original = previous["original"]
				active = original if original != null else mesh.mesh.surface_get_material(surface)
				break
		if not active is StandardMaterial3D and not (active is ShaderMaterial and active.shader != null and active.shader.resource_path == PAINT_SHADER):
			return _reject("Paint requires StandardMaterial3D or the existing car_paint shader")
		var copy := active.duplicate() as Material
		if copy == null:
			return _reject("Paint resource duplication failed")
		if copy is StandardMaterial3D:
			var standard := copy as StandardMaterial3D
			standard.roughness = p["paint_roughness"]
			standard.metallic = p["paint_metallic"]
			standard.clearcoat_enabled = true
			standard.clearcoat = p["paint_clearcoat"]
			standard.clearcoat_roughness = p["paint_clearcoat_roughness"]
		else:
			var shader_mat := copy as ShaderMaterial
			for uniform in ["roughness", "metallic", "clearcoat", "clearcoat_roughness"]:
				shader_mat.set_shader_parameter(uniform, p["paint_" + uniform])
		prepared.append({"mesh": mesh, "surface": surface, "original": original, "candidate": copy})
	var source := world_env.environment
	if world_env == _world_env and source == _candidate_env:
		source = _original_env
	var candidate := source.duplicate() as Environment
	if candidate == null:
		return _reject("Environment duplication failed")
	# Sky and texture resources are intentionally shared READ-ONLY. Preserve HDRI,
	# sun orientation, reflection source, camera attributes and existing fog switch.
	var renderer := RenderingServer.get_current_rendering_method()
	var headless := DisplayServer.get_name() == "headless"
	var forward := renderer == "forward_plus" and not headless
	candidate.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	candidate.ambient_light_color = Color(0.68, 0.78, 0.94)
	candidate.ambient_light_energy = p["ambient_energy"]
	candidate.ambient_light_sky_contribution = 0.68
	candidate.tonemap_exposure = p["exposure"]
	candidate.fog_density = p["fog_density"]
	candidate.adjustment_enabled = true
	candidate.adjustment_contrast = p["contrast"]
	candidate.adjustment_saturation = p["saturation"]
	candidate.glow_enabled = p["glow"] and not headless and renderer != "gl_compatibility"
	candidate.glow_intensity = 0.16
	candidate.glow_bloom = 0.025
	candidate.ssao_enabled = p["ssao"] and forward
	candidate.ssao_radius = p["ao_radius"]
	candidate.ssao_intensity = p["ao_intensity"]
	candidate.ssr_enabled = p["ssr"] and forward
	candidate.ssr_max_steps = int(p["ssr_steps"])
	candidate.ssr_depth_tolerance = 0.2
	candidate.ssil_enabled = false
	candidate.sdfgi_enabled = false
	candidate.volumetric_fog_enabled = false
	# Commit only after all preflight checks have succeeded.
	restore()
	_world_env = world_env
	_original_env = source
	_candidate_env = candidate
	_sun = sun
	for property in SUN_PROPERTIES:
		_sun_before[property] = sun.get(property)
	world_env.environment = candidate
	sun.light_color = Color(1.0, 0.96, 0.89)
	sun.light_energy = p["sun_energy"]
	sun.light_specular = 0.78
	# Never enable shadows or change cascade count/atlas. Tune existing shadows only.
	if sun.shadow_enabled:
		sun.directional_shadow_max_distance = p["shadow_distance"]
		sun.directional_shadow_split_1 = p["split_1"]
		sun.directional_shadow_split_2 = p["split_2"]
		sun.directional_shadow_split_3 = p["split_3"]
		sun.shadow_bias = p["shadow_bias"]
		sun.shadow_normal_bias = p["shadow_normal_bias"]
		sun.shadow_blur = p["shadow_blur"]
	for entry in prepared:
		var mesh: MeshInstance3D = entry["mesh"]
		mesh.set_surface_override_material(entry["surface"], entry["candidate"])
		_paint_before.append(entry)
	var unavailable: Array[String] = []
	if p["ssao"] and not candidate.ssao_enabled:
		unavailable.append("SSAO requires graphical Forward+")
	if p["ssr"] and not candidate.ssr_enabled:
		unavailable.append("SSR requires graphical Forward+")
	if p["glow"] and not candidate.glow_enabled:
		unavailable.append("Glow disabled for this renderer/headless preview")
	if not sun.shadow_enabled:
		unavailable.append("Existing sun shadows disabled; not activated")
	if candidate.sky == null:
		unavailable.append("No existing sky resource; no HDRI fabricated")
	_status = {"active": true, "preset": preset.to_lower(), "renderer": renderer,
		"headless": headless, "values": p.duplicate(), "unavailable": unavailable,
		"ssao_enabled": candidate.ssao_enabled, "ssr_enabled": candidate.ssr_enabled,
		"glow_enabled": candidate.glow_enabled, "shadow_enabled": sun.shadow_enabled,
		"paint_surface_count": prepared.size()}
	return true

func restore() -> void:
	for entry in _paint_before:
		var mesh: Variant = entry["mesh"]
		if is_instance_valid(mesh) and mesh.mesh != null and entry["surface"] < mesh.mesh.get_surface_count():
			# Don't overwrite a replacement material installed by another system.
			if mesh.get_surface_override_material(entry["surface"]) == entry["candidate"]:
				mesh.set_surface_override_material(entry["surface"], entry["original"])
	_paint_before.clear()
	if is_instance_valid(_world_env) and _world_env.environment == _candidate_env:
		_world_env.environment = _original_env
	if is_instance_valid(_sun):
		for property in _sun_before:
			_sun.set(property, _sun_before[property])
	_sun_before.clear()
	_world_env = null
	_original_env = null
	_candidate_env = null
	_sun = null
	_status = {"active": false}

func get_status() -> Dictionary:
	return _status.duplicate(true)

## Data only: no camera controls or blur shader changes.
static func camera_candidate() -> Dictionary:
	return {"chase_height_m": 2.35, "chase_distance_m": 7.4,
		"fov_rest_deg": 58.0, "fov_top_speed_deg": 70.0,
		"top_speed_mps": 60.0, "radial_blur": false}
