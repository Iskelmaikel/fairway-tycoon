class_name Dialogs
extends Control
## Everything that sits over the park: the title screen (new game, load), the pause menu,
## save slots, settings, event cards, the end-of-scenario screen, event results and away earnings.

const K = preload("res://scripts/ui/kit.gd")
var g
var title: Control
var titleMain: VBoxContainer
var titleNew: VBoxContainer
var titleLoad: VBoxContainer
var titleTag: Label
var nameIn: LineEdit
var scenList: VBoxContainer
var diffBox: Control
var diffBlurb: Label
var scenDetail: VBoxContainer
var modals := {}        # name -> overlay Control
var slotMode := 'save'
var slotList: VBoxContainer
var slotTitle: Label
var slotArm = null

const SCEN_NAME := { "fresh": 'Pine Hollow Golf Club', "rescue": 'Pine Hollow Golf Club', "city": 'City Lights Golf Centre', "seaside": 'Seaside Links', "oakmere": 'Oakmere Golf Club', "frost": 'Frostbite Golf Club', "estate": 'Kingsbridge Estate', "champ": 'The Championship Club', "sandbox": 'My Golf Club' }

func _init(game) -> void:
	g = game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buildTitle()
	for m in ['menu', 'slots', 'settings', 'event', 'end', 'cup', 'away']: _overlay(m)

func layout() -> void:
	var vs: Vector2 = get_parent().size
	size = vs
	title.size = vs
	for m in modals.values(): m.size = vs
	if scenScroll and is_instance_valid(scenScroll): _fitNew.call_deferred()
var scenScroll: ScrollContainer
## the scenario list takes whatever height is left so the new-game pane fits on screen
func _fitNew() -> void:
	if not scenScroll or not is_instance_valid(scenScroll) or not titleNew.visible: return
	var col: Control = titleNew.get_parent()
	var vs: Vector2 = get_parent().size
	var others: float = col.get_combined_minimum_size().y - scenScroll.custom_minimum_size.y
	col.position.y = 40 if vs.y < 820 else 64
	scenScroll.custom_minimum_size.y = clampf(vs.y - col.position.y - 48 - others, 120, 420)

## anything open that should stop the park taking input
func blocking() -> bool:
	for k in ['menu', 'slots', 'settings']:
		if modals[k].visible: return true
	return false
func _busy() -> void:
	var b := false
	for m in modals.values():
		if m.visible: b = true
	Sim.uiBusy = b or title.visible
func settingsOpen() -> bool: return modals.settings.visible
func menuOpen() -> bool: return modals.menu.visible

# ---------- a dimmed overlay with a centred card ----------
func _overlay(name: String) -> void:
	var o := Control.new()
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.visible = false
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new(); dim.color = Color(10 / 255.0, 30 / 255.0, 18 / 255.0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(cc)
	var card = K.panel(K.box(K.CARD, 20, Color(0, 0, 0, 0), 0, 18), 22)
	var v = K.vbox(12)
	card.add_child(v)
	cc.add_child(card)
	o.set_meta("card", card); o.set_meta("body", v)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if name == 'menu': closeMenu()
			elif name == 'slots': _hide('slots'); Sim.sfx('close')
			elif name == 'settings': closeSettings())
	add_child(o)
	modals[name] = o
func _body(name: String) -> VBoxContainer: return modals[name].get_meta("body")
func _show(name: String, width := 340.0) -> VBoxContainer:
	var o: Control = modals[name]
	var card: PanelContainer = o.get_meta("card")
	card.custom_minimum_size.x = width
	o.visible = true
	move_child(o, get_child_count() - 1)
	_busy()
	return _body(name)
func _hide(name: String) -> void: modals[name].visible = false; _busy()
func _h2(t: String, center := true) -> Label:
	var l = K.lbl(t, 24, 800, K.INK, true)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
func _p(t: String, center := true) -> Label:
	var l = K.lbl(t, 14, 500, K.MUTED, true)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
func _eye(t: String) -> Label:
	var l = K.eyebrow(t); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; return l
func _bigIcon(t: String, size := 72, lose := false) -> Control:
	var p = K.panel(K.box(Color("#f3e3e0") if lose else Color("#f6efd9"), size / 2, K.FLAG if lose else K.GOLD, 4), 0)
	p.custom_minimum_size = Vector2(size, size)
	var l = K.lbl(t, size * 0.5, 800, K.INK); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return p

