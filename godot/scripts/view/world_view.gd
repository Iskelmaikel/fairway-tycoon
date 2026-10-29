class_name WorldView
extends Node2D
## The park, drawn. This is the whole "view" side of the game: it only reads the simulation
## (the Sim autoload) and never changes it, so it can be swapped for a different renderer.
##
## Layers, bottom to top. Static layers are re-drawn only when something they show changes;
## Godot keeps their draw lists, so they cost almost nothing per frame.
##   ground   (static)   woodland, grass stripes, rough and fairways
##   shade    (shader)   hillshade from the height map
##   water    (shader)   ponds and lakes from the water field
##   waterFx  (frame)    glints, reeds, ducks
##   ground2  (static)   bunkers, greens, tees, roads, paths, buildings, interiors
##   dyn      (frame)    everyone and everything that moves, roofs over them
##   trees    (static)   trees and tree clumps
##   top      (frame)    birds, land, build and design overlays, clouds, night, moods
##   glow     (frame)    floodlights, windows and headlights, blended additively
##   screen   (frame)    fog, heat haze, rain and speech: screen space

const ART := Art.ART
var game          # the controller: tools, selection, open windows (may be null)
var art: Art
var cam := { "x": 0.0, "y": 0.0, "s": 1.0 }
var padTop := 0.0
var padBot := 0.0
var padRight := 0.0
var camera: Camera2D
var L := {}       # name -> Layer
var screenLayer: CanvasLayer
var screenNode: Layer
var t := 0.0      # animation time (follows game time, so pausing freezes the park)
var _dt := 0.0
var _sig := ''
var _sigT := 0.0
var _treeSig := ''
var stripeTex: ImageTexture
var shadeTex: ImageTexture
var waterTex: ImageTexture
var _terVer := -1
var _waterVer := -1
var bubbles: Array = []
var speech: Array = []
var confetti: Array = []
var shots: Array = []
var roofA := {}
var shoreCache: Array = []

class Layer extends Node2D:
	var fn: Callable
	var ctx := Ctx2D.new()
	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		ctx.bind(self)
		fn.call(ctx)
		var t1 := Time.get_ticks_usec()
		ctx.flush()
		Sim.prof(fn.get_method(), t1 - t0)
		Sim.prof('flush', Time.get_ticks_usec() - t1)

func _ready() -> void:
	art = Art.new(Ctx2D.new())
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(camera)
	camera.make_current()
	for nm in ['ground', 'shade', 'water', 'waterFx', 'ground2', 'dyn', 'trees', 'top', 'glow']:
		var ly := Layer.new()
		ly.name = nm
		ly.fn = Callable(self, "_draw_" + nm)
		ly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(ly)
		L[nm] = ly
	var add := CanvasItemMaterial.new(); add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	L.glow.material = add
	_makeStripe()
	_setupShaders()
	screenLayer = CanvasLayer.new(); screenLayer.layer = 1
	add_child(screenLayer)
	screenNode = Layer.new(); screenNode.fn = _draw_screen
	screenLayer.add_child(screenNode)
	Sim.world_changed.connect(_dirtyAll)
	Sim.design_changed.connect(_dirtyAll)
	Sim.terrain_changed.connect(_dirtyAll)
	Sim.trees_changed.connect(func(): L.trees.queue_redraw())
	Sim.emoted.connect(_onEmote)
	Sim.confetti_burst.connect(_onConfetti)
	_dirtyAll()

func _dirtyAll() -> void:
	for nm in ['ground', 'ground2', 'trees']: L[nm].queue_redraw()
	_sig = ''

# ---------- camera ----------
func SW() -> float: return get_viewport_rect().size.x
func SH() -> float: return get_viewport_rect().size.y
func toWorld(sx: float, sy: float) -> Vector2: return Vector2(cam.x + sx / cam.s, cam.y + sy / cam.s)
func toScreen(wx: float, wy: float) -> Vector2: return Vector2((wx - cam.x) * cam.s, (wy - cam.y) * cam.s)
func viewRect() -> Rect2: return Rect2(cam.x, cam.y, SW() / cam.s, SH() / cam.s)
func onScreen(x: float, y: float) -> bool:
	var v := viewRect().grow(20)
	return v.has_point(Vector2(x, y))
func clampCam() -> void:
	var vw = SW() / cam.s
	var vh = SH() / cam.s
	var m := 40.0
	var pr = padRight / cam.s
	if vw - pr >= Sim.W + 2 * m: cam.x = (Sim.W - (vw - pr)) / 2
	else: cam.x = clampf(cam.x, -m, Sim.W - vw + pr + m)
	var minY = -padTop / cam.s - m
	var maxY = Sim.H - vh + padBot / cam.s + m
	if maxY <= minY: cam.y = (minY + maxY) / 2
	else: cam.y = clampf(cam.y, minY, maxY)
func centerOn(wx: float, wy: float) -> void:
	var visH := SH() - padTop - padBot
	cam.x = wx - (SW() - padRight) / 2 / cam.s; cam.y = wy - (padTop + visH / 2) / cam.s
	clampCam()
func minZoom() -> float: return max(0.32, min(SW() / (Sim.W + 80), SH() / (Sim.H + 80)) * 0.98)
func zoomAt(sx: float, sy: float, f: float) -> void:
	var w := toWorld(sx, sy)
	cam.s = clampf(cam.s * f, minZoom(), 4.0)
	cam.x = w.x - sx / cam.s; cam.y = w.y - sy / cam.s
	clampCam()
func homePt() -> Vector2:
	var c = Sim.objOf('club') if Sim.S.get("world") else null
	if c: return Vector2(c.x * Sim.TILE + 210, c.y * Sim.TILE + 60)
	var own := Sim.PARCELS.filter(func(p): return Sim.S.world.land.has(p.id)) if Sim.S.get("world") else []
	if own.is_empty(): return Vector2(Sim.W / 2, Sim.H / 2)
	var x0 := INF; var x1 := -INF; var y0 := INF; var y1 := -INF
	for p in own: x0 = min(x0, p.x0); x1 = max(x1, p.x1); y0 = min(y0, p.y0); y1 = max(y1, p.y1)
	return Vector2((x0 + x1) / 2, y1 - 300) if own.size() > 40 else Vector2((x0 + x1) / 2, (y0 + y1) / 2)
func goHome() -> void:
	cam.s = clampf(1.0, minZoom(), 4.0)
	var h := homePt(); centerOn(h.x, h.y)

# ---------- per frame ----------
func step(dt: float, gameDt: float) -> void:
	_dt = gameDt
	t += gameDt
	art.simTime = t
	art.camS = cam.s
	art.tickCache()
	camera.position = Vector2(cam.x, cam.y)
	camera.zoom = Vector2(cam.s, cam.s)
	# static layers: redraw when what they show has changed
	_sigT -= dt
	if _sigT <= 0:
		_sigT = 0.4
		var s := _staticSig()
		if s != _sig: _sig = s; L.ground.queue_redraw(); L.ground2.queue_redraw()
		var ts := "%s|%d|%d" % [Sim.designing, Sim.draftClear.size(), Sim.trees.size()]
		if ts != _treeSig: _treeSig = ts; L.trees.queue_redraw()
	if Sim.TER.ver != _terVer: _updateShade()
	if Sim.waterField().ver != _waterVer: _updateWater()
	for nm in ['waterFx', 'dyn', 'top', 'glow']: L[nm].queue_redraw()
	screenNode.queue_redraw()
## everything the static layers depend on, as a short string
func _staticSig() -> String:
	var turf := ''
	if Sim.S.get("turf"):
		for v in Sim.S.turf: turf += str(int(v / 10))
	var open := ''
	for i in 18: open += '1' if Sim.holeOpen(i) else '0'
	var sel := ''
	if game: sel = "%s|%s" % [game.get("sheetTab"), Sim.selHole]
	return "%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s" % [Sim.S.lvl, Sim.S.staff, turf, open, Sim.S.get("fac"), Sim.designing, Sim.S.world.objs.size() if Sim.S.get("world") else 0,
		Sim.S.world.paths.size() if Sim.S.get("world") else 0, sel, Sim.clubName(), Sim.facOpen('course')] + str(Sim.S.get("design", {}).get("teeSets", [])) + str(Sim.S.get("sup", {}).get("food", 0) > 0)

# =====================================================================================
# Ground: textures and shaders
# =====================================================================================
func _makeStripe() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var g := Ctx2D.col(ART.grass)
	var hi := g.lerp(Color(1, 0.98, 0.84), 0.06)
	for y in 64:
		for x in 64:
			# mowing stripes running diagonally, as on the web version
			var on := (x - y >= 0 and x - y < 32) or (y - x > 32)
			img.set_pixel(x, y, hi if on else g)
	stripeTex = ImageTexture.create_from_image(img)

const SHADE_SHADER := """
shader_type canvas_item;
uniform sampler2D hmap : filter_linear, repeat_disable;
uniform vec2 grid;      // tiles across, down
uniform float tile;
varying vec2 wpos;
void vertex() { wpos = VERTEX; }
float h(vec2 p) { return texture(hmap, (p / tile) / grid).r; }
void fragment() {
	float d = tile / 4.0;
	float l = h(wpos - vec2(d, 0.0)), r = h(wpos + vec2(d, 0.0)), u = h(wpos - vec2(0.0, d)), dn = h(wpos + vec2(0.0, d));
	float slope = ((l - r) + (u - dn)) * 0.55;
	float lift = (h(wpos) - 0.5) * 0.018;
	float b = slope + lift;
	b = b > 0.0 ? min(0.2, b * 0.7) : max(-0.4, b);
	COLOR = b >= 0.0 ? vec4(1.0, 0.965, 0.784, b) : vec4(0.118, 0.173, 0.055, -b);
}
"""
const WATER_SHADER := """
shader_type canvas_item;
uniform sampler2D field : filter_linear, repeat_disable;
uniform vec2 size;          // samples across, down
uniform float spacing;      // world units between samples
uniform vec4 bank : source_color;
uniform vec4 lip : source_color;
uniform vec4 deep : source_color;
uniform vec4 shallow : source_color;
uniform vec4 rim : source_color;
varying vec2 wpos;
void vertex() { wpos = VERTEX; }
float f(vec2 p) { return texture(field, (p / spacing + 0.5) / size).r; }
void fragment() {
	float v = f(wpos);
	float e = spacing * 0.5;
	vec2 g = vec2(f(wpos + vec2(e, 0.0)) - f(wpos - vec2(e, 0.0)), f(wpos + vec2(0.0, e)) - f(wpos - vec2(0.0, e))) / (2.0 * e);
	float d = (v - 0.5) / max(length(g), 0.002);   // signed distance to the shoreline, + inside
	float aa = max(fwidth(d), 0.001);
	vec4 c = vec4(0.0);
	// outside: a grassy bank with a sandy lip
	float bankA = smoothstep(-4.5 - aa, -4.5 + aa, d);
	c = mix(c, bank, bankA);
	c = mix(c, vec4(mix(c.rgb, lip.rgb, lip.a), c.a), smoothstep(-2.5 - aa, -2.5 + aa, d));
	// inside: a dark rim, the water band, the lighter open water
	float inside = smoothstep(-aa, aa, d);
	vec3 w = mix(deep.rgb, shallow.rgb, smoothstep(7.0 - aa, 7.0 + aa, d));
	w = mix(mix(w, rim.rgb, rim.a), w, smoothstep(2.5 - aa, 2.5 + aa, d));
	c = mix(c, vec4(w, 1.0), inside);
	if (v < 0.05) c.a = 0.0;
	COLOR = c;
}
"""
var shadeMat: ShaderMaterial
var waterMat: ShaderMaterial
func _setupShaders() -> void:
	var sh := Shader.new(); sh.code = SHADE_SHADER
	shadeMat = ShaderMaterial.new(); shadeMat.shader = sh
	L.shade.material = shadeMat
	var ws := Shader.new(); ws.code = WATER_SHADER
	waterMat = ShaderMaterial.new(); waterMat.shader = ws
	waterMat.set_shader_parameter("bank", Ctx2D.col(ART.bank))
	waterMat.set_shader_parameter("lip", Color(160 / 255.0, 140 / 255.0, 90 / 255.0, 0.55))
	waterMat.set_shader_parameter("deep", Ctx2D.col(ART.water))
	waterMat.set_shader_parameter("shallow", Ctx2D.col(ART.waterHi))
	waterMat.set_shader_parameter("rim", Color(40 / 255.0, 95 / 255.0, 130 / 255.0, 0.55))
	L.water.material = waterMat
func _updateShade() -> void:
	_terVer = Sim.TER.ver
	var GW: int = Sim.GW
	var GHt: int = Sim.LAND_ROWS
	# heights in metres at tile centres, softened once
	var hv := PackedFloat32Array(); hv.resize(GW * GHt)
	for i in GW * GHt: hv[i] = Sim.TER.h[i] * Sim.H_STEP
	var tmp := hv.duplicate()
	for y in GHt:
		for x in GW:
			var a := hv[y * GW + x] * 0.5
			a += hv[y * GW + max(0, x - 1)] * 0.25 + hv[y * GW + min(GW - 1, x + 1)] * 0.25
			tmp[y * GW + x] = a
	for y in GHt:
		for x in GW:
			hv[y * GW + x] = tmp[y * GW + x] * 0.5 + tmp[max(0, y - 1) * GW + x] * 0.25 + tmp[min(GHt - 1, y + 1) * GW + x] * 0.25
	var img := Image.create_from_data(GW, GHt, false, Image.FORMAT_RF, hv.to_byte_array())
	if shadeTex and shadeTex.get_size() == Vector2(GW, GHt): shadeTex.update(img)
	else: shadeTex = ImageTexture.create_from_image(img)
	shadeMat.set_shader_parameter("hmap", shadeTex)
	shadeMat.set_shader_parameter("grid", Vector2(GW, GHt))
	shadeMat.set_shader_parameter("tile", float(Sim.TILE))
	L.shade.queue_redraw()
func _updateWater() -> void:
	var wf := Sim.waterField()
	_waterVer = wf.ver
	var img := Image.create_from_data(wf.NX, wf.NY, false, Image.FORMAT_RF, wf.v.to_byte_array())
	waterTex = ImageTexture.create_from_image(img)
	waterMat.set_shader_parameter("field", waterTex)
	waterMat.set_shader_parameter("size", Vector2(wf.NX, wf.NY))
	waterMat.set_shader_parameter("spacing", float(Sim.TILE) / Sim.WQ)
	art.ducks = null
	# points along the shore, for reeds
	shoreCache = []
	if wf.any:
		var s: float = float(Sim.TILE) / Sim.WQ
		var v: PackedFloat32Array = wf.v
		var NX: int = wf.NX
		for y in wf.NY - 1:
			for x in NX - 1:
				var a := v[y * NX + x]
				var b := v[y * NX + x + 1]
				if (a >= 0.5) != (b >= 0.5) and (x + y) % 3 == 0:
					var k := (0.5 - a) / (b - a)
					shoreCache.append(Vector2((x + k) * s, y * s))
	L.water.queue_redraw()

func _draw_shade(ctx: Ctx2D) -> void:
	if shadeTex == null: return
	ctx.flush()
	ctx.ci.draw_rect(Rect2(0, 0, Sim.GW * Sim.TILE, Sim.LAND_ROWS * Sim.TILE), Color.WHITE)
func _draw_water(ctx: Ctx2D) -> void:
	if waterTex == null or not Sim.WF.any: return
	var winter: bool = Sim.season() == 'winter' and Sim.S.wx != 'sunny' and Sim.hour() < 10
	waterMat.set_shader_parameter("shallow", Ctx2D.col('#a9cadb' if winter else ART.waterHi))
	waterMat.set_shader_parameter("deep", Ctx2D.col('#87aec4' if winter else ART.water))
	var wf: Dictionary = Sim.WF
	var s: float = float(Sim.TILE) / Sim.WQ
	ctx.ci.draw_rect(Rect2(-10, -10, (wf.NX - 1) * s + 20, (wf.NY - 1) * s + 20), Color.WHITE)

# =====================================================================================
# Shared helpers
# =====================================================================================
func _setV(r: Rect2) -> void: art.V = r
func vis(x0: float, y0: float, x1: float, y1: float) -> bool: return art.vis(x0, y0, x1, y1)
func tint(h, k: float) -> Color: return Art.tint(h, k)
func strokeHole(ctx: Ctx2D, i: int, t0: float, t1: float, width: float, color, dash = null) -> void:
	ctx.strokeStyle = color; ctx.lineWidth = width; ctx.lineCap = 'round'; ctx.lineJoin = 'round'
	if dash: ctx.setLineDash(dash)
	ctx.beginPath()
	for k in 25:
		var p: Vector2 = Sim.hPt(i, t0 + (t1 - t0) * k / 24.0)
		if k: ctx.lineTo(p.x, p.y)
		else: ctx.moveTo(p.x, p.y)
	ctx.stroke()
	if dash: ctx.setLineDash([])
	ctx.lineCap = 'butt'; ctx.lineJoin = 'miter'
