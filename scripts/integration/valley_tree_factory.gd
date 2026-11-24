extends RefCounted
## Builds branch geometry and phototextured foliage into one instanced surface per species.

const CARDS = preload("res://assets/valley_art/foliage_cards.gdshader")
const BARK = preload("res://assets/forza_env/textures/bark/albedo.jpg")
const PINE = preload("res://assets/valley_art/pine_bough.png")
const BROADLEAF = preload("res://assets/valley_art/broadleaf_spray.png")

static func build(evergreen: bool, distant := false) -> ArrayMesh:
	var material := ShaderMaterial.new()
	material.shader = CARDS
	material.set_shader_parameter("bark", BARK)
	material.set_shader_parameter("canopy", PINE if evergreen else BROADLEAF)
	material.set_shader_parameter("wind", 0.065 if evergreen else 0.11)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random := RandomNumberGenerator.new()
	random.seed = 78211 if evergreen else 3863
	_trunk(tool, evergreen, distant)
	if evergreen:
		_fir(tool, random, distant)
	else:
		_deciduous(tool, random, distant)
	tool.index()
	tool.set_material(material)
	return tool.commit()

static func _trunk(tool: SurfaceTool, evergreen: bool, distant: bool) -> void:
	var previous := Vector3(0, -0.45, 0)
	for tier in 6:
		var t := (tier + 1) / 6.0
		var target := Vector3(t * t * 0.13, t * (4.6 if evergreen else 3.52), sin(t * 4.0) * 0.17)
		var radius := (0.13 if evergreen else 0.23) * pow(1.0 - t, 0.83)
		_tube(tool, previous, target, radius + 0.025, maxf(radius * 0.70, 0.009), 5 if distant else 8)
		previous = target
	if distant:
		return
	for root in 5:
		var along := Vector3.FORWARD.rotated(Vector3.UP, root * TAU / 5.0)
		_tube(tool, Vector3.UP * 0.11, along * 0.46 + Vector3.DOWN * 0.29, 0.095, 0.014, 5)

static func _fir(tool: SurfaceTool, random: RandomNumberGenerator, distant: bool) -> void:
	var whorls := 9 if distant else 15
	for level in whorls:
		var fraction := level / float(whorls - 1)
		var radius := lerpf(1.68, 0.14, pow(fraction, 0.91))
		var stem := Vector3(0.10 * fraction, lerpf(1.01, 4.64, fraction), sin(fraction * 4) * 0.13)
		var count := 5 if distant or fraction >= 0.7 else 7
		for branch in count:
			var angle := branch * TAU / count + level * 1.71 + random.randf_range(-0.24, 0.24)
			var direction := Vector3.FORWARD.rotated(Vector3.UP, angle)
			var span := direction * radius * random.randf_range(0.78, 1.20)
			span.y = lerpf(-0.09, 0.23, fraction) + random.randf_range(-0.28, 0.24)
			var side := direction.cross(Vector3.UP)
			var fork := stem + span * 0.53 + Vector3.DOWN * radius * 0.072
			var tip := stem + span
			var tint := Color("#91a881").lerp(Color("#abc19a"), fraction)
			var pitch := (side * 0.35 + Vector3.UP * random.randf_range(-0.51, 0.51)) * radius
			_spray(tool, stem + span * 0.11, tip + span * 0.15, pitch, tint, distant)
			if distant:
				continue
			_tube(tool, stem, fork, 0.031 * (1 - fraction) + 0.004, 0.01, 4)
			_spray(tool, fork - side * radius * 0.11, tip + side * radius * 0.38 + Vector3.UP * radius * 0.16,
				(side * 0.22 + Vector3.UP * 0.34) * radius, tint)
			if fraction < 0.70:
				_spray(tool, fork, stem + span * 0.88 - side * radius * 0.39 + Vector3.DOWN * radius * 0.14,
					(side * 0.22 - Vector3.UP * 0.27) * radius, tint.darkened(0.10))