# =====================================================================================
# Title screen
# =====================================================================================
func _buildTitle() -> void:
	title = Control.new()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.visible = false
	var shade := ColorRect.new(); shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(8 / 255.0, 26 / 255.0, 15 / 255.0, 0.62)
	title.add_child(shade)
	var col = K.vbox(18)
	col.position = Vector2(64, 64)
	col.custom_minimum_size.x = 420
	title.add_child(col)
	var logo = K.vbox(4)
	logo.add_child(K.icon(Icons.MISC.flag, 46, K.GOLD))
	var fw = K.lbl('F A I R W A Y', 15, 800, Color(1, 1, 1, 0.8))
	logo.add_child(fw)
	var ty = K.lbl('Tycoon', 64, 800, K.GOLD)
	ty.label_settings.shadow_color = Color(0, 0, 0, 0.35); ty.label_settings.shadow_offset = Vector2(0, 4); ty.label_settings.shadow_size = 0
	logo.add_child(ty)
	col.add_child(logo)
	titleTag = K.lbl('Build a golf club from a patch of grass to a five-star championship venue.', 15, 500, Color(1, 1, 1, 0.75), true)
	titleTag.custom_minimum_size.x = 340
	col.add_child(titleTag)
	titleMain = K.vbox(8); col.add_child(titleMain)
	titleNew = K.vbox(12); col.add_child(titleNew)
	titleLoad = K.vbox(12); col.add_child(titleLoad)
	var ver = K.lbl("Early access · v%s" % Sim.GAME_VERSION, 11, 700, Color(1, 1, 1, 0.45))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT); ver.position = Vector2(64, 0)
	ver.name = 'Ver'
	title.add_child(ver)
	add_child(title)
func _tm(text: String, sub: String, primary: bool, cb: Callable) -> Button:
	var b = K.btn('', 'tmPrimary' if primary else 'tm', cb)
	b.custom_minimum_size = Vector2(420, 58 if sub != '' else 46)
	var v = K.vbox(0); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT); v.offset_left = 18; v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(K.lbl(text, 16, 800, K.INK if primary else Color.WHITE))
	if sub != '': v.add_child(K.lbl(sub, 12, 600, Color(18 / 255.0, 38 / 255.0, 26 / 255.0, 0.7) if primary else Color(1, 1, 1, 0.65)))
	b.add_child(v)
	return b
func openTitle(pane := 'main') -> void:
	for m in ['menu', 'slots', 'event']: _hide(m)
	title.visible = true
	move_child(title, 0)
	(title.get_node('Ver') as Control).position = Vector2(64, size.y - 30)
	titlePane(pane)
	_busy()
func closeTitle() -> void:
	title.visible = false; _busy()