func holeBox(i: int) -> Array:
	var h = Sim.G.corr[i]
	var m := 120.0
	return [min(h.a.x, h.b.x, h.c.x) - m, min(h.a.y, h.b.y, h.c.y) - m, max(h.a.x, h.b.x, h.c.x) + m, max(h.a.y, h.b.y, h.c.y) + m]
func shownHoles() -> Array:
	var out := []
	if Sim.G == null: return out
	for i in min(18, Sim.G.corr.size()):
		var b := holeBox(i)
		if vis(b[0], b[1], b[2], b[3]): out.append(i)
	return out
func _withDraft(fn: Callable):
	if Sim.designing and Sim.draftGeo: return Sim.withGeo(Sim.draftGeo, fn)
	return fn.call()

# =====================================================================================
# Static: ground
# =====================================================================================
func _draw_ground(ctx: Ctx2D) -> void:
	art.ctx = ctx; _setV(Rect2(-200, -200, Sim.W + 400, Sim.H + 400))
	ctx.fillStyle = ART.wood; ctx.fillRect(-3000, -3000, Sim.W + 6000, Sim.H + 6000)
	ctx.fillStyle = 'rgba(36,50,20,0.39)'; ctx.fillRect(-4, -4, Sim.W + 8, Sim.H + 10)
	ctx.flush()
	ctx.ci.draw_texture_rect(stripeTex, Rect2(0, 0, Sim.W, Sim.H), true)
	_withDraft(func():
		for i in shownHoles(): drawHole(ctx, i, 'base'))

func drawHole(ctx: Ctx2D, i: int, layer: String) -> void:
	var built := Sim.holeOpen(i)
	var par := Sim.parOf(i)
	var tn: Vector2 = Sim.hTan(i, 1)
	var ang := atan2(tn.y, tn.x)
	if not built:
		if layer != 'base' or not Sim.designing or not Sim.G.corr[i].get("placed"): return
		ctx.globalAlpha = 0.45; strokeHole(ctx, i, -0.02, 1.1, 92, ART.rough); strokeHole(ctx, i, 0.12, 0.94, 30, ART.fair); ctx.globalAlpha = 1
		var gp: Vector2 = Sim.hPt(i, 1)
		ctx.strokeStyle = 'rgba(255,255,255,0.7)'; ctx.setLineDash([4, 4]); ctx.lineWidth = 1.5; ctx.beginPath(); ctx.ellipse(gp.x, gp.y, Sim.greenR(i), Sim.greenR(i) - 2, ang, 0, TAU); ctx.stroke(); ctx.setLineDash([])
		var m: Vector2 = Sim.hPt(i, 0.5)
		ctx.fillStyle = 'rgba(255,255,255,0.85)'; ctx.font = '800 13px'; ctx.textAlign = 'center'
		ctx.fillText("Hole %d (planned)" % (i + 1), m.x, m.y + 4)
		return
	var turf: float = Sim.turfOf(i)
	if layer == 'base':
		strokeHole(ctx, i, -0.02, 1.1, 96, ART.rough)
		var f0 := 0.55 if par == 3 else 0.12
		strokeHole(ctx, i, f0, 0.94, 35, tint(ART.fair, -0.16))
		strokeHole(ctx, i, f0, 0.94, 32, ART.fair)
		strokeHole(ctx, i, f0, 0.94, 32, 'rgba(255,250,215,0.12)', [12, 12])
		if turf < 90: strokeHole(ctx, i, f0, 0.94, 32, Color(150 / 255.0, 120 / 255.0, 50 / 255.0, (90 - turf) / 90 * 0.6))
		return
	var gp: Vector2 = Sim.hPt(i, 1)
	var gr: float = Sim.greenR(i)
	ctx.fillStyle = ART.SH; ctx.beginPath(); ctx.ellipse(gp.x + 2, gp.y + 2.5, gr + 4, gr + 2, ang, 0, TAU); ctx.fill()
	ctx.beginPath(); ctx.ellipse(gp.x, gp.y, gr + 4, gr + 2, ang, 0, TAU); art.inkFill(ART.fringe, 0.5)
	ctx.fillStyle = '#c9c47e' if turf < 50 else ('#b9d27c' if turf < 75 else ART.green); ctx.beginPath(); ctx.ellipse(gp.x, gp.y, gr, gr - 2, ang, 0, TAU); ctx.fill()
	ctx.fillStyle = ART.greenHi; ctx.beginPath(); ctx.ellipse(gp.x - 3, gp.y - 3, gr * 0.5, gr * 0.32, ang, 0, TAU); ctx.fill()
	ctx.fillStyle = ART.ink; ctx.beginPath(); ctx.arc(gp.x + 2, gp.y + 1, 1.6, 0, TAU); ctx.fill()
	var tp: Vector2 = Sim.teePos(i)
	var tt: Vector2 = Sim.hTan(i, 0)
	ctx.save(); ctx.translate(tp.x, tp.y); ctx.rotate(atan2(tt.y, tt.x))
	ctx.fillStyle = ART.SH; ctx.fillRect(-8, -6, 18, 15)
	ctx.beginPath(); ctx.rect(-10, -8, 18, 15); art.inkFill(ART.tee, 0.5)
	ctx.fillStyle = ART.gold; ctx.fillRect(4, -5, 2.5, 2.5); ctx.fillRect(4, 3, 2.5, 2.5)
	ctx.restore()
	drawTeeMarkers(ctx, i)
	var sp: Vector2 = Sim.signPos(i)
	var selected: bool = game != null and game.get("sheetTab") == 'course' and Sim.selHole == i
	ctx.fillStyle = ART.SH; ctx.beginPath(); ctx.arc(sp.x + 2, sp.y + 2.5, 9, 0, TAU); ctx.fill()
	ctx.beginPath(); ctx.arc(sp.x, sp.y, 8.5, 0, TAU); art.inkFill(ART.gold if selected else ART.cream, 0.7)
	ctx.strokeStyle = tint(ART.timber, 0.1); ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(sp.x, sp.y, 6.5, 0, TAU); ctx.stroke()
	ctx.fillStyle = ART.ink; ctx.font = '800 10px'; ctx.textAlign = 'center'; ctx.fillText(str(i + 1), sp.x, sp.y + 3.5)
func drawTeeMarkers(ctx: Ctx2D, i: int) -> void:
	for k in Sim.teeSets():
		if k == 'yellow': continue
		var p: Vector2 = Sim.teePosFor(i, k)
		var tn: Vector2 = Sim.hTan(i, max(0.0, Sim.TEE[k].t))
		ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(atan2(tn.y, tn.x))
		ctx.fillStyle = ART.SH; ctx.fillRect(-4, -4, 12, 11)
		ctx.beginPath(); ctx.rect(-6, -6, 12, 11); art.inkFill(ART.tee, 0.5)
		ctx.fillStyle = Sim.TEE[k].color; ctx.fillRect(2, -4, 2.6, 2.6); ctx.fillRect(2, 2, 2.6, 2.6)
		ctx.restore()
func drawFeature(ctx: Ctx2D, f, layer: String) -> void:
	var F = Sim.FEATS[f.type]
	var top: bool = f.type == 'trees'
	if layer != 'all' and (layer == 'top') != top: return
	if not vis(f.x - F.rx - 20, f.y - F.ry - 20, f.x + F.rx + 20, f.y + F.ry + 20): return
	var rr := Sim.seeded(1000 + int(f.get("id", 0)) * 7)
	var rot: float = f.get("rot", 0.0) if f.get("rot") else 0.0
	if f.type == 'pond' or f.type == 'lake': art.water(f.x, f.y, F.rx, F.ry, rot)
	elif f.type == 'bunker': art.bunker(f.x, f.y, F.rx - 1, F.ry - 1, rot)
	elif f.type == 'waste':
		ctx.save(); ctx.translate(f.x, f.y); ctx.rotate(rot)
		ctx.beginPath(); ctx.ellipse(0, 0, F.rx, F.ry, 0, 0, TAU); art.inkFill(tint(ART.sand, -0.08), 0.5)
		ctx.fillStyle = ART.sand; ctx.beginPath(); ctx.ellipse(-2, -1, F.rx * 0.8, F.ry * 0.62, 0, 0, TAU); ctx.fill()
		ctx.strokeStyle = tint(ART.rough, -0.1); ctx.lineWidth = 1.4
		for k in 18:
			var a: float = rr.call() * TAU
			var d: float = rr.call() * 0.85
			var x = cos(a) * F.rx * d
			var y = sin(a) * F.ry * d
			ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + 2 - rr.call() * 4, y - 4); ctx.moveTo(x, y); ctx.lineTo(x + 1, y - 5); ctx.stroke()
		ctx.restore()
	elif f.type == 'flowers':
		ctx.beginPath(); ctx.arc(f.x, f.y, F.rx, 0, TAU); art.inkFill('#7a5236', 0.6)
		var cols := ['#f28ab0', '#ffd45c', '#fff6e0', '#c79bf2']
		for k in 24:
			var a: float = rr.call() * TAU
			var d: float = rr.call() * (F.rx - 2)
			ctx.fillStyle = cols[k % 4]; ctx.fillRect(f.x + cos(a) * d - 1.3, f.y + sin(a) * d - 1.3, 2.6, 2.6)
		for k in 3:
			var a: float = rr.call() * TAU
			ctx.fillStyle = ART.leafMid[0]; ctx.beginPath(); ctx.arc(f.x + cos(a) * (F.rx + 3), f.y + sin(a) * (F.rx + 3), 4, 0, TAU); ctx.fill()
	elif f.type == 'trees':
		var n := 4 + int(floor(rr.call() * 2))
		for k in n:
			var a: float = k / float(n) * TAU + rr.call()
			var d: float = 6 + rr.call() * 11
			var r: float = 8 + rr.call() * 5
			var s: float = rr.call()
			var kind := 'pine' if rr.call() > 0.75 else 'oak'
			art.paintTree({ "x": f.x + cos(a) * d, "y": f.y + sin(a) * d, "r": r, "s": s, "kind": kind })

# =====================================================================================
# Static: everything built on the ground
# =====================================================================================
func _draw_ground2(ctx: Ctx2D) -> void:
	art.ctx = ctx; _setV(Rect2(-200, -200, Sim.W + 400, Sim.H + 400))
	_withDraft(func():
		var feats: Array = Sim.G.feats if Sim.G else []
		for f in feats: drawFeature(ctx, f, 'ground')
		for i in shownHoles(): drawHole(ctx, i, 'top'))
	drawRoad(ctx); drawLots(ctx); drawWorldPaths(ctx); drawBridges(ctx)
	drawCartPaths(ctx)
	Sim.forRanges(func(_o): drawRangeStatic(ctx))
	drawAmenities(ctx)
	drawClosedSigns(ctx)
	drawClubhouse(ctx)
func drawRoad(ctx: Ctx2D) -> void:
	var W: float = Sim.W
	var RY: float = Sim.ROAD_Y
	ctx.fillStyle = tint(ART.path, -0.1); ctx.fillRect(-40, Sim.LAND_Y1 + 2, W + 80, 5)
	ctx.fillStyle = tint(ART.asphalt, -0.18); ctx.fillRect(-40, RY - 18, W + 80, 36)
	ctx.fillStyle = ART.asphalt; ctx.fillRect(-40, RY - 16, W + 80, 32)
	ctx.fillStyle = 'rgba(255,250,230,0.05)'; ctx.fillRect(-40, RY - 9, W + 80, 5); ctx.fillRect(-40, RY + 5, W + 80, 5)
	ctx.strokeStyle = 'rgba(239,230,204,0.75)'; ctx.lineWidth = 1.6; ctx.setLineDash([12, 14])
	ctx.beginPath(); ctx.moveTo(-40, RY); ctx.lineTo(W + 40, RY); ctx.stroke(); ctx.setLineDash([])
func drawLots(ctx: Ctx2D) -> void:
	for o in Sim.objs():
		if o.type != 'lot': continue
		var px: float = o.x * Sim.TILE
		var py: float = o.y * Sim.TILE
		ctx.fillStyle = tint(ART.path, -0.1); ctx.fillRect(px - 3, py - 3, 166, 86)
		ctx.fillStyle = ART.asphalt; ctx.fillRect(px, py, 160, 80)
		ctx.fillStyle = ART.asphalt; ctx.fillRect(px + 66, py + 76, 28, Sim.ROAD_Y - py - 70)
		ctx.strokeStyle = 'rgba(239,230,204,0.75)'; ctx.lineWidth = 1.2
		for s in Sim.lotSpots(o):
			ctx.beginPath(); ctx.moveTo(s.x - 10, s.y - 13); ctx.lineTo(s.x - 10, s.y + 13); ctx.moveTo(s.x + 10, s.y - 13); ctx.lineTo(s.x + 10, s.y + 13); ctx.stroke()
		ctx.strokeStyle = 'rgba(240,232,200,0.5)'; ctx.setLineDash([8, 10]); ctx.beginPath(); ctx.moveTo(px + 6, py + 40); ctx.lineTo(px + 154, py + 40); ctx.stroke(); ctx.setLineDash([])
		ctx.fillStyle = ART.SH; ctx.fillRect(px + 150, py - 12, 11, 11); ctx.fillStyle = tint(ART.timber, -0.2); ctx.fillRect(px + 152, py - 6, 1.6, 6)
		ctx.beginPath(); ctx.rect(px + 147, py - 16, 10, 10); art.inkFill(ART.blue, 0.5)
		ctx.fillStyle = ART.cream; ctx.font = '800 8px'; ctx.textAlign = 'center'; ctx.fillText('P', px + 152, py - 8)
func drawWorldPaths(ctx: Ctx2D) -> void:
	if not Sim.S.get("world"): return
	var GW: int = Sim.GW
	var GH: int = Sim.GH
	var isPath: PackedByteArray = Sim.isPath
	for pass_ in [[ART.pathEdge, 0], [ART.path, 2]]:
		ctx.fillStyle = pass_[0]
		var p: int = pass_[1]
		for ty in GH:
			for tx in GW:
				if not isPath[ty * GW + tx]: continue
				var x := tx * 20.0
				var y := ty * 20.0
				ctx.fillRect(x + 3 + p, y + 3 + p, 14 - 2 * p, 14 - 2 * p)
				if tx > 0 and isPath[ty * GW + tx - 1]: ctx.fillRect(x, y + 3 + p, 4 + p, 14 - 2 * p)
				if tx < GW - 1 and isPath[ty * GW + tx + 1]: ctx.fillRect(x + 16 - p, y + 3 + p, 4 + p, 14 - 2 * p)
				if ty > 0 and isPath[(ty - 1) * GW + tx]: ctx.fillRect(x + 3 + p, y, 14 - 2 * p, 4 + p)
				if ty < GH - 1 and isPath[(ty + 1) * GW + tx]: ctx.fillRect(x + 3 + p, y + 16 - p, 14 - 2 * p, 4 + p)
func drawBridges(ctx: Ctx2D) -> void:
	if not Sim.S.get("world") or not Sim.WF.any: return
	var GW: int = Sim.GW
	var TILE: float = Sim.TILE
	var isPath: PackedByteArray = Sim.isPath
	for ty in Sim.LAND_ROWS:
		for tx in GW:
			var i: int = ty * GW + tx
			if not isPath[i] or not Sim.TER.w[i]: continue
			var x := tx * TILE
			var y := ty * TILE
			var horiz: bool = (isPath[ty * GW + max(0, tx - 1)] or isPath[ty * GW + min(GW - 1, tx + 1)]) and not (isPath[max(0, ty - 1) * GW + tx] or isPath[(ty + 1) * GW + tx])
			ctx.fillStyle = 'rgba(36,50,20,0.28)'; ctx.fillRect(x + 2, y + 4, TILE, TILE - 2)
			ctx.fillStyle = '#9a7448'; ctx.fillRect(x, y + 1, TILE, TILE - 2)
			ctx.fillStyle = '#7d5c36'
			for k in 5:
				if horiz: ctx.fillRect(x + k * 4, y + 1, 1, TILE - 2)
				else: ctx.fillRect(x, y + 1 + k * 4, TILE, 1)
			ctx.fillStyle = '#5b4126'
			if horiz: ctx.fillRect(x, y, TILE, 2); ctx.fillRect(x, y + TILE - 2, TILE, 2)
			else: ctx.fillRect(x, y, 2, TILE); ctx.fillRect(x + TILE - 2, y, 2, TILE)
func drawCartPaths(ctx: Ctx2D) -> void:
	if Sim.G == null: return
	ctx.strokeStyle = 'rgba(232,217,176,0.6)'; ctx.lineWidth = 4; ctx.setLineDash([10, 8]); ctx.lineCap = 'round'
	var seg := func(a: Vector2, b: Vector2): ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke()
	if Sim.holeOpen(0) and Sim.tee1Tile(): seg.call(Sim.NODES.TEE1, Sim.hOff(0, 0, -14))
	for i in 17:
		if not Sim.holeOpen(i) or not Sim.holeOpen(i + 1): continue
		seg.call(Sim.hOff(i, 1.06, 14), Sim.hOff(i + 1, 0, -14))
	ctx.setLineDash([]); ctx.lineCap = 'butt'
