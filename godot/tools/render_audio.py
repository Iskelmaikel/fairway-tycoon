"""Render the web version's synthesised sounds and music to audio files for the Godot build.

The web game makes every sound live with Web Audio. Godot plays recordings instead, so this
script loads the web game in headless Chromium, swaps its audio context for an offline one,
triggers each sound (and plays each tune start to finish), and saves the results as OGG.

    python3 tools/render_audio.py path/to/fairway.html assets/audio
"""
import time, asyncio, base64, os, subprocess, sys, tempfile
from playwright.async_api import async_playwright

HOOK = r"""
    // ---- offline rendering hook (render_audio.py) ----
    window.__render = async (secs, fn) => {
      const real = window.AudioContext;
      window.AudioContext = function () { return new OfflineAudioContext(2, Math.ceil(44100 * secs), 44100); };
      ac = null; ready = false; on = true; mv = 0.9; av = 0.8; sv = 0.9; muv = 0.6;
      for (const k in last) delete last[k]; lastStrike = -1; lastUi = -1;
      try { start(); } finally { window.AudioContext = real; }
      const myAc = ac;   // bars run later (on suspend), so pin them to this render's context
      const api = window.__soundApi;
      const ev = fn({ api, ac, loops, windG, windF, rainG, trafficG, M, TRACKS, planTrack, playBar, beatsOf, chordAt, bassRoot, chord, voice, ep, bass, bird, blackbird, pigeon, cuckoo, crow, woodpecker, quack, owl, cricket, frog }) || [];
      // Nodes made for a bar stay wired into the music bus after their notes end, and the offline
      // renderer keeps processing all of them, so a long track gets slower and slower. Track what
      // each bar creates and unplug it once its notes (and their longest tail) are over.
      const made = [];
      const P = BaseAudioContext.prototype;
      if (!P.__tracked) {
        P.__tracked = true;
        for (const nm of ['createGain', 'createOscillator', 'createBiquadFilter', 'createStereoPanner', 'createBufferSource', 'createConstantSource', 'createWaveShaper', 'createDelay']) {
          const orig = P[nm]; if (!orig) continue;
          P[nm] = function (...a) { const n = orig.apply(this, a); if (window.__made) window.__made.push([window.__barT, n]); return n; };
        }
      }
      const run = (t, f) => {
        window.__made = made; window.__barT = t; ac = myAc;
        try { f(); } finally { window.__made = null; }
        const now = ac.currentTime;
        for (let i = made.length - 1; i >= 0; i--) if (made[i][0] < now - 8) { try { made[i][1].disconnect(); } catch (e) {} made.splice(i, 1); }
      };
      const Q = 128 / 44100, used = new Set();
      for (const [t, f] of ev) {
        const at = Math.round(Math.max(0, t - 0.8) / Q);
        if (at < 4 || at * Q >= secs || used.has(at)) { if (at * Q < secs) run(t, f); continue; }
        used.add(at);
        ac.suspend(at * Q).then(() => {
          try { run(t, f); if (window.__verbose) console.log('bar', t.toFixed(1), 'live', made.length, Math.round(performance.now() - window.__T0)); }
          catch (e) { console.log('bar error', String(e)); }
          ac.resume();
        });
      }
      const T0 = window.__T0 = performance.now(); console.log('schedule done, rendering');
      const buf = await ac.startRendering();
      console.log('render ms', Math.round(performance.now() - T0));
      const L = buf.getChannelData(0), R = buf.getChannelData(1), n = buf.length;
      const out = new Int16Array(n * 2);
      for (let i = 0; i < n; i++) { out[i * 2] = Math.max(-1, Math.min(1, L[i])) * 32767; out[i * 2 + 1] = Math.max(-1, Math.min(1, R[i])) * 32767; }
      if (ac === myAc) { ac = null; ready = false; }
      let s = ''; const b = new Uint8Array(out.buffer);
      for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
      console.log('encode done ms', Math.round(performance.now() - T0));
      return btoa(s);
    };
"""

