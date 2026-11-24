extends MeshInstance3D
## Two static, collision-free ridgelines beyond the playable heightfield.

const SLICES := 512
const SECTIONS := 22

func _ready() -> void:
	var relief := FastNoiseLite.new()
	relief.seed = 8163
	relief.frequency = 0.00082
	relief.fractal_octaves = 4
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_range(tool, relief, 0, 1420.0, 2190.0, 3070.0, 350.0, Color("#4b656e"), Color("#737e7c"))
	_add_range(tool, relief, (SECTIONS + 1) * SLICES, 2550.0, 3350.0, 4150.0, 505.0, Color("#63798e"), Color("#a0a9ae"))
	tool.generate_normals()
	mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _add_range(tool: SurfaceTool, relief: FastNoiseLite, start: int, foot: float, crest: float, back: float, scale_m: float, lower: Color, upper: Color) -> void:
	for section in SECTIONS + 1:
		var t := float(section) / SECTIONS
		for slice in SLICES:
			var angle := TAU * float(slice) / SLICES
			var radial := Vector2(cos(angle), sin(angle))
			var ridge := radial * crest
			var saddle := relief.get_noise_2dv(ridge)
			var line := crest + 138.0 * saddle + 75.0 * sin(angle * 7.0)
			var radius := lerpf(foot, line, t * 2.0) if t < 0.5 else lerpf(line, back, t * 2.0 - 1.0)
			var fit := pow(sin(t * PI), 1.55)
			var major := 0.47 + 0.24 * cos(angle * 3.0 + 0.8) + 0.12 * sin(angle * 7.0 + 1.7)
			var cuts := relief.get_noise_2dv(ridge * 1.37 + Vector2(19.0, 127.0))
			var shoulder := relief.get_noise_2dv(radial * radius * 2.0)
			var h := -28.0 + scale_m * fit * clampf(major + cuts * 0.49 + saddle * 0.22, 0.14, 1.12)
			h += shoulder * 28.0 * fit
			tool.set_color(lower.lerp(upper, smoothstep(90.0, scale_m * 0.89, h)) * (0.96 + shoulder * 0.17))
			tool.add_vertex(Vector3(radial.x * radius, h, radial.y * radius))
	for section in SECTIONS:
		for slice in SLICES:
			var here := start + section * SLICES + slice
			var next := start + section * SLICES + (slice + 1) % SLICES
			for index in [here, here + SLICES, next, next, here + SLICES, next + SLICES]:
				tool.add_index(index)
