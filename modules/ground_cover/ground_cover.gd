extends Node3D
## Camera-driven, main-thread-only procedural ground cover. World-aligned coordinates.
const Grass = preload("grass_mesh.gd")
const Mask = preload("biome_mask.gd")
const Placement = preload("placement_math.gd")
const SHADER = preload("grass.gdshader")
const CELL := 16.0
const GRID := 64 # 16 candidates/m², nested by deterministic rank
const SPECIES := 5
const MAX_POOL := 75
const WORLD := Rect2(-1000, -1000, 2000, 2000)
const PROFILES := {
	"low": {"radii": [20.0, 45.0, 80.0], "density": [0.30, 0.12, 0.035], "cap": 18000, "checks": 1200, "uploads": 2, "upload_instances": 1800, "work_usec": 1800, "chunks": 120},
	"medium": {"radii": [25.0, 65.0, 130.0], "density": [0.55, 0.20, 0.055], "cap": 54000, "checks": 2400, "uploads": 3, "upload_instances": 2800, "work_usec": 2200, "chunks": 300},
	"high": {"radii": [32.0, 80.0, 150.0], "density": [0.85, 0.30, 0.08], "cap": 90000, "checks": 3600, "uploads": 4, "upload_instances": 4200, "work_usec": 3000, "chunks": 360}
}
var _world: Node
var _clearance: Object
var _clearance_triangles := 0
var _capture_fixture := false
var _fixture_mode := false
var _mask = Mask.new()
var _fixture: Callable
var _bounds := WORLD
var _options: Dictionary = {}
var _profile: Dictionary = {}
var _seed := 20261125
var _state := "disabled"
var _geometry_bytes := 0
var _reason := ""
var _material: ShaderMaterial
var _plain_material: StandardMaterial3D
var _meshes: Array = []
var _mesh_bounds: Array = []
var _union_bounds: Array[AABB] = []
var _active: Dictionary = {}
var _queue: Array = []
var _pool: Array[MultiMeshInstance3D] = []
var _job: Dictionary = {}
var _focus := Vector3.ZERO
var _velocity := Vector3.ZERO
var _has_focus := false
var _dirty := true
var _last_cell := Vector2i(99999,99999)
var _last_predict := Vector2i(99999,99999)
var _last_plan := Vector2(INF, INF)
var _last_plan_predict := Vector2(INF, INF)
var _clock := 0.0
var _counts := [0,0,0]
var _rejected := {"mask": 0, "height": 0, "slope": 0, "road": 0, "bounds": 0}
var _generated := 0
var _uploaded := 0
var _generation_us := 0
var _upload_us := 0
var _last_checks := 0
var _last_uploads := 0
var _last_upload_instances := 0
var _last_work_usec := 0
var _plan_usec := 0
var _jobs_retargeted := 0
var _jobs_cancelled := 0
var _last_planned_limits := [0, 0, 0]
var _last_planned_chunks := [0, 0, 0]

