class_name Ctx2D
extends RefCounted
## A small HTML-canvas-style drawing context on top of a CanvasItem.
## The world art was first written for <canvas>; this keeps the same vocabulary
## (beginPath, arc, fill, stroke, save/restore, transforms, clip, gradients, text)
## so the drawing code reads the same, and swapping the view layer later stays easy.

var ci: CanvasItem
var rid: RID

# ---------- style state ----------
var _fill := Color.BLACK
var _fillGrad = null
var _stroke := Color.BLACK
var lineWidth := 1.0
var lineCap := 'butt'
var lineJoin := 'miter'
var globalAlpha := 1.0
var _dash: Array = []
var _fontSize := 10.0
var _fontWeight := 400
var textAlign := 'left'
var textBaseline := 'alphabetic'
var _xf := Transform2D.IDENTITY
var _clip = null            # Array of PackedVector2Array (device space) or null
var _stack: Array = []
## detail: 1 = normal; raise it when drawing something that will be seen zoomed in
var detail := 1.0

# ---------- current path (device space) ----------
var _subs: Array = []       # Array of PackedVector2Array
var _closed: Array = []     # bool per subpath
var _cur := PackedVector2Array()
var _curClosed := false
var _hasCur := false

static var _colCache := {}
static var _fonts := {}

var fillStyle:
	set(v): _setFill(v)
	get: return _fillGrad if _fillGrad != null else _fill
var strokeStyle:
	set(v): _stroke = col(v)
	get: return _stroke
var font:
	set(v): _setFont(v)
	get: return "%d %dpx" % [_fontWeight, _fontSize]

func _init(item: CanvasItem = null) -> void:
	if item: bind(item)
func bind(item: CanvasItem) -> void:
	ci = item; rid = item.get_canvas_item()
	_xf = Transform2D.IDENTITY; _clip = null; _stack.clear(); globalAlpha = 1.0
	_subs.clear(); _closed.clear(); _cur = PackedVector2Array(); _hasCur = false

# ---------- colours ----------
static func col(v) -> Color:
	if v is Color: return v
	if v == null: return Color.TRANSPARENT
	var s := str(v)
	if _colCache.has(s): return _colCache[s]
	var c := Color.BLACK
	if s.begins_with('#'):
		var h := s.substr(1)
		if h.length() == 3: h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
		c = Color.html(h)
	elif s.begins_with('rgb'):
		var inner := s.substr(s.find('(') + 1, s.rfind(')') - s.find('(') - 1)
		var p := inner.split(',')
		c = Color(float(p[0]) / 255.0, float(p[1]) / 255.0, float(p[2]) / 255.0, float(p[3]) if p.size() > 3 else 1.0)
	elif s == 'transparent': c = Color.TRANSPARENT
	else: c = Color.from_string(s, Color.BLACK)
	_colCache[s] = c
	return c
func _setFill(v) -> void:
	if v is RadialGrad: _fillGrad = v
	else: _fillGrad = null; _fill = col(v)
func _a(c: Color) -> Color:
	if globalAlpha < 1.0: c.a *= globalAlpha
	return c

# ---------- fonts ----------
static func fontFor(weight: int) -> FontFile:
	var file := 'Inter-Regular'
	if weight >= 800: file = 'Inter-ExtraBold'
	elif weight >= 700: file = 'Inter-Bold'
	elif weight >= 600: file = 'Inter-SemiBold'
	if _fonts.has(file): return _fonts[file]
	var f := FontFile.new()
	f.load_dynamic_font("res://assets/fonts/%s.otf" % file)
	f.multichannel_signed_distance_field = true   # stays sharp when the camera zooms in
	f.msdf_pixel_range = 8
	f.fallbacks = [emojiFont()]
	_fonts[file] = f
	return f
