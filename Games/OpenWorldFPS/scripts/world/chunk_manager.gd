extends Node3D
class_name ChunkManager

signal town_pressure_changed(state: int, state_name: String, alert: String, travel_safety: float, pressure_enemies: int)

@export var chunk_scene: PackedScene
@export var seed: int = 20260625
@export var chunk_size: float = 48.0
@export_range(1, 6) var load_radius: int = 1
@export_range(2, 30) var obstacles_per_chunk: int = 12
@export_range(0.25, 1.0, 0.05) var far_chunk_density: float = 0.45
@export_range(1, 20) var chunk_distance_falloff: int = 6
@export_node_path("CharacterBody3D") var player_path: NodePath

const TOWN_PRESSURE_STATE_NAMES := ["Stable", "Uneasy", "Alert", "Overrun"]
const TOWN_ALERT_TEXT := [
	"Towns stable: roads open",
	"Towns uneasy: lookouts posted",
	"Town alert: barricades raised",
	"Town overrun: avoid affected chunks"
]

@onready var player: CharacterBody3D

var _loaded_chunks: Dictionary = {}
var _active_chunk: Vector2i = Vector2i.ZERO
var _lion_pressure_stage: int = 0
var _lion_density_scale: float = 1.0
var _town_pressure_state: int = 0
var _town_travel_safety: float = 1.0
var _town_pressure_enemy_count: int = 0
var _town_count: int = 0

func _ready() -> void:
	if chunk_scene == null:
		chunk_scene = load("res://scenes/chunk.tscn")
	if player_path != NodePath() and has_node(player_path):
		player = get_node(player_path) as CharacterBody3D
	if player == null:
		push_warning("ChunkManager needs a player path for chunk streaming.")
		return

	_active_chunk = _world_chunk_for_position(player.global_position)
	_refresh_chunks()

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var current_chunk: Vector2i = _world_chunk_for_position(player.global_position)
	if current_chunk == _active_chunk:
		return

	_active_chunk = current_chunk
	_refresh_chunks()

func _world_chunk_for_position(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / chunk_size), floori(position.z / chunk_size))

func _refresh_chunks() -> void:
	if player == null:
		return

	var required: Dictionary = {}
	for x in range(_active_chunk.x - load_radius, _active_chunk.x + load_radius + 1):
		for z in range(_active_chunk.y - load_radius, _active_chunk.y + load_radius + 1):
			var coord := Vector2i(x, z)
			var key := _chunk_key(coord)
			required[key] = coord
			if not _loaded_chunks.has(key):
				_spawn_chunk(coord)

	for key in _loaded_chunks.keys():
		if not required.has(key):
			var stale := _loaded_chunks[key] as Node3D
			if is_instance_valid(stale):
				stale.queue_free()
			_loaded_chunks.erase(key)

	_update_town_pressure_summary()

func _spawn_chunk(coord: Vector2i) -> void:
	if chunk_scene == null:
		push_error("ChunkManager is missing chunk scene.")
		return

	var chunk := chunk_scene.instantiate() as Node3D
	if chunk == null:
		return
	if not chunk.has_method("initialize"):
		push_warning("Chunk scene does not implement initialize().")
		chunk.free()
		return

	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk.position = Vector3(coord.x * chunk_size, 0.0, coord.y * chunk_size)
	var player_distance := _chunk_distance_to_player(coord)
	var population_scale := _population_scale(player_distance)
	chunk.call("initialize", coord, seed, chunk_size, obstacles_per_chunk, player_distance, population_scale)
	if chunk.has_method("set_lion_pressure"):
		chunk.call("set_lion_pressure", _lion_pressure_stage, _lion_density_scale)
	add_child(chunk)
	_loaded_chunks[_chunk_key(coord)] = chunk

func _chunk_distance_to_player(coord: Vector2i) -> int:
	return max(abs(coord.x - _active_chunk.x), abs(coord.y - _active_chunk.y))

func _population_scale(distance: int) -> float:
	if distance <= 1:
		return 1.0
	var effective_distance := float(max(distance - 1, 0))
	var falloff: int = max(chunk_distance_falloff, 1)
	var progress: float = clamp(effective_distance / float(falloff), 0.0, 1.0)
	return lerp(1.0, far_chunk_density, progress)

