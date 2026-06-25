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

enum TownPressureState {
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
const TOWN_PRESSURE_STATE_NAMES := ["Stable", "Uneasy", "Alert", "Overrun"]
const TOWN_NPC_BEHAVIOR_BY_STATE := ["routine", "lookout", "defend", "evacuate"]
const TOWN_TRAVEL_SAFETY_BASE := [1.0, 0.78, 0.48, 0.16]
const TOWN_PRESSURE_COLORS: Array[Color] = [
	Color(0.47, 0.67, 0.50),
	Color(0.94, 0.75, 0.30),
	Color(0.95, 0.38, 0.18),
	Color(0.42, 0.05, 0.06)
]
const LION_PRESSURE_COLORS: Array[Color] = [
	Color(0.85, 0.86, 0.76),
	Color(0.92, 0.76, 0.35),
	Color(0.95, 0.48, 0.22),
	Color(0.76, 0.12, 0.11),
	Color(0.16, 0.03, 0.04)
]

var _active_biome: int = BiomeKind.PLAINS
var _distance_to_player: int = 0
var _population_scale: float = 1.0
var _lion_pressure_stage: int = 0
var _lion_density_scale: float = 1.0
var _town_centers: Array[Vector3] = []
var _town_pressure_states: Array[int] = []
var _town_travel_safety: Array[float] = []
var _local_enemy_population: int = 0
var _pressure_enemy_count: int = 0

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
	_town_pressure_states.clear()
	_town_travel_safety.clear()
	_local_enemy_population = 0
	_pressure_enemy_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_from_chunk()

	_active_biome = _resolve_biome()

	_add_ground()
	_add_obstacles(rng)
	_add_towns(rng)
	_add_creature_clusters(rng)
	_refresh_pressure_response()

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
		_town_pressure_states.append(TownPressureState.STABLE)
		_town_travel_safety.append(1.0)
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
		var spawned_size: int = max(2, size)
		if is_hostile:
			_local_enemy_population += spawned_size
		var center := Vector3(
			rng.randf_range(3.0, chunk_size - 3.0),
			0.0,
			rng.randf_range(3.0, chunk_size - 3.0)
		)
		_spawn_creature_cluster(rng, center, creature, spawned_size)

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

func set_lion_pressure(stage: int, density_scale: float) -> void:
	_lion_pressure_stage = int(clamp(stage, 0, 4))
	_lion_density_scale = clampf(density_scale, 0.0, 5.0)
	_refresh_pressure_response()

func get_lion_pressure_stage() -> int:
	return _lion_pressure_stage

func get_lion_density_scale() -> float:
	return _lion_density_scale

func get_town_centers() -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for center in _town_centers:
		centers.append(center)
	return centers

func set_enemy_population_pressure(enemy_count: int) -> void:
	_local_enemy_population = max(0, enemy_count)
	_refresh_pressure_response()

func get_local_enemy_population() -> int:
	return _local_enemy_population

func get_town_pressure_states() -> Array[int]:
	var states: Array[int] = []
	for state in _town_pressure_states:
		states.append(state)
	return states

func get_max_town_pressure_state() -> int:
	var max_state := TownPressureState.STABLE
	for state in _town_pressure_states:
		max_state = max(max_state, state)
	return max_state

func get_town_pressure_state_name(state: int = -1) -> String:
	var state_index := get_max_town_pressure_state() if state < 0 else state
	state_index = int(clamp(state_index, 0, TOWN_PRESSURE_STATE_NAMES.size() - 1))
	return TOWN_PRESSURE_STATE_NAMES[state_index]

func get_average_travel_safety() -> float:
	if _town_travel_safety.is_empty():
		return 1.0

	var total := 0.0
	for safety in _town_travel_safety:
		total += safety
	return clampf(total / float(_town_travel_safety.size()), 0.0, 1.0)

func get_pressure_enemy_count() -> int:
	return _pressure_enemy_count

func get_town_pressure_count() -> int:
	return _town_centers.size()

func _refresh_pressure_response() -> void:
	_refresh_lion_pressure_markers()
	_refresh_town_pressure_response()

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

func _refresh_town_pressure_response() -> void:
	_clear_town_pressure_response()
	_pressure_enemy_count = 0
	if _town_centers.is_empty():
		_town_pressure_states.clear()
		_town_travel_safety.clear()
		return

