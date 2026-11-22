extends DirectionalLight3D

@export var world_env: WorldEnvironment
@export var day_length_seconds: float =  1800.0
# 0.0 = meia-noite, 0.25 = nascer do sol, 0.5 = meio-dia, 0.75 = pôr do sol
@export_range(0.0, 1.0) var time_of_day: float = 0.35
@export var auto_advance: bool = true
@export var day_energy: float = 1.2

var day_top := Color(0.30, 0.50, 0.85)
var day_horizon := Color(0.75, 0.85, 0.95)
var sunset_horizon := Color(0.95, 0.55, 0.35)
var night_top := Color(0.01, 0.02, 0.06)
var night_horizon := Color(0.04, 0.06, 0.12)


func _ready() -> void:
	_update_time()


func _process(delta: float) -> void:
	if auto_advance:
		time_of_day = fmod(time_of_day + delta / day_length_seconds, 1.0)
	_update_time()


func _update_time() -> void:
	# Gira o sol no céu
	var angle := deg_to_rad(90.0 - time_of_day * 360.0)
	transform.basis = Basis(Vector3.UP, deg_to_rad(-30.0)) * Basis(Vector3.RIGHT, angle)

	# elevation: 1 = sol a pino, 0 = no horizonte, -1 = meia-noite
	var elevation := -cos(time_of_day * TAU)
	var daylight := smoothstep(-0.05, 0.3, elevation)
	var sunset := clampf(1.0 - absf(elevation) / 0.3, 0.0, 1.0)

	light_energy = lerpf(0.0, day_energy, daylight)
	light_color = Color(1.0, 0.6, 0.4).lerp(Color(1.0, 0.97, 0.9), smoothstep(0.0, 0.4, elevation))
	shadow_enabled = elevation > 0.0

	if world_env == null or world_env.environment == null:
		return
	var env := world_env.environment
	var top := night_top.lerp(day_top, daylight)
	var horizon := night_horizon.lerp(day_horizon, daylight).lerp(sunset_horizon, sunset * 0.7)

	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var sky := env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = top
		sky.sky_horizon_color = horizon
		sky.ground_horizon_color = horizon
		sky.ground_bottom_color = horizon.darkened(0.5)

	env.fog_light_color = horizon
	env.ambient_light_energy = lerpf(0.25, 1.0, daylight)
