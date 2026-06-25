extends Node3D

@export var world_seed: int = 20260625
@export var chunk_size: float = 48.0
@export var load_radius: int = 1
@export var obstacles_per_chunk: int = 12
@export_range(0.25, 1.0, 0.05) var far_chunk_density: float = 0.45
@export_range(1, 20) var chunk_distance_falloff: int = 6

const DEAD_TEXT := "DEAD - Press R to reload and continue"

@onready var chunk_manager := $ChunkManager
@onready var player: Node = $Player
@onready var lion_pressure_director: Node = $LionPressureDirector
@onready var health_label: Label = $HUD/HUDPanel/HUDRows/HealthLabel
@onready var alert_label: Label = $HUD/HUDPanel/HUDRows/AlertLabel
@onready var lion_pressure_label: Label = $HUD/HUDPanel/HUDRows/LionPressureLabel
@onready var town_pressure_label: Label = $HUD/HUDPanel/HUDRows/TownPressureLabel
@onready var lock_label: Label = $HUD/HUDPanel/HUDRows/TargetLockLabel
@onready var status_label: Label = $HUD/HUDPanel/HUDRows/StatusLabel

func _ready() -> void:
	chunk_manager.seed = world_seed
	chunk_manager.chunk_size = chunk_size
	chunk_manager.load_radius = load_radius
	chunk_manager.obstacles_per_chunk = obstacles_per_chunk
	chunk_manager.far_chunk_density = far_chunk_density
	chunk_manager.chunk_distance_falloff = chunk_distance_falloff
	chunk_manager.player_path = "../Player"

	if not player:
		push_error("Player node missing from WorldRoot.")
	if not chunk_manager:
		push_error("ChunkManager missing from WorldRoot.")
		return
	_connect_player_hud()
	_connect_lion_pressure_hud()


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

func _connect_lion_pressure_hud() -> void:
	if lion_pressure_director == null:
		return

	lion_pressure_director.connect("pressure_changed", Callable(self, "_on_lion_pressure_changed"))
	if lion_pressure_director.has_signal("settlement_pressure_changed"):
		lion_pressure_director.connect("settlement_pressure_changed", Callable(self, "_on_settlement_pressure_changed"))
	if lion_pressure_director.has_method("get_pressure_stage"):
		_on_lion_pressure_changed(
			int(lion_pressure_director.call("get_pressure_stage")),
			float(lion_pressure_director.call("get_pressure_level")),
			String(lion_pressure_director.call("get_warning_text")),
			int(lion_pressure_director.call("get_active_lion_count"))
		)
	if lion_pressure_director.has_method("get_settlement_summary"):
		_on_settlement_pressure_changed(lion_pressure_director.call("get_settlement_summary"))


func _on_health_updated(current_health: float, max_health: float) -> void:
	health_label.text = "Health: %d / %d" % [int(current_health), int(max_health)]


func _on_alert_updated(level: float) -> void:
	alert_label.text = "Alert: %.0f" % level


func _on_target_lock_updated(enabled: bool) -> void:
	if enabled:
		lock_label.text = "Target Lock: ON"
	else:
		lock_label.text = "Target Lock: OFF"

func _on_lion_pressure_changed(stage: int, pressure_level: float, warning: String, active_lions: int) -> void:
	lion_pressure_label.text = "%s | Stage %d | Count %d | Pressure %.2f" % [warning, stage, active_lions, pressure_level]

func _on_settlement_pressure_changed(summary: Dictionary) -> void:
	var warning := String(summary.get("warning", "Stable towns: roads clear"))
	var state_name := String(summary.get("state_name", "Stable"))
	var pressure_enemies := int(summary.get("pressure_enemy_density", 0))
	town_pressure_label.text = "%s | %s | Enemy pressure %d" % [warning, state_name, pressure_enemies]


func _on_death_state_changed(is_dead: bool) -> void:
	status_label.text = DEAD_TEXT if is_dead else "Press LMB to shoot and WASD to move"