## colour emoji for event and medal icons (Noto Color Emoji, OFL)
static func emojiFont() -> FontFile:
	if _fonts.has('emoji'): return _fonts['emoji']
	var e := FontFile.new()
	e.load_dynamic_font("res://assets/fonts/NotoColorEmoji.ttf")
	_fonts['emoji'] = e
	return e
func _setFont(v: String) -> void:
	var m := RegEx.create_from_string("(\\d{3})?\\s*([\\d.]+)px").search(v)
	if m:
		_fontWeight = int(m.get_string(1)) if m.get_string(1) != '' else 400
		_fontSize = float(m.get_string(2))

# ---------- state ----------
func save() -> void:
	_stack.append([_fill, _fillGrad, _stroke, lineWidth, lineCap, lineJoin, globalAlpha, _dash, _fontSize, _fontWeight, textAlign, _xf, _clip, textBaseline])
func restore() -> void:
	if _stack.is_empty(): return
	var s: Array = _stack.pop_back()
	_fill = s[0]; _fillGrad = s[1]; _stroke = s[2]; lineWidth = s[3]; lineCap = s[4]; lineJoin = s[5]; globalAlpha = s[6]; _dash = s[7]
	_fontSize = s[8]; _fontWeight = s[9]; textAlign = s[10]; _xf = s[11]; _clip = s[12]; textBaseline = s[13]
func translate(x: float, y: float) -> void: _xf = _xf * Transform2D(0.0, Vector2(x, y))
func rotate(a: float) -> void: _xf = _xf * Transform2D(a, Vector2.ZERO)
func scale(x: float, y: float) -> void: _xf = _xf * Transform2D.IDENTITY.scaled(Vector2(x, y))
func setTransform(t: Transform2D) -> void: _xf = t
func resetTransform() -> void: _xf = Transform2D.IDENTITY
func setLineDash(d: Array) -> void: _dash = d
func _scaleK() -> float: return sqrt(abs(_xf.determinant()))

# ---------- path building ----------
func beginPath() -> void:
	_subs.clear(); _closed.clear(); _cur = PackedVector2Array(); _hasCur = false; _curClosed = false
func _endSub() -> void:
	if _hasCur and _cur.size() > 0:
		_subs.append(_cur); _closed.append(_curClosed)
	_cur = PackedVector2Array(); _hasCur = false; _curClosed = false
func moveTo(x: float, y: float) -> void:
	_endSub(); _cur.append(_xf * Vector2(x, y)); _hasCur = true
func lineTo(x: float, y: float) -> void:
	if not _hasCur: moveTo(x, y); return
	_cur.append(_xf * Vector2(x, y))
func closePath() -> void:
	if _hasCur and _cur.size():
		_curClosed = true
		var first := _cur[0]
		_endSub()
		_cur.append(first); _hasCur = true
func rect(x: float, y: float, w: float, h: float) -> void:
	_endSub()
	_cur = PackedVector2Array([_xf * Vector2(x, y), _xf * Vector2(x + w, y), _xf * Vector2(x + w, y + h), _xf * Vector2(x, y + h)])
	_hasCur = true; _curClosed = true
	_endSub()
func roundRect(x: float, y: float, w: float, h: float, r = 0.0) -> void:
	var tl: float; var tr: float; var br: float; var bl: float
	if r is Array:
		if r.size() == 1: tl = r[0]; tr = r[0]; br = r[0]; bl = r[0]
		elif r.size() == 2: tl = r[0]; br = r[0]; tr = r[1]; bl = r[1]
		elif r.size() == 3: tl = r[0]; tr = r[1]; bl = r[1]; br = r[2]
		else: tl = r[0]; tr = r[1]; br = r[2]; bl = r[3]
	else: tl = r; tr = r; br = r; bl = r
	var m: float = min(abs(w), abs(h)) / 2
	tl = min(tl, m); tr = min(tr, m); br = min(br, m); bl = min(bl, m)
	_endSub()
	moveTo(x + tl, y)
	if tr > 0: arc(x + w - tr, y + tr, tr, -PI / 2, 0)
	else: lineTo(x + w, y)
	if br > 0: arc(x + w - br, y + h - br, br, 0, PI / 2)
	else: lineTo(x + w, y + h)
	if bl > 0: arc(x + bl, y + h - bl, bl, PI / 2, PI)
	else: lineTo(x, y + h)
	if tl > 0: arc(x + tl, y + tl, tl, PI, PI * 1.5)
	else: lineTo(x, y)
	_curClosed = true
	_endSub()
