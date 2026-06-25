extends CharacterBody3D
class_name AIController

const AIBehaviorProfileResource := preload("res://scripts/ai/ai_behavior_profile.gd")

signal state_changed(previous_state: String, next_state: String)
signal attack_started(target: Node, damage: float)
signal health_changed(current_health: float, max_health: float)
signal died

const STATE_NAMES := {
	AIBehaviorProfileResource.State.IDLE: "idle",
	AIBehaviorProfileResource.State.PATROL: "patrol",
	AIBehaviorProfileResource.State.INVESTIGATE: "investigate",
	AIBehaviorProfileResource.State.EVADE: "evade",
	AIBehaviorProfileResource.State.CHASE: "chase",
	AIBehaviorProfileResource.State.ATTACK: "attack",
	AIBehaviorProfileResource.State.FLEE: "flee",
}

@export var behavior_profile: AIBehaviorProfileResource
@export_node_path("Node3D") var target_path: NodePath
@export_node_path("NavigationAgent3D") var navigation_agent_path: NodePath

var _current_state: int = AIBehaviorProfileResource.State.IDLE
var _health: float = 0.0
var _spawn_position: Vector3
var _patrol_index: int = 0
var _state_timer: float = 0.0
var _attack_timer: float = 0.0
var _target_memory_timer: float = 0.0
var _last_known_target_position: Vector3
var _target_visible: bool = false
var _target_heard: bool = false
var _dead: bool = false
var _target: Node3D
var _navigation_agent: NavigationAgent3D

func _ready() -> void:
	if behavior_profile == null:
		push_error("%s needs an AIBehaviorProfileResource." % name)
		set_physics_process(false)
		return

	_spawn_position = global_position
	_current_state = behavior_profile.initial_state
	_health = behavior_profile.max_health
	_last_known_target_position = global_position
	add_to_group("targets")
	add_to_group("ai_entities")
	_resolve_target()
	_resolve_navigation_agent()
	health_changed.emit(_health, behavior_profile.max_health)

func _physics_process(delta: float) -> void:
	if behavior_profile == null or _dead:
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_state_timer += delta

	_update_perception(delta)
	_apply_global_transitions()
	_run_state(delta)
	_apply_gravity(delta)
	move_and_slide()

func _resolve_target() -> void:
	if target_path != NodePath() and has_node(target_path):
		_target = get_node(target_path) as Node3D
		return

	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_target = players[0] as Node3D

func _resolve_navigation_agent() -> void:
	if navigation_agent_path != NodePath() and has_node(navigation_agent_path):
		_navigation_agent = get_node(navigation_agent_path) as NavigationAgent3D

func _update_perception(delta: float) -> void:
	_target_visible = false
	_target_heard = false

	if _target == null or not is_instance_valid(_target) or _is_target_dead():
		_target_memory_timer = maxf(_target_memory_timer - delta, 0.0)
		return

	var distance := _distance_to_target()
	if distance <= behavior_profile.sight_range and _has_line_of_sight(_target):
		_target_visible = true
		_remember_target_position()
		return

	if distance <= behavior_profile.hearing_range:
		_target_heard = true
		_remember_target_position()
		return

	_target_memory_timer = maxf(_target_memory_timer - delta, 0.0)

func _remember_target_position() -> void:
	_last_known_target_position = _target.global_position
	_target_memory_timer = behavior_profile.target_memory_duration

func _apply_global_transitions() -> void:
	if _target == null or not is_instance_valid(_target):
		return

	if _should_flee_from_health():
		_transition_to(AIBehaviorProfileResource.State.FLEE)
		return

	match behavior_profile.target_response:
		AIBehaviorProfileResource.TargetResponse.EVADE:
			_apply_evasion_transitions()
		AIBehaviorProfileResource.TargetResponse.CHASE:
			_apply_chase_transitions()

func _apply_evasion_transitions() -> void:
	if _current_state == AIBehaviorProfileResource.State.FLEE:
		return

	var distance := _distance_to_target()
	if behavior_profile.emergency_flee_distance > 0.0 and distance <= behavior_profile.emergency_flee_distance:
		_transition_to(AIBehaviorProfileResource.State.FLEE)
		return

	if _target_visible or distance <= behavior_profile.safe_distance:
		if _current_state != AIBehaviorProfileResource.State.EVADE:
			_transition_to(AIBehaviorProfileResource.State.EVADE)

func _apply_chase_transitions() -> void:
	if _current_state == AIBehaviorProfileResource.State.FLEE:
		return

	if _target_visible:
		if behavior_profile.can_attack() and _distance_to_target() <= behavior_profile.attack_range:
			_transition_to(AIBehaviorProfileResource.State.ATTACK)
		elif _current_state != AIBehaviorProfileResource.State.CHASE and _current_state != AIBehaviorProfileResource.State.ATTACK:
			_transition_to(AIBehaviorProfileResource.State.CHASE)
		return

	if _target_heard and _current_state != AIBehaviorProfileResource.State.INVESTIGATE:
		_transition_to(AIBehaviorProfileResource.State.INVESTIGATE)

