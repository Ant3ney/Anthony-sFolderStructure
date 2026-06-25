extends Node3D
class_name ChunkManager

@export var chunk_scene: PackedScene
@export var seed: int = 20260625
@export var chunk_size: float = 48.0
@export_range(1, 6) var load_radius: int = 1
@export_range(2, 30) var obstacles_per_chunk: int = 12
@export_range(0.25, 1.0, 0.05) var far_chunk_density: float = 0.45
@export_range(1, 20) var chunk_distance_falloff: int = 6
@export_node_path("CharacterBody3D") var player_path: NodePath

@onready var player: CharacterBody3D

const TOWN_STATE_STABLE := 0
const TOWN_STATE_UNEASY := 1
const TOWN_STATE_ALERT := 2
const TOWN_STATE_OVERRUN := 3
const TOWN_STATE_NAMES: Array[String] = [
	"Stable",
	"Uneasy",
	"Alert",
	"Overrun"
]

var _loaded_chunks: Dictionary = {}
var _active_chunk: Vector2i = Vector2i.ZERO
var _lion_pressure_stage: int = 0
var _lion_density_scale: float = 1.0
var _active_lion_positions: Array[Vector3] = []
var _town_pressure_summary: Dictionary = {}

func _ready() -> void:
	if chunk_scene == null:
		chunk_scene = load("res://scenes/chunk.tscn")
	if player_path != NodePath() and has_node(player_path):
		player = get_node(player_path) as CharacterBody3D
	if player == null:
		push_warning("ChunkManager needs a player path for chunk streaming.")
		return

	_town_pressure_summary = _default_town_pressure_summary()
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
	_refresh_town_pressure_summary()

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
	add_child(chunk)
	_loaded_chunks[_chunk_key(coord)] = chunk
	if chunk.has_method("set_lion_pressure"):
		chunk.call("set_lion_pressure", _lion_pressure_stage, _lion_density_scale, _active_lion_positions)
	_apply_alert_propagation()
	_refresh_town_pressure_summary()

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

func set_lion_pressure(stage: int, density_scale: float, active_lion_positions: Array = []) -> void:
	_lion_pressure_stage = int(clamp(stage, 0, 4))
	_lion_density_scale = clampf(density_scale, 0.0, 5.0)
	_active_lion_positions.clear()
	for lion_position in active_lion_positions:
		if typeof(lion_position) == TYPE_VECTOR3:
			_active_lion_positions.append(lion_position)
	for chunk in _loaded_chunks.values():
		if is_instance_valid(chunk) and chunk.has_method("set_lion_pressure"):
			chunk.call("set_lion_pressure", _lion_pressure_stage, _lion_density_scale, _active_lion_positions)
	_apply_alert_propagation()
	_refresh_town_pressure_summary()

func get_lion_pressure_stage() -> int:
	return _lion_pressure_stage

func get_lion_density_scale() -> float:
	return _lion_density_scale

func get_town_pressure_summary() -> Dictionary:
	return _town_pressure_summary.duplicate(true)

func get_town_pressure_state() -> int:
	return int(_town_pressure_summary.get("state", TOWN_STATE_STABLE))

func get_town_pressure_state_name() -> String:
	return String(_town_pressure_summary.get("state_name", "Stable"))

func get_town_pressure_warning() -> String:
	return String(_town_pressure_summary.get("warning", "Stable towns: roads clear"))

func get_town_alert_text() -> String:
	return get_town_pressure_warning()

func get_travel_safety_modifier() -> float:
	return float(_town_pressure_summary.get("travel_safety", 1.0))

func get_travel_safety() -> float:
	return get_travel_safety_modifier()

func get_travel_safety_for_position(position: Vector3) -> float:
	var key := _chunk_key(_world_chunk_for_position(position))
	if _loaded_chunks.has(key):
		var chunk: Node = _loaded_chunks[key] as Node
		if is_instance_valid(chunk) and chunk.has_method("get_travel_safety_modifier"):
			return float(chunk.call("get_travel_safety_modifier"))
	return get_travel_safety_modifier()

func get_pressure_enemy_density() -> int:
	return int(_town_pressure_summary.get("pressure_enemy_density", 0))

func get_pressure_enemy_count() -> int:
	return get_pressure_enemy_density()

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

