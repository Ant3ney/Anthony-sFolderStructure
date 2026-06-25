extends StaticBody3D

signal destroyed

@export var max_health: float = 55.0
@export var contact_damage: float = 10.0
@export var contact_interval: float = 0.75

var _health: float = 0.0
var _contact_cooldowns: Dictionary = {}

func _ready() -> void:
	_health = max_health
	add_to_group("targets")
	$DamageArea.body_entered.connect(_on_body_entered)
	$DamageArea.body_exited.connect(_on_body_exited)

func apply_damage(amount: float) -> void:
	if amount <= 0.0 or _health <= 0.0:
		return
	_health = maxf(_health - amount, 0.0)
	if _health <= 0.0:
		destroyed.emit()
		queue_free()

func _physics_process(delta: float) -> void:
	if _contact_cooldowns.is_empty():
		return

	for body_id in _contact_cooldowns.keys():
		var remaining := float(_contact_cooldowns[body_id]) - delta
		if remaining <= 0.0:
			_contact_cooldowns.erase(body_id)
			continue
		_contact_cooldowns[body_id] = remaining

func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("apply_damage"):
		return
	var body_id := body.get_instance_id()
	if _contact_cooldowns.has(body_id):
		return
	body.apply_damage(contact_damage)
	_contact_cooldowns[body_id] = contact_interval

func _on_body_exited(body: Node3D) -> void:
	_contact_cooldowns.erase(body.get_instance_id())
