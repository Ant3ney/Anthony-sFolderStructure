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
- Deterministic placeholder terrain and obstacles per chunk.
- Explicit 3D physics layer names in `project.godot`.
- Shared AI behavior framework with data-driven creature and enemy profiles.

## AI framework
NPC behavior is implemented by `scripts/ai/ai_controller.gd` and tuned through `AIBehaviorProfile` resources. The world currently includes a `FieldGrazer` creature that evades the player and a `RaiderEnemy` that chases and attacks.

See `docs/ai_behavior_framework.md` for the state-machine design and run:

```bash
godot --headless --path Games/OpenWorldFPS --script res://tests/ai_smoke_test.gd
```
