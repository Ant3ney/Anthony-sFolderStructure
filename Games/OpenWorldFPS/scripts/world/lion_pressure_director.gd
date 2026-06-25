extends Node
class_name LionPressureDirector

signal pressure_changed(stage: int, pressure_level: float, warning: String, active_lions: int)
signal migration_wave_started(destination: Vector3, spawned: int, stage: int)

const PRESSURE_THRESHOLDS := [0.16, 0.40, 0.70, 1.0]
const WARNING_TEXT := [
	"Black Mountain Lions: quiet",
	"Black Mountain Lions: tracks near villages",
	"Black Mountain Lions: prowling village edges",
	"Black Mountain Lions: encroaching on roads",
	"Black Mountain Lions: villages under pressure"
]

@export_node_path("Node3D") var chunk_manager_path: NodePath
@export_node_path("CharacterBody3D") var player_path: NodePath
@export var black_mountain_lion_scene: PackedScene
@export_range(5.0, 300.0, 1.0) var pressure_tick_seconds: float = 45.0
@export_range(0.01, 1.0, 0.01) var pressure_per_tick: float = 0.18
@export_range(0.0, 120.0, 1.0) var first_wave_delay: float = 12.0
@export_range(8.0, 80.0, 1.0) var min_spawn_radius: float = 24.0
@export_range(12.0, 120.0, 1.0) var max_spawn_radius: float = 42.0
@export_range(1, 8, 1) var base_lions_per_wave: int = 1
@export_range(1, 12, 1) var max_lions_per_wave: int = 7
@export_range(1, 60, 1) var max_active_lions: int = 30
@export_range(1.0, 5.0, 0.1) var max_pressure_level: float = 2.0

var _chunk_manager: Node
var _player: Node3D
var _pressure_level: float = 0.0
var _pressure_stage: int = 0
var _wave_timer: float = 0.0
var _active_lions: Array[Node] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_resolve_references()
	_seed_rng()
	_wave_timer = maxf(pressure_tick_seconds - first_wave_delay, 0.0)
	_apply_pressure_to_chunks()
	_emit_pressure_changed()

func _physics_process(delta: float) -> void:
	if pressure_tick_seconds <= 0.0:
		return

	_wave_timer += delta
	if _wave_timer < pressure_tick_seconds:
		return

	_wave_timer = fmod(_wave_timer, pressure_tick_seconds)
	advance_pressure(pressure_per_tick, true)

func advance_pressure(amount: float, spawn_wave: bool = true) -> void:
	if amount <= 0.0:
		return

	_set_pressure(_pressure_level + amount)
	if spawn_wave:
		_spawn_migration_wave()
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
	return 1.0 + (_pressure_level * 0.75) + (float(_pressure_stage) * 0.25)

func _apply_pressure_to_chunks() -> void:
	if _chunk_manager == null:
		_resolve_references()
	if _chunk_manager != null and _chunk_manager.has_method("set_lion_pressure"):
		_chunk_manager.call("set_lion_pressure", _pressure_stage, _density_scale())

func _spawn_migration_wave() -> void:
	_cleanup_active_lions()
	if black_mountain_lion_scene == null:
		push_warning("LionPressureDirector needs a black mountain lion scene.")
		return

	var remaining_slots := max_active_lions - _active_lions.size()
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
	return int(clamp(count, 1, max_lions_per_wave))

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

	if lion.has_method("set_migration_destination"):
		lion.call("set_migration_destination", destination + Vector3(0.0, 1.0, 0.0), _pressure_stage)

	return lion

func _cleanup_active_lions() -> void:
	var survivors: Array[Node] = []
	for lion in _active_lions:
		if is_instance_valid(lion):
			survivors.append(lion)
	_active_lions = survivors

func _emit_pressure_changed() -> void:
	pressure_changed.emit(_pressure_stage, _pressure_level, get_warning_text(), get_active_lion_count())