func _segs(r: float, span: float) -> int:
	var rs := r * _scaleK() * detail
	return clampi(int(ceil(sqrt(max(rs, 0.5)) * 3.2 * abs(span) / TAU * 4.0)), 3, 96)
func arc(x: float, y: float, r: float, a0: float, a1: float, ccw := false) -> void:
	ellipse(x, y, r, r, 0.0, a0, a1, ccw)
func ellipse(x: float, y: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw := false) -> void:
	var span := a1 - a0
	if not ccw and span < 0: span = fmod(span, TAU) + TAU
	if ccw and span > 0: span = fmod(span, TAU) - TAU
	if abs(a1 - a0) >= TAU - 1e-6: span = TAU * (-1.0 if ccw else 1.0)
	var n := _segs(max(rx, ry), span)
	var cr := cos(rot)
	var sr := sin(rot)
	for k in n + 1:
		var a := a0 + span * k / n
		var lx := cos(a) * rx
		var ly := sin(a) * ry
		var p := _xf * Vector2(x + lx * cr - ly * sr, y + lx * sr + ly * cr)
		if k == 0 and not _hasCur: _cur.append(p); _hasCur = true
		else: _cur.append(p)
func quadraticCurveTo(cx: float, cy: float, x: float, y: float) -> void:
	if not _hasCur: moveTo(cx, cy)
	var p0 := _xf.affine_inverse() * _cur[_cur.size() - 1]
	var c := Vector2(cx, cy)
	var p1 := Vector2(x, y)
	var n := clampi(int(p0.distance_to(p1) * _scaleK() / 4.0), 4, 24)
	for k in range(1, n + 1):
		var t := float(k) / n
		_cur.append(_xf * (p0 * (1 - t) * (1 - t) + c * 2 * (1 - t) * t + p1 * t * t))
func bezierCurveTo(c1x: float, c1y: float, c2x: float, c2y: float, x: float, y: float) -> void:
	if not _hasCur: moveTo(c1x, c1y)
	var p0 := _xf.affine_inverse() * _cur[_cur.size() - 1]
	var c1 := Vector2(c1x, c1y)
	var c2 := Vector2(c2x, c2y)
	var p1 := Vector2(x, y)
	var n := clampi(int((p0.distance_to(c1) + c1.distance_to(c2) + c2.distance_to(p1)) * _scaleK() / 5.0), 4, 32)
	for k in range(1, n + 1):
		var t := float(k) / n
		var u := 1.0 - t
		_cur.append(_xf * (p0 * u * u * u + c1 * 3 * u * u * t + c2 * 3 * u * t * t + p1 * t * t * t))
func _paths() -> Array:
	var out := _subs.duplicate()
	if _hasCur and _cur.size() > 0: out.append(_cur)
	return out
func _closedFlags() -> Array:
	var out := _closed.duplicate()
	if _hasCur and _cur.size() > 0: out.append(_curClosed)
	return out

# ---------- the triangle buffer ----------
# Everything (fills and strokes) becomes triangles in one buffer, sent to the renderer in a single call.
var _P := PackedVector2Array()
var _C := PackedColorArray()
var _I := PackedInt32Array()
var _rec := []      # stack of saved buffers while recording a sprite
func flush() -> void:
	if _I.size() and rid.is_valid() and _rec.is_empty():
		RenderingServer.canvas_item_add_triangle_array(rid, _I, _P, _C)
	if _rec.is_empty():
		_P = PackedVector2Array(); _C = PackedColorArray(); _I = PackedInt32Array()
