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
var bend_margin := 0.36
var mask_bytes := PackedByteArray()
var preset_under_test := "medium"
const LIMITS := {"low":[18000,120,1200,2,1800],"medium":[54000,300,2400,3,2800],"high":[90000,360,3600,4,4200]}
var strict_stats := false
var stat_map := {}
const MAX_UPLOADS_PER_FRAME := 64
var previous_uploads := -1.0
var peak_upload_delta := 0.0
var audit_cpu := false
var expected_ready := false
var settled_audits := 0
const ASSETS := "res://assets/environment_overhaul/manifest.json"

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
	check(not placement_clear(index,Transform3D(Basis.IDENTITY,Vector3(2,10,2)),AABB(Vector3.ZERO,Vector3.ONE),0.12),"placement rejects deck")
	check(placement_clear(index,Transform3D(Basis.IDENTITY,Vector3(2,0,2)),AABB(Vector3.ZERO,Vector3.ONE),0.12),"placement permits under high bridge")
	check(not placement_clear(index,Transform3D(Basis.IDENTITY,Vector3(999.5,0,0)),AABB(Vector3.ZERO,Vector3.ONE),0.12),"placement rejects footprint outside map")
	check(not placement_clear(index,Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO),AABB(Vector3.ZERO,Vector3.ONE),0.12),"placement rejects singular transform")

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
	var ok := is_finite(number) and number >= 0.0 and floor(number)==number
	check(ok, "finite nonnegative integral " + label)
	return ok

func observe_budget(cover: Node3D, count: int) -> void:
	for i in count:
		await process_frame
		var stats: Dictionary = cover.call("get_stats")
		if expected_ready and str(stats.get("state",""))!="ready":
			check(false,"cover unexpectedly left ready state: "+str(stats.get("fallback","")))
			return
		var active: Variant = stat_value(stats,"active_chunks",["active_chunks","active_chunk_count","chunks_active"])
		var queued: Variant = stat_value(stats,"queued_chunks",["queued_chunks","queued_chunk_count","chunks_queued","pending_chunks"])
		for value: Variant in [active,queued]:
			if value != null and read_nonnegative(value,"chunk counter"):
				check(float(value)<=MAX_CHUNKS,"bounded active/queued chunks")
		var per_frame: Variant = stat_value(stats,"uploads_per_frame",["last_frame_chunk_uploads","uploads_per_frame","chunks_uploaded_this_frame","frame_upload_count"])
		var total: Variant = stat_value(stats,"uploads_total",["uploads_total","chunks_uploaded_total","upload_count_total"])
		if per_frame != null and read_nonnegative(per_frame,"uploads per frame"):
			peak_upload_delta=maxf(peak_upload_delta,float(per_frame))
		if total != null and read_nonnegative(total,"cumulative uploads"):
			if previous_uploads>=0.0 and float(total)>=previous_uploads:
				peak_upload_delta=maxf(peak_upload_delta,float(total)-previous_uploads)
			previous_uploads=float(total)
		check(peak_upload_delta<=MAX_UPLOADS_PER_FRAME,"per-frame upload safety ceiling")
		if strict_stats and expected_ready:
			var limits: Array=LIMITS[preset_under_test]
			var caps: Dictionary={"active_instances":limits[0],"active_chunks":limits[1],"queued_chunks":int(limits[1])+1,"last_frame_checks":limits[2],"last_frame_chunk_uploads":limits[3],"last_frame_upload_instances":limits[4]}
			for key: String in caps:
				var value: Variant=stats.get(key)
				if read_nonnegative(value,key):
					check(float(value)<=float(caps[key]),"preset "+preset_under_test+" cap "+key)

