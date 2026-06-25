extends "res://scripts/ai/ai_controller.gd"
class_name BlackMountainLionController

const LionProfileResource := preload("res://scripts/ai/ai_behavior_profile.gd")

@export_category("Black Mountain Lion")
@export var migration_enabled: bool = true
@export_range(0.5, 16.0, 0.1) var migration_speed: float = 1.8
@export_range(1.0, 30.0, 0.5) var migration_stop_distance: float = 3.5
@export_range(3.0, 30.0, 0.5) var stalk_distance: float = 12.0
@export_range(0.5, 12.0, 0.25) var flank_offset: float = 5.0
@export_range(0.5, 15.0, 0.25) var retreat_trigger_distance: float = 5.5
@export_range(0.5, 12.0, 0.25) var flank_switch_interval: float = 4.0

var pressure_stage: int = 0

var _has_migration_destination: bool = false
var _migration_destination: Vector3 = Vector3.ZERO
var _flank_direction: float = 1.0
var _flank_timer: float = 0.0
var _lion_creep_rate: float = 1.0

func _ready() -> void:
	super._ready()
	add_to_group("black_mountain_lions")
	add_to_group("village_pressure")
	_flank_direction = -1.0 if get_instance_id() % 2 == 0 else 1.0

func _physics_process(delta: float) -> void:
	_flank_timer += delta
	if _flank_timer >= flank_switch_interval:
		_flank_timer = 0.0
		_flank_direction *= -1.0
	super._physics_process(delta)

func _apply_chase_transitions() -> void:
	if _current_state == LionProfileResource.State.FLEE:
		return

	var distance := _distance_to_target()
	if behavior_profile.can_attack() and distance <= behavior_profile.attack_range and (_target_visible or _target_heard or _target_memory_timer > 0.0):
		_transition_to(LionProfileResource.State.ATTACK)
		return

	if _target_visible:
		if distance <= retreat_trigger_distance:
			_transition_to(LionProfileResource.State.FLEE)
			return
		if distance <= behavior_profile.safe_distance:
			_transition_to(LionProfileResource.State.EVADE)
			return
		if _current_state != LionProfileResource.State.CHASE and _current_state != LionProfileResource.State.ATTACK:
			_transition_to(LionProfileResource.State.CHASE)
		return

	if _target_heard and _current_state != LionProfileResource.State.INVESTIGATE:
		_transition_to(LionProfileResource.State.INVESTIGATE)

func _run_idle(delta: float) -> void:
	if _should_migrate():
		_run_migration(delta)
		return
	super._run_idle(delta)

func _run_patrol(delta: float) -> void:
	if _should_migrate():
		_run_migration(delta)
		return
	super._run_patrol(delta)

func _run_investigate(delta: float) -> void:
	if _target_memory_timer > 0.0:
		super._run_investigate(delta)
		return

	if _should_migrate():
		_run_migration(delta)
		return

	_return_to_ambient_state()

func _run_chase(delta: float) -> void:
	if _target_visible and _target != null and is_instance_valid(_target):
		var distance := _distance_to_target()
		if behavior_profile.can_attack() and distance <= behavior_profile.attack_range:
			_transition_to(LionProfileResource.State.ATTACK)
			return
		if distance <= retreat_trigger_distance:
			_transition_to(LionProfileResource.State.FLEE)
			return
		if distance <= behavior_profile.safe_distance:
			_transition_to(LionProfileResource.State.EVADE)
			return

		_move_towards(_flank_destination(), behavior_profile.chase_speed, behavior_profile.path_stop_distance, delta)
		return

	if _target_memory_timer > 0.0:
		_move_towards(_last_known_target_position, behavior_profile.walk_speed, behavior_profile.path_stop_distance, delta)
		return

	if _should_migrate():
		_run_migration(delta)
		return

	_return_to_ambient_state()

func _run_attack(delta: float) -> void:
	_stop_horizontal(delta)
	if _target == null or not is_instance_valid(_target) or _is_target_dead():
		_return_to_ambient_state()
		return

	_face_position(_target.global_position, delta)
	var close_contact := _distance_to_target() <= behavior_profile.attack_range
	var has_sensory_contact := _target_visible or _target_heard or _target_memory_timer > 0.0
	if not close_contact or not has_sensory_contact:
		_transition_to(LionProfileResource.State.EVADE)
		return

	if _is_attack_ready():
		_use_attack_cooldown()
		_transition_to(LionProfileResource.State.EVADE)
		return

	if _state_timer >= behavior_profile.attack_hold_time:
		_transition_to(LionProfileResource.State.EVADE)

func set_migration_destination(destination: Vector3, stage: int = 0, creep_rate: float = 1.0) -> void:
	_migration_destination = destination
	pressure_stage = max(stage, 0)
	_lion_creep_rate = maxf(creep_rate, 0.05)
	_has_migration_destination = true
	migration_enabled = true

func get_migration_destination() -> Vector3:
	return _migration_destination

func get_pressure_stage() -> int:
	return pressure_stage

func _should_migrate() -> bool:
	return migration_enabled \
		and _has_migration_destination \
		and not _target_visible \
		and _target_memory_timer <= 0.0 \
		and _horizontal_distance_to(_migration_destination) > migration_stop_distance

func _run_migration(delta: float) -> void:
	_move_towards(_migration_destination, migration_speed * _lion_creep_rate, migration_stop_distance, delta)

func _flank_destination() -> Vector3:
	if _target == null or not is_instance_valid(_target):
		return global_position

	var away := global_position - _target.global_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = global_transform.basis.x
		away.y = 0.0

	away = away.normalized()
	var tangent := Vector3(-away.z, 0.0, away.x) * _flank_direction
	var desired_distance := maxf(stalk_distance, behavior_profile.safe_distance)
	return _target.global_position + (away * desired_distance) + (tangent * flank_offset)
