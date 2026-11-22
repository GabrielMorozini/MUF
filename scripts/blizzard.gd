extends Node3D

@export var player: Node3D
@export var world_env: WorldEnvironment

@export_group("Neve")
@export var particle_amount: int = 2000
@export var area_size: float = 40.0
@export var fall_speed: float = 4.0

@export_group("Vento")
@export var wind_direction := Vector3(1.0, 0.0, 0.3)
@export var wind_speed: float = 8.0

@export_group("Neblina")
@export var calm_fog: float = 0.02     # valor mínimo: ver observação sobre alcance
@export var storm_fog: float = 0.04
@export var gust_speed: float = 0.15   # com que frequência as rajadas mudam

@export_group("Interior")
@export var indoor_fog: float = 0.02	     # neblina dentro de prédios
@export var indoor_fade_speed: float = 2.0   # velocidade da transição
@export var head_height: float = 1.6         # de onde sai o raio (altura da câmera)
@export var roof_check_height: float = 8.0   # teto até essa distância = ambiente coberto

const SNOW_LIFETIME := 3.0

var snow: GPUParticles3D
var pmat: ParticleProcessMaterial
var gust_noise := FastNoiseLite.new()
var t := 0.0

var is_indoor: bool = false
var roof_overhead: bool = false
var indoor_blend: float = 0.0   # 0 = fora, 1 = dentro (suaviza a neblina)


func _ready() -> void:
	if player == null:
		player = get_node_or_null("../Player")
	if world_env == null:
		world_env = get_node_or_null("../WorldEnvironment")

	gust_noise.seed = randi()
	gust_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	gust_noise.frequency = 1.0

	if world_env and world_env.environment:
		world_env.environment.fog_enabled = true
		world_env.environment.fog_sky_affect = 1.0

	_create_snow()
	print("[Blizzard] jogador encontrado: ", player != null)


func _create_snow() -> void:
	pmat = ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(area_size * 0.5, 4.0, area_size * 0.5)
	pmat.gravity = Vector3.ZERO
	pmat.spread = 12.0
	pmat.turbulence_enabled = true
	pmat.turbulence_noise_strength = 1.5
	pmat.turbulence_noise_scale = 4.0

	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat

	snow = GPUParticles3D.new()
	snow.amount = particle_amount
	snow.lifetime = SNOW_LIFETIME
	snow.preprocess = SNOW_LIFETIME           # a neve já começa caindo
	snow.local_coords = false                 # partículas ficam no mundo, não "grudam" no jogador
	snow.process_material = pmat
	snow.draw_pass_1 = quad
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	snow.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 80, 120))
	snow.top_level = true
	add_child(snow)

	_apply_wind(0.5)


func _apply_wind(intensity: float) -> void:
	var dir := Vector3(wind_direction.x, 0.0, wind_direction.z).normalized()
	var gust := 0.6 + 0.8 * intensity
	var v := Vector3(dir.x * wind_speed * gust, -fall_speed, dir.z * wind_speed * gust)
	pmat.direction = v.normalized()
	pmat.initial_velocity_min = v.length() * 0.8
	pmat.initial_velocity_max = v.length() * 1.2


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	# Raio para cima a partir da cabeça: se bater em algo, tem teto por cima
	var from := player.global_position + Vector3(0.0, head_height, 0.0)
	var to := from + Vector3.UP * roof_check_height
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if player is CollisionObject3D:
		query.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	roof_overhead = not hit.is_empty()


func _process(delta: float) -> void:
	if player == null:
		return
	t += delta

	# Mudou de fora para dentro (ou o contrário)?
	if roof_overhead != is_indoor:
		is_indoor = roof_overhead
		snow.visible = not is_indoor
		if not is_indoor:
			snow.restart()
		print("[Blizzard] ambiente coberto: ", is_indoor)   # pode apagar depois dos testes

	# 0 = calmo, 1 = rajada forte
	var intensity := clampf(gust_noise.get_noise_1d(t * gust_speed) * 0.5 + 0.5, 0.0, 1.0)

	# Emissor acompanha o jogador, deslocado contra o vento para a neve cobrir a área toda
	var dir := Vector3(wind_direction.x, 0.0, wind_direction.z).normalized()
	var upwind := -dir * wind_speed * SNOW_LIFETIME * 0.5
	snow.global_position = player.global_position + Vector3(0.0, 5.0, 0.0) + upwind

	_apply_wind(intensity)

	# Transição suave entre fora (nevasca) e dentro (ar limpo)
	var target := 1.0 if is_indoor else 0.0
	indoor_blend = move_toward(indoor_blend, target, indoor_fade_speed * delta)

	if world_env and world_env.environment:
		var outdoor_fog := lerpf(calm_fog, storm_fog, intensity)
		world_env.environment.fog_density = lerpf(outdoor_fog, indoor_fog, indoor_blend)
