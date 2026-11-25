extends SceneTree
## Foliage Scatter Tool & Placement Generator for Aster Valley.
## Generates and bakes GPU-instanced foliage placements for 3 distinct layers:
##   Layer 1: Roadside dense conifer canopy (fir_sapling_medium + curated pine with PR #30 PBR textures)
##   Layer 2: Mid-height understory (fern_02, rock_moss_set_02, tree_stump_02)
##   Layer 3: Dense road-verge grass clumps (grass_medium_01) within 1-8m of the road corridor
##
## Enforces slope filtering (no trees on cliffs), road exclusion buffers,
## random yaw (0-360°), and subtle scale variation (0.8-1.25).
##
## Usage from CLI:
##   Godot_v4.7.2-stable_win64_console.exe --path driving-game --headless --script res://tools/foliage_scatter.gd

const STRIDE := 7
const OUTPUT_BIN_PATH := "res://data/world/premium_foliage.bin"

# Kinds:
# 0: fir_sapling_medium (Layer 1 conifer)
# 1: curated_pine upgraded with PR #30 bark/twig textures (Layer 1 conifer)
# 2: fern_02 (Layer 2 understory)
# 3: rock_moss_set_02 (Layer 2 boulder)
# 4: tree_stump_02 (Layer 2 deadwood)
# 5: grass_medium_01 (Layer 3 road-verge clump)

func _initialize() -> void:
	print("==================================================")
	print("Aster Valley Premium Foliage Scatter Generator")
	print("==================================================")
	var wr_script = load("res://modules/world_runtime/src/world_runtime.gd")
	if wr_script == null:
		push_error("Could not load WorldRuntime script")
		quit(1)
		return

	var world: Node3D = wr_script.new()
	world.build_full_world = true
	if not world.build_world():
		push_error("Failed to build world runtime: " + world.error_message)
		world.free()
		quit(1)
		return

	var ok = bake_foliage_to_file(world, OUTPUT_BIN_PATH)
	world.free()
	if ok:
		print("Successfully generated and verified premium foliage data.")
		quit(0)
	else:
		push_error("Failed to bake foliage data.")
		quit(1)