# name -> (seconds, javascript that triggers it, given `x` = the hook's toolbox)
FX = {
  'tap': (0.4, "x.api.ui('tap')"), 'open': (0.5, "x.api.ui('open')"), 'close': (0.5, "x.api.ui('close')"),
  'select': (0.5, "x.api.ui('select')"), 'soft': (0.5, "x.api.ui('soft')"),
  'chime': (1.2, "x.api.chime()"), 'kaching': (1.4, "x.api.kaching()"), 'fanfare': (2.0, "x.api.fanfare()"),
  'cup': (0.6, "x.api.cup(SW / 2, 1)"), 'putt': (0.4, "x.api.putt(SW / 2, 1)"), 'sand': (0.7, "x.api.sand(SW / 2, 1)"),
  'splash': (1.2, "x.api.splash(SW / 2, 1)"), 'tree': (1.0, "x.api.tree(SW / 2, 1)"),
  'strike1': (0.5, "x.api.strike(SW / 2, 1)"), 'strike2': (0.5, "x.api.strike(SW / 2, 1)"), 'strike3': (0.5, "x.api.strike(SW / 2, 1)"),
  'door': (0.6, "x.api.door(SW / 2, 1, false)"), 'doorlock': (1.1, "x.api.door(SW / 2, 1, true)"),
  'ignition': (1.6, "x.api.ignition(SW / 2, 1)"), 'desk': (1.4, "x.api.desk(SW / 2, 1)"),
  'balls': (1.4, "x.api.balls(SW / 2, 1, 24)"), 'clink': (0.8, "x.api.clink(SW / 2, 1)"),
  'applause': (2.4, "x.api.applause(SW / 2, 1, 4, false)"), 'cheer': (2.6, "x.api.applause(SW / 2, 1, 6, true)"),
  'bell_open': (5.0, "x.api.bell('open', SW / 2)"), 'bell_close': (16.0, "x.api.bell('close', SW / 2)"),
  'bird1': (2.0, "x.bird(0, 1)"), 'bird2': (2.0, "x.bird(0, 1)"), 'bird3': (2.0, "x.bird(0, 1.2)"),
  'blackbird': (3.0, "x.blackbird()"), 'pigeon': (2.5, "x.pigeon()"), 'cuckoo': (2.0, "x.cuckoo()"),
  'crow': (2.0, "x.crow()"), 'woodpecker': (2.0, "x.woodpecker()"), 'quack1': (1.5, "x.quack(0)"), 'quack2': (1.5, "x.quack(0)"),
  'owl': (3.0, "x.owl()"), 'cricket': (1.0, "x.cricket()"), 'frog': (2.0, "x.frog(0)"),
}
# looping beds: set a loop's level and let it run (rendered long, trimmed into a seamless loop by crossfade)
LOOPS = {
  'loop_wind': "x.windG.gain.value = 0.09; x.windF.frequency.value = 520",
  'loop_rain': "x.rainG.gain.value = 0.09",
  'loop_traffic': "x.trafficG.gain.value = 0.03",
  'loop_cart': "x.loops.cart.g.gain.value = 0.06; x.loops.cart.mod.f.frequency.value = 330",
  'loop_car': "x.loops.car.g.gain.value = 0.03",
  'loop_mower': "x.loops.mower.g.gain.value = 0.05",
  'loop_fountain': "x.loops.fountain.g.gain.value = 0.05",
  'loop_crowd': "x.loops.crowd.g.gain.value = 0.09; x.loops.crowd.mod.a.gain.value = 0.85; x.loops.crowd.mod.b.gain.value = 0.55",
}
MUSIC = r"""
  // returns [time, fn] steps; the hook schedules each bar just before it plays, as the live game does,
  // so the offline renderer only ever carries a few bars of notes
  const tr = x.TRACKS.find(t => t.id === ID), M = x.M, beat = 60 / tr.bpm, step8 = beat / 2;
  M.tr = tr; M.plan = x.planTrack(tr); M.bar = 0; M.nextRoot = null; M.voicing = [55, 59, 62, 65];
  const ev = []; let t = 0.2;
  for (let b = 0; b < M.plan.length; b++) {
    const bt = t, bb = b;
    ev.push([bt, () => { const nb = M.plan[bb + 1]; if (nb) M.nextRoot = x.bassRoot(x.chordAt(tr, nb.sec, nb.bar, 0)); x.playBar(bt, step8, M.plan[bb], tr); }]);
    t += beat * x.beatsOf(tr);
  }
  const te = t;
  ev.push([te, () => { const e = tr.A[0], c = x.chord(Array.isArray(e) ? e[0] : e); x.voice(c).forEach(m => x.ep(te, m, beat * 4, 0.7)); x.bass(te, x.bassRoot(c), beat * 4, 0.9); }]);
  return ev;
"""

