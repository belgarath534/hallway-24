# Hallway 24

An audio horror game for iPhone, made for VoiceOver and headphones. Blind and sighted players play the same game.

Stay in the hallway for 24 hours. Every hour you get through three doors, choosing left or right each time. Each
door makes a sound: bells, keys and dishes are good rooms; dripping, buzzing, scratching and ticking are creatures.
When a creature finds you, you survive it by listening:

| Creature | From hour | How to survive |
|---|---|---|
| The Drip | 1 | Drips speed up. At the splash, swipe down to hide. Not before. |
| Static | 1 | A buzz on one side. Swipe the other way. Several rounds. |
| The Crawler | 3 | Growl: swipe up and run. Sniff: don't touch anything. |
| The Mimic | 4 | Pretends to be a good room, but sounds a little too low. Inside: swipe toward the real voice. |
| The Counter | 5 | Counts down from ten. Don't touch the screen until it sighs. |

You have three hearts. Bedrooms heal, kitchens have bandages, vaults have tokens for the Host's shop (after hours
6, 12 and 18), and storage closets have items: a lighter (the Host tells you what's behind both doors), bandages,
and a lucky charm. Two Hosts to choose from: **Lewis**, a polite gentleman, and **Heart**, who is far too sweet.

## Layout

- `Packages/HallwayCore`: the whole game (doors, rooms, creatures, the Host's script, saving), pure Swift with no
  sound or screen code, so it runs and is tested on Linux too. Includes a robot player that plays hundreds of nights
  to check that every creature is fair and the difficulty is right: `cd Packages/HallwayCore && swift test`.
- `App/`: the iPhone app (SwiftUI menus, the touch area, sound engine, the Host's voice, vibration).
  - `App/Voices`: the Hosts' recorded lines. `App/Sounds`: effects and ambiences. `App/Music`: music.
- `tools/make_voices.py`: records the Hosts (and the Counter and Mimic) with Kokoro. `tools/make_sounds.py`:
  builds the sounds and music from the free packs listed in [CREDITS.md](CREDITS.md).
- `project.yml`: XcodeGen spec. The Xcode project is generated, not committed.

## Builds

GitHub Actions (`.github/workflows/build.yml`) runs the tests and an unsigned iPhone build on every push.

**TestFlight**: Actions tab, *Hallway 24*, *Run workflow*. It needs these repository secrets (Settings, Secrets and
variables, Actions), the same ones as the truck sim: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `MATCH_PASSWORD`,
`CERTS_REPO_TOKEN`. The first run registers the bundle ID `com.hallway24.Hallway24`; then create the app in App Store
Connect (Apps, +, New App, iOS, name "Hallway 24", that bundle ID, SKU hallway24) and run it again.

## Changing what the Host says

Edit `Packages/HallwayCore/Sources/HallwayCore/HostScript.swift`, then:

```
cd Packages/HallwayCore && DUMP_PATH=../../tools/host_lines.json swift test --filter testDumpScript
cd ../.. && tools/.venv/bin/python tools/make_voices.py
```

Lines without a recording are spoken by the phone's own voice until they're recorded.
