# OpenWorldFPS (Godot scaffold)

This directory contains a minimal Godot 4 scene scaffold for a 3D open-world FPS prototype.

## Launch
1. Open this folder in Godot 4.
2. Open `project.godot`.
3. Press `Run Project`.

The world bootstraps a chunked terrain around the player using a deterministic seed.

## Scope of the scaffold
- Baseline input for movement/jump/run and mouse look.
- CharacterBody3D player with camera and grounded movement.
- Chunk manager with configurable radius and seed-driven chunk generation.
- Deterministic biome-aware procedural world population with placeholder towns, creature clusters, and hostile units.
- Runtime town pressure states (`Stable`, `Uneasy`, `Alert`, `Overrun`) driven by black mountain lion pressure, nearby active lions, and hostile population.
- Global game-loop settings for time-of-day pace, lion pressure cadence, settlement threat scaling, and AI difficulty multipliers.
- Lightweight debug/inspector HUD and local world-state snapshot stubs.
- Explicit 3D physics layer names in `project.godot`.

## Spawn and biome controls
- `world_seed` drives deterministic biome assignment for each chunk.
- Three town variants now exist (`market`, `fort`, `farm`) and spawn according to biome and distance tuning.
- `ChunkManager` applies distance-based density falloff so distant chunks produce fewer obstacles/creatures/towns:
  - `far_chunk_density` controls density at the edge of configured load distance.
  - `chunk_distance_falloff` controls how quickly the density curve decays.
- Config values are in `world_root.gd` and can be tuned in-editor (`far_chunk_density`, `chunk_distance_falloff`).

## Game loop tuning
- Primary pacing values live in `resources/world/game_loop_settings.tres`.
- `time_scale`, `starting_hour`, and `real_seconds_per_game_day` control time-of-day progression and sun intensity.
- `difficulty_multiplier`, `threat_scale`, `lion_creep_rate`, `wave_size_multiplier`, and `settlement_pressure_multiplier` shape pressure cadence, lion wave size, migration pace, and settlement pressure curves.
- `ai_health_multiplier`, `ai_damage_multiplier`, `ai_movement_multiplier`, and `ai_perception_multiplier` are applied to active AI without mutating shared behavior profiles.
- `debug_view_enabled` and `inspector_view_enabled` set initial diagnostics visibility. Runtime input actions are `toggle_debug_view`, `toggle_inspector_view`, `save_world_snapshot`, and `load_world_snapshot`.

## Town pressure states
- Chunks compute a settlement state for generated towns from global lion pressure, nearby active lion positions, and local hostile population.
- Towns render placeholder state artifacts: stable residents, uneasy warning flags/lookouts, alert barricades/defenders, and overrun smoke/refugees/pressure enemies.
- `ChunkManager` propagates alerts to neighboring loaded settlements and exposes a town pressure summary for HUD warnings.
- Higher town pressure lowers the chunk travel-safety modifier and can add pressure enemy density near affected towns.

## Diagnostics and snapshots
- The debug HUD reports lion counts, player alert, town state, and active AI state counts.
- Inspector mode adds effective pressure tick, threat scale, lion creep rate, and snapshot path details.
- `WorldRoot.save_world_snapshot()` writes a JSON-compatible placeholder snapshot to `snapshot_path`; `load_world_snapshot()` restores time, player position, and lion pressure level only.
