extends CharacterBody3D

signal health_updated(current_health: float, max_health: float)
signal alert_updated(level: float)
signal target_lock_updated(enabled: bool)
signal death_state_changed(is_dead: bool)

@export var move_speed: float = 8.5
@export var sprint_speed: float = 13.0
@export var jump_velocity: float = 6.0
@export var gravity: float = 18.0
@export var mouse_sensitivity: float = 0.0032

@export var shoot_range: float = 120.0
@export var shoot_damage: float = 18.0
@export var shoot_cooldown: float = 0.14

@export var max_health: float = 100.0
@export var max_alert: float = 100.0
@export var auto_alert_decay: float = 8.0
@export var alert_gain_from_shoot: float = 12.0
@export var alert_gain_from_hit: float = 26.0

@onready var eyes: Node3D = $Head
@onready var eyes_camera: Camera3D = $Head/Camera3D

const LOOK_PITCH_LIMIT: float = 85.0

var _health: float = 0.0
var _alert_level: float = 0.0
var _target_locked: bool = false
var _dead: bool = false
var _shoot_timer: float = 0.0
var _respawn_transform: Transform3D

func _ready() -> void:
	_respawn_transform = global_transform
	_health = max_health
	add_to_group("player")
	_update_health(_health)
	_update_alert(0.0)
	_set_target_lock(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if _dead:
		if event.is_action_pressed("reload"):
			request_reset()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		eyes.rotate_x(-event.relative.y * mouse_sensitivity)
		eyes.rotation.x = clamp(eyes.rotation.x, deg_to_rad(-LOOK_PITCH_LIMIT), deg_to_rad(LOOK_PITCH_LIMIT))

	if event.is_action_pressed("shoot"):
		_try_shoot()

func _physics_process(delta: float) -> void:
	_shoot_timer = maxf(_shoot_timer - delta, 0.0)

	if _dead:
		return

	_update_movement(delta)
	_update_alert(delta)
	_update_target_lock()
	move_and_slide()

func _update_movement(delta: float) -> void:
	var input_direction := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		input_direction -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		input_direction += transform.basis.z
	if Input.is_action_pressed("move_left"):
		input_direction -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		input_direction += transform.basis.x

	input_direction = input_direction.normalized()
	var speed := move_speed
	if Input.is_action_pressed("run"):
		speed = sprint_speed

	velocity.x = input_direction.x * speed
	velocity.z = input_direction.z * speed
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= gravity * delta

func _try_shoot() -> void:
	if _shoot_timer > 0.0:
		return
	_shoot_timer = shoot_cooldown
	_increase_alert(alert_gain_from_shoot)

	var hit = _fire_ray_query()
	if hit.is_empty():
		return

	var target := _resolve_hit_target(hit)
	if target == null:
		return

	target.apply_damage(shoot_damage)
	_increase_alert(alert_gain_from_hit)

func _fire_ray_query() -> Dictionary:
	var from := eyes_camera.global_position
	var direction := -eyes_camera.global_transform.basis.z * shoot_range
	var to := from + direction
	var parameters := PhysicsRayQueryParameters3D.create(from, to)
	parameters.exclude = [self]
	parameters.collide_with_areas = true
	parameters.collide_with_bodies = true

	return get_world_3d().direct_space_state.intersect_ray(parameters)

func _update_target_lock() -> void:
	var hit = _fire_ray_query()
	var target := _resolve_hit_target(hit)
	var locked := target != null
	_set_target_lock(locked)

func _resolve_hit_target(hit: Dictionary) -> Node:
	if hit.is_empty():
		return null

	var collider: Node = hit.get("collider", null) as Node
	if collider == null:
		return null

	var node: Node = collider
	while node:
		if node.is_in_group("targets") and node.has_method("apply_damage"):
			return node
		node = node.get_parent()

	return null

func _update_alert(delta: float) -> void:
	_set_alert(_alert_level - auto_alert_decay * delta)

func _set_target_lock(enabled: bool) -> void:
	if _target_locked == enabled:
		return
	_target_locked = enabled
	target_lock_updated.emit(_target_locked)

func _set_alert(value: float) -> void:
	_alert_level = clampf(value, 0.0, max_alert)
	alert_updated.emit(_alert_level)

func _increase_alert(value: float) -> void:
	_set_alert(_alert_level + value)

func _update_health(value: float) -> void:
	_health = clampf(value, 0.0, max_health)
	health_updated.emit(_health, max_health)

func apply_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	_update_health(_health - amount)
	if _health <= 0.0:
		_die()

func request_reset() -> void:
	_dead = false
	death_state_changed.emit(false)
	global_transform = _respawn_transform
	_update_health(max_health)
	_update_alert(0.0)
	_set_target_lock(false)
	velocity = Vector3.ZERO
	_shoot_timer = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _die() -> void:
	_dead = true
	velocity = Vector3.ZERO
	_update_alert(0.0)
	_set_target_lock(false)
	death_state_changed.emit(true)

func heal(amount: float) -> void:
	if amount <= 0.0 or _dead:
		return
	_update_health(_health + amount)

func get_health() -> float:
	return _health

func get_alert() -> float:
	return _alert_level

func is_dead() -> bool:
	return _dead

func is_target_locked() -> bool:
	return _target_locked