func build(world: Node, preset: String, mask_dir: String, options: Dictionary = {}) -> bool:
	shutdown()
	_options = options.duplicate(true)
	_seed = int(clampf(_finite_number(options.get("seed", 20261125), 20261125.0), -2147483648.0, 2147483647.0))
	_bounds = WORLD
	if options.has("pilot_bounds"):
		if not options.pilot_bounds is Rect2:
			return _fail("pilot bounds must be Rect2")
		var requested: Rect2 = options.pilot_bounds
		if not requested.position.is_finite() or not requested.end.is_finite() or not requested.has_area():
			return _fail("invalid pilot bounds")
		_bounds = WORLD.intersection(requested)
	if not _bounds.has_area():
		return _fail("empty pilot bounds")
	if is_inside_tree() and not global_transform.is_equal_approx(Transform3D.IDENTITY):
		return _fail("ground cover requires identity global transform")
	if not is_instance_valid(world) or not world.has_method("get_surface_height_at") or not _has_property(world,"road_clearance"):
		return _fail("world height API unavailable")
	_world = world
	var clearance: Variant = world.get("road_clearance")
	if not clearance is Object:
		return _fail("road clearance unavailable")
	_clearance = clearance
	if not _valid_clearance():
		return _fail("road clearance unavailable")
	_clearance_triangles = int(_clearance.get("triangle_count"))
	_fixture = Callable()
	if options.get("fixture_sampler") is Callable and OS.is_debug_build() and bool(options.get("test_fixture", false)):
		_fixture = options.fixture_sampler
	_fixture_mode = _fixture.is_valid()
	_capture_fixture = _fixture_mode and bool(options.get("capture_fixture", false))
	var source_directory := ""
	# A preview runtime indexes only rendered roads; never use it as a
	# production clearance source. Canonical masks are baked with roadworks.
	if not _fixture_mode and _has_property(world,"report"):
		var report: Variant = world.get("report")
		if not report is Dictionary or not bool(report.get("full_world",false)):
			return _fail("production cover requires a full-world clearance index")
		if _has_property(world,"roadworks"):
			var works: Variant = world.get("roadworks")
			if not works is Dictionary or works.is_empty():
				return _fail("production mask requires roadworks terrain")
			source_directory = str(report.get("source_directory",""))
			if source_directory.is_empty():
				return _fail("production world source directory unavailable")
	if not _fixture_mode:
		if not _mask.load_package(mask_dir):
			return _fail(_mask.error)
		if not source_directory.is_empty() and not _mask.verify_world_sources(source_directory):
			return _fail(_mask.error)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var draw_material: Material = _material
	var tuning: Dictionary = options.get("tuning", {}) if options.get("tuning") is Dictionary else {}
	if bool(tuning.get("plain_material", false)):
		_plain_material = StandardMaterial3D.new()
		_plain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_plain_material.vertex_color_use_as_albedo = true
		_plain_material.roughness = 0.96
		draw_material = _plain_material
	for s in range(SPECIES):
		var variants: Array[Mesh] = []
		var bounds: Array[AABB] = []
		var merged := AABB()
		for lod in range(3):
			var geometry := Grass.make_geometry(s,lod)
			var mesh := Grass.mesh_from_geometry(geometry, draw_material)
			var bound: AABB = geometry.bounds
			if not bound.has_volume() or mesh.get_surface_count() != 1:
				return _fail("invalid generated grass geometry")
			variants.append(mesh)
			bounds.append(bound)
			merged = bound if lod == 0 else merged.merge(bound)
			_geometry_bytes += int(geometry.estimated_bytes)
		_meshes.append(variants)
		_mesh_bounds.append(bounds)
		_union_bounds.append(merged)
	_state = "ready"
	_reason = ""
	set_graphics(preset)
	set_process(true)
	return true

func _has_property(object: Object, property_name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.get("name")) == property_name:
			return true
	return false

func _valid_clearance() -> bool:
	if not is_instance_valid(_clearance) or not _clearance.has_method("overlaps"):
		return false
	var count: Variant = _clearance.get("triangle_count")
	return count is int and count > 0

func _fail(reason: String) -> bool:
	shutdown()
	_reason = reason
	return false

func set_graphics(preset: String) -> void:
	var key := preset.to_lower()
	_profile = PROFILES.get(key, PROFILES.medium).duplicate(true)
	# Numeric overrides are bounded even in experimental density sweeps.
	var tuning: Dictionary = _options.get("tuning", {}) if _options.get("tuning") is Dictionary else {}
	var densities: Array = _profile.density
	var radii: Array = _profile.radii
	if tuning.get("density") is Array and tuning.density.size() == 3:
		for i in range(3):
			densities[i] = clampf(_finite_number(tuning.density[i], float(densities[i])), 0.0, 1.0 if i == 0 else float(densities[i-1]))
	if tuning.get("radii") is Array and tuning.radii.size() == 3:
		for i in range(3):
			radii[i] = clampf(_finite_number(tuning.radii[i], float(radii[i])), 8.0 if i == 0 else float(radii[i-1]) + 4.0, 152.0 + i * 4.0)
	for k in ["cap", "checks", "uploads", "chunks", "upload_instances", "work_usec"]:
		if tuning.has(k):
			_profile[k] = int(clampf(_finite_number(tuning[k], float(_profile[k])), 1.0, float(PROFILES.high[k])))
	if _material != null:
		_material.set_shader_parameter("wind_enabled", bool(tuning.get("wind_enabled", true)))
		_material.set_shader_parameter("wind_strength", clampf(_finite_number(tuning.get("wind_strength", 0.08), 0.08), 0.0, 0.16))
		_material.set_shader_parameter("fade_enabled", bool(tuning.get("fade_enabled", true)))
		_material.set_shader_parameter("fade_start", float(radii[2]) * 0.84)
		_material.set_shader_parameter("fade_end", float(radii[2]))
	_flush_active()
	_dirty = true

