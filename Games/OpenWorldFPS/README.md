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
- Runtime town pressure states (`Stable`, `Uneasy`, `Alert`, `Overrun`) driven by lion pressure and enemy population.
- Explicit 3D physics layer names in `project.godot`.

## Spawn and biome controls
- `world_seed` drives deterministic biome assignment for each chunk.
- Three town variants now exist (`market`, `fort`, `farm`) and spawn according to biome and distance tuning.
- `ChunkManager` applies distance-based density falloff so distant chunks produce fewer obstacles/creatures/towns:
  - `far_chunk_density` controls density at the edge of configured load distance.
  - `chunk_distance_falloff` controls how quickly the density curve decays.
- Config values are in `world_root.gd` and can be tuned in-editor (`far_chunk_density`, `chunk_distance_falloff`).

## Town pressure loop
- `LionPressureDirector` advances black mountain lion pressure and pushes stage/density updates into `ChunkManager`.
- `Chunk` maps lion pressure plus local enemy population into town states:
  - `Stable`: routine NPC placeholders and full travel safety.
  - `Uneasy`: warning beacons and lookout NPC placeholders.
  - `Alert`: barricades, defender NPC placeholders, lower travel safety, and extra pressure enemy placeholders.
  - `Overrun`: broken defenses, evacuation NPC placeholders, heavy warning artifacts, and the lowest travel safety.
- `ChunkManager` exposes aggregate town state, pressure enemy count, and travel safety for the HUD and future gameplay systems.
