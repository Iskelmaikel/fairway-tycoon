class_name SheetUI
extends PanelContainer
## The management windows: Build, Course, Staff, Golfers, Finances and Park, each with tabs.
## Each tab builds its controls once and registers small update functions that run four times
## a second; when what a tab shows changes shape (a range is added, the designer opens), it is rebuilt.

const K = preload("res://scripts/ui/kit.gd")
var g
var head: PanelContainer
var winIc: PanelContainer
var titleL: Label
var subL: Label
var tabsBar: PanelContainer
var tabsBox: HBoxContainer
var scroll: ScrollContainer
var body: VBoxContainer
var _upd: Array = []      # update callables for the current tab
var _key := ''            # what the current tab was built for
var _tabKey := ''

const LIST_CATS := {
	"range": [['Size', ['bayL', 'bay', 'dmach']], ['Staff', ['attend', 'picker']], ['Facilities', ['covered', 'lights', 'targets']], ['Balls and equipment', ['order', 'balls', 'disp', 'cart', 'basket']]],
	"club": [['Rooms and venues', ['barRoom', 'resto', 'terrace', 'locker', 'reno']], ['Business', ['shop', 'market', 'food']]],
	"staff": [['Academy', ['coach']], ['Course', ['keeper', 'marshal', 'starter']], ['Clubhouse', ['assist', 'bar', 'chef']]],
}
const D_TOOLS := [
	['hole', 'Move hole', 'Drag the tee (T), bend (•) and green (G) of the selected hole. Par follows the length.'],
	['place', 'Place hole', 'Tap where the tee goes, then tap where the green goes. You can fine-tune it afterwards with Move hole.'],
	['adjust', 'Select', 'Tap a bunker, dunes, trees or flowers to select it. Drag it to move it and turn it with the rotate buttons (or R).'],
	['bunker', 'Bunker', 'Tap to place a bunker. Greenside and fairway bunkers raise a hole’s rating.'],
	['waste', 'Sand dunes', 'Tap to lay sandy dunes with beach grass along a hole.'],
	['trees', 'Trees', 'Tap to plant a cluster of trees. Tree-lined holes look and play better.'],
	['flowers', 'Flowers', 'Tap to plant a flowerbed near a tee or green.'],
	['remove', 'Remove', 'Tap a bunker, dunes, trees or flowers to remove it.'],
	['land', 'Buy land', 'Tap a parcel to see its price, then buy it to build there.'],
]
const PART_LABEL := { "length": 'Length', "bunkers": 'Bunkers', "water": 'Water', "dunes": 'Dunes', "trees": 'Trees & flowers', "shape": 'Dogleg', "elev": 'Elevation' }

func _init(game) -> void:
	g = game
	visible = false
	var sb = K.box(K.PAPER, 18, Color(0, 0, 0, 0.08), 1, 16)
	sb.set_content_margin_all(0)
	add_theme_stylebox_override("panel", sb)
	clip_contents = true
	var v = K.vbox(0)
	add_child(v)
	head = K.panel(K.grad(Color("#365f28"), Color("#2a3a20"), 0), 0)
	var hs: StyleBoxTexture = head.get_theme_stylebox("panel")
	hs.content_margin_left = 12; hs.content_margin_right = 10; hs.content_margin_top = 10; hs.content_margin_bottom = 10
	var hb = K.hbox(10)
	winIc = K.panel(K.box(K.GOLD, 11)); winIc.custom_minimum_size = Vector2(38, 38)
	hb.add_child(winIc)
	var tt = K.vbox(0)
	titleL = K.lbl('', 19, 800, Color.WHITE)
	subL = K.lbl('', 12, 700, Color(1, 1, 1, 0.72)); subL.clip_text = true; subL.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tt.add_child(titleL); tt.add_child(subL)
	hb.add_child(K.expand(tt))
	hb.add_child(K.btn('×', 'close', func(): g.closePanel(); Sim.sfx('close')))
	head.add_child(hb)
	v.add_child(head)
	var gold := ColorRect.new(); gold.color = K.GOLD; gold.custom_minimum_size.y = 3
	v.add_child(gold)
	tabsBar = K.panel(K.box(K.PAPER2, 0), 0)
	var ts: StyleBoxFlat = tabsBar.get_theme_stylebox("panel"); ts.content_margin_left = 10; ts.content_margin_right = 10; ts.content_margin_top = 8; ts.content_margin_bottom = 8
	tabsBox = K.hbox(4)
	tabsBar.add_child(tabsBox)
	v.add_child(tabsBar)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	body = K.vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(K.margin(body, 10, 8, 12, 14))
	scroll.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL

func layout() -> void:
	var vs: Vector2 = get_parent().size
	var top: float = g.hud.topCol.position.y + g.hud.bar.size.y + 16 if g.hud else 80.0
	position = Vector2(vs.x - 440 - 12, top)
	size = Vector2(440, vs.y - top - 12)

func open(w: String, k: String) -> void:
	visible = true
	titleL.text = g.WINDOWS[w].title
	K.clear(winIc)
	var ic = K.icon(Icons.TAB[w], 22, K.INK); ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	winIc.add_child(ic)
	K.clear(tabsBox)
	var tabs: Array = g.WINDOWS[w].tabs
	tabsBar.visible = tabs.size() > 1
	for t in tabs:
		var b = K.btn(t[1], 'wintab')
		b.toggle_mode = true
		b.button_pressed = t[0] == k
		var key: String = t[0]
		b.pressed.connect(func(): g.openPanel(key); Sim.sfx('tap'))
		tabsBox.add_child(b)
	_key = ''
	_tabKey = k
	layout()
	scroll.scroll_vertical = 0
	refresh()
func close() -> void:
	visible = false
	K.clear(body); _upd.clear(); _key = ''

## rebuild when the shape changed, then run every updater
func refresh() -> void:
	if not visible: return
	var t: String = g.tab
	var key := _tabKey + '|' + _structKey(t)
	if key != _key:
		_key = key
		var sv := scroll.scroll_vertical
		K.clear(body); _upd.clear()
		_build(t)
		scroll.scroll_vertical = sv
	for u in _upd: u.call()
	K.setText(subL, _sub(t))
func _structKey(t: String) -> String:
	match t:
		'range': return "%s|%d|%s" % [Sim.selRangeId, Sim.rangeObjs().size(), Sim.S.get("fac", {}).keys()]
		'club': return "%s|%s|%d" % [Sim.hasObj('club'), Sim.S.get("fac", {}).keys(), Sim.facList().size()]
		'course': return "%s|%s|%s|%s|%s" % [Sim.designing, Sim.dTool, Sim.selFeat != null, Sim.teeSets(), Sim.dPlaceTee != null]
		'place': return "%d" % Sim.objs().size()
		'hours': return "%d|%s" % [Sim.facList().size(), str(Sim.S.get("fac", {}))]
		'tee': return _teeSig()
		'people': return _peopleSig()
		'crew': return _crewSig()
		'park': return "%s|%s|%s" % [g.parkSub, Sim.S.get("event") != null, Sim.S.get("evLog", []).size()]
	return ''

func _build(t: String) -> void:
	match t:
		'place': _buildPlace()
		'range', 'club', 'staff': _buildUpgrades(t)
		'supplies': _buildSupplies()
		'course': _buildCourse()
		'crew': _buildCrew()
		'people': _buildPeople()
		'tee': _buildTee()
		'hcp': _buildHcp()
		'fin': _buildFin()
		'hours': _buildHours()
		'park':
			match g.parkSub:
				'guests': _buildGuests()
				'goals': _buildGoals()
				'events': _buildEvents()
				'rival': _buildRival()
				'awards': _buildAwards()

func _sub(t: String) -> String:
	var S: Dictionary = Sim.S
	match t:
		'place': return "%d plots of land · %d things built" % [S.world.land.size() if S.get("world") else 0, Sim.objs().size()]
		'hcp':
			var h: Array = Sim.visitors.filter(func(v): return v.get("hcp") != null and v.state != 'gone')
			if h.is_empty(): return 'Nobody here right now'
			var sum := 0.0
			for v in h: sum += v.hcp
			return "%d golfers here · average handicap %.1f" % [h.size(), sum / h.size()]
		'supplies': return "Shop %d · food %d · seed %d" % [int(S.sup.shop), int(S.sup.food), int(S.sup.fert)]
		'range':
			var o = Sim.selRange()
			if not o: return 'Place a driving range on the Build tab first'
			return Sim.withRange(o, func(): return "%s%d of %d bays staffed · %s a bucket" % [(Sim.rangeName(o) + ' · ') if Sim.rangeObjs().size() > 1 else '', Sim.staffedBays(), Sim.bays(), fmtPrice(Sim.PRICE_ITEMS[0], Sim.bucketPrice())])
		'course':
			var cs = Sim.csCache.get("yellow") if Sim.csCache != null else null
			return "%s · %s for 9%s" % [("CR %.1f · slope %d" % [cs.cr, cs.slope]) if cs else 'No holes yet', Sim.fmt(Sim.fee9()), (" · %s for 18" % Sim.fmt(Sim.fee18())) if Sim.L('back9') else '']
		'club': return "Menu prices %d%%" % roundi(S.prices.menu * 100)
		'staff', 'crew': return "%d employed · wages %s a day" % [Sim.staffCount(), Sim.fmt(Sim.wagesPerDay())] if t == 'staff' else "%d employed · click anyone to find them" % Sim.staffCount()
		'tee': return "%d of %d tee time%s in use · %d waiting" % [Sim.groups.size(), Sim.slots(), '' if Sim.slots() == 1 else 's', Sim.teeQueue.size()]
		'fin': return "%s · %s" % [Sim.dateLabel(), Sim.season().capitalize()]
		'hours':
			var l := Sim.facList()
			var c := l.filter(func(x): return not Sim.facOpen(x.key)).size()
			return ("%d open · %d closed right now · %s" % [l.size() - c, c, Sim.clock(S.clock)]) if l.size() else 'Nothing to open or close yet'
		'people': return "%d golfers in the park · click anyone to find them" % Sim.here().size()
		'park':
			if g.parkSub == 'guests': return "%d golfers in the park" % Sim.visitors.filter(func(v): return v.state != 'gone').size()
			return "%s · %s%s" % [Sim.clubName(), Sim.starText(Sim.starsC), (" · %d troph%s" % [S.trophies, 'y' if S.trophies == 1 else 'ies']) if S.get("trophies", 0) else '']
	return ''

# =====================================================================================
# Shared pieces
# =====================================================================================
func subhead(t: String) -> Label:
	var l = K.eyebrow(t, K.MUTED, 10)
	return l
func add(c: Control) -> Control: body.add_child(c); return c
func hint(t: String) -> Label: return K.lbl(t, 12, 600, K.MUTED, true)
static func fmtPrice(it, v: float) -> String:
	if it.get("pct"): return "%d%%" % roundi(v * 100)
	if v < 10 and fmod(v, 1.0) != 0: return ("$%.2f" % v).trim_suffix('0')
	return Sim.fmt(v)
func level(u) -> int: return Sim.level(u)
func canBuy(u) -> bool:
	var L := func(k): return Sim.L(k)
	if u.id == 'order': return Sim.curR != null and Sim.S.money >= Sim.cost(u) and Sim.S.stock + 500 <= Sim.ballCap()
	if u.id == 'cart' and Sim.L('cart') >= Sim.N('picker'): return false
	if Sim.RANGE_UP.has(u.id) or Sim.RANGE_STAFF.has(u.id):
		if Sim.curR == null: return false
	if u.get("tab") == 'club' and u.id != 'market' and not Sim.hasObj('club'): return false
	if u.id == 'food' and not Sim.hasObj('hut'): return false
	if u.id == 'coach' and not Sim.hasObj('academy'): return false
	if (u.id == 'bay' or u.id == 'bayL') and (Sim.bays() >= Sim.MAX_BAYS or not Sim.rangeFits({ u.id: Sim.L(u.id) + 1 })): return false
	if u.id == 'dmach' and not Sim.rangeFits({ "dmach": Sim.L('dmach') + 1 }): return false
	return level(u) < u.max and Sim.S.money >= Sim.cost(u) and not (u.id == 'bar' and not Sim.L('barRoom')) and not (u.id == 'chef' and not Sim.L('resto')) and not (u.id == 'terrace' and not Sim.L('barRoom'))