	_ensure_town_state_storage()
	for i in _town_centers.size():
		var state := _resolve_town_pressure_state()
		_town_pressure_states[i] = state
		_town_travel_safety[i] = _travel_safety_for_state(state)
		_add_town_pressure_response(i, _town_centers[i], state)

func _ensure_town_state_storage() -> void:
	while _town_pressure_states.size() < _town_centers.size():
		_town_pressure_states.append(TownPressureState.STABLE)
	while _town_travel_safety.size() < _town_centers.size():
		_town_travel_safety.append(1.0)
	while _town_pressure_states.size() > _town_centers.size():
		_town_pressure_states.pop_back()
	while _town_travel_safety.size() > _town_centers.size():
		_town_travel_safety.pop_back()

func _clear_town_pressure_response() -> void:
	var response_nodes: Array[Node] = []
	for child in get_children():
		if child.name.begins_with("TownPressureResponse"):
			response_nodes.append(child)

	for node in response_nodes:
		remove_child(node)
		node.free()

func _resolve_town_pressure_state() -> int:
	var town_count: int = max(_town_centers.size(), 1)
	var hostile_component := minf(float(_local_enemy_population) / maxf(float(town_count * 2), 1.0), 3.0)
	var density_component := maxf(_lion_density_scale - 1.0, 0.0) * 0.35
	var pressure_score := float(_lion_pressure_stage) + density_component + hostile_component

	if _lion_pressure_stage >= 4 or pressure_score >= 4.2:
		return TownPressureState.OVERRUN
	if _lion_pressure_stage >= 3 or pressure_score >= 2.7:
		return TownPressureState.ALERT
	if _lion_pressure_stage >= 1 or pressure_score >= 1.1:
		return TownPressureState.UNEASY
	return TownPressureState.STABLE

func _travel_safety_for_state(state: int) -> float:
	var state_index := int(clamp(state, 0, TOWN_TRAVEL_SAFETY_BASE.size() - 1))
	var base := float(TOWN_TRAVEL_SAFETY_BASE[state_index])
	var hostile_drag := minf(float(_local_enemy_population) * 0.015, 0.18)
	var pressure_drag := maxf(_lion_density_scale - 1.0, 0.0) * 0.04
	var defense_bonus := 0.0
	match state_index:
		TownPressureState.UNEASY:
			defense_bonus = 0.05
		TownPressureState.ALERT:
			defense_bonus = 0.12
		TownPressureState.OVERRUN:
			defense_bonus = -0.05
	return clampf(base + defense_bonus - hostile_drag - pressure_drag, 0.05, 1.0)

func _add_town_pressure_response(index: int, center: Vector3, state: int) -> void:
	var response_root := Node3D.new()
	response_root.name = "TownPressureResponse_%s_%d" % [TOWN_PRESSURE_STATE_NAMES[state], index]
	response_root.set_meta("town_state", TOWN_PRESSURE_STATE_NAMES[state])
	response_root.set_meta("travel_safety", _town_travel_safety[index])
	response_root.add_to_group("town_pressure_responses")
	add_child(response_root)

	_add_town_npc_response(response_root, center, state)
	if state >= TownPressureState.UNEASY:
		_add_warning_signal(response_root, center, state)
	if state >= TownPressureState.ALERT:
		_add_temporary_defenses(response_root, center, state)
	if state == TownPressureState.OVERRUN:
		_add_overrun_artifacts(response_root, center)
	_add_pressure_enemies(response_root, center, state)

func _add_town_npc_response(parent: Node3D, center: Vector3, state: int) -> void:
	var npc_count := 2
	if state == TownPressureState.ALERT:
		npc_count = 3
	elif state == TownPressureState.OVERRUN:
		npc_count = 2

	var behavior := String(TOWN_NPC_BEHAVIOR_BY_STATE[state])
	var radius := 2.2 + float(state) * 0.75
	for i in range(npc_count):
		var angle := TAU * float(i) / float(max(npc_count, 1)) + float(state) * 0.35
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		var npc := MeshInstance3D.new()
		npc.name = "TownNPC_%s_%d" % [behavior, i]
		npc.mesh = _shape_mesh("capsule", 0.34)
		npc.position = center + offset + Vector3(0.0, 0.42, 0.0)
		npc.set_meta("behavior_state", behavior)
		npc.add_to_group("town_npcs")

