class_name HudUI
extends Control
## The heads-up display: the top bar (money, date, weather, stars, golfers, mood, speed),
## live status pills, the advisor tip, the toolbar, the build bar, toasts and tooltips.

const K = preload("res://scripts/ui/kit.gd")
var g   # the game controller

var topCol: VBoxContainer
var bar: PanelContainer
var parkName: Label
var money: Label
var rate: RichTextLabel
var clockChip: HBoxContainer
var clockIc: TextureRect
var clockTx: Label
var wxIc: TextureRect
var wxTx: Label
var starBtn: Button
var guestBtn: Button
var happyBtn: Button
var trophy: HBoxContainer
var trophyTx: Label
var soundBtn: Button
var speedBtns := []
var pills: HBoxContainer
var pillClip: Control
var pill := {}
var tipBox: PanelContainer
var tipTag: PanelContainer
var tipTx: Label
var tabBtns := {}
var tabDots := {}
var toolbar: PanelContainer
var buildBar: PanelContainer
var bbTitle: Label
var bbHelp: Label
var bbBtns: HBoxContainer
var recenterBtn: Button
var bottomCol: VBoxContainer
var toasts: VBoxContainer
var tooltip: PanelContainer
var tipRich: RichTextLabel
var pausedTag: Label
var verMark: Label
var nowPlaying: Label
var floaters: Control
var _bbKey := ''

func _init(game) -> void:
	g = game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _glass(radius := 16) -> StyleBoxTexture:
	var s = K.grad(K.HUD_TOP, K.HUD_BOT, radius)
	s.content_margin_left = 6; s.content_margin_right = 6; s.content_margin_top = 5; s.content_margin_bottom = 5
	s.texture_margin_left = 0
	return s
func _glassBox(radius := 16) -> StyleBoxFlat:
	var s = K.box(Color(15 / 255.0, 44 / 255.0, 27 / 255.0, 0.95), radius, Color(1, 1, 1, 0.1), 1, 8)
	s.border_width_bottom = 2; s.border_color = Color(1, 1, 1, 0.1)
	return s