func drawRangeStatic(ctx: Ctx2D) -> void:
	var x1: float = Sim.rangeX1()
	var RX0: float = Sim.RX0
	var RY0: float = Sim.RY0
	var FY1: float = Sim.FIELD_Y1
	var TEE_Y: float = Sim.TEE_Y
	ctx.fillStyle = ART.SH; ctx.fillRect(RX0 + 3, RY0 + 3, x1 - RX0, FY1 - RY0 + 12)
	ctx.fillStyle = tint(ART.fair, -0.05); ctx.fillRect(RX0, RY0, x1 - RX0, FY1 - RY0 + 12)
	ctx.fillStyle = 'rgba(255,250,215,0.09)'
	var y := RY0
	while y < FY1: ctx.fillRect(RX0, y, x1 - RX0, 20); y += 40
	var YD_C := ['#e2553f', '#fbf3dc', '#f2c14e', '#3f6f9e', '#2b2a1f']
	var yds := [50, 100, 150, 200, 250]
	for k in yds.size():
		var yy := FY1 - (k + 1) * 52
		ctx.strokeStyle = 'rgba(251,243,220,0.3)'; ctx.lineWidth = 1.2; ctx.setLineDash([4, 8])
		ctx.beginPath(); ctx.moveTo(RX0 + 6, yy); ctx.lineTo(x1 - 6, yy); ctx.stroke(); ctx.setLineDash([])
		var x := RX0 + 90
		while x < x1 - 20:
			ctx.fillStyle = ART.SH; ctx.fillRect(x + 2, yy - 1, 2, 3)
			ctx.fillStyle = ART.cream; ctx.fillRect(x, yy - 13, 1.4, 13)
			ctx.fillStyle = YD_C[k]; ctx.beginPath(); ctx.moveTo(x + 1.4, yy - 13); ctx.lineTo(x + 8, yy - 10.5); ctx.lineTo(x + 1.4, yy - 8); ctx.fill()
			ctx.strokeStyle = tint('#c9b588' if YD_C[k] == ART.cream else YD_C[k], -0.3); ctx.lineWidth = 0.6; ctx.stroke()
			x += 150
		art.woodSign(RX0 + 24, yy - 8, str(yds[k]), 7)
	var nT: int = min(Sim.L('targets'), 6)
	for k in nT:
		var tx := RX0 + (x1 - RX0) * ((k + 0.7) / (nT + 0.4))
		var ty := FY1 - 80 - ((k * 97) % 180)
		ctx.fillStyle = ART.SH; ctx.beginPath(); ctx.ellipse(tx + 2, ty + 2.5, 26, 14, 0, 0, TAU); ctx.fill()
		ctx.beginPath(); ctx.ellipse(tx, ty, 26, 14, 0, 0, TAU); art.inkFill(ART.green, 0.5)
		ctx.fillStyle = ART.greenHi; ctx.beginPath(); ctx.ellipse(tx - 4, ty - 3, 13, 6, 0, 0, TAU); ctx.fill()
		ctx.strokeStyle = 'rgba(251,243,220,0.7)'; ctx.lineWidth = 1.2; ctx.beginPath(); ctx.ellipse(tx, ty, 16, 8.5, 0, 0, TAU); ctx.stroke()
		ctx.fillStyle = ART.cream; ctx.fillRect(tx, ty - 16, 1.6, 16); ctx.fillStyle = ART.gold; ctx.fillRect(tx + 1.6, ty - 16, 8, 5)
	ctx.strokeStyle = 'rgba(240,232,210,0.45)'; ctx.lineWidth = 1
	ctx.beginPath(); ctx.moveTo(RX0, TEE_Y); ctx.lineTo(RX0, RY0); ctx.lineTo(x1, RY0); ctx.lineTo(x1, TEE_Y); ctx.stroke()
	ctx.fillStyle = tint(ART.timber, -0.15)
	y = RY0
	while y < TEE_Y: ctx.fillRect(RX0 - 1.5, y - 1.5, 3, 3); ctx.fillRect(x1 - 1.5, y - 1.5, 3, 3); y += 46
	var xx := RX0
	while xx < x1: ctx.fillRect(xx - 1.5, RY0 - 1.5, 3, 3); xx += 46
	ctx.fillStyle = ART.SH; ctx.fillRect(RX0 + 3, FY1 + 12, x1 - RX0, 28)
	ctx.beginPath(); ctx.rect(RX0, FY1 + 8, x1 - RX0, 28); art.inkFill('#d8c79a', 0.5)
	ctx.fillStyle = 'rgba(255,250,230,0.25)'; ctx.fillRect(RX0, FY1 + 8, x1 - RX0, 3)
	for i in Sim.bays():
		var x: float = Sim.bayLeftX(i)
		ctx.beginPath(); ctx.rect(x + 2, TEE_Y - 6, Sim.BAY_W - 4, 15); art.inkFill('#5f9a4e', 0.4)
		ctx.fillStyle = ART.cream; ctx.fillRect(x + Sim.BAY_W / 2 - 1, TEE_Y - 3, 2, 2)
		ctx.fillStyle = ART.timber; ctx.fillRect(x, TEE_Y - 8, 1.6, 20)
	if Sim.L('covered'): art.hipRoof(RX0, TEE_Y + 11, x1 - RX0, 15, ART.slate, { "height": 0.6 })
	if Sim.L('lights'):
		var x := RX0
		while x <= x1:
			ctx.fillStyle = '#c9ced1'; ctx.fillRect(x - 2, RY0, 4, 12); ctx.fillStyle = '#eef1f2'; ctx.fillRect(x - 7, RY0 - 3, 14, 5)
			x += 220
		for px in [RX0, x1]: ctx.fillStyle = '#eef1f2'; ctx.fillRect(px - 5, (RY0 + TEE_Y) / 2 - 3, 10, 6)
	# the ball machines (their fill level is drawn with the moving things)
	for m in Sim.machines():
		var mp: Vector2 = Sim.machinePos(m)
		ctx.fillStyle = 'rgba(36,50,20,0.33)'; ctx.fillRect(mp.x - 4, mp.y - 9, 12, 20)
		ctx.fillStyle = '#5b6770'; ctx.fillRect(mp.x - 6, mp.y - 12, 12, 20)
		ctx.fillStyle = '#1b2228'; ctx.fillRect(mp.x - 4, mp.y - 10, 8, 9)
		ctx.fillStyle = '#e8432e'; ctx.fillRect(mp.x - 6, mp.y - 13, 12, 3)
		ctx.fillStyle = '#3a4248'; ctx.fillRect(mp.x - 2, mp.y + 6, 4, 4)

func drawAmenities(ctx: Ctx2D) -> void:
	var TILE: float = Sim.TILE
	for o in Sim.objs():
		var f := Sim.fp(o)
		var px: float = f.x * TILE
		var py: float = f.y * TILE
		var w: float = f.w * TILE
		var h: float = f.h * TILE
		if o.type == 'shortc': drawShortCourse(ctx, o); continue
		if o.type == 'putt' or o.type == 'short':
			ctx.fillStyle = ART.SH; ctx.beginPath(); ctx.ellipse(px + w / 2 + 2, py + h / 2 + 2.5, w / 2 - 2, h / 2 - 3, 0, 0, TAU); ctx.fill()
			ctx.beginPath(); ctx.ellipse(px + w / 2, py + h / 2, w / 2 - 2, h / 2 - 3, 0, 0, TAU); art.inkFill(ART.fringe, 0.5)
			ctx.fillStyle = ART.green; ctx.beginPath(); ctx.ellipse(px + w / 2, py + h / 2, w / 2 - 7, h / 2 - 7, 0, 0, TAU); ctx.fill()
			ctx.fillStyle = ART.greenHi; ctx.beginPath(); ctx.ellipse(px + w * 0.4, py + h * 0.38, w / 4, h / 6, 0, 0, TAU); ctx.fill()
			if o.type == 'short':
				art.bunker(px + w - 26, py + h - 20, 16, 9, 0.3)
				ctx.beginPath(); ctx.rect(px + 4, py + h - 16, 26, 10); art.inkFill('#5f9a4e', 0.4)
			var holes := [[0.25, 0.35], [0.7, 0.3], [0.55, 0.7], [0.3, 0.72]] if o.type == 'putt' else [[0.4, 0.4]]
			for ab in holes:
				var x: float = px + w * ab[0]
				var y: float = py + h * ab[1]
				ctx.fillStyle = ART.ink; ctx.beginPath(); ctx.arc(x, y, 1.8, 0, TAU); ctx.fill()
				ctx.fillStyle = ART.cream; ctx.fillRect(x, y - 10, 1.2, 10); ctx.fillStyle = ART.red if o.type == 'short' else ART.gold; ctx.fillRect(x + 1.2, y - 10, 5, 3)
		elif o.type == 'academy' or o.type == 'shed' or o.type == 'hut':
			ctx.fillStyle = ART.SH; ctx.fillRect(px + ART.SX, py + ART.SY, w - 2, h - 2)
			var wall: String = { "academy": '#e8dcc0', "shed": '#b9a684', "hut": '#f1e6cb' }[o.type]
			ctx.beginPath(); ctx.rect(px + 2, py + 2, w - 4, h - 4); art.inkFill(wall, 0.8)
			if o.type == 'academy':
				ctx.fillStyle = '#3e9d5a'
				for k in 3: ctx.fillRect(px + 6 + k * 18, py + 20, 14, 18)
				ctx.fillStyle = '#2b2f36'; ctx.fillRect(px + w - 14, py + 10, 10, 7)
			if o.type == 'shed': ctx.fillStyle = '#5b4a30'; ctx.fillRect(px + 10, py + h - 18, 22, 14); ctx.fillStyle = '#e8c547'; ctx.fillRect(px + w - 26, py + 14, 14, 12)
			if o.type == 'hut':
				for k in min(3, 1 + Sim.L('food')):
					ctx.fillStyle = '#e8432e' if k % 2 else '#f2c14e'; ctx.beginPath(); ctx.arc(px + 10 + k * 18, py + h - 8, 6, 0, TAU); ctx.fill()
		elif o.type == 'bench':
			ctx.fillStyle = ART.SH; ctx.fillRect(px + 5, py + 8, 14, 7); ctx.beginPath(); ctx.rect(px + 3, py + 5, 14, 7); art.inkFill(ART.timber, 0.5)
			ctx.fillStyle = tint(ART.timber, 0.15); ctx.fillRect(px + 3, py + 5, 14, 1.5); ctx.fillStyle = tint(ART.timber, -0.2); ctx.fillRect(px + 3, py + 8.5, 14, 0.8)
		elif o.type == 'bin':
			ctx.fillStyle = ART.SH; ctx.beginPath(); ctx.arc(px + 12, py + 12.5, 5, 0, TAU); ctx.fill()
			ctx.beginPath(); ctx.arc(px + 10, py + 10, 5, 0, TAU); art.inkFill('#4d6b45', 0.5)
			ctx.fillStyle = '#2b3a26'; ctx.beginPath(); ctx.arc(px + 10, py + 10, 3, 0, TAU); ctx.fill()
		elif o.type == 'flowers':
			ctx.beginPath(); ctx.rect(px + 2, py + 2, 16, 16); art.inkFill('#7a5236', 0.5)
			var cols := ['#f28ab0', '#ffd45c', '#fff6e0', '#c79bf2']
			var r := Sim.seeded(int(o.id) * 13 + 5)
			for k in 12: ctx.fillStyle = cols[k % 4]; ctx.fillRect(px + 3 + r.call() * 13, py + 3 + r.call() * 13, 2.4, 2.4)
		elif o.type == 'fountain':
			ctx.fillStyle = ART.SH; ctx.beginPath(); ctx.arc(px + 22, py + 22.5, 18, 0, TAU); ctx.fill()
			ctx.beginPath(); ctx.arc(px + 20, py + 20, 18, 0, TAU); art.inkFill('#d8cdb2', 0.6)
			art.water(px + 20, py + 20, 14, 14, 0)
			ctx.fillStyle = '#e6eef2'; ctx.beginPath(); ctx.arc(px + 20, py + 20, 3, 0, TAU); ctx.fill()
func drawShortCourse(ctx: Ctx2D, o) -> void:
	var TILE: float = Sim.TILE
	var px: float = o.x * TILE
	var py: float = o.y * TILE
	var w: float = Sim.OBJ.shortc.w * TILE
	var h: float = Sim.OBJ.shortc.h * TILE
	ctx.fillStyle = ART.rough; ctx.fillRect(px + 2, py + 2, w - 4, h - 4)
	ctx.strokeStyle = tint(ART.timber, -0.1); ctx.lineWidth = 1.5; ctx.strokeRect(px + 3, py + 3, w - 6, h - 6)
	var hs := Sim.shortcHoles(o)
	for k in hs.size():
		var hh = hs[k]
		ctx.strokeStyle = ART.fair; ctx.lineWidth = 22; ctx.lineCap = 'round'; ctx.beginPath(); ctx.moveTo(hh.tee.x, hh.tee.y); ctx.lineTo(hh.green.x, hh.green.y); ctx.stroke(); ctx.lineCap = 'butt'
		ctx.beginPath(); ctx.ellipse(hh.green.x, hh.green.y, 15, 12, 0, 0, TAU); art.inkFill(ART.fringe, 0.5)
		ctx.fillStyle = ART.green; ctx.beginPath(); ctx.ellipse(hh.green.x, hh.green.y, 12, 9, 0, 0, TAU); ctx.fill()
		if k % 2 == 0: art.bunker(hh.green.x + (-20 if hh.tee.x > hh.green.x else 20), hh.green.y + 8, 7, 4, 0.4)
		ctx.beginPath(); ctx.rect(hh.tee.x - 6, hh.tee.y - 5, 12, 10); art.inkFill(ART.tee, 0.5)
		ctx.fillStyle = ART.cream; ctx.fillRect(hh.green.x, hh.green.y - 14, 1.4, 14)
		ctx.fillStyle = ART.red; ctx.fillRect(hh.green.x + 1.4, hh.green.y - 14, 7, 4)
		ctx.fillStyle = ART.ink; ctx.font = '800 8px'; ctx.textAlign = 'center'; ctx.fillText(str(k + 1), hh.tee.x, hh.tee.y + 3)
	art.woodSign(px + w / 2, py + h - 10, 'Par-3 course', 7)
func closedSign(ctx: Ctx2D, x: float, y: float, text: String) -> void:
	var w := 6 + text.length() * 4.1
	ctx.fillStyle = 'rgba(36,50,20,0.28)'; ctx.fillRect(x - w / 2 + 1.5, y - 15 + 1.5, w, 9)
	ctx.fillStyle = '#5a4630'; ctx.fillRect(x - w / 2 + 2, y - 7, 1.4, 7); ctx.fillRect(x + w / 2 - 3.4, y - 7, 1.4, 7)
	ctx.fillStyle = '#c8322a'; ctx.fillRect(x - w / 2, y - 15, w, 9)
	ctx.fillStyle = '#fff'; ctx.font = '800 6.5px'; ctx.textAlign = 'center'; ctx.fillText(text, x, y - 8.4)
func drawClosedSigns(ctx: Ctx2D) -> void:
	var TILE: float = Sim.TILE
	for o in Sim.rangeObjs():
		if not Sim.facOpen('range:%s' % o.id):
			var d := Sim.doorOf(o)
			var p: Vector2 = Sim.tileC(d.tx, d.ty)
			closedSign(ctx, p.x, p.y, 'RANGE CLOSED')
	if Sim.courseHoles() > 0 and not Sim.facOpen('course'):
		var p: Vector2 = Sim.teePos(0)
		closedSign(ctx, p.x - 18, p.y + 16, 'COURSE CLOSED')
	for o in Sim.objs():
		if not ['putt', 'short', 'academy', 'shortc', 'hut', 'lot'].has(o.type) or Sim.facOpen('obj:%s' % o.id): continue
		var f := Sim.fp(o)
		closedSign(ctx, (f.x + f.w / 2.0) * TILE, (f.y + f.h) * TILE - 4, 'CLOSED')
	if Sim.hasObj('club'):
		for k in Sim.VENUE_FAC:
			var builtV: bool = true if k == 'shop' else (Sim.L('resto') > 0 if k == 'resto' else (Sim.L('barRoom') > 0 if k == 'bar' else (Sim.L('terrace') > 0 if k == 'terrace' else Sim.L('locker') > 0)))
			if not builtV or Sim.facOpen('venue:' + k): continue
			var r = Sim.ROOMS['lobby' if k == 'shop' else k]
			ctx.fillStyle = 'rgba(20,20,20,0.28)'; ctx.fillRect(r.x0 + Sim.CDX, r.y0 + Sim.CDY, r.x1 - r.x0, r.y1 - r.y0)
			closedSign(ctx, (r.x0 + r.x1) / 2 + Sim.CDX, (r.y0 + r.y1) / 2 + Sim.CDY + 6, Sim.VENUE_FAC[k].to_upper() + ' CLOSED')
