extends Node
## Fairway Tycoon simulation. A faithful port of the web version's game logic.
## Everything that decides what happens lives here; drawing (WorldView) and the interface (UI) only read it
## and call its actions. Names follow the original JavaScript so the two versions stay easy to compare.

signal toast_shown(kicker, title, text, icon)
signal ui_refresh
signal sound(name, args)
signal event_card(ev)
signal end_screen(kind)
signal medal_card(scen, tier)

const GAME_VERSION := "1.0.0-godot"
const SAVE_DIR := "user://saves"

func rnd(a: float, b: float) -> float: return a + randf() * (b - a)
func hyp(x: float, y: float) -> float: return sqrt(x * x + y * y)
func clampf2(v: float, a: float, b: float) -> float: return max(a, min(b, v))
func sgn(v: float) -> float: return 1.0 if v > 0 else (-1.0 if v < 0 else 0.0)
## the original's deterministic random numbers (Park–Miller), so layouts match the web version
func seeded(seed: int) -> Callable:
	var st := [seed]
	return func() -> float:
		st[0] = (st[0] * 16807) % 2147483647
		return float(st[0]) / 2147483647.0
func pick(a: Array):
	return a[randi() % a.size()] if a.size() else null

# ---------- Content ----------
const PARS := [4,3,5,4,4,3,4,5,4, 4,4,3,5,4,3,4,4,5]
const FIRST := ['A','B','D','E','F','H','J','K','L','M','N','P','R','S','T','W']
const LAST := ['de Vries','Jansen','Bakker','Smit','Meijer','Mulder','Visser','Bos','Peters','Hendriks','Dekker','Brouwer','Kok','Willems','Vos','Lammers','Koster','Prins','van Dijk','Janssen','de Boer','Kuipers']
const WEATHER := {
	"sunny":  { "label": 'Sunny',  "range": 1.15, "course": 1.2,  "decay": 1.0,   "wind": 0.3, "cloud": 0.02 },
	"cloudy": { "label": 'Cloudy', "range": 1.0,  "course": 1.0,  "decay": 1.0,   "wind": 0.4, "cloud": 0.16 },
	"windy":  { "label": 'Windy',  "range": 0.9,  "course": 0.8,  "decay": 1.2,   "wind": 1.2, "cloud": 0.1 },
	"rain":   { "label": 'Rain',   "range": 0.45, "course": 0.3,  "decay": 3.0,   "wind": 0.6, "cloud": 0.26 },
}

# ---------- Upgrades ----------
var UP: Array = []
var STAFF: Array = []
var byId := {}
func _build_upgrades() -> void:
	UP = [
		{ "id": 'bay', "tab": 'range', "name": 'Hitting bay, right side', "base": 40, "g": 1.17, "max": 35, "desc": func(): return ("The range is at full width with %d bays." % MAX_BAYS) if bays() >= MAX_BAYS else (("Widens the range to the right. %d of %d bays: %d left of the ball machines, %d right." % [bays(), MAX_BAYS, L('bayL'), 3 + L('bay')]) if rangeFits({ "bay": L('bay') + 1 }) else 'No room to the right: buy land or move what is in the way.') },
		{ "id": 'bayL', "tab": 'range', "name": 'Hitting bay, left side', "base": 40, "g": 1.17, "max": 35, "desc": func(): return ("The range is at full width with %d bays." % MAX_BAYS) if bays() >= MAX_BAYS else ('Widens the range to the left. The ball machines and the door stay where they are.' if rangeFits({ "bayL": L('bayL') + 1 }) else 'No room to the left: buy land or move what is in the way.') },
		{ "id": 'balls', "tab": 'range', "name": 'Premium range balls', "base": 300, "g": 1.8, "max": 5, "desc": func(): return "Golfers value a bucket 8%% more, but premium balls cost more to replace. A bucket is worth %s to them now; 500 balls cost %s." % [fmt(nice(fairBucket())), fmt(cost(byId.order))] },
		{ "id": 'targets', "tab": 'range', "name": 'Target greens', "base": 1500, "g": 2.0, "max": 3, "desc": func(): return "Flags and greens to aim at: buckets are worth 12% more to golfers. Costs $10 a day each to keep up." },
		{ "id": 'order', "tab": 'range', "name": 'Order range balls', "base": 120, "g": 1.0, "max": INF, "desc": func(): return "Adds 500 balls to the dispenser. You own %s; %s lost to the pond and rough so far." % [fmtInt(S.owned), fmtInt(S.lost)] },
		{ "id": 'disp', "tab": 'range', "name": 'Ball dispenser', "base": 200, "g": 1.5, "max": 20, "desc": func(): return "Stores 500 more balls and fills buckets faster. Holds %s; a bucket takes %.1f s." % [fmtInt(ballCap()), fillTime()] },
		{ "id": 'dmach', "tab": 'range', "name": 'Extra ball machine', "base": 900, "g": 2.4, "max": 2, "desc": func(): return "Another machine on the tee line, so more golfers fill buckets at once. You have %d.%s" % [machines(), '' if rangeFits({ "dmach": L('dmach') + 1 }) else ' No room: it widens the range to the right.'] },
		{ "id": 'cart', "tab": 'range', "name": 'Picker cart', "base": 700, "g": 1.5, "max": 20, "desc": func(): return "Gives one ball picker a cart with a ball cage: holds %d balls and drives about 3× faster. %d of %d pickers have one." % [pickerCap(true), min(L('cart'), N('picker')), N('picker')] },
		{ "id": 'basket', "tab": 'range', "name": 'Bigger baskets and cages', "base": 400, "g": 1.6, "max": 10, "desc": func(): return "+25%% picker capacity. Baskets hold %d, cart cages %d." % [pickerCap(false), pickerCap(true)] },
		{ "id": 'covered', "tab": 'range', "name": 'Covered bays', "base": 1200, "g": 1.9, "max": 5, "desc": func(): return "Range golfers keep coming in the rain. Rain demand %d%%." % round(rangeRainMult() * 100) },
		{ "id": 'lights', "tab": 'range', "name": 'Floodlights', "base": 1500, "g": 1.9, "max": 6, "desc": func(): return ("Range open after dark at %d%% demand." % round(nightRange() * 100)) if L('lights') else "Keep the range open after dark." },
		{ "id": 'slot', "tab": 'course', "name": 'Extra tee time', "base": 600, "g": 1.32, "max": 20, "desc": func(): return "+1 group of up to 4 on the course. You have %d." % slots() },
		{ "id": 'green', "tab": 'course', "name": 'Greenkeeping kit', "base": 400, "g": 1.55, "max": 10, "desc": func(): return "Golfers value a round 6%% more and greenkeepers work 15%% faster. Nine holes are worth %s now." % fmt(nice(fairFee9())) },
		{ "id": 'carts', "tab": 'course', "name": 'Golf carts', "base": 900, "g": 1.7, "max": 8, "desc": func(): return ("Golfers ride between shots at %d instead of walking at %d. Faster rounds free up tee times." % [round(RIDE()), STROLL]) if L('carts') else 'Golfers ride between shots instead of walking, so rounds finish sooner.' },
		{ "id": 'irrig', "tab": 'course', "name": 'Irrigation', "base": 1500, "g": 1.75, "max": 8, "desc": func(): return "Waters and drains the course, so summer heat and rain do less damage to the turf." },
		{ "id": 'market', "tab": 'club', "name": 'Local advertising', "base": 150, "g": 1.5, "max": 12, "desc": func(): return "More golfers hear about you, with diminishing returns: +%d%% now%s. Costs $20 a day per level." % [round((marketMult() - 1) * 100), (", +%d%% at the next level" % round((marketMult(L('market') + 1) - 1) * 100)) if L('market') < 12 else ''] },
		{ "id": 'barRoom', "tab": 'club', "name": 'Bar', "base": 1500, "g": 1.8, "max": 4, "desc": func(): return ("%d seats. Drinks %s a visit.%s" % [venueCap('bar'), fmt(venueSpend('bar')), '' if N('bar') else ' Hire a bartender to open it.']) if L('barRoom') else 'Build a bar in the clubhouse. Needs a bartender.' },
		{ "id": 'resto', "tab": 'club', "name": 'Restaurant', "base": 4000, "g": 1.9, "max": 5, "desc": func(): return ("%d seats. Meals %s each.%s" % [venueCap('resto'), fmt(venueSpend('resto')), '' if N('chef') else ' Hire a chef to open it.']) if L('resto') else 'A dining room and kitchen. Busy at lunch and dinner. Needs a chef.' },
		{ "id": 'terrace', "tab": 'club', "name": 'Terrace', "base": 2500, "g": 1.8, "max": 5, "desc": func(): return (("%d seats outside, served by the bar. Popular in the sun, closed in rain and after dark." % venueCap('terrace')) if L('terrace') else 'Tables and umbrellas overlooking the course. Served by the bar.') if L('barRoom') else 'Build the bar first; it serves the terrace.' },
		{ "id": 'locker', "tab": 'club', "name": 'Locker rooms', "base": 2000, "g": 2.0, "max": 3, "desc": func(): return ("Course golfers change first. Green fees +%d%%, patience at the tee +%d%%." % [8 * L('locker'), 15 * L('locker')]) if L('locker') else 'Changing rooms for course golfers. Raises green fees and their patience.' },
		{ "id": 'shop', "tab": 'club', "name": 'Pro shop stock', "base": 80, "g": 1.4, "max": 20, "desc": func(): return "%d shoppers at a time spend %s each, and every golfer buys tees." % [venueCap('shop'), fmt(venueSpend('shop'))] },
		{ "id": 'food', "tab": 'club', "name": 'Halfway house menu', "base": 800, "g": 1.6, "max": 10, "desc": func(): return ("Golfers spend %s each per round at your halfway house." % fmt(foodCourse())) if hasObj('hut') else 'Place a halfway house on the Build tab first.' },
		{ "id": 'reno', "tab": 'club', "name": 'Clubhouse renovation', "base": 25000, "g": 2.0, "max": 5, "desc": func(): return "A smarter club: golfers value everything 10%% more. Now ×%s." % fmtMult(renoMult()) },
	]
	STAFF = [
		{ "id": 'attend', "range": true, "name": 'Range attendant', "base": 200, "g": 1.45, "sal": 0.22, "max": 12, "desc": func(): return "Runs 4 bays each. You can run 3 yourself. Staffed: %d of %d bays." % [staffedBays(), bays()] },
		{ "id": 'picker', "range": true, "name": 'Ball picker', "base": 150, "g": 1.4, "sal": 0.17, "max": 20, "desc": func(): return "Walks the range with a basket of %d balls and carries them to the ball machines. Picker carts speed them up. Without pickers you collect 2 balls a second by hand." % pickerCap(false) },
		{ "id": 'keeper', "name": 'Greenkeeper', "base": 400, "g": 1.45, "sal": 0.3, "max": 15, "desc": func(): return "Drives a mower to the most worn hole and repairs its turf. %d busy right now." % keepers.filter(func(k): return k.hole >= 0).size() },
		{ "id": 'marshal', "name": 'Marshal', "base": 650, "g": 1.5, "sal": 0.28, "max": 12, "desc": func(): return "Patrols the range, course and clubhouse, by golf cart out on the holes. Sends troublemakers home, picks up litter and repairs damage. %d litter and %d damage right now." % [litter.size(), marks.size()] },
		{ "id": 'starter', "name": 'Starter', "base": 700, "g": 1.8, "sal": 0.4, "max": 4, "desc": func(): return "Fills groups faster and brings +10%% course golfers. Groups wait up to %d s." % round(maxWait()) },
		{ "id": 'assist', "name": 'Shop assistant', "base": 300, "g": 1.5, "sal": 0.2, "max": 30, "desc": func(): return "Serves in the pro shop: room for one more shopper and +10%% sales each. The first two also open extra check-in desks (%d open now)." % desks() },
		{ "id": 'bar', "name": 'Bartender', "base": 900, "g": 1.6, "sal": 0.35, "max": 8, "desc": func(): return "Opens the bar and terrace. Each one serves faster and sells +25%." if L('barRoom') else 'Build the bar first.' },
		{ "id": 'coach', "name": 'Teaching pro', "base": 900, "g": 1.6, "sal": 0.4, "max": 3, "desc": func(): return 'Gives lessons at the golf academy. Each one teaches one pupil at a time.' if hasObj('academy') else 'Build a golf academy first.' },
		{ "id": 'chef', "name": 'Chef', "base": 1400, "g": 1.65, "sal": 0.45, "max": 8, "desc": func(): return "Opens the restaurant. Each one cooks faster and meals sell +25%." if L('resto') else 'Build the restaurant first.' },
	]
	byId.clear()
	for u in UP + STAFF: byId[u.id] = u

# ---------- World geometry (world units) ----------
const W := 2200.0
const H := 1540.0
const LAND_Y1 := 1480.0
const ROAD_Y := 1510.0
const BAY_W := 22.0
const MAX_BAYS := 38
const FIELD_DEPTH := 280.0
var RX0 := 60.0
var RY0 := 60.0
var FIELD_Y1 := 340.0
var TEE_Y := 360.0
var BAY0 := 90.0
var RANGE_MAX_X1 := 90.0 + MAX_BAYS * BAY_W + 10
func rangeX1() -> float: return MX0 + MBW + (3 + L('bay')) * BAY_W + 10
func bayLeftX(i: int) -> float:
	var nL := L('bayL')
	return BAY0 + i * BAY_W if i < nL else MX0 + MBW + (i - nL) * BAY_W
func bayX(i: int) -> float: return bayLeftX(i) + BAY_W / 2
const CELL_W := 44.0
const GR := 10
var GCMAX := int(ceil((90.0 + MAX_BAYS * 22.0 + 10 - 60.0) / 44.0))
var CELL_H := (FIELD_DEPTH - 10) / GR

# =====================================================================================
# Driving ranges. A park can have several; each keeps its own bays, upgrades, ball stock,
# attendants and pickers. The range code runs "inside" one range at a time.
# =====================================================================================
const RANGE_UP := {'bay': 1, 'bayL': 1, 'dmach': 1, 'covered': 1, 'lights': 1, 'targets': 1, 'balls': 1, 'disp': 1, 'cart': 1, 'basket': 1}
const RANGE_STAFF := {'attend': 1, 'picker': 1}
var curR = null
var MX0 := -5000.0
var MBW := 26.0
var selRangeId = null
func rangeObjs() -> Array:
	if not S.get("world"): return []
	return S.world.objs.filter(func(o): return o.type == 'range')
func rangeName(o) -> String: return "Range %d" % (rangeObjs().find(o) + 1)
func newRangeState() -> Dictionary:
	var cells := []; cells.resize(GCMAX * GR); cells.fill(0.0)
	return { "lvl": {}, "staff": { "attend": 0, "picker": 0 }, "cells": cells, "stock": 500.0, "owned": 500.0, "lost": 0, "field": 0.0, "mx": null }
## where everything sits: [margin][left bays][ball machines][right bays][margin]
func rangeGeom(o, ex = null) -> Dictionary:
	var r = o.get("r") if o.get("r") else { "lvl": {} }
	var lv = func(k): return ex[k] if (ex != null and ex.has(k)) else int(r.lvl.get(k, 0))
	var nL: int = lv.call('bayL')
	var nR: int = 3 + lv.call('bay')
	var m: int = 1 + lv.call('dmach')
	var mx0: float = float(r.mx) if r.get("mx") != null else o.x * TILE + 20.0
	var rx0 := mx0 - 10 - nL * BAY_W
	var mbw := 12.0 + m * 14
	var x1 := mx0 + mbw + nR * BAY_W + 10
	return { "nL": nL, "nR": nR, "m": m, "mx0": mx0, "rx0": rx0, "mbw": mbw, "x1": x1 }
## runtime state of each range: who is playing, queuing, filling buckets; pickers; balls in the air
var RT := {}
func rt(o) -> Dictionary:
	if not RT.has(o.id):
		RT[o.id] = { "range": [], "bucketQueue": [], "rangeQueue": [], "filling": [], "bayTaken": {}, "brokenBays": {}, "pickers": [], "inFlight": [], "flights": [], "handAcc": 0.0 }
	return RT[o.id]
var rangeP: Array = []          # golfers hitting balls (the JS `range`)
var bucketQueue: Array = []
var rangeQueue: Array = []
var filling: Array = []
var bayTaken := {}
var brokenBays := {}
var pickers: Array = []
var inFlight: Array = []
var flights: Array = []
var handAcc := 0.0
var _nowhere := { "range": [], "bucketQueue": [], "rangeQueue": [], "filling": [], "bayTaken": {}, "brokenBays": {}, "pickers": [], "inFlight": [], "flights": [] }
func enterRange(o) -> void:
	if curR == o: return
	if curR: leaveRange()
	if not o or not o.get("r"): return
	curR = o
	var x := rt(o)
	var r = o.r
	var g := rangeGeom(o)
	rangeP = x.range; bucketQueue = x.bucketQueue; rangeQueue = x.rangeQueue; filling = x.filling; bayTaken = x.bayTaken; brokenBays = x.brokenBays
	pickers = x.pickers; inFlight = x.inFlight; flights = x.flights; handAcc = x.handAcc
	S.cells = r.cells; S.stock = r.stock; S.field = r.field; S.owned = r.owned; S.lost = r.lost
	MX0 = g.mx0; MBW = g.mbw; RX0 = g.rx0; RY0 = o.y * TILE + 10.0; BAY0 = RX0 + 10
	FIELD_Y1 = RY0 + FIELD_DEPTH; TEE_Y = FIELD_Y1 + 20; RANGE_MAX_X1 = RX0 + 10 + MAX_BAYS * BAY_W + 12 + 3 * 14 + 10
func leaveRange() -> void:
	if not curR: return
	var x := rt(curR)
	var r = curR.r
	x.range = rangeP; x.bucketQueue = bucketQueue; x.rangeQueue = rangeQueue; x.filling = filling; x.bayTaken = bayTaken; x.brokenBays = brokenBays
	x.pickers = pickers; x.inFlight = inFlight; x.flights = flights; x.handAcc = handAcc
	r.cells = S.cells; r.stock = S.stock; r.field = S.field; r.owned = S.owned; r.lost = S.lost
	curR = null
	rangeP = _nowhere.range; bucketQueue = _nowhere.bucketQueue; rangeQueue = _nowhere.rangeQueue; filling = _nowhere.filling; bayTaken = _nowhere.bayTaken; brokenBays = _nowhere.brokenBays
	pickers = _nowhere.pickers; inFlight = _nowhere.inFlight; flights = _nowhere.flights
	MX0 = -5000; RX0 = -5000; BAY0 = -5000; RY0 = -5000; FIELD_Y1 = RY0 + FIELD_DEPTH; TEE_Y = FIELD_Y1 + 20
func withRange(o, fn: Callable):
	var prev = curR
	enterRange(o)
	var res = fn.call()
	leaveRange()
	if prev: enterRange(prev)
	return res
func rangeOfV(v):
	return objById(v.rangeId) if v and v.get("rangeId") else null
func inRangeOf(v, fn: Callable):
	var o = rangeOfV(v)
	return withRange(o, fn) if o and o.get("r") else fn.call()
func forRanges(fn: Callable) -> void:
	for o in rangeObjs():
		if o.get("r"): withRange(o, func(): fn.call(o))
func rangeDoorPt() -> Vector2:
	if curR:
		var d := doorOf(curR); return tileC(d.tx, d.ty)
	return NODES.RANGE_E
## move a range's footprint to a new left edge, keeping its shape
func shiftRange(o, tx: int) -> Dictionary:
	if not o or not o.get("r"): return { "type": 'range', "x": tx, "y": o.y if o else 0 }
	var cur: int = fp(o).x
	var r: Dictionary = o.r.duplicate()
	r.mx = rangeGeom(o).mx0 + (tx - cur) * TILE
	return { "type": 'range', "id": o.id, "x": tx, "y": o.y, "r": r }
## totals across every range, for the status bar and the Park panel
func rangeSum() -> Dictionary:
	var s := { "players": 0, "staffed": 0, "bays": 0, "stock": 0.0, "field": 0.0, "owned": 0.0, "cap": 0, "queue": 0, "broken": 0, "n": 0 }
	forRanges(func(_o):
		s.n += 1; s.players += rangeP.size(); s.staffed += staffedBays(); s.bays += bays(); s.stock += S.stock; s.field += S.field; s.owned += S.owned; s.cap += ballCap()
		s.queue += bucketQueue.size() + rangeQueue.size(); s.broken += brokenBays.size())
	return s
## a new range golfer goes to the range with the most room
func pickRange():
	var best = null
	var bs := -1.0
	for o in rangeObjs():
		if not o.get("r") or not connected('OBJ:%s' % o.id) or not facOpen('range:%s' % o.id): continue
		var sc: float = withRange(o, func(): return (staffedBays() + 0.5) / (1.0 + rangeP.size() + bucketQueue.size() + rangeQueue.size())) * (0.85 + randf() * 0.3)
		if sc > bs: bs = sc; best = o
	return best
## caps levels at their maximum; parks from before the campaign get a deadline
func clampLevels() -> void:
	if S.get("startDay") == null and S.get("scenario"):
		var sc = scenOf(S.scenario)
		S.startDay = S.day
		if not S.get("diff"): S.diff = 'normal'
		if not S.get("medal"): S.medal = 0
		S.over = null; S.finished = false
		if not S.get("peakStars"): S.peakStars = 0
		S.repLow = 0; S.lastReview = { "stars": null, "medal": 0 }
		if sc and sc.id != 'sandbox' and sc.get("years"): S.deadline = S.day + sc.years * 36; S.board = 60
		else: S.deadline = null; S.board = null
	if int(S.get("econ", 1)) < 2: S.econ = 2
	for u in UP:
		if u.get("tab") and is_finite(u.max) and int(S.lvl.get(u.id, 0)) > u.max: S.lvl[u.id] = int(u.max)
	for o in rangeObjs():
		if o.get("r"):
			for k in RANGE_UP:
				var u = byId.get(k)
				if u and is_finite(u.max) and int(o.r.lvl.get(k, 0)) > u.max: o.r.lvl[k] = int(u.max)
func migrateRanges() -> void:
	for o in rangeObjs():
		if not o.get("r"): o.r = newRangeState()
	var ro := rangeObjs()
	if ro.is_empty() or S.get("rangeMigrated"): return
	S.rangeMigrated = true
func selRange():
	var o = objById(selRangeId)
	if o: return o
	var ro := rangeObjs()
	return ro[0] if ro.size() else null
func rangeStaffTotal() -> int:
	var n := 0
	for o in rangeObjs():
		if o.get("r"): n += int(o.r.staff.get("attend", 0)) + int(o.r.staff.get("picker", 0))
	return n
func freshHoles() -> Array:
	var a := []
	for i in 18: a.append({ "par": 3, "bunk": 0, "water": 0, "beach": 0, "trees": 0 })
	return a

# ---------- State ----------
func freshState() -> Dictionary:
	var lvl := {}
	for u in UP: lvl[u.id] = 0
	var st := {}
	for s in STAFF: st[s.id] = 0
	var turf := []; turf.resize(18); turf.fill(100.0)
	var cells := []; cells.resize(GCMAX * GR); cells.fill(0.0)
	return {
		"money": 1500.0, "prices": null, "invested": 0.0, "turf": turf, "members": 0, "memberMood": 70.0, "memberLog": null, "run": 0.0, "lvl": lvl, "staff": st,
		"cond": 100.0, "stock": 500.0, "field": 0.0, "owned": 500.0, "lost": 0, "rounds": 0, "cells": cells, "holes": freshHoles(), "design": null,
	}
func baseState() -> Dictionary:
	var s := freshState()
	s.merge({ "loan": 0.0, "redDays": 0, "ledger": null, "frostDay": false, "total": 0.0, "trophies": 0, "ach": {}, "aces": 0, "sales": 0, "buckets": 0, "clock": 7.0 * 15, "day": 1, "wx": 'sunny', "wxLeft": 90.0, "wxNext": 'cloudy', "lastSave": Time.get_unix_time_from_system(), "lastRate": 0 }, true)
	return s
var S: Dictionary = {}
func L(id: String) -> int:
	if RANGE_UP.has(id):
		if curR: return int(curR.r.lvl.get(id, 0))
		var m := 0
		for o in rangeObjs():
			if o.get("r"): m = max(m, int(o.r.lvl.get(id, 0)))
		return m
	return int(S.lvl.get(id, 0)) if S.has("lvl") else 0
func level(u) -> int: return rStaff(u.id) if RANGE_STAFF.has(u.id) else (L(u.id) if u.get("tab") else int(S.staff.get(u.id, 0)))
func rStaff(id: String) -> int:
	if curR: return int(curR.r.staff.get(id, 0))
	var n := 0
	for o in rangeObjs():
		if o.get("r"): n += int(o.r.staff.get(id, 0))
	return n
var strikeRoles := {}   # staff on strike after a random event
var strike := false
func N(id: String) -> int:
	if strike or strikeRoles.has(id): return 0
	return rStaff(id) if RANGE_STAFF.has(id) else int(S.staff.get(id, 0))

# ---------- Economy ----------
const DAY_LEN := 360.0   # real seconds per in-game day
func hour() -> float: return (S.clock / DAY_LEN) * 24.0
func daylight() -> float:
	var h := hour()
	var sun: Array = SUN[monthIdx()]
	var rise: float = sun[0]
	var sset: float = sun[1]
	if h >= rise + 1 and h < sset - 1: return 1.0
	if h >= rise - 1 and h < rise + 1: return (h - rise + 1) / 2.0
	if h >= sset - 1 and h < sset + 1: return 1.0 - (h - sset + 1) / 2.0
	return 0.0
func isDark() -> bool: return daylight() < 0.35
func incomeMult() -> float: return renoMult() * (1 + 0.08 * min(5, int(S.get("trophies", 0))))
func renoMult() -> float: return 1 + 0.1 * L('reno')
func condMult() -> float: return 0.5 + 0.5 * S.cond / 100.0
func fairBucket() -> float: return 6 * (1 + 0.08 * L('balls')) * (1 + 0.12 * L('targets')) * incomeMult()
func bucketPrice() -> float: return S.prices.bucket
func feeBase() -> float: return 55 * (1 + 0.06 * L('green')) * (1 + 0.08 * L('locker')) * condMult() * incomeMult()
func fairFee9() -> float: return feeBase() * (1 + 0.006 * rating9())
func fairFee18() -> float: return feeBase() * 1.9 * (1 + 0.006 * rating18() / 2.0)
func fee9() -> float: return S.prices.fee9
func fee18() -> float: return S.prices.fee18
func dur9() -> float: return 60 * pow(0.9, L('carts'))
const RANGE_DUR := 24.0
func bays() -> int: return min(MAX_BAYS, 3 + L('bay') + L('bayL'))
func slots() -> int: return 2 + L('slot')
func ballCap() -> int: return 500 + 500 * L('disp')
func activeCols() -> int: return min(GCMAX, int(ceil((rangeX1() - RX0) / CELL_W)))
func machines() -> int: return 1 + L('dmach')
func machinePos(m: int) -> Vector2: return Vector2(MX0 + 12 + m * 14, TEE_Y)
func fillTime() -> float: return 4.0 / (1 + 0.2 * L('disp'))
func pickerCap(cart: bool) -> int: return roundi((250 if cart else 60) * (1 + 0.25 * L('basket')))
func pickerSpeed(cart: bool) -> float: return 85.0 if cart else 28.0
func pickerGrab(cart: bool) -> float: return 30.0 if cart else 6.0
func pickerDrop(cart: bool) -> float: return 80.0 if cart else 30.0
func hasCart(i: int) -> bool: return i < L('cart')
func cellCenter(i: int) -> Vector2:
	var c := i % GCMAX
	var r := i / GCMAX
	return Vector2(min(rangeX1() - 12, RX0 + (c + 0.5) * CELL_W), RY0 + 10 + (r + 0.5) * CELL_H)
func fieldTotal() -> float:
	var s := 0.0
	for c in S.cells: s += c
	return s
const RANGE_IMPACT := 0.75   # seconds from the start of a range swing to the strike

func hitBall(g) -> void:
	var x1 := rangeX1()
	var lx: float = max(RX0 + 8, min(x1 - 8, bayX(g.bay) + (randf() - 0.5) * 260 + W_().wind * 70 * (randf() - 0.3)))
	var ly := RY0 + 18 + pow(randf(), 0.9) * (FIELD_Y1 - RY0 - 40)
	var col: int = min(activeCols() - 1, int(floor((lx - RX0) / CELL_W)))
	var row: int = min(GR - 1, max(0, int(floor((ly - RY0 - 10) / CELL_H))))
	inFlight.append({ "cell": row * GCMAX + col, "at": simTime + 1.3 + RANGE_IMPACT })
	g.swing = 1; g.swingT = 0.0
	if flights.size() < 40: flights.append({ "bay": g.bay, "x": lx, "y": ly })
func takeNearDispenser(mx: float) -> float:
	var cols := activeCols()
	for r in range(GR - 1, -1, -1):
		for c in range(cols - 1, -1, -1):
			var i := r * GCMAX + c
			if S.cells[i] > 0.5:
				var n: float = min(S.cells[i], mx)
				S.cells[i] -= n
				return n
	return 0.0
func handPick(dt: float) -> void:   # the manager picks up two balls a second by the tee line
	handAcc = min(1.0, handAcc + dt * 2)
	if handAcc >= 1 and S.stock + 1 <= ballCap():
		var n := takeNearDispenser(1)
		if n: S.stock += n; handAcc = 0.0
func syncPickers() -> void:
	var want := N('picker')
	while pickers.size() < want: pickers.append({ "x": machinePos(0).x - 10 - pickers.size() * 8, "y": TEE_Y - 16, "state": 'idle', "load": 0.0, "target": -1, "ang": -PI / 2, "wob": randf() * 6 })
	while pickers.size() > want:
		var p = pickers.pop_back(); S.stock = min(ballCap(), S.stock + p.load)
func chooseCell(p) -> int:
	var best := -1
	var bestScore := 0.0
	var taken := {}
	for o in pickers:
		if o != p and o.target >= 0: taken[o.target] = 1
	for i in S.cells.size():
		var c: float = S.cells[i]
		if c < 1: continue
		if taken.has(i) and c < 40: continue
		var cc := cellCenter(i)
		var d := hyp(cc.x - p.x, cc.y - p.y)
		var score: float = min(c, 120.0) / (d + 60)
		if score > bestScore: bestScore = score; best = i
	return best
func moveTo(p, tx: float, ty: float, speed: float, dt: float) -> bool:
	var dx: float = tx - p.x
	var dy: float = ty - p.y
	var d := hyp(dx, dy)
	var step := speed * dt
	if d < 0.01: return true
	p.ang = atan2(dy, dx)
	if d <= step: p.x = tx; p.y = ty; return true
	p.x += dx / d * step; p.y += dy / d * step
	return false
func updatePicker(p, i: int, dt: float) -> void:
	if strike: return
	var cart := hasCart(i)
	var cap := pickerCap(cart)
	var sp := pickerSpeed(cart)
	if p.state == 'idle':
		if p.load < cap and fieldTotal() >= 1:
			p.target = chooseCell(p)
			if p.target >= 0: p.state = 'seek'
		if p.state == 'idle' and p.load > 0: p.state = 'return'
	if p.state == 'seek':
		if S.cells[p.target] < 1:
			p.target = chooseCell(p)
			if p.target < 0: p.state = 'return' if p.load else 'idle'; return
		var cc := cellCenter(p.target)
		if moveTo(p, cc.x, cc.y, sp, dt): p.state = 'collect'
	elif p.state == 'collect':
		var take: float = min(S.cells[p.target], pickerGrab(cart) * dt, cap - p.load)
		S.cells[p.target] -= take; p.load += take
		p.wob += dt * (3 if cart else 2)
		var cc := cellCenter(p.target)
		moveTo(p, cc.x + sin(p.wob) * CELL_W * 0.4, cc.y + cos(p.wob * 0.7) * CELL_H * 0.35, sp * 0.5, dt)
		if p.load >= cap - 0.01: p.state = 'return'; p.target = -1
		elif S.cells[p.target] < 0.5:
			S.cells[p.target] = 0.0
			p.target = chooseCell(p)
			p.state = 'seek' if p.target >= 0 else 'return'
	elif p.state == 'return':
		if moveTo(p, machinePos(0).x - 4 + (i % 3) * 6, TEE_Y - 16, sp, dt):
			p.state = 'unload'
			sfx('balls', Vector2(p.x, p.y), [32])
	elif p.state == 'unload':
		var give: float = min(p.load, pickerDrop(cart) * dt, max(0.0, ballCap() - S.stock))
		p.load -= give; S.stock += give
		if p.load <= 0.01: p.load = 0.0; p.state = 'idle'

# ---------- The 18 holes, as you design them ----------
# A hole is a tee, a bend point the hole passes through, and a green. Par comes from its length.
const YARDS_PER_UNIT := 1.6
const GREEN_T := { 3: 0.4, 4: 0.7, 5: 0.96 }
const HOLE_SHARE := { 3: 0.75, 4: 1.0, 5: 1.3 }
const MIN_YD := 90
const MAX_YD := 620
func parForYards(y: float) -> int: return 3 if y < 250 else (4 if y < 470 else 5)
var OLD_CORR: Array = []
func _build_corr() -> void:
	OLD_CORR = []
	for e in [
		[1300, 1170, 1300, 850, 40], [1300, 780, 1300, 460, -50], [1300, 400, 1300, 80, 30],
		[1640, 80, 1640, 400, -40], [1640, 460, 1640, 780, 50], [1640, 850, 1640, 1170, -30],
		[1980, 1170, 1980, 850, 45], [1980, 780, 1980, 460, -35], [1980, 400, 1980, 80, 40],
		[1060, 1180, 760, 1180, 35], [720, 1180, 420, 1180, -40], [380, 1180, 80, 1180, 30],
		[80, 930, 380, 930, -35], [420, 930, 720, 930, 40], [760, 930, 1060, 930, -30],
		[1060, 680, 760, 680, 35], [720, 680, 420, 680, -40], [380, 680, 80, 680, 30]]:
		var a := Vector2(e[0], e[1]); var b := Vector2(e[2], e[3])
		var d := b - a; var l := d.length(); var pp := Vector2(-d.y / l, d.x / l)
		OLD_CORR.append({ "a": a, "b": b, "c": (a + b) / 2 + pp * e[4] * 2, "side": -1 if e[4] > 0 else 1 })