func _run_state(delta: float) -> void:
	match _current_state:
		AIBehaviorProfileResource.State.IDLE:
			_run_idle(delta)
		AIBehaviorProfileResource.State.PATROL:
			_run_patrol(delta)
		AIBehaviorProfileResource.State.INVESTIGATE:
			_run_investigate(delta)
		AIBehaviorProfileResource.State.EVADE:
			_run_evade(delta)
		AIBehaviorProfileResource.State.CHASE:
			_run_chase(delta)
		AIBehaviorProfileResource.State.ATTACK:
			_run_attack(delta)
		AIBehaviorProfileResource.State.FLEE:
			_run_flee(delta)

func _run_idle(delta: float) -> void:
	_stop_horizontal(delta)
	if _state_timer >= behavior_profile.idle_duration and _has_patrol_route():
		_transition_to(AIBehaviorProfileResource.State.PATROL)

func _run_patrol(delta: float) -> void:
	if not _has_patrol_route():
		_transition_to(AIBehaviorProfileResource.State.IDLE)
		return

	var destination := _patrol_destination()
	if _horizontal_distance_to(destination) <= behavior_profile.path_stop_distance:
		_patrol_index = (_patrol_index + 1) % behavior_profile.patrol_offsets.size()
		_transition_to(AIBehaviorProfileResource.State.IDLE)
		return

	_move_towards(destination, behavior_profile.walk_speed, behavior_profile.path_stop_distance, delta)

func _run_investigate(delta: float) -> void:
	var reached := _horizontal_distance_to(_last_known_target_position) <= behavior_profile.path_stop_distance
	if reached or _state_timer >= behavior_profile.investigate_duration:
		_return_to_ambient_state()
		return

	_move_towards(_last_known_target_position, behavior_profile.walk_speed, behavior_profile.path_stop_distance, delta)

func _run_evade(delta: float) -> void:
	var destination := _away_from_target_destination(behavior_profile.safe_distance)
	_move_towards(destination, behavior_profile.evade_speed, behavior_profile.path_stop_distance, delta)

	var safe := _target == null or not is_instance_valid(_target) or _distance_to_target() >= behavior_profile.safe_distance
	if _state_timer >= behavior_profile.evade_duration and safe:
		_return_to_ambient_state()

func _run_chase(delta: float) -> void:
	if _target_visible and _target != null and is_instance_valid(_target):
		if behavior_profile.can_attack() and _distance_to_target() <= behavior_profile.attack_range:
			_transition_to(AIBehaviorProfileResource.State.ATTACK)
			return
		_move_towards(_target.global_position, behavior_profile.chase_speed, behavior_profile.attack_range * 0.75, delta)
		return

	if _target_memory_timer > 0.0:
		_move_towards(_last_known_target_position, behavior_profile.chase_speed, behavior_profile.path_stop_distance, delta)
		return

	_transition_to(AIBehaviorProfileResource.State.INVESTIGATE)

func _run_attack(delta: float) -> void:
	_stop_horizontal(delta)
	if _target == null or not is_instance_valid(_target) or _is_target_dead():
		_return_to_ambient_state()
		return

	_face_position(_target.global_position, delta)
	if not _target_visible:
		_transition_to(AIBehaviorProfileResource.State.CHASE)
		return

	if _distance_to_target() > behavior_profile.attack_range:
		_transition_to(AIBehaviorProfileResource.State.CHASE)
		return

	if _is_attack_ready():
		_use_attack_cooldown()

	if _state_timer >= behavior_profile.attack_hold_time and _distance_to_target() > behavior_profile.attack_range * 0.8:
		_transition_to(AIBehaviorProfileResource.State.CHASE)

func _run_flee(delta: float) -> void:
	var destination := _away_from_target_destination(maxf(behavior_profile.safe_distance * 1.5, behavior_profile.emergency_flee_distance + 2.0))
	_move_towards(destination, behavior_profile.flee_speed, behavior_profile.path_stop_distance, delta)

	var safe := _target == null or not is_instance_valid(_target) or _distance_to_target() >= behavior_profile.safe_distance * 1.25
	if _state_timer >= behavior_profile.flee_duration and safe:
		_return_to_ambient_state()

func _return_to_ambient_state() -> void:
	if _has_patrol_route():
		_transition_to(AIBehaviorProfileResource.State.PATROL)
	else:
		_transition_to(AIBehaviorProfileResource.State.IDLE)

func _transition_to(next_state: int) -> void:
	if _current_state == next_state:
		return

	var previous_name := get_current_state_name()
	_current_state = next_state
	_state_timer = 0.0
	state_changed.emit(previous_name, get_current_state_name())

