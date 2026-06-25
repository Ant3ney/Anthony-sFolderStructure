extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const WORLD_SCENE := preload("res://scenes/world_root.tscn")
const FIELD_GRAZER_SCENE := preload("res://scenes/creatures/field_grazer.tscn")
const RAIDER_ENEMY_SCENE := preload("res://scenes/enemies/raider_enemy.tscn")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/ai/ai_controller.gd")

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

	await process_frame
	await _step_physics(12)

	_expect(creature.get_script() == AI_CONTROLLER_SCRIPT, "FieldGrazer scene uses AIController")
	_expect(enemy.get_script() == AI_CONTROLLER_SCRIPT, "RaiderEnemy scene uses AIController")
	_expect(creature.behavior_profile != null, "FieldGrazer has a behavior profile")
	_expect(enemy.behavior_profile != null, "RaiderEnemy has a behavior profile")
	_expect(creature.get_current_state_name() in ["evade", "flee"], "FieldGrazer evades or flees after seeing the player")
	_expect(enemy.get_current_state_name() in ["chase", "attack"], "RaiderEnemy chases or attacks after seeing the player")
	_expect(_world_scene_uses_ai(), "WorldRoot instantiates creature and enemy AI scenes")

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
		and world.get_node("FieldGrazer").get_script() == AI_CONTROLLER_SCRIPT \
		and world.get_node("RaiderEnemy").get_script() == AI_CONTROLLER_SCRIPT
	world.free()
	return has_ai

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failures += 1
	printerr("FAIL: %s" % message)