async def main(src, outdir):
    html = open(src, encoding='utf-8').read()
    anchor = "    return {\n      get on() { return on; },"
    assert anchor in html, 'Sound API not found'
    html = html.replace(anchor, HOOK + anchor, 1)
    html = html.replace("  })();\n  let audibleCarts = 0;", "  })();\n  window.__soundApi = Sound;\n  let audibleCarts = 0;", 1)
    os.makedirs(outdir, exist_ok=True)
    tmp = tempfile.mkdtemp()
    async with async_playwright() as p:
        b = await p.chromium.launch(args=['--autoplay-policy=no-user-gesture-required'])
        pg = await b.new_page()
        errs = []
        pg.on('pageerror', lambda e: errs.append(str(e)))
        if '--verbose' in sys.argv: pg.on('console', lambda m: print('  page:', m.text, flush=True))
        await pg.route('**/*', lambda r: r.fulfill(body='<!doctype html><html><head><meta charset="utf-8"></head><body>' + html + '</body></html>', content_type='text/html') if r.request.url.startswith('http://game') else r.abort())
        await pg.goto('http://game/'); await pg.wait_for_timeout(500)
        if '--verbose' in sys.argv: await pg.evaluate('window.__verbose = true')
        tracks = await pg.evaluate("(async () => { let out; await window.__render(0.1, x => { out = x.TRACKS.map(t => [t.id, t.name, t.mood, t.bpm, x.planTrack(t).length, x.beatsOf(t)]); }); return out; })()")
        music_only = '--music' in sys.argv
        jobs = [] if music_only else [(k, s, js, None) for k, (s, js) in FX.items()]
        jobs += [] if music_only else [(k, 14.0, js, 'loop') for k, js in LOOPS.items()]
        for tid, name, mood, bpm, bars, bpb in tracks:
            secs = 0.2 + bars * bpb * 60 / bpm + 4 * 60 / bpm + 3.0
            cap = [float(a.split('=')[1]) for a in sys.argv if a.startswith('--cap=')]
            if cap: secs = min(secs, cap[0])
            only = [a.split('=')[1].split(',') for a in sys.argv if a.startswith('--only=')]
            if only and tid not in only[0]: continue
            jobs.append(('music_' + tid, secs, "const ID = '%s';" % tid + MUSIC, 'music'))
        open(os.path.join(outdir, 'tracks.json'), 'w').write(__import__('json').dumps([{'id': t[0], 'name': t[1], 'mood': t[2]} for t in tracks], indent=1))
        for name, secs, js, kind in jobs:
            if os.path.exists(os.path.join(outdir, name + '.ogg')) and '--force' not in sys.argv: continue   # already rendered
            print('rendering', name, '%.0f s' % secs, flush=True)
            t0 = time.time()
            b64 = await pg.evaluate("async ([secs, js]) => window.__render(secs, new Function('x', 'const SW = 1000;' + js))", [secs, js])
            raw = os.path.join(tmp, name + '.raw')
            open(raw, 'wb').write(base64.b64decode(b64))
            out = os.path.join(outdir, name + '.ogg')
            filt = []
            if kind == 'loop':   # take 10 s from the middle and crossfade the ends so it loops cleanly
                filt = ['-af', 'atrim=start=2:end=12.5,asetpts=PTS-STARTPTS']
            else:
                filt = ['-af', 'silenceremove=stop_periods=-1:stop_duration=0.3:stop_threshold=-70dB']
            q = '4' if kind == 'music' else '5'
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', '44100', '-ac', '2', '-i', raw] + filt + ['-c:a', 'libvorbis', '-q:a', q, out], check=True)
            print(name, os.path.getsize(out) // 1024, 'KB', '%.1f s' % (time.time() - t0), flush=True)
        open(os.path.join(outdir, 'tracks.json'), 'w').write(__import__('json').dumps([{'id': t[0], 'name': t[1], 'mood': t[2]} for t in tracks], indent=1))
        print(errs or 'no page errors')
        await b.close()

if __name__ == '__main__':
    asyncio.run(main(sys.argv[1], sys.argv[2]))   # options: --music (music only), --only=theme,dogleg, --cap=SECONDS, --force