func _has_patrol_route() -> bool:
	return behavior_profile.patrol_offsets.size() > 0

func _patrol_destination() -> Vector3:
	return _spawn_position + behavior_profile.patrol_offsets[_patrol_index]

func _move_towards(destination: Vector3, speed: float, stop_distance: float, delta: float) -> void:
	var desired_velocity := _get_path_velocity(destination, speed, stop_distance)
	_apply_horizontal_velocity(desired_velocity, delta)
	_face_position(destination, delta)

func _stop_horizontal(delta: float) -> void:
	_apply_horizontal_velocity(Vector3.ZERO, delta)

func _apply_horizontal_velocity(desired_velocity: Vector3, delta: float) -> void:
	var current := Vector3(velocity.x, 0.0, velocity.z)
	var next := current.move_toward(desired_velocity, behavior_profile.acceleration * delta)
	velocity.x = next.x
	velocity.z = next.z

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -0.1
	else:
		velocity.y -= behavior_profile.gravity * delta

func _get_path_velocity(destination: Vector3, speed: float, stop_distance: float) -> Vector3:
	var next_position := destination
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		_navigation_agent.target_position = destination
		next_position = _navigation_agent.get_next_path_position()

	var offset := next_position - global_position
	offset.y = 0.0
	if offset.length() <= stop_distance:
		return Vector3.ZERO
	return offset.normalized() * speed

func _has_line_of_sight(target: Node3D) -> bool:
	var from := global_position + Vector3.UP * behavior_profile.eye_height
	var to := target.global_position + Vector3.UP * behavior_profile.target_aim_height
	var offset := to - from

	if offset.length() > behavior_profile.sight_range:
		return false
	if not _is_inside_field_of_view(offset):
		return false

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collision_mask = behavior_profile.line_of_sight_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	return _collider_belongs_to_target(hit.get("collider", null), target)

func _is_inside_field_of_view(offset: Vector3) -> bool:
	if behavior_profile.field_of_view_degrees >= 359.0:
		return true

	var planar_offset := offset
	planar_offset.y = 0.0
	if planar_offset.length_squared() <= 0.001:
		return true

	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		return true

	var angle := rad_to_deg(forward.normalized().angle_to(planar_offset.normalized()))
	return angle <= behavior_profile.field_of_view_degrees * 0.5

func _collider_belongs_to_target(collider: Variant, target: Node3D) -> bool:
	var node := collider as Node
	while node != null:
		if node == target:
			return true
		node = node.get_parent()
	return false

func _is_attack_ready() -> bool:
	return _attack_timer <= 0.0 and behavior_profile.can_attack()

func _use_attack_cooldown() -> void:
	_attack_timer = behavior_profile.attack_cooldown
	attack_started.emit(_target, behavior_profile.attack_damage)
	if _target != null and is_instance_valid(_target) and _target.has_method("apply_damage"):
		_target.call("apply_damage", behavior_profile.attack_damage)

func _away_from_target_destination(distance: float) -> Vector3:
	if _target == null or not is_instance_valid(_target):
		return global_position

	var away := global_position - _target.global_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = global_transform.basis.x
		away.y = 0.0
	return global_position + away.normalized() * maxf(distance, 1.0)

func _face_position(destination: Vector3, delta: float) -> void:
	var direction := destination - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return

	var target_basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	global_basis = global_basis.slerp(target_basis, clampf(delta * 8.0, 0.0, 1.0)).orthonormalized()

func _horizontal_distance_to(position: Vector3) -> float:
	var offset := position - global_position
	offset.y = 0.0
	return offset.length()

func _distance_to_target() -> float:
	if _target == null or not is_instance_valid(_target):
		return INF
	return global_position.distance_to(_target.global_position)

func _should_flee_from_health() -> bool:
	if behavior_profile.flee_health_ratio <= 0.0:
		return false
	return _health <= behavior_profile.max_health * behavior_profile.flee_health_ratio

func _is_target_dead() -> bool:
	return _target != null and _target.has_method("is_dead") and bool(_target.call("is_dead"))

func apply_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return

	_health = maxf(_health - amount, 0.0)
	health_changed.emit(_health, behavior_profile.max_health)
	if _health <= 0.0:
		_die()
	elif _should_flee_from_health():
		_transition_to(AIBehaviorProfileResource.State.FLEE)

func _die() -> void:
	_dead = true
	velocity = Vector3.ZERO
	died.emit()
	queue_free()

func set_target(target: Node3D) -> void:
	_target = target
	if _target != null:
		_remember_target_position()

func get_current_state() -> int:
	return _current_state

func get_current_state_name() -> String:
	return STATE_NAMES.get(_current_state, "unknown")

func get_health() -> float:
	return _health

func is_dead() -> bool:
	return _dead
