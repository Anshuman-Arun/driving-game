extends SceneTree
## Baseline runs a synthetic exact triangle clearance fixture; integrated exercises
## real world and dynamically discovered candidate scripts, no root wiring.
const Clearance = preload("res://modules/world_runtime/src/road_clearance.gd")
const World = preload("res://modules/world_runtime/src/world_runtime.gd")
const MASK := "res://content/scenery/environment_overhaul/masks"
const COVER := "res://modules/ground_cover/ground_cover.gd"
const TERRAIN := "res://modules/environment_terrain/terrain_preview.gd"
const RENDER := "res://modules/environment_rendering/render_profile.gd"
const FOCUS := [Vector3(-870,0,-154), Vector3(-850,0,-154), Vector3(-830,0,-154), Vector3(72,0,170)]
# Provisional independent safety ceilings, not tuned GPU targets.
const MAX_INSTANCES := 1500000
const MAX_BATCHES := 4096
const MAX_CHUNKS := 2048
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", message)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func triangle(mesh: ArrayMesh, a: Vector3, b: Vector3, c: Vector3) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a,b,c])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func fixture() -> void:
	var mesh := ArrayMesh.new()
	triangle(mesh, Vector3(0,10,0), Vector3(10,10,0), Vector3(0,10,10))
	triangle(mesh, Vector3(10,10,0), Vector3(15,10,0), Vector3(10,10,5))
	var index = Clearance.new()
	index.add_surface(mesh, 0, Transform3D.IDENTITY)
	index.add_surface(mesh, 1, Transform3D.IDENTITY)
	check(index.triangle_count == 2, "synthetic triangles registered")
	check(index.overlaps(AABB(Vector3(2,10,2), Vector3.ONE)), "deck rejected")
	check(not index.overlaps(AABB(Vector3(2,0,2), Vector3.ONE)), "below elevated deck allowed")
	check(not index.overlaps(AABB(Vector3(2,16,2), Vector3.ONE)), "above clearance allowed")
	check(index.overlaps(AABB(Vector3(12,10,1), Vector3.ONE)), "shoulder rejected")
	check(not index.overlaps(AABB(Vector3(12,10,1), Vector3.ONE), 0.0, false), "pavement-only mode")
	check(not index.overlaps(AABB(Vector3(8,10,8), Vector3.ONE)), "outside triangle not rejected")
	check(not index.overlaps(AABB(Vector3(-20,10,-20), Vector3.ONE)), "outside index")

func inspect_cover(cover: Node3D, world: Node, margin: float) -> Dictionary:
	var count := 0
	var batches := 0
	var invalid := 0
	var overlap := 0
	var positions := PackedStringArray()
	for node: MultiMeshInstance3D in cover.find_children("*", "MultiMeshInstance3D", true, false):
		var batch := node.multimesh
		if batch == null or batch.mesh == null:
			invalid += 1
			continue
		batches += 1
		var active := batch.instance_count if batch.visible_instance_count < 0 else batch.visible_instance_count
		count += batch.instance_count
		if count > MAX_INSTANCES or batches > MAX_BATCHES:
			break
		for i in active:
			var transform := node.global_transform * batch.get_instance_transform(i)
			if not transform.is_finite():
				invalid += 1
				continue
			var bounds := transform * batch.mesh.get_aabb()
			var p := transform.origin
			if not bounds.position.is_finite() or not bounds.size.is_finite() or p.x < -1000 or p.x >= 1000 or p.z < -1000 or p.z >= 1000:
				invalid += 1
				continue
			if world.road_clearance.overlaps(bounds, margin, true):
				overlap += 1
			positions.append(str(transform))
	check(count <= MAX_INSTANCES and batches <= MAX_BATCHES, "allocated batch/instance safety ceilings")
	check(invalid == 0 and overlap == 0, "finite in-map transforms; exact triangle clearance incl shoulders, margin %.2f: invalid=%d overlap=%d" % [margin, invalid, overlap])
	var stats: Dictionary = cover.call("get_stats")
	print("COVER_STATS ", JSON.stringify(stats), " allocation=", count, " batches=", batches)
	check(not stats.is_empty(), "cover stats exposed")
	for key: Variant in stats:
		var value: Variant = stats[key]
		if value is float:
			check(is_finite(value), "finite stat " + str(key))
		if str(key) in ["active_chunks", "queued_chunks"]:
			if value is int or value is float:
				check(value >= 0 and value <= MAX_CHUNKS, "chunk ceiling: " + str(key))
	positions.sort()
	return {"count": count, "active": positions.size(), "signature": "\n".join(positions).sha256_text()}