func _build() -> void:
	# ---------- top ----------
	topCol = K.vbox(8)
	topCol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(topCol)
	var hb = K.panel(_glassBox(16), 6)
	hb.get_theme_stylebox("panel").content_margin_left = 6
	bar = hb
	var row = K.hbox(4)
	hb.add_child(row)
	topCol.add_child(hb)
	var menuBtn := _hudIconBtn(Icons.MISC.menu, func(): g.dialogs.openMenu())
	menuBtn.tooltip_text = 'Menu (Esc)'
	row.add_child(menuBtn)
	# park, money and today's result
	var park = K.vbox(0)
	parkName = K.lbl('', 10, 800, K.GOLD); parkName.uppercase = true
	money = K.lbl('$0', 22, 800, Color.WHITE)
	rate = K.rich('', 11, Color(1, 1, 1, 0.8)); rate.custom_minimum_size.x = 200; rate.autowrap_mode = TextServer.AUTOWRAP_OFF
	park.add_child(parkName); park.add_child(money); park.add_child(rate)
	row.add_child(_sec(park, false))
	# date and weather
	var tm = K.vbox(3)
	clockChip = K.hbox(6); clockIc = K.icon(Icons.HUD.day, 16, Color.WHITE); clockTx = K.lbl('', 12, 700, Color.WHITE)
	clockChip.add_child(clockIc); clockChip.add_child(clockTx)
	var wx = K.hbox(6); wxIc = K.icon(Icons.HUD.sunny, 16, Color.WHITE); wxTx = K.lbl('', 12, 700, Color.WHITE)
	wx.add_child(wxIc); wx.add_child(wxTx)
	tm.add_child(clockChip); tm.add_child(wx)
	row.add_child(_sec(tm))
	# stars, golfers, mood
	var st = K.hbox(6)
	starBtn = K.btn('★★★★★', 'hud', func(): g.openPanel('park:goals'))
	starBtn.add_theme_color_override("font_color", K.GOLD); starBtn.add_theme_color_override("font_hover_color", K.GOLD)
	starBtn.tooltip_text = 'Star rating: open the Park window'
	guestBtn = K.btn('0 GOLFERS', 'hud', func(): g.openPanel('park:guests'))
	guestBtn.icon = K.svgTex(Icons.MISC.person, 34, Color.WHITE); guestBtn.expand_icon = false
	guestBtn.tooltip_text = 'Golfers in the park: open the Golfers window'
	happyBtn = K.btn('– HAPPY', 'hud', func(): g.openPanel('park:guests'))
	happyBtn.icon = K.svgTex(Icons.MISC.smile, 34, Color.WHITE)
	happyBtn.tooltip_text = 'Golfer happiness and reputation'
	for b in [guestBtn, happyBtn]:
		b.add_theme_constant_override("icon_max_width", 17)
	trophy = K.hbox(5); trophy.add_child(K.icon(Icons.HUD.trophy, 16, K.GOLD)); trophyTx = K.lbl('', 12, 700, K.GOLD); trophy.add_child(trophyTx)
	st.add_child(starBtn); st.add_child(guestBtn); st.add_child(happyBtn); st.add_child(trophy)
	row.add_child(_sec(st))
	row.add_child(K.spacer())
	soundBtn = _hudIconBtn(Icons.MISC.soundOn, func(): g.audio.toggle(); paintSound())
	soundBtn.tooltip_text = 'Sound (M)'
	row.add_child(soundBtn)
	var gear := _hudIconBtn(Icons.MISC.gear, func(): g.dialogs.openSettings())
	gear.tooltip_text = 'Settings'
	row.add_child(gear)
	var speed = K.panel(K.box(Color(1, 1, 1, 0.06), 12), 3)
	var sp = K.hbox(2)
	speed.add_child(sp)
	var names := ['pause', 'play', 'fast', 'fastest']
	var tips := ['Pause (Space)', 'Normal speed', 'Fast', 'Fastest']
	for i in 4:
		var b = K.btn('', 'hud')
		b.toggle_mode = true
		b.icon = K.svgTex(Icons.MISC[names[i]], 36, Color.WHITE)
		b.add_theme_constant_override("icon_max_width", 18)
		b.custom_minimum_size = Vector2(38, 36)
		b.tooltip_text = tips[i]
		var idx := i
		b.pressed.connect(func(): Sim.setSpeed(idx); Sim.sfx('tap'); paintSpeed())
		sp.add_child(b); speedBtns.append(b)
	row.add_child(speed)
	Sim.speed_changed.connect(paintSpeed)
	# ---------- pills ----------
	pills = K.hbox(6)
	pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pillClip = Control.new(); pillClip.clip_contents = true; pillClip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pillClip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pillClip.add_child(pills)
	topCol.add_child(pillClip)
	for k in ['goal', 'event', 'bays', 'balls', 'park', 'tee', 'club', 'cond', 'mood', 'conduct', 'away']:
		var click = k == 'goal' or k == 'event'
		var p = K.panel(K.box(Color(242 / 255.0, 193 / 255.0, 78 / 255.0, 0.92) if k == 'event' else K.GLASS, 10, Color(1, 1, 1, 0.12), 1), 0)
		var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
		sb.content_margin_left = 9; sb.content_margin_right = 10; sb.content_margin_top = 4; sb.content_margin_bottom = 4
		var h = K.hbox(6)
		var dot := DotRect.new()
		var tx = K.lbl('', 11, 700, Color("#2a2008") if k == 'event' else Color.WHITE)
		h.add_child(dot); h.add_child(tx)
		p.add_child(h)
		pills.add_child(p)
		p.mouse_filter = Control.MOUSE_FILTER_STOP if click else Control.MOUSE_FILTER_IGNORE
		if click:
			p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var key = k
			p.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					g.openPanel('park:goals' if key == 'goal' else 'park:events'); Sim.sfx('open'))
		pill[k] = { "p": p, "dot": dot, "tx": tx }
	# ---------- advisor ----------
	tipBox = K.panel(K.box(K.PAPER, 14, K.GOLD, 0, 6), 0)
	var tsb: StyleBoxFlat = tipBox.get_theme_stylebox("panel")
	tsb.border_width_left = 5; tsb.content_margin_left = 8; tsb.content_margin_right = 12; tsb.content_margin_top = 8; tsb.content_margin_bottom = 8
	var th = K.hbox(10)
	tipTag = K.panel(K.box(K.GOLD, 8), 0)
	var tg: StyleBoxFlat = tipTag.get_theme_stylebox("panel"); tg.content_margin_left = 7; tg.content_margin_right = 7; tg.content_margin_top = 5; tg.content_margin_bottom = 5
	var tl = K.lbl('ADVISOR', 9, 800, K.INK)
	tipTag.add_child(tl)
	tipTag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tipTx = K.lbl('', 13, 700, K.INK, true)
	tipTx.custom_minimum_size.x = 420
	th.add_child(tipTag); th.add_child(tipTx)
	tipBox.add_child(th)
	tipBox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	topCol.add_child(tipBox)
	# ---------- bottom ----------
	bottomCol = K.vbox(8)
	bottomCol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottomCol)
	recenterBtn = K.btn('Recenter', 'hud', func(): g.recenter())
	var rcs = K.box(K.GLASS, 999, Color(1, 1, 1, 0.12), 1); rcs.content_margin_left = 14; rcs.content_margin_right = 14; rcs.content_margin_top = 8; rcs.content_margin_bottom = 8
	recenterBtn.add_theme_stylebox_override("normal", rcs)
	recenterBtn.add_theme_font_size_override("font_size", 12)
	recenterBtn.size_flags_horizontal = Control.SIZE_SHRINK_END
	recenterBtn.visible = false
	bottomCol.add_child(recenterBtn)
	buildBar = K.panel(K.box(K.PAPER, 16, K.GOLD, 0, 10), 0)
	var bbs: StyleBoxFlat = buildBar.get_theme_stylebox("panel")
	bbs.border_width_left = 5; bbs.content_margin_left = 14; bbs.content_margin_right = 10; bbs.content_margin_top = 10; bbs.content_margin_bottom = 10
	var bbr = K.hbox(12)
	var bbt = K.vbox(2)
	bbTitle = K.lbl('', 14, 800, K.INK)
	bbHelp = K.lbl('', 12, 600, K.MUTED, true)
	bbHelp.custom_minimum_size.x = 360
	bbt.add_child(bbTitle); bbt.add_child(bbHelp)
	bbr.add_child(K.expand(bbt))
	bbBtns = K.hbox(6)
	bbBtns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bbr.add_child(bbBtns)
	buildBar.add_child(bbr)
	buildBar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buildBar.custom_minimum_size.x = 520
	buildBar.visible = false
	bottomCol.add_child(buildBar)
	toolbar = K.panel(_glassBox(20), 6)
	var tb = K.hbox(4)
	toolbar.add_child(tb)
	toolbar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tabNames := { "build": 'Build', "course": 'Course', "staff": 'Staff', "golfers": 'Golfers', "fin": 'Finances', "park": 'Park' }
	var n := 1
	for k in g.WIN_ORDER:
		var b = K.btn(tabNames[k], 'tab')
		b.toggle_mode = true
		b.icon = K.svgTex(Icons.TAB[k], 48, Color(1, 1, 1, 0.85))
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_constant_override("icon_max_width", 24)
		b.custom_minimum_size = Vector2(74, 62)
		b.tooltip_text = "%s (%d)" % [tabNames[k], n]
		var key: String = k
		b.pressed.connect(func(): g.toggleWindow(key); paintTabs())
		var kb = K.lbl(str(n), 9, 800, Color(1, 1, 1, 0.45)); kb.position = Vector2(6, 3)
		b.add_child(kb)
		var dot := DotRect.new(); dot.col = K.FLAG; dot.custom_minimum_size = Vector2(9, 9); dot.position = Vector2(54, 6); dot.visible = false
		b.add_child(dot)
		tb.add_child(b)
		tabBtns[k] = b; tabDots[k] = dot
		n += 1
	bottomCol.add_child(toolbar)
	# ---------- floating bits ----------
	toasts = K.vbox(8)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)
	floaters = Control.new(); floaters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floaters)
	pausedTag = K.lbl('PAUSED', 26, 800, Color.WHITE)
	var pt = K.panel(K.box(Color(9 / 255.0, 28 / 255.0, 17 / 255.0, 0.55), 14), 0)
	pt.get_theme_stylebox("panel").content_margin_left = 20; pt.get_theme_stylebox("panel").content_margin_right = 20
	pt.get_theme_stylebox("panel").content_margin_top = 6; pt.get_theme_stylebox("panel").content_margin_bottom = 6
	pt.add_child(pausedTag); pt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pt.name = 'PausedTag'
	add_child(pt)
	verMark = K.lbl("Fairway Tycoon v%s" % Sim.GAME_VERSION, 10, 700, Color(1, 1, 1, 0.45))
	add_child(verMark)
	nowPlaying = K.lbl('', 11, 700, Color(1, 1, 1, 0.75)); nowPlaying.modulate.a = 0
	add_child(nowPlaying)
	tooltip = K.panel(K.box(Color(9 / 255.0, 28 / 255.0, 17 / 255.0, 0.94), 10, Color(1, 1, 1, 0.12), 1, 6), 9)
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tipRich = K.rich('', 12, Color.WHITE)
	tipRich.custom_minimum_size.x = 240
	tipRich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(tipRich)
	tooltip.visible = false
	add_child(tooltip)
	paintSound(); paintSpeed()

