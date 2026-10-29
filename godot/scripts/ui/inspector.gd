class_name InspectorUI
extends PanelContainer
## Click anyone to see who they are, what they're doing, and a live camera on them,
## with buttons to follow them or jump the main view there.

const K = preload("res://scripts/ui/kit.gd")
var g
var av: AvatarView
var titleL: Label
var subL: Label
var camBox: SubViewportContainer
var camVP: SubViewport
var cam2: Camera2D
var followBtn: Button
var bodyBox: VBoxContainer
var foot: HBoxContainer
var _sig := ''
var _goneT := -1.0

func _init(game) -> void:
	g = game
	visible = false
	var sb = K.box(K.PAPER, 16, Color(0, 0, 0, 0.08), 1, 14)
	sb.set_content_margin_all(0)
	add_theme_stylebox_override("panel", sb)
	clip_contents = true
	custom_minimum_size = Vector2(300, 0)
	var v = K.vbox(0)
	add_child(v)
	var head = K.panel(K.grad(Color("#365f28"), Color("#2a3a20"), 0), 0)
	var hs: StyleBoxTexture = head.get_theme_stylebox("panel"); hs.content_margin_left = 12; hs.content_margin_right = 8; hs.content_margin_top = 8; hs.content_margin_bottom = 8
	var hb = K.hbox(8)
	av = AvatarView.new()
	hb.add_child(av)
	var tt = K.vbox(0)
	titleL = K.lbl('', 14, 800, Color.WHITE); titleL.clip_text = true; titleL.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subL = K.lbl('', 11, 700, Color(1, 1, 1, 0.8)); subL.clip_text = true; subL.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tt.add_child(titleL); tt.add_child(subL)
	hb.add_child(K.expand(tt))
	var cl = K.btn('×', 'close', func(): g.closeInspector()); cl.custom_minimum_size = Vector2(28, 28)
	hb.add_child(cl)
	head.add_child(hb)
	v.add_child(head)
	var gold := ColorRect.new(); gold.color = K.GOLD; gold.custom_minimum_size.y = 3
	v.add_child(gold)
	# the live camera: a second viewport looking at the same world
	camBox = SubViewportContainer.new()
	camBox.stretch = true
	camBox.custom_minimum_size = Vector2(300, 150)
	camVP = SubViewport.new()
	camVP.size = Vector2i(300, 150)
	camVP.handle_input_locally = false
	camVP.msaa_2d = Viewport.MSAA_2X
	camBox.add_child(camVP)
	cam2 = Camera2D.new(); cam2.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER; cam2.zoom = Vector2(3.4, 3.4)
	camVP.add_child(cam2)
	camBox.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and g.entityAlive(g.insp):
			g.glideTo(g.insp.o.x, g.insp.o.y - 6, max(g.view.cam.s, 2.6)))
	camBox.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var live = K.panel(K.box(Color(200 / 255.0, 50 / 255.0, 42 / 255.0, 0.9), 6), 0)
	var ls: StyleBoxFlat = live.get_theme_stylebox("panel"); ls.content_margin_left = 6; ls.content_margin_right = 6; ls.content_margin_top = 2; ls.content_margin_bottom = 2
	live.add_child(K.lbl('● LIVE', 9, 800, Color.WHITE))
	live.position = Vector2(8, 7)
	camBox.add_child(live)
	var btns = K.hbox(5)
	followBtn = K.btn('Follow', 'plain', func():
		g.camFollow = not g.camFollow; followBtn.text = 'Following' if g.camFollow else 'Follow'; Sim.sfx('tap'))
	followBtn.toggle_mode = true
	var go = K.btn('Go to', 'plain', func():
		if g.entityAlive(g.insp): g.glideTo(g.insp.o.x, g.insp.o.y - 6, max(g.view.cam.s, 2.6)); Sim.sfx('tap'))
	for b in [followBtn, go]: b.add_theme_font_size_override("font_size", 11)
	btns.add_child(followBtn); btns.add_child(go)
	btns.name = 'camBtns'
	camBox.add_child(btns)
	v.add_child(camBox)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = 120
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bodyBox = K.vbox(4)
	bodyBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(K.margin(bodyBox, 12, 10, 12, 10))
	sc.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	foot = K.hbox(6)
	v.add_child(K.margin(foot, 12, 0, 12, 10))

func _ready() -> void:
	camVP.world_2d = get_viewport().world_2d