func inspect_cover(cover: Node3D, world: Node, margin: float) -> Dictionary:
	var count := 0
	var visible_count := 0
	var batches := 0
	var pooled := 0
	var invalid := 0
	var overlap := 0
	var positions := PackedStringArray()
	for node: MultiMeshInstance3D in cover.find_children("*", "MultiMeshInstance3D", true, false):
		var batch := node.multimesh
		if batch == null:
			pooled+=1
			if node.visible:
				invalid += 1
			continue
		if batch.mesh == null:
			invalid += 1
			continue
		batches += 1
		var active := batch.instance_count if batch.visible_instance_count < 0 else batch.visible_instance_count
		count += batch.instance_count
		if node.visible:
			visible_count+=active
		if count > MAX_INSTANCES or batches > MAX_BATCHES:
			break
		if DisplayServer.get_name()=="headless" or not node.is_visible_in_tree():
			continue
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
	if strict_stats and expected_ready:
		check(str(stats.get("state",""))=="ready","cover stays ready")
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
			check(total<=int(LIMITS[preset_under_test][0]),"reported active LOD counts bounded")
			check(total==int(stats.get("active_instances",-1)),"LOD sum agrees with active counter")
			check(total==count and total==visible_count,"LOD sum agrees with allocated and visible nonempty batches")
			check(pooled==int(stats.get("pooled_batches",-1)) and pooled<=75,"reported pool agrees and is bounded")
		else:
			check(false,"instances-per-LOD stats missing; use --stats-map")
		var rejected: Variant = stat_value(stats,"rejected_candidates",["rejected_candidates","rejected","rejection_count"])
		if rejected is Dictionary:
			check(not rejected.is_empty(),"rejection categories present")
			for value: Variant in rejected.values():
				read_nonnegative(value,"rejection category")
		else:
			read_nonnegative(rejected,"rejected candidates")
		var work: Variant = stat_value(stats,"uploads_total",["uploads_total","chunks_uploaded_total","upload_count_total"])
		var frame_work: Variant = stat_value(stats,"uploads_per_frame",["last_frame_chunk_uploads","uploads_per_frame","chunks_uploaded_this_frame","frame_upload_count"])
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
	return {"count": count, "visible":visible_count,"pooled":pooled,"active": int(stats.get("active_instances",positions.size())), "signature": "\n".join(positions).sha256_text()}

func focus_path(cover: Node3D, world: Node) -> void:
	for point: Vector3 in FOCUS:
		var p := Vector3(point.x, world.get_surface_height_at(point.x, point.z) + 2.0, point.z)
		cover.call("update_focus", p, Vector3(25,0,0))
		await observe_budget(cover,90)
		var stats: Dictionary=cover.call("get_stats")
		var queued: Variant=stat_value(stats,"queued_chunks",["queued_chunks","queued_chunk_count","chunks_queued","pending_chunks"])
		for wait in range(24):
			if queued==null or float(queued)==0.0:
				break
			await observe_budget(cover,90)
			stats=cover.call("get_stats")
			queued=stat_value(stats,"queued_chunks",["queued_chunks","queued_chunk_count","chunks_queued","pending_chunks"])
		check(queued!=null and float(queued)==0.0,"bounded traversal settles queue")
		inspect_cover(cover,world,bend_margin)
		if audit_cpu:
			cpu_snapshot(cover,world)
			settled_audits+=1

func sample_mask(x: float,z: float) -> Vector4:
	if not is_finite(x) or not is_finite(z) or x< -1000.0 or x>=1000.0 or z< -1000.0 or z>=1000.0:
		return Vector4.ZERO
	if mask_bytes.size()!=4000000:
		return Vector4.ZERO
	var offset: int=4*(mini(999,floori((z+1000.0)/2.0))*1000+mini(999,floori((x+1000.0)/2.0)))
	return Vector4(mask_bytes[offset],mask_bytes[offset+1],mask_bytes[offset+2],mask_bytes[offset+3])/255.0

