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
const SETTLEMENT_ALERT_OVERRIDE_NONE := -1
const TOWN_LION_PRESSURE_RADIUS := 38.0
const LION_PRESSURE_COLORS: Array[Color] = [
	Color(0.85, 0.86, 0.76),
	Color(0.92, 0.76, 0.35),
	Color(0.95, 0.48, 0.22),
	Color(0.76, 0.12, 0.11),
	Color(0.16, 0.03, 0.04)
]
const SETTLEMENT_STATE_NAMES: Array[String] = [
	"Stable",
	"Uneasy",
	"Alert",
	"Overrun"
]
const SETTLEMENT_WARNING_TEXT: Array[String] = [
	"Stable town: roads clear",
	"Uneasy town: warning signals raised",
	"Alert town: temporary defenses active",
	"Overrun town: travel unsafe"
]
const SETTLEMENT_STATE_COLORS: Array[Color] = [
	Color(0.44, 0.78, 0.56),
	Color(0.94, 0.76, 0.28),
	Color(0.93, 0.28, 0.16),
	Color(0.18, 0.02, 0.03)
]

var _active_biome: int = BiomeKind.PLAINS
var _distance_to_player: int = 0
var _population_scale: float = 1.0
var _lion_pressure_stage: int = 0
var _lion_density_scale: float = 1.0
var _town_centers: Array[Vector3] = []
var _hostile_population: int = 0
var _hostile_cluster_count: int = 0
var _nearby_lion_count: int = 0
var _town_pressure_state: int = SettlementState.STABLE
var _settlement_alert_override: int = SETTLEMENT_ALERT_OVERRIDE_NONE
var _settlement_pressure_score: float = 0.0
var _travel_safety_modifier: float = 1.0
var _defense_level: float = 0.0
var _pressure_enemy_density: int = 0
var _settlement_pressure_multiplier: float = 1.0

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
	_hostile_cluster_count = 0
	_nearby_lion_count = 0
	_settlement_alert_override = SETTLEMENT_ALERT_OVERRIDE_NONE
	_town_pressure_state = SettlementState.STABLE
	_settlement_pressure_score = 0.0
	_travel_safety_modifier = 1.0
	_defense_level = 0.0
	_pressure_enemy_density = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_from_chunk()

	_active_biome = _resolve_biome()

	_add_ground()
	_add_obstacles(rng)
	_add_towns(rng)
	_add_creature_clusters(rng)
	_refresh_lion_pressure_markers()
	_refresh_town_pressure_state()

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
		var member_count: int = max(2, size)
		if is_hostile:
			_hostile_cluster_count += 1
			_hostile_population += member_count
		var center := Vector3(
			rng.randf_range(3.0, chunk_size - 3.0),
			0.0,
			rng.randf_range(3.0, chunk_size - 3.0)
		)
		_spawn_creature_cluster(rng, center, creature, member_count)

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

func set_lion_pressure(stage: int, density_scale: float, active_lion_positions: Array = []) -> void:
	_lion_pressure_stage = int(clamp(stage, 0, 4))
	_lion_density_scale = clampf(density_scale, 0.0, 5.0)
	_nearby_lion_count = _count_nearby_lions(active_lion_positions)
	_settlement_alert_override = SETTLEMENT_ALERT_OVERRIDE_NONE
	_refresh_lion_pressure_markers()
	_refresh_town_pressure_state()

func set_settlement_pressure_multiplier(value: float) -> void:
	_settlement_pressure_multiplier = clampf(value, 0.05, 10.0)
	_refresh_town_pressure_state()

func get_lion_pressure_stage() -> int:
	return _lion_pressure_stage

func get_lion_density_scale() -> float:
	return _lion_density_scale

func get_town_centers() -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for center in _town_centers:
		centers.append(center)
	return centers

func set_settlement_alert_override(state: int) -> void:
	_settlement_alert_override = int(clamp(state, SETTLEMENT_ALERT_OVERRIDE_NONE, SettlementState.OVERRUN))
	_refresh_town_pressure_state()

func get_town_pressure_state() -> int:
	return _town_pressure_state

