extends Node3D
class_name Chunk

@export var chunk_size: float = 48.0
@export var obstacle_count: int = 12
@export var world_seed: int = 20260625
@export var chunk_coord: Vector2i = Vector2i.ZERO

const WORLD_LAYER: int = 1
const OBSTACLE_LAYER: int = 4
const PLAYER_LAYER: int = 2

enum BiomeKind {
	PLAINS,
	FOREST,
	BADLANDS,
	HILLS
}

enum SettlementState {
	STABLE,
	UNEASY,
	ALERT,
	OVERRUN
}

const BIOME_LIBRARY: Dictionary = {
	BiomeKind.PLAINS: {
		"name": "Plains",
		"hue": 0.16,
		"saturation": 0.24,
		"lightness": 0.36,
		"obstacle_scale": 0.95,
		"town_chance": 0.62,
		"cluster_count": 2.6,
		"cluster_max_size": 4,
		"hostile_chance": 0.20,
		"passive_pool": [0, 1, 2],
		"passive_weights": [0.58, 0.30, 0.12],
		"hostile_pool": [0, 1],
		"hostile_weights": [0.72, 0.28],
		"town_scale": 1.1
	},
	BiomeKind.FOREST: {
		"name": "Forest",
		"hue": 0.36,
		"saturation": 0.35,
		"lightness": 0.32,
		"obstacle_scale": 1.15,
		"town_chance": 0.38,
		"cluster_count": 3.1,
		"cluster_max_size": 5,
		"hostile_chance": 0.28,
		"passive_pool": [1, 2, 3],
		"passive_weights": [0.34, 0.35, 0.31],
		"hostile_pool": [1, 2, 3],
		"hostile_weights": [0.44, 0.36, 0.20],
		"town_scale": 0.85
	},
	BiomeKind.BADLANDS: {
		"name": "Badlands",
		"hue": 0.07,
		"saturation": 0.20,
		"lightness": 0.30,
		"obstacle_scale": 1.30,
		"town_chance": 0.26,
		"cluster_count": 2.2,
		"cluster_max_size": 6,
		"hostile_chance": 0.52,
		"passive_pool": [0, 2],
		"passive_weights": [0.63, 0.37],
		"hostile_pool": [0, 3, 4],
		"hostile_weights": [0.45, 0.30, 0.25],
		"town_scale": 0.8
	},
	BiomeKind.HILLS: {
		"name": "Hills",
		"hue": 0.05,
		"saturation": 0.25,
		"lightness": 0.34,
		"obstacle_scale": 1.05,
		"town_chance": 0.45,
		"cluster_count": 2.4,
		"cluster_max_size": 4,
		"hostile_chance": 0.33,
		"passive_pool": [0, 1, 3],
		"passive_weights": [0.44, 0.41, 0.15],
		"hostile_pool": [2, 3, 4],
		"hostile_weights": [0.24, 0.38, 0.38],
		"town_scale": 0.92
	}
}

const PASSIVE_CREATURES: Array[Dictionary] = [
	{"name": "Rabbit", "mesh": "sphere", "size": 0.34, "color": Color(0.88, 0.84, 0.73)},
	{"name": "Deer", "mesh": "capsule", "size": 0.42, "color": Color(0.56, 0.53, 0.48)},
	{"name": "Sheep", "mesh": "box", "size": 0.36, "color": Color(0.88, 0.90, 0.94)},
	{"name": "Falcon", "mesh": "cone", "size": 0.3, "color": Color(0.35, 0.48, 0.58)}
]

const HOSTILE_CREATURES: Array[Dictionary] = [
	{"name": "Bandit", "mesh": "capsule", "size": 0.55, "color": Color(0.67, 0.18, 0.16)},
	{"name": "Wolf", "mesh": "capsule", "size": 0.58, "color": Color(0.28, 0.33, 0.29)},
	{"name": "Wraith", "mesh": "sphere", "size": 0.52, "color": Color(0.58, 0.12, 0.60)},
	{"name": "Beast", "mesh": "box", "size": 0.72, "color": Color(0.20, 0.23, 0.26)},
	{"name": "Sentinel", "mesh": "cylinder", "size": 0.44, "color": Color(0.16, 0.20, 0.28)}
]

