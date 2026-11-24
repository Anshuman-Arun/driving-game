extends RefCounted
## Geometry below and above an elevated road strip. The road builder owns the deck collision.

static func build_bridge(parent: Node3D, label: String, sections: Array, world: Variant, colliders: bool) -> void:
	if sections.size() < 2:
		return
	var bridge := Node3D.new()
	bridge.name = label
	parent.add_child(bridge)
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curbs := SurfaceTool.new()
	curbs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := PackedVector3Array()
	var posts: Array[Transform3D] = []
	var piers: Array[Transform3D] = []
	var caps: Array[Transform3D] = []
	var reflectors: Array[Transform3D] = []
	var mountain := label.begins_with("Needle")
	var viaduct := label.begins_with("Eastwater")
	for index in range(sections.size() - 1):
		var a: Array = sections[index]
		var b: Array = sections[index + 1]
		var left := a[0] as Vector3
		var right := a[4] as Vector3
		var next_left := b[0] as Vector3
		var next_right := b[4] as Vector3
		var thickness := Vector3.DOWN * 0.65
		_quad(deck, left, next_left, left + thickness, next_left + thickness)
		_quad(deck, next_right, right, next_right + thickness, right + thickness)
		_quad(deck, left + thickness, right + thickness, next_left + thickness, next_right + thickness)
		for side in [0, 4]:
			var p: Vector3 = a[side]
			var q: Vector3 = b[side]
			var lift := Vector3.UP * 0.018
			var inside := 1 if side == 0 else 3
			var inner_start: Vector3 = a[inside]
			var inner_end: Vector3 = b[inside]
			if side == 0:
				_quad(curbs, p + lift, q + lift, inner_start + lift, inner_end + lift)
			else:
				_quad(curbs, inner_start + lift, inner_end + lift, p + lift, q + lift)
			var outward := (p - (left + right) * 0.5).normalized()
			p -= outward * 0.16
			q -= outward * 0.16
			var height := Vector3.UP * 0.86
			rails.append_array(PackedVector3Array([p, q, p + height, p + height, q, q + height]))
			for fraction in [0.10, 0.62]:
				var center := p.lerp(q, fraction) + Vector3.UP * 0.46
				posts.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.14, 0.92, 0.14)), center))
			if index % 2 == 0:
				var marker := p.lerp(q, 0.1) + Vector3.UP * 0.78
				reflectors.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.19, 0.11, 0.19)), marker))
			for position_y: float in [0.35, 0.83]:
				var line := q - p
				var frame := Basis.looking_at(line.normalized()).scaled_local(Vector3(0.14, 0.12, line.length() + 0.08))
				posts.append(Transform3D(frame, (p + q) * 0.5 + Vector3.UP * position_y))
		if index % 3 == 1:
			var bearing := left.lerp(right, 0.5) + thickness
			var across := right - left
			var frame := Basis.looking_at(across.normalized())
			caps.append(Transform3D(frame.scaled_local(Vector3(1.60, 0.77, across.length() * 0.90)), bearing + Vector3.DOWN * 0.36))
			for fraction in [0.23, 0.77]:
				var top := left.lerp(right, fraction) + thickness
				var floor_height: float = world.sample_surface_height(top.x, top.z) - 0.6
				if top.y - floor_height > 1.3:
					var width := 1.30 if viaduct else 1.84
					var size := Vector3(width, top.y - floor_height, 1.65)
					piers.append(Transform3D(frame.scaled_local(size), Vector3(top.x, (top.y + floor_height) * 0.5, top.z)))
					caps.append(Transform3D(frame.scaled_local(Vector3(width + 0.65, 0.65, 2.32)), top - Vector3.UP * 1.13))
					caps.append(Transform3D(frame.scaled_local(Vector3(width + 1.1, 0.93, 2.80)), Vector3(top.x, floor_height + 0.78, top.z)))
	deck.set_material(_material(Color("#666e70") if mountain else Color("#858477")))
	var fascia := MeshInstance3D.new()
	fascia.mesh = deck.commit()
	bridge.add_child(fascia)
	curbs.set_material(_material(Color("#9a9f98") if viaduct else Color("#777d78")))
	var footway := MeshInstance3D.new()
	footway.mesh = curbs.commit()
	bridge.add_child(footway)
	_boxes(bridge, "Railings", posts, _material(Color("#645647") if mountain else Color("#3b4a48")))
	_boxes(bridge, "Piers", piers, _material(Color("#989380") if mountain else Color("#868c8c")))
	_boxes(bridge, "BearingsAndCaps", caps, _material(Color("#656a66")))
	_boxes(bridge, "RailReflectors", reflectors, _material(Color("#e0ac67")))
	if colliders:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(rails)
		var body := StaticBody3D.new()
		body.name = "BridgeRailCollision"
		body.set_meta("world_surface", "barrier")
		var boundary := CollisionShape3D.new()
		boundary.shape = shape
		body.add_child(boundary)
		bridge.add_child(body)

static func build_water(parent: Node3D, pools: Array, material: Material) -> void:
	if material == null:
		material = _material(Color("#3b6170"))
	for pool: Dictionary in pools:
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var water_level := float(pool["height"])
		for cell: Array in pool["cells"]:
			var at := Vector3(-1000.0 + float(cell[0]) * 4.0, water_level, -1000.0 + float(cell[1]) * 4.0)
			for offset: Vector3 in [Vector3.ZERO, Vector3(4, 0, 0), Vector3(0, 0, 4), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4)]:
				var point := at + offset
				builder.set_normal(Vector3.UP)
				builder.set_uv(Vector2(point.x, point.z) / 24.0)
				builder.add_vertex(point)
		builder.generate_tangents()
		builder.set_material(material)
		var mesh := MeshInstance3D.new()
		mesh.name = "CrossingWater"
		mesh.mesh = builder.commit()
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh)

static func _quad(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for point in [a, b, c, b, d, c]:
		builder.set_normal(normal)
		builder.set_uv(Vector2(point.x + point.z, point.y) * 0.25)
		builder.add_vertex(point)

static func _boxes(parent: Node3D, label: String, placements: Array[Transform3D], material: Material) -> void:
	if placements.is_empty():
		return
	var box := BoxMesh.new()
	box.material = material
	var instance := MultiMesh.new()
	instance.transform_format = MultiMesh.TRANSFORM_3D
	instance.mesh = box
	instance.instance_count = placements.size()
	for index in placements.size():
		instance.set_instance_transform(index, placements[index])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = instance
	parent.add_child(node)

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
