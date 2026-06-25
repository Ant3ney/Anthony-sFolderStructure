extends Node
class_name LionPressureDirector

signal pressure_changed(stage: int, pressure_level: float, warning: String, active_lions: int)
signal migration_wave_started(destination: Vector3, spawned: int, stage: int)
signal settlement_pressure_changed(summary: Dictionary)

const PRESSURE_THRESHOLDS := [0.16, 0.40, 0.70, 1.0]
const WARNING_TEXT := [
	"Black Mountain Lions: quiet",
	"Black Mountain Lions: tracks near villages",
	"Black Mountain Lions: prowling village edges",
	"Black Mountain Lions: encroaching on roads",
	"Black Mountain Lions: villages under pressure"
]
const GameLoopSettingsResource := preload("res://scripts/world/game_loop_settings.gd")

@export_node_path("Node3D") var chunk_manager_path: NodePath
@export_node_path("CharacterBody3D") var player_path: NodePath
@export var black_mountain_lion_scene: PackedScene
@export var game_loop_settings: GameLoopSettingsResource
@export_range(5.0, 300.0, 1.0) var pressure_tick_seconds: float = 45.0
@export_range(0.01, 1.0, 0.01) var pressure_per_tick: float = 0.18
@export_range(0.0, 120.0, 1.0) var first_wave_delay: float = 12.0
@export_range(8.0, 80.0, 1.0) var min_spawn_radius: float = 24.0
@export_range(12.0, 120.0, 1.0) var max_spawn_radius: float = 42.0
@export_range(1, 8, 1) var base_lions_per_wave: int = 1
@export_range(1, 12, 1) var max_lions_per_wave: int = 7
@export_range(1, 60, 1) var max_active_lions: int = 30
@export_range(1.0, 5.0, 0.1) var max_pressure_level: float = 2.0
@export_range(0.5, 20.0, 0.5) var settlement_refresh_seconds: float = 3.0

var _chunk_manager: Node
var _player: Node3D
var _pressure_level: float = 0.0
var _pressure_stage: int = 0
var _wave_timer: float = 0.0
var _settlement_refresh_timer: float = 0.0
var _active_lions: Array[Node] = []
var _settlement_summary: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_resolve_references()
	_seed_rng()
	_wave_timer = maxf(_effective_pressure_tick_seconds() - _effective_first_wave_delay(), 0.0)
	_settlement_summary = _default_settlement_summary()
	_apply_pressure_to_chunks()
	_emit_pressure_changed()

func _physics_process(delta: float) -> void:
	var tick_seconds := _effective_pressure_tick_seconds()
	if tick_seconds <= 0.0:
		return

	var refresh_seconds := _effective_settlement_refresh_seconds()
	_settlement_refresh_timer += delta
	if _settlement_refresh_timer >= refresh_seconds:
		_settlement_refresh_timer = fmod(_settlement_refresh_timer, refresh_seconds)
		_apply_pressure_to_chunks()
		_emit_settlement_pressure_changed()

	_wave_timer += delta
	if _wave_timer < tick_seconds:
		return

	_wave_timer = fmod(_wave_timer, tick_seconds)
	advance_pressure(pressure_per_tick, true)

func advance_pressure(amount: float, spawn_wave: bool = true) -> void:
	if amount <= 0.0:
		return

	_set_pressure(_pressure_level + _effective_pressure_amount(amount))
	if spawn_wave:
		_spawn_migration_wave()
		_apply_pressure_to_chunks()
	_emit_pressure_changed()

func set_pressure_level(value: float) -> void:
	_set_pressure(value)
	_emit_pressure_changed()

func set_game_loop_settings(settings: Resource) -> void:
	if settings == null:
		game_loop_settings = null
	else:
		game_loop_settings = settings as GameLoopSettingsResource
	_wave_timer = minf(_wave_timer, _effective_pressure_tick_seconds())
	_apply_pressure_to_chunks()
	_emit_pressure_changed()

func get_pressure_level() -> float:
	return _pressure_level

func get_pressure_stage() -> int:
	return _pressure_stage