const TOWN_VARIANT_COUNT := 3
const LION_PRESSURE_COLORS: Array[Color] = [
	Color(0.85, 0.86, 0.76),
	Color(0.92, 0.76, 0.35),
	Color(0.95, 0.48, 0.22),
	Color(0.76, 0.12, 0.11),
	Color(0.16, 0.03, 0.04)
]
const SETTLEMENT_STATE_NAMES := ["Stable", "Uneasy", "Alert", "Overrun"]
const SETTLEMENT_NPC_BEHAVIORS := ["routine", "watch", "defend", "shelter"]
const SETTLEMENT_TRAVEL_SAFETY := [1.0, 0.82, 0.58, 0.32]
const SETTLEMENT_STATE_COLORS: Array[Color] = [
	Color(0.42, 0.72, 0.62),
	Color(0.95, 0.78, 0.28),
	Color(0.96, 0.28, 0.20),
	Color(0.18, 0.05, 0.06)
]

var _active_biome: int = BiomeKind.PLAINS
var _distance_to_player: int = 0
var _population_scale: float = 1.0
var _lion_pressure_stage: int = 0
var _lion_density_scale: float = 1.0
var _active_lion_count: int = 0
var _hostile_population: int = 0
var _settlement_state: int = SettlementState.STABLE
var _travel_safety_scale: float = 1.0
var _pressure_enemy_count: int = 0
var _town_centers: Array[Vector3] = []

func initialize(coord: Vector2i, seed: int, chunk_scale: float, obstacle_total: int, player_distance: int, population_scale: float) -> void:
	chunk_coord = coord
	world_seed = seed
	chunk_size = chunk_scale
	obstacle_count = max(0, obstacle_total)
	_distance_to_player = max(0, player_distance)
	_population_scale = clamp(population_scale, 0.15, 1.0)
	_generate_chunk()

func _generate_chunk() -> void:
	for child in get_children():
		child.queue_free()

	_town_centers.clear()
	_hostile_population = 0
	_pressure_enemy_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_from_chunk()

	_active_biome = _resolve_biome()

	_add_ground()
	_add_obstacles(rng)
	_add_towns(rng)
	_add_creature_clusters(rng)
	_refresh_lion_pressure_markers()

func _seed_from_chunk() -> int:
	var x := chunk_coord.x
	var y := chunk_coord.y
	var mixed := (world_seed * 0x9e3779b9) ^ (x * 0x85ebca6b) ^ (y * 0xc2b2ae35)
	if mixed < 0:
		mixed = -mixed
	return mixed

func _chunk_color() -> Color:
	var settings := _active_biome_settings()
	var hue := fmod(abs(float(chunk_coord.x) * 0.17 + float(chunk_coord.y) * 0.23 + float(settings["hue"])), 1.0)
	return Color.from_hsv(hue, float(settings["saturation"]), float(settings["lightness"]))

func _add_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = WORLD_LAYER

	var half_size := chunk_size * 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3(chunk_size, 1.0, chunk_size)
	var collision := CollisionShape3D.new()
	collision.position = Vector3(half_size, -0.5, half_size)
	collision.shape = shape

	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(chunk_size, 1.0, chunk_size)
	var material := StandardMaterial3D.new()
	material.albedo_color = _chunk_color()
	cube.material = material
	mesh.mesh = cube
	mesh.position = Vector3(half_size, -0.5, half_size)

	body.add_child(collision)
	body.add_child(mesh)
	add_child(body)

func _add_obstacles(rng: RandomNumberGenerator) -> void:
	var half_size := chunk_size * 0.5
	var settings := _active_biome_settings()
	var density_scale := float(settings["obstacle_scale"]) * _population_scale
	var obstacle_limit: int = max(1, int(round(float(obstacle_count) * density_scale)))
	var keep_clear_center := chunk_coord == Vector2i.ZERO
	for i in range(obstacle_limit):
		var width := rng.randf_range(0.8, 2.2)
		var depth := rng.randf_range(0.8, 2.2)
		var height := rng.randf_range(0.8, 3.4)
		var x := rng.randf_range(1.5, chunk_size - 1.5)
		var z := rng.randf_range(1.5, chunk_size - 1.5)
		if keep_clear_center and abs(x - half_size) < 6.0 and abs(z - half_size) < 6.0:
			continue
		var origin := Vector3(x, height * 0.5, z)
		_add_box_obstacle(width, height, depth, origin)

