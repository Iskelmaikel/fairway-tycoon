extends Node
## The game: the simulation (Sim autoload), the world view, the interface, and the
## controller that connects them (windows, tools, selection, camera and input).

var view: WorldView
var ui: CanvasLayer
var root: Control
var hud: HudUI
var sheet: SheetUI
var inspector: InspectorUI
var dialogs: Dialogs
var audio: AudioPlayer

# ---- interface state (the view reads some of these) ----
var sheetOpen := false
var curWin = null
var tab := 'range'
var parkSub := 'goals'
var lastTabOf := {}
var sheetTab = null          # what the view needs to know: which tab is showing
var insp = null              # the selected entity: { kind, role, o }
var camFollow := false
var tool = null              # the build tool in hand
var ghostT = null
var hoverWorld = null        # the mouse, in world coordinates (null when not over the park)
var facFocus = null
var whoFilter := 'all'
var scenPick := 'fresh'
var diffPick := 'normal'
var speedBeforeMenu := 1
var titleDir := 1.0

# ---- camera motion ----
var glide = null
var camV := Vector2.ZERO
var gesture = null
var _mouse := Vector2.ZERO
var _mouseOn := false
var _shot := {}
var _perf: Array = []
var _perfStarted := false
var _args := {}

const WINDOWS := {
	"build": { "title": 'Build', "tabs": [['place', 'Build'], ['range', 'Range'], ['club', 'Clubhouse'], ['supplies', 'Supplies']] },
	"course": { "title": 'Golf course', "tabs": [['course', 'Holes']] },
	"staff": { "title": 'Staff', "tabs": [['staff', 'Hire'], ['crew', 'On duty']] },
	"golfers": { "title": 'Golfers', "tabs": [['tee', 'On the course'], ['people', 'Who’s here'], ['hcp', 'Handicaps'], ['park:guests', 'Park overview']] },
	"fin": { "title": 'Finances', "tabs": [['fin', 'Finances']] },
	"park": { "title": 'Your club', "tabs": [['park:goals', 'Goals'], ['hours', 'Opening hours'], ['park:events', 'Events'], ['park:rival', 'Rival'], ['park:awards', 'Awards']] },
}
const WIN_ORDER := ['build', 'course', 'staff', 'golfers', 'fin', 'park']

func entityAlive(e) -> bool:
	if e == null or e.get("o") == null: return false
	var o = e.o
	if e.kind == 'golfer': return Sim.has_(Sim.visitors, o) and o.state != 'gone' and o.state != 'drive'
	if e.role == 'marshal': return Sim.has_(Sim.marshals, o)
	if e.role == 'keeper': return Sim.has_(Sim.keepers, o)
	if e.role == 'picker':
		for x in Sim.RT.values():
			if Sim.has_(x.pickers, o): return true
		return Sim.has_(Sim.pickers, o)
	return is_same(Sim.actors.get(o.key), o)

func _ready() -> void:
	get_window().min_size = Vector2i(1024, 640)
	view = WorldView.new()
	view.game = self
	add_child(view)
	audio = AudioPlayer.new()
	audio.game = self
	add_child(audio)
	ui = CanvasLayer.new(); ui.layer = 5
	add_child(ui)
	root = Control.new()
	root.theme = UIKit.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	hud = HudUI.new(self); root.add_child(hud)
	sheet = SheetUI.new(self); root.add_child(sheet)
	inspector = InspectorUI.new(self); root.add_child(inspector)
	dialogs = Dialogs.new(self); root.add_child(dialogs)
	_layoutRoot()
	get_viewport().size_changed.connect(_layoutRoot)
	Sim.toast_shown.connect(func(k, t, x, i): hud.toast(k, t, x, i))
	Sim.event_card.connect(func(ev): dialogs.showEventCard(ev))
	Sim.end_screen.connect(func(kind): dialogs.showEnd(kind))
	Sim.cup_result.connect(func(r): dialogs.showCup(r))
	Sim.inspect_requested.connect(func(e): inspect(e))
	Sim.path_offer_needed.connect(func(need): get_tree().create_timer(0.3).timeout.connect(func(): offerPath(need)))
	Sim.money_popped.connect(func(v, amount): hud.moneyPop(v, amount))
	Sim.game_started.connect(_onGameStarted)
	Sim.ui_tick.connect(_uiTick)
	Sim.settings_changed.connect(applySettings)
	Sim.design_changed.connect(_onDesignChanged)
	# command-line options for tests and screenshots: -- --scen=rescue --shot=file.png
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	applySettings()
	if _args.has("scen"):
		Sim.startScenario(_args.scen, _args.get("diff", "normal"), _args.get("name", "Pine Hollow Golf Club"))
		if _args.has("days"):
			for i in int(float(_args.days) * Sim.DAY_LEN * 10): Sim.tick(0.1)
		if _args.has("hour"): Sim.S.clock = float(_args.hour) / 24.0 * Sim.DAY_LEN
		if _args.has("money"): Sim.S.money = float(_args.money)
		Sim.setSpeed(int(_args.get("speed", "1")))
	else:
		openTitle('main')
	view.goHome()
	if _args.has("zoom"):
		view.cam.s = float(_args.zoom); var h := view.homePt(); view.centerOn(h.x, h.y)
	if _args.has("at"):
		var p: PackedStringArray = _args.at.split(",")
		view.centerOn(float(p[0]), float(p[1]))
	if _args.has("open"): openPanel(_args.open)
	if _args.has("act"): _testAct.call_deferred(_args.act)
	if _args.has("shot"): _shot = { "path": _args.shot, "frames": int(_args.get("wait", "30")) }
	if Sim.gameLive and not Sim.atTitle: _checkAway()

