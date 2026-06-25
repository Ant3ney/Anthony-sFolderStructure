extends Resource
class_name AIBehaviorProfile

const VALID_STATES: Array[String] = [
	"idle",
	"patrol",
	"investigate",
	"evade",
	"chase",
	"attack",
	"flee",
]

@export_group("Identity")
@export var display_name: String = "AI Agent"
@export_enum("idle", "patrol", "investigate", "evade", "chase", "attack", "flee") var initial_state: String = "idle"
@export_enum("ignore", "evade", "chase") var target_response: String = "chase"
@export var target_group: StringName = &"player"

@export_group("Perception")
@export var sight_range: float = 22.0
@export_range(1.0, 180.0, 1.0) var field_of_view_degrees: float = 110.0
@export var hearing_range: float = 8.0
@export var eye_height: float = 1.0
@export var line_of_sight_mask: int = 1 | 2 | 4

@export_group("Navigation")
@export var move_speed: float = 3.0
@export var chase_speed: float = 5.0
@export var evade_speed: float = 4.5
@export var flee_speed: float = 6.0
@export var acceleration: float = 16.0
@export var gravity: float = 18.0
@export var stopping_distance: float = 0.75
@export var patrol_points: PackedVector3Array = PackedVector3Array()
@export var patrol_wait_time: float = 1.2
@export var idle_duration_min: float = 0.8
@export var idle_duration_max: float = 2.0
@export var investigation_duration: float = 5.0
@export var lost_target_memory: float = 2.5
@export var evade_duration: float = 1.1
@export var flee_duration: float = 4.0
@export var safe_distance: float = 14.0

@export_group("Combat")
@export var attack_range: float = 2.2
@export var attack_cooldown: float = 1.25
@export var attack_hold_time: float = 0.35
@export var damage: float = 10.0

@export_group("Survival")
@export_range(0.0, 1.0, 0.01) var flee_health_fraction: float = 0.2
@export var evade_distance: float = 8.0
@export var emergency_flee_distance: float = 2.5
@export var return_to_patrol_after_flee: bool = true

func has_patrol_route() -> bool:
	return patrol_points.size() > 0

func normalized_initial_state() -> StringName:
	if VALID_STATES.has(initial_state):
		return StringName(initial_state)
	return &"idle"