func buyOrFire(u, buy: bool) -> void:
	if buy:
		if not canBuy(u): return
		var c := Sim.cost(u)
		Sim.spend(c, 'supplies' if u.id == 'order' else 'build')
		if u.id != 'order': Sim.S.invested = Sim.S.get("invested", 0.0) + c
		if u.id == 'order': Sim.S.owned += 500; Sim.S.stock += 500
		elif Sim.RANGE_UP.has(u.id): Sim.curR.r.lvl[u.id] = int(Sim.curR.r.lvl.get(u.id, 0)) + 1
		elif Sim.RANGE_STAFF.has(u.id): Sim.curR.r.staff[u.id] = int(Sim.curR.r.staff.get(u.id, 0)) + 1
		elif u.get("tab"): Sim.S.lvl[u.id] = int(Sim.S.lvl.get(u.id, 0)) + 1
		else: Sim.S.staff[u.id] = int(Sim.S.staff.get(u.id, 0)) + 1
		if u.id == 'bay' or u.id == 'bayL' or u.id == 'dmach':
			var o = Sim.curR
			Sim.leaveRange(); Sim.rebuildWorld(); Sim.layout(); Sim.enterRange(o)
		Sim.sfx('chime')
	else:
		Sim.sfx('soft')
		if Sim.RANGE_STAFF.has(u.id):
			if Sim.curR and int(Sim.curR.r.staff.get(u.id, 0)) > 0: Sim.curR.r.staff[u.id] -= 1
		elif int(Sim.S.staff.get(u.id, 0)) > 0: Sim.S.staff[u.id] -= 1
## anything affordable in a window, for the toolbar's red dot
func anythingToBuy(w: String) -> bool:
	match w:
		'build':
			if not Sim.hasObj('range') and Sim.S.money >= Sim.OBJ.range.cost: return true
			for u in Sim.UP:
				if u.get("tab") == 'club' and canBuy(u): return true
			var any := [false]
			Sim.forRanges(func(_o):
				if any[0]: return
				for u in Sim.UP:
					if u.get("tab") == 'range' and u.id != 'order' and canBuy(u): any[0] = true; return)
			return any[0]
		'course':
			for u in Sim.UP:
				if u.get("tab") == 'course' and canBuy(u): return true
		'staff':
			for u in Sim.STAFF:
				if not u.get("range") and canBuy(u): return true
	return false

## an item card: icon, name, level, description, wage, buy and fire buttons
func upgradeRow(u, inRange) -> Control:
	var staff: bool = not u.get("tab") or u.get("range", false)
	var row = K.card(10)
	var h = K.hbox(12)
	row.add_child(h)
	var ic = K.badge(Icons.ITEM.get(u.id, Icons.ITEM._), 46, Color("#fdf0d3") if staff else Color("#e5f1e8"), Color("#8a5a10") if staff else K.TURF)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var info = K.vbox(3)
	info.add_child(K.lbl(u.name, 14, 800, K.INK))
	var lv = K.hbox(6)
	var lvT = K.lbl('', 11, 800, K.MUTED)
	var pips = K.Pips.new()
	lv.add_child(lvT); lv.add_child(pips)
	info.add_child(lv)
	var d = K.lbl('', 12, 500, K.MUTED, true)
	info.add_child(d)
	if staff: info.add_child(K.lbl("Wage %s a day each" % Sim.fmt(u.sal * Sim.DAY_LEN), 11, 700, Color("#a0522d")))
	h.add_child(K.expand(info))
	var btns = K.vbox(6)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var buy = K.btn('', 'buy')
	var fire = K.btn('Let one go', 'fire') if staff else null
	var act := func(isBuy: bool):
		if inRange: Sim.withRange(inRange, func(): buyOrFire(u, isBuy))
		else: buyOrFire(u, isBuy)
		Sim.save(); refresh(); g.hud.refresh()
	buy.pressed.connect(func(): act.call(true))
	btns.add_child(buy)
	if fire: fire.pressed.connect(func(): act.call(false)); btns.add_child(fire)
	h.add_child(btns)
	_upd.append(func():
		var f := func():
			var l := level(u)
			var mx: bool = l >= u.max
			var pipN: int = min(u.max, 10) if u.max != INF else 0
			if u.id == 'order': lvT.text = "%s balls owned" % Sim.fmtInt(floor(Sim.S.owned)); pips.visible = false
			elif staff: lvT.text = "%d employed%s" % [l, ' here' if (u.get("range") and Sim.rangeObjs().size() > 1) else '']; pips.visible = false
			elif u.max == 1: lvT.text = 'Built' if l else 'Not built'; pips.visible = false
			else: lvT.text = "Level %d of %d" % [l, u.max]; pips.visible = true; pips.setp(pipN, roundi(float(l) / u.max * pipN))
			K.setText(d, u.desc.call())
			var t := ''
			if u.id == 'order' and Sim.S.stock + 500 > Sim.ballCap(): t = 'No room'
			elif u.id == 'cart' and not mx and Sim.L('cart') >= Sim.N('picker'): t = 'Hire a picker'
			elif (u.id == 'bay' or u.id == 'bayL') and Sim.bays() >= Sim.MAX_BAYS: t = 'Maxed'
			elif mx: t = 'Built' if u.max == 1 else 'Maxed'
			else: t = ('' if u.get("tab") else 'Hire ') + Sim.fmt(Sim.cost(u))
			K.setText(buy, t)
			buy.disabled = not canBuy(u)
			if fire: fire.visible = l > 0
			var sb: StyleBoxFlat = row.get_theme_stylebox("panel")
			sb.bg_color = Color("#f3f6f1") if mx else Color.WHITE
		if inRange: Sim.withRange(inRange, f)
		else: f.call())
	return row

# =====================================================================================
# Build: the place cards and tools
# =====================================================================================
func _toolBtn(key: String, label: String, sub: String, svg: String, cb: Callable) -> Button:
	var b = K.btn('', 'plain')
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(98, 74)
	var v = K.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic = K.icon(svg, 22, K.TURF); ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l = K.lbl(label, 12, 800, K.INK); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var s = K.lbl(sub, 10, 600, K.MUTED); s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.name = 'sub'
	v.add_child(s)
	b.add_child(v)
	b.pressed.connect(cb)
	_upd.append(func(): b.set_pressed_no_signal(g.tool != null and g.tool.kind == key))
	return b
func _buildPlace() -> void:
	add(subhead('Paths and land'))
	var tr = K.flow(6)
	add(tr)
	var toggle := func(k: String):
		g.setTool(null if (g.tool != null and g.tool.kind == k) else { "kind": k }); Sim.sfx('select'); refresh()
	tr.add_child(_toolBtn('path', 'Footpath', "%s a tile" % Sim.fmt(Sim.PATH_COST), Icons.TOOL.path, func(): toggle.call('path')))
	tr.add_child(_toolBtn('unpath', 'Remove path', '50% back', Icons.TOOL.unpath, func(): toggle.call('unpath')))
	tr.add_child(_toolBtn('autopath', 'Auto path', 'suggests a route', Icons.TOOL.autopath, func(): Sim.sfx('select'); g.offerNextPath(false)))
	tr.add_child(_toolBtn('move', 'Move', 'free', Icons.TOOL.move, func(): toggle.call('move')))
	tr.add_child(_toolBtn('erase', 'Demolish', '40% back', Icons.TOOL.erase, func(): toggle.call('erase')))
	var land := _toolBtn('land', 'Buy land', '', Icons.TOOL.land, func(): toggle.call('land'))
	tr.add_child(land)
	_upd.append(func(): land.find_child('sub', true, false).text = Sim.fmt(Sim.parcelPrice()))
	add(subhead('Landscaping'))
	var lr = K.flow(6)
	add(lr)
	for k in Sim.TERRA:
		var d = Sim.TERRA[k]
		var key: String = k
		lr.add_child(_toolBtn(k, d.short, ("%s a tile" % Sim.fmt(d.cost)) if (k == 'water' or k == 'drain') else ("%s per m" % Sim.fmt(d.cost * 2)), Icons.TERRA[k], func(): toggle.call(key)))
	for cat in ['Facilities', 'Amenities', 'Decoration']:
		add(subhead(cat))
		for k in Sim.OBJ:
			var D = Sim.OBJ[k]
			if D.cat != cat: continue
			add(_placeRow(k, D))
func _placeRow(k: String, D) -> Control:
	var row = K.card(10)
	var h = K.hbox(12)
	row.add_child(h)
	var ic = K.badge(Icons.ITEM.get(D.icon, Icons.ITEM._), 46)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var info = K.vbox(3)
	info.add_child(K.lbl(D.label, 14, 800, K.INK))
	info.add_child(K.lbl(("8 × %d" % D.h if k == 'range' else "%d × %d" % [D.w, D.h]) + " tiles" + ((" · upkeep %s a day" % Sim.fmt(D.upkeep)) if D.get("upkeep") else ''), 11, 800, K.MUTED))
	info.add_child(K.lbl(D.desc, 12, 500, K.MUTED, true))
	var st = K.rich('', 12)
	info.add_child(st)
	h.add_child(K.expand(info))
	var b = K.btn('', 'buy', func():
		var have = Sim.objOf(k)
		g.setTool({ "kind": 'place', "type": k, "moveId": have.id if (D.get("unique") and have) else null }); Sim.sfx('select'))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	var conn = K.btn('Suggest path', 'ghost')
	conn.visible = false
	info.add_child(conn)
	conn.pressed.connect(func():
		var id = conn.get_meta("id", -1)
		for n in Sim.needsPath():
			if n.get("o") and n.o.id == id: g.offerPath(n); break
		Sim.sfx('select'))
	_upd.append(func():
		var have: Array = Sim.objs().filter(func(o): return o.type == k)
		var built: bool = D.get("unique", false) and have.size() > 0
		K.setText(b, 'Move' if built else Sim.fmt(D.cost))
		b.disabled = not built and Sim.S.money < D.cost
		var s := ''
		var first = null
		if have.size():
			var un := 0
			if not D.get("free"):
				for o in have:
					if not Sim.connected('OBJ:%s' % o.id):
						un += 1
						if first == null: first = o
			if D.get("unique"): s = K.neg('Built · not connected to a car park') if un else K.pos('Built and open')
			else: s = "%d built%s" % [have.size(), (" · " + K.neg("%d not connected" % un)) if un else '']
		if k == 'academy' and have.size() and not Sim.N('coach'): s += ' · ' + K.neg('hire a teaching pro')
		K.setRich(st, s)
		st.visible = s != ''
		conn.visible = first != null
		if first: conn.set_meta("id", first.id))
	return row
