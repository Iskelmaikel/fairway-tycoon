class_name Hover
extends RefCounted
## What the tooltip says about whatever is under the mouse (BBCode).

const STATE_LABEL := { "walk": 'walking', "queue": 'waiting', "filling": 'filling a bucket', "play": 'hitting balls', "venue": 'inside', "locker": 'changing', "idle": 'thinking', "desk": 'checking in at the desk', "amen": 'practising' }
const PLAN_NAME := { "range": 'Range', "course": 'Course', "club": 'Clubhouse', "checkin": 'Check in', "putt": 'Putting green', "short": 'Short game', "lesson": 'Lesson', "shortc": 'Short course' }
const MARK_NAME := { "branch": 'Fallen branch', "bay": 'Broken bay', "furniture": 'Broken furniture', "green": 'Damaged green', "fairway": 'Divots in the fairway', "tee": 'Damaged tee box' }

static func gold(t: String) -> String: return "[color=#f2c14e]%s[/color]" % t
static func bar(pct: float, col: String) -> String:
	var n := clampi(roundi(pct * 20), 0, 20)
	return "[color=%s]%s[/color][color=#ffffff33]%s[/color]" % [col, '▬'.repeat(n), '▬'.repeat(20 - n)]
static func planLabel(v) -> String:
	var out := []
	for i in v.plan.size():
		var n: String = PLAN_NAME.get(v.plan[i], v.plan[i])
		out.append(gold(n) if i == v.step else n)
	return ' → '.join(out)
static func ordinal(n: int) -> String: return ['st', 'nd', 'rd'][n] if n < 3 else 'th'

static func html(g, wx: float, wy: float) -> String:
	var r: float = 12 / clampf(g.view.cam.s, 0.6, 1.6)
	for m in Sim.marshals:
		if Vector2(m.x - wx, m.y - 4 - wy).length() < r:
			var j = m.get("job")
			var what := ''
			if m.state == 'patrol': what = 'On patrol'
			elif j:
				if j.kind == 'person': what = "%s %s%s" % ['Sending' if m.state == 'work' else 'Heading for', j.v.name, ' home' if m.state == 'work' else '']
				elif j.kind == 'litter': what = 'Picking up litter'
				else: what = 'Repairing damage'
			return "[b]Marshal[/b]%s\n%s" % [' · in a cart' if m.get("cart") else '', what]
	for k in Sim.marks:
		if Vector2(k.x - wx, k.y - wy).length() < r:
			return "[b]%s[/b]%s\n%s%s" % [MARK_NAME.get(k.type, 'Damage'), (" · hole %d" % (k.hole + 1)) if k.get("hole") != null else '', 'A marshal is on the way' if k.get("by") else 'Waiting for repair', '\nThe bay is out of order' if k.type == 'bay' else '']
	for l in Sim.litter:
		if Vector2(l.x - wx, l.y - wy).length() < r * 0.7: return "[b]Litter[/b]\nMakes the park less inviting%s" % ('\nA marshal is on the way' if l.get("by") else '')
	# people first
	var best = null
	var bd := r
	for v in Sim.visitors:
		if v.state == 'drive' or v.state == 'golf': continue
		var d := Vector2(v.x - wx, v.y - 4 - wy).length()
		if d < bd: bd = d; best = v
	if best:
		var v = best
		var line: String = STATE_LABEL.get(v.state, '')
		if v.state == 'venue': line = "at the %s" % Sim.VENUE_LABEL.get(v.venue, 'clubhouse').to_lower()
		var wait := ''
		if v.state == 'queue' and v.get("patience"):
			var left: float = max(0.0, 1 - v.wait / v.patience)
			wait = "\n%s\nPatience %d s" % [bar(left, '#7fe09a' if left > 0.5 else ('#f2c14e' if left > 0.25 else '#e8432e')), int(ceil(v.patience - v.wait))]
		var st = Sim.STANDING[v.standing]
		var stl := "%s%s golfer%s" % [(st.icon + ' ') if st.icon else '', st.label, (" · %d offence%s" % [v.offenses, 's' if v.offenses > 1 else '']) if v.get("offenses") else '']
		var mo: float = Sim.moodOf(v)
		var mk: String = Sim.moodKind(mo)
		var gt: String = Sim.GTYPES[v.type].label if Sim.GTYPES.has(v.type) else ''
		return "[b]%s[/b] · %s%s\n%s\n%s\n%s%s\n%s\nMood %d%% · %s" % [v.name, gt, (" · HCP %s" % Sim.fmtHcp(v.hcp)) if v.get("hcp") != null else '',
			'[i]Sent home by a marshal[/i]' if v.get("ejected") else stl, planLabel(v), line, wait, bar(mo / 100.0, Sim.MOOD_COLOR[mk]), roundi(mo), Sim.MOOD_LABEL[mk]]
	for grp in Sim.groups:
		for v in grp.players:
			if Vector2(v.x - wx, v.y - 4 - wy).length() > r: continue
			var b = Sim.ball(grp, v) if grp.phase == 'play' else null
			var pin: Vector2 = Sim.pinPos(grp.hole)
			var where := ''
			if not b: where = "walking to the %d%s tee" % [grp.hole + 1, ordinal(grp.hole)]
			elif b.lie == 'holed': where = 'picked up' if b.get("pickedUp") else "holed out in %d" % b.strokes
			else: where = "%s%s the %s, %d yd to the pin" % [("%d shot%s, " % [b.strokes, 's' if b.strokes > 1 else '']) if b.strokes else '', 'on' if ['green', 'fringe', 'fairway', 'tee'].has(b.lie) else 'in', Sim.LIE[b.lie].label, Sim.yd(pin.distance_to(Vector2(b.x, b.y)))]
			var mk: String = Sim.moodKind(Sim.moodOf(v))
			return "[b]%s[/b] · HCP %s · %s tees · Group %s\nHole %d · par %d · %s\nRound: %s\n%s · mood %d%% (%s)" % [v.name, Sim.fmtHcp(v.get("hcp", 0.0)), Sim.TEE[v.get("tee", 'yellow') if v.get("tee") else 'yellow'].label, grp.id,
				grp.hole + 1, grp.pars[grp.hole], where, (Sim.toPar(v, grp) + " thru %d" % v.strokes.size()) if v.strokes.size() else 'first hole', Sim.STANDING[v.standing].label, roundi(Sim.moodOf(v)), Sim.MOOD_LABEL[mk].to_lower()]
	var hi: int = Sim.holeAt(wx, wy, g.view.cam.s)
	if hi >= 0:
		var h = Sim.S.holes[hi]
		if Sim.holeOpen(hi): return "[b]Hole %d[/b] · Par %d · %d yd\nRating %d/%d · turf %d%%\n%s" % [hi + 1, h.par, Sim.holeYards(hi), Sim.holeRating(hi), Sim.HOLE_MAX_RATING, roundi(Sim.turfOf(hi)), gold('Click to see this hole')]
		return "[b]Hole %d[/b]\nBuild the back nine to open it." % (hi + 1)
	var hits := []
	Sim.forRanges(func(o): hits.append(_rangeHover(o, wx, wy)))
	for hh in hits:
		if hh != '': return hh
	if Sim.hasObj('club'):
		for k in Sim.ROOMS:
			var rm = Sim.ROOMS[k]
			if wx < rm.x0 + Sim.CDX or wx > rm.x1 + Sim.CDX or wy < rm.y0 + Sim.CDY or wy > rm.y1 + Sim.CDY: continue
			var vk = { "lobby": 'shop', "bar": 'bar', "resto": 'resto', "terrace": 'terrace' }.get(k)
			if vk == null: return "[b]%s[/b]\n%s" % [rm.label, ("Course golfers change here. Green fees +%d%%" % (8 * Sim.L('locker'))) if Sim.L('locker') else 'Not built yet']
			var cap: int = Sim.venueCap(vk)
			var used := 0
			var seats = Sim.seatTaken.get(vk, {})
			for s in seats.keys():
				if seats[s] and int(s) < cap: used += 1
			return "[b]%s[/b]\n%s%s" % [rm.label, ("%d of %d seats taken" % [used, cap]) if cap else 'Not built yet', '\n[i]Closed[/i]' if (cap and not Sim.venueOpen(vk)) else '']
	var t := Sim.tileOf(wx, wy)
	if t.tx >= 0 and t.ty >= 0 and t.tx < Sim.GW and t.ty < Sim.GH:
		var id: int = Sim.occ[Sim.tIdx(t.tx, t.ty)]
		var o = Sim.objById(id) if id > 0 else null
		if o and o.type != 'range' and o.type != 'club':
			var D = Sim.OBJ[o.type]
			var st := ''
			if o.type == 'lot':
				var used := 0
				for s in Sim.lotSpots(o):
					if Sim.spotsHeld.has(s.key): used += 1
				st = "%d of 14 spaces taken" % used
			elif Sim.AMEN.has(o.type): st = "%d using it · %d waiting%s" % [Sim.amenUsers(o).size(), Sim.amenQ.get(o.id, []).size(), '\n[i]Needs a teaching pro[/i]' if (o.type == 'academy' and not Sim.N('coach')) else '']
			else: st = D.desc
			return "[b]%s[/b]\n%s%s" % [D.label, st, '\n[i]Not connected to a car park by footpath[/i]' if (not D.get("free") and not Sim.connected('OBJ:%s' % o.id)) else '']
	return ''
