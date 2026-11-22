extends Node3D

@export var player: Node3D
@export var noise_seed: int = 1337

@export_group("Chunks")
@export var chunk_size: float = 64.0
@export var chunk_resolution: int = 32      # 32 em 64 m = um ponto a cada 2 m
@export var view_radius: int = 3            # chunks carregados em cada direção
@export var chunks_per_frame: int = 1       # sobe se notar chunks demorando a aparecer

@export_group("Planície")
@export var plain_height: float = 2.5
@export var detail_height: float = 0.3

@export_group("Colinas isoladas")
@export var hill_height: float = 14.0
@export_range(0.0, 0.6) var hill_threshold: float = 0.3

@export_group("Montanhas distantes")
@export var mountain_height: float = 90.0
@export var mountain_start_distance: float = 500.0   # só aparecem longe da base
@export var mountain_ramp: float = 400.0

@export_group("Clareira da base")
@export var flat_radius: float = 200
@export var flat_blend: float = 100

@export_group("Cores")
@export var snow_color := Color(0.92, 0.95, 1.0)
@export var rock_color := Color(0.28, 0.30, 0.34)

var plain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var hill_noise := FastNoiseLite.new()
var mountain_noise := FastNoiseLite.new()

var material: StandardMaterial3D
var chunks: Dictionary = {}          # Vector2i -> Node3D
var queue: Array[Vector2i] = []
var current_chunk := Vector2i(999999, 999999)


func _ready() -> void:
	plain_noise.seed = noise_seed
	plain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	plain_noise.frequency = 0.004
	plain_noise.fractal_octaves = 3

	detail_noise.seed = noise_seed + 1
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.04
	detail_noise.fractal_octaves = 2

	hill_noise.seed = noise_seed + 2
	hill_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	hill_noise.frequency = 0.006

	mountain_noise.seed = noise_seed + 3
	mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mountain_noise.frequency = 0.01
	mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	mountain_noise.fractal_octaves = 4

	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0

	if player == null:
		player = get_node_or_null("../Player")

	# Carrega os chunks mais próximos de uma vez (para ter chão antes do jogador cair)
	_update_current_chunk()
	for i in mini(9, queue.size()):
		_build_chunk(queue.pop_front())


func _process(_delta: float) -> void:
	_update_current_chunk()
	for i in chunks_per_frame:
		if queue.is_empty():
			break
		_build_chunk(queue.pop_front())


func _update_current_chunk() -> void:
	if player == null:
		return
	var p := player.global_position
	var c := Vector2i(roundi(p.x / chunk_size), roundi(p.z / chunk_size))
	if c == current_chunk:
		return
	current_chunk = c
	_refresh_chunks()


func _refresh_chunks() -> void:
	# Descarrega os chunks que ficaram longe
	var limit := (view_radius + 1) * (view_radius + 1)
	for coord in chunks.keys():
		var d: Vector2i = coord - current_chunk
		if d.x * d.x + d.y * d.y > limit:
			chunks[coord].queue_free()
			chunks.erase(coord)

	# Enfileira os que faltam, do mais perto para o mais longe
	queue.clear()
	var r2 := view_radius * view_radius
	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			if dx * dx + dz * dz > r2:
				continue
			var coord := current_chunk + Vector2i(dx, dz)
			if not chunks.has(coord):
				queue.append(coord)
	queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - current_chunk).length_squared() < (b - current_chunk).length_squared())


func get_height(x: float, z: float) -> float:
	# Planície suave + detalhe fino
	var h := plain_noise.get_noise_2d(x, z) * plain_height
	h += detail_noise.get_noise_2d(x, z) * detail_height

	# Colinas isoladas
	var hill := smoothstep(hill_threshold, hill_threshold + 0.3, hill_noise.get_noise_2d(x, z))
	h += hill * hill_height

	# Montanhas só muito longe da base
	var dist := Vector2(x, z).length()
	var m := smoothstep(mountain_start_distance, mountain_start_distance + mountain_ramp, dist)
	var ridge := mountain_noise.get_noise_2d(x, z) * 0.5 + 0.5
	h += m * m * mountain_height * (0.4 + 0.6 * ridge)

	# Clareira plana no centro
	h *= smoothstep(flat_radius, flat_radius + flat_blend, dist)
	return h


func _build_chunk(coord: Vector2i) -> void:
	if chunks.has(coord):
		return

	var res := chunk_resolution
	var n := res + 1
	var step := chunk_size / res
	var half := chunk_size / 2.0
	var origin := Vector3(coord.x * chunk_size, 0.0, coord.y * chunk_size)

	# Alturas com 1 ponto extra em cada lado, para as normais não terem costura entre chunks
	var m := n + 2
	var grid := PackedFloat32Array()
	grid.resize(m * m)
	for zi in m:
		for xi in m:
			var wx := origin.x + (xi - 1) * step - half
			var wz := origin.z + (zi - 1) * step - half
			grid[zi * m + xi] = get_height(wx, wz)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var heights := PackedFloat32Array()
	vertices.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	uvs.resize(n * n)
	heights.resize(n * n)

	for zi in n:
		for xi in n:
			var i := zi * n + xi
			var h := grid[(zi + 1) * m + (xi + 1)]
			var h_left := grid[(zi + 1) * m + xi]
			var h_right := grid[(zi + 1) * m + (xi + 2)]
			var h_up := grid[zi * m + (xi + 1)]
			var h_down := grid[(zi + 2) * m + (xi + 1)]
			var normal := Vector3(h_left - h_right, 2.0 * step, h_up - h_down).normalized()

			heights[i] = h
			vertices[i] = Vector3(xi * step - half, h, zi * step - half)
			normals[i] = normal
			var rock := smoothstep(0.12, 0.45, 1.0 - normal.y)
			colors[i] = snow_color.lerp(rock_color, rock)
			uvs[i] = Vector2(float(xi) / res, float(zi) / res)

	# Triângulos (sentido horário visto de cima)
	var indices := PackedInt32Array()
	indices.resize(res * res * 6)
	var k := 0
	for zi in res:
		for xi in res:
			var a := zi * n + xi
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = d
			indices[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var chunk := MeshInstance3D.new()
	chunk.mesh = arr_mesh
	chunk.material_override = material
	chunk.position = origin

	# Colisão leve
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights

	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(step, 1.0, step)

	var body := StaticBody3D.new()
	body.add_child(col)
	chunk.add_child(body)

	add_child(chunk)
	chunks[coord] = chunk