## the clubhouse campus, drawn as an open floor plan so you can see people inside
func room(ctx: Ctx2D, r, floor, built: bool, wallsOpen := false) -> void:
	var w: float = r.x1 - r.x0
	var h: float = r.y1 - r.y0
	if not built:
		ctx.fillStyle = 'rgba(205,185,138,0.55)'; ctx.fillRect(r.x0 + 3, r.y0 + 3, w - 6, h - 6)
		ctx.strokeStyle = 'rgba(251,243,220,0.75)'; ctx.lineWidth = 0.8; ctx.strokeRect(r.x0 + 4, r.y0 + 4, w - 8, h - 8)
		ctx.fillStyle = ART.timber
		for p in [[r.x0 + 4, r.y0 + 4], [r.x1 - 4, r.y0 + 4], [r.x0 + 4, r.y1 - 4], [r.x1 - 4, r.y1 - 4]]: ctx.fillRect(p[0] - 1.5, p[1] - 1.5, 3, 3)
		art.woodSign((r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2, r.label, 6)
		return
	ctx.fillStyle = floor; ctx.fillRect(r.x0, r.y0, w, h)
	if not wallsOpen: ctx.strokeStyle = '#6b5440'; ctx.lineWidth = 3; ctx.strokeRect(r.x0, r.y0, w, h)
func table(ctx: Ctx2D, x: float, y: float, r: float, top) -> void:
	ctx.fillStyle = 'rgba(36,50,20,0.2)'; ctx.beginPath(); ctx.arc(x + 1.5, y + 1.5, r, 0, TAU); ctx.fill()
	ctx.fillStyle = top; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill()
func drawClubhouse(ctx: Ctx2D) -> void:
	if not Sim.hasObj('club'): return
	ctx.save(); ctx.translate(Sim.CDX, Sim.CDY)
	var R: Dictionary = Sim.ROOMS
	var reno: int = Sim.L('reno')
	ctx.beginPath(); ctx.rect(1120, 1430, 140, 34); art.inkFill(ART.path, 0.4)
	ctx.fillStyle = tint(ART.path, -0.06)
	var x := 1124
	while x < 1258: ctx.fillRect(x, 1432, 6, 30); x += 12
	room(ctx, R.lobby, '#d6b58a' if reno >= 3 else '#c9a77a', true)
	ctx.fillStyle = 'rgba(36,50,20,0.07)'
	var xx: float = R.lobby.x0
	while xx < R.lobby.x1: ctx.fillRect(xx, R.lobby.y0, 1, 80); xx += 8
	var racks: int = min(6, 2 + Sim.L('shop') / 2)
	var rackC := ['#e8432e', '#2c4a6e', '#f2c14e', '#3f7d4f', '#ffffff', '#7fa8bf']
	for k in racks:
		var rx := 1140 + (k % 2) * 22
		var ry := 1360 + (k / 2) * 18
		ctx.fillStyle = '#5a4630'; ctx.fillRect(rx, ry, 14, 9)
		for j in 4: ctx.fillStyle = rackC[(k + j) % 6]; ctx.fillRect(rx + 1 + j * 3.3, ry + 1, 2.6, 7)
	ctx.fillStyle = '#4a3726'; ctx.fillRect(1196, 1356, 36, 8); ctx.fillRect(1224, 1356, 8, 30)
	ctx.fillStyle = '#2b2f36'; ctx.fillRect(1206, 1358, 6, 4)
	ctx.fillStyle = '#e8e2d2'; ctx.fillRect(1176, 1424, 18, 6)
	ctx.font = '800 7px'; ctx.textAlign = 'center'; ctx.fillStyle = 'rgba(60,40,25,0.55)'; ctx.fillText('PRO SHOP', 1185, 1424)
	var resto := Sim.L('resto') > 0
	room(ctx, R.resto, '#ece2cf', resto)
	if resto:
		ctx.fillStyle = '#b9b2a3'; ctx.fillRect(1002, 1352, 22, 76)
		ctx.fillStyle = '#8d949a'; ctx.fillRect(1004, 1356, 18, 10); ctx.fillRect(1004, 1372, 18, 10); ctx.fillStyle = '#d64a2e'; ctx.fillRect(1006, 1358, 4, 4); ctx.fillRect(1014, 1358, 4, 4)
		var nT := int(ceil(Sim.venueCap('resto') / 4.0))
		for k in 6:
			var s = Sim.VENUE_SEATS.resto[k * 4]
			if k < nT: table(ctx, s.tx, s.ty, 6, '#ffffff')
		if not Sim.venueOpen('resto'): ctx.fillStyle = 'rgba(30,20,10,0.55)'; ctx.font = '800 8px'; ctx.fillText('NEEDS A CHEF' if not Sim.N('chef') else 'CLOSED', 1078, 1424)
	var bar := Sim.L('barRoom') > 0
	room(ctx, R.bar, '#7a5236', bar)
	if bar:
		ctx.fillStyle = '#4a2f1e'; ctx.fillRect(1244, 1354, 72, 12)
		ctx.fillStyle = '#c9a227'
		var bx := 1248
		while bx < 1314: ctx.fillRect(bx, 1356, 3, 3); bx += 7
		for s in Sim.VENUE_SEATS.bar.slice(0, 6): ctx.fillStyle = '#2b1d12'; ctx.beginPath(); ctx.arc(s.x, s.y + 3, 2.6, 0, TAU); ctx.fill()
		var hiTables: int = max(0, int(ceil((Sim.venueCap('bar') - 6) / 3.0)))
		for k in 3:
			if k < hiTables:
				var s = Sim.VENUE_SEATS.bar[6 + k * 3]
				table(ctx, s.tx, s.ty, 5, '#a37a52')
		if not Sim.venueOpen('bar'): ctx.fillStyle = 'rgba(255,240,220,0.8)'; ctx.font = '800 8px'; ctx.fillText('NEEDS A BARTENDER' if not Sim.N('bar') else 'CLOSED', 1280, 1424)
	var lk := Sim.L('locker') > 0
	room(ctx, R.locker, '#b8c4cc', lk)
	if lk:
		ctx.fillStyle = '#6d7c86'; ctx.fillRect(934, 1354, 62, 10); ctx.fillRect(934, 1416, 62, 10)
		ctx.strokeStyle = 'rgba(255,255,255,0.4)'; ctx.lineWidth = 1
		var lx := 940
		while lx < 996: ctx.beginPath(); ctx.moveTo(lx, 1354); ctx.lineTo(lx, 1364); ctx.moveTo(lx, 1416); ctx.lineTo(lx, 1426); ctx.stroke(); lx += 7
		ctx.fillStyle = '#9a7b56'; ctx.fillRect(942, 1386, 46, 6)
	ctx.strokeStyle = '#6b5440'; ctx.lineWidth = 3
	var wall := func(x0, y0, x1, y1): ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke()
	wall.call(1130, 1350, 1130, 1385); wall.call(1130, 1405, 1130, 1430)
	wall.call(1240, 1350, 1240, 1385); wall.call(1240, 1405, 1240, 1430)
	wall.call(1000, 1350, 1000, 1385); wall.call(1000, 1405, 1000, 1430)
	wall.call(1130, 1350, 1175, 1350); wall.call(1195, 1350, 1240, 1350)
	wall.call(1130, 1430, 1175, 1430); wall.call(1195, 1430, 1240, 1430)
	var ter := Sim.L('terrace') > 0
	room(ctx, R.terrace, '#dcd3c1', ter, true)
	if ter:
		ctx.strokeStyle = 'rgba(120,110,90,0.25)'; ctx.lineWidth = 1
		var tx: float = R.terrace.x0
		while tx < R.terrace.x1: ctx.beginPath(); ctx.moveTo(tx, R.terrace.y0); ctx.lineTo(tx, R.terrace.y1); ctx.stroke(); tx += 12
		var ty: float = R.terrace.y0
		while ty < R.terrace.y1: ctx.beginPath(); ctx.moveTo(R.terrace.x0, ty); ctx.lineTo(R.terrace.x1, ty); ctx.stroke(); ty += 12
		ctx.fillStyle = '#4f7a3a'
		for px in [1004, 1236]:
			var py := 1298
			while py < 1348: ctx.beginPath(); ctx.arc(px, py, 4, 0, TAU); ctx.fill(); py += 12
	var keys := ['lobby']
	if lk: keys.append('locker')
	if resto: keys.append('resto')
	if bar: keys.append('bar')
	for k in keys:
		var r = R[k]
		ctx.strokeStyle = tint(ART.wall, -0.45); ctx.lineWidth = 4.5; ctx.strokeRect(r.x0 - 1, r.y0 - 1, r.x1 - r.x0 + 2, r.y1 - r.y0 + 2)
		ctx.strokeStyle = ART.wall; ctx.lineWidth = 2.5; ctx.strokeRect(r.x0 - 1, r.y0 - 1, r.x1 - r.x0 + 2, r.y1 - r.y0 + 2)
	art.woodSign(1185, 1446, 'Clubhouse' if Sim.clubName().length() > 22 else Sim.clubName(), 7)
	for fx in [1108, 1262]:
		ctx.fillStyle = ART.SH; ctx.fillRect(fx + 2, 1466, 6, 3); ctx.fillStyle = ART.cream; ctx.fillRect(fx, 1440, 2, 30); ctx.fillStyle = ART.red; ctx.fillRect(fx + 2, 1440, 9, 5)
	ctx.restore()

# =====================================================================================
# Static: trees
# =====================================================================================
func _draw_trees(ctx: Ctx2D) -> void:
	art.ctx = ctx; _setV(Rect2(-200, -200, Sim.W + 400, Sim.H + 400))
	var trees: Array = Sim.trees
	for k in trees.size():
		if Sim.designing and Sim.draftClear.has(k): ctx.globalAlpha = 0.35
		art.paintTree(trees[k])
		ctx.globalAlpha = 1
	_withDraft(func():
		var feats: Array = Sim.G.feats if Sim.G else []
		for f in feats: drawFeature(ctx, f, 'top'))

# =====================================================================================
# Every frame: water life
# =====================================================================================
func _draw_waterFx(ctx: Ctx2D) -> void:
	art.ctx = ctx; _setV(viewRect().grow(30))
	if not Sim.WF.any: return
	ctx.strokeStyle = 'rgba(255,255,255,0.38)'; ctx.lineWidth = 1.3
	for p in Sim.WF.glints:
		if not vis(p.x - 8, p.y - 8, p.x + 8, p.y + 8): continue
		var a := 0.5 + 0.5 * sin(t * 0.9 + p.ph)
		if a < 0.3: continue
		ctx.globalAlpha = a; ctx.beginPath(); ctx.arc(p.x, p.y, 4 + 2 * sin(p.ph), PI * 1.1, PI * 1.85); ctx.stroke()
	ctx.globalAlpha = 1
	if cam.s > 0.45:
		ctx.strokeStyle = tint(ART.bank, -0.1); ctx.lineWidth = 1.2
		for k in range(0, shoreCache.size(), 2):
			var p: Vector2 = shoreCache[k]
			if not vis(p.x - 6, p.y - 8, p.x + 6, p.y + 2): continue
			var sway := sin(t * 1.3 + p.x * 0.1) * 0.8
			ctx.beginPath(); ctx.moveTo(p.x - 1.5, p.y); ctx.lineTo(p.x - 2 + sway, p.y - 5); ctx.moveTo(p.x, p.y); ctx.lineTo(p.x + sway, p.y - 6.5); ctx.moveTo(p.x + 1.5, p.y); ctx.lineTo(p.x + 2 + sway, p.y - 4.5); ctx.stroke()
	var night: bool = Sim.daylight() < 0.25
	art.stepDucks(_dt, night)
	art.drawDucks(t, night)

# =====================================================================================
# Every frame: everything that moves
# =====================================================================================
func _draw_dyn(ctx: Ctx2D) -> void:
	art.ctx = ctx; _setV(viewRect().grow(30))
	var shown: Array = _withDraft(func(): return shownHoles())
	var simTime: float = t
	# the selected hole's outline
	if not Sim.designing and game != null and game.get("sheetTab") == 'course' and shown.has(Sim.selHole) and Sim.holeOpen(Sim.selHole):
		strokeHole(ctx, Sim.selHole, -0.02, min(1.02, Sim.greenT(Sim.selHole) + 0.1), 100, Color(242 / 255.0, 193 / 255.0, 78 / 255.0, 0.25 + 0.15 * sin(t * 3)), [14, 10])
	# fountains splash
	for o in Sim.objs():
		if o.type != 'fountain': continue
		var px: float = o.x * Sim.TILE
		var py: float = o.y * Sim.TILE
		if not vis(px, py, px + 40, py + 40): continue
		ctx.fillStyle = 'rgba(255,255,255,0.85)'
		for k in 6:
			var a := k / 6.0 * TAU + t
			var rr := 4 + fmod(t * 8, 6.0)
			ctx.fillRect(px + 20 + cos(a) * rr, py + 20 + sin(a) * rr, 1.6, 1.6)
	# the clubhouse staff, inside
	if Sim.hasObj('club'):
		for a in Sim.actors.values():
			if a.role == 'owner' or a.role == 'shop': art.drawPerson(a.x, a.y, art.staffLook(a.lookRole, a.lookSeed), { "act": 'work', "k": fmod(simTime * 0.4 + a.idx * 0.3, 1.0), "scale": 1.0 })
			elif a.role == 'chef': art.drawPerson(a.x, a.y, art.staffLook('chef', a.lookSeed), { "ang": a.ang, "walk": a.walk, "scale": 1.0 } if a.walk != null else { "act": 'work', "k": fmod(simTime * 0.8, 1.0), "scale": 1.0 })
			elif a.role == 'bar': art.drawPerson(a.x, a.y, art.staffLook('bar', a.lookSeed), { "act": 'work', "k": fmod(simTime * 0.7 + a.idx * 0.5, 1.0), "scale": 1.0 })
	# ---------- range: balls, dispenser, pickers, golfers ----------
	Sim.forRanges(func(o): _drawRangeDyn(ctx, o))
	for s in shots:
		s.t += _dt / 1.3
		var k: float = min(1.0, s.t)
		var x: float = s.x0 + (s.x1 - s.x0) * k
		var y: float = s.y0 + (s.y1 - s.y0) * k
		var h := sin(k * PI) * 60
		if not vis(x - 5, y - h - 5, x + 5, y + 5): continue
		ctx.fillStyle = 'rgba(36,50,20,0.28)'; ctx.beginPath(); ctx.arc(x + h * 0.25, y, 1.6, 0, TAU); ctx.fill()
		ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(x, y - h, 1.8 + h / 40, 0, TAU); ctx.fill()
	shots = shots.filter(func(s): return s.t < 1)
	# ---------- course: flags, mowers, golfers ----------
	var wind: float = Sim.W_().wind
	_withDraft(func():
		for i in shown:
			if not Sim.holeOpen(i): continue
			var gr: Vector2 = Sim.hPt(i, Sim.greenT(i))
			ctx.fillStyle = '#fff'; ctx.fillRect(gr.x + 1, gr.y - 18, 1.8, 19)
			var wv := sin(t * (4 + wind * 6) + i) * (1 + wind * 1.5)
			ctx.fillStyle = ART.red; ctx.beginPath(); ctx.moveTo(gr.x + 2.8, gr.y - 18); ctx.lineTo(gr.x + 13 + wind * 3, gr.y - 15.5 + wv * 0.8); ctx.lineTo(gr.x + 2.8, gr.y - 12); ctx.fill())
	drawSelRing(ctx)
	drawKeepers(ctx)
	drawGroups(ctx)
	drawConduct(ctx)
	var night: bool = Sim.daylight() < 0.5
	for v in Sim.vehicles:
		if vis(v.x - 20, v.y - 20, v.x + 20, v.y + 20): art.drawCarSprite(v, t, night, L.glow.ctx if false else null)
	for v in Sim.visitors:
		var st: String = v.state
		if st == 'drive' or st == 'play' or st == 'golf' or st == 'gone': continue
		if not vis(v.x - 16, v.y - 28, v.x + 16, v.y + 12): art.gait(v, _dt); continue
		var gt := art.gait(v, _dt)
		var lk := art.lookOf(v)
		if st == 'walk' and v.get("cart"):
			art.drawGolfCart(v.x, v.y, v.get("ang", 0.0), { "t": t, "moving": gt.moving, "riders": [lk], "bags": [lk.bag], "seed": v.id }); continue
		var seated: bool = st == 'venue' and v.get("venue") != 'shop'
		var act = null
		var k := 0.0
		var face := 'S'
		var flip := false
		var ang: float = gt.dir if gt.moving else (PI / 2 if gt.idle > 1.5 else gt.dir)
		if seated:
			act = 'sit'
			var seats = Sim.VENUE_SEATS.get(v.venue)
			var seat = seats[v.seat] if (seats and v.get("seat") != null and v.seat < seats.size()) else null
			face = 'N' if (not seat or seat.get("ty") == null or seat.y > seat.ty) else 'S'
			k = fmod(t * 0.3 + v.id * 0.1, 1.0)
		elif st == 'amen':
			var cyc := func(len_: float, rest: float):
				var c := fmod(v.t + v.id * 0.77, len_ + rest)
				return c / len_ if c < len_ else null
			if v.amenType == 'putt':
				var c = cyc.call(1.6, 1.4)
				if c != null: act = 'putt'; k = c
				else: act = 'address'
			elif v.amenType == 'short':
				var c = cyc.call(1.4, 2)
				if c != null: act = 'chip'; k = c
				else: act = 'address'
			elif v.amenType == 'academy':
				var c = cyc.call(1.5, 2.5)
				act = 'swing' if c != null else 'address'
				k = c if c != null else fmod(t * 0.5, 1.0)
			flip = v.id % 3 == 0
		elif st == 'filling': ang = -PI / 2
		elif st == 'queue' and v.get("bag") and not v.get("hasBucket") and not gt.moving:
			var c := fmod(simTime + v.id * 1.7, 11.0)
			if c < 1.5: act = 'swing'; k = c / 1.5; flip = v.id % 2 == 0
		if act == null and v.get("fx") and simTime - v.fx.t0 < 1.6: act = v.fx.kind; k = (simTime - v.fx.t0) / 1.6
		var carry = null
		if v.get("hasBucket") and st != 'play': carry = 'bucket'
		elif v.get("bag") and not seated and st != 'venue' and st != 'amen': carry = 'trolley' if lk.trolley else 'bag'
		art.drawPerson(v.x, v.y, lk, { "ang": ang, "walk": gt.ph if gt.moving else null, "act": act, "k": k, "face": face, "flip": flip, "carry": carry, "scale": 1.0 if seated else 1.12, "umbrella": Sim.S.wx == 'rain' and gt.moving, "look": sin(t * 0.35 + v.id) * 0.8 })
		if st == 'queue':
			var left: float = max(0.0, 1 - v.wait / v.patience)
			ctx.fillStyle = 'rgba(36,50,20,0.45)'; ctx.fillRect(v.x - 7, v.y - 23, 14, 3)
			ctx.fillStyle = '#7fe09a' if left > 0.5 else ('#f2c14e' if left > 0.25 else '#e8432e'); ctx.fillRect(v.x - 7, v.y - 23, 14 * left, 3)
		if v.get("upset"):
			ctx.fillStyle = '#e8432e'; ctx.beginPath(); ctx.arc(v.x, v.y - 27, 5, 0, TAU); ctx.fill()
			ctx.fillStyle = '#fff'; ctx.font = '800 8px'; ctx.textAlign = 'center'; ctx.fillText('!', v.x, v.y - 24)
	drawOutdoorActors(ctx)
	drawEventWorld(ctx)
	drawUmbrellas(ctx)
	drawRoofs(ctx)
	drawFlags(ctx)

func _drawRangeDyn(ctx: Ctx2D, o) -> void:
	var x1: float = Sim.rangeX1()
	var RX0: float = Sim.RX0
	var RY0: float = Sim.RY0
	var TEE_Y: float = Sim.TEE_Y
	if vis(RX0 - 20, RY0 - 20, x1 + 20, TEE_Y + 40):
		ctx.fillStyle = 'rgba(255,255,255,0.92)'
		var cols: int = Sim.activeCols()
		var cells: Array = Sim.S.cells
		for i in cells.size():
			if i % Sim.GCMAX >= cols: continue
			var n: int = min(18, int(ceil(cells[i] / 2.0)))
			if not n: continue
			var cx0: float = RX0 + (i % Sim.GCMAX) * Sim.CELL_W
			var cy0: float = RY0 + 10 + (i / Sim.GCMAX) * Sim.CELL_H
			var dots: Array = _cellDots[i % _cellDots.size()]
			var w: float = min(Sim.CELL_W, x1 - cx0 - 4)
			if not vis(cx0, cy0, cx0 + w, cy0 + Sim.CELL_H): continue
			for k in n: ctx.fillRect(cx0 + dots[k * 2] * w, cy0 + dots[k * 2 + 1] * Sim.CELL_H, 2.2, 2.2)
		var fill: float = Sim.S.stock / Sim.ballCap()
		for m in Sim.machines():
			var mp: Vector2 = Sim.machinePos(m)
			if not vis(mp.x - 12, mp.y - 20, mp.x + 12, mp.y + 20): continue
			ctx.fillStyle = '#ffffff'; ctx.fillRect(mp.x - 4, mp.y - 1 - 9 * fill, 8, 9 * fill)
			ctx.fillStyle = '#7fe09a' if Sim.S.stock >= 50 else '#e8432e'; ctx.fillRect(mp.x + 2, mp.y + 2, 2, 2)
			var v = Sim.filling[m] if m < Sim.filling.size() else null
			if v and v.state == 'filling':
				var k: float = min(1.0, v.t / v.dur)
				ctx.fillStyle = '#e8432e'; ctx.fillRect(mp.x - 3.5, mp.y + 10, 7, 6)
				ctx.fillStyle = '#ffffff'; ctx.fillRect(mp.x - 2.5, mp.y + 15 - 4.5 * k, 5, 4.5 * k)
				for d in 3: ctx.fillRect(mp.x - 0.8, mp.y + 8 + fmod(t * 40 + d * 3, 6.0), 1.6, 1.6)
		for i in Sim.pickers.size():
			var p = Sim.pickers[i]
			var cart := Sim.hasCart(i)
			var cap: float = Sim.pickerCap(cart)
			var lf: float = p.load / cap
			var gt := art.gait(p, _dt)
			var lk := art.staffLook('picker', int(o.id) * 20 + i)
			if cart: art.drawPickerCart(p.x, p.y, p.get("ang", 0.0), { "t": t, "moving": gt.moving, "collect": p.state == 'collect', "load": lf, "look": lk })
			else: art.drawPerson(p.x, p.y, lk, { "ang": gt.dir if gt.moving else PI / 2, "walk": gt.ph if gt.moving else null, "act": 'bend' if (p.state == 'collect' and not gt.moving) else null, "k": fmod(t * 0.7 + i * 0.3, 1.0), "carry": 'basket', "load": lf, "scale": 1.15 })
			if p.load > 0 and p.state != 'unload':
				ctx.fillStyle = 'rgba(36,50,20,0.45)'; ctx.fillRect(p.x - 8, p.y - 18, 16, 3)
				ctx.fillStyle = '#f2c14e' if lf >= 0.99 else '#ffffff'; ctx.fillRect(p.x - 8, p.y - 18, 16 * lf, 3)
		var staffed: int = Sim.staffedBays()
		for i in range(staffed, Sim.bays()):
			var x: float = Sim.bayLeftX(i)
			ctx.fillStyle = 'rgba(20,25,20,0.45)'; ctx.fillRect(x + 2, TEE_Y - 6, Sim.BAY_W - 4, 15)
			ctx.fillStyle = '#ff8a3d'; ctx.beginPath(); ctx.moveTo(x + Sim.BAY_W / 2, TEE_Y - 8); ctx.lineTo(x + Sim.BAY_W / 2 + 4, TEE_Y + 4); ctx.lineTo(x + Sim.BAY_W / 2 - 4, TEE_Y + 4); ctx.fill()
		for a in Sim.actors.values():
			if a.role != 'attend' or a.get("rangeId") != o.id: continue
			art.drawPerson(a.x, a.y, art.staffLook('attend', a.lookSeed), { "ang": a.ang, "walk": a.walk, "scale": 1.15 })
		for g in Sim.rangeP:
			if g.state != 'play': continue
			g.swingT = g.get("swingT", 9.0) + _dt
			var st: float = g.swingT
			var bx0: float = Sim.bayX(g.bay)
			var ballY := TEE_Y + 6.4
			if st < Sim.RANGE_IMPACT or st > Sim.RANGE_IMPACT + 0.9: ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(bx0 + 1, ballY, 1.3, 0, TAU); ctx.fill()
			art.drawPerson(bx0, TEE_Y + 1, art.lookOf(g), { "act": 'swing', "k": st / 1.25, "scale": 1.2 } if st < 1.25 else { "act": 'address', "k": fmod(st * 0.5, 1.0), "scale": 1.2 })
			var left: float = max(0.0, 1 - g.t / g.dur)
			var bx: float = bx0 + 8
			var by := TEE_Y + 4
			ctx.fillStyle = '#e8432e'; ctx.fillRect(bx - 2.5, by - 2.5, 5, 5)
			ctx.fillStyle = '#ffffff'; ctx.fillRect(bx - 1.8, by + 1.8 - 3.6 * left, 3.6, 3.6 * left)
	# balls leave the tee in time with the swing
	var fl: Array = Sim.flights
	for fi in range(fl.size() - 1, -1, -1):
		var f = fl[fi]
		f.wait = f.get("wait", Sim.RANGE_IMPACT) - _dt
		if f.wait > 0: continue
		fl.remove_at(fi)
		if shots.size() < 80: shots.append({ "x0": Sim.bayX(f.bay) + 1, "y0": TEE_Y + 6, "x1": f.x, "y1": f.y, "t": 0.0 })
		if Sim.warp <= 2 and onScreen(Sim.bayX(f.bay), TEE_Y): Sim.sfx('strike', Vector2(Sim.bayX(f.bay), TEE_Y))
var _cellDots := _makeCellDots()
static func _makeCellDots() -> Array:
	var r := func(): return 0.0
	var out := []
	var seed_ := 7
	for i in 22 * 10:
		var a := []
		for k in 36:
			seed_ = (seed_ * 16807) % 2147483647
			a.append(0.08 + (seed_ - 1) / 2147483646.0 * 0.84)
		out.append(a)
	return out

func drawGroups(ctx: Ctx2D) -> void:
	for g in Sim.groups:
		var sh = g.get("shot")
		for v in g.players:
			var b = Sim.ball(g, v) if g.phase == 'play' else null
			if b and not b.get("flying") and b.get("lie") != 'holed' and vis(b.x - 4, b.y - 4, b.x + 4, b.y + 4):
				ctx.fillStyle = 'rgba(36,50,20,0.33)'; ctx.beginPath(); ctx.arc(b.x + 0.6, b.y + 0.6, 1.5, 0, TAU); ctx.fill()
				ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(b.x, b.y, 1.4, 0, TAU); ctx.fill()
			var mine = sh if (sh and is_same(sh.v, v)) else null
			if mine and mine.t < 0 and vis(mine.from.x - 4, mine.from.y - 4, mine.from.x + 4, mine.from.y + 4):
				ctx.fillStyle = 'rgba(36,50,20,0.33)'; ctx.beginPath(); ctx.arc(mine.from.x + 0.6, mine.from.y + 0.6, 1.5, 0, TAU); ctx.fill()
				ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(mine.from.x, mine.from.y, 1.4, 0, TAU); ctx.fill()
			if not vis(v.x - 16, v.y - 26, v.x + 16, v.y + 12): art.gait(v, _dt); continue
			var gt := art.gait(v, _dt)
			var lk := art.lookOf(v)
			if v.get("riding"): art.drawGolfCart(v.x, v.y, v.get("ang", 0.0), { "t": t, "moving": gt.moving, "riders": [lk], "bags": [lk.bag], "seed": v.id }); continue
			if mine:
				var act := 'putt' if mine.kind == 'putt' else ('chip' if mine.kind == 'chip' else 'swing')
				var imp := 0.5 if act == 'putt' else 0.6
				var pre: float = Sim.SHOT_PRE.get(mine.kind, 0.7)
				var k: float = imp * (1 + mine.t / pre) if mine.t < 0 else imp + (1 - imp) * min(1.0, mine.t / 0.55)
				var flip: bool = mine.to.x < mine.from.x
				var sc: float = 1.25 * lk.h
				var off: Array = { "swing": [0.8, 4.5], "chip": [0.5, 3.6], "putt": [0.1, 4.0] }[act]
				art.drawPerson(mine.from.x - (-off[0] if flip else off[0]) * sc, mine.from.y - off[1] * sc, lk, { "act": act, "k": k, "flip": flip, "scale": 1.25 })
				continue
			var fx = v.fx if (v.get("fx") and t - v.fx.t0 < 1.6) else null
			art.drawPerson(v.x, v.y, lk, { "ang": gt.dir if gt.moving else PI / 2, "walk": gt.ph if gt.moving else null, "act": fx.kind if fx else null, "k": (t - fx.t0) / 1.6 if fx else 0.0,
				"carry": 'trolley' if lk.trolley else 'bag', "scale": 1.25, "umbrella": Sim.S.wx == 'rain', "look": sin(t * 0.4 + v.id) * 0.8 })
		if sh and sh.t > 0:
			var k: float = min(1.0, sh.t / sh.dur)
			var e := 1 - (1 - k) * (1 - k) if sh.kind == 'putt' else k
			var x: float = sh.from.x + (sh.to.x - sh.from.x) * e
			var y: float = sh.from.y + (sh.to.y - sh.from.y) * e
			var hgt: float = sin(k * PI) * sh.peak
			if vis(min(x, sh.from.x) - 10, min(y, sh.from.y) - hgt - 10, max(x, sh.from.x) + 10, max(y, sh.from.y) + 10):
				if sh.peak > 10:
					ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 1; ctx.beginPath()
					for j in 17:
						var kk := k * j / 16.0
						var xx: float = sh.from.x + (sh.to.x - sh.from.x) * kk
						var yy: float = sh.from.y + (sh.to.y - sh.from.y) * kk - sin(kk * PI) * sh.peak
						if j: ctx.lineTo(xx, yy)
						else: ctx.moveTo(xx, yy)
					ctx.stroke()
				ctx.fillStyle = 'rgba(36,50,20,0.33)'; ctx.beginPath(); ctx.arc(x + hgt * 0.15, y, 1.4, 0, TAU); ctx.fill()
				ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(x, y - hgt, 1.5 + hgt / 45, 0, TAU); ctx.fill()
	for sp in Sim.splashes:
		sp.vy += 90 * _dt; sp.x += sp.vx * _dt; sp.y += sp.vy * _dt; sp.life -= _dt
		ctx.fillStyle = sp.c; ctx.fillRect(sp.x - 1, sp.y - 1, 2, 2)
	Sim.splashes = Sim.splashes.filter(func(s): return s.life > 0)

func drawKeepers(ctx: Ctx2D) -> void:
	for kp in Sim.keepers:
		var gt := art.gait(kp, _dt)
		if not vis(kp.x - 24, kp.y - 24, kp.x + 24, kp.y + 24): continue
		if kp.state == 'mow':
			ctx.save(); ctx.translate(kp.x, kp.y); ctx.rotate(kp.get("ang", 0.0)); ctx.fillStyle = 'rgba(255,255,255,0.16)'; ctx.fillRect(-30, -8, 36, 16); ctx.restore()
		art.drawMower(kp.x, kp.y, kp.get("ang", 0.0), { "t": t, "mowing": kp.state == 'mow', "moving": gt.moving, "look": art.staffLook('keeper', kp.id), "dt": _dt })
	art.drawClippings(_dt)

func drawConduct(ctx: Ctx2D) -> void:
	for l in Sim.litter:
		if not vis(l.x - 4, l.y - 4, l.x + 4, l.y + 4): continue
		ctx.save(); ctx.translate(l.x, l.y); ctx.rotate(l.rot)
		ctx.fillStyle = 'rgba(36,50,20,0.28)'; ctx.fillRect(-2, -1, 5, 3)
		ctx.fillStyle = '#d64a2e' if l.kind == 'can' else ('#3f8f5a' if l.kind == 'bottle' else ('#f2c14e' if l.kind == 'cup' else '#f4f1ea'))
		if l.kind == 'paper': ctx.beginPath(); ctx.arc(0, 0, 2.2, 0, TAU); ctx.fill()
		else: ctx.fillRect(-2.5, -1.2, 5, 2.4)
		ctx.restore()
	for k in Sim.marks:
		if not vis(k.x - 12, k.y - 12, k.x + 12, k.y + 12): continue
		if k.type == 'branch': drawBranch(ctx, k); continue
		if k.type == 'bay':
			ctx.fillStyle = '#3a2d22'; ctx.fillRect(k.x - 9, k.y - 7, 18, 14)
			ctx.strokeStyle = '#c9b08a'; ctx.lineWidth = 1.2; ctx.beginPath(); ctx.moveTo(k.x - 7, k.y - 5); ctx.lineTo(k.x - 1, k.y + 1); ctx.lineTo(k.x + 2, k.y - 3); ctx.lineTo(k.x + 7, k.y + 5); ctx.stroke()
			ctx.fillStyle = '#ff8a3d'; ctx.beginPath(); ctx.moveTo(k.x, k.y - 12); ctx.lineTo(k.x + 4, k.y); ctx.lineTo(k.x - 4, k.y); ctx.fill()
		elif k.type == 'furniture':
			ctx.save(); ctx.translate(k.x, k.y); ctx.rotate(0.9)
			ctx.fillStyle = '#5a3d27'; ctx.fillRect(-4, -2, 8, 4); ctx.fillRect(-4, -6, 2, 4)
			ctx.restore()
			ctx.strokeStyle = '#e8432e'; ctx.lineWidth = 1.4; ctx.beginPath(); ctx.moveTo(k.x - 3, k.y - 9); ctx.lineTo(k.x + 3, k.y - 3); ctx.moveTo(k.x + 3, k.y - 9); ctx.lineTo(k.x - 3, k.y - 3); ctx.stroke()
		else:
			var w := 7.0 if k.type == 'green' else 9.0
			ctx.fillStyle = '#5b3f24'; ctx.beginPath(); ctx.ellipse(k.x, k.y, w, w * 0.45, 0.6, 0, TAU); ctx.fill()
			ctx.fillStyle = '#7a5a36'; ctx.beginPath(); ctx.ellipse(k.x + 3, k.y - 2, w * 0.45, w * 0.25, 0.2, 0, TAU); ctx.fill()
			ctx.fillStyle = '#8b6a3e'; ctx.fillRect(k.x - w, k.y + 2, 2, 2); ctx.fillRect(k.x + w - 2, k.y - 3, 2, 2)
	for m in Sim.marshals:
		var gt := art.gait(m, _dt)
		if not vis(m.x - 16, m.y - 26, m.x + 16, m.y + 12): continue
		var lk := art.staffLook('marshal', m.id)
		if m.get("cart"): art.drawGolfCart(m.x, m.y, m.get("ang", 0.0), { "t": t, "moving": gt.moving, "riders": [lk], "roof": '#f5f5f0', "stripe": '#1f3a5f', "beacon": true, "seed": m.id })
		else:
			var working: bool = m.state == 'work' and m.get("job") and m.job.kind != 'person'
			art.drawPerson(m.x, m.y, lk, { "ang": gt.dir if gt.moving else PI / 2, "walk": gt.ph if gt.moving else null, "act": 'bend' if working else ('wave' if m.state == 'work' else null), "k": fmod(t * 0.8, 1.0), "scale": 1.15 })
			if working: ctx.fillStyle = 'rgba(255,255,255,0.8)'; ctx.fillRect(m.x - 6 + sin(t * 20) * 2, m.y + 2, 1.5, 1.5)
func drawBranch(ctx: Ctx2D, k) -> void:
	ctx.save(); ctx.translate(k.x, k.y); ctx.rotate(k.get("rot", 0.0))
	ctx.fillStyle = 'rgba(36,50,20,0.28)'; ctx.fillRect(-9, 0, 20, 3)
	ctx.strokeStyle = '#6b4a2b'; ctx.lineWidth = 2; ctx.lineCap = 'round'; ctx.beginPath(); ctx.moveTo(-10, 0); ctx.lineTo(10, -1); ctx.moveTo(-2, -0.5); ctx.lineTo(3, -6); ctx.moveTo(4, -0.8); ctx.lineTo(8, 4); ctx.stroke()
	ctx.fillStyle = '#3f7d4f'
	for p in [[3, -7], [9, 4], [10, -2], [-9, -1]]: ctx.beginPath(); ctx.arc(p[0], p[1], 2.6, 0, TAU); ctx.fill()
	ctx.restore()
func drawFlags(ctx: Ctx2D) -> void:
	for v in Sim.visitors:
		if not v.get("flagged") or v.get("ejected") or v.state == 'drive' or v.state == 'gone': continue
		var x: float = v.x
		var y: float = v.y - (4 if v.state == 'golf' else 0)
		if not vis(x - 8, y - 26, x + 8, y): continue
		var pulse := 1 + sin(t * 6) * 0.12
		ctx.fillStyle = '#e8432e'; ctx.beginPath(); ctx.moveTo(x, y - 27 * pulse); ctx.lineTo(x + 6 * pulse, y - 17); ctx.lineTo(x - 6 * pulse, y - 17); ctx.fill()
		ctx.fillStyle = '#fff'; ctx.font = '800 7px'; ctx.textAlign = 'center'; ctx.fillText('!', x, y - 18.5)
func selected():
	return game.insp if (game != null and game.get("insp") and game.entityAlive(game.insp)) else null
func drawSelRing(ctx: Ctx2D) -> void:
	var insp = selected()
	if insp == null: return
	var o = insp.o
	var big: bool = insp.get("role") == 'keeper' or o.get("cart") or o.get("riding") or (insp.get("role") == 'picker' and o.get("idx", 99) < Sim.L('cart'))
	if not vis(o.x - 20, o.y - 20, o.x + 20, o.y + 20): return
	var p := 0.5 + 0.5 * sin(t * 5)
	var r := (13.0 if big else 6.0) + p * 1.5
	ctx.strokeStyle = Color(242 / 255.0, 193 / 255.0, 78 / 255.0, 0.6 + 0.4 * p); ctx.lineWidth = 1.4; ctx.beginPath(); ctx.ellipse(o.x, o.y, r, r * 0.45, 0, 0, TAU); ctx.stroke()
	ctx.fillStyle = 'rgba(242,193,78,0.18)'; ctx.fill()
func drawOutdoorActors(ctx: Ctx2D) -> void:
	for a in Sim.actors.values():
		if a.role != 'starter' and a.role != 'coach': continue
		if not vis(a.x - 12, a.y - 24, a.x + 12, a.y + 8): continue
		var busy := false
		if a.role == 'coach' and a.get("academy"):
			for u in Sim.amenUsers(a.academy):
				if u.get("amenSlot") == a.idx and u.state == 'amen': busy = true
		var lk := art.staffLook(a.role, a.lookSeed)
		art.drawPerson(a.x, a.y, lk, { "act": 'wave', "k": fmod(t * 0.4, 1.0), "scale": 1.12 } if busy else { "ang": PI / 2, "scale": 1.12, "look": sin(t * 0.5 + a.idx) })
		if a.role == 'starter': ctx.fillStyle = '#f4f1ea'; ctx.fillRect(a.x + 2.6, a.y - 9.5, 3, 3.8); ctx.fillStyle = '#5a4630'; ctx.fillRect(a.x + 2.6, a.y - 9.9, 3, 0.8)
var _crewLooks := []
func drawEventWorld(ctx: Ctx2D) -> void:
	var ms: Array = Sim.activeMods()
	var anyCeleb := false
	for v in Sim.visitors:
		if v.get("celeb"): anyCeleb = true; break
	if ms.is_empty() and not anyCeleb: return
	var geese := false
	for m in ms:
		if m.eff.get("geese"): geese = true
	if geese:
		Sim.forRanges(func(_o):
			var x1: float = Sim.rangeX1()
			var r := Sim.seeded(99)
			for k in 14:
				var x: float = Sim.RX0 + 24 + r.call() * (x1 - Sim.RX0 - 48) + sin(t * 0.07 + k) * 6
				var y: float = Sim.RY0 + 30 + r.call() * (Sim.FIELD_Y1 - Sim.RY0 - 60) + cos(t * 0.05 + k * 2) * 4
				if not vis(x - 8, y - 8, x + 8, y + 8): continue
				var head := sin(t * 0.6 + k * 1.7) > 0.3
				var dir := 1 if k % 2 else -1
				ctx.fillStyle = 'rgba(36,50,20,0.22)'; ctx.beginPath(); ctx.ellipse(x + 1, y + 1.5, 4, 2, 0, 0, TAU); ctx.fill()
				ctx.fillStyle = '#8b7d6b'; ctx.beginPath(); ctx.ellipse(x, y, 4.2, 2.4, 0, 0, TAU); ctx.fill()
				ctx.fillStyle = '#5b5047'; ctx.beginPath(); ctx.ellipse(x - dir * 1, y - 0.3, 2.6, 1.6, 0, 0, TAU); ctx.fill()
				ctx.strokeStyle = '#1f2124'; ctx.lineWidth = 1.1; ctx.lineCap = 'round'; ctx.beginPath(); ctx.moveTo(x + dir * 3.2, y - 0.6)
				var hx := x + dir * (5.6 if head else 6.2)
				var hy := y - 4.6 if head else y + 1.2
				ctx.lineTo(hx, hy); ctx.stroke(); ctx.lineCap = 'butt'
				ctx.fillStyle = '#1f2124'; ctx.beginPath(); ctx.arc(hx, hy, 1.1, 0, TAU); ctx.fill(); ctx.fillStyle = '#f4f4f0'; ctx.fillRect(hx - 0.6, hy, 1.2, 0.6))
	if _crewLooks.is_empty():
		for k in 3:
			var lk: Dictionary = art.lookOf({ "id": 7700 + k }).duplicate()
			lk.merge({ "shirt": '#2b2f36', "bottom": '#2b2f36', "hat": 'cap' if k == 0 else null, "hatC": '#2b2f36', "key": 900000 + k }, true)
			_crewLooks.append(lk)
	for m in ms:
		if m.eff.get("film"):
			var i: int = int(m.eff.film) - 1
			if not Sim.holeOpen(i): continue
			var g: Vector2 = Sim.hPt(i, 0.82)
			if not vis(g.x - 40, g.y - 40, g.x + 40, g.y + 20): continue
			ctx.strokeStyle = '#2b2f36'; ctx.lineWidth = 0.8
			for dx in [-3, 0, 3]: ctx.beginPath(); ctx.moveTo(g.x - 20, g.y - 7); ctx.lineTo(g.x - 20 + dx, g.y); ctx.stroke()
			ctx.fillStyle = '#2b2f36'; ctx.fillRect(g.x - 24, g.y - 11, 8, 5); ctx.fillStyle = '#7fa3ba'; ctx.beginPath(); ctx.arc(g.x - 15.5, g.y - 8.5, 1.4, 0, TAU); ctx.fill()
			if sin(t * 3) > 0: ctx.fillStyle = '#e8432e'; ctx.beginPath(); ctx.arc(g.x - 22.5, g.y - 12, 0.8, 0, TAU); ctx.fill()
			for k in 3:
				art.drawPerson(g.x - 12 + k * 9, g.y + 4 + (k % 2) * 4, _crewLooks[k], { "act": 'wave', "k": fmod(t * 0.5, 1.0), "scale": 1.1 } if k == 0 else { "ang": PI, "scale": 1.1 })
			ctx.fillStyle = 'rgba(255,255,255,0.85)'; ctx.beginPath(); ctx.ellipse(g.x + 18, g.y - 6, 4, 6, 0.3, 0, TAU); ctx.fill()
		if m.eff.get("strike") and Sim.hasObj('club'):
			var x0: float = 1128 + Sim.CDX
			var y0: float = 1476 + Sim.CDY
			if not vis(x0 - 20, y0 - 34, x0 + 90, y0 + 10): continue
			var role: String = { "assist": 'shop', "keeper": 'keeper', "chef": 'chef', "bar": 'bar' }.get(m.eff.strike, 'marshal')
			for k in 3:
				var x := x0 + k * 30 + sin(t * 0.6 + k) * 6
				art.drawPerson(x, y0, art.staffLook(role, 50 + k), { "ang": 0.0 if cos(t * 0.8 + k) > 0 else PI, "walk": x * 0.5, "scale": 1.05 })
				ctx.strokeStyle = '#7a5a36'; ctx.lineWidth = 0.7; ctx.beginPath(); ctx.moveTo(x + 2, y0 - 8); ctx.lineTo(x + 2, y0 - 22); ctx.stroke()
				ctx.fillStyle = 'rgba(36,50,20,0.28)'; ctx.fillRect(x - 7, y0 - 29, 19, 9); ctx.fillStyle = '#f4f1ea'; ctx.fillRect(x - 8, y0 - 30, 19, 9)
				ctx.fillStyle = '#c8322a'; ctx.font = '800 5.6px'; ctx.textAlign = 'center'; ctx.fillText('STRIKE', x + 1.5, y0 - 23.6)
	for v in Sim.visitors:
		if not v.get("celeb") or v.state == 'drive' or v.state == 'gone': continue
		var y: float = v.y - 24 - abs(sin(t * 3)) * 2
		if not vis(v.x - 8, y - 8, v.x + 8, y + 8): continue
		ctx.save(); ctx.translate(v.x, y); ctx.rotate(sin(t * 2) * 0.15)
		ctx.fillStyle = '#f2c14e'; ctx.strokeStyle = '#8a6a10'; ctx.lineWidth = 0.6; ctx.beginPath()
		for k in 10:
			var a := -PI / 2 + k * PI / 5
			var r := 2.0 if k % 2 else 4.6
			ctx.lineTo(cos(a) * r, sin(a) * r)
		ctx.closePath(); ctx.fill(); ctx.stroke(); ctx.restore()
func drawUmbrellas(ctx: Ctx2D) -> void:
	if not Sim.hasObj('club') or not Sim.L('terrace'): return
	ctx.save(); ctx.translate(Sim.CDX, Sim.CDY)
	var n := int(ceil(Sim.venueCap('terrace') / 4.0))
	var cols := ['#e8432e', '#f5f5f0', '#2c4a6e', '#f2c14e', '#3f7d4f', '#e8432e']
	for k in 6:
		var s = Sim.VENUE_SEATS.terrace[k * 4]
		if k >= n: continue
		ctx.globalAlpha = 0.88
		for j in 8:
			ctx.fillStyle = cols[k] if j % 2 else '#ffffff'; ctx.beginPath(); ctx.moveTo(s.tx, s.ty); ctx.arc(s.tx, s.ty, 13, j / 8.0 * TAU, (j + 1) / 8.0 * TAU); ctx.fill()
		ctx.globalAlpha = 1
		ctx.fillStyle = '#5a4630'; ctx.beginPath(); ctx.arc(s.tx, s.ty, 1.6, 0, TAU); ctx.fill()
	ctx.restore()
## roofs fade away when you zoom right in, hover over a building, or look at someone inside
func roofAlpha(key: String, x0: float, y0: float, x1: float, y1: float) -> float:
	var tg := 1.0
	if not Sim.designing:
		tg = 0.0 if cam.s >= 2.3 else (1.0 if cam.s <= 1.7 else 1 - (cam.s - 1.7) / 0.6)
		if game != null and game.get("hoverWorld") != null and game.get("tool") == null:
			var w: Vector2 = game.hoverWorld
			if w.x > x0 and w.x < x1 and w.y > y0 and w.y < y1: tg = min(tg, 0.12)
		var insp = selected()
		if insp != null and insp.o.x > x0 and insp.o.x < x1 and insp.o.y > y0 and insp.o.y < y1: tg = 0.0
		if key == 'club' and game != null and game.get("sheetTab") == 'club': tg = min(tg, 0.12)
	var cur: float = roofA.get(key, tg)
	roofA[key] = cur + (tg - cur) * min(1.0, get_process_delta_time() * 9)
	return roofA[key]
func drawRoofs(ctx: Ctx2D) -> void:
	var CDX: float = Sim.CDX
	var CDY: float = Sim.CDY
	if Sim.hasObj('club') and vis(920 + CDX, 1290 + CDY, 1340 + CDX, 1470 + CDY):
		var R: Dictionary = Sim.ROOMS
		var reno: int = Sim.L('reno')
		var x0: float = R.locker.x0 + CDX
		var x1: float = R.bar.x1 + CDX
		var y0: float = R.lobby.y0 + CDY
		var y1: float = R.lobby.y1 + CDY
		var a := roofAlpha('club', x0, y0, x1, y1)
		if a > 0.01:
			ctx.save(); ctx.translate(CDX, CDY); ctx.globalAlpha = a
			var base = ART.slate if reno >= 3 else ART.roof
			var built := { "locker": Sim.L('locker') > 0, "resto": Sim.L('resto') > 0, "bar": Sim.L('barRoom') > 0 }
			for k in ['locker', 'resto', 'bar']:
				if built[k]:
					var r = R[k]
					art.hipRoof(r.x0 - 3, r.y0 - 3, r.x1 - r.x0 + 6, r.y1 - r.y0 + 6, base)
			if built.resto:
				ctx.fillStyle = ART.SH; ctx.fillRect(1014, 1360, 10, 10); ctx.fillStyle = '#b8a48a'; ctx.fillRect(1010, 1356, 10, 10)
				ctx.strokeStyle = tint('#b8a48a', -0.4); ctx.lineWidth = 1; ctx.strokeRect(1010, 1356, 10, 10); ctx.fillStyle = '#4a3e33'; ctx.fillRect(1012, 1358, 6, 6)
			var Lb = R.lobby
			art.hipRoof(Lb.x0 - 6, Lb.y0 - 8, Lb.x1 - Lb.x0 + 12, Lb.y1 - Lb.y0 + 12, tint(base, -0.06) if reno >= 1 else Ctx2D.col(base), { "height": 1.5 })
			ctx.fillStyle = ART.SH; ctx.fillRect(1182, 1388, 14, 14); ctx.fillStyle = ART.wall; ctx.fillRect(1178, 1383, 14, 14); ctx.strokeStyle = tint(ART.wall, -0.45); ctx.strokeRect(1178, 1383, 14, 14)
			art.hipRoof(1176, 1381, 18, 18, ART.moss, { "tiles": false })
			ctx.globalAlpha = 1; ctx.restore()
	var TILE: float = Sim.TILE
	for o in Sim.objs():
		if o.type != 'academy' and o.type != 'shed' and o.type != 'hut': continue
		var f := Sim.fp(o)
		var px: float = f.x * TILE
		var py: float = f.y * TILE
		var w: float = f.w * TILE
		var h: float = f.h * TILE
		if not vis(px - 10, py - 10, px + w + 10, py + h + 10): continue
		var a := roofAlpha('o%s' % o.id, px, py, px + w, py + h)
		if a <= 0.01: continue
		ctx.globalAlpha = a
		if o.type == 'hut':
			ctx.fillStyle = ART.SH; ctx.fillRect(px + 2 + ART.SX, py + 2 + ART.SY, w - 4, h - 12)
			for k in 6: ctx.fillStyle = ART.cream if k % 2 else ART.red; ctx.fillRect(px + 2 + k * (w - 4) / 6, py + 2, (w - 4) / 6 + 0.5, h - 12)
			ctx.fillStyle = 'rgba(255,255,255,0.18)'; ctx.fillRect(px + 2, py + 2, w - 4, 4)
			ctx.strokeStyle = tint(ART.red, -0.45); ctx.lineWidth = 1.2; ctx.strokeRect(px + 2, py + 2, w - 4, h - 12)
			for k in 6: ctx.fillStyle = ART.cream if k % 2 else ART.red; ctx.beginPath(); ctx.arc(px + 2 + (k + 0.5) * (w - 4) / 6, py + h - 10, (w - 4) / 12, 0, PI); ctx.fill()
		else: art.hipRoof(px + 1, py + 1, w - 2, h - 2, ART.slate if o.type == 'academy' else ART.tin, { "tiles": o.type == 'academy' })
		if o.type == 'shed':
			ctx.strokeStyle = 'rgba(30,40,30,0.25)'; ctx.lineWidth = 1; ctx.beginPath()
			var x := px + 5
			while x < px + w - 2: ctx.moveTo(x, py + 2); ctx.lineTo(x, py + h - 2); x += 4
			ctx.stroke()
		if o.type == 'academy':
			for sx in [px + w * 0.3, px + w * 0.62]: ctx.fillStyle = '#bfe1ef'; ctx.fillRect(sx, py + 9, 9, 6); ctx.strokeStyle = tint(ART.slate, -0.4); ctx.strokeRect(sx, py + 9, 9, 6)
		ctx.globalAlpha = 1
		if cam.s > 1.05: art.woodSign(px + w / 2, py + h + 6, { "academy": 'Academy', "shed": 'Greenkeeping', "hut": 'Snacks' }[o.type], 6)

# =====================================================================================
# Every frame: over the trees
# =====================================================================================
func _draw_top(ctx: Ctx2D) -> void:
	art.ctx = ctx
	var vr := viewRect()
	_setV(vr.grow(30))
	art.stepFliers(_dt, vr, Sim.daylight() > 0.5 and Sim.S.wx != 'rain' and Sim.warp <= 3)
	art.drawFliers()
	drawLand(ctx)
	if game != null:
		drawConnectWarnings(ctx)
		if game.get("tool") != null: drawBuildOverlay(ctx)
		if Sim.designing: _withDraft(func(): drawDesignOverlay(ctx))
	# clouds
	var w: Dictionary = Sim.W_()
	var cl: float = w.cloud
	if cl > 0.03:
		for c in Sim.clouds:
			c.x += (8 + w.wind * 24) * _dt
			if c.x - c.r > Sim.W + 200: c.x = -c.r - 200; c.y = randf() * Sim.H
			if not vis(c.x - c.r, c.y - c.r, c.x + c.r, c.y + c.r): continue
			var g := ctx.createRadialGradient(c.x, c.y, 0, c.x, c.y, c.r)
			g.addColorStop(0, Color(20 / 255.0, 30 / 255.0, 40 / 255.0, cl)); g.addColorStop(1, 'rgba(20,30,40,0)')
			ctx.fillStyle = g; ctx.beginPath(); ctx.arc(c.x, c.y, c.r, 0, TAU); ctx.fill()
	# dusk and night over the whole view
	var dl: float = 1.0 if Sim.designing else Sim.daylight()
	if dl < 1:
		var warm := sin(dl * PI) * 0.18
		var dark := 1 - dl
		var r := vr.grow(60)
		if warm > 0.01: ctx.fillStyle = Color(1, 130 / 255.0, 60 / 255.0, warm); ctx.fillRect(r.position.x, r.position.y, r.size.x, r.size.y)
		ctx.fillStyle = Color(6 / 255.0, 12 / 255.0, 38 / 255.0, 0.62 * dark); ctx.fillRect(r.position.x, r.position.y, r.size.x, r.size.y)
	# confetti and mood bubbles stay bright
	for c in confetti:
		c.vy += 120 * _dt; c.x += c.vx * _dt; c.y += c.vy * _dt; c.life -= _dt
		ctx.fillStyle = c.c; ctx.fillRect(c.x - 1.5, c.y - 1.5, 3, 3)
	confetti = confetti.filter(func(c): return c.life > 0)
	_drawBubbles(ctx)

## the glow layer: added on top of the night
func _draw_glow(ctx: Ctx2D) -> void:
	art.ctx = ctx
	_setV(viewRect().grow(60))
	var dl: float = 1.0 if Sim.designing else Sim.daylight()
	if dl >= 1: return
	var dark := 1 - dl
	Sim.forRanges(func(_o):
		var x1: float = Sim.rangeX1()
		if Sim.L('lights') and dark > 0.2 and vis(Sim.RX0, Sim.RY0, x1, Sim.TEE_Y):
			var x: float = Sim.RX0
			while x <= x1:
				var g := ctx.createRadialGradient(x, Sim.RY0, 4, x, (Sim.RY0 + Sim.TEE_Y) / 2, 320)
				g.addColorStop(0, Color(1, 240 / 255.0, 190 / 255.0, 0.3 * dark)); g.addColorStop(1, 'rgba(255,240,190,0)')
				ctx.fillStyle = g; ctx.fillRect(max(Sim.RX0, x - 320), Sim.RY0, 640, Sim.TEE_Y - Sim.RY0 + 30)
				x += 220)
	if Sim.hasObj('club'):
		for k in Sim.ROOMS:
			if k == 'terrace': continue
			if (k == 'resto' and not Sim.L('resto')) or (k == 'bar' and not Sim.L('barRoom')) or (k == 'locker' and not Sim.L('locker')): continue
			var r = Sim.ROOMS[k]
			ctx.fillStyle = Color(1, 190 / 255.0, 100 / 255.0, 0.22 * dark); ctx.fillRect(r.x0 + Sim.CDX, r.y0 + Sim.CDY, r.x1 - r.x0, r.y1 - r.y0)
	if dl < 0.5:
		for v in Sim.vehicles:
			if v.state == 'parked' or not v.get("kind") or not vis(v.x - 60, v.y - 60, v.x + 60, v.y + 60): continue
			var Lc: float = v.kind.l
			var Wc: float = v.kind.w
			ctx.save(); ctx.translate(v.x, v.y); ctx.rotate(v.ang)
			var gr := ctx.createRadialGradient(Lc / 2 + 2, 0, 1, Lc / 2 + 22, 0, 26)
			gr.addColorStop(0, 'rgba(255,240,190,0.35)'); gr.addColorStop(1, 'rgba(255,240,190,0)')
			ctx.fillStyle = gr; ctx.beginPath(); ctx.moveTo(Lc / 2, -Wc / 2 + 1); ctx.lineTo(Lc / 2 + 36, -16); ctx.lineTo(Lc / 2 + 36, 16); ctx.lineTo(Lc / 2, Wc / 2 - 1); ctx.fill()
			ctx.restore()

func drawLand(ctx: Ctx2D) -> void:
	if not Sim.S.get("world") or Sim.designing: return
	var owned := {}
	for id in Sim.S.world.land: owned[int(id)] = true
	var showPrice: bool = game != null and game.get("tool") != null and game.tool.kind == 'land'
	for p in Sim.PARCELS:
		if not vis(p.x0, p.y0, p.x1, p.y1): continue
		var own: bool = owned.has(int(p.id))
		if not own: ctx.fillStyle = 'rgba(30,40,20,0.55)' if showPrice else 'rgba(30,40,20,0.32)'; ctx.fillRect(p.x0, p.y0, p.x1 - p.x0, p.y1 - p.y0)
		if showPrice:
			var sel: bool = game.tool.get("plot") == p.id
			ctx.strokeStyle = '#f2c14e' if sel else ('rgba(255,255,255,0.18)' if own else 'rgba(255,255,255,0.4)'); ctx.lineWidth = 4 if sel else 1.5; ctx.setLineDash([] if sel else [10, 8])
			ctx.strokeRect(p.x0 + 2, p.y0 + 2, p.x1 - p.x0 - 4, p.y1 - p.y0 - 4); ctx.setLineDash([])
			if not own: ctx.fillStyle = 'rgba(255,255,255,0.9)'; ctx.font = '800 13px'; ctx.textAlign = 'center'; ctx.fillText(Sim.fmt(Sim.parcelPrice()), (p.x0 + p.x1) / 2, (p.y0 + p.y1) / 2 + 5)
	ctx.strokeStyle = 'rgba(240,232,210,0.55)'; ctx.lineWidth = 2
	var nb := func(x: float, y: float) -> bool:
		var q = Sim.parcelAt(x, y)
		return q != null and owned.has(int(q.id))
	for p in Sim.PARCELS:
		if not owned.has(int(p.id)) or not vis(p.x0 - 4, p.y0 - 4, p.x1 + 4, p.y1 + 4): continue
		ctx.beginPath()
		if not nb.call(p.x0 - 5, p.y0 + 5): ctx.moveTo(p.x0, p.y0); ctx.lineTo(p.x0, p.y1)
		if not nb.call(p.x1 + 5, p.y0 + 5): ctx.moveTo(p.x1, p.y0); ctx.lineTo(p.x1, p.y1)
		if not nb.call(p.x0 + 5, p.y0 - 5): ctx.moveTo(p.x0, p.y0); ctx.lineTo(p.x1, p.y0)
		if not nb.call(p.x0 + 5, p.y1 + 5) and p.y1 < Sim.LAND_Y1: ctx.moveTo(p.x0, p.y1); ctx.lineTo(p.x1, p.y1)
		ctx.stroke()
var _warnT := 0.0
var _warnCache := []
func drawConnectWarnings(ctx: Ctx2D) -> void:
	# working out what's connected is a search, so do it a few times a second
	_warnT -= _dt if _dt > 0 else 0.016
	if _warnT <= 0:
		_warnT = 0.5
		_warnCache = []
		var anyBuilding := false
		for x in Sim.objs():
			if x.type != 'lot' and not Sim.OBJ[x.type].get("free"): anyBuilding = true
		for o in Sim.objs():
			if Sim.OBJ[o.type].get("free") or (o.type == 'lot' and not anyBuilding): continue
			var key := 'OBJ:%s' % o.id
			var ok := false
			if o.type == 'lot':
				var f = Sim.fieldOf(key)
				var d := Sim.doorOf(o)
				var di := Sim.tIdx(d.tx, d.ty)
				for i in f.size():
					if f[i] >= 0 and Sim.occ[i] == 0 and i != di: ok = true; break
			else: ok = Sim.connected(key)
			if not ok: _warnCache.append(o)
	for o in _warnCache:
		var d := Sim.doorOf(o)
		var c: Vector2 = Sim.tileC(d.tx, d.ty)
		var bob := sin(t * 4) * 2
		if not vis(c.x - 30, c.y - 40, c.x + 30, c.y + 10): continue
		ctx.strokeStyle = 'rgba(232,67,46,0.9)'; ctx.lineWidth = 2; ctx.setLineDash([3, 3]); ctx.strokeRect(d.tx * Sim.TILE + 1, d.ty * Sim.TILE + 1, Sim.TILE - 2, Sim.TILE - 2); ctx.setLineDash([])
		ctx.fillStyle = '#e8432e'; ctx.beginPath(); ctx.arc(c.x, c.y - 22 + bob, 8, 0, TAU); ctx.fill()
		ctx.fillStyle = '#fff'; ctx.font = '800 11px'; ctx.textAlign = 'center'; ctx.fillText('!', c.x, c.y - 18 + bob)
		if cam.s > 0.8:
			ctx.fillStyle = 'rgba(9,28,17,0.85)'; ctx.fillRect(c.x - 36, c.y - 44 + bob, 72, 13)
			ctx.fillStyle = '#fff'; ctx.font = '800 8px'; ctx.fillText('NO FOOTPATH' if o.type == 'lot' else 'NOT CONNECTED', c.x, c.y - 35 + bob)
func drawBuildOverlay(ctx: Ctx2D) -> void:
	var tool: Dictionary = game.tool
	var TILE: float = Sim.TILE
	if tool.kind == 'suggest':
		var a := 0.35 + 0.2 * sin(t * 4)
		for i in tool.tiles:
			var x: float = (i % Sim.GW) * TILE
			var y: float = (i / Sim.GW) * TILE
			if not vis(x - 2, y - 2, x + TILE + 2, y + TILE + 2): continue
			ctx.fillStyle = Color(242 / 255.0, 193 / 255.0, 78 / 255.0, a); ctx.fillRect(x + 2, y + 2, TILE - 4, TILE - 4)
			ctx.strokeStyle = 'rgba(242,193,78,0.95)'; ctx.lineWidth = 1.5; ctx.setLineDash([4, 3]); ctx.strokeRect(x + 2, y + 2, TILE - 4, TILE - 4); ctx.setLineDash([])
	var V := art.V
	if cam.s > 0.55:
		ctx.strokeStyle = 'rgba(255,255,255,0.07)'; ctx.lineWidth = 1; ctx.beginPath()
		var x = floor(V.position.x / TILE) * TILE
		while x < V.end.x: ctx.moveTo(x, max(0.0, V.position.y)); ctx.lineTo(x, min(Sim.LAND_Y1, V.end.y)); x += TILE
		var y = floor(V.position.y / TILE) * TILE
		while y < min(Sim.LAND_Y1, V.end.y): ctx.moveTo(V.position.x, y); ctx.lineTo(V.end.x, y); y += TILE
		ctx.stroke()
	if Sim.TERRA.has(tool.kind): drawTerraOverlay(ctx, tool); return
	for o in Sim.objs():
		if Sim.OBJ[o.type].get("free"): continue
		var d := Sim.doorOf(o)
		ctx.strokeStyle = 'rgba(127,224,154,0.9)' if (o.type == 'lot' or not _warnCache.has(o)) else 'rgba(232,67,46,0.9)'
		ctx.lineWidth = 2; ctx.strokeRect(d.tx * TILE + 2, d.ty * TILE + 2, TILE - 4, TILE - 4)
	var ghost = game.get("ghostT")
	if tool.kind == 'place' and ghost:
		var mo = Sim.objById(tool.moveId) if tool.get("moveId") else null
		var go: Dictionary
		if mo and mo.type == 'range':
			go = Sim.shiftRange(mo, ghost.tx); go.y = ghost.ty
		else: go = { "type": tool.type, "x": ghost.tx, "y": ghost.ty, "id": -1 }
		var f := Sim.fp(go)
		var ok: bool = ghost.ok and Sim.S.money >= (0 if tool.get("moveId") else Sim.OBJ[tool.type].cost)
		ctx.fillStyle = 'rgba(127,224,154,0.35)' if ok else 'rgba(232,67,46,0.35)'; ctx.fillRect(f.x * TILE, f.y * TILE, f.w * TILE, f.h * TILE)
		ctx.strokeStyle = '#7fe09a' if ok else '#e8432e'; ctx.lineWidth = 2; ctx.strokeRect(f.x * TILE, f.y * TILE, f.w * TILE, f.h * TILE)
		var d := Sim.doorOf(go)
		if not Sim.OBJ[tool.type].get("free"): ctx.fillStyle = '#f2c14e'; ctx.fillRect(d.tx * TILE + 4, d.ty * TILE + 4, TILE - 8, TILE - 8)
		ctx.fillStyle = '#fff'; ctx.font = '800 12px'; ctx.textAlign = 'center'
		ctx.fillText(Sim.OBJ[tool.type].label, f.x * TILE + f.w * TILE / 2, f.y * TILE - 6)
	var hover = tool.get("hover")
	if (tool.kind == 'path' or tool.kind == 'unpath' or tool.kind == 'erase') and hover:
		ctx.strokeStyle = '#f2c14e' if tool.kind == 'path' else '#e8432e'; ctx.lineWidth = 2; ctx.strokeRect(hover.tx * TILE + 1, hover.ty * TILE + 1, TILE - 2, TILE - 2)
## landscaping: contour lines every metre, and the brush
var _contours := { "ver": -1, "minor": PackedVector2Array(), "major": PackedVector2Array() }
func _contourSegs() -> Dictionary:
	if _contours.ver == Sim.TER.ver: return _contours
	_contours.ver = Sim.TER.ver
	var minor := PackedVector2Array()
	var major := PackedVector2Array()
	var Q := 2
	var s: float = Sim.TILE / float(Q)
	var NX: int = Sim.GW * Q
	var NY: int = Sim.LAND_ROWS * Q
	var f := PackedFloat32Array(); f.resize(NX * NY)
	for y in NY:
		for x in NX: f[y * NX + x] = Sim.hmAt((x + 0.5) * s, (y + 0.5) * s)
	var o := s / 2
	for y in NY - 1:
		for x in NX - 1:
			var a := f[y * NX + x]
			var b := f[y * NX + x + 1]
			var c := f[(y + 1) * NX + x + 1]
			var d := f[(y + 1) * NX + x]
			var lo := int(ceil(min(a, b, c, d)))
			var hi := int(floor(max(a, b, c, d)))
			if hi < lo: continue
			var C := [[x, y, a], [x + 1, y, b], [x + 1, y + 1, c], [x, y + 1, d]]
			for lv in range(lo, hi + 1):
				var cut := []
				for k in 4:
					var p0: Array = C[k]
					var p1: Array = C[(k + 1) % 4]
					if (p0[2] >= lv) != (p1[2] >= lv):
						var tt: float = (lv - p0[2]) / (p1[2] - p0[2])
						cut.append(Vector2((p0[0] + (p1[0] - p0[0]) * tt) * s + o, (p0[1] + (p1[1] - p0[1]) * tt) * s + o))
				var P := major if lv % 5 == 0 else minor
				for k in range(0, cut.size() - 1, 2): P.append(cut[k]); P.append(cut[k + 1])
	_contours.minor = minor; _contours.major = major
	return _contours
func drawTerraOverlay(ctx: Ctx2D, tool: Dictionary) -> void:
	var c := _contourSegs()
	ctx.flush()
	var k: float = max(0.5, cam.s)
	if c.minor.size(): ctx.ci.draw_multiline(c.minor, Color(1, 248 / 255.0, 215 / 255.0, 0.22), 1.0 / k)
	if c.major.size(): ctx.ci.draw_multiline(c.major, Color(1, 248 / 255.0, 215 / 255.0, 0.5), 1.8 / k)
	var hv = tool.get("hw")
	if not hv: return
	var R: float = (Sim.BRUSH[Sim.terBrush].r + 0.5) * Sim.TILE
	var op: String = tool.kind
	var col := '#7fd0ff' if op == 'water' else ('#d9c48a' if op == 'drain' else ('#ff9b6b' if op == 'lower' else '#f2c14e'))
	var tc := Sim.tileOf(hv.x, hv.y)
	var bad = Sim.terraWhy(op, tc.tx, tc.ty)
	ctx.strokeStyle = '#e8432e' if bad else col; ctx.lineWidth = 2 / k; ctx.setLineDash([6, 4])
	ctx.beginPath(); ctx.arc(tc.tx * Sim.TILE + Sim.TILE / 2.0, tc.ty * Sim.TILE + Sim.TILE / 2.0, R, 0, TAU); ctx.stroke(); ctx.setLineDash([])
	ctx.fillStyle = '#fff'; ctx.font = "800 %dpx" % roundi(12 / max(0.6, cam.s)); ctx.textAlign = 'center'
	var z: float = Sim.hmAt(hv.x, hv.y)
	ctx.fillText(("Water · bed %.1f m" % z) if Sim.isWaterTile(tc.tx, tc.ty) else ("%s%.1f m" % ['+' if z >= 0 else '', z]), tc.tx * Sim.TILE + Sim.TILE / 2.0, tc.ty * Sim.TILE + Sim.TILE / 2.0 - R - 6)
func drawDesignOverlay(ctx: Ctx2D) -> void:
	var draft = Sim.draft
	if draft == null: return
	var k: float = max(0.7, cam.s)
	for p in Sim.PARCELS:
		if not vis(p.x0, p.y0, p.x1, p.y1): continue
		var own: bool = draft.land.has(p.id)
		var sel: bool = Sim.selParcel == p.id
		if not own: ctx.fillStyle = 'rgba(8,18,10,0.5)'; ctx.fillRect(p.x0, p.y0, p.x1 - p.x0, p.y1 - p.y0)
		ctx.strokeStyle = '#f2c14e' if sel else ('rgba(255,255,255,0.18)' if own else 'rgba(255,255,255,0.4)'); ctx.lineWidth = 4 if sel else 1.5; ctx.setLineDash([] if sel else [10, 8])
		ctx.strokeRect(p.x0 + 2, p.y0 + 2, p.x1 - p.x0 - 4, p.y1 - p.y0 - 4); ctx.setLineDash([])
		if not own and (Sim.dTool == 'land' or cam.s < 0.9):
			ctx.fillStyle = 'rgba(255,255,255,0.9)'; ctx.font = '800 13px'; ctx.textAlign = 'center'
			ctx.fillText(Sim.fmt(Sim.parcelPrice()), (p.x0 + p.x1) / 2, (p.y0 + p.y1) / 2)
	for ti in Sim.draftClear:
		var tr = Sim.trees[ti] if ti < Sim.trees.size() else null
		if not tr or not vis(tr.x - 10, tr.y - 10, tr.x + 10, tr.y + 10): continue
		ctx.strokeStyle = 'rgba(232,67,46,0.85)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(tr.x - 5, tr.y - 5); ctx.lineTo(tr.x + 5, tr.y + 5); ctx.moveTo(tr.x + 5, tr.y - 5); ctx.lineTo(tr.x - 5, tr.y + 5); ctx.stroke()
	var sf = null
	if Sim.dTool == 'adjust' and Sim.selFeat != null:
		for o in draft.feats:
			if o.id == Sim.selFeat: sf = o
	if sf:
		var F = Sim.FEATS[sf.type]
		ctx.strokeStyle = '#f2c14e'; ctx.lineWidth = 2.5 / k; ctx.setLineDash([6, 4]); ctx.beginPath(); ctx.ellipse(sf.x, sf.y, F.rx + 6, F.ry + 6, sf.get("rot", 0.0), 0, TAU); ctx.stroke(); ctx.setLineDash([])
	var m = game.get("hoverWorld") if game else null
	if Sim.dTool == 'place':
		if Sim.dPlaceTee:
			ctx.fillStyle = '#f2c14e'; ctx.beginPath(); ctx.arc(Sim.dPlaceTee.x, Sim.dPlaceTee.y, 9 / k, 0, TAU); ctx.fill()
			if m:
				var yd := roundi(Vector2(m.x - Sim.dPlaceTee.x, m.y - Sim.dPlaceTee.y).length() * Sim.YARDS_PER_UNIT / 5) * 5
				var ok: bool = yd >= Sim.MIN_YD and yd <= Sim.MAX_YD and Sim.validSpot(draft, m.x, m.y)
				ctx.strokeStyle = '#f2c14e' if ok else '#e8432e'; ctx.lineWidth = 3; ctx.setLineDash([8, 6]); ctx.beginPath(); ctx.moveTo(Sim.dPlaceTee.x, Sim.dPlaceTee.y); ctx.lineTo(m.x, m.y); ctx.stroke(); ctx.setLineDash([])
				ctx.fillStyle = '#fff'; ctx.font = "800 %dpx" % roundi(13 / k); ctx.textAlign = 'center'
				ctx.fillText("%d yd · par %d" % [yd, Sim.parForYards(yd)], (m.x + Sim.dPlaceTee.x) / 2, (m.y + Sim.dPlaceTee.y) / 2 - 10)
		elif m:
			ctx.strokeStyle = '#f2c14e' if Sim.validSpot(draft, m.x, m.y) else '#e8432e'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(m.x, m.y, 10 / k, 0, TAU); ctx.stroke()
	var h = draft.holes[Sim.selHole]
	if not h.get("placed"): return
	var v := Sim.holeValid(draft, Sim.draftGeo, Sim.selHole)
	var col := '#f2c14e' if v.ok else '#e8432e'
	strokeHole(ctx, Sim.selHole, -0.02, 1.1, 104, 'rgba(242,193,78,0.16)' if v.ok else 'rgba(232,67,46,0.2)')
	ctx.strokeStyle = col; ctx.lineWidth = 2; ctx.setLineDash([6, 6]); ctx.beginPath(); ctx.moveTo(h.tee.x, h.tee.y); ctx.lineTo(h.bend.x, h.bend.y); ctx.lineTo(h.green.x, h.green.y); ctx.stroke(); ctx.setLineDash([])
	if Sim.dTool == 'hole':
		for pr in [['tee', 'T'], ['bend', ''], ['green', 'G']]:
			var p = h[pr[0]]
			var r: float = (7.0 if pr[0] == 'bend' else 11.0) / k
			ctx.fillStyle = 'rgba(36,50,20,0.39)'; ctx.beginPath(); ctx.arc(p.x + 1.5, p.y + 1.5, r, 0, TAU); ctx.fill()
			ctx.fillStyle = col; ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, TAU); ctx.fill()
			ctx.strokeStyle = '#12261a'; ctx.lineWidth = 2 / k; ctx.stroke()
			if pr[1] != '': ctx.fillStyle = '#12261a'; ctx.font = "800 %dpx" % roundi(12 / k); ctx.textAlign = 'center'; ctx.fillText(pr[1], p.x, p.y + 4 / k)
	var mid: Vector2 = Sim.hPt(Sim.selHole, 0.5)
	ctx.font = "800 %dpx" % roundi(13 / k); ctx.textAlign = 'center'
	var info = Sim.draftGeo.info[Sim.selHole]
	var lbl := "Hole %d · par %d · %d yd" % [Sim.selHole + 1, info.par, info.yards]
	var tw: float = ctx.measureText(lbl).width
	ctx.fillStyle = 'rgba(9,28,17,0.85)'; ctx.fillRect(mid.x - tw / 2 - 6, mid.y - 30 / k, tw + 12, 18 / k)
	ctx.fillStyle = '#fff'; ctx.fillText(lbl, mid.x, mid.y - 17 / k)
	if Sim.FEATS.has(Sim.dTool) and m:
		var F = Sim.FEATS[Sim.dTool]
		var ok: bool = Sim.validSpot(draft, m.x, m.y)
		var pr: float = 0.0 if (Sim.dTool == 'trees' or Sim.dTool == 'flowers') else Sim.dRot
		ctx.globalAlpha = 0.55; drawFeature(ctx, { "type": Sim.dTool, "x": m.x, "y": m.y, "rot": pr, "id": 0 }, 'all'); ctx.globalAlpha = 1
		ctx.strokeStyle = '#ffffff' if ok else '#e8432e'; ctx.lineWidth = 2; ctx.beginPath(); ctx.ellipse(m.x, m.y, F.rx + 3, F.ry + 3, pr, 0, TAU); ctx.stroke()

