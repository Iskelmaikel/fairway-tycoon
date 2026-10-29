class_name Art
extends RefCounted
## Art direction: "storybook diorama". One light from the upper left. Every object gets a warm
## shadow down and to the right, a body colour, a highlight on the lit side and a thin outline
## in a darker shade of its own colour. Colours come from this palette, so new things fit in.
## Shared drawing helpers and every animated sprite (people, carts, cars, mowers, birds).

const ART := {
	"wood": '#2c4529',
	"grass": '#6f9a4f', "rough": '#76a152', "fair": '#93bf63', "fringe": '#9fcb6a', "green": '#b0d97c', "greenHi": '#c6e797', "tee": '#a6cf70',
	"sand": '#efdca8', "water": '#4f9fc4', "waterHi": '#72b8d8', "waterLo": '#3d82a9', "bank": '#5b7f3e',
	"leaf": ['#3f6f3d', '#487a42'], "leafMid": ['#548c49', '#5d9550'], "leafHi": '#7caf63', "pine": '#355f37', "pineHi": '#4f8249',
	"timber": '#8a6744', "path": '#e8d9b0', "pathEdge": '#c9b588', "asphalt": '#6b6961', "paint": '#efe6cc',
	"roof": '#c4674b', "slate": '#5f7187', "moss": '#6f8f5a', "tin": '#8c9890', "wall": '#f1e6cb', "floorDirt": '#cdb98a',
	"red": '#e2553f', "gold": '#f2c14e', "blue": '#3f6f9e', "ink": '#2b2a1f', "cream": '#fbf3dc',
	"SH": 'rgba(36,50,20,0.32)', "SX": 4.0, "SY": 5.0,
}

var ctx: Ctx2D
var camS := 1.0          # current zoom, for level-of-detail choices
var simTime := 0.0
var V := Rect2()         # the visible world rectangle

func _init(c: Ctx2D) -> void: ctx = c

func vis(x0: float, y0: float, x1: float, y1: float) -> bool:
	return x1 >= V.position.x and x0 <= V.end.x and y1 >= V.position.y and y0 <= V.end.y

# ---------- colour helpers ----------
static var _tint := {}
## lighten (k > 0) or darken (k < 0) a palette colour; cached
static func tint(hex, k: float) -> Color:
	var key := str(hex) + str(k)
	if _tint.has(key): return _tint[key]
	var c := Ctx2D.col(hex)
	var f := func(v: float) -> float: return clampf(v * (1 + k) if k < 0 else v + (1 - v) * k, 0, 1)
	var out := Color(f.call(c.r), f.call(c.g), f.call(c.b), c.a)
	_tint[key] = out
	return out
## fill the current path with an outline that only shows outside it
func inkFill(c, w := 1.3) -> void:
	ctx.strokeStyle = tint(c, -0.38); ctx.lineWidth = w * 2; ctx.lineJoin = 'round'; ctx.stroke()
	ctx.fillStyle = c; ctx.fill()
func poly(pts: Array, c) -> void:
	ctx.fillStyle = c; ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1])
	for k in range(1, pts.size()): ctx.lineTo(pts[k][0], pts[k][1])
	ctx.closePath(); ctx.fill()
## a hipped roof seen from above: four faces lit from the upper left, tiles, a ridge and a shadow
func hipRoof(x: float, y: float, w: float, h: float, base, opt := {}) -> void:
	var ht: float = opt.get("height", 1.0)
	var hi := tint(base, 0.18)
	var lo := tint(base, -0.16)
	var side := tint(base, 0.07)
	var ink := tint(base, -0.42)
	ctx.fillStyle = ART.SH; ctx.fillRect(x + ART.SX * ht, y + ART.SY * ht, w, h)
	var horiz := w >= h
	var i := (h if horiz else w) / 2
	var a := [x + i, y + h / 2] if horiz else [x + w / 2, y + i]
	var b := [x + w - i, y + h / 2] if horiz else [x + w / 2, y + h - i]
	var NW := [x, y]
	var NE := [x + w, y]
	var SE := [x + w, y + h]
	var SW_ := [x, y + h]
	var faces := [[[NW, NE, b, a], hi], [[SW_, SE, b, a], base], [[NW, a, SW_], side], [[NE, b, SE], lo]] if horiz \
		else [[[NW, SW_, b, a], hi], [[NE, SE, b, a], base], [[NW, a, NE], side], [[SW_, b, SE], lo]]
	for f in faces: poly(f[0], f[1])
	if opt.get("tiles", true) and camS > 0.7:
		ctx.strokeStyle = 'rgba(40,20,10,0.13)'; ctx.lineWidth = 1; ctx.beginPath()
		if horiz:
			var yy := y + 4
			while yy < y + h: ctx.moveTo(x, yy); ctx.lineTo(x + w, yy); yy += 4
		else:
			var xx := x + 4
			while xx < x + w: ctx.moveTo(xx, y); ctx.lineTo(xx, y + h); xx += 4
		ctx.stroke()
	ctx.strokeStyle = ink; ctx.lineWidth = 1.2; ctx.lineJoin = 'round'
	ctx.beginPath(); ctx.moveTo(NW[0], NW[1]); ctx.lineTo(a[0], a[1]); ctx.lineTo(SW_[0], SW_[1]); ctx.moveTo(NE[0], NE[1]); ctx.lineTo(b[0], b[1]); ctx.lineTo(SE[0], SE[1]); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke()
	ctx.lineWidth = 1.6; ctx.strokeRect(x, y, w, h)
	ctx.strokeStyle = tint(base, 0.35); ctx.lineWidth = 1; ctx.beginPath()
	ctx.moveTo(a[0] - (0.0 if horiz else 0.8), a[1] - (0.8 if horiz else 0.0)); ctx.lineTo(b[0] - (0.0 if horiz else 0.8), b[1] - (0.8 if horiz else 0.0)); ctx.stroke()
## a small wooden sign with painted lettering
func woodSign(x: float, y: float, text: String, size := 7.0) -> void:
	ctx.font = "800 %spx" % size; ctx.textAlign = 'center'
	var w: float = ctx.measureText(text).width + size * 1.4
	var h := size * 1.7
	ctx.fillStyle = ART.SH; ctx.fillRect(x - w / 2 + 2, y - h / 2 + 2.5, w, h)
	ctx.fillStyle = tint(ART.timber, -0.25); ctx.fillRect(x - 1, y + h / 2 - 1, 2, 4)
	ctx.fillStyle = ART.timber; ctx.fillRect(x - w / 2, y - h / 2, w, h)
	ctx.fillStyle = tint(ART.timber, 0.15); ctx.fillRect(x - w / 2, y - h / 2, w, 1.5)
	ctx.strokeStyle = tint(ART.timber, -0.4); ctx.lineWidth = 1; ctx.strokeRect(x - w / 2, y - h / 2, w, h)
	ctx.fillStyle = ART.cream; ctx.fillText(text, x, y + size * 0.36)

# ---------- trees, water, bunkers ----------
func _star(R: float, n0: float, ox: float, oy: float) -> void:
	for j in 16:
		var a := j / 16.0 * TAU + n0
		var rr := R * 0.8 if j % 2 else R
		if j: ctx.lineTo(ox + cos(a) * rr, oy + sin(a) * rr)
		else: ctx.moveTo(ox + cos(a) * rr, oy + sin(a) * rr)
	ctx.closePath()
func paintTree(t) -> void:
	var r: float = t.r
	var x: float = t.x
	var y: float = t.y
	var s: float = t.s
	ctx.fillStyle = ART.SH; ctx.beginPath(); ctx.ellipse(x + ART.SX * 1.3, y + ART.SY * 1.3, r * 1.02, r * 0.9, 0, 0, TAU); ctx.fill()
	if t.kind == 'pine':
		for ps in 2:
			ctx.save(); ctx.translate(x, y)
			if ps == 0: ctx.scale(1.07, 1.07)
			ctx.beginPath(); _star(r * 0.95, s, 0, 0)
			ctx.fillStyle = tint(ART.pine, -0.38) if ps == 0 else Ctx2D.col(ART.pine); ctx.fill(); ctx.restore()
		ctx.fillStyle = tint(ART.pine, 0.12); ctx.beginPath(); _star(r * 0.68, 0.3 + s, x - r * 0.12, y - r * 0.13); ctx.fill()
		ctx.fillStyle = ART.pineHi; ctx.beginPath(); _star(r * 0.4, 0.6 + s, x - r * 0.22, y - r * 0.24); ctx.fill()
		return
	var v := 1 if s > 0.5 else 0
	# a leafy crown: a few overlapping clumps
	for ps in 2:
		ctx.save(); ctx.translate(x, y)
		if ps == 0: ctx.scale(1.07, 1.07)
		ctx.beginPath(); ctx.arc(0, 0, r * 0.78, 0, TAU)
		for k in 5:
			var a := k / 5.0 * TAU + s * 6
			ctx.moveTo(cos(a) * r * 0.42 + r * 0.5, sin(a) * r * 0.42); ctx.arc(cos(a) * r * 0.42, sin(a) * r * 0.42, r * 0.5, 0, TAU)
		ctx.fillStyle = tint(ART.leaf[v], -0.38) if ps == 0 else Ctx2D.col(ART.leaf[v]); ctx.fill(); ctx.restore()
	ctx.fillStyle = ART.leafMid[v]; ctx.beginPath(); ctx.arc(x - r * 0.2, y - r * 0.22, r * 0.62, 0, TAU); ctx.fill()
	ctx.fillStyle = ART.leafHi; ctx.beginPath(); ctx.arc(x - r * 0.38, y - r * 0.42, r * 0.28, 0, TAU); ctx.fill()