func _finite_number(value: Variant, fallback: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return float(value)
	return fallback

func update_focus(camera_position: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
	if _state != "ready":
		return
	if not camera_position.is_finite():
		_flush_active()
		_has_focus = false
		_dirty = true
		return
	if _has_focus and _focus.distance_to(camera_position) > 80.0:
		_flush_active()
		_dirty = true
	_focus = camera_position
	_velocity = _safe_velocity(velocity)
	_has_focus = true

func _safe_velocity(velocity: Vector3) -> Vector3:
	if not velocity.is_finite():
		return Vector3.ZERO
	return velocity.clamp(Vector3.ONE * -80.0, Vector3.ONE * 80.0).limit_length(80.0)

func set_vehicle_interaction(position: Vector3, velocity: Vector3, enabled: bool) -> void:
	if _material == null:
		return
	var valid := enabled and position.is_finite() and velocity.is_finite()
	_material.set_shader_parameter("vehicle_enabled", valid)
	if valid:
		_material.set_shader_parameter("vehicle_position", position)
		_material.set_shader_parameter("vehicle_velocity", _safe_velocity(velocity))

func _process(delta: float) -> void:
	if _state != "ready":
		return
	if (_fixture_mode and not _fixture.is_valid()) or not is_instance_valid(_world) or not _valid_clearance() or _world.get("road_clearance") != _clearance or int(_clearance.get("triangle_count")) != _clearance_triangles:
		_fail("world, fixture or road clearance changed")
		return
	if not _has_focus:
		return
	# This module consumes world coordinates: reject a non-identity parent transform.
	if not global_transform.is_equal_approx(Transform3D.IDENTITY):
		_fail("ground cover requires identity global transform")
		return
	_clock += delta
	var current := Vector2(_focus.x, _focus.z)
	var predicted := current + Vector2(_velocity.x, _velocity.z) * 0.65
	if not WORLD.grow(300.0).has_point(current):
		_flush_active()
		_dirty = true
		return
	var cell := _cell(current)
	var predict_cell := _cell(predicted)
	if _dirty or cell != _last_cell or predict_cell != _last_predict or (_clock >= 0.15 and (current.distance_to(_last_plan) >= 4.0 or predicted.distance_to(_last_plan_predict) >= 4.0)):
		_clock = 0.0
		_last_cell = cell
		_last_predict = predict_cell
		_last_plan = current
		_last_plan_predict = predicted
		_dirty = false
		var plan_start := Time.get_ticks_usec()
		_plan(current, predicted)
		_plan_usec += Time.get_ticks_usec() - plan_start
	_work()

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

func _center(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5,0.5)) * CELL

func _plan(current: Vector2, predicted: Vector2) -> void:
	var radii: Array = _profile.radii
	var outer := float(radii[2])
	var candidates: Array = []
	var start := _cell(current.min(predicted) - Vector2.ONE * (outer + CELL))
	var finish := _cell(current.max(predicted) + Vector2.ONE * (outer + CELL))
	# Reject distant focus rather than iterating outside the finite map.
	start = start.max(_cell(_bounds.position))
	finish = finish.min(_cell(_bounds.end))
	for z in range(start.y, finish.y + 1):
		for x in range(start.x, finish.x + 1):
			var key := Vector2i(x,z)
			var rect := Rect2(Vector2(key) * CELL, Vector2.ONE * CELL)
			if not rect.intersects(_bounds):
				continue
			var center := _center(key)
			var d := center.distance_to(current)
			var pd := center.distance_to(predicted)
			var existing: Dictionary = _active.get(key, {})
			var keep_margin := 5.0 if not existing.is_empty() else 0.0
			var nearest := current.distance_to(current.clamp(rect.position, rect.end))
			var nearest_predicted := predicted.distance_to(predicted.clamp(rect.position, rect.end))
			if minf(nearest, nearest_predicted) > outer + keep_margin:
				continue
			var lod := 2
			if d < float(radii[0]):
				lod = 0
			elif d < float(radii[1]):
				lod = 1
			if not existing.is_empty():
				var old := int(existing.lod)
				if old < lod and d < float(radii[old]) + 5.0:
					lod = old
				elif old > lod and d > float(radii[lod]) - 5.0:
					lod = old
			candidates.append({"key":key,"lod":lod,"priority":minf(d, pd + 8.0)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.priority == b.priority:
			return a.key.y < b.key.y or (a.key.y == b.key.y and a.key.x < b.key.x)
		return a.priority < b.priority)
	var wanted: Dictionary = {}
	var tiers: Array = [[], [], []]
	var density: Array = []
	var tier_counts: Array = []
	for entry: Dictionary in candidates:
		tiers[int(entry.lod)].append(entry)
	for lod in range(3):
		tier_counts.append(tiers[lod].size())
		density.append(ceili(GRID * GRID * float(_profile.density[lod])))
	var plan := Placement.allocate(tier_counts, density, int(_profile.cap), int(_profile.chunks), int(_profile.upload_instances))
	_last_planned_chunks = plan[0]
	_last_planned_limits = plan[1]
	for lod in range(3):
		for i in range(int(_last_planned_chunks[lod])):
			var entry: Dictionary = tiers[lod][i]
			entry["limit"] = int(_last_planned_limits[lod])
			wanted[entry.key] = entry
	for key: Vector2i in _active.keys():
		if not wanted.has(key) or int(_active[key].count) > int(wanted[key].limit):
			# Free excess allocation before upgrades, so old batches cannot starve jobs.
			_release(key)
	_queue.clear()
	if not _job.is_empty():
		var job_key: Vector2i = _job.key
		if not wanted.has(job_key):
			_job.clear()
			_jobs_cancelled += 1
		else:
			_retarget_job(wanted[job_key])
	for key: Vector2i in wanted:
		var entry: Dictionary = wanted[key]
		if _active.has(key) and int(_active[key].lod) == int(entry.lod) and int(_active[key].limit) == int(entry.limit):
			continue
		if not _job.is_empty() and _job.key == key:
			continue
		_queue.append(entry)

# Pure integer mixing, stable across engine hash implementations.
func candidate_index(key: Vector2i, rank: int) -> int:
	return Placement.rank_index(key.x, key.y, rank, _seed)

func _random(key: Vector2i, index: int, salt: int) -> float:
	return Placement.unit_random(key.x, key.y, index, _seed, salt)

func _start_job(entry: Dictionary) -> void:
	_job = entry.duplicate()
	_job["cursor"] = 0
	_job["groups"] = [[],[],[],[],[]]

func _retarget_job(target: Dictionary) -> void:
	var new_limit := int(target.limit)
	if new_limit == int(_job.limit) and int(target.lod) == int(_job.lod):
		return
	# Candidate acceptance is LOD-independent. Keep accepted rank prefixes
	# when the moving camera changes the desired detail or quota.
	for group: Array in _job.groups:
		while not group.is_empty() and int(group.back().rank) >= new_limit:
			group.pop_back()
	_job.cursor = mini(int(_job.cursor), new_limit)
	_job.limit = new_limit
	_job.lod = target.lod
	_jobs_retargeted += 1

func _sample_mask(x: float, z: float) -> Vector4:
	if not WORLD.has_point(Vector2(x,z)):
		return Vector4.ZERO
	if _fixture.is_valid():
		var value: Variant = _fixture.call(x,z)
		if value is Vector4 and value.is_finite():
			var rgba: Vector4 = value
			return Vector4(clampf(rgba.x,0,1),clampf(rgba.y,0,1),clampf(rgba.z,0,1),clampf(rgba.w,0,1))
		return Vector4.ZERO
	return _mask.sample(x,z)

func _height(x: float, z: float) -> float:
	var value: Variant = _world.call("get_surface_height_at", x, z)
	if (value is float or value is int) and is_finite(float(value)) and absf(float(value)) <= 10000.0:
		return float(value)
	return NAN

func _candidate(rank: int) -> void:
	var key: Vector2i = _job.key
	var idx := candidate_index(key, rank)
	var step := CELL / GRID
	var p := Vector2(key) * CELL + Vector2(float(idx % GRID) + _random(key,idx,11), float(idx >> 6) + _random(key,idx,17)) * step
	if not _bounds.has_point(p):
		_rejected.bounds += 1
		return
	var mask := _sample_mask(p.x, p.y)
	if _random(key,idx,23) >= mask.x * (1.0 - mask.w):
		_rejected.mask += 1
		return
	var y := _height(p.x,p.y)
	var hx := _height(p.x+0.25,p.y)
	var hz := _height(p.x,p.y+0.25)
	if not is_finite(y) or not is_finite(hx) or not is_finite(hz):
		_rejected.height += 1
		return
	var gradient := Vector2(hx-y,hz-y) * 4.0
	if not gradient.is_finite() or gradient.length() > 0.8:
		_rejected.slope += 1
		return
	var selector := _random(key,idx,31)
	var species := 1
	if mask.y > 0.55:
		species = 4
	elif mask.z < 0.27:
		species = 3
	elif mask.z > 0.68 and selector > 0.35:
		species = 2
	elif selector < 0.28:
		species = 0
	var scale := lerpf(0.78,1.20,_random(key,idx,37))
	var normal := Vector3(-gradient.x,1.0,-gradient.y).normalized()
	var alignment := Quaternion(Vector3.UP,normal)
	var basis := Basis(alignment) * Basis(Vector3.UP,_random(key,idx,41)*TAU)
	basis = basis.scaled(Vector3.ONE*scale)
	var frame := Transform3D(basis,Vector3(p.x,y-0.025,p.y))
	# Precomputed union of all LODs avoids renderer readback and is conservative.
	var swept := Grass.sweep_aabb(_union_bounds[species],frame)
	if not _bounds.encloses(Rect2(Vector2(swept.position.x,swept.position.z),Vector2(swept.size.x,swept.size.z))):
		_rejected.bounds += 1
		return
	var overlap: Variant = _clearance.call("overlaps",swept,0.12,true)
	if not overlap is bool or overlap:
		_rejected.road += 1
		return
	_job.groups[species].append({"frame":frame,"seed":_random(key,idx,53),"rank":rank})

func _work() -> void:
	_last_checks = 0
	_last_uploads = 0
	_last_upload_instances = 0
	var start := Time.get_ticks_usec()
	var budget := int(_profile.checks)
	var time_budget := int(_profile.work_usec)
	var upload_budget := int(_profile.upload_instances)
	while _last_uploads < int(_profile.uploads):
		if _job.is_empty():
			if _queue.is_empty():
				break
			_start_job(_queue.pop_front())
		while int(_job.cursor) < int(_job.limit) and _last_checks < budget:
			_candidate(int(_job.cursor))
			_job.cursor += 1
			_last_checks += 1
			# Soft time budget (checked in blocks to avoid per-candidate timer cost).
			if _last_checks % 32 == 0 and Time.get_ticks_usec() - start >= time_budget:
				break
		if int(_job.cursor) < int(_job.limit):
			break
		var count := 0
		for group: Array in _job.groups:
			count += group.size()
		if _last_upload_instances + count > upload_budget:
			break
		if _last_checks > 0 and Time.get_ticks_usec() - start >= time_budget:
			# A fully prepared job can publish next frame without redoing candidate work.
			break
		var upload_start := Time.get_ticks_usec()
		if not _publish():
			return
		_upload_us += Time.get_ticks_usec() - upload_start
		_last_uploads += 1
		_last_upload_instances += count
		_job.clear()
		if _last_checks >= budget or Time.get_ticks_usec() - start >= time_budget:
			break
	_generated += _last_checks
	_last_work_usec = Time.get_ticks_usec() - start
	_generation_us += _last_work_usec

func _take_batch() -> MultiMeshInstance3D:
	if not _pool.is_empty():
		return _pool.pop_back()
	var node := MultiMeshInstance3D.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(node)
	return node

func _publish() -> bool:
	var key: Vector2i = _job.key
	var lod := int(_job.lod)
	var count := 0
	for group: Array in _job.groups:
		count += group.size()
	var old_count := int(_active.get(key,{}).get("count",0))
	# A violation is a programming error, never silently drop a completed job.
	if count > int(_job.limit) or _counts[0]+_counts[1]+_counts[2]-old_count+count > int(_profile.cap):
		return _fail("instance cap invariant violated")
	_release(key)
	var nodes: Array[MultiMeshInstance3D] = []
	var center := _center(key)
	var origin := Vector3(center.x,0,center.y)
	for species in range(SPECIES):
		var group: Array = _job.groups[species]
		if group.is_empty():
			continue
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.use_custom_data = true
		mesh.mesh = _meshes[species][lod]
		mesh.instance_count = group.size()
		var bounds := AABB()
		var buffer := PackedFloat32Array()
		buffer.resize(group.size()*16)
		for i in range(group.size()):
			var frame: Transform3D = group[i].frame
			frame.origin -= origin
			Grass.write_instance(buffer,i*16,frame,float(group[i].seed))
			var swept := Grass.sweep_aabb(_mesh_bounds[species][lod],frame)
			bounds = swept if i == 0 else bounds.merge(swept)
		mesh.buffer = buffer
		mesh.custom_aabb = bounds
		var node := _take_batch()
		node.position = origin
		node.multimesh = mesh
		node.visible = true
		nodes.append(node)
	_active[key] = {"nodes":nodes,"lod":lod,"count":count,"limit":int(_job.limit)}
	# Dummy rendering backends may not retain GPU-side instance transforms.
	# Preserve a CPU diagnostic snapshot only for explicit debug fixtures.
	if _capture_fixture:
		_active[key]["fixture_groups"] = _job.groups.duplicate(true)
	_counts[lod] += count
	_uploaded += count
	return true

func _release(key: Vector2i) -> void:
	if not _active.has(key):
		return
	var entry: Dictionary = _active[key]
	_counts[entry.lod] -= int(entry.count)
	for node: MultiMeshInstance3D in entry.nodes:
		node.visible = false
		node.multimesh = null
		if _pool.size() < MAX_POOL:
			_pool.append(node)
		else:
			node.free()
	_active.erase(key)

func _flush_active() -> void:
	for key: Vector2i in _active.keys():
		_release(key)
	_queue.clear()
	_job.clear()
	_last_planned_limits = [0, 0, 0]
	_last_planned_chunks = [0, 0, 0]

func get_stats() -> Dictionary:
	var total := int(_counts[0]+_counts[1]+_counts[2])
	return {"state":_state,"fallback":_reason,"plain_material":_plain_material != null,"active_chunks":_active.size(),"queued_chunks":_queue.size()+int(not _job.is_empty()),"pooled_batches":_pool.size(),"instances_per_lod":_counts.duplicate(),"active_instances":total,"planned_chunks_per_lod":_last_planned_chunks.duplicate(),"planned_candidate_limit_per_chunk":_last_planned_limits.duplicate(),"rejected_candidates":_rejected.duplicate(),"candidates_processed":_generated,"instances_uploaded":_uploaded,"generation_usec_including_upload":_generation_us,"planning_usec":_plan_usec,"retargeted_jobs":_jobs_retargeted,"cancelled_jobs":_jobs_cancelled,"upload_usec":_upload_us,"last_frame_checks":_last_checks,"last_frame_chunk_uploads":_last_uploads,"last_frame_upload_instances":_last_upload_instances,"last_frame_work_usec":_last_work_usec,"instance_buffer_estimated_bytes":total*64,"geometry_estimated_bytes":_geometry_bytes,"triangles_estimate":int(_counts[0])*56+int(_counts[1])*15+int(_counts[2])*3,"cap":int(_profile.get("cap",0))}

func shutdown() -> void:
	set_process(false)
	_flush_active()
	for node in _pool:
		node.free()
	_pool.clear()
	_meshes.clear()
	_mesh_bounds.clear()
	_union_bounds.clear()
	_geometry_bytes = 0
	_material = null
	_plain_material = null
	_mask.clear()
	_fixture = Callable()
	_capture_fixture = false
	_fixture_mode = false
	_world = null
	_clearance = null
	_clearance_triangles = 0
	_has_focus = false
	_dirty = true
	_profile.clear()
	_options.clear()
	_counts = [0,0,0]
	_clock = 0.0
	_state = "disabled"
	_reason = "shutdown"
	_generated = 0
	_uploaded = 0
	_generation_us = 0
	_upload_us = 0
	_last_checks = 0
	_last_uploads = 0
	_last_upload_instances = 0
	_last_work_usec = 0
	_plan_usec = 0
	_jobs_retargeted = 0
	_jobs_cancelled = 0
	for k in _rejected:
		_rejected[k] = 0
