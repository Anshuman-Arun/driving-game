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
		printerr("[WORLD SMOKE] FAILED: " + world.error_message)
		quit(1)
		return
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
		world.report["physical_corridors"] + world.report["junction_pads"]):
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
	var ray_queries := 0
	var ray_hits := 0
	for lane in model.lanes.values():
		if not String(lane["id"]).begins_with("turn_alder_"):
			continue
		var points: Array = lane["points"]
		var pick: Array = points[int(points.size() / 2)]
		var x: float = float(pick[0])
		var z: float = float(pick[2])
		var y: float = model.sample_surface_height(x, z)
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(x, y + 15.0, z), Vector3(x, y - 5.0, z))
		var hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(query)
		ray_queries += 1
		if not hit.is_empty() and String(hit["collider"].name).begins_with("Junction_"):
			ray_hits += 1
	if ray_queries == 0 or ray_hits != ray_queries:
		_fail("Junction collision coverage failed: %d / %d rays on pads." % [ray_hits, ray_queries])
		return
	# At least one unambiguous physical road deck must be hit, away from the pads.
	var physical_rays := 0
	var physical_hits := 0
	for corridor in travel:
		if corridor["id"] != "alder_cedar":
			continue
		var p: Vector3 = corridor["points"][mini(50, corridor["points"].size() - 2)]
		var road_query := PhysicsRayQueryParameters3D.create(
			p + Vector3.UP * 15.0, p - Vector3.UP * 5.0)
		var road_hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(road_query)
		physical_rays += 1
		if not road_hit.is_empty() and String(road_hit["collider"].name) == "Road_alder_cedar_Collision":
			physical_hits += 1
	if physical_rays != 1 or physical_hits != physical_rays:
		_fail("Physical road collision ray failed: %d / %d." % [physical_hits, physical_rays])
		return
	if world.report["full_world"]:
		if world.report["turn_paths_covered"] != int(model.metadata["roads"]["junction_connector_count"]):
			_fail("Full-world run omitted connector path coverage.")
			return
		if world.report["junction_pads"] != 11:
			_fail("Full-world run omitted one or more of the 11 real junction pads.")
			return
	print("[WORLD SMOKE] PASS | data sample count=", model.height_samples.size(),
		" | colliders=", world.report["static_colliders"],
		" | junction ray hits=", ray_hits, "/", ray_queries,
		" | generation_ms=", world.report["generation_ms"])
	quit(0)

func _fail(message: String) -> void:
	printerr("[WORLD SMOKE] FAILED: " + message)
	quit(1)
