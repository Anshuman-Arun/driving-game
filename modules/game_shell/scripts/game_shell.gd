extends Control
## Standalone Aster Valley shell. Integration owns physics/world; this scene owns UI.
const Catalog = preload("car_catalog.gd")
const SaveService = preload("save_service.gd")
const MockGame = preload("mock_game_state.gd")
const ShellTheme = preload("shell_theme.gd")
const Preview = preload("car_preview.gd")
const Minimap = preload("minimap.gd")

var save_path := SaveService.DEFAULT_PATH
var save: Variant
var game: Variant
var screen: String = "MENU"  # MENU, FREE_ROAM, GARAGE, EVENTS, RACE, RESULTS, PAUSE, SETTINGS
var return_screen: String = "MENU"
var paused_from: String = "FREE_ROAM"
var inspected_car: String = "vela_gt"
var large_map: bool = false
var first_focus: Control
var speed_label: Label
var gear_label: Label
var car_label: Label
var notification_label: Label
var race_lap_label: Label
var race_position_label: Label
var race_time_label: Label
var countdown_label: Label
var settings_error: Label
var map_view: Variant
var layout_is_narrow: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = ShellTheme.make()
	_register_input_defaults()
	save = SaveService.new(save_path)
	save.load()
	game = MockGame.new(save)
	game.stage_changed.connect(_on_race_stage)
	inspected_car = save.selected_car()
	_apply_all_settings()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_render()

func _on_viewport_resized() -> void:
	var narrow := get_viewport_rect().size.x < 890.0
	if narrow != layout_is_narrow:
		_render()

func _register_input_defaults() -> void:
	## No shared InputMap edit: only additive runtime fallback actions for standalone demo.
	for action in ["shell_accelerate", "shell_brake", "shell_left", "shell_right", "shell_interact", "shell_pause", "shell_back", "shell_garage", "shell_map", "shell_finish_mock"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	## Respect integrator/user bindings when they already exist.
	_bind_keys("shell_accelerate", [KEY_W, KEY_UP])
	_bind_keys("shell_brake", [KEY_S, KEY_DOWN])
	_bind_keys("shell_left", [KEY_A, KEY_LEFT])
	_bind_keys("shell_right", [KEY_D, KEY_RIGHT])
	_bind_keys("shell_interact", [KEY_E])
	_bind_keys("shell_pause", [KEY_ESCAPE])
	_bind_keys("shell_back", [KEY_BACKSPACE])
	_bind_keys("shell_garage", [KEY_G])
	_bind_keys("shell_map", [KEY_M])
	_bind_keys("shell_finish_mock", [KEY_F])
	_bind_pad("shell_interact", JOY_BUTTON_A)
	_bind_pad("shell_back", JOY_BUTTON_B)
	_bind_pad("shell_pause", JOY_BUTTON_START)
	_bind_pad("shell_map", JOY_BUTTON_BACK)
	_bind_pad("shell_garage", JOY_BUTTON_X)
	_bind_axis("shell_accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_bind_axis("shell_brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_bind_axis("shell_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("shell_right", JOY_AXIS_LEFT_X, 1.0)
	for action in ["ui_accept", "ui_up", "ui_down", "ui_left", "ui_right"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_bind_pad("ui_accept", JOY_BUTTON_A)
	_bind_pad("ui_up", JOY_BUTTON_DPAD_UP)
	_bind_pad("ui_down", JOY_BUTTON_DPAD_DOWN)
	_bind_pad("ui_left", JOY_BUTTON_DPAD_LEFT)
	_bind_pad("ui_right", JOY_BUTTON_DPAD_RIGHT)

func _bind_keys(action: String, keys: Array) -> void:
	for code in keys:
		var event := InputEventKey.new()
		event.physical_keycode = int(code)
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)

func _bind_pad(action: String, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

func _bind_axis(action: String, axis: int, direction: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("shell_pause"):
		if screen in ["FREE_ROAM", "RACE", "PAUSE"]:
			toggle_pause()
		elif screen not in ["MENU"]:
			_go_back()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shell_back"):
		if screen != "MENU":
			_go_back()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shell_interact") and screen == "FREE_ROAM":
		open_events()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shell_garage") and screen == "FREE_ROAM":
		open_garage()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shell_map") and screen in ["FREE_ROAM", "RACE"]:
		large_map = not large_map
		_render()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shell_finish_mock") and screen == "RACE" and game.stage == "RACING":
		game.finish_event()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if game == null:
		return
	if screen == "FREE_ROAM" or screen == "RACE":
		var sens := float(save.data["settings"]["controller_sensitivity"])
		var steer := Input.get_action_strength("shell_right") - Input.get_action_strength("shell_left")
		game.advance(delta, Input.get_action_strength("shell_accelerate"), Input.get_action_strength("shell_brake"), steer * (0.5 + sens))
		_refresh_hud()

func _on_race_stage(stage: String) -> void:
	if stage == "RESULTS":
		screen = "RESULTS"
		_render()
	elif stage == "RACING" or stage == "COUNTDOWN":
		screen = "RACE"
		_render()

func _base() -> VBoxContainer:
	for child in get_children():
		child.visible = false
		remove_child(child)
		child.queue_free()
	speed_label = null
	gear_label = null
	car_label = null
	notification_label = null
	race_lap_label = null
	race_position_label = null
	race_time_label = null
	countdown_label = null
	settings_error = null
	map_view = null
	first_focus = null
	layout_is_narrow = get_viewport_rect().size.x < 890.0
	var bg := ColorRect.new()
	bg.color = ShellTheme.BACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	## Layered atmospheric bars to give simple UI depth without external images.
	var band := ColorRect.new()
	band.color = Color("#112734")
	band.anchor_right = 1.0
	band.anchor_bottom = 0.18
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad: int = 16 if layout_is_narrow else 36
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, pad)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 17)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 15)
	margin.add_child(stack)
	return stack

func _label(parent: Node, content: String, font_size: int = 18, tint: Color = ShellTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = content
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", tint)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

func _spacer(parent: Node) -> void:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)

func _surface(parent: Node, minimum: Vector2 = Vector2.ZERO) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ShellTheme.box(ShellTheme.PANEL, ShellTheme.LINE, 14, 4))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 17)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 11)
	margin.add_child(v)
	return v