func _add_towns(rng: RandomNumberGenerator) -> void:
	var settings := _active_biome_settings()
	var scaled_town_chance := float(settings["town_chance"]) * _population_scale * float(settings["town_scale"])
	var target := 0
	if _distance_to_player == 0:
		target = 1
	elif rng.randf() < clamp(scaled_town_chance, 0.0, 1.0):
		target = 1
	elif _distance_to_player <= 2 and rng.randf() < clamp(scaled_town_chance * 0.45, 0.0, 1.0):
		target = 1

	for i in target:
		var margin := 6.0
		var center := Vector3(
			rng.randf_range(margin, chunk_size - margin),
			0.0,
			rng.randf_range(margin, chunk_size - margin)
		)
		_town_centers.append(center)
		var variant := rng.randi_range(0, TOWN_VARIANT_COUNT - 1)
		match variant:
			0:
				_spawn_town_market(center)
			1:
				_spawn_town_fort(center)
			2:
				_spawn_town_farm(center)

func _add_creature_clusters(rng: RandomNumberGenerator) -> void:
	var settings := _active_biome_settings()
	var cluster_count := int(round(float(settings["cluster_count"]) * _population_scale))
	cluster_count = max(0, cluster_count)
	for i in cluster_count:
		var is_hostile := rng.randf() < float(settings["hostile_chance"]) * _population_scale
		var creature := _pick_creature_definition(rng, is_hostile)
		var size := rng.randi_range(2, int(settings["cluster_max_size"]))
		if is_hostile:
			_hostile_population += max(2, size)
		var center := Vector3(
			rng.randf_range(3.0, chunk_size - 3.0),
			0.0,
			rng.randf_range(3.0, chunk_size - 3.0)
		)
		_spawn_creature_cluster(rng, center, creature, size)

func _add_box_obstacle(width: float, height: float, depth: float, position: Vector3, color: Color = Color(0.42, 0.44, 0.46), is_physical: bool = true) -> void:
	var body := StaticBody3D.new()
	if is_physical:
		body.collision_layer = OBSTACLE_LAYER
		body.collision_mask = WORLD_LAYER | PLAYER_LAYER

	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, depth)
	var collision := CollisionShape3D.new()
	collision.position = position
	collision.shape = shape

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, depth)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	mesh.position = position
	mesh.position.y += 0.01

	body.add_child(collision)
	body.add_child(mesh)
	add_child(body)

func _spawn_creature_cluster(rng: RandomNumberGenerator, center: Vector3, definition: Dictionary, member_count: int) -> void:
	var radius := rng.randf_range(1.0, 2.2)
	for i in range(max(2, member_count)):
		var angle := TAU * float(i) / float(max(2, member_count)) + rng.randf_range(-0.35, 0.35)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		_add_creature(definition, center + offset)

