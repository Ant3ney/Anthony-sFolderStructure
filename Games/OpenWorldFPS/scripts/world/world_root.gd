extends Node3D

const GameLoopSettingsResource := preload("res://scripts/world/game_loop_settings.gd")

const DEFAULT_GAME_LOOP_SETTINGS := "res://resources/world/game_loop_settings.tres"
const DEAD_TEXT := "DEAD - Press R to reload and continue"
const SECONDS_PER_GAME_DAY := 86400.0
const SNAPSHOT_SCHEMA_VERSION := 1

@export var world_seed: int = 20260625
@export var chunk_size: float = 48.0
@export var load_radius: int = 1
@export var obstacles_per_chunk: int = 12
@export_range(0.25, 1.0, 0.05) var far_chunk_density: float = 0.45
@export_range(1, 20) var chunk_distance_falloff: int = 6
@export var game_loop_settings: GameLoopSettingsResource

@onready var chunk_manager := $ChunkManager
@onready var player: Node = $Player
@onready var lion_pressure_director: Node = $LionPressureDirector
@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var health_label: Label = $HUD/HUDPanel/HUDRows/HealthLabel
@onready var alert_label: Label = $HUD/HUDPanel/HUDRows/AlertLabel
@onready var time_label: Label = $HUD/HUDPanel/HUDRows/TimeLabel
@onready var lion_pressure_label: Label = $HUD/HUDPanel/HUDRows/LionPressureLabel
@onready var town_pressure_label: Label = $HUD/HUDPanel/HUDRows/TownPressureLabel
@onready var lock_label: Label = $HUD/HUDPanel/HUDRows/TargetLockLabel
@onready var status_label: Label = $HUD/HUDPanel/HUDRows/StatusLabel
@onready var snapshot_label: Label = $HUD/HUDPanel/HUDRows/SnapshotLabel
@onready var debug_panel: PanelContainer = $HUD/DebugPanel
@onready var debug_label: Label = $HUD/DebugPanel/DebugRows/DebugLabel

var _time_of_day_seconds: float = 0.0
var _day_index: int = 1
var _debug_refresh_timer: float = 0.0
var _debug_visible: bool = false
var _inspector_visible: bool = false
var _last_snapshot_status: String = "not saved"

func _ready() -> void:
	_ensure_game_loop_settings()
	_initialize_time_of_day()

	if chunk_manager == null:
		push_error("ChunkManager missing from WorldRoot.")
		return
	if player == null:
		push_error("Player node missing from WorldRoot.")

	chunk_manager.seed = world_seed
	chunk_manager.chunk_size = chunk_size
	chunk_manager.load_radius = load_radius
	chunk_manager.obstacles_per_chunk = obstacles_per_chunk
	chunk_manager.far_chunk_density = far_chunk_density
	chunk_manager.chunk_distance_falloff = chunk_distance_falloff
	chunk_manager.player_path = "../Player"

	_apply_game_loop_settings()
	_configure_diagnostics()
	_connect_player_hud()
	_connect_lion_pressure_hud()
	_update_time_hud()
	_update_snapshot_hud()
	_apply_time_of_day_to_lighting()
	_update_debug_view(true)

func _process(delta: float) -> void:
	_advance_time_of_day(delta)
	_debug_refresh_timer += delta
	if _debug_refresh_timer >= _debug_refresh_seconds():
		_debug_refresh_timer = 0.0
		_update_debug_view()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_view"):
		set_debug_view_visible(not _debug_visible)
	if event.is_action_pressed("toggle_inspector_view"):
		set_inspector_view_visible(not _inspector_visible)
	if event.is_action_pressed("save_world_snapshot"):
		save_world_snapshot()
	if event.is_action_pressed("load_world_snapshot"):
		load_world_snapshot()

func set_debug_view_visible(visible: bool) -> void:
	_debug_visible = visible
	_update_debug_view(true)

func set_inspector_view_visible(visible: bool) -> void:
	_inspector_visible = visible
	_update_debug_view(true)

func save_world_snapshot() -> Dictionary:
	var snapshot := get_world_state_snapshot()
	if not _snapshots_enabled():
		_last_snapshot_status = "disabled"
		_update_snapshot_hud()
		_update_debug_view(true)
		return snapshot

	var path := _snapshot_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_last_snapshot_status = "save failed"
		push_warning("Unable to save world snapshot to %s." % path)
		_update_snapshot_hud()
		_update_debug_view(true)
		return snapshot

	file.store_string(JSON.stringify(snapshot, "\t"))
	_last_snapshot_status = "saved"
	_update_snapshot_hud()
	_update_debug_view(true)
	return snapshot