func water(x: float, y: float, rx: float, ry: float, rot: float) -> void:
	ctx.save(); ctx.translate(x, y); ctx.rotate(rot)
	ctx.fillStyle = ART.bank; ctx.beginPath(); ctx.ellipse(0, 0, rx + 4, ry + 4, 0, 0, TAU); ctx.fill()
	ctx.fillStyle = ART.water; ctx.beginPath(); ctx.ellipse(0, 0, rx, ry, 0, 0, TAU); ctx.fill()
	ctx.fillStyle = ART.waterHi; ctx.beginPath(); ctx.ellipse(-rx * 0.08, -ry * 0.1, rx * 0.82, ry * 0.74, 0, 0, TAU); ctx.fill()
	ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 1.4
	for k in 3:
		ctx.beginPath(); ctx.arc(-rx * 0.35 + k * rx * 0.33, -ry * 0.25 + k * ry * 0.18, min(rx, ry) * 0.22, PI * 1.1, PI * 1.85); ctx.stroke()
	ctx.fillStyle = ART.bank
	for k in 6:
		var a := k * 1.05 + 0.4
		ctx.fillRect(cos(a) * (rx + 2) - 1, sin(a) * (ry + 2) - 3, 2, 5)
	ctx.restore()
func _bunkerShape(rx: float, ry: float, dx := 0.0, dy := 0.0) -> void:
	ctx.ellipse(dx, dy, rx, ry, 0, 0, TAU)
	ctx.moveTo(dx + rx * 1.15, dy + ry * 0.45); ctx.ellipse(dx + rx * 0.55, dy + ry * 0.45, rx * 0.6, ry * 0.65, 0, 0, TAU)
func bunker(x: float, y: float, rx: float, ry: float, rot: float) -> void:
	ctx.save(); ctx.translate(x, y); ctx.rotate(rot)
	ctx.beginPath(); _bunkerShape(rx, ry); inkFill(ART.sand, 0.6)
	# the lip shades the side of the hollow nearest the light
	ctx.save(); ctx.beginPath(); _bunkerShape(rx, ry); ctx.clip()
	ctx.fillStyle = tint(ART.sand, -0.16); ctx.fillRect(-rx * 3, -rx * 3, rx * 6, rx * 6)
	ctx.fillStyle = ART.sand; ctx.beginPath(); _bunkerShape(rx, ry, 1.8 * cos(rot) + 2.2 * sin(rot), -1.8 * sin(rot) + 2.2 * cos(rot)); ctx.fill()
	ctx.restore()
	ctx.fillStyle = 'rgba(255,250,230,0.35)'; ctx.beginPath(); ctx.ellipse(rx * 0.15, ry * 0.25, rx * 0.4, ry * 0.25, 0, 0, TAU); ctx.fill()
	ctx.restore()

# =====================================================================================
# People: every person gets a stable look from their id. Poses are recorded once into
# small meshes and re-used, so a crowd costs a few draw calls instead of thousands of shapes.
# =====================================================================================
const SKIN := ['#f6d7b8', '#ebbd93', '#d19a6c', '#a8714a', '#7a4d2e', '#5a3820']
const HAIR := ['#2b2118', '#3b2a1e', '#5a3b24', '#8a5a32', '#c9a063', '#e3cf9a', '#a8452a', '#8e8e8e', '#d9d6cf']
const BOTTOMS := ['#e6dcc4', '#2c3a52', '#5b6168', '#f2f0ea', '#2b2f36', '#8a7a5a', '#3d5a40', '#a7b0b8']
const HATS := ['#ffffff', '#2c4a6e', '#e8432e', '#2b2f36', '#f2c14e', '#3f7d4f', '#d9d4c4', '#7fa8bf']
const BAGC := ['#2b2f36', '#2c4a6e', '#e8432e', '#f5f5f0', '#3f7d4f', '#7a4f2c', '#f2c14e', '#9b2d3a']
const UNIFORM := {
	"shop":    { "shirt": '#2c4a6e', "hat": null, "bottom": '#2b2f36', "legs": 'trousers' },
	"shop2":   { "shirt": '#1f6b3a', "hat": null, "bottom": '#2b2f36', "legs": 'trousers' },
	"owner":   { "shirt": '#7a1f2b', "hat": null, "bottom": '#2b2f36', "legs": 'trousers' },
	"chef":    { "shirt": '#ffffff', "hat": 'chef', "hatC": '#ffffff', "bottom": '#2b2f36', "legs": 'trousers', "apron": '#e9e9e4' },
	"bar":     { "shirt": '#f4f4f0', "vest": '#2b2f36', "hat": null, "bottom": '#2b2f36', "legs": 'trousers' },
	"attend":  { "shirt": '#3a4a5a', "vest": '#ff8a3d', "hat": 'cap', "hatC": '#ff8a3d', "bottom": '#2b2f36', "legs": 'trousers' },
	"picker":  { "shirt": '#3a7bd5', "hat": 'cap', "hatC": '#ffffff', "bottom": '#5b6168', "legs": 'shorts' },
	"marshal": { "shirt": '#1f3a5f', "hat": 'cap', "hatC": '#ffffff', "bottom": '#e6dcc4', "legs": 'trousers', "band": '#ffb31a' },
	"keeper":  { "shirt": '#3d5a40', "vest": '#d8f24a', "hat": 'cap', "hatC": '#3d5a40', "bottom": '#3d5a40', "legs": 'trousers' },
	"starter": { "shirt": '#14365a', "hat": 'cap', "hatC": '#14365a', "bottom": '#8a7a5a', "legs": 'trousers' },
	"coach":   { "shirt": '#ffffff', "hat": 'visor', "hatC": '#2c4a6e', "bottom": '#2c3a52', "legs": 'trousers' },
}
static var _lookSeq := 0
func lookOf(o, shirt = null) -> Dictionary:
	var want = shirt if shirt else o.get("color", '#ffffff')
	var lk = o.get("_lk")
	if lk and lk.shirt == want: return lk
	var r := Sim.seeded(((int(o.get("id", 0))) + 7) * 7919 % 2147483646 + 1)
	r.call(); r.call()
	var pk := func(a: Array): return a[int(floor(r.call() * a.size()))]
	var older: bool = r.call() < 0.22
	var style: String = pk.call(['short', 'short', 'side', 'long', 'pony', 'curly', 'bald', 'short'])
	var hatR: float = r.call()
	_lookSeq += 1
	lk = {
		"key": _lookSeq,
		"shirt": want, "skin": pk.call(SKIN), "hair": pk.call(['#8e8e8e', '#d9d6cf', '#bdb8ae']) if older else pk.call(HAIR),
		"style": 'short' if (older and style == 'long') else style,
		"hat": 'cap' if hatR < 0.3 else ('visor' if hatR < 0.38 else ('bucket' if hatR < 0.43 else null)), "hatC": pk.call(HATS),
		"bottom": pk.call(BOTTOMS), "legs": 'shorts' if r.call() < 0.3 else 'trousers', "shoes": '#f4f4f0' if r.call() < 0.55 else '#2b2f36',
		"build": 0.9 + r.call() * 0.25, "h": 0.95 + r.call() * 0.1, "bag": pk.call(BAGC), "trolley": r.call() < 0.35,
		"umb": pk.call(['#e8432e', '#2c4a6e', '#f2c14e', '#ffffff', '#3f7d4f', '#2b2f36']),
		"vest": null, "apron": null, "band": null,
	}
	if (lk.style == 'long' or lk.style == 'pony') and r.call() < 0.35: lk.legs = 'skirt'
	o["_lk"] = lk
	return lk
var _staffLooks := {}
func staffLook(role: String, id := 0) -> Dictionary:
	var key := "%s:%d" % [role, id]
	if _staffLooks.has(key): return _staffLooks[key]
	var lk: Dictionary = lookOf({ "id": 9000 + id * 31 + role.length() * 7 }).duplicate()
	lk.merge(UNIFORM.get(role, {}), true)
	_lookSeq += 1; lk.key = _lookSeq
	_staffLooks[key] = lk
	return lk
## walking: each walker's stride follows the distance they actually cover
func gait(o, dt: float) -> Dictionary:
	var g = o.get("_g")
	if g == null:
		g = { "x": o.x, "y": o.y, "ph": randf() * 6, "idle": 9.0, "dir": PI / 2, "moving": false }
		o["_g"] = g
		return g
	var dx: float = o.x - g.x
	var dy: float = o.y - g.y
	var d := sqrt(dx * dx + dy * dy)
	g.x = o.x; g.y = o.y
	if d > 0.02 and d < 40: g.ph += d * 0.55; g.idle = 0.0; g.dir = atan2(dy, dx); g.moving = true
	else: g.idle += dt; g.moving = g.idle < 0.12 and g.moving
	return g
static func faceOf(ang: float) -> String:
	var c := cos(ang)
	var s := sin(ang)
	if abs(c) > abs(s) * 1.1: return 'E' if c > 0 else 'W'
	return 'S' if s > 0 else 'N'
const SWING_K := [0, 0.14, 0.5, 0.6, 0.7, 0.86, 1]
const SWING_H := [0, -0.3, -2.05, 0.02, 1.35, 2.25, 2.2]
const SWING_C := [0.04, -0.45, -4.35, 0.08, 1.7, 5.0, 5.0]
static func swingAt(k: float, amp: float) -> Dictionary:
	k = clampf(k, 0, 1)
	var i := 0
	while i < SWING_K.size() - 2 and k > SWING_K[i + 1]: i += 1
	var f: float = (k - SWING_K[i]) / (SWING_K[i + 1] - SWING_K[i])
	f = f * f * (3 - 2 * f)
	var h: float = SWING_H[i] + (SWING_H[i + 1] - SWING_H[i]) * f
	var c: float = SWING_C[i] + (SWING_C[i + 1] - SWING_C[i]) * f
	return { "h": h * amp, "c": c * (amp * 0.85 if amp < 1 else 1.0) }