func get_active_lion_count() -> int:
	_cleanup_active_lions()
	return _active_lions.size()

func get_warning_text() -> String:
	return WARNING_TEXT[_pressure_stage]

func get_settlement_summary() -> Dictionary:
	return _settlement_summary.duplicate(true)

func get_settlement_state_name() -> String:
	return String(_settlement_summary.get("state_name", "Stable"))

func get_settlement_warning_text() -> String:
	return String(_settlement_summary.get("warning", "Stable towns: roads clear"))

func get_settlement_travel_safety() -> float:
	return float(_settlement_summary.get("travel_safety", 1.0))

func get_pressure_diagnostics() -> Dictionary:
	return {
		"pressure_tick_seconds": _effective_pressure_tick_seconds(),
		"pressure_per_tick": _effective_pressure_amount(pressure_per_tick),
		"threat_scale": _settings_value("effective_threat_scale", 1.0),
		"lion_creep_rate": _settings_value("effective_lion_creep_rate", 1.0),
		"wave_size_multiplier": _settings_value("effective_wave_size_multiplier", 1.0),
		"active_lions": get_active_lion_count(),
		"max_active_lions": _effective_max_active_lions(),
	}

func _resolve_references() -> void:
	if chunk_manager_path != NodePath() and has_node(chunk_manager_path):
		_chunk_manager = get_node(chunk_manager_path)
	if player_path != NodePath() and has_node(player_path):
		_player = get_node(player_path) as Node3D

func _seed_rng() -> void:
	var seed_value := 20260625
	if _chunk_manager != null:
		var chunk_seed = _chunk_manager.get("seed")
		if chunk_seed != null:
			seed_value = int(chunk_seed)
	_rng.seed = seed_value ^ 0x6d2b79f5

func _set_pressure(value: float) -> void:
	_pressure_level = clampf(value, 0.0, max_pressure_level)
	_pressure_stage = _stage_for_pressure(_pressure_level)
	_apply_pressure_to_chunks()

func _stage_for_pressure(value: float) -> int:
	var stage := 0
	for i in PRESSURE_THRESHOLDS.size():
		if value >= float(PRESSURE_THRESHOLDS[i]):
			stage = i + 1
	return stage

func _density_scale() -> float:
	var pressure_component := (_pressure_level * 0.75) + (float(_pressure_stage) * 0.25)
	return 1.0 + (pressure_component * _settings_value("effective_threat_scale", 1.0))

func _apply_pressure_to_chunks() -> void:
	if _chunk_manager == null:
		_resolve_references()
	if _chunk_manager != null and _chunk_manager.has_method("set_lion_pressure"):
		_chunk_manager.call("set_lion_pressure", _pressure_stage, _density_scale(), _collect_active_lion_positions())
	_update_settlement_summary()

func _spawn_migration_wave() -> void:
	_cleanup_active_lions()
	if black_mountain_lion_scene == null:
		push_warning("LionPressureDirector needs a black mountain lion scene.")
		return

	var remaining_slots := _effective_max_active_lions() - _active_lions.size()
	if remaining_slots <= 0:
		return

	var destination := _pick_migration_destination()
	var spawn_count: int = min(_spawn_count_for_pressure(), remaining_slots)
	if spawn_count <= 0:
		return

	for i in range(spawn_count):
		var lion := _spawn_lion(destination, i, spawn_count)
		if lion != null:
			_active_lions.append(lion)

	migration_wave_started.emit(destination, spawn_count, _pressure_stage)

func _spawn_count_for_pressure() -> int:
	var count := base_lions_per_wave + _pressure_stage + int(floor(_pressure_level * 1.5))
	var tuned_count := int(round(float(count) * _settings_value("effective_wave_size_multiplier", 1.0)))
	return int(clamp(tuned_count, 1, max_lions_per_wave))

