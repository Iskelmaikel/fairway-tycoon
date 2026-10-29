class_name UIKit
extends RefCounted
## The interface toolkit: colours, fonts, panel styles and small widget factories,
## matching the web version's look (dark green glass HUD, warm paper windows, gold accents).

const TURF := Color("#3f6e2f")
const INK := Color("#262718")
const MUTED := Color("#6c6a52")
const LINE := Color("#e4dcc6")
const PAPER := Color("#faf5e6")
const PAPER2 := Color("#efeadb")
const CARD := Color("#fdf9ee")
const FLAG := Color("#e8432e")
const GOLD := Color("#f2c14e")
const WHITE := Color.WHITE
const HUD_TOP := Color(20 / 255.0, 58 / 255.0, 36 / 255.0, 0.95)
const HUD_BOT := Color(10 / 255.0, 30 / 255.0, 18 / 255.0, 0.95)
const GLASS := Color(30 / 255.0, 38 / 255.0, 22 / 255.0, 0.85)
const POS := Color("#3f8a2f")
const NEG := Color("#c8322a")

static var _fonts := {}
static func font(weight := 700) -> Font:
	if _fonts.has(weight): return _fonts[weight]
	var f := Ctx2D.fontFor(weight)
	var fv := FontVariation.new()
	fv.base_font = f
	_fonts[weight] = fv
	return fv
static func display() -> Font: return font(800)

static var _theme: Theme
static func theme() -> Theme:
	if _theme: return _theme
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 14
	t.set_color("font_color", "Label", INK)
	t.set_font("normal_font", "RichTextLabel", font(500))
	t.set_font("bold_font", "RichTextLabel", font(800))
	t.set_font("italics_font", "RichTextLabel", font(500))
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font_size("normal_font_size", "RichTextLabel", 13)
	t.set_font_size("bold_font_size", "RichTextLabel", 13)
	t.set_constant("line_separation", "RichTextLabel", 2)
	# scroll bars: thin and quiet
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0, 0.18); sb.set_corner_radius_all(4); sb.content_margin_left = 3; sb.content_margin_right = 3
	var sbg := StyleBoxFlat.new(); sbg.bg_color = Color(0, 0, 0, 0.0)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb)
	t.set_stylebox("scroll", "VScrollBar", sbg)
	# text input, sliders, option buttons, check boxes
	var le := box(Color.WHITE, 10, LINE, 1); le.content_margin_left = 10; le.content_margin_right = 10; le.content_margin_top = 8; le.content_margin_bottom = 8
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate(); lef.border_color = TURF; lef.set_border_width_all(2)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", INK)
	t.set_font_size("font_size", "LineEdit", 15)
	t.set_color("caret_color", "LineEdit", INK)
	var ob := box(Color.WHITE, 8, LINE, 1); ob.content_margin_left = 8; ob.content_margin_right = 8; ob.content_margin_top = 5; ob.content_margin_bottom = 5
	for st in ["normal", "hover", "pressed", "focus"]: t.set_stylebox(st, "OptionButton", ob)
	t.set_color("font_color", "OptionButton", INK)
	t.set_color("font_hover_color", "OptionButton", INK)
	t.set_color("font_pressed_color", "OptionButton", INK)
	t.set_color("font_focus_color", "OptionButton", INK)
	t.set_font_size("font_size", "OptionButton", 13)
	var pm := box(Color.WHITE, 8, LINE, 1); pm.set_content_margin_all(4)
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_stylebox("hover", "PopupMenu", box(Color("#f1ead6"), 6))
	var sl := box(Color("#e3dcc8"), 3); sl.content_margin_top = 3; sl.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", sl)
	var sla := box(TURF, 3); sla.content_margin_top = 3; sla.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", sla)
	t.set_stylebox("grabber_area_highlight", "HSlider", sla)
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_hover_pressed_color", "CheckBox", INK)
	var tt := box(Color(15 / 255.0, 32 / 255.0, 20 / 255.0, 0.96), 10); tt.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tt)
	t.set_color("font_color", "TooltipLabel", Color.WHITE)
	_theme = t
	return t