func qb(h, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * h.a + 2 * u * t * h.c + t * t * h.b
func qbTan(h, t: float) -> Vector2:
	var v: Vector2 = 2 * (1 - t) * (h.c - h.a) + 2 * t * (h.b - h.c)
	var l := v.length()
	return v / (l if l else 1.0)
func qbOff(h, t: float, d: float) -> Vector2:
	var p := qb(h, t)
	var tn := qbTan(h, t)
	return Vector2(p.x - tn.y * d, p.y + tn.x * d)
func r2(p: Vector2) -> Dictionary: return { "x": roundi(p.x), "y": roundi(p.y) }
func pv(d) -> Vector2: return Vector2(d.x, d.y)

# ---- land: a grid of parcels you can buy
const PARCEL_COLS := [0, 220, 440, 660, 880, 1100, 1320, 1540, 1760, 1980, 2200]
const PARCEL_ROWS := [0, 160, 320, 480, 640, 800, 960, 1120, 1280, 1480]
var PARCELS: Array = []
func _build_parcels() -> void:
	PARCELS = []
	for r in 9:
		for c in 10: PARCELS.append({ "id": r * 10 + c, "x0": PARCEL_COLS[c], "x1": PARCEL_COLS[c + 1], "y0": PARCEL_ROWS[r], "y1": PARCEL_ROWS[r + 1] })
func parcelAt(x: float, y: float):
	if x < 0 or y < 0 or x >= 2200 or y >= LAND_Y1: return null
	var c := 0
	while c < 9 and x >= PARCEL_COLS[c + 1]: c += 1
	var r := 0
	while r < 8 and y >= PARCEL_ROWS[r + 1]: r += 1
	return PARCELS[r * 10 + c]
func ownsAt(_design, x: float, y: float) -> bool:
	var p = parcelAt(x, y)
	return p != null and S.get("world") != null and S.world.land.has(p.id)
func parcelPrice() -> float:
	var n: int = S.world.land.size() if S.get("world") else 6
	var lm: float = S.smod.get("land", 1.0) if S.get("smod") else 1.0
	return round(2000 * pow(1.06, n) * lm / 100.0) * 100
## places you can't put a tee, green or feature: buildings, roads, car parks, footpaths and water
func noBuild(x: float, y: float, wetOk := false) -> bool:
	if x < 0 or y < 0 or x > W or y > LAND_Y1 - 6: return true
	var t := tileOf(x, y)
	var o: int = occ[tIdx(min(GW - 1, t.tx), min(GH - 1, t.ty))]
	return o != 0 and not (wetOk and o == -2)
func validSpot(design, x: float, y: float) -> bool: return ownsAt(design, x, y) and not noBuild(x, y)

# ---- feature types you can place
const FEATS := {
	"bunker": { "label": 'Bunker', "rx": 11.0, "ry": 7.0, "cost": 350, "upkeep": 3 },
	"pond":   { "label": 'Pond', "rx": 34.0, "ry": 21.0, "cost": 1600, "upkeep": 8 },
	"lake":   { "label": 'Lake strip', "rx": 52.0, "ry": 16.0, "cost": 2400, "upkeep": 10 },
	"waste":  { "label": 'Sand dunes', "rx": 44.0, "ry": 15.0, "cost": 1100, "upkeep": 6 },
	"trees":  { "label": 'Trees', "rx": 22.0, "ry": 22.0, "cost": 240, "upkeep": 1 },
	"flowers":{ "label": 'Flowerbed', "rx": 13.0, "ry": 13.0, "cost": 180, "upkeep": 2 },
}
var featId := 1

# ---- designs: a new park
func defaultDesign(builtFront := true, oldHoles = null, back9 := false) -> Dictionary:
	var holes := []
	for i in OLD_CORR.size():
		var h = OLD_CORR[i]
		var par: int = oldHoles[i].par if oldHoles else (3 if i < 9 else 4)
		var tg: float = GREEN_T[par]
		var built: bool = builtFront if i < 9 else back9
		holes.append({ "tee": r2(qb(h, 0.03)), "bend": r2(qb(h, (0.03 + tg) / 2)), "green": r2(qb(h, tg)), "built": built, "placed": built })
	var d := { "holes": holes, "feats": [], "land": [] }
	var owned := {}
	for id in [2, 3, 4, 7, 8, 9, 12, 13, 14, 17, 18, 19]: owned[id] = 1
	for h in holes:
		if h.built:
			for k in ["tee", "bend", "green"]:
				var pc = parcelAt(h[k].x, h[k].y)
				if pc: owned[pc.id] = 1
	var ks := owned.keys(); ks.sort()
	d.land = ks
	return d

# ---- geometry built from a design. `G` is the one in use; drawing swaps in the draft while you design.
var G = null
func buildGeo(design) -> Dictionary:
	var geo := { "design": design, "feats": design.feats, "corr": [], "hs": [], "info": [] }
	for h in design.holes:
		var tee := pv(h.tee); var green := pv(h.green); var bend := pv(h.bend)
		geo.corr.append({ "a": tee, "b": green, "c": 2 * bend - (tee + green) / 2, "built": h.built, "placed": h.built or bool(h.get("placed", false)) })
	var prev = G
	G = geo
	for i in geo.corr.size():
		var out := []
		var s := 0.0
		var p0 = null
		for k in 121:
			var t := -0.02 + 1.12 * k / 120.0
			var p := hPt(i, t)
			if p0 != null: s += p.distance_to(p0)
			out.append({ "t": t, "x": p.x, "y": p.y, "s": s })
			p0 = p
		geo.hs.append(out)
	for i in geo.corr.size(): geo.info.append(analyzeHole(i))
	G = prev
	return geo
func withGeo(geo, fn: Callable):
	var prev = G
	G = geo
	var r = fn.call()
	G = prev
	return r
func hPt(i: int, t: float) -> Vector2: return qb(G.corr[i], t)
func hTan(i: int, t: float) -> Vector2: return qbTan(G.corr[i], t)
func hOff(i: int, t: float, d: float) -> Vector2:
	var p := hPt(i, t)
	var tn := hTan(i, t)
	return Vector2(p.x - tn.y * d, p.y + tn.x * d)
func greenT(_i = 0) -> float: return 1.0
func holeLen(i: int) -> float:
	var a: Array = G.hs[i]
	var k1 := -1
	var k0 := -1
	for k in a.size():
		if k0 < 0 and a[k].t >= 0: k0 = k
		if k1 < 0 and a[k].t >= 1: k1 = k
	return a[max(0, k1)].s - a[max(0, k0)].s
func holeYards(i: int) -> int: return roundi(holeLen(i) * YARDS_PER_UNIT / 5.0) * 5
func teePos(i: int) -> Vector2: return hPt(i, 0)
func signPos(i: int) -> Vector2: return hOff(i, -0.02, -20)
func holeOpen(i: int) -> bool: return G != null and i < G.corr.size() and bool(G.corr[i].built)
func parOf(i: int) -> int: return G.info[i].par if G.info.size() > i else 4

# ---- what a hole is like: par, hazards in play, shape and beauty, and a rating out of 15
const HOLE_MAX_RATING := 15
func distToHole(i: int, x: float, y: float) -> Dictionary:
	var best := INF
	var bt := 0.0
	for q in G.hs[i]:
		var d := hyp(q.x - x, q.y - y)
		if d < best: best = d; bt = q.t
	return { "d": best, "t": bt }
func analyzeHole(i: int) -> Dictionary:
	var yards := holeYards(i)
	var par := parForYards(yards)
	var h = G.design.holes[i]
	var gp := pv(h.green); var tp := pv(h.tee); var bp := pv(h.bend)
	var gsBunk := 0; var fwBunk := 0; var waterBeside := 0; var waterCarry := 0; var waste := 0; var treeN := 0; var flowers := 0
	for f in G.feats:
		var F = FEATS[f.type]
		var dt := distToHole(i, f.x, f.y)
		var d: float = dt.d; var t: float = dt.t
		var edge: float = d - max(F.rx, F.ry) * 0.7
		var dGreen := hyp(f.x - gp.x, f.y - gp.y)
		var dTee := hyp(f.x - tp.x, f.y - tp.y)
		if f.type == 'bunker':
			if dGreen < 48: gsBunk += 1
			elif edge < 26 and t > 0.15 and t < 0.98: fwBunk += 1
		elif f.type == 'waste':
			if edge < 40 and t > 0 and t < 1.05: waste += 1
		elif f.type == 'trees':
			if d < 95 and t > -0.05 and t < 1.1: treeN += 1
		elif f.type == 'flowers':
			if dGreen < 70 or dTee < 70: flowers += 1
	var wv := waterOnHole(i)
	if wv.carry: waterCarry += 1
	if wv.beside: waterBeside += 1
	var ev := elevOfHole(i)
	var a1 := atan2(bp.y - tp.y, bp.x - tp.x)
	var a2 := atan2(gp.y - bp.y, gp.x - bp.x)
	var bendDeg: float = abs(fposmod((a2 - a1) * 180 / PI + 540, 360.0) - 180)
	var parts := {
		"length": (par - 3) * 2,
		"bunkers": min(3, gsBunk + min(1, fwBunk)),
		"water": min(4, (2 if waterCarry else 0) + (2 if waterBeside else 0)),
		"dunes": 2 if waste else 0,
		"trees": min(2, treeN / 3) + (1 if flowers else 0),
		"shape": 1 if bendDeg > 22 else 0,
		"elev": (1 if abs(ev.delta) >= 4 else 0) + (1 if ev.range >= 6 else 0),
	}
	var tot := 0
	for v in parts.values(): tot += v
	var rating: int = min(HOLE_MAX_RATING, tot)
	return { "yards": yards, "par": par, "rating": rating, "parts": parts, "bendDeg": bendDeg, "elev": ev, "bunk": min(3, gsBunk + fwBunk), "water": (1 if waterCarry else 0) + (1 if waterBeside else 0), "beach": 1 if waste else 0, "trees": min(2, treeN / 3) + (1 if flowers else 0) }
func holeRating(i: int) -> int: return G.info[i].rating if G.info.size() > i else 0
## the live course: rebuild geometry, mirror it into S.holes and the back-nine flag
var liveGeo = null
func ensureDesign() -> void:
	if not S.get("design") or not (S.design.get("holes") is Array): S.design = defaultDesign(true, null, false)
	for h in S.design.holes:
		if not h.has("placed") or not h.built: h.placed = bool(h.built)
	applyDesign()
func applyDesign() -> void:
	liveGeo = buildGeo(S.design); G = liveGeo
	S.holes = liveGeo.info.map(func(f): return { "par": f.par, "bunk": f.bunk, "water": f.water, "beach": f.beach, "trees": f.trees })
	var all9 := true
	for k in range(9, 18):
		if not S.design.holes[k].built: all9 = false
	S.lvl.back9 = 1 if all9 else 0
	for f in S.design.feats: featId = max(featId, int(f.id) + 1)
func rating9() -> int:
	var r := 0
	for i in 9: r += holeRating(i)
	return r
func rating18() -> int:
	var r := 0
	for i in 18: r += holeRating(i)
	return r
func courseAppeal() -> float: return min(2.0, 1 + 0.006 * (rating18() if L('back9') else rating9()))
func staffedBays() -> int: return min(bays(), 3 + 4 * N('attend'))
func rangeRainMult() -> float: return min(1.0, 0.45 + 0.11 * L('covered'))
func nightRange() -> float: return min(1.0, 0.25 + 0.15 * L('lights')) if L('lights') else 0.04
func marketMult(l = null) -> float:
	var lv: int = L('market') if l == null else l
	return 1 + 0.9 * (1 - pow(0.82, lv))
func arrivalBase() -> float: return 0.3 * marketMult() * modMult('arrive')
func W_() -> Dictionary: return WEATHER[S.wx]
func openRanges() -> int:
	return rangeObjs().filter(func(o): return o.get("r") and connected('OBJ:%s' % o.id) and facOpen('range:%s' % o.id)).size()
func openBays() -> int:
	var n := 0
	for o in rangeObjs():
		if o.get("r") and connected('OBJ:%s' % o.id) and facOpen('range:%s' % o.id): n += withRange(o, func(): return staffedBays())
	return n
func rangeDraw() -> float: return pow(max(1, openBays()) / 6.0, 0.65)
var crowdT := 0.0
var rangeCrowd := 1.0
var teeCrowd := 1.0
func updateCrowding(dt: float) -> void:
	crowdT -= dt
	if crowdT > 0: return
	crowdT = 1
	var rs := rangeSum()
	rangeCrowd = 1.0 / (1 + 0.6 * rs.queue / max(1, rs.staffed))
	teeCrowd = 1.0 / (1 + 0.35 * teeQueue.size() / max(1, slots()))
func rangeDemand() -> float:
	return modMult('range') * rangeCrowd * ((hcpDemand(false) * rangeDraw()) if rangeOK() else 0.0) * starAppeal() * arrivalBase() * 0.6 * (rangeRainMult() if S.wx == 'rain' else W_().range) * (nightRange() if isDark() else 1.0) * parkAppeal() * seasonDemand() * valueDemand(ratioOf('bucket'))
func courseDemand() -> float:
	if isDark() or isFrost() or not facOpen('course'): return 0.0
	return modMult('course') * teeCrowd * seasonDemand() * courseValue() * arrivalBase() * 0.32 * W_().course * (0.4 + 0.6 * S.cond / 100.0) * (1 + 0.1 * N('starter')) * courseAppeal() * parkAppeal() * starAppeal() * rivalShare() * (0.0 if eventRunning() else 1.0) * ((pow(min(1.0, courseHoles() / 9.0), 0.6) * hcpDemand(true)) if courseOK() else 0.0)
func shopSpend() -> float: return 0.4 * min(10, L('shop')) * incomeMult()
func foodCourse() -> float:
	for o in objs():
		if o.type == 'hut' and facOpen('obj:%s' % o.id): return 6 * (1 + 0.25 * L('food')) * incomeMult() * modMult('food')
	return 0.0
func maxWait() -> float: return 16 * pow(0.7, N('starter'))
func salaries() -> float:
	var a := 0.0
	for s in STAFF: a += s.sal * (rStaff(s.id) if RANGE_STAFF.has(s.id) else int(S.staff.get(s.id, 0)))
	return a
func cost(u) -> float:
	if u.id == 'order': return ceil(u.base * (1 + 0.2 * L('balls')))
	return ceil(u.base * pow(u.g, (bays() - 3) if (u.id == 'bay' or u.id == 'bayL') else level(u)))

# =====================================================================================
# Business: calendar and seasons, prices you set, running costs, the books and the bank
# =====================================================================================
const MONTH_DAYS := 3
const MONTHS := ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
func SEASON_OF(m: int) -> String: return 'winter' if (m == 11 or m <= 1) else ('spring' if m <= 4 else ('summer' if m <= 7 else 'autumn'))
const SEASON_DEMAND := [0.4, 0.45, 0.65, 0.85, 1.0, 1.15, 1.2, 1.15, 0.95, 0.75, 0.55, 0.4]
const SUN := [[8.2, 16.8], [7.6, 17.8], [6.6, 18.8], [6.0, 20.0], [5.4, 21.0], [5.0, 21.8], [5.2, 21.6], [5.8, 20.8], [6.6, 19.6], [7.2, 18.4], [7.8, 17.0], [8.4, 16.5]]
const WX_BY_SEASON := {
	"spring": [['sunny', 0.35], ['cloudy', 0.3], ['windy', 0.15], ['rain', 0.2]],
	"summer": [['sunny', 0.58], ['cloudy', 0.22], ['windy', 0.08], ['rain', 0.12]],
	"autumn": [['sunny', 0.2], ['cloudy', 0.32], ['windy', 0.2], ['rain', 0.28]],
	"winter": [['sunny', 0.22], ['cloudy', 0.4], ['windy', 0.13], ['rain', 0.25]],
}
func monthIdx(d = null) -> int:
	var dd: int = S.day if d == null else d
	return (2 + int(floor((dd - 1) / float(MONTH_DAYS)))) % 12
func yearOf(d = null) -> int:
	var dd: int = S.day if d == null else d
	return 1 + int(floor((2 + int(floor((dd - 1) / float(MONTH_DAYS)))) / 12.0))
func partOfMonth(d = null) -> String:
	var dd: int = S.day if d == null else d
	return ['Early', 'Mid', 'Late'][(dd - 1) % MONTH_DAYS]
func dateLabel(d = null, short := false) -> String:
	var dd: int = S.day if d == null else d
	var m: String = MONTHS[monthIdx(dd)]
	return ("%s %s · Y%d" % [partOfMonth(dd), m.substr(0, 3), yearOf(dd)]) if short else ("%s %s, Year %d" % [partOfMonth(dd), m, yearOf(dd)])
func season() -> String: return SEASON_OF(monthIdx())
func seasonDemand() -> float: return SEASON_DEMAND[monthIdx()]
func isFrost() -> bool: return season() == 'winter' and bool(S.get("frostDay", false)) and hour() < 10.5

# ---- prices: you set them; golfers compare them with what the park is worth to them
func nice(v: float) -> float:
	if v < 10: return max(0.5, round(v * 2) / 2.0)
	var m := pow(10, floor(log(v) / log(10)) - 1)
	return round(v / m) * m
func priceStep(f: float) -> float:
	if f < 10: return 0.5
	if f < 50: return 1.0
	if f < 200: return 5.0
	if f < 1000: return 10.0
	return pow(10, floor(log(f) / log(10)) - 1) * 5
func ensurePrices() -> void:
	if not S.get("prices"): S.prices = {}
	var P: Dictionary = S.prices
	if not (P.get("bucket", 0) > 0): P.bucket = nice(fairBucket())
	if not (P.get("fee9", 0) > 0): P.fee9 = nice(fairFee9())
	if not (P.get("fee18", 0) > 0): P.fee18 = nice(fairFee18())
	if not (P.get("menu", 0) > 0): P.menu = 1.0
	if not (P.get("member", 0) > 0): P.member = nice(fairFee9() * 2.5)
	if not (P.get("short", 0) > 0): P.short = nice(fairBucket() * 0.8)
	if not (P.get("lesson", 0) > 0): P.lesson = nice(40 * incomeMult())
	if not (P.get("shortc", 0) > 0): P.shortc = nice(14 * incomeMult())
	if not (P.get("rental", 0) > 0): P.rental = nice(14 * incomeMult())
var PRICE_ITEMS: Array = []
func _build_prices() -> void:
	PRICE_ITEMS = [
		{ "k": 'bucket', "label": 'Bucket of balls', "fair": func(): return fairBucket(), "shown": func(): return true },
		{ "k": 'fee9', "label": '9 holes', "fair": func(): return fairFee9(), "shown": func(): return true },
		{ "k": 'fee18', "label": '18 holes', "fair": func(): return fairFee18(), "shown": func(): return L('back9') > 0 },
		{ "k": 'member', "label": 'Membership, per month', "fair": func(): return fairFee9() * 2.5, "shown": func(): return true },
		{ "k": 'short', "label": 'Short game session', "fair": func(): return fairBucket() * 0.8, "shown": func(): return hasObj('short') },
		{ "k": 'lesson', "label": 'Golf lesson', "fair": func(): return 40 * incomeMult(), "shown": func(): return hasObj('academy') },
		{ "k": 'rental', "label": 'Club rental', "fair": func(): return 14 * incomeMult(), "shown": func(): return true },
		{ "k": 'shortc', "label": 'Short course round', "fair": func(): return 14 * incomeMult() * (1 + 0.05 * L('green')), "shown": func(): return hasObj('shortc') },
		{ "k": 'menu', "label": 'Clubhouse menu', "fair": func(): return 1.0, "shown": func(): return L('barRoom') > 0 or L('resto') > 0, "pct": true },
	]
func ratioOf(k: String) -> float:
	for it in PRICE_ITEMS:
		if it.k == k: return float(S.prices[k]) / max(0.01, it.fair.call())
	return 1.0
## cheaper than fair brings more golfers, dearer drives them off
func valueDemand(r: float) -> float: return min(1.35, 1 + 0.7 * (1 - r)) if r <= 1 else max(0.05, exp(-1.25 * (r - 1)))
func courseValue() -> float: return 0.6 * valueDemand(ratioOf('fee9')) + 0.4 * valueDemand(ratioOf('fee18')) if L('back9') else valueDemand(ratioOf('fee9'))
func p18() -> float: return max(0.1, min(0.7, 0.4 * valueDemand(ratioOf('fee18')) / max(0.05, valueDemand(ratioOf('fee9')))))
func priceReact(v, r: float) -> void:
	var hb = BAND.get(v.get("band")) if v else null
	if hb: r = 1 + (r - 1) * hb.priceE
	if r > 1.15: emote(v, -min(25.0, (r - 1) * 30), 'annoyed', LINES.pricey, 0.4)
	elif r < 0.85: emote(v, 6, 'happy', LINES.value, 0.3)

# ---- running costs, per in-game day
func upkeepItems() -> Array:
	var it := []
	var add := func(label, v):
		if v > 0.5: it.append([label, v])
	var acc := [0.0, 0.0, 0.0]
	forRanges(func(o):
		var f := facShare('range:%s' % o.id)
		acc[0] += f * (3 * bays() + 6 * machines()); acc[1] += f * (8 * L('covered') + 14 * L('lights') + 10 * L('targets')); acc[2] += 6 * min(L('cart'), N('picker')))
	add.call('Range bays and ball machines', acc[0]); add.call('Covered bays and floodlights', acc[1]); add.call('Picker carts', acc[2])
	var holes := 0.0
	for i in 18:
		if S.get("design") and S.design.holes[i].built: holes += 6 + 2 * (S.holes[i].par - 3)
	if S.get("design"):
		for f in S.design.feats: holes += FEATS[f.type].upkeep
	add.call('Course upkeep', holes)
	if S.get("world") and S.world.get("terrain"): add.call('Ponds and lakes', 0.8 * max(0, waterCount() - int(S.world.terrain.get("nat", 0))))
	add.call('Irrigation water', 10 * L('irrig') * (1.6 if season() == 'summer' else (0.4 if season() == 'winter' else 1.0)))
	add.call('Golf carts', 12 * L('carts'))
	add.call('Clubhouse', (20 if hasObj('club') else 0) + 25 * L('barRoom') * facShare('venue:bar') + 40 * L('resto') * facShare('venue:resto') + 15 * L('terrace') * facShare('venue:terrace') + 15 * L('locker') * facShare('venue:locker') + 10 * L('food') + 30 * L('reno'))
	var o_up := 0.0
	for o in objs(): o_up += OBJ[o.type].get("upkeep", 0) * facShare('obj:%s' % o.id)
	add.call('Car parks, amenities and paths', o_up + 0.15 * (S.world.paths.size() if S.get("world") else 0))
	add.call('Advertising', 20 * L('market'))
	add.call('Business rates and insurance', RATES * S.get("invested", 0.0))
	return it
const RATES := 0.0015
func upkeepPerDay() -> float:
	var s := 0.0
	for x in upkeepItems(): s += x[1]
	return s * diff().costs
func wagesPerDay() -> float: return salaries() * DAY_LEN * diff().costs
const LOAN_RATE := 0.0025
func interestPerDay() -> float: return S.get("loan", 0.0) * LOAN_RATE + (-S.money * 0.01 if S.money < 0 else 0.0)
func creditLimit() -> float: return max(20000.0, round((20000 + 0.6 * S.get("invested", 0.0)) / 1000.0) * 1000)
var upkeepCache := 0.0
var upkeepT := 0.0

# ---- the books
const INCOME_CATS := { "members": 'Memberships', "range": 'Driving range', "course": 'Green fees', "food": 'Food and drink', "shop": 'Pro shop', "events": 'Events', "other": 'Other' }
const COST_CATS := { "wages": 'Wages', "upkeep": 'Upkeep', "interest": 'Interest', "build": 'Construction', "supplies": 'Supplies' }
func newLedger() -> Dictionary: return { "day": {}, "month": {}, "days": [], "months": [] }
func book(cat: String, v: float) -> void:
	if not S.get("ledger"): S.ledger = newLedger()
	S.ledger.day[cat] = S.ledger.day.get(cat, 0.0) + v
	S.ledger.month[cat] = S.ledger.month.get(cat, 0.0) + v
func spend(v: float, cat: String) -> void:
	if not (v > 0): return
	S.money -= v; book(cat, -v); earnLog[earnIdx] -= v
func sumOf(o) -> float:
	var s := 0.0
	if o:
		for v in o.values(): s += v
	return s
func incomeOf(o) -> float:
	var s := 0.0
	if o == null: return 0.0
	for k in INCOME_CATS: s += max(0.0, o.get(k, 0.0))
	return s
func runCosts(dt: float) -> void:
	upkeepT -= dt
	if upkeepT <= 0: upkeepT = 2; upkeepCache = upkeepPerDay()
	spend(salaries() * dt * diff().costs, 'wages')
	spend(upkeepCache * dt / DAY_LEN * diff().costs, 'upkeep')
	spend(interestPerDay() * dt / DAY_LEN, 'interest')
func endOfDay() -> void:
	if not S.get("ledger"): S.ledger = newLedger()
	var L_: Dictionary = S.ledger
	var profit := sumOf(L_.day)
	L_.days.append({ "day": S.day, "profit": profit, "income": incomeOf(L_.day) })
	if L_.days.size() > 24: L_.days.pop_front()
	L_.day = {}
	if bankDaily(): return
	repDaily()
	if S.get("over"): return
	if eventRunning() and S.day >= S.event.day + 1: resolveEvent()
	var prevMonth := monthIdx()
	S.day += 1
	if monthIdx() != prevMonth: endOfMonth(prevMonth)
	if S.get("event") and S.event.state == 'booked' and S.day >= S.event.day: startEvent()
	S.frostDay = season() == 'winter' and randf() < 0.6
	if S.frostDay: toast('Frost', 'Frosty morning', 'The greens are frozen. The course opens at 10:30 once they thaw.', '❄')
	scheduleRandomEvent()
func endOfMonth(m: int) -> void:
	boardReview(S.ledger.month.duplicate())
	var L_: Dictionary = S.ledger
	var profit := sumOf(L_.month)
	var inc := incomeOf(L_.month)
	var rec := { "name": MONTHS[m], "year": yearOf(S.day - 1) }
	rec.merge(L_.month)
	L_.months.append(rec)
	if L_.months.size() > 12: L_.months.pop_front()
	L_.month = {}
	var mb := membersMonth()
	if S.get("hcpLog"): S.hcpLog.last = S.hcpLog.month; S.hcpLog.month = {}
	rivalMonth()
	toast('Monthly report', "%s: %s%s" % [MONTHS[m], 'profit ' if profit >= 0 else 'loss ', fmt(abs(profit))], "Income %s · costs %s · members +%d −%d (%d)" % [fmt(inc), fmt(inc - profit), mb[0], mb[1], S.members], '$')
	if SEASON_OF(monthIdx()) != SEASON_OF(m):
		var se := season()
		toast('New season', se.capitalize(), { "spring": 'Golfers are coming back as the days get longer.', "summer": 'High season: long evenings and the busiest months.', "autumn": 'Wetter, windier, and the evenings draw in.', "winter": 'Short days, frost and far fewer golfers. Keep an eye on cash.' }[se], '☀')
func borrow(a: float) -> void:
	a = min(a, creditLimit() - S.get("loan", 0.0))
	if a <= 0: return
	S.loan = S.get("loan", 0.0) + a; S.money += a; sfx('kaching'); ui_refresh.emit(); save()
func repay(a: float) -> void:
	a = min(a, S.get("loan", 0.0), max(0.0, S.money))
	if a <= 0: return
	S.loan -= a; S.money -= a; sfx('tap'); ui_refresh.emit(); save()
func bankrupt() -> void: gameOver('bank')

# ---------- Live sim ----------
var groups: Array = []
var rangeAcc := 0.0
var courseAcc := 0.0
var assistAcc := 0.0
var away: Array = []
var earnLog := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var earnIdx := 0
var earnTick := 0.0
var simTime := 0.0
var groupId := 1
func earnV(who, x: float, cat: String) -> void:
	earn(x, cat)
	if who: who.spent = who.get("spent", 0.0) + x
func earn(v: float, cat := 'other') -> void:
	S.money += v; S.total += v; S.run += v; earnLog[earnIdx] += v; book(cat, v)
func pickWeather() -> String:
	var r := randf()
	var acc := 0.0
	var ws := []
	var tot := 0.0
	for e in WX_BY_SEASON[season()]:
		var w: float = e[1] * (S.smod.get('wx_' + e[0], 1.0) if S.get("smod") else 1.0)
		ws.append([e[0], w]); tot += w
	r *= tot
	for e in ws:
		acc += e[1]
		if r < acc: return e[0]
	return 'sunny'

func tick(dt: float) -> void:
	simTime += dt
	S.clock += dt
	if S.clock >= DAY_LEN: S.clock -= DAY_LEN; endOfDay()
	S.wxLeft -= dt
	if S.wxLeft <= 0: S.wx = S.wxNext; S.wxNext = pickWeather(); S.wxLeft = rnd(70, 140)
	if not S.get("prices"): ensurePrices()
	runCosts(dt)
	strike = false
	eventsTick()
	updateCrowding(dt)
	tickVisitors(dt)
	forRanges(func(_o):
		while inFlight.size() and inFlight[0].at <= simTime:
			var c: int = inFlight.pop_front().cell
			S.cells[c] += 1
		handPick(dt); syncPickers()
		for i in pickers.size(): updatePicker(pickers[i], i, dt)
		S.field = fieldTotal() + inFlight.size())
	var onHole := {}
	for g in groups:
		onHole[g.hole] = onHole.get(g.hole, 0) + g.players.size()
		stepGroup(g, dt)
	var keep := []
	for g in groups:
		if not g.get("done"): keep.append(g); continue
		if g.players.size():
			if foodCourse() and useSupply('food', g.players.size()):
				earn(foodCourse() * g.players.size(), 'food')
				for v in g.players: v.spent = v.get("spent", 0.0) + foodCourse()
			S.rounds += g.players.size(); finishRound(g)
	groups = keep
	turfTick(dt, onHole)
	membersTick(dt)
	goalsTick(dt)
	suppliesTick(dt)
	hcpTick(dt)
	shortcTick(dt)
	earnTick += dt
	if earnTick >= 1: earnTick -= 1; earnIdx = (earnIdx + 1) % 10; earnLog[earnIdx] = 0.0
	away = away.filter(func(a): return simTime - a.t < 60)
func incomeRate() -> float:
	var s := 0.0
	for i in 10:
		if i != earnIdx: s += earnLog[i]
	return s / 9.0

# ---------- Formatting ----------
func fmtInt(v: float) -> String:
	var s := str(int(floor(abs(v))))
	var out := ""
	var n := s.length()
	for i in n:
		out += s[i]
		if (n - i - 1) % 3 == 0 and i < n - 1: out += ","
	return ("-" if v < 0 else "") + out
func fmt(v: float) -> String:
	var neg := v < 0
	v = abs(v)
	var out: String
	if v < 1000:
		out = '$' + (("%.1f" % v) if (v < 10 and fmod(v, 1.0) != 0) else fmtInt(v))
	else:
		var units := ['K', 'M', 'B', 'T', 'Qa', 'Qi', 'Sx']
		var i := -1
		while v >= 1000 and i < units.size() - 1: v /= 1000.0; i += 1
		out = '$' + ((("%.2f" if v < 10 else "%.1f") % v) if v < 100 else str(int(floor(v)))) + units[i]
	return ('−' if neg else '') + out
func fmtMult(m: float) -> String:
	if m < 100: return ("%.2f" % m) if fmod(m, 1.0) != 0 else str(int(m))
	return fmtInt(round(m))
func fmtDur(s: float) -> String:
	var h := int(s / 3600)
	var m := int(fmod(s, 3600) / 60)
	return ("%d h %d m" % [h, m]) if h else (("%d m" % m) if m else ("%d s" % int(s)))
func fmtClock() -> String:
	var h := hour()
	var hh := int(h)
	var mm := int((h - hh) * 60 / 10) * 10
	return "%02d:%02d" % [hh, mm]
func toPar(p, g) -> String:
	var s := 0
	for x in p.strokes: s += x
	for k in p.strokes.size(): s -= g.pars[k]
	return 'E' if s == 0 else (('+%d' % s) if s > 0 else ('−%d' % abs(s)))

# ---------- Static scenery, generated once ----------
const LAKE := { "x": 1150.0, "y": 360.0, "rx": 62.0, "ry": 118.0 }
var trees: Array = []
var clouds: Array = []
var rain: Array = []
var treesDirty := false
func layout() -> void:
	var r := seeded(42)
	trees = []
	for k in 1500:
		var x: float = r.call() * W
		var y: float = r.call() * H
		if y > LAND_Y1 - 8: continue
		var blocked := false
		for ab in [[0, 0], [12, 12], [-12, 12], [12, -12], [-12, -12]]:
			var tt := tileOf(x + ab[0], y + ab[1])
			if tt.tx < 0 or tt.ty < 0 or tt.tx >= GW or tt.ty >= GH: continue
			var i := tIdx(tt.tx, tt.ty)
			if occ[i] > 0 or isPath[i]: blocked = true; break
		if blocked: continue
		if wetAt(x, y) > 0.12 or wetAt(x + 10, y) > 0.2 or wetAt(x - 10, y) > 0.2 or wetAt(x, y + 10) > 0.2 or wetAt(x, y - 10) > 0.2: continue
		if clearsTree(liveGeo, x, y): continue
		var rr: float = 9 + r.call() * 9
		var s: float = r.call()
		trees.append({ "x": x, "y": y, "r": rr, "s": s, "kind": 'pine' if r.call() < 0.18 else 'oak' })
	clouds = []
	for k in 14: clouds.append({ "x": randf() * W, "y": randf() * H, "r": rnd(150, 300) })
	rain = []
	for k in 140: rain.append({ "x": randf(), "y": randf(), "s": rnd(0.7, 1.3) })
	trees_changed.emit()
signal trees_changed

# =====================================================================================
# Golf, shot by shot. Every player hits every shot; where the ball ends up depends on skill and lie.
# =====================================================================================
func nearestOnHole(i: int, x: float, y: float) -> Dictionary:
	var best = G.hs[i][0]
	var bd := INF
	for q in G.hs[i]:
		var d: float = (q.x - x) * (q.x - x) + (q.y - y) * (q.y - y)
		if d < bd: bd = d; best = q
	var tn := hTan(i, best.t)
	var lat: float = (x - best.x) * -tn.y + (y - best.y) * tn.x
	return { "t": best.t, "s": best.s, "lat": lat }
func sAtT(i: int, t: float) -> float:
	var a: Array = G.hs[i]
	for q in a:
		if q.t >= t: return q.s
	return a[a.size() - 1].s
func tAtS(i: int, s: float) -> float:
	var a: Array = G.hs[i]
	for q in a:
		if q.s >= s: return q.t
	return a[a.size() - 1].t
func inEllipse(x: float, y: float, cx: float, cy: float, rx: float, ry: float, rot: float) -> bool:
	var c := cos(-rot); var sn := sin(-rot); var dx := x - cx; var dy := y - cy
	var u := dx * c - dy * sn; var w := dx * sn + dy * c
	return (u / rx) * (u / rx) + (w / ry) * (w / ry) <= 1
func greenR(i: int) -> float: return { 3: 15.0, 4: 17.0, 5: 18.0 }[parOf(i)]
func pinPos(i: int) -> Vector2:
	var g := hPt(i, 1)
	return Vector2(g.x + 2, g.y + 1)
func featAt(x: float, y: float, types = null):
	for f in G.feats:
		if types and not types.has(f.type): continue
		var F = FEATS[f.type]
		if inEllipse(x, y, f.x, f.y, F.rx, F.ry, f.get("rot", 0.0)): return f
	return null
func lieAt(i: int, x: float, y: float) -> String:
	var gp := hPt(i, 1)
	var dG := hyp(x - gp.x, y - gp.y)
	if dG <= greenR(i) - 1: return 'green'
	if inWater(x, y): return 'water'
	var f = featAt(x, y, ['pond', 'lake', 'bunker', 'waste', 'trees'])
	if f: return { "pond": 'water', "lake": 'water', "bunker": 'bunker', "waste": 'waste', "trees": 'trees' }[f.type]
	if dG <= greenR(i) + 5: return 'fringe'
	var n := nearestOnHole(i, x, y)
	if n.t > 0.1 and n.t < 0.94 and abs(n.lat) < 16: return 'fairway'
	if abs(n.lat) < 48 and n.t < 1.1: return 'rough'
	return 'trees'
const LIE := {
	"tee": { "label": 'tee', "dist": 1.0, "err": 1.0 }, "fairway": { "label": 'fairway', "dist": 0.97, "err": 1.0 }, "fringe": { "label": 'fringe', "dist": 0.97, "err": 1.0 },
	"rough": { "label": 'rough', "dist": 0.82, "err": 1.3 }, "waste": { "label": 'sand', "dist": 0.85, "err": 1.25 }, "bunker": { "label": 'bunker', "dist": 0.6, "err": 1.7 },
	"trees": { "label": 'trees', "dist": 0.55, "err": 1.9 }, "green": { "label": 'green', "dist": 1.0, "err": 1.0 }, "holed": { "label": 'holed', "dist": 1.0, "err": 1.0 },
}
func gauss() -> float: return (randf() + randf() + randf() - 1.5) * 1.15
func yd(u: float) -> int: return roundi(u * YARDS_PER_UNIT)
func ball(g, v): return g.balls.get(v.id)

# ---- choosing and hitting a shot
func planShot(v, g, b) -> Dictionary:
	var h: int = g.hole
	var pin := pinPos(h)
	var D := hyp(pin.x - b.x, pin.y - b.y)
	var sk: float = v.skill
	var L_: Dictionary = LIE.get(b.lie, LIE.rough)
	if b.lie == 'green':
		var make: float = max(0.03, min(0.97, (0.97 - 0.085 * D - 0.45 * sk) * (0.75 + 0.25 * turfOf(h) / 100.0)))
		if randf() < make: return { "kind": 'putt', "to": pin, "holed": true, "dist": D }
		var a := randf() * PI * 2
		var r := D * rnd(0.06, 0.3) + 0.6
		return { "kind": 'putt', "to": Vector2(pin.x + cos(a) * r, pin.y + sin(a) * r), "holed": false, "dist": D }
	var drop := hmAt(b.x, b.y) - hmAt(pin.x, pin.y)   # downhill shots fly further, uphill ones come up short
	var maxC: float = (142 - sk * 80) * (1.0 if b.lie == 'tee' else 0.9) * L_.dist * (1 + max(-0.12, min(0.12, drop * 0.006)))
	if D <= maxC * 0.95 or D < 45:
		var chip := D < 45
		var err: float = ((1.8 + D * 0.14) if chip else (3.5 + D * 0.1)) * (1.1 + 2.6 * sk) * L_.err * (1 + (1 - turfOf(h) / 100.0) * 0.4)
		var short := D * rnd(-0.1, 0.04)
		var dd := D if D else 1.0
		var ux = (pin.x - b.x) / dd
		var uy = (pin.y - b.y) / dd
		var to := Vector2(pin.x + ux * short + gauss() * err * 0.6, pin.y + uy * short + gauss() * err * 0.6)
		var holed := to.distance_to(pin) < (0.9 if chip else 0.75)
		return { "kind": 'chip' if chip else 'approach', "to": pin if holed else to, "holed": holed, "dist": D }
	var n := nearestOnHole(h, b.x, b.y)
	var sGreen := sAtT(h, greenT(h))
	var carry := maxC * rnd(0.88, 1.04)
	var s1: float = min(n.s + carry, sGreen - 8)
	var t1 := tAtS(h, s1)
	var lat: float = n.lat * 0.25 + gauss() * (10 + 30 * sk) * (1.15 if b.lie == 'tee' else 1.0)
	var to2 := hOff(h, t1, lat)
	return { "kind": 'full', "to": to2, "holed": false, "dist": hyp(to2.x - b.x, to2.y - b.y) }
var splashes: Array = []
const SHOT_PRE := { "putt": 0.45, "chip": 0.55, "approach": 0.7, "full": 0.75 }
func startShot(g, v) -> void:
	var b = ball(g, v)
	var plan := planShot(v, g, b)
	var dist: float = plan.to.distance_to(Vector2(b.x, b.y))
	g.shot = { "v": v, "from": Vector2(b.x, b.y), "to": plan.to, "kind": plan.kind, "holed": plan.holed, "t": -SHOT_PRE.get(plan.kind, 0.7),
		"dur": (0.4 + dist * 0.035) if plan.kind == 'putt' else (0.55 if plan.kind == 'chip' else 0.5 + dist / 240.0),
		"peak": 0.0 if plan.kind == 'putt' else (7.0 if plan.kind == 'chip' else min(70.0, dist * 0.32)), "fromLie": b.lie, "struck": false }
	b.strokes += 1
	b.flying = true
	if b.lie == 'bunker' or b.lie == 'waste':
		for k in 10: splashes.append({ "x": b.x, "y": b.y, "vx": rnd(-25, 25), "vy": rnd(-40, -10), "life": 0.6, "c": Color('#e9d7a0') })
func landShot(g) -> void:
	var sh = g.shot
	var v = sh.v
	var b = ball(g, v)
	var h: int = g.hole
	b.flying = false; b.x = sh.to.x; b.y = sh.to.y
	if sh.holed:
		b.lie = 'holed'
		sfx('cup', Vector2(b.x, b.y))
		if b.strokes < g.pars[h]: sfx('applause', Vector2(b.x, b.y), [6 if b.strokes <= g.pars[h] - 2 else 3, b.strokes <= g.pars[h] - 2], 0.35)
		if b.strokes == 1: holeInOne(v, h)
		elif b.strokes <= g.pars[h] - 2: emote(v, 12, 'delighted', ['Eagle!', 'What a shot!'], 0.8)
		elif b.strokes == g.pars[h] - 1 and randf() < 0.5: emote(v, 5, 'happy', ['Birdie!', 'Get in!'], 0.6)
	else:
		b.lie = lieAt(h, b.x, b.y)
		if sh.kind != 'putt':
			if b.lie == 'water': sfx('splash', Vector2(b.x, b.y))
			elif b.lie == 'bunker' or b.lie == 'waste': sfx('sand', Vector2(b.x, b.y), [], 0.0, 0.5)
			elif b.lie == 'trees': sfx('tree', Vector2(b.x, b.y))
		if b.lie == 'water':
			for k in 14: splashes.append({ "x": b.x, "y": b.y, "vx": rnd(-30, 30), "vy": rnd(-50, -15), "life": 0.7, "c": Color('#bfe3ff') })
			var ux: float = sh.from.x - b.x
			var uy: float = sh.from.y - b.y
			var l := hyp(ux, uy)
			if l == 0: l = 1.0
			var k := 0
			while k < 60 and lieAt(h, b.x, b.y) == 'water': b.x += ux / l * 4; b.y += uy / l * 4; k += 1
			b.strokes += 1; b.lie = lieAt(h, b.x, b.y)
			if b.lie == 'water' or b.lie == 'green': b.lie = 'rough'
			emote(v, -4, 'annoyed', ['Splash…', 'Into the drink.'], 0.5)
		elif b.lie == 'bunker' and randf() < 0.3: emote(v, -2, 'meh', null)
	if b.lie != 'holed' and b.strokes >= g.pars[h] + 4: b.lie = 'holed'; b.pickedUp = true
	g.shot = null; g.pause = 0.2

# ---- groups
func RIDE() -> float: return 70.0 + 15 * L('carts')
const STROLL := 38.0
func createGroup(mates: Array, holes: int) -> Dictionary:
	var g := { "id": groupId, "holes": holes, "players": mates, "hole": 0, "phase": 'toTee', "balls": {}, "shot": null, "pause": 0.0, "playing": true, "order": [] }
	groupId += 1
	g.pars = S.holes.slice(0, holes).map(func(h): return h.par)
	var tp := teePos(0)
	for k in mates.size():
		var v = mates[k]
		v.strokes = []; v.tee = chooseTee(v.get("hcp", 18)); v.target = Vector2(tp.x - 8 + k * 6, tp.y + 10)
	groups.append(g)
	return g
func holeBusy(g, h: int) -> bool:
	for o in groups:
		if o != g and o.hole == h and o.phase == 'play': return true
	return false
func standSpot(g, v, b) -> Vector2:
	var k: int = g.players.find(v)
	if b.lie == 'holed':
		var p := pinPos(g.hole)
		return Vector2(p.x + 8 + (k % 2) * 6, p.y + 9 + (k / 2) * 5)
	var shooter: bool = g.shot != null and g.shot.v == v
	return Vector2(b.x - (4 if (shooter or b.lie == 'green') else 6), b.y + (2 if b.lie == 'green' else 1))
func moveGolfer(v, tx: float, ty: float, dt: float) -> bool:
	var d := hyp(tx - v.x, ty - v.y)
	v.riding = L('carts') > 0 and not modOn('nocarts') and d > 30
	return moveTo(v, tx, ty, RIDE() if v.riding else STROLL, dt)
func startHole(g) -> void:
	g.phase = 'play'; g.balls = {}
	for v in g.players:
		var p := teePosFor(g.hole, v.tee)
		g.balls[v.id] = { "x": p.x, "y": p.y, "lie": 'tee', "strokes": 0, "flying": false }
	# honours: best score on the last hole tees off first
	var ord: Array = g.players.duplicate()
	ord.sort_custom(func(a, b): return (a.strokes[a.strokes.size() - 1] if a.strokes.size() else 0) < (b.strokes[b.strokes.size() - 1] if b.strokes.size() else 0))
	g.order = ord
func nextShooter(g):
	var left: Array = g.players.filter(func(v): return ball(g, v).lie != 'holed')
	if left.is_empty(): return null
	var onTee := left.filter(func(v): return ball(g, v).lie == 'tee')
	if onTee.size():
		for v in g.order:
			if onTee.has(v): return v
		return onTee[0]
	var pin := pinPos(g.hole)
	var best = null
	var bd := -1.0
	for v in left:
		var B = ball(g, v)
		var d := hyp(B.x - pin.x, B.y - pin.y)
		if d > bd: bd = d; best = v
	return best
func finishHole(g) -> void:
	for v in g.players: v.strokes.append(ball(g, v).strokes)
	if g.hole + 1 >= g.holes: g.done = true; return
	g.hole += 1; g.phase = 'toTee'
	var tp := teePos(g.hole)
	for k in g.players.size(): g.players[k].target = Vector2(tp.x - 8 + k * 6, tp.y + 10)
func stepGroup(g, dt: float) -> void:
	if g.players.is_empty(): g.done = true; return
	if g.phase == 'toTee':
		var all := true
		for v in g.players:
			if not moveGolfer(v, v.target.x, v.target.y, dt): all = false
		if all and not holeBusy(g, g.hole): startHole(g)
		return
	for v in g.players:
		if g.shot and g.shot.v == v: continue
		var st := standSpot(g, v, ball(g, v))
		moveGolfer(v, st.x, st.y, dt)
	if g.shot:
		var sh = g.shot
		sh.t += dt
		if sh.t >= 0 and not sh.struck:
			sh.struck = true
			if sh.kind == 'putt': sfx('putt', sh.from)
			elif sh.fromLie == 'bunker' or sh.fromLie == 'waste': sfx('sand', sh.from); sfx('strike', sh.from, [], 0.0, 0.35)
			else: sfx('strike', sh.from, [], 0.0, 0.5 if sh.kind == 'chip' else 1.0)
		if sh.t >= sh.dur: landShot(g)
		return
	if g.pause > 0: g.pause -= dt; return
	var v = nextShooter(g)
	if v == null: finishHole(g); return
	var st := standSpot(g, v, ball(g, v))
	if hyp(st.x - v.x, st.y - v.y) < 2.5: startShot(g, v)
	else: moveGolfer(v, st.x, st.y, dt)
## a group's rough position, for tooltips and the tee sheet
func groupPos(g) -> Dictionary:
	var ps: Array = g.players
	if ps.is_empty(): return { "x": 0.0, "y": 0.0, "hole": g.hole, "onGreen": false }
	var x := 0.0; var y := 0.0
	for v in ps: x += v.x; y += v.y
	var onGreen = g.phase == 'play'
	if onGreen:
		for v in ps:
			var b = ball(g, v)
			if not (b and (b.lie == 'green' or b.lie == 'holed')): onGreen = false
	return { "x": x / ps.size(), "y": y / ps.size(), "hole": g.hole, "onGreen": onGreen }
func holeStrokes(g, v) -> int: return ball(g, v).strokes if (g.phase == 'play' and ball(g, v)) else 0

# ---------- Traffic ----------
var spotsHeld := {}
func usedSpots(_k = null) -> int: return spotsHeld.size()
const CAR_COLORS := ['#d64a2e', '#2c4a6e', '#f5f5f0', '#2b2f36', '#7fa8bf', '#c9a227', '#3f7d4f', '#8a3b2c', '#b9bec4']
var vehicles: Array = []
var _carId := 1
func makeCar(spot) -> Dictionary:
	var path: Array = spot.via.duplicate(); path.append(Vector2(spot.x, spot.y))
	var v := { "id": _carId, "x": spot.via[0].x, "y": spot.via[0].y, "ang": 0.0 if spot.via[0].x < 0 else PI, "path": path, "pi": 1, "state": 'in', "spot": spot, "door": 0.0, "color": CAR_COLORS[randi() % CAR_COLORS.size()] }
	_carId += 1
	vehicles.append(v); return v
func follow(o, speed: float, dt: float) -> bool:
	var step := speed * dt
	while o.pi < o.path.size():
		var p: Vector2 = o.path[o.pi]
		var dx: float = p.x - o.x
		var dy: float = p.y - o.y
		var d := hyp(dx, dy)
		if d > 0.01: o.ang = atan2(dy, dx)
		if d <= step: o.x = p.x; o.y = p.y; o.pi += 1; step -= d
		else: o.x += dx / d * step; o.y += dy / d * step; return false
	return true
func driveAway(v) -> void:
	v.door = 0.7; v.leaveIn = 0.6
	sfx('door', Vector2(v.x, v.y), [false]); sfx('ignition', Vector2(v.x, v.y), [], 0.3)
func tickCars(dt: float) -> void:
	for v in vehicles:
		v.door = max(0.0, v.door - dt)
		if v.has("leaveIn"):
			v.leaveIn -= dt
			if v.leaveIn <= 0:
				v.erase("leaveIn"); v.state = 'out'; spotsHeld.erase(v.spot.key)
				var via: Array = v.spot.via.duplicate(); via.reverse()
				v.path = [v.spot.aisle] + via; v.pi = 0
		if v.state == 'in':
			if follow(v, 40.0 if v.pi >= v.path.size() - 1 else 150.0, dt):
				v.state = 'parked'; v.ang = v.spot.ang
				sfx('door', Vector2(v.x, v.y), [randf() < 0.4])
		elif v.state == 'out':
			if follow(v, 35.0 if v.pi <= 1 else 150.0, dt): v.gone = true
	vehicles = vehicles.filter(func(v): return not v.get("gone", false))
var NODES := { "LOBBY": Vector2.ZERO, "TERR": Vector2.ZERO, "ENT": Vector2.ZERO, "LOT": Vector2.ZERO, "TEE1": Vector2.ZERO, "NORTH": Vector2.ZERO, "RANGE_E": Vector2.ZERO }

# =====================================================================================
# The world: land plots, a tile grid, and everything you place on it: the range, the
# clubhouse, car parks on the road, amenities, decorations and footpaths.
# =====================================================================================
const TILE := 20.0
const GW := 110
const GH := 77
const LAND_ROWS := 74
func tIdx(tx: int, ty: int) -> int: return ty * GW + tx
func tileOf(x: float, y: float) -> Dictionary: return { "tx": int(floor(x / TILE)), "ty": int(floor(y / TILE)) }
func tileC(tx: int, ty: int) -> Vector2: return Vector2(tx * TILE + TILE / 2, ty * TILE + TILE / 2)
## things you can place. w × h in tiles
const OBJ := {
	"range":    { "label": 'Driving range', "cat": 'Facilities', "cost": 2500, "h": 18, "upkeep": 0, "icon": 'bay',
				"desc": 'Bays, a tee line, ball machines and an outfield. Widen it to either side in the Range tab. Each range has its own staff and upgrades.' },
	"club":     { "label": 'Clubhouse', "cat": 'Facilities', "cost": 4000, "unique": true, "w": 21, "h": 9, "upkeep": 0, "icon": 'reno',
				"desc": 'Pro shop and reception, with room to add a bar, restaurant, terrace and locker rooms.' },
	"lot":      { "label": 'Car park', "cat": 'Facilities', "cost": 800, "w": 8, "h": 4, "road": true, "upkeep": 5, "icon": 'rpark',
				"desc": '14 spaces. Must sit on the public road. Golfers walk to your paths from its exit.' },
	"shortc":   { "label": 'Par-3 short course', "cat": 'Facilities', "cost": 9000, "w": 20, "h": 12, "upkeep": 30, "slots": 12, "icon": 'targets',
				"desc": 'Six short par-3 holes in one plot. Novices, families and high handicappers pay for a quick round.' },
	"putt":     { "label": 'Practice putting green', "cat": 'Amenities', "cost": 1200, "w": 5, "h": 4, "upkeep": 6, "slots": 6, "icon": 'targets',
				"desc": 'Course golfers warm up here before their round. Happier golfers, better ratings.' },
	"short":    { "label": 'Short game area', "cat": 'Amenities', "cost": 2600, "w": 7, "h": 5, "upkeep": 10, "slots": 6, "icon": 'balls',
				"desc": 'A chipping green with a practice bunker. Golfers pay to practise their short game.' },
	"academy":  { "label": 'Golf academy', "cat": 'Amenities', "cost": 4500, "w": 4, "h": 3, "upkeep": 12, "icon": 'slot',
				"desc": 'A teaching studio. With a teaching pro and training aids, beginners pay for lessons.' },
	"hut":      { "label": 'Halfway house', "cat": 'Amenities', "cost": 900, "unique": true, "w": 3, "h": 3, "upkeep": 4, "icon": 'food', "free": true,
				"desc": 'A snack hut. Course golfers buy food and drink on their round. Upgrade it in the Clubhouse tab.' },
	"shed":     { "label": 'Maintenance shed', "cat": 'Amenities', "cost": 1500, "unique": true, "w": 4, "h": 3, "upkeep": 5, "icon": 'green', "free": true,
				"desc": 'Home base for greenkeepers. Without one they work at 60% speed.' },
	"bench":    { "label": 'Bench', "cat": 'Decoration', "cost": 60, "w": 1, "h": 1, "upkeep": 0, "icon": 'bay', "free": true, "decor": 1.0,
				"desc": 'A place to sit. Golfers waiting nearby are more patient.' },
	"bin":      { "label": 'Litter bin', "cat": 'Decoration', "cost": 45, "w": 1, "h": 1, "upkeep": 0.5, "icon": 'basket', "free": true, "decor": 0.5,
				"desc": 'Golfers nearby use the bin instead of dropping litter.' },
	"flowers":  { "label": 'Flowerbed', "cat": 'Decoration', "cost": 90, "w": 1, "h": 1, "upkeep": 1, "icon": 'terrace', "free": true, "decor": 1.0,
				"desc": 'Colour around your buildings. Decoration makes the park more inviting.' },
	"fountain": { "label": 'Fountain', "cat": 'Decoration', "cost": 950, "w": 2, "h": 2, "upkeep": 3, "icon": 'irrig', "free": true, "decor": 4.0,
				"desc": 'A centrepiece for the clubhouse lawn. Decoration makes the park more inviting.' },
}
const PATH_COST := 12.0
# ---- state helpers
func objs() -> Array: return S.world.objs if S.get("world") else []
func objOf(type: String):
	for o in objs():
		if o.type == type: return o
	return null
func hasObj(type: String) -> bool: return objOf(type) != null
func objById(id):
	if id == null: return null
	for o in objs():
		if o.id == id: return o
	return null
var occ := PackedInt32Array()
var isPath := PackedByteArray()
var worldVer := 0
var CDX := 0.0
var CDY := 0.0
signal world_changed
## the range's footprint grows with its bays and ball machines
func fp(o, extra = null) -> Dictionary:
	var D = OBJ[o.type]
	if o.type == 'range':
		var g := rangeGeom(o, extra)
		var x0 := int(floor((g.rx0 - 10) / TILE))
		return { "x": x0, "y": int(o.y), "w": int(ceil((g.x1 + 6 - x0 * TILE) / TILE)), "h": D.h }
	return { "x": int(o.x), "y": int(o.y), "w": D.w, "h": D.h }
## the tile people walk to: just outside the building
func doorOf(o) -> Dictionary:
	var f := fp(o)
	if o.type == 'lot': return { "tx": int(o.x) + 4, "ty": int(o.y) - 1 }
	if o.type == 'range': return { "tx": int(floor((rangeGeom(o).mx0 + 18) / TILE)), "ty": int(o.y) + f.h }
	if o.type == 'club': return { "tx": int(o.x) + 13, "ty": int(o.y) + f.h }
	return { "tx": int(o.x) + f.w / 2, "ty": int(o.y) + f.h }
func ownsTile(tx: int, ty: int) -> bool:
	var p = parcelAt(tx * TILE + 1, ty * TILE + 1)
	return p != null and S.get("world") != null and S.world.land.has(p.id)
func rebuildWorld() -> void:
	var freshTer := ensureTerrain()
	migrateRanges(); clampLevels()
	for o in rangeObjs(): o.x = fp(o).x
	occ = PackedInt32Array(); occ.resize(GW * GH)
	isPath = PackedByteArray(); isPath.resize(GW * GH)
	for ty in range(LAND_ROWS, GH):
		for tx in GW: occ[tIdx(tx, ty)] = -1   # the road
	for i in TN:
		if TER.w[i]: occ[i] = -2   # water
	for o in objs():
		var f := fp(o)
		for ty in range(f.y, f.y + f.h):
			for tx in range(f.x, f.x + f.w):
				if tx >= 0 and ty >= 0 and tx < GW and ty < GH: occ[tIdx(tx, ty)] = int(o.id)
	if S.get("world"):
		for i in S.world.paths:
			if occ[i] == 0 or occ[i] == -2: isPath[i] = 1   # a path over water is a bridge
	worldVer += 1; fields.clear(); reach = PackedByteArray(); t1Cache = findTee1(); treesDirty = true
	syncAnchors()
	if freshTer and S.get("design") and liveGeo: applyDesign()
	world_changed.emit()
## the range and clubhouse were drawn for fixed spots; these offsets move them to where you put them
func syncAnchors() -> void:
	var r = null
	for o in rangeObjs():
		if connected('OBJ:%s' % o.id): r = o; break
	if r == null: r = objOf('range')
	var c = objOf('club')
	if c: CDX = c.x * TILE - 920; CDY = c.y * TILE - 1290
	else: CDX = -5000; CDY = -5000
	var tee1 = tee1Tile()
	var ent: Vector2
	if c: var d := doorOf(c); ent = tileC(d.tx, d.ty)
	elif tee1: ent = tileC(tee1.tx, tee1.ty)
	else: ent = Vector2(W / 2, LAND_Y1 - 40)
	var lot = objOf('lot')
	NODES = {
		"LOBBY": cw(1185, 1395), "TERR": cw(1185, 1322), "ENT": ent,
		"LOT": tileC(doorOf(lot).tx, doorOf(lot).ty) if lot else ent,
		"TEE1": tileC(tee1.tx, tee1.ty) if tee1 else ent,
		"NORTH": tileC(tee1.tx, tee1.ty) if tee1 else ent,
		"RANGE_E": tileC(doorOf(r).tx, doorOf(r).ty) if r else ent,
	}
## the path tile nearest the first tee: where golfers wait to start
var t1Cache = null
func tee1Tile(): return t1Cache
func findTee1():
	if not S.get("design") or not S.design.holes[0].built or not liveGeo: return null
	var t: Vector2 = withGeo(liveGeo, func(): return teePos(0))
	var c := tileOf(t.x, t.y)
	var best = null
	var bd := 1e9
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var tx: int = c.tx + dx
			var ty: int = c.ty + dy
			if tx < 0 or ty < 0 or tx >= GW or ty >= LAND_ROWS or not isPath[tIdx(tx, ty)]: continue
			var d := dx * dx + dy * dy
			if d < bd: bd = d; best = { "tx": tx, "ty": ty }
	return best
# ---- walking: breadth-first distance fields over the footpaths, one per destination
var fields := {}
var reach := PackedByteArray()
func walkable(i: int) -> bool: return isPath[i] == 1
func nodeTile(key: String):
	if key == 'TEE1': return tee1Tile()
	if key.begins_with('OBJ:'):
		var o = objById(int(key.substr(4)))
		return doorOf(o) if o else null
	var o = null
	if key == 'RANGE':
		for x in rangeObjs():
			if x.get("r") and reachOK('OBJ:%s' % x.id): o = x; break
		if o == null: o = objOf('range')
	else: o = objOf('club' if key == 'CLUB' else key)
	return doorOf(o) if o else null
func fieldOf(key: String) -> PackedInt32Array:
	if fields.has(key): return fields[key]
	var t = nodeTile(key)
	var f := PackedInt32Array(); f.resize(GW * GH); f.fill(-1)
	if t and t.tx >= 0 and t.ty >= 0 and t.tx < GW and t.ty < GH and walkable(tIdx(t.tx, t.ty)):
		var q := [tIdx(t.tx, t.ty)]
		f[q[0]] = 0
		var h := 0
		while h < q.size():
			var i: int = q[h]; h += 1
			var x := i % GW
			var y := i / GW
			var d := f[i] + 1
			for j in [i - 1 if x > 0 else -1, i + 1 if x < GW - 1 else -1, i - GW if y > 0 else -1, i + GW if y < GH - 1 else -1]:
				if j >= 0 and f[j] < 0 and walkable(j): f[j] = d; q.append(j)
	fields[key] = f
	return f
func reachOK(key: String) -> bool:
	var t = nodeTile(key)
	return t != null and reach.size() > 0 and t.tx >= 0 and t.ty >= 0 and t.tx < GW and t.ty < GH and reach[tIdx(t.tx, t.ty)] == 1
## can golfers get from a car park to here?
func connected(key: String) -> bool:
	var t = nodeTile(key)
	if not t: return false
	if reach.is_empty():
		reach = PackedByteArray(); reach.resize(GW * GH)
		for o in objs():
			if o.type == 'lot':
				var f := fieldOf('OBJ:%s' % o.id)
				for i in f.size():
					if f[i] >= 0: reach[i] = 1
	return t.tx >= 0 and t.ty >= 0 and t.tx < GW and t.ty < GH and reach[tIdx(t.tx, t.ty)] == 1
func nearestPath(x: float, y: float, r := 5):
	var c := tileOf(x, y)
	var best = null
	var bd := 1e9
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var tx: int = c.tx + dx
			var ty: int = c.ty + dy
			if tx < 0 or ty < 0 or tx >= GW or ty >= GH or not isPath[tIdx(tx, ty)]: continue
			var p := tileC(tx, ty)
			var d := hyp(p.x - x, p.y - y)
			if d < bd: bd = d; best = { "tx": tx, "ty": ty }
	return best
## points along the paths from where someone stands to a destination
func routePts(v, key: String):
	var f := fieldOf(key)
	var s = nearestPath(v.x, v.y, 8)
	if not s or f[tIdx(s.tx, s.ty)] < 0: return null
	var vid: int = int(v.get("id", 0))
	var jx := ((vid * 37) % 9) - 4
	var jy := ((vid * 53) % 9) - 4
	var out := []
	var i := tIdx(s.tx, s.ty)
	var guard := 0
	while f[i] > 0 and guard < 4000:
		guard += 1
		var x := i % GW
		var y := i / GW
		out.append(Vector2(x * TILE + TILE / 2 + jx, y * TILE + TILE / 2 + jy))
		var nx := -1
		for j in [i - 1 if x > 0 else -1, i + 1 if x < GW - 1 else -1, i - GW if y > 0 else -1, i + GW if y < GH - 1 else -1]:
			if j >= 0 and f[j] >= 0 and f[j] < f[i]: nx = j; break
		if nx < 0: break
		i = nx
	out.append(Vector2((i % GW) * TILE + TILE / 2 + jx, (i / GW) * TILE + TILE / 2 + jy))
	# drop points in the middle of straight runs
	var res := []
	for k in out.size():
		if k == 0 or k == out.size() - 1: res.append(out[k]); continue
		var p: Vector2 = out[k]
		var a: Vector2 = out[k - 1]
		var b: Vector2 = out[k + 1]
		if (abs(a.x - p.x) < 1 and abs(b.x - p.x) < 1) or (abs(a.y - p.y) < 1 and abs(b.y - p.y) < 1): continue
		res.append(p)
	return res
const LEGACY_KEY := { "RANGE_E": 'RANGE', "LOBBY": 'CLUB', "TERR": 'CLUB', "ENT": 'CLUB', "TEE1": 'TEE1', "NORTH": 'TEE1' }
## the clubhouse's own front door and hallway, in clubhouse coordinates
func cw(x: float, y: float) -> Vector2: return Vector2(x + CDX, y + CDY)

# ---- facilities open for business: built and connected to a car park
func rangeOK() -> bool:
	for o in rangeObjs():
		if o.get("r") and connected('OBJ:%s' % o.id) and facOpen('range:%s' % o.id): return true
	return false
func clubOK() -> bool: return hasObj('club') and connected('CLUB')
func courseHoles() -> int:
	var n := 0
	while n < 18 and S.get("design") and S.design.holes[n].built: n += 1
	return n
func courseOK() -> bool: return courseHoles() > 0 and tee1Tile() != null and connected('TEE1') and clubOK()
func amenOK(o) -> bool: return connected('OBJ:%s' % o.id)

# ---- car parks: spaces along an aisle; cars come off the public road
func lotSpots(o) -> Array:
	var px: float = o.x * TILE
	var py: float = o.y * TILE
	var cx := px + 80
	var ay := py + 40
	var base := []
	for k in 8: base.append({ "x": px + 10 + k * 20, "y": py + 15, "ang": -PI / 2 })
	for k in 8:
		if k != 3 and k != 4: base.append({ "x": px + 10 + k * 20, "y": py + 66, "ang": PI / 2 })
	var out := []
	for i in base.size():
		var s: Dictionary = base[i]
		var fromLeft: bool = (int(o.id) + i) % 2 == 0
		var lane: float = ROAD_Y + 7 if fromLeft else ROAD_Y - 7
		s.merge({ "via": [Vector2(-60 if fromLeft else W + 60, lane), Vector2(cx, lane), Vector2(cx, ay), Vector2(s.x, ay)], "aisle": Vector2(s.x, ay), "lot": 'main', "lotId": o.id, "key": "L%s:%d" % [o.id, i], "cx": cx, "ay": ay, "exit": tileC(int(o.x) + 4, int(o.y) - 1) })
		out.append(s)
	return out
func totalSpots() -> int: return objs().filter(func(o): return o.type == 'lot').size() * 14
## the lot nearest to where they're heading
func freeSpot(kind: String):
	var target: Vector2 = NODES.RANGE_E if (kind == 'range' and hasObj('range')) else NODES.ENT
	var lots := objs().filter(func(o): return o.type == 'lot' and connected('OBJ:%s' % o.id) and facOpen('obj:%s' % o.id))
	lots.sort_custom(func(a, b): return hyp(a.x * TILE - target.x, a.y * TILE - target.y) < hyp(b.x * TILE - target.x, b.y * TILE - target.y))
	for o in lots:
		for s in lotSpots(o):
			if not spotsHeld.has(s.key): spotsHeld[s.key] = 1; return s
	return null
func carSide(s) -> Vector2: return Vector2(s.x + 9, s.y + (s.aisle.y - s.y) * 0.6)
func carToNet(spot) -> Dictionary: return { "pts": [carSide(spot), Vector2(spot.x + 9, spot.ay), Vector2(spot.cx, spot.ay), spot.exit], "node": 'OBJ:%s' % spot.lotId }

# ---- placing things
func blockedFor(o, tx: int, ty: int) -> bool:
	var v := occ[tIdx(tx, ty)]
	return v != 0 and not (o and v == int(o.id))
func holeNear(x: float, y: float, pad := 34.0) -> int:
	if not liveGeo: return -1
	for i in 18:
		if not liveGeo.corr[i].built: continue
		for q in liveGeo.hs[i]:
			if abs(q.x - x) < pad + 30 and hyp(q.x - x, q.y - y) < pad + 30: return i
	return -1
## can this footprint go here?
func canPlace(type: String, tx: int, ty: int, moving = null, extra = null) -> Dictionary:
	var D = OBJ[type]
	var probe: Dictionary
	if type == 'range' and moving:
		probe = shiftRange(moving, tx); probe.y = ty
	else: probe = { "type": type, "x": tx, "y": ty }
	var f := fp(probe, extra)
	tx = f.x
	if D.get("road") and ty + f.h != LAND_ROWS: return { "ok": false, "why": 'Car parks have to sit on the public road.' }
	if tx < 0 or ty < 0 or tx + f.w > GW or ty + f.h > LAND_ROWS: return { "ok": false, "why": 'Out of bounds.' }
	for y in range(ty, ty + f.h):
		for x in range(tx, tx + f.w):
			if not ownsTile(x, y): return { "ok": false, "why": "You don't own all of this land. Buy more in the Land tool." }
			if blockedFor(moving, x, y): return { "ok": false, "why": "You can't build on water." if occ[tIdx(x, y)] == -2 else 'Something is already built here.' }
			if isPath[tIdx(x, y)] and not D.get("road"): return { "ok": false, "why": 'Remove the footpath here first.' }
			var c := tileC(x, y)
			if not D.get("decor") and holeNear(c.x, c.y, 10) >= 0: return { "ok": false, "why": "This would cut into hole %d." % (holeNear(c.x, c.y, 10) + 1) }
	return { "ok": true }
## would this range still fit with more bays or machines?
func rangeFits(ex: Dictionary) -> bool:
	var o = curR if curR else selRange()
	if not o: return false
	var e := { "bay": int(o.r.lvl.get("bay", 0)), "bayL": int(o.r.lvl.get("bayL", 0)), "dmach": int(o.r.lvl.get("dmach", 0)) }
	e.merge(ex, true)
	return canPlace('range', fp(o).x, int(o.y), o, e).ok
func placeObj(type: String, tx: int, ty: int) -> Dictionary:
	var D = OBJ[type]
	var ok := canPlace(type, tx, ty)
	if not ok.ok: return ok
	if S.money < D.cost: return { "ok": false, "why": 'Not enough cash.' }
	spend(D.cost, 'build'); S.invested = S.get("invested", 0.0) + D.cost
	var no := { "id": int(S.world.nextId), "type": type, "x": tx, "y": ty }
	S.world.nextId = int(S.world.nextId) + 1
	if type == 'range': no.r = newRangeState(); no.r.mx = tx * TILE + 20; selRangeId = no.id
	S.world.objs.append(no); levelPlot(fp(no))
	rebuildWorld(); layout(); sfx('kaching')
	return { "ok": true }
## moving a building: whoever is using it finishes up first
func evictFrom(type: String, o) -> void:
	if type == 'range':
		withRange(o, func():
			for v in visitors.duplicate():
				if v.get("rangeId") != o.id or v.state == 'drive' or v.state == 'gone': continue
				if v.state == 'play': finishRange(v)
				elif v.state == 'filling' or bucketQueue.has(v) or rangeQueue.has(v):
					leaveQueue(v)
					if v.get("machine") != null: filling[v.machine] = null; v.machine = null
					nextStop(v))
		return
	for v in visitors.duplicate():
		if v.state == 'drive' or v.state == 'gone': continue
		if type == 'club' and v.state == 'desk': finishCheckin(v); continue
		if type == 'club' and (v.state == 'venue' or v.state == 'locker' or lobbyQueue.has(v) or deskQueue.has(v)):
			if v.state == 'venue': leaveVenue(v)
			else: leaveQueue(v); nextStop(v)
func moveObj(o, tx: int, ty: int) -> Dictionary:
	var ok := canPlace(o.type, tx, ty, o)
	if not ok.ok: return ok
	evictFrom(o.type, o)
	if o.type == 'range': o.r.mx = shiftRange(o, tx).r.mx
	o.x = tx; o.y = ty; levelPlot(fp(o)); rebuildWorld(); layout(); sfx('chime')
	if o.type == 'range':
		withRange(o, func():
			for p in pickers: p.x = machinePos(0).x; p.y = TEE_Y - 16; p.state = 'idle'; p.target = -1)
	return { "ok": true }
func removeObj(o) -> Dictionary:
	if o.type == 'club': return { "ok": false, "why": 'Use Move to relocate the clubhouse.' }
	if o.type == 'range' and withRange(o, func(): return rangeP.size() + bucketQueue.size() + rangeQueue.size() + filling.filter(func(x): return x != null).size()) > 0:
		return { "ok": false, "why": 'Golfers are using this range. Try again when it is empty.' }
	if o.type == 'lot':
		for k in spotsHeld.keys():
			if str(k).begins_with("L%s:" % o.id): return { "ok": false, "why": 'Cars are parked here. Try again when it is empty.' }
	if amenUsers(o).size(): return { "ok": false, "why": 'Golfers are using it. Try again in a moment.' }
	S.world.objs.erase(o); RT.erase(o.id)
	earn(round(OBJ[o.type].cost * 0.4), 'other')
	rebuildWorld(); layout(); sfx('soft')
	return { "ok": true }
func paintPath(tx: int, ty: int, on: bool) -> bool:
	if tx < 0 or ty < 0 or tx >= GW or ty >= LAND_ROWS: return false
	var i := tIdx(tx, ty)
	var has: bool = S.world.paths.has(i)
	if on:
		var c := BRIDGE_COST if occ[i] == -2 else PATH_COST
		if has or (occ[i] != 0 and occ[i] != -2) or not ownsTile(tx, ty) or S.money < c: return false
		spend(c, 'build'); S.world.paths.append(i)
	else:
		if not has: return false
		S.world.paths.erase(i); earn((BRIDGE_COST if occ[i] == -2 else PATH_COST) / 2, 'other')
	rebuildWorld(); return true
func buyPlot(id: int) -> bool:
	var price := parcelPrice()
	if S.world.land.has(id) or S.money < price: return false
	spend(price, 'build'); S.invested = S.get("invested", 0.0) + price
	S.world.land.append(id)
	if S.get("design"): S.design.land = S.world.land
	rebuildWorld(); sfx('kaching'); return true
## straight runs of path between two tiles, for laying out ready-made parks
func pathRun(w: Dictionary, x0: int, y0: int, x1: int, y1: int) -> void:
	for x in range(min(x0, x1), max(x0, x1) + 1):
		var i := tIdx(x, y0)
		if not w.paths.has(i): w.paths.append(i)
	for y in range(min(y0, y1), max(y0, y1) + 1):
		var i := tIdx(x1, y)
		if not w.paths.has(i): w.paths.append(i)
func plotsCovering(x0: float, y0: float, x1: float, y1: float) -> Array:
	var out := []
	for p in PARCELS:
		if p.x0 < x1 and p.x1 > x0 and p.y0 < y1 and p.y1 > y0: out.append(p.id)
	return out
## the original Pine Hollow layout, for the rescue scenario
func classicWorld(oldLand = null) -> Dictionary:
	var w := { "land": [], "objs": [], "paths": [], "nextId": 1 }
	var land := {}
	var OLD_C := [0, 440, 880, 1320, 1760, 2200]
	var OLD_R := [0, 320, 640, 960, 1280]
	for id in (oldLand if oldLand else [2, 3, 4, 7, 8, 9, 12, 13, 14, 17, 18, 19]):
		var c: int = id % 5
		var r: int = id / 5
		for x in plotsCovering(OLD_C[c], OLD_R[r], OLD_C[c + 1], OLD_R[r + 1]): land[x] = 1
	for x in plotsCovering(0, 0, 1100, 620): land[x] = 1
	for x in plotsCovering(780, 1200, 1700, LAND_Y1): land[x] = 1
	for x in plotsCovering(1080, 540, 1240, 1300): land[x] = 1
	var ks := land.keys(); ks.sort()
	w.land = ks
	var add := func(type, x, y):
		w.objs.append({ "id": w.nextId, "type": type, "x": x, "y": y }); w.nextId += 1
	add.call('range', 2, 2); add.call('club', 46, 64); add.call('lot', 68, 70); add.call('lot', 76, 70); add.call('putt', 40, 66)
	pathRun(w, 72, 69, 80, 69); pathRun(w, 67, 69, 72, 69); pathRun(w, 59, 73, 67, 73); pathRun(w, 67, 73, 67, 63)
	pathRun(w, 67, 63, 59, 63); pathRun(w, 59, 63, 59, 28); pathRun(w, 42, 70, 42, 73); pathRun(w, 42, 73, 59, 73)
	return w
## fill in the range's walkway once its door is known (depends on its width)
func linkRange(w: Dictionary) -> void:
	var r = null
	for o in w.objs:
		if o.type == 'range': r = o; break
	if not r: return
	var prev = S.get("world")
	S.world = w
	var d := doorOf(r)
	S.world = prev
	pathRun(w, d.tx, d.ty, d.tx, 28); pathRun(w, d.tx, 28, 59, 28)
func freshWorld(kind: String) -> Dictionary:
	var w := { "land": [], "objs": [], "paths": [], "nextId": 1 }
	if kind == 'sandbox': w.land = PARCELS.map(func(p): return p.id)
	else: w.land = plotsCovering(880, 960, 1540, LAND_Y1)
	return w
func ensureWorld() -> void:
	if not S.get("world") or not (S.world.get("objs") is Array):
		S.world = classicWorld(null)
		linkRange(S.world)
	if not S.get("sup"): S.sup = { "shop": 300.0, "food": 300.0, "fert": 150.0, "training": 40.0, "rental": 8.0 }
	if not S.get("auto"): S.auto = { "shop": true, "food": true, "fert": true, "training": true }
	if S.get("design"): S.design.land = S.world.land
	rebuildWorld()

# ---------- Terrain: hills, valleys and water ----------
# Heights are stored per tile in half-metre steps; water is a per-tile flag.
const TN := GW * LAND_ROWS
const H_MIN := -12
const H_MAX := 32
const H_STEP := 0.5
const TERRA := {
	"raise":   { "label": 'Raise land',  "short": 'Raise',   "cost": 8,  "help": 'Brush to build up hills. Each pass adds about a metre in the middle of the brush.' },
	"lower":   { "label": 'Lower land',  "short": 'Lower',   "cost": 8,  "help": 'Brush to dig out hollows and valleys.' },
	"flatten": { "label": 'Level land',  "short": 'Level',   "cost": 8,  "help": 'Brush to level the ground to the height where you start.' },
	"smooth":  { "label": 'Smooth land', "short": 'Smooth',  "cost": 6,  "help": 'Brush to soften steep banks and bumps.' },
	"water":   { "label": 'Dig water',   "short": 'Water',   "cost": 90, "help": 'Paint ponds, lakes and streams. Water beside or across a hole raises its rating. Lay footpath over water for a bridge.' },
	"drain":   { "label": 'Fill in water', "short": 'Fill in', "cost": 45, "help": 'Brush over water to fill it back in with turf.' },
}
const BRUSH := [{ "k": 'S', "r": 0.6 }, { "k": 'M', "r": 2.0 }, { "k": 'L', "r": 3.1 }]
const BRIDGE_COST := 60.0
var TER := { "h": PackedInt32Array(), "w": PackedByteArray(), "src": null, "ver": 1 }
var terBrush := 1
var terStroke = null
var terDirtyT := 0.0
signal terrain_changed

# ---- storage: compact strings in the save
func encTer() -> void:
	var hb := PackedByteArray(); hb.resize(TN)
	var wb := PackedByteArray(); wb.resize(TN)
	for i in TN:
		hb[i] = 36 + TER.h[i] - H_MIN
		wb[i] = 49 if TER.w[i] else 48
	var nat: int = int(S.world.terrain.get("nat", 0)) if S.world.get("terrain") else 0
	S.world.terrain = { "h": hb.get_string_from_ascii(), "w": wb.get_string_from_ascii(), "nat": nat }
	TER.src = S.world.terrain; TER.ver += 1
	terrain_changed.emit()
func decTer(t: Dictionary) -> void:
	TER.h = PackedInt32Array(); TER.h.resize(TN)
	TER.w = PackedByteArray(); TER.w.resize(TN)
	var hb: PackedByteArray = str(t.h).to_ascii_buffer()
	var wb: PackedByteArray = str(t.w).to_ascii_buffer()
	for i in TN:
		TER.h[i] = clampi((hb[i] if i < hb.size() else 48) - 36 + H_MIN, H_MIN, H_MAX)
		TER.w[i] = 1 if (i < wb.size() and wb[i] == 49) else 0
	TER.src = t; TER.ver += 1
	terrain_changed.emit()
func waterCount() -> int:
	var n := 0
	for i in TN: n += TER.w[i]
	return n

# ---- a new park's ground: gentle rolling land, shaped by the scenario, with the old lake as water
const TER_STYLE := { "fresh": [3.0, 9.0], "rescue": [3.0, 9.0], "city": [1.2, 12.0], "seaside": [4.0, 4.0], "oakmere": [5.0, 10.0], "frost": [4.0, 8.0], "estate": [9.0, 12.0], "champ": [7.0, 10.0], "sandbox": [4.0, 10.0] }
func genTerrain(seedKey: int) -> void:
	var st: Array = TER_STYLE.get(S.get("scenario", ""), [3.0, 9.0])
	var amp: float = st[0]
	var scale: float = st[1]
	var r := seeded(7 + seedKey)
	var oct := []
	for e in [[scale, 1.0], [scale / 2, 0.45], [scale / 4, 0.2]]:
		var gw := int(ceil(GW / e[0])) + 2
		var gh := int(ceil(LAND_ROWS / e[0])) + 2
		var g := PackedFloat32Array(); g.resize(gw * gh)
		for k in gw * gh: g[k] = r.call() * 2 - 1
		oct.append({ "s": e[0], "a": e[1], "gw": gw, "g": g })
	TER.h = PackedInt32Array(); TER.h.resize(TN)
	TER.w = PackedByteArray(); TER.w.resize(TN)
	for ty in LAND_ROWS:
		for tx in GW:
			var v := 0.0
			for o in oct:
				var u: float = tx / o.s
				var w: float = ty / o.s
				var i := int(floor(u)); var j := int(floor(w))
				var fx := sst(u - i); var fy := sst(w - j)
				var gw: int = o.gw
				var g: PackedFloat32Array = o.g
				v += o.a * ((g[j * gw + i] * (1 - fx) + g[j * gw + i + 1] * fx) * (1 - fy) + (g[(j + 1) * gw + i] * (1 - fx) + g[(j + 1) * gw + i + 1] * fx) * fy)
			var edge: float = min(1.0, (LAND_ROWS - 1 - ty) / 6.0)
			TER.h[ty * GW + tx] = roundi(clampf(v * amp * 2 * edge + 1, H_MIN, H_MAX))
	# the lake that was always there
	var nat := 0
	for ty in LAND_ROWS:
		for tx in GW:
			var c := tileC(tx, ty)
			if hyp((c.x - LAKE.x) / (LAKE.rx + 6), (c.y - LAKE.y) / (LAKE.ry + 6)) < 1: TER.w[ty * GW + tx] = 1; nat += 1
	# water sits in a hollow, and buildings stand on level plots
	for i in TN:
		if TER.w[i]: TER.h[i] = max(H_MIN, TER.h[i] - 2)
	for o in (S.world.objs if S.get("world") else []): levelPlot(fp(o), true)
	S.world.terrain = { "h": '', "w": '', "nat": nat }
	encTer()
	S.world.terrain.nat = nat
## level a building's footprint (free: the builders do it)
func levelPlot(f: Dictionary, quiet := false) -> void:
	var s := 0; var n := 0
	for y in range(f.y, f.y + f.h):
		for x in range(f.x, f.x + f.w):
			if x >= 0 and y >= 0 and x < GW and y < LAND_ROWS: s += TER.h[y * GW + x]; n += 1
	if not n: return
	var avg := roundi(float(s) / n)
	for y in range(f.y, f.y + f.h):
		for x in range(f.x, f.x + f.w):
			if x >= 0 and y >= 0 and x < GW and y < LAND_ROWS: TER.h[y * GW + x] = avg; TER.w[y * GW + x] = 0
	if not quiet: encTer()
## called before the world's grid is rebuilt: decode the save, or make terrain for a park that has none
func ensureTerrain() -> bool:
	if not S.get("world"): return false
	var t = S.world.get("terrain")
	if not t or not (t.get("h") is String) or t.h.length() != TN or not (t.get("w") is String) or t.w.length() != TN:
		genTerrain(S.world.land.size()); return true
	if TER.src != t: decTer(t)
	return false

# ---- reading the ground
func tH(tx: int, ty: int) -> int: return TER.h[clampi(ty, 0, LAND_ROWS - 1) * GW + clampi(tx, 0, GW - 1)]
func tW(tx: int, ty: int) -> int: return 0 if (tx < 0 or ty < 0 or tx >= GW or ty >= LAND_ROWS) else TER.w[ty * GW + tx]
func isWaterTile(tx: int, ty: int) -> bool: return tW(tx, ty) != 0
## height in metres at a point (bilinear between tile centres)
func hmAt(x: float, y: float) -> float:
	var u := x / TILE - 0.5; var v := y / TILE - 0.5
	var i := int(floor(u)); var j := int(floor(v))
	var fx := u - i; var fy := v - j
	return H_STEP * ((tH(i, j) * (1 - fx) + tH(i + 1, j) * fx) * (1 - fy) + (tH(i, j + 1) * (1 - fx) + tH(i + 1, j + 1) * fx) * fy)
func sst(x: float) -> float: return x * x * (3 - 2 * x)
func rawWet(x: float, y: float) -> float:
	var u := x / TILE - 0.5; var v := y / TILE - 0.5
	var i := int(floor(u)); var j := int(floor(v))
	var fx := sst(u - i); var fy := sst(v - j)
	return (tW(i, j) * (1 - fx) + tW(i + 1, j) * fx) * (1 - fy) + (tW(i, j + 1) * (1 - fx) + tW(i + 1, j + 1) * fx) * fy
## The water field: the tile flags smoothed and softened, sampled twice per tile. The shoreline is 0.5.
## The view draws exactly this field (as a texture), so what you see is what the ball lands in.
const WQ := 2
var WF := { "v": PackedFloat32Array(), "NX": 1, "NY": 1, "ver": -1, "bodies": [], "glints": [], "any": false }
func waterField() -> Dictionary:
	if WF.ver == TER.ver: return WF
	WF.ver = TER.ver
	var s := TILE / WQ
	var NX := GW * WQ + 1
	var NY := LAND_ROWS * WQ + 1
	var v := PackedFloat32Array(); v.resize(NX * NY)
	var any := false
	for i in TN:
		if TER.w[i]: any = true; break
	if any:
		for y in NY:
			for x in NX:
				v[y * NX + x] = rawWet(x * s, y * s)
		# soften the corners: two small box blurs
		var tmp := PackedFloat32Array(); tmp.resize(NX * NY)
		for _pass in 2:
			for y in NY:
				var row := y * NX
				for x in NX:
					var a := v[row + x]; var k := 1
					if x > 0: a += v[row + x - 1]; k += 1
					if x < NX - 1: a += v[row + x + 1]; k += 1
					tmp[row + x] = a / 3.0 if k == 3 else a / k
			for y in NY:
				for x in NX:
					var a := tmp[y * NX + x]; var k := 1
					if y > 0: a += tmp[(y - 1) * NX + x]; k += 1
					if y < NY - 1: a += tmp[(y + 1) * NX + x]; k += 1
					v[y * NX + x] = a / k
	WF.v = v; WF.NX = NX; WF.NY = NY; WF.any = any
	# bodies of water, for ducks and the ambience
	var seen := PackedByteArray(); seen.resize(TN)
	var bodies := []
	for i in TN:
		if not TER.w[i] or seen[i]: continue
		var q := [i]
		var tiles := []
		seen[i] = 1
		while q.size():
			var j: int = q.pop_back(); tiles.append(j)
			var tx := j % GW; var ty := j / GW
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = tx + d[0]; var ny: int = ty + d[1]
				if nx < 0 or ny < 0 or nx >= GW or ny >= LAND_ROWS: continue
				var k := ny * GW + nx
				if TER.w[k] and not seen[k]: seen[k] = 1; q.append(k)
		var inner := tiles.filter(func(j): var tx: int = j % GW; var ty: int = j / GW; return tW(tx + 1, ty) and tW(tx - 1, ty) and tW(tx, ty + 1) and tW(tx, ty - 1))
		var cx := 0.0; var cy := 0.0
		for j in tiles: cx += (j % GW) * TILE + TILE / 2; cy += (j / GW) * TILE + TILE / 2
		bodies.append({ "n": tiles.size(), "tiles": tiles, "inner": inner, "x": cx / tiles.size(), "y": cy / tiles.size() })
	bodies.sort_custom(func(a, b): return a.n > b.n)
	var r := seeded(TER.ver % 997 + 5)
	var glints := []
	for b in bodies:
		if b.inner.is_empty(): continue
		for k in min(24, int(ceil(b.inner.size() / 3.0))):
			var j: int = b.inner[int(floor(r.call() * b.inner.size()))]
			glints.append({ "x": (j % GW) * TILE + r.call() * TILE, "y": (j / GW) * TILE + r.call() * TILE, "ph": r.call() * 6 })
	WF.bodies = bodies; WF.glints = glints
	return WF
## how wet a point is, 0..1
func wetAt(x: float, y: float) -> float:
	var g := waterField()
	if not g.any: return 0.0
	var u := x / TILE * WQ; var v := y / TILE * WQ
	var i := int(floor(u)); var j := int(floor(v))
	var fx := u - i; var fy := v - j
	var NX: int = g.NX; var NY: int = g.NY
	var f: PackedFloat32Array = g.v
	var a := 0.0 if (i < 0 or j < 0 or i >= NX or j >= NY) else f[j * NX + i]
	var b := 0.0 if (i + 1 < 0 or j < 0 or i + 1 >= NX or j >= NY) else f[j * NX + i + 1]
	var c := 0.0 if (i < 0 or j + 1 < 0 or i >= NX or j + 1 >= NY) else f[(j + 1) * NX + i]
	var d := 0.0 if (i + 1 < 0 or j + 1 < 0 or i + 1 >= NX or j + 1 >= NY) else f[(j + 1) * NX + i + 1]
	return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
func inWater(x: float, y: float) -> bool: return y < LAND_Y1 and wetAt(x, y) >= 0.5
## water a hole plays over or alongside
func waterOnHole(i: int) -> Dictionary:
	var hs: Array = G.hs[i]
	var wet := []
	var carry := false
	for q in hs:
		var w: bool = q.t >= 0.05 and q.t <= 1.02 and inWater(q.x, q.y)
		wet.append(w)
		if w: carry = true
	var beside := false
	for k in hs.size():
		if beside: break
		var q = hs[k]
		if q.t < 0.05 or q.t > 1.02: continue
		var near := false
		for m in range(max(0, k - 8), min(hs.size() - 1, k + 8) + 1):
			if wet[m]: near = true; break
		if near: continue   # that's the carry, not water alongside
		var t := tileOf(q.x, q.y)
		for dy in range(-3, 4):
			if beside: break
			for dx in range(-3, 4):
				if tW(t.tx + dx, t.ty + dy):
					var c := tileC(t.tx + dx, t.ty + dy)
					if hyp(c.x - q.x, c.y - q.y) < 56: beside = true; break
	return { "carry": carry, "beside": beside }
## ups and downs along a hole, in metres
func elevOfHole(i: int) -> Dictionary:
	var h = G.design.holes[i]
	var a := hmAt(h.tee.x, h.tee.y)
	var b := hmAt(h.green.x, h.green.y)
	var lo := INF; var hi := -INF
	for q in G.hs[i]:
		if q.t < 0 or q.t > 1: continue
		var z := hmAt(q.x, q.y)
		lo = min(lo, z); hi = max(hi, z)
	return { "delta": round((b - a) * 2) / 2.0, "range": round((hi - lo) * 2) / 2.0 }
## is a green ringed by water?
func islandGreen(i: int) -> bool:
	var g = G.design.holes[i].green
	var R := greenR(i) + 32
	for k in 16:
		var a := k / 16.0 * PI * 2
		if not inWater(g.x + cos(a) * R, g.y + sin(a) * R): return false
	return true

# ---- why a tile can't be landscaped
func terraWhy(op: String, tx: int, ty: int) -> String:
	if tx < 0 or ty < 0 or tx >= GW or ty >= LAND_ROWS - 1: return 'Out of bounds.'
	if not ownsTile(tx, ty): return "You don't own this land."
	var i := tIdx(tx, ty)
	var o := occ[i]
	if o > 0 or o == -1: return 'Something is built here.'
	if op == 'water':
		if isPath[i]: return 'Remove the footpath here first.'
		var c := tileC(tx, ty)
		for k in 18:
			if not holeOpen(k): continue
			var h = G.design.holes[k]
			if hyp(c.x - h.green.x, c.y - h.green.y) < greenR(k) + 12 or hyp(c.x - h.tee.x, c.y - h.tee.y) < 22: return 'Keep water off tees and greens.'
	return ''
## brush the ground around a point; returns what it cost (0 if nothing changed)
func terraBrush(op: String, wx: float, wy: float) -> float:
	if terStroke == null: terStroke = { "op": op, "seen": {}, "cost": 0.0, "target": null, "why": '', "wet": false }
	var st: Dictionary = terStroke
	var c := tileOf(wx, wy)
	var R: float = BRUSH[terBrush].r
	var n := int(ceil(R))
	if op == 'flatten' and st.target == null: st.target = tH(c.tx, c.ty)
	var edits := []
	for dy in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var d := hyp(dx, dy)
			if d > R: continue
			var tx: int = c.tx + dx; var ty: int = c.ty + dy
			var why := terraWhy(op, tx, ty)
			if why:
				if edits.is_empty(): st.why = why
				continue
			var i := ty * GW + tx
			var fall := 1 - pow(d / (R + 0.6), 2)
			var cur: int = TER.h[i]
			if op == 'raise' or op == 'lower':
				var want: int = max(1, roundi(2 * fall))
				var done: int = st.seen.get(i, 0)
				var add := want - done
				if add <= 0: continue
				var nh: int = clampi(cur + (add if op == 'raise' else -add), H_MIN, H_MAX)
				if nh == cur: continue
				edits.append([i, nh, null, abs(nh - cur) * TERRA[op].cost]); st.seen[i] = want
			elif op == 'flatten':
				var nh: int = st.target if fall > 0.55 else roundi(cur + (st.target - cur) * 0.5)
				if nh == cur: continue
				edits.append([i, nh, null, abs(nh - cur) * TERRA[op].cost])
			elif op == 'smooth':
				if st.seen.has(i): continue
				var s := 0.0; var k := 0
				for yy in range(-1, 2):
					for xx in range(-1, 2): s += tH(tx + xx, ty + yy); k += 1
				var nh := roundi((cur + s / k) / 2.0); st.seen[i] = 1
				if nh == cur: continue
				edits.append([i, nh, null, abs(nh - cur) * TERRA[op].cost])
			elif op == 'water' and not TER.w[i]: edits.append([i, max(H_MIN, cur - 2), 1, TERRA.water.cost])
			elif op == 'drain' and TER.w[i]: edits.append([i, cur if cur + 2 > H_MAX else cur + 2, 0, TERRA.drain.cost])
	if edits.is_empty(): return 0.0
	var total := 0.0
	for e in edits: total += e[3]
	if S.money < total: st.why = 'Not enough cash.'; return 0.0
	for e in edits:
		TER.h[e[0]] = e[1]
		if e[2] != null: TER.w[e[0]] = e[2]; st.wet = true
	spend(total, 'build'); S.invested = S.get("invested", 0.0) + total; st.cost += total; st.why = ''
	encTer()
	if st.wet: rebuildWorld()
	terDirtyT = 0.25
	return total
## returns the stroke's outcome for the build bar: { msg, bad }
func endTerraStroke() -> Dictionary:
	if terStroke == null: return { "msg": '', "bad": false }
	var st: Dictionary = terStroke
	terStroke = null
	if st.cost:
		applyDesign()
		if st.wet: layout()
		sfx('splash' if (st.op == 'water' or st.op == 'drain') else 'sand')
		for i in 18:
			if holeOpen(i) and islandGreen(i): unlockAch('ACH_ISLAND'); break
		save()
	return { "msg": st.why if st.why else (("That cost %s." % fmt(st.cost)) if st.cost else ''), "bad": st.why != '' }
## ratings follow the ground while you sculpt, a few times a second
func terraTick(dt: float) -> void:
	if terDirtyT > 0:
		terDirtyT -= dt
		if terDirtyT <= 0: applyDesign(); ui_refresh.emit()

# ---- identity helpers: Godot compares dictionaries by content, so people and objects are matched with is_same()
func has_(a: Array, x) -> bool:
	for e in a:
		if is_same(e, x): return true
	return false
func idx(a: Array, x) -> int:
	for i in a.size():
		if is_same(a[i], x): return i
	return -1
func del(a: Array, x) -> void:
	var i := idx(a, x)
	if i >= 0: a.remove_at(i)

# ---- amenities golfers visit: putting green, short game area, academy
var AMEN := {}
func _build_amen() -> void:
	AMEN = {
		"putt":    { "dur": [16, 24], "mood": 7, "lines": ['Nice warm-up.', 'Greens are rolling well.'], "fee": func(): return 0.0, "cat": 'other' },
		"short":   { "dur": [24, 34], "mood": 8, "lines": ['Chipping is coming along.', 'Got out of that bunker!'], "fee": func(): return float(S.prices.get("short", 0)), "cat": 'range' },
		"shortc":  { "dur": [80, 100], "mood": 9, "lines": ['Great little course!', 'Perfect for a quick round.', 'Made a birdie on the 4th!'], "fee": func(): return float(S.prices.get("shortc", 0)), "cat": 'course' },
		"academy": { "dur": [36, 46], "mood": 12, "lines": ['That lesson really helped.', 'Finally fixed my slice!'], "fee": func(): return float(S.prices.get("lesson", 0)), "cat": 'shop' },
	}
func amenSlots(o) -> int: return min(3, N('coach')) if o.type == 'academy' else int(OBJ[o.type].get("slots", 4))
var amenQ := {}
var amenIn := {}   # object id → visitors inside
func amenUsers(o) -> Array: return amenIn.get(o.id, [])
func amenOpen(o) -> bool:
	if not amenOK(o) or not facOpen('obj:%s' % o.id): return false
	if o.type == 'academy': return N('coach') > 0 and S.sup.training > 0
	return true
func amenFor(type: String) -> Array: return objs().filter(func(o): return o.type == type and amenOpen(o))
func amenSpot(o, k: int) -> Vector2:
	var f := fp(o)
	var px: float = f.x * TILE
	var py: float = f.y * TILE
	var n: int = max(1, amenSlots(o))
	if o.type == 'academy': return Vector2(px + 14 + k * 18, py + 30)
	if o.type == 'shortc': return shortcPos(o, k, 0)
	var cols := int(ceil(sqrt(n)))
	var r := k / cols
	var c := k % cols
	return Vector2(px + (c + 0.5) * f.w * TILE / cols, py + 14 + (r + 0.5) * (f.h * TILE - 24) / ceil(float(n) / cols))
func startAmen(v, type: String) -> void:
	var list := amenFor(type)
	if list.is_empty(): nextStop(v); return
	var o = list[randi() % list.size()]
	v.amen = o.id; v.amenType = o.type
	walkNet(v, v.at, 'OBJ:%s' % o.id, [], func(_v):
		if not objById(o.id): nextStop(v); return
		v.state = 'queue'; v.wait = 0.0; v.relief = 0.0; v.patience = 40 * v.temper; v.grumbled = false
		if not amenQ.has(o.id): amenQ[o.id] = []
		amenQ[o.id].append(v))
func serveAmen() -> void:
	for o in objs():
		var q: Array = amenQ.get(o.id, [])
		if q.is_empty(): continue
		if not amenIn.has(o.id): amenIn[o.id] = []
		var inside: Array = amenIn[o.id]
		while q.size() and inside.size() < amenSlots(o) and amenOpen(o):
			var v = q.pop_front(); calm(q)
			var k := 0
			for i in amenSlots(o):
				var used := false
				for u in inside:
					if u.get("amenSlot") == i: used = true; break
				if not used: k = i; break
			inside.append(v); v.amenSlot = k
			var s := amenSpot(o, k)
			var A = AMEN[o.type]
			walk(v, [s], func(_v): v.state = 'amen'; v.t = 0.0; v.dur = rnd(A.dur[0], A.dur[1]))
			if o.type == 'academy': S.sup.training = max(0.0, S.sup.training - 1)
func finishAmen(v) -> void:
	var o = objById(v.get("amen"))
	var A = AMEN.get(o.type) if o else null
	if o: amenIn[o.id] = amenIn.get(o.id, []).filter(func(u): return not is_same(u, v))
	if A:
		var fee: float = A.fee.call()
		if fee > 0:
			earnV(v, fee * spendOf(v), A.cat); moneyPop(v, fee)
			priceReact(v, ratioOf({ "academy": 'lesson', "short": 'short', "shortc": 'shortc' }[o.type]))
		emote(v, A.mood + (6 if (o.type == 'academy' and v.type == 'beginner') else 0), null, A.lines, 0.5)
		if o.type == 'academy': v.skill = max(0.0, v.skill - 0.03)
	v.amen = null; v.amenSlot = null; nextStop(v)
## decoration: a little more appeal for every flowerbed, bench and fountain, up to +12%
func decorAppeal() -> float:
	var d := 0.0
	for o in objs(): d += OBJ[o.type].get("decor", 0.0)
	return 1 + min(0.12, d * 0.004)
func nearObj(type: String, x: float, y: float, r: float) -> bool:
	for o in objs():
		if o.type == type and hyp(o.x * TILE + 10 - x, o.y * TILE + 10 - y) < r: return true
	return false

# ---- supplies: stock you order, which runs down as it's used
const SUPPLIES := {
	"shop":     { "label": 'Pro shop stock', "pack": 100, "cost": 260, "unit": 'items', "icon": 'shop', "desc": 'Balls, gloves and tees. Every shop sale uses one. An empty shop sells nothing.' },
	"food":     { "label": 'Food and drink', "pack": 100, "cost": 320, "unit": 'servings', "icon": 'resto', "desc": 'For the bar, restaurant, terrace and halfway house. They close when it runs out.' },
	"fert":     { "label": 'Seed and fertiliser', "pack": 60, "cost": 380, "unit": 'bags', "icon": 'green', "desc": 'Greenkeepers use it to repair turf. Without it they work at 40% speed.' },
	"training": { "label": 'Training aids', "pack": 40, "cost": 300, "unit": 'kits', "icon": 'slot', "desc": 'Alignment sticks, mats and video kits. Each academy lesson uses one.' },
	"rental":   { "label": 'Rental club sets', "pack": 4, "cost": 700, "unit": 'sets', "icon": 'cart', "desc": 'Beginners without clubs rent a set. More sets, fewer disappointed beginners.', "durable": true },
}
var rentalsOut := 0
var supT := 0.0
func orderSupply(k: String, auto := false) -> bool:
	var D = SUPPLIES[k]
	var c := roundf(D.cost * (1.1 if auto else 1.0))
	if S.money < c: return false
	spend(c, 'supplies'); S.sup[k] = S.sup.get(k, 0.0) + D.pack
	if not auto: sfx('kaching')
	return true
func suppliesTick(dt: float) -> void:
	supT += dt
	if supT < 3: return
	supT = 0
	for k in SUPPLIES:
		if not SUPPLIES[k].get("durable") and S.auto.get(k) and S.sup[k] < SUPPLIES[k].pack * 0.25 and S.money > SUPPLIES[k].cost * 3: orderSupply(k, true)
func useSupply(k: String, n := 1) -> bool:
	if S.sup.get(k, 0.0) < n: return false
	S.sup[k] -= n
	return true
func hasFood() -> bool: return (S.sup.food if S.get("sup") else 1.0) > 0

# ---------- Clubhouse venues ----------
const ROOMS := {
	"locker":  { "x0": 930.0,  "y0": 1350.0, "x1": 1000.0, "y1": 1430.0, "label": 'Locker rooms' },
	"resto":   { "x0": 1000.0, "y0": 1350.0, "x1": 1130.0, "y1": 1430.0, "label": 'Restaurant' },
	"lobby":   { "x0": 1130.0, "y0": 1350.0, "x1": 1240.0, "y1": 1430.0, "label": 'Pro shop' },
	"bar":     { "x0": 1240.0, "y0": 1350.0, "x1": 1320.0, "y1": 1430.0, "label": 'Bar' },
	"terrace": { "x0": 1000.0, "y0": 1294.0, "x1": 1240.0, "y1": 1350.0, "label": 'Terrace' },
}
func seatsGrid(cols: int, rows: int, x0: float, y0: float, dx: float, dy: float, per: int) -> Array:
	var out := []
	for r in rows:
		for c in cols:
			var cx := x0 + c * dx
			var cy := y0 + r * dy
			for k in per:
				var a := float(k) / per * PI * 2 + PI / 4
				out.append({ "x": cx + cos(a) * 7.5, "y": cy + sin(a) * 6.5, "tx": cx, "ty": cy })
	return out
var VENUE_SEATS := {}
const VENUE_LABEL := { "shop": 'Pro shop', "bar": 'Bar', "resto": 'Restaurant', "terrace": 'Terrace' }
const VENUE_ROOM := { "shop": 'lobby', "bar": 'bar', "resto": 'resto', "terrace": 'terrace' }
func _build_venues() -> void:
	var shop := []
	for p in [[1146, 1366], [1160, 1366], [1146, 1384], [1160, 1384], [1146, 1402], [1160, 1402]]: shop.append({ "x": p[0], "y": p[1] })
	var bar := []
	for x in [1252, 1262, 1272, 1282, 1292, 1302]: bar.append({ "x": x, "y": 1374 })
	bar.append_array(seatsGrid(3, 1, 1257, 1408, 23, 0, 3))
	VENUE_SEATS = { "shop": shop, "bar": bar, "resto": seatsGrid(3, 2, 1050, 1372, 30, 34, 4), "terrace": seatsGrid(6, 1, 1022, 1322, 39, 0, 4) }
func venueCap(k: String) -> int:
	match k:
		"shop": return min(6, 2 + L('shop') / 4 + N('assist'))
		"bar": return min(15, 6 + 3 * (L('barRoom') - 1)) if L('barRoom') else 0
		"resto": return min(24, 8 + 4 * (L('resto') - 1)) if L('resto') else 0
		"terrace": return min(24, 8 + 4 * (L('terrace') - 1)) if L('terrace') else 0
	return 0
func venueOpen(k: String) -> bool:
	var o := false
	match k:
		"shop": o = hasObj('club')
		"bar": o = L('barRoom') > 0 and N('bar') > 0 and hasFood()
		"resto": o = L('resto') > 0 and N('chef') > 0 and hasFood()
		"terrace": o = L('terrace') > 0 and L('barRoom') > 0 and N('bar') > 0 and hasFood() and S.wx != 'rain' and not isDark()
	return o and facOpen('venue:' + k)
func venueDur(k: String) -> float:
	match k:
		"shop": return rnd(6, 10)
		"bar": return rnd(18, 26) / (1 + 0.12 * N('bar'))
		"resto": return rnd(32, 44) / (1 + 0.1 * N('chef'))
		"terrace": return rnd(24, 32)
	return 10.0
func venueSpend(k: String) -> float:
	match k:
		"shop": return (4 + 1.0 * L('shop')) * (1 + 0.1 * min(5, N('assist'))) * incomeMult()
		"bar": return 7 * (1 + 0.2 * (L('barRoom') - 1)) * (1 + 0.15 * min(3, N('bar'))) * incomeMult()
		"resto": return 16 * (1 + 0.15 * (L('resto') - 1)) * (1 + 0.15 * min(3, N('chef'))) * incomeMult()
		"terrace": return 11 * (1 + 0.15 * (L('terrace') - 1)) * (1 + 0.12 * min(3, N('bar'))) * (1.25 if S.wx == 'sunny' else 1.0) * incomeMult()
	return 0.0
const LOCKERS := [Vector2(948, 1372), Vector2(962, 1372), Vector2(976, 1372), Vector2(948, 1408), Vector2(962, 1408), Vector2(976, 1408)]
var seatTaken := { "shop": {}, "bar": {}, "resto": {}, "terrace": {} }
func takeSeat(k: String) -> int:
	var n := venueCap(k)
	for i in n:
		if not seatTaken[k].get(i, false): seatTaken[k][i] = true; return i
	return -1
func foodOpen() -> bool: return venueOpen('bar') or venueOpen('resto') or venueOpen('terrace')
## what someone fancies at the clubhouse right now
func pickVenue(afterPlay: bool) -> String:
	var h := hour()
	var w := []
	if venueOpen('shop'): w.append(['shop', 0.6 if afterPlay else 1.4])
	if venueOpen('bar'): w.append(['bar', 2.0 if h >= 17 else 1.0])
	if venueOpen('resto'): w.append(['resto', 2.6 if ((h >= 11 and h < 14) or (h >= 18 and h < 21)) else 0.8])
	if venueOpen('terrace'): w.append(['terrace', 2.4 if S.wx == 'sunny' else 1.2])
	var tot := 0.0
	for e in w: tot += e[1]
	var r := randf() * tot
	for e in w:
		r -= e[1]
		if r <= 0: return e[0]
	return 'shop'

# ---------- Visitors ----------
# Everyone arrives with a plan: an ordered list of stops ('range', 'course', 'club').
# At each stop they queue; if they wait longer than their patience, they give up and go home.
var visitors: Array = []
var teeQueue: Array = []
var lobbyQueue: Array = []
var visitorId := 1
var clubAcc := 0.0
func PATIENCE(k: String) -> float:
	var p := 60.0
	match k:
		"range": p = 90.0
		"bay": p = 75.0
		"course": p = 110 * (1 + 0.2 * N('starter')) * (1 + 0.15 * L('locker'))
		"club": p = 45 * (1 + 0.1 * L('reno'))
		"checkin": p = 70 * (1 + 0.1 * L('reno'))
	return p * diff().patience
const WALK := 62.0
const SHIRT := ['#ffffff', '#f2c14e', '#7fd3ff', '#ff9ec7', '#c6f27a', '#ffb070']
func newName() -> String: return FIRST[randi() % FIRST.size()] + '. ' + LAST[randi() % LAST.size()]
func arriveVisitor(plan: Array, forceType = null) -> void:
	var lot: String = 'range' if plan[0] == 'range' else 'club'
	var spot = freeSpot(lot)
	if not spot and lot == 'range': spot = freeSpot('club')
	if not spot: away.append({ "t": simTime, "why": 'rpark' if lot == 'range' else 'cpark' }); return
	var v := {
		"id": visitorId, "plan": plan, "step": 0, "state": 'drive', "car": makeCar(spot), "x": 0.0, "y": 0.0, "path": [], "pi": 0, "at": null,
		"color": SHIRT[randi() % SHIRT.size()], "name": newName(), "skill": randf() * 0.5, "strokes": [],
		"bag": plan.has('course') or plan.has('range'), "holes": 18 if (L('back9') and facOpen('back9') and randf() < p18()) else min(9, max(1, courseHoles())), "didLocker": false, "temper": rnd(0.8, 1.3), "standing": pickStanding(),
		"slot": null, "then": null, "speed": WALK, "upset": 0.0, "wait": 0.0, "relief": 0.0, "patience": 60.0, "grumbled": false, "t": 0.0, "dur": 1.0,
		"rangeId": null, "hasBucket": false, "machine": null, "seat": null, "venue": null, "amen": null, "amenType": null, "amenSlot": null, "deskSlot": null,
		"riding": false, "cart": false, "paid": false, "spent": 0.0, "ang": 0.0, "fx": null, "bay": null, "rental": false,
	}
	visitorId += 1
	v.temper *= STANDING[v.standing].temper
	v.arrived = { "day": S.day, "clock": S.clock }
	v.type = forceType if forceType else 'regular'
	assignHcp(v, forceType)
	if v.type == 'member': v.temper *= 1.3
	v.mood = 65.0 + (12 if v.standing == 'exemplary' else (-12 if v.standing == 'bad' else 0)) + rnd(-8, 8) + modAdd('mood')
	conductLog.append(v.standing)
	if conductLog.size() > 200: conductLog.pop_front()
	# amenities: a warm-up putt before a round, a lesson for beginners, short game practice
	if plan.has('course'): plan.insert(plan.find('course'), 'checkin')
	var ci := plan.find('course')
	if ci >= 0 and amenFor('putt').size() and randf() < 0.45: plan.insert(ci, 'putt')
	if v.type == 'beginner' and amenFor('academy').size() and randf() < 0.35: plan.insert(1 if plan[0] == 'range' else 0, 'lesson')
	if amenFor('short').size() and randf() < (0.3 if plan[0] == 'range' else 0.12): plan.insert(1 if plan[0] == 'range' else 0, 'short')
	# beginners without clubs rent a set, if there is one
	if v.type == 'beginner' and v.bag and randf() < 0.5:
		if rentalsOut < (S.sup.rental if S.get("sup") else 0):
			rentalsOut += 1; v.rental = true; earnV(v, S.prices.get("rental", 0.0) * spendOf(v), 'shop')
		else: v.mood -= 8
	visitors.append(v)
func walk(v, pts: Array, then: Callable, speed := WALK) -> void:
	v.path = pts; v.pi = 0; v.state = 'walk'; v.then = then; v.speed = speed; v.slot = null
func walkNet(v, _from, to: String, extra: Array, then: Callable) -> void:
	var key: String = LEGACY_KEY.get(to, to)
	var pre := [cw(1185, 1448), cw(1185, 1402)] if to == 'LOBBY' else []
	var pts = routePts(v, key)
	if pts == null:
		var t = nodeTile(key)
		pts = [tileC(t.tx, t.ty)] if t else []
	var all: Array = pts + pre + extra
	walk(v, all, func(vv): v.at = to; then.call(v))
func startStop(v) -> void:
	var stop: String = v.plan[v.step]
	if stop == 'course' and (isDark() or not courseOK() or not facOpen('course')): nextStop(v); return
	if stop == 'range' and not rangeOK(): nextStop(v); return
	if stop == 'range' and not v.get("rangeId"):
		var o = pickRange()
		if not o: nextStop(v); return
		v.rangeId = o.id
	if stop == 'club' and not clubOK(): nextStop(v); return
	if stop == 'putt' or stop == 'short' or stop == 'shortc': startAmen(v, stop); return
	if stop == 'checkin': startCheckin(v); return
	if stop == 'lesson': startAmen(v, 'academy'); return
	if stop == 'range':   # join the line once at the machines
		var o = rangeOfV(v)
		if not o or not connected('OBJ:%s' % o.id):
			o = pickRange()
			if not o: nextStop(v); return
			v.rangeId = o.id
		var spot: Vector2 = withRange(o, func(): return Vector2(machinePos(0).x + 8, TEE_Y + 34))
		walkNet(v, v.at, 'OBJ:%s' % o.id, [spot], func(vv): joinQueue(vv))
	elif stop == 'course':
		if L('locker') and not v.didLocker and facOpen('venue:locker'):
			var lk: Vector2 = LOCKERS[randi() % LOCKERS.size()]
			walkNet(v, v.at, 'LOBBY', [cw(1135, 1392), cw(1000, 1392), Vector2(lk.x + CDX + rnd(-3, 3), lk.y + CDY + 8)], func(_v):
				v.didLocker = true; v.state = 'locker'; v.t = 0.0; v.dur = rnd(4, 6))
		else: walkNet(v, v.at, 'TEE1', [teeWaitPos()], func(vv): joinQueue(vv))
	else: walkNet(v, v.at, 'LOBBY', [cw(1185 + rnd(-14, 14), 1412 + rnd(-6, 6))], func(vv): joinQueue(vv))
func teeWaitPos() -> Vector2:
	var t := teePos(0)
	return Vector2(t.x - 30 + rnd(-10, 10), t.y + 22 + rnd(-6, 8))
func joinQueue(v) -> void:
	var stop: String = v.plan[v.step]
	v.state = 'queue'; v.wait = 0.0; v.relief = 0.0; v.patience = PATIENCE(stop) * v.temper * (1.2 if nearObj('bench', v.x, v.y, 90) else 1.0); v.grumbled = false
	if stop == 'range': inRangeOf(v, func(): bucketQueue.append(v))
	elif stop == 'course': teeQueue.append(v)
	else: v.want = pickVenue(v.step > 0); lobbyQueue.append(v)
func leaveQueue(v) -> void:
	if v.get("rangeId") and not curR: inRangeOf(v, func(): leaveQueue(v)); return
	for q in [bucketQueue, rangeQueue, teeQueue, lobbyQueue, deskQueue] + amenQ.values(): del(q, v)
	if has_(deskIn, v): del(deskIn, v); v.deskSlot = null
func giveUp(v) -> void:
	if v.get("rangeId") and not curR: inRangeOf(v, func(): giveUp(v)); return
	var waitingForBay := has_(rangeQueue, v)
	leaveQueue(v)
	if waitingForBay and v.hasBucket: S.stock = min(ballCap(), S.stock + v.keep); v.hasBucket = false   # they hand the bucket back
	var stop: String = v.plan[v.step]
	away.append({ "t": simTime, "why": 'gaveup-bay' if waitingForBay else 'gaveup-' + stop, "range": v.get("rangeId") })
	emote(v, -25, 'angry', LINES.giveUp, 0.6)
	if v.get("eventPlayer") and S.get("event") and not v.get("evDone"): v.evDone = true; S.event.moods.append(5)
	goHome(v)
func nextStop(v) -> void:
	v.step += 1
	if v.step < v.plan.size(): startStop(v)
	else: goHome(v)
func goHome(v) -> void:
	recordMood(v)
	if v.get("rental"): v.rental = false; rentalsOut = max(0, rentalsOut - 1)
	var net := carToNet(v.car.spot)
	var pts: Array = net.pts.duplicate(); pts.reverse()
	walkNet(v, v.at, net.node, pts, func(_v): v.state = 'gone'; driveAway(v.car))
## range: take a staffed bay when one frees up
func freeBay() -> int:
	for i in range(staffedBays() - 1, -1, -1):
		if not bayTaken.has(i) and not brokenBays.has(i): return i
	return -1
func bucketSlot(k: int) -> Vector2:
	var m := machinePos(0)
	return Vector2(m.x - 2 + (k % 2) * 9, TEE_Y + 30 + (k / 2) * 9)
func baySlot(k: int) -> Vector2: return Vector2(rangeX1() - 14 - (k % 4) * 9, TEE_Y + 46 + (k / 4) * 9)
## moving up the line gives a little patience back: 4% a step, and never more than a quarter of it per queue
func calm(q: Array) -> void:
	for v in q:
		var pt: float = v.get("patience", 60.0)
		if not pt: pt = 60.0
		var cap := pt * 0.25
		var give: float = min(pt * 0.04, cap - v.get("relief", 0.0), v.wait)
		if give > 0: v.wait -= give; v.relief = v.get("relief", 0.0) + give
func serveBuckets() -> void:
	for m in machines():
		while filling.size() <= m: filling.append(null)
		if filling[m]: continue
		if bucketQueue.is_empty() or S.stock < 50: return
		var v = bucketQueue.pop_front(); filling[m] = v
		calm(bucketQueue)
		var lost := int(floor(rnd(1, 3) + (1 if S.wx == 'windy' else 0)))
		S.owned -= lost; S.lost += lost; S.stock -= 50; v.keep = 50 - lost
		var mp := machinePos(m)
		walk(v, [Vector2(mp.x, TEE_Y + 17)], func(_v):
			v.state = 'filling'; v.t = 0.0; v.dur = fillTime() * rnd(0.9, 1.1); v.machine = m
			sfx('balls', Vector2(v.x, v.y)))
func bucketDone(v) -> void:
	filling[v.machine] = null; v.machine = null
	earnV(v, bucketPrice() * spendOf(v), 'range'); earnV(v, shopSpend() * spendOf(v), 'shop'); S.buckets = S.get("buckets", 0) + 1
	moneyPop(v, bucketPrice()); priceReact(v, ratioOf('bucket'))
	v.hasBucket = true; v.state = 'queue'; v.patience = PATIENCE('bay') * v.temper; v.grumbled = false
	if v.wait > v.patience * 0.5: emote(v, -3, 'annoyed', LINES.finally, 0.4)
	else: v.mood = min(100.0, moodOf(v) + 2)
	v.wait = 0.0; v.relief = 0.0
	rangeQueue.append(v)
func serveRange() -> void:
	while rangeQueue.size():
		var b := freeBay()
		if b < 0: return
		var v = rangeQueue.pop_front(); bayTaken[b] = true
		calm(rangeQueue)
		v.bay = b; v.t = 0.0; v.dur = RANGE_DUR * rnd(0.8, 1.2); v.acc = 0.0; v.swing = 0
		walk(v, [Vector2(bayX(b), TEE_Y + 34), Vector2(bayX(b) - 4, TEE_Y + 2)], func(_v): inRangeOf(v, func(): v.state = 'play'; rangeP.append(v)))
func finishRange(v) -> void:
	del(rangeP, v); bayTaken.erase(v.bay); v.hasBucket = false
	var d = 8 + 3 * min(3, L('targets')) + min(3.0, L('balls') / 3.0) + (3 if (L('covered') and S.wx == 'rain') else 0) - (6 if (S.wx == 'rain' and not L('covered')) else 0)
	emote(v, d, null, LINES.rangeGood if moodOf(v) + d >= 60 else LINES.rangeMeh)
	walk(v, [Vector2(bayX(v.bay), TEE_Y + 34), rangeDoorPt()], func(_v): v.at = 'RANGE_E'; v.bay = null; nextStop(v))
## course: groups form at the first tee from whoever is waiting
func serveTee() -> void:
	if isDark() or not facOpen('course'):
		for v in teeQueue.duplicate(): leaveQueue(v); nextStop(v)
		return
	if teeQueue.is_empty() or groups.size() >= slots(): return
	var first = teeQueue[0]
	var mates := teeQueue.filter(func(v): return v.holes == first.holes).slice(0, 4)
	if mates.size() < 4 and first.wait < maxWait(): return
	for o in groups:
		if o.hole == 0: return   # the first tee is still busy
	calm(teeQueue.filter(func(v): return not has_(mates, v)))
	for v in mates:
		if v.wait > v.patience * 0.5: emote(v, -4, 'annoyed', LINES.finally, 0.35)
	for v in mates:
		leaveQueue(v); v.state = 'golf'; earnV(v, shopSpend() * spendOf(v), 'shop')
		if v.type == 'member' or v.get("eventPlayer") or v.get("paid"): continue
		payGreenFee(v)
	createGroup(mates, first.holes)
func finishRound(g) -> void:
	for v in g.players: v.card = g.pars.slice(0, v.strokes.size())
	var cart: bool = L('carts') > 0 and not modOn('nocarts')
	for k in g.players.size():
		var v = g.players[k]
		v.riding = false
		walk(v, [NODES.NORTH], func(_v): v.at = 'NORTH'; v.cart = false; nextStop(v), 160.0 if cart else 75.0)
		v.cart = cart
		var over := 0
		for s in v.strokes: over += s
		for p in g.pars: over -= p
		var avgR := 0.0
		for i in g.holes: avgR += holeRating(i)
		avgR /= g.holes
		var expected: float = g.holes * (-0.15 + 2.3 * v.skill)
		var tm := typeRoundMood(v, g)
		var d: float = 12 - (over - expected) * 1.6 + (tm.turf - 75) / 5.0 + avgR * 0.8 - (6 if S.wx == 'rain' else 0) + tm.d
		var lines = tm.lines if tm.lines else (LINES.roundGreat if over <= 0 else (LINES.roundGood if moodOf(v) + d >= 55 else LINES.roundBad))
		emote(v, d, null, lines, 0.55 if tm.lines else (0.7 if over <= 0 else 0.35))
		if v.get("eventPlayer") and S.get("event") and not v.get("evDone"): v.evDone = true; S.event.moods.append(moodOf(v))
		if v.type == 'member': S.memberMood = S.get("memberMood", 70.0) * 0.9 + moodOf(v) * 0.1
# ---- the clubhouse desk: golfers check in and pay their green fee (members show their card)
var deskQueue: Array = []
var deskIn: Array = []
func desks() -> int: return 1 + min(2, N('assist'))
func deskSlot(k: int) -> Vector2: return cw(1214 - (k % 2) * 9, 1398 + (k / 2) * 8)
func deskSpot(k: int) -> Vector2: return cw(1200 + k * 9, 1383)
func payGreenFee(v) -> void:
	var fee: float = fee18() if v.holes == 18 else fee9() * min(9, v.holes) / 9.0
	earnV(v, fee * spendOf(v), 'course'); moneyPop(v, fee); priceReact(v, ratioOf('fee18' if v.holes == 18 else 'fee9'))
	v.paid = true
func startCheckin(v) -> void:
	if isDark() or not courseOK() or not facOpen('course'): v.step += 1; nextStop(v); return
	walkNet(v, v.at, 'LOBBY', [], func(_v):
		v.state = 'queue'; v.wait = 0.0; v.relief = 0.0; v.patience = PATIENCE('checkin') * v.temper; v.grumbled = false; deskQueue.append(v))
func serveDesk() -> void:
	for k in deskQueue.size(): deskQueue[k].slot = deskSlot(k)
	while deskQueue.size() and deskIn.size() < desks():
		var v = deskQueue.pop_front(); calm(deskQueue)
		var k := 0
		for i in 3:
			var used := false
			for u in deskIn:
				if u.get("deskSlot") == i: used = true; break
			if not used: k = i; break
		deskIn.append(v); v.deskSlot = k; v.slot = null
		walk(v, [deskSpot(k)], func(_v): v.state = 'desk'; v.t = 0.0; v.dur = rnd(3.5, 5.5) / (1 + 0.1 * min(5, N('assist'))))
func finishCheckin(v) -> void:
	sfx('desk', Vector2(v.x, v.y))
	del(deskIn, v); v.deskSlot = null
	if v.type == 'member' or v.get("eventPlayer"): emote(v, 2, null, ['Morning! Member card.', 'Just me today, thanks.'], 0.15)
	else:
		payGreenFee(v)
		# a happy regular might sign up as a member at the desk
		var r := ratioOf('member')
		var room: bool = S.get("members", 0) < memberCap()
		if room and v.type != 'beginner' and randf() < 0.025 * (moodOf(v) / 70.0) * valueDemand(1 + (r - 1) * 1.2):
			S.members = S.get("members", 0) + 1; S.deskJoins = S.get("deskJoins", 0) + 1; v.type = 'member'
			earn(S.prices.member * 0.25, 'members')
			emote(v, 10, 'happy', ['Signed up as a member!', 'Count me in as a member.'], 0.9)
	v.paid = true; nextStop(v)
func serveLobby() -> void:
	var i := 0
	while i < lobbyQueue.size():
		var v = lobbyQueue[i]
		if not venueOpen(v.want): v.want = pickVenue(v.step > 0)
		var seat := takeSeat(v.want)
		if seat < 0: i += 1; continue
		lobbyQueue.remove_at(i)
		calm(lobbyQueue)
		v.seat = seat; v.venue = v.want
		var s = VENUE_SEATS[v.venue][seat]
		var via := []
		if v.venue == 'terrace': via = [NODES.LOBBY, cw(1185, 1350)]
		elif v.venue == 'resto': via = [cw(1132, 1395)]
		elif v.venue == 'bar': via = [cw(1238, 1395)]
		via.append(Vector2(s.x + CDX, s.y + CDY))
		walk(v, via, func(_v): v.state = 'venue'; v.t = 0.0; v.dur = venueDur(v.venue))
func leaveVenue(v) -> void:
	var stocked := useSupply('shop' if v.venue == 'shop' else 'food')
	var vs: float = venueSpend(v.venue) * spendOf(v) * (1.0 if v.venue == 'shop' else S.prices.menu * modMult('food')) if stocked else 0.0
	if not stocked: emote(v, -8, 'annoyed', ['Nothing in stock?', 'Sold out, again.'], 0.6)
	else: earnV(v, vs, 'shop' if v.venue == 'shop' else 'food'); moneyPop(v, vs)
	if v.venue == 'shop': S.sales = S.get("sales", 0) + 1
	else: priceReact(v, S.prices.menu)
	var lvl: int = { "shop": L('shop') / 5, "bar": L('barRoom'), "resto": L('resto'), "terrace": L('terrace') }.get(v.venue, 0)
	emote(v, 8 + 2 * lvl + (4 if (v.venue == 'terrace' and S.wx == 'sunny') else 0), null, LINES[v.venue], 0.4)
	seatTaken[v.venue][v.seat] = false
	var via := []
	if v.venue == 'terrace': via = [cw(1185, 1350)]
	elif v.venue == 'resto': via = [cw(1132, 1395)]
	elif v.venue == 'bar': via = [cw(1238, 1395)]
	via.append(NODES.LOBBY)
	v.seat = null; v.venue = null
	walk(v, via, func(_v): v.at = 'LOBBY'; nextStop(v))
## how many people turn up, and with which plans
func clubDemand() -> float:
	if not foodOpen(): return 0.0
	var h := hour()
	var meal := 1.6 if ((h >= 11 and h < 14) or (h >= 18 and h < 21)) else 0.6
	return (1.0 if clubOK() else 0.0) * parkAppeal() * (0.6 + 0.4 * seasonDemand()) * valueDemand(S.prices.menu) * arrivalBase() * 0.22 * meal * (((0.5 if venueOpen('bar') else 0.0)) if isDark() else 1.0)
func rangePlan() -> Array:
	var p := ['range']
	if not isDark() and not eventRunning() and courseOK() and randf() < 0.08: p.append('course')
	if clubOK() and randf() < (0.3 if foodOpen() else 0.1): p.append('club')
	return p
func coursePlan() -> Array:
	var p := ['course']
	if clubOK() and randf() < 0.15: p.push_front('club')
	if clubOK() and randf() < (0.45 if foodOpen() else 0.15): p.append('club')
	return p
func tickVisitors(dt: float) -> void:
	rangeAcc += rangeDemand() * dt
	while rangeAcc >= 1: rangeAcc -= 1; arriveVisitor(rangePlan())
	courseAcc += courseDemand() * dt
	while courseAcc >= 1: courseAcc -= 1; arriveVisitor(coursePlan())
	clubAcc += clubDemand() * dt
	while clubAcc >= 1: clubAcc -= 1; arriveVisitor(['club'])
	for v in visitors.duplicate():
		if v.upset: v.upset = max(0.0, v.upset - dt)
		match v.state:
			'drive':
				if v.car.state == 'parked':
					v.car.door = 0.7
					var net := carToNet(v.car.spot)
					v.x = net.pts[0].x; v.y = net.pts[0].y
					walk(v, net.pts.slice(1), func(_v): v.at = net.node; startStop(v))
					if v.standing == 'exemplary' and randf() < 0.35: emote(v, 0, 'happy', LINES.hello, 1)
			'walk':
				if follow(v, v.speed, dt):
					var f: Callable = v.then
					v.then = null; v.state = 'idle'
					f.call(v)
			'queue':
				v.wait += dt
				v.mood = max(0.0, moodOf(v) - dt * 0.2)
				if not v.grumbled and v.wait > v.patience * 0.6: v.grumbled = true; emote(v, -4, 'annoyed', LINES.slowLine, 0.45)
				if v.slot != null: moveTo(v, v.slot.x, v.slot.y, WALK * 0.7, dt)
				if v.wait > v.patience: giveUp(v)
			'filling':
				v.t += dt
				if v.t >= v.dur: inRangeOf(v, func(): bucketDone(v))
			'play':
				v.t += dt; v.acc += v.keep * dt / v.dur
				inRangeOf(v, func():
					while v.acc >= 1: v.acc -= 1; hitBall(v)
					if v.t >= v.dur: finishRange(v))
			'venue':
				v.t += dt
				if v.t >= v.dur: leaveVenue(v)
			'locker':
				v.t += dt
				if v.t >= v.dur: walk(v, [cw(1000, 1392), NODES.LOBBY], func(_v): v.at = 'LOBBY'; startStop(v))
			'desk':
				v.t += dt
				if v.t >= v.dur: finishCheckin(v)
			'amen':
				v.t += dt
				if v.amenType == 'shortc':
					var ao = objById(v.amen)
					if ao:
						var p := shortcPos(ao, v.amenSlot, min(1.0, v.t / v.dur))
						moveTo(v, p.x, p.y, 45, dt)
				if v.t >= v.dur: finishAmen(v)
	forRanges(func(_o):
		for k in bucketQueue.size(): bucketQueue[k].slot = bucketSlot(k)
		for k in rangeQueue.size(): rangeQueue[k].slot = baySlot(k)
		serveBuckets(); serveRange())
	serveTee(); serveLobby(); serveAmen(); serveDesk()
	conductTick(dt)
	visitors = visitors.filter(func(v): return v.state != 'gone')
	tickCars(dt)
func waitingAt(stop: String) -> int:
	if stop == 'range': return rangeSum().queue
	return (teeQueue if stop == 'course' else lobbyQueue).size()

# ---------- Conduct: golfer standing, misbehaviour, litter, damage and marshals ----------
const STANDING := {
	"exemplary": { "label": 'Exemplary', "icon": '★', "temper": 1.3, "spend": 1.15 },
	"normal":    { "label": 'Normal',    "icon": '',  "temper": 1.0, "spend": 1.0 },
	"bad":       { "label": 'Troublemaker', "icon": '⚠', "temper": 0.8, "spend": 1.0 },
}
func pickStanding() -> String:
	var r := randf()
	return 'bad' if r < 0.06 else ('exemplary' if r < 0.23 else 'normal')
func spendOf(v) -> float:
	if not v: return 1.0
	var s: float = STANDING[v.standing].spend if STANDING.has(v.get("standing", "")) else 1.0
	s *= GTYPES[v.type].spend if GTYPES.has(v.get("type", "")) else 1.0
	s *= BAND[v.band].spend if BAND.has(v.get("band", "")) else 1.0
	return s
var litter: Array = []
var marks: Array = []
var marshals: Array = []
var conductId := 1
var conductLog: Array = []
## how pleasant the park feels: litter and damage put people off
func parkAppeal() -> float: return max(0.65, 1 - 0.008 * litter.size() - 0.02 * marks.size()) * repMult() * decorAppeal()
const LITTER_KINDS := ['paper', 'can', 'bottle', 'cup']
func dropLitter(x: float, y: float) -> void:
	if litter.size() >= 80: return
	if nearObj('bin', x, y, 80) and randf() < 0.85: return   # into the bin
	litter.append({ "id": conductId, "x": x + rnd(-5, 5), "y": y + rnd(-3, 4), "kind": LITTER_KINDS[randi() % 4], "rot": randf() * 6, "by": null })
	conductId += 1
func addMark(type: String, x: float, y: float, extra := {}):
	if marks.size() >= 40: return null
	var m := { "id": conductId, "type": type, "x": x, "y": y, "by": null }
	conductId += 1
	m.merge(extra, true)
	marks.append(m)
	return m
func groupOf(v):
	for g in groups:
		if has_(g.players, v): return g
	return null
## a troublemaker acts up; what they damage depends on where they are
func misbehave(v) -> void:
	v.offenses = v.get("offenses", 0) + 1; v.flagged = true; v.flagT = 0.0
	var r := randf()
	if v.state == 'play':
		if r < 0.45:
			inRangeOf(v, func():
				if not brokenBays.has(v.bay): brokenBays[v.bay] = true; addMark('bay', bayX(v.bay), TEE_Y + 2, { "bay": v.bay, "rangeId": v.rangeId })
				else: dropLitter(v.x, v.y + 6))
		else: dropLitter(v.x, v.y + 6)
	elif v.state == 'golf':
		var g = groupOf(v)
		if not g or g.phase != 'play': dropLitter(v.x, v.y + 4); return
		var h: int = g.hole
		var b = ball(g, v)
		var lie: String = b.lie if b else 'rough'
		if r < 0.3: dropLitter(v.x, v.y + 4)
		elif lie == 'green' or lie == 'holed': addMark('green', v.x + rnd(-4, 4), v.y + rnd(-3, 3), { "hole": h }); wearHole(h, 5)
		else: addMark('tee' if lie == 'tee' else 'fairway', v.x + rnd(-4, 4), v.y + rnd(-3, 4), { "hole": h }); wearHole(h, 4)
	elif v.state == 'venue' and v.venue != 'shop' and r < 0.5:
		addMark('furniture', v.x + rnd(-4, 4), v.y + rnd(-3, 3), { "venue": v.venue })
	else: dropLitter(v.x, v.y + 5)
## escorted off the premises
func eject(v) -> void:
	if v.get("rangeId") and not curR: inRangeOf(v, func(): eject(v)); return
	if v.get("ejected") or v.state == 'gone' or v.state == 'drive': return
	leaveQueue(v)
	if v.state == 'play': del(rangeP, v)
	if v.get("bay") != null: bayTaken.erase(v.bay); v.bay = null
	if v.get("machine") != null: filling[v.machine] = null; v.machine = null
	if v.get("venue"): seatTaken[v.venue][v.seat] = false; v.venue = null; v.seat = null
	var g = groupOf(v)
	if g:
		del(g.players, v)
		if g.players.is_empty(): del(groups, g)
		if not v.get("at") or v.at == 'TEE1': v.at = 'NORTH'
	v.hasBucket = false; v.ejected = true; v.flagged = false
	emote(v, -30, 'angry', LINES.ejected, 0.7)
	away.append({ "t": simTime, "why": 'ejected' })
	S.ejected = S.get("ejected", 0) + 1
	goHome(v); v.speed = 85.0

# ---------- Marshals ----------
const MARSHAL_SEE := 320.0
func patrolPoint() -> Vector2:
	var r := randf()
	var open := []
	for i in 18:
		if holeOpen(i): open.append(i)
	var ro := rangeObjs()
	if r < 0.3 and ro.size():
		var o = ro[randi() % ro.size()]
		if o.get("r"): return withRange(o, func(): return Vector2(rnd(BAY0, rangeX1()), TEE_Y + rnd(30, 50)))
	if r < 0.5 or open.is_empty():
		var ps: Array = S.world.paths if S.get("world") else []
		if ps.size():
			var i: int = ps[randi() % ps.size()]
			return tileC(i % GW, i / GW)
		return NODES.ENT
	var h: int = open[randi() % open.size()]
	return hOff(h, rnd(0.1, greenT(h)), rnd(-20, 20))
func onCourseArea(p) -> bool:
	var t := tileOf(p.x, p.y)
	if t.tx < 0 or t.ty < 0 or t.tx >= GW or t.ty >= GH: return false
	return occ[tIdx(t.tx, t.ty)] == 0
func syncMarshals() -> void:
	var want: int = int(S.staff.get("marshal", 0))
	while marshals.size() < want:
		marshals.append({ "x": NODES.ENT.x + marshals.size() * 10, "y": NODES.ENT.y, "state": 'patrol', "target": patrolPoint(), "job": null, "t": 0.0, "ang": 0.0, "cart": false, "id": conductId })
		conductId += 1
	while marshals.size() > want:
		var m = marshals.pop_back()
		if m.job: m.job.ref.by = null
func jobPos(j) -> Vector2: return Vector2(j.v.x, j.v.y) if j.kind == 'person' else Vector2(j.ref.x, j.ref.y)
func findJob(m):
	var best = [null, MARSHAL_SEE]
	var consider := func(kind, ref, x, y, prio):
		if ref.get("by") and not is_same(ref.by, m): return
		var d: float = hyp(x - m.x, y - m.y) / prio
		if d < best[1]: best[1] = d; best[0] = { "kind": kind, "ref": ref, "v": ref if kind == 'person' else null }
	for v in visitors:
		if v.get("flagged") and not v.get("ejected") and v.state != 'drive' and v.state != 'gone': consider.call('person', v, v.x, v.y, 3.0)
	for k in marks: consider.call('mark', k, k.x, k.y, 1.6)
	for l in litter: consider.call('litter', l, l.x, l.y, 1.0)
	return best[0]
func moveMarshal(m, tx: float, ty: float, dt: float) -> bool:
	var far := hyp(tx - m.x, ty - m.y) > 260
	m.cart = far or (onCourseArea(Vector2(tx, ty)) and onCourseArea(m))
	return moveTo(m, tx, ty, 140.0 if m.cart else 52.0, dt)
func updateMarshal(m, dt: float) -> void:
	if strike: return
	if m.state == 'patrol':
		var j = findJob(m)
		if j: m.job = j; j.ref.by = m; m.state = 'job'; return
		if moveMarshal(m, m.target.x, m.target.y, dt):
			m.t += dt
			if m.t > 2.5: m.t = 0.0; m.target = patrolPoint()
	elif m.state == 'job':
		var j = m.job
		var gone: bool
		if j.kind == 'person': gone = j.v.get("ejected", false) or j.v.state == 'gone' or j.v.state == 'drive'
		elif j.kind == 'mark': gone = not has_(marks, j.ref)
		else: gone = not has_(litter, j.ref)
		if gone: j.ref.by = null; m.job = null; m.state = 'patrol'; m.target = patrolPoint(); return
		var p := jobPos(j)
		if moveMarshal(m, p.x + (9 if j.kind == 'person' else 0), p.y, dt) or hyp(p.x - m.x, p.y - m.y) < 12: m.state = 'work'; m.t = 0.0; m.cart = false
	elif m.state == 'work':
		var j = m.job
		m.t += dt
		var need: float = 1.6 if j.kind == 'person' else (1.1 if j.kind == 'litter' else (5.0 if j.ref.type == 'bay' else 3.5))
		if j.kind == 'person' and (j.v.get("ejected", false) or j.v.state == 'gone'): m.state = 'patrol'; m.job = null; return
		if j.kind == 'person': m.x = j.v.x + 9; m.y = j.v.y
		if m.t >= need:
			if j.kind == 'person': eject(j.v)
			elif j.kind == 'litter': del(litter, j.ref); S.cleaned = S.get("cleaned", 0) + 1
			else: repairMark(j.ref)
			j.ref.by = null; m.job = null; m.state = 'patrol'; m.target = patrolPoint(); m.t = 0.0
func repairMark(k) -> void:
	var i := idx(marks, k)
	if i < 0: return
	marks.remove_at(i)
	if k.type == 'bay':
		var ro = objById(k.get("rangeId"))
		if not ro and rangeObjs().size(): ro = rangeObjs()[0]
		if ro and ro.get("r"): withRange(ro, func(): brokenBays.erase(k.bay))
	if (k.type == 'green' or k.type == 'fairway' or k.type == 'tee') and k.has("hole"): wearHole(k.hole, -4)
	S.repaired = S.get("repaired", 0) + 1
var slowFixT := 0.0
func conductTick(dt: float) -> void:
	syncMarshals()
	for v in visitors:
		if v.get("ejected") or v.state == 'drive' or v.state == 'gone': continue
		if v.get("flagged"): v.flagT = v.get("flagT", 0.0) + dt
		var active: bool = v.state == 'play' or v.state == 'golf' or v.state == 'venue' or v.state == 'queue' or v.state == 'walk'
		if not active: continue
		if v.standing == 'bad' and randf() < dt / 24: misbehave(v)
		elif v.standing == 'normal' and v.state == 'walk' and randf() < dt / 900: dropLitter(v.x, v.y + 5)
		if v.state == 'walk' and v.standing != 'bad' and litter.size() and simTime - v.get("litterT", -99.0) > 25 and randf() < dt * 2:
			for l in litter:
				if abs(l.x - v.x) < 14 and abs(l.y - v.y) < 14: v.litterT = simTime; emote(v, -3, 'annoyed', LINES.litter, 0.5); break
		# exemplary golfers pick up litter they pass
		if v.standing == 'exemplary' and v.state == 'walk' and litter.size() and randf() < dt * 2:
			for i in litter.size():
				var l = litter[i]
				if not l.by and hyp(l.x - v.x, l.y - v.y) < 14: litter.remove_at(i); S.cleaned = S.get("cleaned", 0) + 1; break
		# queues near litter or damage wear people's patience down faster
		if v.state == 'queue' and (litter.size() or marks.size()):
			var near := false
			for l in litter:
				if abs(l.x - v.x) < 70 and abs(l.y - v.y) < 70: near = true; break
			if not near:
				for k in marks:
					if abs(k.x - v.x) < 70 and abs(k.y - v.y) < 70: near = true; break
			if near: v.wait += dt * 0.35
	for m in marshals: updateMarshal(m, dt)
	# without marshals, other staff still fix things, slowly
	slowFixT += dt
	if slowFixT > 1:
		slowFixT = 0
		for k in marks.duplicate():
			if k.by: continue
			var crew: int = N('attend') if k.type == 'bay' else ((N('bar') + N('chef')) if k.type == 'furniture' else N('keeper'))
			if crew and randf() < 0.025 * crew: repairMark(k); break

# ---------- Moods: how golfers feel, little reactions above their heads, and the club's reputation ----------
func moodOf(v) -> float: return v.get("mood", 65.0)
func moodKind(m: float) -> String: return 'delighted' if m >= 82 else ('happy' if m >= 62 else ('meh' if m >= 42 else ('annoyed' if m >= 25 else 'angry')))
const MOOD_LABEL := { "delighted": 'Delighted', "happy": 'Happy', "meh": 'So-so', "annoyed": 'Annoyed', "angry": 'Angry' }
const MOOD_COLOR := { "delighted": '#ff6f91', "happy": '#6fcf5f', "meh": '#f2c14e', "annoyed": '#ff9f43', "angry": '#e8432e' }
const LINES := {
	"rangeGood": ['Great session!', 'Pured that 7-iron.', 'Finally fixed my slice!', 'Lovely range.', 'Same time tomorrow?'],
	"rangeMeh": ['Not my day.', 'Shanked half the bucket.', 'Bit pricey for that.'],
	"roundGreat": ['Career round!', 'Birdie fest!', 'What a course!', 'Under par!'],
	"roundGood": ['Good round.', 'Lovely track.', 'Greens were perfect.', 'That par 5 is a beauty.'],
	"roundBad": ['Too many bunkers…', 'Lost three balls.', 'Never again, that 17th.', 'Greens were rough.'],
	"resto": ['Best club sandwich!', 'Compliments to the chef.', 'Lovely lunch.'],
	"bar": ['Cheers!', 'One more?', 'Great pint.'],
	"terrace": ['What a view!', 'Perfect weather for this.', 'Sun’s out!'],
	"shop": ['New glove!', 'Picked up some tees.', 'Nice gear.'],
	"slowLine": ['Come on…', 'This line is slow.', 'Any day now…'],
	"finally": ['Finally!', 'About time.'],
	"giveUp": ['Forget it, I’m out.', 'Not waiting any longer.', 'I’ll go elsewhere.'],
	"ejected": ['Fine, I’m leaving!', 'This club is no fun.', 'Whatever.'],
	"litter": ['Who dropped this?', 'Messy…', 'Bit untidy here.'],
	"hello": ['Lovely day for golf!', 'Morning!', 'Can’t wait to play.'],
	"value": ['Great value here.', 'Cheap as chips!', 'Bargain.'],
	"pricey": ['Bit steep, this.', 'How much?!', 'Pricey place.'],
	"ace": ['ACE!!!', 'HOLE-IN-ONE!', 'Did you SEE that?!'],
}
func pickLine(a: Array) -> String: return a[randi() % a.size()]
func anchor(v) -> Vector2: return Vector2(v.x, v.y - (4 if v.state == 'golf' else 0))
## someone reacts: the view shows a bubble (and maybe a spoken line) if they're on screen
signal emoted(v, kind, said, chance)
## change someone's mood, and show it if they're on screen
func emote(v, delta: float, kind, lines, chance := 0.35) -> void:
	v.mood = clampf(moodOf(v) + delta, 0, 100)
	var k: String = kind if kind else moodKind(v.mood)
	if k == 'delighted' or k == 'annoyed': v.fx = { "kind": 'cheer' if k == 'delighted' else 'slump', "t0": simTime }
	var said = pickLine(lines) if lines else null
	if said: v.thought = { "text": said, "t": simTime }
	emoted.emit(v, k, said, chance)
## when someone leaves, how they felt feeds the club's reputation
func recordMood(v) -> void:
	if v.get("recorded"): return
	v.recorded = true
	if v.get("celeb"): celebLeaves(v)
	if v.get("ejected"): return   # nobody misses a troublemaker
	S.rep = S.get("rep", 70.0) * 0.985 + moodOf(v) * 0.015
func repMult() -> float: return clampf(0.85 + 0.3 * (S.get("rep", 70.0) - 40) / 60.0, 0.85, 1.15)
func avgMood():
	var n := 0
	var s := 0.0
	for v in visitors:
		if v.state != 'drive' and v.state != 'gone': s += moodOf(v); n += 1
	return s / n if n else null

# =====================================================================================
# A living course: turf on every hole wears, dries and recovers; greenkeepers tend the worst holes
# =====================================================================================
func turfOf(i: int) -> float: return S.turf[i] if (S.get("turf") and i < S.turf.size()) else 100.0
func wearHole(i: int, a: float) -> void:
	if not S.get("turf"):
		S.turf = []; S.turf.resize(18); S.turf.fill(100.0)
	if i >= 0 and i < 18: S.turf[i] = max(0.0, S.turf[i] - a)
func builtIdx() -> Array:
	var out := []
	for i in 18:
		if S.get("design") and S.design.holes[i].built: out.append(i)
	return out
var keepers: Array = []
func syncKeepers() -> void:
	var want := N('keeper')
	var home: Vector2 = tileC(doorOf(objOf('shed')).tx, doorOf(objOf('shed')).ty) if hasObj('shed') else NODES.ENT
	while keepers.size() < want: keepers.append({ "x": home.x, "y": home.y, "hole": -1, "state": 'idle', "ang": 0.0, "t": 0.0, "id": keepers.size() })
	while keepers.size() > want: keepers.pop_back()
func turfTick(dt: float, onHole: Dictionary) -> void:
	if not S.get("turf"):
		S.turf = []; S.turf.resize(18); S.turf.fill(100.0)
	var sea := season()
	var hot: bool = sea == 'summer' and S.wx == 'sunny'
	var irr := L('irrig')
	var built := builtIdx()
	for i in built:
		var d := 0.006
		if S.wx == 'rain': d += 0.03 * pow(0.85, irr)
		if hot: d += 0.025 * pow(0.75, irr)
		if sea == 'winter': d *= 0.5
		d += 0.012 * onHole.get(i, 0)
		d *= modMult('wear')
		var grow := (0.008 if sea == 'spring' else (0.001 if sea == 'winter' else 0.004)) * (3.0 if facShut('course') else 1.0)
		S.turf[i] = clampf(S.turf[i] - d * dt + grow * dt, 0, 100)
	# greenkeepers drive to the most worn hole and mow and repair it
	syncKeepers()
	for kp in keepers:
		if strike: break
		if kp.state == 'idle':
			var taken := {}
			for o in keepers:
				if not is_same(o, kp) and o.hole >= 0: taken[o.hole] = true
			var best := -1
			var bv := 97.0
			for i in built:
				if not taken.has(i) and S.turf[i] < bv: bv = S.turf[i]; best = i
			if best < 0: kp.t += dt; continue
			kp.hole = best; kp.state = 'go'
		if kp.state == 'go':
			var p := hPt(kp.hole, 0.12)
			if moveTo(kp, p.x, p.y, 110, dt): kp.state = 'mow'; kp.t = 0.0
		elif kp.state == 'mow':
			kp.t += dt
			var k := 0.5 - 0.5 * cos(kp.t * 0.22)
			var p := hPt(kp.hole, 0.12 + 0.86 * k)
			moveTo(kp, p.x, p.y, 70, dt)
			S.turf[kp.hole] = min(100.0, S.turf[kp.hole] + 1.4 * dt * (1 + 0.15 * L('green')) * (1.0 if hasObj('shed') else 0.6) * (1.0 if (S.get("sup") and S.sup.fert > 0) else 0.4))
			if S.get("sup"): S.sup.fert = max(0.0, S.sup.fert - 0.012 * dt)
			if S.turf[kp.hole] >= 99.5: kp.state = 'idle'; kp.hole = -1
	var tot := 0.0
	for i in built: tot += S.turf[i]
	S.cond = tot / built.size() if built.size() else 100.0

# =====================================================================================
# Golfer types and memberships
# =====================================================================================
const GTYPES := {
	"beginner": { "label": 'Beginner', "skill": [0.32, 0.5], "w": 0.28, "e": 1.0, "spend": 0.9, "tag": 'B' },
	"regular":  { "label": 'Regular', "skill": [0.14, 0.34], "w": 0.47, "e": 1.4, "spend": 1.0, "tag": '' },
	"expert":   { "label": 'Low handicapper', "skill": [0.0, 0.14], "w": 0.13, "e": 0.6, "spend": 1.3, "tag": 'LH' },
	"member":   { "label": 'Member', "skill": [0.08, 0.36], "w": 0.0, "e": 0.0, "spend": 1.1, "tag": 'M' },
}
func courseAvgRating() -> float:
	var b := builtIdx().filter(func(i): return i < (18 if L('back9') else 9))
	if b.is_empty(): return 0.0
	var s := 0.0
	for i in b: s += holeRating(i)
	return s / b.size()
## who turns up depends on the course and your prices
func pickType(plan: Array) -> String:
	var course := plan.has('course')
	var r := ratioOf('fee9') if course else ratioOf('bucket')
	var avg := courseAvgRating()
	var fit := { "beginner": max(0.4, 1.4 - avg / 12) * (1.6 if plan[0] == 'range' else 1.0), "regular": 1.0, "expert": (0.5 + avg / 8) if course else 0.4 }
	var w := []
	var tot := 0.0
	for k in ['beginner', 'regular', 'expert']:
		var x: float = GTYPES[k].w * fit[k] * valueDemand(1 + (r - 1) * GTYPES[k].e)
		w.append([k, x]); tot += x
	var x := randf() * tot
	for e in w:
		x -= e[1]
		if x <= 0: return e[0]
	return 'regular'
## members pay monthly, play for free and come back often
var memberAcc := 0.0
func memberCap() -> int: return 14 * slots()
func memberDemand() -> float:
	if isDark() or isFrost() or eventRunning() or not courseOK() or not facOpen('course'): return 0.0
	return S.get("members", 0) / DAY_LEN * (0.5 + 0.5 * seasonDemand()) * (0.4 if S.wx == 'rain' else 1.0)
func membersTick(dt: float) -> void:
	if S.get("members", 0) > 0: earn(S.members * S.prices.member / (MONTH_DAYS * DAY_LEN) * dt, 'members')
	memberAcc += memberDemand() * dt
	while memberAcc >= 1: memberAcc -= 1; arriveVisitor(coursePlan(), 'member')
## returns [joined, left]
func membersMonth() -> Array:
	if not courseOK(): S.memberLog = { "join": 0, "leave": 0 }; return [0, 0]
	var r := ratioOf('member')
	var rep: float = S.get("rep", 70.0)
	var rating := rating18() if L('back9') else rating9()
	var seasonF := 1.3 if (season() == 'spring' or season() == 'summer') else 0.6
	var condF := clampf((S.cond - 50) / 35.0, 0, 1.2)
	var repF := 0.6 + 0.6 * rep / 100.0
	var smodM: float = S.smod.get("members", 1.0) if S.get("smod") else 1.0
	var pot: float = smodM * [0.0, 0.5, 1.2, 2.5, 4.0, 6.0][clampi(stars(), 0, 5)] * condF * repF * (1 + rating / 400.0) * valueDemand(1 + (r - 1) * 1.2) * seasonF
	var join: int = clampi(int(floor(pot + randf())), 0, max(0, memberCap() - S.get("members", 0)))
	var mm: float = S.get("memberMood", 70.0)
	var churn: float = min(0.5, 0.08 + max(0.0, (60 - mm) / 120.0) + max(0.0, r - 1) * 0.25 + max(0.0, (60 - S.cond) / 200.0))
	var leave := 0
	for k in S.get("members", 0):
		if randf() < churn: leave += 1
	S.members = max(0, S.get("members", 0) + join - leave)
	S.memberLog = { "join": join, "leave": leave }
	return [join, leave]
## what each kind of golfer thinks of a round on your course
func typeRoundMood(v, g) -> Dictionary:
	var d := 0.0
	var lines = null
	var haz := 0.0
	for i in g.holes:
		var p = G.info[i].parts
		haz += p.water + p.bunkers
	haz /= g.holes
	var turf := 0.0
	for i in g.holes: turf += turfOf(i)
	turf = turf / g.holes if g.holes else 100.0
	var hm := hcpRoundMood(v)
	d += hm.d
	if hm.lines: lines = hm.lines
	var tm2 := teeMood(v)
	d += tm2.d
	if tm2.lines: lines = tm2.lines
	if turf < 65 and v.get("hcp", 18) < 15: d -= 6; lines = ['The greens are a mess.', 'Shocking conditions.']
	if haz > 3 and v.get("hcp", 18) > 36: d -= 4; lines = ['Way too hard…', 'Lost all my balls.']
	return { "d": d, "lines": lines, "turf": turf }

# =====================================================================================
# Star rating, a rival club, events, and goals for each scenario
# =====================================================================================
func starPoints() -> Dictionary:
	var decor := 0.0
	for o in objs(): decor += OBJ[o.type].get("decor", 0.0)
	var flags := [L('barRoom') > 0, L('resto') > 0, L('terrace') > 0, L('locker') > 0, hasObj('range') and bays() >= 15, L('carts') > 0, hasObj('hut'), hasObj('putt'), hasObj('short'), hasObj('academy'), hasObj('shortc'), teeSets().size() >= 3, decor >= 15]
	var facilities := 0
	for f in flags:
		if f: facilities += 1
	var rep: float = S.get("rep", 70.0)
	var parts := {
		'Course design': min(30.0, courseAvgRating() * 4),
		'Turf': clampf((S.cond - 50) * 0.4, 0, 20) if courseHoles() > 0 else 0.0,
		'18 holes': 10.0 if L('back9') else 0.0,
		'Facilities': min(30.0, facilities * 3.0),
		'Reputation': clampf((rep - 40) * 0.3, 0, 18),
	}
	var total := 0.0
	for v in parts.values(): total += v
	return { "parts": parts, "total": total }
const STAR_STEPS := [0, 18, 36, 54, 72]
func starsOf(pts: float) -> int:
	var n := 0
	for s in STAR_STEPS:
		if pts >= s: n += 1
	return max(1, n)
func stars() -> int: return starsOf(starPoints().total)
func starText(n: int) -> String: return '★'.repeat(n) + '☆'.repeat(5 - n)
var lastStars := 0
func checkStars() -> void:
	var n := stars()
	if lastStars and n != lastStars: toast('Golf Monthly', "%s is now a %d-star club" % [clubName(), n], 'The reviewers loved what you have done with the place.' if n > lastStars else 'The reviewers were less impressed this time.', '★')
	lastStars = n

# ---- the rival down the road
func ensureRival() -> void:
	if not S.get("rival"): S.rival = { "name": 'Oakridge Golf Club', "stars": 2.2, "fee9": 48.0, "holes": 9, "news": '' }
## golfers weigh your stars and price against Oakridge's
func rivalShare() -> float:
	ensureRival()
	var q = starsC / max(1.0, S.rival.stars)
	var p := pow(S.rival.fee9 / max(1.0, S.prices.fee9), 0.6)
	return clampf(0.75 + 0.25 * q * p, 0.7, 1.25)
func rivalMonth() -> void:
	ensureRival()
	var R: Dictionary = S.rival
	R.stars = min(4.6, R.stars + rnd(0, 0.12))
	if R.holes == 9 and yearOf() >= 2 and randf() < 0.15:
		R.holes = 18; R.news = "%s opened a back nine." % R.name
		toast('Rival news', R.news, 'Expect them to win over some of your golfers.', '!'); return
	var fair: float = 30 + R.stars * 12
	if S.prices.fee9 < R.fee9 * 0.85 and randf() < 0.6:
		R.fee9 = round(R.fee9 * 0.92); R.news = "%s cut its green fee to %s to compete with you." % [R.name, fmt(R.fee9)]
		toast('Rival news', "%s cut its prices" % R.name, "Nine holes there now cost %s." % fmt(R.fee9), '!')
	else: R.fee9 = round(R.fee9 + (fair - R.fee9) * 0.3)

# ---- events you can book for early next month
var EVENTS := {}
func _build_events() -> void:
	EVENTS = {
		"corporate": { "label": 'Corporate golf day', "players": 16, "holes": 9, "repK": 0.6, "blurb": 'A local firm takes over the course for a day of golf and lunch.',
			"needs": func(): return [['Restaurant open', venueOpen('resto')], ['2 stars or more', stars() >= 2]], "pay": func(): return fairFee9() * 16 * 2.2 + 1500 },
		"proam": { "label": 'Charity Pro-Am', "players": 28, "holes": 18, "repK": 1.0, "blurb": 'Pros and amateurs play for a good cause, with a crowd watching.',
			"needs": func(): return [['18 holes', L('back9') > 0], ['3 stars or more', stars() >= 3], ['Turf 75% or better', S.cond >= 75]], "pay": func(): return fairFee9() * 28 * 2.5 + 4000 },
		"county": { "label": 'County Championship', "players": 36, "holes": 18, "repK": 1.5, "trophy": true, "blurb": 'The best amateurs in the county. Win their respect and a trophy.',
			"needs": func(): return [['18 holes', L('back9') > 0], ['4 stars or more', stars() >= 4], ['Par 70 or more', totalPar() >= 70], ['Turf 85% or better', S.cond >= 85]], "pay": func(): return fairFee9() * 36 * 3 + 10000 },
	}
func totalPar() -> int:
	var p := 0
	for h in S.holes: p += h.par
	return p
func eventRunning() -> bool: return S.get("event") != null and S.event.state == 'running'
func nextMonthStart() -> int:
	var d: int = S.day + 1
	while (d - 1) % MONTH_DAYS: d += 1
	return d
func eventNeedsMet(k: String) -> bool:
	for n in EVENTS[k].needs.call():
		if not n[1]: return false
	return true
func bookEvent(k: String) -> void:
	if S.get("event") or not eventNeedsMet(k): return
	S.event = { "key": k, "day": nextMonthStart(), "state": 'booked', "moods": [], "left": EVENTS[k].players, "acc": 0.0 }
	toast('Events', "%s booked" % EVENTS[k].label, "%s. The course closes to the public until it is over." % dateLabel(S.event.day), '⛳')
	sfx('chime'); ui_refresh.emit(); save()
func startEvent() -> void:
	var E = EVENTS[S.event.key]
	var missing := []
	for n in E.needs.call():
		if not n[1]: missing.append(n[0].to_lower())
	if missing.size():
		toast('Events', "%s cancelled" % E.label, "The organisers pulled out: %s." % ", ".join(missing), '!')
		S.rep = max(0.0, S.get("rep", 70.0) - 5); S.event = null; return
	S.event.state = 'running'
	toast('Events', "Today: %s" % E.label, 'The course is closed to the public until the last group is in. Players arrive from 7:00.', '⛳')
func eventTick(dt: float) -> void:
	var ev = S.get("event")
	if not ev or ev.state != 'running': return
	if ev.left <= 0:
		var still := false
		for v in visitors:
			if v.get("eventPlayer") and not v.get("evDone") and v.state != 'gone': still = true; break
		if not still: resolveEvent(); return
	if ev.left <= 0 or S.day != ev.day or hour() < 7 or hour() > 12: return
	ev.acc += EVENTS[ev.key].players / (4 * DAY_LEN / 24.0) * dt
	while ev.acc >= 1 and ev.left > 0:
		var before := visitors.size()
		arriveVisitor(['course', 'club'], 'expert')
		if visitors.size() == before: break
		var v = visitors[visitors.size() - 1]
		v.eventPlayer = true; v.holes = EVENTS[ev.key].holes if L('back9') else min(9, courseHoles()); v.temper *= 3
		ev.acc -= 1; ev.left -= 1
signal cup_result(info)
func resolveEvent() -> void:
	var ev = S.event
	var E = EVENTS[ev.key]
	var n: int = ev.moods.size()
	var avg := 35.0
	if n:
		avg = 0.0
		for m in ev.moods: avg += m
		avg /= n
	var done: float = min(1.0, float(n) / E.players)
	var score := roundi(avg * (0.4 + 0.6 * done))
	var pay := roundf(E.pay.call() * clampf(score / 70.0, 0.4, 1.3))
	earn(pay, 'events')
	S.rep = clampf(S.get("rep", 70.0) + (score - 60) / 3.0 * E.repK, 0, 100)
	var won: bool = E.get("trophy", false) and score >= 60
	if won: S.trophies += 1
	if not S.get("eventsDone"): S.eventsDone = {}
	if score >= 50: S.eventsDone[ev.key] = S.eventsDone.get(ev.key, 0) + 1
	var msg := "%d of %d players finished. %s" % [n, E.players, 'The organisers were delighted and want to come back.' if score >= 70 else ('A decent day, with a few complaints.' if score >= 50 else 'It did not go well: slow play, unhappy players, or both.')]
	if won: msg += " You won a trophy: every bucket, fee and sale now earns +%d%%." % (S.trophies * 15)
	cup_result.emit({ "eyebrow": E.label, "winner": "Event score %d/100" % score, "won": "+%s" % fmt(pay), "msg": msg })
	steamCall('timeline', 'championship', E.label)
	S.event = null
	sfx('fanfare')

# ---- scenarios and their goals
func staffTotal() -> int:
	var n := 0
	for x in STAFF:
		if not RANGE_STAFF.has(x.id): n += int(S.staff.get(x.id, 0))
	return n + rangeStaffTotal()
func monthProfit() -> float:
	var led = S.get("ledger") if S.get("ledger") else {}
	var best := sumOf(led.get("month", {}))
	for m in led.get("months", []):
		var s := 0.0
		for k in m:
			if INCOME_CATS.has(k) or COST_CATS.has(k): s += m[k]
		best = max(best, s)
	return best
var GOALS := {}
func _build_goals() -> void:
	GOALS = {
		"fresh": [
			['A good month', 'Make $3,000 profit in one month.', func(): return monthProfit() >= 3000, 1000],
			['Hire a team', 'Employ 5 staff.', func(): return staffTotal() >= 5, 1500],
			['First members', 'Have 10 members.', func(): return S.get("members", 0) >= 10, 2000],
			['Three stars', 'Reach a 3-star rating.', func(): return stars() >= 3, 5000],
			['Eighteen holes', 'Build all 18 holes in the course designer.', func(): return L('back9') > 0, 10000],
			['Corporate client', 'Host a successful corporate golf day.', func(): return S.get("eventsDone", {}).get("corporate", 0) >= 1, 5000],
			['Four stars', 'Reach a 4-star rating.', func(): return stars() >= 4, 20000],
			['County Championship', 'Host a successful County Championship.', func(): return S.get("eventsDone", {}).get("county", 0) >= 1, 50000],
			['Five stars', 'Reach a 5-star rating.', func(): return stars() >= 5, 100000],
		],
		"rescue": [
			['Fix the course', 'Get the turf above 80% on average.', func(): return S.cond >= 80, 1500],
			['Restore the name', 'Reach a reputation of 60.', func(): return S.get("rep", 0) >= 60, 3000],
			['Three stars', 'Reach a 3-star rating.', func(): return stars() >= 3, 5000],
			['Clear the debt', 'Pay off the loan.', func(): return not (S.get("loan", 0) > 0), 5000],
		],
		"sandbox": [],
	}
func goalList() -> Array: return GOALS.get(S.get("scenario", 'fresh'), [])
func checkGoals() -> void:
	var list := goalList()
	var i: int = S.get("goalIdx", 0)
	if i >= list.size() or S.get("goalFailed"): return
	var g: Array = list[i]
	if not g[2].call(): return
	S.goalIdx = i + 1
	earn(g[3], 'other')
	toast('Goal complete', g[0], "Reward: %s.%s" % [fmt(g[3]), ' Every goal done. Well played!' if S.goalIdx >= list.size() else ''], '✓')
	sfx('fanfare'); ui_refresh.emit(); save()
var goalT := 0.0
var starsC := 1
func starAppeal() -> float: return 0.9 + 0.05 * starsC
func goalsTick(dt: float) -> void:
	eventTick(dt)
	goalT += dt
	if goalT < 2: return
	goalT = 0
	starsC = stars(); checkStars(); checkGoals(); checkCampaign(); ui_refresh.emit()

# =====================================================================================
# The course designer: edit a draft copy of the course, then pay for the changes in one go
# =====================================================================================
var dPlaceTee = null
var dRot := 0.3
var selFeat = null
var designing := false
var draft = null
var draftGeo = null
var dTool := 'hole'
var selParcel = null
var draftClear := {}
var speedBefore := 1
var dMsg := ''
var selHole := 0
signal design_changed
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
func dd(a, b) -> float: return hyp(a.x - b.x, a.y - b.y)
func holeValid(design, geo, i: int) -> Dictionary:
	var h = design.holes[i]
	if not h.built: return { "ok": true }
	for k in ['tee', 'bend', 'green']:
		if not (ownsAt(design, h[k].x, h[k].y) and not noBuild(h[k].x, h[k].y, k == 'bend')):
			return { "ok": false, "why": ("The %s can't go on a building, car park or water." % k) if ownsAt(design, h[k].x, h[k].y) else ("The %s is on land you don't own." % k) }
	var y: int = geo.info[i].yards
	if y < MIN_YD: return { "ok": false, "why": "Too short (%d yd). Holes need at least %d yd." % [y, MIN_YD] }
	if y > MAX_YD: return { "ok": false, "why": "Too long (%d yd). Holes can be at most %d yd." % [y, MAX_YD] }
	return { "ok": true }
## trees that a design clears: inside a built hole's corridor or under a feature
func clearsTree(geo, x: float, y: float) -> bool:
	if geo == null: return false
	for i in 18:
		if not geo.corr[i].built: continue
		var c = geo.corr[i]
		if x < min(c.a.x, c.b.x, c.c.x) - 70 or x > max(c.a.x, c.b.x, c.c.x) + 70 or y < min(c.a.y, c.b.y, c.c.y) - 70 or y > max(c.a.y, c.b.y, c.c.y) + 70: continue
		for q in geo.hs[i]:
			if abs(q.x - x) < 62 and hyp(q.x - x, q.y - y) < 62: return true
	for f in geo.feats:
		if f.type == 'trees' or f.type == 'flowers': continue
		var F = FEATS[f.type]
		if inEllipse(x, y, f.x, f.y, F.rx + 12, F.ry + 12, f.get("rot", 0.0)): return true
	return false
func draftCost() -> Dictionary:
	var total := 0.0
	var valid := true
	var why := ''
	var lines := []
	for i in 18:
		var d = draft.holes[i]
		var c = S.design.holes[i]
		var v := holeValid(draft, draftGeo, i)
		if not v.ok:
			valid = false
			if why == '': why = "Hole %d: %s" % [i + 1, v.why]
		if d.built and not c.built:
			var x: float = 1500 + 4 * draftGeo.info[i].yards
			for k in S.design.get("teeSets", []): x += TEE[k].perHole
			total += x; lines.append(["Build hole %d" % (i + 1), x])
		elif d.built and c.built:
			var m := dd(d.tee, c.tee) + dd(d.green, c.green) + 0.5 * dd(d.bend, c.bend)
			if m > 2:
				var x := roundf(200 + 3 * m)
				total += x; lines.append(["Reshape hole %d" % (i + 1), x])
	var cur := {}
	for f in S.design.feats: cur[f.id] = true
	var nxt := {}
	for f in draft.feats: nxt[f.id] = true
	var added := {}
	for f in draft.feats:
		if not cur.has(f.id): added[f.type] = added.get(f.type, 0) + 1
	for k in added:
		var x: float = FEATS[k].cost * added[k]
		total += x; lines.append(["%d × %s" % [added[k], FEATS[k].label.to_lower()], x])
	var removed := 0
	for f in S.design.feats:
		if not nxt.has(f.id): removed += 1
	if removed: total += 60 * removed; lines.append(["Remove %d feature%s" % [removed, 's' if removed > 1 else ''], 60.0 * removed])
	if draftClear.size(): total += 15 * draftClear.size(); lines.append(["Clear %d tree%s" % [draftClear.size(), 's' if draftClear.size() > 1 else ''], 15.0 * draftClear.size()])
	return { "total": total, "lines": lines, "valid": valid, "why": why }
func rebuildDraft() -> void:
	draftGeo = buildGeo(draft)
	draftClear = {}
	for k in trees.size():
		if clearsTree(draftGeo, trees[k].x, trees[k].y): draftClear[k] = true
	design_changed.emit()
func enterDesign() -> void:
	draft = JSON.parse_string(JSON.stringify(S.design)); _normDesign(draft)
	draftGeo = buildGeo(draft); designing = true; dTool = 'hole'; selParcel = null; dMsg = ''
	speedBefore = speedIdx; setSpeed(0)
	rebuildDraft()
	sfx('open')
func exitDesign() -> void:
	designing = false; draft = null; draftGeo = null; draftClear = {}; selParcel = null
	setSpeed(speedBefore if speedBefore else 1)
	design_changed.emit()
func commitDesign() -> void:
	var c := draftCost()
	if not c.valid or S.money < c.total: return
	if c.total > 0: spend(c.total, 'build'); S.invested = S.get("invested", 0.0) + c.total
	var changed := []
	for i in 18:
		var a = draft.holes[i]
		var b = S.design.holes[i]
		if a.built != b.built or dd(a.tee, b.tee) + dd(a.green, b.green) + dd(a.bend, b.bend) > 0: changed.append(i)
	S.design = draft; S.design.land = S.world.land; applyDesign(); rebuildWorld(); layout()
	# groups on a reshaped hole start it again from the new tee
	for g in groups:
		g.pars = S.holes.slice(0, g.holes).map(func(h): return h.par)
		if changed.has(g.hole):
			g.phase = 'toTee'; g.shot = null
			var tp := teePos(g.hole)
			for k in g.players.size(): g.players[k].target = Vector2(tp.x - 8 + k * 6, tp.y + 10)
	sfx('chime')
	toast('Course designer', ("Construction done: %s" % fmt(c.total)) if c.total else 'Design saved', "Course rating %d. %s" % [rating18() if L('back9') else rating9(), '18-hole rounds are open.' if L('back9') else ''], '⛳')
	exitDesign(); save()
	for need in needsPath():
		if need.get("tee"): path_offer_needed.emit(need); break
signal path_offer_needed(need)
func buyParcel(id: int) -> void:
	var price := parcelPrice()
	if not buyPlot(id): return
	if draft: draft.land = S.world.land.duplicate()
	dMsg = "Bought the land for %s." % fmt(price)
	if draft: rebuildDraft()
	save()
func holeAt(wx: float, wy: float, camS := 1.0) -> int:
	var r: float = max(22.0, 30.0 / camS)
	for i in 18:
		if not G.corr[i] or not G.corr[i].placed: continue
		var sp := signPos(i)
		var gp := hPt(i, greenT(i))
		if hyp(sp.x - wx, sp.y - wy) < r or hyp(gp.x - wx, gp.y - wy) < r: return i
	return -1
## a tap on the map while designing
func designTap(x: float, y: float, camS := 1.0) -> void:
	dMsg = ''
	if dTool == 'place':
		if not validSpot(draft, x, y):
			dMsg = "You can't build on buildings, car parks or water." if ownsAt(draft, x, y) else "You don't own this land. Buy it with the Buy land tool."
			sfx('soft'); design_changed.emit(); return
		var p := { "x": roundi(x), "y": roundi(y) }
		if dPlaceTee == null: dPlaceTee = p; sfx('tap'); design_changed.emit(); return
		var h = draft.holes[selHole]
		h.tee = dPlaceTee; h.green = p; h.bend = { "x": roundi((dPlaceTee.x + p.x) / 2.0), "y": roundi((dPlaceTee.y + p.y) / 2.0) }; h.built = true; h.placed = true
		dPlaceTee = null; dTool = 'hole'; sfx('chime'); rebuildDraft(); return
	if dTool == 'adjust':
		var f = withGeo(draftGeo, func(): return featAt(x, y))
		if not f:
			for o in draft.feats:
				if dd(o, Vector2(x, y)) < 18: f = o; break
		selFeat = f.id if f else null
		if f: dRot = f.get("rot", 0.0)
		sfx('select' if f else 'tap'); design_changed.emit(); return
	if dTool == 'hole':
		var hi: int = withGeo(draftGeo, func(): return holeAt(x, y, camS))
		if hi >= 0: selHole = hi; sfx('select'); design_changed.emit()
		return
	if dTool == 'land':
		var p = parcelAt(x, y)
		selParcel = p.id if p else null; sfx('tap'); design_changed.emit(); return
	if dTool == 'remove':
		var f = withGeo(draftGeo, func(): return featAt(x, y))
		if not f:
			for o in draft.feats:
				if dd(o, Vector2(x, y)) < 16: f = o; break
		if f: del(draft.feats, f); sfx('soft'); rebuildDraft()
		return
	if not FEATS.has(dTool): return
	var F = FEATS[dTool]
	var rot: float = 0.0 if (dTool == 'trees' or dTool == 'flowers') else round(dRot * 100) / 100.0
	for uw in [[0, 0], [F.rx * 0.8, 0], [-F.rx * 0.8, 0], [0, F.ry * 0.8], [0, -F.ry * 0.8]]:
		var px: float = x + uw[0] * cos(rot) - uw[1] * sin(rot)
		var py: float = y + uw[0] * sin(rot) + uw[1] * cos(rot)
		if not validSpot(draft, px, py):
			dMsg = "You can't build on buildings, car parks or water." if ownsAt(draft, px, py) else "You don't own this land. Buy it with the Buy land tool."
			sfx('soft'); design_changed.emit(); return
	draft.feats.append({ "id": featId, "type": dTool, "x": roundi(x), "y": roundi(y), "rot": rot })
	featId += 1
	sfx('tap'); rebuildDraft()
func rotateDesign(dir: int) -> void:
	dRot = round((dRot + dir * PI / 12) * 100) / 100.0
	var f = null
	if dTool == 'adjust' and selFeat != null:
		for o in draft.feats:
			if o.id == selFeat: f = o; break
	if f and f.type != 'trees' and f.type != 'flowers': f.rot = dRot; rebuildDraft()
	else: design_changed.emit()
	sfx('tap')
## dragging a hole's handles (world coordinates)
func dragHandle(which: String, wx: float, wy: float) -> void:
	if which == 'feat':
		for f in draft.feats:
			if f.id == selFeat:
				if not validSpot(draft, wx, wy): return
				f.x = roundi(wx); f.y = roundi(wy); rebuildDraft(); return
		return
	draft.holes[selHole][which] = { "x": roundi(clampf(wx, 10, W - 10)), "y": roundi(clampf(wy, 10, LAND_Y1 - 10)) }
	rebuildDraft()
## JSON brings numbers back as floats; ids and grid indices must be whole numbers again
func _normDesign(d) -> void:
	if d == null: return
	for h in d.get("holes", []):
		for k in ['tee', 'bend', 'green']:
			if h.has(k): h[k] = { "x": float(h[k].x), "y": float(h[k].y) }
	for f in d.get("feats", []): f.id = int(f.id)
	if d.has("land"): d.land = d.land.map(func(x): return int(x))

# ---------- Speed ----------
const SPEEDS := [0, 1, 2, 4]
var speedIdx := 1
var lastSpeed := 1
var warp := 1
signal speed_changed
func setSpeed(i: int) -> void:
	i = clampi(i, 0, SPEEDS.size() - 1)
	if i > 0: lastSpeed = i
	speedIdx = i; warp = SPEEDS[i]
	speed_changed.emit()
func togglePause() -> void: setSpeed(lastSpeed if speedIdx == 0 else 0)

# =====================================================================================
# Opening hours. Every facility can be open, closed, or open between set hours.
# =====================================================================================
func facOpen(key: String) -> bool:
	if S.get("mods") and S.mods.size() and tempShut(key): return false
	var f = S.fac.get(key) if S.get("fac") else null
	if not f: return true
	if f.get("shut"): return false
	if f.get("from") == null: return true
	var h := hour()
	return (h >= f.from and h < f.to) if f.from < f.to else (h >= f.from or h < f.to)
func facShut(key: String) -> bool: return bool(S.get("fac") and S.fac.has(key) and S.fac[key].get("shut"))
## running costs scale with the share of the day it's open; a closed facility still costs a third
func facShare(key: String) -> float:
	var f = S.fac.get(key) if S.get("fac") else null
	if not f: return 1.0
	if f.get("shut"): return 0.35
	if f.get("from") == null: return 1.0
	var hrs: float = (f.to - f.from) if f.from < f.to else (24 - f.from + f.to)
	return 0.35 + 0.65 * hrs / 24.0
func hh(h: int) -> String: return "%02d:00" % (h % 24)
const VENUE_FAC := { "shop": 'Pro shop', "resto": 'Restaurant', "bar": 'Bar', "terrace": 'Terrace', "locker": 'Locker rooms' }
func facList() -> Array:
	var out := []
	var add := func(group, key, label, note, icon): out.append({ "group": group, "key": key, "label": label, "note": note, "icon": icon })
	if courseHoles() > 0: add.call('Golf course', 'course', 'Golf course', 'Close it to rest the turf: it recovers three times faster. Groups already out finish their round.', 'course')
	if L('back9'): add.call('Golf course', 'back9', 'Back nine', 'While it is closed everyone plays nine holes, so rounds are quicker.', 'course')
	var ro := rangeObjs()
	for o in ro: add.call('Driving ranges', 'range:%s' % o.id, rangeName(o) if ro.size() > 1 else 'Driving range', 'Golfers already hitting finish their bucket.', 'range')
	if hasObj('club'):
		add.call('Clubhouse', 'venue:shop', 'Pro shop', 'The check-in desk stays open either way.', 'shop')
		if L('resto'): add.call('Clubhouse', 'venue:resto', 'Restaurant', '', 'resto')
		if L('barRoom'): add.call('Clubhouse', 'venue:bar', 'Bar', '', 'bar')
		if L('terrace'): add.call('Clubhouse', 'venue:terrace', 'Terrace', 'Also needs the bar to be open.', 'terrace')
		if L('locker'): add.call('Clubhouse', 'venue:locker', 'Locker rooms', 'Golfers change here before a round.', 'locker')
	var num := {}
	for o in objs():
		if not ['putt', 'short', 'academy', 'shortc', 'hut', 'lot'].has(o.type): continue
		var many := objs().filter(func(x): return x.type == o.type).size() > 1
		num[o.type] = num.get(o.type, 0) + 1
		var note := 'Cars already parked can still leave.' if o.type == 'lot' else ('Golfers buy food and drink here during a round.' if o.type == 'hut' else '')
		add.call('Car parks' if o.type == 'lot' else 'Practice and amenities', 'obj:%s' % o.id, OBJ[o.type].label + ((' %d' % num[o.type]) if many else ''), note, o.type)
	return out
## how busy it is right now
func facUse(key: String) -> int:
	var parts := key.split(':')
	var k := parts[0]
	var id := parts[1] if parts.size() > 1 else ''
	if k == 'course':
		var n := teeQueue.size()
		for g in groups: n += g.players.size()
		return n
	if k == 'range':
		var o = objById(int(id))
		return withRange(o, func(): return rangeP.size() + bucketQueue.size() + rangeQueue.size()) if (o and o.get("r")) else 0
	if k == 'venue':
		if id == 'locker': return visitors.filter(func(v): return v.state == 'locker').size()
		var n := 0
		for x in seatTaken.get(id, {}).values():
			if x: n += 1
		return n
	if k == 'obj':
		var o = objById(int(id))
		if not o: return 0
		if o.type == 'lot': return lotSpots(o).filter(func(s): return spotsHeld.has(s.key)).size()
		return amenUsers(o).size() + amenQ.get(o.id, []).size()
	return 0
func clockOf(t: float) -> String:
	var h := fmod(t, DAY_LEN) / DAY_LEN * 24.0
	return "%02d:%02d" % [int(h), int((h - int(h)) * 60)]
func facStatus(key: String) -> Dictionary:
	var f = S.fac.get(key) if S.get("fac") else null
	var open := facOpen(key)
	var use := facUse(key)
	var k := key.split(':')[0]
	var unit := 'golfers'
	if k == 'obj':
		var o = objById(int(key.split(':')[1]))
		if o and o.type == 'lot': unit = 'cars'
	var inUse := (" · %d %s" % [use, unit.substr(0, unit.length() - 1) if use == 1 else unit]) if use else ''
	var tm = tempShut(key)
	if tm: return { "open": false, "text": "Closed · %s until %s" % [str(tm.get("note", tm.label) if tm.get("note") else tm.label).to_lower(), clockOf(tm.until)] + inUse }
	if f and f.get("shut"): return { "open": false, "text": ('Closed · resting the turf' if key == 'course' else 'Closed') + inUse }
	if not open: return { "open": false, "text": "Closed · opens at %s" % hh(f.from) + inUse }
	if key == 'course' and isDark(): return { "open": false, "text": 'Closed for the night' + inUse }
	return { "open": true, "text": (("Open until %s" % hh(f.to)) if (f and f.get("from") != null) else 'Open') + inUse }
func setFac(key: String, patch: Dictionary) -> void:
	if not S.get("fac"): S.fac = {}
	var f: Dictionary = S.fac.get(key, {}).duplicate()
	f.merge(patch, true)
	if not f.get("shut") and f.get("from") == null: S.fac.erase(key)
	else: S.fac[key] = f
	csCache = null; sfx('soft' if patch.get("shut") else 'tap'); save()

# =====================================================================================
# Staff who work in one spot (attendants, shop, kitchen, bar, starter, teaching pro)
# =====================================================================================
const ROLE := {
	"owner": 'Club manager (you)', "shop": 'Shop assistant', "chef": 'Chef', "bar": 'Bartender', "attend": 'Range attendant', "picker": 'Ball picker',
	"marshal": 'Marshal', "keeper": 'Greenkeeper', "starter": 'Starter', "coach": 'Teaching pro',
}
var staffNames := {}
func staffName(key: String) -> String:
	if staffNames.has(key): return staffNames[key]
	var h := 7
	for c in key: h = (h * 31 + c.unicode_at(0)) % 2147483647
	var r := seeded(h if h else 1)
	r.call()
	var n: String = FIRST[int(floor(r.call() * FIRST.size()))] + '. ' + LAST[int(floor(r.call() * LAST.size()))]
	staffNames[key] = n
	return n
var actors := {}
func actor(key: String, role: String, i: int) -> Dictionary:
	if not actors.has(key): actors[key] = { "key": key, "role": role, "idx": i, "x": 0.0, "y": 0.0, "ang": PI / 2, "walk": null, "actor": true, "name": staffName(key), "lookRole": role, "lookSeed": i }
	actors[key].live = true
	return actors[key]
func updateActors(t: float) -> void:
	for a in actors.values(): a.live = false
	forRanges(func(o):
		var n: int = min(6, N('attend'))
		for k in n:
			var a := actor("attend:%s:%d" % [o.id, k], 'attend', k)
			var span := rangeX1() - RX0 - 32
			var ph := t * 0.3 + k * 2.1
			var vx := cos(ph)
			a.x = RX0 + 16 + span * (0.5 + 0.5 * sin(ph)); a.y = TEE_Y + 18; a.ang = 0.0 if vx > 0 else PI; a.walk = a.x * 0.55 if abs(vx) > 0.08 else null
			a.rangeId = o.id; a.lookRole = 'attend'; a.lookSeed = int(o.id) * 10 + k)
	if hasObj('club'):
		for k in min(3, N('assist') + 1):
			var a := actor("shop:%d" % k, 'shop' if k else 'owner', k)
			a.x = 1210 + k * 8 + CDX; a.y = 1372 + CDY; a.walk = null; a.ang = PI / 2
			a.lookRole = ('shop' if k == 1 else 'shop2') if k else 'owner'; a.lookSeed = k
		if L('resto'):
			for k in min(2, N('chef')):
				var a := actor("chef:%d" % k, 'chef', k)
				var ph = t * 0.5 + k * 2
				var vx := cos(ph)
				a.x = 1013 + sin(ph) * 5 + CDX; a.y = 1396 + k * 14 + CDY; a.ang = 0.0 if vx > 0 else PI; a.walk = a.x * 0.6 if abs(vx) > 0.2 else null; a.lookRole = 'chef'; a.lookSeed = k
		if L('barRoom'):
			for k in min(2, N('bar')):
				var a := actor("bar:%d" % k, 'bar', k)
				a.x = 1262 + k * 26 + sin(t * 0.25 + k) * 6 + CDX; a.y = 1361 + CDY; a.walk = null; a.ang = PI / 2; a.lookRole = 'bar'; a.lookSeed = k
	if N('starter') > 0 and courseHoles() > 0 and tee1Tile():
		var tp := teePos(0)
		for k in min(2, N('starter')):
			var a := actor("starter:%d" % k, 'starter', k)
			a.x = tp.x - 16 - k * 10; a.y = tp.y + 13; a.walk = null; a.ang = PI / 2; a.lookRole = 'starter'; a.lookSeed = k
	var ac = objOf('academy')
	if ac:
		var f := fp(ac)
		for k in min(3, N('coach')):
			var a := actor("coach:%d" % k, 'coach', k)
			a.x = f.x * TILE + 14 + k * 18 + 8; a.y = f.y * TILE + 37; a.walk = null; a.ang = PI; a.lookRole = 'coach'; a.lookSeed = k; a.academy = ac
	for k in actors.keys():
		if not actors[k].live: actors.erase(k)
func actorsOf(role: String) -> Array: return actors.values().filter(func(a): return a.role == role)
## everyone on the payroll who is out and about
func staffRoster() -> Array:
	var out := []
	for a in actors.values():
		if a.role == 'owner': out.append({ "kind": 'staff', "role": 'owner', "o": a })
	for m in marshals:
		if not m.get("name"): m.name = staffName('marshal:%s' % m.id)
		out.append({ "kind": 'staff', "role": 'marshal', "o": m })
	for k in keepers:
		if not k.get("name"): k.name = staffName('keeper:%s' % k.id)
		out.append({ "kind": 'staff', "role": 'keeper', "o": k })
	forRanges(func(r):
		for i in pickers.size():
			var p = pickers[i]
			if not p.get("name"): p.name = staffName("picker:%s:%d" % [r.id, i])
			p.rangeId = r.id; p.idx = i
			out.append({ "kind": 'staff', "role": 'picker', "o": p }))
	for a in actors.values():
		if a.role != 'owner': out.append({ "kind": 'staff', "role": a.role, "o": a })
	return out
const ROLE_ORDER := ['owner', 'starter', 'marshal', 'keeper', 'attend', 'picker', 'shop', 'coach', 'chef', 'bar']

# =====================================================================================
# Random events. Effects are temporary modifiers (S.mods) and temporary closures.
# =====================================================================================
func nowT() -> float: return S.day * DAY_LEN + S.clock
func atT(day: int, h: float) -> float: return day * DAY_LEN + h / 24.0 * DAY_LEN
func activeMods() -> Array:
	var t := nowT()
	return S.get("mods", []).filter(func(m): return m.get("start", 0) <= t and t < m.until) if S.get("mods") else []
func smodOf(k: String) -> float: return S.smod.get(k, 1.0) if S.get("smod") else 1.0
func modMult(k: String) -> float:
	var x := smodOf(k)
	for m in activeMods():
		if m.eff.get(k) != null: x *= m.eff[k]
	return x
func modAdd(k: String) -> float:
	var x := 0.0
	for m in activeMods():
		if m.eff.get(k) != null: x += m.eff[k]
	return x
func modOn(k: String) -> bool:
	for m in activeMods():
		if m.eff.get(k): return true
	return false
func tempShut(key: String):
	for m in activeMods():
		if m.eff.get("close") and m.eff.close.has(key): return m
	return null
func addMod(key: String, label: String, icon: String, startT: float, untilT: float, eff: Dictionary, note := '') -> void:
	if not S.get("mods"): S.mods = []
	S.modId = S.get("modId", 0) + 1
	S.mods.append({ "id": S.modId, "key": key, "label": label, "icon": icon, "start": startT, "until": untilT, "eff": eff, "note": note })
	csCache = null
func timeLeft(m) -> String:
	var t := nowT()
	var h: float = max(0.0, ((m.start if m.start > t else m.until) - t) / DAY_LEN * 24)
	var s := ("%dd %dh" % [int(h / 24), roundi(fmod(h, 24))]) if h >= 24 else (("%dh" % roundi(h)) if h >= 1 else ("%dm" % max(1, roundi(h * 60))))
	return ("starts in " + s) if m.start > t else (s + " left")
func builtHoles() -> Array: return builtIdx().filter(func(i): return holeOpen(i))
func roundTo(x: float, n := 100.0) -> float: return max(n, round(x / n) * n)
const CELEBS := [['Max Albatross', 'TV quiz show host'], ['Lena Fairweather', 'pop star'], ['Coach Duffy', 'football manager'], ['Dr Ivy Spinks', 'TV doctor'],
	['Rocco Vale', 'action film star'], ['Bea Holloway', 'Olympic rower'], ['Sir Nigel Pembury', 'retired racing driver'], ['DJ Kestrel', 'radio presenter']]
const STAFF_PLURAL := { "keeper": 'greenkeepers', "marshal": 'marshals', "bar": 'bartenders', "chef": 'chefs', "assist": 'shop assistants', "starter": 'starters', "coach": 'teaching pros' }
func shuffled(a: Array) -> Array:
	var b := a.duplicate(); b.shuffle(); return b
var RANDOM_EVENTS := {}
func _build_random_events() -> void:
	RANDOM_EVENTS = {
		"heatwave": { "icon": '☀', "w": 1.0, "cool": 25, "at": [8, 10], "when": func(): return season() == 'summer',
			"fire": func():
				S.wx = 'sunny'; S.wxNext = 'sunny'; S.wxLeft = DAY_LEN
				addMod('heatwave', 'Heatwave', '☀', nowT(), nowT() + 2 * DAY_LEN, { "course": 1.15, "range": 1.1, "food": 1.35, "wear": 1.8, "heat": 1 })
				return ['Heatwave', 'Two scorching days ahead. Expect more golfers and thirsty ones, but the turf will dry out fast without irrigation.'] },
		"fog": { "icon": '🌫', "w": 1.0, "cool": 8, "at": [5.5, 6.5], "when": func(): return courseHoles() > 0 and season() != 'summer' and not S.get("frostDay"),
			"fire": func():
				addMod('fog', 'Fog', '🌫', nowT(), atT(S.day, 10.5), { "close": ['course'], "fog": 1 }, 'Fog')
				return ['Fog', 'Thick fog rolled in overnight. Nobody can see the flags, so the course opens at 10:30 once it lifts.'] },
		"storm": { "icon": '⛈', "w": 1.0, "cool": 14, "at": [5.5, 6.5], "when": func(): return (season() == 'autumn' or season() == 'winter' or randf() < 0.3) and courseHoles() > 0,
			"fire": func():
				S.wx = 'rain'; S.wxLeft = 120.0
				var hs := builtHoles()
				var n := 4 + randi() % 5
				for k in n:
					if hs.is_empty(): break
					var i: int = pick(hs)
					var p := hPt(i, rnd(0.15, 0.9))
					var tn := hTan(i, 0.5)
					addMark('branch', p.x - tn.y * rnd(-22, 22), p.y + tn.x * rnd(-22, 22), { "hole": i, "rot": randf() * 6 })
				for k in 10:
					if hs.is_empty(): break
					var i: int = pick(hs)
					var p := hPt(i, randf())
					dropLitter(p.x + rnd(-30, 30), p.y + rnd(-30, 30))
				return ['Storm', "A storm blew through overnight. %d fallen branches lie across the course and there is debris everywhere. Marshals and greenkeepers will clear it, the more of them the faster." % n] },
		"pests": { "icon": '🐛', "w": 0.8, "cool": 30, "at": [7, 12], "when": func(): return (season() == 'spring' or season() == 'summer') and builtHoles().size() >= 3,
			"fire": func():
				var hs := shuffled(builtHoles()).slice(0, 2 + randi() % 2)
				for i in hs: S.turf[i] = max(5.0, S.turf[i] - rnd(18, 28))
				return ['Pests', "Leatherjackets are eating the roots on hole%s %s. The turf there has taken a beating. Greenkeepers and seed will bring it back." % ['s' if hs.size() > 1 else '', ", ".join(hs.map(func(i): return str(i + 1)))]] },
		"feature": { "icon": '📰', "w": 0.7, "cool": 30, "at": [8, 12], "when": func(): return stars() >= 2,
			"fire": func():
				addMod('feature', 'Magazine feature', '📰', nowT(), nowT() + 3 * DAY_LEN, { "arrive": 1.25 }); S.rep = min(100.0, S.get("rep", 70.0) + 3)
				return ['In the press', "Golf Monthly ran a two-page spread on %s. Expect a busier few days." % clubName()] },
		"viral": { "icon": '📱', "w": 0.8, "cool": 20, "at": [9, 15], "when": func(): return visitors.size() > 5,
			"fire": func():
				var here := visitors.filter(func(x): return x.state != 'drive' and x.state != 'gone')
				var nm: String = pick(here).name if here.size() else 'A golfer'
				addMod('viral', 'Gone viral', '📱', nowT(), nowT() + DAY_LEN, { "arrive": 1.45 })
				return ['Gone viral', "%s posted a video of a trick shot at your club and it is everywhere. Golfers are flocking in today." % nm] },
		"juniors": { "icon": '🎒', "w": 1.0, "cool": 40, "at": [7, 9], "when": func(): return [6, 7].has(monthIdx()) or (monthIdx() == 3 and randf() < 0.5),
			"fire": func():
				addMod('juniors', 'School holidays', '🎒', nowT(), nowT() + 5 * DAY_LEN, { "band_novice": 3, "band_high": 1.5 })
				return ['School holidays', 'The schools are out. For five days you will see far more juniors and beginners. Rental clubs, lessons and the short course will be in demand.'] },
		"celebrity": { "icon": '⭐', "w": 0.6, "cool": 20, "at": [9, 12], "when": func(): return stars() >= 3 and courseOK() and facOpen('course') and not isDark(),
			"fire": func():
				var before := visitors.size()
				arriveVisitor(['course', 'club'], 'expert')
				if visitors.size() == before: return null
				var v = visitors[visitors.size() - 1]
				var c: Array = pick(CELEBS)
				v.name = c[0]; v.celeb = c[1]; v.temper *= 0.8; v.color = '#f2c14e'
				return ['Celebrity visit', "%s, the %s, has just arrived for a round. Look after them: a good day out means great publicity, a bad one gets talked about too." % [c[0], c[1]], v] },
		"powercut": { "icon": '⚡', "w": 0.6, "cool": 25, "at": [10, 15], "when": func(): return hasObj('club') and (L('resto') or L('barRoom')),
			"fire": func():
				addMod('powercut', 'Power cut', '⚡', nowT(), nowT() + 3 / 24.0 * DAY_LEN, { "close": ['venue:shop', 'venue:resto', 'venue:bar', 'venue:terrace'] }, 'Power cut')
				return ['Power cut', 'The clubhouse has lost power. The shop, restaurant, bar and terrace are closed for about three hours. The check-in desk works by torchlight.'] },
		"geese": { "icon": '🦆', "w": 0.8, "cool": 15, "at": [7, 12], "when": func(): return rangeOK() and season() != 'winter',
			"fire": func():
				addMod('geese', 'Geese on the range', '🦆', nowT(), nowT() + 6 / 24.0 * DAY_LEN, { "range": 0.8, "geese": 1 })
				return ['Geese on the range', 'A flock of Canada geese has landed on the driving range and refuses to move. Some golfers are put off. They should leave by this afternoon.'] },
		"vandals": { "icon": '🔦', "w": 0.6, "cool": 25, "at": [6, 7], "when": func(): return builtHoles().size() >= 2,
			"fire": func():
				var hs := shuffled(builtHoles()).slice(0, 2 + randi() % 2)
				for i in hs:
					var g := hPt(i, greenT(i))
					addMark('green', g.x + rnd(-6, 6), g.y + rnd(-4, 4), { "hole": i }); wearHole(i, 6); dropLitter(g.x + rnd(-20, 20), g.y + rnd(-15, 15))
				if not N('marshal'): S.rep = max(0.0, S.get("rep", 70.0) - 2)
				return ['Vandals', "Someone got onto the course overnight and cut up the greens on hole%s %s. %s" % ['s' if hs.size() > 1 else '', ", ".join(hs.map(func(i): return str(i + 1))), 'Your marshals are on it.' if N('marshal') else 'With no marshals, word has got around.']] },
		"cartbreak": { "icon": '🔧', "w": 0.6, "cool": 25, "at": [7, 9], "when": func(): return L('carts') > 0,
			"fire": func():
				addMod('cartbreak', 'Carts off the road', '🔧', nowT(), nowT() + DAY_LEN, { "nocarts": 1, "course": 0.92 })
				return ['Carts grounded', 'The golf cart fleet failed its safety check. Everyone walks today, so rounds take longer.'] },
		# ---------------- offers and requests ----------------
		"sponsor": { "icon": '🍺', "w": 0.7, "cool": 45, "at": [9, 14], "when": func(): return stars() >= 2 and courseHoles() > 0, "choice": true,
			"ask": func():
				var pay := roundTo(fairFee9() * 60 + 1500)
				return { "kicker": 'An offer', "title": 'Sponsorship offer', "text": "Hollow Hill Brewery wants its logo on every tee sign for a month and offers %s up front. Some golfers will find it a bit tacky." % fmt(pay),
					"options": [
						{ "label": "Accept %s" % fmt(pay), "sub": 'Golfers are a little less happy for 30 days', "apply": func():
							earn(pay, 'other'); addMod('sponsor', 'Brewery sponsorship', '🍺', nowT(), nowT() + MONTH_DAYS * DAY_LEN, { "mood": -2 })
							return "You signed with the brewery for %s." % fmt(pay) },
						{ "label": 'Turn it down', "sub": 'Nothing changes', "apply": func(): return 'You turned the brewery down. The tee signs stay clean.' }] } },
		"filmcrew": { "icon": '🎬', "w": 0.5, "cool": 40, "at": [10, 15], "when": func(): return courseOK() and builtHoles().size() >= 3, "choice": true,
			"ask": func():
				var pay := roundTo(fairFee9() * 40 + 2500)
				var hole: int = pick(builtHoles())
				return { "kicker": 'A request', "title": 'Film crew', "text": "A production company wants to shoot a car advert on hole %d tomorrow morning. They offer %s, but the course would be closed until 13:00." % [hole + 1, fmt(pay)],
					"options": [
						{ "label": "Accept %s" % fmt(pay), "sub": 'Course closed tomorrow 06:00–13:00 · a little publicity', "apply": func():
							earn(pay, 'events'); addMod('filmcrew', 'Film crew on the course', '🎬', atT(S.day + 1, 6), atT(S.day + 1, 13), { "close": ['course'], "film": hole + 1 }, 'Filming'); S.rep = min(100.0, S.get("rep", 70.0) + 2)
							return "The film crew booked hole %d for tomorrow morning and paid %s." % [hole + 1, fmt(pay)] },
						{ "label": 'Decline', "sub": 'Keep the course open', "apply": func(): return 'You declined the film crew.' }] } },
		"charity": { "icon": '🎗', "w": 0.6, "cool": 45, "at": [9, 15], "when": func(): return courseOK(), "choice": true,
			"ask": func():
				return { "kicker": 'A request', "title": 'Charity morning', "text": 'The local hospice asks whether it can hold a free fundraising scramble on your course tomorrow morning. You would lose a morning of green fees.',
					"options": [
						{ "label": 'Host it for free', "sub": 'Course closed tomorrow 07:00–12:00 · reputation +6 · busier afterwards', "apply": func():
							addMod('charity', 'Charity scramble', '🎗', atT(S.day + 1, 7), atT(S.day + 1, 12), { "close": ['course'] }, 'Charity scramble')
							addMod('goodwill', 'Goodwill', '💚', atT(S.day + 1, 12), atT(S.day + 4, 12), { "arrive": 1.1 }); S.rep = min(100.0, S.get("rep", 70.0) + 6)
							return 'You are hosting the hospice fundraiser tomorrow morning. The town is talking about it.' },
						{ "label": 'Politely decline', "sub": 'Reputation −2', "apply": func():
							S.rep = max(0.0, S.get("rep", 70.0) - 2)
							return 'You declined the hospice. A few locals were disappointed.' }] } },
		"bonus": { "icon": '🤝', "w": 0.7, "cool": 35, "at": [8, 12], "when": func(): return STAFF_PLURAL.keys().any(func(r): return int(S.staff.get(r, 0)) >= 2), "choice": true,
			"ask": func():
				var role: String = pick(STAFF_PLURAL.keys().filter(func(r): return int(S.staff.get(r, 0)) >= 2))
				var n: int = S.staff[role]
				var sal: float = byId[role].sal * DAY_LEN
				var pay := roundTo(n * sal * 2, 50)
				var who: String = STAFF_PLURAL[role]
				return { "kicker": 'Your staff', "title": 'A bonus for the team?', "text": "Your %d %s have been working flat out and ask for a one-off bonus of %s. They hint that saying no might not go down well." % [n, who, fmt(pay)],
					"options": [
						{ "label": "Pay %s" % fmt(pay), "sub": 'They stay happy', "apply": func():
							spend(pay, 'wages')
							return "You paid your %s a %s bonus." % [who, fmt(pay)] },
						{ "label": 'Say no', "sub": 'Risk a one-day strike tomorrow', "apply": func():
							if randf() < 0.6:
								addMod('strike', "%s on strike" % who.capitalize(), '✊', atT(S.day + 1, 7), atT(S.day + 1, 19), { "strike": role })
								return "Your %s are walking out tomorrow from 07:00 to 19:00." % who
							return "Your %s grumbled, but they are carrying on." % who }] } },
		"poach": { "icon": '🕴', "w": 0.5, "cool": 40, "at": [10, 15], "when": func(): return ['keeper', 'chef', 'marshal', 'coach'].any(func(r): return int(S.staff.get(r, 0)) >= 1), "choice": true,
			"ask": func():
				ensureRival()
				var role: String = pick(['keeper', 'chef', 'marshal', 'coach'].filter(func(r): return int(S.staff.get(r, 0)) >= 1))
				var nm: String = byId[role].name.to_lower()
				var pay := roundTo(byId[role].sal * DAY_LEN * 12, 50)
				return { "kicker": 'Rival news', "title": 'Poaching attempt', "text": "%s has offered your best %s a job. Match it with a %s retention bonus, or let them go." % [S.rival.name, nm, fmt(pay)],
					"options": [
						{ "label": "Match it: %s" % fmt(pay), "sub": 'They stay', "apply": func():
							spend(pay, 'wages')
							return "Your %s is staying, for a %s bonus." % [nm, fmt(pay)] },
						{ "label": 'Let them go', "sub": "You lose one %s" % nm, "apply": func():
							S.staff[role] = max(0, int(S.staff.get(role, 0)) - 1)
							return "Your %s left for %s." % [nm, S.rival.name] }] } },
		"balldeal": { "icon": '🛒', "w": 0.7, "cool": 25, "at": [9, 15], "when": func(): return rangeOK(), "choice": true,
			"ask": func():
				var r = null
				for o in rangeObjs():
					if o.get("r"): r = o; break
				var unit: float = withRange(r, func(): return cost(byId.order) / 500.0)
				var n := 1500
				var price := roundTo(unit * n * 0.5, 10)
				return { "kicker": 'An offer', "title": 'Bulk ball deal', "text": "A supplier is clearing stock: %s range balls for %s, half the usual price." % [fmtInt(n), fmt(price)],
					"options": [
						{ "label": "Buy for %s" % fmt(price), "sub": "+%s balls for %s" % [fmtInt(n), rangeName(r) if rangeObjs().size() > 1 else 'your range'], "apply": func():
							spend(price, 'supplies')
							withRange(r, func(): S.owned += n; S.stock = min(ballCap(), S.stock + n))
							return "%s range balls delivered for %s." % [fmtInt(n), fmt(price)] },
						{ "label": 'No thanks', "sub": 'Nothing changes', "apply": func(): return 'You passed on the ball deal.' }] } },
		"members": { "icon": '📝', "w": 0.6, "cool": 45, "at": [10, 16], "when": func(): return S.get("members", 0) >= 15, "choice": true,
			"ask": func():
				var lose: int = max(1, roundi(S.members * 0.08))
				var price := roundf(S.prices.member * 0.9)
				return { "kicker": 'Your members', "title": 'Members’ petition', "text": "%d members signed a petition asking for a cheaper membership. They want %s a month instead of %s." % [roundi(S.members * 0.4), fmt(price), fmt(S.prices.member)],
					"options": [
						{ "label": "Cut to %s" % fmt(price), "sub": 'Members happier · less income each', "apply": func():
							S.prices.member = price; S.rep = min(100.0, S.get("rep", 70.0) + 2)
							return "Membership now costs %s a month." % fmt(price) },
						{ "label": 'Keep the price', "sub": "About %d members leave" % lose, "apply": func():
							S.members = max(0, S.members - lose)
							return "%d members cancelled in protest." % lose }] } },
		"wedding": { "icon": '💍', "w": 0.5, "cool": 40, "at": [10, 16], "when": func(): return L('terrace') > 0 and L('resto') > 0, "choice": true,
			"ask": func():
				var pay := roundTo(4000 + 1500 * L('resto'))
				return { "kicker": 'A booking', "title": 'Wedding reception', "text": "A couple wants to hold their wedding reception at the club tomorrow evening and offers %s. The terrace and restaurant would be closed to golfers from 15:00." % fmt(pay),
					"options": [
						{ "label": "Accept %s" % fmt(pay), "sub": 'Terrace and restaurant private from 15:00 tomorrow', "apply": func():
							earn(pay, 'events'); addMod('wedding', 'Wedding reception', '💍', atT(S.day + 1, 15), atT(S.day + 2, 0), { "close": ['venue:terrace', 'venue:resto'] }, 'Private function')
							return "The wedding is booked for tomorrow evening, for %s." % fmt(pay) },
						{ "label": 'Decline', "sub": 'Nothing changes', "apply": func(): return 'You turned the wedding down.' }] } },
	}
const EV_CHANCE := { "off": 0.0, "rare": 0.2, "normal": 0.4, "often": 0.7 }
func scheduleRandomEvent() -> void:
	var t := nowT()
	S.mods = S.get("mods", []).filter(func(m): return m.until > t) if S.get("mods") else []
	var ch: float = EV_CHANCE.get(SETTINGS.get("events", 'normal'), 0.4)
	if S.get("evNext") or S.day < 3 or (S.get("scenario") == 'sandbox' and SETTINGS.get("events") != 'often') or randf() >= ch: return
	if not S.get("evCool"): S.evCool = {}
	var pool := []
	for k in RANDOM_EVENTS:
		if S.evCool.get(k, 0) <= S.day and RANDOM_EVENTS[k].when.call(): pool.append(k)
	if pool.is_empty(): return
	var tot := 0.0
	for k in pool: tot += RANDOM_EVENTS[k].w
	var x := randf() * tot
	var key: String = pool[0]
	for k in pool:
		x -= RANDOM_EVENTS[k].w
		if x <= 0: key = k; break
	var E = RANDOM_EVENTS[key]
	S.evNext = { "key": key, "day": S.day, "at": rnd(E.at[0], E.at[1]) }
var evQueue: Array = []
var evOpen = null
var evSpeed := 1
var uiBusy := false   # the UI sets this while a menu, settings or another dialog is open
signal inspect_requested(ent)
func logEvent(icon: String, title: String, text: String) -> void:
	if not S.get("evLog"): S.evLog = []
	S.evLog.push_front({ "day": S.day, "clock": S.clock, "icon": icon, "title": title, "text": text })
	if S.evLog.size() > 14: S.evLog.resize(14)
func fireRandomEvent(key: String) -> void:
	if not RANDOM_EVENTS.has(key): return
	var E = RANDOM_EVENTS[key]
	if not S.get("evCool"): S.evCool = {}
	S.evCool[key] = S.day + E.cool
	if E.get("choice"):
		var ev: Dictionary = E.ask.call()
		ev.key = key; ev.icon = E.icon
		evQueue.append(ev); return
	var r = E.fire.call()
	if not r: return
	logEvent(E.icon, r[0], r[1])
	toast('Club news', r[0], r[1], E.icon); sfx('chime')
	if r.size() > 2: inspect_requested.emit({ "kind": 'golfer', "o": r[2] })
	save()
func eventsTick() -> void:
	if S.get("mods") and S.mods.size():
		var t := nowT()
		for m in S.mods:
			if not m.get("begun") and m.start <= t and m.until > t:
				m.begun = true
				if m.start < t - 1 and m.start > t - DAY_LEN and m.get("note"): toast('Club news', "%s has started" % m.label, timeLeft(m), m.icon)
			if not m.get("ended") and m.until <= t:
				m.ended = true
				if ['heatwave', 'fog', 'powercut', 'geese', 'strike', 'cartbreak', 'filmcrew', 'charity', 'wedding'].has(m.key): toast('Club news', "%s: over" % m.label, 'Back to normal.', m.icon)
		S.mods = S.mods.filter(func(m): return m.until > t)
		strikeRoles = {}
		for m in activeMods():
			if m.eff.get("strike"): strikeRoles[m.eff.strike] = true
	elif strikeRoles.size(): strikeRoles = {}
	var nx = S.get("evNext")
	if nx and (S.day > nx.day or hour() >= nx.at):
		S.evNext = null
		if S.day <= nx.day + 1: fireRandomEvent(nx.key)
	# offers wait for a quiet moment: not over the title screen or another window
	if evQueue.size() and evOpen == null and not atTitle and not uiBusy: showEventCard(evQueue.pop_front())
func showEventCard(ev) -> void:
	evOpen = ev; evSpeed = speedIdx if speedIdx else (lastSpeed if lastSpeed else 1); setSpeed(0)
	event_card.emit(ev); sfx('open')
func chooseEventOption(i: int) -> void:
	if evOpen == null: return
	var ev = evOpen
	var res: String = ev.options[i].apply.call()
	var ic: String = ev.get("icon", '★')
	if ev.key != 'medal': logEvent(ic, ev.title, res)
	evOpen = null; setSpeed(evSpeed)
	if ev.key != 'medal': toast('The bank' if ev.key == 'bank' else 'Club news', ev.title, res, ic)
	sfx('chime'); ui_refresh.emit(); save()
## a famous visitor's day out ends up in the papers either way
func celebLeaves(v) -> void:
	var m := moodOf(v)
	if m >= 60:
		S.rep = min(100.0, S.get("rep", 70.0) + 6); addMod('celebpost', "%s raves about you" % v.name, '⭐', nowT(), nowT() + 2 * DAY_LEN, { "arrive": 1.3 })
		logEvent('⭐', "%s loved it" % v.name, "%s posted glowing photos from %s. Reputation +6 and a busier couple of days." % [v.name, clubName()])
		toast('Club news', "%s loved it" % v.name, 'Glowing photos all over social media. Expect a busier couple of days.', '⭐'); sfx('fanfare')
	else:
		S.rep = max(0.0, S.get("rep", 70.0) - 4)
		logEvent('⭐', "%s was not impressed" % v.name, "%s complained about the visit in an interview. Reputation −4." % v.name)
		toast('Club news', "%s was not impressed" % v.name, 'They had a poor day and told everyone about it. Reputation −4.', '!')
func modFx(m) -> String:
	var out := []
	for k in m.eff:
		var v = m.eff[k]
		match k:
			"arrive": out.append("%s%d%% golfers" % ['+' if v > 1 else '−', roundi(abs(v - 1) * 100)])
			"course": out.append("%s%d%% course demand" % ['+' if v > 1 else '−', roundi(abs(v - 1) * 100)])
			"range": out.append("%s%d%% range demand" % ['+' if v > 1 else '−', roundi(abs(v - 1) * 100)])
			"food": out.append("+%d%% food and drink" % roundi((v - 1) * 100))
			"wear": out.append("turf wears %s× faster" % str(v))
			"mood": out.append("mood %s%s" % ['+' if v > 0 else '', str(v)])
			"band_novice": out.append('many more beginners')
			"nocarts": out.append('no golf carts')
			"strike": out.append("%s not working" % STAFF_PLURAL.get(v, v))
			"close":
				var names := []
				for kk in v:
					var lbl: String = kk.split(':')[1] if kk.contains(':') else kk
					for it in facList():
						if it.key == kk: lbl = it.label; break
					names.append(lbl.to_lower())
				out.append("closed: " + ", ".join(names))
	return " · ".join(out)

# =====================================================================================
# The campaign. Each scenario has its own start, a deadline and three medals.
# You can lose four ways: the bank, the board, the deadline and a boycott.
# =====================================================================================
const DIFF := {
	"easy":   { "label": 'Easy', "blurb": 'More cash, cheaper running costs, patient golfers, a forgiving bank and board.', "cash": 1.5, "costs": 0.85, "patience": 1.25, "redDays": 9, "repDays": 9, "board": 70, "boardK": 0.6, "score": 0.8 },
	"normal": { "label": 'Normal', "blurb": 'The game as intended.', "cash": 1.0, "costs": 1.0, "patience": 1.0, "redDays": 6, "repDays": 6, "board": 60, "boardK": 1.0, "score": 1.0 },
	"hard":   { "label": 'Hard', "blurb": 'Less cash, dearer running costs, impatient golfers, a strict bank and board.', "cash": 0.75, "costs": 1.15, "patience": 0.85, "redDays": 4, "repDays": 4, "board": 50, "boardK": 1.4, "score": 1.35 },
}
func diff() -> Dictionary: return DIFF.get(S.get("diff", 'normal'), DIFF.normal)
func endOfYear(n: int) -> int: return 30 + 36 * (n - 1)
func netWorth() -> float: return S.money - S.get("loan", 0.0)
func bestMonth(k: String) -> float:
	var best: float = S.ledger.month.get(k, 0.0) if (S.get("ledger") and S.ledger.get("month")) else 0.0
	if S.get("ledger"):
		for m in S.ledger.get("months", []): best = max(best, m.get(k, 0.0))
	return best
## a condition: what it asks for, whether it's met, and how far along you are
func C(kind: String, n = 0, label := '') -> Dictionary:
	match kind:
		"stars": return { "t": "%d-star rating" % n, "ok": func(): return stars() >= n, "now": func(): return "%d★" % stars() }
		"holes": return { "t": "%d holes built" % n, "ok": func(): return courseHoles() >= n, "now": func(): return str(courseHoles()) }
		"members": return { "t": "%d members" % n, "ok": func(): return S.get("members", 0) >= n, "now": func(): return str(S.get("members", 0)) }
		"cash": return { "t": "%s in the bank" % fmt(n), "ok": func(): return S.money >= n, "now": func(): return fmt(S.money) }
		"worth": return { "t": "%s net worth (cash minus loans)" % fmt(n), "ok": func(): return netWorth() >= n, "now": func(): return fmt(netWorth()) }
		"noLoan": return { "t": 'Loan paid off', "ok": func(): return not (S.get("loan", 0) > 0), "now": func(): return (fmt(S.loan) + ' left') if S.get("loan", 0) > 0 else 'paid' }
		"rep": return { "t": "Reputation %d+" % n, "ok": func(): return S.get("rep", 70.0) >= n, "now": func(): return str(roundi(S.get("rep", 70.0))) }
		"turf": return { "t": "Turf %d%% or better" % n, "ok": func(): return S.cond >= n and courseHoles() > 0, "now": func(): return "%d%%" % roundi(S.cond) }
		"bays": return { "t": "%d range bays open" % n, "ok": func(): return openBays() >= n, "now": func(): return str(openBays()) }
		"rangeMonth": return { "t": "%s range income in one month" % fmt(n), "ok": func(): return bestMonth('range') >= n, "now": func(): return fmt(bestMonth('range')) }
		"event": return { "t": "A successful %s" % label, "ok": func(): return S.get("eventsDone", {}).get(n, 0) >= 1, "now": func(): return 'done' if S.get("eventsDone", {}).get(n, 0) else 'not yet' }
		"trophies": return { "t": "%d %s won" % [n, 'trophy' if n == 1 else 'trophies'], "ok": func(): return S.get("trophies", 0) >= n, "now": func(): return str(S.get("trophies", 0)) }
		"slope": return { "t": "Slope %d+ from the yellow tees" % n, "ok": func(): return csCache != null and csCache.has("yellow") and csCache.yellow.slope >= n and L('back9') > 0, "now": func(): return str(csCache.yellow.slope) if (csCache != null and csCache.has("yellow")) else '–' }
		"lights": return { "t": 'Floodlights on a range', "ok": func(): return rangeObjs().any(func(o): return o.get("r") and int(o.r.lvl.get("lights", 0)) > 0), "now": func(): return 'yes' if rangeObjs().any(func(o): return o.get("r") and int(o.r.lvl.get("lights", 0)) > 0) else 'no' }
	return {}
var CAMPAIGN: Array = []
var SANDBOX := {}
func _setupClassic(keepers_: int, bayLvl: int) -> void:
	S.design = defaultDesign(true, null, false); applyDesign()
	S.staff.keeper = keepers_
	S.world = classicWorld(null); linkRange(S.world); S.design.land = S.world.land
	for o in S.world.objs:
		if o.type == 'range':
			o.r = newRangeState(); o.r.mx = o.x * TILE + 20; o.r.lvl.bay = bayLvl; o.r.staff.attend = 1
	S.rangeMigrated = true
func _turf(a: float, b: float) -> Array:
	var t := []
	for i in 18: t.append(float(roundi(rnd(a, b))))
	return t
func _build_campaign() -> void:
	CAMPAIGN = [
		{ "id": 'fresh', "name": 'Pine Hollow', "tag": 'Start here', "blurb": 'A small plot beside the road and $30,000. Build a car park, a range, a clubhouse and your first holes, then grow it into a proper club.',
			"years": 3, "medals": [[C('stars', 2), C('holes', 9)], [C('stars', 3), C('members', 20)], [C('stars', 4), C('holes', 18), C('cash', 25000)]],
			"setup": func(): S.money = 30000.0 },
		{ "id": 'rescue', "name": 'The Rescue', "tag": 'Turnaround', "blurb": 'You inherit a run-down club: worn turf, a poor name and a $30,000 loan. Turn it around before the owners lose patience.',
			"years": 3, "medals": [[C('stars', 3), C('noLoan')], [C('rep', 70)], [C('stars', 4), C('members', 40)]],
			"setup": func():
				_setupClassic(1, 3)
				S.money = 8000.0; S.loan = 30000.0; S.rep = 42.0; S.invested = 90000.0; S.turf = _turf(35, 55) },
		{ "id": 'city', "name": 'City Lights Range', "tag": 'Range', "blurb": 'A plot on the edge of town. Commuters love a driving range after work, but few want a round of golf here, and land is expensive.',
			"years": 2, "smod": { "range": 1.6, "course": 0.6, "land": 1.8 }, "medals": [[C('bays', 15), C('rangeMonth', 2500)], [C('lights'), C('bays', 24), C('stars', 3)], [C('rangeMonth', 6000), C('worth', 30000)]],
			"setup": func(): S.money = 35000.0 },
		{ "id": 'seaside', "name": 'Seaside Links', "tag": 'Course', "blurb": 'Dunes, wind and rain off the sea. Golfers will travel for a proper links course, but the range is an afterthought here.',
			"years": 4, "smod": { "course": 1.3, "range": 0.7, "wx_windy": 2.2, "wx_rain": 1.3 }, "medals": [[C('holes', 18), C('stars', 3)], [C('stars', 4), C('turf', 85)], [C('event', 'proam', 'Charity Pro-Am'), C('stars', 4)]],
			"setup": func(): S.money = 60000.0 },
		{ "id": 'oakmere', "name": 'Oakmere Members’ Club', "tag": 'Members', "blurb": 'A pretty nine-hole club whose public trade has dried up. The money is in memberships now, so build a club people want to belong to.',
			"years": 3, "smod": { "course": 0.55, "members": 1.8 }, "medals": [[C('members', 35)], [C('members', 60), C('stars', 3)], [C('members', 90), C('stars', 4)]],
			"setup": func():
				_setupClassic(2, 2)
				S.money = 25000.0; S.rep = 66.0; S.invested = 90000.0; S.turf = _turf(80, 92); S.members = 12 },
		{ "id": 'frost', "name": 'Frostbite', "tag": 'Survival', "blurb": 'You open in November with little cash and a small loan. Survive the winter, then make the most of a single summer.',
			"years": 2, "start": 25, "medals": [[C('stars', 2), C('cash', 10000)], [C('stars', 3)], [C('stars', 3), C('members', 30), C('noLoan')]],
			"setup": func(): S.money = 18000.0; S.loan = 10000.0 },
		{ "id": 'estate', "name": 'Kingsbridge Estate', "tag": 'Events', "blurb": 'A grand old estate course that wants to host tournaments again. Win over the organisers, from a corporate day all the way to the County Championship.',
			"years": 4, "medals": [[C('event', 'corporate', 'corporate golf day')], [C('event', 'proam', 'Charity Pro-Am')], [C('event', 'county', 'County Championship'), C('trophies', 1)]],
			"setup": func():
				_setupClassic(2, 4)
				S.money = 60000.0; S.rep = 62.0; S.invested = 90000.0; S.turf = _turf(70, 85) },
		{ "id": 'champ', "name": 'The Championship Course', "tag": 'Finale', "blurb": 'An investor gives you $120,000 and five years to build the finest club in the county: five stars, a testing course and silverware.',
			"years": 5, "medals": [[C('stars', 5)], [C('stars', 5), C('slope', 125)], [C('stars', 5), C('trophies', 2), C('worth', 250000)]],
			"setup": func(): S.money = 120000.0 },
	]
	SANDBOX = { "id": 'sandbox', "name": 'Sandbox', "tag": 'Creative', "blurb": '$1,000,000, every plot of land, no goals, no deadline and no board. Build the course you have always wanted.',
		"setup": func(): S.money = 1000000.0; S.world = freshWorld('sandbox'); S.design.land = S.world.land }
func scenOf(id):
	for s in CAMPAIGN:
		if s.id == id: return s
	return SANDBOX if id == 'sandbox' else null
func inCampaign() -> bool:
	for s in CAMPAIGN:
		if s.id == S.get("scenario"): return true
	return false
const MEDAL := ['None', 'Bronze', 'Silver', 'Gold']
const MEDAL_IC := ['–', '🥉', '🥈', '🥇']
## campaign progress lives with your settings, so it carries across saves
func campaignOf() -> Dictionary:
	if not SETTINGS.get("campaign"): SETTINGS.campaign = {}
	return SETTINGS.campaign
func unlocked(i: int) -> bool: return i < 2 or int(campaignOf().get(CAMPAIGN[i - 1].id, {}).get("medal", 0)) >= 1
## ---- starting a scenario
func setupScenario(k: String, d := 'normal') -> void:
	var sc = scenOf(k) if scenOf(k) else CAMPAIGN[0]
	S.scenario = sc.id; S.goalIdx = 0; S.goalFailed = false; S.diff = d; S.smod = sc.smod.duplicate() if sc.get("smod") else null
	if sc.get("start"): S.day = sc.start; S.clock = 7.0 * 15
	sc.setup.call()
	if sc.id != 'sandbox': S.money = roundf(S.money * diff().cash); S.deadline = endOfYear(sc.years)
	S.startDay = S.day; S.medal = 0; S.board = null if sc.id == 'sandbox' else diff().board; S.boardLog = []; S.over = null; S.finished = false
	S.peakStars = 0; S.repLow = 0; S.lastReview = { "stars": null, "medal": 0 }; S.econ = 2
	rebuildWorld(); layout()
## medals: each tier needs its own conditions and every tier below it
func tierMet(sc, t: int) -> bool:
	for list in sc.medals.slice(0, t + 1):
		for c in list:
			if not c.ok.call(): return false
	return true
func medalNow(sc) -> int:
	var m := 0
	for t in 3:
		if tierMet(sc, t): m = t + 1
		else: break
	return m
func checkCampaign() -> void:
	if not gameLive or atTitle or S.get("over"): return
	var sc = scenOf(S.get("scenario"))
	if not sc or sc.id == 'sandbox': return
	S.peakStars = max(S.get("peakStars", 0), stars())
	if S.get("finished"): return
	var m := medalNow(sc)
	if m > S.get("medal", 0):
		S.medal = m; S.medalDay = S.day
		recordResult(sc, m)
		if m == 3: showEnd('gold'); return
		showMedalCard(sc, m)
	if S.get("deadline") and S.day > S.deadline:
		if S.medal > 0: showEnd('deadline-won')
		else: gameOver('deadline')
func recordResult(sc, m: int) -> void:
	var c := campaignOf()
	var prev: Dictionary = c.get(sc.id, {})
	var sc2 := scoreOf(m)
	c[sc.id] = { "medal": max(int(prev.get("medal", 0)), m), "score": max(int(prev.get("score", 0)), sc2), "diff": prev.get("diff") if int(prev.get("medal", 0)) > m else S.diff }
	saveSettings()
	if m >= 1: unlockAch('ACH_MEDAL_FIRST')
	if m >= 3: unlockAch('ACH_MEDAL_GOLD')
	if CAMPAIGN.all(func(s): return int(c.get(s.id, {}).get("medal", 0)) >= 1): unlockAch('ACH_CAMPAIGN_DONE')
	if CAMPAIGN.all(func(s): return int(c.get(s.id, {}).get("medal", 0)) >= 3): unlockAch('ACH_CAMPAIGN_GOLD')
	if S.diff == 'hard' and m >= 1: unlockAch('ACH_HARD_MEDAL')
func scoreOf(m: int) -> int:
	var left: float = max(0, S.get("deadline", S.day) if S.get("deadline") else S.day - S.day)
	if S.get("deadline"): left = max(0, S.deadline - S.day)
	return roundi(([0, 1000, 2000, 3500][m] + max(0.0, netWorth()) / 50.0 + (S.get("peakStars", 0) if S.get("peakStars") else stars()) * 150 + S.get("rep", 70.0) * 4 + S.get("members", 0) * 5 + left * 12) * diff().score)
## the board reviews the club every month
func boardReview(monthLedger) -> void:
	var sc = scenOf(S.get("scenario"))
	if not sc or sc.id == 'sandbox' or S.get("board") == null or S.get("over") or S.get("finished"): return
	var k: float = diff().boardK
	var notes := []
	var monthsIn := int(floor((S.day - S.get("startDay", 1)) / float(MONTH_DAYS)))
	var d := 0
	var L_: Dictionary = monthLedger if monthLedger else {}
	var build: float = -L_.get("build", 0.0)
	var op := sumOf(L_) + build
	if op > 2000: d += 6; notes.append(['+6', "operating profit %s" % fmt(op)])
	elif op > 0: d += 3; notes.append(['+3', 'a small operating profit'])
	elif monthsIn >= 2:
		var p := -roundi((8 if op < -2000 else 4) * k)
		d += p; notes.append([str(p), "an operating loss of %s" % fmt(-op)])
	var st := stars()
	var ls = S.lastReview.get("stars") if S.get("lastReview") else null
	if ls != null and st > ls: d += 6; notes.append(['+6', "up to %d stars" % st])
	if ls != null and st < ls:
		var p := -roundi(8 * k)
		d += p; notes.append([str(p), "down to %d stars" % st])
	var rp: float = S.get("rep", 70.0)
	if rp >= 70: d += 2; notes.append(['+2', 'a good name locally'])
	elif rp < 35:
		var p := -roundi((8 if rp < 22 else 4) * k)
		d += p; notes.append([str(p), 'a poor reputation'])
	if S.get("medal", 0) > (S.lastReview.get("medal", 0) if S.get("lastReview") else 0): d += 10; notes.append(['+10', "%s objective reached" % MEDAL[S.medal]])
	if S.money < 0:
		var p := -roundi(8 * k)
		d += p; notes.append([str(p), 'the account is overdrawn'])
	var before: float = S.board
	S.board = clampf(S.board + d, 0, 100)
	S.lastReview = { "stars": st, "medal": S.get("medal", 0) }
	var bl: Array = [{ "day": S.day, "d": d, "notes": notes, "board": S.board }] + S.get("boardLog", [])
	S.boardLog = bl.slice(0, 6)
	if S.board <= 0: gameOver('board'); return
	var tone := 'pleased' if d > 0 else ('concerned' if d < 0 else 'satisfied')
	var nt := ", ".join(notes.map(func(n): return n[1]))
	toast('Board review', "Confidence %d%% (%s%d)" % [roundi(S.board), '+' if d >= 0 else '', d], "The board is %s: %s." % [tone, nt if nt else 'nothing much to report'], '🏛' if d >= 0 else '!')
	if S.board <= 30 and before > 30: toast('The board', 'The board is losing patience', 'If confidence reaches zero you will be dismissed. Turn a profit, lift the star rating or reach the next objective.', '!')
## reputation collapse: checked every day
func repDaily() -> void:
	if not inCampaign() or S.get("over") or S.get("finished"): return
	if S.get("rep", 70.0) < 15:
		S.repLow = S.get("repLow", 0) + 1
		var left: int = diff().repDays - S.repLow
		if left <= 0: gameOver('rep'); return
		toast('Boycott', 'Golfers are staying away', "Your reputation is so poor that people are boycotting the club. Get it above 15 within %d day%s or the club closes." % [left, 's' if left > 1 else ''], '!')
	else: S.repLow = 0
## the bank: warnings, a forecast and one emergency loan
func bankDaily() -> bool:
	if S.get("over"): return false
	var lim: int = diff().redDays
	if S.money < 0:
		S.redDays = S.get("redDays", 0) + 1
		var left: int = lim - S.redDays
		if left <= 0: gameOver('bank'); return true
		if left == lim - 1 or left == 2: toast('The bank', 'Your account is overdrawn' if S.redDays == 1 else 'Final warning from the bank', "%d more day%s in the red and the bank closes the club. Borrow in Finances, raise prices or cut costs." % [left, 's' if left > 1 else ''], '!')
		if left == 1 and not S.get("rescueLoan"): offerRescueLoan()
	else: S.redDays = 0
	return false
func offerRescueLoan() -> void:
	S.rescueLoan = true
	var amt := roundTo(max(5000.0, -S.money + (wagesPerDay() + upkeepPerDay()) * 4), 500)
	var owe := roundf(amt * 1.3)
	evQueue.push_front({ "key": 'bank', "icon": '🏦', "kicker": 'The bank', "title": 'A last chance', "text": "You are one day from being closed down. The bank will lend you %s to keep going, but you will owe %s. This offer will not come again." % [fmt(amt), fmt(owe)],
		"options": [
			{ "label": "Take %s" % fmt(amt), "sub": "Adds %s to your loan · clears the overdraft" % fmt(owe), "apply": func():
				S.money += amt; S.loan = S.get("loan", 0.0) + owe; S.redDays = 0
				return "You took the emergency loan. You now owe the bank %s." % fmt(S.loan) },
			{ "label": 'Refuse', "sub": 'Get out of the red by tomorrow, or the club closes', "apply": func(): return 'You refused the emergency loan.' }] })
## how long the money lasts at the current rate
func cashForecast():
	var ds: Array = S.ledger.get("days", []).slice(-3) if S.get("ledger") else []
	if ds.is_empty(): return null
	var avg := 0.0
	for d in ds: avg += d.profit
	avg /= ds.size()
	if avg >= 0: return { "avg": avg, "days": null }
	return { "avg": avg, "days": max(0, int(floor(S.money / -avg))) }
## the end: a medal, or game over
func endInfo(kind: String) -> Dictionary:
	var m: int = S.get("medal", 0)
	match kind:
		"gold": return { "ic": '🥇', "kicker": 'Scenario complete', "title": 'Gold medal!', "text": "You reached every objective at %s. A superb piece of management." % clubName(), "lose": false }
		"deadline-won": return { "ic": MEDAL_IC[m], "kicker": 'Deadline reached', "title": "%s medal" % MEDAL[m], "text": "Time is up at %s. You finished with a %s medal." % [clubName(), MEDAL[m].to_lower()], "lose": false }
		"finish": return { "ic": MEDAL_IC[m], "kicker": 'Scenario complete', "title": "%s medal" % MEDAL[m], "text": "You chose to finish at %s with a %s medal." % [clubName(), MEDAL[m].to_lower()], "lose": false }
		"bank": return { "ic": '🏦', "kicker": 'Game over', "title": 'The bank has closed your club', "text": "%s spent too long in the red. The bank has taken over the park and its debts." % clubName(), "lose": true }
		"board": return { "ic": '🏛', "kicker": 'Game over', "title": 'The board has dismissed you', "text": "Confidence in your management ran out. The owners of %s have appointed someone else." % clubName(), "lose": true }
		"deadline": return { "ic": '⌛', "kicker": 'Game over', "title": 'Out of time', "text": "The deadline passed without reaching the bronze objective at %s." % clubName(), "lose": true }
		"rep": return { "ic": '📉', "kicker": 'Game over', "title": 'The club has closed', "text": "Nobody wants to play at %s any more. With golfers boycotting it, the club had to close its doors." % clubName(), "lose": true }
	return {}
func gameOver(cause: String) -> void:
	if S.get("over"): return
	S.over = cause; showEnd(cause)
func showEnd(kind: String) -> void:
	var E := endInfo(kind)
	var sc = scenOf(S.get("scenario"))
	if not E.lose: S.finished = true; recordResult(sc, S.get("medal", 0))
	setSpeed(0); evOpen = null
	end_screen.emit(kind)
	sfx('soft' if E.lose else 'fanfare')
	save()
func endScreenData(kind: String) -> Dictionary:
	var E := endInfo(kind)
	var sc = scenOf(S.get("scenario"))
	var i := -1
	for k in CAMPAIGN.size():
		if CAMPAIGN[k].id == S.get("scenario"): i = k
	var nxt = CAMPAIGN[i + 1] if (i >= 0 and i + 1 < CAMPAIGN.size()) else null
	var canNext: bool = not E.lose and nxt != null and unlocked(i + 1)
	var days: int = S.day - S.get("startDay", 1)
	var score := 0 if E.lose else scoreOf(S.get("medal", 0))
	var tm := ("%dy " % (days / 36) if days / 36 else '') + "%dm" % ((days % 36) / 3)
	E.kicker = "%s · %s · %s" % [E.kicker, sc.name if sc else '', diff().label]
	E.stats = [['Time', tm], ['Best rating', "%d★" % (S.get("peakStars", 0) if S.get("peakStars") else stars())], ['Members', str(S.get("members", 0))], ['Net worth', fmt(netWorth())], ['Reputation', str(roundi(S.get("rep", 70.0)))], ['Score', '–' if E.lose else fmtInt(score)]]
	E.next = nxt.name if canNext else null
	E.nextId = nxt.id if canNext else null
	return E
## a medal along the way: carry on for the next one, or finish now
func showMedalCard(sc, m: int) -> void:
	var nextTier = sc.medals[m] if m < sc.medals.size() else null
	var i := CAMPAIGN.find(sc)
	var nxt = CAMPAIGN[i + 1] if (i >= 0 and i + 1 < CAMPAIGN.size()) else null
	var text := "You have earned %s at %s%s. " % [MEDAL[m].to_lower(), clubName(), (", and %s is unlocked" % nxt.name) if (m == 1 and nxt) else '']
	if nextTier: text += "For %s: %s." % [MEDAL[m + 1].to_lower(), ", ".join(nextTier.map(func(c): return c.t.to_lower()))]
	evQueue.push_front({ "key": 'medal', "icon": MEDAL_IC[m], "kicker": 'Objective reached', "title": "%s medal" % MEDAL[m], "text": text,
		"options": [
			{ "label": "Go for %s" % MEDAL[min(3, m + 1)].to_lower(), "sub": "You have until %s" % dateLabel(S.deadline), "apply": func(): return "Pushing on for %s." % MEDAL[min(3, m + 1)].to_lower() },
			{ "label": "Finish with %s" % MEDAL[m].to_lower(), "sub": 'See your result now', "apply": func():
				get_tree().create_timer(0.05).timeout.connect(func(): showEnd('finish'))
				return "You finished with %s." % MEDAL[m].to_lower() }] })
func timeLeftTxt() -> String:
	if not S.get("deadline"): return ''
	var d: float = max(0.0, S.deadline - S.day + (1 - S.clock / DAY_LEN))
	var months := d / MONTH_DAYS
	if months >= 12: return "%dy %dm left" % [int(months / 12), int(fmod(months, 12))]
	if months >= 1: return "%d month%s left" % [int(months), '' if int(months) == 1 else 's']
	return "%d day%s left" % [int(ceil(d)), '' if int(ceil(d)) == 1 else 's']
func unlockAch(id: String) -> void:
	if not S.get("ach"): S.ach = {}
	if S.ach.get(id): return
	S.ach[id] = Time.get_unix_time_from_system()
	steamCall('unlock', id)
	for a in ACH:
		if a[0] == id: toast('Achievement unlocked', a[1], a[2], '★'); break

# ---- title state, starting a park
var atTitle := false
var gameLive := false
func clubName() -> String: return S.get("parkName", 'Pine Hollow Golf Club') if S.get("parkName") else 'Pine Hollow Golf Club'
signal game_started
func resetRuntime() -> void:
	leaveRange(); RT.clear(); selRangeId = null; groups = []; away = []; earnLog.fill(0.0); vehicles = []; spotsHeld.clear(); rentalsOut = 0
	amenQ.clear(); amenIn = {}; visitors = []; teeQueue = []; lobbyQueue = []; deskQueue = []; deskIn = []
	for k in seatTaken: seatTaken[k] = {}
	litter = []; marks = []; marshals = []; keepers = []; actors = {}; evQueue = []; evOpen = null; splashes = []
	if designing: designing = false; draft = null; draftGeo = null
func newPark() -> void:
	var ach = S.get("ach", {})
	S = baseState(); S.ach = ach; S.ledger = newLedger()
	resetRuntime()
	S.design = defaultDesign(false, null, false); S.world = freshWorld('fresh')
	ensureDesign(); ensureWorld(); layout(); ensurePrices()
	starsC = stars(); lastStars = starsC; ensureRival()
func startScenario(id: String, d: String, nm: String) -> void:
	newPark(); setupScenario(id, d); ensurePrices()
	S.parkName = nm if nm else 'Pine Hollow Golf Club'; gameLive = true; atTitle = false
	setSpeed(1)
	game_started.emit(); ui_refresh.emit(); save(); sfx('chime')
	var sc = scenOf(id)
	toast('Welcome', S.parkName, 'Build whatever you like. Open Build to get started.' if sc.id == 'sandbox' else "%s · %s. Your objectives are in Park → Goals. Deadline: %s." % [sc.name, DIFF[d].label, dateLabel(S.deadline)], '⛳')

# ---------- Save / load ----------
const SLOTS := ['auto', '1', '2', '3']
func slotPath(s: String) -> String: return "%s/%s.json" % [SAVE_DIR, 'autosave' if s == 'auto' else 'slot' + s]
func readSlot(s: String):
	if not FileAccess.file_exists(slotPath(s)): return null
	var f := FileAccess.open(slotPath(s), FileAccess.READ)
	if not f: return null
	var d = JSON.parse_string(f.get_as_text())
	return d if (d is Dictionary and d.has("money")) else null
func writeSlot(s: String, json: String) -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(slotPath(s), FileAccess.WRITE)
	if f: f.store_string(json)
func deleteSlot(s: String) -> void:
	if FileAccess.file_exists(slotPath(s)): DirAccess.remove_absolute(slotPath(s))
func _saveJson() -> String:
	S.lastSave = Time.get_unix_time_from_system(); S.starsSaved = starsC
	return JSON.stringify(S)
func save() -> void:
	if not gameLive: return
	writeSlot('auto', _saveJson())
func saveToSlot(s: String) -> void:
	writeSlot(s, _saveJson())
	toast('Saved', "%s saved to slot %s" % [clubName(), s], dateLabel(), '✓'); sfx('chime')
## fold a save into a fresh state, mending what JSON turned into floats
func hydrate(d) -> bool:
	if not (d is Dictionary and d.has("money")): return false
	var base := baseState()
	var lvl: Dictionary = base.lvl.duplicate(); lvl.merge(d.get("lvl", {}), true)
	var st: Dictionary = base.staff.duplicate(); st.merge(d.get("staff", {}), true)
	base.merge(d, true)
	base.lvl = lvl; base.staff = st
	S = base
	for k in S.lvl.keys():
		S.lvl[k] = int(S.lvl[k])
		if not byId.has(k) or not byId[k].get("tab") or k == 'order': S.lvl.erase(k)
	for k in S.staff.keys(): S.staff[k] = int(S.staff[k])
	for k in ['day', 'members', 'trophies', 'aces', 'sales', 'buckets', 'rounds', 'goalIdx', 'redDays', 'repLow', 'medal', 'peakStars', 'startDay', 'deadline', 'modId', 'ejected', 'cleaned', 'repaired', 'deskJoins', 'lost']:
		if S.get(k) != null: S[k] = int(S[k])
	if S.get("world"):
		S.world.nextId = int(S.world.nextId)
		S.world.paths = S.world.paths.map(func(x): return int(x))
		S.world.land = S.world.land.map(func(x): return int(x))
		for o in S.world.objs:
			o.id = int(o.id); o.x = int(o.x); o.y = int(o.y)
			if o.get("r"):
				for k in o.r.lvl.keys(): o.r.lvl[k] = int(o.r.lvl[k])
				for k in o.r.staff.keys(): o.r.staff[k] = int(o.r.staff[k])
	_normDesign(S.get("design"))
	if not S.get("design") or not (S.design.get("holes") is Array): S.design = defaultDesign(true, null, false)
	if S.get("event"): S.event.day = int(S.event.day); S.event.left = int(S.event.left)
	if S.get("evNext"): S.evNext.day = int(S.evNext.day)
	return true
func applySave(d) -> void:
	var ach: Dictionary = S.get("ach", {}).duplicate()
	ach.merge(d.get("ach", {}), true)
	S = baseState(); hydrate(d); S.ach = ach
	resetRuntime()
	ensureDesign(); ensureWorld(); ensurePrices()
	if not S.get("ledger"): S.ledger = newLedger()
	layout()
	starsC = stars(); lastStars = starsC; ensureRival()
	game_started.emit(); ui_refresh.emit()
func loadSlot(s: String) -> bool:
	var d = readSlot(s)
	if not d: return false
	applySave(d); gameLive = true; atTitle = false
	setSpeed(1)
	toast('Loaded', clubName(), "%s · %s" % [dateLabel(), fmt(S.money)], '✓'); sfx('open')
	return true

# ---------- Settings ----------
const SETTINGS_PATH := "user://settings.json"
var SETTINGS := { "uiScale": 1.0, "master": 0.9, "music": 0.6, "ambience": 0.8, "sfx": 0.9, "track": 'auto', "events": 'normal', "camSpeed": 1.0, "edgePan": true, "fullscreen": false, "campaign": {} }
signal settings_changed
func loadSettings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH): return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if d is Dictionary: SETTINGS.merge(d, true)
func saveSettings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(SETTINGS))
	settings_changed.emit()

