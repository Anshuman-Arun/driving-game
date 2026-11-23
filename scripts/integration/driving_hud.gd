extends Control

const DISPLAY := preload("res://assets/ui/fonts/BarlowCondensed-BoldItalic.ttf")
const BODY := preload("res://assets/ui/fonts/BarlowSemiCondensed-SemiBold.ttf")
const MAP_SHADER := preload("res://assets/ui/dashboard/minimap.gdshader")
const ROADS := preload("res://assets/ui/dashboard/minimap.png")
const WHITE := Color("#fff8e8")
const INK := Color("#101a22")
const MUTED := Color("#a9b5b4")
const MINT := Color("#8ef5cf")
const AMBER := Color("#ffd897")
const REDLINE := Color("#ff8056")
const MAP_SIZE := 181.0
const TACH_TICKS := 24

var _map := ColorRect.new()
var _map_material := ShaderMaterial.new()
var _mph := 0
var _gear := "N"
var _rpm := 0.0
var _heading := 0.0
var _notice := ""
var _drifting := false
var _layout_scale := 1.0
var _regions: Array = []
var _region := "ASTER VALLEY"
var _last_region_position := Vector2(INF, INF)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_material.shader = MAP_SHADER
	_map_material.set_shader_parameter("roads", ROADS)
	_map.material = _map_material
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.show_behind_parent = true
	add_child(_map)
	resized.connect(_layout)
	_layout()

func set_regions(regions: Array) -> void:
	_regions = regions

func _layout() -> void:
	_layout_scale = clampf(size.x / 1220.0, 0.60, 1.0)
	_map.size = Vector2.ONE * MAP_SIZE * _layout_scale
	_map.position = Vector2(39, size.y / _layout_scale - MAP_SIZE - 64) * _layout_scale
	queue_redraw()

func update_telemetry(mps: float, gear: String, rpm_ratio: float, car_pose: Transform3D, drifting: bool, notice: String) -> void:
	_mph = roundi(mps * 2.236936)
	_gear = gear
	_rpm = clampf(rpm_ratio, 0.0, 1.0)
	var forward := -car_pose.basis.z
	_heading = atan2(forward.x, -forward.z)
	var position_xz := Vector2(car_pose.origin.x, car_pose.origin.z)
	_map_material.set_shader_parameter("map_center", (position_xz + Vector2(1000, 1000)) / 2000.0)
	_map_material.set_shader_parameter("heading", _heading)
	if position_xz.distance_squared_to(_last_region_position) > 196.0:
		var nearest := INF
		for area: Dictionary in _regions:
			var center: Array = area["center"]
			var distance := position_xz.distance_squared_to(Vector2(center[0], center[1]))
			if distance < nearest:
				nearest = distance
				_region = str(area["name"]).to_upper()
		_last_region_position = position_xz
	_notice = notice
	_drifting = drifting
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _layout_scale)
	var canvas := size / _layout_scale
	var center := _map.position / _layout_scale + Vector2.ONE * MAP_SIZE * 0.5
	_draw_navigation(center)
	_draw_instruments(canvas - Vector2(327, 179))
	if not _notice.is_empty():
		var width := BODY.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
		var origin := Vector2((canvas.x - width) / 2 - 21, 30)
		_chamfer(origin, Vector2(width + 42, 40), 10, Color("#17242beb"))
		_centered(BODY, _notice, Vector2(canvas.x / 2, 57), 21, WHITE)