func _pick_migration_destination() -> Vector3:
	if _chunk_manager != null and _chunk_manager.has_method("get_loaded_town_centers"):
		var centers: Array = _chunk_manager.call("get_loaded_town_centers")
		if not centers.is_empty():
			return centers[_rng.randi_range(0, centers.size() - 1)]

	if _player != null and is_instance_valid(_player):
		return _player.global_position + Vector3(8.0, 0.0, 8.0)

	return Vector3.ZERO

func _spawn_lion(destination: Vector3, index: int, spawn_count: int) -> Node:
	var lion := black_mountain_lion_scene.instantiate() as Node3D
	if lion == null:
		return null

	var parent := get_parent()
	if parent == null:
		parent = self
	parent.add_child(lion)

	var angle := (TAU * float(index) / float(max(spawn_count, 1))) + _rng.randf_range(-0.45, 0.45)
	var radius := _rng.randf_range(min_spawn_radius, max_spawn_radius) + float(_pressure_stage) * 2.0
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
	lion.global_position = destination + offset + Vector3(0.0, 1.0, 0.0)
	lion.name = "BlackMountainLion_Pressure_%d" % _pressure_stage
	lion.set_meta("pressure_stage", _pressure_stage)
	lion.set_meta("lion_creep_rate", _settings_value("effective_lion_creep_rate", 1.0))

	if game_loop_settings != null and lion.has_method("apply_game_loop_settings"):
		lion.call("apply_game_loop_settings", game_loop_settings)

	if lion.has_method("set_migration_destination"):
		lion.call("set_migration_destination", destination + Vector3(0.0, 1.0, 0.0), _pressure_stage, _settings_value("effective_lion_creep_rate", 1.0))

	return lion

func _cleanup_active_lions() -> void:
	var survivors: Array[Node] = []
	for lion in _active_lions:
		if is_instance_valid(lion):
			survivors.append(lion)
	_active_lions = survivors

func _emit_pressure_changed() -> void:
	pressure_changed.emit(_pressure_stage, _pressure_level, get_warning_text(), get_active_lion_count())
	_emit_settlement_pressure_changed()

func _emit_settlement_pressure_changed() -> void:
	settlement_pressure_changed.emit(get_settlement_summary())

func _collect_active_lion_positions() -> Array[Vector3]:
	_cleanup_active_lions()
	var positions: Array[Vector3] = []
	for lion in _active_lions:
		var lion_node := lion as Node3D
		if lion_node != null and is_instance_valid(lion_node):
			positions.append(lion_node.global_position)
	return positions

func _update_settlement_summary() -> void:
	if _chunk_manager != null and _chunk_manager.has_method("get_town_pressure_summary"):
		_settlement_summary = _chunk_manager.call("get_town_pressure_summary")
	else:
		_settlement_summary = _default_settlement_summary()

func _default_settlement_summary() -> Dictionary:
	return {
		"state": 0,
		"state_name": "Stable",
		"warning": "Stable towns: roads clear",
		"town_count": 0,
		"affected_chunks": 0,
		"travel_safety": 1.0,
		"pressure_enemy_density": 0,
		"pressure_score": 0.0,
		"nearby_lions": 0,
		"hostile_population": 0,
		"state_counts": [0, 0, 0, 0],
	}

func _effective_pressure_tick_seconds() -> float:
	return maxf(1.0, pressure_tick_seconds / _settings_value("effective_lion_creep_rate", 1.0))

func _effective_first_wave_delay() -> float:
	return maxf(0.0, first_wave_delay / _settings_value("effective_lion_creep_rate", 1.0))

func _effective_settlement_refresh_seconds() -> float:
	return maxf(0.1, settlement_refresh_seconds / _settings_value("effective_lion_creep_rate", 1.0))

func _effective_pressure_amount(amount: float) -> float:
	return amount * _settings_value("effective_threat_scale", 1.0)

func _effective_max_active_lions() -> int:
	return max(1, int(round(float(max_active_lions) * _settings_value("effective_wave_size_multiplier", 1.0))))

func _settings_value(method_name: String, fallback: float) -> float:
	if game_loop_settings != null and game_loop_settings.has_method(method_name):
		return maxf(float(game_loop_settings.call(method_name)), 0.05)
	return fallback
