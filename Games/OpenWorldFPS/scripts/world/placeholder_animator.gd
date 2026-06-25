extends Node
class_name PlaceholderAnimator

@export_enum("bob", "sway", "pulse", "drift") var motion: String = "bob"
@export var amplitude: float = 0.08
@export var speed: float = 1.0
@export var rotation_degrees: float = 3.0
@export var start_offset: float = 0.0

var _target: Node3D
var _base_position: Vector3
var _base_rotation: Vector3
var _base_scale: Vector3
var _time: float = 0.0

func _ready() -> void:
	_target = get_parent() as Node3D
	if _target == null:
		set_process(false)
		return

	_base_position = _target.position
	_base_rotation = _target.rotation
	_base_scale = _target.scale
	add_to_group("placeholder_animation")

func _process(delta: float) -> void:
	if _target == null:
		return

	_time += delta * speed
	var phase := _time + start_offset
	match motion:
		"sway":
			_target.position = _base_position + Vector3(sin(phase * 0.75) * amplitude, 0.0, 0.0)
			_target.rotation = _base_rotation + Vector3(0.0, 0.0, deg_to_rad(sin(phase) * rotation_degrees))
		"pulse":
			var scale_factor := 1.0 + sin(phase) * amplitude
			_target.scale = _base_scale * maxf(scale_factor, 0.05)
		"drift":
			_target.position = _base_position + Vector3(0.0, sin(phase * 0.6) * amplitude, 0.0)
			_target.rotation = _base_rotation + Vector3(0.0, phase * 0.15, 0.0)
		_:
			_target.position = _base_position + Vector3(0.0, sin(phase) * amplitude, 0.0)
			_target.rotation = _base_rotation + Vector3(deg_to_rad(sin(phase * 0.5) * rotation_degrees), 0.0, 0.0)
