extends SceneTree
## Baseline runs a synthetic exact triangle clearance fixture; integrated exercises
## real world and dynamically discovered candidate scripts, no root wiring.
const Clearance = preload("res://modules/world_runtime/src/road_clearance.gd")
const GAME = preload("res://scenes/bootstrap/game.tscn")
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
var bend_margin := 0.0
var strict_stats := false
var stat_map := {}
const MAX_UPLOADS_PER_FRAME := 64
var previous_uploads := -1.0
var peak_upload_delta := 0.0

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

func stat_value(stats: Dictionary, semantic: String, aliases: Array) -> Variant:
	var keys: Array = [stat_map[semantic]] if stat_map.has(semantic) else aliases
	for key: Variant in keys:
		if stats.has(key):
			return stats[key]
	return null

func read_nonnegative(value: Variant, label: String) -> bool:
	if not (value is int or value is float):
		check(false, "numeric " + label)
		return false
	var number := float(value)
	var ok := is_finite(number) and number >= 0.0
	check(ok, "finite nonnegative " + label)
	return ok

func observe_budget(cover: Node3D, count: int) -> void:
	for i in count:
		await process_frame
		var stats: Dictionary = cover.call("get_stats")
		var active: Variant = stat_value(stats,"active_chunks",["active_chunks","active_chunk_count","chunks_active"])
		var queued: Variant = stat_value(stats,"queued_chunks",["queued_chunks","queued_chunk_count","chunks_queued","pending_chunks"])
		for value: Variant in [active,queued]:
			if value != null and read_nonnegative(value,"chunk counter"):
				check(float(value)<=MAX_CHUNKS,"bounded active/queued chunks")
		var per_frame: Variant = stat_value(stats,"uploads_per_frame",["uploads_per_frame","chunks_uploaded_this_frame","frame_upload_count"])
		var total: Variant = stat_value(stats,"uploads_total",["uploads_total","chunks_uploaded_total","upload_count_total"])
		if per_frame != null and read_nonnegative(per_frame,"uploads per frame"):
			peak_upload_delta=maxf(peak_upload_delta,float(per_frame))
		if total != null and read_nonnegative(total,"cumulative uploads"):
			if previous_uploads>=0.0 and float(total)>=previous_uploads:
				peak_upload_delta=maxf(peak_upload_delta,float(total)-previous_uploads)
			previous_uploads=float(total)
		check(peak_upload_delta<=MAX_UPLOADS_PER_FRAME,"per-frame upload safety ceiling")

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
	print("COVER_STATS ", JSON.stringify(stats), " allocation=", count, " batches=", batches, " peak_upload_delta=", peak_upload_delta)
	if strict_stats and positions.size()>0:
		for semantic in ["active_chunks","queued_chunks"]:
			var aliases := ["active_chunks","active_chunk_count","chunks_active"] if semantic=="active_chunks" else ["queued_chunks","queued_chunk_count","chunks_queued","pending_chunks"]
			var value: Variant = stat_value(stats,semantic,aliases)
			if read_nonnegative(value,semantic):
				check(float(value)<=MAX_CHUNKS,"chunk cap")
		var lod: Variant = stat_value(stats,"instances_per_lod",["instances_per_lod","lod_counts","instance_counts_by_lod","lod_instances"])
		if lod is Dictionary or lod is Array:
			var values: Array = lod.values() if lod is Dictionary else lod
			var total := 0
			for value: Variant in values:
				if read_nonnegative(value,"LOD instance count"):
					total+=int(value)
			check(total<=MAX_INSTANCES and total>0,"reported active LOD counts bounded and nonzero")
		else:
			check(false,"instances-per-LOD stats missing; use --stats-map")
		var rejected: Variant = stat_value(stats,"rejected_candidates",["rejected_candidates","rejected","rejection_count"])
		read_nonnegative(rejected,"rejected candidates")
		var work: Variant = stat_value(stats,"uploads_total",["uploads_total","chunks_uploaded_total","upload_count_total"])
		var frame_work: Variant = stat_value(stats,"uploads_per_frame",["uploads_per_frame","chunks_uploaded_this_frame","frame_upload_count"])
		check(work!=null or frame_work!=null,"upload work counter missing; use --stats-map")
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
		await observe_budget(cover,90)
		var stats: Dictionary=cover.call("get_stats")
		var queued: Variant=stat_value(stats,"queued_chunks",["queued_chunks","queued_chunk_count","chunks_queued","pending_chunks"])
		for wait in range(3):
			if queued==null or float(queued)==0.0:
				break
			await observe_budget(cover,90)
			stats=cover.call("get_stats")
			queued=stat_value(stats,"queued_chunks",["queued_chunks","queued_chunk_count","chunks_queued","pending_chunks"])
		check(queued==null or float(queued)==0.0,"bounded traversal settles queue")

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
	previous_uploads=-1.0
	peak_upload_delta=0.0
	var result: bool = cover.call("build", world, "medium", MASK, options)
	check(result, "real mask build")
	if result:
		await focus_path(cover, world)
		var first := inspect_cover(cover, world, bend_margin)
		check(first.active > 0, "nonempty observable candidate transforms")
		for preset in ["low", "high", "medium"]:
			cover.call("set_graphics", preset)
			await observe_budget(cover,90)
			inspect_cover(cover, world, bend_margin)
		cover.call("set_vehicle_interaction", FOCUS[3], Vector3(20,0,0), true)
		await frames(30)
		inspect_cover(cover, world, bend_margin)
		cover.call("set_vehicle_interaction", FOCUS[3], Vector3.ZERO, false)
		cover.call("shutdown")
		await frames(10)
		check(inspect_cover(cover, world, bend_margin).active == 0, "shutdown releases active instances")
		cover.free()
		cover = script.new() as Node3D
		root.add_child(cover)
		previous_uploads=-1.0
		if bool(cover.call("build", world, "medium", MASK, options)):
			await focus_path(cover, world)
			var second := inspect_cover(cover, world, bend_margin)
			check(first.signature == second.signature, "same seed and traversal yield same settled transforms")
		else:
			check(false, "rebuild succeeds")
	cover.call("shutdown")
	await frames(10)
	cover.free()
	var corrupt_dir := "user://environment-qa-corrupt-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(corrupt_dir))
	var corrupt_file := FileAccess.open(corrupt_dir+"/manifest.json",FileAccess.WRITE)
	if corrupt_file!=null:
		corrupt_file.store_string('{"schema_version":1,"width":1000,"height":1000,"sha256":"invalid"}')
		corrupt_file.close()
	var raw := FileAccess.open(corrupt_dir+"/biome_rgba8.bin",FileAccess.WRITE)
	if raw!=null:
		raw.store_buffer(PackedByteArray([1,2,3]))
		raw.close()
	check(corrupt_file!=null and raw!=null,"corrupt-mask fixture created")
	for bad_path in ["res://tests/environment_overhaul/nonexistent-mask",corrupt_dir]:
		var bad := script.new() as Node3D
		root.add_child(bad)
		bad.call("build", world, "medium", bad_path, {})
		bad.call("update_focus", FOCUS[0], Vector3.ZERO)
		await frames(30)
		check(inspect_cover(bad, world, 0.0).active == 0, "missing mask fails closed")
		bad.call("shutdown")
		bad.free()
	for filename in ["manifest.json","biome_rgba8.bin"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_dir+"/"+filename))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_dir))
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
	print("PREVIEW ", path, " applied=", ok, " (headless, not visual acceptance)" if ok else " N/A unsupported headless capability or adapter refusal")
	preview.call("restore")
	preview.call("restore")
	if preview is Node:
		preview.free()

