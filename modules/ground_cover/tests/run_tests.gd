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

func drain(cover: Cover, max_frames: int = 1200) -> void:
	for i in range(max_frames):
		cover._process(0.016)
		var stats: Dictionary = cover.get_stats()
		if stats.state != "ready":
			check(false,"stream unexpectedly disabled: "+str(stats.fallback))
			return
		check(stats.active_instances <= stats.cap,"instance cap")
		check(stats.last_frame_checks <= int(cover._profile.checks),"candidate budget")
		check(stats.last_frame_chunk_uploads <= int(cover._profile.uploads),"upload budget")
		check(stats.last_frame_upload_instances <= int(cover._profile.upload_instances),"instance upload budget")
		var reserved := 0
		for lod in range(3):
			reserved += int(stats.planned_chunks_per_lod[lod]) * int(stats.planned_candidate_limit_per_chunk[lod])
		check(reserved <= stats.cap,"planned candidate cap")
		check(stats.pooled_batches <= 75,"pool cap")
		check(stats.active_chunks <= int(cover._profile.chunks),"chunk cap")
		check(stats.queued_chunks <= int(cover._profile.chunks),"queue cap")
		check(cover.get_child_count() <= stats.active_chunks * 5 + stats.pooled_batches,"node cap")
		for lod in range(3):
			check((int(stats.planned_chunks_per_lod[lod]) == 0) == (int(stats.planned_candidate_limit_per_chunk[lod]) == 0),"no zero-quota jobs")
		if stats.queued_chunks == 0:
			return
	check(false,"queue drained before timeout")

func fingerprint(cover: Cover) -> int:
	var entries: Array = []
	var keys: Array = cover._active.keys()
	keys.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for key: Vector2i in keys:
		var entry: Dictionary = cover._active[key]
		entries.append(key)
		entries.append(entry.lod)
		for group: Array in entry.fixture_groups:
			for pose: Dictionary in group:
				entries.append(pose.frame)
				entries.append(pose.seed)
	return hash(entries)