func _chunk_key(coord: Vector2i) -> String:
	return "%d_%d" % [coord.x, coord.y]

func set_lion_pressure(stage: int, density_scale: float) -> void:
	_lion_pressure_stage = int(clamp(stage, 0, 4))
	_lion_density_scale = clampf(density_scale, 0.0, 5.0)
	for chunk in _loaded_chunks.values():
		if is_instance_valid(chunk) and chunk.has_method("set_lion_pressure"):
			chunk.call("set_lion_pressure", _lion_pressure_stage, _lion_density_scale)
	_update_town_pressure_summary()

func get_lion_pressure_stage() -> int:
	return _lion_pressure_stage

func get_lion_density_scale() -> float:
	return _lion_density_scale

func get_loaded_town_centers() -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for chunk in _loaded_chunks.values():
		if not is_instance_valid(chunk) or not chunk.has_method("get_town_centers"):
			continue
		var chunk_node := chunk as Node3D
		if chunk_node == null:
			continue
		for local_center in chunk.call("get_town_centers"):
			centers.append(chunk_node.to_global(local_center))
	return centers

func get_loaded_town_pressure_states() -> Array[int]:
	var states: Array[int] = []
	for chunk in _loaded_chunks.values():
		if not is_instance_valid(chunk) or not chunk.has_method("get_town_pressure_states"):
			continue
		for state in chunk.call("get_town_pressure_states"):
			states.append(int(state))
	return states

func get_town_pressure_state() -> int:
	return _town_pressure_state

func get_town_pressure_state_name(state: int = -1) -> String:
	var state_index := _town_pressure_state if state < 0 else state
	state_index = int(clamp(state_index, 0, TOWN_PRESSURE_STATE_NAMES.size() - 1))
	return TOWN_PRESSURE_STATE_NAMES[state_index]

func get_town_alert_text() -> String:
	return TOWN_ALERT_TEXT[_town_pressure_state]

func get_travel_safety() -> float:
	return _town_travel_safety

func get_travel_safety_for_position(position: Vector3) -> float:
	var key := _chunk_key(_world_chunk_for_position(position))
	if _loaded_chunks.has(key):
		var chunk := _loaded_chunks[key] as Node
		if is_instance_valid(chunk) and chunk.has_method("get_average_travel_safety"):
			return float(chunk.call("get_average_travel_safety"))
	return _town_travel_safety

func get_pressure_enemy_count() -> int:
	return _town_pressure_enemy_count

func get_town_count() -> int:
	return _town_count

func _update_town_pressure_summary() -> void:
	var next_state := 0
	var next_town_count := 0
	var next_pressure_enemies := 0
	var safety_total := 0.0

	for chunk in _loaded_chunks.values():
		if not is_instance_valid(chunk):
			continue

		var chunk_town_count := 0
		if chunk.has_method("get_town_pressure_count"):
			chunk_town_count = int(chunk.call("get_town_pressure_count"))
		elif chunk.has_method("get_town_centers"):
			chunk_town_count = int(chunk.call("get_town_centers").size())

		if chunk_town_count <= 0:
			continue

		if chunk.has_method("get_max_town_pressure_state"):
			next_state = max(next_state, int(chunk.call("get_max_town_pressure_state")))

		var chunk_safety := 1.0
		if chunk.has_method("get_average_travel_safety"):
			chunk_safety = float(chunk.call("get_average_travel_safety"))
		safety_total += chunk_safety * float(chunk_town_count)
		next_town_count += chunk_town_count

		if chunk.has_method("get_pressure_enemy_count"):
			next_pressure_enemies += int(chunk.call("get_pressure_enemy_count"))

	var next_safety := 1.0
	if next_town_count > 0:
		next_safety = clampf(safety_total / float(next_town_count), 0.0, 1.0)

	var changed := next_state != _town_pressure_state \
		or absf(next_safety - _town_travel_safety) > 0.001 \
		or next_pressure_enemies != _town_pressure_enemy_count \
		or next_town_count != _town_count

	_town_pressure_state = next_state
	_town_travel_safety = next_safety
	_town_pressure_enemy_count = next_pressure_enemies
	_town_count = next_town_count

	if changed:
		town_pressure_changed.emit(
			_town_pressure_state,
			get_town_pressure_state_name(),
			get_town_alert_text(),
			_town_travel_safety,
			_town_pressure_enemy_count
		)