func layout() -> void:
	var vs: Vector2 = get_parent().size
	var bottom: float = g.hud.bottomHeight() if g.hud else 100.0
	size = Vector2(300, min(470, vs.y - bottom - 140))
	position = Vector2(12, vs.y - bottom - size.y - 8)
	var btns := camBox.get_node('camBtns') as Control
	btns.reset_size()
	btns.position = Vector2(300 - btns.size.x - 6, 150 - btns.size.y - 6)

func show_for(e) -> void:
	visible = true
	_sig = ''; _goneT = -1
	var o = e.o
	if e.kind == 'golfer':
		titleL.text = o.name
		subL.text = "%s%s%s" % [('★ ' + o.celeb + ' · ') if o.get("celeb") else '', Sim.GTYPES[o.type].label if Sim.GTYPES.has(o.type) else 'Golfer', (' · HCP ' + Sim.fmtHcp(o.hcp)) if o.get("hcp") != null else '']
	else:
		titleL.text = o.get("name", Sim.ROLE[e.role]) if o.get("name") else Sim.ROLE[e.role]
		subL.text = Sim.ROLE[e.role]
	followBtn.set_pressed_no_signal(false); followBtn.text = 'Follow'
	av.look = g.view.art.lookOf(o) if e.kind == 'golfer' else _staffLook(e)
	av.queue_redraw()
	K.clear(foot)
	if e.kind == 'staff' and e.role != 'owner':
		foot.add_child(K.expand(K.btn('Staff window', 'plain', func():
			var r = g.insp.role if g.insp else null
			if r == 'attend' or r == 'picker': Sim.selRangeId = g.insp.o.get("rangeId"); g.openPanel('range')
			else: g.openPanel('crew')
			Sim.sfx('open'))))
	elif e.kind == 'golfer':
		foot.add_child(K.expand(K.btn('Everyone here', 'plain', func(): g.openPanel('people'); Sim.sfx('open'))))
	layout()
	refresh()
func _staffLook(e) -> Dictionary:
	var o = e.o
	if o.get("lookRole"): return g.view.art.staffLook(o.lookRole, int(o.get("lookSeed", 0)))
	if e.role == 'picker': return g.view.art.staffLook('picker', int(o.get("rangeId", 0)) * 20 + int(o.get("idx", 0)))
	return g.view.art.staffLook(e.role, int(o.get("id", 0)))
func hide_panel() -> void: visible = false

func frame(dt: float) -> void:
	if not visible: return
	if _goneT >= 0:
		_goneT -= dt
		if _goneT < 0: g.closeInspector()
		return
	if g.entityAlive(g.insp):
		cam2.position = Vector2(g.insp.o.x, g.insp.o.y - 8)
func refresh() -> void:
	if not visible or g.insp == null: return
	var e = g.insp
	if not g.entityAlive(e):
		if e.kind == 'golfer' and e.o.state == 'gone' and _goneT < 0 and not e.get("gone"):
			e.gone = true
			K.clear(bodyBox)
			bodyBox.add_child(K.lbl("%s has gone home%s." % [e.o.name, (" after spending %s" % Sim.fmt(e.o.spent)) if e.o.get("spent") else ''], 13, 800, K.INK, true))
			_goneT = 2.5
		elif _goneT < 0: g.closeInspector()
		return
	var parts: Array = golferParts(e.o) if e.kind == 'golfer' else staffParts(e)
	var sig := str(parts)
	if sig == _sig: return
	_sig = sig
	K.clear(bodyBox)
	for p in parts:
		match p[0]:
			'now': bodyBox.add_child(K.lbl(p[1], 13, 800, K.INK, true))
			'kv':
				var h = K.hbox(10)
				h.add_child(K.expand(K.lbl(p[1], 12, 600, K.MUTED)))
				var r = K.lbl(str(p[2]), 12, 800, K.INK); r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				h.add_child(r)
				bodyBox.add_child(h)
			'bar':
				var m = K.meter(5, Ctx2D.col(p[2])); m.set_value(p[1] / 100.0)
				bodyBox.add_child(m)
			'sec':
				bodyBox.add_child(HSeparator.new())
				if p[1] != '': bodyBox.add_child(K.eyebrow(p[1]))
			'thought': bodyBox.add_child(K.lbl("“%s”" % p[1], 12, 500, Color("#4c5a50"), true))
			'steps':
				var f = K.flow(4)
				for s in p[1]:
					var c = K.panel(K.box(Color("#e4f3e8") if s[1] == 'done' else (K.GOLD if s[1] == 'now' else Color("#efeadb")), 999), 0)
					var cs: StyleBoxFlat = c.get_theme_stylebox("panel"); cs.content_margin_left = 7; cs.content_margin_right = 7; cs.content_margin_top = 2; cs.content_margin_bottom = 2
					c.add_child(K.lbl(('✓ ' if s[1] == 'done' else '') + s[0], 11, 700, K.INK))
					f.add_child(c)
				bodyBox.add_child(f)
			'card':
				var gr = K.grid(9, 2)
				for c in p[1]:
					var cell = K.panel(K.box(c[3], 5), 2)
					var cv = K.vbox(0)
					for x in [[str(c[0]), 9, K.MUTED], [str(c[1]), 9, K.MUTED], [str(c[2]), 12, K.INK]]:
						var l = K.lbl(x[0], x[1], 800, x[2]); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; cv.add_child(l)
					cell.add_child(cv); cell.custom_minimum_size = Vector2(28, 0)
					gr.add_child(cell)
				bodyBox.add_child(gr)

