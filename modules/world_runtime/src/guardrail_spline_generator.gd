class_name GuardrailSplineGenerator
extends Node3D

## =============================================================================
## Continuous Spline-Aligned Highway Guardrail Generator
## =============================================================================
## Features:
## - Samples road corridor centerlines and resamples along continuous splines.
## - Computes exact forward tangents and lateral vectors.
## - Offsets laterally by (half_road_width + shoulder_width) (e.g. 4.2m to 4.75m).
## - Aligns guardrail segments strictly PARALLEL to the road tangent (never
##   perpendicular or blocking the road).
## - Grounds steel posts via surface height queries (world_source) or physics
##   downward raycasts, embedding posts firmly into the terrain shoulder so they
##   never float above the ground.
## - Supports both continuous procedural W-beam mesh generation and modular
##   guardrail_4m.glb model instancing.
## - Generates static collision barriers (world_surface="barrier") for physics.
## =============================================================================

const MODEL_PATH := "res://assets/curated/models/environment/guardrail_4m.glb"

@export var half_road_width: float = 3.4
@export var shoulder_width: float = 1.35
@export var default_lateral_offset: float = 4.75 # half_road_width + shoulder_width
@export var rail_height_above_road: float = 0.72
@export var post_embed_depth: float = 0.45
@export var post_spacing: float = 2.0
@export var segment_step: float = 4.0
@export var generate_colliders: bool = true
@export_enum("continuous", "hazards", "outer_curves") var placement_mode: String = "hazards"
@export_enum("both", "left", "right") var side_selection: String = "both"
@export var hazard_drop_threshold: float = 0.65 # meters of drop on shoulder to trigger guardrail
@export var hazard_curve_radius_threshold: float = 95.0 # meters radius to trigger guardrail

var _steel_material: StandardMaterial3D
var _reflector_material: StandardMaterial3D
var _cached_model: PackedScene

func _init() -> void:
	_init_materials()

func _init_materials() -> void:
	# Galvanized weathered steel
	_steel_material = StandardMaterial3D.new()
	_steel_material.resource_name = "Guardrail/GalvanizedSteel"
	_steel_material.albedo_color = Color(0.68, 0.71, 0.73)
	_steel_material.metallic = 0.78
	_steel_material.roughness = 0.38
	_steel_material.cull_mode = BaseMaterial3D.CULL_BACK

	# Amber highway reflector
	_reflector_material = StandardMaterial3D.new()
	_reflector_material.resource_name = "Guardrail/AmberReflector"
	_reflector_material.albedo_color = Color(0.96, 0.68, 0.12)
	_reflector_material.roughness = 0.18
	_reflector_material.emission_enabled = true
	_reflector_material.emission = Color(0.96, 0.68, 0.12)
	_reflector_material.emission_energy_multiplier = 0.65

# -----------------------------------------------------------------------------
# Static Convenience API
# -----------------------------------------------------------------------------

## Generates spline-aligned guardrails for a single road corridor.
static func generate_guardrails(
	parent: Node3D,
	corridor_points: PackedVector3Array,
	road_half_width: float = 3.4,
	road_shoulder_width: float = 1.35,
	world_source: Variant = null,
	options: Dictionary = {}
) -> Node3D:
	var script: GDScript = load("res://modules/world_runtime/src/guardrail_spline_generator.gd") as GDScript
	var gen: Node3D = script.new() as Node3D
	gen.name = options.get("name", "Guardrails")
	gen.half_road_width = road_half_width
	gen.shoulder_width = road_shoulder_width
	gen.default_lateral_offset = options.get("lateral_offset", road_half_width + road_shoulder_width)
	gen.placement_mode = options.get("placement_mode", "hazards")
	gen.side_selection = options.get("side", "both")
	gen.generate_colliders = options.get("colliders", true)

	parent.add_child(gen)
	gen.build_corridor(corridor_points, world_source, options)
	return gen