func _sec(c: Control, line := true) -> Control:
	var m = K.margin(c, 12, 0, 12, 0)
	if line:
		var p = K.panel(StyleBoxEmpty.new())
		var hb = K.hbox(0)
		var ln := ColorRect.new(); ln.color = Color(1, 1, 1, 0.1); ln.custom_minimum_size = Vector2(1, 30); ln.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(ln); hb.add_child(m)
		return hb
	return m
func _hudIconBtn(svg: String, cb: Callable) -> Button:
	var b = K.btn('', 'hud', cb)
	b.icon = K.svgTex(svg, 40, Color.WHITE)
	b.add_theme_constant_override("icon_max_width", 20)
	b.custom_minimum_size = Vector2(40, 40)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b

class DotRect extends Control:
	var col := Color("#7fe09a")
	func _init() -> void: custom_minimum_size = Vector2(7, 7); size_flags_vertical = Control.SIZE_SHRINK_CENTER; mouse_filter = Control.MOUSE_FILTER_IGNORE
	func setc(c: Color) -> void:
		if c != col: col = c; queue_redraw()
	func _draw() -> void: draw_circle(size / 2, min(size.x, size.y) / 2, col, true, -1.0, true)

# ---------- layout ----------
func layout() -> void:
	var vs: Vector2 = get_parent().size if get_parent() else Vector2(1600, 900)
	topCol.position = Vector2(12, 12)
	topCol.size = Vector2(vs.x - 24, 0)
	bar.custom_minimum_size.x = vs.x - 24
	var dock: float = (g.sheet.size.x + 24) if g.sheetOpen else 0.0
	_fitPills()
	bottomCol.size = Vector2(vs.x - 20 - dock, 0)
	bottomCol.position = Vector2(10, vs.y - bottomCol.get_combined_minimum_size().y - 8)
	toasts.custom_minimum_size.x = 380
	toasts.position = Vector2((vs.x - 380) / 2, topCol.position.y + bar.size.y + 16)
	var pt := get_node("PausedTag") as Control
	pt.reset_size()
	pt.position = Vector2((vs.x - dock - pt.size.x) / 2, vs.y * 0.42 - pt.size.y / 2)
	verMark.reset_size(); verMark.position = Vector2(vs.x - verMark.size.x - 6, vs.y - verMark.size.y - 4)
	nowPlaying.reset_size(); nowPlaying.position = Vector2(vs.x - nowPlaying.size.x - 6 - dock, vs.y - nowPlaying.size.y - 18)
	floaters.size = vs
