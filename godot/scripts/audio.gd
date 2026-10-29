class_name AudioPlayer
extends Node
## Sound and music. The web version synthesised everything live; these are recordings of
## exactly those sounds (made by tools/render_audio.py), played the same way: effects heard
## when they're on screen, looping beds steered by what is near the camera, birds by season and
## hour, and a jazz soundtrack that follows the time of day and the weather.

var game
var on := true
var players: Array = []       # one-shot voices
var loops := {}               # name -> AudioStreamPlayer
var music: AudioStreamPlayer
var _streams := {}
var _last := {}
var _tracks: Array = []       # [{ id, name, mood }]
var _cur = null
var _want := 'title'
var _gap := 0.0
var _fade := 0.0
var _played: Array = []
var _duck := 1.0
var _duckT := 0.0
var _birdT := 2.0
var _nightT := 3.0
var _cricketT := 0.0
var _clinkT := 0.0
var _wasDark = null
var _lastPos := {}
var _t := 0.0

const DIR := "res://assets/audio/"
const BUSES := ['Music', 'Ambience', 'SFX']

func _ready() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	# a gentle limiter on the master, as the web version had a compressor
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectLimiter.new(); lim.threshold_db = -3.0
		AudioServer.add_bus_effect(0, lim)
	for i in 14:
		var p := AudioStreamPlayer2D.new()
		p.bus = 'SFX'; p.max_distance = 1e7; p.attenuation = 0.0; p.panning_strength = 0.8
		add_child(p); players.append(p)
	for k in ['wind', 'rain', 'traffic', 'cart', 'car', 'mower', 'fountain', 'crowd']:
		var s = _stream('loop_' + k)
		var p := AudioStreamPlayer.new()
		p.bus = 'Ambience' if k in ['wind', 'rain', 'traffic', 'fountain', 'crowd'] else 'SFX'
		if s: s.loop = true; p.stream = s
		p.volume_db = -80
		add_child(p)
		loops[k] = p
	music = AudioStreamPlayer.new(); music.bus = 'Music'
	add_child(music)
	music.finished.connect(func(): _cur = null; _gap = 3.0)
	var f := FileAccess.open(DIR + "tracks.json", FileAccess.READ)
	if f: _tracks = JSON.parse_string(f.get_as_text())
	Sim.sound.connect(_onSound)
	on = Sim.SETTINGS.get("soundOn", true)
	setVolumes()

func _stream(name: String):
	if _streams.has(name): return _streams[name]
	var path := DIR + name + ".ogg"
	var s = null
	if ResourceLoader.exists(path): s = load(path)
	elif FileAccess.file_exists(path): s = AudioStreamOggVorbis.load_from_file(path)
	_streams[name] = s
	return s

## The recordings were made with the web game's default mix already applied (master 0.9, music 0.6,
## ambience 0.8, effects 0.9), so the buses divide that back out: at default settings it sounds
## exactly like the web version, and the sliders still work the same way.
const BAKED := { "master": 0.9, "music": 0.6, "ambience": 0.8, "sfx": 0.9 }
func setVolumes() -> void:
	var S: Dictionary = Sim.SETTINGS
	var db := func(k: String, def: float) -> float: return linear_to_db(max(0.0001, S.get(k, def) / BAKED[k]))
	AudioServer.set_bus_volume_db(0, db.call("master", 0.9) if on else -80.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('Music'), db.call("music", 0.6))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('Ambience'), db.call("ambience", 0.8))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('SFX'), db.call("sfx", 0.9))
func toggle() -> void:
	on = not on
	Sim.SETTINGS.soundOn = on; Sim.saveSettings()
	setVolumes()
func trackList() -> Array: return _tracks.map(func(t): return [t.id, t.name])
func skipTrack() -> void:
	if _cur != null: _fade = 0.6

## how close something is to the screen, and how loud that makes it
func _ear(pos) -> float:
	if pos == null or game == null: return 1.0
	var v: WorldView = game.view
	var sp := v.toScreen(pos.x, pos.y)
	var SW := v.SW()
	var SH := v.SH()
	var dx: float = -sp.x if sp.x < 0 else (sp.x - SW if sp.x > SW else 0.0)
	var dy: float = -sp.y if sp.y < 0 else (sp.y - SH if sp.y > SH else 0.0)
	return exp(-Vector2(dx, dy).length() / 260.0)
func zoomVol() -> float: return clampf(game.view.cam.s / 1.4, 0.15, 1.0) if game else 1.0
func _ok(k: String, gap: float) -> bool:
	if _last.has(k) and _t - _last[k] < gap: return false
	_last[k] = _t
	return true