func titlePane(p: String) -> void:
	titleMain.visible = p == 'main'; titleNew.visible = p == 'new'; titleLoad.visible = p == 'load'; titleTag.visible = p == 'main'
	if p == 'main':
		K.clear(titleMain)
		if Sim.gameLive:
			titleMain.add_child(_tm('Continue', "%s · %s · %s" % [Sim.clubName(), Sim.dateLabel(Sim.S.day, true), Sim.fmt(Sim.S.money)], true, func(): g.closeTitle(); Sim.sfx('open')))
		titleMain.add_child(_tm('New game', 'Choose a scenario and name your club', not Sim.gameLive, func(): titlePane('new'); Sim.sfx('open')))
		var any := false
		for s in Sim.SLOTS:
			if Sim.readSlot(s): any = true
		var lb := _tm('Load game', 'Pick a saved club' if any else 'No saved games yet', false, func(): titlePane('load'); Sim.sfx('open'))
		lb.disabled = not any
		titleMain.add_child(lb)
		titleMain.add_child(_tm('Settings', 'Sound, interface size, controls', false, func(): openSettings()))
		titleMain.add_child(_tm('Quit to desktop', '', false, func(): Sim.save(); get_tree().quit()))
	elif p == 'new':
		K.clear(titleNew)
		titleNew.add_child(K.lbl('New game', 26, 800, Color.WHITE))
		titleNew.add_child(K.eyebrow('Club name', Color(1, 1, 1, 0.7), 12))
		nameIn = LineEdit.new(); nameIn.max_length = 32
		nameIn.text = SCEN_NAME.get(g.scenPick, 'Pine Hollow Golf Club')
		nameIn.text_submitted.connect(func(_t): g.startNewGame(nameIn.text))
		var ns = K.box(Color(1, 1, 1, 0.08), 12, Color(1, 1, 1, 0.2), 1); ns.set_content_margin_all(12)
		nameIn.add_theme_stylebox_override("normal", ns)
		var nf = ns.duplicate(); nf.border_color = K.GOLD; nameIn.add_theme_stylebox_override("focus", nf)
		nameIn.add_theme_color_override("font_color", Color.WHITE)
		nameIn.add_theme_font_override("font", K.font(700)); nameIn.add_theme_font_size_override("font_size", 16)
		titleNew.add_child(nameIn)
		var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(420, 330); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scenScroll = sc
		scenList = K.vbox(8); scenList.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(scenList)
		titleNew.add_child(sc)
		diffBox = K.hbox(10)
		titleNew.add_child(diffBox)
		diffBlurb = K.lbl('', 12, 500, Color(1, 1, 1, 0.7), true); diffBlurb.custom_minimum_size.x = 420
		titleNew.add_child(diffBlurb)
		scenDetail = K.vbox(4)
		titleNew.add_child(scenDetail)
		var btns = K.hbox(8)
		btns.add_child(K.expand(_tm('Back', '', false, func(): titlePane('main'); Sim.sfx('close'))))
		btns.add_child(K.expand(_tm('Start', '', true, func(): g.startNewGame(nameIn.text))))
		for b in btns.get_children(): b.custom_minimum_size.x = 0
		titleNew.add_child(btns)
		renderNewGame()
		_fitNew.call_deferred()
	elif p == 'load':
		K.clear(titleLoad)
		titleLoad.add_child(K.lbl('Load game', 26, 800, Color.WHITE))
		var l = K.vbox(8)
		titleLoad.add_child(l)
		renderSlots(l, 'load', true)
		titleLoad.add_child(_tm('Back', '', false, func(): titlePane('main'); Sim.sfx('close')))
