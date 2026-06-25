extends Node3D
class_name ChunkManager

@export var chunk_scene: PackedScene
@export var seed: int = 20260625
@export var chunk_size: float = 48.0
@export_range(1, 6) var load_radius: int = 1
@export_range(2, 30) var obstacles_per_chunk: int = 12
@export_node_path("CharacterBody3D") var player_path: NodePath

@onready var player: CharacterBody3D

var _loaded_chunks: Dictionary = {}
var _active_chunk: Vector2i = Vector2i.ZERO

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
	chunk.call("initialize", coord, seed, chunk_size, obstacles_per_chunk)
	add_child(chunk)
	_loaded_chunks[_chunk_key(coord)] = chunk

func _chunk_key(coord: Vector2i) -> String:
	return "%d_%d" % [coord.x, coord.y]