# ---------- Toasts and sound requests ----------
func toast(kicker: String, title: String, text: String, icon := '★') -> void: toast_shown.emit(kicker, title, text, icon)
## a sound for the audio player: pos (world) makes it positional and only audible on screen
func sfx(nm: String, pos = null, args := [], delay := 0.0, vol := 1.0) -> void:
	sound.emit(nm, { "pos": pos, "args": args, "delay": delay, "vol": vol })
signal money_popped(v, amount)
func moneyPop(v, amount: float) -> void: money_popped.emit(v, amount)

# ---------- Achievements (API names match the Steamworks setup) ----------
func staffCount() -> int: return staffTotal()
var ACH: Array = []
func _build_ach() -> void:
	ACH = [
		['ACH_MEDAL_FIRST', 'On the podium', 'Earn a medal in any campaign scenario.', func(): return false],
		['ACH_MEDAL_GOLD', 'Gold standard', 'Earn a gold medal in a campaign scenario.', func(): return false],
		['ACH_HARD_MEDAL', 'Hard as nails', 'Earn a medal on Hard difficulty.', func(): return false],
		['ACH_CAMPAIGN_DONE', 'Club legend', 'Earn a medal in every campaign scenario.', func(): return false],
		['ACH_CAMPAIGN_GOLD', 'Grand slam', 'Earn gold in every campaign scenario.', func(): return false],
		['ACH_FIRST_SALE', 'Open for business', 'Sell something in the pro shop.', func(): return S.get("sales", 0) >= 1],
		['ACH_FIRST_BUCKET', 'First bucket', 'Sell your first bucket of balls.', func(): return S.get("buckets", 0) >= 1],
		['ACH_BAYS_10', 'Busy tee line', 'Run a range with 10 bays.', func(): return bays() >= 10],
		['ACH_BAYS_38', 'Wall to wall', 'Build the range out to all 38 bays.', func(): return bays() >= MAX_BAYS],
		['ACH_PICKER_CART', 'Ride-on', 'Give a ball picker a cart.', func(): return L('cart') >= 1],
		['ACH_FIRST_ROUND', 'Out on the course', 'See your first round completed.', func(): return S.get("rounds", 0) >= 1],
		['ACH_BACK_NINE', 'Eighteen', 'Build the back nine.', func(): return L('back9') >= 1],
		['ACH_PAR_72', 'Championship length', 'Stretch the course to par 72.', func(): return L('back9') and totalPar() >= 72],
		['ACH_SIGNATURE', 'Signature hole', 'Max out one hole’s rating.', func():
			for i in S.holes.size():
				if holeRating(i) >= HOLE_MAX_RATING: return true
			return false],
		['ACH_ACE', 'Ace!', 'Witness a hole-in-one.', func(): return S.get("aces", 0) >= 1],
		['ACH_ACES_10', 'Lucky course', 'Witness 10 hole-in-ones.', func(): return S.get("aces", 0) >= 10],
		['ACH_RESTAURANT', 'Table for four', 'Open the restaurant.', func(): return venueOpen('resto')],
		['ACH_TERRACE', 'Sun’s out', 'Build the terrace.', func(): return L('terrace') >= 1],
		['ACH_STAFF_25', 'Big employer', 'Employ 25 staff.', func(): return staffCount() >= 25],
		['ACH_PACKED', 'Packed house', 'Have 100 visitors in the park at once.', func(): return visitors.size() >= 100],
		['ACH_NIGHT_OWL', 'Night owl', 'Have 10 golfers on the range after dark.', func(): return isDark() and rangeSum().players >= 10],
		['ACH_RAIN', 'Rain or shine', 'Have 8 golfers on the range in the rain.', func(): return S.wx == 'rain' and rangeSum().players >= 8],
		['ACH_RATING_150', 'Destination course', 'Reach a course rating of 150.', func(): return rating18() >= 150],
		['ACH_MILLION', 'Millionaire', 'Earn $1M in total.', func(): return S.total >= 1e6],
		['ACH_BILLION', 'Golf mogul', 'Earn $1B in total.', func(): return S.total >= 1e9],
		['ACH_TROPHY', 'Champion', 'Win a trophy at the County Championship.', func(): return S.get("trophies", 0) >= 1],
		['ACH_DYNASTY', 'Dynasty', 'Win 5 County Championship trophies.', func(): return S.get("trophies", 0) >= 5],
		['ACH_MARSHAL', 'Order on the course', 'Have a marshal send a troublemaker home.', func(): return S.get("ejected", 0) >= 1],
		['ACH_SPOTLESS', 'Spotless', 'Pick up 250 pieces of litter.', func(): return S.get("cleaned", 0) >= 250],
		['ACH_MEMBERS_50', 'Members only', 'Have 50 members.', func(): return S.get("members", 0) >= 50],
		['ACH_TEES', 'Something for everyone', 'Build all five tee sets.', func(): return teeSets().size() >= 5],
		['ACH_SHORTC', 'Short and sweet', 'Open a par-3 short course.', func(): return hasObj('shortc')],
		['ACH_ELITE', 'Scratch club', 'Welcome 25 elite handicap golfers in one month.', func(): return (S.hcpLog.month.get("elite", 0) if S.get("hcpLog") else 0) >= 25],
		['ACH_ACADEMY', 'Learning centre', 'Open a golf academy with a teaching pro.', func(): return hasObj('academy') and N('coach') > 0],
		['ACH_FIVE_STAR', 'Five-star club', 'Reach a 5-star rating.', func(): return starsC >= 5],
		['ACH_ISLAND', 'Island green', 'Surround a green with water.', func(): return false],
		['ACH_EVENT', 'Event host', 'Host a successful event.', func(): return S.get("eventsDone", {}).size() >= 1],
		['ACH_SCENARIO', 'Mission accomplished', 'Complete every goal in a scenario.', func(): return goalList().size() > 0 and S.get("goalIdx", 0) >= goalList().size()],
		['ACH_RESCUE', 'Turnaround', 'Complete the Pine Hollow Rescue.', func(): return S.get("scenario") == 'rescue' and S.get("goalIdx", 0) >= GOALS.rescue.size()],
	]