## Generates guardrails for all physical road corridors in a WorldRuntime instance.
static func generate_all_corridors(
	parent: Node3D,
	world_runtime: Variant,
	options: Dictionary = {}
) -> Node3D:
	var root := Node3D.new()
	root.name = "AllGuardrails"
	parent.add_child(root)

	if world_runtime == null or not world_runtime.has_method("get_physical_road_centerlines"):
		return root

	var corridors: Array = world_runtime.get_physical_road_centerlines()
	for corr in corridors:
		if not corr is Dictionary:
			continue
		var points: PackedVector3Array = corr.get("points", PackedVector3Array())
		if points.size() < 2:
			continue
		var width_m: float = float(corr.get("width_m", 6.8))
		var half_w: float = width_m * 0.5
		var sub_opts := options.duplicate()
		sub_opts["name"] = "Guardrails_" + str(corr.get("id", "road"))
		generate_guardrails(root, points, half_w, 1.35, world_runtime, sub_opts)

	return root

# -----------------------------------------------------------------------------
# Spline Resampling & Station Math
# -----------------------------------------------------------------------------

class SplineStation:
	var position: Vector3
	var forward: Vector3
	var lateral: Vector3 # Unit vector perpendicular in XZ (+lateral = right side of road)
	var curvature: float = 0.0 # Radians per meter
	var arc_length: float = 0.0

## Resamples centerline points at uniform spacing `step_m` using Catmull-Rom interpolation.
func resample_corridor_spline(points: PackedVector3Array, step_m: float = 2.0) -> Array[SplineStation]:
	var stations: Array[SplineStation] = []
	var n := points.size()
	if n < 2:
		return stations

	# Compute cumulative arc length of input points
	var cum_dist := PackedFloat32Array()
	cum_dist.resize(n)
	cum_dist[0] = 0.0
	for i in range(1, n):
		cum_dist[i] = cum_dist[i - 1] + points[i].distance_to(points[i - 1])

	var total_length := cum_dist[n - 1]
	if total_length < 0.1:
		return stations

	var num_steps := int(ceil(total_length / step_m))
	var seg_idx := 0

	for step_idx in range(num_steps + 1):
		var target_s := minf(float(step_idx) * step_m, total_length)

		# Advance segment pointer
		while seg_idx < n - 2 and cum_dist[seg_idx + 1] < target_s:
			seg_idx += 1

		var s0 := cum_dist[seg_idx]
		var s1 := cum_dist[seg_idx + 1]
		var seg_len := maxf(s1 - s0, 0.001)
		var t := clampf((target_s - s0) / seg_len, 0.0, 1.0)

		# 4 control points for Catmull-Rom
		var p0: Vector3 = points[maxi(seg_idx - 1, 0)]
		var p1: Vector3 = points[seg_idx]
		var p2: Vector3 = points[seg_idx + 1]
		var p3: Vector3 = points[mini(seg_idx + 2, n - 1)]

		var pos := _catmull_rom(p0, p1, p2, p3, t)
		var vel := _catmull_rom_derivative(p0, p1, p2, p3, t)

		var fwd := vel.normalized()
		if fwd.length_squared() < 0.001:
			fwd = (p2 - p1).normalized()
		if fwd.length_squared() < 0.001:
			fwd = Vector3.FORWARD

		# Lateral vector: perpendicular to forward in the XZ plane
		# (fwd.x, fwd.z) rotated 90 deg clockwise -> (-fwd.z, 0, fwd.x)
		var fwd_2d := Vector2(fwd.x, fwd.z).normalized()
		var lat := Vector3(-fwd_2d.y, 0.0, fwd_2d.x).normalized()

		var st := SplineStation.new()
		st.position = pos
		st.forward = fwd
		st.lateral = lat
		st.arc_length = target_s
		stations.append(st)

	# Calculate local curvature
	for i in range(stations.size()):
		var prev_idx := maxi(0, i - 1)
		var next_idx := mini(stations.size() - 1, i + 1)
		if prev_idx != next_idx:
			var ds := stations[next_idx].arc_length - stations[prev_idx].arc_length
			if ds > 0.01:
				var angle := stations[prev_idx].forward.angle_to(stations[next_idx].forward)
				stations[i].curvature = angle / ds

	return stations

