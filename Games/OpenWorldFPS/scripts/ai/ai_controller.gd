extends CharacterBody3D
class_name AIController

signal state_changed(previous_state: StringName, current_state: StringName)
signal attack_started(target: Node3D, damage: float)

const AIBehaviorProfileResource := preload("res://scripts/ai/ai_behavior_profile.gd")

const STATE_IDLE: StringName = &"idle"
const STATE_PATROL: StringName = &"patrol"
const STATE_INVESTIGATE: StringName = &"investigate"
const STATE_EVADE: StringName = &"evade"
const STATE_CHASE: StringName = &"chase"
const STATE_ATTACK: StringName = &"attack"
const STATE_FLEE: StringName = &"flee"

const RESPONSE_IGNORE := "ignore"
const RESPONSE_EVADE := "evade"
const RESPONSE_CHASE := "chase"

@export var profile: AIBehaviorProfileResource
@export_node_path("Node3D") var target_path: NodePath
@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var debug_state_changes: bool = false

var current_state: StringName = &""

var _target: Node3D
var _spawn_origin: Vector3
var _last_known_target_position: Vector3
var _last_threat_position: Vector3
var _has_last_known_target := false
var _state_elapsed := 0.0
var _ai_time := 0.0
var _last_seen_at := -1000000.0
var _idle_duration := 1.0
var _patrol_index := 0
var _attack_cooldown_remaining := 0.0
var _attack_hold_remaining := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if profile == null:
		profile = AIBehaviorProfileResource.new()

	add_to_group("ai_agents")
	_spawn_origin = global_position
	_last_known_target_position = global_position
	_last_threat_position = global_position
	_rng.seed = abs(hash("%s:%s" % [name, str(global_position)]))
	_resolve_target()
	_change_state(profile.normalized_initial_state())

func _physics_process(delta: float) -> void:
	if profile == null:
		return

	_ai_time += delta
	_state_elapsed += delta
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	_attack_hold_remaining = maxf(0.0, _attack_hold_remaining - delta)

	if _target == null or not is_instance_valid(_target):
		_resolve_target()

	var perception := _sense_target()
	_apply_global_transitions(perception)
	_tick_current_state(delta, perception)
	_apply_gravity(delta)
	move_and_slide()

func get_state() -> StringName:
	return current_state

func take_damage(amount: float, source: Node3D = null) -> void:
	current_health = clampf(current_health - amount, 0.0, max_health)
	if source != null:
		_last_threat_position = source.global_position
	if _health_fraction() <= profile.flee_health_fraction:
		_change_state(STATE_FLEE)

func _resolve_target() -> void:
	if target_path != NodePath() and has_node(target_path):
		_target = get_node(target_path) as Node3D
		return

	var grouped_target := get_tree().get_first_node_in_group(profile.target_group)
	_target = grouped_target as Node3D

func _sense_target() -> Dictionary:
	var perception := {
		"has_target": false,
		"can_see": false,
		"can_hear": false,
		"distance": 1000000.0,
	}
	if _target == null or not is_instance_valid(_target):
		return perception

	var target_position := _target.global_position
	var planar_offset := target_position - global_position
	planar_offset.y = 0.0
	var distance := planar_offset.length()
	perception["has_target"] = true
	perception["distance"] = distance

	var can_see: bool = distance <= profile.sight_range and _target_in_field_of_view(planar_offset) and _has_line_of_sight(_target)
	var can_hear: bool = not can_see and distance <= profile.hearing_range
	perception["can_see"] = can_see
	perception["can_hear"] = can_hear

	if can_see or can_hear:
		_remember_target(target_position, can_see)

	return perception

func _remember_target(target_position: Vector3, saw_target: bool) -> void:
	_last_known_target_position = target_position
	_last_threat_position = target_position
	_has_last_known_target = true
	if saw_target:
		_last_seen_at = _ai_time

