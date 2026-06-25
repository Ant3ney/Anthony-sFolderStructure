extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const WORLD_SCENE := preload("res://scenes/world_root.tscn")
const FIELD_GRAZER_SCENE := preload("res://scenes/creatures/field_grazer.tscn")
const RAIDER_ENEMY_SCENE := preload("res://scenes/enemies/raider_enemy.tscn")
const BLACK_MOUNTAIN_LION_SCENE := preload("res://scenes/creatures/black_mountain_lion.tscn")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/ai/ai_controller.gd")
const BLACK_MOUNTAIN_LION_SCRIPT := preload("res://scripts/ai/black_mountain_lion_controller.gd")
const GAME_LOOP_SETTINGS_SCRIPT := preload("res://scripts/world/game_loop_settings.gd")

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var test_root := Node3D.new()
	test_root.name = "AISmokeTestRoot"
	root.add_child(test_root)

	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = "Player"
	player.position = Vector3(0.0, 1.0, 0.0)
	test_root.add_child(player)

	var creature := FIELD_GRAZER_SCENE.instantiate()
	creature.position = Vector3(4.0, 1.0, 0.0)
	test_root.add_child(creature)

	var enemy := RAIDER_ENEMY_SCENE.instantiate()
	enemy.position = Vector3(8.0, 1.0, 0.0)
	test_root.add_child(enemy)

	var lion := BLACK_MOUNTAIN_LION_SCENE.instantiate()
	lion.position = Vector3(14.0, 1.0, 0.0)
	test_root.add_child(lion)

	await process_frame
	await _step_physics(12)

	_expect(creature.get_script() == AI_CONTROLLER_SCRIPT, "FieldGrazer scene uses AIController")
	_expect(enemy.get_script() == AI_CONTROLLER_SCRIPT, "RaiderEnemy scene uses AIController")
	_expect(lion.get_script() == BLACK_MOUNTAIN_LION_SCRIPT, "BlackMountainLion scene uses specialized controller")
	_expect(creature.behavior_profile != null, "FieldGrazer has a behavior profile")
	_expect(enemy.behavior_profile != null, "RaiderEnemy has a behavior profile")
	_expect(lion.behavior_profile != null, "BlackMountainLion has a behavior profile")
	_expect(creature.get_current_state_name() in ["evade", "flee"], "FieldGrazer evades or flees after seeing the player")
	_expect(enemy.get_current_state_name() in ["chase", "attack"], "RaiderEnemy chases or attacks after seeing the player")
	_expect(lion.get_current_state_name() != "attack", "BlackMountainLion keeps distance outside close range")

	var close_lion := BLACK_MOUNTAIN_LION_SCENE.instantiate()
	close_lion.position = Vector3(1.25, 1.0, 0.0)
	var health_before := float(player.call("get_health"))
	test_root.add_child(close_lion)
	await process_frame
	await _step_physics(8)
	_expect(float(player.call("get_health")) < health_before, "BlackMountainLion attacks only after close proximity is reached")

	_expect(_world_scene_uses_ai(), "WorldRoot instantiates baseline AI and lion pressure systems")
	var pressure_snapshot := await _pressure_director_snapshot()
	_expect(int(pressure_snapshot["stage"]) >= 3, "Lion pressure advances village pressure stages")
	_expect(int(pressure_snapshot["count"]) > 0, "Lion pressure spawns migration lions over time")
	_expect(int(pressure_snapshot["chunk_stage"]) == int(pressure_snapshot["stage"]), "Chunk villages receive lion pressure stages")
	_expect(int(pressure_snapshot["settlement_state"]) >= 2, "Town pressure advances into Alert or Overrun")
	_expect(float(pressure_snapshot["travel_safety"]) < 1.0, "Town pressure lowers travel safety in affected chunks")
	_expect(int(pressure_snapshot["pressure_enemy_density"]) > 0, "Town pressure adds pressure enemy density")
	_expect(float(pressure_snapshot["travel_safety_api"]) == float(pressure_snapshot["travel_safety"]), "ChunkManager exposes documented travel safety")
	_expect(int(pressure_snapshot["pressure_enemy_count_api"]) == int(pressure_snapshot["pressure_enemy_density"]), "ChunkManager exposes documented pressure enemy count")

	var tuning_snapshot := await _game_loop_tuning_snapshot()
	_expect(float(tuning_snapshot["pressure_tick_seconds"]) < 45.0, "Game loop settings speed up lion pressure ticks")
	_expect(float(tuning_snapshot["pressure_per_tick"]) > 0.18, "Game loop settings scale pressure gained per tick")
	_expect(int(tuning_snapshot["stage"]) >= 2, "Game loop settings shift pressure stage curve")
	_expect(bool(tuning_snapshot["debug_visible"]), "Debug view can be toggled on")
	_expect(String(tuning_snapshot["debug_text"]).find("Lions:") >= 0, "Debug view shows lion counts")
	_expect(String(tuning_snapshot["debug_text"]).find("Alert:") >= 0, "Debug view shows alert level")
	_expect(String(tuning_snapshot["debug_text"]).find("AI States:") >= 0, "Debug view shows active AI states")
	_expect((tuning_snapshot["ai_state_counts"] as Dictionary).size() > 0, "Debug snapshot exposes active AI state counts")
	_expect(int(tuning_snapshot["snapshot_schema"]) == 1, "World snapshot stub returns schema version")

	test_root.queue_free()
	if _failures > 0:
		quit(1)
	else:
		print("AI smoke test passed.")
		quit(0)