# =====================================================================================
# Moods: reaction icons above heads, and spoken lines in screen space
# =====================================================================================
const MOOD_COLOR := { "delighted": '#ff6f91', "happy": '#6fcf5f', "meh": '#f2c14e', "annoyed": '#ff9f43', "angry": '#e8432e' }
func anchor(v) -> Vector2: return Vector2(v.x, v.y - (4 if v.state == 'golf' else 0))
func _onEmote(v, kind: String, said, chance: float) -> void:
	var p := anchor(v)
	if not onScreen(p.x, p.y) or Sim.warp == 0: return
	bubbles = bubbles.filter(func(b): return not is_same(b.v, v))
	var crowded := false
	for b in bubbles:
		if b.t < 2.2 and abs(b.x - p.x) < 16 and abs(b.y - p.y) < 14: crowded = true; break
	if (not crowded or kind == 'delighted' or kind == 'angry') and bubbles.size() < 40:
		bubbles.append({ "v": v, "kind": kind, "t": 0.0, "x": p.x, "y": p.y, "dx": 12.0 if crowded else 0.0 })
	var talking := false
	for sp in speech:
		if abs(sp.x - p.x) < 60 and abs(sp.y - p.y) < 30: talking = true; break
	if said and not talking and randf() < chance and speech.size() < 6 and cam.s > 0.7:
		speech.append({ "v": v, "text": said, "t": 0.0, "x": p.x, "y": p.y })