func focus_path(cover: Node3D, world: Node) -> void:
	for point: Vector3 in FOCUS:
		var p := Vector3(point.x, world.get_surface_height_at(point.x, point.z) + 2.0, point.z)
		cover.call("update_focus", p, Vector3(25,0,0))
		await frames(90)

func cover_test(world: Node) -> void:
	var script := load(COVER) as Script
	if script == null:
		check(false, "cover script loaded")
		return
	var cover := script.new() as Node3D
	if cover == null:
		check(false, "cover is Node3D")
		return
	root.add_child(cover)
	var options := {"seed": 1234, "pilot_bounds": Rect2(-1000,-1000,2000,2000)}
	var result: bool = cover.call("build", world, "medium", MASK, options)
	check(result, "real mask build")
	if result:
		await focus_path(cover, world)
		var first := inspect_cover(cover, world, 0.0)
		check(first.active > 0, "nonempty observable candidate transforms")
		for preset in ["low", "high", "medium"]:
			cover.call("set_graphics", preset)
			await frames(90)
			inspect_cover(cover, world, 0.0)
		cover.call("set_vehicle_interaction", FOCUS[3], Vector3(20,0,0), true)
		await frames(30)
		inspect_cover(cover, world, 0.0)
		cover.call("set_vehicle_interaction", FOCUS[3], Vector3.ZERO, false)
		cover.call("shutdown")
		await frames(10)
		check(inspect_cover(cover, world, 0.0).active == 0, "shutdown releases active instances")
		cover.free()
		cover = script.new() as Node3D
		root.add_child(cover)
		if bool(cover.call("build", world, "medium", MASK, options)):
			await focus_path(cover, world)
			var second := inspect_cover(cover, world, 0.0)
			check(first.signature == second.signature, "same seed and traversal yield same settled transforms")
		else:
			check(false, "rebuild succeeds")
	cover.call("shutdown")
	await frames(10)
	cover.free()
	for bad_path in ["res://tests/environment_overhaul/nonexistent-mask"]:
		var bad := script.new() as Node3D
		root.add_child(bad)
		bad.call("build", world, "medium", bad_path, {})
		bad.call("update_focus", FOCUS[0], Vector3.ZERO)
		await frames(30)
		check(inspect_cover(bad, world, 0.0).active == 0, "missing mask fails closed")
		bad.call("shutdown")
		bad.free()
	var bad_world := Node.new()
	root.add_child(bad_world)
	var bad_cover := script.new() as Node3D
	root.add_child(bad_cover)
	bad_cover.call("build", bad_world, "medium", MASK, {})
	await frames(10)
	check(inspect_cover(bad_cover, world, 0.0).active == 0, "invalid world fails closed")
	bad_cover.call("shutdown")
	bad_cover.free()
	bad_world.free()

func preview_test(path: String, target: Node, rendering: bool) -> void:
	var script := load(path) as Script
	if script == null:
		check(false, "preview script load: " + path)
		return
	var preview: Object = script.new()
	if preview is Node:
		root.add_child(preview)
	var ok: bool
	if rendering:
		ok = preview.call("apply_candidate", target, "medium", {})
	else:
		ok = preview.call("apply_candidate", target, {})
	# Headless capabilities may be unavailable; exercise restore even on refusal.
	print("PREVIEW ", path, " applied=", ok, " (headless, not visual acceptance)")
	preview.call("restore")
	preview.call("restore")
	if preview is Node:
		preview.free()

func run() -> void:
	fixture()
	var integrated := "integrated" in OS.get_cmdline_user_args()
	var present := ResourceLoader.exists(COVER) and FileAccess.file_exists(MASK + "/manifest.json")
	if not present and not integrated:
		print("N/A candidate cover and mask absent on baseline")
		quit(1 if failures else 0)
		return
	if not present:
		check(false, "integrated requires cover and mask")
		quit(1)
		return
	var world := World.new()
	world.build_on_ready = false
	world.build_full_world = true
	world.roadworks = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/roadworks.json"))
	root.add_child(world)
	if not world.build_world():
		check(false, "canonical world builds")
		quit(1)
		return
	await physics_frame
	await process_frame
	check(world.road_clearance.triangle_count > 18000, "real road triangle index")
	await cover_test(world)
	if ResourceLoader.exists(TERRAIN):
		preview_test(TERRAIN, world, false)
	elif integrated:
		check(false, "terrain adapter required")
	# E requires an actual scene environment; its own explicit tests run via
	# --agent-command; capture.gd applies the profile to the real driving scene.
	check(not integrated or ResourceLoader.exists(RENDER), "render adapter required")
	world.free()
	print("Environment QA failures=", failures)
	quit(1 if failures else 0)