func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _catmull_rom_derivative(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	return 0.5 * (
		(-p0 + p2) +
		(4.0 * p0 - 10.0 * p1 + 8.0 * p2 - 2.0 * p3) * t +
		(-3.0 * p0 + 9.0 * p1 - 9.0 * p2 + 3.0 * p3) * t2
	)

# -----------------------------------------------------------------------------
# Terrain Grounding Query
# -----------------------------------------------------------------------------

## Queries the exact terrain height at (x, z) to firmly anchor guardrail posts.
## Uses world_source first, then physics raycasts, falling back to road elevation.
func query_ground_height(x: float, z: float, road_y: float, world_source: Variant = null) -> float:
	# 1. Query world_source directly (fastest and most accurate for terrain meshes)
	if world_source != null:
		if world_source.has_method("sample_surface_height"):
			var h: float = world_source.sample_surface_height(x, z)
			if not is_nan(h):
				return h
		if world_source.has_method("get_surface_height_at"):
			var h: float = world_source.get_surface_height_at(x, z)
			if not is_nan(h):
				return h
		if world_source.get("data") != null and world_source.data.has_method("sample_surface_height"):
			var h: float = world_source.data.sample_surface_height(x, z)
			if not is_nan(h):
				return h

	# 2. Query physics direct space state if inside the scene tree
	if is_inside_tree() and get_world_3d() != null:
		var space := get_world_3d().direct_space_state
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(x, road_y + 12.0, z),
				Vector3(x, road_y - 25.0, z)
			)
			query.collision_mask = 1 # Terrain and ground geometry
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				return hit.position.y

	# 3. Fallback: assume shoulder sloped slightly below road
	return road_y - 0.12

# -----------------------------------------------------------------------------
# Main Generation Logic
# -----------------------------------------------------------------------------

## Builds guardrails along the corridor points.
func build_corridor(points: PackedVector3Array, world_source: Variant = null, options: Dictionary = {}) -> void:
	if points.size() < 2:
		return

	var lateral_offset: float = options.get("lateral_offset", default_lateral_offset)
	var use_model: bool = options.get("use_model", false)
	var step_size: float = 4.0 if use_model else 2.0
	var stations := resample_corridor_spline(points, step_size)
	if stations.size() < 2:
		return

	var sides: Array[float] = []
	if side_selection == "both" or side_selection == "left":
		sides.append(-1.0) # Left side of road (-lateral)
	if side_selection == "both" or side_selection == "right":
		sides.append(1.0)  # Right side of road (+lateral)

	for side_sign in sides:
		var active_spans := _identify_guardrail_spans(stations, side_sign, lateral_offset, world_source)
		for span in active_spans:
			var start_i: int = span["start"]
			var end_i: int = span["end"]
			if end_i - start_i < 1:
				continue

			var span_stations: Array[SplineStation] = []
			for idx in range(start_i, end_i + 1):
				span_stations.append(stations[idx])

			if use_model and _can_load_model():
				_build_instanced_guardrail(span_stations, side_sign, lateral_offset, world_source)
			else:
				_build_procedural_w_beam_guardrail(span_stations, side_sign, lateral_offset, world_source)

## Identifies contiguous station spans that warrant guardrails based on hazards or settings.
func _identify_guardrail_spans(
	stations: Array[SplineStation],
	side_sign: float,
	lateral_offset: float,
	world_source: Variant
) -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	var n := stations.size()
	if n < 2:
		return spans

	if placement_mode == "continuous":
		spans.append({"start": 0, "end": n - 1})
		return spans

	var in_span := false
	var span_start := 0

	for i in range(n):
		var st := stations[i]
		var is_hazard := false

		if placement_mode == "outer_curves":
			# Guardrails on outer curves:
			# If curving left (curvature > 0), outer side is right (side_sign = 1.0)
			# If curving right (curvature < 0), outer side is left (side_sign = -1.0)
			is_hazard = (st.curvature * side_sign > 0.015)
		else: # "hazards"
			# Check 1: Steep drop-off / ravine along shoulder
			var sample_pos := st.position + st.lateral * (side_sign * (lateral_offset + 1.2))
			var ground_y := query_ground_height(sample_pos.x, sample_pos.z, st.position.y, world_source)
			var drop := st.position.y - ground_y
			if drop >= hazard_drop_threshold:
				is_hazard = true

			# Check 2: Sharp curve
			if not is_hazard and st.curvature > (1.0 / hazard_curve_radius_threshold):
				is_hazard = true

		if is_hazard:
			if not in_span:
				in_span = true
				span_start = maxi(0, i - 1) # Add 1 station lead-in
		else:
			if in_span:
				in_span = false
				var span_end := mini(n - 1, i + 1) # Add 1 station lead-out
				spans.append({"start": span_start, "end": span_end})

	if in_span:
		spans.append({"start": span_start, "end": n - 1})

	# Merge adjacent spans that are separated by small gaps (< 12 meters)
	var merged: Array[Dictionary] = []
	for span in spans:
		if merged.is_empty():
			merged.append(span)
			continue
		var prev: Dictionary = merged[merged.size() - 1]
		var gap := stations[span["start"]].arc_length - stations[prev["end"]].arc_length
		if gap <= 12.0:
			prev["end"] = span["end"]
		else:
			merged.append(span)

	return merged