func renderNewGame() -> void:
	_fitNew.call_deferred()
	var idx := -1
	for i in Sim.CAMPAIGN.size():
		if Sim.CAMPAIGN[i].id == g.scenPick: idx = i
	if g.scenPick != 'sandbox' and (idx < 0 or not Sim.unlocked(idx)): g.scenPick = 'fresh'
	K.clear(scenList)
	var camp: Dictionary = Sim.campaignOf()
	var card := func(s, i, locked: bool):
		var r: Dictionary = camp.get(s.id, {})
		var b = K.btn('', 'tm')
		var sel: bool = s.id == g.scenPick
		var v = K.vbox(2); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_TOP_WIDE); v.offset_left = 14; v.offset_top = 10; v.offset_right = -14
		var h = K.hbox(8)
		h.add_child(K.lbl('∞' if i == null else str(i + 1), 13, 800, K.GOLD))
		h.add_child(K.expand(K.lbl(s.name, 15, 800, Color.WHITE)))
		var med: int = r.get("medal", 0)
		h.add_child(K.lbl('🔒' if locked else (("%s %s" % [Sim.MEDAL_IC[med], Sim.MEDAL[med]]) if med else s.tag), 12, 700, Color(1, 1, 1, 0.7)))
		v.add_child(h)
		var hgt := 44.0
		if sel and not locked:
			var bl = K.lbl(s.blurb, 12, 500, Color(1, 1, 1, 0.75), true); bl.custom_minimum_size.x = 380
			v.add_child(bl); hgt = 96
		elif locked:
			v.add_child(K.lbl("Earn a medal on %s to unlock" % Sim.CAMPAIGN[i - 1].name, 12, 600, Color(1, 1, 1, 0.5))); hgt = 62
		b.add_child(v)
		b.custom_minimum_size = Vector2(400, hgt)
		if sel: K.styleBtn(b, 'tm'); b.add_theme_stylebox_override("normal", K.box(Color(1, 1, 1, 0.16), 14, K.GOLD, 2))
		b.modulate.a = 0.55 if locked else 1.0
		b.pressed.connect(func():
			if locked: Sim.sfx('soft'); return
			if g.scenPick != s.id: g.scenPick = s.id; nameIn.text = SCEN_NAME.get(s.id, nameIn.text)
			Sim.sfx('tap'); renderNewGame())
		scenList.add_child(b)
	for i in Sim.CAMPAIGN.size(): card.call(Sim.CAMPAIGN[i], i, not Sim.unlocked(i))
	card.call(Sim.SANDBOX, null, false)
	K.clear(diffBox)
	diffBox.add_child(K.lbl('DIFFICULTY', 12, 800, Color(1, 1, 1, 0.7)))
	var opts := []
	for k in Sim.DIFF: opts.append([k, Sim.DIFF[k].label])
	diffBox.add_child(K.seg(opts, g.diffPick, func(k): g.diffPick = k; Sim.sfx('tap'); renderNewGame()))
	diffBlurb.text = 'Difficulty does not apply to the sandbox.' if g.scenPick == 'sandbox' else Sim.DIFF[g.diffPick].blurb
	K.clear(scenDetail)
	var s = Sim.scenOf(g.scenPick)
	if s and s.id != 'sandbox':
		var r: Dictionary = camp.get(s.id, {})
		scenDetail.add_child(K.lbl("Deadline: end of Year %d%s" % [s.years, ("   ·   Best: %s %s · %s pts" % [Sim.MEDAL_IC[r.medal], Sim.MEDAL[r.medal], Sim.fmtInt(r.get("score", 0))]) if r.get("medal") else ''], 12, 800, K.GOLD))
		for t in s.medals.size():
			var parts := []
			for c in s.medals[t]: parts.append(c.t)
			scenDetail.add_child(K.lbl("%s  %s" % [Sim.MEDAL_IC[t + 1], ' · '.join(parts)], 12, 600, Color(1, 1, 1, 0.8), true))
	elif s:
		scenDetail.add_child(K.lbl('No objectives, no deadline and no board. Only the bank can end the game.', 12, 600, Color(1, 1, 1, 0.75), true))

# =====================================================================================
# Save slots
# =====================================================================================
func renderSlots(el: VBoxContainer, mode: String, dark := false) -> void:
	K.clear(el)
	for s in Sim.SLOTS:
		if mode == 'save' and s == 'auto': continue
		var d = Sim.readSlot(s)
		var label := 'Autosave' if s == 'auto' else "Slot %s" % s
		var p = K.panel(K.box(Color(1, 1, 1, 0.06) if dark else Color.WHITE, 14, Color(1, 1, 1, 0.12) if dark else K.LINE, 1), 11)
		var h = K.hbox(10)
		var v = K.vbox(2)
		var tc = Color.WHITE if dark else K.INK
		var mc = Color(1, 1, 1, 0.65) if dark else K.MUTED
		if d == null:
			v.add_child(K.lbl("%s · empty" % label, 14, 700, mc))
			v.add_child(K.lbl('Save your club here' if mode == 'save' else 'Nothing saved', 12, 600, mc))
		else:
			v.add_child(K.lbl("%s · %s" % [label, d.get("parkName", 'Pine Hollow Golf Club')], 14, 800, tc))
			v.add_child(K.rich("[color=#f2c14e]%s[/color] · %s · %s" % [Sim.starText(int(d.get("starsSaved", 1))), Sim.dateLabel(int(d.get("day", 1)), true), Sim.fmt(d.money)], 12, mc))
			if d.get("lastSave"): v.add_child(K.lbl(Time.get_datetime_string_from_unix_time(int(d.lastSave + Time.get_time_zone_from_system().bias * 60), true), 11, 600, mc))
		h.add_child(K.expand(v))
		var slot: String = s
		if mode == 'save':
			h.add_child(K.btn('Overwrite' if d else 'Save', 'gold', func(): Sim.saveToSlot(slot); renderSlots(el, mode, dark)))
		elif d:
			h.add_child(K.btn('Load', 'gold', func(): _load(slot)))
		if d:
			var del = K.btn('✕', 'ghost')
			del.pressed.connect(func():
				if slotArm != slot:
					slotArm = slot; del.text = 'Delete?'; K.styleBtn(del, 'mmDanger')
					get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(del) and slotArm == slot: slotArm = null; renderSlots(el, mode, dark))
					return
				slotArm = null; Sim.deleteSlot(slot); Sim.sfx('soft')
				if Sim.atTitle: titlePane('load')
				else: renderSlots(el, mode, dark))
			h.add_child(del)
		p.add_child(h)
		el.add_child(p)