func _action(parent: Node, title: String, on_press: Callable, primary: bool = false, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = title
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = not enabled
	if primary:
		b.add_theme_stylebox_override("normal", ShellTheme.box(ShellTheme.ACCENT, ShellTheme.ACCENT, 8, 15))
		b.add_theme_color_override("font_color", ShellTheme.BACK)
		b.add_theme_color_override("font_focus_color", ShellTheme.BACK)
	b.pressed.connect(on_press)
	parent.add_child(b)
	if first_focus == null and enabled:
		first_focus = b
	return b

func _header(parent: Node, eyebrow: String) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	parent.add_child(top)
	_label(top, "AV  /  ASTER VALLEY    •    " + eyebrow, 15, ShellTheme.ACCENT)
	var wallet := _label(top, "%d CR" % int(save.data["credits"]), 15, ShellTheme.MUTED)
	wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _heading(parent: Node, title: String, detail: String) -> void:
	_label(parent, title, 40 if layout_is_narrow else 58)
	_label(parent, detail, 16, ShellTheme.MUTED)

func _footer(parent: Node, hints: String = "") -> void:
	_label(parent, hints if not hints.is_empty() else "KEYBOARD: ENTER CONFIRM · ESC BACK/PAUSE     GAMEPAD: A CONFIRM · B BACK · START PAUSE", 13, ShellTheme.MUTED)

func _columns(parent: Node) -> BoxContainer:
	var body: BoxContainer
	if layout_is_narrow:
		body = VBoxContainer.new()
	else:
		body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	parent.add_child(body)
	return body

func _scroll(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 13)
	scroll.add_child(v)
	return v

func _render() -> void:
	var root := _base()
	_header(root, "OFFLINE DRIVING EXPERIENCE")
	match screen:
		"MENU": _menu(root)
		"FREE_ROAM": _free_roam(root)
		"GARAGE": _garage(root)
		"EVENTS": _events(root)
		"RACE": _race(root)
		"RESULTS": _results(root)
		"PAUSE": _pause(root)
		"SETTINGS": _settings(root)
		_: _menu(root)
	if first_focus != null:
		_focus_after_layout(first_focus)

func _focus_after_layout(control: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(control) and control.is_inside_tree():
		control.grab_focus()

func _quality_scale() -> float:
	var preset: String = str(save.data["settings"]["graphics_quality"])
	return 0.85 if preset == "low" else 1.0

func _preview(parent: Node, car_id: String) -> void:
	var preview := Preview.new()
	parent.add_child(preview)
	preview.set_car(car_id)
	preview.set_quality(_quality_scale())

func _menu(root: VBoxContainer) -> void:
	var content := _scroll(root)
	var body := _columns(content)
	var left := _surface(body, Vector2(290, 450))
	_label(left, "THE ROAD IS YOURS", 14, ShellTheme.TEAL)
	_heading(left, "ASTER\nVALLEY", "A world to wander. A line to chase.")
	_spacer(left)
	_action(left, "PLAY  /  FREE ROAM", func(): enter_free_roam(), true)
	_action(left, "GARAGE  /  03 VEHICLES", func(): open_garage())
	_action(left, "SETTINGS", func(): open_settings())
	_action(left, "QUIT TO DESKTOP", func(): get_tree().quit())
	var right := _surface(body, Vector2(320, 420))
	_label(right, "CURRENT DRIVE    •    " + Catalog.car_name(save.selected_car()), 16, ShellTheme.ACCENT)
	_preview(right, save.selected_car())
	_label(right, "MOUNTAIN ROADS     /     TOWN CIRCUITS     /     LAKESIDE SPRINTS", 14, ShellTheme.MUTED)
	_label(right, "DEMO MODE  •  Independently running game shell; road and vehicle physics are not connected.", 13, ShellTheme.MUTED)
	_footer(root)

func enter_free_roam() -> void:
	game.set_paused(false)
	if game.stage != "FREE_ROAM":
		game.return_to_free_roam()
	screen = "FREE_ROAM"
	large_map = false
	_render()

func _mini_panel(parent: Node, expand: bool = false) -> void:
	var panel := _surface(parent, Vector2(270, 258) if expand else Vector2(236, 216))
	_label(panel, "SCHEMATIC MAP   /   DEMO ONLY", 13, ShellTheme.MUTED)
	var mini := Minimap.new()
	mini.custom_minimum_size = Vector2(270, 285) if expand else Vector2(230, 205)
	mini.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mini.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(mini)
	map_view = mini

func _hud_metrics(parent: Node) -> void:
	var panel := _surface(parent, Vector2(285, 255))
	_label(panel, "FREE ROAM" if screen == "FREE_ROAM" else "EVENT ACTIVE", 14, ShellTheme.ACCENT)
	speed_label = _label(panel, "000", 72)
	_label(panel, "KM/H  •  SIMULATED", 14, ShellTheme.MUTED)
	gear_label = _label(panel, "GEAR  1", 23)
	car_label = _label(panel, Catalog.car_name(save.selected_car()), 17, ShellTheme.TEAL)
	notification_label = _label(panel, game.notification, 14, ShellTheme.MUTED)

func _free_roam(root: VBoxContainer) -> void:
	var content := _scroll(root)
	var top := _columns(content)
	var left := _surface(top, Vector2(300, 390))
	_label(left, "EXPLORE  /  ALDER TOWN", 14, ShellTheme.ACCENT)
	_label(left, "YOUR WORLD,\nYOUR PACE.", 31)
	_label(left, "The standalone demo models driving telemetry and event flow, not collision or scenery.", 15, ShellTheme.MUTED)
	_spacer(left)
	_action(left, "DISCOVER RACES  [E / A]", func(): open_events(), true)
	_action(left, "GARAGE  [G / X]", func(): open_garage())
	_action(left, "MAP SIZE  [M / VIEW]", func(): _toggle_map())
	_action(left, "PAUSE  [ESC / START]", func(): toggle_pause())
	var right := _surface(top, Vector2(320, 380))
	_label(right, "SELECTED CAR    •    SHOWROOM VISUAL", 14, ShellTheme.MUTED)
	_preview(right, save.selected_car())
	var widgets := HBoxContainer.new()
	widgets.add_theme_constant_override("separation", 12)
	content.add_child(widgets)
	_hud_metrics(widgets)
	_mini_panel(widgets, large_map)
	_footer(root, "W / RT ACCELERATE    S / LT BRAKE    A-D / LEFT STICK STEER    E / A DISCOVER    G / X GARAGE    M / VIEW MAP")
	_refresh_hud()

func _toggle_map() -> void:
	large_map = not large_map
	_render()

func open_garage() -> void:
	if screen in ["FREE_ROAM", "PAUSE"] and game.speed_kph > 4.0:
		game.set_notice("PARK THE CAR BEFORE ENTERING THE GARAGE")
		return
	if screen == "RACE" or (game.stage != "FREE_ROAM" and screen != "MENU" and screen != "PAUSE"):
		return
	return_screen = screen
	inspected_car = save.selected_car()
	screen = "GARAGE"
	_render()

func _inspect(car_id: String) -> void:
	inspected_car = car_id
	_render()

func _choose_car() -> void:
	if save.select_car(inspected_car):
		game.set_notice(Catalog.car_name(inspected_car) + " READY TO DRIVE")
		_render()
	else:
		_render()

func _stat(parent: Node, label: String, value: int) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, label, 14, ShellTheme.MUTED)
	var amount := _label(row, str(value), 15, ShellTheme.TEXT)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = clampi(value, 0, 100)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	parent.add_child(bar)

func _garage(root: VBoxContainer) -> void:
	_heading(root, "THE GARAGE", "Three fictional sports cars. Progression is saved locally.")
	var content := _scroll(root)
	var body := _columns(content)
	var left := _surface(body, Vector2(292, 350))
	_label(left, "VEHICLE COLLECTION", 14, ShellTheme.ACCENT)
	for spec in Catalog.CARS:
		var unlocked: bool = save.is_unlocked(str(spec["id"]))
		var suffix := "   /   ACTIVE" if save.selected_car() == spec["id"] else ("   /   READY" if unlocked else "   /   LOCKED")
		var b := _action(left, str(spec["name"]) + suffix, _inspect.bind(str(spec["id"])), inspected_car == spec["id"])
		b.tooltip_text = str(spec["tagline"])
		if inspected_car == spec["id"]:
			first_focus = b
	_label(left, "UNLOCKS", 13, ShellTheme.MUTED)
	_label(left, "ORION RS  •  Complete any event\nKESTREL XR  •  Complete three distinct events", 13, ShellTheme.MUTED)
	_spacer(left)
	_action(left, "BACK", func(): _go_back())
	var details := _surface(body, Vector2(340, 350))
	var spec := Catalog.car(inspected_car)
	_label(details, str(spec["class"]), 13, ShellTheme.ACCENT)
	_label(details, str(spec["name"]), 34)
	_label(details, str(spec["tagline"]), 16, ShellTheme.MUTED)
	var unlocked: bool = save.is_unlocked(inspected_car)
	var text := "SELECT VEHICLE" if unlocked else "LOCKED  /  " + str(spec["unlock"])
	_action(details, text, func(): _choose_car(), true, unlocked)
	_preview(details, inspected_car)
	var stat_group := VBoxContainer.new()
	details.add_child(stat_group)
	_stat(stat_group, "HANDLING", int(spec["handling"]))
	_stat(stat_group, "BRAKING", int(spec["braking"]))
	_label(details, "%d HP     •     %d KG     •     %d KM/H (FICTIONAL SPECS)" % [int(spec["power_hp"]), int(spec["mass_kg"]), int(spec["top_kph"])], 13, ShellTheme.MUTED)
	_footer(root, "GARAGE DEMO: 3D mesh is original and visual-only. Real GLBs import later from the Art PR.")

func open_events() -> void:
	if screen != "FREE_ROAM" or game.stage != "FREE_ROAM":
		return
	screen = "EVENTS"
	_render()

func _events(root: VBoxContainer) -> void:
	_heading(root, "FIND YOUR NEXT RACE", "Four event cards. Mock routes and times are clearly labeled.")
	var items := _scroll(root)
	for spec in Catalog.EVENTS:
		var box := _surface(items, Vector2(280, 145))
		var bar := HBoxContainer.new()
		box.add_child(bar)
		_label(bar, str(spec["name"]), 23, ShellTheme.ACCENT)
		var stamp := _label(bar, str(spec["kind"]) + "  /  " + str(spec["laps"]) + " LAP(S)", 13, ShellTheme.MUTED)
		stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_label(box, str(spec["region"]) + "   •   DESIGN TARGET " + str(spec["distance"]), 15)
		var existing: Dictionary = save.data["completed_events"].get(spec["id"], {})
		var record := "BEST:  --" if existing.is_empty() else "BEST:  " + _time(float(existing["best_time_s"]))
		_label(box, record + "     |     DEMO RUN: ~" + str(int(spec["mock_duration"])) + "s", 13, ShellTheme.MUTED)
		_action(box, "START EVENT", _start_event.bind(str(spec["id"])), true)
	_action(items, "BACK TO FREE ROAM", func(): _go_back())
	_footer(root, "E / A  •  EVENT INTERACT     ENTER / A  •  START     ESC / B  •  BACK")

func _start_event(id: String) -> void:
	game.start_event(id)

func _race(root: VBoxContainer) -> void:
	var event: Dictionary = game.current_event()
	_heading(root, str(event.get("name", "EVENT")), str(event.get("kind", "RACE")) + "   /   " + str(event.get("region", "ASTER VALLEY")) + "   /   DEMO SIMULATION")
	var content := _scroll(root)
	var columns := _columns(content)
	var left := _surface(columns, Vector2(280, 360))
	_label(left, "POSITION", 15, ShellTheme.MUTED)
	race_position_label = _label(left, "4 / 4", 49, ShellTheme.ACCENT)
	race_lap_label = _label(left, "LAP 1 / 3", 22, ShellTheme.TEAL)
	race_time_label = _label(left, "00:00.00", 27)
	var telemetry := HBoxContainer.new()
	left.add_child(telemetry)
	speed_label = _label(telemetry, "000", 27)
	_label(telemetry, "KM/H", 13, ShellTheme.MUTED)
	gear_label = _label(telemetry, "GEAR  1", 15)
	countdown_label = _label(left, "", 39, ShellTheme.ACCENT)
	var right := _surface(columns, Vector2(300, 360))
	_label(right, "LIVE VEHICLE VISUAL  /  MOCK", 14, ShellTheme.ACCENT)
	_preview(right, save.selected_car())
	_mini_panel(columns, large_map)
	_action(root, "PAUSE / RACE OPTIONS", func(): toggle_pause())
	_footer(root, "ESC / START PAUSE   ·   F FINISH MOCK RACE EARLY   ·   M / VIEW MAP")
	_refresh_hud()

func _results(root: VBoxContainer) -> void:
	var results: Dictionary = game.result
	_label(root, "EVENT COMPLETE  /  DEMO RESULTS", 15, ShellTheme.TEAL)
	_heading(root, str(results.get("event_name", "RACE COMPLETE")), "Return to free roam, or replay this event.")
	var body := _columns(root)
	var left := _surface(body, Vector2(300, 330))
	var place := int(results.get("position", 4))
	_label(left, "#%02d FINISH" % place, 52, ShellTheme.ACCENT)
	_label(left, _time(float(results.get("time_s", 0.0))), 37)
	_label(left, "BEST TIME   " + _time(float(results.get("best_time_s", results.get("time_s", 0.0)))), 16, ShellTheme.MUTED)
	_label(left, "REWARD    +%d CREDITS" % int(results.get("reward", 0)), 18, ShellTheme.TEAL)
	if not bool(results.get("record_saved", false)):
		_label(left, "SAVE FAILED  •  PROGRESSION NOT COMMITTED", 16, Color("#ff8b7f"))
	else:
		var unlocked: Array = results.get("new_unlocks", [])
		if unlocked.is_empty():
			_label(left, "PROGRESSION SAVED OFFLINE", 15, ShellTheme.MUTED)
		for car_id in unlocked:
			_label(left, "UNLOCKED  /  " + Catalog.car_name(str(car_id)), 17, ShellTheme.TEAL)
	var right := _surface(body, Vector2(290, 330))
	_label(right, "THE DRIVE CONTINUES", 24)
	_label(right, "This standalone result is generated from the mock session clock, not from physics or the Racing Agent's official race engine.", 16, ShellTheme.MUTED)
	_spacer(right)
	_action(right, "RETRY EVENT", _start_event.bind(str(results.get("event_id", ""))), true)
	_action(right, "RETURN TO FREE ROAM", func(): _return_from_race())
	_action(right, "MAIN MENU", func(): _main_menu())
	_footer(root)

func _pause(root: VBoxContainer) -> void:
	_heading(root, "DRIVE PAUSED", "A quiet moment in Aster Valley.")
	var panel := _surface(root, Vector2(280, 360))
	_label(panel, "SESSION", 15, ShellTheme.ACCENT)
	_label(panel, "IN RACE" if paused_from == "RACE" else "FREE ROAM", 25)
	_action(panel, "RESUME", func(): toggle_pause(), true)
	if paused_from == "FREE_ROAM":
		var parked: bool = game.speed_kph <= 4.0
		_action(panel, "GARAGE" if parked else "PARK TO ENTER GARAGE", func(): open_garage(), false, parked)
	_action(panel, "SETTINGS", func(): open_settings())
	_action(panel, "ABANDON RACE & FREE ROAM" if paused_from == "RACE" else "RETURN TO MAIN MENU", func(): _leave_pause())
	_footer(root, "ESC / START TO RESUME    B / BACK TO RESUME")

func _leave_pause() -> void:
	game.set_paused(false)
	if paused_from == "RACE":
		_return_from_race()
	else:
		_main_menu()

func toggle_pause() -> void:
	if screen == "PAUSE":
		game.set_paused(false)
		screen = paused_from
	elif screen == "FREE_ROAM" or screen == "RACE":
		paused_from = screen
		game.set_paused(true)
		screen = "PAUSE"
	else:
		return
	_render()

func open_settings() -> void:
	return_screen = screen
	screen = "SETTINGS"
	_render()

func _setting_option(parent: Node, title: String, key: String, values: Array) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, title, 16)
	var chooser := OptionButton.new()
	chooser.custom_minimum_size = Vector2(240, 42)
	chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in values:
		chooser.add_item(str(value).to_upper())
	chooser.select(maxi(0, values.find(save.data["settings"][key])))
	chooser.item_selected.connect(func(index: int):
		if not _save_option(key, values[index]):
			chooser.select(values.find(save.data["settings"][key]))
	)
	row.add_child(chooser)
	if first_focus == null:
		first_focus = chooser