func cpu_snapshot(cover: Node3D, world: Node) -> Dictionary:
	# Agent A's explicit debug snapshot: dummy rendering does not preserve
	# MultiMesh transforms. Use actual verified mask bytes and real clearance.
	var active: Variant=cover.get("_active")
	var meshes: Variant=cover.get("_meshes")
	if not active is Dictionary or not meshes is Array:
		check(false,"CPU snapshot adapter unavailable")
		return {"count":0,"signature":""}
	var frames_seen:=PackedStringArray()
	var grass_script=load("res://modules/ground_cover/grass_mesh.gd")
	if grass_script==null:
		check(false,"swept mesh helper missing")
		return {"count":0,"signature":""}
	var invalid:=0
	var seen:= {}
	var per_lod: Array[int]=[0,0,0]
	for entry: Dictionary in active.values():
		if not entry.has("fixture_groups"):
			check(false,"fixture snapshot missing")
			continue
		var groups: Array=entry["fixture_groups"]
		var lod:=int(entry.get("lod",-1))
		if lod<0 or lod>=3 or groups.size()!=meshes.size():
			check(false,"invalid CPU snapshot group/LOD")
			continue
		for species in groups.size():
			for item: Dictionary in groups[species]:
				var transform: Transform3D=item["frame"]
				var p:=transform.origin
				if not transform.is_finite() or absf(transform.basis.determinant())<0.0001 or p.x< -1000 or p.x>=1000 or p.z< -1000 or p.z>=1000:
					invalid+=1
					continue
				var key:=str(transform)
				if seen.has(key):
					invalid+=1
				seen[key]=true
				per_lod[lod]+=1
				for mesh: Mesh in meshes[species]:
					var swept: AABB=grass_script.swept_bounds(mesh,transform)
					if not swept.position.is_finite() or not swept.size.is_finite() or swept.size.x<=0 or swept.size.y<=0 or swept.size.z<=0 or swept.position.x< -1000 or swept.end.x>1000 or swept.position.z< -1000 or swept.end.z>1000 or world.road_clearance.overlaps(swept,maxf(0.12,bend_margin-0.24),true):
						invalid+=1
				frames_seen.append(str(transform))
	check(invalid==0,"CPU snapshots finite and all LOD swept bounds clear, invalid="+str(invalid))
	var stats: Dictionary=cover.call("get_stats")
	check(frames_seen.size()==int(stats.get("active_instances",-1)),"CPU snapshot count agrees with stats")
	check(stats.get("instances_per_lod")==per_lod,"CPU snapshot per-LOD counts agree")
	frames_seen.sort()
	return {"count":frames_seen.size(),"signature":"\n".join(frames_seen).sha256_text()}

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
	preset_under_test="medium"
	previous_uploads=-1.0
	peak_upload_delta=0.0
	var result: bool = cover.call("build", world, "medium", MASK, options)
	check(result, "real mask build")
	expected_ready=result
	if result:
		await focus_path(cover, world)
		var first := inspect_cover(cover, world, bend_margin)
		check(first.active > 0, "nonempty observable candidate transforms")
		for preset in ["low", "high", "medium"]:
			preset_under_test=preset
			cover.call("set_graphics", preset)
			await focus_path(cover,world)
			var state:=inspect_cover(cover,world,bend_margin)
			check(state.active>0,"preset rebuild nonempty: "+preset)
		cover.call("set_vehicle_interaction", FOCUS[3], Vector3(20,0,0), true)
		await frames(30)
		inspect_cover(cover, world, bend_margin)
		cover.call("set_vehicle_interaction", FOCUS[3], Vector3.ZERO, false)
		cover.call("shutdown")
		expected_ready=false
		await frames(10)
		var stopped:=inspect_cover(cover,world,bend_margin)
		check(stopped.active==0 and stopped.count==0 and cover.get_child_count()==0,"shutdown releases active and pooled batches")
		mask_bytes=FileAccess.get_file_as_bytes(MASK+"/biome_rgba8.bin")
		check(mask_bytes.size()==4000000,"real mask fixture bytes")
		if mask_bytes.size()==4000000:
			options["fixture_sampler"]=sample_mask
			options["test_fixture"]=true
			options["capture_fixture"]=true
			audit_cpu=true
			settled_audits=0
			var signature:=""
			for repeat in 2:
				cover.call("shutdown")
				expected_ready=false
				previous_uploads=-1.0
				if not bool(cover.call("build",world,"medium",MASK,options)):
					check(false,"CPU snapshot rebuild")
					break
				expected_ready=true
				await focus_path(cover,world)
				var snap:=cpu_snapshot(cover,world)
				check(snap.count>0,"nonempty CPU snapshot")
				if repeat==0:
					signature=snap.signature
				else:
					check(signature==snap.signature,"same seed and traversal deterministic CPU snapshot")
			check(settled_audits==2*FOCUS.size(),"all settled CPU traversal states audited")
			audit_cpu=false
	cover.call("shutdown")
	expected_ready=false
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
		check(not bool(bad.call("build", world, "medium", bad_path, {})),"missing/corrupt mask build refuses")
		bad.call("update_focus", FOCUS[0], Vector3.ZERO)
		await frames(30)
		var rejected:=inspect_cover(bad,world,0.0)
		check(rejected.active==0 and rejected.count==0 and rejected.visible==0,"missing/corrupt mask fails closed")
		bad.call("shutdown")
		bad.free()
	for filename in ["manifest.json","biome_rgba8.bin"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_dir+"/"+filename))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_dir))
	var bad_world := Node.new()
	root.add_child(bad_world)
	var bad_cover := script.new() as Node3D
	root.add_child(bad_cover)
	check(not bool(bad_cover.call("build", bad_world, "medium", MASK, {})),"invalid world build refuses")
	await frames(10)
	var rejected_world:=inspect_cover(bad_cover,world,0.0)
	check(rejected_world.active==0 and rejected_world.count==0 and rejected_world.visible==0,"invalid world fails closed")
	bad_cover.call("shutdown")
	bad_cover.free()
	bad_world.free()

