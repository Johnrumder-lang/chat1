# NORTHBOUND

An atmospheric R6 first-person road trip for Roblox: an original 1994 Aster touring wagon, independent suspension, and an endlessly generated alpine route.

**Download:** [Northbound.rbxlx](https://github.com/Johnrumder-lang/chat1/raw/refs/heads/main/Northbound.rbxlx) · [Game file ZIP](https://github.com/Johnrumder-lang/chat1/raw/refs/heads/main/Northbound-download.zip) · [Complete project ZIP](https://github.com/Johnrumder-lang/chat1/raw/refs/heads/main/dist/Northbound-project.zip)

The Roblox place is **`Northbound.rbxlx`**, directly in the main repository folder. GitHub previews `.rbxlx` files as XML; that is Roblox's place-file format. Use **Download raw file** on the file page. If your browser displays XML instead of saving it, download **Game file ZIP**, extract `Northbound.rbxlx`, and open that file in Roblox Studio.

## Open the game

1. Open **`Northbound.rbxlx`** in Roblox Studio with **File → Open from File**.
2. Press **Play / F5**, wait for the opening road to generate and stream, then choose **Begin journey**.
3. Use a high graphics setting for the intended shadows, glass, terrain water and clouds. Studio may migrate Future lighting to its current equivalent.

The file includes the scripts, R6 character, a 450-part original car, and an edit-mode opening scene. The smooth terrain is generated during Play. No toolbox models, plugins, uploaded meshes, external scripts or API keys are required.

## Controls

| Input | Action |
| --- | --- |
| W / S or ↑ / ↓ | Accelerate; brake, then reverse |
| A / D or ← / → | Steer |
| Space | Handbrake |
| Hold right mouse + move | Look around the cabin; release to recenter |
| H | Headlights |
| V | Automatic rain wipers on/off |
| R | Recover onto the nearby road |
| Gamepad RT / LT, left stick, A | Throttle / brake-reverse, steer, handbrake |
| Touch | Onscreen driving controls; swipe above them to look |

## Included

- A detailed sage-green wagon with wheel tread, alloys, brake details, bumpers, grille, mirrors, roof rack, luggage, seats, console and an instrument cluster.
- Four spring/damper tyre contacts, axle anti-roll, front steering, all-wheel drive, drag, reversing logic, braking, and reduced dirt/wet grip. Nominal top speed is about 140 km/h on level road.
- A fixed driver-eye camera with restrained acceleration movement, animated steering wheel, gauges and wipers.
- Deterministic smooth terrain: mountain ridges, conifer forests, lake basins, river channels, concrete bridges, asphalt, dirt tracks, roadside reflectors, crash barriers, signs, shrubs and rocks.
- Clear, overcast, rain, storm and fog conditions, gradual weather transitions, clouds, subtle color grading and slow daylight progression.
- Bounded local rain and bird flocks; grazing deer near the road; a minimal speed, direction, distance and weather display.
- Startup streaming checks, recovery, per-player car ownership, and bounded scenery cleanup.

The route extends along the north/south axis. The default generator keeps seven nearby 256-stud chunks, capped at eleven when drivers separate. It is an endless driving corridor; floating-point precision still limits extreme distances. Start with a **single-player server**. Up to three nearby/separated drivers have been considered in the streaming budget, but multiplayer behavior requires Studio testing before publication.

## Build and check

Python 3.10+ is enough to reproduce the place:

```sh
python3 tools/build_place.py
python3 tests/verify_place.py
```

With the official [Luau](https://github.com/luau-lang/luau) CLI installed:

```sh
luau-compile --null src/shared/*.lua src/server/*.lua src/client/*.lua
python3 tests/run_route_spec.py /path/to/luau
python3 tests/vehicle_spec.py --luau /path/to/luau
python3 tests/weather_spec.py /path/to/luau
```

`assets/car.json` is the editable car geometry. `src/shared/Route.lua` controls the route and `VehiclePhysics.lua` its driving constants. `src/server/World.lua` controls scenery density and streaming. `Weather.lua` contains weather presets and their timing.

`tools/preview_car.py` optionally renders the authored car with Blender. The model-study images in `dist` are **offline Blender renders, not Roblox screenshots**; Roblox materials and rendering differ.

## Validation and remaining work

The delivered source compiles with the official Luau compiler. Automated checks exercise actual route, vehicle and weather modules using controlled Roblox API stand-ins, and verify the XML's references, car joint graph, joint rest transforms, R6 rig, and embedded scripts.

Roblox Studio is unavailable on the build machine. The place has **not been opened or playtested in Studio**. Engine suspension/contact solving, streaming timing, mobile performance, and final visual quality need the [Studio playtest checklist](docs/STUDIO_PLAYTEST.md). The project uses detailed procedural geometry and Roblox materials; it does not include scanned/PBR mesh assets or a licensed engine/ambience soundtrack. No claim of photorealistic graphics or final production readiness is made.