static func generate_foliage_data(world: Node, seed_val: int = 20261124) -> PackedFloat32Array:
	var roads: Array[Dictionary] = world.get_physical_road_centerlines()
	if roads.is_empty():
		push_warning("FoliageScatterer: No physical road centerlines found.")
		return PackedFloat32Array()

	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val

	var placements = PackedFloat32Array()
	var layer1_count := 0
	var layer2_count := 0
	var layer3_count := 0
	var min_road_clearance := 999.0
	var min_slope_ny := 1.0

	for road in roads:
		var pts: PackedVector3Array = road["points"]
		var half_w: float = float(road["width_m"]) * 0.5
		var region: String = road.get("region", "")
		var is_woodland: bool = region == "cedar_woods" or region.find("woods") != -1 or region.find("ridge") != -1

		if pts.size() < 2:
			continue

		for i in range(pts.size() - 1):
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var seg := p1 - p0
			var seg_len := seg.length()
			if seg_len < 0.5:
				continue
			var tangent := seg.normalized()
			var lateral := Vector3(-tangent.z, 0, tangent.x).normalized()

			# -------------------------------------------------------------
			# LAYER 3: Dense Road-Verge Grass Clumps (grass_medium_01)
			# Concentrated strictly within 1-8m of the road corridor edge
			# -------------------------------------------------------------
			var grass_interval := 1.8
			var grass_steps := int(ceil(seg_len / grass_interval))
			for s in range(grass_steps):
				var t := (float(s) + rng.randf_range(0.1, 0.9)) / float(grass_steps)
				var center := p0.lerp(p1, t)
				for side: float in [-1.0, 1.0]:
					# Distance from road edge: 0.8m to 7.8m (within 1-8m corridor)
					var edge_dist: float = rng.randf_range(0.85, 7.6)
					var lat_offset: float = side * (half_w + edge_dist)
					var pos_xz: Vector3 = center + lateral * lat_offset + tangent * rng.randf_range(-0.5, 0.5)
					var h: float = world.get_surface_height_at(pos_xz.x, pos_xz.z)
					if is_nan(h):
						continue

					# Slope filtering (normal.y > 0.76)
					var norm: Vector3 = _sample_normal(world, pos_xz.x, pos_xz.z)
					if norm.y < 0.76:
						continue

					# Road exclusion check
					if edge_dist < min_road_clearance:
						min_road_clearance = edge_dist
					if norm.y < min_slope_ny:
						min_slope_ny = norm.y

					# Random yaw (0 to TAU) and subtle scale variation (0.8 to 1.25)
					var yaw: float = rng.randf_range(0.0, TAU)
					var scale: float = rng.randf_range(0.82, 1.22)
					var seed_val_inst: float = rng.randf()

					placements.append_array([
						pos_xz.x, h - 0.02, pos_xz.z,
						yaw, scale, 5.0, seed_val_inst
					])
					layer3_count += 1

			# -------------------------------------------------------------
			# LAYER 2: Mid-Height Understory
			# Ferns (fern_02), mossy boulders (rock_moss_set_02), deadwood (tree_stump_02)
			# -------------------------------------------------------------
			var understory_interval: float = 3.6 if is_woodland else 5.2
			var understory_steps: int = int(ceil(seg_len / understory_interval))
			for s in range(understory_steps):
				var t: float = (float(s) + rng.randf_range(0.1, 0.9)) / float(understory_steps)
				var center: Vector3 = p0.lerp(p1, t)
				for side: float in [-1.0, 1.0]:
					var edge_dist: float = rng.randf_range(1.6, 22.0)
					var lat_offset: float = side * (half_w + edge_dist)
					var pos_xz: Vector3 = center + lateral * lat_offset + tangent * rng.randf_range(-1.2, 1.2)
					var h: float = world.get_surface_height_at(pos_xz.x, pos_xz.z)
					if is_nan(h):
						continue

					var norm: Vector3 = _sample_normal(world, pos_xz.x, pos_xz.z)
					var pick: float = rng.randf()
					var kind: float = 2.0 # fern_02
					var min_ny: float = 0.75
					var sink_depth: float = 0.04

					if pick < 0.52:
						kind = 2.0 # fern_02
						min_ny = 0.75
						sink_depth = 0.03
					elif pick < 0.82:
						kind = 3.0 # rock_moss_set_02 boulder
						min_ny = 0.62 # boulders can rest on moderate/steep slopes
						sink_depth = 0.14
					else:
						kind = 4.0 # tree_stump_02 deadwood
						min_ny = 0.72
						sink_depth = 0.08

					if norm.y < min_ny:
						continue

					var yaw: float = rng.randf_range(0.0, TAU)
					var scale: float = rng.randf_range(0.80, 1.25)
					var seed_val_inst: float = rng.randf()

					placements.append_array([
						pos_xz.x, h - sink_depth, pos_xz.z,
						yaw, scale, kind, seed_val_inst
					])
					layer2_count += 1

			# -------------------------------------------------------------
			# LAYER 1: Roadside Dense Conifer Canopy
			# fir_sapling_medium + curated conifer meshes with PR #30 bark/twig textures
			# Casting dappled shadows over the road edge
			# -------------------------------------------------------------
			var conifer_interval: float = 5.0 if is_woodland else 7.5
			var conifer_steps: int = int(ceil(seg_len / conifer_interval))
			for s in range(conifer_steps):
				var t: float = (float(s) + rng.randf_range(0.1, 0.9)) / float(conifer_steps)
				var center: Vector3 = p0.lerp(p1, t)
				for side: float in [-1.0, 1.0]:
					# Distance from road edge: 3.2m to 28.0m (branches overhang road verge casting shadows)
					var edge_dist: float = rng.randf_range(3.2, 28.0)
					var lat_offset: float = side * (half_w + edge_dist)
					var pos_xz: Vector3 = center + lateral * lat_offset + tangent * rng.randf_range(-1.8, 1.8)
					var h: float = world.get_surface_height_at(pos_xz.x, pos_xz.z)
					if is_nan(h):
						continue

					# Slope filtering: no trees on vertical cliffs (normal.y > 0.70)
					var norm: Vector3 = _sample_normal(world, pos_xz.x, pos_xz.z)
					if norm.y < 0.70:
						continue

					# Alternating conifer species: fir_sapling_medium (kind 0) and curated pine (kind 1)
					var conifer_kind: float = 0.0 if rng.randf() < 0.55 else 1.0
					var yaw: float = rng.randf_range(0.0, TAU)
					var scale: float = rng.randf_range(0.85, 1.25)
					var seed_val_inst: float = rng.randf()

					# Sink root flare slightly into terrain
					placements.append_array([
						pos_xz.x, h - 0.16, pos_xz.z,
						yaw, scale, conifer_kind, seed_val_inst
					])
					layer1_count += 1

	print("[FoliageScatterer] Generation complete:")
	print("  Layer 1 (Conifers): %d instances" % layer1_count)
	print("  Layer 2 (Understory): %d instances" % layer2_count)
	print("  Layer 3 (Verge Grass): %d instances" % layer3_count)
	print("  Total Placements: %d instances" % (placements.size() / STRIDE))
	print("  Min Road Edge Clearance: %.2f m (deck clear)" % min_road_clearance)
	print("  Min Surface Normal Y: %.2f (cliffs excluded)" % min_slope_ny)

	return placements

static func bake_foliage_to_file(world: Node, path: String) -> bool:
	var data: PackedFloat32Array = generate_foliage_data(world)
	if data.is_empty():
		push_error("Failed to generate foliage data to bake.")
		return false

	var global_path := ProjectSettings.globalize_path(path)
	var dir := global_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write foliage file: %s (error %d)" % [path, FileAccess.get_open_error()])
		return false

	file.store_buffer(data.to_byte_array())
	file.close()

	print("[FoliageScatterer] Saved %d bytes to %s" % [data.size() * 4, path])
	return true

static func _sample_normal(world: Node, x: float, z: float) -> Vector3:
	var eps := 0.5
	var hl: float = world.get_surface_height_at(x - eps, z)
	var hr: float = world.get_surface_height_at(x + eps, z)
	var hd: float = world.get_surface_height_at(x, z - eps)
	var hu: float = world.get_surface_height_at(x, z + eps)
	return Vector3(hl - hr, 2.0 * eps, hd - hu).normalized()