## what we know about a golfer, as a list of parts
func golferParts(v) -> Array:
	var out := []
	var mo: float = Sim.moodOf(v)
	var mk: String = Sim.moodKind(mo)
	out.append(['now', SheetUI.doingOf(v)])
	if v.state == 'queue' and v.get("patience"):
		var left: float = max(0.0, 1 - v.wait / v.patience)
		out.append(['kv', 'Patience', "%d s" % int(ceil(v.patience - v.wait))])
		out.append(['bar', left * 100, '#3fae5f' if left > 0.5 else ('#d9a520' if left > 0.25 else '#e8432e')])
	out.append(['sec', ''])
	out.append(['kv', 'Mood', "%d%% · %s" % [roundi(mo), Sim.MOOD_LABEL[mk]]])
	out.append(['bar', roundi(mo), Sim.MOOD_COLOR[mk]])
	if v.get("thought") and Sim.clockT - v.thought.t < 90: out.append(['thought', v.thought.text])
	var gr = Sim.groupOf(v)
	var pars: Array = gr.pars if gr else v.get("card", [])
	var n: int = v.strokes.size() if v.get("strokes") else 0
	if n or gr:
		out.append(['sec', "Scorecard%s" % ((" · %s tees" % Sim.TEE[v.get("tee", 'yellow') if v.get("tee") else 'yellow'].label) if gr else '')])
		var holes: int = gr.holes if gr else n
		var cells := []
		for i in holes:
			var s = v.strokes[i] if i < n else null
			var p = pars[i] if i < pars.size() else null
			var bg := Color("#f7f4ec")
			if s != null and p != null:
				if s <= p - 2: bg = Color("#f2c14e")
				elif s == p - 1: bg = Color("#bfe3c7")
				elif s == p: bg = Color.WHITE
				elif s == p + 1: bg = Color("#f6dcd5")
				else: bg = Color("#eab9ac")
			if gr and i == gr.hole: bg = bg.darkened(0.08)
			cells.append([i + 1, p if p != null else '', s if s != null else '·', bg])
		out.append(['card', cells])
		if n:
			var tot := 0
			for s in v.strokes: tot += s
			var par := 0
			for i in n: par += pars[i] if i < pars.size() else 0
			var d := tot - par
			out.append(['kv', 'Score', "%d (%s) thru %d" % [tot, 'level par' if d == 0 else (("+%d" % d) if d > 0 else ("−%d" % -d)), n]])
	out.append(['sec', "Today's visit"])
	var steps := []
	for i in v.plan.size(): steps.append([SheetUI.STEP_LABEL.get(v.plan[i], v.plan[i]), 'done' if i < v.step else ('now' if (i == v.step and v.state != 'gone') else '')])
	out.append(['steps', steps])
	out.append(['sec', ''])
	out.append(['kv', 'Golfer', "%s%s" % [Sim.GTYPES[v.type].label if Sim.GTYPES.has(v.type) else 'Golfer', (" · HCP %s" % Sim.fmtHcp(v.hcp)) if v.get("hcp") != null else '']])
	var st = Sim.STANDING[v.standing]
	out.append(['kv', 'Conduct', "%s%s%s" % [(st.icon + ' ') if st.icon else '', st.label, (" · %d offence%s" % [v.offenses, 's' if v.offenses > 1 else '']) if v.get("offenses") else '']])
	out.append(['kv', 'Spent here', Sim.fmt(v.get("spent", 0.0))])
	var arr = v.get("arrived")
	out.append(['kv', 'Arrived', ("%s%s" % [Sim.clock(arr.clock), ' yesterday' if arr.day != Sim.S.day else '']) if arr else '–'])
	if v.get("rental"): out.append(['kv', 'Clubs', 'Rented a set'])
	return out