func run() -> void:
	fixture()
	strict_stats = "integrated" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bend-margin="):
			bend_margin=float(arg.trim_prefix("--bend-margin="))
		if arg.begins_with("--stats-map="):
			var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--stats-map=")))
			if parsed is Dictionary:
				stat_map=parsed
			else:
				check(false,"stats mapping must be a JSON dictionary")
	check(is_finite(bend_margin) and bend_margin>=0.0 and bend_margin<=2.0,"swept clearance margin range")
	var present := ResourceLoader.exists(COVER) and FileAccess.file_exists(MASK + "/manifest.json")
	var terrain_present := ResourceLoader.exists(TERRAIN)
	var render_present := ResourceLoader.exists(RENDER)
	if not present and not terrain_present and not render_present and not strict_stats:
		print("N/A candidate modules absent on baseline")
		quit(1 if failures else 0)
		return
	if strict_stats:
		check(present and terrain_present and render_present,"integrated candidate scripts and mask required")
	var game := GAME.instantiate()
	var shell = game.get_node("GameShell")
	var profile := "user://environment-qa-%d.json" % Time.get_ticks_usec()
	shell.save_path=profile
	root.add_child(game)
	shell.enter_free_roam()
	var drive = shell.drive
	for frame in 900:
		await physics_frame
		if drive!=null and drive.vehicle_body!=null:
			break
	if drive==null or drive.vehicle_body==null:
		check(false,"real game world builds")
		quit(1)
		return
	var world: Node=drive.world
	check(world.road_clearance.triangle_count>18000,"real road triangle index")
	if present:
		await cover_test(world)
	else:
		print("N/A candidate cover/mask absent")
	if terrain_present:
		preview_test(TERRAIN,world,false)
	if render_present:
		preview_test(RENDER,drive,true)
	game.queue_free()
	await process_frame
	for suffix in ["",".tmp",".bak",".backup"]:
		if FileAccess.file_exists(profile+suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(profile+suffix))
	print("Environment QA failures=", failures)
	quit(1 if failures else 0)