func load_world_snapshot() -> Dictionary:
	var path := _snapshot_path()
	if not FileAccess.file_exists(path):
		_last_snapshot_status = "missing"
		_update_snapshot_hud()
		_update_debug_view(true)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_last_snapshot_status = "load failed"
		push_warning("Unable to load world snapshot from %s." % path)
		_update_snapshot_hud()
		_update_debug_view(true)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_snapshot_status = "invalid"
		_update_snapshot_hud()
		_update_debug_view(true)
		return {}

	var snapshot: Dictionary = parsed
	_apply_world_state_snapshot(snapshot)
	_last_snapshot_status = "loaded"
	_update_snapshot_hud()
	_update_debug_view(true)
	return snapshot

func get_world_state_snapshot() -> Dictionary:
	var player_position := Vector3.ZERO
	var player_health := 0.0
	var player_alert := 0.0
	var player_dead := false
	var player_node := player as Node3D
	if player_node != null:
		player_position = player_node.global_position
	if player != null:
		if player.has_method("get_health"):
			player_health = float(player.call("get_health"))
		if player.has_method("get_alert"):
			player_alert = float(player.call("get_alert"))
		if player.has_method("is_dead"):
			player_dead = bool(player.call("is_dead"))

	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"world_seed": world_seed,
		"day_index": _day_index,
		"time_of_day_seconds": _time_of_day_seconds,
		"time_of_day_text": _time_of_day_text(),
		"settings_resource": game_loop_settings.resource_path if game_loop_settings != null else "",
		"player": {
			"position": _vector3_to_dictionary(player_position),
			"health": player_health,
			"alert": player_alert,
			"dead": player_dead,
		},
		"lion_pressure": _lion_pressure_snapshot(),
		"settlement": _settlement_snapshot(),
		"ai_state_counts": _collect_ai_state_counts(),
	}

func get_game_loop_debug_snapshot() -> Dictionary:
	return {
		"debug_visible": _debug_visible,
		"inspector_visible": _inspector_visible,
		"time_of_day": _time_of_day_text(),
		"day_index": _day_index,
		"lion_count": _lion_count_in_world(),
		"tracked_lion_count": _tracked_lion_count(),
		"alert_level": _player_alert_level(),
		"ai_state_counts": _collect_ai_state_counts(),
		"snapshot_status": _last_snapshot_status,
	}

func _ensure_game_loop_settings() -> void:
	if game_loop_settings != null:
		return

	var loaded := load(DEFAULT_GAME_LOOP_SETTINGS)
	if loaded is GameLoopSettingsResource:
		game_loop_settings = loaded

func _initialize_time_of_day() -> void:
	var starting_hour := 8.0
	if game_loop_settings != null:
		starting_hour = game_loop_settings.starting_hour
	_time_of_day_seconds = clampf(starting_hour, 0.0, 24.0) * 3600.0
	_day_index = 1

func _apply_game_loop_settings() -> void:
	if game_loop_settings == null:
		return

	if lion_pressure_director != null and lion_pressure_director.has_method("set_game_loop_settings"):
		lion_pressure_director.call("set_game_loop_settings", game_loop_settings)
	if chunk_manager != null and chunk_manager.has_method("set_game_loop_settings"):
		chunk_manager.call("set_game_loop_settings", game_loop_settings)
	_apply_game_loop_settings_to_ai()

func _apply_game_loop_settings_to_ai() -> void:
	if game_loop_settings == null:
		return

	for node in get_tree().get_nodes_in_group("ai_entities"):
		var ai_node := node as Node
		if ai_node != null and _is_descendant_of_world(ai_node) and ai_node.has_method("apply_game_loop_settings"):
			ai_node.call("apply_game_loop_settings", game_loop_settings)

func _configure_diagnostics() -> void:
	_debug_visible = game_loop_settings != null and game_loop_settings.debug_view_enabled
	_inspector_visible = game_loop_settings != null and game_loop_settings.inspector_view_enabled
	if debug_panel != null:
		debug_panel.visible = _debug_visible