func staffParts(e) -> Array:
	var o = e.o
	var role: String = e.role
	var out := [['now', SheetUI.staffNow(e)]]
	match role:
		'marshal':
			out.append(['sec', ''])
			out.append(['kv', 'Litter about', Sim.litter.size()]); out.append(['kv', 'Damage to fix', Sim.marks.size()])
			out.append(['kv', 'Troublemakers', Sim.visitors.filter(func(v): return v.get("flagged") and not v.get("ejected")).size()])
		'keeper':
			if o.hole >= 0: out.append(['kv', "Turf on hole %d" % (o.hole + 1), "%d%%" % roundi(Sim.turfOf(o.hole))]); out.append(['bar', Sim.turfOf(o.hole), '#3fae5f'])
			out.append(['sec', ''])
			out.append(['kv', 'Course condition', "%d%%" % roundi(Sim.S.cond)]); out.append(['kv', 'Seed and fertiliser', "%d bags" % int(Sim.S.sup.fert)])
		'picker':
			var rg = Sim.objById(o.get("rangeId"))
			var cart: bool = rg != null and rg.get("r") and o.get("idx", 99) < int(rg.r.lvl.get("cart", 0))
			var cap: float = Sim.withRange(rg, func(): return Sim.pickerCap(cart)) if rg else 60.0
			out.append(['kv', 'Load', "%d / %d balls" % [int(o.load), cap]]); out.append(['bar', o.load / cap * 100, '#3a7bd5'])
			out.append(['sec', ''])
			out.append(['kv', 'Range', Sim.rangeName(rg) if rg else '–']); out.append(['kv', 'Works with', 'A picker cart' if cart else 'A basket and tube'])
			if rg:
				var vals: Array = Sim.withRange(rg, func(): return [Sim.fmtInt(floor(Sim.S.field)), Sim.fmtInt(floor(Sim.S.stock))])
				out.append(['kv', 'Balls on the range', vals[0]]); out.append(['kv', 'Balls in the machines', vals[1]])
		'attend':
			var rg = Sim.objById(o.get("rangeId"))
			if rg:
				var vals: Array = Sim.withRange(rg, func(): return [Sim.staffedBays(), Sim.bays(), Sim.rangeP.size()])
				out.append(['sec', ''])
				out.append(['kv', 'Range', Sim.rangeName(rg)]); out.append(['kv', 'Bays staffed', "%d of %d" % [vals[0], vals[1]]]); out.append(['kv', 'Golfers hitting', vals[2]])
		'owner', 'shop':
			out.append(['sec', ''])
			out.append(['kv', 'In the shop', SheetUI._seats('shop')]); out.append(['kv', 'Waiting at the desk', Sim.deskQueue.size()])
			out.append(['kv', 'Shop sales today', Sim.fmt(Sim.S.ledger.day.get("shop", 0.0) if Sim.S.get("ledger") else 0.0)])
		'chef', 'bar':
			out.append(['sec', ''])
			out.append(['kv', 'Food and drink today' if role == 'bar' else 'Food sales today', Sim.fmt(Sim.S.ledger.day.get("food", 0.0) if Sim.S.get("ledger") else 0.0)])
		'starter':
			out.append(['sec', ''])
			out.append(['kv', 'Groups on the course', Sim.groups.size()]); out.append(['kv', 'Waiting for a tee time', Sim.teeQueue.size()])
		'coach':
			out.append(['sec', ''])
			out.append(['kv', 'Training supplies', Sim.S.sup.get("training", 0)])
	var wage := 0.0
	for s in Sim.STAFF:
		if s.id == ('assist' if role == 'shop' else role): wage = s.sal * Sim.DAY_LEN
	out.append(['kv', 'Wage', 'You run the place' if role == 'owner' else "%s a day" % Sim.fmt(wage)])
	return out

## a little portrait in the header
class AvatarView extends Control:
	var look = null
	var ctx := Ctx2D.new()
	var art: Art
	func _init() -> void:
		custom_minimum_size = Vector2(40, 40)
		art = Art.new(ctx)
		art.camS = 6.0
	func _draw() -> void:
		draw_circle(Vector2(20, 20), 20, Color("#e8efe9"))
		draw_arc(Vector2(20, 20), 19, 0, TAU, 32, Color(1, 1, 1, 0.7), 2, true)
		if look == null: return
		ctx.bind(self)
		art.ctx = ctx
		ctx.save(); ctx.scale(2.6, 2.6)
		art.drawPerson(7.7, 15.4, look, { "ang": PI / 2, "scale": 1.0 })
		ctx.restore()
		ctx.flush()