## like the web version, the pills stop at the edge of a docked window
func _fitPills() -> void:
	var vs: Vector2 = get_parent().size if get_parent() else Vector2(1600, 900)
	var dock: float = (g.sheet.size.x + 24) if g.sheetOpen else 0.0
	var ms := pills.get_combined_minimum_size()
	pills.size = ms
	pillClip.custom_minimum_size = Vector2(min(ms.x, vs.x - dock - 30), ms.y)
func topHeight() -> float: return topCol.position.y + topCol.get_combined_minimum_size().y + 8
func bottomHeight() -> float: return bottomCol.get_combined_minimum_size().y + 16

# ---------- per frame ----------
var _toastT := []
var _npT := 0.0
func frame(dt: float) -> void:
	# toasts fade out after a few seconds
	for i in range(_toastT.size() - 1, -1, -1):
		var t = _toastT[i]
		t.t += dt
		if t.t > 4.2: t.n.modulate.a = max(0.0, 1 - (t.t - 4.2) / 0.4)
		if t.t > 4.6: t.n.queue_free(); _toastT.remove_at(i)
	for f in floaters.get_children():
		var age: float = f.get_meta("age", 0.0) + dt
		f.set_meta("age", age)
		f.position.y = f.get_meta("y0") - 64 * age / 0.9
		f.modulate.a = max(0.0, 1 - age / 0.9)
		if age > 0.95: f.queue_free()
	if _npT > 0:
		_npT -= dt
		nowPlaying.modulate.a = clampf(min(_npT, 6 - _npT) / 0.6, 0, 0.75)
	var pt := get_node("PausedTag") as Control
	pt.visible = Sim.speedIdx == 0 and not Sim.designing and not Sim.atTitle and not g.dialogs.blocking()
	visible = not Sim.atTitle
	if g.tool != null and g.tool.kind == 'place': paintBuildBar()

# ---------- refresh (four times a second) ----------
func refresh() -> void:
	if Sim.atTitle: return
	var S: Dictionary = Sim.S
	K.setText(parkName, Sim.clubName().to_upper())
	K.setText(money, Sim.fmt(S.money))
	K.setCol(money, Color("#ff9b8c") if S.money < 0 else Color.WHITE)
	var td: float = Sim.sumOf(S.ledger.day) if S.get("ledger") else 0.0
	K.setRich(rate, "[b][color=%s]%s%s[/color][/b] today · costs %s a day" % ['#ff9b8c' if td < 0 else '#9ff0b4', '−' if td < 0 else '+', Sim.fmt(abs(td)), Sim.fmt(Sim.costsPerDay())])
	var dark: bool = Sim.isDark()
	clockIc.texture = K.svgTex(Icons.HUD.night if dark else Icons.HUD.day, 32, Color.WHITE)
	K.setText(clockTx, "%s · %s%s" % [Sim.dateLabel(S.day, true), Sim.fmtClock(), ' · frost' if Sim.isFrost() else ''])
	wxIc.texture = K.svgTex(Icons.HUD[S.wx], 32, Color.WHITE)
	K.setText(wxTx, "%s → %s in %dm" % [Sim.W_().label, Sim.WEATHER[S.wxNext].label.to_lower(), int(ceil(S.wxLeft / 60.0))])
	trophy.visible = S.get("trophies", 0) > 0
	K.setText(trophyTx, "%d · +%d%%" % [S.get("trophies", 0), S.get("trophies", 0) * 15])
	starBtn.text = Sim.starText(Sim.starsC)
	var here: Array = Sim.visitors.filter(func(v): return v.state != 'gone')
	guestBtn.text = "%d GOLFERS" % here.size()
	var am = Sim.avgMood()
	happyBtn.text = "%s HAPPY" % ('–' if am == null else "%d%%" % roundi(am))
	var hc = Color.WHITE if am == null else (Color("#ff9b8c") if am < 40 else (K.GOLD if am < 58 else Color("#9ff0b4")))
	for k in ["font_color", "font_hover_color"]: happyBtn.add_theme_color_override(k, hc)
	S.lastRate = max(0.0, Sim.incomeRate())
	_pills()
	_fitPills()
	_tip()
	paintTabs()
	layout()
func _setPill(k: String, show: bool, lvl: String, text: String) -> void:
	var p = pill[k]
	p.p.visible = show
	if not show: return
	p.dot.setc(K.FLAG if lvl == 'bad' else (K.GOLD if lvl == 'warn' else Color("#7fe09a")))
	p.dot.visible = k != 'event'
	K.setText(p.tx, text)
