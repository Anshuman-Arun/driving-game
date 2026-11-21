extends Node3D
## Needle Pass visual-only art overlay. No collisions or vehicle/gameplay ownership.
## Works standalone after staging or as an instance within an integrated repo.
@export var render_terrain_visual: bool = true
@export var render_road_visual: bool = true
@export_range(0, 2) var foliage_quality: int = 2
@export var add_lighting: bool = true
@export_range(0, 5) var initial_viewpoint: int = 0
@export var enable_showcase_camera: bool = true
@export var show_viewpoint_ui: bool = false
@export var show_legacy_procedural_cliffs: bool = false

const VIEW_NAMES := [
	"01 Road-level wide shot", "02 Roadside ground study",
	"03 Dense forest interior", "04 Rock / road transition",
	"05 Mountain vista", "06 Golden hour"
]

var _data: Dictionary = {}
var _route: PackedVector3Array = PackedVector3Array()
var _heights: Array = []
var _origin_x: float = 0.0
var _origin_z: float = 0.0
var _nx: int = 0
var _nz: int = 0
var _step: float = 4.0
var _camera: Camera3D
var _caption: Label
var _rock_material: StandardMaterial3D
var _shots: Array = []
var _batches: Dictionary = {}

func _ready() -> void:
	var file_path := "res://data/corridor_v1.json"
	if not FileAccess.file_exists(file_path):
		file_path = "res://showcase/environment_hd/data/corridor_v1.json"
	if not FileAccess.file_exists(file_path):
		push_error("Needle Pass: canonical corridor_v1.json not found")
		return
	var decoded = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if typeof(decoded) != TYPE_DICTIONARY:
		push_error("Needle Pass: malformed corridor JSON")
		return
	_data = decoded
	var patch: Dictionary = _data["patch"]
	_origin_x = float(patch["origin_x"])
	_origin_z = float(patch["origin_z"])
	_nx = int(patch["nx"])
	_nz = int(patch["nz"])
	_step = float(patch["spacing_m"])
	_heights = patch["heights_cm"]
	if _heights.size() != _nx * _nz:
		push_error("Needle Pass: elevation sample count mismatch")
		return
	for source_point in _data["road_center"]:
		_route.append(Vector3(float(source_point[0]), float(source_point[1]), float(source_point[2])))
	if _route.size() < 2:
		push_error("Needle Pass: no road segment")
		return
	_load_authored_shots()
	_rock_material = _make_rock_material()
	if render_terrain_visual:
		_build_terrain()
	if render_road_visual:
		_build_roads()
	_place_scenery()
	_flush_batches()
	if show_legacy_procedural_cliffs:
		_place_hero_geology()
	_place_road_furniture()
	if add_lighting:
		_setup_light()
	if enable_showcase_camera:
		_setup_cameras()

func _asset_path(relative_path: String) -> String:
	var integrated := "res://assets/environment_hd/" + relative_path
	if ResourceLoader.exists(integrated):
		return integrated
	return "res://staged_assets/" + relative_path

func _tex(relative_path: String) -> Texture2D:
	var p := _asset_path("textures/" + relative_path)
	if not ResourceLoader.exists(p):
		push_warning("Needle Pass missing texture: " + p)
		return null
	return load(p) as Texture2D

func _make_rock_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "Rock063 scanned PBR / CC0"
	m.albedo_texture = _tex("rock_color.jpg")
	m.normal_enabled = true
	m.normal_texture = _tex("rock_normal.jpg")
	m.normal_scale = 0.85
	m.roughness_texture = _tex("rock_rough.jpg")
	m.roughness = 0.96
	m.metallic = 0.0
	m.uv1_scale = Vector3(0.30, 0.30, 0.30)
	return m

func _height(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, _nx - 1)
	iz = clampi(iz, 0, _nz - 1)
	return float(_heights[iz * _nx + ix]) * 0.01

func surface_height(x: float, z: float) -> float:
	var fx: float = clampf((x - _origin_x) / _step, 0.0, float(_nx - 1))
	var fz: float = clampf((z - _origin_z) / _step, 0.0, float(_nz - 1))
	var ix := mini(int(floorf(fx)), _nx - 2)
	var iz := mini(int(floorf(fz)), _nz - 2)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	return lerpf(lerpf(_height(ix, iz), _height(ix + 1, iz), tx), lerpf(_height(ix, iz + 1), _height(ix + 1, iz + 1), tx), tz)

