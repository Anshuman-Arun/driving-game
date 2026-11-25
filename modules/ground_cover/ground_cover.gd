extends Node3D
## Camera-driven, main-thread-only procedural ground cover. World-aligned coordinates.
const Grass = preload("grass_mesh.gd")
const Mask = preload("biome_mask.gd")
const SHADER = preload("grass.gdshader")
const CELL := 16.0
const GRID := 64 # 16 candidates/m², nested by deterministic rank
const SPECIES := 5
const MAX_POOL := 75
const WORLD := Rect2(-1000, -1000, 2000, 2000)
const PROFILES := {
	"low": {"radii": [20.0, 45.0, 80.0], "density": [0.30, 0.12, 0.035], "cap": 18000, "checks": 1200, "uploads": 2, "chunks": 120},
	"medium": {"radii": [25.0, 65.0, 130.0], "density": [0.55, 0.20, 0.055], "cap": 54000, "checks": 2400, "uploads": 3, "chunks": 300},
	"high": {"radii": [32.0, 80.0, 150.0], "density": [0.85, 0.30, 0.08], "cap": 90000, "checks": 3600, "uploads": 4, "chunks": 360}
}
var _world: Node
var _clearance: Object
var _mask = Mask.new()
var _fixture: Callable
var _bounds := WORLD
var _options: Dictionary = {}
var _profile: Dictionary = {}
var _seed := 20261125
var _state := "disabled"
var _reason := ""
var _material: ShaderMaterial
var _meshes: Array = []
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

func build(world: Node, preset: String, mask_dir: String, options: Dictionary = {}) -> bool:
	shutdown()
	_options = options.duplicate()
	_seed = int(options.get("seed", 20261125))
	_bounds = WORLD
	if options.get("pilot_bounds") is Rect2:
		_bounds = WORLD.intersection(options.pilot_bounds)
	if not _bounds.has_area():
		return _fail("empty pilot bounds")
	if not is_instance_valid(world) or not world.has_method("get_surface_height_at"):
		return _fail("world height API unavailable")
	_world = world
	_clearance = world.get("road_clearance")
	if not _valid_clearance():
		return _fail("road clearance unavailable")
	_fixture = Callable()
	if options.get("fixture_sampler") is Callable and OS.is_debug_build() and bool(options.get("test_fixture", false)):
		_fixture = options.fixture_sampler
	if not _fixture.is_valid() and not _mask.load_package(mask_dir):
		return _fail(_mask.error)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	for s in range(SPECIES):
		var variants: Array[Mesh] = []
		for lod in range(3):
			variants.append(Grass.make_mesh(s, lod, _material))
		_meshes.append(variants)
	_state = "ready"
	_reason = ""
	set_graphics(preset)
	set_process(true)
	return true

func _valid_clearance() -> bool:
	if not is_instance_valid(_clearance) or not _clearance.has_method("overlaps"):
		return false
	var count: Variant = _clearance.get("triangle_count")
	return (count is int or count is float) and int(count) > 0

func _fail(reason: String) -> bool:
	_state = "disabled"
	_reason = reason
	set_process(false)
	return false

func set_graphics(preset: String) -> void:
	var key := preset.to_lower()
	_profile = PROFILES.get(key, PROFILES.medium).duplicate(true)
	# Numeric overrides are bounded even in experimental density sweeps.
	var tuning: Dictionary = _options.get("tuning", {})
	var densities: Array = _profile.density
	var radii: Array = _profile.radii
	if tuning.get("density") is Array and tuning.density.size() == 3:
		for i in range(3):
			densities[i] = clampf(float(tuning.density[i]), 0.0, 1.0 if i == 0 else float(densities[i-1]))
	if tuning.get("radii") is Array and tuning.radii.size() == 3:
		for i in range(3):
			radii[i] = clampf(float(tuning.radii[i]), 8.0 if i == 0 else float(radii[i-1]) + 4.0, 152.0 + i * 4.0)
	for k in ["cap", "checks", "uploads", "chunks"]:
		if tuning.has(k):
			_profile[k] = clampi(int(tuning[k]), 1, int(PROFILES.high[k]))
	if _material != null:
		_material.set_shader_parameter("wind_enabled", bool(tuning.get("wind_enabled", true)))
		_material.set_shader_parameter("wind_strength", clampf(float(tuning.get("wind_strength", 0.08)), 0.0, 0.16))
		_material.set_shader_parameter("fade_enabled", bool(tuning.get("fade_enabled", true)))
		_material.set_shader_parameter("fade_start", float(radii[2]) * 0.84)
		_material.set_shader_parameter("fade_end", float(radii[2]))
	_flush_active()
	_dirty = true

