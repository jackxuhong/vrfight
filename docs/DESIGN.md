# VR Fight design

How the game works, for whoever changes it next. Player-facing info is in the
[README](../README.md).

## The big idea: a boxer is a head and two gloves

Every boxer, whoever controls it, is a `Fighter` (`scripts/fighters/fighter.gd`): a head transform
and two glove positions in world space. Something else writes that pose every physics tick:

| Driver | Who | File |
|--------|-----|------|
| `VrRig` | you, in a headset (XROrigin + camera + two Touch controllers) | `scripts/rigs/vr_rig.gd` |
| `DesktopRig` | you, with keyboard and mouse (same methods as `VrRig`) | `scripts/rigs/desktop_rig.gd` |
| `BotBrain` | the Single Player opponent, or your own boxer with `--bot-vs-bot` | `scripts/fighters/bot_brain.gd` |
| `DummyBrain` | the practice dummy | `scripts/fighters/dummy_brain.gd` |
| network | the other player in a LAN match (smoothed toward their latest pose) | `scripts/main.gd` (`_follow_remote`) |

Because everything works on that one shape, hit detection, scoring, bots, and the network code are
the same in every mode. The torso is not tracked: it hangs under the head.

## Frame loop

All game logic runs in `Main._physics_process` (`scripts/main.gd`), in this order:

1. My driver writes my pose (rig, or autopilot bot); the rig is pushed back inside the ropes and
   out of the opponent.
2. The opponent's driver writes theirs (dummy, bot or network).
3. `Fighter.step()`: glove velocities from the change in position since the last tick.
4. Hit detection (below).
5. `BoxingMatch.tick()`, if this machine runs the rules.
6. Network send, knockdown-recovery check, scoreboard.

Physics runs at the headset refresh rate in VR (90 Hz by default) so glove speeds are accurate.

## Hit detection

`Fighter.punches_on(other)`. Zones on the defender: a head sphere, a body capsule (chest to belt),
and a sphere below the belt. A glove **lands** when, in one tick, it:

- enters a zone (it wasn't touching it last tick),
- moves faster than 1.6 m/s toward the zone's centre (slower contact is a push), and
- hasn't landed in the last 0.3 s.

Each landed punch reports its zone, speed and power (speed / 7, capped at 1.5). It is
**blocked** if a defending glove is touching the attacking glove, and **behind** (a rabbit punch)
if it travelled the way the defender faces. `tests/test_hits.gd` covers these cases.

## Rules engine

`BoxingMatch` (`scripts/core/boxing_match.gd`) is plain logic with no nodes: feed it `tick(dt)` and
`register_hit(...)`, and it emits events (`round_start`, `hit`, `knockdown`, `count`, `resume`,
`foul`, `round_end`, `match_over`). Main turns events into sound, the HUD, the scoreboard,
haptics and bot reactions. Being plain logic, it is unit-tested directly (`tests/test_rules.gd`).

- **Health and knockdowns:** clean head hits take 6 × power, body hits 4 × power. At 0 the boxer is
  down; getting up restores some health (less after each knockdown), and rest periods restore 25.
- **Judges:** each judge sees every clean punch with ±30% personal variation (fixed seed, so a
  fight always scores the same). A round within 10% is even (10-10); otherwise it goes 10-9 to the
  boxer who did more. Knockdowns and foul deductions come off afterwards.
- **Getting up:** a bot gets up at a count it picks when it goes down (less likely to get up the
  more often it has been down). A player gets up by holding their guard up for 1.5 s.

Tuning numbers (damage, bot work rate) are first guesses from bot-vs-bot runs and need play
testing in a headset.

## Bot

`BotBrain` keeps to its favourite range (0.75 m head to head), circles at random, and bobs its
head. It throws combos built from jab, cross, hook (a curved path), uppercut (from below) and body
shots, aiming at the opponent's live zones. When a glove comes fast at its head, it reacts once
per punch: tighten the guard, slip sideways, or neither. Its `skill` (0 to 1, from `settings.cfg`)
scales reaction chance, accuracy, hand speed and work rate.

## Networking (LAN)

`Net` (`scripts/net/net.gd`) only connects players. The game's RPCs are on `Main`.

- **Find:** the host broadcasts `VRFIGHT1` on UDP 47231 every second. A joining game listens, then
  connects to the sender over ENet on UDP 47230. `--join=<ip>` skips discovery.
- **The host runs the rules.** It owns the only `BoxingMatch`. It sends every match event to the
  client (reliable) and the clock and health 10 times a second (unreliable). The host is red, the
  joined player blue.
- **Poses:** each side sends its own head and gloves 45 times a second (unreliable, ordered). The
  other side smooths toward the latest one.
- **Hits are detected by the puncher.** Each machine checks its own gloves against the opponent as
  it sees them, so landing a punch feels instant. The client reports its hits to the host
  (`net_hit`), which checks them (zone name, power capped) and scores them. That trusts the
  client, which is fine on a LAN but not for public internet play.
- A knockdown recovery on the client is sent to the host as `net_recover`.

## Where things live

```
project.godot          engine config (OpenXR on, Compatibility renderer, 90 Hz physics)
settings.cfg           match, bot, practice and network settings
scenes/main.tscn       a single node; everything else is built in code
scripts/main.gd        entry point: lobby, modes, frame loop, match events, RPCs, HUD
scripts/core/          config loading, BoxingMatch rules engine
scripts/fighters/      Fighter (pose, zones, hit detection), BotBrain, DummyBrain
scripts/rigs/          VrRig, DesktopRig
scripts/net/           Net: ENet host/join and LAN discovery
scripts/world/         Arena (ring geometry, lights), Sfx (synthesized sounds)
tests/                 unit tests and run.sh (all headless checks)
```

## Known limits

- The client is trusted with its own hits (see Networking).
- Each player sees the other's punches about 30 ms late after smoothing, plus network delay.
- There is no fade when you're moved back to your corner between rounds.
- The bot's gloves pass through its target's head instead of stopping on contact.
- On Windows, a broadcast from one process should reach a listener in another on the same PC (the
  test suite relies on this). Some routers and networks block broadcast; use `--join` there.