func _apply_global_transitions(perception: Dictionary) -> void:
	if profile.target_response == RESPONSE_IGNORE:
		return

	if _should_flee(perception):
		_change_state(STATE_FLEE)
		return

	if not perception["has_target"]:
		return

	var distance := float(perception["distance"])
	var can_see := bool(perception["can_see"])
	var can_hear := bool(perception["can_hear"])

	if profile.target_response == RESPONSE_EVADE:
		if can_see and distance <= profile.emergency_flee_distance:
			_change_state(STATE_FLEE)
		elif (can_see or can_hear) and distance <= profile.evade_distance and current_state != STATE_EVADE:
			_change_state(STATE_EVADE)
		return

	if profile.target_response == RESPONSE_CHASE:
		if can_see:
			if distance <= profile.attack_range:
				_change_state(STATE_ATTACK)
			elif current_state != STATE_CHASE:
				_change_state(STATE_CHASE)
		elif can_hear and current_state != STATE_CHASE and current_state != STATE_ATTACK:
			_change_state(STATE_INVESTIGATE)

func _should_flee(perception: Dictionary) -> bool:
	if max_health > 0.0 and _health_fraction() <= profile.flee_health_fraction:
		return true
	return profile.target_response == RESPONSE_EVADE and bool(perception["can_see"]) and float(perception["distance"]) <= profile.emergency_flee_distance

func _tick_current_state(delta: float, perception: Dictionary) -> void:
	match current_state:
		STATE_IDLE:
			_tick_idle(delta)
		STATE_PATROL:
			_tick_patrol(delta)
		STATE_INVESTIGATE:
			_tick_investigate(delta, perception)
		STATE_EVADE:
			_tick_evade(delta, perception)
		STATE_CHASE:
			_tick_chase(delta, perception)
		STATE_ATTACK:
			_tick_attack(delta, perception)
		STATE_FLEE:
			_tick_flee(delta, perception)
		_:
			_change_state(STATE_IDLE)

func _tick_idle(delta: float) -> void:
	_stop_planar(delta)
	if profile.has_patrol_route() and _state_elapsed >= maxf(profile.patrol_wait_time, _idle_duration):
		_change_state(STATE_PATROL)

func _tick_patrol(delta: float) -> void:
	if not profile.has_patrol_route():
		_change_state(STATE_IDLE)
		return

	var destination := _patrol_point_global(_patrol_index)
	if _move_toward(destination, profile.move_speed, profile.stopping_distance, delta):
		_patrol_index = (_patrol_index + 1) % profile.patrol_points.size()
		_change_state(STATE_IDLE)

func _tick_investigate(delta: float, perception: Dictionary) -> void:
	if bool(perception["can_see"]):
		return
	if not _has_last_known_target:
		_return_to_default_state()
		return
	if _state_elapsed >= profile.investigation_duration:
		_return_to_default_state()
		return
	if _move_toward(_last_known_target_position, profile.move_speed, profile.stopping_distance, delta):
		_return_to_default_state()

func _tick_evade(delta: float, perception: Dictionary) -> void:
	var threat_position := _last_threat_position
	if _target != null and is_instance_valid(_target):
		threat_position = _target.global_position

	_steer_away(threat_position, profile.evade_speed, delta)
	if _state_elapsed >= profile.evade_duration or float(perception["distance"]) >= profile.safe_distance:
		_return_to_default_state()

func _tick_chase(delta: float, perception: Dictionary) -> void:
	if not bool(perception["has_target"]):
		_change_state(STATE_INVESTIGATE)
		return

	var destination := _last_known_target_position
	if _target != null and is_instance_valid(_target) and bool(perception["can_see"]):
		destination = _target.global_position

	if not bool(perception["can_see"]) and _ai_time - _last_seen_at >= profile.lost_target_memory:
		_change_state(STATE_INVESTIGATE)
		return

	_move_toward(destination, profile.chase_speed, profile.attack_range * 0.8, delta)

func _tick_attack(delta: float, perception: Dictionary) -> void:
	_stop_planar(delta)
	if not bool(perception["has_target"]):
		_change_state(STATE_INVESTIGATE)
		return
	if not bool(perception["can_see"]):
		_change_state(STATE_CHASE)
		return
	if float(perception["distance"]) > profile.attack_range + profile.stopping_distance:
		_change_state(STATE_CHASE)
		return

	if _target != null and is_instance_valid(_target):
		_face_toward(_target.global_position)
	if _attack_hold_remaining <= 0.0 and _is_attack_ready():
		attack_started.emit(_target, profile.damage)
		_use_attack_cooldown()

func _tick_flee(delta: float, perception: Dictionary) -> void:
	var threat_position := _last_threat_position
	if _target != null and is_instance_valid(_target):
		threat_position = _target.global_position

	_steer_away(threat_position, profile.flee_speed, delta)
	if _state_elapsed >= profile.flee_duration and (not bool(perception["has_target"]) or float(perception["distance"]) >= profile.safe_distance):
		if profile.return_to_patrol_after_flee:
			_return_to_default_state()
		else:
			_change_state(STATE_IDLE)

