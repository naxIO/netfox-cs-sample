# netfox CS Sample

A **Counter-Strike 1.6 inspired** multiplayer FPS built with [Godot 4.6](https://godotengine.org/) and the [netfox](https://github.com/foxssake/netfox) networking framework.

This is a community sample showcasing how to build a server-authoritative FPS with rollback netcode, client-side prediction, and latency compensation using netfox's `RollbackSynchronizer`, `RewindableAction`, and related systems.

> **Note:** This is a fork of the [netfox repository](https://github.com/foxssake/netfox). The game lives in `examples/multiplayer-fps/`.

## Features

- **Teams & Rounds** — Terrorists vs Counter-Terrorists with freeze-time, round timer, and win conditions
- **6 Weapons** — Knife, Glock, USP, AK-47, M4A1, AWP with per-weapon damage, fire rate, recoil, ammo, and reload
- **Economy System** — Kill/round rewards, loss streak bonus, buy menu (B-key), Kevlar & defuse kit
- **Bomb Plant/Defuse** — 2 bombsites, server-authoritative bomb logic, carrier tracking, drop on death
- **Grenades** — Flashbang (LOS + distance whiteout) and Smoke grenades
- **Rollback Netcode** — Server-authoritative with client-side prediction at 64 tick
- **Latency-Compensated Weapons** — `RewindableAction`-based hitscan firing inside the rollback loop
- **Frame-Rate Camera** — Mouse look renders at display refresh rate, not tick rate

## How to Run

1. Clone this repo
2. Open the project root in **Godot 4.6**
3. Run the main scene (`examples/multiplayer-fps/multiplayer-fps.tscn`)
4. Use the network popup to host/join a game

For multiple local clients, enable **auto-tile windows** in the netfox settings (already on by default).

## Controls

| Key | Action |
|---|---|
| WASD | Move |
| Mouse | Look |
| Left Click | Fire |
| R | Reload |
| 1-4 | Weapon slots |
| Scroll | Next/prev weapon |
| B | Buy menu |
| E | Use (plant/defuse bomb) |
| Tab | Scoreboard |
| Esc | Release mouse |

## Project Structure

```
examples/multiplayer-fps/
├── multiplayer-fps.tscn          # Main scene (map, spawns, UI, network)
├── characters/player.tscn        # Player prefab (CharacterBody3D)
├── scripts/
│   ├── player.gd                 # Movement, health, respawn
│   ├── player-input.gd           # Input gathering (BaseNetInput)
│   ├── weapon_manager.gd         # Weapon switching, ammo, models
│   ├── round-manager.gd          # Round state machine, win conditions
│   ├── team-manager.gd           # Team assignment (T/CT)
│   ├── economy_manager.gd        # Money, buy logic, rewards
│   ├── bomb.gd                   # Bomb plant/defuse/explode
│   ├── bombsite.gd               # Bombsite area detection
│   ├── grenade.gd                # Flash & smoke grenades
│   ├── bullethole.gd             # Decal pool
│   ├── node-pool.gd              # Object pooling utility
│   ├── player-spawner.gd         # Player spawn/despawn on connect
│   ├── data/weapon_data.gd       # Weapon stats resource
│   ├── data/weapon_registry.gd   # Weapon ID → resource mapping
│   └── ui/                       # HUD, buy menu, bomb HUD, crosshair
addons/
├── netfox/                       # Core: timing, rollback, synchronizers
├── netfox.extras/                # Weapons, input, state machines
├── netfox.internals/             # Internal utilities
└── netfox.noray/                 # NAT punchthrough & relay
```

## Netfox Patterns Used

- **`RollbackSynchronizer`** with `_rollback_tick()` for deterministic state sync
- **`RewindableAction`** for rollback-safe weapon firing
- **`TickInterpolator`** for smooth visuals between ticks
- **`BaseNetInput`** for input gathering with `_gather()`
- **`NetworkEvents`** for peer join/leave handling
- **`MultiplayerSynchronizer`** for non-rollback state (health, death, economy)
- **Self-RPC pattern** — direct-call for listen-server host, RPC for clients

## License

MIT — see [LICENSE](LICENSE).

Built on top of [netfox](https://github.com/foxssake/netfox) by [Fox's Sake Studio](https://foxssake.studio/).

## Credits

- [netfox](https://github.com/foxssake/netfox) — Networking framework by Tamás Gálffy / Fox's Sake
- Sound effects from [Sonniss GDC Bundle](https://sonniss.com/)
- Bullet hole texture by [musdasch](https://opengameart.org/users/musdasch) (CC0)
- Crosshair by [krazyjakee](https://github.com/krazyjakee) (CC0)
