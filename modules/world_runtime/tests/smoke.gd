extends SceneTree
## Run after staging World PR #3 data:
## godot --headless --path modules/world_runtime --script res://tests/smoke.gd
## Add -- --full-world for the complete 2 x 2 km mesh/collider sweep.

const WorldRuntime = preload("res://src/world_runtime.gd")
const EPSILON := 0.0005

func _initialize() -> void:
	call_deferred("_execute")

func _execute() -> void:
	var world := WorldRuntime.new()
	world.name = "SmokeWorld"
	world.build_on_ready = false
	world.preview_center_xz = Vector2(-620.0, 560.0)
	world.preview_radius_m = 470.0
	world.generate_colliders = true
	root.add_child(world)
	if not world.build_world():
		_fail(world.error_message)
		return
	var first_report: Dictionary = world.report.duplicate(true)
	var model = world.data
	if model.grid_width != 501 or model.grid_height != 501:
		_fail("Expected authoritative 501 x 501 raster.")
		return
	if world.report["terrain_chunks"] < 2:
		_fail("No independent terrain chunks created.")
		return
	if world.report["physical_corridors"] < 1:
		_fail("No physical road surfaces generated.")
		return
	if world.report["junction_pads"] < 1:
		_fail("No junction pads generated.")
		return
	if world.report["static_colliders"] != (world.report["terrain_chunks"] +
		world.report["physical_corridors"] + world.report["junction_pads"] +
		int(world.report.get("shoulder_colliders", 0))):
		_fail("Each generated mesh must have an independent collider.")
		return
	for ix in [0, 32, 64, 200, 500]:
		for iz in [0, 32, 64, 200, 500]:
			var x: float = model.origin_x + ix * model.spacing_m
			var z: float = model.origin_z + iz * model.spacing_m
			if absf(model.height_index(ix, iz) - model.sample_surface_height(x, z)) > EPSILON:
				_fail("Triangle interpolation differs at a raster vertex.")
				return
	var all_lanes: Dictionary = world.get_road_graph()
	if all_lanes.get("schema_version") != 1:
		_fail("The exported directed road graph was altered.")
		return
	if all_lanes.get("lanes", []).size() != 104:
		_fail("Expected 104 directed lanes in untouched road graph.")
		return
	var travel: Array[Dictionary] = world.get_physical_road_centerlines()
	if travel.size() != int(model.metadata["roads"]["unique_corridor_count"]):
		_fail("Paired travel lanes were duplicated or dropped.")
		return
	for corridor in travel:
		if corridor["points"].size() < 2:
			_fail("Invalid physical road centerline for " + corridor["id"])
			return
		if not is_equal_approx(float(corridor["width_m"]), 6.8):
			_fail("Physical road width differs from the graph.")
			return
	var image: Image = world.create_height_image_rf()
	if image == null or image.get_format() != Image.FORMAT_RF or image.get_width() != model.grid_width:
		_fail("Terrain3D float-image adapter failed.")
		return

	# Validate collision coverage *in the physics engine*, not just point-in-polygon.
	await physics_frame
	await process_frame
	var space := root.get_world_3d().direct_space_state
	var is_full: bool = bool(world.report["full_world"])

	# 1. Verify junction pad collision, upward normals, and traversability.
	var ray_queries := 0
	var ray_hits := 0
	var turn_samples_checked := 0
	for lane in model.lanes.values():
		var lid := String(lane["id"])
		if is_full:
			if not lid.begins_with("turn_"):
				continue
		else:
			if not lid.begins_with("turn_alder_"):
				continue
		var points: Array = lane["points"]
		var sample_indices: Array[int] = [0, int(points.size() / 2), points.size() - 1]
		var prev_hit_y := NAN
		for idx in sample_indices:
			var pick: Array = points[idx]
			var x: float = float(pick[0])
			var z: float = float(pick[2])
			var surf_y: float = model.sample_surface_height(x, z)
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(x, surf_y + 15.0, z), Vector3(x, surf_y - 5.0, z))
			var hit: Dictionary = space.intersect_ray(query)
			turn_samples_checked += 1
			if hit.is_empty():
				_fail("Missing collision on turn lane %s at index %d." % [lid, idx])
				return
			var cname := String(hit["collider"].name)
			var normal: Vector3 = hit["normal"]
			if normal.y < 0.80:
				_fail("Non-drivable normal %.3f on turn lane %s (%s)." % [normal.y, lid, cname])
				return
			if idx == int(points.size() / 2):
				ray_queries += 1
				if cname.begins_with("Junction_"):
					ray_hits += 1
			if not cname.begins_with("Junction_") and not cname.begins_with("Road_"):
				_fail("Turn lane %s fell through to %s at index %d." % [lid, cname, idx])
				return
			var hy: float = hit["position"].y
			var lift: float = hy - surf_y
			if lift < 0.04 or lift > 0.20:
				_fail("Turn lane %s height alignment out of range (lift=%.4f m) at %s." % [lid, lift, cname])
				return
			if is_finite(prev_hit_y) and absf(hy - prev_hit_y) > 4.0:
				_fail("Abrupt vertical jump on turn lane %s." % lid)
				return
			prev_hit_y = hy
	if ray_queries == 0 or ray_hits != ray_queries:
		_fail("Junction collision coverage failed: %d / %d rays on pads." % [ray_hits, ray_queries])
		return

	# 2. Verify physical road deck collision and terrain-road alignment.
	var physical_rays := 0
	var physical_hits := 0
	for corridor in travel:
		var cid: String = corridor["id"]
		if not is_full and cid != "alder_cedar":
			continue
		var pts: PackedVector3Array = corridor["points"]
		var half_w: float = float(corridor["width_m"]) * 0.5
		var stride_step: int = 8 if is_full else 10
		for i in range(1, pts.size() - 1, stride_step):
			var p: Vector3 = pts[i]
			if not is_full and Vector2(p.x, p.z).distance_to(world.preview_center_xz) > world.preview_radius_m - 20.0:
				continue
			var prev_p: Vector3 = pts[i - 1]
			var next_p: Vector3 = pts[i + 1]
			var tan2 := Vector2(next_p.x - prev_p.x, next_p.z - prev_p.z).normalized()
			var lat2 := Vector2(-tan2.y, tan2.x)
			for lat_off in [-half_w + 0.4, 0.0, half_w - 0.4]:
				var lo: float = float(lat_off)
				var rx: float = p.x + lat2.x * lo
				var rz: float = p.z + lat2.y * lo
				var surf_y: float = model.sample_surface_height(rx, rz)
				var road_query := PhysicsRayQueryParameters3D.create(
					Vector3(rx, surf_y + 15.0, rz), Vector3(rx, surf_y - 5.0, rz))
				var road_hit: Dictionary = space.intersect_ray(road_query)
				physical_rays += 1
				if road_hit.is_empty():
					_fail("Missing collision on corridor %s at sample %d." % [cid, i])
					return
				var cname := String(road_hit["collider"].name)
				if cname.begins_with("Road_") or cname.begins_with("Junction_"):
					physical_hits += 1
				else:
					_fail("Terrain poked through corridor %s at sample %d (hit %s)." % [cid, i, cname])
					return
				var dy: float = road_hit["position"].y - surf_y
				if dy < 0.05 or dy > 0.20:
					_fail("Road-terrain height misalignment %.4f m on %s." % [dy, cid])
					return
				if road_hit["normal"].y < 0.80:
					_fail("Steep/inverted road normal on %s." % cid)
					return
	if physical_rays == 0 or physical_hits != physical_rays:
		_fail("Physical road collision ray failed: %d / %d." % [physical_hits, physical_rays])
		return

	# 3. Verify terrain chunk-seam collision continuity (no cracks along 128 m chunk edges).
	var seam_checks := 0
	var seam_coords: Array = [32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448]
	for ix in seam_coords:
		for iz in seam_coords:
			var sx: float = model.origin_x + ix * model.spacing_m
			var sz: float = model.origin_z + iz * model.spacing_m
			if not is_full and Vector2(sx, sz).distance_to(world.preview_center_xz) > world.preview_radius_m - 30.0:
				continue
			var expected_y: float = model.sample_surface_height(sx, sz)
			var sq := PhysicsRayQueryParameters3D.create(
				Vector3(sx, expected_y + 20.0, sz), Vector3(sx, expected_y - 10.0, sz))
			var shit: Dictionary = space.intersect_ray(sq)
			if shit.is_empty():
				_fail("Terrain chunk seam crack (ray miss) at grid (%d, %d)." % [ix, iz])
				return
			var cname := String(shit["collider"].name)
			if cname.begins_with("Terrain_") and absf(shit["position"].y - expected_y) > 0.01:
				_fail("Terrain seam height mismatch %.4f m at (%d, %d)." % [shit["position"].y - expected_y, ix, iz])
				return
			seam_checks += 1
	if seam_checks == 0:
		_fail("No terrain chunk seams were tested.")
		return

	if is_full:
		if world.report["physical_corridors"] != 16:
			_fail("Full-world run expected 16 physical corridors, got %d." % world.report["physical_corridors"])
			return
		if world.report["turn_paths_covered"] != int(model.metadata["roads"]["junction_connector_count"]):
			_fail("Full-world run omitted connector path coverage.")
			return
		if world.report["junction_pads"] != 11:
			_fail("Full-world run omitted one or more of the 11 real junction pads.")
			return

	# 4. Determinism & clean rebuild check (no duplicated nodes/colliders).
	if not world.build_world():
		_fail("Rebuild failed: " + world.error_message)
		return
	var deterministic_keys := [
		"terrain_chunks", "terrain_vertices", "terrain_triangles",
		"physical_corridors", "road_vertices", "road_triangles",
		"junction_pads", "junction_vertices", "junction_triangles",
		"static_colliders", "turn_paths_covered"
	]
	for key in deterministic_keys:
		if first_report[key] != world.report[key]:
			_fail("Non-deterministic rebuild for %s: %s vs %s" % [key, str(first_report[key]), str(world.report[key])])
			return

	print("[WORLD SMOKE] PASS | mode=", ("full_world" if is_full else "preview"),
		" | data samples=", model.height_samples.size(),
		" | colliders=", world.report["static_colliders"],
		" | junction mid rays=", ray_hits, "/", ray_queries,
		" | turn samples=", turn_samples_checked,
		" | road rays=", physical_hits, "/", physical_rays,
		" | seam checks=", seam_checks,
		" | generation_ms=", first_report["generation_ms"])
	quit(0)

func _fail(message: String) -> void:
	printerr("[WORLD SMOKE] FAILED: " + message)
	quit(1)