func get_town_pressure_state_name() -> String:
	return SETTLEMENT_STATE_NAMES[_town_pressure_state]

func get_town_pressure_warning() -> String:
	if _town_centers.is_empty():
		return "No settlement in chunk"
	return SETTLEMENT_WARNING_TEXT[_town_pressure_state]

func get_settlement_pressure_score() -> float:
	return _settlement_pressure_score

func get_nearby_lion_count() -> int:
	return _nearby_lion_count

func get_hostile_population() -> int:
	return _hostile_population

func get_travel_safety_modifier() -> float:
	return _travel_safety_modifier

func get_defense_level() -> float:
	return _defense_level

func get_pressure_enemy_density() -> int:
	return _pressure_enemy_density

func get_settlement_pressure_multiplier() -> float:
	return _settlement_pressure_multiplier

func _count_nearby_lions(active_lion_positions: Array) -> int:
	if _town_centers.is_empty() or active_lion_positions.is_empty():
		return 0

	var count := 0
	for lion_position in active_lion_positions:
		if typeof(lion_position) != TYPE_VECTOR3:
			continue
		var lion_vector: Vector3 = lion_position
		for center in _town_centers:
			if lion_vector.distance_to(to_global(center)) <= TOWN_LION_PRESSURE_RADIUS:
				count += 1
				break
	return count

func _refresh_town_pressure_state() -> void:
	var previous_state := _town_pressure_state
	var previous_pressure_enemy_density := _pressure_enemy_density
	if _town_centers.is_empty():
		_town_pressure_state = SettlementState.STABLE
		_settlement_pressure_score = 0.0
		_travel_safety_modifier = 1.0
		_defense_level = 0.0
		_pressure_enemy_density = 0
		_clear_town_pressure_artifacts()
		return

	_settlement_pressure_score = _calculate_settlement_pressure_score()
	_town_pressure_state = _state_for_pressure_score(_settlement_pressure_score)
	if _settlement_alert_override != SETTLEMENT_ALERT_OVERRIDE_NONE:
		_town_pressure_state = max(_town_pressure_state, _settlement_alert_override)

	_defense_level = _defense_level_for_state(_town_pressure_state)
	_travel_safety_modifier = _travel_safety_for_state(_town_pressure_state, _defense_level)
	_pressure_enemy_density = _pressure_enemy_density_for_state(_town_pressure_state)
	if previous_state != _town_pressure_state \
			or previous_pressure_enemy_density != _pressure_enemy_density \
			or not _has_town_pressure_artifacts():
		_refresh_town_pressure_artifacts()

func _calculate_settlement_pressure_score() -> float:
	var stage_pressure := float(_lion_pressure_stage) * _settlement_pressure_multiplier
	var density_pressure := maxf(_lion_density_scale - 1.0, 0.0) * 0.45 * _settlement_pressure_multiplier
	var enemy_pressure := (float(_hostile_population) * 0.08 + float(_hostile_cluster_count) * 0.22) * maxf(0.5, _settlement_pressure_multiplier)
	var lion_presence_pressure := float(_nearby_lion_count) * 0.90 * _settlement_pressure_multiplier
	return stage_pressure + density_pressure + enemy_pressure + lion_presence_pressure

func _state_for_pressure_score(score: float) -> int:
	if score >= 4.2:
		return SettlementState.OVERRUN
	if score >= 2.6:
		return SettlementState.ALERT
	if score >= 1.2:
		return SettlementState.UNEASY
	return SettlementState.STABLE

func _defense_level_for_state(state: int) -> float:
	match state:
		SettlementState.UNEASY:
			return 0.25
		SettlementState.ALERT:
			return 0.75
		SettlementState.OVERRUN:
			return 0.10
		_:
			return 0.0

func _travel_safety_for_state(state: int, defense_level: float) -> float:
	var base_safety := 1.0
	match state:
		SettlementState.UNEASY:
			base_safety = 0.78
		SettlementState.ALERT:
			base_safety = 0.54
		SettlementState.OVERRUN:
			base_safety = 0.20
	return clampf(base_safety + defense_level * 0.16, 0.0, 1.0)

