# Netfox Project

## Projekt-Kontext
Wir arbeiten am **Multiplayer-FPS-Beispiel** unter `/examples/multiplayer-fps/`.
Godot 4.6 mit dem netfox Networking-Framework. Sprache: GDScript.

## Multiplayer-FPS Struktur

**Architektur:** Server-autoritativ mit Rollback (Client-Side Prediction)

### Dateien
- `multiplayer-fps.tscn` — Hauptszene (Map, 5 Spawn Points, UI, Network)
- `characters/player.tscn` — Spieler-Prefab (CharacterBody3D)
- `scripts/player.gd` — Bewegung (Speed 5, Jump 5), Health (100 HP), Respawn
- `scripts/player-input.gd` — Input-Gathering (extends `BaseNetInput`), Mouse Sensitivity 0.005
- `scripts/player-weapon.gd` — Hitscan-Waffe (extends `NetworkWeaponHitscan3D`), 34 DMG/Hit, 0.25s Cooldown
- `scripts/player-spawner.gd` — Spieler spawnen/despawnen bei Connect/Disconnect
- `scripts/bullethole.gd` — Bullet-Hole Decal-Pool (max 20)
- `scripts/ui/` — Crosshair, Health-Bar, 3D-Projection, Window-Resize

### Netzwerk-Setup
- `RollbackSynchronizer` synct: transform, velocity, head rotation
- Inputs: movement, jump, fire, look_angle
- `MultiplayerSynchronizer` repliziert: health, death_tick, respawn_position
- `TickInterpolator` für smooth visuals zwischen Ticks
- Avatar-Body Authority: Server (ID 1), Input-Authority: jeweiliger Peer

### Gameplay
- WASD + Maus FPS-Steuerung
- 3 Hits = Tod (3x34 = 102 > 100 HP)
- Respawn an deterministischem Spawn Point (Hash-basiert)
- Sounds: fire.mp3, hit.wav, death.wav

## Netfox Framework (Addon)

### Kern-Systeme (Autoloads)
- `NetworkTime` — Zentraler Tick-Loop (Projekt-Default: 24 Hz)
- `NetworkTimeSynchronizer` — Clock-Sync zum Server
- `NetworkRollback` — Orchestriert Rollback
- `NetworkEvents` — Event-Broadcasting (on_client_start, on_server_start, on_peer_join, etc.)
- `RollbackSimulationServer` — Führt Physics/Logic während Rollback aus
- `NetworkHistoryServer` — State/Input History
- `NetworkSynchronizationServer` — Paket-Übertragung
- `NetworkIdentityServer` — Node-ID-Mapping

### Custom Nodes
- `RollbackSynchronizer` — Deterministische State-Sync mit Rollback + `_rollback_tick(delta, tick, is_fresh)`
- `StateSynchronizer` — Einfachere State-Sync ohne Rollback
- `TickInterpolator` — Smooth Interpolation zwischen Ticks
- `RewindableAction` — Rollback-fähige Actions (fire, abilities)
- `PredictiveSynchronizer` — Client-Side Prediction

### Extras (netfox.extras)
- `BaseNetInput` — Basis-Klasse für Input-Gathering mit `_gather()`
- `NetworkWeaponHitscan3D` — Hitscan-Waffen mit Latenz-Kompensation
- `NetworkWeapon3D/2D` — Projektil-Waffen
- `RewindableStateMachine` / `RewindableState` — Rollback-fähige State Machine
- `NetworkRigidBody2D/3D` — Physics-Sync mit Rollback
- `NetworkSimulator` — Latenz/Packet-Loss Simulation
- `RewindableRandomNumberGenerator` — Deterministische RNG

### Noray (netfox.noray)
- NAT Punchthrough + Relay-Fallback
- OpenID/PrivateID System

## Doku
- Framework-Docs: `/docs/netfox/`, `/docs/netfox.extras/`, `/docs/netfox.noray/`
- Tutorials: `/docs/netfox/tutorials/`
- Guides: `/docs/netfox/guides/`
