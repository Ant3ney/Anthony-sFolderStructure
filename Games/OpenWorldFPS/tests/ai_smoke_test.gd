extends SceneTree

const WORLD_SCENE := preload("res://scenes/world_root.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := WORLD_SCENE.instantiate()
	root.add_child(world)

	var grazer := world.get_node_or_null("FieldGrazer")
	var raider := world.get_node_or_null("RaiderEnemy")
	if not _expect(grazer != null, "FieldGrazer is present"):
		_finish()
		return
	if not _expect(raider != null, "RaiderEnemy is present"):
		_finish()
		return
	if not _expect(grazer.has_signal("state_changed"), "FieldGrazer uses AIController"):
		_finish()
		return
	if not _expect(raider.has_signal("state_changed"), "RaiderEnemy uses AIController"):
		_finish()
		return

	var grazer_states: Array[String] = []
	var raider_states: Array[String] = []
	grazer.connect("state_changed", func(_previous_state: StringName, current_state: StringName) -> void:
		grazer_states.append(String(current_state))
	)
	raider.connect("state_changed", func(_previous_state: StringName, current_state: StringName) -> void:
		raider_states.append(String(current_state))
	)

	await process_frame
	for frame in 120:
		await physics_frame

	_expect(grazer_states.has("evade"), "FieldGrazer transitions into evade")
	_expect(raider_states.has("chase"), "RaiderEnemy transitions into chase")
	_expect(["chase", "attack"].has(String(raider.get_state())), "RaiderEnemy remains in combat behavior")
	_finish()

func _expect(condition: bool, message: String) -> bool:
	if condition:
		print("PASS: %s" % message)
		return true
	push_error("FAIL: %s" % message)
	_failures.append(message)
	return false

func _finish() -> void:
	if _failures.is_empty():
		print("AI smoke test passed.")
		quit(0)
	else:
		print("AI smoke test failed: %s" % ", ".join(_failures))
		quit(1)