static func _deciduous(tool: SurfaceTool, random: RandomNumberGenerator, distant: bool) -> void:
	for limb in 9:
		var angle := limb * 2.39996 + random.randf_range(-0.15, 0.15)
		var out := Vector3.FORWARD.rotated(Vector3.UP, angle)
		var side := out.cross(Vector3.UP)
		var start := Vector3.UP * random.randf_range(1.30, 2.30)
		var elbow := start + out * random.randf_range(0.63, 0.92) + Vector3.UP * 0.72
		var end := elbow + out * random.randf_range(0.70, 1.17) + Vector3.UP * random.randf_range(0.53, 1.2)
		_tube(tool, start, elbow, 0.067, 0.036, 4 if distant else 6)
		if not distant:
			_tube(tool, elbow, end, 0.035, 0.011, 6)
		for cluster in 4:
			var signed_span := (cluster - 1.5) * 0.52
			var crown := end + side * signed_span + Vector3.UP * random.randf_range(-0.12, 0.44)
			var tint := Color("#97a066").lerp(Color("#d1d59a"), random.randf())
			var up := Vector3.UP * random.randf_range(0.33, 0.69)
			_spray(tool, crown - out * 0.65 - up * 0.35, crown + out * 0.68 + up * 0.37, side * 0.58 + up * 0.21, tint, distant)
			_spray(tool, crown - side * 0.63 - up * 0.54, crown + side * 0.63 + up * 0.74, out * 0.52, tint, distant)
			if distant:
				continue
			_tube(tool, elbow, crown, 0.023, 0.008, 4)
			_spray(tool, crown - out * 0.52 - up * 0.6, crown + out * 0.59 + up * 0.66, side * 0.26 - up * 0.42, tint)
			var inner := elbow.lerp(crown, 0.56) + up * 0.47
			_spray(tool, inner - side * 0.62 - up * 0.13, inner + side * 0.61 + up * 0.59, out * 0.54, tint.darkened(0.06))

static func _spray(tool: SurfaceTool, from: Vector3, to: Vector3, cross: Vector3, tint: Color, distant := false) -> void:
	var pairs := 1 if distant else 2
	var fold := cross.cross(to - from).normalized() * cross.length() * 0.36
	for pair in pairs:
		var u0 := pair / float(pairs)
		var u1 := (pair + 1) / float(pairs)
		var base0 := from.lerp(to, u0) + fold * sin(u0 * PI)
		var base1 := from.lerp(to, u1) + fold * sin(u1 * PI)
		var width0 := cross * (1.0 - 0.24 * u0)
		var width1 := cross * (1.0 - 0.24 * u1)
		var vertices := [base0 - width0, base0 + width0, base1 - width1, base1 + width1]
		var uv := [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 0), Vector2(u1, 1)]
		var normal := cross.cross(base1 - base0).normalized().lerp(Vector3.UP, 0.47).normalized()
		for i in [0, 1, 2, 2, 1, 3]:
			tool.set_uv(uv[i])
			tool.set_color(Color(tint.r, tint.g, tint.b, 0.22 + uv[i].x * 0.78))
			tool.set_normal(normal)
			tool.add_vertex(vertices[i])

static func _tube(tool: SurfaceTool, from: Vector3, to: Vector3, base: float, tip: float, sides: int) -> void:
	var direction := (to - from).normalized()
	var reference := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.88 else Vector3.UP
	var right := reference.cross(direction).normalized()
	var outward := direction.cross(right)
	for edge in sides:
		var a := edge * TAU / sides
		var b := (edge + 1) * TAU / sides
		var axis_a := cos(a) * right + sin(a) * outward
		var axis_b := cos(b) * right + sin(b) * outward
		var bottom_a := from + axis_a * base
		var bottom_b := from + axis_b * base
		var top_a := to + axis_a * tip
		var top_b := to + axis_b * tip
		var tint := Color(0.52, 0.44, 0.34, 0.0).lightened(0.13 * (edge % 3))
		var normal := (axis_a + axis_b).normalized()
		for position in [bottom_a, bottom_b, top_a, top_a, bottom_b, top_b]:
			tool.set_uv(Vector2(-1, 0))
			tool.set_normal(normal)
			tool.set_color(tint)
			tool.add_vertex(position)
