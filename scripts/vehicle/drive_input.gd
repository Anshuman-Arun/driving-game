class_name DriveInput
extends RefCounted
## All driving input actions (Keyboard + Xbox Series Controller) installed in one place.
## Analog triggers and sticks use clean deadzones and Forza-style smooth response curves.

const DEADZONE := 0.16
const STEER_DEADZONE := 0.14
const TRIGGER_DEADZONE := 0.05
const LOOK_DEADZONE := 0.22

var steering_sensitivity := 0.65
var connected_joypads: Array[int]:
	get:
		return _connected_joypads

var _input_state: Dictionary = {
	"steer": 0.0,
	"throttle": 0.0,
	"brake": 0.0,
	"handbrake": false,
}
var _connected_joypads: Array[int] = []

func _init() -> void:
	_refresh_joypads()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _refresh_joypads() -> void:
	_connected_joypads.clear()
	for pad in Input.get_connected_joypads():
		_connected_joypads.append(pad)

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_joypads()

static func install() -> void:
	for action in ["drive_throttle", "drive_brake", "drive_left", "drive_right", "drive_handbrake", "drive_reset", "drive_camera", "drive_pause"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		else:
			InputMap.action_erase_events(action)
	# Keyboard bindings
	_add_key("drive_throttle", KEY_W)
	_add_key("drive_throttle", KEY_UP)
	_add_key("drive_brake", KEY_S)
	_add_key("drive_brake", KEY_DOWN)
	_add_key("drive_left", KEY_A)
	_add_key("drive_left", KEY_LEFT)
	_add_key("drive_right", KEY_D)
	_add_key("drive_right", KEY_RIGHT)
	_add_key("drive_handbrake", KEY_SPACE)
	_add_key("drive_reset", KEY_R)
	_add_key("drive_camera", KEY_C)
	_add_key("drive_pause", KEY_ESCAPE)
	# Xbox Series controller bindings
	_add_axis("drive_throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_axis("drive_brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_axis("drive_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("drive_right", JOY_AXIS_LEFT_X, 1.0)
	_add_button("drive_handbrake", JOY_BUTTON_A)
	_add_button("drive_camera", JOY_BUTTON_LEFT_SHOULDER)
	_add_button("drive_reset", JOY_BUTTON_Y)
	_add_button("drive_pause", JOY_BUTTON_START)

static func _add_key(action: StringName, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

static func _add_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)

static func _add_button(action: StringName, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)

func sample() -> Dictionary:
	# Preserve linear action strength for keyboard / automated Input.action_press tests.
	var steer := Input.get_axis("drive_right", "drive_left")
	var throttle := Input.get_action_strength("drive_throttle")
	var brake := Input.get_action_strength("drive_brake")
	var handbrake := Input.get_action_strength("drive_handbrake") > 0.35

	# Physical Xbox Series gamepad axes with smooth deadzones and steering curve.
	for device in _connected_joypads:
		var stick := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		var abs_stick := absf(stick)
		if abs_stick > STEER_DEADZONE:
			var remapped := clampf((abs_stick - STEER_DEADZONE) / (1.0 - STEER_DEADZONE), 0.0, 1.0)
			steer = -signf(stick) * pow(remapped, 2.0 - steering_sensitivity) # GEVP expects positive = left.
		var rt := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
		if rt > TRIGGER_DEADZONE:
			throttle = maxf(throttle, clampf((rt - TRIGGER_DEADZONE) / (1.0 - TRIGGER_DEADZONE), 0.0, 1.0))
		var lt := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
		if lt > TRIGGER_DEADZONE:
			brake = maxf(brake, clampf((lt - TRIGGER_DEADZONE) / (1.0 - TRIGGER_DEADZONE), 0.0, 1.0))
		if Input.is_joy_button_pressed(device, JOY_BUTTON_A):
			handbrake = true
		break

	_input_state["steer"] = steer
	_input_state["throttle"] = throttle
	_input_state["brake"] = brake
	_input_state["handbrake"] = handbrake
	return _input_state

func sample_look() -> Vector2:
	for device in _connected_joypads:
		var raw := Vector2(
			Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
		)
		var mag := raw.length()
		if mag > LOOK_DEADZONE:
			var remapped := clampf((mag - LOOK_DEADZONE) / (1.0 - LOOK_DEADZONE), 0.0, 1.0)
			return (raw / mag) * remapped
		if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_STICK):
			return Vector2(0.0, 1.0) # Quick look-back on R3 click
	return Vector2.ZERO
