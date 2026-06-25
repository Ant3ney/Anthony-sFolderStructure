extends Resource
class_name GameLoopSettings

@export_category("World Time")
@export var time_progression_enabled: bool = true
@export_range(0.0, 24.0, 0.1) var starting_hour: float = 8.0
@export_range(60.0, 7200.0, 1.0) var real_seconds_per_game_day: float = 1200.0
@export_range(0.05, 8.0, 0.05) var time_scale: float = 1.0

@export_category("Threat Pacing")
@export_range(0.1, 5.0, 0.05) var difficulty_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.05) var threat_scale: float = 1.0
@export_range(0.1, 5.0, 0.05) var lion_creep_rate: float = 1.0
@export_range(0.1, 5.0, 0.05) var wave_size_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.05) var settlement_pressure_multiplier: float = 1.0

@export_category("AI Difficulty")
@export_range(0.1, 5.0, 0.05) var ai_health_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.05) var ai_damage_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.05) var ai_movement_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.05) var ai_perception_multiplier: float = 1.0

@export_category("Diagnostics")
@export var debug_view_enabled: bool = false
@export var inspector_view_enabled: bool = false
@export_range(0.05, 5.0, 0.05) var debug_refresh_seconds: float = 0.25

@export_category("Persistence")
@export var local_snapshots_enabled: bool = true
@export var snapshot_path: String = "user://world_state_snapshot.json"

func effective_difficulty() -> float:
	return maxf(difficulty_multiplier, 0.05)

func effective_threat_scale() -> float:
	return maxf(threat_scale * effective_difficulty(), 0.05)

func effective_lion_creep_rate() -> float:
	return maxf(lion_creep_rate * effective_difficulty(), 0.05)

func effective_wave_size_multiplier() -> float:
	return maxf(wave_size_multiplier * effective_difficulty(), 0.05)

func effective_settlement_pressure_multiplier() -> float:
	return maxf(settlement_pressure_multiplier * effective_threat_scale(), 0.05)

func effective_ai_health_multiplier() -> float:
	return maxf(ai_health_multiplier * effective_difficulty(), 0.05)

func effective_ai_damage_multiplier() -> float:
	return maxf(ai_damage_multiplier * effective_difficulty(), 0.05)

func effective_ai_movement_multiplier() -> float:
	return maxf(ai_movement_multiplier * effective_difficulty(), 0.05)

func effective_ai_perception_multiplier() -> float:
	return maxf(ai_perception_multiplier * effective_difficulty(), 0.05)
