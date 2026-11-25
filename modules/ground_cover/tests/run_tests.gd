extends SceneTree
const Cover = preload("../ground_cover.gd")
const Grass = preload("../grass_mesh.gd")
const Mask = preload("../biome_mask.gd")
const Fixture = preload("fixture_world.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",message)

func drain(cover: Node, max_frames: int = 400) -> void:
	for i in range(max_frames):
		cover._process(0.016)
		var stats: Dictionary = cover.get_stats()
		check(stats.active_instances <= stats.cap,"instance cap")
		check(stats.last_frame_checks <= int(cover._profile.checks),"candidate budget")
		check(stats.last_frame_chunk_uploads <= int(cover._profile.uploads),"upload budget")
		check(stats.pooled_batches <= 75,"pool cap")
		check(stats.active_chunks <= int(cover._profile.chunks),"chunk cap")
		check(stats.queued_chunks <= int(cover._profile.chunks),"queue cap")
		if stats.queued_chunks == 0:
			return
	check(false,"queue drained before timeout")

func fingerprint(cover: Node) -> int:
	var entries: Array = []
	var keys: Array = cover._active.keys()
	keys.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for key: Vector2i in keys:
		var entry: Dictionary = cover._active[key]
		for node: MultiMeshInstance3D in entry.nodes:
			var mm := node.multimesh
			for i in range(mm.instance_count):
				entries.append(mm.get_instance_transform(i))
	return hash(entries)