static func box(bg: Color, radius := 12, border := Color(0, 0, 0, 0), bw := 0, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0: s.border_color = border; s.set_border_width_all(bw)
	if shadow > 0: s.shadow_color = Color(0, 0, 0, 0.3); s.shadow_size = shadow; s.shadow_offset = Vector2(0, shadow * 0.4)
	s.anti_aliasing = true
	return s
static func grad(top: Color, bot: Color, radius := 16, h := 60.0) -> StyleBoxTexture:
	var g := Gradient.new(); g.set_color(0, top); g.set_color(1, bot)
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 4; gt.height = 64
	var s := StyleBoxTexture.new(); s.texture = gt
	return s

# ---------- labels ----------
static func lbl(text: String, size := 14, weight := 700, col := INK, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new(); ls.font = font(weight); ls.font_size = size; ls.font_color = col
	l.label_settings = ls
	if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
static func eyebrow(text: String, col := MUTED, size := 10) -> Label:
	var l := lbl(text.to_upper(), size, 800, col)
	l.label_settings.font_color = col
	return l
static func setCol(l: Label, c: Color) -> void:
	if l.label_settings.font_color != c: l.label_settings.font_color = c
static func setText(l, t: String) -> void:
	if l.text != t: l.text = t
## rich text with [b], [color] and [url]; fits its content
static func rich(bb: String, size := 13, col := INK) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", col)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.text = bb
	return r
static func setRich(r: RichTextLabel, bb: String) -> void:
	if r.text != bb: r.text = bb
static func pos(t: String) -> String: return "[color=#3f8a2f]%s[/color]" % t
static func neg(t: String) -> String: return "[color=#c8322a]%s[/color]" % t
static func muted(t: String) -> String: return "[color=#6c6a52]%s[/color]" % t
static func esc(t: String) -> String: return t.replace("[", "[lb]")

# ---------- containers ----------
static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", sep); return v
static func hbox(sep := 6) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", sep); return h
static func flow(sep := 6) -> HFlowContainer:
	var f := HFlowContainer.new(); f.add_theme_constant_override("h_separation", sep); f.add_theme_constant_override("v_separation", sep); return f
static func grid(cols: int, sep := 8) -> GridContainer:
	var g := GridContainer.new(); g.columns = cols; g.add_theme_constant_override("h_separation", sep); g.add_theme_constant_override("v_separation", sep); return g
static func panel(sb: StyleBox, pad := 0) -> PanelContainer:
	var p := PanelContainer.new()
	var s := sb.duplicate()
	if pad > 0: s.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", s)
	return p
static func card(pad := 10, bg := Color.WHITE, radius := 14) -> PanelContainer: return panel(box(bg, radius, LINE, 1), pad)
static func margin(n: Control, l := 0, t := 0, r := 0, b := 0) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l); m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r); m.add_theme_constant_override("margin_bottom", b)
	m.add_child(n)
	return m
static func spacer() -> Control:
	var c := Control.new(); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; c.mouse_filter = Control.MOUSE_FILTER_IGNORE; return c
static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return c
static func clear(n: Node) -> void:
	for c in n.get_children(): n.remove_child(c); c.queue_free()

# ---------- buttons ----------
## styles: buy, ghost, fire, wintab, hud, tm, mm, seg, close, hb, who, scen, plain, evopt, dark
static func btn(text: String, style := 'buy', cb = null) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE   # no focus ring, and Space (pause) never presses the last-clicked button
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	styleBtn(b, style)
	if cb is Callable: b.pressed.connect(cb)
	return b