func checkAchievements() -> void:
	if not S.get("ach"): S.ach = {}
	for a in ACH:
		if S.ach.get(a[0]): continue
		if not a[3].call(): continue
		S.ach[a[0]] = Time.get_unix_time_from_system()
		toast('Achievement unlocked', a[1], a[2], '★')
		sfx('fanfare')
		steamCall('unlock', a[0])
func syncAchievementsToSteam() -> void:
	for id in S.get("ach", {}).keys(): steamCall('unlock', id)

# ---------- Hole-in-ones ----------
signal confetti_burst(pos)
func holeInOne(p, h: int) -> void:
	emote(p, 35, 'delighted', LINES.ace, 1)
	S.aces = S.get("aces", 0) + 1
	toast('Hole-in-one!', "%s aces hole %d" % [p.name, h + 1], "%d yards, one swing. Ace number %d at %s." % [holeYards(h), S.aces, clubName()], '1')
	sfx('fanfare')
	steamCall('timeline', 'ace', "Hole-in-one on hole %d" % (h + 1))
	confetti_burst.emit(hPt(h, greenT(h)))

# ---------- Steam (GodotSteam, when the addon is installed) ----------
var steam = null
func _init_steam() -> void:
	if Engine.has_singleton("Steam"):
		steam = Engine.get_singleton("Steam")
		var r = steam.call("steamInitEx", false) if steam.has_method("steamInitEx") else (steam.call("steamInit") if steam.has_method("steamInit") else null)
		if r is Dictionary and int(r.get("status", 1)) != 0: steam = null
