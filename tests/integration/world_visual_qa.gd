extends SceneTree
## godot --headless --fixed-fps 120 --script res://tests/integration/world_visual_qa.gd
## Optional -- --rebake=absolute_path writes the accepted deterministic vegetation cache.

const GAME := preload("res://scenes/bootstrap/game.tscn")
const WorldRuntime := preload("res://modules/world_runtime/src/world_runtime.gd")
const Curated := preload("res://scripts/integration/curated_car_visual.gd")
const PremiumMesh := preload("res://scripts/integration/premium_mesh.gd")
const Vegetation := preload("res://scripts/integration/valley_vegetation.gd")
var failures := 0
var seen: Dictionary = {}
var materials_checked := 0
var texture_bindings := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game := GAME.instantiate()
	var shell = game.get_node("GameShell")
	shell.save_path = "user://world-visual-qa-%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	shell.enter_free_roam()
	var drive = shell.drive
	for i in 450:
		await physics_frame
		if drive.vehicle_body != null:
			break
	if drive.vehicle_body == null or drive.vegetation == null or drive.scenery == null:
		quit(1)
		return
	var index = drive.world.road_clearance
	check(index.triangle_count > 18000, "%d road, shoulder and junction triangles indexed" % index.triangle_count)
	audit_vegetation(drive, index)
	audit_authored(drive, index)
	audit_guardrail_preservation(drive)
	for node: MeshInstance3D in drive.find_children("*", "MeshInstance3D", true, false):
		audit_mesh(node.mesh, node.material_override)
	for id in PlayerCarFactory.PRESETS:
		var car := Curated.load_model(id)
		check(car != null, "Garage loads " + id)
		if car != null:
			for node: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
				for surface in node.mesh.get_surface_count():
					audit_material(node.get_active_material(surface))
			car.free()
	print("MATERIALS unique=%d texture_bindings=%d" % [materials_checked, texture_bindings])
	for asset: String in ["fir", "fern"]:
		check(has_foliage_cutout(asset), asset + " imports a real opacity mask and an alpha-scissor material")
	var road_rays := audit_routes(drive)
	check(road_rays > 1000, "Full-network collision sweep tested %d samples" % road_rays)
	for car_id: String in PlayerCarFactory.PRESETS:
		await drive_car(drive, car_id)
	for preset in ["low", "high", "medium"]:
		check(shell._save_option("graphics_quality", preset) and drive.graphics_preset == preset, "Graphics preset applies and saves: " + preset)
	await sweep_corridors(drive)
	quit(failures)

func audit_vegetation(drive: Node, index: RefCounted) -> void:
	var plant = drive.vegetation
	var overlaps := 0
	var rows: PackedFloat32Array = plant._placements
	for offset in range(0, rows.size(), 7):
		var kind := int(rows[offset + 5])
		var at := Vector3(rows[offset], rows[offset + 1] - (0.18 if kind < 2 else 0.04), rows[offset + 2])
		var pose: Transform3D = plant._instance_frame(at, rows[offset + 3], rows[offset + 4], rows[offset + 6])
		var mesh: Mesh = plant._meshes[kind]
		if index.overlaps(pose * mesh.get_aabb()):
			overlaps += 1
		if kind < plant._distant_trees.size() and index.overlaps(pose * plant._distant_trees[kind].get_aabb()):
			overlaps += 1
	check(overlaps == 0, "%d accepted baked placements and both tree LODs have %d overlaps" % [plant._placements.size() / 7, overlaps])
	for mesh: Mesh in plant._meshes:
		audit_mesh(mesh)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rebake=") and overlaps == 0:
			var file := FileAccess.open(arg.trim_prefix("--rebake="), FileAccess.WRITE)
			check(file != null, "Opened vegetation rebake destination")
			if file != null:
				file.store_buffer(plant._placements.to_byte_array())

func audit_authored(drive: Node, index: RefCounted) -> void:
	var count := 0
	var overlaps := 0
	for node: MultiMeshInstance3D in drive.scenery.find_children("*", "MultiMeshInstance3D", true, false):
		var batch := node.multimesh
		var box := batch.mesh.get_aabb()
		audit_mesh(batch.mesh)
		for i in batch.instance_count:
			count += 1
			if index.overlaps(node.global_transform * batch.get_instance_transform(i) * box, 0.0, not bool(node.get_meta("roadside_barrier", false))):
				overlaps += 1
	check(overlaps == 0, "%d authored near/far render instances have %d overlaps" % [count, overlaps])
	count = 0
	overlaps = 0
	for node: CollisionShape3D in drive.scenery.find_children("*", "CollisionShape3D", true, false):
		if node.shape is BoxShape3D:
			count += 1
			var box := AABB(-node.shape.size * 0.5, node.shape.size)
			if index.overlaps(node.global_transform * box, 0.0, not bool(node.get_parent().get_meta("roadside_barrier", false))):
				overlaps += 1
	check(overlaps == 0, "%d authored collision shapes have %d overlaps" % [count, overlaps])