func _setting_slider(parent: Node, title: String, key: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, title, 15)
	var amount := _label(row, "%d%%" % int(roundf(float(save.data["settings"][key]) * 100.0)), 15, ShellTheme.ACCENT)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(save.data["settings"][key])
	slider.custom_minimum_size = Vector2(140, 29)
	parent.add_child(slider)
	slider.value_changed.connect(func(value: float):
		if not _save_option(key, value):
			slider.set_value_no_signal(float(save.data["settings"][key]))
		amount.text = "%d%%" % int(roundf(slider.value * 100.0))
	)
	if first_focus == null:
		first_focus = slider

func _settings(root: VBoxContainer) -> void:
	_heading(root, "SETTINGS", "Changes save immediately to the offline profile.")
	var v := _scroll(root)
	var display := _surface(v, Vector2(275, 275))
	_label(display, "DISPLAY", 20, ShellTheme.ACCENT)
	_setting_option(display, "QUALITY", "graphics_quality", SaveService.GRAPHICS)
	_setting_option(display, "WINDOW MODE", "window_mode", SaveService.MODES)
	_setting_option(display, "RESOLUTION", "resolution", SaveService.RESOLUTIONS)
	_label(display, "Graphics preset changes 3D render scale; window mode and resolution apply to this demo.", 13, ShellTheme.MUTED)
	var control := _surface(v, Vector2(275, 110))
	_label(control, "CONTROL", 20, ShellTheme.ACCENT)
	_setting_slider(control, "CONTROLLER STEERING SENSITIVITY", "controller_sensitivity")
	var audio := _surface(v, Vector2(275, 250))
	_label(audio, "AUDIO", 20, ShellTheme.ACCENT)
	_setting_slider(audio, "MASTER VOLUME", "master_volume")
	_setting_slider(audio, "MUSIC VOLUME", "music_volume")
	_setting_slider(audio, "SFX VOLUME", "sfx_volume")
	_label(audio, "Music/SFX volumes persist; separate buses become active once the integrated project provides them.", 13, ShellTheme.MUTED)
	_action(v, "SAVE & BACK", func(): _go_back(), true)
	settings_error = _label(root, "", 15, Color("#ff8b7f"))
	settings_error.hide()
	_footer(root, "ARROWS / D-PAD NAVIGATE    ENTER / A CONFIRM    ESC / B BACK")