# -----------------------------------------------------------------------------
# Procedural Continuous W-Beam Mesh Generation
# -----------------------------------------------------------------------------

## Generates a continuous, smooth corrugated W-beam guardrail with grounded steel posts.
func _build_procedural_w_beam_guardrail(
	stations: Array[SplineStation],
	side_sign: float,
	lateral_offset: float,
	world_source: Variant
) -> void:
	if stations.size() < 2:
		return

	var rail_st := SurfaceTool.new()
	rail_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	rail_st.set_material(_steel_material)

	var post_st := SurfaceTool.new()
	post_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	post_st.set_material(_steel_material)

	var reflector_st := SurfaceTool.new()
	reflector_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	reflector_st.set_material(_reflector_material)

	var collision_faces := PackedVector3Array()

	# W-beam cross section profile points (lateral, vertical) relative to rail center
	# Creates the characteristic two-convex wave profile of highway guardrails
	var profile: Array[Vector2] = [
		Vector2(0.045, 0.35),   # Top hem
		Vector2(-0.045, 0.22),  # Top peak
		Vector2(0.015, 0.0),    # Center valley
		Vector2(-0.045, -0.22), # Bottom peak
		Vector2(0.045, -0.35)   # Bottom hem
	]

	# Build rail ribbon rings at each station
	var rings: Array[Array] = []
	for st in stations:
		var center_pt := st.position + st.lateral * (side_sign * lateral_offset)
		var rail_center := center_pt + Vector3(0.0, rail_height_above_road, 0.0)

		# Forward is road tangent; Lateral points away from road on right side, towards road on left side.
		# Ensure the convex face points TOWARD the road (towards -side_sign * st.lateral)
		var out_normal := st.lateral * side_sign
		var ring: Array[Vector3] = []
		for p in profile:
			# p.x is depth away from road, p.y is vertical height
			var vert := rail_center + out_normal * p.x + Vector3(0.0, p.y, 0.0)
			ring.append(vert)
		rings.append(ring)

	# Connect rings with quads
	for i in range(rings.size() - 1):
		var ring_a: Array = rings[i]
		var ring_b: Array = rings[i + 1]
		var fwd := (stations[i + 1].position - stations[i].position).normalized()

		for k in range(ring_a.size() - 1):
			var a0 := ring_a[k] as Vector3
			var a1 := ring_a[k + 1] as Vector3
			var b0 := ring_b[k] as Vector3
			var b1 := ring_b[k + 1] as Vector3

			# Normal points towards traffic (-side_sign * lateral)
			var n := (a1 - a0).cross(b0 - a0).normalized()
			if n.dot(stations[i].lateral * side_sign) > 0.0:
				n = -n

			var u0 := float(k) / float(profile.size() - 1)
			var u1 := float(k + 1) / float(profile.size() - 1)
			var v0 := stations[i].arc_length * 0.5
			var v1 := stations[i + 1].arc_length * 0.5

			_add_quad_st(rail_st, a0, b0, a1, b1, n, u0, u1, v0, v1)

		# Add front collision face quad
		if generate_colliders:
			var top_a := ring_a[0] as Vector3
			var top_b := ring_b[0] as Vector3
			var bot_a := ring_a[ring_a.size() - 1] as Vector3
			var bot_b := ring_b[ring_b.size() - 1] as Vector3
			collision_faces.append_array([top_a, top_b, bot_a, top_b, bot_b, bot_a])

	# -------------------------------------------------------------------------
	# Grounded Steel Posts
	# -------------------------------------------------------------------------
	var post_dist_accum := 0.0
	for i in range(stations.size()):
		var st := stations[i]
		var post_spacing_m := maxf(post_spacing, 1.5)

		if i == 0 or i == stations.size() - 1 or post_dist_accum >= post_spacing_m:
			post_dist_accum = 0.0

			var post_pos := st.position + st.lateral * (side_sign * lateral_offset)
			# Post sits just behind the rail ribbon
			post_pos += st.lateral * (side_sign * 0.06)

			# Query surface height at post position
			var ground_y := query_ground_height(post_pos.x, post_pos.z, st.position.y, world_source)

			var post_top_y := st.position.y + rail_height_above_road + 0.12
			var post_bottom_y := minf(ground_y, st.position.y) - post_embed_depth

			var post_height := post_top_y - post_bottom_y
			if post_height > 0.2:
				var post_center := Vector3(post_pos.x, (post_top_y + post_bottom_y) * 0.5, post_pos.z)
				var post_size := Vector3(0.12, post_height, 0.14)
				_add_box_st(post_st, post_center, post_size, st.forward)

			# Add amber reflector on post every ~8m
			if i % 4 == 0:
				var refl_pos := post_pos - st.lateral * (side_sign * 0.065) + Vector3(0.0, rail_height_above_road, 0.0)
				_add_reflector_st(reflector_st, refl_pos, st.forward, st.lateral * side_sign)

		if i < stations.size() - 1:
			post_dist_accum += stations[i].position.distance_to(stations[i + 1].position)

	# -------------------------------------------------------------------------
	# Commit Meshes to Scene
	# -------------------------------------------------------------------------
	var rail_mesh := rail_st.commit()
	if rail_mesh != null and rail_mesh.get_surface_count() > 0:
		var rail_inst := MeshInstance3D.new()
		rail_inst.name = "RailRibbon"
		rail_inst.mesh = rail_mesh
		add_child(rail_inst)

	var post_mesh := post_st.commit()
	if post_mesh != null and post_mesh.get_surface_count() > 0:
		var post_inst := MeshInstance3D.new()
		post_inst.name = "GroundedPosts"
		post_inst.mesh = post_mesh
		add_child(post_inst)

	var refl_mesh := reflector_st.commit()
	if refl_mesh != null and refl_mesh.get_surface_count() > 0:
		var refl_inst := MeshInstance3D.new()
		refl_inst.name = "Reflectors"
		refl_inst.mesh = refl_mesh
		add_child(refl_inst)

	# -------------------------------------------------------------------------
	# Create StaticBody3D Barrier Collision
	# -------------------------------------------------------------------------
	if generate_colliders and not collision_faces.is_empty():
		var col_body := StaticBody3D.new()
		col_body.name = "GuardrailCollider"
		col_body.set_meta("world_surface", "barrier")

		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(collision_faces)

		var col_shape := CollisionShape3D.new()
		col_shape.shape = shape
		col_body.add_child(col_shape)
		add_child(col_body)