func _run() -> void:
	for s in range(5):
		for lod in range(3):
			var geometry := Grass.make_geometry(s,lod)
			var mesh := Grass.mesh_from_geometry(geometry,null)
			var arrays: Array = geometry.arrays
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var roots := 0
			for i in range(vertices.size()):
				check(vertices[i].is_finite() and uv[i].y >= 0 and uv[i].y <= 1,"finite mesh and flex")
				if uv[i].y == 0:
					roots += 1
					check(is_zero_approx(vertices[i].y),"root anchored")
			check(roots > 0 and geometry.bounds.size.y > 0 and mesh.get_surface_count()==1,"mesh dimensions and upload")
			for i in indices:
				check(i >= 0 and i < vertices.size(),"valid index")
			var bound: AABB = geometry.bounds
			var swept := Grass.sweep_aabb(bound,Transform3D.IDENTITY)
			check(swept.encloses(bound.grow(0.239)),"wind bounds")
			var frame := Transform3D(Basis(Vector3.UP,0.7).scaled(Vector3.ONE*1.2),Vector3(-8,12,6))
			var world_bounds := Grass.sweep_aabb(bound,frame)
			for vertex: Vector3 in vertices:
				for bend: Vector3 in [Vector3(0.239,0,0),Vector3(-0.239,0,0),Vector3(0,0,0.239),Vector3(0,0,-0.239)]:
					check(world_bounds.has_point(frame*vertex+bend),"rotated swept bounds contain displaced vertex")
	var packed := PackedFloat32Array()
	packed.resize(32)
	var basis := Basis(Vector3(1,2,3),Vector3(4,5,6),Vector3(7,8,9))
	Grass.write_instance(packed,16,Transform3D(basis,Vector3(-4,11,4)),0.5)
	check(packed.slice(16,32)==PackedFloat32Array([1,4,7,-4,2,5,8,11,3,6,9,4,0.5,0.75,0.25,1]),"bulk buffer row-major layout")
	check(packed.slice(0,16)==PackedFloat32Array([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]),"bulk buffer offset isolation")
	var mask := Mask.new()
	check(not mask.load_package("user://not-a-mask"),"missing mask rejected")
	check(mask.sample(0,0) == Vector4.ZERO,"missing mask fail closed")
	var path := "user://ground_cover_fixture_mask_"+str(Time.get_ticks_usec())
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
	var hashes: Dictionary = {}
	for filename: String in Mask.WORLD_FILES:
		var source := FileAccess.open(path.path_join(filename),FileAccess.WRITE)
		if source == null:
			printerr("FAIL fixture source creation")
			quit(1)
			return
		source.store_string("fixture "+filename)
		source.close()
		hashes["data/world/"+filename] = FileAccess.get_sha256(path.path_join(filename))
	var manifest := {"schema_version":1,"width":1000,"height":1000,"cell_size_m":2,"origin_x":-1000,"origin_z":-1000,"byte_order":"RGBA","channels":Mask.CHANNELS,"row_order":"z_ascending_x_ascending","source_hashes":hashes,"seed":17,"sha256":digest}
	var f := FileAccess.open(path.path_join("manifest.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	f = FileAccess.open(path.path_join("biome_rgba8.bin"),FileAccess.WRITE)
	f.store_buffer(payload)
	f.close()
	check(mask.load_package(path),"valid mask")
	check(mask.verify_world_sources(path),"valid source fingerprints")
	check(mask.sample(-999,-999).is_equal_approx(Vector4(255,64,128,32)/255.0),"RGBA mapping")
	check(mask.sample(1000,0)==Vector4.ZERO and mask.sample(-1000.1,0)==Vector4.ZERO and mask.sample(NAN,0)==Vector4.ZERO,"mask outside or nonfinite")
	manifest["channels"] = ["moisture","woodland_weight","grass_suitability","exposed_rock_weight"]
	f = FileAccess.open(path.path_join("manifest.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	check(not mask.load_package(path),"wrong channel ordering rejected")
	manifest["channels"] = Mask.CHANNELS
	f = FileAccess.open(path.path_join("manifest.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	check(mask.load_package(path),"restored manifest")
	f = FileAccess.open(path.path_join("roadworks.json"),FileAccess.WRITE)
	f.store_string("changed source")
	f.close()
	check(not mask.verify_world_sources(path) and mask.sample(-999,-999)==Vector4.ZERO,"stale source clears mask")
	payload[0]=0
	f = FileAccess.open(path.path_join("biome_rgba8.bin"),FileAccess.WRITE)
	f.store_buffer(payload)
	f.close()
	check(not mask.load_package(path),"corrupt payload")
	DirAccess.remove_absolute(path.path_join("manifest.json"))
	DirAccess.remove_absolute(path.path_join("biome_rgba8.bin"))
	for filename: String in Mask.WORLD_FILES:
		DirAccess.remove_absolute(path.path_join(filename))
	DirAccess.remove_absolute(path)
	var world := Fixture.new()
	root.add_child(world)
	var cover := Cover.new()
	root.add_child(cover)
	var options := {"test_fixture":true,"capture_fixture":true,"fixture_sampler":Callable(world,"sample_mask"),"pilot_bounds":Rect2(-48,-48,96,96),"tuning":{"radii":[16.0,26.0,44.0],"density":[0.18,0.09,0.04],"cap":10000,"checks":500,"uploads":2,"chunks":48}}
	check(not cover.build(world,"medium","user://missing"),"missing production mask")
	if not cover.build(world,"medium","",options):
		printerr("FAIL fixture build: ",cover.get_stats())
		quit(1)
		return
	check(true,"fixture build")
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
	cover._job.cursor = 150
	cover._retarget_job({"lod":0,"limit":600})
	check(cover._job.cursor==150,"retarget preserves completed rank prefix")
	for rank in range(150,600):
		cover._candidate(rank)
	cover._job.cursor = 600
	check(cover._job.groups==near_groups,"retarget extension equals original generation")
	var original_far: Array = []
	for group: Array in near_groups:
		var prefix: Array = []
		for pose: Dictionary in group:
			if int(pose.rank) < 150:
				prefix.append(pose)
		original_far.append(prefix)
	cover._retarget_job({"lod":2,"limit":150})
	check(cover._job.groups==original_far and cover._job.cursor==150,"retarget shrink preserves only valid ranks")
	cover._job.clear()
	cover.update_focus(Vector3(8,2,8))
	drain(cover)
	var first := fingerprint(cover)
	var stats: Dictionary = cover.get_stats()
	check(stats.active_instances>0 and stats.rejected_candidates.road>0,"actual grass and road rejection")
	for key: Vector2i in cover._active:
		var entry: Dictionary = cover._active[key]
		for s in range(5):
			for pose: Dictionary in entry.fixture_groups[s]:
				var frame: Transform3D = pose.frame
				for lod in range(3):
					check(not world.road_clearance.overlaps(Grass.sweep_aabb(cover._mesh_bounds[s][lod],frame),0.12,true),"exact swept road exclusion, every LOD")
	check(world.road_clearance.overlaps(AABB(Vector3(3.5,0,7),Vector3(0.2,0.3,0.2)),0,true),"shoulder fixture")
	check(not world.road_clearance.overlaps(AABB(Vector3(17,0,7),Vector3(0.2,0.3,0.2)),0,true),"under bridge allowed")
	check(world.road_clearance.overlaps(AABB(Vector3(17,8,7),Vector3(0.2,0.3,0.2)),0,true),"deck excluded")
	var uploaded_before := int(cover.get_stats().instances_uploaded)
	cover.set_graphics("medium")
	drain(cover)
	check(first==fingerprint(cover) and int(cover.get_stats().instances_uploaded)==uploaded_before,"same preset is idempotent")
	cover._flush_active()
	cover._dirty=true
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
	cover.update_focus(Vector3(NAN,0,0))
	check(cover.get_stats().active_instances==0,"invalid focus clears old instances")
	cover.update_focus(Vector3(8,2,8))
	drain(cover)
	check(first==fingerprint(cover),"valid focus recovers deterministically")
	world.bad_height=true
	cover._flush_active()
	cover._dirty=true
	drain(cover)
	check(cover.get_stats().active_instances==0 and cover.get_stats().rejected_candidates.height>0,"invalid height rejected")
	world.bad_height=false
	world.steep=true
	cover._flush_active()
	cover._dirty=true
	drain(cover)
	check(cover.get_stats().active_instances==0 and cover.get_stats().rejected_candidates.slope>0,"steep slope rejected")
	world.steep=false
	world.add_strip(Rect2(27,-60,2,120),0.0,false)
	cover._process(0.016)
	check(cover.get_stats().state=="disabled","mutated triangle index disables")
	if not cover.build(world,"medium","",options):
		printerr("FAIL rebuild after mutation: ",cover.get_stats())
		quit(1)
		return
	cover.set_process(false)
	world.road_clearance=null
	cover._process(0.016)
	check(cover.get_stats().state=="disabled" and cover.get_stats().active_instances==0,"lost clearance independently disables")
	check(not cover.build(world,"medium","",options),"invalid clearance build")
	# Full pilot planning under cap pressure: check all tiers without spawning.
	world.road_clearance = Fixture.Clearance.new()
	world.add_strip(Rect2(-3,-60,6,120),0.0,false)
	check(not cover.build(world,"medium","",{"pilot_bounds":Rect2(0,0,-1,10)}),"negative pilot bounds")
	if not cover.build(world,"high","",{"test_fixture":true,"fixture_sampler":Callable(world,"sample_mask"),"tuning":{"cap":12000}}):
		printerr("FAIL tight cap fixture: ",cover.get_stats())
		quit(1)
		return
	cover.set_process(false)
	for p in [Vector2(0,0),Vector2(7,7),Vector2(-19,3),Vector2(70,-50)]:
		cover._plan(p,p+Vector2(48,0))
		var plan: Dictionary = cover.get_stats()
		var reserved := 0
		for lod in range(3):
			check(plan.planned_chunks_per_lod[lod] > 0 and plan.planned_candidate_limit_per_chunk[lod] > 0,"tight cap preserves all distance tiers")
			reserved += int(plan.planned_chunks_per_lod[lod])*int(plan.planned_candidate_limit_per_chunk[lod])
		check(reserved <= plan.cap,"tight cap exact reservation")
	# Tiny cap and zero density cannot silently queue empty work.
	var tiny_options := {"test_fixture":true,"fixture_sampler":Callable(world,"sample_mask"),"tuning":{"cap":1,"chunks":360,"density":[1.0,0.0,0.0]}}
	if not cover.build(world,"high","",tiny_options):
		printerr("FAIL tiny cap fixture")
		quit(1)
		return
	cover.set_process(false)
	cover.update_focus(Vector3(8,2,8))
	drain(cover)
	check(cover.get_stats().active_chunks==1 and cover.get_stats().active_instances<=1,"cap one creates one actual candidate chunk")
	tiny_options.tuning.density=[0.0,0.0,0.0]
	if not cover.build(world,"high","",tiny_options):
		printerr("FAIL zero density fixture")
		quit(1)
		return
	cover.set_process(false)
	cover.update_focus(Vector3(8,2,8))
	drain(cover)
	check(cover.get_stats().active_chunks==0 and cover.get_stats().candidates_processed==0,"zero density does not enqueue empty chunks")
	cover.shutdown()
	check(cover.get_child_count()==0 and cover.get_stats().active_instances==0,"shutdown releases nodes")
	cover.free()
	world.free()
	print("[GroundCover] ", checks, " checks, ",failures," failures")
	quit(1 if failures else 0)