func _buildUpgrades(t: String) -> void:
	var inRange = null
	if t == 'range':
		var o = Sim.selRange()
		if not o: add(hint('You have no driving range yet. Place one on the Build tab.')); return
		inRange = o
		if Sim.rangeObjs().size() > 1:
			var opts := []
			for r in Sim.rangeObjs(): opts.append([r.id, Sim.rangeName(r)])
			add(K.seg(opts, o.id, func(id):
				Sim.selRangeId = id; Sim.sfx('tap'); refresh()
				var f = g._focusFor('range')
				if f != null: g.glideTo(f.x, f.y, f.z), true))
		for it in Sim.facList():
			if it.key == 'range:%s' % o.id: add(facRow(it))
	if t == 'staff': add(hint('Range attendants and ball pickers are hired for each range, on the Build → Range tab.'))
	if t == 'club':
		var l := Sim.facList().filter(func(x): return x.key.begins_with('venue:'))
		if l.size():
			add(subhead('Open or closed'))
			for it in l: add(facRow(it))
	for cat in LIST_CATS[t]:
		add(subhead(cat[0]))
		for id in cat[1]: add(upgradeRow(Sim.byId[id], inRange))
func _buildSupplies() -> void:
	add(hint('Range balls are ordered for each range on the Range tab.'))
	add(subhead('Stock and equipment'))
	for k in Sim.SUPPLIES:
		var D = Sim.SUPPLIES[k]
		var row = K.card(10)
		var h = K.hbox(12)
		row.add_child(h)
		var ic = K.badge(Icons.ITEM.get(D.icon, Icons.ITEM._), 46); ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(ic)
		var info = K.vbox(3)
		info.add_child(K.lbl(D.label, 14, 800, K.INK))
		var lv = K.rich('', 11)
		info.add_child(lv)
		info.add_child(K.lbl(D.desc, 12, 500, K.MUTED, true))
		var auto = null
		if not D.get("durable"):
			auto = CheckBox.new(); auto.focus_mode = Control.FOCUS_NONE; auto.text = 'Reorder automatically (+10%)'
			auto.add_theme_font_size_override("font_size", 12)
			var key: String = k
			auto.toggled.connect(func(on): Sim.S.auto[key] = on; Sim.save())
			info.add_child(auto)
		h.add_child(K.expand(info))
		var b = K.btn('', 'buy')
		var kk: String = k
		b.pressed.connect(func(): Sim.orderSupply(kk); refresh())
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
		add(row)
		_upd.append(func():
			var n := int(Sim.S.sup.get(kk, 0))
			var low: bool = not D.get("durable") and n < D.pack * 0.25
			K.setRich(lv, "[b]%s %s%s[/b]%s" % [Sim.fmtInt(n), D.unit, (" · %d out now" % Sim.rentalsOut) if kk == 'rental' else '', (' · ' + K.neg('running low')) if low else ''])
			K.setText(b, "+%d · %s" % [D.pack, Sim.fmt(D.cost)]); b.disabled = Sim.S.money < D.cost
			if auto: auto.set_pressed_no_signal(Sim.S.auto.get(kk, false)))

# =====================================================================================
# Course: holes, the designer, tee sets
# =====================================================================================
func _buildCourse() -> void:
	var designing: bool = Sim.designing
	if designing:
		var tools = K.flow(4)
		for t in D_TOOLS:
			if t[0] == 'place': continue
			var key: String = t[0]
			var b = K.btn(t[1], 'seg')
			b.toggle_mode = true
			b.button_pressed = Sim.dTool == key
			b.pressed.connect(func():
				Sim.dTool = key; Sim.dMsg = ''; Sim.selParcel = null; Sim.dPlaceTee = null
				if key != 'adjust': Sim.selFeat = null
				Sim.sfx('tap'); refresh())
			tools.add_child(b)
		add(K.panel(K.box(K.PAPER2, 12), 4)).add_child(tools)
		var rot = K.hbox(6)
		var rotT = K.lbl('', 12, 700, K.INK)
		rot.add_child(K.expand(rotT))
		rot.add_child(K.btn('⟲ Rotate', 'ghost', func(): Sim.rotateDesign(-1)))
		rot.add_child(K.btn('⟳ Rotate', 'ghost', func(): Sim.rotateDesign(1)))
		var del = K.btn('Remove', 'ghost', func():
			Sim.draft.feats = Sim.draft.feats.filter(func(o): return o.id != Sim.selFeat); Sim.selFeat = null; Sim.sfx('soft'); Sim.rebuildDraft())
		rot.add_child(del)
		add(rot)
		var help = K.rich('', 12, K.MUTED)
		add(help)
		_upd.append(func():
			var feat: bool = Sim.FEATS.has(Sim.dTool) and Sim.dTool != 'trees' and Sim.dTool != 'flowers'
			var sf = null
			if Sim.dTool == 'adjust' and Sim.selFeat != null:
				for o in Sim.draft.feats:
					if o.id == Sim.selFeat: sf = o
			rot.visible = feat or sf != null
			del.visible = sf != null
			if sf: rotT.text = "%s · %d°" % [Sim.FEATS[sf.type].label, int(fposmod(rad_to_deg(sf.get("rot", 0.0)), 360))]
			else: rotT.text = "Angle %d° (R to turn)" % int(fposmod(rad_to_deg(Sim.dRot), 360))
			var h := ''
			for t in D_TOOLS:
				if t[0] == Sim.dTool: h = t[2]
			K.setRich(help, (K.pos(Sim.dMsg) if Sim.dMsg.contains('Bought') else K.neg(Sim.dMsg)) if Sim.dMsg != '' else h))
	add(_holeStrip())
	add(_holeHead())
	if designing:
		var land = K.hbox(8)
		var lt = K.rich('', 12)
		land.add_child(K.expand(lt))
		var lb = K.btn('', 'buy', func(): Sim.buyParcel(Sim.selParcel); refresh())
		land.add_child(lb)
		add(land)
		_upd.append(func():
			land.visible = Sim.dTool == 'land'
			if not land.visible: return
			var price := Sim.parcelPrice()
			var p = Sim.selParcel
			lb.visible = false
			if p == null: K.setRich(lt, "You own %d of %d parcels. The next one costs [b]%s[/b]. Click a darkened parcel on the map." % [Sim.S.design.land.size(), Sim.PARCELS.size(), Sim.fmt(price)])
			elif Sim.S.design.land.has(p): K.setRich(lt, 'You already own this parcel.')
			else:
				K.setRich(lt, "This parcel costs [b]%s[/b]." % Sim.fmt(price))
				lb.visible = true; lb.text = "Buy for %s" % Sim.fmt(price); lb.disabled = Sim.S.money < price)
		var foot = K.card(10, Color("#fffaf0"))
		var fv = K.vbox(6)
		foot.add_child(fv)
		var cost = K.rich('', 12)
		fv.add_child(cost)
		var fb = K.hbox(8)
		fb.add_child(K.spacer())
		fb.add_child(K.btn('Cancel', 'ghost', func(): Sim.exitDesign(); Sim.sfx('close'); refresh()))
		var build = K.btn('Build', 'buy', func(): Sim.commitDesign(); refresh())
		fb.add_child(build)
		fv.add_child(fb)
		add(foot)
		_upd.append(func():
			var c := Sim.draftCost()
			var r0: int = Sim.rating18() if Sim.L('back9') else Sim.rating9()
			var r1: int = Sim.withGeo(Sim.draftGeo, func(): return Sim.rating18() if Sim.draft.holes.slice(9).all(func(h): return h.built) else Sim.rating9())
			var lines := ''
			if c.lines.size():
				for l in c.lines: lines += "%s  [b]%s[/b]\n" % [l[0], Sim.fmt(l[1])]
			else: lines = "No changes yet  [b]$0[/b]\n"
			K.setRich(cost, lines + "Course rating %d → [b]%d[/b]   ·   total [b]%s[/b]%s" % [r0, r1, Sim.fmt(c.total), ('\n' + K.neg(c.why)) if not c.valid else ''])
			build.disabled = not c.valid or Sim.S.money < c.total
			build.text = 'Fix the hole first' if not c.valid else ('Not enough cash' if Sim.S.money < c.total else (("Build for %s" % Sim.fmt(c.total)) if c.total else 'Done')))
		return
	var open = K.card(10, Color("#fffaf0"))
	var ov = K.vbox(6)
	ov.add_child(K.btn('Open course designer', 'buy', func(): Sim.enterDesign(); g.openPanel('course')))
	ov.add_child(hint('Move holes, add bunkers, dunes, trees and flowers, buy land and build new holes. The game pauses while you design. Dig ponds and shape hills with Landscaping in the Build tab.'))
	open.add_child(ov)
	add(open)
	add(subhead('Tee sets'))
	for t in Sim.TEE_SETS: add(_teeCard(t))
	add(subhead('Whole course'))
	for u in Sim.UP:
		if u.get("tab") == 'course': add(upgradeRow(u, null))
func _holeStrip() -> Control:
	var gr = K.grid(9, 4)
	for i in 18:
		var b = K.btn('', 'hb')
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(40, 46)
		var v = K.vbox(0); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.set_anchors_preset(Control.PRESET_FULL_RECT); v.alignment = BoxContainer.ALIGNMENT_CENTER
		var n = K.lbl(str(i + 1), 14, 800, K.INK); n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var s = K.lbl('', 9, 700, K.MUTED); s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var m = K.meter(3); m.custom_minimum_size = Vector2(26, 3); m.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(n); v.add_child(s); v.add_child(m)
		b.add_child(v)
		var dot = HudUI.DotRect.new(); dot.col = K.FLAG; dot.custom_minimum_size = Vector2(6, 6); dot.position = Vector2(31, 3)
		b.add_child(dot)
		var idx := i
		b.pressed.connect(func(): g.selectHole(idx); Sim.sfx('select'))
		gr.add_child(b)
		_upd.append(func():
			var designing: bool = Sim.designing
			var geo = Sim.draftGeo if designing else Sim.liveGeo
			var design = Sim.draft if designing else Sim.S.design
			var built: bool = design.holes[idx].built
			var inf = geo.info[idx]
			var sel: bool = Sim.selHole == idx
			b.set_pressed_no_signal(sel)
			K.setCol(n, Color.WHITE if sel else K.INK); K.setCol(s, Color(1, 1, 1, 0.75) if sel else K.MUTED)
			b.modulate.a = 1.0 if built else 0.45
			s.text = ("Par %d" % inf.par) if built else ('Plan' if (designing and design.holes[idx].get("placed")) else ('Place' if designing else 'Not built'))
			m.set_value(inf.rating / float(Sim.HOLE_MAX_RATING) if built else 0.0)
			dot.visible = designing and JSON.stringify(design.holes[idx]) != JSON.stringify(Sim.S.design.holes[idx]))
	return gr