func steamCall(fn: String, a = null, b = null):
	if steam == null: return null
	match fn:
		'unlock':
			steam.call("setAchievement", a); steam.call("storeStats")
		'presence':
			steam.call("setRichPresence", "steam_display", "#Status"); steam.call("setRichPresence", "status", str(a))
		'info':
			return { "available": true, "name": steam.call("getPersonaName") }
		'timeline':
			if steam.has_method("addTimelineEvent"): steam.call("addTimelineEvent", "steam_marker", str(b), "", 0, 0.0, 0.0, 0)
	return null
func updatePresence() -> void:
	steamCall('presence', "Day %d at %s · %s earned · course rating %d" % [S.day, clubName(), fmt(S.total), rating18() if L('back9') else rating9()])

# =====================================================================================
# Handicaps
# =====================================================================================
const HCP_BANDS := [
	{ "k": 'elite',  "label": 'Elite',  "lo": 0.0,  "hi": 5.4,  "share": 0.04, "spend": 1.45, "priceE": 0.45, "pref": 136, "color": '#c9940f', "wants": 'A long, testing 18 holes in championship condition. Not fussy about price.' },
	{ "k": 'low',    "label": 'Low',    "lo": 5.5,  "hi": 12.4, "share": 0.15, "spend": 1.2,  "priceE": 0.75, "pref": 126, "color": '#2c4a6e', "wants": 'A proper challenge, 18 holes, good greens and a practice putting green.' },
	{ "k": 'mid',    "label": 'Mid',    "lo": 12.5, "hi": 20.4, "share": 0.31, "spend": 1.0,  "priceE": 1.0,  "pref": 115, "color": '#1f6b3a', "wants": 'A fair, varied course and a clubhouse to relax in afterwards.' },
	{ "k": 'high',   "label": 'High',   "lo": 20.5, "hi": 36.0, "share": 0.35, "spend": 0.92, "priceE": 1.25, "pref": 103, "color": '#a0522d', "wants": 'A forgiving course, not too much water, and good value.' },
	{ "k": 'novice', "label": 'Novice', "lo": 36.1, "hi": 54.0, "share": 0.15, "spend": 0.85, "priceE": 1.5,  "pref": 90,  "color": '#7a6a9a', "wants": 'Lessons, a short game area, rental clubs and an easy course. Very price-conscious.' },
]
var BAND := {}
func _build_bands() -> void:
	for b in HCP_BANDS: BAND[b.k] = b