func _load(s: String) -> void:
	if not Sim.loadSlot(s): return
	_hide('slots'); _hide('menu')
	if Sim.atTitle: g.closeTitle()
	else: Sim.setSpeed(1)
func openSlots(mode: String) -> void:
	slotMode = mode
	var b := _show('slots', 460)
	K.clear(b)
	var h = K.hbox(8)
	h.add_child(K.expand(_h2('Save game' if mode == 'save' else 'Load game', false)))
	h.add_child(K.btn('×', 'closeDark', func(): _hide('slots'); Sim.sfx('close')))
	b.add_child(h)
	slotList = K.vbox(8)
	b.add_child(slotList)
	renderSlots(slotList, mode)
	Sim.sfx('open')

# =====================================================================================
# The pause menu
# =====================================================================================
func openMenu() -> void:
	if Sim.atTitle: return
	g.speedBeforeMenu = Sim.speedIdx if Sim.speedIdx else (Sim.lastSpeed if Sim.lastSpeed else 1)
	Sim.setSpeed(0)
	var b := _show('menu', 320)
	K.clear(b)
	b.add_child(_eye('Game paused'))
	b.add_child(_h2('Menu'))
	b.add_child(K.btn('Resume', 'mmPrimary', closeMenu))
	b.add_child(K.btn('Save game', 'mm', func(): openSlots('save')))
	b.add_child(K.btn('Load game', 'mm', func(): openSlots('load')))
	b.add_child(K.btn('Settings', 'mm', func(): openSettings()))
	b.add_child(K.btn('Exit to main menu', 'mm', func(): Sim.save(); _hide('menu'); g.openTitle('main')))
	b.add_child(K.btn('Quit to desktop', 'mmDanger', func(): Sim.save(); get_tree().quit()))
	for c in b.get_children():
		if c is Button: c.alignment = HORIZONTAL_ALIGNMENT_LEFT
	Sim.sfx('open')
func closeMenu() -> void:
	_hide('menu'); Sim.setSpeed(g.speedBeforeMenu); Sim.sfx('close')

