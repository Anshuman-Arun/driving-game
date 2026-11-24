class_name CarMaterialSpec
extends RefCounted
## Assignment helper that maps Forza-grade PBR and multi-layer automotive materials
## to vehicle mesh surfaces:
## - car_paint.gdshader for body lacquer
## - Dark tinted mirror-like glass
## - Matte tires (#1A1A1A, roughness 0.85)
## - Dark diffuser metal (metallic 0.85, roughness 0.45)
## - Emissive brake/taillights (#FF0011, emission Color(3.5, 0.1, 0.1), energy >= 3.0)

const CAR_PAINT_SHADER = preload("res://shaders/car_paint.gdshader")
const ContactShadowScript = preload("res://scripts/vehicle/under_car_contact_shadow.gd")

const COLOR_DEEP_RED := Color("#7A0A10")
const COLOR_GRAZING_WARM := Color("#FF4520")
const COLOR_TIRE_ALBEDO := Color("#1A1A1A")
const COLOR_TAILLIGHT_ALBEDO := Color("#FF0011")
const COLOR_TAILLIGHT_EMISSION := Color(3.5, 0.1, 0.1)


## Creates a multi-layer automotive lacquer ShaderMaterial driven by car_paint.gdshader
static func create_car_paint(
	body_color: Color = COLOR_DEEP_RED,
	grazing_color: Color = COLOR_GRAZING_WARM,
	flake_intensity: float = 0.18,
	metallic: float = 0.80,
	roughness: float = 0.18,
	clearcoat: float = 1.0,
	clearcoat_roughness: float = 0.04
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CAR_PAINT_SHADER
	mat.set_shader_parameter("base_color", body_color)
	mat.set_shader_parameter("grazing_color", grazing_color)
	mat.set_shader_parameter("fresnel_power", 2.6)
	mat.set_shader_parameter("flake_intensity", flake_intensity)
	mat.set_shader_parameter("flake_scale", 320.0)
	mat.set_shader_parameter("flake_color", Color(0.85, 0.18, 0.10, 1.0))
	mat.set_shader_parameter("metallic", metallic)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("specular", 0.70)
	mat.set_shader_parameter("clearcoat", clearcoat)
	mat.set_shader_parameter("clearcoat_roughness", clearcoat_roughness)
	return mat


## Creates dark tinted mirror-like glass (roughness = 0.03, metallic = 0.1, specular = 0.95)
static func create_glass() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "CarGlass_Tinted"
	mat.albedo_color = Color(0.02, 0.03, 0.04, 0.88)
	mat.roughness = 0.03
	mat.metallic = 0.1
	mat.metallic_specular = 0.95
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.clearcoat_enabled = true
	mat.clearcoat = 1.0
	mat.clearcoat_roughness = 0.02
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Creates matte tire material (roughness = 0.85, albedo #1A1A1A)
static func create_tire() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "CarTire_Matte"
	mat.albedo_color = COLOR_TIRE_ALBEDO
	mat.roughness = 0.85
	mat.metallic = 0.0
	mat.metallic_specular = 0.15
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Creates dark diffuser metal (roughness = 0.45, metallic = 0.85)
static func create_diffuser() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "CarDiffuser_Metal"
	mat.albedo_color = Color(0.06, 0.06, 0.07, 1.0)
	mat.roughness = 0.45
	mat.metallic = 0.85
	mat.metallic_specular = 0.50
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Creates emissive brake/taillights (albedo #FF0011, emission Color(3.5, 0.1, 0.1), emission_energy >= 3.0)
static func create_taillight(emission_energy: float = 3.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "CarTaillight_Emissive"
	mat.albedo_color = COLOR_TAILLIGHT_ALBEDO
	mat.roughness = 0.15
	mat.metallic = 0.05
	mat.clearcoat_enabled = true
	mat.clearcoat = 1.0
	mat.clearcoat_roughness = 0.08
	mat.emission_enabled = true
	mat.emission = COLOR_TAILLIGHT_EMISSION
	mat.emission_energy_multiplier = maxf(emission_energy, 3.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Creates clear lens headlight material with forward emission
static func create_headlight(emission_energy: float = 2.5) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "CarHeadlight_Reflector"
	mat.albedo_color = Color(0.92, 0.95, 1.0, 0.92)
	mat.roughness = 0.06
	mat.metallic = 0.20
	mat.clearcoat_enabled = true
	mat.clearcoat = 1.0
	mat.clearcoat_roughness = 0.04
	mat.emission_enabled = true
	mat.emission = Color(2.5, 2.7, 3.0)
	mat.emission_energy_multiplier = emission_energy
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Creates high-gloss racing brake caliper material
static func create_caliper(caliper_color: Color = Color(0.85, 0.08, 0.08, 1.0)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "CarCaliper_Gloss"
	mat.albedo_color = caliper_color
	mat.metallic = 0.55
	mat.roughness = 0.20
	mat.clearcoat_enabled = true
	mat.clearcoat = 1.0
	mat.clearcoat_roughness = 0.05
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Creates satin alloy wheel rim material
static func create_rim(rim_color: Color = Color(0.72, 0.74, 0.76, 1.0)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "CarRim_Alloy"
	mat.albedo_color = rim_color
	mat.metallic = 0.92
	mat.roughness = 0.22
	mat.metallic_specular = 0.65
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Traverses all MeshInstance3D nodes in a vehicle or model hierarchy and assigns tailored PBR materials
static func apply_to_vehicle(
	root_node: Node3D,
	body_color: Color = COLOR_DEEP_RED,
	grazing_color: Color = COLOR_GRAZING_WARM
) -> void:
	if root_node == null:
		return

	var paint_mat := create_car_paint(body_color, grazing_color)
	var glass_mat := create_glass()
	var tire_mat := create_tire()
	var diffuser_mat := create_diffuser()
	var taillight_mat := create_taillight(3.0)
	var headlight_mat := create_headlight(2.5)
	var caliper_mat := create_caliper()
	var rim_mat := create_rim()

	var mesh_instances := root_node.find_children("*", "MeshInstance3D", true, false)
	if root_node is MeshInstance3D:
		mesh_instances.append(root_node)

	for node in mesh_instances:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue

		var node_name := mi.name.to_lower()
		var parent_name := mi.get_parent().name.to_lower() if mi.get_parent() != null else ""
		var surf_count := mi.mesh.get_surface_count()

		for s in range(surf_count):
			var active_mat := mi.get_active_material(s)
			var mat_name := active_mat.resource_name.to_lower() if active_mat != null else ""

			var assigned_mat: Material = null

			# Heuristic 1: Inspect material resource name
			if "carpaint" in mat_name or "paint" in mat_name:
				assigned_mat = paint_mat
			elif "glass" in mat_name or "window" in mat_name or "windshield" in mat_name:
				assigned_mat = glass_mat
			elif "tire" in mat_name or "rubber" in mat_name:
				assigned_mat = tire_mat
			elif "diffuser" in mat_name or "splitter" in mat_name or "grille" in mat_name or "skirt" in mat_name:
				assigned_mat = diffuser_mat
			elif "taillight" in mat_name or "tail_light" in mat_name or "brakelight" in mat_name:
				assigned_mat = taillight_mat
			elif "headlight" in mat_name or "head_light" in mat_name:
				assigned_mat = headlight_mat
			elif "caliper" in mat_name:
				assigned_mat = caliper_mat
			elif "rim" in mat_name or "hub" in mat_name or "wheel" in mat_name:
				assigned_mat = rim_mat

			# Heuristic 2: Inspect node and parent names if material name didn't match
			if assigned_mat == null:
				if "body_shell" in node_name or "sculptedbody" in node_name or "nose" in node_name or "roof" in node_name or "mirror" in node_name:
					assigned_mat = paint_mat
				elif "cabin" in node_name or "glass" in node_name or "window" in node_name:
					assigned_mat = glass_mat
				elif "tire" in node_name or "rubber" in node_name:
					assigned_mat = tire_mat
				elif "diffuser" in node_name or "reardiffuser" in node_name or "frontgrille" in node_name or "sideskirt" in node_name or "spoilerblade" in node_name:
					assigned_mat = diffuser_mat
				elif "taillamp" in node_name or "taillight" in node_name or "brakelight" in node_name:
					assigned_mat = taillight_mat
				elif "headlamp" in node_name or "headlight" in node_name:
					assigned_mat = headlight_mat
				elif "brake" in node_name or "caliper" in node_name:
					assigned_mat = caliper_mat
				elif "hub" in node_name or "rim" in node_name or ("wheel" in parent_name and not "tire" in node_name):
					assigned_mat = rim_mat

			if assigned_mat != null:
				mi.set_surface_override_material(s, assigned_mat)


## Helper method to attach and ground UnderCarContactShadow to any vehicle root
static func attach_contact_shadow(vehicle: Node3D, shadow_mode: UnderCarContactShadow.ShadowMode = UnderCarContactShadow.ShadowMode.DECAL) -> UnderCarContactShadow:
	if vehicle == null:
		return null

	var existing := vehicle.get_node_or_null("UnderCarContactShadow") as UnderCarContactShadow
	if existing != null:
		existing.shadow_mode = shadow_mode
		return existing

	var shadow := UnderCarContactShadow.new()
	shadow.name = "UnderCarContactShadow"
	shadow.shadow_mode = shadow_mode
	vehicle.add_child(shadow)
	return shadow