## For screenshots and tests: open a piece of the interface from the command line (--act=...).
func _testAct(a: String) -> void:
	match a:
		'golfer':
			for v in Sim.visitors:
				if v.state != 'drive' and v.state != 'gone': inspect({ "kind": 'golfer', "o": v }); return
		'player':
			for grp in Sim.groups: inspect({ "kind": 'golfer', "o": grp.players[0] }); return
		'staff':
			if Sim.keepers.size(): inspect({ "kind": 'staff', "role": 'keeper', "o": Sim.keepers[0] })
		'designer': Sim.enterDesign(); openPanel('course')
		'menu': dialogs.openMenu()
		'settings': dialogs.openSettings()
		'slots': dialogs.openSlots('save')
		'newgame': openTitle('new')
		'loadgame': openTitle('load')
		'end': Sim.showEnd('gold')
		'lose': Sim.showEnd('bank')
		'cup': Sim.cup_result.emit({ "eyebrow": 'Charity Pro-Am', "winner": 'Event score 82/100', "won": '+$7.00K', "msg": 'A lovely day out.' })
		'away': dialogs.showAway(1234.0, 'While you were away for 2 hours, the club earned this.')
		_:
			if a.begins_with('event:'): Sim.fireRandomEvent(a.substr(6))
			elif a.begins_with('click:'):   # click:x,y[;x,y...] in screen pixels, through the real input path
				for pt in a.substr(6).split(';'):
					var xy := pt.split(',')
					var pos := Vector2(float(xy[0]), float(xy[1]))
					for down in [true, false]:
						var e := InputEventMouseButton.new()
						e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = pos; e.global_position = pos
						Input.parse_input_event(e)
						await get_tree().process_frame
					await get_tree().create_timer(0.3).timeout
			elif a.begins_with('tool:'): openPanel('place'); setTool({ "kind": a.substr(5) })

func _layoutRoot() -> void:
	var s: float = Sim.SETTINGS.get("uiScale", 1.0)
	var vs := get_viewport().get_visible_rect().size
	root.scale = Vector2(s, s)
	root.size = vs / s
	root.position = Vector2.ZERO
	if hud: hud.layout(); sheet.layout(); inspector.layout(); dialogs.layout()
	measurePads()
func uiScale() -> float: return Sim.SETTINGS.get("uiScale", 1.0)
func applySettings() -> void:
	_layoutRoot()
	audio.setVolumes()
	var fs: bool = Sim.SETTINGS.get("fullscreen", false)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and DisplayServer.get_name() != "headless": DisplayServer.window_set_mode(want)

func _onDesignChanged() -> void:
	if sheetOpen and tab == 'course': sheet.refresh()
func _onGameStarted() -> void:
	closeInspector()
	if sheetOpen: closePanel()
	recenter()
	hud.refresh(); sheet.refresh()