func _holeHead() -> Control:
	var v = K.vbox(4)
	var top = K.hbox(8)
	var t = K.rich('', 14)
	top.add_child(K.expand(t))
	var pb = K.btn('', 'buy')
	pb.pressed.connect(func():
		var h = Sim.draft.holes[Sim.selHole]
		if h.built: h.built = false; h.placed = false; Sim.sfx('tap'); Sim.rebuildDraft()
		else: Sim.dTool = 'place'; Sim.dPlaceTee = null; Sim.dMsg = ''; Sim.sfx('select')
		refresh())
	top.add_child(pb)
	v.add_child(top)
	var chips = K.flow(4)
	v.add_child(chips)
	var why = K.rich('', 12)
	v.add_child(why)
	_upd.append(func():
		var designing: bool = Sim.designing
		var geo = Sim.draftGeo if designing else Sim.liveGeo
		var design = Sim.draft if designing else Sim.S.design
		var i: int = Sim.selHole
		var h = design.holes[i]
		var inf = geo.info[i]
		var vv: Dictionary = Sim.holeValid(Sim.draft, Sim.draftGeo, i) if designing else { "ok": true }
		pb.visible = designing and not Sim.S.design.holes[i].built
		if pb.visible:
			K.styleBtn(pb, 'ghost' if h.built else 'buy')
			pb.text = "Don't build it" if h.built else ('Placing…' if Sim.dTool == 'place' else 'Place this hole')
		var parts := ''
		if designing and not h.built:
			K.setRich(t, "[b]Hole %d[/b] · not placed yet\n%s" % [i + 1, K.muted(('Now click where the green goes.' if Sim.dPlaceTee else 'Click your land where the tee goes.') if Sim.dTool == 'place' else 'Place it anywhere on land you own, then fine-tune it.')])
			chips.visible = false; why.visible = false; return
		if h.built or designing:
			var el := ''
			if inf.get("elev") and abs(inf.elev.delta) >= 1: el = " · %s %d m" % ['uphill' if inf.elev.delta > 0 else 'downhill', abs(inf.elev.delta)]
			var tf: float = Sim.turfOf(i)
			K.setRich(t, "[b]Hole %d[/b] · Par %d · %d yd%s%s" % [i + 1, inf.par, inf.yards, el, (" · rating %d/%d · turf [b]%s[/b]" % [inf.rating, Sim.HOLE_MAX_RATING, K.neg("%d%%" % roundi(tf)) if tf < 60 else "%d%%" % roundi(tf)]) if h.built else ' · planned'])
			var key := str(inf.parts)
			if chips.get_meta("k", '') != key:
				chips.set_meta("k", key); K.clear(chips)
				for pk in inf.parts:
					var on: bool = inf.parts[pk] != 0
					var c = K.panel(K.box(Color("#e1f3e5") if on else Color("#eef1ee"), 999), 0)
					var cs: StyleBoxFlat = c.get_theme_stylebox("panel"); cs.content_margin_left = 7; cs.content_margin_right = 7; cs.content_margin_top = 2; cs.content_margin_bottom = 2
					c.add_child(K.lbl("%s %s" % [PART_LABEL.get(pk, pk), inf.parts[pk]], 11, 700, Color("#5a8a3a") if on else K.MUTED))
					chips.add_child(c)
			chips.visible = true
			why.visible = not vv.ok
			if not vv.ok: K.setRich(why, K.neg(vv.why))
		else:
			K.setRich(t, "[b]Hole %d[/b]  %s" % [i + 1, K.muted('Not built yet. Open the course designer and place it wherever you like on your land.')])
			chips.visible = false; why.visible = false)
	return K.margin(v, 4, 4, 4, 4)
func _teeCard(T) -> Control:
	var row = K.card(10)
	var h = K.hbox(10)
	row.add_child(h)
	var sw := ColorRect.new(); sw.color = Ctx2D.col(T.color); sw.custom_minimum_size = Vector2(14, 14); sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sw)
	var v = K.vbox(2)
	v.add_child(K.lbl("%s tees" % T.label, 13, 800, K.INK))
	v.add_child(K.lbl("%s For %s." % [T.blurb, T.forB], 12, 500, K.MUTED, true))
	var ty = K.lbl('', 11, 800, K.TURF)
	v.add_child(ty)
	h.add_child(K.expand(v))
	var b = null
	if T.k == 'yellow': h.add_child(K.lbl('Standard', 12, 800, K.MUTED))
	else:
		b = K.btn('', 'buy', func(): Sim.buildTeeSet(T.k); refresh())
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	_upd.append(func():
		var built: bool = Sim.teeSets().has(T.k)
		var st = Sim.csCache.get(T.k) if Sim.csCache != null else null
		K.setText(ty, ("%s yd · CR %.1f · slope %d" % [Sim.fmtInt(st.yards), st.cr, st.slope]) if (built and st) else ('Built' if built else ''))
		if b:
			b.text = 'Built' if built else Sim.fmt(Sim.teeSetCost(T.k))
			b.disabled = built or Sim.S.money < Sim.teeSetCost(T.k) or not Sim.courseHoles())
	return row

# =====================================================================================
# Opening hours
# =====================================================================================
func facRow(it) -> Control:
	var row = K.card(10)
	var v = K.vbox(8)
	row.add_child(v)
	var top = K.hbox(10)
	top.add_child(K.badge(Icons.FAC.get(it.icon, Icons.FAC.course), 32, Color("#f3eedf"), K.TURF, 10, 18))
	var tt = K.vbox(1)
	tt.add_child(K.lbl(it.label, 14, 800, K.INK))
	var st = K.lbl('', 12, 700, K.POS)
	tt.add_child(st)
	top.add_child(K.expand(tt))
	v.add_child(top)
	var f: Dictionary = Sim.S.get("fac", {}).get(it.key, {})
	var mode := 'shut' if f.get("shut") else ('hours' if f.get("from") != null else 'open')
	v.add_child(K.seg([['open', 'Open'], ['hours', 'Set hours'], ['shut', 'Closed']], mode, func(m):
		var ff: Dictionary = Sim.S.get("fac", {}).get(it.key, {})
		if m == 'open': Sim.setFac(it.key, { "shut": false, "from": null, "to": null })
		elif m == 'shut': Sim.setFac(it.key, { "shut": true })
		else: Sim.setFac(it.key, { "shut": false, "from": ff.get("from", 8) if ff.get("from") != null else 8, "to": ff.get("to", 20) if ff.get("to") != null else 20 })
		_key = ''; refresh()))
	if mode == 'hours':
		var hh = K.hbox(6)
		hh.add_child(K.lbl('Open from', 12, 700, K.INK))
		hh.add_child(_hourPick(it.key, 'from', int(f.get("from", 8))))
		hh.add_child(K.lbl('to', 12, 700, K.INK))
		hh.add_child(_hourPick(it.key, 'to', int(f.get("to", 20))))
		v.add_child(hh)
	if it.note != '': v.add_child(K.lbl(it.note, 11, 500, K.MUTED, true))
	_upd.append(func():
		var s := Sim.facStatus(it.key)
		K.setText(st, '● ' + s.text); K.setCol(st, Color("#548536") if s.open else K.NEG))
	if g.facFocus == it.key:
		g.facFocus = null
		var sb: StyleBoxFlat = row.get_theme_stylebox("panel"); sb.border_color = K.GOLD; sb.set_border_width_all(3)
		get_tree().create_timer(0.05).timeout.connect(func(): scroll.ensure_control_visible(row))
		get_tree().create_timer(1.8).timeout.connect(func():
			if is_instance_valid(row): sb.border_color = K.LINE; sb.set_border_width_all(1))
	return row
func _hourPick(key: String, which: String, cur: int) -> OptionButton:
	var o := OptionButton.new(); o.focus_mode = Control.FOCUS_NONE
	for h in 25: o.add_item("%02d:00" % h, h)
	o.select(clampi(cur, 0, 24))
	o.item_selected.connect(func(i): Sim.setFac(key, { which: i }))
	return o
func _buildHours() -> void:
	var list := Sim.facList()
	if list.is_empty(): add(hint('Nothing to open or close yet. Build a range, a course or a clubhouse first.')); return
	var shut := list.filter(func(x): return not Sim.facOpen(x.key)).size()
	var hh = K.hbox(10)
	hh.add_child(K.expand(K.rich("Close anything you like, or give it opening hours. Closed facilities take no new golfers and cost about a third to run.%s" % ((" [b]%d closed right now.[/b]" % shut) if shut else ''), 12, K.MUTED)))
	var allb = K.btn('Open everything', 'ghost', func():
		Sim.S.fac = {}; Sim.sfx('chime'); Sim.save(); Sim.toast('Opening hours', 'Everything is open', 'All facilities are open all day again.', '✓'); _key = ''; refresh())
	allb.disabled = Sim.S.get("fac", {}).is_empty()
	allb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hh.add_child(allb)
	add(hh)
	var groups := []
	for x in list:
		if not groups.has(x.group): groups.append(x.group)
	for gname in groups:
		add(subhead(gname))
		for x in list:
			if x.group == gname: add(facRow(x))

# =====================================================================================
# People: who's here, and staff on duty
# =====================================================================================
const WHO_FILTERS := [['all', 'Everyone'], ['course', 'On the course'], ['range', 'Range'], ['club', 'Clubhouse'], ['practice', 'Practising'], ['unhappy', 'Unhappy']]
const STEP_LABEL := { "range": 'Driving range', "course": 'Round of golf', "club": 'Clubhouse', "checkin": 'Check in', "putt": 'Putting green', "short": 'Short game', "lesson": 'Lesson', "shortc": 'Short course' }
const WALK_TO := { "range": 'the driving range', "course": 'the first tee', "club": 'the clubhouse', "checkin": 'the clubhouse to check in', "putt": 'the putting green', "short": 'the short game area', "lesson": 'the academy', "shortc": 'the short course' }
const AMEN_DOING := { "putt": 'Practising putts on the putting green', "short": 'Chipping at the short game area', "academy": 'Having a lesson at the academy', "shortc": 'Playing the short course' }
static func whereOf(v) -> String:
	if Sim.groupOf(v) or v.state == 'golf' or Sim.has_(Sim.teeQueue, v): return 'course'
	if v.state == 'play' or v.state == 'filling' or Sim.has_(Sim.bucketQueue, v) or Sim.has_(Sim.rangeQueue, v) or (v.get("rangeId") != null and v.step < v.plan.size() and v.plan[v.step] == 'range'): return 'range'
	if v.state == 'venue' or v.state == 'desk' or v.state == 'locker' or Sim.has_(Sim.deskQueue, v): return 'club'
	if v.state == 'amen': return 'practice'
	return 'walk'
static func doingOf(v) -> String:
	var gr = Sim.groupOf(v)
	if gr:
		var b = Sim.ball(gr, v) if gr.phase == 'play' else null
		var pin: Vector2 = Sim.pinPos(gr.hole)
		if gr.get("shot") and is_same(gr.shot.v, v): return "Playing a %s on hole %d" % ['putt' if gr.shot.kind == 'putt' else ('chip' if gr.shot.kind == 'chip' else 'shot'), gr.hole + 1]
		if not b: return "%s to the %d%s tee" % ['Driving' if v.get("riding") else 'Walking', gr.hole + 1, Hover.ordinal(gr.hole)]
		if b.lie == 'holed': return ("Picked up on hole %d" % (gr.hole + 1)) if b.get("pickedUp") else ("Holed out in %d on hole %d" % [b.strokes, gr.hole + 1])
		return "Hole %d: %s%s the %s, %d yd to the pin" % [gr.hole + 1, ("%d shot%s, " % [b.strokes, 's' if b.strokes > 1 else '']) if b.strokes else '', 'on' if ['green', 'fringe', 'fairway', 'tee'].has(b.lie) else 'in', Sim.LIE[b.lie].label, Sim.yd(pin.distance_to(Vector2(b.x, b.y)))]
	var nx = v.plan[v.step] if v.step < v.plan.size() else null
	var to: String = WALK_TO.get(nx, 'the car park') if nx else 'the car park'
	if v.get("ejected"): return 'Being sent home by a marshal'
	match v.state:
		'walk': return 'Riding a cart back from the last green' if v.get("cart") else ('Walking back to the car' if v.step >= v.plan.size() else "Walking to %s" % to)
		'queue':
			if Sim.has_(Sim.deskQueue, v): return 'Waiting at the check-in desk'
			if Sim.has_(Sim.teeQueue, v): return 'Waiting for a tee time'
			if Sim.has_(Sim.bucketQueue, v): return 'Waiting for a bucket of balls'
			if Sim.has_(Sim.rangeQueue, v): return 'Waiting for a free bay'
			return "Waiting at %s" % to
		'filling': return 'Filling a bucket at the ball machine'
		'play': return "Hitting balls in bay %d" % (int(v.get("bay", 0)) + 1)
		'venue':
			if v.venue == 'shop': return 'Browsing in the pro shop'
			return "%s at the %s" % ['Having a drink' if v.venue == 'bar' else ('Having a meal' if v.venue == 'resto' else 'Relaxing'), Sim.VENUE_LABEL.get(v.venue, '').to_lower()]
		'locker': return 'Changing in the locker rooms'
		'desk': return 'Showing a membership card at the desk' if v.type == 'member' else 'Paying a green fee at the desk'
		'amen': return AMEN_DOING.get(v.get("amenType"), 'Practising')
		'golf': return 'On the course'
	return 'Deciding what to do next'
