class_name UnderCarContactShadow
extends Node3D
## Dynamic under-car contact shadow controller for grounded automotive presence.
## Projects a soft-falloff occlusion footprint onto the road deck via Decal or Quad
## and dynamically modulates opacity with suspension travel and jump clearance.

enum ShadowMode {
	DECAL = 0,
	QUAD = 1,
	BOTH = 2,
}

@export var shadow_mode: ShadowMode = ShadowMode.DECAL
@export var base_opacity: float = 0.85
@export var resting_ground_clearance: float = 0.34
@export var max_airborne_fade_distance: float = 0.60
@export var shadow_size: Vector3 = Vector3(2.4, 2.4, 4.8)
@export var ray_length: float = 3.5
@export var ground_collision_mask: int = 1
@export var quad_offset_y: float = 0.02
@export var smooth_speed: float = 16.0
@export var texture_resolution: Vector2i = Vector2i(256, 512)

static var _cached_texture: ImageTexture = null

var _decal: Decal = null
var _quad: MeshInstance3D = null
var _quad_mat: StandardMaterial3D = null
var _raycast: RayCast3D = null
var _vehicle_parent: Node3D = null

var _current_opacity: float = 0.85
var _is_setup: bool = false


func _ready() -> void:
	_init_components()


## Procedurally generates a smooth oval chassis footprint gradient ImageTexture:
## Pitch-black #000000 core under floorpan/wheelbase with feathered exponential falloff to alpha 0.0.
static func generate_shadow_texture(width: int = 256, height: int = 512) -> ImageTexture:
	if _cached_texture != null and _cached_texture.get_width() == width and _cached_texture.get_height() == height:
		return _cached_texture

	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var inv_w := 2.0 / float(width)
	var inv_h := 2.0 / float(height)

	# Chassis footprint normalized UV coordinates [-1.0, 1.0]:
	# Core floorpan where ambient light is 100% occluded under chassis center
	var core_x := 0.36
	var core_y := 0.46
	var edge_x := 0.86
	var edge_y := 0.94

	for y in range(height):
		var v := (float(y) + 0.5) * inv_h - 1.0 # -1.0 to 1.0 along length
		var abs_v := absf(v)
		for x in range(width):
			var u := (float(x) + 0.5) * inv_w - 1.0 # -1.0 to 1.0 along width
			var abs_u := absf(u)

			# Distance from rounded core rectangle
			var dx := maxf(abs_u - core_x, 0.0) / maxf(edge_x - core_x, 0.001)
			var dy := maxf(abs_v - core_y, 0.0) / maxf(edge_y - core_y, 0.001)
			var d := sqrt(dx * dx + dy * dy)

			var alpha: float = 0.0
			if d <= 0.0:
				alpha = 1.0
			elif d < 1.0:
				var fade := 1.0 - d
				# Smoothstep feathered decay
				var s := fade * fade * (3.0 - 2.0 * fade)
				# Exponential ambient occlusion decay
				alpha = s * exp(-1.75 * d)
			else:
				alpha = 0.0

			# Pitch-black #000000 core with feathered alpha
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, clampf(alpha, 0.0, 1.0)))

	img.generate_mipmaps()
	_cached_texture = ImageTexture.create_from_image(img)
	return _cached_texture


