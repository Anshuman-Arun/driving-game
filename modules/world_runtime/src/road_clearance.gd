extends RefCounted
## Conservative static roadside clearance raster. Built from the same road strips
## and junction hulls as the collision meshes, not from the narrower AI lanes.
## The nearest grid sample's distance is reduced by half a cell diagonal.
const STEP := 2.0
const SIDE := 1001
const ORIGIN := -1000.0
const LIMIT := 18.0
var distances := PackedFloat32Array()

func _init() -> void:
	distances.resize(SIDE * SIDE)
	distances.fill(LIMIT)

func _index(value: float) -> int:
	return clampi(roundi((value - ORIGIN) / STEP), 0, SIDE - 1)

func add_segment(a: Vector2, b: Vector2, reach: float) -> void:
	var margin := reach + LIMIT
	var x0 := _index(minf(a.x, b.x) - margin)
	var x1 := _index(maxf(a.x, b.x) + margin)
	var z0 := _index(minf(a.y, b.y) - margin)
	var z1 := _index(maxf(a.y, b.y) + margin)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var p := Vector2(ORIGIN + ix * STEP, ORIGIN + iz * STEP)
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) - reach
			var i := iz * SIDE + ix
			distances[i] = minf(distances[i], d)

func add_polygon(hull: Array[Vector2], shoulder: float) -> void:
	var polygon := PackedVector2Array(hull)
	var low := hull[0]
	var high := hull[0]
	for j in hull.size():
		var a := hull[j]
		var b := hull[(j + 1) % hull.size()]
		add_segment(a, b, shoulder)
		low = low.min(a)
		high = high.max(a)
	for iz in range(_index(low.y), _index(high.y) + 1):
		for ix in range(_index(low.x), _index(high.x) + 1):
			var p := Vector2(ORIGIN + ix * STEP, ORIGIN + iz * STEP)
			if Geometry2D.is_point_in_polygon(p, polygon):
				var i := iz * SIDE + ix
				distances[i] = minf(distances[i], -shoulder)

func at(x: float, z: float) -> float:
	return distances[_index(z) * SIDE + _index(x)] - STEP * 0.707107