func _peopleSig() -> String:
	var here: Array = Sim.here()
	var s = g.whoFilter + str(here.size())
	for v in here.slice(0, 160): s += "%d%s%d" % [v.id, v.state, roundi(Sim.moodOf(v) / 10)]
	return str(s.hash())
func _buildPeople() -> void:
	var here: Array = Sim.here()
	var count := func(k):
		if k == 'all': return here.size()
		return here.filter(func(v): return Sim.moodOf(v) < 40 if k == 'unhappy' else whereOf(v) == k).size()
	var opts := []
	for f in WHO_FILTERS: opts.append([f[0], "%s %d" % [f[1], count.call(f[0])]])
	add(K.seg(opts, g.whoFilter, func(k): g.whoFilter = k; Sim.sfx('tap'); refresh(), true))
	var list: Array = here.filter(func(v): return g.whoFilter == 'all' or (Sim.moodOf(v) < 40 if g.whoFilter == 'unhappy' else whereOf(v) == g.whoFilter))
	if list.is_empty(): add(_empty('Nobody here matches.' if here.size() else 'No golfers in the park right now.')); return
	for v in list.slice(0, 160):
		var mk: String = Sim.moodKind(Sim.moodOf(v))
		var who := _whoBtn(Ctx2D.col(v.color), ('★ ' if v.get("celeb") else '') + v.name, doingOf(v), ("%s%s" % [Sim.GTYPES[v.type].label if Sim.GTYPES.has(v.type) else '', (' · ' + Sim.fmtHcp(v.hcp)) if v.get("hcp") != null else '']), Sim.moodOf(v) / 100.0, Ctx2D.col(Sim.MOOD_COLOR[mk]))
		var vv = v
		who.pressed.connect(func():
			var e := { "kind": 'golfer', "o": vv }
			g.inspect(e); g.glideTo(vv.x, vv.y - 6, max(g.view.cam.s, 2.6)))
		add(who)
func _whoBtn(dot: Color, title: String, sub: String, right: String, mood := -1.0, mcol := Color.WHITE) -> Button:
	var b = K.btn('', 'who')
	b.custom_minimum_size.y = 50
	var h = K.hbox(10); h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT); h.offset_left = 10; h.offset_right = -10
	var d = HudUI.DotRect.new(); d.col = dot; d.custom_minimum_size = Vector2(12, 12)
	h.add_child(d)
	var t = K.vbox(0); t.alignment = BoxContainer.ALIGNMENT_CENTER
	t.add_child(K.lbl(title, 13, 800, K.INK))
	var sl = K.lbl(sub, 11, 600, K.MUTED); sl.clip_text = true; sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.add_child(sl)
	h.add_child(K.expand(t))
	var r = K.vbox(3); r.alignment = BoxContainer.ALIGNMENT_CENTER
	var rl = K.lbl(right, 11, 700, K.MUTED); rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(rl)
	if mood >= 0:
		var m = K.meter(5); m.custom_minimum_size = Vector2(54, 5); m.size_flags_horizontal = Control.SIZE_SHRINK_END; m.set_value(mood, mcol)
		r.add_child(m)
	h.add_child(r)
	b.add_child(h)
	return b
func _empty(t: String) -> Control:
	var p = K.panel(K.box(Color(0, 0, 0, 0), 14, K.LINE, 2), 16)
	var l = K.lbl(t, 14, 600, K.MUTED, true); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p
static func staffNow(e) -> String:
	var o = e.o
	match e.role:
		'marshal':
			var j = o.get("job")
			if o.state == 'patrol' or not j: return 'On patrol' + (' in a cart' if o.get("cart") else ' on foot')
			if j.kind == 'person': return "%s %s%s" % ['Sending' if o.state == 'work' else 'Heading for', j.v.name, ' home' if o.state == 'work' else '']
			return 'Picking up litter' if j.kind == 'litter' else 'Repairing damage'
		'keeper': return ("%s hole %d" % ['Mowing and repairing' if o.state == 'mow' else 'Driving to', o.hole + 1]) if o.hole >= 0 else 'Every hole is in good shape. Waiting for work.'
		'picker': return { "seek": 'Heading out to collect balls', "collect": 'Picking up balls', "return": 'Taking balls back to the machines', "unload": 'Filling the ball machines', "idle": 'Waiting: the range is clear' }.get(o.state, 'Working')
		'attend': return "Looking after bays %d–%d" % [o.idx * 4 + 1, o.idx * 4 + 4]
		'owner', 'shop': return ("Checking in %s" % ' and '.join(Sim.deskIn.slice(0, 2).map(func(v): return v.name))) if Sim.deskIn.size() else 'Behind the counter in the pro shop'
		'chef':
			var n := _seats('resto')
			return (("Cooking for %d diner%s" % [n, 's' if n > 1 else '']) if n else 'Prepping in the kitchen') if Sim.venueOpen('resto') else 'The restaurant is closed'
		'bar':
			var n := _seats('bar') + _seats('terrace')
			return (("Serving %d guest%s at the bar and terrace" % [n, 's' if n > 1 else '']) if n else 'Polishing glasses') if Sim.venueOpen('bar') else 'The bar is closed'
		'starter':
			if not Sim.facOpen('course') or Sim.isDark(): return 'The course is closed'
			return ("Calling the next group: %d waiting" % Sim.teeQueue.size()) if Sim.teeQueue.size() else 'Waiting at the first tee'
		'coach':
			if o.get("academy"):
				for u in Sim.amenUsers(o.academy):
					if u.get("amenSlot") == o.idx and u.state == 'amen': return "Teaching %s" % u.name
			return 'Waiting for a pupil'
	return ''
static func _seats(k: String) -> int:
	var n := 0
	for x in Sim.seatTaken.get(k, {}).values():
		if x: n += 1
	return n
func _crewSig() -> String:
	var s := ''
	for e in Sim.staffRoster(): s += e.role + staffNow(e)
	return str(s.hash())
func _buildCrew() -> void:
	var ros := Sim.staffRoster()
	ros.sort_custom(func(a, b): return Sim.ROLE_ORDER.find(a.role) < Sim.ROLE_ORDER.find(b.role))
	if ros.is_empty(): add(_empty('Nobody on the payroll yet. Hire staff on the Hire tab.')); return
	for e in ros:
		var lk: Dictionary = g.view.art.staffLook(e.o.get("lookRole", e.role) if e.o.get("lookRole") else e.role, int(e.o.get("lookSeed", e.o.get("id", 0))))
		var who := _whoBtn(Ctx2D.col(lk.shirt), e.o.get("name", Sim.ROLE[e.role]) if e.o.get("name") else Sim.ROLE[e.role], staffNow(e), Sim.ROLE[e.role])
		var ee = e
		who.pressed.connect(func(): g.inspect(ee); g.glideTo(ee.o.x, ee.o.y - 6, max(g.view.cam.s, 2.6)))
		add(who)
	var N := func(k): return Sim.N(k)
	var hidden: int = max(0, Sim.N('assist') + 1 - min(3, Sim.N('assist') + 1)) + max(0, Sim.N('chef') - min(2, Sim.N('chef'))) + max(0, Sim.N('bar') - min(2, Sim.N('bar'))) + max(0, Sim.N('starter') - 2) + max(0, Sim.N('coach') - 3)
	if hidden: add(hint("%d more staff are working behind the scenes." % hidden))

# =====================================================================================
# The tee sheet
# =====================================================================================
func _teeSig() -> String:
	var s := "%d|%d|" % [Sim.teeQueue.size(), Sim.isDark()]
	for v in Sim.teeQueue.slice(0, 8): s += "%d,%d;" % [v.id, int(ceil(v.patience - v.wait))]
	for gr in Sim.groups:
		s += "%s/%d/%s/%s;" % [gr.id, gr.hole, gr.phase, gr.players.map(func(p): return p.strokes.size())]
		for p in gr.players: s += str(Sim.holeStrokes(gr, p))
	return str(s.hash())
func _buildTee() -> void:
	var cards = K.grid(2, 10)
	var any := false
	if Sim.teeQueue.size():
		any = true
		var full: bool = Sim.groups.size() >= Sim.slots()
		var rows := []
		for v in Sim.teeQueue.slice(0, 8):
			var left := int(max(0, ceil(v.patience - v.wait)))
			var st = Sim.STANDING[v.standing]
			rows.append(["%s%s · %d holes · hcp %s" % [(st.icon + ' ') if st.icon else '', v.name, v.holes, Sim.fmtHcp(v.get("hcp", 0.0))], "%ds" % left, K.FLAG if left < 10 else K.MUTED])
		if Sim.teeQueue.size() > 8: rows.append(["+%d more" % (Sim.teeQueue.size() - 8), '', K.MUTED])
		cards.add_child(_scCard("First tee · %d waiting" % Sim.teeQueue.size(), 'all tee times taken' if full else "next group in %ds" % int(max(0, ceil(Sim.maxWait() - Sim.teeQueue[0].wait))), [], -1, rows, true))
	var gs := Sim.groups.duplicate()
	gs.sort_custom(func(a, b): return a.hole > b.hole)
	for gr in gs:
		any = true
		var thru: int = gr.players[0].strokes.size()
		var rows := []
		for p in gr.players:
			var tp: String = Sim.toPar(p, gr)
			var st = Sim.STANDING.get(p.standing)
			var hs: int = Sim.holeStrokes(gr, p)
			rows.append(["%s%s" % [(st.icon + ' ') if (st and st.icon) else '', p.name], ('–' if not thru else tp) + ((" (%d)" % hs) if hs else ''), K.FLAG if tp.begins_with('−') else K.INK, Ctx2D.col(Sim.TEE[p.get("tee", 'yellow') if p.get("tee") else 'yellow'].color)])
		var status := ''
		if gr.phase == 'toTee': status = ("Waiting on %d" % (gr.hole + 1)) if Sim.holeBusy(gr, gr.hole) else ("To hole %d" % (gr.hole + 1))
		else: status = "Hole %d · par %d" % [gr.hole + 1, gr.pars[gr.hole]]
		cards.add_child(_scCard("Group %s · %d holes" % [gr.id, gr.holes], status, range(gr.holes), thru, rows, false, gr.hole))
	if not any:
		add(_empty('The course is closed for the night. It opens again at 06:00.' if Sim.isDark() else 'No groups yet. Golfers who book a round wait at the first tee and go out in groups of up to 4.'))
		return
	add(cards)