const GAPS := { "putt": 0.08, "sand": 0.1, "splash": 0.1, "tree": 0.15, "applause": 0.6, "door": 0.25, "ignition": 0.4, "desk": 1.2, "balls": 0.5, "clink": 1.5, "strike": 0.07, "tap": 0.03, "open": 0.03, "close": 0.03, "select": 0.03, "soft": 0.03 }
const UI := ['tap', 'open', 'close', 'select', 'soft', 'chime', 'kaching', 'fanfare']
func _onSound(name: String, o: Dictionary) -> void:
	if not on or Sim.atTitle and not UI.has(name): return
	var pos = o.get("pos")
	var vol: float = o.get("vol", 1.0)
	if pos != null:
		if Sim.warp > 2: return
		if game and not game.view.onScreen(pos.x, pos.y): return
		vol *= zoomVol()
	if not _ok(name, GAPS.get(name, 0.0)): return
	var file := name
	var args: Array = o.get("args", [])
	match name:
		'strike': file = 'strike%d' % (randi() % 3 + 1)
		'door': file = 'doorlock' if (args.size() and args[0]) else 'door'
		'applause': file = 'cheer' if (args.size() > 1 and args[1]) else 'applause'
	if name == 'fanfare': _duckFor(1.6, 0.25)
	var d: float = o.get("delay", 0.0)
	if d > 0: get_tree().create_timer(d).timeout.connect(func(): play(file, pos, vol))
	else: play(file, pos, vol)
func play(file: String, pos = null, vol := 1.0, bus := 'SFX') -> void:
	var s = _stream(file)
	if s == null: return
	var p: AudioStreamPlayer2D = null
	for x in players:
		if not x.playing: p = x; break
	if p == null: p = players[0]
	p.stream = s
	p.bus = bus
	p.volume_db = linear_to_db(max(0.0001, vol))
	p.pitch_scale = randf_range(0.97, 1.03) if file.begins_with('strike') or file == 'tap' else 1.0
	if pos != null: p.global_position = pos
	elif game: p.global_position = game.view.camera.get_screen_center_position()
	p.play()
func _duckFor(secs: float, level: float) -> void: _duck = level; _duckT = secs

# ---------- every frame: the beds, the wildlife, the music ----------
func _isMoving(o) -> bool:
	var id = o.get_instance_id() if o is Object else hash(str(o.get("id", 0)) + str(o.get("name", '')))
	var l = _lastPos.get(id)
	var m: bool = l != null and Vector2(o.x - l.x, o.y - l.y).length() > 0.05
	_lastPos[id] = Vector2(o.x, o.y)
	return m
func _process(dt: float) -> void:
	_t += dt
	if game == null: return
	var titleNow: bool = Sim.atTitle
	_music(dt, titleNow)
	if not on: return
	var mix := { "cart": [0.0, 0.0], "car": [0.0, 0.0], "mower": [0.0, 0.0], "fountain": [0.0, 0.0], "crowd": [0.0, 0.0] }
	var add := func(k: String, x: float, y: float, a := 1.0):
		mix[k][0] += _ear(Vector2(x, y)) * a
	if not titleNow:
		for v in Sim.visitors:
			if (v.get("riding") and v.state == 'golf') or (v.state == 'walk' and v.get("cart")):
				if _isMoving(v): add.call('cart', v.x, v.y, 0.45)
		for m in Sim.marshals:
			if m.get("cart") and _isMoving(m): add.call('cart', m.x, m.y, 0.5)
		for k in Sim.keepers:
			if k.state == 'mow': add.call('mower', k.x, k.y)
			elif k.state == 'go' and _isMoving(k): add.call('cart', k.x, k.y, 0.5)
		for v in Sim.vehicles:
			if v.state != 'parked': add.call('car', v.x, v.y, 0.5)
		for o in Sim.objs():
			if o.type == 'fountain': add.call('fountain', (o.x + 1) * Sim.TILE, (o.y + 1) * Sim.TILE)
		var club = Sim.objOf('club')
		if club:
			var cx: float = (club.x + Sim.OBJ.club.w / 2.0) * Sim.TILE
			var cy: float = (club.y + Sim.OBJ.club.h / 2.0) * Sim.TILE
			var n := 0
			for v in Sim.visitors:
				if v.state != 'drive' and v.state != 'gone' and v.state != 'golf' and abs(v.x - cx) < 170 and abs(v.y - cy) < 150: n += 1
			add.call('crowd', cx, cy, min(1.3, n / 10.0))
	var zv := zoomVol()
	var fast: bool = Sim.warp > 2
	var w: Dictionary = Sim.W_()
	var gust := 0.5 + 0.5 * sin(_t * 0.37) * sin(_t * 0.13 + 1)
	_bed('wind', (0.025 + w.wind * 0.07) * (0.6 + 0.6 * gust) / 0.09, dt)
	_bed('rain', 1.0 if (Sim.S.wx == 'rain' and not titleNow) else 0.0, dt)
	var cs: Vector2 = game.view.camera.get_screen_center_position()
	_bed('traffic', (0.006 + 0.014 * _ear(Vector2(cs.x, Sim.ROAD_Y)) * zv) / 0.03, dt)
	for k in mix: _bed(k, min(1.0, mix[k][0] * zv), dt)
	var cr: float = mix.crowd[0] * zv
	if cr > 0.3 and randf() < dt * 0.25 * cr and _ok('clink', 1.5): play('clink', null, min(1.0, cr), 'Ambience')
	# the clubhouse bell when the course opens in the morning and closes at dusk
	var dk: bool = Sim.isDark()
	if _wasDark != null and dk != _wasDark and not titleNow and Sim.hasObj('club') and _ok('bell', 5):
		play('bell_close' if dk else 'bell_open', null, 1.0, 'Ambience'); _duckFor(10.0 if dk else 2.5, 0.35)
	_wasDark = dk
	if fast or titleNow: return
	# wildlife, by season and time of day
	var sea: String = Sim.season()
	var h: float = Sim.hour()
	var sun: Array = Sim.SUN[Sim.monthIdx()]
	var dawn: float = max(0.0, 1 - abs(h - sun[0] - 0.5) / 1.5)
	var water := false
	for b in Sim.WF.bodies:
		if b.n >= 6 and _ear(Vector2(b.x, b.y)) > 0.3: water = true
	if Sim.daylight() > 0.4 and Sim.S.wx != 'rain':
		_birdT -= dt * (1 + 2.5 * dawn) * (0.4 if sea == 'winter' else 1.0)
		if _birdT <= 0:
			var r := randf()
			var nm := ''
			if water and r < 0.12: nm = 'quack%d' % (randi() % 2 + 1)
			elif r < 0.2 and (dawn > 0.2 or h > sun[1] - 2): nm = 'blackbird'
			elif r < 0.3: nm = 'pigeon'
			elif r < 0.36: nm = 'crow'
			elif r < 0.41 and sea == 'spring' and h < 13: nm = 'cuckoo'
			elif r < 0.44 and sea != 'winter': nm = 'woodpecker'
			else: nm = 'bird%d' % (randi() % 3 + 1)
			_ambient(nm)
			_birdT = randf_range(1.2, 5) / (0.5 if w.wind > 1 else 1.0)
	if Sim.daylight() < 0.3:
		if (sea == 'summer' or (sea == 'spring' and h > 12)) and Sim.S.wx != 'rain':
			_cricketT -= dt
			if _cricketT <= 0: _ambient('cricket', 0.7); _cricketT = randf_range(0.25, 0.9)
		_nightT -= dt
		if _nightT <= 0:
			if water and sea != 'winter' and randf() < 0.6: _ambient('frog')
			elif randf() < 0.5: _ambient('owl')
			_nightT = randf_range(6, 16)