## record what is drawn next into a reusable mesh instead of the canvas
func beginRecord() -> void:
	_rec.append([_P, _C, _I, _xf, globalAlpha])
	_P = PackedVector2Array(); _C = PackedColorArray(); _I = PackedInt32Array()
	_xf = Transform2D.IDENTITY; globalAlpha = 1.0
func endRecord() -> Array:
	var m := [_P, _C, _I]
	var s: Array = _rec.pop_back()
	_P = s[0]; _C = s[1]; _I = s[2]; _xf = s[3]; globalAlpha = s[4]
	return m
## draw a recorded mesh with a transform (one call; no per-vertex work here)
func emit(mesh: Array, xf: Transform2D, alpha := 1.0) -> void:
	if mesh[2].is_empty(): return
	if not _rec.is_empty():
		var o := _P.size()
		for i in mesh[0].size():
			_P.append(xf * mesh[0][i])
			var c: Color = mesh[1][i]; c.a *= alpha; _C.append(c)
		for i in mesh[2]: _I.append(o + i)
		return
	flush()
	RenderingServer.canvas_item_add_set_transform(rid, xf)
	if alpha < 1.0:
		var cs: PackedColorArray = mesh[1].duplicate()
		for i in cs.size(): cs[i].a *= alpha
		RenderingServer.canvas_item_add_triangle_array(rid, mesh[2], mesh[0], cs)
	else: RenderingServer.canvas_item_add_triangle_array(rid, mesh[2], mesh[0], mesh[1])
	RenderingServer.canvas_item_add_set_transform(rid, Transform2D.IDENTITY)
func _tris(pts: PackedVector2Array, idx: PackedInt32Array, c: Color) -> void:
	var o := _P.size()
	_P.append_array(pts)
	for i in pts.size(): _C.append(c)
	for i in idx: _I.append(o + i)
	if _I.size() > 60000 and _rec.is_empty(): flush()