func _scCard(title: String, right: String, holes: Array, thru: int, rows: Array, waiting: bool, cur := -1) -> Control:
	var card = K.panel(K.box(Color.WHITE, 14, K.LINE, 1), 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v = K.vbox(0)
	card.add_child(v)
	var hd = K.panel(K.box(Color("#6b5b1e") if waiting else K.INK, 0), 0)
	var hs: StyleBoxFlat = hd.get_theme_stylebox("panel"); hs.corner_radius_top_left = 13; hs.corner_radius_top_right = 13
	hs.content_margin_left = 10; hs.content_margin_right = 10; hs.content_margin_top = 7; hs.content_margin_bottom = 7
	var hh = K.vbox(0)
	hh.add_child(K.lbl(title, 12, 800, Color.WHITE))
	hh.add_child(K.lbl(right, 11, 600, Color(1, 1, 1, 0.85)))
	hd.add_child(hh)
	v.add_child(hd)
	if holes.size():
		var hb = K.hbox(2)
		for i in holes:
			var c := ColorRect.new(); c.custom_minimum_size = Vector2(0, 5); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.color = K.TURF if i < thru else (K.FLAG if i == cur else K.LINE)
			hb.add_child(c)
		v.add_child(K.margin(hb, 10, 7, 10, 3))
	var pl = K.vbox(3)
	for r in rows:
		var h = K.hbox(6)
		if r.size() > 3:
			var d = HudUI.DotRect.new(); d.col = r[3]; d.custom_minimum_size = Vector2(7, 7); h.add_child(d)
		var nl = K.lbl(r[0], 12, 600, K.INK); nl.clip_text = true; nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(K.expand(nl))
		h.add_child(K.lbl(r[1], 12, 800, r[2]))
		pl.add_child(h)
	v.add_child(K.margin(pl, 10, 4, 10, 9))
	return card

# =====================================================================================
# Handicaps
# =====================================================================================
func _buildHcp() -> void:
	var course = K.card(12, Color("#fffaf0"))
	var cv = K.vbox(6)
	course.add_child(cv)
	var nums = K.rich('', 13)
	cv.add_child(nums)
	var slope := SlopeBar.new()
	cv.add_child(slope)
	var tees = K.rich('', 12)
	cv.add_child(tees)
	var best = K.rich('', 12, K.MUTED)
	cv.add_child(best)
	add(course)
	_upd.append(func():
		var cs = Sim.csCache.get("yellow") if Sim.csCache != null else null
		slope.visible = cs != null; tees.visible = cs != null
		if not cs: K.setRich(nums, K.muted('Build your first holes to get a course rating and slope.')); best.visible = false; return
		best.visible = true
		K.setRich(nums, "Course rating [b]%.1f[/b]   ·   Slope [b]%d[/b]   ·   Par [b]%d[/b]   ·   [b]%s[/b] yd" % [cs.cr, cs.slope, cs.par, Sim.fmtInt(cs.yards)])
		slope.slope = cs.slope; slope.queue_redraw()
		var tl := ''
		if Sim.teeSets().size() > 1:
			for k in Sim.teeSets():
				var c = Sim.csCache.get(k)
				if c: tl += "[color=%s]●[/color] [b]%s[/b]  %s yd · CR %.1f · slope %d\n" % [Sim.TEE[k].color, Sim.TEE[k].label, Sim.fmtInt(c.yards), c.cr, c.slope]
		K.setRich(tees, tl.strip_edges()); tees.visible = tl != ''
		var bb = Sim.HCP_BANDS[0]
		for b in Sim.HCP_BANDS:
			if abs(cs.slope - b.pref) < abs(cs.slope - bb.pref): bb = b
		K.setRich(best, "From the yellow tees it plays best for [b]%s handicappers[/b]. More tee sets (Course window) let each golfer play from tees that suit them. Longer holes and more hazards raise the slope; shorter, open holes lower it." % bb.label.to_lower()))
	add(subhead('Golfers by handicap'))
	var hdr = K.grid(4, 6)
	for t in ['Band', 'Everyone', 'Your visitors', 'Fit']: hdr.add_child(K.eyebrow(t))
	add(hdr)
	for b in Sim.HCP_BANDS:
		var row = K.vbox(2)
		var gr = K.grid(4, 6)
		var name = K.hbox(6)
		var d = HudUI.DotRect.new(); d.col = Ctx2D.col(b.color); d.custom_minimum_size = Vector2(10, 10)
		name.add_child(d)
		var nv = K.vbox(0); nv.add_child(K.lbl(b.label, 13, 800, K.INK)); nv.add_child(K.lbl("%s–%s" % ['0' if b.lo == 0 else str(b.lo), b.hi], 11, 600, K.MUTED))
		name.add_child(nv)
		name.custom_minimum_size.x = 90
		gr.add_child(name)
		var m1 = K.meter(8, Ctx2D.col(b.color)); m1.custom_minimum_size.x = 80; m1.set_value(b.share / 0.35)
		var l1 = K.lbl("%d%%" % roundi(b.share * 100), 11, 700, K.MUTED)
		var c1 = K.vbox(1); c1.add_child(m1); c1.add_child(l1); gr.add_child(c1)
		var m2 = K.meter(8, Ctx2D.col(b.color)); m2.custom_minimum_size.x = 80
		var l2 = K.lbl('', 11, 700, K.MUTED)
		var c2 = K.vbox(1); c2.add_child(m2); c2.add_child(l2); gr.add_child(c2)
		var fit = K.lbl('', 12, 800, K.INK)
		gr.add_child(fit)
		row.add_child(gr)
		var spend := "Spends %s%d%%." % ['+' if b.spend >= 1 else '−', roundi(abs(b.spend - 1) * 100)]
		row.add_child(K.lbl("%s %s" % [b.wants, spend], 11, 500, K.MUTED, true))
		add(K.card(8)).add_child(row)
		_upd.append(func():
			var log: Dictionary = Sim.S.hcpLog.month if Sim.S.get("hcpLog") else {}
			var tot := 0.0
			for x in log.values(): tot += x
			if tot == 0: tot = 1
			var mine: float = log.get(b.k, 0) / tot
			m2.set_value(mine / 0.5); l2.text = "%d%%" % roundi(mine * 100)
			var cs = Sim.csCache.get("yellow") if Sim.csCache != null else null
			var f: float = Sim.bandFit(b, cs != null)
			var s := 'Great' if f >= 1.15 else ('Good' if f >= 0.85 else ('Poor' if f >= 0.55 else ('Bad' if f > 0 else 'Barred')))
			K.setText(fit, s); K.setCol(fit, K.POS if f >= 0.85 else (Color("#b8860b") if f >= 0.55 else K.NEG)))
	add(subhead('Who may play your course'))
	add(K.seg([[0, 'Open to all'], [36, 'Max 36'], [28, 'Max 28'], [18, 'Max 18']], int(Sim.S.get("hcpLimit", 0)), func(v): Sim.setHcpLimit(v); _key = ''; refresh()))
	add(hint('A handicap limit keeps slow, struggling golfers off a hard course. The range stays open to everyone.'))
	add(subhead('Marketing focus'))
	var fo := [['all', 'Everyone']]
	for b in Sim.HCP_BANDS: fo.append([b.k, b.label])
	add(K.seg(fo, Sim.S.get("hcpFocus", 'all') if Sim.S.get("hcpFocus") else 'all', func(k): Sim.setHcpFocus(k); _key = ''; refresh(), true))
	var fh := hint('')
	add(fh)
	_upd.append(func():
		var f = Sim.S.get("hcpFocus")
		K.setText(fh, ("Your local advertising (level %d) is aimed at %s. A focus brings more of one band and slightly fewer of the rest." % [Sim.L('market'), (Sim.BAND[f].label.to_lower() + ' handicappers') if (f and f != 'all') else 'everyone']) if Sim.L('market') else 'Aim your adverts at one band. It works better the more local advertising you buy (Clubhouse tab).'))
class SlopeBar extends Control:
	var slope := 113
	func _init() -> void: custom_minimum_size = Vector2(300, 34)
	func _draw() -> void:
		var w := size.x
		var y := 8.0
		draw_rect(Rect2(0, y, w, 6), Color("#e8e1cf"))
		for b in Sim.HCP_BANDS: draw_circle(Vector2((b.pref - 55) / 100.0 * w, y + 3), 4, Ctx2D.col(b.color))
		var x := (slope - 55) / 100.0 * w
		draw_rect(Rect2(x - 1.5, y - 5, 3, 16), UIKit.INK)
		var f = UIKit.font(700)
		draw_string(f, Vector2(0, 32), 'Easy', HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.MUTED)
		draw_string(f, Vector2(w / 2 - 40, 32), 'Average (113)', HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.MUTED)
		draw_string(f, Vector2(w - 34, 32), 'Brutal', HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.MUTED)

# =====================================================================================
# Park overview (stats)
# =====================================================================================
func _stat(t: String) -> Array:
	var p = K.panel(K.box(Color("#f3eedf"), 12), 10)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v = K.vbox(4)
	v.add_child(K.eyebrow(t))
	var r = K.rich('', 16)
	v.add_child(r)
	var m = K.meter(6)
	v.add_child(m); m.visible = false
	p.add_child(v)
	return [p, r, m]
func _buildGuests() -> void:
	var gr = K.grid(2, 8)
	add(gr)
	var items := {}
	for k in [['bays', 'Range bays'], ['balls', 'Ball stock'], ['cond', 'Course condition'], ['arr', 'Golfers per minute'], ['away', 'Left unhappy'], ['rounds', 'Rounds played'], ['stand', 'Golfer standing'], ['mood', 'Happiness'], ['marsh', 'Marshals’ work']]:
		var s := _stat(k[1]); gr.add_child(s[0]); items[k[0]] = s
	items.bays[2].visible = true; items.balls[2].visible = true; items.cond[2].visible = true
	_upd.append(func():
		var S: Dictionary = Sim.S
		var RS: Dictionary = Sim.rangeSum()
		var sm := func(t): return "[font_size=11][color=#6c6a52]%s[/color][/font_size]" % t
		var bp: float = RS.players / float(max(1, RS.staffed))
		K.setRich(items.bays[1], "[b]%d / %d[/b] %s" % [RS.players, RS.staffed, sm.call("· %s%s" % [("%d unstaffed" % (RS.bays - RS.staffed)) if RS.staffed < RS.bays else 'all staffed', (" · %d ranges" % RS.n) if RS.n > 1 else ''])])
		items.bays[2].set_value(bp, K.FLAG if bp >= 1 else K.TURF)
		K.setRich(items.balls[1], "[b]%s[/b] %s" % [Sim.fmtInt(floor(RS.stock)), sm.call("ready · %s out · %s owned" % [Sim.fmtInt(floor(RS.field)), Sim.fmtInt(floor(RS.owned))])])
		items.balls[2].set_value(RS.stock / RS.cap if RS.cap else 0.0, K.FLAG if RS.stock < 100 else K.TURF)
		K.setRich(items.cond[1], "[b]%d%%[/b]" % roundi(S.cond))
		items.cond[2].set_value(S.cond / 100.0, K.FLAG if S.cond < 50 else (K.GOLD if S.cond < 80 else K.TURF))
		K.setRich(items.arr[1], "[b]%d[/b]" % roundi((Sim.rangeDemand() + Sim.courseDemand()) * 60))
		K.setRich(items.away[1], "[b]%d[/b] %s" % [Sim.away.size(), sm.call('last min')])
		K.setRich(items.rounds[1], "[b]%s[/b]" % Sim.fmtInt(S.get("rounds", 0)))
		var cl: Array = Sim.conductLog
		var n: int = max(1, cl.size())
		var c := func(k): return roundi(cl.filter(func(x): return x == k).size() * 100.0 / n)
		K.setRich(items.stand[1], ("[b]%d%%[/b] %s" % [c.call('normal'), sm.call("normal · ★ %d%% · ⚠ %d%%" % [c.call('exemplary'), c.call('bad')])]) if cl.size() else '[b]–[/b]')
		var am = Sim.avgMood()
		var eff := roundi((Sim.repMult() - 1) * 100)
		K.setRich(items.mood[1], "[b]%s[/b] %s" % ['–' if am == null else "%d%%" % roundi(am), sm.call("now · reputation %d/100 (%s%d%% golfers)" % [roundi(S.get("rep", 70.0)), '+' if eff >= 0 else '', eff])])
		K.setRich(items.marsh[1], "[b]%d[/b] %s" % [S.get("ejected", 0), sm.call("sent home · %d litter · %d repairs" % [S.get("cleaned", 0), S.get("repaired", 0)])]))

# =====================================================================================
# Finances
# =====================================================================================
func _buildFin() -> void:
	var tiles = K.grid(4, 6)
	var tv := {}
	for k in [['cash', 'Cash'], ['today', 'Today'], ['month', 'This month'], ['loan', 'Loan']]:
		var p = K.panel(K.box(Color("#f3eedf"), 12), 9)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v = K.vbox(2); v.add_child(K.eyebrow(k[1])); var r = K.rich('', 15); v.add_child(r); p.add_child(v)
		tiles.add_child(p); tv[k[0]] = r
	add(tiles)
	var sign := func(v: float): return (K.neg("−" + Sim.fmt(abs(v))) if v < 0 else K.pos("+" + Sim.fmt(v)))
	_upd.append(func():
		var L_: Dictionary = Sim.S.ledger if Sim.S.get("ledger") else Sim.newLedger()
		K.setRich(tv.cash, "[b]%s[/b]" % (K.neg(Sim.fmt(Sim.S.money)) if Sim.S.money < 0 else Sim.fmt(Sim.S.money)))
		K.setRich(tv.today, "[b]%s[/b]" % sign.call(Sim.sumOf(L_.day)))
		K.setRich(tv.month, "[b]%s[/b]" % sign.call(Sim.sumOf(L_.month)))
		K.setRich(tv.loan, "[b]%s[/b]" % Sim.fmt(Sim.S.get("loan", 0.0))))
	add(subhead('Prices'))
	Sim.ensurePrices()
	for it in Sim.PRICE_ITEMS:
		var row = K.card(10)
		var h = K.hbox(8)
		row.add_child(h)
		var info = K.vbox(1)
		info.add_child(K.lbl(it.label, 13, 800, K.INK))
		var fair = K.lbl('', 11, 600, K.MUTED)
		var note = K.rich('', 11)
		info.add_child(fair); info.add_child(note)
		h.add_child(K.expand(info))
		var ctl = K.hbox(4); ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var val = K.lbl('', 15, 800, K.INK); val.custom_minimum_size.x = 60; val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var step := func(d: int):
			var stp: float = 0.05 if it.get("pct") else Sim.priceStep(it.fair.call())
			var v: float = Sim.S.prices[it.k] + stp * d
			v = clampf(round(v / stp) * stp, 0.5 if it.get("pct") else stp, 2.0 if it.get("pct") else it.fair.call() * 3)
			if it.get("pct"): v = round(v * 100) / 100.0
			Sim.S.prices[it.k] = v; Sim.sfx('tap'); Sim.save(); refresh()
		ctl.add_child(K.btn('−', 'ghost', func(): step.call(-1)))
		ctl.add_child(val)
		ctl.add_child(K.btn('+', 'ghost', func(): step.call(1)))
		h.add_child(ctl)
		var fb = K.btn('Fair', 'ghost', func():
			Sim.S.prices[it.k] = 1.0 if it.get("pct") else Sim.nice(it.fair.call()); Sim.sfx('tap'); Sim.save(); refresh())
		fb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(fb)
		add(row)
		_upd.append(func():
			row.visible = it.shown.call()
			if not row.visible: return
			var f: float = it.fair.call()
			var r: float = Sim.S.prices[it.k] / f
			K.setText(val, fmtPrice(it, Sim.S.prices[it.k]))
			K.setText(fair, 'Golfers expect 100%' if it.get("pct") else "Golfers think it's worth %s" % fmtPrice(it, Sim.nice(f)))
			var d := roundi((Sim.valueDemand(r) - 1) * 100)
			K.setRich(note, K.neg("Pricey · %d%% golfers" % d) if r > 1.08 else (K.pos("Bargain · +%d%% golfers" % d) if r < 0.92 else K.muted('Fair price'))))
	add(subhead('Members'))
	var mem = K.rich('', 12)
	add(K.card(10)).add_child(mem)
	_upd.append(func():
		var n: int = Sim.S.get("members", 0)
		var mm: float = Sim.S.get("memberMood", 70.0)
		var lg = Sim.S.get("memberLog")
		K.setRich(mem, "[b]%d[/b] member%s of %d the course can take · %s a month\nSatisfaction [b]%s[/b]%s\n%s" % [n, '' if n == 1 else 's', Sim.memberCap(), Sim.fmt(n * Sim.S.prices.member),
			K.neg("%d%%" % roundi(mm)) if mm < 55 else K.pos("%d%%" % roundi(mm)), (" · last month +%d joined, −%d left" % [lg.join, lg.leave]) if lg else '',
			K.muted('New members join at the start of each month if your reputation, course rating and fee appeal. Unhappy members leave. Members play for free, so too many can crowd out paying golfers.')]))
	add(subhead('Daily profit'))
	var bars := ProfitBars.new()
	add(K.card(10)).add_child(bars)
	_upd.append(func(): bars.queue_redraw())
	add(subhead('Income and costs'))
	var led = K.grid(3, 4)
	add(K.card(10)).add_child(led)
	_upd.append(func():
		var L_: Dictionary = Sim.S.ledger if Sim.S.get("ledger") else Sim.newLedger()
		var last = L_.months[L_.months.size() - 1] if L_.months.size() else null
		var sig := str(L_.month) + str(last)
		if led.get_meta("sig", '') == sig: return
		led.set_meta("sig", sig); K.clear(led)
		var cell := func(o, k): return Sim.fmt(abs(o[k])) if (o and o.get(k)) else '–'
		var addRow := func(a: String, b: String, c: String, bold := false):
			for x in [a, b, c]:
				var l = K.rich(("[b]%s[/b]" % x) if bold else x, 12)
				l.custom_minimum_size.x = 100
				led.add_child(l)
		addRow.call('', 'This month', last.name if last else 'Last month', true)
		for k in Sim.INCOME_CATS:
			if L_.month.get(k) or (last and last.get(k)): addRow.call(Sim.INCOME_CATS[k], cell.call(L_.month, k), cell.call(last, k))
		addRow.call('Income', Sim.fmt(Sim.incomeOf(L_.month)), Sim.fmt(Sim.incomeOf(last)) if last else '–', true)
		for k in Sim.COST_CATS:
			if L_.month.get(k) or (last and last.get(k)): addRow.call(Sim.COST_CATS[k], cell.call(L_.month, k), cell.call(last, k))
		var lp = null
		if last:
			lp = 0.0
			for k in last:
				if Sim.INCOME_CATS.has(k) or Sim.COST_CATS.has(k): lp += last[k]
		addRow.call('Profit', sign.call(Sim.sumOf(L_.month)), sign.call(lp) if lp != null else '–', true))
	add(subhead('Running costs per day'))
	var costs = K.rich('', 12)
	add(K.card(10)).add_child(costs)
	_upd.append(func():
		var items: Array = [['Wages', Sim.wagesPerDay()]] + Sim.upkeepItems()
		if Sim.interestPerDay() > 0.5: items.append(['Interest', Sim.interestPerDay()])
		var s := ''
		var tot := 0.0
		for x in items: s += "%s  [b]%s[/b]\n" % [x[0], Sim.fmt(x[1])]; tot += x[1]
		K.setRich(costs, s + "[b]Total  %s[/b]" % Sim.fmt(tot)))
	add(subhead('Bank'))
	var bank = K.vbox(8)
	var bt = K.rich('', 12)
	bank.add_child(bt)
	var bb = K.flow(6)
	var b1 = K.btn('Borrow $5K', 'buy', func(): Sim.borrow(5000); refresh())
	var b2 = K.btn('Borrow $25K', 'buy', func(): Sim.borrow(25000); refresh())
	var r1 = K.btn('Repay $5K', 'ghost', func(): Sim.repay(5000); refresh())
	var r2 = K.btn('Repay all', 'ghost', func(): Sim.repay(INF); refresh())
	for b in [b1, b2, r1, r2]: bb.add_child(b)
	bank.add_child(bb)
	add(K.card(10)).add_child(bank)
	_upd.append(func():
		var S: Dictionary = Sim.S
		var t := ("You owe [b]%s[/b]. Interest is %s a day (about 9%% a year). The bank will lend up to %s in total." % [Sim.fmt(S.loan), Sim.fmt(S.loan * Sim.LOAN_RATE), Sim.fmt(Sim.creditLimit())]) if S.get("loan", 0) > 0 else ("No loan. The bank will lend up to [b]%s[/b] at about 9%% a year, more as you invest in the park." % Sim.fmt(Sim.creditLimit()))
		if S.money < 0: t += " " + K.neg("Overdrawn for %d day%s: 1%% a day overdraft interest. %d days in the red and the bank closes the club." % [S.get("redDays", 0), '' if S.get("redDays", 0) == 1 else 's', Sim.diff().redDays])
		K.setRich(bt, t)
		b1.disabled = S.get("loan", 0.0) >= Sim.creditLimit(); b2.disabled = b1.disabled
		r1.disabled = not (S.get("loan", 0) > 0) or S.money <= 0; r2.disabled = r1.disabled)
class ProfitBars extends Control:
	func _init() -> void: custom_minimum_size = Vector2(300, 70)
	func _draw() -> void:
		var L_: Dictionary = Sim.S.ledger if Sim.S.get("ledger") else Sim.newLedger()
		var days: Array = L_.days.slice(-12)
		days = days.duplicate()
		days.append({ "day": Sim.S.day, "profit": Sim.sumOf(L_.day), "now": true })
		var mx := 1.0
		for d in days: mx = max(mx, abs(d.profit))
		var w := size.x / 13.0
		var mid := size.y / 2
		draw_line(Vector2(0, mid), Vector2(size.x, mid), UIKit.LINE, 1)
		for i in days.size():
			var d = days[i]
			var h: float = max(2.0, abs(d.profit) / mx * (mid - 2))
			var c = UIKit.NEG if d.profit < 0 else UIKit.TURF
			if d.get("now"): c = c.lightened(0.25)
			var x := i * w + 3
			if d.profit >= 0: draw_rect(Rect2(x, mid - h, w - 6, h), c)
			else: draw_rect(Rect2(x, mid, w - 6, h), c)

# =====================================================================================
# Park: goals, events, rival, awards
# =====================================================================================
func _pkBox(title: String, right: String) -> Array:
	var p = K.card(12, Color.WHITE)
	var v = K.vbox(6)
	p.add_child(v)
	var h = K.hbox(8)
	h.add_child(K.expand(K.lbl(title, 17, 800, K.INK)))
	var r = K.lbl(right, 12, 700, K.MUTED)
	h.add_child(r)
	v.add_child(h)
	add(p)
	return [v, r]
func _buildGoals() -> void:
	var obj := _pkBox('', '')
	var objV: VBoxContainer = obj[0]
	var objBody = K.vbox(6)
	objV.add_child(objBody)
	_upd.append(func():
		var S: Dictionary = Sim.S
		var sc = Sim.scenOf(S.get("scenario"))
		var sig := "%s|%s|%s|%s|%s|%s" % [S.get("medal"), S.get("board"), S.get("boardLog", []).size(), S.money < 0, S.get("repLow"), S.get("finished")]
		for t in (sc.medals if (sc and sc.has("medals")) else []):
			for c in t: sig += str(c.ok.call()) + c.now.call()
		if objBody.get_meta("sig", '') == sig: return
		objBody.set_meta("sig", sig); K.clear(objBody)
		var titleL: Label = objV.get_child(0).get_child(0)
		var rightL: Label = obj[1]
		if not sc or sc.id == 'sandbox':
			titleL.text = 'Sandbox'; rightL.text = 'No objectives, no deadline'
			objBody.add_child(hint('Build whatever you like. Only the bank can stop you.')); return
		titleL.text = sc.name
		rightL.text = "%s · %s" % [Sim.diff().label, 'finished' if S.get("finished") else "deadline %s · %s" % [Sim.dateLabel(S.deadline), Sim.timeLeftTxt()]]
		if S.get("medal", 0): objBody.add_child(K.lbl("%s %s medal earned" % [Sim.MEDAL_IC[S.medal], Sim.MEDAL[S.medal]], 14, 800, Color("#8a6a10")))
		for t in sc.medals.size():
			var got: bool = S.get("medal", 0) > t
			var now: bool = S.get("medal", 0) == t
			var tier = K.panel(K.box(Color("#fbf6e6") if now else (Color("#eef6ea") if got else Color("#f7f4ec")), 12), 9)
			var th = K.hbox(10)
			th.add_child(K.lbl(Sim.MEDAL_IC[t + 1], 22, 800, K.INK))
			var tv = K.vbox(2)
			tv.add_child(K.rich("[b]%s[/b]%s" % [Sim.MEDAL[t + 1], ('  ' + K.muted('also needs everything above')) if t else ''], 13))
			for c in sc.medals[t]:
				var ok: bool = c.ok.call()
				tv.add_child(K.rich("%s %s  %s" % [K.pos('✓') if ok else '○', c.t, K.muted(c.now.call())], 12))
			th.add_child(K.expand(tv))
			tier.add_child(th)
			objBody.add_child(tier)
		var b = S.get("board")
		if b != null:
			var bv = K.vbox(4)
			var bh = K.hbox(6); bh.add_child(K.expand(K.lbl('Board confidence', 13, 800, K.INK))); bh.add_child(K.lbl("%d%%" % roundi(b), 13, 800, K.INK))
			bv.add_child(bh)
			var m = K.meter(8); m.set_value(b / 100.0, K.FLAG if b < 30 else (K.TURF if b >= 60 else K.GOLD)); bv.add_child(m)
			var bl = S.get("boardLog", [])
			if bl.size():
				var notes := []
				for n in bl[0].notes: notes.append("%s %s" % [K.neg(n[0]) if n[0].begins_with('-') else K.pos(n[0]), n[1]])
				bv.add_child(K.rich(K.muted("Last review (%s): " % Sim.dateLabel(bl[0].day, true)) + (' · '.join(notes) if notes.size() else 'no change'), 12))
			else: bv.add_child(hint('The board reviews the club at the end of every month: operating profit, stars, reputation and objectives.'))
			objBody.add_child(bv)
		var fc = Sim.cashForecast()
		if fc and fc.days != null and S.money >= 0: objBody.add_child(K.rich(K.neg("At the current rate the money runs out in about %d day%s." % [fc.days, '' if fc.days == 1 else 's']), 12))
		if S.money < 0: objBody.add_child(K.rich(K.neg("Overdrawn: %d days before the bank closes the club." % max(0, Sim.diff().redDays - S.get("redDays", 0))), 12))
		if S.get("repLow", 0) > 0: objBody.add_child(K.rich(K.neg("Golfers are boycotting the club: %d days to lift the reputation above 15." % (Sim.diff().repDays - S.repLow)), 12)))
	# stars
	var st := _pkBox('Star rating', '')
	var stV: VBoxContainer = st[0]
	var rows := {}
	var maxes := { 'Course design': 30.0, 'Turf': 20.0, '18 holes': 10.0, 'Facilities': 30.0, 'Reputation': 18.0 }
	for k in maxes:
		var h = K.hbox(8)
		var l = K.lbl(k, 12, 700, K.INK); l.custom_minimum_size.x = 110
		var m = K.meter(7); m.size_flags_horizontal = Control.SIZE_EXPAND_FILL; m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var v = K.lbl('', 12, 800, K.INK); v.custom_minimum_size.x = 28; v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l); h.add_child(m); h.add_child(v)
		stV.add_child(h); rows[k] = [m, v]
	var stNote := hint('')
	stV.add_child(stNote)
	_upd.append(func():
		var sp := Sim.starPoints()
		var n := Sim.starsOf(sp.total)
		st[1].text = Sim.starText(n); K.setCol(st[1], Color("#b8860b"))
		for k in rows:
			rows[k][0].set_value(sp.parts[k] / maxes[k]); rows[k][1].text = str(roundi(sp.parts[k]))
		K.setText(stNote, ("%d points. %d more for %d stars." % [roundi(sp.total), Sim.STAR_STEPS[n] - roundi(sp.total), n + 1]) if n < 5 else "%d points: a five-star club." % roundi(sp.total)))
	# milestones
	var list: Array = Sim.goalList()
	var gl := _pkBox('Milestones', ("%d of %d done · cash rewards" % [min(Sim.S.get("goalIdx", 0), list.size()), list.size()]) if list.size() else 'None in this scenario')
	if list.is_empty(): gl[0].add_child(hint('Sandbox mode: build whatever you like.' if Sim.S.get("scenario") == 'sandbox' else 'No milestones in this scenario: the objective above is what counts.'))
	var gi: int = Sim.S.get("goalIdx", 0)
	for i in list.size():
		var gg = list[i]
		var h = K.hbox(10)
		var done := i < gi
		var now := i == gi
		var ic = K.panel(K.box(K.TURF if done else (K.FLAG if (now and Sim.S.get("goalFailed")) else (K.GOLD if now else Color("#f1ede0"))), 12)); ic.custom_minimum_size = Vector2(24, 24)
		var il = K.lbl('✓' if done else str(i + 1), 12, 800, Color.WHITE if done else K.INK); il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ic.add_child(il)
		h.add_child(ic)
		var v = K.vbox(0); v.add_child(K.lbl(gg[0], 13, 800, K.INK)); v.add_child(K.lbl(gg[1], 12, 500, K.MUTED, true))
		h.add_child(K.expand(v))
		h.add_child(K.lbl(Sim.fmt(gg[3]), 12, 800, Color("#8a6a10")))
		h.modulate.a = 1.0 if now else (0.7 if done else 0.55)
		gl[0].add_child(h)
