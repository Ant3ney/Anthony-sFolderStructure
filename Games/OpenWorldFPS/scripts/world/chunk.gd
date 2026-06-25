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

var _active_biome: int = BiomeKind.PLAINS
var _distance_to_player: int = 0
var _population_scale: float = 1.0

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

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_from_chunk()

	_active_biome = _resolve_biome()

	_add_ground()
	_add_obstacles(rng)
	_add_towns(rng)
	_add_creature_clusters(rng)

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
