extends Control
## Self-contained audition panel. Run modules/audio as a Godot project (F6/F5).
var audio
var _gear_spin: SpinBox
var telemetry := {
	"rpm": 950.0, "idle_rpm": 950.0, "max_rpm": 7100.0,
	"throttle": 0.0, "load": 0.0, "speed_mps": 0.0,
	"lateral_slip": 0.0, "grip": 1.0, "gear": 1,
	"surface": "asphalt", "handbrake": false, "on_ground": true,
}
var _numbers: Dictionary = {}
var _profile: OptionButton
var _readout: Label


func _ready() -> void:
	var base: String = get_script().resource_path.get_base_dir().get_base_dir()
	var controller_script = load(base.path_join("audio_controller.gd"))
	audio = controller_script.new()
	add_child(audio)
	_make_interface()
	_push()


func _make_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.025, 0.036, 0.056)
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 30
	scroll.offset_top = 18
	scroll.offset_right = -30
	scroll.offset_bottom = -18
	add_child(scroll)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(590, 0)
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)
	var title := Label.new()
	title.text = "ASTER VALLEY  /  AUDIO DYNAMOMETER"
	title.add_theme_font_size_override("font_size", 23)
	root.add_child(title)
	var hint := Label.new()
	hint.text = "Original offline synthesis. Change controls to audition the mix. Speed uses km/h."
	root.add_child(hint)
	_profile = OptionButton.new()
	for name in ["Vela GT  · balanced six", "Orion RS  · high-rev four", "Kestrel XR  · deep eight"]:
		_profile.add_item(name)
	_profile.item_selected.connect(_select_profile)
	root.add_child(_profile)
	_add_slider(root, "RPM", "rpm", 800.0, 8600.0, 950.0, 50.0)
	_add_slider(root, "Throttle", "throttle", 0.0, 1.0, 0.0, 0.01)
	_add_slider(root, "Engine load", "load", 0.0, 1.0, 0.0, 0.01)
	_add_slider(root, "Speed (km/h)", "speed_mps", 0.0, 220.0, 0.0, 1.0)
	_add_slider(root, "Lateral slip", "lateral_slip", 0.0, 1.0, 0.0, 0.01)
	_add_slider(root, "Grip", "grip", 0.0, 1.0, 1.0, 0.01)
	var row := HBoxContainer.new()
	root.add_child(row)
	var gear_label := Label.new()
	gear_label.text = "GEAR"
	row.add_child(gear_label)
	var gear := SpinBox.new()
	gear.min_value = -1
	gear.max_value = 6
	gear.value = 1
	_gear_spin = gear
	gear.value_changed.connect(func(value: float) -> void:
		telemetry["gear"] = int(value)
		_push())
	row.add_child(gear)
	var road := OptionButton.new()
	for item in ["Asphalt", "Gravel / dirt", "Grass"]:
		road.add_item(item)
	road.item_selected.connect(func(index: int) -> void:
		telemetry["surface"] = ["asphalt", "gravel", "grass"][index]
		_push())
	row.add_child(road)
	var handbrake := CheckBox.new()
	handbrake.text = "Handbrake"
	handbrake.toggled.connect(func(enabled: bool) -> void:
		telemetry["handbrake"] = enabled
		_push())
	row.add_child(handbrake)
	var grounded := CheckBox.new()
	grounded.text = "Ground contact"
	grounded.button_pressed = true
	grounded.toggled.connect(func(enabled: bool) -> void:
		telemetry["on_ground"] = enabled
		_push())
	root.add_child(grounded)
	var events := HBoxContainer.new()
	for spec in [["Gearshift", "gearshift"], ["Suspension bump", "suspension"], ["Collision", "collision"]]:
		var button := Button.new()
		button.text = spec[0]
		var event_name: String = spec[1]
		button.pressed.connect(func() -> void: _event(event_name))
		events.add_child(button)
	root.add_child(events)
	_readout = Label.new()
	root.add_child(_readout)
	var footer := Label.new()
	footer.text = "All audio rendered locally · no microphone/network use · Esc to close"
	root.add_child(footer)


func _add_slider(parent: VBoxContainer, label: String, key: String, low: float, high: float, initial: float, step: float) -> void:
	var header := Label.new()
	header.text = label
	parent.add_child(header)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size.x = 520
	slider.value_changed.connect(func(value: float) -> void:
		telemetry[key] = value / 3.6 if key == "speed_mps" else value
		_push())
	parent.add_child(slider)
	_numbers[key] = header


func _select_profile(index: int) -> void:
	var profiles := ["vela_gt", "orion_rs", "kestrel_xr"]
	var id: String = profiles[index]
	audio.set_profile(id)
	telemetry["idle_rpm"] = [950.0, 1100.0, 800.0][index]
	telemetry["max_rpm"] = [7100.0, 8600.0, 6900.0][index]
	_push()


func _event(event_name: String) -> void:
	match event_name:
		"gearshift":
			var next_gear := int(telemetry["gear"]) + 1
			if next_gear > 6:
				next_gear = 1
			if is_instance_valid(_gear_spin):
				_gear_spin.value = next_gear # value_changed keeps telemetry + UI in sync
			else:
				telemetry["gear"] = next_gear
				_push()
		"suspension": audio.trigger_suspension(0.85)
		"collision": audio.trigger_collision(0.85)


func _push() -> void:
	if not is_instance_valid(audio):
		return
	audio.update_telemetry(telemetry)
	if is_instance_valid(_readout):
		_readout.text = "%.0f RPM   ·   %.0f km/h   ·   Gear %d   ·   %s" % [telemetry["rpm"], telemetry["speed_mps"] * 3.6, telemetry["gear"], telemetry["surface"]]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
