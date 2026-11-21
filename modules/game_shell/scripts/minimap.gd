extends Control
## Decorative schematic only. Never claims to render the unmerged road_graph_v1.
var player_uv: Vector2 = Vector2(0.27, 0.74)
var heading_rad: float = 0.0
var show_events: bool = true
const BG := Color("#10252f")
const ROAD := Color("#6b858c")
const HIGHLIGHT := Color("#f2ae65")
const WATER := Color("#226577")

func _ready() -> void:
	custom_minimum_size = Vector2(230, 210)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_player(uv: Vector2, heading: float) -> void:
	player_uv = uv.clamp(Vector2(0.05, 0.05), Vector2(0.95, 0.95))
	heading_rad = heading
	queue_redraw()

func _line(points: Array, color: Color, thickness: float) -> void:
	var scaled := PackedVector2Array()
	for p in points:
		scaled.append(Vector2(p.x * size.x, p.y * size.y))
	draw_polyline(scaled, color, thickness, true)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG, true)
	for i in range(1, 8):
		var x: float = size.x * float(i) / 8.0
		var y: float = size.y * float(i) / 8.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("#22404a"), 1.0)
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("#22404a"), 1.0)
	draw_circle(size * Vector2(0.8, 0.75), minf(size.x, size.y) * 0.18, WATER)
	_line([Vector2(.17,.89),Vector2(.29,.78),Vector2(.42,.70),Vector2(.61,.68),Vector2(.75,.78),Vector2(.83,.56),Vector2(.68,.41),Vector2(.52,.22),Vector2(.34,.13),Vector2(.22,.33),Vector2(.29,.55),Vector2(.17,.89)], ROAD, 4.0)
	_line([Vector2(.29,.55),Vector2(.46,.51),Vector2(.68,.41)], ROAD, 3.0)
	_line([Vector2(.42,.70),Vector2(.53,.84),Vector2(.75,.78)], ROAD, 3.0)
	_line([Vector2(.22,.33),Vector2(.35,.43),Vector2(.46,.51)], ROAD, 2.0)
	if show_events:
		for uv in [Vector2(.17,.82),Vector2(.53,.22),Vector2(.76,.70),Vector2(.55,.60)]:
			var center := uv * size
			draw_circle(center, 7.5, HIGHLIGHT)
			draw_circle(center, 3.1, BG)
	var center := player_uv * size
	var forward := Vector2(sin(heading_rad), -cos(heading_rad))
	var sideways := Vector2(-forward.y, forward.x)
	var marker := PackedVector2Array([center + forward * 11.0, center - forward * 7.0 + sideways * 5.0, center - forward * 7.0 - sideways * 5.0])
	draw_colored_polygon(marker, Color("#f6f9ef"))
	draw_arc(center, 14.0, 0.0, TAU, 30, Color("#f6f9ef", 0.4), 1.0, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color("#587581"), false, 1.0)