# =====================================================================================
# The frame
# =====================================================================================
func _process(delta: float) -> void:
	var dt: float = min(delta, 0.25)
	_pcTick(dt)
	_stepCamera(dt)
	_followCam(dt)
	_titleDrift(dt)
	var t0 := Time.get_ticks_usec()
	view.step(dt, dt * Sim.warp)
	var t1 := Time.get_ticks_usec()
	hud.frame(dt)
	inspector.frame(dt)
	Sim.prof('view.step', t1 - t0); Sim.prof('hud+insp', Time.get_ticks_usec() - t1)
	if _args.has("perf"):
		if _perf.is_empty() and not _perfStarted: _perfStarted = true; Sim.PROF.clear()
		_perf.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		if _perf.size() == 240:
			_perf.sort()
			var ks: Array = Sim.PROF.keys(); ks.sort_custom(func(a, b): return Sim.PROF[a] > Sim.PROF[b])
			for k in ks: print("  %-14s %7.2f ms/frame" % [k, Sim.PROF[k] / 240000.0])
			print("process ms: median %.2f · p95 %.2f · max %.2f · visitors %d · groups %d · draw calls %d" % [_perf[120], _perf[228], _perf[239], Sim.visitors.size(), Sim.groups.size(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	if _shot.size():
		_shot.frames -= 1
		if _shot.frames <= 0:
			var path: String = _shot.path
			_shot = {}
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path)
			get_tree().quit()
func _uiTick() -> void:
	hud.refresh()
	if sheetOpen: sheet.refresh()
	inspector.refresh()
	measurePads(); view.clampCam()
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		Sim.save()
	if what == NOTIFICATION_WM_CLOSE_REQUEST: get_tree().quit()

# ---- the screen space the park is not covered by windows
func measurePads() -> void:
	if Sim.atTitle:
		view.padTop = 0; view.padBot = 0; view.padRight = 0; return
	var s := uiScale()
	view.padRight = (sheet.size.x + 24) * s if sheetOpen else 0.0
	view.padTop = hud.topHeight() * s
	view.padBot = hud.bottomHeight() * s

# =====================================================================================
# Windows
# =====================================================================================
func openPanel(k: String) -> void:
	if k == 'park': k = 'park:' + (parkSub if ['goals', 'events', 'rival', 'awards'].has(parkSub) else 'goals')
	var w = null
	for x in WIN_ORDER:
		for t in WINDOWS[x].tabs:
			if t[0] == k: w = x
	if w == null: return
	var parts := k.split(':')
	tab = parts[0]
	if parts.size() > 1: parkSub = parts[1]
	curWin = w; lastTabOf[w] = k; sheetOpen = true
	sheetTab = tab
	sheet.open(w, k)
	measurePads()
	var focus = _focusFor(tab)
	if focus != null: glideTo(focus.x, focus.y, focus.z)
	else: view.clampCam()
	hud.refresh()
func closePanel() -> void:
	sheetOpen = false; curWin = null; sheetTab = null
	sheet.close()
	measurePads(); view.clampCam(); hud.refresh()
func toggleWindow(w: String) -> void:
	if Sim.designing and w != 'course':
		Sim.toast('Course designer', 'Finish your design first', 'Build it or cancel before leaving the course designer.', '⛳'); return
	if sheetOpen and curWin == w and not Sim.designing: closePanel(); Sim.sfx('close')
	else: openPanel(lastTabOf.get(w, WINDOWS[w].tabs[0][0])); Sim.sfx('open')
func cycleWindowTab(dir: int) -> void:
	if not sheetOpen: return
	var t: Array = WINDOWS[curWin].tabs
	if t.size() < 2: return
	var cur := ('park:' + parkSub) if tab == 'park' else tab
	var i := 0
	for j in t.size():
		if t[j][0] == cur: i = j
	openPanel(t[(i + dir + t.size()) % t.size()][0]); Sim.sfx('tap')
func cycleTab(dir: int) -> void:
	var i := WIN_ORDER.find(curWin if sheetOpen else 'park')
	openPanel(WINDOWS[WIN_ORDER[(i + dir + WIN_ORDER.size()) % WIN_ORDER.size()]].tabs[0][0]); Sim.sfx('open')
func fitScale(w: float, h: float) -> float:
	var SW := view.SW()
	var SH := view.SH()
	return max(view.minZoom(), min(1.6, (SW - view.padRight) / w, max(120.0, SH - view.padTop - view.padBot) / h))
func _focusFor(t: String):
	if t == 'range':
		var o = Sim.selRange()
		if not o: return null
		return Sim.withRange(o, func():
			var x1: float = Sim.rangeX1()
			return Vector3((Sim.RX0 + x1) / 2, (Sim.RY0 + Sim.TEE_Y) / 2 + 20, fitScale(x1 - Sim.RX0 + 60, Sim.TEE_Y - Sim.RY0 + 80)))
	if t == 'course':
		var design = Sim.draft if Sim.designing else Sim.S.design
		if not design.holes[Sim.selHole].get("placed"): return null
		var f := func():
			var x0 := 1e9; var y0 := 1e9; var x1 := -1e9; var y1 := -1e9
			for k in 13:
				var q: Vector2 = Sim.hPt(Sim.selHole, -0.02 + (Sim.greenT(Sim.selHole) + 0.12) * k / 12.0)
				x0 = min(x0, q.x); y0 = min(y0, q.y); x1 = max(x1, q.x); y1 = max(y1, q.y)
			return Vector3((x0 + x1) / 2, (y0 + y1) / 2, fitScale(x1 - x0 + 160, y1 - y0 + 150))
		return Sim.withGeo(Sim.draftGeo, f) if Sim.designing else f.call()
	if t == 'club':
		if not Sim.hasObj('club'): return null
		return Vector3(1120 + Sim.CDX, 1380 + Sim.CDY, fitScale(500, 260))
	return null
func selectHole(i: int) -> void:
	Sim.selHole = i
	if not (sheetOpen and tab == 'course'): openPanel('course'); return
	sheet.refresh()
	var f = _focusFor('course')
	if f != null: glideTo(f.x, f.y, f.z)

# =====================================================================================
# Camera
# =====================================================================================
func glideTo(wx: float, wy: float, ts = null) -> void:
	var cam := view.cam
	var SW := view.SW()
	var SH := view.SH()
	var visH := SH - view.padTop - view.padBot
	var o := [cam.x, cam.y, cam.s]
	cam.s = clampf(ts if ts != null else cam.s, view.minZoom(), 4.0)
	var ax := (SW - view.padRight) / 2
	cam.x = wx - ax / cam.s; cam.y = wy - (view.padTop + visH / 2) / cam.s; view.clampCam()
	glide = { "x": cam.x, "y": cam.y, "s": cam.s, "wx": cam.x + ax / cam.s, "wy": cam.y + (view.padTop + visH / 2) / cam.s, "ay": view.padTop + visH / 2, "ax": ax }
	cam.x = o[0]; cam.y = o[1]; cam.s = o[2]
func _stepCamera(dt: float) -> void:
	var cam := view.cam
	if glide:
		var k: float = min(1.0, dt * 5)
		var cx: float = cam.x + glide.ax / cam.s
		var cy: float = cam.y + glide.ay / cam.s
		cam.s += (glide.s - cam.s) * k
		var nx: float = cx + (glide.wx - cx) * k
		var ny: float = cy + (glide.wy - cy) * k
		cam.x = nx - glide.ax / cam.s; cam.y = ny - glide.ay / cam.s; view.clampCam()
		if abs(glide.x - cam.x) + abs(glide.y - cam.y) < 0.5 and abs(glide.s - cam.s) < 0.003:
			cam.x = glide.x; cam.y = glide.y; cam.s = glide.s; glide = null
	elif gesture == null and camV.length() > 2:
		cam.x += camV.x * dt; cam.y += camV.y * dt; view.clampCam()
		camV *= pow(0.04, dt)
func _followCam(dt: float) -> void:
	if not camFollow or not entityAlive(insp): return
	var o = insp.o
	var cam := view.cam
	var visH := view.SH() - view.padTop - view.padBot
	var k: float = min(1.0, dt * 4)
	var tx: float = o.x - (view.SW() - view.padRight) / 2 / cam.s
	var ty: float = o.y - 6 - (view.padTop + visH / 2) / cam.s
	cam.x += (tx - cam.x) * k; cam.y += (ty - cam.y) * k; view.clampCam()
func recenter() -> void:
	view.goHome(); hud.showRecenter(false)
func _titleDrift(dt: float) -> void:
	if not Sim.atTitle: return
	var x0: float = view.cam.x
	view.cam.x += titleDir * 22 * dt / view.cam.s; view.clampCam()
	if abs(view.cam.x - x0) < 1e-4: titleDir *= -1
func parkCenter() -> Vector2:
	return Vector2((view.SW() - view.padRight) / 2, view.padTop + (view.SH() - view.padTop - view.padBot) / 2)
func uiBlocked() -> bool:
	return Sim.atTitle or dialogs.blocking()
func _pcTick(dt: float) -> void:
	var m := Vector2.ZERO
	var z := 0.0
	if not uiBlocked() and not _textFocused():
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): m.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): m.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): m.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): m.y += 1
		if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD): z += 1
		if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT): z -= 1
		# controller: left stick moves, right stick and triggers zoom
		for dev in Input.get_connected_joypads():
			var ax := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
			if ax.length() > 0.18: m += ax
			var rz := -Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y) + Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)
			if abs(rz) > 0.18: z += rz
		# edge scrolling, when the mouse is over the park
		if Sim.SETTINGS.get("edgePan", true) and _mouseOn and gesture == null and DisplayServer.window_is_focused():
			var mm := 14.0
			var SW := view.SW()
			var SH := view.SH()
			if _mouse.x < mm: m.x -= 1
			elif _mouse.x > SW - view.padRight - mm and _mouse.x < SW - view.padRight: m.x += 1
			if _mouse.y < mm: m.y -= 1
			elif _mouse.y > SH - mm: m.y += 1
	if m != Vector2.ZERO:
		glide = null
		var sp: float = 650 * Sim.SETTINGS.get("camSpeed", 1.0) * (2.2 if Input.is_key_pressed(KEY_SHIFT) else 1.0) / view.cam.s
		view.cam.x += m.x * sp * dt; view.cam.y += m.y * sp * dt; view.clampCam(); hud.showRecenter(true)
	if z != 0:
		glide = null
		var c := parkCenter()
		view.zoomAt(c.x, c.y, exp(z * 1.4 * dt)); hud.showRecenter(true)
	# what's under the mouse
	if _mouseOn and not uiBlocked():
		hoverWorld = view.toWorld(_mouse.x, _mouse.y)
		if tool != null: buildHover(hoverWorld.x, hoverWorld.y)
	else: hoverWorld = null
	hud.updateTooltip(_mouse / uiScale(), _mouseOn and gesture == null and not uiBlocked() and not Sim.designing and tool == null)
