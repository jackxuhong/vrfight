# VR Fight (working title)

A VR boxing game that follows pro boxing rules. Three modes:

| Mode | What it is |
|------|------------|
| **Practice** | Hit a dummy that sways. The scoreboard shows hits, your fastest punch and the last one. |
| **Single Player** | A full match against a bot that moves, guards, throws combos, blocks and slips. |
| **LAN** | Two players on the same network. One hosts; the other joins automatically. |

Headsets: **Oculus Rift**, **Quest 2 through Link or Air Link** (PC VR), and **Quest 2
standalone** (a sideloaded APK).

Built with **Godot 4.7** (OpenXR). Everything you see and hear is generated in code, with no
asset files.

## Run it

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build, not .NET).
2. **In VR:** start the Meta Quest Link app (Rift, or Quest 2 over Link/Air Link) and make sure it
   is the active OpenXR runtime. Open this folder in Godot and press **Play**, or run
   `godot --path .` from this folder.
3. **Without a headset:** `godot --path . --xr-mode off`
   (`--xr-mode off` matters: with no headset connected, the OpenXR runtime can hang startup.)

## Standalone Quest 2

One-time setup:

1. Turn on **Developer Mode** for the headset in the Meta Horizon phone app (it needs a free Meta
   developer organization).
2. Install **JDK 17** (`winget install Microsoft.OpenJDK.17`), the **Android SDK** command-line
   tools with `platform-tools`, `build-tools;36.1.0` and `platforms;android-36`, and the Godot
   **4.7.2 export templates**. In Godot, set *Editor Settings → Export → Android* to the JDK and
   SDK folders.

Build and install with the headset plugged in over USB and worn, after accepting "Allow USB
debugging":

```bash
GODOT=/path/to/Godot_v4.7.2-stable_win64_console.exe bash tests/export_quest.sh
```

That writes `build/vrfight-quest.apk`, installs it and starts it. After that it's in the
headset's library under **Unknown Sources**. Pass `--no-install` to only build. Logs:
`adb logcat -s godot`.

For a LAN match between a Quest and a PC, **host on the Quest** and join from the PC (see Known
limits in `docs/DESIGN.md`).

## Controls

| | VR (Touch controllers) | Desktop |
|---|---|---|
| Punch | Punch. Speed sets power. | Left / right click (hold **Shift** for a body shot) |
| Guard / get up after a knockdown | Hold both gloves up by your face | Hold **Space** |
| Move | Walk around your room, or use the left stick | **WASD**, mouse to look (click to capture it) |
| Turn | Right stick (45° snap turn) | Mouse |
| Back to lobby | Hold **B** or **Y** | Hold **Esc** |
| Pick a mode in the lobby | Punch a pad | Punch a pad, or press **1–4** |

## The rules

Pro rules, simplified only where VR makes it necessary:

- Rounds (default 3 × 3 min) with 1 min rest between them. The clock stops during a count.
- **Scoring:** three judges, 10-point must system. Clean punches to the head or body (above the
  belt, from the front) count; blocked punches don't. Each knockdown costs a point on that round.
- **Knockdowns:** each clean punch drains health; at zero you're down. The referee counts to ten.
  To get up in VR, **hold your guard up by your face** for 1.5 s. Boxing resumes at eight at the
  earliest (mandatory eight count). Not up by ten = **KO**. Three knockdowns in one round = **TKO**.
- **Fouls:** low blows and punches to the back of the head (rabbit punches) don't score and earn a
  warning. From the third warning on, every foul costs a point.
- After the last round: unanimous, majority or split decision, or a draw.

Round count, round and rest length, bot skill, dummy sway and network ports are in
[`settings.cfg`](settings.cfg). Any of them can be overridden on the command line, after `--`:

```
godot --path . -- --rounds=1 --round-seconds=60 --bot-skill=0.9
```

## LAN play

- Both players pick **HOST LAN** or **JOIN LAN**. The joining game finds the host by UDP
  broadcast (port 47231), then connects over ENet (UDP port 47230).
- Windows will ask to allow Godot through the firewall the first time you host. Allow it on
  private networks.
- If discovery doesn't work on your network, join by address: `godot --path . -- --join=192.168.1.20`
  (the host's address is shown on its scoreboard while it waits).
- Two windows on one PC work too, which is handy for testing:
  `godot --path . --xr-mode off -- --mode=host` and `... -- --mode=join --join=127.0.0.1`.
- Over the internet it can work today if the host forwards UDP 47230 and the other player uses
  `--join=<public IP>`. Proper internet play (relay, matchmaking) is future work.

## Tests

```
GODOT=/path/to/Godot_v4.7.2-stable_win64_console.exe bash tests/run.sh
```

Runs headless with no headset: rules and hit-detection unit tests, a full bot-vs-bot match, and a
LAN match between two Godot processes on this PC (it checks that both sides agree on the result).
Feel in a real headset is the one thing these can't check.

Other launch options for testing: `--mode=practice|bot|host|join` (skip the lobby),
`--bot-vs-bot` (a bot drives your boxer), `--timescale=4`, `--quit-on-end`.

## Docs

- [docs/DESIGN.md](docs/DESIGN.md): how it works (architecture, hit detection, rules engine,
  networking) and where things live.

## Not built yet

Internet matchmaking · full-body avatars · real art and audio assets ·
in-game settings menu · bot difficulty presets · crowd sound · referee figure · stamina ·
clinch/break.
