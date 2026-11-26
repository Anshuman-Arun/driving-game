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
	"sun_energy": [0.5, 3.0], "ambient_energy": [0.15, 1.0],
	"exposure": [0.6, 1.4], "shadow_distance": [50, 380],
	"shadow_bias": [0.001, 0.15], "shadow_normal_bias": [0, 2],
	"shadow_blur": [0, 2], "split_1": [0.02, 0.25],
	"split_2": [0.10, 0.55], "split_3": [0.30, 0.90],
	"ao_radius": [0.3, 2.0], "ao_intensity": [0, 1.2],
	"fog_density": [0, 0.001], "contrast": [0.9, 1.15],
	"saturation": [0.85, 1.15], "ssr_steps": [16, 48],
	"paint_roughness": [0.12, 0.5], "paint_clearcoat": [0, 1],
	"paint_clearcoat_roughness": [0.05, 0.35], "paint_metallic": [0, 0.8],
}
const SUN_PROPERTIES := [
	"light_color", "light_energy", "light_specular", "directional_shadow_max_distance",
	"directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3",
	"shadow_bias", "shadow_normal_bias", "shadow_blur",
]
static var _world_owners: Dictionary = {}
var _world_id := 0
var _owner_id := 0
var _preview_root: Node
var _world_env: WorldEnvironment
var _original_env: Environment
var _candidate_env: Environment
var _sun: DirectionalLight3D
var _sun_before: Dictionary = {}
var _sun_applied: Dictionary = {}
var _paint_before: Array[Dictionary] = []
var _status: Dictionary = {"active": false}

static func validate_profile(preset: String, options: Dictionary = {}) -> Dictionary:
	var q := preset.to_lower()
	if not PRESETS.has(q):
		return {"ok": false, "error": "Unknown preset: " + preset}
	var p := DEFAULTS.duplicate()
	p.merge(PRESETS[q], true)
	for raw_key in options:
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return {"ok": false, "error": "Option keys must be strings"}
		var key := String(raw_key)
		if key in ["world_environment", "sun", "paint_surfaces"]:
			continue
		if not p.has(key):
			return {"ok": false, "error": "Unknown option: " + str(key)}
		var value: Variant = options[raw_key]
		if key in ["ssao", "ssr", "glow"]:
			if typeof(value) != TYPE_BOOL:
				return {"ok": false, "error": "Expected bool: " + str(key)}
		else:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
				return {"ok": false, "error": "Expected number: " + str(key)}
			var n := float(value)
			var bounds: Array = RANGES[key]
			if not is_finite(n) or n < float(bounds[0]) or n > float(bounds[1]):
				return {"ok": false, "error": "Out of range: " + str(key)}
			if key == "ssr_steps" and n != floor(n):
				return {"ok": false, "error": "SSR steps must be integral"}
			value = int(n) if key == "ssr_steps" else n
		p[key] = value
	if not (p["split_1"] < p["split_2"] and p["split_2"] < p["split_3"]):
		return {"ok": false, "error": "Shadow splits must be strictly increasing"}
	return {"ok": true, "values": p}

static func _within(root: Node, node: Node) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree() or node.get_viewport() != root.get_viewport():
		return false
	var cursor: Node = node
	while cursor != null:
		if cursor.is_queued_for_deletion():
			return false
		if cursor == root:
			return true
		cursor = cursor.get_parent()
	return false

