extends Node3D

@export var world_seed: int = 20260625
@export var chunk_size: float = 48.0
@export var load_radius: int = 1
@export var obstacles_per_chunk: int = 12

@onready var chunk_manager := $ChunkManager
@onready var player := $Player

func _ready() -> void:
	chunk_manager.seed = world_seed
	chunk_manager.chunk_size = chunk_size
	chunk_manager.load_radius = load_radius
	chunk_manager.obstacles_per_chunk = obstacles_per_chunk
	chunk_manager.player_path = "../Player"

	if not player:
		push_error("Player node missing from WorldRoot.")
	if not chunk_manager:
		push_error("ChunkManager missing from WorldRoot.")