func _draw_navigation(center: Vector2) -> void:
	draw_arc(center + Vector2(0, 2), 94, 0, TAU, 72, Color("#111b24dd"), 8, true)
	draw_arc(center, 91, 0, TAU, 72, Color("#31424b"), 4, true)
	draw_arc(center, 96, deg_to_rad(203), deg_to_rad(284), 25, MINT, 2, true)
	draw_arc(center, 96, deg_to_rad(27), deg_to_rad(75), 20, Color("#b9c4b0"), 2, true)
	for index in range(12):
		var ray := Vector2.from_angle(index * TAU / 12.0)
		draw_line(center + ray * 91, center + ray * 95, Color("#ced7bd"), 1.2, true)
	for index in range(4):
		var marker := center + Vector2.UP.rotated(index * PI * 0.5 - _heading) * 72.0
		draw_circle(marker, 9, Color("#121e25e8"), true, -1, true)
		_centered(BODY, ["N", "E", "S", "W"][index], marker + Vector2(0, 4), 12, MINT if index == 0 else Color("#c7d2ba"))
	var shadow := center + Vector2(0, 2)
	draw_colored_polygon(PackedVector2Array([shadow + Vector2(0, -16), shadow + Vector2(12, 12),
		shadow + Vector2(0, 7), shadow + Vector2(-12, 12)]), INK)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -11), center + Vector2(8, 8),
		center + Vector2(0, 4), center + Vector2(-8, 8)]), WHITE)
	var origin := center + Vector2(-76, 101)
	_chamfer(origin, Vector2(152, 26), 7, Color("#15252cf5"))
	draw_line(origin + Vector2(14, 1), origin + Vector2(37, 1), MINT, 2, true)
	_centered(BODY, _region, origin + Vector2(76, 18), 15, WHITE)

func _draw_instruments(origin: Vector2) -> void:
	var plate := PackedVector2Array([origin + Vector2(21, 0), origin + Vector2(291, 0),
		origin + Vector2(276, 130), origin + Vector2(260, 145), origin + Vector2(0, 145), origin + Vector2(0, 24)])
	draw_polygon(plate, PackedColorArray([Color("#2a3b43ed"), Color("#1d292fe8"), Color("#121c24f5"),
		Color("#121c24f5"), Color("#121c24f5"), Color("#202f36ed")]))
	plate.append(plate[0])
	draw_polyline(plate, Color("#9ab0a968"), 1.3, true)
	draw_line(origin + Vector2(21, 0), origin + Vector2(106, 0), AMBER, 2, true)
	draw_string(BODY, origin + Vector2(18, 27), "RPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED)
	var lit := clampi(ceili(_rpm * TACH_TICKS), 0, TACH_TICKS)
	for index in range(TACH_TICKS):
		var t := index / float(TACH_TICKS - 1)
		var position := origin + Vector2(54.0 + index * 8.97, 16)
		var extent := lerpf(10, 19, t)
		var hot := index >= 20
		var ink := (REDLINE if hot else AMBER.lerp(REDLINE, t * 0.58)) if index < lit else (Color("#9b5f4d") if hot else Color("#566667"))
		draw_colored_polygon(PackedVector2Array([position + Vector2(2, 0), position + Vector2(8, 0),
			position + Vector2(6, extent), position + Vector2(0, extent)]), ink)
	draw_line(origin + Vector2(18, 45), origin + Vector2(266, 45), Color("#cbd2be35"), 1, true)
	_chamfer(origin + Vector2(22, 60), Vector2(62, 62), 11, Color("#394843"))
	draw_line(origin + Vector2(32, 61), origin + Vector2(73, 61), MINT, 2, true)
	_centered(DISPLAY, _gear, origin + Vector2(53, 105), 42, MINT)
	_centered(BODY, "GEAR", origin + Vector2(53, 135), 11, MUTED)
	_centered(DISPLAY, str(_mph), origin + Vector2(163, 122), 86, WHITE)
	draw_string(BODY, origin + Vector2(226, 120), "MPH", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, AMBER)
	if _drifting:
		draw_string(BODY, origin + Vector2(23, 168), "DRIFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MINT)

func _chamfer(origin: Vector2, span: Vector2, corner: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([origin + Vector2(corner, 0), origin + Vector2(span.x, 0),
		origin + span - Vector2(0, corner), origin + span - Vector2(corner, 0),
		origin + Vector2(0, span.y), origin + Vector2(0, corner)]), color)

func _centered(font: Font, value: String, at: Vector2, text_size: int, ink: Color) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	draw_string(font, at - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, ink)