static func _live_object(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and is_instance_valid(value)

func _owned_by_other(world_id: int) -> bool:
	var owner: int = _world_owners.get(world_id, 0)
	return owner != 0 and owner != get_instance_id() and is_instance_id_valid(owner)

func _on_root_exiting() -> void:
	restore()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _world_id != 0:
		restore()

func _reject(reason: String) -> bool:
	# Failed reconfiguration leaves the currently active preview unchanged.
	_status["last_error"] = reason
	return false

func apply_candidate(root: Node, preset: String, options: Dictionary = {}) -> bool:
	var validated := validate_profile(preset, options)
	if not validated["ok"]:
		return _reject(str(validated["error"]))
	if not is_instance_valid(root) or not root.is_inside_tree() or root.is_queued_for_deletion():
		return _reject("Root must be a live scene node")
	var env_node: Variant = options.get("world_environment", root.get_node_or_null("WorldEnvironment"))
	var sun_node: Variant = options.get("sun", root.get_node_or_null("Sun"))
	if not _live_object(env_node) or not _live_object(sun_node) or not env_node is WorldEnvironment or not sun_node is DirectionalLight3D:
		return _reject("Missing WorldEnvironment or directional Sun")
	var world_env := env_node as WorldEnvironment
	var sun := sun_node as DirectionalLight3D
	if not _within(root, world_env) or not _within(root, sun) or not is_instance_valid(world_env.environment):
		return _reject("Invalid environment or nodes outside preview root")
	var world: World3D = root.get_viewport().find_world_3d()
	if world == null or _owned_by_other(world.get_instance_id()):
		return _reject("World3D missing or already has an active render preview")
	var world_id := world.get_instance_id()
	var p: Dictionary = validated["values"]
	var requested: Variant = options.get("paint_surfaces", [])
	if not requested is Array:
		return _reject("paint_surfaces must be an array of mesh/surface dictionaries")
	var prepared: Array[Dictionary] = []
	var seen: Dictionary = {}
	var previous_by_key: Dictionary = {}
	var copies: Dictionary = {}
	for previous in _paint_before:
		previous_by_key[previous["key"]] = previous
	# Validate the full request first, including the original material if reapplying.
	for entry in requested:
		if not entry is Dictionary:
			return _reject("Invalid paint surface entry")
		if entry.size() != 2 or not entry.has("mesh") or not entry.has("surface"):
			return _reject("Paint entry must contain only mesh and surface")
		var target: Variant = entry.get("mesh")
		var index: Variant = entry.get("surface")
		if not _live_object(target) or not target is MeshInstance3D or typeof(index) != TYPE_INT:
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
		if previous_by_key.has(key):
			var previous: Dictionary = previous_by_key[key]
			if original == previous["candidate"]:
				# A replacement Mesh must never receive the old geometry's override.
				original = previous["original"] if mesh.mesh == previous["geometry"] else null
				active = original if original != null else mesh.mesh.surface_get_material(surface)
		var shader_source := active as ShaderMaterial
		if not active is StandardMaterial3D:
			if shader_source == null or shader_source.shader == null or shader_source.shader.resource_path != PAINT_SHADER:
				return _reject("Paint requires StandardMaterial3D or the existing car_paint shader")
		# Reuse the same candidate for surfaces sharing the source material.
		var material_id := active.get_instance_id()
		var copy: Material = copies.get(material_id)
		if copy == null:
			copy = active.duplicate() as Material
			if copy == null:
				return _reject("Paint resource duplication failed")
			if copy is StandardMaterial3D:
				var standard := copy as StandardMaterial3D
				standard.roughness = p["paint_roughness"]
				standard.metallic = p["paint_metallic"]
				standard.clearcoat_enabled = float(p["paint_clearcoat"]) > 0.0
				standard.clearcoat = p["paint_clearcoat"]
				standard.clearcoat_roughness = p["paint_clearcoat_roughness"]
			else:
				var shader_mat := copy as ShaderMaterial
				for uniform in ["roughness", "metallic", "clearcoat", "clearcoat_roughness"]:
					shader_mat.set_shader_parameter(uniform, float(p["paint_" + uniform]))
			copies[material_id] = copy
		prepared.append({"key": key, "mesh": mesh, "geometry": mesh.mesh, "surface": surface, "original": original, "candidate": copy})
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
	candidate.glow_enabled = p["glow"] and not headless and renderer in ["forward_plus", "mobile"]
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
	_world_id = world_id
	_owner_id = get_instance_id()
	_world_owners[_world_id] = _owner_id
	_preview_root = root
	_preview_root.tree_exiting.connect(_on_root_exiting)
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
	for property in SUN_PROPERTIES:
		var current: Variant = sun.get(property)
		if current != _sun_before[property]:
			_sun_applied[property] = current
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
		"paint_surface_count": prepared.size(), "paint_material_count": copies.size()}
	return true

func restore() -> void:
	if is_instance_valid(_preview_root) and _preview_root.tree_exiting.is_connected(_on_root_exiting):
		_preview_root.tree_exiting.disconnect(_on_root_exiting)
	_preview_root = null
	for entry in _paint_before:
		var mesh: Variant = entry["mesh"]
		if is_instance_valid(mesh) and mesh.mesh != null and entry["surface"] < mesh.mesh.get_surface_count():
			# Don't overwrite a replacement material installed by another system.
			if mesh.get_surface_override_material(entry["surface"]) == entry["candidate"]:
				mesh.set_surface_override_material(entry["surface"], entry["original"] if mesh.mesh == entry["geometry"] else null)
	_paint_before.clear()
	if is_instance_valid(_world_env) and _world_env.environment == _candidate_env:
		_world_env.environment = _original_env
	if is_instance_valid(_sun):
		# Compare-and-restore only properties actually changed by us. Do not clobber
		# another controller's newer values during a late restore.
		for property in _sun_applied:
			if _sun.get(property) == _sun_applied[property]:
				_sun.set(property, _sun_before[property])
	_sun_applied.clear()
	_sun_before.clear()
	if _world_id != 0 and _world_owners.get(_world_id, 0) == _owner_id:
		_world_owners.erase(_world_id)
	_world_id = 0
	_owner_id = 0
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
