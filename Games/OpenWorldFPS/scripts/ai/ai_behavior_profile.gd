extends Resource
class_name AIBehaviorProfile

enum State {
	IDLE,
	PATROL,
	INVESTIGATE,
	EVADE,
	CHASE,
	ATTACK,
	FLEE,
}

enum TargetResponse {
	IGNORE,
	EVADE,
	CHASE,
}

@export var entity_name: String = "AI Entity"
@export var initial_state: State = State.IDLE
@export var target_response: TargetResponse = TargetResponse.IGNORE

@export_category("Vitals")
@export_range(1.0, 500.0, 1.0) var max_health: float = 50.0
@export_range(0.0, 1.0, 0.01) var flee_health_ratio: float = 0.2

@export_category("Perception")
@export_range(0.0, 120.0, 0.5) var sight_range: float = 22.0
@export_range(0.0, 120.0, 0.5) var hearing_range: float = 8.0
@export_range(1.0, 360.0, 1.0) var field_of_view_degrees: float = 180.0
@export_flags_3d_physics var line_of_sight_mask: int = 6
@export_range(0.0, 3.0, 0.05) var eye_height: float = 0.8
@export_range(0.0, 3.0, 0.05) var target_aim_height: float = 0.5
@export_range(0.0, 15.0, 0.1) var target_memory_duration: float = 2.5

@export_category("Movement")
@export_range(0.1, 20.0, 0.1) var walk_speed: float = 3.0
@export_range(0.1, 25.0, 0.1) var chase_speed: float = 5.0
@export_range(0.1, 25.0, 0.1) var evade_speed: float = 5.5
@export_range(0.1, 25.0, 0.1) var flee_speed: float = 7.0
@export_range(0.1, 60.0, 0.1) var acceleration: float = 16.0
@export_range(0.0, 80.0, 0.1) var gravity: float = 18.0
@export_range(0.05, 5.0, 0.05) var path_stop_distance: float = 0.75

@export_category("Patrol")
@export var patrol_offsets: Array[Vector3] = []
@export_range(0.0, 10.0, 0.1) var idle_duration: float = 1.0

@export_category("Investigate")
@export_range(0.0, 20.0, 0.1) var investigate_duration: float = 3.0

@export_category("Evade And Flee")
@export_range(0.0, 20.0, 0.1) var evade_duration: float = 1.25
@export_range(0.0, 40.0, 0.5) var safe_distance: float = 12.0
@export_range(0.0, 40.0, 0.5) var emergency_flee_distance: float = 4.0
@export_range(0.0, 30.0, 0.1) var flee_duration: float = 4.0

@export_category("Combat")
@export_range(0.0, 25.0, 0.1) var attack_range: float = 2.0
@export_range(0.0, 10.0, 0.05) var attack_cooldown: float = 1.0
@export_range(0.0, 5.0, 0.05) var attack_hold_time: float = 0.35
@export_range(0.0, 200.0, 1.0) var attack_damage: float = 8.0

func can_attack() -> bool:
	return target_response == TargetResponse.CHASE and attack_damage > 0.0 and attack_range > 0.0