func audit_guardrail_preservation(drive: Node) -> void:
	# Compare to the exact prior road geometry, not a guessed placement count.
	# No colliders in this temporary baseline; it cannot affect live driving.
	var baseline := WorldRuntime.new()
	baseline.build_on_ready = false
	baseline.build_full_world = true
	baseline.generate_colliders = false
	baseline.roadworks = drive.world.roadworks.duplicate(true)
	baseline.roadworks.erase("network_upgrade")
	for profile: Dictionary in baseline.roadworks["roads"].values():
		profile.erase("support_start")
		profile.erase("support_end")
	root.add_child(baseline)
	if not baseline.build_world():
		check(false, "pre-widening comparison world builds")
		baseline.free()
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/scenery/manifest.json"))
	var expected := 0
	for entry: Dictionary in manifest["region_packs"]:
		var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + str(entry["path"])))
		for raw: Dictionary in pack["placements"]:
			if raw["asset"] != "guardrail" or not drive.scenery._quality_keeps(raw):
				continue
			var p: Array = raw["position"]
			var height := baseline.get_surface_height_at(float(p[0]), float(p[2]))
			var original := baseline.get_authored_surface_height_at(float(p[0]), float(p[2]))
			if absf(height - original) > 0.33:
				continue
			var item := raw.duplicate()
			item["position"] = [p[0], height + float(raw.get("terrain_offset_m", 0.0)), p[2]]
			var frame: Transform3D = drive.scenery._placement_frame(item)
			var bounds: AABB = frame * drive.scenery._model_bounds(manifest["assets"]["guardrail"])
			if drive.scenery.generate_selective_colliders:
				bounds = bounds.merge(frame * drive.scenery._local_collider_bounds("guardrail"))
			if not baseline.road_clearance.overlaps(bounds, 0.16, false):
				expected += 1
	audit_vegetation_preservation(drive, baseline)
	baseline.free()
	var report: Dictionary = drive.scenery.report
	var retained := int(report.get("guardrails_accepted", 0))
	var relocated := int(report.get("guardrails_relocated", 0))
	check(expected > 0 and retained >= expected and relocated > 0,
		"guardrails retained %d vs pre-widening %d; %d safely relocated; unresolved %s" %
		[retained, expected, relocated, str(report.get("unresolved_guardrails", []))])


func audit_vegetation_preservation(drive: Node, baseline: Node) -> void:
	# Re-run the identical production vegetation filter against pre-widening
	# geometry and the exact same baked source. No alternate art or seed.
	var plant = drive.vegetation
	var file := FileAccess.open(Vegetation.DATA_PATH, FileAccess.READ)
	if file == null:
		check(false, "original vegetation source available")
		return
	var probe := Vegetation.new()
	probe._world = baseline
	probe._meshes.assign(plant._meshes)
	probe._distant_trees.assign(plant._distant_trees)
	probe._placements = file.get_buffer(file.get_length()).to_float32_array()
	probe._filter_placements()
	var prior: PackedFloat32Array = probe._placements
	var current: PackedFloat32Array = plant._placements
	var lookup: Dictionary = {}
	var duplicates := 0
	for offset in range(0, current.size(), Vegetation.STRIDE):
		var key := Vector3(current[offset], current[offset + 2], current[offset + 6])
		if lookup.has(key):
			duplicates += 1
		lookup[key] = offset
	var lost := [0, 0, 0, 0, 0, 0]
	var retained := 0
	var unexplained := 0
	var changed := 0
	for offset in range(0, prior.size(), Vegetation.STRIDE):
		var key := Vector3(prior[offset], prior[offset + 2], prior[offset + 6])
		if lookup.has(key):
			retained += 1
			var new_offset: int = lookup[key]
			for field in Vegetation.STRIDE:
				if not is_equal_approx(prior[offset + field], current[new_offset + field]):
					changed += 1
					break
			continue
		var kind := int(prior[offset + 5])
		lost[kind] += 1
		var footprint: AABB = plant._meshes[kind].get_aabb()
		if kind < plant._distant_trees.size():
			footprint = footprint.merge(plant._distant_trees[kind].get_aabb())
		var origin := Vector3(prior[offset], prior[offset + 1] - (0.18 if kind < 2 else 0.04), prior[offset + 2])
		var frame: Transform3D = plant._instance_frame(origin, prior[offset + 3], prior[offset + 4], prior[offset + 6])
		var margin := 1.8 if kind < 2 or kind == 4 else 0.34
		if not drive.world.road_clearance.overlaps(frame * footprint, margin):
			unexplained += 1
	var before := int(prior.size() / Vegetation.STRIDE)
	var after := int(current.size() / Vegetation.STRIDE)
	print("VEGETATION BASELINE before=", before, " after=", after, " retained=", retained,
		" newly_accepted=", after - retained, " lost_by_kind=", lost, " unexplained=", unexplained)
	check(before > 0 and after > 0 and duplicates == 0 and unexplained == 0 and changed == 0,
		"all removed baseline vegetation is explained by wider road clearance; retained poses unchanged")
	probe.free()