func mesh_bounds(node: Node, parent: Transform3D, parts: Array[AABB]) -> void:
	var frame:=parent
	if node is Node3D:
		frame=parent*(node as Node3D).transform
	if node is MeshInstance3D:
		var mesh: Mesh=(node as MeshInstance3D).mesh
		if mesh!=null:
			parts.append(frame*mesh.get_aabb())
	for child: Node in node.get_children():
		mesh_bounds(child,frame,parts)

func placement_clear(index: Object, frame: Transform3D, bounds: AABB, margin: float) -> bool:
	if not frame.is_finite() or absf(frame.basis.determinant())<0.0001 or not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<=0 or bounds.size.y<=0 or bounds.size.z<=0:
		return false
	var actual:=frame*bounds
	if not actual.position.is_finite() or not actual.size.is_finite() or actual.position.x< -1000 or actual.end.x>1000 or actual.position.z< -1000 or actual.end.z>1000:
		return false
	return not bool(index.call("overlaps",actual,margin,true))

func understory_test(world: Node) -> void:
	# The F-owned audit does not spawn or approve production vegetation. It
	# independently evaluates real imported species' union bounds for every
	# optional C placement, and reports what must be skipped by integration.
	var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string(ASSETS))
	var placements: Variant=JSON.parse_string(FileAccess.get_file_as_string(MASK+"/understory.json"))
	if not manifest is Dictionary or not placements is Dictionary or not manifest.get("assets") is Array or not placements.get("placements") is Array:
		check(false,"understory/asset manifest shape")
		return
	var species_bounds: Dictionary={}
	for entry: Dictionary in manifest.assets:
		var species:=str(entry.get("species_id",""))
		if species_bounds.has(species):
			# Union across variants, conservative for a coordinator-selected LOD.
			pass
		for lod: String in ["lod0","lod1","lod2"]:
			if not entry.has(lod):
				continue
			var packed:=ResourceLoader.load(str(entry[lod]),"PackedScene") as PackedScene
			if packed==null:
				check(false,"understory imported asset missing "+str(entry[lod]))
				continue
			var node:=packed.instantiate()
			var parts: Array[AABB]=[]
			mesh_bounds(node,Transform3D.IDENTITY,parts)
			node.free()
			if parts.is_empty():
				check(false,"understory resource has no meshes: "+str(entry[lod]))
				continue
			for part: AABB in parts:
				if not part.position.is_finite() or not part.size.is_finite():
					check(false,"nonfinite imported understory bounds")
					continue
				if species_bounds.has(species):
					species_bounds[species]=(species_bounds[species] as AABB).merge(part)
				else:
					species_bounds[species]=part
	var accepted:=0
	var unsafe:=0
	var missing:=0
	for item: Dictionary in placements.placements:
		var species:=str(item.get("species_id",""))
		if not species_bounds.has(species):
			missing+=1
			continue
		var x:=float(item.get("x",NAN))
		var z:=float(item.get("z",NAN))
		var yaw:=float(item.get("yaw_rad",NAN))
		var scale:=float(item.get("scale",NAN))
		if not is_finite(x) or not is_finite(z) or not is_finite(yaw) or not is_finite(scale) or scale<=0 or x< -1000 or x>=1000 or z< -1000 or z>=1000:
			check(false,"invalid understory placement")
			continue
		var y: float=world.get_surface_height_at(x,z)
		if not is_finite(y):
			check(false,"invalid understory surface")
			continue
		var frame:=Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale),Vector3(x,y,z))
		if placement_clear(world.road_clearance,frame,species_bounds[species],0.12):
			accepted+=1
		else:
			unsafe+=1
	check(accepted+unsafe+missing==placements.placements.size(),"understory accounted for")
	print("UNDERSTORY_AUDIT ",JSON.stringify({"clear":accepted,"must_skip_road_or_bounds":unsafe,"must_skip_missing_species":missing,"placed":0}))
	if strict_stats and not placements.placements.is_empty():
		check(accepted>0,"nonempty safe understory candidate set")
	# No claim that unsafe raw C records have been spawned or accepted.