func _pills() -> void:
	var S: Dictionary = Sim.S
	var RS: Dictionary = Sim.rangeSum()
	var b: int = RS.bays
	var sb: int = max(1, RS.staffed)
	var bp: float = RS.players / float(sb)
	if not RS.n: _setPill('bays', true, '', 'No range yet')
	else: _setPill('bays', true, 'bad' if bp >= 1 else ('warn' if bp > 0.7 else ''), "Bays %d/%d%s" % [RS.players, RS.staffed, (" (%d closed)" % (b - RS.staffed)) if RS.staffed < b else ''])
	_setPill('balls', true, 'bad' if (RS.n and RS.stock < 100 * RS.n) else ('warn' if RS.stock < 300 * RS.n else ''), "Balls %s" % Sim.fmtInt(floor(RS.stock)))
	var sp: float = Sim.groups.size() / float(max(1, Sim.slots()))
	_setPill('tee', true, 'bad' if sp >= 1 else ('warn' if sp > 0.6 else ''), "Tee times %d/%d" % [Sim.groups.size(), Sim.slots()])
	var u: int = Sim.usedSpots()
	var n: int = Sim.totalSpots()
	var f: float = u / float(n) if n else 1.0
	_setPill('park', true, 'bad' if f >= 1 else ('warn' if f > 0.75 else ''), ("Parking %d/%d" % [u, n]) if n else 'No car park')
	_setPill('cond', true, 'bad' if S.cond < 50 else ('warn' if S.cond < 80 else ''), "Course %d%%" % roundi(S.cond))
	_setPill('away', true, 'bad' if Sim.away.size() >= 5 else ('warn' if Sim.away.size() else ''), "Left unhappy %d" % Sim.away.size())
	var inside: int = Sim.visitors.filter(func(v): return v.state == 'venue' or v.state == 'desk').size()
	var q: int = Sim.teeQueue.size() + Sim.lobbyQueue.size() + Sim.deskQueue.size()
	_setPill('club', true, 'bad' if q >= 6 else ('warn' if q >= 2 else ''), "Clubhouse %d in · %d queuing" % [inside, q])
	var am = Sim.avgMood()
	var rep: float = S.get("rep", 70.0)
	_setPill('mood', true, '' if am == null else ('bad' if am < 40 else ('warn' if am < 58 else '')), "Mood %s · reputation %d" % ['–' if am == null else "%d%%" % roundi(am), roundi(rep)])
	var trouble := false
	for v in Sim.visitors:
		if v.get("flagged") and not v.get("ejected"): trouble = true; break
	var lm: int = Sim.litter.size() + Sim.marks.size() * 2
	_setPill('conduct', true, 'bad' if lm >= 12 else ('warn' if (Sim.litter.size() + Sim.marks.size()) else ''), "Litter %d · damage %d%s" % [Sim.litter.size(), Sim.marks.size(), ' · ⚠ trouble' if trouble else ''])
	# what's happening now
	var t: float = Sim.nowT()
	var ms: Array = Sim.activeMods()
	for m in S.get("mods", []):
		if m.start > t and m.start - t < Sim.DAY_LEN: ms.append(m)
	if ms.is_empty(): _setPill('event', false, '', '')
	else: _setPill('event', true, '', "%s %s · %s%s" % [ms[0].icon, ms[0].label, Sim.timeLeft(ms[0]), (" +%d" % (ms.size() - 1)) if ms.size() > 1 else ''])
	# the objective
	var sc = Sim.scenOf(S.get("scenario"))
	if not sc or sc.id == 'sandbox': _setPill('goal', false, '', '')
	else:
		var lvl := ''
		var h := ''
		if S.money < 0: h = "Overdrawn · %dd to bank closure" % max(0, Sim.diff().redDays - S.get("redDays", 0)); lvl = 'bad'
		elif S.get("repLow", 0) > 0: h = "Boycott · %dd left" % (Sim.diff().repDays - S.repLow); lvl = 'bad'
		elif S.get("board") != null and S.board < 30 and not S.get("finished"): h = "Board confidence %d%%" % roundi(S.board); lvl = 'warn'
		elif S.get("finished"): h = "%s %s · free play" % [Sim.MEDAL_IC[S.medal], Sim.MEDAL[S.medal]]
		else:
			var tier: int = min(2, S.get("medal", 0))
			var list: Array = sc.medals[tier]
			var done := 0
			for c in list:
				if c.ok.call(): done += 1
			h = "%s%s %d/%d · %s" % [(Sim.MEDAL_IC[S.medal] + ' ') if S.get("medal", 0) else '', Sim.MEDAL[tier + 1], done, list.size(), Sim.timeLeftTxt()]
		_setPill('goal', true, lvl, h)
