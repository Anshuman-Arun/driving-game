extends RefCounted
## Conservative square-distance band from actual rendered triangle clearance.
## Full vertical columns, including terrain beneath bridge decks, are protected.
const Contract := preload("world_contract.gd")
const MAX_SIDE := 256
const CELL_M := 1.0
const TILE_CELLS := 8
const MAX_MARGIN_M := 4.0
# Cushion for float32 rounding when forming a tile's enclosing AABB.
const BROADPHASE_PAD_M := 0.01
var status := "disabled"
var stats: Dictionary = {}

func build(world: Node, region: Rect2) -> Texture2D:
	var image := build_image(world, region)
	if image == null or int(stats.get("active_cells", 0)) == 0:
		return null
	var texture := ImageTexture.create_from_image(image)
	if texture == null or texture.get_width() != image.get_width() or texture.get_height() != image.get_height():
		status = "roadside texture creation failed"
		return null
	return texture

func build_image(world: Node, region: Rect2) -> Image:
	return _rasterize(world, region, true)

# CPU oracle used by tests only. It deliberately bypasses tile rejection.
func build_reference_image(world: Node, region: Rect2) -> Image:
	return _rasterize(world, region, false)

func _column(center: Vector2, half: Vector2) -> AABB:
	return AABB(Vector3(center.x - half.x, -10000.0, center.y - half.y),
		Vector3(half.x * 2.0, 20000.0, half.y * 2.0))

func _rasterize(world: Node, region: Rect2, use_tiles: bool) -> Image:
	status = "invalid roadside region or clearance"
	stats = {}
	if not region.position.is_finite() or not region.size.is_finite():
		return null
	if region.size.x < 1.0 or region.size.y < 1.0 or region.size.x > MAX_SIDE or region.size.y > MAX_SIDE:
		return null
	if region.position.x < -1000.0 or region.position.y < -1000.0 or region.end.x > 1000.0 or region.end.y > 1000.0:
		return null
	var clearance := Contract.clearance_for(world)
	if clearance == null:
		return null
	var started := Time.get_ticks_usec()
	var width := ceili(region.size.x / CELL_M)
	var height := ceili(region.size.y / CELL_M)
	var step := region.size / Vector2(width, height)
	var image := Image.create_empty(width, height, false, Image.FORMAT_R8)
	image.fill(Color(0.0, 0.0, 0.0))
	var active := 0
	var excluded := 0
	var queries := 0
	var tile_queries := 0
	var skipped_cells := 0
	# One extra texel margin prevents bilinear leakage into protected triangles.
	var half := step * 1.5
	for tz in range(0, height, TILE_CELLS):
		for tx in range(0, width, TILE_CELLS):
			var end_x := mini(tx + TILE_CELLS, width)
			var end_z := mini(tz + TILE_CELLS, height)
			if use_tiles:
				# Enclose all child-cell query AABBs, including their largest margin.
				var first := region.position + (Vector2(tx, tz) + Vector2(0.5, 0.5)) * step
				var last := region.position + (Vector2(end_x - 1, end_z - 1) + Vector2(0.5, 0.5)) * step
				var tile_half := (last - first) * 0.5 + half + Vector2.ONE * BROADPHASE_PAD_M
				tile_queries += 1
				if not clearance.overlaps(_column((first + last) * 0.5, tile_half), MAX_MARGIN_M, true):
					skipped_cells += (end_x - tx) * (end_z - tz)
					continue
			for z in range(tz, end_z):
				for x in range(tx, end_x):
					var center := region.position + (Vector2(x, z) + Vector2(0.5, 0.5)) * step
					var box := _column(center, half)
					queries += 1
					if clearance.overlaps(box, 0.0, true):
						excluded += 1
						continue
					var weight := 0.0
					for i in range(1, 5):
						queries += 1
						if clearance.overlaps(box, float(i), true):
							weight = 1.0 - float(i - 1) / MAX_MARGIN_M
							break
					# Fade the raster edge, avoiding a visible rectangle.
					var edge := minf(minf(center.x - region.position.x, region.end.x - center.x),
						minf(center.y - region.position.y, region.end.y - center.y))
					weight *= clampf((edge - 1.0) / 5.0, 0.0, 1.0)
					# Count actual stored nonzero R8 values, not sub-quantization weights.
					var byte_value := roundi(weight * 255.0)
					if byte_value > 0:
						active += 1
						image.set_pixel(x, z, Color(float(byte_value) / 255.0, 0.0, 0.0))
	stats = {"width": width, "height": height, "active_cells": active, "excluded_cells": excluded,
		"clearance_queries": queries + tile_queries, "cell_queries": queries, "tile_queries": tile_queries,
		"skipped_cells": skipped_cells, "generation_ms": float(Time.get_ticks_usec() - started) / 1000.0}
	status = "ready" if active > 0 else "no roadside transition in region"
	return image