# -----------------------------------------------------------------------------
# Instanced 3D Model Guardrail (Strictly Parallel Alignment)
# -----------------------------------------------------------------------------

func _can_load_model() -> bool:
	if _cached_model != null:
		return true
	if ResourceLoader.exists(MODEL_PATH):
		_cached_model = ResourceLoader.load(MODEL_PATH) as PackedScene
		return _cached_model != null
	return false

## Builds guardrail using 4m modular mesh instances aligned strictly parallel to road tangent.
func _build_instanced_guardrail(
	stations: Array[SplineStation],
	side_sign: float,
	lateral_offset: float,
	world_source: Variant
) -> void:
	if _cached_model == null and not _can_load_model():
		return

	var n := stations.size()
	for i in range(n - 1):
		var st_a := stations[i]
		var st_b := stations[i + 1]

		var mid_pos := (st_a.position + st_b.position) * 0.5
		var fwd := (st_b.position - st_a.position).normalized()
		if fwd.length_squared() < 0.001:
			fwd = st_a.forward

		var fwd_2d := Vector2(fwd.x, fwd.z).normalized()
		var lat := Vector3(-fwd_2d.y, 0.0, fwd_2d.x).normalized()

		# Guardrail placement position: offset laterally by half_width + shoulder
		var inst_pos := mid_pos + lat * (side_sign * lateral_offset)

		# Ground query for post anchoring
		var ground_y := query_ground_height(inst_pos.x, inst_pos.z, mid_pos.y, world_source)
		inst_pos.y = ground_y

		# Compute strictly PARALLEL basis:
		# guardrail_4m.glb beam length is along local X (-2.04 to +2.04).
		# Local Y is UP.
		# Local Z is lateral.
		var basis_x: Vector3
		var basis_y: Vector3 = Vector3.UP
		var basis_z: Vector3

		if side_sign > 0.0:
			# Right side of road:
			# Forward along road tangent
			basis_x = fwd
			basis_z = basis_x.cross(basis_y).normalized() # Points right (away from road)
			# Reflector is on local -Z, which now faces left towards road traffic!
		else:
			# Left side of road:
			# Reverse tangent so beam extends along road, but local -Z faces right towards road traffic
			basis_x = -fwd
			basis_z = basis_x.cross(basis_y).normalized() # Points left (away from road)

		var inst_basis := Basis(basis_x, basis_y, basis_z).orthonormalized()
		var segment := _cached_model.instantiate() as Node3D
		if segment != null:
			segment.transform = Transform3D(inst_basis, inst_pos)
			add_child(segment)