func _run() -> void:
	for s in range(5):
		for lod in range(3):
			var mesh := Grass.make_mesh(s,lod,null)
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var roots := 0
			for i in range(vertices.size()):
				check(vertices[i].is_finite() and uv[i].y >= 0 and uv[i].y <= 1,"finite mesh and flex")
				if uv[i].y == 0:
					roots += 1
					check(is_zero_approx(vertices[i].y),"root anchored")
			check(roots > 0 and mesh.get_aabb().size.y > 0,"mesh dimensions")
			for i in indices:
				check(i >= 0 and i < vertices.size(),"valid index")
			var swept := Grass.swept_bounds(mesh,Transform3D.IDENTITY)
			check(swept.encloses(mesh.get_aabb().grow(0.239)),"wind bounds")
	var mask := Mask.new()
	check(not mask.load_package("user://not-a-mask"),"missing mask rejected")
	check(mask.sample(0,0) == Vector4.ZERO,"missing mask fail closed")
	var path := "user://ground_cover_fixture_mask"
	DirAccess.make_dir_recursive_absolute(path)
	var payload := PackedByteArray()
	payload.resize(4000000)
	payload[0]=255
	payload[1]=64
	payload[2]=128
	payload[3]=32
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(payload)
	var digest := hash_context.finish().hex_encode()
	var manifest := {"schema_version":1,"width":1000,"height":1000,"cell_size_m":2,"origin_x":-1000,"origin_z":-1000,"byte_order":"RGBA","sha256":digest}
	var f := FileAccess.open(path.path_join("manifest.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	f = FileAccess.open(path.path_join("biome_rgba8.bin"),FileAccess.WRITE)
	f.store_buffer(payload)
	f.close()
	check(mask.load_package(path),"valid mask")
	check(mask.sample(-999,-999).is_equal_approx(Vector4(255,64,128,32)/255.0),"RGBA mapping")
	check(mask.sample(1000,0)==Vector4.ZERO and mask.sample(-1000.1,0)==Vector4.ZERO,"mask outside")
	payload[0]=0
	f = FileAccess.open(path.path_join("biome_rgba8.bin"),FileAccess.WRITE)
	f.store_buffer(payload)
	f.close()
	check(not mask.load_package(path),"corrupt payload")
	DirAccess.remove_absolute(path.path_join("manifest.json"))
	DirAccess.remove_absolute(path.path_join("biome_rgba8.bin"))
	DirAccess.remove_absolute(path)
	var world := Fixture.new()
	root.add_child(world)
	var cover := Cover.new()
	root.add_child(cover)
	var options := {"test_fixture":true,"fixture_sampler":Callable(world,"sample_mask"),"pilot_bounds":Rect2(-48,-48,96,96),"tuning":{"radii":[16.0,26.0,44.0],"density":[0.18,0.09,0.04],"cap":10000,"checks":500,"uploads":2,"chunks":48}}
	check(not cover.build(world,"medium","user://missing"),"missing production mask")
	check(cover.build(world,"medium","",options),"fixture build")
	cover.set_process(false)
	var seen := {}
	for rank in range(4096):
		var idx := cover.candidate_index(Vector2i(-2,3),rank)
		seen[idx]=true
	check(seen.size()==4096,"unique permutation")
	# Generate the same cell at two nested rank limits using the real candidate path.
	var cell := Vector2i(0,1)
	cover._start_job({"key":cell,"lod":0,"limit":600})
	for rank in range(600):
		cover._candidate(rank)
	var near_groups: Array = cover._job.groups.duplicate(true)
	cover._start_job({"key":cell,"lod":2,"limit":150})
	for rank in range(150):
		cover._candidate(rank)
	var far_groups: Array = cover._job.groups
	var far_count := 0
	for s in range(5):
		far_count += far_groups[s].size()
		check(near_groups[s].slice(0,far_groups[s].size()) == far_groups[s],"nested actual accepted transforms")
	check(far_count > 0,"nested fixture nonempty")
	cover._job.clear()
	cover.update_focus(Vector3(8,2,8))
	drain(cover)
	var first := fingerprint(cover)
	var stats: Dictionary = cover.get_stats()
	check(stats.active_instances>0 and stats.rejected_candidates.road>0,"actual grass and road rejection")
	for key: Vector2i in cover._active:
		for node: MultiMeshInstance3D in cover._active[key].nodes:
			var mm := node.multimesh
			for i in range(mm.instance_count):
				var frame := Transform3D(Basis.IDENTITY,node.position)*mm.get_instance_transform(i)
				check(not world.road_clearance.overlaps(Grass.swept_bounds(mm.mesh,frame),0.12,true),"exact swept road exclusion")
	check(world.road_clearance.overlaps(AABB(Vector3(3.5,0,7),Vector3(0.2,0.3,0.2)),0,true),"shoulder fixture")
	check(not world.road_clearance.overlaps(AABB(Vector3(17,0,7),Vector3(0.2,0.3,0.2)),0,true),"under bridge allowed")
	check(world.road_clearance.overlaps(AABB(Vector3(17,8,7),Vector3(0.2,0.3,0.2)),0,true),"deck excluded")
	cover.set_graphics("medium")
	drain(cover)
	check(first==fingerprint(cover),"deterministic rebuild")
	for preset in ["low","high","medium"]:
		cover.set_graphics(preset)
		drain(cover)
	for x in range(8,45,4):
		cover.update_focus(Vector3(x,2,12),Vector3(16,0,0))
		drain(cover)
	cover.update_focus(Vector3(8,2,8))
	drain(cover)
	cover.update_focus(Vector3(500,2,500),Vector3(60,0,0))
	drain(cover)
	check(cover.get_stats().active_instances==0,"teleport clears old instances")
	cover.update_focus(Vector3(8,2,8))
	drain(cover)
	check(first==fingerprint(cover),"teleport deterministic")
	world.bad_height=true
	cover.set_graphics("medium")
	drain(cover)
	check(cover.get_stats().active_instances==0 and cover.get_stats().rejected_candidates.height>0,"invalid height rejected")
	world.bad_height=false
	world.steep=true
	cover.set_graphics("medium")
	drain(cover)
	check(cover.get_stats().active_instances==0 and cover.get_stats().rejected_candidates.slope>0,"steep slope rejected")
	world.steep=false
	world.road_clearance=null
	cover._process(0.016)
	check(cover.get_stats().state=="disabled","lost clearance disables")
	check(not cover.build(world,"medium","",options),"invalid clearance build")
	cover.shutdown()
	check(cover.get_child_count()==0 and cover.get_stats().active_instances==0,"shutdown releases nodes")
	cover.free()
	world.free()
	print("[GroundCover] ", checks, " checks, ",failures," failures")
	quit(1 if failures else 0)