static func styleBtn(b: Button, style: String) -> void:
	var n: StyleBoxFlat; var h: StyleBoxFlat; var p: StyleBoxFlat; var d: StyleBoxFlat
	var fc := WHITE; var fs := 13; var fw := 800
	var dc := Color("#8a9a8f")
	match style:
		'buy':
			n = box(TURF, 11); n.content_margin_left = 12; n.content_margin_right = 12; n.content_margin_top = 9; n.content_margin_bottom = 9
			n.border_color = Color(0, 0, 0, 0.15); n.border_width_bottom = 3
			h = n.duplicate(); h.bg_color = TURF.lightened(0.12)
			d = n.duplicate(); d.bg_color = Color("#e3e9e4"); d.border_width_bottom = 0
			b.custom_minimum_size.x = 86
		'gold':
			n = box(Color("#b8860b"), 11); n.set_content_margin_all(11); n.border_color = Color(0, 0, 0, 0.15); n.border_width_bottom = 3
			h = n.duplicate(); h.bg_color = Color("#c99a1c")
			d = n.duplicate(); d.bg_color = Color("#e3e9e4")
		'ghost':
			n = box(Color(0, 0, 0, 0), 10, LINE, 1); n.content_margin_left = 12; n.content_margin_right = 12; n.content_margin_top = 7; n.content_margin_bottom = 7
			h = n.duplicate(); h.bg_color = Color(0, 0, 0, 0.04)
			d = n.duplicate()
			fc = MUTED; fs = 12; fw = 700
		'fire':
			n = box(Color(0, 0, 0, 0), 9, LINE, 1); n.content_margin_left = 10; n.content_margin_right = 10; n.content_margin_top = 5; n.content_margin_bottom = 5
			h = n.duplicate(); h.bg_color = Color("#fbe9e6")
			d = n.duplicate()
			fc = MUTED; fs = 11; fw = 700
		'wintab':
			n = box(Color(0, 0, 0, 0), 10); n.content_margin_left = 13; n.content_margin_right = 13; n.content_margin_top = 7; n.content_margin_bottom = 7
			h = n.duplicate(); h.bg_color = Color(0, 0, 0, 0.05)
			p = n.duplicate(); p.bg_color = WHITE; p.shadow_color = Color(0, 0, 0, 0.12); p.shadow_size = 2
			d = n.duplicate()
			fc = MUTED; fs = 12
		'seg':
			n = box(Color(0, 0, 0, 0), 9); n.content_margin_left = 10; n.content_margin_right = 10; n.content_margin_top = 6; n.content_margin_bottom = 6
			h = n.duplicate(); h.bg_color = Color(0, 0, 0, 0.05)
			p = n.duplicate(); p.bg_color = INK
			d = n.duplicate()
			fc = MUTED; fs = 12
		'hud':
			n = box(Color(1, 1, 1, 0.08), 12); n.set_content_margin_all(8)
			h = n.duplicate(); h.bg_color = Color(1, 1, 1, 0.16)
			p = n.duplicate(); p.bg_color = GOLD
			d = n.duplicate()
			fs = 13
		'tab':
			n = box(Color(0, 0, 0, 0), 14); n.set_content_margin_all(6)
			h = n.duplicate(); h.bg_color = Color(1, 1, 1, 0.08)
			p = n.duplicate(); p.bg_color = GOLD
			d = n.duplicate()
			fc = Color(1, 1, 1, 0.8); fs = 11
		'close':
			n = box(Color(1, 1, 1, 0.12), 10); n.set_content_margin_all(6)
			h = n.duplicate(); h.bg_color = FLAG
			d = n.duplicate()
			fs = 16
			b.custom_minimum_size = Vector2(34, 34)
		'closeDark':
			n = box(Color("#e7f0e9"), 10); n.set_content_margin_all(6)
			h = n.duplicate(); h.bg_color = FLAG
			d = n.duplicate()
			fc = INK; fs = 16
			b.custom_minimum_size = Vector2(34, 34)
		'tm', 'tmPrimary':
			var prim := style == 'tmPrimary'
			n = box(GOLD if prim else Color(1, 1, 1, 0.1), 14, Color(1, 1, 1, 0.15) if not prim else Color(0, 0, 0, 0), 0 if prim else 1)
			n.content_margin_left = 18; n.content_margin_right = 18; n.content_margin_top = 12; n.content_margin_bottom = 12
			h = n.duplicate(); h.bg_color = GOLD.lightened(0.1) if prim else Color(1, 1, 1, 0.18)
			d = n.duplicate(); d.bg_color = Color(1, 1, 1, 0.04)
			fc = INK if prim else WHITE; fs = 16
			dc = Color(1, 1, 1, 0.35)
		'mm', 'mmPrimary', 'mmDanger':
			var c := TURF if style == 'mmPrimary' else (FLAG if style == 'mmDanger' else Color.WHITE)
			n = box(c, 12, LINE, 0 if style != 'mm' else 1); n.content_margin_left = 16; n.content_margin_right = 16; n.content_margin_top = 11; n.content_margin_bottom = 11
			h = n.duplicate(); h.bg_color = c.darkened(0.06) if style == 'mm' else c.lightened(0.1)
			d = n.duplicate()
			fc = INK if style == 'mm' else WHITE; fs = 15
		'hb':
			n = box(WHITE, 9, LINE, 1); n.content_margin_top = 4; n.content_margin_bottom = 4
			h = n.duplicate(); h.border_color = TURF
			p = n.duplicate(); p.bg_color = INK; p.border_color = INK
			d = n.duplicate()
			fc = INK; fs = 13
		'who', 'scen', 'plain':
			n = box(WHITE, 12, LINE, 1); n.set_content_margin_all(9)
			h = n.duplicate(); h.border_color = TURF; h.bg_color = Color("#faf5e8")
			p = n.duplicate(); p.border_color = TURF; p.set_border_width_all(2)
			d = n.duplicate(); d.bg_color = Color("#f1eee5")
			fc = INK; fs = 13; fw = 700
		'evopt', 'evoptPrimary':
			var pr := style == 'evoptPrimary'
			n = box(TURF if pr else WHITE, 12, LINE, 0 if pr else 1); n.set_content_margin_all(11)
			h = n.duplicate(); h.bg_color = TURF.lightened(0.1) if pr else Color("#faf5e8")
			d = n.duplicate()
			fc = WHITE if pr else INK; fs = 14
		_:
			n = box(Color(1, 1, 1, 0.1), 10); n.set_content_margin_all(8)
			h = n.duplicate(); h.bg_color = Color(1, 1, 1, 0.2)
			d = n.duplicate()
	if p == null: p = h
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	var f := StyleBoxFlat.new(); f.bg_color = Color(0, 0, 0, 0); f.border_color = GOLD; f.set_border_width_all(2); f.set_corner_radius_all(int(n.corner_radius_top_left)); f.draw_center = false
	b.add_theme_stylebox_override("focus", f)
	b.add_theme_font_override("font", font(fw))
	b.add_theme_font_size_override("font_size", fs)
	for k in ["font_color", "font_hover_color", "font_focus_color"]: b.add_theme_color_override(k, fc)
	var pc := fc
	if style == 'wintab': pc = INK
	elif style == 'seg' or style == 'hb': pc = WHITE
	elif style == 'hud' or style == 'tab': pc = INK
	b.add_theme_color_override("font_pressed_color", pc)
	b.add_theme_color_override("font_hover_pressed_color", pc)
	b.add_theme_color_override("font_disabled_color", dc)
	b.add_theme_color_override("icon_normal_color", fc)
	b.add_theme_color_override("icon_hover_color", fc)
	b.add_theme_color_override("icon_pressed_color", pc)
	b.add_theme_color_override("icon_hover_pressed_color", pc)
	b.add_theme_color_override("icon_focus_color", fc)
	b.add_theme_color_override("icon_disabled_color", dc)