# -----------------------------------------------------------------------------
# SurfaceTool Geometry Helpers
# -----------------------------------------------------------------------------

func _add_quad_st(
	st: SurfaceTool,
	a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3,
	norm: Vector3,
	u0: float, u1: float, v0: float, v1: float
) -> void:
	st.set_normal(norm)
	st.set_uv(Vector2(u0, v0))
	st.add_vertex(a0)

	st.set_normal(norm)
	st.set_uv(Vector2(u1, v0))
	st.add_vertex(a1)

	st.set_normal(norm)
	st.set_uv(Vector2(u0, v1))
	st.add_vertex(b0)

	st.set_normal(norm)
	st.set_uv(Vector2(u1, v0))
	st.add_vertex(a1)

	st.set_normal(norm)
	st.set_uv(Vector2(u1, v1))
	st.add_vertex(b1)

	st.set_normal(norm)
	st.set_uv(Vector2(u0, v1))
	st.add_vertex(b0)

func _add_box_st(st: SurfaceTool, center: Vector3, size: Vector3, forward: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5

	var fwd_2d := Vector2(forward.x, forward.z).normalized()
	var lat := Vector3(-fwd_2d.y, 0.0, fwd_2d.x).normalized()
	var fwd := Vector3(fwd_2d.x, 0.0, fwd_2d.y).normalized()
	var up := Vector3.UP

	var corners := [
		center - lat * hx - up * hy - fwd * hz, # 0: ---
		center + lat * hx - up * hy - fwd * hz, # 1: +--
		center + lat * hx + up * hy - fwd * hz, # 2: ++-
		center - lat * hx + up * hy - fwd * hz, # 3: -+-
		center - lat * hx - up * hy + fwd * hz, # 4: --+
		center + lat * hx - up * hy + fwd * hz, # 5: +-+
		center + lat * hx + up * hy + fwd * hz, # 6: +++
		center - lat * hx + up * hy + fwd * hz  # 7: -++
	]

	# 4 vertical sides for the post (front, back, left, right)
	_add_quad_st(st, corners[0], corners[1], corners[3], corners[2], -fwd, 0, 1, 0, 1)
	_add_quad_st(st, corners[5], corners[4], corners[6], corners[7], fwd, 0, 1, 0, 1)
	_add_quad_st(st, corners[4], corners[0], corners[7], corners[3], -lat, 0, 1, 0, 1)
	_add_quad_st(st, corners[1], corners[5], corners[2], corners[6], lat, 0, 1, 0, 1)

func _add_reflector_st(st: SurfaceTool, center: Vector3, forward: Vector3, out_normal: Vector3) -> void:
	var fwd := forward.normalized() * 0.08
	var up := Vector3.UP * 0.04
	var norm := -out_normal.normalized()

	var p0 := center - fwd - up
	var p1 := center + fwd - up
	var p2 := center - fwd + up
	var p3 := center + fwd + up

	_add_quad_st(st, p0, p1, p2, p3, norm, 0, 1, 0, 1)
