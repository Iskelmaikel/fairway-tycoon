# Fairway Tycoon (Godot)

This is the main version of the game from now on. The web version in the repository root (`index.html`, v0.41.0) is frozen as the reference the port was made from; new work happens here.

Open the folder in **Godot 4.5** (standard build, no C#) and press Play.

## How it is put together

The simulation and the picture are kept apart, so the view can be replaced (a new 2D art style, or 3D) without touching the game rules.

| Part | File | What it does |
|---|---|---|
| Simulation | `scripts/sim.gd` (autoload `Sim`) | The whole game: golfers, staff, the course, money, weather, events, campaign, saves. It knows nothing about drawing and talks to the rest through signals (`toast_shown`, `sound`, `event_card`, `ui_tick`, …). |
| View | `scripts/view/` | `world_view.gd` draws the park in layers (static ground and trees are cached, people and carts are redrawn each frame). `art.gd` holds the drawing of people, vehicles and wildlife. `ctx2d.gd` is a small canvas-style drawing layer that batches everything into a few draw calls. |
| Interface | `scripts/ui/` | HUD, windows (`sheet.gd`), the golfer/staff inspector, dialogs and the title screen, all built in code with `kit.gd`. |
| Sound | `scripts/audio.gd` | Plays the recorded sounds and music: effects you can see, beds that follow what's near the camera, birds by season and hour, music by time of day and weather. |
| Controller | `scripts/main.gd` | Camera, input (mouse, keyboard, controller), build tools, and wiring the parts together. |

`scripts/sim.gd` is long. It is the web game's logic carried over function by function, so the two can still be compared line for line.

## Sound and music

The web version made every sound live with Web Audio. `tools/render_audio.py` records those exact sounds into `assets/audio/` (it loads the web game in headless Chromium with an offline audio context). Run it again only if you change the web synth:

```
pip install playwright && python3 tools/render_audio.py ../index.html assets/audio   # add --force to redo existing files
```

## Testing

Headless checks, no window needed:

```
godot --headless --path . --script tools/smoke.gd     # 12 days of The Rescue
godot --headless --path . --script tools/systems.gd   # every scenario, event, save/load, terraforming, the designer
```

Screenshots from the command line (any of these options can be combined):

```
godot --path . -- --scen=rescue --days=0.5 --open=fin --shot=out.png
```

`--scen` starts a scenario, `--days` fast-forwards, `--open` opens a window tab, `--act` opens a dialog or inspector (`golfer`, `designer`, `menu`, `settings`, `end`, `event:charity`, …), `--zoom`/`--at=x,y` move the camera.

## Exporting

`export_presets.cfg` has Windows, Linux and macOS presets that write to `build/`. Install the export templates once (Editor → Manage Export Templates), then:

```
godot --headless --path . --export-release "Windows Desktop"
```

## Steam

Achievements, rich presence and cloud saves work through [GodotSteam](https://godotsteam.com/) when it is present. Use the GodotSteam build of the editor (or the GDExtension), and put `steam_appid.txt` next to the executable while testing. Without it the game runs normally and simply skips Steam. The achievement API names match the ones in the Steamworks setup used by the Electron build.

Saves live in `user://saves` (on Windows: `%APPDATA%\Godot\app_userdata\Fairway Tycoon\saves`).

## Fonts

The web version uses Figtree; this build uses **Inter** (very close, SIL Open Font License) with **Noto Color Emoji** for event and medal icons (also OFL). Swap in Figtree by dropping its files into `assets/fonts/` and changing the names in `Ctx2D.fontFor`.
