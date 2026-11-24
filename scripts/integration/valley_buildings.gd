extends RefCounted
## Roadside buildings assembled by material so facade details stay in instanced batches.

const PLASTER = preload("res://assets/valley_art/plaster.jpg")
const PLASTER_NORMAL = preload("res://assets/valley_art/plaster_normal.jpg")
const STONE = preload("res://assets/forza_env/textures/stone_wall/albedo.jpg")
const STONE_NORMAL = preload("res://assets/forza_env/textures/stone_wall/normal.png")
const ROOF = preload("res://assets/forza_env/textures/roof_slate/albedo.jpg")
const ROOF_NORMAL = preload("res://assets/forza_env/textures/roof_slate/normal.png")
const WOOD = preload("res://assets/forza_env/textures/wood_planks/albedo.jpg")
const WOOD_NORMAL = preload("res://assets/forza_env/textures/wood_planks/normal.png")
const METAL = preload("res://assets/forza_env/textures/corrugated_metal/albedo.jpg")
const METAL_NORMAL = preload("res://assets/forza_env/textures/corrugated_metal/normal.png")

var _surfaces: Dictionary = {}

func assets() -> Dictionary:
	return {
		"content/scenery/models/town_house.gltf": [_house(0), _house(1), _house(2)],
		"content/scenery/models/barn.gltf": [_industrial(true)],
		"content/scenery/models/garage.gltf": [_industrial(false)],
	}

func _house(variant: int) -> ArrayMesh:
	_surfaces.clear()
	var width := 11.5
	var depth := 8.9
	var wall_top := [5.75, 6.35, 7.05][variant] as float
	var peak := [2.60, 2.86, 2.18][variant] as float
	_box("stone", Vector3(0, -0.12, 0), Vector3(width + 0.22, 1.42, depth + 0.22))
	_box("plaster", Vector3(0, wall_top * 0.5, 0), Vector3(width, wall_top, depth))
	_gable(width, depth, wall_top, peak)
	for direction in [0, 1, 2, 3]:
		var yaw: float = direction * PI * 0.5
		var face := depth * 0.5 if direction % 2 == 0 else width * 0.5
		var span := width if direction % 2 == 0 else depth
		for side in [-1, 1]:
			_facade("timber", Vector3(side * (span * 0.5 - 0.26), wall_top * 0.53, face + 0.075), Vector3(0.24, wall_top - 0.65, 0.16), yaw)
			_facade("dark", Vector3(side * (span * 0.5 - 0.20), wall_top * 0.47, face + 0.15), Vector3(0.095, wall_top - 0.50, 0.11), yaw)
		for z in [1.41, wall_top - 0.17]:
			_facade("trim", Vector3(0, z, face + 0.03), Vector3(span + 0.08, 0.17, 0.18), yaw)
		for floor in [2.43, wall_top - 1.57]:
			for x in ([-3.28, 0.0, 3.28] if direction % 2 == 0 else [-2.05, 2.05]):
				if floor < 3.0 and x == 0.0:
					continue
				_window(x, floor, face, 1.19, 1.52, yaw, variant)
		if direction % 2 == 0:
			_facade("dark", Vector3(0, 1.52, face + 0.07), Vector3(1.36, 2.65, 0.18), yaw)
			_facade("timber", Vector3(0, 1.53, face + 0.173), Vector3(1.1, 2.38, 0.075), yaw)
			_facade("stone", Vector3(0, 0.15, face + 0.46), Vector3(2.14, 0.34, 0.94), yaw)
			var canopy := Vector3(0, 3.01, face + 0.56)
			_facade("roof", canopy, Vector3(2.32, 0.20, 1.25), yaw)
			for x in [-0.94, 0.94]:
				_facade("timber", Vector3(x, 1.54, face + 0.95), Vector3(0.13, 2.88, 0.13), yaw)
	_box("stone", Vector3(3.14, wall_top + peak * 0.78, 1.64), Vector3(0.82, 2.71, 0.93))
	_box("dark", Vector3(3.14, wall_top + peak * 0.78 + 1.38, 1.64), Vector3(1.01, 0.21, 1.15))
	return _finish(variant)

func _industrial(barn: bool) -> ArrayMesh:
	_surfaces.clear()
	var width := 15.0 if barn else 14.0
	var depth := 11.0 if barn else 10.0
	var top := 6.4 if barn else 6.8
	_box("stone", Vector3(0, -0.26, 0), Vector3(width + 0.3, 1.6, depth + 0.3))
	_box("timber" if barn else "plaster", Vector3(0, top * 0.5, 0), Vector3(width, top, depth))
	_gable(width, depth, top, 3.1 if barn else 1.29)
	for yaw in [0.0, PI]:
		for bay in [-3.35, 3.35]:
			var face := depth * 0.5
			_facade("dark", Vector3(bay, 2.39, face + 0.06), Vector3(5.3, 4.75, 0.12), yaw)
			_facade("metal" if not barn else "timber", Vector3(bay, 2.39, face + 0.18), Vector3(4.83, 4.39, 0.14), yaw)
			for line in range(1, 7):
				_facade("dark", Vector3(bay, 0.41 + line * 0.55, face + 0.26), Vector3(4.84, 0.04, 0.055), yaw)
			_window(bay, top - 0.68, face, 2.55, 0.64, yaw, 1)
		_facade("roof", Vector3(0, top - 0.05, depth * 0.5 + 0.43), Vector3(width - 0.5, 0.16, 1.05), yaw)
	for yaw in [PI * 0.5, PI * 1.5]:
		for x in [-3.7, -1.2, 1.2, 3.7]:
			_window(x, 3.75, width * 0.5, 1.02, 1.38, yaw, 0)
	return _finish(2 if barn else 1)

