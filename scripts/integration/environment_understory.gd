extends Node3D
## Bounded optional visual-only placement of C records with B's licensed meshes.
const Mask := preload("res://modules/ground_cover/biome_mask.gd")
const ASSETS := "res://assets/environment_overhaul/"
const CAP := 1600
const CELL := 32.0
const SPECIES := ["fern", "shrub", "sapling", "reed", "wildflower"]
var report: Dictionary = {}
var _occupied: Dictionary = {}

func _fail(reason: String) -> bool:
	report["error"] = reason
	return false

func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _parts(node: Node, parent: Transform3D, result: Array) -> void:
	var frame := parent
	if node is Node3D:
		frame = parent * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			result.append({"mesh": mesh, "frame": frame, "bounds": frame * mesh.get_aabb()})
	for child: Node in node.get_children():
		_parts(child, frame, result)

func _load_species(entry: Dictionary) -> Dictionary:
	if str(entry.get("origin", "")) != "ground_center" or str(entry.get("license", "")) != "CC0-1.0":
		return {}
	if not entry.get("sha256_by_path") is Dictionary:
		return {}
	var lods: Array = []
	var union := AABB()
	var first := true
	for lod: String in ["lod0", "lod1"]:
		var path := str(entry.get(lod, ""))
		if not path.begins_with(ASSETS) or path.contains("..") or not path.ends_with(".gltf"):
			return {}
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(entry.sha256_by_path.get(path, "")):
			return {}
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null:
			return {}
		var scene := packed.instantiate()
		var parts: Array = []
		_parts(scene, Transform3D.IDENTITY, parts)
		scene.free()
		if parts.is_empty():
			return {}
		for part: Dictionary in parts:
			var box: AABB = part.bounds
			if not box.has_volume() or not box.position.is_finite() or not box.size.is_finite():
				return {}
			union = box if first else union.merge(box)
			first = false
		lods.append(parts)
	return {"lods": lods, "bounds": union}

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / 4.0), floori(point.y / 4.0))

func _reserve(rect: Rect2) -> void:
	var lo := _cell(rect.position)
	var hi := _cell(rect.end)
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var key := Vector2i(x, z)
			if not _occupied.has(key):
				_occupied[key] = []
			_occupied[key].append(rect)

func _free_footprint(rect: Rect2) -> bool:
	var lo := _cell(rect.position)
	var hi := _cell(rect.end)
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for other: Rect2 in _occupied.get(Vector2i(x, z), []):
				if rect.intersects(other, true):
					return false
	return true

