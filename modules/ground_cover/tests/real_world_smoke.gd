extends SceneTree
const Runtime = preload("res://modules/world_runtime/src/world_runtime.gd")
const Cover = preload("../ground_cover.gd")
const Grass = preload("../grass_mesh.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Runtime.new()
	world.build_on_ready = false
	world.generate_colliders = false
	# Reproduce live terrain/roadworks, not only the unmodified canonical raster.
	var works_file := FileAccess.open("res://data/world/roadworks.json",FileAccess.READ)
	if works_file == null:
		printerr("FAIL missing roadworks JSON")
		quit(1)
		return
	var works: Variant = JSON.parse_string(works_file.get_as_text())
	if not works is Dictionary or works.is_empty():
		printerr("FAIL invalid roadworks JSON")
		quit(1)
		return
	world.roadworks = works
	world.build_full_world = true
	root.add_child(world)
	if not world.build_world():
		printerr("FAIL real world build: ",world.error_message)
		quit(1)
		return
	var corridors: Array[Dictionary] = world.get_physical_road_centerlines()
	var p := Vector2(INF,INF)
	var best := INF
	for corridor: Dictionary in corridors:
		var points: PackedVector3Array = corridor.points
		for point: Vector3 in points:
			var xz := Vector2(point.x,point.z)
			var distance := xz.distance_squared_to(Vector2(-620,560))
			if distance < best:
				best = distance
				p = xz
	if not p.is_finite():
		printerr("FAIL no real corridor points")
		quit(1)
		return
	var cover := Cover.new()
	root.add_child(cover)
	var sampler := func(_x: float,_z: float) -> Vector4: return Vector4(1,0.2,0.5,0)
	var options := {"test_fixture":true,"capture_fixture":true,"fixture_sampler":sampler,"pilot_bounds":Rect2(p-Vector2.ONE*48,Vector2.ONE*96),"tuning":{"radii":[16,28,42],"density":[0.12,0.06,0.025],"cap":8000,"checks":800}}
	var mask_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mask="):
			mask_path = arg.trim_prefix("--mask=")
	# The fixture first proves the renderer's independent exact road rejection,
	# not just the ecological mask's road exclusions.
	if not cover.build(world,"medium","",options):
		printerr("FAIL cover build: ",cover.get_stats())
		quit(1)
		return
	cover.set_process(false)
	cover.update_focus(Vector3(p.x,world.get_surface_height_at(p.x,p.y)+2,p.y))
	for i in range(1200):
		cover._process(0.016)
		if cover.get_stats().queued_chunks == 0:
			break
	var stats: Dictionary = cover.get_stats()
	var failed: bool = stats.state != "ready" or stats.active_instances <= 0 or stats.queued_chunks != 0 or stats.active_instances > stats.cap or stats.rejected_candidates.road <= 0
	for key: Vector2i in cover._active:
		var entry: Dictionary = cover._active[key]
		for s in range(5):
			for pose: Dictionary in entry.fixture_groups[s]:
				var frame: Transform3D = pose.frame
				for lod in range(3):
					if world.road_clearance.overlaps(Grass.sweep_aabb(cover._mesh_bounds[s][lod],frame),0.12,true):
						failed = true
	print("[GroundCoverRealWorld] ",JSON.stringify(stats))
	# Optional production package (not needed for independent Wave 1 smoke).
	# No capture_fixture bypass: exercise actual manifest and source checks.
	if not mask_path.is_empty():
		options.erase("test_fixture")
		options.erase("capture_fixture")
		options.erase("fixture_sampler")
		if not cover.build(world,"medium",mask_path,options):
			printerr("FAIL production mask build: ",cover.get_stats())
			failed = true
		else:
			cover.set_process(false)
			cover.update_focus(Vector3(p.x,world.get_surface_height_at(p.x,p.y)+2,p.y))
			for i in range(1200):
				cover._process(0.016)
				if cover.get_stats().queued_chunks == 0:
					break
			var production: Dictionary = cover.get_stats()
			print("[GroundCoverProductionMask] ",JSON.stringify(production))
			if production.state != "ready" or production.queued_chunks != 0 or production.active_instances > production.cap:
				failed = true
	cover.shutdown()
	cover.free()
	world.free()
	if failed:
		printerr("FAIL real-world streaming or clearance")
	else:
		print("[GroundCoverRealWorld] PASS")
	quit(1 if failed else 0)