func _add_creature(definition: Dictionary, position: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var size := float(definition["size"])
	var mesh_name := String(definition["mesh"])

	var mesh := _shape_mesh(mesh_name, size)
	var material := StandardMaterial3D.new()
	material.albedo_color = definition["color"]
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(
		position.x,
		size * 0.55,
		position.z
	)
	mesh_instance.name = "Creature_%s" % definition["name"]
	add_child(mesh_instance)

func _shape_mesh(shape_name: String, size: float) -> Mesh:
	var mesh: Mesh
	match shape_name:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = size
			sphere.height = size * 2.0
			mesh = sphere
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = size * 0.45
			capsule.height = size * 2.4
			mesh = capsule
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.bottom_radius = size * 0.55
			cylinder.top_radius = size * 0.55
			cylinder.height = size * 2.4
			mesh = cylinder
		_:
			var box := BoxMesh.new()
			box.size = Vector3(size, size * 0.9, size)
			mesh = box
	return mesh

func _spawn_town_market(origin: Vector3) -> void:
	_add_box_obstacle(6.8, 0.65, 5.4, origin + Vector3(0.0, 0.0, 0.0), Color(0.76, 0.69, 0.47), true)
	_add_box_obstacle(1.4, 1.0, 1.4, origin + Vector3(-2.2, 0.0, -0.8), Color(0.78, 0.52, 0.33), true)
	_add_box_obstacle(1.1, 0.8, 1.1, origin + Vector3(0.9, 0.0, 1.2), Color(0.73, 0.62, 0.52), true)
	_add_box_obstacle(1.0, 0.9, 1.0, origin + Vector3(2.1, 0.0, -1.4), Color(0.72, 0.60, 0.55), true)
	_add_box_obstacle(1.5, 0.3, 1.5, origin + Vector3(0.0, 1.2, 0.0), Color(0.95, 0.87, 0.59), false)

func _spawn_town_fort(origin: Vector3) -> void:
	_add_box_obstacle(7.2, 1.0, 0.7, origin + Vector3(0.0, 0.0, -2.8), Color(0.45, 0.36, 0.33), true)
	_add_box_obstacle(7.2, 1.0, 0.7, origin + Vector3(0.0, 0.0, 2.8), Color(0.45, 0.36, 0.33), true)
	_add_box_obstacle(0.7, 1.0, 7.2, origin + Vector3(-2.8, 0.0, 0.0), Color(0.45, 0.36, 0.33), true)
	_add_box_obstacle(0.7, 1.0, 7.2, origin + Vector3(2.8, 0.0, 0.0), Color(0.45, 0.36, 0.33), true)
	_add_box_obstacle(1.3, 2.3, 1.3, origin + Vector3(0.0, 0.0, 0.0), Color(0.62, 0.53, 0.44), true)
	_add_box_obstacle(1.8, 3.0, 1.8, origin + Vector3(0.0, 1.8, 0.0), Color(0.83, 0.78, 0.67), true)

func _spawn_town_farm(origin: Vector3) -> void:
	_add_box_obstacle(6.0, 0.45, 1.2, origin + Vector3(0.0, 0.0, -1.9), Color(0.72, 0.62, 0.44), true)
	_add_box_obstacle(1.4, 0.8, 1.4, origin + Vector3(-2.1, 0.0, 1.0), Color(0.62, 0.72, 0.53), true)
	_add_box_obstacle(1.2, 0.8, 1.1, origin + Vector3(0.5, 0.0, 1.2), Color(0.54, 0.66, 0.53), true)
	_add_box_obstacle(1.3, 0.9, 1.4, origin + Vector3(2.0, 0.0, 0.7), Color(0.52, 0.63, 0.50), true)
	_add_box_obstacle(1.0, 0.6, 1.0, origin + Vector3(-0.2, 0.0, -1.4), Color(0.84, 0.86, 0.72), false)

func set_lion_pressure(stage: int, density_scale: float, active_lion_count: int = 0) -> void:
	_lion_pressure_stage = int(clamp(stage, 0, 4))
	_lion_density_scale = clampf(density_scale, 0.0, 5.0)
	_active_lion_count = max(0, active_lion_count)
	_refresh_lion_pressure_markers()

func get_lion_pressure_stage() -> int:
	return _lion_pressure_stage

func get_lion_density_scale() -> float:
	return _lion_density_scale

func get_settlement_state() -> int:
	return _settlement_state

func get_settlement_state_name() -> String:
	return _state_name(_settlement_state)

func get_settlement_npc_behavior() -> String:
	return _npc_behavior_for_state(_settlement_state)

func get_travel_safety_scale() -> float:
	return _travel_safety_scale

func get_hostile_population() -> int:
	return _hostile_population

func get_pressure_enemy_count() -> int:
	return _pressure_enemy_count

func get_effective_enemy_density() -> int:
	return _hostile_population + _pressure_enemy_count

func get_town_centers() -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for center in _town_centers:
		centers.append(center)
	return centers

func _refresh_lion_pressure_markers() -> void:
	_clear_lion_pressure_markers()
	_recalculate_settlement_pressure()
	if _town_centers.is_empty():
		_pressure_enemy_count = 0
		return

	_pressure_enemy_count = _pressure_enemy_target_count()
	var remaining_pressure_enemies := _pressure_enemy_count
	for i in _town_centers.size():
		var center := _town_centers[i]
		_add_settlement_state_marker(i, center)
		if _lion_pressure_stage > 0:
			_add_lion_pressure_marker(i, center)
		if _settlement_state >= SettlementState.UNEASY:
			_add_warning_signal(i, center)
		if _settlement_state >= SettlementState.ALERT:
			_add_temporary_defenses(i, center)
		_add_npc_posture_markers(i, center)
		if remaining_pressure_enemies > 0:
			var towns_left: int = max(1, _town_centers.size() - i)
			var town_enemy_count := int(ceil(float(remaining_pressure_enemies) / float(towns_left)))
			_add_pressure_enemy_markers(i, center, town_enemy_count)
			remaining_pressure_enemies -= town_enemy_count

func _clear_lion_pressure_markers() -> void:
	for child in get_children():
		if child.is_in_group("settlement_pressure_artifacts") or child.name.begins_with("LionPressureMarker"):
			child.queue_free()

func _recalculate_settlement_pressure() -> void:
	var score := float(_lion_pressure_stage)
	score += clampf(float(_hostile_population) / 7.0, 0.0, 1.25)
	score += clampf((_lion_density_scale - 1.0) * 0.35, 0.0, 0.8)
	score += clampf(float(_active_lion_count) / 18.0, 0.0, 0.9)

	if score >= 4.2:
		_settlement_state = SettlementState.OVERRUN
	elif score >= 2.55:
		_settlement_state = SettlementState.ALERT
	elif score >= 0.85:
		_settlement_state = SettlementState.UNEASY
	else:
		_settlement_state = SettlementState.STABLE

	var base_safety := float(SETTLEMENT_TRAVEL_SAFETY[_settlement_state])
	var density_penalty := clampf((_lion_density_scale - 1.0) * 0.04, 0.0, 0.12)
	var enemy_penalty := clampf((float(_hostile_population) / 90.0) + (float(_active_lion_count) / 180.0), 0.0, 0.15)
	_travel_safety_scale = clampf(base_safety - density_penalty - enemy_penalty, 0.2, 1.0)

func _pressure_enemy_target_count() -> int:
	if _town_centers.is_empty() or _settlement_state < SettlementState.ALERT:
		return 0

	var pressure_bonus: int = max(0, _lion_pressure_stage - 1)
	var density_bonus: int = max(0, int(floor(_lion_density_scale - 1.0)))
	var population_bonus := int(floor(float(_hostile_population) / 5.0))
	if _settlement_state >= SettlementState.OVERRUN:
		return min(10, max(4, pressure_bonus + density_bonus + population_bonus + 2))
	return min(6, max(2, pressure_bonus + density_bonus + population_bonus))

func _state_name(state: int) -> String:
	var index: int = int(clamp(state, 0, SETTLEMENT_STATE_NAMES.size() - 1))
	return String(SETTLEMENT_STATE_NAMES[index])

func _npc_behavior_for_state(state: int) -> String:
	var index: int = int(clamp(state, 0, SETTLEMENT_NPC_BEHAVIORS.size() - 1))
	return String(SETTLEMENT_NPC_BEHAVIORS[index])

func _add_settlement_state_marker(index: int, center: Vector3) -> void:
	var marker_root := Node3D.new()
	marker_root.name = "TownPressureState_%s_%d" % [get_settlement_state_name(), index]
	marker_root.add_to_group("settlement_pressure_artifacts")
	marker_root.set_meta("settlement_state", get_settlement_state_name())
	marker_root.set_meta("npc_behavior", get_settlement_npc_behavior())
	marker_root.set_meta("travel_safety_scale", _travel_safety_scale)
	add_child(marker_root)

	var color := SETTLEMENT_STATE_COLORS[_settlement_state]
	_add_pressure_box(marker_root, Vector3(1.25, 0.08, 1.25), center + Vector3(0.0, 0.10, 0.0), color.darkened(0.35))
	_add_pressure_box(marker_root, Vector3(0.22, 1.35, 0.22), center + Vector3(0.0, 0.78, 0.0), color)
	_add_pressure_box(marker_root, Vector3(1.25, 0.16, 0.12), center + Vector3(0.48, 1.50, 0.0), color.lightened(0.18))

	if _settlement_state == SettlementState.OVERRUN:
		_add_pressure_box(marker_root, Vector3(1.6, 0.12, 1.6), center + Vector3(0.0, 0.18, 0.0), color.lightened(0.12))

func _add_warning_signal(index: int, center: Vector3) -> void:
	var signal_root := Node3D.new()
	signal_root.name = "TownWarningSignal_%s_%d" % [get_settlement_state_name(), index]
	signal_root.add_to_group("settlement_pressure_artifacts")
	signal_root.set_meta("settlement_state", get_settlement_state_name())
	add_child(signal_root)

	var color := SETTLEMENT_STATE_COLORS[_settlement_state]
	var signal_count: int = 2 + min(_settlement_state, 2)
	var radius := 5.2 + float(_settlement_state) * 0.45
	for i in range(signal_count):
		var angle := TAU * float(i) / float(signal_count)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		_add_pressure_box(signal_root, Vector3(0.16, 1.45, 0.16), center + offset + Vector3(0.0, 0.75, 0.0), color)
		_add_pressure_box(signal_root, Vector3(0.78, 0.12, 0.28), center + offset + Vector3(0.28, 1.42, 0.0), color.lightened(0.14))

func _add_temporary_defenses(index: int, center: Vector3) -> void:
	var defense_root := Node3D.new()
	defense_root.name = "TownDefense_%s_%d" % [get_settlement_state_name(), index]
	defense_root.add_to_group("settlement_pressure_artifacts")
	defense_root.set_meta("settlement_state", get_settlement_state_name())
	defense_root.set_meta("travel_safety_scale", _travel_safety_scale)
	add_child(defense_root)

	var color := SETTLEMENT_STATE_COLORS[_settlement_state]
	var defense_count := 4
	if _settlement_state >= SettlementState.OVERRUN:
		defense_count = 6
	var radius := 6.4 + float(_settlement_state) * 0.35
	for i in range(defense_count):
		var angle := TAU * float(i) / float(defense_count)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		_add_pressure_box(defense_root, Vector3(1.45, 0.42, 0.32), center + offset + Vector3(0.0, 0.28, 0.0), color.darkened(0.15))
		if _settlement_state >= SettlementState.OVERRUN and i % 2 == 0:
			_add_pressure_box(defense_root, Vector3(0.28, 0.95, 0.28), center + offset + Vector3(0.34, 0.62, 0.34), color.darkened(0.45))

func _add_npc_posture_markers(index: int, center: Vector3) -> void:
	var npc_root := Node3D.new()
	npc_root.name = "TownNPCPosture_%s_%d" % [get_settlement_npc_behavior(), index]
	npc_root.add_to_group("settlement_pressure_artifacts")
	npc_root.set_meta("npc_behavior", get_settlement_npc_behavior())
	npc_root.set_meta("settlement_state", get_settlement_state_name())
	add_child(npc_root)

	var npc_count := 3
	var radius := 2.4
	var body_height := 0.62
	match _settlement_state:
		SettlementState.UNEASY:
			npc_count = 2
			radius = 1.9
		SettlementState.ALERT:
			npc_count = 4
			radius = 4.8
			body_height = 0.78
		SettlementState.OVERRUN:
			npc_count = 2
			radius = 1.15
			body_height = 0.46

	var color := SETTLEMENT_STATE_COLORS[_settlement_state].lightened(0.22)
	for i in range(npc_count):
		var angle := (TAU * float(i) / float(npc_count)) + 0.35
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		var npc_marker := Node3D.new()
		npc_marker.name = "TownNPC_%s_%d_%d" % [get_settlement_npc_behavior(), index, i]
		npc_marker.add_to_group("settlement_pressure_artifacts")
		npc_marker.set_meta("npc_behavior", get_settlement_npc_behavior())
		npc_marker.set_meta("settlement_state", get_settlement_state_name())
		npc_root.add_child(npc_marker)
		_add_pressure_box(npc_marker, Vector3(0.32, body_height, 0.32), center + offset + Vector3(0.0, body_height * 0.5, 0.0), color)
		_add_pressure_box(npc_marker, Vector3(0.24, 0.20, 0.24), center + offset + Vector3(0.0, body_height + 0.16, 0.0), color.lightened(0.16))

func _add_pressure_enemy_markers(index: int, center: Vector3, count: int) -> void:
	if count <= 0:
		return

	var enemy_root := Node3D.new()
	enemy_root.name = "PressureEnemyCluster_%d_%d" % [_settlement_state, index]
	enemy_root.add_to_group("settlement_pressure_artifacts")
	enemy_root.add_to_group("pressure_enemy_markers")
	enemy_root.set_meta("settlement_state", get_settlement_state_name())
	enemy_root.set_meta("density_contribution", count)
	add_child(enemy_root)

	var color := Color(0.18, 0.03, 0.03)
	if _settlement_state == SettlementState.ALERT:
		color = Color(0.52, 0.08, 0.05)
	var radius := 7.4 + float(_lion_pressure_stage) * 0.55
	for i in range(count):
		var angle := TAU * float(i) / float(max(1, count)) + 0.22
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		var marker := Node3D.new()
		marker.name = "PressureEnemy_%d_%d_%d" % [_settlement_state, index, i]
		marker.add_to_group("settlement_pressure_artifacts")
		marker.add_to_group("pressure_enemy_markers")
		marker.set_meta("travel_safety_scale", _travel_safety_scale)
		enemy_root.add_child(marker)
		_add_pressure_box(marker, Vector3(0.42, 0.82, 0.42), center + offset + Vector3(0.0, 0.46, 0.0), color)
		_add_pressure_box(marker, Vector3(0.72, 0.14, 0.18), center + offset + Vector3(0.0, 0.96, 0.0), color.lightened(0.14))

func _add_lion_pressure_marker(index: int, center: Vector3) -> void:
	var marker_root := Node3D.new()
	marker_root.name = "LionPressureMarker_%d_%d" % [_lion_pressure_stage, index]
	marker_root.add_to_group("lion_pressure_markers")
	add_child(marker_root)

	var color := LION_PRESSURE_COLORS[_lion_pressure_stage]
	var marker_count: int = max(1, min(8, _lion_pressure_stage + int(round(_lion_density_scale))))
	var radius := 4.0 + float(_lion_pressure_stage) * 0.65
	for i in range(marker_count):
		var angle := TAU * float(i) / float(marker_count)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		var height := 0.65 + float(_lion_pressure_stage) * 0.22
		_add_pressure_box(marker_root, Vector3(0.22, height, 0.22), center + offset + Vector3(0.0, height * 0.5, 0.0), color)
		if _lion_pressure_stage >= 3:
			_add_pressure_box(marker_root, Vector3(0.78, 0.08, 0.16), center + offset + Vector3(0.0, height + 0.12, 0.0), color.darkened(0.2))

	if _lion_pressure_stage >= 2:
		_add_pressure_box(marker_root, Vector3(radius * 1.5, 0.06, 0.14), center + Vector3(0.0, 0.08, 0.0), color.darkened(0.35))
		_add_pressure_box(marker_root, Vector3(0.14, 0.06, radius * 1.5), center + Vector3(0.0, 0.09, 0.0), color.darkened(0.35))

	if _lion_pressure_stage >= 4:
		_add_pressure_box(marker_root, Vector3(0.42, 2.4, 0.42), center + Vector3(0.0, 1.2, 0.0), color)

func _add_pressure_box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.35
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = position
	parent.add_child(mesh_instance)

func _resolve_biome() -> int:
	var region_scale: int = 5
	var region_x := floori(float(chunk_coord.x) / float(region_scale))
	var region_y := floori(float(chunk_coord.y) / float(region_scale))
	var region_seed := _seed_from_pair(world_seed, region_x, region_y)
	var roll := region_seed % 100
	if roll < 32:
		return BiomeKind.PLAINS
	if roll < 64:
		return BiomeKind.FOREST
	if roll < 84:
		return BiomeKind.BADLANDS
	return BiomeKind.HILLS

func _active_biome_settings() -> Dictionary:
	return BIOME_LIBRARY.get(_active_biome, BIOME_LIBRARY[BiomeKind.PLAINS])

func _pick_creature_definition(rng: RandomNumberGenerator, is_hostile: bool) -> Dictionary:
	var settings := _active_biome_settings()
	var candidates: Array
	var weights: Array
	if is_hostile:
		candidates = settings["hostile_pool"]
		weights = settings["hostile_weights"]
		return _weighted_pick(rng, HOSTILE_CREATURES, candidates, weights)
	candidates = settings["passive_pool"]
	weights = settings["passive_weights"]
	return _weighted_pick(rng, PASSIVE_CREATURES, candidates, weights)

func _weighted_pick(rng: RandomNumberGenerator, source: Array[Dictionary], candidates: Array, weights: Array) -> Dictionary:
	if candidates.is_empty():
		return source[0]
	var total_weight := 0.0
	for w in weights:
		total_weight += float(w)
	if total_weight <= 0.0:
		return source[candidates[0]]
	var roll := rng.randf() * total_weight
	var accumulator := 0.0
	for i in candidates.size():
		accumulator += float(weights[i])
		if roll <= accumulator:
			return source[int(candidates[i])]
	return source[int(candidates[candidates.size() - 1])]

func _seed_from_pair(seed: int, x: int, y: int) -> int:
	var mixed := (seed * 0x9e3779b9) ^ (x * 0x85ebca6b) ^ (y * 0xc2b2ae35)
	mixed = mixed ^ (mixed << 13)
	mixed = mixed ^ (mixed >> 17)
	mixed = mixed ^ (mixed << 5)
	if mixed < 0:
		mixed = -mixed
	return mixed