func _textFocused() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit

# =====================================================================================
# Input: the park gets whatever the interface does not use
# =====================================================================================
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo: _key(e); return
	if e is InputEventJoypadButton and e.pressed: _padButton(e); return
	if uiBlocked():
		if e is InputEventMouseMotion: _mouse = e.position; _mouseOn = false
		return
	if e is InputEventMouseMotion:
		_mouse = e.position; _mouseOn = true
		if gesture == null: return
		if gesture.type == 'handle': var w := view.toWorld(e.position.x, e.position.y); Sim.dragHandle(gesture.which, w.x, w.y); return
		if gesture.type == 'paint': var w := view.toWorld(e.position.x, e.position.y); buildDrag(w.x, w.y); return
		if gesture.type == 'pan':
			if not gesture.moved and e.position.distance_to(gesture.s) > 8: gesture.moved = true
			if gesture.moved:
				var d: Vector2 = e.position - gesture.l
				var now := Time.get_ticks_msec()
				var dtm: float = max(1, now - gesture.t)
				view.cam.x -= d.x / view.cam.s; view.cam.y -= d.y / view.cam.s; view.clampCam()
				camV = -d / view.cam.s / dtm * 1000
				gesture.t = now; hud.showRecenter(true)
			gesture.l = e.position
		return
	if e is InputEventMouseButton:
		_mouse = e.position; _mouseOn = true
		if e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			glide = null
			var dir := 1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			view.zoomAt(e.position.x, e.position.y, exp(dir * 0.12 * (e.factor if e.factor > 0 else 1.0)))
			hud.showRecenter(true); return
		if e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			if tool != null: setTool(null); Sim.sfx('close')
			return
		if e.button_index != MOUSE_BUTTON_LEFT: return
		if e.pressed:
			glide = null; camV = Vector2.ZERO
			if tool != null and (tool.kind == 'path' or tool.kind == 'unpath' or Sim.TERRA.has(tool.kind)):
				gesture = { "type": 'paint', "moved": true }
				var w := view.toWorld(e.position.x, e.position.y); buildDrag(w.x, w.y); return
			var hnd = handleAt(e.position)
			if hnd: gesture = { "type": 'handle', "which": hnd, "moved": true }; return
			gesture = { "type": 'pan', "s": e.position, "l": e.position, "t": Time.get_ticks_msec(), "moved": false }
		else:
			if gesture == null: return
			if gesture.type == 'paint' and Sim.terStroke != null:
				var r = Sim.endTerraStroke()
				if tool: tool.msg = r.msg; tool.bad = r.bad
				hud.paintBuildBar(); sheet.refresh()
			if gesture.type == 'pan' and not gesture.moved: _tap(e.position)
			if gesture.type == 'pan' and Time.get_ticks_msec() - gesture.t > 80: camV = Vector2.ZERO
			gesture = null