func limb(x0: float, y0: float, x1: float, y1: float, w: float, c0, c1, split := 0.5) -> void:
	var mx := x0 + (x1 - x0) * split
	var my := y0 + (y1 - y0) * split
	ctx.lineWidth = w; ctx.strokeStyle = c0; ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(mx, my); ctx.stroke()
	ctx.strokeStyle = c1; ctx.beginPath(); ctx.moveTo(mx, my); ctx.lineTo(x1, y1); ctx.stroke()

# ---- the pose cache ----
var _poses := {}
var _poseUse := {}
var _frame := 0
func tickCache() -> void:
	_frame += 1
	if _frame % 600 == 0:
		for k in _poseUse.keys():
			if _frame - _poseUse[k] > 1200: _poses.erase(k); _poseUse.erase(k)
func _q(x: float, steps: float) -> int: return int(round(x * steps))

## a person. p: { ang, walk (phase or null), act: swing|chip|putt|address|cheer|slump|sit|bend|work|wave, k (0..1),
## flip, scale, carry: bag|bucket|basket|trolley|null, umbrella, look, face, load, club }
func drawPerson(x: float, y: float, lk: Dictionary, p := {}) -> void:
	var s: float = p.get("scale", 1.2) * lk.h
	var px := camS * s
	var fine := px > 2.1
	var act = p.get("act")
	var swingLike: bool = act == 'swing' or act == 'chip' or act == 'putt' or act == 'address'
	var simple := px < 1.15 and not swingLike
	var walk = p.get("walk")
	# the key: everything that changes the shape, quantised so poses are shared
	var dirKey := ''
	if not (swingLike or act == 'cheer' or act == 'slump' or act == 'wave' or act == 'sit'):
		dirKey = faceOf(p.get("ang", PI / 2) if p.get("ang") != null else PI / 2)
	var key := "%d|%s|%s|%s|%d|%d|%s|%s|%s|%d|%d|%d|%s" % [lk.key, act, dirKey, p.get("face", 'S'),
		(_q(fmod(walk, TAU), 12.0 / TAU) % 12) if (walk != null and not act) else -1,
		_q(p.get("k", 0.0), 40 if swingLike else 16), p.get("flip", false), p.get("carry"), p.get("umbrella", false),
		_q(p.get("look", 0.0), 5), _q(p.get("load", 0.0), 8), (1 if fine else 0) + (2 if simple else 0), p.get("club", true)]
	var mesh = _poses.get(key)
	if mesh == null:
		ctx.beginRecord()
		if simple: _personSimple(lk, p)
		else: _personFull(lk, p, fine)
		mesh = ctx.endRecord()
		_poses[key] = mesh
	_poseUse[key] = _frame
	ctx.emit(mesh, Transform2D(0.0, Vector2(s, s), 0.0, Vector2(x, y)) if ctx._xf == Transform2D.IDENTITY else ctx._xf * Transform2D(0.0, Vector2(s, s), 0.0, Vector2(x, y)), ctx.globalAlpha)

func _personSimple(lk: Dictionary, p: Dictionary) -> void:
	var act = p.get("act")
	var walking: bool = p.get("walk") != null and not act
	var ph: float = p.get("walk") if walking else 0.0
	var lift2 := sin(ph) * 1.1 if walking else 0.0
	var bob2 := 2.6 if act == 'sit' else 0.0
	ctx.fillStyle = 'rgba(36,50,20,0.24)'; ctx.fillRect(-2.6, -0.6, 6, 1.6)
	if act != 'sit':
		ctx.fillStyle = lk.bottom; ctx.fillRect(-2 + lift2 * 0.3, -5.6, 1.7, 5.4); ctx.fillRect(0.3 - lift2 * 0.3, -5.6, 1.7, 5.4)
	if p.get("carry") == 'bag': ctx.fillStyle = lk.bag; ctx.fillRect(1.6, -12 + bob2, 2.2, 8.5)
	ctx.fillStyle = lk.shirt; ctx.fillRect(-2.5, -11.2 + bob2, 5, 6)
	ctx.fillStyle = lk.skin; ctx.fillRect(-1.9, -15.4 + bob2, 3.8, 3.9)
	ctx.fillStyle = (lk.hatC if lk.hatC else '#ffffff') if (lk.hat == 'cap' or lk.hat == 'bucket' or lk.hat == 'chef') else lk.hair
	ctx.fillRect(-2.1, -15.8 + bob2, 4.2, 1.6)
	if p.get("umbrella"): ctx.fillStyle = lk.umb; ctx.fillRect(-5.5, -19.5, 11, 2.4)