# =====================================================================================
# Settings
# =====================================================================================
func openSettings() -> void:
	var b := _show('settings', 460)
	K.clear(b)
	var h = K.hbox(8)
	h.add_child(K.expand(_h2('Settings', false)))
	h.add_child(K.btn('×', 'closeDark', closeSettings))
	b.add_child(h)
	var S: Dictionary = Sim.SETTINGS
	var pct := func(v): return "%d%%" % roundi(v * 100)
	for row in [['Interface size', 'uiScale', 0.8, 1.6, 0.05, pct], ['Master volume', 'master', 0.0, 1.0, 0.05, pct], ['Music', 'music', 0.0, 1.0, 0.05, pct],
			['Ambience', 'ambience', 0.0, 1.0, 0.05, pct], ['Effects', 'sfx', 0.0, 1.0, 0.05, pct], ['Camera speed', 'camSpeed', 0.4, 2.5, 0.1, func(v): return "%.1f×" % v]]:
		var r = K.hbox(10)
		var l = K.lbl(row[0], 13, 700, K.INK); l.custom_minimum_size.x = 130
		var sl := HSlider.new(); sl.focus_mode = Control.FOCUS_NONE; sl.min_value = row[2]; sl.max_value = row[3]; sl.step = row[4]; sl.value = S.get(row[1], 1.0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var vl = K.lbl(row[5].call(sl.value), 13, 800, K.INK); vl.custom_minimum_size.x = 50; vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var key: String = row[1]
		var f: Callable = row[5]
		sl.value_changed.connect(func(v): S[key] = v; vl.text = f.call(v); g.audio.setVolumes())
		sl.drag_ended.connect(func(_c): Sim.saveSettings())
		r.add_child(l); r.add_child(sl); r.add_child(vl)
		b.add_child(r)
		if key == 'music':
			var tr = K.hbox(10)
			var tl = K.lbl('Soundtrack', 13, 700, K.INK); tl.custom_minimum_size.x = 130
			var ob := OptionButton.new(); ob.focus_mode = Control.FOCUS_NONE; ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ob.add_item('Follow the day'); ob.set_item_metadata(0, 'auto')
			var tracks: Array = g.audio.trackList()
			for i in tracks.size(): ob.add_item(tracks[i][1]); ob.set_item_metadata(i + 1, tracks[i][0])
			for i in ob.item_count:
				if ob.get_item_metadata(i) == S.get("track", 'auto'): ob.select(i)
			ob.item_selected.connect(func(i): S.track = ob.get_item_metadata(i); Sim.saveSettings())
			tr.add_child(tl); tr.add_child(ob)
			tr.add_child(K.btn('⏭', 'ghost', func(): g.audio.skipTrack()))
			b.add_child(tr)
	var ck := func(label: String, key: String):
		var c := CheckBox.new(); c.focus_mode = Control.FOCUS_NONE; c.text = label; c.button_pressed = S.get(key, false)
		c.add_theme_font_override("font", K.font(700)); c.add_theme_font_size_override("font_size", 13)
		c.toggled.connect(func(on): S[key] = on; Sim.saveSettings())
		b.add_child(c)
	ck.call('Scroll at screen edges', 'edgePan')
	ck.call('Fullscreen', 'fullscreen')
	var er = K.hbox(10)
	var el = K.lbl('Random events', 13, 700, K.INK); el.custom_minimum_size.x = 130
	er.add_child(el)
	er.add_child(K.seg([['off', 'Off'], ['rare', 'Rare'], ['normal', 'Normal'], ['often', 'Frequent']], S.get("events", 'normal'), func(k): S.events = k; Sim.saveSettings(); openSettings()))
	b.add_child(er)
	b.add_child(HSeparator.new())
	b.add_child(K.lbl('Controls', 15, 800, K.INK))
	var kg = K.grid(2, 8)
	for kv in [['Click', 'Inspect a golfer, staff member, hole or building'], ['WASD / arrows', 'Move the camera (hold Shift to go faster)'], ['Q / E, scroll', 'Zoom out and in'],
			['1 – 6', 'Build, Course, Staff, Golfers, Finances, Park'], ['Tab', 'Next tab inside a window'], ['Space', 'Pause or resume'], [', and .', 'Slower and faster'],
			['H', 'Recenter the camera'], ['N', 'Next tune'], ['M', 'Mute or unmute'], ['F', 'Fullscreen'], ['F5', 'Quick save'], ['Esc', 'Close a window, or open the menu'],
			['Controller', 'Left stick moves, right stick zooms, B backs out, X pauses, LB/RB switch windows, Start opens the menu']]:
		var kk = K.panel(K.box(Color("#efeadb"), 6), 0)
		var ks: StyleBoxFlat = kk.get_theme_stylebox("panel"); ks.content_margin_left = 6; ks.content_margin_right = 6; ks.content_margin_top = 2; ks.content_margin_bottom = 2
		kk.add_child(K.lbl(kv[0], 11, 800, K.INK)); kk.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		kg.add_child(kk)
		var d = K.lbl(kv[1], 12, 500, K.MUTED, true); d.custom_minimum_size.x = 280
		kg.add_child(d)
	b.add_child(kg)
	var info = Sim.steamCall('info')
	b.add_child(K.lbl(("Steam: signed in%s. Saves sync with Steam Cloud." % ((' as ' + info.name) if info.get("name") else '')) if info else 'Steam is not running. Achievements unlock when you next play with Steam open.', 11, 600, K.MUTED, true))
	Sim.sfx('open')
func closeSettings() -> void:
	_hide('settings'); Sim.saveSettings(); g.applySettings(); Sim.sfx('close')

# =====================================================================================
# Event cards, the end screen, event results, away earnings
# =====================================================================================
func showEventCard(ev) -> void:
	var b := _show('event', 400)
	K.clear(b)
	b.add_child(_bigIcon(ev.get("icon", '★')))
	b.add_child(_eye(ev.kicker))
	b.add_child(_h2(ev.title))
	b.add_child(_p(ev.text))
	for i in ev.options.size():
		var o = ev.options[i]
		var btn = K.btn('', 'evoptPrimary' if i == 0 else 'evopt')
		var v = K.vbox(1); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_FULL_RECT); v.offset_left = 14; v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.offset_right = -14
		v.add_child(K.lbl(o.label, 15, 800, Color.WHITE if i == 0 else K.INK))
		var sub = K.lbl(o.sub, 12, 600, Color(1, 1, 1, 0.85) if i == 0 else K.MUTED, true)
		v.add_child(sub)
		btn.add_child(v)
		var subH: float = K.font(600).get_multiline_string_size(o.sub, HORIZONTAL_ALIGNMENT_LEFT, 328, 12).y
		btn.custom_minimum_size = Vector2(356, 40 + subH)
		var idx = i
		btn.pressed.connect(func(): _hide('event'); Sim.chooseEventOption(idx))
		b.add_child(btn)