func _move_toward(destination: Vector3, speed: float, stop_distance: float, delta: float) -> bool:
	var offset := destination - global_position
	offset.y = 0.0
	if offset.length() <= stop_distance:
		_stop_planar(delta)
		return true

	var desired_velocity := _get_path_velocity(destination, speed, stop_distance)
	_set_planar_velocity(desired_velocity, delta)
	_face_toward(global_position + desired_velocity)
	return false

func _get_path_velocity(destination: Vector3, speed: float, stop_distance: float) -> Vector3:
	var offset := destination - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= stop_distance or distance <= 0.001:
		return Vector3.ZERO
	return offset.normalized() * speed

func _steer_away(threat_position: Vector3, speed: float, delta: float) -> void:
	var offset := global_position - threat_position
	offset.y = 0.0
	if offset.length() <= 0.001:
		offset = global_transform.basis.z
	var desired_velocity := offset.normalized() * speed
	_set_planar_velocity(desired_velocity, delta)
	_face_toward(global_position + desired_velocity)

func _set_planar_velocity(planar_velocity: Vector3, delta: float) -> void:
	var accel := maxf(profile.acceleration, 0.1) * delta
	velocity.x = move_toward(velocity.x, planar_velocity.x, accel)
	velocity.z = move_toward(velocity.z, planar_velocity.z, accel)

func _stop_planar(delta: float) -> void:
	_set_planar_velocity(Vector3.ZERO, delta)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= profile.gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

func _target_in_field_of_view(planar_offset: Vector3) -> bool:
	if planar_offset.length() <= 0.001:
		return true
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length() <= 0.001:
		return true
	var angle := rad_to_deg(forward.normalized().angle_to(planar_offset.normalized()))
	return angle <= profile.field_of_view_degrees * 0.5

func _has_line_of_sight(candidate: Node3D) -> bool:
	var origin: Vector3 = global_position + Vector3.UP * profile.eye_height
	var target_position: Vector3 = candidate.global_position + Vector3.UP * profile.eye_height
	var query := PhysicsRayQueryParameters3D.create(origin, target_position)
	query.collision_mask = profile.line_of_sight_mask
	query.exclude = [get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true

	var collider: Variant = hit.get("collider")
	if collider == candidate:
		return true
	if collider is Node and candidate.is_ancestor_of(collider):
		return true
	return false

func _face_toward(point: Vector3) -> void:
	var look_target := Vector3(point.x, global_position.y, point.z)
	if global_position.distance_squared_to(look_target) <= 0.0001:
		return
	look_at(look_target, Vector3.UP)

func _is_attack_ready() -> bool:
	return _attack_cooldown_remaining <= 0.0

func _use_attack_cooldown() -> void:
	_attack_cooldown_remaining = maxf(profile.attack_cooldown, 0.0)
	_attack_hold_remaining = maxf(profile.attack_hold_time, 0.0)

func _return_to_default_state() -> void:
	if profile.has_patrol_route():
		_change_state(STATE_PATROL)
	else:
		_change_state(STATE_IDLE)

func _patrol_point_global(index: int) -> Vector3:
	var clamped_index: int = index % profile.patrol_points.size()
	return _spawn_origin + profile.patrol_points[clamped_index]

func _pick_idle_duration() -> float:
	var minimum := minf(profile.idle_duration_min, profile.idle_duration_max)
	var maximum := maxf(profile.idle_duration_min, profile.idle_duration_max)
	return _rng.randf_range(minimum, maximum)

func _health_fraction() -> float:
	if max_health <= 0.0:
		return 1.0
	return clampf(current_health / max_health, 0.0, 1.0)

func _change_state(next_state: StringName) -> void:
	if current_state == next_state:
		return

	var previous_state := current_state
	current_state = next_state
	_state_elapsed = 0.0
	if current_state == STATE_IDLE:
		_idle_duration = _pick_idle_duration()
	if current_state == STATE_ATTACK:
		_attack_hold_remaining = 0.0

	if debug_state_changes:
		print("%s AI state: %s -> %s" % [name, previous_state, current_state])
	state_changed.emit(previous_state, current_state)
