class_name DriveInput
extends RefCounted
## All input actions are installed in one place before the first physics frame.
## Godot's action strengths retain analog triggers and left stick deflection.

const DEADZONE := 0.16

static func install() -> void:
	for action in ["drive_throttle", "drive_brake", "drive_left", "drive_right", "drive_handbrake", "drive_reset", "drive_camera", "drive_pause"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
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
	_add_axis("drive_throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_axis("drive_brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_axis("drive_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("drive_right", JOY_AXIS_LEFT_X, 1.0)
	_add_button("drive_handbrake", JOY_BUTTON_B)
	_add_button("drive_reset", JOY_BUTTON_Y)
	_add_button("drive_camera", JOY_BUTTON_RIGHT_STICK)
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
	var steer := Input.get_axis("drive_right", "drive_left")
	# Preserve raw stick deflection and its priority over keyboard steering.
	for device in Input.get_connected_joypads():
		var stick := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		if absf(stick) > DEADZONE:
			steer = -stick  # Easy Vehicle Physics expects positive = left.
			break
	return {
		"steer": steer,
		"throttle": Input.get_action_strength("drive_throttle"),
		"brake": Input.get_action_strength("drive_brake"),
		"handbrake": Input.get_action_strength("drive_handbrake") > 0.35,
	}
