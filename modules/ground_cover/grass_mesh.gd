extends RefCounted
## Original opaque curved ribbons; local root plane y=0, UV.y is flex.
const HEIGHTS := [0.15, 0.24, 0.39, 0.27, 0.20]
const WIDTHS := [0.012, 0.014, 0.018, 0.012, 0.017]
const TINTS := [Color("607c37"), Color("718344"), Color("65783d"), Color("a49a60"), Color("496838")]
const MAX_BEND := 0.24

static func make_geometry(species: int, lod: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 67123 + species * 197
	var blades: int = [8, 5, 3][lod]
	var segments: int = [4, 2, 1][lod]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for blade in range(blades):
		var angle := float(blade) * 2.399963 + rng.randf_range(-0.3, 0.3)
		var along := Vector3(cos(angle), 0, sin(angle))
		var side := along.cross(Vector3.UP)
		var root := along * rng.randf_range(0.015, 0.065)
		var height: float = HEIGHTS[species] * rng.randf_range(0.72, 1.2)
		var width: float = WIDTHS[species] * rng.randf_range(0.8, 1.2)
		var lean := rng.randf_range(0.25, 0.65) * height
		var tint: Color = TINTS[species].lightened(rng.randf_range(-0.06, 0.09))
		var start := verts.size()
		for j in range(segments):
			var t := float(j) / float(segments)
			var mid := root + Vector3.UP * height * t + along * lean * t * t
			var half := width * (1.0 - t) * 0.5
			var normal := along.lerp(Vector3.UP, 0.65).normalized()
			for k in range(2):
				verts.append(mid + side * half * (-1.0 if k == 0 else 1.0))
				normals.append(normal)
				uvs.append(Vector2(blade, t))
				colors.append(tint)
			if j > 0:
				var a := start + (j - 1) * 2
				indices.append_array(PackedInt32Array([a, a+1, a+2, a+2, a+1, a+3]))
		var tip := verts.size()
		verts.append(root + Vector3.UP * height + along * lean)
		normals.append(along.lerp(Vector3.UP, 0.65).normalized())
		uvs.append(Vector2(blade, 1))
		colors.append(tint)
		indices.append_array(PackedInt32Array([tip-2, tip-1, tip]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var bounds := AABB(Vector3.ZERO, Vector3.ZERO)
	for vertex: Vector3 in verts:
		bounds = bounds.expand(vertex)
	return {"arrays":arrays,"bounds":bounds,"estimated_bytes":verts.size()*48+indices.size()*4,"triangles":indices.size()/3}

static func make_mesh(species: int, lod: int, material: Material) -> ArrayMesh:
	return mesh_from_geometry(make_geometry(species,lod),material)

static func mesh_from_geometry(geometry: Dictionary, material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, geometry.arrays)
	mesh.surface_set_material(0, material)
	return mesh

# Godot MultiMesh TRANSFORM_3D + custom data: 12 row-major transform
# floats followed by four custom-data floats. Use one bulk upload per species.
static func write_instance(buffer: PackedFloat32Array, offset: int, frame: Transform3D, seed: float) -> void:
	var b := frame.basis
	var p := frame.origin
	buffer[offset] = b.x.x
	buffer[offset+1] = b.y.x
	buffer[offset+2] = b.z.x
	buffer[offset+3] = p.x
	buffer[offset+4] = b.x.y
	buffer[offset+5] = b.y.y
	buffer[offset+6] = b.z.y
	buffer[offset+7] = p.y
	buffer[offset+8] = b.x.z
	buffer[offset+9] = b.y.z
	buffer[offset+10] = b.z.z
	buffer[offset+11] = p.z
	buffer[offset+12] = seed
	buffer[offset+13] = clampf(0.5 - p.x / 16.0, 0.0, 1.0)
	buffer[offset+14] = clampf(0.5 - p.z / 16.0, 0.0, 1.0)
	buffer[offset+15] = 1.0

static func sweep_aabb(bounds: AABB, frame: Transform3D) -> AABB:
	# World-space horizontal shader displacement is at most MAX_BEND.
	return (frame * bounds).grow(MAX_BEND)

static func swept_bounds(mesh: Mesh, frame: Transform3D) -> AABB:
	# Shader displacement is clamped in world metres, independent of scale.
	return sweep_aabb(mesh.get_aabb(),frame)