func bandOf(h: float) -> Dictionary:
	for b in HCP_BANDS:
		if h <= b.hi: return b
	return HCP_BANDS[HCP_BANDS.size() - 1]
func skillOfHcp(h: float) -> float: return min(0.56, 0.02 + 0.5 * pow(max(0.0, h) / 54.0, 0.9))
func sampleHcp(b) -> float: return round((b.lo + (b.hi - b.lo) * pow(randf(), 0.75)) * 10) / 10.0
func fmtHcp(h: float) -> String: return ('+%.1f' % -h) if h < 0 else ('%.1f' % h)
## the course as a handicap golfer sees it: course rating and slope
func courseStats(set_ := 'yellow'):
	var n := courseHoles()
	if not n: return null
	var holes: int = min(18, n)
	var par := 0; var yards := 0; var rating := 0.0; var haz := 0.0
	for i in holes:
		par += S.holes[i].par; yards += teeYards(i, set_); rating += holeRating(i)
		var p = liveGeo.info[i].parts
		haz += p.water * 1.4 + p.bunkers + p.dunes * 0.6 + p.trees * 0.4
	var perHole := yards / float(holes)
	var avgR := rating / holes
	var avgHaz := haz / holes
	var slope := roundi(max(55.0, min(155.0, 78 + (perHole - 260) * 0.09 + avgHaz * 7 + avgR * 2.2 + (4 if S.cond < 70 else 0))))
	var cr = round((par + (slope - 113) / 113.0 * holes * 0.55 + (perHole - 340) / 340.0 * holes * 0.35) * 10) / 10.0
	return { "holes": holes, "par": par, "yards": yards, "slope": slope, "cr": cr }