func _buildEvents() -> void:
	var news := _pkBox('Club news', "Random events: %s" % { "off": 'off', "rare": 'rare', "normal": 'normal', "often": 'frequent' }.get(Sim.SETTINGS.get("events", 'normal'), 'normal'))
	var nv: VBoxContainer = news[0]
	var t: float = Sim.nowT()
	var ms: Array = Sim.S.get("mods", []).filter(func(m): return m.until > t)
	ms.sort_custom(func(a, b): return a.start < b.start)
	if ms.size():
		nv.add_child(subhead('Happening now'))
		for m in ms: nv.add_child(_newsRow(m.icon, m.label, Sim.modFx(m), Sim.timeLeft(m), true))
	var log: Array = Sim.S.get("evLog", [])
	if log.is_empty(): nv.add_child(hint('Nothing has happened yet. News, offers and surprises turn up every few days.'))
	for l in log.slice(0, 8): nv.add_child(_newsRow(l.icon, l.title, l.text, Sim.dateLabel(l.day, true), false))
	var ev = Sim.S.get("event")
	var evb := _pkBox('Events', ("%s: %s" % [Sim.EVENTS[ev.key].label, 'today' if ev.state == 'running' else Sim.dateLabel(ev.day)]) if ev else 'Nothing booked')
	for k in Sim.EVENTS:
		var E = Sim.EVENTS[k]
		var v = K.vbox(4)
		v.add_child(K.lbl(E.label, 14, 800, K.INK))
		v.add_child(K.lbl("%s %d players, pays about %s%s." % [E.blurb, E.players, Sim.fmt(Sim.nice(E.pay.call())), ' and a trophy' if E.get("trophy") else ''], 12, 500, K.MUTED, true))
		var needs = K.flow(5)
		var ok := true
		for n in E.needs.call():
			if not n[1]: ok = false
			var c = K.panel(K.box(Color("#e4f3e8") if n[1] else Color("#fbe9e6"), 999), 0)
			var cs: StyleBoxFlat = c.get_theme_stylebox("panel"); cs.content_margin_left = 7; cs.content_margin_right = 7; cs.content_margin_top = 3; cs.content_margin_bottom = 3
			c.add_child(K.lbl(("✓ " if n[1] else "✗ ") + n[0], 11, 700, Color("#3f6e2f") if n[1] else Color("#9b3426")))
			needs.add_child(c)
		v.add_child(needs)
		var key: String = k
		var nm: float = Sim.nextMonthStart()
		var b = K.btn('Booked' if (ev and ev.key == k) else "Book for %s %s" % [Sim.partOfMonth(nm).to_lower(), Sim.MONTHS[Sim.monthIdx(nm)].substr(0, 3)], 'buy', func(): Sim.bookEvent(key); _key = ''; refresh())
		b.disabled = not ok or ev != null
		v.add_child(b)
		var sep := HSeparator.new()
		evb[0].add_child(sep)
		evb[0].add_child(v)
