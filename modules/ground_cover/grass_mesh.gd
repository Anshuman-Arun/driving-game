extends RefCounted
## Original opaque curved ribbons; local root plane y=0, UV.y is flex.
const HEIGHTS := [0.15, 0.24, 0.39, 0.27, 0.20]
const WIDTHS := [0.012, 0.014, 0.018, 0.012, 0.017]
const TINTS := [Color("607c37"), Color("718344"), Color("65783d"), Color("a49a60"), Color("496838")]
const MAX_BEND := 0.24

static func make_mesh(species: int, lod: int, material: Material) -> ArrayMesh:
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
				uvs.append(Vector2(k, t))
				colors.append(tint)
			if j > 0:
				var a := start + (j - 1) * 2
				indices.append_array(PackedInt32Array([a, a+1, a+2, a+2, a+1, a+3]))
		var tip := verts.size()
		verts.append(root + Vector3.UP * height + along * lean)
		normals.append(along.lerp(Vector3.UP, 0.65).normalized())
		uvs.append(Vector2(0.5, 1))
		colors.append(tint)
		indices.append_array(PackedInt32Array([tip-2, tip-1, tip]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

static func swept_bounds(mesh: Mesh, frame: Transform3D) -> AABB:
	# Shader displacement is clamped in world metres, independent of scale.
	return (frame * mesh.get_aabb()).grow(MAX_BEND)