var csCache = null
var csT := 0.0
func courseSlope(v) -> int:
	if csCache == null: return 113
	var k: String = v.get("tee", 'yellow') if (v and v.get("tee")) else 'yellow'
	var c = csCache.get(k, csCache.get("yellow"))
	return c.slope if c else 113
## how well the park suits each band (about 0.2 to 1.6)
func bandFit(b, forCourse: bool) -> float:
	var cs = null
	if csCache != null: cs = csCache.get(chooseTee((b.lo + b.hi) / 2), csCache.get("yellow"))
	var f := 1.0
	if forCourse:
		if not cs: return 0.0
		if S.get("hcpLimit") and b.lo > S.hcpLimit: return 0.0
		var d: float = (cs.slope - b.pref) / 24.0
		f = 0.35 + 0.95 * exp(-d * d)
		var full := courseHoles() >= 18
		var putt := 1.1 if hasObj('putt') else 1.0
		if b.k == 'elite': f *= (1.25 if full else 0.55) * (1.15 if S.cond >= 85 else (0.7 if S.cond < 70 else 1.0)) * putt
		if b.k == 'low': f *= (1.15 if full else 0.8) * putt
		if b.k == 'mid': f *= 1.1 if (L('barRoom') or L('resto')) else 1.0
		if b.k == 'novice': f *= (1.15 if cs.holes <= 9 else 0.9) * (1.1 if (S.get("sup") and S.sup.get("rental", 0) > 0) else 0.85)
	else:
		f = { "elite": 0.6, "low": 0.8, "mid": 1.0, "high": 1.15, "novice": 1.2 }[b.k] * ((1.15 if (b.k == 'novice' or b.k == 'high') else 1.05) if hasObj('short') else 1.0)
	if b.k == 'novice': f *= 1.3 if (hasObj('academy') and N('coach')) else 0.85
	var fo = S.get("hcpFocus")
	if fo and fo != 'all': f *= (1 + 0.12 * min(5, L('market') + 1)) if fo == b.k else 0.9
	return f