func build(drive: Node, bounds: Rect2, mask_dir: String) -> bool:
	report = {"accepted": 0, "missing": 0, "unsafe": 0, "outside": 0, "cap_skips": 0, "species": {}}
	var world: Node = drive.world
	var mask := Mask.new()
	if not mask.load_package(mask_dir) or not mask.verify_production_sources(str(world.report.get("source_directory", ""))):
		return _fail("mask provenance: " + mask.error)
	var meta: Variant = _json(mask_dir.path_join("manifest.json"))
	var path := mask_dir.path_join("understory.json")
	var placement_data: Variant = _json(path)
	var assets: Variant = _json(ASSETS + "manifest.json")
	if not meta is Dictionary or not placement_data is Dictionary or not assets is Dictionary:
		return _fail("missing package")
	if placement_data.get("schema_version") != 1 or assets.get("schema_version") != 1 or placement_data.get("seed") != meta.get("seed") or placement_data.get("source_hashes") != meta.get("source_hashes"):
		return _fail("invalid package provenance")
	if FileAccess.get_sha256(path) != str(meta.get("understory_sha256", "")) or not placement_data.get("placements") is Array or not assets.get("assets") is Array:
		return _fail("invalid package contents")
	if placement_data.placements.size() > 12000 or assets.assets.size() > 64:
		return _fail("package budget exceeded")
	var index: Object = world.road_clearance
	if not is_instance_valid(index) or int(index.get("triangle_count")) <= 0:
		return _fail("road clearance unavailable")
	var species: Dictionary = {}
	for entry: Variant in assets.assets:
		if entry is Dictionary and entry.get("species_id") in SPECIES and not species.has(entry.species_id):
			var loaded := _load_species(entry)
			if not loaded.is_empty():
				species[entry.species_id] = loaded
	# C has already excluded source-authored props and water. Add actual live
	# retained plant footprints and current selective collider footprints.
	for rect: Rect2 in drive.vegetation.pilot_obstacles(bounds):
		_reserve(rect.grow(0.15))
	for shape_node: CollisionShape3D in drive.scenery.find_children("*", "CollisionShape3D", true, false):
		if shape_node.shape is BoxShape3D:
			var size: Vector3 = (shape_node.shape as BoxShape3D).size
			var box := shape_node.global_transform * AABB(-size * 0.5, size)
			var rect := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
			if bounds.intersects(rect):
				_reserve(rect.grow(0.15))
	var batches: Dictionary = {}
	for item: Variant in placement_data.placements:
		if not item is Dictionary:
			report.unsafe += 1
			continue
		var point := Vector2(float(item.get("x", NAN)), float(item.get("z", NAN)))
		var yaw := float(item.get("yaw_rad", NAN))
		var scale := float(item.get("scale", NAN))
		if not point.is_finite() or not is_finite(yaw) or not is_finite(scale) or scale <= 0.0 or scale > 4.0:
			report.unsafe += 1
			continue
		if not bounds.has_point(point):
			report.outside += 1
			continue
		var id := str(item.get("species_id", ""))
		if not species.has(id):
			report.missing += 1
			continue
		if int(report.accepted) >= CAP:
			report.cap_skips += 1
			continue
		var y: float = world.get_surface_height_at(point.x, point.y)
		if not is_finite(y):
			report.unsafe += 1
			continue
		var frame := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(point.x, y, point.y))
		var box: AABB = frame * (species[id].bounds as AABB)
		var footprint := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		if not bounds.encloses(footprint) or not _free_footprint(footprint.grow(0.15)) or bool(index.call("overlaps", box, 0.12, true)):
			report.unsafe += 1
			continue
		var safe := true
		for probe: Vector2 in [footprint.position, footprint.end, Vector2(footprint.position.x, footprint.end.y), Vector2(footprint.end.x, footprint.position.y)]:
			var height: float = world.get_surface_height_at(probe.x, probe.y)
			if not is_finite(height) or absf(height - y) > maxf(0.14, point.distance_to(probe) * 0.63):
				safe = false
		if not safe:
			report.unsafe += 1
			continue
		_reserve(footprint.grow(0.15))
		var cell := Vector3i(floori(point.x / CELL), floori(point.y / CELL), SPECIES.find(id))
		if not batches.has(cell):
			batches[cell] = []
		batches[cell].append(frame)
		report.accepted += 1
		report.species[id] = int(report.species.get(id, 0)) + 1
	for cell: Vector3i in batches:
		var id: String = SPECIES[cell.z]
		var origin := Vector3((cell.x + 0.5) * CELL, 0.0, (cell.y + 0.5) * CELL)
		var frames: Array = batches[cell]
		# Two nonoverlapping visibility ranges; same placements, no physical bodies.
		for lod in range(2):
			for part: Dictionary in species[id].lods[lod]:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = part.mesh
				mm.instance_count = frames.size()
				for i in frames.size():
					var instance: Transform3D = frames[i] * (part.frame as Transform3D)
					instance.origin -= origin
					mm.set_instance_transform(i, instance)
				var draw := MultiMeshInstance3D.new()
				draw.multimesh = mm
				draw.position = origin
				draw.visibility_range_begin = 0.0 if lod == 0 else 45.0
				draw.visibility_range_end = 45.0 if lod == 0 else 115.0
				draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(draw)
	_occupied.clear()
	print("Environment understory: ", report)
	return int(report.accepted) > 0