func _init_components() -> void:
	if _is_setup:
		return
	_is_setup = true

	_vehicle_parent = get_parent() as Node3D

	var tex := generate_shadow_texture(texture_resolution.x, texture_resolution.y)

	# 1. Decal component (Downward-projecting onto road deck)
	_decal = get_node_or_null("ShadowDecal") as Decal
	if _decal == null:
		_decal = Decal.new()
		_decal.name = "ShadowDecal"
		add_child(_decal)

	_decal.size = shadow_size
	_decal.texture_albedo = tex
	_decal.modulate = Color(1.0, 1.0, 1.0, base_opacity)
	_decal.upper_fade = 0.35
	_decal.lower_fade = 0.25
	_decal.normal_fade = 0.45
	_decal.cull_mask = ground_collision_mask
	_decal.visible = (shadow_mode == ShadowMode.DECAL or shadow_mode == ShadowMode.BOTH)

	# 2. Downward raycast for ground clearance tracking
	_raycast = get_node_or_null("GroundRayCast") as RayCast3D
	if _raycast == null:
		_raycast = RayCast3D.new()
		_raycast.name = "GroundRayCast"
		add_child(_raycast)

	_raycast.position = Vector3(0.0, 0.35, 0.0)
	_raycast.target_position = Vector3(0.0, -ray_length, 0.0)
	_raycast.collision_mask = ground_collision_mask
	_raycast.hit_from_inside = true
	_raycast.exclude_parent = true
	_raycast.enabled = true

	# 3. Optional unshaded soft-alpha quad (0.02m above road deck)
	_quad = get_node_or_null("ShadowQuad") as MeshInstance3D
	if _quad == null:
		_quad = MeshInstance3D.new()
		_quad.name = "ShadowQuad"
		var quad_mesh := QuadMesh.new()
		quad_mesh.size = Vector2(shadow_size.x, shadow_size.z)
		quad_mesh.orientation = PlaneMesh.FACE_Y
		_quad.mesh = quad_mesh
		add_child(_quad)

	_quad_mat = StandardMaterial3D.new()
	_quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_quad_mat.albedo_texture = tex
	_quad_mat.albedo_color = Color(1.0, 1.0, 1.0, base_opacity)
	_quad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad.material_override = _quad_mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.top_level = true
	_quad.visible = (shadow_mode == ShadowMode.QUAD or shadow_mode == ShadowMode.BOTH)


func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return

	var target_opacity := 0.0
	var hit_pos := Vector3.ZERO
	var hit_norm := Vector3.UP
	var has_hit := false

	if _raycast != null and _raycast.is_colliding():
		hit_pos = _raycast.get_collision_point()
		hit_norm = _raycast.get_collision_normal()
		has_hit = true

		var current_clearance := global_position.y - hit_pos.y
		var airborne_distance := maxf(0.0, current_clearance - resting_ground_clearance)

		if airborne_distance <= 0.001:
			target_opacity = base_opacity
		elif airborne_distance < max_airborne_fade_distance:
			# Fade from base_opacity down to 0.0 when airborne > max_airborne_fade_distance (0.6m)
			var fade_ratio := 1.0 - (airborne_distance / max_airborne_fade_distance)
			target_opacity = base_opacity * (fade_ratio * fade_ratio)
		else:
			target_opacity = 0.0

		# Check if vehicle has wheels and all are airborne
		if _vehicle_parent != null:
			var all_airborne := true
			for child in _vehicle_parent.get_children():
				if child.has_method("is_grounded"):
					if child.call("is_grounded"):
						all_airborne = false
						break
				elif "grounded" in child:
					if child.get("grounded"):
						all_airborne = false
						break
			if all_airborne and airborne_distance > 0.08:
				target_opacity *= 0.4
	else:
		target_opacity = 0.0

	# Smoothly transition opacity to eliminate abrupt pops on suspension rebound
	_current_opacity = lerpf(_current_opacity, target_opacity, clampf(delta * smooth_speed, 0.0, 1.0))

	# Update Decal
	if _decal != null:
		var show_decal := (shadow_mode == ShadowMode.DECAL or shadow_mode == ShadowMode.BOTH) and (_current_opacity > 0.01)
		_decal.visible = show_decal
		if show_decal:
			_decal.modulate = Color(1.0, 1.0, 1.0, _current_opacity)

	# Update Quad (if enabled)
	if _quad != null:
		var show_quad := (shadow_mode == ShadowMode.QUAD or shadow_mode == ShadowMode.BOTH) and (_current_opacity > 0.01) and has_hit
		_quad.visible = show_quad
		if show_quad:
			if _quad_mat != null:
				_quad_mat.albedo_color = Color(1.0, 1.0, 1.0, _current_opacity)
			_quad.global_position = hit_pos + hit_norm * quad_offset_y

			# Align quad planar surface to ground normal and chassis forward direction
			var forward := -global_basis.z
			var normal := hit_norm
			var right := forward.cross(normal).normalized()
			if right.length_squared() > 0.001:
				forward = normal.cross(right).normalized()
				_quad.global_basis = Basis(right, normal, -forward)