func _save_option(key: String, value: Variant) -> bool:
	var saved: bool = save.set_setting(key, value)
	if saved:
		_apply_setting(key, value)
	if is_instance_valid(settings_error):
		settings_error.text = save.last_error
		settings_error.visible = not saved
	return saved

func _apply_all_settings() -> void:
	for key in save.data["settings"].keys():
		_apply_setting(str(key), save.data["settings"][key])

func _apply_setting(key: String, value: Variant) -> void:
	match key:
		"graphics_quality":
			var factor := 0.85 if value == "low" else 1.0
			var vp := get_viewport()
			vp.scaling_3d_scale = factor
			vp.msaa_3d = Viewport.MSAA_DISABLED if value == "low" else Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_debanding = true
			for node in find_children("*", "SubViewportContainer", true, false):
				if node.has_method("set_quality"):
					node.call("set_quality", factor)
		"window_mode":
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value == "fullscreen" else DisplayServer.WINDOW_MODE_WINDOWED)
				if value == "windowed":
					_apply_setting("resolution", save.data["settings"]["resolution"])
		"resolution":
			if DisplayServer.get_name() != "headless" and save.data["settings"]["window_mode"] == "windowed":
				var halves := str(value).split("x")
				if halves.size() == 2:
					DisplayServer.window_set_size(Vector2i(int(halves[0]), int(halves[1])))
		"master_volume", "music_volume", "sfx_volume":
			var bus := "Master" if key == "master_volume" else ("Music" if key == "music_volume" else "SFX")
			var index := AudioServer.get_bus_index(bus)
			if index >= 0:
				AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, float(value))))

