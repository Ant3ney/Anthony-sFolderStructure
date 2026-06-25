extends Node3D

@export var world_seed: int = 20260625
@export var chunk_size: float = 48.0
@export var load_radius: int = 1
@export var obstacles_per_chunk: int = 12
const DEAD_TEXT := "DEAD - Press R to reload and continue"

@onready var chunk_manager := $ChunkManager
@onready var player := $Player
@onready var health_label: Label = $HUD/HUDPanel/HUDRows/HealthLabel
@onready var alert_label: Label = $HUD/HUDPanel/HUDRows/AlertLabel
@onready var lock_label: Label = $HUD/HUDPanel/HUDRows/TargetLockLabel
@onready var status_label: Label = $HUD/HUDPanel/HUDRows/StatusLabel

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
		return
	_connect_player_hud()


func _connect_player_hud() -> void:
	if player == null:
		return

	player.health_updated.connect(_on_health_updated)
	player.alert_updated.connect(_on_alert_updated)
	player.target_lock_updated.connect(_on_target_lock_updated)
	player.death_state_changed.connect(_on_death_state_changed)
	
	_on_health_updated(player.get_health(), player.max_health)
	_on_alert_updated(player.get_alert())
	_on_target_lock_updated(player.is_target_locked())
	_on_death_state_changed(player.is_dead())


func _on_health_updated(current_health: float, max_health: float) -> void:
	health_label.text = "Health: %d / %d" % [int(current_health), int(max_health)]


func _on_alert_updated(level: float) -> void:
	alert_label.text = "Alert: %.0f" % level


func _on_target_lock_updated(enabled: bool) -> void:
	if enabled:
		lock_label.text = "Target Lock: ON"
	else:
		lock_label.text = "Target Lock: OFF"


func _on_death_state_changed(is_dead: bool) -> void:
	status_label.text = DEAD_TEXT if is_dead else "Press LMB to shoot and WASD to move"