func _personFull(lk: Dictionary, p: Dictionary, fine: bool) -> void:
	var act = p.get("act")
	var swingLike: bool = act == 'swing' or act == 'chip' or act == 'putt' or act == 'address'
	var dir: String
	if swingLike or act == 'cheer' or act == 'slump' or act == 'wave': dir = 'S'
	elif act == 'sit': dir = p.get("face", 'S') if p.get("face") else 'S'
	else: dir = faceOf(p.get("ang") if p.get("ang") != null else PI / 2)
	var side := dir == 'E' or dir == 'W'
	var walking: bool = p.get("walk") != null and not act
	var ph: float = p.get("walk") if walking else 0.0
	var step := sin(ph)
	var lift = abs(cos(ph)) if walking else 0.0
	var k: float = p.get("k", 0.0)
	# shadow on the ground
	ctx.fillStyle = 'rgba(36,50,20,0.26)'; ctx.beginPath(); ctx.ellipse(0.8, 0.4, 3.6 if act == 'sit' else 3.4, 1.35, 0, 0, TAU); ctx.fill()
	if dir == 'W' or p.get("flip", false): ctx.scale(-1, 1)
	var bob := 0.0
	if walking: bob = -lift * 0.55
	elif act == 'cheer': bob = -abs(sin(k * PI * 3)) * 1.6
	elif act == 'sit': bob = 2.6
	elif act == 'bend': bob = 1.6
	elif act == 'putt' or act == 'address': bob = 0.6
	var w: float = (3.3 if side else 4.8) * lk.build
	ctx.lineCap = 'round'; ctx.lineJoin = 'round'
	var legC = lk.bottom if lk.legs == 'trousers' else lk.skin
	var shoe = lk.shoes
	var sw = null
	var hipX := 0.0
	if swingLike:
		if act == 'putt':
			var hh := -sin(k / 0.5 * PI) * 0.3 if k < 0.5 else sin(min(1.0, (k - 0.5) / 0.25) * PI / 2) * 0.3
			sw = { "h": hh, "c": hh }
		elif act == 'address': sw = { "h": sin(k * TAU) * 0.12, "c": sin(k * TAU) * 0.2 }
		else: sw = swingAt(k, 0.5 if act == 'chip' else 1.0)
		if act == 'swing':
			if k > 0.6: hipX = min(1.0, (k - 0.6) / 0.2) * 0.9
			elif k > 0.15: hipX = -min(1.0, (k - 0.15) / 0.35) * 0.35
	var lean := 0.8 if (act == 'putt' or act == 'address') else (1.4 if act == 'bend' else 0.0)
	var top := -11.2 + bob + lean
	var waist := -5.4 + bob
	var turn: float = min(1.0, abs(sw.h) / 2.1) if (sw and act != 'putt') else 0.0
	var tw := w * (1 - 0.22 * turn)
	var tx = hipX * 0.6 + (sw.h * 0.15 if sw else 0.0)
	var club = null
	if sw:
		var R := 4.4 if act == 'putt' else 4.7
		var H := Vector2(tx + sin(sw.h) * R, top + 2.4 + cos(sw.h) * R + (0.6 if act == 'putt' else 0.0))
		var Lc := 6.4 if act == 'putt' else (7.6 if act == 'chip' else 8.6)
		club = { "H": H, "ex": H.x + sin(sw.c) * Lc, "ey": H.y + cos(sw.c) * Lc, "behind": act == 'swing' and ((k > 0.4 and k < 0.57) or k > 0.77) }
	var drawClub := func():
		var H: Vector2 = club.H
		ctx.lineWidth = 0.55; ctx.strokeStyle = '#d5dce2'; ctx.beginPath(); ctx.moveTo(H.x, H.y); ctx.lineTo(club.ex, club.ey); ctx.stroke()
		ctx.lineWidth = 0.9; ctx.strokeStyle = '#2b2f36'; ctx.beginPath(); ctx.moveTo(H.x, H.y); ctx.lineTo(H.x + sin(sw.c) * 1.4, H.y + cos(sw.c) * 1.4); ctx.stroke()
		ctx.save(); ctx.translate(club.ex, club.ey); ctx.rotate(-sw.c); ctx.fillStyle = '#9aa4ad' if act == 'putt' else '#3a4048'; ctx.fillRect(-1.3, -0.5, 2.1, 1.1); ctx.restore()
	# a chair to sit on
	if act == 'sit' and p.get("face", 'S') == 'S':
		ctx.fillStyle = '#6b4f30'; ctx.beginPath(); ctx.roundRect(-3.4, top - 0.4, 6.8, 6.2, 1.2); ctx.fill()
		ctx.fillStyle = '#5a3f24'; ctx.fillRect(-3.6, waist - 0.6, 7.2, 1.4)
	# a carried golf bag behind the body
	var bag: bool = p.get("carry") == 'bag' and act != 'sit'
	var drawBag := func():
		ctx.save(); ctx.translate(-1.9 if side else 1.6, -3.4 + bob); ctx.rotate(-0.24 if side else 0.32)
		ctx.fillStyle = lk.bag; ctx.fillRect(-1.25, -9.2, 2.5, 9.4)
		ctx.fillStyle = tint(lk.bag, -0.3); ctx.fillRect(-1.25, -2.6, 2.5, 1.1)
		ctx.fillStyle = '#cfd6dc'; ctx.fillRect(-1.1, -10.6, 0.8, 1.6); ctx.fillRect(0.2, -10.9, 0.9, 1.9)
		ctx.fillStyle = '#e8432e'; ctx.beginPath(); ctx.arc(-0.2, -10.4, 0.75, 0, TAU); ctx.fill()
		ctx.restore()
	if bag and dir != 'N': drawBag.call()
	var trolley: bool = p.get("carry") == 'trolley' and not act
	if trolley:
		var tx0 := -5.6 if side else 4.2
		var rock := sin(ph * 2) * 0.05 if walking else 0.0
		ctx.fillStyle = '#1d2023'; ctx.beginPath(); ctx.arc(tx0, -1.1, 1.15, 0, TAU); ctx.fill()
		if not side: ctx.beginPath(); ctx.arc(tx0 + 2.2, -1.3, 1.0, 0, TAU); ctx.fill()
		ctx.save(); ctx.translate(tx0 + (0.0 if side else 1.1), -1.6); ctx.rotate((-0.42 if side else -0.12) + rock)
		ctx.strokeStyle = '#9aa4ad'; ctx.lineWidth = 0.45; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(0, -9.5); ctx.stroke()
		ctx.fillStyle = lk.bag; ctx.fillRect(-1.2, -9, 2.4, 8); ctx.fillStyle = tint(lk.bag, -0.3); ctx.fillRect(-1.2, -3.2, 2.4, 1)
		ctx.fillStyle = '#cfd6dc'; ctx.fillRect(-1, -10.3, 0.8, 1.5); ctx.fillRect(0.2, -10.6, 0.8, 1.8)
		ctx.restore()
		ctx.strokeStyle = '#6c757d'; ctx.lineWidth = 0.45; ctx.beginPath(); ctx.moveTo(-3.3 if side else 3.1, -8.4 + bob); ctx.lineTo(-0.9 if side else 2.7, -6.1 + bob); ctx.stroke()
	# ---- legs ----
	if act != 'sit':
		var hip := -5.6 + bob
		if side:
			var a := step * 0.55 if walking else 0.0
			var fb := Vector2(-sin(a) * 5.6, -max(0.0, -cos(ph)) * (0.6 if walking else 0.0))
			var ff := Vector2(sin(a) * 5.6, -max(0.0, cos(ph)) * (0.6 if walking else 0.0))
			for pair in [[fb, true], [ff, false]]:
				var f: Vector2 = pair[0]
				var dark: bool = pair[1]
				var kneeX := f.x * 0.5 + (0.5 if walking else 0.0)
				var kneeY := hip + 3
				var upper = lk.bottom if legC == lk.skin else legC
				ctx.lineWidth = 1.6; ctx.strokeStyle = tint(upper, -0.25) if dark else Ctx2D.col(upper)
				ctx.beginPath(); ctx.moveTo(0, hip); ctx.lineTo(kneeX, kneeY); ctx.stroke()
				ctx.strokeStyle = tint(legC, -0.25) if dark else Ctx2D.col(legC); ctx.beginPath(); ctx.moveTo(kneeX, kneeY); ctx.lineTo(f.x, f.y - 0.4); ctx.stroke()
				ctx.fillStyle = shoe; ctx.beginPath(); ctx.ellipse(f.x + 0.5, f.y - 0.3, 1.1, 0.55, 0, 0, TAU); ctx.fill()
		else:
			var spread := 1.9 if (swingLike and act != 'putt') else (1.4 if act == 'putt' else (1.5 if act == 'bend' else 1.05))
			for sgn in [-1, 1]:
				var up = max(0.0, sin(ph + (PI if sgn > 0 else 0.0))) * 1.2 if walking else 0.0
				var toe = min(1.0, (k - 0.62) / 0.15) * 0.9 if (act == 'swing' and sgn < 0 and k > 0.62) else 0.0
				var fx = sgn * spread + (0.9 if toe else 0.0)
				var fy = -up - toe
				var hx = sgn * 1.05 + hipX
				var kx = (hx + fx) / 2 + (0.5 if toe else 0.0)
				var ky = hip + 2.9 - up * 0.5
				ctx.lineWidth = 1.75; ctx.strokeStyle = lk.bottom
				ctx.beginPath(); ctx.moveTo(hx, hip); ctx.lineTo(kx, ky); ctx.stroke()
				ctx.strokeStyle = legC; ctx.beginPath(); ctx.moveTo(kx, ky); ctx.lineTo(fx, fy - 0.5); ctx.stroke()
				ctx.fillStyle = shoe; ctx.beginPath(); ctx.ellipse(fx, fy - 0.35, 0.95, 0.6, 0, 0, TAU); ctx.fill()
		if lk.legs == 'skirt':
			ctx.fillStyle = lk.bottom; ctx.beginPath(); ctx.moveTo(-w / 2 + 0.3 + hipX, hip - 0.6); ctx.lineTo(w / 2 - 0.3 + hipX, hip - 0.6); ctx.lineTo(w / 2 + 0.6 + hipX, hip + 2.6); ctx.lineTo(-w / 2 - 0.6 + hipX, hip + 2.6); ctx.fill()
		elif lk.legs == 'shorts' and not side:
			ctx.fillStyle = lk.bottom; ctx.fillRect(-w / 2 + 0.2 + hipX, hip - 0.6, w - 0.4, 2.4)
	else:
		ctx.fillStyle = lk.bottom; ctx.fillRect(-w / 2 + 0.2, -3.6 + bob - 2.4, w - 0.4, 2.2)
		ctx.fillStyle = shoe; ctx.fillRect(-1.9, -0.9 + bob - 2.4, 1.4, 0.9); ctx.fillRect(0.5, -0.9 + bob - 2.4, 1.4, 0.9)
	# ---- body ----
	if club and club.behind: drawClub.call()
	ctx.fillStyle = lk.shirt
	ctx.beginPath(); ctx.roundRect(tx - tw / 2, top, tw, waist - top + 0.4, [1.6, 1.6, 0.8, 0.8]); ctx.fill()
	if fine:
		ctx.fillStyle = 'rgba(36,50,20,0.14)'; ctx.fillRect(tx + tw / 2 - tw * 0.32, top + 0.6, tw * 0.32, waist - top - 0.2)
		if lk.get("vest"):
			ctx.fillStyle = lk.vest; ctx.fillRect(tx - tw / 2 + 0.3, top + 1, tw - 0.6, waist - top - 1.4)
			if lk.vest == '#ff8a3d' or lk.vest == '#d8f24a': ctx.fillStyle = 'rgba(255,255,255,0.8)'; ctx.fillRect(tx - tw / 2 + 0.3, top + 3.6, tw - 0.6, 0.5)
		if lk.get("apron") and not side: ctx.fillStyle = lk.apron; ctx.fillRect(tx - tw / 2 + 0.6, top + 3.2, tw - 1.2, waist - top - 1.4)
		if not side and dir == 'S' and not lk.get("vest"):
			ctx.fillStyle = tint('#dddddd' if lk.shirt == '#ffffff' else lk.shirt, -0.25); ctx.beginPath(); ctx.moveTo(tx - 1.1, top + 0.1); ctx.lineTo(tx, top + 1.4); ctx.lineTo(tx + 1.1, top + 0.1); ctx.fill()
		if lk.legs != 'skirt': ctx.fillStyle = 'rgba(36,50,20,0.39)'; ctx.fillRect(tx - tw / 2 + 0.2, waist - 0.5, tw - 0.4, 0.55)
	if bag and dir == 'N': drawBag.call()
	if act == 'sit' and p.get("face") == 'N': ctx.fillStyle = '#6b4f30'; ctx.beginPath(); ctx.roundRect(-3.4, waist - 3.8, 6.8, 4.6, 1.2); ctx.fill()
	# ---- arms ----
	var sl = lk.shirt
	var sk = lk.skin
	var shY := top + 1.1
	var hands = null
	if sw:
		var H: Vector2 = club.H
		limb(tx - tw / 2 + 0.4, shY, H.x - 0.3, H.y, 1.25, sl, sk, 0.38)
		limb(tx + tw / 2 - 0.4, shY, H.x + 0.3, H.y, 1.25, sl, sk, 0.38)
		if not club.behind: drawClub.call()
		ctx.fillStyle = sk; ctx.beginPath(); ctx.arc(H.x, H.y, 0.75, 0, TAU); ctx.fill()
		if act == 'swing' and k > 0.56 and k < 0.72 and fine:
			ctx.strokeStyle = 'rgba(255,255,255,0.45)'; ctx.lineWidth = 0.8; ctx.beginPath(); ctx.arc(tx, top + 2.4, 13, PI * 0.42, PI * 0.85); ctx.stroke()
	elif act == 'cheer':
		var up: float = min(1.0, k * 5)
		var hy := shY - 4.8 * up + 2 * (1 - up)
		limb(tx - tw / 2 + 0.3, shY, tx - 3.6, hy, 1.3, sl, sk, 0.4)
		limb(tx + tw / 2 - 0.3, shY, tx + 3.6, hy, 1.3, sl, sk, 0.4)
		hands = [Vector2(tx - 3.6, hy), Vector2(tx + 3.6, hy)]
		if p.get("club", true) != false:
			ctx.lineWidth = 0.55; ctx.strokeStyle = '#d5dce2'; ctx.beginPath(); ctx.moveTo(hands[1].x, hands[1].y); ctx.lineTo(hands[1].x + 2.4, hands[1].y - 6.5); ctx.stroke()
	elif act == 'slump':
		limb(tx - tw / 2 + 0.3, shY, tx - 2.1, top - 3.2, 1.3, sl, sk, 0.45)
		limb(tx + tw / 2 - 0.3, shY, tx + 2.1, top - 3.2, 1.3, sl, sk, 0.45)
	elif act == 'sit' or act == 'work':
		var wv := sin(k * TAU) * 0.8 if act == 'work' else 0.0
		limb(tx - tw / 2 + 0.3, shY, tx - 1.6, waist - 1 + wv, 1.25, sl, sk, 0.45)
		limb(tx + tw / 2 - 0.3, shY, tx + 1.6, waist - 1 - wv, 1.25, sl, sk, 0.45)
	elif act == 'wave':
		limb(tx - tw / 2 + 0.3, shY, tx - w / 2 - 0.5, waist + 0.3, 1.25, sl, sk, 0.45)
		var a := sin(k * PI * 6) * 0.4
		limb(tx + tw / 2 - 0.3, shY, tx + 3 + sin(a) * 2, shY - 4.4, 1.25, sl, sk, 0.45)
	elif side:
		var a := -0.25 if trolley else (-step * 0.6 if walking else 0.0)
		var hx := sin(a) * 4.6
		var hy := shY + cos(a) * 4.6
		limb(0, shY, hx, hy, 1.35, sl, sk, 0.42)
		hands = [Vector2(hx, hy)]
	else:
		var a := step * 0.7 if walking else 0.0
		for sgn in [-1, 1]:
			var hx: float = tx + sgn * (tw / 2 + 0.35)
			var hy: float = waist + 0.4 + (sgn * a * 0.6 if walking else 0.0)
			limb(tx + sgn * (tw / 2 - 0.3), shY, hx, hy, 1.3, sl, sk, 0.42)
		hands = [Vector2(tx - tw / 2 - 0.35, waist + 0.4), Vector2(tx + tw / 2 + 0.35, waist + 0.4)]
	if lk.get("band") and not sw: ctx.fillStyle = lk.band; ctx.fillRect(-0.8 if side else tx - tw / 2 - 0.4, shY + 1.4, 1.6 if side else 1.4, 0.9)
	# things in hand
	var hand = hands[hands.size() - 1] if hands else null
	if hand != null and p.get("carry") == 'bucket':
		ctx.fillStyle = '#e8432e'; ctx.beginPath(); ctx.moveTo(hand.x - 1.4, hand.y + 0.4); ctx.lineTo(hand.x + 1.4, hand.y + 0.4); ctx.lineTo(hand.x + 1.1, hand.y + 3); ctx.lineTo(hand.x - 1.1, hand.y + 3); ctx.fill()
		ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.ellipse(hand.x, hand.y + 0.4, 1.3, 0.5, 0, 0, TAU); ctx.fill()
	elif hand != null and p.get("carry") == 'basket':
		ctx.strokeStyle = '#9aa4ad'; ctx.lineWidth = 0.4; ctx.strokeRect(hand.x - 1.6, hand.y, 3.2, 2.8)
		var lf: float = p.get("load", 0.0)
		ctx.fillStyle = '#ffffff'; ctx.fillRect(hand.x - 1.4, hand.y + 2.7 - 2.5 * lf, 2.8, 2.5 * lf)
		if hands[0] and not side:
			var tap = abs(sin(k * PI * 4)) * 1.2 if act == 'bend' else 0.0
			ctx.strokeStyle = '#d5dce2'; ctx.lineWidth = 0.7; ctx.beginPath(); ctx.moveTo(hands[0].x, hands[0].y - 1); ctx.lineTo(hands[0].x - 1.6, hands[0].y + 5.2 - tap); ctx.stroke()
	# ---- head ----
	var lookX: float = (min(1.0, (k - 0.66) / 0.12) * 0.8 if (act == 'swing' and k > 0.66) else 0.0) if sw else p.get("look", 0.0)
	var hx = tx + lookX * 0.4
	var hy := top - 2.25 + (0.5 if act == 'slump' else 0.0) + (0.3 if (sw and act != 'swing') else 0.0)
	ctx.fillStyle = sk; ctx.fillRect(hx - 0.7, top - 0.9, 1.4, 1.2)
	ctx.beginPath(); ctx.arc(hx, hy, 2.15, 0, TAU); ctx.fill()
	var hs = lk.style
	ctx.fillStyle = lk.hair
	if dir == 'N':
		if hs != 'bald': ctx.beginPath(); ctx.arc(hx, hy, 2.25, 0, TAU); ctx.fill()
		else: ctx.beginPath(); ctx.arc(hx, hy + 0.5, 2.2, 0.15, PI - 0.15); ctx.fill()
		if hs == 'long': ctx.fillRect(hx - 2.1, hy, 4.2, 3.4)
		if hs == 'pony': ctx.beginPath(); ctx.ellipse(hx, hy + 2.6, 0.9, 1.5, 0, 0, TAU); ctx.fill()
	elif side:
		if hs != 'bald': ctx.beginPath(); ctx.arc(hx - 0.25, hy - 0.2, 2.25, PI * 0.62, PI * 1.98); ctx.fill()
		if hs == 'long': ctx.fillRect(hx - 2.2, hy - 0.4, 1.9, 3.6)
		if hs == 'pony': ctx.beginPath(); ctx.ellipse(hx - 2.4, hy + 0.6, 0.8, 1.6, 0.4, 0, TAU); ctx.fill()
		ctx.fillStyle = sk; ctx.beginPath(); ctx.arc(hx + 2.05, hy + 0.3, 0.5, 0, TAU); ctx.fill()
		if fine: ctx.fillStyle = '#2b2118'; ctx.fillRect(hx + 0.95, hy - 0.25, 0.5, 0.55)
	else:
		if hs != 'bald':
			ctx.beginPath(); ctx.arc(hx, hy - 0.1, 2.25, PI * 1.02, PI * 1.98); ctx.fill()
			if hs == 'side': ctx.beginPath(); ctx.ellipse(hx - 0.7, hy - 1.1, 1.6, 0.8, 0.3, 0, TAU); ctx.fill()
			if hs == 'curly':
				for a in [-2.6, -1.9, -1.2, -0.5]:
					ctx.beginPath(); ctx.arc(hx + cos(a) * 1.9, hy - 0.2 + sin(a) * 1.9, 0.8, 0, TAU); ctx.fill()
			if hs == 'long': ctx.fillRect(hx - 2.3, hy - 0.6, 1, 3.6); ctx.fillRect(hx + 1.3, hy - 0.6, 1, 3.6)
		else: ctx.fillRect(hx - 2.2, hy - 0.2, 0.6, 1.2); ctx.fillRect(hx + 1.6, hy - 0.2, 0.6, 1.2)
		if fine:
			var ex := lookX * 0.5
			ctx.fillStyle = '#2b2118'; ctx.fillRect(hx - 1.05 + ex, hy + 0.05, 0.55, 0.6); ctx.fillRect(hx + 0.5 + ex, hy + 0.05, 0.55, 0.6)
			if act == 'cheer': ctx.fillStyle = '#7a2f22'; ctx.beginPath(); ctx.arc(hx + ex, hy + 1.2, 0.6, 0, PI); ctx.fill()
	# hats
	var hat = lk.hat
	if hat == 'chef':
		ctx.fillStyle = '#ffffff'; ctx.fillRect(hx - 1.7, hy - 3.6, 3.4, 2.2)
		ctx.beginPath(); ctx.arc(hx - 0.9, hy - 3.9, 1.2, 0, TAU); ctx.fill()
		ctx.beginPath(); ctx.arc(hx + 0.9, hy - 3.9, 1.2, 0, TAU); ctx.fill()
	elif hat == 'cap' or hat == 'visor':
		ctx.fillStyle = lk.hatC
		if hat == 'cap': ctx.beginPath(); ctx.arc(hx, hy - 0.35, 2.3, PI, TAU); ctx.fill()
		else: ctx.fillRect(hx - 2.2, hy - 1.3, 4.4, 0.8)
		ctx.fillStyle = tint(lk.hatC, -0.18)
		if side: ctx.fillRect(hx + 0.6, hy - 0.75, 2.9, 0.75)
		elif dir == 'S': ctx.beginPath(); ctx.ellipse(hx, hy - 0.45, 2.5, 0.75, 0, 0, PI); ctx.fill()
		elif hat == 'cap': ctx.fillStyle = tint(lk.hatC, -0.3); ctx.fillRect(hx - 0.6, hy - 0.4, 1.2, 0.5)
	elif hat == 'bucket':
		ctx.fillStyle = lk.hatC; ctx.beginPath(); ctx.arc(hx, hy - 0.6, 2.1, PI, TAU); ctx.fill()
		ctx.fillStyle = tint(lk.hatC, -0.15); ctx.beginPath(); ctx.ellipse(hx, hy - 0.5, 3.2, 0.85, 0, 0, TAU); ctx.fill()
	# an umbrella in the rain
	if p.get("umbrella"):
		var ux = hx + 0.6
		var uy = hy - 4.6 - (lift * 0.3 if walking else 0.0)
		ctx.strokeStyle = '#3a3f45'; ctx.lineWidth = 0.4; ctx.beginPath(); ctx.moveTo(ux, uy); ctx.lineTo(hx + 2.6, waist - 1.5); ctx.stroke()
		ctx.fillStyle = lk.umb; ctx.beginPath(); ctx.ellipse(ux, uy, 6.2, 2.7, 0, PI, TAU); ctx.lineTo(ux + 6.2, uy); ctx.fill()
		ctx.fillStyle = 'rgba(255,255,255,0.25)'; ctx.beginPath(); ctx.ellipse(ux - 1.6, uy - 1.3, 2.2, 0.8, -0.2, 0, TAU); ctx.fill()
		ctx.fillStyle = tint('#e0e0e0' if lk.umb == '#ffffff' else lk.umb, -0.25)
		var j := -3
		while j <= 3:
			ctx.beginPath(); ctx.arc(ux + j * 1.55, uy, 0.95, 0, PI); ctx.fill(); j += 2