		var material := StandardMaterial3D.new()
		material.albedo_color = TOWN_PRESSURE_COLORS[state].lightened(0.18)
		npc.mesh.material = material
		parent.add_child(npc)

func _add_warning_signal(parent: Node3D, center: Vector3, state: int) -> void:
	var color := TOWN_PRESSURE_COLORS[state]
	var height := 1.6 + float(state) * 0.35
	var signal_position := center + Vector3(0.0, height * 0.5, -3.4 - float(state) * 0.35)
	_add_response_box(parent, Vector3(0.18, height, 0.18), signal_position, color.darkened(0.3), "TownWarningSignalPost", "town_warning_signals")
	_add_response_box(parent, Vector3(0.72, 0.22, 0.72), signal_position + Vector3(0.0, height * 0.5 + 0.22, 0.0), color, "TownWarningSignalBeacon", "town_warning_signals", true)

func _add_temporary_defenses(parent: Node3D, center: Vector3, state: int) -> void:
	var defense_count := 4 if state == TownPressureState.ALERT else 3
	var radius := 5.0 + float(state) * 0.55
	for i in range(defense_count):
		var angle := TAU * float(i) / float(defense_count)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		var barricade_color := Color(0.50, 0.37, 0.24)
		if state == TownPressureState.OVERRUN:
			barricade_color = Color(0.24, 0.17, 0.16)
		var barricade := _add_response_box(parent, Vector3(1.8, 0.42, 0.34), center + offset + Vector3(0.0, 0.24, 0.0), barricade_color, "TownTemporaryDefense", "town_defenses")
		barricade.rotation.y = -angle
		barricade.set_meta("defense_state", "holding" if state == TownPressureState.ALERT else "broken")

func _add_overrun_artifacts(parent: Node3D, center: Vector3) -> void:
	_add_response_box(parent, Vector3(0.36, 2.2, 0.36), center + Vector3(1.8, 1.1, 1.8), Color(0.08, 0.06, 0.06), "TownOverrunSmoke", "town_overrun_markers", true)
	_add_response_box(parent, Vector3(2.4, 0.08, 0.18), center + Vector3(-1.6, 0.11, -1.4), Color(0.38, 0.05, 0.05), "TownOverrunWarningTrail", "town_overrun_markers", true)

func _add_pressure_enemies(parent: Node3D, center: Vector3, state: int) -> void:
	var count := _pressure_enemy_count_for_state(state)
	if count <= 0:
		return

	_pressure_enemy_count += count
	var radius := 6.0 + float(state) * 0.7
	for i in range(count):
		var angle := TAU * float(i) / float(count) + 0.22
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		var enemy := MeshInstance3D.new()
		enemy.name = "TownPressureEnemy_%s_%d" % [TOWN_PRESSURE_STATE_NAMES[state], i]
		enemy.mesh = _shape_mesh("capsule", 0.46)
		enemy.position = center + offset + Vector3(0.0, 0.54, 0.0)
		enemy.set_meta("source", "town_pressure")
		enemy.set_meta("town_state", TOWN_PRESSURE_STATE_NAMES[state])
		enemy.add_to_group("pressure_enemies")

		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.32, 0.04, 0.05).lerp(TOWN_PRESSURE_COLORS[state], 0.25)
		enemy.mesh.material = material
		parent.add_child(enemy)

func _pressure_enemy_count_for_state(state: int) -> int:
	match state:
		TownPressureState.UNEASY:
			if _lion_pressure_stage >= 2 or _local_enemy_population >= 3:
				return 1
		TownPressureState.ALERT:
			return 2 + min(_lion_pressure_stage, 3)
		TownPressureState.OVERRUN:
			return 5 + min(_lion_pressure_stage, 4) + int(floor(maxf(_lion_density_scale - 1.0, 0.0)))
	return 0

func _add_response_box(parent: Node3D, size: Vector3, position: Vector3, color: Color, node_name: String, group_name: String = "", emissive: bool = false) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.45
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = position
	if group_name != "":
		mesh_instance.add_to_group(group_name)
	parent.add_child(mesh_instance)
	return mesh_instance

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