func _pressure_enemy_density_for_state(state: int) -> int:
	match state:
		SettlementState.ALERT:
			return max(1, int(round(float(max(1, _nearby_lion_count)) * _settlement_pressure_multiplier)))
		SettlementState.OVERRUN:
			return max(3, int(round(float(max(3, _nearby_lion_count + 1)) * _settlement_pressure_multiplier)))
		_:
			return 0

func _has_town_pressure_artifacts() -> bool:
	for child in get_children():
		if child.name.begins_with("TownPressureState"):
			return true
	return false

func _refresh_town_pressure_artifacts() -> void:
	_clear_town_pressure_artifacts()
	for i in _town_centers.size():
		_add_town_pressure_artifacts(i, _town_centers[i])

func _clear_town_pressure_artifacts() -> void:
	for child in get_children():
		if child.name.begins_with("TownPressureState"):
			child.queue_free()

func _add_town_pressure_artifacts(index: int, center: Vector3) -> void:
	var state_name := SETTLEMENT_STATE_NAMES[_town_pressure_state]
	var marker_root := Node3D.new()
	marker_root.name = "TownPressureState_%s_%d" % [state_name, index]
	marker_root.add_to_group("town_pressure_artifacts")
	marker_root.set_meta("settlement_state", state_name)
	marker_root.set_meta("travel_safety_modifier", _travel_safety_modifier)
	marker_root.set_meta("pressure_enemy_density", _pressure_enemy_density)
	add_child(marker_root)

	var color := SETTLEMENT_STATE_COLORS[_town_pressure_state]
	_add_state_beacon(marker_root, center, color)
	match _town_pressure_state:
		SettlementState.STABLE:
			_add_stable_town_behavior(marker_root, center)
		SettlementState.UNEASY:
			_add_uneasy_town_behavior(marker_root, center, color)
		SettlementState.ALERT:
			_add_alert_town_behavior(marker_root, center, color)
		SettlementState.OVERRUN:
			_add_overrun_town_behavior(marker_root, center, color)

func _add_state_beacon(parent: Node3D, center: Vector3, color: Color) -> void:
	var height := 0.9 + float(_town_pressure_state) * 0.35
	var offset := Vector3(-3.9, 0.0, -3.9)
	_add_artifact_box(parent, Vector3(0.28, height, 0.28), center + offset + Vector3(0.0, height * 0.5, 0.0), color, true)
	if _town_pressure_state >= SettlementState.UNEASY:
		_add_artifact_box(parent, Vector3(1.2, 0.12, 0.12), center + offset + Vector3(0.0, height + 0.12, 0.0), color.lightened(0.12), true)

func _add_stable_town_behavior(parent: Node3D, center: Vector3) -> void:
	_add_settlement_npc(parent, "Resident", center + Vector3(-1.7, 0.0, 2.7), Color(0.54, 0.72, 0.62), "trade_idle")
	_add_settlement_npc(parent, "Trader", center + Vector3(1.8, 0.0, 2.3), Color(0.58, 0.66, 0.78), "market_patrol")

func _add_uneasy_town_behavior(parent: Node3D, center: Vector3, color: Color) -> void:
	_add_warning_flags(parent, center, color, 3, 4.2)
	_add_settlement_npc(parent, "Lookout", center + Vector3(-3.0, 0.0, 0.5), color, "watch_perimeter")
	_add_settlement_npc(parent, "ShelteringResident", center + Vector3(1.0, 0.0, 1.2), Color(0.78, 0.68, 0.46), "shelter_near_town")

func _add_alert_town_behavior(parent: Node3D, center: Vector3, color: Color) -> void:
	_add_warning_flags(parent, center, color, 5, 5.0)
	_add_temporary_defenses(parent, center, color)
	for i in range(3):
		var angle := TAU * float(i) / 3.0
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 4.6
		_add_settlement_npc(parent, "Defender", center + offset, Color(0.64, 0.70, 0.74), "defend_perimeter")
	_add_pressure_enemies(parent, center, color)