# ---- seen from above: a person sitting in a vehicle ----
func drawRiderTop(x: float, y: float, lk: Dictionary, steer = null) -> void:
	ctx.fillStyle = lk.shirt; ctx.beginPath(); ctx.ellipse(x - 0.6, y, 1.7, 2.4, 0, 0, TAU); ctx.fill()
	if lk.get("vest"): ctx.fillStyle = lk.vest; ctx.beginPath(); ctx.ellipse(x - 0.6, y, 1.3, 2.0, 0, 0, TAU); ctx.fill()
	if steer: ctx.strokeStyle = lk.skin; ctx.lineWidth = 0.7; ctx.beginPath(); ctx.moveTo(x, y - 1.6); ctx.lineTo(steer.x, steer.y - 0.7); ctx.moveTo(x, y + 1.6); ctx.lineTo(steer.x, steer.y + 0.7); ctx.stroke()
	ctx.fillStyle = lk.skin; ctx.beginPath(); ctx.arc(x + 0.25, y, 1.45, 0, TAU); ctx.fill()
	if lk.hat == 'cap' or lk.hat == 'visor' or lk.hat == 'bucket':
		ctx.fillStyle = lk.hatC
		if lk.hat != 'visor': ctx.beginPath(); ctx.arc(x + 0.1, y, 1.45, 0, TAU); ctx.fill()
		ctx.fillStyle = tint(lk.hatC, -0.2); ctx.beginPath(); ctx.ellipse(x + 1.5, y, 0.8, 1.2, 0, -PI / 2, PI / 2); ctx.fill()
	elif lk.style != 'bald':
		ctx.fillStyle = lk.hair; ctx.beginPath(); ctx.arc(x - 0.05, y, 1.4, PI * 0.6, PI * 1.4); ctx.fill()