func _apply_alert_propagation() -> void:
	var alert_sources: Array[Dictionary] = []
	for key in _loaded_chunks.keys():
		var chunk := _loaded_chunks[key] as Node
		if not is_instance_valid(chunk) or not chunk.has_method("get_town_pressure_state"):
			continue
		var state := int(chunk.call("get_town_pressure_state"))
		if state >= TOWN_STATE_ALERT:
			alert_sources.append({
				"coord": _chunk_coord_for(chunk),
				"state": state
			})

	if alert_sources.is_empty():
		return

	for chunk_value in _loaded_chunks.values():
		var chunk := chunk_value as Node
		if not is_instance_valid(chunk) or not chunk.has_method("set_settlement_alert_override"):
			continue
		var coord := _chunk_coord_for(chunk)
		var override_state := -1
		for source in alert_sources:
			var source_coord: Vector2i = source["coord"]
			var distance: int = max(abs(coord.x - source_coord.x), abs(coord.y - source_coord.y))
			if distance <= 0 or distance > 1:
				continue
			var source_state := int(source["state"])
			if source_state >= TOWN_STATE_OVERRUN:
				override_state = max(override_state, TOWN_STATE_ALERT)
			elif source_state >= TOWN_STATE_ALERT:
				override_state = max(override_state, TOWN_STATE_UNEASY)
		if override_state >= TOWN_STATE_UNEASY:
			chunk.call("set_settlement_alert_override", override_state)

func _refresh_town_pressure_summary() -> void:
	var summary := _default_town_pressure_summary()
	var town_count := 0
	var affected_chunks := 0
	var pressure_enemy_density := 0
	var state_counts := [0, 0, 0, 0]
	var strongest_state := TOWN_STATE_STABLE
	var lowest_travel_safety := 1.0
	var highest_pressure_score := 0.0
	var nearby_lion_count := 0
	var hostile_population := 0

	for chunk in _loaded_chunks.values():
		if not is_instance_valid(chunk) or not chunk.has_method("get_town_centers"):
			continue
		var centers: Array = chunk.call("get_town_centers")
		if centers.is_empty():
			continue

		town_count += centers.size()
		var state := TOWN_STATE_STABLE
		if chunk.has_method("get_town_pressure_state"):
			state = int(chunk.call("get_town_pressure_state"))
		strongest_state = max(strongest_state, state)
		if state > TOWN_STATE_STABLE:
			affected_chunks += 1
		state_counts[state] += centers.size()

		if chunk.has_method("get_travel_safety_modifier"):
			lowest_travel_safety = min(lowest_travel_safety, float(chunk.call("get_travel_safety_modifier")))
		if chunk.has_method("get_pressure_enemy_density"):
			pressure_enemy_density += int(chunk.call("get_pressure_enemy_density"))
		if chunk.has_method("get_settlement_pressure_score"):
			highest_pressure_score = max(highest_pressure_score, float(chunk.call("get_settlement_pressure_score")))
		if chunk.has_method("get_nearby_lion_count"):
			nearby_lion_count += int(chunk.call("get_nearby_lion_count"))
		if chunk.has_method("get_hostile_population"):
			hostile_population += int(chunk.call("get_hostile_population"))

	if town_count <= 0:
		_town_pressure_summary = summary
		return

	summary["state"] = strongest_state
	summary["state_name"] = TOWN_STATE_NAMES[strongest_state]
	summary["town_count"] = town_count
	summary["affected_chunks"] = affected_chunks
	summary["travel_safety"] = lowest_travel_safety
	summary["pressure_enemy_density"] = pressure_enemy_density
	summary["pressure_score"] = highest_pressure_score
	summary["nearby_lions"] = nearby_lion_count
	summary["hostile_population"] = hostile_population
	summary["state_counts"] = state_counts
	summary["warning"] = _town_warning_for_summary(strongest_state, affected_chunks, lowest_travel_safety)
	_town_pressure_summary = summary

func _default_town_pressure_summary() -> Dictionary:
	return {
		"state": TOWN_STATE_STABLE,
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

func _town_warning_for_summary(state: int, affected_chunks: int, travel_safety: float) -> String:
	match state:
		TOWN_STATE_UNEASY:
			return "Towns Uneasy: warning signals up in %d chunk(s), travel safety %.0f%%" % [affected_chunks, travel_safety * 100.0]
		TOWN_STATE_ALERT:
			return "Towns Alert: defenses deployed in %d chunk(s), travel safety %.0f%%" % [affected_chunks, travel_safety * 100.0]
		TOWN_STATE_OVERRUN:
			return "Towns Overrun: roads unsafe in %d chunk(s), travel safety %.0f%%" % [affected_chunks, travel_safety * 100.0]
		_:
			return "Stable towns: roads clear"

func _chunk_coord_for(chunk: Node) -> Vector2i:
	var coord = chunk.get("chunk_coord")
	if typeof(coord) == TYPE_VECTOR2I:
		return coord
	return Vector2i.ZERO
