extends RefCounted
## Conservative distance-band approximation from actual rendered triangle clearance.
## The entire vertical column is excluded, including terrain beneath bridge decks.
const Contract := preload("world_contract.gd")
const MAX_SIDE := 256
const CELL_M := 1.0
var status := "disabled"
var stats: Dictionary = {}

func build(world: Node, region: Rect2) -> Texture2D:
	var image := build_image(world, region)
	if image == null:
		return null
	var texture := ImageTexture.create_from_image(image)
	if texture == null or texture.get_width() != image.get_width() or texture.get_height() != image.get_height():
		status = "roadside texture creation failed"
		return null
	return texture

func build_image(world: Node, region: Rect2) -> Image:
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
	var width := ceili(region.size.x / CELL_M)
	var height := ceili(region.size.y / CELL_M)
	var step := region.size / Vector2(width, height)
	var image := Image.create_empty(width, height, false, Image.FORMAT_R8)
	image.fill(Color(0.0, 0.0, 0.0))
	var active := 0
	var excluded := 0
	var queries := 0
	for z in range(height):
		for x in range(width):
			var center := region.position + (Vector2(x, z) + Vector2(0.5, 0.5)) * step
			# One extra texel margin prevents bilinear leakage into protected triangles.
			var half := step * 1.5
			var box := AABB(Vector3(center.x - half.x, -10000.0, center.y - half.y), Vector3(half.x * 2.0, 20000.0, half.y * 2.0))
			queries += 1
			if clearance.call("overlaps", box, 0.0, true):
				excluded += 1
				continue
			var weight := 0.0
			for i in range(1, 5):
				queries += 1
				if clearance.call("overlaps", box, float(i), true):
					weight = 1.0 - float(i - 1) / 4.0
					break
			# Fade the outer raster edge to avoid a visible rectangular boundary.
			var edge := minf(minf(center.x - region.position.x, region.end.x - center.x), minf(center.y - region.position.y, region.end.y - center.y))
			weight *= clampf((edge - 1.0) / 5.0, 0.0, 1.0)
			if weight > 0.0:
				active += 1
				image.set_pixel(x, z, Color(weight, 0.0, 0.0))
	stats = {"width": width, "height": height, "active_cells": active, "excluded_cells": excluded, "clearance_queries": queries}
	status = "ready"
	return image