# ---------- filling ----------
func _poly(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() < 3 or c.a <= 0.002: return
	if _clip != null:
		for cp in _clip:
			for part in Geometry2D.intersect_polygons(pts, cp): _polyRaw(part, c)
		return
	_polyRaw(pts, c)
func _polyRaw(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() > 3 and pts[0].is_equal_approx(pts[pts.size() - 1]): pts = pts.slice(0, pts.size() - 1)
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		pts = Geometry2D.convex_hull(pts)
		if pts.size() < 3: return
		pts = pts.slice(0, pts.size() - 1)
		idx = Geometry2D.triangulate_polygon(pts)
		if idx.is_empty(): return
	_tris(pts, idx, c)
func _gradPoly(pts: PackedVector2Array) -> void:
	# a radial gradient: subdivide the outline and fan from the gradient's centre
	var g: RadialGrad = _fillGrad
	var cen := _xf * Vector2(g.x1, g.y1)
	var R := g.r1 * _scaleK()
	var ring := PackedVector2Array()
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var n := clampi(int(a.distance_to(b) / max(4.0, R / 8.0)), 1, 24)
		for k in n: ring.append(a.lerp(b, float(k) / n))
	var o := _P.size()
	_P.append(cen); _C.append(_a(g.at(0.0)))
	for i in ring.size():
		_P.append(ring[i]); _C.append(_a(g.at(cen.distance_to(ring[i]) / max(R, 0.001))))
	for i in ring.size():
		_I.append(o); _I.append(o + 1 + i); _I.append(o + 1 + (i + 1) % ring.size())
func fill() -> void:
	if _fillGrad != null:
		for p in _paths():
			if p.size() >= 3: _gradPoly(p)
		return
	var c := _a(_fill)
	for p in _paths(): _poly(p, c)
func fillRect(x: float, y: float, w: float, h: float) -> void:
	var pts := PackedVector2Array([_xf * Vector2(x, y), _xf * Vector2(x + w, y), _xf * Vector2(x + w, y + h), _xf * Vector2(x, y + h)])
	if _fillGrad != null: _gradPoly(pts); return
	var c := _a(_fill)
	if c.a <= 0.002: return
	if _clip == null: _tris(pts, PackedInt32Array([0, 1, 2, 0, 2, 3]), c)
	else: _poly(pts, c)
func clip() -> void:
	var ps := []
	for p in _paths():
		if p.size() >= 3: ps.append(p)
	if _clip != null:
		var out := []
		for a in ps:
			for b in _clip: out.append_array(Geometry2D.intersect_polygons(a, b))
		ps = out
	_clip = ps

# ---------- stroking ----------
func _line(pts: PackedVector2Array, c: Color, w: float) -> void:
	if pts.size() < 2: return
	if _clip != null:
		for cp in _clip:
			for part in Geometry2D.intersect_polyline_with_polygon(pts, cp): _lineRaw(part, c, w)
		return
	_lineRaw(pts, c, w)
func _disc(p: Vector2, r: float, c: Color) -> void:
	var n := clampi(int(r * 1.5) + 6, 6, 24)
	var o := _P.size()
	_P.append(p); _C.append(c)
	for k in n:
		var a := TAU * k / n
		_P.append(p + Vector2(cos(a), sin(a)) * r); _C.append(c)
	for k in n:
		_I.append(o); _I.append(o + 1 + k); _I.append(o + 1 + (k + 1) % n)
func _lineRaw(pts: PackedVector2Array, c: Color, w: float) -> void:
	var hw := w * 0.5
	# see-through wide strokes are outlined as one shape, so overlapping joints don't darken
	if c.a < 0.999 and w > 2.2 and pts.size() > 2 and not pts[0].is_equal_approx(pts[pts.size() - 1]):
		var polys := Geometry2D.offset_polyline(pts, hw, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND if lineCap == 'round' else Geometry2D.END_BUTT)
		var ok := true
		for poly in polys:
			if Geometry2D.is_polygon_clockwise(poly) and polys.size() > 1: ok = false
		if ok and polys.size():
			for poly in polys:
				var idx := Geometry2D.triangulate_polygon(poly)
				if idx.size(): _tris(poly, idx, c)
			return
	var o := _P.size()
	var n := pts.size()
	# one quad per segment; joints get filled below
	var segs := 0
	for i in n - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var L := d.length()
		if L < 0.0001: continue
		var nn := Vector2(-d.y, d.x) / L * hw
		var q := o + segs * 4
		_P.append(a + nn); _P.append(b + nn); _P.append(b - nn); _P.append(a - nn)
		_C.append(c); _C.append(c); _C.append(c); _C.append(c)
		_I.append(q); _I.append(q + 1); _I.append(q + 2); _I.append(q); _I.append(q + 2); _I.append(q + 3)
		segs += 1
	if w > 2.2:
		var closed := n > 2 and pts[0].is_equal_approx(pts[n - 1])
		for i in range(1, n - 1): _disc(pts[i], hw, c)
		if closed: _disc(pts[0], hw, c)
		elif lineCap == 'round':
			_disc(pts[0], hw, c); _disc(pts[n - 1], hw, c)
		elif lineCap == 'square':
			pass
	elif lineCap == 'round' and w > 1.2:
		_disc(pts[0], hw, c); _disc(pts[n - 1], hw, c)
	if _I.size() > 60000 and _rec.is_empty(): flush()
func _dashed(pts: PackedVector2Array, c: Color, w: float) -> void:
	var k := _scaleK()
	var pat: Array = _dash.map(func(d): return max(0.5, float(d) * k))
	var di := 0
	var left: float = pat[0]
	var on := true
	var cur := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var segL := a.distance_to(b)
		var pos := 0.0
		while segL - pos > left:
			pos += left
			var p := a.lerp(b, pos / segL)
			if on: cur.append(p); _line(cur, c, w)
			cur = PackedVector2Array([p])
			on = not on; di = (di + 1) % pat.size(); left = pat[di]
		left -= segL - pos
		if on: cur.append(b)
		else: cur = PackedVector2Array([b])
	if on and cur.size() > 1: _line(cur, c, w)
func stroke() -> void:
	var c := _a(_stroke)
	if c.a <= 0.002: return
	var w: float = max(0.35, lineWidth * _scaleK())
	var ps := _paths()
	var cl := _closedFlags()
	for i in ps.size():
		var p: PackedVector2Array = ps[i]
		if cl[i] and p.size() > 2 and not p[0].is_equal_approx(p[p.size() - 1]): p = p.duplicate(); p.append(p[0])
		if _dash.size(): _dashed(p, c, w)
		else: _line(p, c, w)
func strokeRect(x: float, y: float, w: float, h: float) -> void:
	var keep := [_subs, _closed, _cur, _hasCur, _curClosed]
	_subs = []; _closed = []; _cur = PackedVector2Array(); _hasCur = false
	rect(x, y, w, h); stroke()
	_subs = keep[0]; _closed = keep[1]; _cur = keep[2]; _hasCur = keep[3]; _curClosed = keep[4]

# ---------- text ----------
func measureText(t: String) -> Dictionary:
	return { "width": fontFor(_fontWeight).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(_fontSize))).x }