func wheel(x: float, y: float, l: float, w: float, moving: bool, t: float) -> void:
	ctx.fillStyle = '#1d2023'; ctx.beginPath(); ctx.roundRect(x - l / 2, y - w / 2, l, w, w / 2); ctx.fill()
	if moving:
		ctx.fillStyle = 'rgba(255,255,255,0.18)'
		var o := fmod(t * 26, 2.0)
		var kk := -l / 2 + o
		while kk < l / 2: ctx.fillRect(x + kk, y - w / 2, 0.5, w); kk += 2
## golf cart: open two-seater, bags strapped on the back. A marshal's cart has a roof and a beacon
func drawGolfCart(x: float, y: float, ang: float, o: Dictionary) -> void:
	var t: float = o.get("t", 0.0)
	var moving: bool = o.get("moving", false)
	var bob := sin(t * 21 + o.get("seed", 0)) * 0.18 if moving else 0.0
	var sc: float = o.get("scale", 1.0)
	ctx.save(); ctx.translate(x, y + bob); ctx.rotate(ang); ctx.scale(sc, sc)
	ctx.fillStyle = 'rgba(36,50,20,0.31)'; ctx.beginPath(); ctx.roundRect(-7.2, -3.6, 17, 10.6, 3); ctx.fill()
	for wpt in [[-5, -5.5], [-5, 5.5], [5, -5.3], [5, 5.3]]: wheel(wpt[0], wpt[1], 3.4, 1.5, moving, t)
	var body = o.get("body", '#f4f2ea')
	ctx.fillStyle = body; ctx.beginPath(); ctx.roundRect(-8.5, -5.3, 17, 10.6, [2, 4, 4, 2]); ctx.fill()
	ctx.fillStyle = 'rgba(36,50,20,0.11)'; ctx.fillRect(-8.5, 2.6, 17, 2.4)
	ctx.fillStyle = tint(body, 0.4); ctx.beginPath(); ctx.roundRect(4.4, -4.4, 3.8, 8.8, [0, 3, 3, 0]); ctx.fill()
	ctx.fillStyle = '#fff6c8'; ctx.fillRect(7.6, -4, 0.9, 1.4); ctx.fillRect(7.6, 2.6, 0.9, 1.4)
	if o.get("stripe"): ctx.fillStyle = o.stripe; ctx.fillRect(-8.5, -5.3, 17, 1.2); ctx.fillRect(-8.5, 4.1, 17, 1.2)
	ctx.fillStyle = '#2b2f36'; ctx.fillRect(3.2, -4.6, 1.1, 9.2)
	ctx.fillStyle = 'rgba(160,200,225,0.75)'; ctx.fillRect(3.9, -4.4, 0.5, 8.8)
	ctx.fillStyle = '#3a3f45'; ctx.beginPath(); ctx.roundRect(-3.6, -4.6, 4.4, 9.2, 1.2); ctx.fill()
	ctx.fillStyle = '#2b2f36'; ctx.fillRect(-3.9, -4.6, 1, 9.2)
	var bags: Array = o.get("bags", [])
	for k in bags.size():
		var by := 2.3 if k else -2.3
		var bx := -6.6
		ctx.fillStyle = bags[k]; ctx.beginPath(); ctx.arc(bx, by, 1.9, 0, TAU); ctx.fill()
		ctx.fillStyle = '#1d2023'; ctx.beginPath(); ctx.arc(bx, by, 1.2, 0, TAU); ctx.fill()
		ctx.fillStyle = '#cfd6dc'; ctx.fillRect(bx - 0.9, by - 0.6, 0.8, 0.8); ctx.fillRect(bx + 0.1, by - 0.2, 0.8, 0.8); ctx.fillRect(bx - 0.5, by + 0.4, 0.8, 0.8)
	var steer := Vector2(2.6, -2.4)
	if not o.get("roof"): ctx.strokeStyle = '#1d2023'; ctx.lineWidth = 0.6; ctx.beginPath(); ctx.arc(steer.x, steer.y, 1.1, 0, TAU); ctx.stroke()
	var riders: Array = o.get("riders", [])
	for k in riders.size(): drawRiderTop(-1.3, 2.3 if k else -2.4, riders[k], null if k else steer)
	if o.get("roof"):
		ctx.fillStyle = 'rgba(36,50,20,0.2)'; ctx.fillRect(-4.8, -4.6, 9.2, 10.2)
		ctx.fillStyle = o.roof; ctx.beginPath(); ctx.roundRect(-5.4, -5.6, 9.6, 11.2, 1.6); ctx.fill()
		ctx.fillStyle = 'rgba(255,255,255,0.35)'; ctx.fillRect(-5, -5.2, 8.8, 1.2)
		if o.get("stripe"): ctx.fillStyle = o.stripe; ctx.fillRect(-5.4, -0.7, 9.6, 1.4)
		if o.get("beacon"):
			var on := sin(t * 9 + o.get("seed", 0)) > 0
			ctx.fillStyle = '#ffb31a' if on else '#a26a00'; ctx.beginPath(); ctx.arc(-0.6, 0, 1.4, 0, TAU); ctx.fill()
			if on: ctx.fillStyle = 'rgba(255,190,40,0.28)'; ctx.beginPath(); ctx.arc(-0.6, 0, 5, 0, TAU); ctx.fill()
	ctx.restore()
## range picker: a little tractor in a ball cage, towing a gang of picker reels
func drawPickerCart(x: float, y: float, ang: float, o: Dictionary) -> void:
	var t: float = o.get("t", 0.0)
	var moving: bool = o.get("moving", false)
	var spin := t * 10 if o.get("collect") else 0.0
	ctx.save(); ctx.translate(x, y); ctx.rotate(ang); ctx.scale(1.15, 1.15)
	ctx.fillStyle = 'rgba(36,50,20,0.28)'; ctx.fillRect(-19, -6, 30, 13)
	ctx.fillStyle = '#6c757d'; ctx.fillRect(-18.5, -7.5, 9, 15); ctx.fillStyle = '#4a5157'; ctx.fillRect(-9.5, -0.6, 3.2, 1.2)
	for r in 3:
		for c in 4:
			var rx := -16.8 + r * 3
			var ry := -6 + c * 4 + (r % 2) * 2 - 1
			if ry > 6.5: continue
			ctx.fillStyle = '#c3cbd1'; ctx.beginPath(); ctx.arc(rx, ry, 1.35, 0, TAU); ctx.fill()
			ctx.strokeStyle = '#59626a'; ctx.lineWidth = 0.4; ctx.beginPath(); ctx.moveTo(rx + cos(spin + c) * 1.2, ry + sin(spin + c) * 1.2); ctx.lineTo(rx - cos(spin + c) * 1.2, ry - sin(spin + c) * 1.2); ctx.stroke()
			if o.get("collect") and (r + c + int(floor(t * 6))) % 3 == 0: ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(rx + 0.4, ry, 0.5, 0, TAU); ctx.fill()
	wheel(-3.6, -5.1, 4.6, 2.1, moving, t); wheel(-3.6, 5.1, 4.6, 2.1, moving, t); wheel(5, -4.3, 2.8, 1.4, moving, t); wheel(5, 4.3, 2.8, 1.4, moving, t)
	ctx.fillStyle = '#c8402a'; ctx.beginPath(); ctx.roundRect(-6.2, -4, 13.5, 8, 2); ctx.fill()
	ctx.fillStyle = '#e25a3f'; ctx.beginPath(); ctx.roundRect(1.6, -2.8, 5.8, 5.6, [0, 2, 2, 0]); ctx.fill()
	ctx.fillStyle = '#2b2f36'
	var kk := -2.0
	while kk <= 2: ctx.fillRect(6.6, kk - 0.25, 0.9, 0.5); kk += 1.3
	var lf := clampf(o.get("load", 0.0), 0, 1)
	ctx.fillStyle = '#5b6168'; ctx.fillRect(-6, -3.4, 2.6, 6.8)
	ctx.fillStyle = '#ffffff'; ctx.fillRect(-5.8, 3.2 - 6.4 * lf, 2.2, 6.4 * lf)
	drawRiderTop(-1.4, 0, o.look, Vector2(0.8, 0))
	ctx.strokeStyle = 'rgba(225,230,235,0.9)'; ctx.lineWidth = 0.35; ctx.strokeRect(-3.4, -3.6, 5, 7.2)
	var a := -2.6
	while a < 1.6: ctx.beginPath(); ctx.moveTo(a, -3.6); ctx.lineTo(a, 3.6); ctx.stroke(); a += 1.2
	a = -2.4
	while a < 3.6: ctx.beginPath(); ctx.moveTo(-3.4, a); ctx.lineTo(1.6, a); ctx.stroke(); a += 1.2
	ctx.restore()