static func _rangeHover(o, wx: float, wy: float) -> String:
	var nm := (Sim.rangeName(o) + ' · ') if Sim.rangeObjs().size() > 1 else ''
	for m in Sim.machines():
		var mp: Vector2 = Sim.machinePos(m)
		if abs(mp.x - wx) < 8 and abs(mp.y - wy) < 14: return "[b]%sBall machine %d[/b]\n%s balls ready · %d in line\nA bucket takes %.1f s" % [nm, m + 1, Sim.fmtInt(floor(Sim.S.stock)), Sim.bucketQueue.size(), Sim.fillTime()]
	if wy > Sim.TEE_Y - 10 and wy < Sim.TEE_Y + 12:
		for b in Sim.bays():
			var x: float = Sim.bayLeftX(b)
			if wx < x or wx > x + Sim.BAY_W: continue
			var who = null
			for v in Sim.rangeP:
				if v.get("bay") == b: who = v
			var st := ''
			if Sim.brokenBays.has(b): st = 'Out of order: damaged mat'
			elif b >= Sim.staffedBays(): st = 'Closed: no attendant'
			elif who: st = "%s is hitting" % who.name
			elif Sim.bayTaken.has(b): st = 'Reserved'
			else: st = 'Free'
			return "[b]%sBay %d[/b]\n%s" % [nm, b + 1, st]
	if wx > Sim.RX0 and wx < Sim.rangeX1() and wy > Sim.RY0 and wy < Sim.FIELD_Y1:
		return "[b]%s[/b]\n%s balls out on the grass · %d of %d bays in use\n%s" % [Sim.rangeName(o) if Sim.rangeObjs().size() > 1 else 'Driving range', Sim.fmtInt(floor(Sim.S.field)), Sim.rangeP.size(), Sim.staffedBays(), gold('Click to manage it')]
	return ''