func _newsRow(icon: String, title: String, text: String, when: String, now: bool) -> Control:
	var p = K.panel(K.box(Color("#fbf6e6") if now else Color(0, 0, 0, 0), 10), 7)
	var h = K.hbox(10)
	var ic = K.panel(K.box(Color("#f3f0e4"), 15)); ic.custom_minimum_size = Vector2(30, 30)
	var il = K.lbl(icon, 16, 700, K.INK); il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.add_child(il); ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v = K.vbox(1); v.add_child(K.lbl(title, 13, 800, K.INK)); v.add_child(K.lbl(text, 12, 500, K.MUTED, true))
	h.add_child(K.expand(v))
	h.add_child(K.lbl(when, 11, 700, Color("#8a6a10")))
	p.add_child(h)
	return p
func _buildRival() -> void:
	Sim.ensureRival()
	var R: Dictionary = Sim.S.rival
	var b := _pkBox('The competition', R.name)
	var v: VBoxContainer = b[0]
	var sh := roundi((Sim.rivalShare() - 1) * 100)
	var row := func(a: String, c: String, col := K.INK):
		var h = K.hbox(6); h.add_child(K.expand(K.lbl(a, 13, 600, K.MUTED))); h.add_child(K.lbl(c, 13, 800, col)); v.add_child(h)
	row.call('Their rating', Sim.starText(roundi(R.stars)), Color("#b8860b"))
	row.call('Their 9-hole fee', Sim.fmt(R.fee9))
	row.call('Their course', "%d holes" % R.holes)
	v.add_child(hint("Golfers compare your stars and green fee with theirs: %s.%s" % [("you win %d%% more course golfers than you would alone" % sh) if sh >= 0 else ("they take %d%% of your course golfers" % -sh), (' ' + R.news) if R.get("news") else '']))
func _buildAwards() -> void:
	var got := 0
	for a in Sim.ACH:
		if Sim.S.get("ach", {}).get(a[0]): got += 1
	var b := _pkBox('Achievements', "%d of %d" % [got, Sim.ACH.size()])
	var gr = K.grid(2, 6)
	b[0].add_child(gr)
	for a in Sim.ACH:
		var on: bool = Sim.S.get("ach", {}).get(a[0], 0) != 0
		var p = K.panel(K.box(Color("#fbf6e6") if on else Color("#f4f2ec"), 10), 7)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h = K.hbox(8)
		var ic = K.panel(K.box(K.GOLD if on else Color("#e2ddcf"), 13)); ic.custom_minimum_size = Vector2(26, 26)
		var il = K.lbl('★' if on else '?', 13, 800, K.INK); il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ic.add_child(il); ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(ic)
		var v = K.vbox(0); v.add_child(K.lbl(a[1], 12, 800, K.INK if on else K.MUTED)); v.add_child(K.lbl(a[2], 11, 500, K.MUTED, true))
		h.add_child(K.expand(v))
		p.add_child(h)
		p.tooltip_text = a[2]
		gr.add_child(p)
	b[0].add_child(hint("Lifetime earnings %s" % Sim.fmt(Sim.S.total)))