func _tip() -> void:
	var S: Dictionary = Sim.S
	var why := func(k): return Sim.away.filter(func(a): return a.why == k).size()
	var tip := ''
	var bad := false
	var unlinked = null
	for o in Sim.objs():
		if not Sim.OBJ[o.type].get("free") and o.type != 'lot' and not Sim.connected('OBJ:%s' % o.id): unlinked = o; break
	var lowSup = null
	for k in Sim.SUPPLIES:
		if not Sim.SUPPLIES[k].get("durable") and S.sup.get(k, 0) < 1 and (k != 'training' or Sim.hasObj('academy')): lowSup = k; break
	var rtips := []
	Sim.forRanges(func(o): rtips.append(_rangeTip(o)))
	var rtip = null
	for r in rtips:
		if r != null: rtip = r; break
	var closedVenue := ''
	if Sim.L('barRoom') and not Sim.N('bar'): closedVenue = 'The bar is built but closed. Hire a bartender on the Staff tab.'
	elif Sim.L('resto') and not Sim.N('chef'): closedVenue = 'The restaurant is built but closed. Hire a chef on the Staff tab.'
	var pricey := []
	for it in Sim.PRICE_ITEMS:
		if it.shown.call() and Sim.ratioOf(it.k) > 1.25: pricey.append(it.label.to_lower())
	var RS: Dictionary = Sim.rangeSum()
	var hasLot := Sim.objs().any(func(o): return o.type == 'lot')
	var worst := -1
	for i in Sim.builtIdx():
		if Sim.turfOf(i) < 50 and (worst < 0 or Sim.turfOf(i) < Sim.turfOf(worst)): worst = i
	var canEvent := false
	for E in Sim.EVENTS.values():
		if E.needs.call().all(func(x): return x[1]): canEvent = true
	if not hasLot: tip = 'Welcome! Start with a car park on the public road along the bottom of your land. Open Build and pick Car park.'
	elif not Sim.hasObj('range') and not Sim.courseHoles() and not Sim.hasObj('shortc'): tip = 'Now build a driving range: it is the quickest way to start earning. Build → Driving range.'
	elif unlinked: tip = "Golfers can't reach your %s. Lay a footpath from a car park to its door (the red square), or let Build → Auto path suggest one." % Sim.OBJ[unlinked.type].label.to_lower(); bad = true
	elif not Sim.hasObj('club') and Sim.courseHoles(): tip = 'Golfers check in and pay their green fee at the clubhouse before a round. Build a clubhouse so they can play your course.'; bad = true
	elif not Sim.hasObj('club') and S.money >= Sim.OBJ.club.cost: tip = 'Build a clubhouse so golfers can shop, eat and drink, and so you can sell memberships.'
	elif not Sim.courseHoles() and S.money >= 8000: tip = 'Ready for golf? Open Course, then the course designer, to build your first holes. Buy land with Build → Buy land.'
	elif Sim.courseHoles() and not Sim.courseOK(): tip = 'Run a footpath to within a few tiles of the first tee so golfers can start their rounds. Build → Auto path can suggest one.'; bad = true
	elif lowSup: tip = "You've run out of %s. Order more on Build → Supplies, or turn on automatic reordering." % Sim.SUPPLIES[lowSup].label.to_lower(); bad = true
	elif S.money < 0: tip = "You're overdrawn%s. Borrow in Finances, raise prices or cut costs before the bank steps in." % ((" (%d day%s)" % [S.redDays, 's' if S.redDays > 1 else '']) if S.get("redDays", 0) else ''); bad = true
	elif Sim.isFrost() and Sim.hour() > 6: tip = 'Frost has closed the course until 10:30. The range and clubhouse are still open.'
	elif pricey.size(): tip = "Golfers think your %s %s overpriced, so fewer of them come. Check prices in Finances." % [' and '.join(pricey), 'are' if pricey.size() > 1 else 'is']
	elif rtip: tip = rtip.tip; bad = rtip.bad
	elif why.call('gaveup-course') >= 2: tip = 'Golfers gave up waiting at the first tee. Add tee times or golf carts, or hire a starter to keep them patient.'
	elif why.call('gaveup-checkin') >= 2: tip = "Golfers gave up waiting to check in at the clubhouse desk. Shop assistants open extra desks (%d of 3 open)." % Sim.desks()
	elif why.call('gaveup-club') >= 2: tip = 'Guests gave up waiting for a table at the clubhouse. Add seats, or more staff to serve them faster.'
	elif why.call('rpark') + why.call('cpark') >= 2: tip = 'Golfers are turning around because your car parks are full. Place another car park on the road (Build tab).'
	elif (Sim.litter.size() >= 8 or Sim.marks.size() >= 4) and not Sim.N('marshal'): tip = "Litter and damage are piling up (%d litter, %d damage), and it is putting golfers off. Hire a marshal to patrol the park." % [Sim.litter.size(), Sim.marks.size()]; bad = true
	elif RS.broken >= 2 and not Sim.N('marshal'): tip = "%d range bays are out of order after vandalism. A marshal repairs them quickly." % RS.broken
	elif S.get("rep", 70.0) < 50: tip = "The club's reputation is slipping (%d/100), so fewer golfers come. Cut the waiting, keep the course in shape and add things to enjoy." % roundi(S.rep); bad = true
	elif closedVenue != '': tip = closedVenue
	elif worst >= 0: tip = "Hole %d's turf is badly worn (%d%%). Golfers play worse and enjoy it less. Hire greenkeepers%s." % [worst + 1, roundi(Sim.turfOf(worst)), '' if Sim.L('irrig') else ' or install irrigation']; bad = true
	elif S.get("memberMood", 70.0) < 50 and S.get("members", 0) > 3: tip = "Your members are unhappy (%d%%) and some will leave at the end of the month. Look after the turf, the pace of play and the clubhouse." % roundi(S.memberMood); bad = true
	elif Sim.isDark() and not Sim.L('lights'): tip = "It's night, so the course is closed and the range is empty. Floodlights keep the range open."
	elif S.wx == 'rain' and Sim.L('covered') < 2: tip = 'Rain keeps golfers home. Covered bays bring range golfers back in bad weather.'
	elif not Sim.L('back9') and S.money >= 20000: tip = 'Buy land and build holes 10 to 18 in the course designer. 18-hole rounds pay nearly double.'
	elif not Sim.L('barRoom') and S.money >= 1500: tip = 'Build a bar at the clubhouse. Golfers stop for a drink after playing, and it opens the way to a terrace.'
	elif not S.get("event") and not S.get("eventsDone") and canEvent: tip = 'You can host your first event. Book one in the Park tab.'
	tipBox.visible = tip != '' and not Sim.designing
	K.setText(tipTx, tip)
	var sbx: StyleBoxFlat = tipBox.get_theme_stylebox("panel")
	sbx.border_color = K.FLAG if bad else K.GOLD
	var tgs: StyleBoxFlat = tipTag.get_theme_stylebox("panel")
	tgs.bg_color = K.FLAG if bad else K.GOLD
	K.setCol(tipTag.get_child(0), Color.WHITE if bad else K.INK)