func showEnd(kind: String) -> void:
	_hide('event')
	var E: Dictionary = Sim.endScreenData(kind)
	var b := _show('end', 420)
	K.clear(b)
	b.add_child(_bigIcon(E.ic, 96, E.lose))
	b.add_child(_eye(E.kicker))
	b.add_child(_h2(E.title))
	b.add_child(_p(E.text))
	var gr = K.grid(3, 6)
	for s in E.stats:
		var p = K.panel(K.box(Color("#f5f1e5"), 10), 7)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v = K.vbox(1)
		v.add_child(K.eyebrow(s[0])); v.add_child(K.lbl(s[1], 15, 800, K.INK))
		p.add_child(v); gr.add_child(p)
	b.add_child(gr)
	if E.next: b.add_child(K.btn("Next: %s" % E.next, 'buy', func():
		_hide('end'); g.scenPick = E.nextId; Sim.deleteSlot('auto'); Sim.gameLive = false; g.openTitle('new')))
	if not E.lose: b.add_child(K.btn('Keep playing', 'ghost', func():
		_hide('end'); Sim.setSpeed(1); Sim.toast('Free play', 'Keep building', 'The scenario is over and its medal is saved. Play on as long as you like.', '⛳')))
	else:
		b.add_child(K.btn('Try again', 'buy', func(): _hide('end'); Sim.startScenario(Sim.S.scenario, Sim.S.diff, Sim.clubName()); g.recenter()))
		b.add_child(K.btn('Load a save', 'ghost', func(): _hide('end'); Sim.deleteSlot('auto'); Sim.gameLive = false; g.openTitle('load')))
	b.add_child(K.btn('Main menu', 'ghost', func():
		_hide('end')
		if Sim.S.get("over"): Sim.deleteSlot('auto')
		Sim.gameLive = false; g.openTitle('main')))
func showCup(r: Dictionary) -> void:
	var b := _show('cup', 340)
	K.clear(b)
	b.add_child(_eye(r.eyebrow))
	b.add_child(_h2(r.winner))
	var big = K.lbl(r.won, 32, 800, K.TURF); big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(big)
	b.add_child(_p(r.msg))
	b.add_child(K.btn('Continue', 'buy', func(): _hide('cup')))
func showAway(amt: float, text: String) -> void:
	var b := _show('away', 340)
	K.clear(b)
	b.add_child(_eye('While you were away'))
	b.add_child(_h2('Your staff kept the park open'))
	var big = K.lbl(Sim.fmt(amt), 32, 800, K.TURF); big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(big)
	b.add_child(_p(text))
	b.add_child(K.btn('Collect', 'buy', func(): Sim.earn(amt); Sim.sfx('kaching'); _hide('away'); Sim.save()))

## Esc: close the topmost dialog. Returns true if it did something.
func backOut() -> bool:
	if modals.settings.visible: closeSettings(); return true
	if modals.slots.visible: _hide('slots'); Sim.sfx('close'); return true
	if title.visible:
		if not titleMain.visible: titlePane('main'); Sim.sfx('close')
		return true
	if modals.menu.visible: closeMenu(); return true
	if modals.cup.visible: _hide('cup'); return true
	if modals.event.visible or modals.end.visible or modals.away.visible: return true
	return false