func _step_physics(frames: int) -> void:
	for i in frames:
		await physics_frame

func _world_scene_uses_ai() -> bool:
	var world := WORLD_SCENE.instantiate()
	var has_ai: bool = world.has_node("FieldGrazer") \
		and world.has_node("RaiderEnemy") \
		and world.has_node("LionPressureDirector") \
		and world.get_node("FieldGrazer").get_script() == AI_CONTROLLER_SCRIPT \
		and world.get_node("RaiderEnemy").get_script() == AI_CONTROLLER_SCRIPT
	world.free()
	return has_ai

func _pressure_director_snapshot() -> Dictionary:
	var snapshot := {
		"stage": 0,
		"count": 0,
		"chunk_stage": -1,
		"settlement_state": 0,
		"travel_safety": 1.0,
		"pressure_enemy_density": 0,
		"travel_safety_api": 1.0,
		"pressure_enemy_count_api": 0,
	}
	var world := WORLD_SCENE.instantiate()
	root.add_child(world)
	await process_frame
	await _step_physics(2)

	var director := world.get_node("LionPressureDirector")
	var chunk_manager := world.get_node("ChunkManager")
	director.call("advance_pressure", 0.72, true)
	await process_frame
	await _step_physics(4)

	snapshot["stage"] = int(director.call("get_pressure_stage"))
	snapshot["count"] = int(director.call("get_active_lion_count"))
	snapshot["chunk_stage"] = int(chunk_manager.call("get_lion_pressure_stage"))
	var settlement_summary: Dictionary = director.call("get_settlement_summary")
	snapshot["settlement_state"] = int(settlement_summary.get("state", 0))
	snapshot["travel_safety"] = float(settlement_summary.get("travel_safety", 1.0))
	snapshot["pressure_enemy_density"] = int(settlement_summary.get("pressure_enemy_density", 0))
	snapshot["travel_safety_api"] = float(chunk_manager.call("get_travel_safety"))
	snapshot["pressure_enemy_count_api"] = int(chunk_manager.call("get_pressure_enemy_count"))
	world.queue_free()
	return snapshot

func _game_loop_tuning_snapshot() -> Dictionary:
	var snapshot := {
		"pressure_tick_seconds": 45.0,
		"pressure_per_tick": 0.18,
		"stage": 0,
		"debug_visible": false,
		"debug_text": "",
		"ai_state_counts": {},
		"snapshot_schema": 0,
	}
	var settings := GAME_LOOP_SETTINGS_SCRIPT.new()
	settings.lion_creep_rate = 2.0
	settings.threat_scale = 1.5
	settings.wave_size_multiplier = 1.4
	settings.settlement_pressure_multiplier = 1.25
	settings.debug_view_enabled = true
	settings.inspector_view_enabled = true
	settings.snapshot_path = "user://ai_smoke_world_state_snapshot.json"

	var world := WORLD_SCENE.instantiate()
	world.game_loop_settings = settings
	root.add_child(world)
	await process_frame
	await _step_physics(2)

	var director := world.get_node("LionPressureDirector")
	director.call("advance_pressure", 0.36, true)
	await process_frame
	await _step_physics(4)

	world.call("set_debug_view_visible", true)
	world.call("set_inspector_view_visible", true)
	var diagnostics: Dictionary = director.call("get_pressure_diagnostics")
	var debug_snapshot: Dictionary = world.call("get_game_loop_debug_snapshot")
	var world_snapshot: Dictionary = world.call("save_world_snapshot")
	var debug_label := world.get_node("HUD/DebugPanel/DebugRows/DebugLabel") as Label

	snapshot["pressure_tick_seconds"] = float(diagnostics.get("pressure_tick_seconds", 45.0))
	snapshot["pressure_per_tick"] = float(diagnostics.get("pressure_per_tick", 0.18))
	snapshot["stage"] = int(director.call("get_pressure_stage"))
	snapshot["debug_visible"] = bool(debug_snapshot.get("debug_visible", false))
	snapshot["debug_text"] = debug_label.text
	snapshot["ai_state_counts"] = debug_snapshot.get("ai_state_counts", {})
	snapshot["snapshot_schema"] = int(world_snapshot.get("schema_version", 0))
	world.queue_free()
	return snapshot

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failures += 1
	printerr("FAIL: %s" % message)