func _tap(sp: Vector2) -> void:
	var w := view.toWorld(sp.x, sp.y)
	if tool != null: buildTap(w.x, w.y); return
	if Sim.designing: Sim.designTap(w.x, w.y, view.cam.s); sheet.refresh(); return
	var ent = entityAt(w.x, w.y)
	var hi: int = Sim.holeAt(w.x, w.y, view.cam.s) if ent == null else -1
	if ent != null: inspect(ent); return
	if hi >= 0: selectHole(hi); Sim.sfx('select'); return
	var bld = buildingAt(w.x, w.y)
	if bld: openPanel(bld); Sim.sfx('open')
func _key(e: InputEventKey) -> void:
	var k := e.keycode
	if k == KEY_ESCAPE: backOut(); get_viewport().set_input_as_handled(); return
	if _textFocused(): return
	if uiBlocked() or e.ctrl_pressed or e.meta_pressed or e.alt_pressed: return
	if Sim.designing and k == KEY_R: Sim.rotateDesign(-1 if e.shift_pressed else 1); return
	if tool != null and Sim.TERRA.has(tool.kind) and (k == KEY_BRACKETLEFT or k == KEY_BRACKETRIGHT):
		Sim.terBrush = clampi(Sim.terBrush + (1 if k == KEY_BRACKETRIGHT else -1), 0, Sim.BRUSH.size() - 1); hud.paintBuildBar(); Sim.sfx('tap'); return
	if k == KEY_F5: Sim.save(); Sim.toast('Quick save', Sim.clubName(), 'Saved to the autosave slot.', '✓'); return
	if k >= KEY_1 and k <= KEY_6: toggleWindow(WIN_ORDER[k - KEY_1]); return
	if k == KEY_TAB:
		if sheetOpen: cycleWindowTab(-1 if e.shift_pressed else 1)
		get_viewport().set_input_as_handled(); return
	if k == KEY_SPACE: Sim.togglePause(); Sim.sfx('tap'); return
	if k == KEY_COMMA or k == KEY_PERIOD: Sim.setSpeed(Sim.speedIdx + (1 if k == KEY_PERIOD else -1)); Sim.sfx('tap'); return
	if k == KEY_H: recenter(); Sim.sfx('tap'); return
	if k == KEY_M: audio.toggle(); hud.paintSound(); return
	if k == KEY_N: audio.skipTrack(); return
	if k == KEY_F or k == KEY_F11: Sim.SETTINGS.fullscreen = not Sim.SETTINGS.get("fullscreen", false); Sim.saveSettings(); return
