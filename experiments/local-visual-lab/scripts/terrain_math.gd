class_name TerrainMath
extends RefCounted

## Deterministic spatial math for Aster Valley Local Visual Lab.
## Coordinate system: Godot +Y up, +X east, +Z south, 1 unit = 1 meter.

const WATER_Y: float = 0.0
const WORLD_HALF_EXTENT: float = 210.0
const ROAD_Z_MIN: float = -195.0
const ROAD_Z_MAX: float = 195.0
const ROAD_HALF_WIDTH: float = 4.2      # 8.4 m paved width (two 3.5 m lanes + paved edges)
const SHOULDER_HALF_WIDTH: float = 6.2  # +2.0 m gravel verge each side
const GRADE_BLEND_WIDTH: float = 18.0   # Embankment / cut-slope blend width

# Scenic overlook turnout pocket on the east (lakeside) edge of the road near z = -18
const OVERLOOK_Z: float = -18.0
const OVERLOOK_Z_HALF: float = 13.0
const OVERLOOK_EXTRA_EAST: float = 6.5

var _noise_macro: FastNoiseLite
var _noise_ridge: FastNoiseLite
var _noise_detail: FastNoiseLite
var _noise_far: FastNoiseLite

# Pre-sampled road polyline for fast closest-point queries
var road_samples: PackedVector3Array = PackedVector3Array()
var road_tangents: PackedVector3Array = PackedVector3Array()
var road_rights: PackedVector3Array = PackedVector3Array()
var road_dists: PackedFloat32Array = PackedFloat32Array()
var total_road_length: float = 0.0


func _init() -> void:
	_noise_macro = FastNoiseLite.new()
	_noise_macro.seed = 40721
	_noise_macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_macro.frequency = 0.0055
	_noise_macro.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_macro.fractal_octaves = 4
	_noise_macro.fractal_gain = 0.48

	_noise_ridge = FastNoiseLite.new()
	_noise_ridge.seed = 91823
	_noise_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_ridge.frequency = 0.0085
	_noise_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise_ridge.fractal_octaves = 4
	_noise_ridge.fractal_gain = 0.52

	_noise_detail = FastNoiseLite.new()
	_noise_detail.seed = 13377
	_noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_detail.frequency = 0.038
	_noise_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_detail.fractal_octaves = 3
	_noise_detail.fractal_gain = 0.45

	_noise_far = FastNoiseLite.new()
	_noise_far.seed = 77211
	_noise_far.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_far.frequency = 0.0022
	_noise_far.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise_far.fractal_octaves = 5
	_noise_far.fractal_gain = 0.54

	_build_road_samples(260)


func road_center_x(z: float) -> float:
	return -14.0 + 26.0 * sin(z * 0.0175) + 11.0 * cos(z * 0.030 - 0.55)


func road_center_y(z: float) -> float:
	var crest: float = 8.4 * exp(-pow((z + 18.0) / 88.0, 2.0))
	var undulation: float = -2.0 * sin(z * 0.0145) + 0.9 * cos(z * 0.032)
	return 9.8 + crest + undulation


func road_point(z: float) -> Vector3:
	return Vector3(road_center_x(z), road_center_y(z), z)


func road_tangent(z: float) -> Vector3:
	var eps: float = 0.25
	var p0: Vector3 = road_point(z - eps)
	var p1: Vector3 = road_point(z + eps)
	return (p1 - p0).normalized()


func road_right(z: float) -> Vector3:
	var t: Vector3 = road_tangent(z)
	# Cross tangent (pointing +Z) with UP gives +X (east) when moving south (+Z)
	var r: Vector3 = Vector3(t.z, 0.0, -t.x)
	if r.length_squared() < 1e-6:
		return Vector3.RIGHT
	return r.normalized()


func _build_road_samples(count: int) -> void:
	road_samples.resize(count)
	road_tangents.resize(count)
	road_rights.resize(count)
	road_dists.resize(count)
	var accum: float = 0.0
	for i in range(count):
		var u: float = float(i) / float(count - 1)
		var z: float = lerpf(ROAD_Z_MIN, ROAD_Z_MAX, u)
		var p: Vector3 = road_point(z)
		road_samples[i] = p
		road_tangents[i] = road_tangent(z)
		road_rights[i] = road_right(z)
		if i > 0:
			accum += p.distance_to(road_samples[i - 1])
		road_dists[i] = accum
	total_road_length = accum


## Returns Dictionary: { "dist": float, "signed_x": float, "road_y": float, "z": float, "point": Vector3 }
func query_road_proximity(x: float, z: float) -> Dictionary:
	# Fast local search around approximate z index
	var n: int = road_samples.size()
	var z_norm: float = clampf((z - ROAD_Z_MIN) / (ROAD_Z_MAX - ROAD_Z_MIN), 0.0, 1.0)
	var approx_idx: int = int(round(z_norm * float(n - 1)))
	var start_idx: int = maxi(0, approx_idx - 22)
	var end_idx: int = mini(n - 1, approx_idx + 22)

	var best_d2: float = 1e20
	var best_idx: int = approx_idx
	for i in range(start_idx, end_idx + 1):
		var sp: Vector3 = road_samples[i]
		var dx: float = x - sp.x
		var dz: float = z - sp.z
		var d2: float = dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_idx = i

	# Refine along segment around best_idx
	var p_best: Vector3 = road_samples[best_idx]
	var r_best: Vector3 = road_rights[best_idx]
	var t_best: Vector3 = road_tangents[best_idx]
	var rel: Vector3 = Vector3(x - p_best.x, 0.0, z - p_best.z)
	var along: float = rel.dot(Vector3(t_best.x, 0.0, t_best.z).normalized())
	var refined_z: float = clampf(p_best.z + t_best.z * along, ROAD_Z_MIN, ROAD_Z_MAX)
	var rp: Vector3 = road_point(refined_z)
	var rr: Vector3 = road_right(refined_z)
	var delta_xz: Vector2 = Vector2(x - rp.x, z - rp.z)
	var dist: float = delta_xz.length()
	var signed_x: float = (x - rp.x) * rr.x + (z - rp.z) * rr.z

	return {
		"dist": dist,
		"signed_x": signed_x,
		"road_y": rp.y,
		"z": refined_z,
		"point": rp,
	}