func _return_from_race() -> void:
	game.return_to_free_roam()
	screen = "FREE_ROAM"
	_render()

func _main_menu() -> void:
	game.set_paused(false)
	if game.stage != "FREE_ROAM":
		game.return_to_free_roam()
	screen = "MENU"
	_render()

func _go_back() -> void:
	match screen:
		"GARAGE", "SETTINGS":
			screen = return_screen
			if screen == "PAUSE":
				game.set_paused(true)
			_render()
		"EVENTS": enter_free_roam()
		"PAUSE": toggle_pause()
		"RESULTS": _return_from_race()
		"RACE": toggle_pause()
		"FREE_ROAM": toggle_pause()
		_: _main_menu()

func _refresh_hud() -> void:
	if is_instance_valid(speed_label):
		speed_label.text = "%03d" % int(roundf(game.speed_kph))
	if is_instance_valid(gear_label):
		gear_label.text = "GEAR  " + game.gear
	if is_instance_valid(car_label):
		car_label.text = Catalog.car_name(save.selected_car())
	if is_instance_valid(notification_label):
		notification_label.text = game.notification if game.notification_s > 0.0 else ""
	if is_instance_valid(race_position_label):
		race_position_label.text = "%d / 4" % game.race_position
	if is_instance_valid(race_lap_label):
		var laps: int = game.current_event().get("laps", 1)
		race_lap_label.text = "LAP  %d / %d" % [game.lap, laps]
	if is_instance_valid(race_time_label):
		race_time_label.text = _time(game.race_time_s)
	if is_instance_valid(countdown_label):
		countdown_label.text = str(maxi(1, int(ceil(game.countdown_s)))) if game.stage == "COUNTDOWN" else "GO  /  RACE"
	if is_instance_valid(map_view):
		var u := 0.4 + sin(game.travel_m / 680.0) * 0.2
		var v := 0.53 + cos(game.travel_m / 820.0) * 0.18
		map_view.set_player(Vector2(u, v), game.yaw)

static func _time(seconds: float) -> String:
	var safe := maxf(0.0, seconds)
	var minutes := int(safe / 60.0)
	var remainder := fmod(safe, 60.0)
	return "%02d:%05.2f" % [minutes, remainder]