func _padButton(e: InputEventJoypadButton) -> void:
	match e.button_index:
		JOY_BUTTON_B: backOut()
		JOY_BUTTON_X:
			if not uiBlocked(): Sim.togglePause()
		JOY_BUTTON_Y:
			if not uiBlocked(): openPanel('tee')
		JOY_BUTTON_LEFT_SHOULDER:
			if not uiBlocked(): cycleTab(-1)
		JOY_BUTTON_RIGHT_SHOULDER:
			if not uiBlocked(): cycleTab(1)
		JOY_BUTTON_BACK: recenter()
		JOY_BUTTON_START:
			if dialogs.settingsOpen(): dialogs.closeSettings()
			elif dialogs.menuOpen(): dialogs.closeMenu()
			elif not Sim.atTitle: dialogs.openMenu()
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			if sheetOpen and tab == 'course': selectHole((Sim.selHole + (1 if e.button_index == JOY_BUTTON_DPAD_RIGHT else 17)) % 18)
## Esc and the controller's B button back out of whatever is on top
func backOut() -> void:
	if dialogs.backOut(): return
	if Sim.atTitle: return
	if tool != null: setTool(null); Sim.sfx('close')
	elif Sim.designing: Sim.exitDesign(); sheet.refresh(); Sim.sfx('close')
	elif insp != null: closeInspector()
	elif sheetOpen: closePanel(); Sim.sfx('close')
	else: dialogs.openMenu()

# =====================================================================================
# Picking things in the park
# =====================================================================================
func entityAt(wx: float, wy: float):
	var r: float = 13 / clampf(view.cam.s, 0.6, 1.8)
	var best = null
	var bd := r
	# (lambdas can't assign outer locals, so collect candidates and pick after)
	var cands := []
	for m in Sim.marshals: cands.append([{ "kind": 'staff', "role": 'marshal', "o": m }, m.x, m.y - (0 if m.get("cart") else 7), 3.0 if m.get("cart") else 0.0])
	for k in Sim.keepers: cands.append([{ "kind": 'staff', "role": 'keeper', "o": k }, k.x, k.y, 4.0])
	for a in Sim.actors.values(): cands.append([{ "kind": 'staff', "role": a.role, "o": a }, a.x, a.y - 7, 0.0])
	Sim.forRanges(func(rg):
		for i in Sim.pickers.size():
			var p = Sim.pickers[i]
			p.rangeId = rg.id; p.idx = i
			var cart := i < Sim.L('cart')
			cands.append([{ "kind": 'staff', "role": 'picker', "o": p }, p.x, p.y - (0 if cart else 7), 4.0 if cart else 0.0]))
	for v in Sim.visitors:
		if v.state == 'drive' or v.state == 'gone': continue
		cands.append([{ "kind": 'golfer', "o": v }, v.x, v.y - (0 if (v.get("riding") or v.get("cart")) else 7), 0.0])
	for c in cands:
		var d = Vector2(c[1] - wx, c[2] - wy).length() - c[3]
		if d < bd: bd = d; best = c[0]
	return best
func buildingAt(wx: float, wy: float):
	var t := Sim.tileOf(wx, wy)
	if t.tx < 0 or t.ty < 0 or t.tx >= Sim.GW or t.ty >= Sim.GH: return null
	var id: int = Sim.occ[Sim.tIdx(t.tx, t.ty)]
	var o = Sim.objById(id) if id > 0 else null
	if not o: return null
	if o.type == 'range': Sim.selRangeId = o.id
	if ['putt', 'short', 'academy', 'shortc', 'hut', 'lot'].has(o.type): facFocus = 'obj:%s' % o.id; return 'hours'
	return 'range' if o.type == 'range' else ('club' if o.type == 'club' else 'place')