func _gable(width: float, depth: float, top: float, peak: float) -> void:
	var edge := width * 0.5 + 0.52
	var front := depth * 0.5 + 0.61
	for side in [-1, 1]:
		var low := Vector3(edge * side, top - 0.19, -front)
		var high := Vector3(0, top + peak, -front)
		var far_low := low + Vector3.BACK * front * 2.0
		var far_high := high + Vector3.BACK * front * 2.0
		_quad("roof", low, high, far_low, far_high, Vector3(side * peak, edge, 0).normalized())
		_box("metal", Vector3(edge * side, top - 0.22, 0), Vector3(0.20, 0.16, front * 2.0))
		for fas in [-1, 1]:
			var d := -low + high
			var angle := atan2(d.y, d.x)
			var cap := Vector3(low.x * 0.5, top + peak * 0.5 - 0.19, fas * front)
			_box("dark", cap, Vector3(d.length() + 0.13, 0.22, 0.19), Basis(Vector3.BACK, angle))
	_box("roof", Vector3(0, top + peak, 0), Vector3(0.30, 0.20, front * 2.0 + 0.12))
	for side: int in [-1, 1]:
		var face := depth * 0.5 * side
		var normal := Vector3.BACK * side
		_triangle("plaster", Vector3(-width * 0.5, top, face), Vector3(width * 0.5, top, face), Vector3(0, top + peak, face), normal)

func _window(x: float, y: float, face: float, w: float, h: float, yaw: float, variant: int) -> void:
	_facade("dark", Vector3(x, y, face + 0.056), Vector3(w + 0.31, h + 0.31, 0.15), yaw)
	_facade("glass", Vector3(x, y, face + 0.149), Vector3(w, h, 0.075), yaw)
	for side in [-1, 1]:
		_facade("trim", Vector3(x + side * (w * 0.51), y, face + 0.212), Vector3(0.12, h + 0.15, 0.15), yaw)
		_facade("trim", Vector3(x, y + side * (h * 0.50), face + 0.212), Vector3(w + 0.16, 0.11, 0.15), yaw)
		if variant == 2 and h > 1:
			_facade("timber", Vector3(x + side * (w * 0.76), y, face + 0.16), Vector3(w * 0.37, h + 0.06, 0.13), yaw)
	_facade("trim", Vector3(x, y, face + 0.231), Vector3(0.058, h, 0.07), yaw)
	_facade("trim", Vector3(x, y, face + 0.231), Vector3(w, 0.056, 0.07), yaw)
	_facade("stone", Vector3(x, y - h * 0.55, face + 0.26), Vector3(w + 0.47, 0.14, 0.54), yaw)

func _facade(kind: String, point: Vector3, size: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_box(kind, basis * point, size, basis)

func _box(kind: String, center: Vector3, size: Vector3, rotation := Basis.IDENTITY) -> void:
	for face: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var side := Vector3.RIGHT if absf(face.dot(Vector3.UP)) > 0.5 else Vector3.UP
		var right := face.cross(side)
		var a := center + rotation * ((face + side - right) * size * 0.5)
		var b := center + rotation * ((face + side + right) * size * 0.5)
		var c := center + rotation * ((face - side - right) * size * 0.5)
		var d := center + rotation * ((face - side + right) * size * 0.5)
		_quad(kind, a, b, c, d, rotation * face)

func _quad(kind: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_triangle(kind, a, b, c, normal)
	_triangle(kind, b, d, c, normal)

func _triangle(kind: String, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if not _surfaces.has(kind):
		var part := SurfaceTool.new()
		part.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[kind] = part
	var part: SurfaceTool = _surfaces[kind]
	var vertices := [a, c, b] if (b - a).cross(c - a).dot(normal) > 0.0 else [a, b, c]
	for point: Vector3 in vertices:
		var axis := absf(normal.x) > absf(normal.z)
		var uv := Vector2(point.x, point.z) if absf(normal.y) > 0.56 else Vector2(point.z if axis else point.x, point.y)
		part.set_normal(normal)
		part.set_uv(uv * (0.36 if kind == "plaster" else 0.68))
		part.add_vertex(point)

func _finish(variant: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var surface_materials := {
		"plaster": _material([Color("#d7c4a1"), Color("#a8bec0"), Color("#dcccb3")][variant], PLASTER, PLASTER_NORMAL),
		"stone": _material(Color("#c5b39c"), STONE, STONE_NORMAL),
		"roof": _material([Color("#a7a293"), Color("#a1a1a4"), Color("#b4947d")][variant], ROOF, ROOF_NORMAL),
		"timber": _material([Color("#788570"), Color("#807059"), Color("#9e5b42")][variant], WOOD, WOOD_NORMAL),
		"dark": _material(Color("#3b3329"), WOOD, WOOD_NORMAL),
		"trim": _material(Color("#d1c0a0"), WOOD, WOOD_NORMAL),
		"metal": _material(Color("#a6aaa6"), METAL, METAL_NORMAL),
		"glass": _material(Color("#405762")),
	}
	for name: String in _surfaces:
		var surface: SurfaceTool = _surfaces[name]
		surface.set_material(surface_materials[name])
		surface.generate_tangents()
		surface.index()
		surface.commit(mesh)
	return mesh

func _material(tint: Color, albedo: Texture2D = null, normals: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	material.albedo_texture = albedo
	material.normal_enabled = normals != null
	material.normal_texture = normals
	material.normal_scale = 0.57
	material.roughness = 0.83 if albedo != null else 0.22
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material