func _onConfetti(p: Vector2) -> void:
	var cols := ['#f2c14e', '#e8432e', '#ffffff', '#7fd3ff', '#c6f27a']
	for k in 60: confetti.append({ "x": p.x, "y": p.y, "vx": Sim.rnd(-60, 60), "vy": Sim.rnd(-110, -30), "life": Sim.rnd(1.4, 2.4), "c": cols[k % 5] })
func drawFace(ctx: Ctx2D, x: float, y: float, r: float, kind: String) -> void:
	if kind == 'delighted':
		ctx.fillStyle = MOOD_COLOR.delighted
		ctx.beginPath(); ctx.moveTo(x, y + r * 0.9)
		ctx.bezierCurveTo(x - r * 1.6, y - r * 0.2, x - r * 0.6, y - r * 1.4, x, y - r * 0.4)
		ctx.bezierCurveTo(x + r * 0.6, y - r * 1.4, x + r * 1.6, y - r * 0.2, x, y + r * 0.9); ctx.fill()
		return
	ctx.fillStyle = MOOD_COLOR[kind]; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill()
	ctx.fillStyle = '#2b1d12'
	ctx.beginPath(); ctx.arc(x - r * 0.36, y - r * 0.22, r * 0.14, 0, TAU); ctx.fill()
	ctx.beginPath(); ctx.arc(x + r * 0.36, y - r * 0.22, r * 0.14, 0, TAU); ctx.fill()
	ctx.strokeStyle = '#2b1d12'; ctx.lineWidth = r * 0.16; ctx.lineCap = 'round'
	ctx.beginPath()
	if kind == 'happy': ctx.arc(x, y + r * 0.05, r * 0.45, 0.2 * PI, 0.8 * PI)
	elif kind == 'meh': ctx.moveTo(x - r * 0.38, y + r * 0.35); ctx.lineTo(x + r * 0.38, y + r * 0.35)
	else: ctx.arc(x, y + r * 0.75, r * 0.42, 1.2 * PI, 1.8 * PI)
	ctx.stroke()
	if kind == 'angry': ctx.beginPath(); ctx.moveTo(x - r * 0.6, y - r * 0.6); ctx.lineTo(x - r * 0.15, y - r * 0.4); ctx.moveTo(x + r * 0.6, y - r * 0.6); ctx.lineTo(x + r * 0.15, y - r * 0.4); ctx.stroke()
	ctx.lineCap = 'butt'