func _advance_time_of_day(delta: float) -> void:
	if game_loop_settings == null or not game_loop_settings.time_progression_enabled:
		return

	var day_length := maxf(game_loop_settings.real_seconds_per_game_day, 1.0)
	_time_of_day_seconds += delta * (SECONDS_PER_GAME_DAY / day_length) * maxf(game_loop_settings.time_scale, 0.0)
	while _time_of_day_seconds >= SECONDS_PER_GAME_DAY:
		_time_of_day_seconds -= SECONDS_PER_GAME_DAY
		_day_index += 1

	_update_time_hud()
	_apply_time_of_day_to_lighting()

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
	_update_debug_view()

func _on_target_lock_updated(enabled: bool) -> void:
	if enabled:
		lock_label.text = "Target Lock: ON"
	else:
		lock_label.text = "Target Lock: OFF"

func _on_lion_pressure_changed(stage: int, pressure_level: float, warning: String, active_lions: int) -> void:
	lion_pressure_label.text = "%s | Stage %d | Count %d | Pressure %.2f" % [warning, stage, active_lions, pressure_level]
	_update_debug_view()

func _on_settlement_pressure_changed(summary: Dictionary) -> void:
	var warning := String(summary.get("warning", "Stable towns: roads clear"))
	var state_name := String(summary.get("state_name", "Stable"))
	var pressure_enemies := int(summary.get("pressure_enemy_density", 0))
	town_pressure_label.text = "%s | %s | Enemy pressure %d" % [warning, state_name, pressure_enemies]
	_update_debug_view()

func _on_death_state_changed(is_dead: bool) -> void:
	status_label.text = DEAD_TEXT if is_dead else "Press LMB to shoot and WASD to move"

func _update_time_hud() -> void:
	if time_label != null:
		time_label.text = "Day %d | %s" % [_day_index, _time_of_day_text()]

func _update_snapshot_hud() -> void:
	if snapshot_label != null:
		snapshot_label.text = "Snapshot: %s" % _last_snapshot_status

func _update_debug_view(force: bool = false) -> void:
	if debug_panel == null or debug_label == null:
		return
	if not force and not _debug_visible:
		return

	debug_panel.visible = _debug_visible
	if not _debug_visible:
		return

	var lines := PackedStringArray()
	lines.append("Debug | Day %d %s" % [_day_index, _time_of_day_text()])
	lines.append("Lions: tracked %d | alive %d" % [_tracked_lion_count(), _lion_count_in_world()])
	lines.append("Alert: %.0f | Town: %s" % [_player_alert_level(), _settlement_state_name()])
	lines.append("AI States: %s" % _format_state_counts(_collect_ai_state_counts()))
	if _inspector_visible:
		var diagnostics := _pressure_diagnostics()
		lines.append("Pacing: tick %.1fs | threat %.2f | creep %.2f" % [
			float(diagnostics.get("pressure_tick_seconds", 0.0)),
			float(diagnostics.get("threat_scale", 1.0)),
			float(diagnostics.get("lion_creep_rate", 1.0)),
		])
		lines.append("Snapshot: %s | %s" % [_last_snapshot_status, _snapshot_path()])
	debug_label.text = "\n".join(lines)

func _apply_time_of_day_to_lighting() -> void:
	if sun_light == null:
		return

	var hour := _time_of_day_seconds / 3600.0
	var daylight := clampf(sin(((hour - 6.0) / 12.0) * PI), 0.0, 1.0)
	sun_light.light_energy = lerp(0.22, 1.35, daylight)
	sun_light.rotation_degrees.x = lerp(-15.0, -75.0, daylight)
	sun_light.rotation_degrees.y = -45.0 + hour * 4.0

func _apply_world_state_snapshot(snapshot: Dictionary) -> void:
	_day_index = max(1, int(snapshot.get("day_index", _day_index)))
	_time_of_day_seconds = clampf(float(snapshot.get("time_of_day_seconds", _time_of_day_seconds)), 0.0, SECONDS_PER_GAME_DAY - 1.0)

	var player_node := player as Node3D
	var player_snapshot: Dictionary = snapshot.get("player", {})
	if player_node != null and player_snapshot.has("position"):
		player_node.global_position = _dictionary_to_vector3(player_snapshot.get("position"), player_node.global_position)

	var pressure_snapshot: Dictionary = snapshot.get("lion_pressure", {})
	if lion_pressure_director != null and pressure_snapshot.has("level") and lion_pressure_director.has_method("set_pressure_level"):
		lion_pressure_director.call("set_pressure_level", float(pressure_snapshot.get("level", 0.0)))

	_update_time_hud()
	_apply_time_of_day_to_lighting()