func material_snapshot(target: Node, terrain_only: bool) -> Dictionary:
	var result: Dictionary={}
	for mesh: MeshInstance3D in target.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:
			continue
		if terrain_only and (mesh.get_parent()==null or str(mesh.get_parent().name)!="TerrainChunks"):
			continue
		var surfaces: Array=[]
		for index in mesh.mesh.get_surface_count():
			surfaces.append(mesh.get_surface_override_material(index))
		result[mesh.get_instance_id()]=[mesh.mesh,mesh.material_override,surfaces]
	return result

func preview_test(path: String, target: Node, rendering: bool) -> void:
	var script := load(path) as Script
	if script == null:
		check(false, "preview script load: " + path)
		return
	var preview: Object = script.new()
	if preview is Node:
		root.add_child(preview)
	var prior:=material_snapshot(target,not rendering)
	var environment: WorldEnvironment=target.get_node_or_null("WorldEnvironment") as WorldEnvironment if rendering else null
	var original: Environment=environment.environment if environment!=null else null
	var ok: bool
	if rendering:
		ok = preview.call("apply_candidate", target, "medium", {})
	else:
		var pilot:=Rect2(-930,-220,120,120)
		ok = preview.call("apply_candidate", target, {"pilot_bounds":pilot,"roadside_bounds":pilot,"mask_dir":MASK})
	if ok:
		if rendering:
			check(environment!=null and environment.environment!=original,"render candidate changes actual environment identity")
		else:
			check(not prior.is_empty() and material_snapshot(target,true)!=prior,"terrain candidate changes actual terrain material identity")
	# Headless capabilities may be unavailable; exercise restore even on refusal.
	print("PREVIEW ", path, " applied=", ok, " (headless, not visual acceptance)")
	check(ok,"preview applies to actual root: "+path)
	preview.call("restore")
	preview.call("restore")
	check(material_snapshot(target,not rendering)==prior,"preview restores original material identities")
	if rendering:
		check(environment!=null and environment.environment==original,"render restores actual environment identity")
	if preview is Node:
		preview.free()
	elif not preview is RefCounted:
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
	var understory_present:=FileAccess.file_exists(MASK+"/understory.json") and FileAccess.file_exists(ASSETS)
	if not present and not terrain_present and not render_present and not understory_present and not strict_stats:
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
		drive=shell.drive
		if drive!=null and drive.vehicle_body!=null:
			break
	if drive==null or drive.vehicle_body==null:
		check(false,"real game world builds")
		quit(1)
		return
	var world: Node=drive.world
	check(world.road_clearance.triangle_count>18000,"real road triangle index")
	if understory_present:
		understory_test(world)
	else:
		print("N/A optional understory or asset manifest absent")
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