## greenkeeper's ride-on mower with a cutting deck in front
var clippings: Array = []
func drawMower(x: float, y: float, ang: float, o: Dictionary) -> void:
	var t: float = o.get("t", 0.0)
	var mowing: bool = o.get("mowing", false)
	var moving: bool = o.get("moving", false)
	ctx.save(); ctx.translate(x, y); ctx.rotate(ang)
	ctx.fillStyle = 'rgba(36,50,20,0.28)'; ctx.fillRect(-6, -6.5, 20, 14)
	ctx.fillStyle = '#8d949a'; ctx.beginPath(); ctx.roundRect(5.4, -8, 6.4, 16, 2.4); ctx.fill()
	ctx.fillStyle = '#6c737a'; ctx.fillRect(5.4, -0.4, 6.4, 0.8)
	for cy in [-4.9, 0.0, 4.9]:
		ctx.strokeStyle = '#4a5157'; ctx.lineWidth = 0.5; ctx.beginPath(); ctx.arc(8.6, cy, 2.1, 0, TAU); ctx.stroke()
		if mowing:
			var a: float = t * 30 + cy
			ctx.beginPath(); ctx.moveTo(8.6 + cos(a) * 1.9, cy + sin(a) * 1.9); ctx.lineTo(8.6 - cos(a) * 1.9, cy - sin(a) * 1.9); ctx.stroke()
	wheel(-3.4, -5.6, 4.8, 2.2, moving, t); wheel(-3.4, 5.6, 4.8, 2.2, moving, t); wheel(3.6, -4.6, 2.6, 1.4, moving, t); wheel(3.6, 4.6, 2.6, 1.4, moving, t)
	ctx.fillStyle = '#2f7d45'; ctx.beginPath(); ctx.roundRect(-6, -4.6, 11.4, 9.2, 2.4); ctx.fill()
	ctx.fillStyle = '#f2c14e'; ctx.fillRect(-6, -4.6, 11.4, 1); ctx.fillRect(-6, 3.6, 11.4, 1)
	ctx.fillStyle = '#3a8a52'; ctx.beginPath(); ctx.roundRect(0.8, -3, 4.6, 6, [0, 2, 2, 0]); ctx.fill()
	ctx.fillStyle = '#2b2f36'; ctx.beginPath(); ctx.roundRect(-5, -2.6, 3.6, 5.2, 1); ctx.fill()
	ctx.strokeStyle = '#1d2023'; ctx.lineWidth = 0.6; ctx.beginPath(); ctx.arc(0.4, 0, 1.2, 0, TAU); ctx.stroke()
	drawRiderTop(-2.6, 0, o.look, Vector2(0.4, 0))
	ctx.restore()
	if mowing and o.get("dt", 0.0) > 0 and clippings.size() < 160 and randf() < 0.9:
		var c := cos(ang)
		var sn := sin(ang)
		var sx := x + c * 8.6 - sn * 8.5
		var sy := y + sn * 8.6 + c * 8.5
		for k in 2:
			clippings.append({ "x": sx, "y": sy, "vx": -sn * Sim.rnd(18, 34) + c * Sim.rnd(-6, 6), "vy": c * Sim.rnd(18, 34) + sn * Sim.rnd(-6, 6), "life": Sim.rnd(0.35, 0.7), "c": '#8fd98a' if randf() < 0.5 else '#5cbd77' })
func drawClippings(dt: float) -> void:
	for p in clippings:
		p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.9; p.vy *= 0.9; p.life -= dt
		ctx.globalAlpha = clampf(p.life * 2.2, 0, 1); ctx.fillStyle = p.c; ctx.fillRect(p.x - 0.6, p.y - 0.6, 1.2, 1.2)
	ctx.globalAlpha = 1
	clippings = clippings.filter(func(p): return p.life > 0)

# ---- cars: hatchbacks, saloons, estates, SUVs and vans, seen from above ----
const CAR_KINDS := [{ "k": 'hatch', "l": 21.0, "w": 11.4 }, { "k": 'saloon', "l": 24.0, "w": 11.8 }, { "k": 'saloon', "l": 24.0, "w": 11.8 }, { "k": 'estate', "l": 25.0, "w": 12.0 }, { "k": 'suv', "l": 25.5, "w": 13.0 }, { "k": 'van', "l": 27.0, "w": 13.0 }]
func drawCarSprite(v: Dictionary, t: float, night: bool, glow: Ctx2D = null) -> void:
	if not v.get("kind"): v.kind = CAR_KINDS[randi() % CAR_KINDS.size()]
	var K: Dictionary = v.kind
	var L: float = K.l
	var W: float = K.w
	var c = v.color
	ctx.save(); ctx.translate(v.x, v.y); ctx.rotate(v.ang)
	ctx.fillStyle = 'rgba(36,50,20,0.33)'; ctx.beginPath(); ctx.roundRect(-L / 2 + 2, -W / 2 + 2.2, L, W, 4); ctx.fill()
	ctx.fillStyle = '#1d2023'
	for wpt in [[L * 0.3, -1], [L * 0.3, 1], [-L * 0.3, -1], [-L * 0.3, 1]]: ctx.fillRect(wpt[0] - 2.2, wpt[1] * (W / 2 + 0.2) - 0.8, 4.4, 1.6)
	ctx.fillStyle = c; ctx.beginPath(); ctx.roundRect(-L / 2, -W / 2, L, W, 2.5 if K.k == 'van' else 4.0); ctx.fill()
	ctx.fillStyle = 'rgba(36,50,20,0.15)'; ctx.fillRect(-L / 2 + 1, W / 2 - 2, L - 2, 1.6)
	ctx.fillStyle = 'rgba(255,255,255,0.16)'; ctx.fillRect(-L / 2 + 1.5, -W / 2 + 0.6, L - 3, 1.1)
	var glass := '#a9c9dc'
	var g2 := '#7fa3ba'
	var fx := L * 0.26 if K.k == 'van' else L * 0.1
	var fw := L * 0.12 if K.k == 'van' else L * 0.16
	ctx.fillStyle = glass; ctx.beginPath(); ctx.moveTo(fx, -W / 2 + 1.4); ctx.lineTo(fx + fw, -W / 2 + 2.3); ctx.lineTo(fx + fw, W / 2 - 2.3); ctx.lineTo(fx, W / 2 - 1.4); ctx.fill()
	ctx.fillStyle = 'rgba(255,255,255,0.45)'; ctx.beginPath(); ctx.moveTo(fx + 0.6, -W / 2 + 2.2); ctx.lineTo(fx + fw * 0.6, -W / 2 + 2.6); ctx.lineTo(fx + 0.6, -W / 2 + 4.2); ctx.fill()
	var rx0 := -L * 0.42 if K.k == 'hatch' else (-L / 2 + 1.2 if K.k == 'van' else -L * 0.3)
	var rx1 := fx
	ctx.fillStyle = g2; ctx.fillRect(rx0, -W / 2 + 1.0, rx1 - rx0, 0.9); ctx.fillRect(rx0, W / 2 - 1.9, rx1 - rx0, 0.9)
	ctx.fillStyle = tint(c, -0.08 if (c == '#f5f5f0' or c == '#b9bec4') else 0.08); ctx.beginPath(); ctx.roundRect(rx0 + 0.6, -W / 2 + 2.0, rx1 - rx0 - 0.8, W - 4, 1.8); ctx.fill()
	if K.k == 'suv' or K.k == 'estate': ctx.fillStyle = 'rgba(30,30,30,0.5)'; ctx.fillRect(rx0 + 1.5, -W / 2 + 2.6, rx1 - rx0 - 3, 0.5); ctx.fillRect(rx0 + 1.5, W / 2 - 3.1, rx1 - rx0 - 3, 0.5)
	if K.k != 'van':
		var back := 1.4 if K.k == 'hatch' else 2.6
		ctx.fillStyle = glass; ctx.beginPath(); ctx.moveTo(rx0, -W / 2 + 2.1); ctx.lineTo(rx0 - back, -W / 2 + 2.6); ctx.lineTo(rx0 - back, W / 2 - 2.6); ctx.lineTo(rx0, W / 2 - 2.1); ctx.fill()
	ctx.fillStyle = c; ctx.fillRect(fx + 1.2, -W / 2 - 0.9, 1.3, 1); ctx.fillRect(fx + 1.2, W / 2 - 0.1, 1.3, 1)
	ctx.fillStyle = '#fff6c8'; ctx.fillRect(L / 2 - 1.2, -W / 2 + 1, 1.2, 2.4); ctx.fillRect(L / 2 - 1.2, W / 2 - 3.4, 1.2, 2.4)
	var brake: bool = (v.state == 'in' and v.pi >= v.path.size() - 1) or (v.state == 'out' and v.pi <= 1)
	ctx.fillStyle = '#ff3b2f' if brake else '#a8261f'; ctx.fillRect(-L / 2, -W / 2 + 1, 1.1, 2.4); ctx.fillRect(-L / 2, W / 2 - 3.4, 1.1, 2.4)
	if brake:
		ctx.fillStyle = 'rgba(255,60,40,0.3)'; ctx.beginPath(); ctx.arc(-L / 2 - 1, -W / 2 + 2.2, 2.4, 0, TAU); ctx.fill()
		ctx.beginPath(); ctx.arc(-L / 2 - 1, W / 2 - 2.2, 2.4, 0, TAU); ctx.fill()
	var turning: bool = (v.state == 'in' and v.pi >= 1 and v.pi <= 2) or (v.state == 'out' and v.pi >= v.path.size() - 3 and v.pi <= v.path.size() - 2)
	if turning and sin(t * 9) > 0:
		ctx.fillStyle = '#ffb31a'
		var sd := (-1 if v.path[0].x < 0 else 1) if v.state == 'in' else 1
		var yy := -W / 2 - 0.2 if sd < 0 else W / 2 - 0.9
		ctx.fillRect(L / 2 - 2.2, yy, 1.8, 1.1); ctx.fillRect(-L / 2 + 0.4, yy, 1.8, 1.1)
	if v.get("door", 0.0) > 0:
		var k: float = min(1.0, v.door / 0.25) * min(1.0, (0.7 - v.door) / 0.15 + 0.2)
		ctx.save(); ctx.translate(fx - 0.5, -W / 2); ctx.rotate(-1.1 * k)
		ctx.fillStyle = c; ctx.fillRect(-7, -1.4, 7, 1.6); ctx.fillStyle = glass; ctx.fillRect(-5, -1.1, 4, 0.6); ctx.restore()
	ctx.restore()
	# headlights after dark, in the additive glow layer
	if night and v.state != 'parked' and glow:
		glow.save(); glow.translate(v.x, v.y); glow.rotate(v.ang)
		var gr := glow.createRadialGradient(L / 2 + 2, 0, 1, L / 2 + 22, 0, 26)
		gr.addColorStop(0, 'rgba(255,240,190,0.35)'); gr.addColorStop(1, 'rgba(255,240,190,0)')
		glow.fillStyle = gr; glow.beginPath(); glow.moveTo(L / 2, -W / 2 + 1); glow.lineTo(L / 2 + 36, -16); glow.lineTo(L / 2 + 36, 16); glow.lineTo(L / 2, W / 2 - 1); glow.fill()
		glow.restore()

