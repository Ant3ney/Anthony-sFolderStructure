extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const WORLD_SCENE := preload("res://scenes/world_root.tscn")
const FIELD_GRAZER_SCENE := preload("res://scenes/creatures/field_grazer.tscn")
const RAIDER_ENEMY_SCENE := preload("res://scenes/enemies/raider_enemy.tscn")
const BLACK_MOUNTAIN_LION_SCENE := preload("res://scenes/creatures/black_mountain_lion.tscn")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/ai/ai_controller.gd")
const BLACK_MOUNTAIN_LION_SCRIPT := preload("res://scripts/ai/black_mountain_lion_controller.gd")

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
	_expect(int(pressure_snapshot["settlement_state"]) >= 2, "Town settlement state reaches Alert under pressure")
	_expect(float(pressure_snapshot["travel_safety"]) < 0.9, "Pressured towns lower loaded chunk travel safety")
	_expect(int(pressure_snapshot["pressure_enemy_count"]) > 0, "Alert towns add pressure enemy density")
	_expect(bool(pressure_snapshot["has_state_artifacts"]), "Town pressure renders warning, NPC, and defense artifacts")

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
		"pressure_enemy_count": 0,
		"has_state_artifacts": false,
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
	var summary: Dictionary = chunk_manager.call("get_settlement_pressure_summary")
	snapshot["settlement_state"] = int(summary["state"])
	snapshot["travel_safety"] = float(summary["travel_safety_scale"])
	snapshot["pressure_enemy_count"] = int(summary["pressure_enemy_count"])
	snapshot["has_state_artifacts"] = _count_group_members(world, "settlement_pressure_artifacts") > 0
	world.queue_free()
	return snapshot

func _count_group_members(node: Node, group_name: String) -> int:
	var count := 0
	if node.is_in_group(group_name):
		count += 1
	for child in node.get_children():
		count += _count_group_members(child, group_name)
	return count

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failures += 1
	printerr("FAIL: %s" % message)
