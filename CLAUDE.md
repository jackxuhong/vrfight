# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

VR boxing game in **Godot 4.7 (GDScript, OpenXR, GL Compatibility renderer)** for Oculus Rift and
Quest 2 over Link (PC VR). It has three modes: practice vs a dummy, a match vs a bot, and 2-player
LAN. There are no asset files: the arena, meshes and sounds are all generated in code. Player docs
are in `README.md`; architecture is in `docs/DESIGN.md`, which should be updated along with the code.

## Commands

Godot is not on PATH. Use the **console** build (`Godot_v4.7.2-stable_win64_console.exe`) so output
reaches the terminal.

**Always pass `--xr-mode off` when running without a headset**, including headless runs and
`--import`. Otherwise the Oculus OpenXR runtime hangs startup indefinitely.

```bash
GODOT=/path/to/Godot_v4.7.2-stable_win64_console.exe bash tests/run.sh   # all checks
"$GODOT" --headless --xr-mode off --import                                # after adding scripts/classes
"$GODOT" --headless --xr-mode off -s res://tests/test_rules.gd            # one unit-test file
"$GODOT" --path . --xr-mode off                                           # play on desktop (mouse/keyboard)
"$GODOT" --path . --xr-mode off -- --mode=bot --bot-vs-bot --timescale=4  # watch a bot match
```

`tests/run.sh` runs these steps:
1. the rules and hit-detection unit tests
2. a full bot-vs-bot match (it greps for the `MATCH_OVER <json>` line)
3. a LAN host and client as two processes on this PC, which must print identical `MATCH_OVER` lines
4. a check that no log contains `SCRIPT ERROR` or `ERROR`

Unit tests are `extends SceneTree` scripts with a `check()` helper that print `ALL TESTS PASSED`.
A test file runs only if `run.sh` lists it in its `for t in rules hits` loop.

Game options come from `settings.cfg` and can be overridden after `--` as `--key=value`; dashes
become underscores (see `scripts/core/config.gd`). The launch-only keys are `mode`, `join`,
`bot_vs_bot`, `timescale` and `quit_on_end`.

To check visuals without a headset, render frames with
`--xr-mode off --write-movie out.png --fixed-fps 30 --quit-after N`.

## Architecture

- **A boxer is just a pose.** `Fighter` (`scripts/fighters/fighter.gd`) holds a head transform and
  two glove positions. One driver writes that pose each physics tick:
  - `VrRig`, or `DesktopRig` (which has the same method set, so `main.gd` keeps `rig` untyped)
  - `BotBrain`
  - `DummyBrain`
  - the network, through `_follow_remote` in `main.gd`

  Hit detection, scoring, the bot and the networking only use that pose, so every mode shares
  them. The torso is not tracked; it hangs under the head.
- **`scripts/main.gd` is the hub.** It holds the lobby and mode switching, the whole frame loop in
  `_physics_process` (driver → opponent → `step()` → hits → `match.tick` → net send → recovery →
  scoreboard), the match-event handling (sound, HUD, haptics, bot reactions) and every RPC. The
  scene `scenes/main.tscn` is a single node; everything else is built at runtime.
- **The rules are plain logic.** `BoxingMatch` (`scripts/core/boxing_match.gd`) is a `RefCounted`
  with no nodes. Feed it `tick(dt)` and `register_hit()`; it emits `event(what, data)`. Keep it free
  of nodes so `tests/test_rules.gd` can test it directly. Scoring randomness uses a fixed seed, so
  results are deterministic, and the LAN test depends on that.
- **Hits are computed, not physics.** `Fighter.punches_on()` detects them from zone spheres and a
  capsule, a minimum speed toward the zone, and a per-glove cooldown. It runs at 90 Hz, since glove
  speed is measured from the change in position per tick. `tests/test_hits.gd` covers it.
- **LAN networking.** `scripts/net/net.gd` only connects the two games: ENet on UDP 47230, with
  `VRFIGHT1` broadcast discovery on UDP 47231. The host is authoritative and owns the only
  `BoxingMatch`. Hits are detected by the attacker's machine; the client reports its own with
  `net_hit`, and the host checks the zone and caps the power before scoring them. Poses are sent at
  45 Hz unreliably; match state at 10 Hz. The host is red, the joiner blue.

## Conventions

- Tuning numbers (damage, speed thresholds, bot work rate) are first guesses that haven't been
  tested in a headset. Change them in the constants at the top of `boxing_match.gd`,
  `fighter.gd` and `bot_brain.gd`.
- Commit the `.gd.uid` files that Godot generates next to scripts. `.godot/` is ignored.
- Known limits and shortcuts are listed in `docs/DESIGN.md` under "Known limits". Keep that list
  current.
