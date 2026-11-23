extends RefCounted
## All colors and shapes are authored for this game shell; no external visual assets.
const INK := Color("#0b1720")
const BACK := Color("#07141b")
const PANEL := Color("#102a35")
const PANEL_ALT := Color("#183b47")
const LINE := Color("#3c606d")
const TEXT := Color("#f3f3ea")
const MUTED := Color("#a9bec1")
const ACCENT := Color("#ffb861")
const TEAL := Color("#64d6c4")

static func box(bg: Color, outline: Color = Color.TRANSPARENT, radius: int = 13, pad: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = outline
	s.set_border_width_all(1 if outline.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", BACK)
	t.set_color("font_pressed_color", "Button", BACK)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.2))
	t.set_stylebox("normal", "Button", box(PANEL_ALT, LINE, 6, 15))
	t.set_stylebox("hover", "Button", box(ACCENT, ACCENT, 8, 15))
	t.set_stylebox("pressed", "Button", box(TEAL, TEAL, 8, 15))
	t.set_stylebox("focus", "Button", box(Color.TRANSPARENT, TEAL, 8, 15))
	t.set_stylebox("disabled", "Button", box(PANEL, LINE.darkened(0.35), 8, 15))
	t.set_stylebox("normal", "PanelContainer", box(PANEL, LINE, 12, 3))
	t.set_stylebox("normal", "LineEdit", box(PANEL_ALT, LINE, 6, 9))
	t.set_stylebox("normal", "OptionButton", box(PANEL_ALT, LINE, 8, 9))
	t.set_stylebox("hover", "OptionButton", box(ACCENT, ACCENT, 8, 9))
	t.set_stylebox("pressed", "OptionButton", box(TEAL, TEAL, 8, 9))
	t.set_stylebox("focus", "OptionButton", box(Color.TRANSPARENT, TEAL, 8, 9))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", BACK)
	t.set_color("font_pressed_color", "OptionButton", BACK)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_stylebox("panel", "PopupMenu", box(PANEL_ALT, LINE, 8, 6))
	t.set_stylebox("hover", "PopupMenu", box(LINE, LINE, 4, 4))
	t.set_stylebox("background", "ProgressBar", box(INK, LINE, 4, 0))
	t.set_stylebox("fill", "ProgressBar", box(TEAL, TEAL, 4, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	return t