func bandWeights(forCourse: bool) -> Array:
	var r := ratioOf('fee9') if forCourse else ratioOf('bucket')
	return HCP_BANDS.map(func(b): return [b, b.share * modMult('band_' + b.k) * bandFit(b, forCourse) * valueDemand(1 + (r - 1) * b.priceE)])
func hcpDemand(forCourse: bool) -> float:
	var t := 0.0
	for x in bandWeights(forCourse): t += x[1]
	return t / 0.95
func _pickWeighted(w: Array, fallback):
	var tot := 0.0
	for x in w: tot += x[1]
	var r := randf() * tot
	for x in w:
		r -= x[1]
		if r <= 0: return x[0]
	return fallback
func pickBand(forCourse: bool): return _pickWeighted(bandWeights(forCourse), BAND.mid)
## give a new visitor a handicap (members and event players come from the better bands)
func assignHcp(v, forceType = null) -> void:
	var b
	if forceType == 'member': b = [BAND.low, BAND.mid, BAND.mid, BAND.high][randi() % 4]
	elif forceType == 'expert': b = BAND.elite if randf() < 0.35 else BAND.low
	else: b = pickShortBand() if v.plan[0] == 'shortc' else pickBand(v.plan.has('course'))
	if S.get("hcpLimit") and v.plan.has('course') and b.lo > S.hcpLimit: b = BAND.mid
	v.hcp = sampleHcp(b); v.band = b.k
	if not forceType: v.type = 'expert' if v.hcp < 10 else ('beginner' if v.hcp > 36 else 'regular')
	v.skill = skillOfHcp(v.hcp)
	if not S.get("hcpLog"): S.hcpLog = { "month": {}, "last": {} }
	S.hcpLog.month[b.k] = S.hcpLog.month.get(b.k, 0) + 1
func hcpRoundMood(v) -> Dictionary:
	var s := courseSlope(v)
	var h: float = v.get("hcp", 18.0) if v.get("hcp") != null else 18.0
	if h < 12 and s < 108: return { "d": -7, "lines": ['Too easy for me.', 'Bit of a pitch and putt.'] }
	if h < 12 and s >= 128 and S.cond >= 80: return { "d": 7, "lines": ['Proper test of golf.', 'Championship stuff.'] }
	if h > 28 and s > 128: return { "d": -8, "lines": ['Way too hard…', 'Lost all my balls.'] }
	if h > 28 and s < 106: return { "d": 5, "lines": ['Nice and friendly.', 'Perfect for my game.'] }
	return { "d": 0, "lines": null }
func hcpTick(dt: float) -> void:
	csT -= dt
	if csT <= 0 or csCache == null:
		csT = 3.0
		if courseHoles():
			csCache = {}
			for k in teeSets(): csCache[k] = courseStats(k)
		else: csCache = null
func setHcpLimit(v: int) -> void: S.hcpLimit = v; sfx('tap'); save()
func setHcpFocus(k: String) -> void: S.hcpFocus = k; sfx('tap'); save()

# =====================================================================================
# Tee sets: coloured tees on every hole. Golfers play from the tees that suit them.
# =====================================================================================
const TEE_SETS := [
	{ "k": 'white',  "label": 'White',  "t": -0.09, "color": '#f5f5f0', "perHole": 600, "forB": 'elite and low handicappers', "blurb": 'Championship tees behind the yellows. The full test.' },
	{ "k": 'yellow', "label": 'Yellow', "t": 0.0,   "color": '#f2c14e', "perHole": 0,   "forB": 'most club golfers', "blurb": 'The standard tees, built with every hole.' },
	{ "k": 'blue',   "label": 'Blue',   "t": 0.06,  "color": '#2c6fd6', "perHole": 350, "forB": 'mid and high handicappers', "blurb": 'A little forward of the yellows.' },
	{ "k": 'red',    "label": 'Red',    "t": 0.13,  "color": '#e8432e', "perHole": 350, "forB": 'high handicappers', "blurb": 'Forward tees that take the long carries out of play.' },
	{ "k": 'orange', "label": 'Orange', "t": 0.24,  "color": '#ff8a3d', "perHole": 300, "forB": 'novices and juniors', "blurb": 'Short tees for beginners and juniors.' },
]
var TEE := {}
func _build_tees() -> void:
	for t in TEE_SETS: TEE[t.k] = t
func teeSets() -> Array:
	var ts: Array = S.design.get("teeSets", []) if S.get("design") else []
	return TEE_SETS.filter(func(t): return t.k == 'yellow' or ts.has(t.k)).map(func(t): return t.k)
func teePosFor(i: int, set_ = null) -> Vector2: return hPt(i, TEE[set_ if set_ else 'yellow'].t)
func teeYards(i: int, set_ = null) -> int:
	var t0: float = TEE[set_ if set_ else 'yellow'].t
	var len_ := 0.0
	var p := hPt(i, t0)
	for k in range(1, 25):
		var q := hPt(i, t0 + (1 - t0) * k / 24.0)
		len_ += p.distance_to(q); p = q
	return roundi(len_ * YARDS_PER_UNIT / 5) * 5
func prefTeeIdx(h: float) -> float:
	if h < 5.5: return 0.0
	if h < 10: return 0.6
	if h < 20.5: return 1.2
	if h < 28: return 2.0
	if h <= 36: return 3.0
	return 4.0
func teeIndex(k: String) -> int:
	for i in TEE_SETS.size():
		if TEE_SETS[i].k == k: return i
	return 1
func chooseTee(h: float) -> String:
	var want := prefTeeIdx(h)
	var best := 'yellow'
	var bd := 1e9
	for k in teeSets():
		var d: float = abs(teeIndex(k) - want)
		if d < bd - 1e-9: bd = d; best = k
	return best
func teeMood(v) -> Dictionary:
	var want := prefTeeIdx(v.hcp if v.get("hcp") != null else 18.0)
	var d := teeIndex(v.get("tee", 'yellow') if v.get("tee") else 'yellow') - want
	if abs(d) <= 0.7: return { "d": 3, "lines": null }
	if d <= -1.5: return { "d": -6, "lines": ['These tees are far too long for me.', 'Is there not a forward tee?'] }
	if d >= 1.5: return { "d": -4, "lines": ['Too short from up here.', 'Not much of a test from these tees.'] }
	return { "d": 0, "lines": null }
func teeSetCost(k: String) -> float: return TEE[k].perHole * max(1, courseHoles() if courseHoles() else builtIdx().size())
func buildTeeSet(k: String) -> void:
	var T = TEE[k]
	var c := teeSetCost(k)
	if not S.get("design") or S.design.get("teeSets", []).has(k) or S.money < c: return
	spend(c, 'build'); S.invested = S.get("invested", 0.0) + c
	if not S.design.get("teeSets"): S.design.teeSets = []
	S.design.teeSets.append(k)
	csCache = null; sfx('chime')
	toast('Course', "%s tees built" % T.label, "%s tee boxes on every hole. %s will play from them." % [T.label, T.forB.capitalize().split(' ')[0] + T.forB.substr(T.forB.find(' '))], '⛳')
	design_changed.emit(); ui_refresh.emit(); save()

# =====================================================================================
# The par-3 short course: six little holes in one plot
# =====================================================================================
func shortcHoles(o) -> Array:
	var px: float = o.x * TILE
	var py: float = o.y * TILE
	var out := []
	for k in 6:
		var col := k % 3
		var row := k / 3
		var x0 := px + 24 + col * 128
		var y0 := py + 24 + row * 116
		var flip := (k + row) % 2
		out.append({ "tee": Vector2(x0 + (92 if flip else 6), y0 + 82), "green": Vector2(x0 + (14 if flip else 86), y0 + 14) })
	return out
func shortcPos(o, slot, k: float) -> Vector2:
	var hs := shortcHoles(o)
	var seg: float = min(5.999, k * 6)
	var h = hs[int(floor(seg))]
	var f := fmod(seg, 1.0)
	var sl: int = slot if slot else 0
	var j := Vector2((sl % 3 - 1) * 5, ((sl / 3) % 3 - 1) * 4)
	var w: float = min(1.0, f / 0.85)
	return h.tee.lerp(h.green, w) + j
const SHORTC_W := { "elite": 0.1, "low": 0.35, "mid": 0.8, "high": 1.4, "novice": 2.2 }
var shortcAcc := 0.0
func shortcDemand() -> float:
	if amenFor('shortc').is_empty() or isDark() or isFrost() or eventRunning(): return 0.0
	return amenFor('shortc').size() * arrivalBase() * 0.3 * seasonDemand() * W_().course * parkAppeal() * starAppeal() * valueDemand(ratioOf('shortc'))
func shortcTick(dt: float) -> void:
	shortcAcc += shortcDemand() * dt
	while shortcAcc >= 1:
		shortcAcc -= 1
		arriveVisitor(['shortc', 'club'] if (clubOK() and randf() < 0.35) else ['shortc'])
func pickShortBand():
	var r := ratioOf('shortc')
	return _pickWeighted(HCP_BANDS.map(func(b): return [b, b.share * SHORTC_W[b.k] * valueDemand(1 + (r - 1) * b.priceE)]), BAND.high)

# =====================================================================================
# Suggested footpaths: after you place something, find the cheapest path from its door
# to the network (or a car park) and offer it as a ghost.
# =====================================================================================
func linkLot(o) -> bool:
	var f = fieldOf('OBJ:%s' % o.id)
	for b in objs():
		if OBJ[b.type].get("free") or b.type == 'lot': continue
		var d = doorOf(b)
		if d.ty < GH and f[tIdx(d.tx, d.ty)] >= 0: return true
	return false
func needsPath() -> Array:
	var out := []
	var buildings := objs().filter(func(o): return not OBJ[o.type].get("free") and o.type != 'lot')
	for o in buildings:
		if not connected('OBJ:%s' % o.id):
			out.append({ "o": o, "label": (rangeName(o) if (o.type == 'range' and rangeObjs().size() > 1) else OBJ[o.type].label).to_lower() })
	if buildings.size():
		for o in objs():
			if o.type == 'lot' and not linkLot(o): out.append({ "o": o, "label": 'car park' })
	if courseHoles() > 0 and not courseOK() and hasObj('club'): out.append({ "tee": true, "o": null, "label": 'first tee' })
	return out
func pathable(i: int) -> bool: return isPath[i] == 1 or (occ[i] == 0 and ownsTile(i % GW, i / GW))
func targetsFor(src) -> PackedByteArray:
	var T := PackedByteArray(); T.resize(GW * GH)
	for l in objs():
		if l.type != 'lot' or is_same(l, src): continue
		var f = fieldOf('OBJ:%s' % l.id)
		for i in f.size():
			if f[i] >= 0: T[i] = 1
		var e = doorOf(l)
		if e.ty >= 0: T[tIdx(e.tx, e.ty)] = 1
	if src and src.type == 'lot':
		for o in objs():
			if not OBJ[o.type].get("free") and o.type != 'lot':
				var d = doorOf(o)
				if d.ty < LAND_ROWS: T[tIdx(d.tx, d.ty)] = 1
	return T
## a tiny binary heap of [cost, state]
class MinHeap:
	var a: Array = []
	func push(d: float, s: int) -> void:
		a.append([d, s])
		var i := a.size() - 1
		while i:
			var p := (i - 1) >> 1
			if a[p][0] <= a[i][0]: break
			var t = a[p]; a[p] = a[i]; a[i] = t; i = p
	func pop() -> Array:
		var top = a[0]
		var last = a.pop_back()
		if a.size():
			a[0] = last
			var i := 0
			while true:
				var l := 2 * i + 1
				var r := l + 1
				var m := i
				if l < a.size() and a[l][0] < a[m][0]: m = l
				if r < a.size() and a[r][0] < a[m][0]: m = r
				if m == i: break
				var t = a[m]; a[m] = a[i]; a[i] = t; i = m
		return top
	func size() -> int: return a.size()
## cheapest route over the tile grid: existing path is almost free, fairways cost extra, turns a little
func findPath(starts: Array, T: PackedByteArray):
	var NN := GW * GH
	var dist := PackedFloat32Array(); dist.resize(NN * 4); dist.fill(1e9)
	var prev := PackedInt32Array(); prev.resize(NN * 4); prev.fill(-1)
	var tileCost := PackedFloat32Array(); tileCost.resize(NN); tileCost.fill(-1)
	var costOf := func(i: int) -> float:
		if tileCost[i] >= 0: return tileCost[i]
		var c := 0.05
		if not isPath[i]:
			var p := tileC(i % GW, i / GW)
			c = 1.0 + (3.0 if holeNear(p.x, p.y, 0) >= 0 else 0.0)
		tileCost[i] = c
		return c
	var heap := MinHeap.new()
	for s in starts:
		var i := tIdx(s.tx, s.ty)
		if not pathable(i): continue
		for d in 4:
			var st := i * 4 + d
			dist[st] = costOf.call(i); heap.push(dist[st], st)
	var DX := [1, -1, 0, 0]
	var DY := [0, 0, 1, -1]
	var end := -1
	var guard := 0
	while heap.size() and guard < 400000:
		guard += 1
		var top := heap.pop()
		var d: float = top[0]
		var st: int = top[1]
		if d > dist[st]: continue
		var i := st >> 2
		var dir := st & 3
		if T[i]: end = st; break
		var x := i % GW
		var y := i / GW
		for k in 4:
			var nx: int = x + DX[k]
			var ny: int = y + DY[k]
			if nx < 0 or ny < 0 or nx >= GW or ny >= LAND_ROWS: continue
			var j := ny * GW + nx
			if not pathable(j) and not T[j]: continue
			var nd: float = d + costOf.call(j) + (0.35 if k != dir else 0.0)
			var ns := j * 4 + k
			if nd < dist[ns]: dist[ns] = nd; prev[ns] = st; heap.push(nd, ns)
	if end < 0: return null
	var seen := {}
	var fresh := []
	var st2 := end
	while st2 >= 0:
		var i := st2 >> 2
		if not seen.has(i):
			seen[i] = true
			if not isPath[i] and occ[i] == 0: fresh.append(i)
		st2 = prev[st2]
	fresh.reverse()
	return { "tiles": fresh, "cost": fresh.size() * PATH_COST }
func suggestFor(need) -> Dictionary:
	var starts := []
	if need.get("tee"):
		var t: Vector2 = withGeo(liveGeo, func(): return teePos(0))
		var c = tileOf(t.x, t.y)
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var tx: int = c.tx + dx
				var ty: int = c.ty + dy
				if tx >= 0 and ty >= 0 and tx < GW and ty < LAND_ROWS and pathable(tIdx(tx, ty)): starts.append({ "tx": tx, "ty": ty })
	else: starts = [doorOf(need.o)]
	var T := targetsFor(need.o)
	if T.count(1) == 0:
		return { "fail": 'Place a building first, then connect the car park to it.' if (need.o and need.o.type == 'lot') else 'Place a car park on the road first: paths have to lead back to one.' }
	var r = findPath(starts, T)
	if r == null: return { "fail": "No route: the %s's door is blocked, or the land in between isn't yours. Buy land or move things out of the way." % need.label }
	return r
## build a suggested path (the view keeps the suggestion as its current tool)
func buildPathTiles(tiles: Array, label: String) -> Dictionary:
	var ts := tiles.filter(func(i): return not isPath[i] and occ[i] == 0)
	var cost: float = ts.size() * PATH_COST
	if S.money < cost: sfx('soft'); return { "ok": false, "msg": "Not enough cash: this path costs %s." % fmt(cost) }
	spend(cost, 'build'); S.invested = S.get("invested", 0.0) + cost
	for i in ts:
		if not S.world.paths.has(i): S.world.paths.append(i)
	rebuildWorld(); sfx('kaching')
	toast('Footpath', "Path to the %s built" % label, "%d tiles for %s." % [ts.size(), fmt(cost)], '⚒')
	ui_refresh.emit(); save()
	return { "ok": true }

# =====================================================================================
# Startup and the main loop
# =====================================================================================
var clockT := 0.0
var _saveT := 0.0
var _achT := 0.0
var _presT := 15.0
var _uiT := 0.0
signal ui_tick   # four times a second: lists, stats and windows refresh on this
func _ready() -> void:
	randomize()
	_build_all()
	loadSettings()
	_init_steam()
	var d = readSlot('auto')
	if d: applySave(d); gameLive = true
	else:
		S.design = defaultDesign(false, null, false); S.world = freshWorld('fresh')
		ensureDesign(); ensureWorld(); ensurePrices()
		if not S.get("ledger"): S.ledger = newLedger()
		layout(); starsC = stars(); lastStars = starsC; ensureRival()
	atTitle = true
	setSpeed(1)
	get_tree().create_timer(3.0).timeout.connect(syncAchievementsToSteam)
func _build_all() -> void:
	_build_bands(); _build_tees()
	TER.h.resize(TN); TER.w.resize(TN)
	for fn in ['_build_upgrades', '_build_corr', '_build_parcels', '_build_prices', '_build_amen', '_build_venues', '_build_events', '_build_goals', '_build_random_events', '_build_campaign', '_build_ach']:
		if has_method(fn): call(fn)
	S = baseState()
func _process(delta: float) -> void:
	var dt: float = min(delta, 0.25)
	var simDt := dt * warp
	var rem := simDt
	var t0 := Time.get_ticks_usec()
	while rem > 0:
		var st: float = min(rem, 0.1)
		tick(st); rem -= st
	var t1 := Time.get_ticks_usec()
	clockT += simDt
	terraTick(dt)
	updateActors(clockT)
	prof('sim.tick', t1 - t0); prof('sim.other', Time.get_ticks_usec() - t1)
	_uiT += dt; _saveT += dt; _achT += dt; _presT += dt
	if _uiT > 0.25:
		_uiT = 0; var t2 := Time.get_ticks_usec(); ui_tick.emit(); prof('ui_tick', Time.get_ticks_usec() - t2)
	if _saveT > 5: _saveT = 0; save()
	if _achT > 1: _achT = 0; checkAchievements()
	if _presT > 20: _presT = 0; updatePresence()

# ---------- small helpers for the interface ----------
func playing() -> Array: return groups
func clock(c: float) -> String: return clockOf(c)
## visitors still in the park (not driving in or gone)
func here() -> Array: return visitors.filter(func(v): return v.state != 'gone' and v.state != 'drive')
## what the interface shows as wages, upkeep and interest per day
func costsPerDay() -> float: return wagesPerDay() + upkeepPerDay() + interestPerDay()

# ---------- a light profiler for --perf runs: microseconds per section ----------
var PROF := {}
func prof(k: String, us: int) -> void: PROF[k] = PROF.get(k, 0) + us