func get_overlook_extra_width(z: float) -> float:
	var dz: float = absf(z - OVERLOOK_Z)
	if dz >= OVERLOOK_Z_HALF + 8.0:
		return 0.0
	var t: float = clampf(1.0 - (dz - OVERLOOK_Z_HALF * 0.55) / (OVERLOOK_Z_HALF * 0.45 + 8.0), 0.0, 1.0)
	return OVERLOOK_EXTRA_EAST * (t * t * (3.0 - 2.0 * t))


func get_raw_terrain_height(x: float, z: float) -> float:
	var rx: float = road_center_x(clampf(z, ROAD_Z_MIN, ROAD_Z_MAX))
	var rel_x: float = x - rx

	var n_macro: float = _noise_macro.get_noise_2d(x, z)
	var n_ridge: float = _noise_ridge.get_noise_2d(x, z)
	var n_detail: float = _noise_detail.get_noise_2d(x, z)

	var h: float = 0.0
	if rel_x < 0.0:
		# West side: forested cedar ridge climbing naturally into scenic alpine slopes
		var climb: float = -rel_x
		var slope_base: float = pow(climb * 0.042, 1.24) * 11.5
		var ridge_contrib: float = (0.5 + 0.5 * n_ridge) * smoothstep(14.0, 110.0, climb) * 26.0
		var roll: float = n_macro * 8.5 + n_detail * 1.2
		h = 11.5 + slope_base + ridge_contrib + roll
	else:
		# East side: gentle embankment down into Eastwater Lake, then opposite forested peninsula
		var lake_center_x: float = rx + 92.0 + 18.0 * sin(z * 0.015 + 0.9)
		var dist_from_lake_center: float = absf(x - lake_center_x)
		var lake_half_width: float = 68.0 + 14.0 * sin(z * 0.022)
		var shore_t: float = smoothstep(8.0, 44.0, rel_x)
		var far_shore_t: float = smoothstep(lake_half_width - 18.0, lake_half_width + 55.0, x - (rx + 42.0))

		var near_slope: float = lerpf(10.5, -10.5, shore_t)
		var far_peninsula: float = far_shore_t * (36.0 + 22.0 * (0.5 + 0.5 * n_ridge))
		var lake_bed_mod: float = -2.2 * exp(-pow(dist_from_lake_center / 36.0, 2.0))
		h = near_slope + far_peninsula + lake_bed_mod + n_macro * 5.2 + n_detail * 0.85

	return h


func get_height(x: float, z: float) -> float:
	var raw_h: float = get_raw_terrain_height(x, z)
	var prox: Dictionary = query_road_proximity(x, z)
	var dist: float = prox["dist"]
	var signed_x: float = prox["signed_x"]
	var road_y: float = prox["road_y"]
	var rz: float = prox["z"]

	# Account for the scenic overlook pullout pocket on the east side
	var eff_shoulder: float = SHOULDER_HALF_WIDTH
	if signed_x > 0.0:
		eff_shoulder += get_overlook_extra_width(rz)

	# Keep terrain slightly below road mesh right under asphalt to avoid any z-fighting
	var target_h: float = road_y - 0.07
	if dist <= eff_shoulder:
		return target_h

	var blend_outer: float = eff_shoulder + GRADE_BLEND_WIDTH
	if dist >= blend_outer:
		return raw_h

	var t: float = (dist - eff_shoulder) / GRADE_BLEND_WIDTH
	var s: float = t * t * (3.0 - 2.0 * t)
	return lerpf(target_h, raw_h, s)


func get_normal(x: float, z: float, eps: float = 0.6) -> Vector3:
	var h_l: float = get_height(x - eps, z)
	var h_r: float = get_height(x + eps, z)
	var h_d: float = get_height(x, z - eps)
	var h_u: float = get_height(x, z + eps)
	return Vector3(h_l - h_r, 2.0 * eps, h_d - h_u).normalized()


func get_distant_mountain_height(x: float, z: float) -> float:
	var r: float = sqrt(x * x + z * z)
	var inner_fade: float = smoothstep(255.0, 640.0, r)
	var angle: float = atan2(z, x)
	# Wide scenic valley opening toward the east/northeast lake horizon so sky & layered ridges shine
	var lake_gap: float = 1.0 - 0.58 * exp(-pow(wrapf(angle - 0.15, -PI, PI) / 0.72, 2.0))
	var ridge: float = 0.5 + 0.5 * _noise_far.get_noise_2d(x, z)
	var macro: float = 0.5 + 0.5 * _noise_macro.get_noise_2d(x * 0.24, z * 0.24)
	var peaks: float = pow(ridge, 1.45) * 195.0 + macro * 62.0
	var base: float = lerpf(-12.0, 14.0 + peaks * lake_gap, inner_fade)
	return base


static func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