func _add_overrun_town_behavior(parent: Node3D, center: Vector3, color: Color) -> void:
	_add_warning_flags(parent, center, color, 6, 5.4)
	_add_broken_defenses(parent, center, color)
	_add_artifact_box(parent, Vector3(0.9, 3.4, 0.9), center + Vector3(0.0, 1.7, 0.0), color, true)
	_add_settlement_npc(parent, "Refugee", center + Vector3(-4.8, 0.0, 3.8), Color(0.68, 0.62, 0.55), "evacuate")
	_add_pressure_enemies(parent, center, color)

func _add_warning_flags(parent: Node3D, center: Vector3, color: Color, count: int, radius: float) -> void:
	for i in range(count):
		var angle := TAU * float(i) / float(max(1, count))
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		_add_artifact_box(parent, Vector3(0.14, 1.2, 0.14), center + offset + Vector3(0.0, 0.6, 0.0), color, true)
		_add_artifact_box(parent, Vector3(0.7, 0.08, 0.22), center + offset + Vector3(0.25, 1.18, 0.0), color.lightened(0.1), true)

func _add_temporary_defenses(parent: Node3D, center: Vector3, color: Color) -> void:
	var defense_color := Color(0.42, 0.31, 0.22).lerp(color, 0.25)
	_add_artifact_box(parent, Vector3(3.2, 0.45, 0.35), center + Vector3(0.0, 0.28, -5.0), defense_color, false)
	_add_artifact_box(parent, Vector3(3.2, 0.45, 0.35), center + Vector3(0.0, 0.28, 5.0), defense_color, false)
	_add_artifact_box(parent, Vector3(0.35, 0.45, 3.2), center + Vector3(-5.0, 0.28, 0.0), defense_color, false)
	_add_artifact_box(parent, Vector3(0.35, 0.45, 3.2), center + Vector3(5.0, 0.28, 0.0), defense_color, false)

func _add_broken_defenses(parent: Node3D, center: Vector3, color: Color) -> void:
	var defense_color := Color(0.18, 0.13, 0.11).lerp(color, 0.2)
	_add_artifact_box(parent, Vector3(2.1, 0.32, 0.32), center + Vector3(-1.8, 0.2, -5.0), defense_color, false)
	_add_artifact_box(parent, Vector3(1.4, 0.32, 0.32), center + Vector3(2.6, 0.2, 5.2), defense_color, false)
	_add_artifact_box(parent, Vector3(0.32, 0.32, 2.0), center + Vector3(-5.2, 0.2, 2.0), defense_color, false)

func _add_pressure_enemies(parent: Node3D, center: Vector3, color: Color) -> void:
	for i in range(_pressure_enemy_density):
		var angle := TAU * float(i) / float(max(1, _pressure_enemy_density)) + 0.35
		var radius := 6.2 + float(i % 2)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		_add_settlement_npc(parent, "PressureEnemy", center + offset, color.darkened(0.35), "pressure_hunt")

func _add_settlement_npc(parent: Node3D, role: String, position: Vector3, color: Color, behavior: String) -> void:
	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 0.95
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	capsule.material = material
	mesh_instance.mesh = capsule
	mesh_instance.position = position + Vector3(0.0, 0.5, 0.0)
	mesh_instance.name = "TownNPC_%s_%s" % [role, behavior]
	mesh_instance.add_to_group("settlement_npcs")
	mesh_instance.set_meta("settlement_state", SETTLEMENT_STATE_NAMES[_town_pressure_state])
	mesh_instance.set_meta("settlement_behavior", behavior)
	if behavior == "defend_perimeter":
		mesh_instance.add_to_group("town_defenders")
	if behavior == "pressure_hunt":
		mesh_instance.add_to_group("town_pressure_enemies")
	parent.add_child(mesh_instance)

func _add_artifact_box(parent: Node3D, size: Vector3, position: Vector3, color: Color, emissive: bool) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.25
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = position
	parent.add_child(mesh_instance)

func _refresh_lion_pressure_markers() -> void:
	_clear_lion_pressure_markers()
	if _lion_pressure_stage <= 0:
		return

	for i in _town_centers.size():
		_add_lion_pressure_marker(i, _town_centers[i])

func _clear_lion_pressure_markers() -> void:
	for child in get_children():
		if child.name.begins_with("LionPressureMarker"):
			child.queue_free()

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
