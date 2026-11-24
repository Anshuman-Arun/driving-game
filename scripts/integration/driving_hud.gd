extends Control

const DISPLAY := preload("res://assets/ui/fonts/BarlowCondensed-BoldItalic.ttf")
const BODY := preload("res://assets/ui/fonts/BarlowSemiCondensed-SemiBold.ttf")
const MAP_SHADER := preload("res://assets/ui/dashboard/minimap.gdshader")
const ROADS := preload("res://assets/ui/dashboard/minimap.png")
const WHITE := Color("#fff8e8")
const INK := Color("#101a22")
const MUTED := Color("#a9b5b4")
const MINT := Color("#8ef5cf")
const REDLINE := Color("#ff8967")
const MAP_SIZE := 199.0
const TACH_LABELS: Array[String] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]

static var _mph_strings: Array[String] = []

static func _get_mph_string(val: int) -> String:
	if _mph_strings.is_empty():
		_mph_strings.resize(320)
		for i in 320:
			_mph_strings[i] = str(i)
	if val >= 0 and val < _mph_strings.size():
		return _mph_strings[val]
	return str(val)

var _map := ColorRect.new()
var _map_material := ShaderMaterial.new()
var _mph := 0
var _gear := "N"
var _rpm := 0.0
var _heading := 0.0
var _rpm_max := 8000.0
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
	_map.position = Vector2(39, size.y / _layout_scale - MAP_SIZE - 42) * _layout_scale
	queue_redraw()

func update_telemetry(mps: float, gear: String, rpm_ratio: float, car_pose: Transform3D, drifting: bool, notice: String, rpm_limit: float = 8000.0) -> void:
	_mph = roundi(mps * 2.236936)
	_gear = gear
	_rpm = clampf(rpm_ratio, 0.0, 1.0)
	_rpm_max = rpm_limit
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
	_draw_instruments(canvas - Vector2(153, 145))
	if not _notice.is_empty():
		var width := BODY.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
		var origin := Vector2((canvas.x - width) / 2 - 21, 30)
		_chamfer(origin, Vector2(width + 42, 40), 10, Color("#17242beb"))
		_centered(BODY, _notice, Vector2(canvas.x / 2, 57), 21, WHITE)

func _draw_navigation(center: Vector2) -> void:
	var radius := MAP_SIZE * 0.5
	draw_arc(center, radius, deg_to_rad(13), deg_to_rad(167), 37, Color("#f8f3e98c"), 1.6, true)
	draw_arc(center, radius, deg_to_rad(191), deg_to_rad(349), 38, Color("#f8f3e97d"), 1.7, true)
	draw_arc(center, radius + 2, deg_to_rad(227), deg_to_rad(267), 16, MINT, 2.2, true)
	var north := center + Vector2.UP.rotated(-_heading) * (radius - 15)
	draw_circle(north, 10, Color("#10202cc9"), true, -1, true)
	_centered(BODY, "N", north + Vector2(0, 4), 13, WHITE)
	# Offset the vehicle marker so more road fits ahead in the heading-up map.
	var mark := center + Vector2(0, 24)
	var outer := PackedVector2Array([mark + Vector2(0, -15), mark + Vector2(11, 10),
		mark + Vector2(0, 6), mark + Vector2(-11, 10)])
	draw_colored_polygon(outer, INK)
	var marker := PackedVector2Array([mark + Vector2(0, -10), mark + Vector2(8, 7),
		mark + Vector2(0, 3), mark + Vector2(-8, 7)])
	draw_colored_polygon(marker, WHITE)
	_outline_text(BODY, _region, center + Vector2(0, radius + 26), 16, WHITE)

func _draw_instruments(center: Vector2) -> void:
	const START := 153.0
	const FINISH := 367.0
	const RADIUS := 112.0
	var a := deg_to_rad(START)
	var b := deg_to_rad(FINISH)
	var redline := lerpf(a, b, 0.87)
	draw_arc(center, RADIUS, a, b, 64, Color("#101b236b"), 4.5, true)
	draw_arc(center, RADIUS, a, b, 64, Color("#f9efe1c2"), 1.5, true)
	draw_arc(center, RADIUS, redline, b, 12, REDLINE, 2.8, true)
	var rev_end := lerpf(a, b, _rpm)
	if _rpm > 0.0:
		draw_arc(center, RADIUS - 4, a, rev_end, 36, Color("#a3f2dcab"), 2.2, true)
	for index in range(floori(_rpm_max / 250.0) + 1):
		var proportion := index * 250.0 / _rpm_max
		var ray := Vector2.from_angle(lerpf(a, b, proportion))
		var major := index % 4 == 0
		var inner := 101.0 if major else 107.5
		draw_line(center + ray * inner, center + ray * RADIUS, REDLINE if proportion >= 0.87 else Color("#eae4d7c9"), 1.5 if major else 0.8, true)
		if major:
			var major_idx := index / 4
			var label: String = TACH_LABELS[major_idx] if major_idx < TACH_LABELS.size() else str(major_idx)
			_outline_text(BODY, label, center + ray * 86.0 + Vector2(0, 4), 13, WHITE)
	var needle := Vector2.from_angle(rev_end)
	draw_line(center + needle * 80.0, center + needle * 112.5, Color("#101b23d9"), 6, true)
	draw_line(center + needle * 82.0, center + needle * 114.0, WHITE if _rpm < 0.87 else REDLINE, 3.2, true)
	var gear := center + Vector2(-18, -12)
	draw_circle(gear, 22, Color("#13272c9c"), true, -1, true)
	draw_arc(gear, 21.5, 0, TAU, 43, MINT, 1.6, true)
	_outline_text(DISPLAY, _gear, gear + Vector2(0, 11), 32, WHITE)
	_outline_text(DISPLAY, _get_mph_string(_mph), center + Vector2(27, 84), 92, WHITE)
	_outline_text(BODY, "MPH", center + Vector2(82, 23), 17, WHITE)
	if _drifting:
		_outline_text(BODY, "DRIFT", center + Vector2(13, 111), 15, MINT)

func _outline_text(font: Font, text: String, baseline: Vector2, font_size: int, tint: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var anchor := baseline - Vector2(width * 0.5, 0)
	draw_string_outline(font, anchor, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color("#101a24bc"))
	draw_string(font, anchor, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)

func _chamfer(origin: Vector2, span: Vector2, corner: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([origin + Vector2(corner, 0), origin + Vector2(span.x, 0),
		origin + span - Vector2(0, corner), origin + span - Vector2(corner, 0),
		origin + Vector2(0, span.y), origin + Vector2(0, corner)]), color)

func _centered(font: Font, value: String, at: Vector2, text_size: int, ink: Color) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	draw_string(font, at - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, ink)