# ---- wildlife: ducks on the lake, and birds that fly over now and then ----
var ducks = null
func stepDucks(dt: float, night: bool) -> void:
	var g := Sim.waterField()
	if ducks == null:
		ducks = []
		for b in g.bodies.slice(0, 4):
			if b.inner.size() < 4: continue
			var n: int = min(5, max(1, b.inner.size() / 8))
			for k in n:
				var j: int = b.inner[randi() % b.inner.size()]
				var p: Vector2 = Sim.tileC(j % Sim.GW, j / Sim.GW)
				ducks.append({ "x": p.x, "y": p.y, "b": b, "tx": p.x, "ty": p.y, "hd": 0.0, "k": ducks.size(), "wait": randf() * 4 })
	var sp := 1.2 if night else 4.5
	for d in ducks:
		var dx: float = d.tx - d.x
		var dy: float = d.ty - d.y
		var l := sqrt(dx * dx + dy * dy)
		if l < 1.5:
			d.wait -= dt
			if d.wait <= 0:
				var j: int = d.b.inner[randi() % d.b.inner.size()]
				var p: Vector2 = Sim.tileC(j % Sim.GW, j / Sim.GW)
				var mx = (p.x + d.x) / 2.0
				var my = (p.y + d.y) / 2.0
				if Vector2(p.x - d.x, p.y - d.y).length() < 140 and Sim.wetAt(mx, my) > 0.7: d.tx = p.x + Sim.rnd(-5, 5); d.ty = p.y + Sim.rnd(-5, 5)
				d.wait = Sim.rnd(1, 6)
			continue
		var m: float = min(l, sp * dt)
		d.x += dx / l * m; d.y += dy / l * m; d.hd = atan2(dy, dx)
func drawDucks(t: float, night: bool) -> void:
	if ducks == null: return
	for dk in ducks:
		var k: int = dk.k
		if not vis(dk.x - 10, dk.y - 10, dk.x + 10, dk.y + 10): continue
		var dabble := not night and fmod(t * 0.13 + k * 0.37, 1.0) < 0.08
		ctx.save(); ctx.translate(dk.x, dk.y); ctx.rotate(dk.hd)
		ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 0.6; ctx.beginPath(); ctx.moveTo(-3, -1.6); ctx.lineTo(-9, -4.2); ctx.moveTo(-3, 1.6); ctx.lineTo(-9, 4.2); ctx.stroke()
		if dabble:
			ctx.strokeStyle = 'rgba(255,255,255,0.45)'; ctx.beginPath(); ctx.arc(0, 0, 3 + fmod(t * 4, 2.0), 0, TAU); ctx.stroke()
			ctx.fillStyle = '#6b5032'; ctx.beginPath(); ctx.ellipse(-0.5, 0, 1.6, 1.2, 0, 0, TAU); ctx.fill()
			ctx.fillStyle = '#f4f4f0'; ctx.fillRect(-2, -0.5, 1, 1)
		else:
			var drake := k % 2 == 0
			ctx.fillStyle = '#8a7a66' if drake else '#7a5c3a'; ctx.beginPath(); ctx.ellipse(0, 0, 3.2, 1.9, 0, 0, TAU); ctx.fill()
			ctx.fillStyle = '#5a4632' if drake else '#5e452b'; ctx.beginPath(); ctx.ellipse(-0.8, 0, 2, 1.3, 0, 0, TAU); ctx.fill()
			ctx.fillStyle = '#1f6b3a' if drake else '#7a5c3a'; ctx.beginPath(); ctx.arc(2.6, 0, 1.25, 0, TAU); ctx.fill()
			ctx.fillStyle = '#f2a33a'; ctx.fillRect(3.6, -0.45, 1.3, 0.9)
			if drake: ctx.fillStyle = '#ffffff'; ctx.fillRect(1.6, -1.2, 0.4, 2.4)
		ctx.restore()
var fliers: Array = []
var flyT := 8.0
func stepFliers(dt: float, view: Rect2, ok: bool) -> void:
	flyT -= dt
	if flyT <= 0 and ok:
		flyT = Sim.rnd(18, 40)
		var kind := 'goose' if randf() < 0.4 else ('gull' if randf() < 0.5 else 'crow')
		var n := 5 + randi() % 5 if kind == 'goose' else 2 + randi() % 3
		var fromL := randf() < 0.5
		var y0 := view.position.y + view.size.y * Sim.rnd(0.15, 0.85)
		var ang := (0.0 if fromL else PI) + Sim.rnd(-0.35, 0.35)
		var x0 := view.position.x - 60 if fromL else view.end.x + 60
		var sp := 55.0 if kind == 'goose' else (48.0 if kind == 'gull' else 42.0)
		for i in n:
			var row := int(ceil(i / 2.0))
			var side := 1 if i % 2 else -1
			var back := row * 9.0 if kind == 'goose' else Sim.rnd(0, 26)
			var lat := side * row * 7.0 if kind == 'goose' else Sim.rnd(-18, 18)
			fliers.append({ "kind": kind, "x": x0 - cos(ang) * back - sin(ang) * lat, "y": y0 - sin(ang) * back + cos(ang) * lat, "vx": cos(ang) * sp, "vy": sin(ang) * sp, "ph": randf() * 6, "life": (view.size.x + 200) / sp + 4, "h": 55.0 if kind == 'goose' else 38.0 })
	for f in fliers:
		f.x += f.vx * dt; f.y += f.vy * dt; f.life -= dt
		f.ph += dt * (7 if f.kind == 'goose' else (5 if f.kind == 'gull' else 9))
	fliers = fliers.filter(func(f): return f.life > 0)
func drawFliers() -> void:
	for f in fliers:
		if not vis(f.x - 20, f.y - 80, f.x + 30, f.y + 20): continue
		var flap := sin(f.ph)
		var span := 6.5 if f.kind == 'goose' else (6.0 if f.kind == 'gull' else 5.0)
		ctx.fillStyle = 'rgba(36,50,20,0.18)'; ctx.beginPath(); ctx.ellipse(f.x + f.h * 0.35, f.y, span * (0.6 + 0.4 * abs(flap)), 1.2, atan2(f.vy, f.vx) + PI / 2, 0, TAU); ctx.fill()
		var col := '#5b5650' if f.kind == 'goose' else ('#f4f4f0' if f.kind == 'gull' else '#1f2124')
		ctx.save(); ctx.translate(f.x, f.y - f.h); ctx.rotate(atan2(f.vy, f.vx))
		ctx.strokeStyle = col; ctx.lineWidth = 1.1; ctx.lineCap = 'round'
		ctx.beginPath(); ctx.moveTo(-0.5, -span); ctx.quadraticCurveTo(1.2, -span * 0.4 + flap * 1.6, 0.6, 0); ctx.quadraticCurveTo(1.2, span * 0.4 - flap * 1.6, -0.5, span); ctx.stroke()
		ctx.fillStyle = col; ctx.beginPath(); ctx.ellipse(0.4, 0, 2.2, 0.8, 0, 0, TAU); ctx.fill()
		if f.kind == 'goose': ctx.fillStyle = '#1f2124'; ctx.fillRect(2.2, -0.35, 1.6, 0.7)
		ctx.restore()
