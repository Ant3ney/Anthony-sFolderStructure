# OpenWorldFPS AI Behavior Framework

## Purpose
`AIController` provides a reusable Godot `CharacterBody3D` state machine for NPCs and hostile enemies. Entity differences are configured through `AIBehaviorProfile` resources instead of bespoke scripts, so creatures and enemies can share perception, pathing, and combat timing behavior.

## Files
- `scripts/ai/ai_controller.gd`: Shared runtime state machine.
- `scripts/ai/ai_behavior_profile.gd`: Resource schema for reusable AI tuning.
- `resources/ai/field_grazer_profile.tres`: Creature profile that evades the player.
- `resources/ai/raider_enemy_profile.tres`: Enemy profile that chases and attacks the player.
- `scenes/creatures/field_grazer.tscn`: Creature using `AIController`.
- `scenes/enemies/raider_enemy.tscn`: Enemy using `AIController`.
- `tests/ai_smoke_test.gd`: Headless verification for scene wiring and startup transitions.

## State Machine
The shared states are:
- `idle`: Waits in place before returning to patrol.
- `patrol`: Moves through profile patrol-point offsets relative to spawn position.
- `investigate`: Moves to the last known or heard target position.
- `evade`: Performs a short reposition away from a nearby threat.
- `chase`: Pursues a visible target or recently seen target.
- `attack`: Holds position, faces the target, and emits `attack_started` on cooldown.
- `flee`: Runs away from a threat after low health or emergency proximity.

Global perception transitions run before state-specific behavior. A chase profile moves visible targets into `chase` or `attack`; an evade profile moves nearby targets into `evade` or `flee`; low health can force `flee`.

## Shared Hooks
- Pathing: `_get_path_velocity(destination, speed, stop_distance)` currently returns direct planar steering and is the integration point for `NavigationAgent3D` later.
- Line of sight: `_has_line_of_sight(target)` uses a physics ray with the profile's `line_of_sight_mask`.
- Combat cooldown: `_is_attack_ready()` and `_use_attack_cooldown()` gate `attack_started` emissions.

## Data-Driven Profiles
Profiles configure:
- Identity and initial state.
- Target response: `ignore`, `evade`, or `chase`.
- Sight/hearing ranges, field of view, and LOS mask.
- Movement speeds, acceleration, patrol route, investigation memory, evade/flee timing, and safe distance.
- Attack range, cooldown, hold time, and damage.
- Flee health threshold and emergency-flee distance.

When editing `.tscn` or `.tres` files manually, serialize physics masks as numeric values. For example, `7` means layers 1, 2, and 3. GDScript can use bitwise expressions, but scene/resource files cannot safely use `1 | 2 | 4`.

## Current World Usage
`world_root.tscn` starts the player near chunk center and instantiates:
- `FieldGrazer`, using `field_grazer_profile.tres`, which transitions into `evade` when the player is nearby.
- `RaiderEnemy`, using `raider_enemy_profile.tres`, which transitions into `chase` and then `attack` when close enough.

`project.godot` names physics/render layer 4 as `AI`, and the player mask includes that layer so the player and AI bodies can collide.

## Verification
Run:

```bash
godot --headless --path Games/OpenWorldFPS --quit
godot --headless --path Games/OpenWorldFPS --script res://tests/ai_smoke_test.gd
```

The smoke test asserts that both concrete NPC scenes use `AIController`, that the creature transitions into `evade`, and that the enemy transitions into `chase` and remains in combat behavior.
