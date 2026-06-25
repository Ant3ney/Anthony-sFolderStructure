extends Node3D

@export var world_seed: int = 20260625
@export var chunk_size: float = 48.0
@export var load_radius: int = 1
@export var obstacles_per_chunk: int = 12
const DEAD_TEXT := "DEAD - Press R to reload and continue"

@onready var chunk_manager := $ChunkManager
@onready var player: Node = $Player
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

	player.connect("health_updated", Callable(self, "_on_health_updated"))
	player.connect("alert_updated", Callable(self, "_on_alert_updated"))
	player.connect("target_lock_updated", Callable(self, "_on_target_lock_updated"))
	player.connect("death_state_changed", Callable(self, "_on_death_state_changed"))
	
	_on_health_updated(float(player.call("get_health")), float(player.get("max_health")))
	_on_alert_updated(float(player.call("get_alert")))
	_on_target_lock_updated(bool(player.call("is_target_locked")))
	_on_death_state_changed(bool(player.call("is_dead")))


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