func handleAt(sp: Vector2):
	if not Sim.designing: return null
	var cam := view.cam
	if Sim.dTool == 'adjust' and Sim.selFeat != null:
		for f in Sim.draft.feats:
			if f.id == Sim.selFeat:
				if Vector2((f.x - cam.x) * cam.s, (f.y - cam.y) * cam.s).distance_to(sp) < max(22.0, Sim.FEATS[f.type].rx * cam.s): return 'feat'
		return null
	if Sim.dTool != 'hole' or not Sim.draft.holes[Sim.selHole].get("placed"): return null
	var h = Sim.draft.holes[Sim.selHole]
	for k in ['green', 'tee', 'bend']:
		var p = h[k]
		if Vector2((p.x - cam.x) * cam.s, (p.y - cam.y) * cam.s).distance_to(sp) < 20: return k
	return null
func inspect(e) -> void:
	insp = e; camFollow = false
	inspector.show_for(e)
	Sim.sfx('select')
func closeInspector() -> void:
	insp = null; camFollow = false
	if inspector: inspector.hide_panel()

# =====================================================================================
# Build tools: place, path, remove, move, demolish, buy land, landscaping, suggested paths
# =====================================================================================
func setTool(t) -> void:
	tool = t; ghostT = null
	if t != null and t.kind == 'place' and hoverWorld != null: ghostT = ghostAt(hoverWorld.x, hoverWorld.y)
	hud.paintBuildBar()
	if sheetOpen: sheet.refresh()
func ghostAt(wx: float, wy: float):
	if tool == null or tool.kind != 'place': return null
	var D = Sim.OBJ[tool.type]
	var o = Sim.objById(tool.moveId) if tool.get("moveId") else null
	var f := Sim.fp(o) if o else Sim.fp({ "type": tool.type, "x": 0, "y": 0 })
	var tx := roundi(wx / Sim.TILE - f.w / 2.0)
	var ty := roundi(wy / Sim.TILE - f.h / 2.0)
	if D.get("road"): ty = Sim.LAND_ROWS - f.h
	var r := Sim.canPlace(tool.type, tx, ty, o)
	r.tx = tx; r.ty = ty
	return r
func commitGhost() -> void:
	if tool == null or tool.kind != 'place' or ghostT == null: return
	var o = Sim.objById(tool.moveId) if tool.get("moveId") else null
	var r: Dictionary = Sim.moveObj(o, ghostT.tx, ghostT.ty) if o else Sim.placeObj(tool.type, ghostT.tx, ghostT.ty)
	if not r.ok: tool.msg = r.why; tool.bad = true; Sim.sfx('soft'); hud.paintBuildBar(); return
	var D = Sim.OBJ[tool.type]
	var placed = o if o else Sim.S.world.objs[Sim.S.world.objs.size() - 1]
	var need = null
	if not D.get("free"):
		for n in Sim.needsPath():
			if n.get("o") != null and is_same(n.o, placed): need = n; break
	var msg := "Here's a suggested footpath to its door. Build it, or lay your own." if need else ('Moved. It is still connected.' if o else ('Ready.' if D.get("free") else ('Golfers walk on from its exit, the square above it. Run paths from there.' if D.get("road") else 'Golfers can already reach it.')))
	Sim.toast('Moved' if o else 'Built', D.label, msg, '⚒')
	if need: setTool(null); offerPath(need); Sim.save(); return
	if D.get("decor") or D.get("road"): tool.msg = ''; tool.bad = false; ghostT = null; hud.paintBuildBar()
	else: setTool(null)
	sheet.refresh(); Sim.save()
func buildTap(wx: float, wy: float) -> void:
	if tool == null: return
	var c := Sim.tileOf(wx, wy)
	tool.msg = ''; tool.bad = false
	if Sim.TERRA.has(tool.kind):
		tool.hw = Vector2(wx, wy); Sim.terraBrush(tool.kind, wx, wy)
		var r = Sim.endTerraStroke(); tool.msg = r.msg; tool.bad = r.bad
		hud.paintBuildBar(); sheet.refresh(); return
	match tool.kind:
		'place':
			ghostT = ghostAt(wx, wy); commitGhost(); return
		'path', 'unpath':
			var ok: bool = Sim.paintPath(c.tx, c.ty, tool.kind == 'path')
			if ok: Sim.sfx('tap')
			elif tool.kind == 'path':
				var o: int = Sim.occ[Sim.tIdx(c.tx, c.ty)] if (c.tx >= 0 and c.ty >= 0 and c.tx < Sim.GW and c.ty < Sim.GH) else 0
				tool.msg = "You don't own this land." if not Sim.ownsTile(c.tx, c.ty) else ('Something is built here.' if (o and o != -2) else ('Not enough cash.' if Sim.S.money < (Sim.BRIDGE_COST if o == -2 else Sim.PATH_COST) else ''))
				tool.bad = tool.msg != ''
		'move':
			var id: int = Sim.occ[Sim.tIdx(c.tx, c.ty)]
			var o = Sim.objById(id) if id > 0 else null
			if o and o.type != 'lot':
				setTool({ "kind": 'place', "type": o.type, "moveId": o.id }); ghostT = ghostAt(wx, wy); hud.paintBuildBar(); return
			tool.msg = 'Car parks have to stay on the road: demolish and rebuild instead.' if o else 'Tap a building to move it.'; tool.bad = o != null
		'erase':
			var id: int = Sim.occ[Sim.tIdx(c.tx, c.ty)]
			if id > 0:
				var r: Dictionary = Sim.removeObj(Sim.objById(id))
				if not r.ok: tool.msg = r.why; tool.bad = true
				else: tool.msg = 'Demolished.'
			elif Sim.isPath[Sim.tIdx(c.tx, c.ty)]: Sim.paintPath(c.tx, c.ty, false)
		'land':
			var p = Sim.parcelAt(wx, wy); tool.plot = p.id if p else null; Sim.sfx('tap')
	hud.paintBuildBar(); sheet.refresh()