func _ambient(name: String, vol := 1.0) -> void:
	play(name, null, vol, 'Ambience')
	# birds come from somewhere on screen
	var p: AudioStreamPlayer2D = null
	for x in players:
		if x.playing and x.stream == _stream(name): p = x
	if p and game: p.global_position = game.view.camera.get_screen_center_position() + Vector2(randf_range(-0.4, 0.4) * game.view.SW() / game.view.cam.s, 0)
func _bed(k: String, level: float, dt: float) -> void:
	var p: AudioStreamPlayer = loops[k]
	if p.stream == null: return
	var target: float = clampf(level, 0, 1.5)
	var cur: float = p.get_meta("lv", 0.0)
	cur += (target - cur) * min(1.0, dt * 2.5)
	p.set_meta("lv", cur)
	if cur < 0.003:
		if p.playing: p.stop()
		return
	if not p.playing: p.play(randf() * 8.0)
	p.volume_db = linear_to_db(cur)

# ---------- music ----------
func _poolFor(mood: String) -> Array:
	return _tracks.filter(func(t): return t.mood == mood or (mood == 'rain' and t.id == 'backnine'))
func _music(dt: float, titleNow: bool) -> void:
	var want := 'title'
	if not titleNow:
		var dk: bool = Sim.isDark() or Sim.daylight() < 0.5
		want = 'evening' if dk else ('rain' if Sim.S.wx == 'rain' else 'day')
	_want = want
	var pick: String = Sim.SETTINGS.get("track", 'auto')
	# duck under fanfares and bells
	if _duckT > 0: _duckT -= dt
	else: _duck = min(1.0, _duck + dt * 0.8)
	var base := 1.0
	if _fade > 0:
		_fade -= dt
		base = max(0.0, _fade / 0.6)
		if _fade <= 0: music.stop(); _cur = null; _gap = 1.2
	music.volume_db = linear_to_db(max(0.0001, base * _duck))
	if Sim.SETTINGS.get("music", 0.6) <= 0.001: return
	if _cur != null:
		var mismatch: bool = (_cur.mood != want and not _poolFor(want).has(_cur)) if pick == 'auto' else pick != _cur.id
		if mismatch and _fade <= 0: _fade = 2.0
		return
	if _gap > 0: _gap -= dt; return
	var tr = null
	if pick != 'auto':
		for t in _tracks:
			if t.id == pick: tr = t
	if tr == null:
		var pool := _poolFor(want)
		if pool.is_empty(): pool = _poolFor('day')
		if pool.is_empty(): return
		var fresh := pool.filter(func(t): return not _played.has(t.id))
		var from := fresh if fresh.size() else pool
		tr = from[randi() % from.size()]
		_played = (_played.filter(func(id): return id != tr.id) + [tr.id]).slice(-3)
	var s = _stream('music_' + tr.id)
	if s == null: return
	s.loop = false
	_cur = tr
	music.stream = s
	music.play()
	if game and game.hud: game.hud.nowPlayingShow(tr.name)