func _lion_pressure_snapshot() -> Dictionary:
	var snapshot := {
		"level": 0.0,
		"stage": 0,
		"tracked_lions": 0,
		"alive_lions": _lion_count_in_world(),
		"diagnostics": {},
	}
	if lion_pressure_director == null:
		return snapshot
	if lion_pressure_director.has_method("get_pressure_level"):
		snapshot["level"] = float(lion_pressure_director.call("get_pressure_level"))
	if lion_pressure_director.has_method("get_pressure_stage"):
		snapshot["stage"] = int(lion_pressure_director.call("get_pressure_stage"))
	if lion_pressure_director.has_method("get_active_lion_count"):
		snapshot["tracked_lions"] = int(lion_pressure_director.call("get_active_lion_count"))
	if lion_pressure_director.has_method("get_pressure_diagnostics"):
		snapshot["diagnostics"] = lion_pressure_director.call("get_pressure_diagnostics")
	return snapshot

func _settlement_snapshot() -> Dictionary:
	if lion_pressure_director != null and lion_pressure_director.has_method("get_settlement_summary"):
		return lion_pressure_director.call("get_settlement_summary")
	if chunk_manager != null and chunk_manager.has_method("get_town_pressure_summary"):
		return chunk_manager.call("get_town_pressure_summary")
	return {}

func _pressure_diagnostics() -> Dictionary:
	if lion_pressure_director != null and lion_pressure_director.has_method("get_pressure_diagnostics"):
		return lion_pressure_director.call("get_pressure_diagnostics")
	return {}

func _collect_ai_state_counts() -> Dictionary:
	var counts := {}
	for node in get_tree().get_nodes_in_group("ai_entities"):
		var ai_node := node as Node
		if ai_node == null or not _is_descendant_of_world(ai_node):
			continue
		var state := "unknown"
		if ai_node.has_method("get_current_state_name"):
			state = String(ai_node.call("get_current_state_name"))
		counts[state] = int(counts.get(state, 0)) + 1
	return counts

func _format_state_counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "none"

	var keys := counts.keys()
	keys.sort()
	var parts := PackedStringArray()
	for key in keys:
		parts.append("%s=%d" % [String(key), int(counts[key])])
	return ", ".join(parts)

func _tracked_lion_count() -> int:
	if lion_pressure_director != null and lion_pressure_director.has_method("get_active_lion_count"):
		return int(lion_pressure_director.call("get_active_lion_count"))
	return 0

func _lion_count_in_world() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("black_mountain_lions"):
		var lion_node := node as Node
		if lion_node != null and _is_descendant_of_world(lion_node):
			count += 1
	return count

func _player_alert_level() -> float:
	if player != null and player.has_method("get_alert"):
		return float(player.call("get_alert"))
	return 0.0

func _settlement_state_name() -> String:
	var summary := _settlement_snapshot()
	return String(summary.get("state_name", "Stable"))

func _time_of_day_text() -> String:
	var hour := floori(_time_of_day_seconds / 3600.0)
	var minute := floori(fmod(_time_of_day_seconds, 3600.0) / 60.0)
	return "%02d:%02d" % [hour, minute]

func _debug_refresh_seconds() -> float:
	if game_loop_settings != null:
		return maxf(game_loop_settings.debug_refresh_seconds, 0.05)
	return 0.25

func _snapshot_path() -> String:
	if game_loop_settings != null and not game_loop_settings.snapshot_path.is_empty():
		return game_loop_settings.snapshot_path
	return "user://world_state_snapshot.json"

func _snapshots_enabled() -> bool:
	return game_loop_settings == null or game_loop_settings.local_snapshots_enabled

func _vector3_to_dictionary(value: Vector3) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z,
	}

func _dictionary_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_DICTIONARY:
		return fallback

	var dictionary: Dictionary = value
	return Vector3(
		float(dictionary.get("x", fallback.x)),
		float(dictionary.get("y", fallback.y)),
		float(dictionary.get("z", fallback.z))
	)

func _is_descendant_of_world(node: Node) -> bool:
	var current := node
	while current != null:
		if current == self:
			return true
		current = current.get_parent()
	return false