func _drawBubbles(ctx: Ctx2D) -> void:
	for b in bubbles:
		b.t += _dt
		if b.v.state != 'gone' and b.v.state != 'drive':
			var p := anchor(b.v); b.x = p.x; b.y = p.y
		if not vis(b.x - 12, b.y - 40, b.x + 12, b.y): continue
		var D := 2.6
		var pop: float = min(1.0, b.t / 0.16)
		var s: float = 0.6 + 0.55 * pop if pop < 1 else 1 + 0.05 * max(0.0, 1 - (b.t - 0.16) / 0.15)
		var a: float = min(1.0, (D - b.t) / 0.45)
		var x: float = b.x + 7 + b.dx
		var y: float = b.y - 24 - min(2.0, b.t * 2)
		ctx.save(); ctx.globalAlpha = max(0.0, a); ctx.translate(x, y); ctx.scale(s, s)
		ctx.fillStyle = 'rgba(36,50,20,0.24)'; ctx.beginPath(); ctx.arc(0.8, 1, 7.2, 0, TAU); ctx.fill()
		ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(0, 0, 7, 0, TAU); ctx.fill()
		ctx.beginPath(); ctx.moveTo(-4, 4.5); ctx.lineTo(-7, 9); ctx.lineTo(-1, 6.4); ctx.fill()
		drawFace(ctx, 0, 0, 4.6, b.kind)
		ctx.restore()
	bubbles = bubbles.filter(func(b): return b.t < 2.6)