func update_focus(camera_position: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
	if _state != "ready" or not camera_position.is_finite():
		return
	if _has_focus and _focus.distance_to(camera_position) > 80.0:
		_flush_active()
		_dirty = true
	_focus = camera_position
	_velocity = velocity.limit_length(80.0) if velocity.is_finite() else Vector3.ZERO
	_has_focus = true

func set_vehicle_interaction(position: Vector3, velocity: Vector3, enabled: bool) -> void:
	if _material == null:
		return
	var valid := enabled and position.is_finite() and velocity.is_finite()
	_material.set_shader_parameter("vehicle_enabled", valid)
	if valid:
		_material.set_shader_parameter("vehicle_position", position)
		_material.set_shader_parameter("vehicle_velocity", velocity.limit_length(80.0))

func _process(delta: float) -> void:
	if _state != "ready":
		return
	if not is_instance_valid(_world) or not _valid_clearance() or _world.get("road_clearance") != _clearance:
		_flush_active()
		_fail("world or road clearance changed")
		return
	if not _has_focus:
		return
	_clock += delta
	var current := Vector2(_focus.x, _focus.z)
	var predicted := current + Vector2(_velocity.x, _velocity.z) * 0.65
	var cell := _cell(current)
	var predict_cell := _cell(predicted)
	if _dirty or cell != _last_cell or predict_cell != _last_predict or (_clock >= 0.15 and (current.distance_to(_last_plan) >= 4.0 or predicted.distance_to(_last_plan_predict) >= 4.0)):
		_clock = 0.0
		_last_cell = cell
		_last_predict = predict_cell
		_last_plan = current
		_last_plan_predict = predicted
		_dirty = false
		_plan(current, predicted)
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
			var center := _center(key)
			var d := center.distance_to(current)
			var pd := center.distance_to(predicted)
			var existing: Dictionary = _active.get(key, {})
			var keep_margin := 5.0 if not existing.is_empty() else 0.0
			if minf(d, pd) > outer + keep_margin:
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
	var reserved := 0
	for entry: Dictionary in candidates:
		var estimate := ceili(GRID * GRID * float(_profile.density[entry.lod]))
		# Guaranteed upper bound uses a fixed nested candidate index subset.
		if wanted.size() >= int(_profile.chunks) or reserved + estimate > int(_profile.cap):
			continue
		entry["limit"] = estimate
		reserved += estimate
		wanted[entry.key] = entry
	for key: Vector2i in _active.keys():
		if not wanted.has(key):
			_release(key)
	_queue.clear()
	if not _job.is_empty():
		var job_key: Vector2i = _job.key
		if not wanted.has(job_key) or int(wanted[job_key].lod) != int(_job.lod):
			_job.clear()
	for key: Vector2i in wanted:
		var entry: Dictionary = wanted[key]
		if _active.has(key) and int(_active[key].lod) == int(entry.lod):
			continue
		if not _job.is_empty() and _job.key == key:
			continue
		_queue.append(entry)

# Affine permutation of 4096 indices (odd multiplier), hence exact nested subsets.
func candidate_index(key: Vector2i, rank: int) -> int:
	var h := hash(Vector3i(key.x, key.y, _seed))
	return (rank * 2027 + (h & 4095)) & 4095

func _random(key: Vector2i, index: int, salt: int) -> float:
	return float(hash(Vector4i(key.x, key.y, index, _seed ^ salt)) & 0xFFFFFF) / 16777216.0

func _start_job(entry: Dictionary) -> void:
	_job = entry.duplicate()
	_job["cursor"] = 0
	_job["groups"] = [[],[],[],[],[]]

func _sample_mask(x: float, z: float) -> Vector4:
	if not WORLD.has_point(Vector2(x,z)):
		return Vector4.ZERO
	if _fixture.is_valid():
		var value: Variant = _fixture.call(x,z)
		if value is Vector4 and value.is_finite():
			return value.clamp(Vector4.ZERO, Vector4.ONE)
		return Vector4.ZERO
	return _mask.sample(x,z)

func _height(x: float, z: float) -> float:
	var value: Variant = _world.call("get_surface_height_at", x, z)
	if value is float or value is int:
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
	if gradient.length() > 0.8:
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
	# Near mesh bounds also enclose reduced-detail variants (same seeded blades).
	var swept := Grass.swept_bounds(_meshes[species][0],frame)
	for lod in range(1,3):
		swept = swept.merge(Grass.swept_bounds(_meshes[species][lod],frame))
	if bool(_clearance.call("overlaps",swept,0.12,true)):
		_rejected.road += 1
		return
	_job.groups[species].append({"frame":frame,"seed":_random(key,idx,53)})

func _work() -> void:
	_last_checks = 0
	_last_uploads = 0
	var start := Time.get_ticks_usec()
	var budget := int(_profile.checks)
	while _last_uploads < int(_profile.uploads):
		if _job.is_empty():
			if _queue.is_empty():
				break
			_start_job(_queue.pop_front())
		while int(_job.cursor) < int(_job.limit) and _last_checks < budget:
			_candidate(int(_job.cursor))
			_job.cursor += 1
			_last_checks += 1
		if int(_job.cursor) < int(_job.limit):
			break
		var upload_start := Time.get_ticks_usec()
		_publish()
		_upload_us += Time.get_ticks_usec() - upload_start
		_last_uploads += 1
		_job.clear()
		if _last_checks >= budget:
			break
	_generated += _last_checks
	_generation_us += Time.get_ticks_usec() - start

func _take_batch() -> MultiMeshInstance3D:
	if not _pool.is_empty():
		return _pool.pop_back()
	var node := MultiMeshInstance3D.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(node)
	return node

func _publish() -> void:
	var key: Vector2i = _job.key
	var lod := int(_job.lod)
	_release(key)
	var count := 0
	for group: Array in _job.groups:
		count += group.size()
	# Enforce cap even while old LODs await replacement.
	if _counts[0]+_counts[1]+_counts[2]+count > int(_profile.cap):
		return
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
		for i in range(group.size()):
			var frame: Transform3D = group[i].frame
			frame.origin -= origin
			mesh.set_instance_transform(i,frame)
			mesh.set_instance_custom_data(i,Color(group[i].seed,0,0,1))
			var swept := Grass.swept_bounds(mesh.mesh,frame)
			bounds = swept if i == 0 else bounds.merge(swept)
		mesh.custom_aabb = bounds
		var node := _take_batch()
		node.position = origin
		node.multimesh = mesh
		node.visible = true
		nodes.append(node)
	_active[key] = {"nodes":nodes,"lod":lod,"count":count}
	_counts[lod] += count
	_uploaded += count

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

func get_stats() -> Dictionary:
	var total := int(_counts[0]+_counts[1]+_counts[2])
	return {"state":_state,"fallback":_reason,"active_chunks":_active.size(),"queued_chunks":_queue.size()+int(not _job.is_empty()),"pooled_batches":_pool.size(),"instances_per_lod":_counts.duplicate(),"active_instances":total,"rejected_candidates":_rejected.duplicate(),"candidates_processed":_generated,"instances_uploaded":_uploaded,"generation_usec_including_upload":_generation_us,"upload_usec":_upload_us,"last_frame_checks":_last_checks,"last_frame_chunk_uploads":_last_uploads,"instance_buffer_estimated_bytes":total*64,"triangles_estimate":int(_counts[0])*56+int(_counts[1])*15+int(_counts[2])*3,"cap":int(_profile.get("cap",0))}

func shutdown() -> void:
	set_process(false)
	_flush_active()
	for node in _pool:
		node.free()
	_pool.clear()
	_meshes.clear()
	_material = null
	_mask.bytes.clear()
	_fixture = Callable()
	_world = null
	_clearance = null
	_has_focus = false
	_dirty = true
	_state = "disabled"
	_reason = "shutdown"
	_generated = 0
	_uploaded = 0
	_generation_us = 0
	_upload_us = 0
	_last_checks = 0
	_last_uploads = 0
	for k in _rejected:
		_rejected[k] = 0