func _rangeTip(o):
	var nm := (Sim.rangeName(o) + ': ') if Sim.rangeObjs().size() > 1 else ''
	var S: Dictionary = Sim.S
	var ballsShort: bool = Sim.bucketQueue.size() > 0 and S.stock < 50
	var mine := func(k): return Sim.away.filter(func(a): return a.why == k and a.get("range") == o.id).size()
	if ballsShort and S.owned < 300: return { "tip": nm + "Golfers are queuing for balls and you're running low. Too many have been lost. Order more range balls (Range tab).", "bad": true }
	if ballsShort and not Sim.N('picker'): return { "tip": nm + "Golfers are queuing because the dispenser is empty while %s balls lie on the range. Hire a ball picker for this range." % Sim.fmtInt(floor(S.field)), "bad": true }
	if ballsShort and Sim.L('cart') < Sim.N('picker'): return { "tip": nm + "The pickers can't keep up with %s balls on the range. Give them carts, or hire another picker." % Sim.fmtInt(floor(S.field)), "bad": true }
	if ballsShort: return { "tip": nm + 'The picker carts cannot keep up. Hire another picker or buy bigger cages.', "bad": true }
	if mine.call('gaveup-range') >= 2: return { "tip": nm + "Golfers gave up in the line at the ball machine. %supgrade the dispenser so buckets fill faster." % ('Add an extra ball machine or ' if Sim.machines() < 3 else ''), "bad": false }
	if mine.call('gaveup-bay') >= 2 and Sim.staffedBays() < Sim.bays(): return { "tip": nm + "Golfers gave up waiting for a bay while %d sit closed. Hire a range attendant for this range." % (Sim.bays() - Sim.staffedBays()), "bad": false }
	if mine.call('gaveup-bay') >= 2: return { "tip": nm + 'Golfers with a full bucket gave up waiting for a free bay. Add hitting bays.', "bad": false }
	return null

func paintSpeed() -> void:
	for i in speedBtns.size(): speedBtns[i].set_pressed_no_signal(i == Sim.speedIdx)
func paintSound() -> void:
	soundBtn.icon = K.svgTex(Icons.MISC.soundOn if g.audio.on else Icons.MISC.soundOff, 40, Color.WHITE if g.audio.on else Color(1, 1, 1, 0.5))
## the red dots that say "something to buy here"
func paintTabs() -> void:
	for k in tabBtns:
		var b: Button = tabBtns[k]
		var sel: bool = g.sheetOpen and g.curWin == k
		b.set_pressed_no_signal(sel)
		b.icon = K.svgTex(Icons.TAB[k], 48, K.INK if sel else Color(1, 1, 1, 0.85))
		var show := false
		match k:
			'park':
				if not Sim.S.get("event"):
					for E in Sim.EVENTS.values():
						if E.needs.call().all(func(x): return x[1]): show = true
			'fin': show = Sim.S.money < 0
			'build': show = g.sheet.anythingToBuy('build')
			'course': show = g.sheet.anythingToBuy('course')
			'staff': show = g.sheet.anythingToBuy('staff')
		tabDots[k].visible = show and not sel
func showRecenter(on: bool) -> void: recenterBtn.visible = on

# ---------- toasts ----------
func toast(kicker: String, title: String, text: String, icon := '★') -> void:
	var p = K.panel(K.box(K.INK, 16, Color(1, 1, 1, 0.08), 1, 10), 0)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel"); sb.content_margin_left = 10; sb.content_margin_right = 14; sb.content_margin_top = 10; sb.content_margin_bottom = 10
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h = K.hbox(12)
	var ic = K.panel(K.box(K.GOLD, 20), 0)
	ic.custom_minimum_size = Vector2(40, 40)
	var il = K.lbl(icon, 18, 800, K.INK); il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.add_child(il)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v = K.vbox(1)
	v.add_child(K.eyebrow(kicker, K.GOLD))
	v.add_child(K.lbl(title, 15, 800, Color.WHITE, true))
	if text != '': v.add_child(K.lbl(text, 12, 600, Color(1, 1, 1, 0.8), true))
	h.add_child(K.expand(v))
	p.add_child(h)
	p.custom_minimum_size.x = 380
	toasts.add_child(p)
	_toastT.append({ "n": p, "t": 0.0 })
	while toasts.get_child_count() > 3:
		var c := toasts.get_child(0)
		toasts.remove_child(c); c.queue_free()
		_toastT = _toastT.filter(func(x): return is_instance_valid(x.n) and x.n != c)
## "+$6" pops where golfers pay, when you're zoomed in close enough to see them
func moneyPop(v, amount: float) -> void:
	if Sim.warp == 0 or Sim.warp > 2 or g.view.cam.s < 0.9 or floaters.get_child_count() > 6 or not g.view.onScreen(v.x, v.y): return
	var sp: Vector2 = g.view.toScreen(v.x, v.y) / g.uiScale()
	var l = K.lbl('+' + Sim.fmt(amount), 13, 800, Color("#c6f27a"))
	l.label_settings.outline_size = 4; l.label_settings.outline_color = Color(0, 0, 0, 0.45)
	l.position = Vector2(sp.x - 14, sp.y - 22)
	l.set_meta("y0", sp.y - 22)
	floaters.add_child(l)