func audit_routes(drive: Node) -> int:
	var space: PhysicsDirectSpaceState3D = drive.get_world_3d().direct_space_state
	var samples := 0
	var invalid: Array[String] = []
	for lane: Dictionary in drive.world.get_road_graph()["lanes"]:
		var points: Array = lane["points"]
		for i in range(0, points.size(), 2):
			var p: Array = points[i]
			var pos := Vector3(p[0], p[1], p[2])
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2.1, pos - Vector3.UP * 3.1, 1)
			var hit := space.intersect_ray(q)
			samples += 1
			if hit.is_empty() or hit.collider.get_meta("world_surface", "") not in ["asphalt", "gravel", "shoulder"]:
				invalid.append("%s/%d %s" % [lane.id, i, hit.collider.name if not hit.is_empty() else "no hit"])
	check(invalid.is_empty(), "Pavement is the first collider on %d/%d lane rays. Exceptions %s" % [samples - invalid.size(), samples, str(invalid.slice(0, 16))])
	return samples

func drive_car(drive: Node, car_id: String) -> void:
	var pose = drive.find_road_pose(Vector3(-575, 0, 545), Vector3.RIGHT)
	if pose == null:
		check(false, "Road start available for " + car_id)
		return
	drive._spawn_vehicle(car_id, pose)
	for step in 48:
		await physics_frame
	var body = drive.vehicle_body
	var wheel_contact: bool = body.wheel_array.all(func(wheel: Wheel) -> bool: return wheel.is_colliding())
	check(body.has_node("CuratedCar") and wheel_contact, car_id + " mounts its body, steering wheels and settles on four contacts")
	Input.action_press("drive_throttle", 0.76)
	for step in 168:
		await physics_frame
	Input.action_release("drive_throttle")
	check(drive.adapter.get_speed_mps() > 2.0 and drive.adapter.get_gear_display() == "1", car_id + " drives under live throttle")

func sweep_corridors(drive: Node) -> void:
	var passes := 0
	var count := 0
	var gravel := 0
	var space: PhysicsDirectSpaceState3D = drive.get_world_3d().direct_space_state
	for corridor: Dictionary in drive.world.get_physical_road_centerlines():
		var points: PackedVector3Array = corridor.points
		var driven := 0
		for fraction: float in [0.24, 0.50, 0.74]:
			var i := clampi(roundi(points.size() * fraction), 1, points.size() - 2)
			var heading := (points[i + 1] - points[i - 1]).normalized()
			# Use the downhill lane direction for sample starts on steep roads.
			if heading.y > 0.035:
				heading = -heading
			var q := PhysicsRayQueryParameters3D.create(points[i] + Vector3.UP * 3.0, points[i] - Vector3.UP * 3.0, 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or hit.collider.get_meta("world_surface", "") != corridor.surface:
				continue
			var normal: Vector3 = hit.normal
			var pose := Transform3D(Basis.looking_at(heading.slide(normal), normal), hit.position + normal * 0.58)
			drive.adapter.reset_to(pose)
			drive.camera.snap_to_vehicle()
			Input.action_press("drive_throttle", 0.68)
			for step in 166:
				await physics_frame
			Input.action_release("drive_throttle")
			var displacement: float = drive.vehicle_body.global_position.distance_to(pose.origin)
			if displacement > 3.5 and drive.adapter.get_speed_mps() > 3.0:
				driven += 1
		passes += int(driven > 0)
		count += 1
		gravel += int(corridor.surface == "gravel" and driven > 0)
		print("CORRIDOR ", corridor.id, " ", corridor.surface, " ", driven, "/3 live drive samples")
	check(count == 16 and passes == count and gravel > 0, "Live car moved on all %d corridors, including %d gravel" % [passes, gravel])

func audit_mesh(mesh: Mesh, override: Material = null) -> void:
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		audit_material(override if override != null else mesh.surface_get_material(i))

func audit_material(material: Material) -> void:
	if material == null or seen.has(material.get_instance_id()):
		return
	seen[material.get_instance_id()] = true
	materials_checked += 1
	if material is StandardMaterial3D:
		for texture in [material.albedo_texture, material.normal_texture, material.ao_texture, material.roughness_texture, material.metallic_texture]:
			if texture != null:
				audit_texture(texture)
	elif material is ShaderMaterial:
		if material.shader == null:
			check(false, "Shader material without shader")
			return
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var resource = material.get_shader_parameter(uniform.name)
			if resource is Texture2D:
				audit_texture(resource)

func audit_texture(texture: Texture2D) -> void:
	texture_bindings += 1
	if texture.get_width() < 1 or texture.get_height() < 1 or "/payload/" in texture.resource_path:
		check(false, "Invalid or source-only runtime texture " + texture.resource_path)

func has_foliage_cutout(asset: String) -> bool:
	var mesh := PremiumMesh.fit(asset, Vector3(3, 5, 3))
	if mesh == null:
		return false
	for surface in mesh.get_surface_count():
		var mat := mesh.surface_get_material(surface) as StandardMaterial3D
		if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or mat.albedo_texture == null:
			continue
		var pixels := mat.albedo_texture.get_image()
		if pixels != null and (not pixels.is_compressed() or pixels.decompress() == OK):
			if pixels.detect_alpha() != Image.ALPHA_NONE:
				return true
	return false

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