func _build_terrain() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var texcoords := PackedVector2Array()
	var faces := PackedInt32Array()
	for z in range(_nz):
		for x in range(_nx):
			var h := _height(x, z)
			vertices.append(Vector3(_origin_x + x * _step, h + 0.04, _origin_z + z * _step))
			var n := Vector3(_height(x - 1, z) - _height(x + 1, z), 2.0 * _step, _height(x, z - 1) - _height(x, z + 1)).normalized()
			normals.append(n)
			texcoords.append(Vector2(float(x) * 0.16, float(z) * 0.16))
	for z in range(_nz - 1):
		for x in range(_nx - 1):
			var a := z * _nx + x
			faces.append_array(PackedInt32Array([a, a + _nx, a + 1, a + 1, a + _nx, a + _nx + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = texcoords
	arrays[Mesh.ARRAY_INDEX] = faces
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "CanonicalTerrainVisual_NoCollision"
	instance.mesh = mesh
	instance.material_override = _make_ground_material()
	add_child(instance)

func _make_ground_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(_asset_path("shaders/ground_triplanar.gdshader")) as Shader
	if m.shader == null:
		push_error("Needle Pass: ground shader missing")
		return m
	m.set_shader_parameter("ground_albedo", _tex("ground_color.jpg"))
	m.set_shader_parameter("ground_roughness", _tex("ground_rough.jpg"))
	m.set_shader_parameter("rock_albedo", _tex("rock_color.jpg"))
	m.set_shader_parameter("rock_roughness", _tex("rock_rough.jpg"))
	return m

func _simple_material(color: Color, roughness: float = 0.94) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

func _ribbon(points: PackedVector3Array, width: float, lateral: float, lift: float, conform_edges: bool = false) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var texcoords := PackedVector2Array()
	var indices := PackedInt32Array()
	var progress := 0.0
	for i in range(points.size()):
		var p := points[i]
		var previous := points[maxi(0, i - 1)]
		var following := points[mini(points.size() - 1, i + 1)]
		var d := following - previous
		d.y = 0.0
		d = d.normalized()
		var side := Vector3(d.z, 0.0, -d.x)
		var centre := p + side * lateral + Vector3.UP * lift
		var normal := d.cross(side).normalized()
		for edge in [-1.0, 1.0]:
			var vertex: Vector3 = centre + side * float(edge) * width * 0.5
			if conform_edges:
				# Blend the outer verge back onto the unmodified canonical terrain.
				vertex.y = lerpf(vertex.y, surface_height(vertex.x, vertex.z) + 0.07, 0.90)
			vertices.append(vertex)
			normals.append(normal)
			tangents.append_array(PackedFloat32Array([side.x, side.y, side.z, 1.0]))
			texcoords.append(Vector2((edge + 1.0) * width / 6.0, progress / 3.0))
		if i < points.size() - 1:
			var a := i * 2
			indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
			progress += points[i].distance_to(points[i + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = texcoords
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_ribbon(name: String, width: float, lateral: float, lift: float, material: Material, conform_edges: bool = false) -> void:
	var obj := MeshInstance3D.new()
	obj.name = name
	obj.mesh = _ribbon(_route, width, lateral, lift, conform_edges)
	obj.material_override = material
	obj.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(obj)

func _paint_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(_asset_path("shaders/paint_wear.gdshader")) as Shader
	material.set_shader_parameter("paint_color", color)
	return material

func _build_roads() -> void:
	var earth := _simple_material(Color(0.26, 0.24, 0.18))
	earth.albedo_texture = _tex("ground_color.jpg")
	earth.roughness_texture = _tex("ground_rough.jpg")
	earth.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_add_ribbon("OuterGravelBlendedIntoTerrain_NoCollision", 13.8, 0.0, 0.07, earth, true)
	_add_ribbon("CompactedStonyShoulder_NoCollision", 10.2, 0.0, 0.115, earth, true)
	var road := ShaderMaterial.new()
	road.shader = load(_asset_path("shaders/road_wear.gdshader")) as Shader
	road.set_shader_parameter("asphalt_albedo", _tex("asphalt_color.jpg"))
	road.set_shader_parameter("asphalt_roughness", _tex("asphalt_rough.jpg"))
	_add_ribbon("NeedlePass_Asphalt_NoCollision", float(_data["road_width_m"]), 0.0, 0.165, road)
	var white := _paint_material(Color(0.76, 0.76, 0.67))
	var gold := _paint_material(Color(0.76, 0.51, 0.14))
	_add_ribbon("WestEdgePaint", 0.12, -3.17, 0.187, white)
	_add_ribbon("EastEdgePaint", 0.12, 3.17, 0.187, white)
	_add_ribbon("CenterPaint_A", 0.11, -0.13, 0.189, gold)
	_add_ribbon("CenterPaint_B", 0.11, 0.13, 0.189, gold)

func _instance_model(relative_path: String, name: String, at: Vector3, yaw_deg: float, scale_factor: float, material: Material = null) -> Node3D:
	var path := _asset_path("models/" + relative_path)
	var res := load(path) as PackedScene
	if res == null:
		push_warning("Needle Pass missing model: " + path)
		return null
	var node := res.instantiate() as Node3D
	if node == null:
		return null
	node.name = name
	node.position = at
	node.rotation_degrees.y = yaw_deg
	node.scale = Vector3.ONE * scale_factor
	add_child(node)
	if material != null:
		_apply_material_recursive(node, material)
	return node

func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for c in node.get_children():
		_apply_material_recursive(c, material)

func _queue_batch(model: String, at: Vector3, yaw: float, factor: float, rock: bool = false) -> void:
	# Spatial cells keep the AABBs tight enough for Godot frustum culling.
	var cell := "%d:%d" % [floori(at.x / 72.0), floori(at.z / 72.0)]
	var key := model + "|" + cell
	var item: Dictionary = _batches.get(key, {})
	if item.is_empty():
		item = {"model": model, "rock": rock, "instances": []}
	var records: Array = item["instances"]
	records.append({"at": at, "yaw": yaw, "factor": factor})
	_batches[key] = item

func _collect_model_meshes(node: Node, parent_transform: Transform3D, meshes: Array) -> void:
	var local := parent_transform
	if node is Node3D:
		local = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var m := node as MeshInstance3D
		if m.mesh != null:
			meshes.append({"mesh": m.mesh, "transform": local, "material": m.material_override})
	for child in node.get_children():
		_collect_model_meshes(child, local, meshes)

func _flush_batches() -> void:
	for key in _batches.keys():
		var entry: Dictionary = _batches[key]
		var model: String = entry["model"]
		var packed := load(_asset_path("models/" + model)) as PackedScene
		if packed == null:
			push_warning("Needle Pass missing batched model: " + model)
			continue
		var source := packed.instantiate()
		if source == null:
			push_warning("Needle Pass cannot instantiate batched model: " + model)
			continue
		var meshes: Array = []
		_collect_model_meshes(source, Transform3D.IDENTITY, meshes)
		source.free()
		var instances: Array = entry["instances"]
		for mesh_index in range(meshes.size()):
			var mesh_data: Dictionary = meshes[mesh_index]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh_data["mesh"] as Mesh
			mm.instance_count = instances.size()
			var subtransform: Transform3D = mesh_data["transform"]
			for i in range(instances.size()):
				var record: Dictionary = instances[i]
				var placement := Transform3D(Basis(Vector3.UP, deg_to_rad(float(record["yaw"]))), record["at"])
				placement.basis = placement.basis.scaled(Vector3.ONE * float(record["factor"]))
				mm.set_instance_transform(i, placement * subtransform)
			var node := MultiMeshInstance3D.new()
			node.name = "Culled_" + model.get_basename().replace(".", "_") + "_" + str(mesh_index)
			node.multimesh = mm
			if bool(entry["rock"]):
				node.material_override = _rock_material
			else:
				node.material_override = mesh_data["material"] as Material
			node.visibility_range_end = 380.0 if model.begins_with("cedar_fir") else 560.0
			node.visibility_range_end_margin = 40.0
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(node)
	_batches.clear()

func _place_scenery() -> void:
	var n := 0
	for item in _data["placements"]:
		var pos := Vector3(float(item["p"][0]), float(item["p"][1]), float(item["p"][2]))
		var clearance := float(item["clearance"])
		var factor := float(item["scale"])
		var yaw := float(item["yaw"])
		var kind: String = item["asset"]
		var model := ""
		match kind:
			"pine":
				if foliage_quality >= 2 and clearance > 14.0 and n % 4 != 0:
					model = "cedar_fir_a.gltf" if n % 3 == 0 else "cedar_fir_b.gltf"
					factor *= 0.92
				else:
					model = "pine_lod0.glb" if foliage_quality > 0 and clearance < 100.0 else "pine_lod1.glb"
				n += 1
			"rock", "boulder":
				model = "boulder.glb"
			"shrub":
				model = "fern_clump.gltf" if foliage_quality > 0 and n % 3 != 0 else "shrub.glb"
				n += 1
			"arch":
				model = "stone_arch.gltf"
			_:
				continue
		if kind == "arch":
			_instance_model(model, str(item["id"]), pos, yaw, factor)
		else:
			_queue_batch(model, pos, yaw, factor, kind == "rock" or kind == "boulder")

func _place_hero_geology() -> void:
	# 3 curated repeated rock cuts, wide berth from road. Collision stays in World Runtime.
	for i in range(3):
		var index := [24, 45, 66][i]
		var anchor := _route[index]
		var tangent := (_route[index + 3] - _route[index - 3]).normalized()
		tangent.y = 0.0
		var side := Vector3(-tangent.z, 0.0, tangent.x)
		var direction := -1.0 if i == 1 else 1.0
		var centre := anchor + side * direction * 53.0
		centre.y = surface_height(centre.x, centre.z) - 1.0
		var yaw := -rad_to_deg(atan2(tangent.z, tangent.x))
		# Front-facing normals of the scanned-textured cliff point towards the roadway.
		if direction > 0.0:
			yaw += 180.0
		_instance_model("cliff_rockface_a.gltf" if i != 1 else "cliff_rockface_b.gltf", "EscarpmentArt_%d" % i, centre, yaw, 1.0 + 0.13 * i, _rock_material)

func _place_road_furniture() -> void:
	if foliage_quality == 0:
		return
	for index in [30, 31, 32, 49, 50, 51]:
		var p := _route[index]
		var t := (_route[index + 1] - _route[index - 1]).normalized()
		t.y = 0.0
		var edge := Vector3(t.z, 0.0, -t.x)
		var place := p + edge * 5.7
		place.y = surface_height(place.x, place.z) + 0.15
		_instance_model("guardrail.glb", "GuardrailArt_%d" % index, place, -rad_to_deg(atan2(t.z, t.x)), 1.0)

func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "NeedlePassLateAfternoonSun"
	sun.rotation_degrees = Vector3(-35.0, -41.0, 0.0)
	sun.light_color = Color(1.0, 0.88, 0.75)
	sun.light_energy = 1.45
	sun.light_angular_distance = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	var sky := Sky.new()
	var sky_material := PhysicalSkyMaterial.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_density = 0.0017
	environment.fog_light_color = Color(0.79, 0.82, 0.83)
	var world_env := WorldEnvironment.new()
	world_env.name = "PortfolioEnvironment"
	world_env.environment = environment
	add_child(world_env)

func _load_authored_shots() -> void:
	var p := "res://data/camera_shots_v2.json"
	if not FileAccess.file_exists(p):
		p = "res://showcase/environment_hd/data/camera_shots_v2.json"
	if not FileAccess.file_exists(p):
		push_error("Needle Pass: fixed camera shot manifest missing")
		return
	var decoded = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(decoded) != TYPE_DICTIONARY:
		push_error("Needle Pass: camera manifest is not a JSON object")
		return
	_shots = decoded.get("shots", [])
	if _shots.size() != 6:
		push_error("Needle Pass: expected six fixed camera compositions")

func _setup_cameras() -> void:
	_camera = Camera3D.new()
	_camera.name = "PortfolioComparisonCamera"
	_camera.near = 0.1
	_camera.far = 1600.0
	add_child(_camera)
	if show_viewpoint_ui:
		var canvas := CanvasLayer.new()
		canvas.name = "OptionalCameraLabels"
		add_child(canvas)
		_caption = Label.new()
		_caption.position = Vector2(24.0, 25.0)
		_caption.add_theme_font_size_override("font_size", 18)
		_caption.add_theme_color_override("font_color", Color(0.95, 0.95, 0.88))
		canvas.add_child(_caption)
	_select_view(clampi(initial_viewpoint, 0, 5))

func _select_view(view: int) -> void:
	if _camera == null or _shots.size() != 6:
		return
	var shot: Dictionary = _shots[view]
	var eye: Array = shot["camera"]
	var aim: Array = shot["target"]
	_camera.global_position = Vector3(float(eye[0]), float(eye[1]), float(eye[2]))
	_camera.fov = float(shot["vertical_fov_deg"])
	_camera.look_at(Vector3(float(aim[0]), float(aim[1]), float(aim[2])), Vector3.UP)
	_camera.current = true
	if _caption != null:
		_caption.text = "ASTER VALLEY / NEEDLE PASS\n" + str(shot["name"]) + " • press 1–6"

func _unhandled_key_input(event: InputEvent) -> void:
	if enable_showcase_camera and event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.keycode
		if code >= KEY_1 and code <= KEY_6:
			_select_view(code - KEY_1)