## a segmented control: one of several, as toggle buttons
static func seg(opts: Array, cur, cb: Callable, wrap := false) -> Container:
	var box_: Container = flow(4) if wrap else hbox(4)
	var bg := panel(box(Color("#efeadb"), 11), 3)
	var inner: Container = flow(3) if wrap else hbox(3)
	bg.add_child(inner)
	for o in opts:
		var b := btn(str(o[1]), 'seg')
		b.toggle_mode = true
		b.button_pressed = o[0] == cur
		var key = o[0]
		b.pressed.connect(func(): cb.call(key))
		inner.add_child(b)
	box_.add_child(bg)
	return box_

# ---------- icons: the web version's SVG icons, rasterised at runtime ----------
static var _icons := {}
static func svgTex(svg: String, px: int, col: Color) -> Texture2D:
	var key := "%s|%d|%s" % [svg.hash(), px, col.to_html()]
	if _icons.has(key): return _icons[key]
	var s := svg.replace("currentColor", "#" + col.to_html(false))
	var img := Image.new()
	var scale := px / 24.0
	if img.load_svg_from_string(s, scale) != OK: return null
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex
static func IC(inner: String, sw := 2.0) -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [sw, inner]
static func icon(svg: String, px := 22, col := TURF) -> TextureRect:
	var t := TextureRect.new()
	t.texture = svgTex(svg, px * 2, col)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
## a square badge with an icon in it
static func badge(svg: String, px := 46, bg := Color("#e5f1e8"), fg := TURF, radius := 12, ipx := 26) -> PanelContainer:
	var p := panel(box(bg, radius))
	p.custom_minimum_size = Vector2(px, px)
	var ic := icon(svg, ipx, fg)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(ic)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

# ---------- meters ----------
class Meter extends Control:
	var value := 0.0
	var col := Color("#3f6e2f")
	var bg := Color("#e8e1cf")
	func _init(h := 6.0) -> void: custom_minimum_size = Vector2(20, h); mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_value(v: float, c = null) -> void:
		v = clampf(v, 0, 1)
		if c is Color and c != col: col = c; queue_redraw()
		if abs(v - value) > 0.002: value = v; queue_redraw()
	func _draw() -> void:
		var r := size.y / 2
		draw_rect(Rect2(Vector2.ZERO, size), bg, true)
		if value > 0: draw_rect(Rect2(0, 0, size.x * value, size.y), col, true)
static func meter(h := 6.0, c := TURF) -> Meter:
	var m := Meter.new(h); m.col = c
	return m
class Pips extends Control:
	var n := 5
	var on := 0
	func _init() -> void: custom_minimum_size = Vector2(60, 7); mouse_filter = Control.MOUSE_FILTER_IGNORE
	func setp(nn: int, oo: int) -> void:
		if nn != n or oo != on: n = nn; on = oo; custom_minimum_size.x = n * 9; queue_redraw()
	func _draw() -> void:
		for i in n: draw_rect(Rect2(i * 9, 0, 7, 7), Color("#3f6e2f") if i < on else Color("#dfe7e1"))
