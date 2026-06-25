extends CharacterBody3D

@export var move_speed: float = 8.5
@export var sprint_speed: float = 13.0
@export var jump_velocity: float = 6.0
@export var gravity: float = 18.0
@export var mouse_sensitivity: float = 0.0032

@onready var eyes: Node3D = $Head

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		eyes.rotate_x(-event.relative.y * mouse_sensitivity)
		eyes.rotation.x = clamp(eyes.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))

	if event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
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

	var desired = Vector3(input_direction.x * speed, velocity.y, input_direction.z * speed)
	velocity.x = desired.x
	velocity.z = desired.z

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	move_and_slide()