func nowPlayingShow(text: String) -> void:
	nowPlaying.text = '♪ ' + text; _npT = 6.0; layout()

# ---------- the build bar ----------
func paintBuildBar() -> void:
	var tool = g.tool
	buildBar.visible = tool != null
	if tool == null: return
	var key := ''
	if tool.kind == 'suggest':
		var cost: float = tool.cost
		key = "s|%s|%s|%s|%d" % [tool.label, tool.get("msg", ''), Sim.S.money >= cost, tool.tiles.size()]
		if key == _bbKey: return
		_bbKey = key
		bbTitle.text = "Suggested footpath to the %s" % tool.label
		var msg: String = tool.get("msg", '')
		bbHelp.text = msg if msg != '' else "%d tile%s · %s. Build it, or lay your own path instead." % [tool.tiles.size(), '' if tool.tiles.size() == 1 else 's', Sim.fmt(cost)]
		K.setCol(bbHelp, K.NEG if tool.get("bad") else K.MUTED)
		K.clear(bbBtns)
		var b = K.btn('Build path', 'buy', func(): g.buildSuggested())
		b.disabled = Sim.S.money < cost
		bbBtns.add_child(b)
		bbBtns.add_child(_doneBtn('Not now'))
		return
	var D = Sim.OBJ[tool.type] if tool.kind == 'place' else null
	var TT = Sim.TERRA.get(tool.kind)
	var title := ''
	if TT: title = "%s · %s" % [TT.label, ("%s a tile" % Sim.fmt(TT.cost)) if (tool.kind == 'water' or tool.kind == 'drain') else ("%s a metre a tile" % Sim.fmt(TT.cost * 2))]
	elif D: title = ("Move: %s" % D.label) if tool.get("moveId") else ("%s · %s" % [D.label, Sim.fmt(D.cost)])
	else: title = { "path": "Footpath · %s a tile" % Sim.fmt(Sim.PATH_COST), "unpath": 'Remove footpath', "erase": 'Demolish', "land": 'Buy land', "move": 'Move a building' }.get(tool.kind, '')
	var help: String = tool.get("msg", '')
	if help == '':
		if D: help = "Click to place the %s. Right-click or Esc to stop." % D.label.to_lower()
		elif TT: help = TT.help + ' Click and drag to brush. [ and ] change the brush.'
		else: help = { "path": "Click and drag to lay footpath. Right-click or Esc to stop. Over water it becomes a bridge (%s a tile)." % Sim.fmt(Sim.BRIDGE_COST),
			"unpath": 'Click and drag over footpath to remove it.', "erase": 'Click something you built to demolish it (you get 40% back). The range and clubhouse can only be moved.',
			"land": 'Click a plot for sale to see its price, then buy it.', "move": 'Click a building to pick it up, then put it somewhere else. Moving is free.' }.get(tool.kind, '')
	var plot = tool.get("plot")
	key = "%s|%s|%s|%s|%s|%d|%s" % [tool.kind, title, help, tool.get("bad"), plot, Sim.terBrush, Sim.S.money >= Sim.parcelPrice()]
	if key == _bbKey: return
	_bbKey = key
	bbTitle.text = title
	bbHelp.text = help
	K.setCol(bbHelp, K.NEG if tool.get("bad") else K.MUTED)
	K.clear(bbBtns)
	if TT:
		var segs := []
		for i in Sim.BRUSH.size(): segs.append([i, Sim.BRUSH[i].k])
		bbBtns.add_child(K.seg(segs, Sim.terBrush, func(i): Sim.terBrush = i; Sim.sfx('tap'); _bbKey = ''; paintBuildBar()))
	if tool.kind == 'land' and plot != null:
		if not Sim.S.world.land.has(plot):
			var price := Sim.parcelPrice()
			var b = K.btn("Buy for %s" % Sim.fmt(price), 'buy', func():
				if Sim.buyPlot(tool.plot): tool.msg = 'Bought. The land is yours to build on.'; tool.bad = false
				_bbKey = ''; paintBuildBar())
			b.disabled = Sim.S.money < price
			bbBtns.add_child(b)
	bbBtns.add_child(_doneBtn('Done'))
func _doneBtn(t: String) -> Button:
	var b = K.btn(t, 'ghost', func(): g.setTool(null); Sim.sfx('close'))
	b.add_theme_color_override("font_color", K.INK); b.add_theme_font_size_override("font_size", 13)
	return b

# ---------- the hover tooltip ----------
var _ttT := 0.0
func updateTooltip(mouse: Vector2, allowed: bool) -> void:
	_ttT -= get_process_delta_time()
	if not allowed or g.hoverWorld == null: tooltip.visible = false; return
	if _ttT > 0 and tooltip.visible:
		_placeTip(mouse); return
	_ttT = 0.15
	var html: String = Hover.html(g, g.hoverWorld.x, g.hoverWorld.y)
	if html == '': tooltip.visible = false; return
	K.setRich(tipRich, html)
	tooltip.visible = true
	tooltip.reset_size()
	_placeTip(mouse)
func _placeTip(mouse: Vector2) -> void:
	var vs: Vector2 = get_parent().size
	tooltip.position = Vector2(min(vs.x - tooltip.size.x - 8, mouse.x + 16), min(vs.y - tooltip.size.y - 8, mouse.y + 18))