func buildDrag(wx: float, wy: float) -> void:
	if tool == null: return
	if Sim.TERRA.has(tool.kind): tool.hw = Vector2(wx, wy); Sim.terraBrush(tool.kind, wx, wy); return
	if tool.kind != 'path' and tool.kind != 'unpath': return
	var c := Sim.tileOf(wx, wy)
	if Sim.paintPath(c.tx, c.ty, tool.kind == 'path'): Sim.sfx('tap')
func buildHover(wx: float, wy: float) -> void:
	if tool == null: return
	if tool.kind == 'place': ghostT = ghostAt(wx, wy)
	tool.hover = Sim.tileOf(wx, wy)
	if Sim.TERRA.has(tool.kind): tool.hw = Vector2(wx, wy)
func offerPath(need) -> bool:
	var r := Sim.suggestFor(need)
	if r.has("fail"): Sim.toast('Footpath', "Can't reach the %s" % need.label, r.fail, '!'); return false
	if r.tiles.is_empty(): return false
	setTool({ "kind": 'suggest', "tiles": r.tiles, "cost": r.cost, "label": need.label, "need": need })
	var x0 := 1e9; var x1 := -1e9; var y0 := 1e9; var y1 := -1e9
	for i in r.tiles:
		x0 = min(x0, i % Sim.GW); x1 = max(x1, i % Sim.GW); y0 = min(y0, i / Sim.GW); y1 = max(y1, i / Sim.GW)
	glideTo((x0 + x1 + 1) / 2 * Sim.TILE, (y0 + y1 + 1) / 2 * Sim.TILE)
	return true
func offerNextPath(quiet: bool) -> bool:
	for need in Sim.needsPath():
		if offerPath(need): return true
	if not quiet: Sim.toast('Footpaths', 'Everything is connected', 'Golfers can reach every building from your car parks.', '✓')
	return false
func buildSuggested() -> void:
	if tool == null or tool.kind != 'suggest': return
	var r: Dictionary = Sim.buildPathTiles(tool.tiles, tool.label)
	if not r.ok: tool.msg = r.msg; tool.bad = true; hud.paintBuildBar(); return
	setTool(null); sheet.refresh()
	get_tree().create_timer(0.4).timeout.connect(func(): offerNextPath(true))

# =====================================================================================
# Title, away earnings
# =====================================================================================
func openTitle(pane := 'main') -> void:
	Sim.atTitle = true
	if sheetOpen: closePanel()
	closeInspector(); setTool(null)
	Sim.setSpeed(0)
	dialogs.openTitle(pane)
	measurePads()
func closeTitle() -> void:
	Sim.atTitle = false
	dialogs.closeTitle()
	Sim.setSpeed(1)
	measurePads(); view.clampCam()
func startNewGame(name: String) -> void:
	var nm := name.strip_edges().substr(0, 32)
	if nm == '': nm = 'Pine Hollow Golf Club'
	Sim.startScenario(scenPick, 'normal' if scenPick == 'sandbox' else diffPick, nm)
	closeTitle(); recenter()
## while you were away: half the usual rate for up to 8 hours
func _checkAway() -> void:
	var last: float = Sim.S.get("lastSave", 0.0)
	var secs: float = Time.get_unix_time_from_system() - last
	if last <= 0 or secs < 30 or Sim.S.get("lastRate", 0.0) <= 0: return
	var s: float = min(secs, 8 * 3600)
	var amt: float = Sim.S.lastRate * s * 0.5
	dialogs.showAway(amt, "You were gone for %s. Your staff earned half your usual rate%s." % [Sim.fmtDur(s), ', for up to 8 hours' if secs > 8 * 3600 else ''])