# =====================================================================================
# Screen space: fog, heat haze, rain and speech
# =====================================================================================
func _draw_screen(ctx: Ctx2D) -> void:
	var sw := SW()
	var sh := SH()
	var fog = null
	for m in Sim.activeMods():
		if m.eff.get("fog"): fog = m
	if fog:
		var left: float = (fog.until - Sim.nowT()) / Sim.DAY_LEN * 24
		ctx.fillStyle = Color(225 / 255.0, 232 / 255.0, 236 / 255.0, min(1.0, left / 1.2) * 0.55); ctx.fillRect(0, 0, sw, sh)
	if Sim.modOn('heat') and Sim.daylight() > 0.5: ctx.fillStyle = 'rgba(255,170,70,0.07)'; ctx.fillRect(0, 0, sw, sh)
	if Sim.S.wx == 'rain' and not Sim.designing:
		var wind: float = Sim.W_().wind
		ctx.strokeStyle = 'rgba(200,225,245,0.45)'; ctx.lineWidth = 1
		ctx.beginPath()
		for r in Sim.rain:
			r.y += 1.1 * r.s * _dt; r.x += 0.15 * wind * _dt
			if r.y > 1: r.y = -0.02; r.x = randf()
			if r.x > 1: r.x -= 1
			var x: float = r.x * sw
			var y: float = r.y * sh
			ctx.moveTo(x, y); ctx.lineTo(x - 2 - wind * 3, y - 12)
		ctx.stroke()
	if speech.size():
		ctx.font = '800 12px'; ctx.textAlign = 'center'
		for sp in speech:
			sp.t += _dt
			if sp.v.state != 'gone' and sp.v.state != 'drive':
				var p := anchor(sp.v); sp.x = p.x; sp.y = p.y
			var sx: float = (sp.x - cam.x) * cam.s
			var sy: float = (sp.y - 36 - cam.y) * cam.s - 6 - sp.t * 9
			var a: float = min(1.0, sp.t / 0.25) * min(1.0, (3.2 - sp.t) / 1.2)
			ctx.globalAlpha = max(0.0, a)
			ctx.strokeStyle = 'rgba(10,25,15,0.7)'; ctx.lineWidth = 3.5; ctx.strokeText(sp.text, sx, sy)
			ctx.fillStyle = '#ffffff'; ctx.fillText(sp.text, sx, sy)
		ctx.globalAlpha = 1
		speech = speech.filter(func(sp): return sp.t < 3.2)
