extends RefCounted
## Spatial index of the generated pavement and shoulder triangles, in world coordinates.

const CELL := 8.0
const VEHICLE_CLEARANCE := 4.5

var triangle_count := 0
var _cells: Dictionary = {}

func add_surface(mesh: ArrayMesh, surface: int, transform: Transform3D) -> void:
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in range(0, vertices.size(), 3):
		var a := transform * vertices[index]
		var b := transform * vertices[index + 1]
		var c := transform * vertices[index + 2]
		var origin := Vector2(a.x, a.z)
		var edge_b := Vector2(b.x, b.z) - origin
		var edge_c := Vector2(c.x, c.z) - origin
		var winding := signf(edge_b.cross(edge_c))
		if winding == 0.0:
			continue
		var low := origin.min(origin + edge_b).min(origin + edge_c)
		var high := origin.max(origin + edge_b).max(origin + edge_c)
		var edge_bc := edge_c - edge_b
		var triangle := {
			"low": low, "high": high, "origin": origin, "b": edge_b, "c": edge_c,
			"ab": Vector2(-edge_b.y, edge_b.x).normalized() * winding,
			"bc": Vector2(-edge_bc.y, edge_bc.x).normalized() * winding,
			"ca": Vector2(edge_c.y, -edge_c.x).normalized() * winding,
			"floor": minf(a.y, minf(b.y, c.y)), "roof": maxf(a.y, maxf(b.y, c.y)), "shoulder": surface > 0,
		}
		triangle_count += 1
		var start := _cell(low)
		var finish := _cell(high)
		for z in range(start.y, finish.y + 1):
			for x in range(start.x, finish.x + 1):
				var key := Vector2i(x, z)
				if not _cells.has(key):
					_cells[key] = []
				_cells[key].append(triangle)

func overlaps(bounds: AABB, margin: float = 0.0, include_shoulders := true) -> bool:
	var center := Vector2(bounds.get_center().x, bounds.get_center().z)
	var extent := Vector2(bounds.size.x, bounds.size.z) * 0.5 + Vector2.ONE * margin
	var low := center - extent
	var high := center + extent
	var start := _cell(low)
	var finish := _cell(high)
	for z in range(start.y, finish.y + 1):
		for x in range(start.x, finish.x + 1):
			var key := Vector2i(x, z)
			if not _cells.has(key):
				continue
			for tri: Dictionary in _cells[key]:
				if not include_shoulders and tri.shoulder:
					continue
				if high.x < tri.low.x or low.x > tri.high.x or high.y < tri.low.y or low.y > tri.high.y:
					continue
				# Allow terrain-level objects under an elevated deck, and objects well above the lane.
				if bounds.end.y < float(tri.floor) - 0.35 or bounds.position.y > float(tri.roof) + VEHICLE_CLEARANCE:
					continue
				var offset: Vector2 = center - tri.origin
				if _inside(offset, extent, tri.ab) and _inside(offset - tri.b, extent, tri.bc) and _inside(offset - tri.c, extent, tri.ca):
					return true
	return false

func _cell(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.y / CELL))

func _inside(from_edge: Vector2, extent: Vector2, normal: Vector2) -> bool:
	return from_edge.dot(normal) + extent.dot(normal.abs()) >= 0.0
