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
- Towns progress through Stable, Uneasy, Alert, and Overrun pressure states as lion pressure and enemy density rise.
- Explicit 3D physics layer names in `project.godot`.

## Spawn and biome controls
- `world_seed` drives deterministic biome assignment for each chunk.
- Three town variants now exist (`market`, `fort`, `farm`) and spawn according to biome and distance tuning.
- Pressure state adds warning markers, temporary defenses, NPC posture placeholders, travel safety changes, and pressure enemy density in affected chunks.
- `ChunkManager` applies distance-based density falloff so distant chunks produce fewer obstacles/creatures/towns:
  - `far_chunk_density` controls density at the edge of configured load distance.
  - `chunk_distance_falloff` controls how quickly the density curve decays.
- Config values are in `world_root.gd` and can be tuned in-editor (`far_chunk_density`, `chunk_distance_falloff`).