func fillText(t, x: float, y: float) -> void:
	var s := str(t)
	var f := fontFor(_fontWeight)
	var sz := int(round(_fontSize))
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var ox := 0.0
	if textAlign == 'center': ox = -w / 2
	elif textAlign == 'right' or textAlign == 'end': ox = -w
	var oy := 0.0
	if textBaseline == 'middle': oy = (f.get_ascent(sz) - f.get_descent(sz)) / 2
	elif textBaseline == 'top': oy = f.get_ascent(sz)
	flush()
	ci.draw_set_transform_matrix(_xf)
	ci.draw_string(f, Vector2(x + ox, y + oy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, _a(_fill))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
func strokeText(t, x: float, y: float) -> void:
	var s := str(t)
	var f := fontFor(_fontWeight)
	var sz := int(round(_fontSize))
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var ox := -w / 2 if textAlign == 'center' else 0.0
	flush()
	ci.draw_set_transform_matrix(_xf)
	ci.draw_string_outline(f, Vector2(x + ox, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, int(max(1.0, lineWidth)), _a(_stroke))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# ---------- images ----------
func drawTexture(tex: Texture2D, x: float, y: float, w: float, h: float, modulate := Color.WHITE) -> void:
	flush()
	ci.draw_set_transform_matrix(_xf)
	ci.draw_texture_rect(tex, Rect2(x, y, w, h), false, _a(modulate))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# ---------- gradients ----------
class RadialGrad:
	var x0: float; var y0: float; var r0: float; var x1: float; var y1: float; var r1: float
	var stops: Array = []
	func addColorStop(o: float, c) -> void:
		stops.append([o, Ctx2D.col(c)]); stops.sort_custom(func(a, b): return a[0] < b[0])
	func at(t: float) -> Color:
		t = clampf((t * r1 - r0) / max(0.001, r1 - r0), 0.0, 1.0)
		if stops.is_empty(): return Color.TRANSPARENT
		if t <= stops[0][0]: return stops[0][1]
		for i in range(1, stops.size()):
			if t <= stops[i][0]:
				var a = stops[i - 1]
				var b = stops[i]
				return a[1].lerp(b[1], (t - a[0]) / max(0.0001, b[0] - a[0]))
		return stops[stops.size() - 1][1]
func createRadialGradient(x0: float, y0: float, r0: float, x1: float, y1: float, r1: float) -> RadialGrad:
	var g := RadialGrad.new()
	g.x0 = x0; g.y0 = y0; g.r0 = r0; g.x1 = x1; g.y1 = y1; g.r1 = r1
	return g
