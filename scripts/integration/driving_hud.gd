extends Control

const DISPLAY := preload("res://assets/ui/fonts/BarlowCondensed-BoldItalic.ttf")
const BODY := preload("res://assets/ui/fonts/BarlowSemiCondensed-SemiBold.ttf")
const MAP_SHADER := preload("res://assets/ui/dashboard/minimap.gdshader")
const ROADS := preload("res://assets/ui/dashboard/minimap.png")
const CYAN := Color("#6af1ce")
const WHITE := Color("#f9f8ef")
const INK := Color("#101f2a")
const MAP_SIZE := 178.0
const DIAL_SIZE := Vector2(218, 184)

var _map := ColorRect.new()
var _map_material := ShaderMaterial.new()
var _mph := 0
var _gear := "N"
var _rpm := 0.0
var _heading := 0.0
var _notice := ""
var _drifting := false
var _layout_scale := 1.0

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

func _layout() -> void:
	_layout_scale = clampf(size.x / 1220.0, 0.68, 1.0)
	_map.size = Vector2.ONE * MAP_SIZE * _layout_scale
	_map.position = Vector2(35, size.y / _layout_scale - MAP_SIZE - 35) * _layout_scale
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
	_notice = notice
	_drifting = drifting
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _layout_scale)
	var canvas := size / _layout_scale
	var center := _map.position / _layout_scale + Vector2.ONE * MAP_SIZE / 2.0
	var arrow := PackedVector2Array([center + Vector2(0, -12), center + Vector2(9, 10),
		center + Vector2(0, 6), center + Vector2(-9, 10)])
	draw_colored_polygon(arrow, WHITE)
	arrow.append(arrow[0])
	draw_polyline(arrow, INK, 2.0, true)
	var north := center + Vector2.UP.rotated(-_heading) * 74.0
	draw_circle(north, 11, INK, true, -1, true)
	_centered(BODY, "N", north + Vector2(0, 5), 14, WHITE)

	var dial := canvas - Vector2(35, 31) - DIAL_SIZE + Vector2(109, 98)
	var arc_start := deg_to_rad(162.0)
	var arc_end := deg_to_rad(378.0)
	var redline := lerpf(arc_start, arc_end, 0.83)
	draw_circle(dial, 88, Color("#0c1621b8"), true, -1, true)
	draw_arc(dial, 82, arc_start, arc_end, 64, Color("#a0b5c57f"), 3, true)
	draw_arc(dial, 82, redline, arc_end, 15, Color("#ff755d"), 3, true)
	if _rpm > 0.0:
		draw_arc(dial, 82, arc_start, lerpf(arc_start, arc_end, _rpm), 48, CYAN if _rpm < 0.88 else Color("#ff9b73"), 5, true)
	for index in range(9):
		var direction := Vector2.from_angle(lerpf(arc_start, arc_end, index / 8.0))
		draw_line(dial + direction * 68, dial + direction * 74, Color("#ccd8deaa"), 1.4, true)
	draw_circle(dial + Vector2(0, -26), 19, Color("#e9faf52a"), true, -1, true)
	_centered(DISPLAY, _gear, dial + Vector2(0, -17), 28, CYAN)
	_centered(DISPLAY, str(_mph), dial + Vector2(0, 44), 66, WHITE)
	_centered(BODY, "MPH", dial + Vector2(0, 63), 17, WHITE)
	if _drifting:
		_centered(BODY, "DRIFT", dial + Vector2(0, 106), 17, CYAN)
	if not _notice.is_empty():
		var width := BODY.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
		draw_rect(Rect2((canvas.x - width) / 2.0 - 18, 29, width + 36, 38), Color("#101f2ae8"))
		_centered(BODY, _notice, Vector2(canvas.x / 2.0, 55), 21, WHITE)

func _centered(font: Font, value: String, at: Vector2, text_size: int, ink: Color) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	draw_string(font, at - Vector2(width / 2.0, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, ink)
