extends Node3D

@export var player: Jogador
@export var bus: Onibus

@export_group("Trajeto")
@export var start_z: float = 185.0    # onde o ônibus começa (a estrada vem do lado +Z)
@export var stop_z: float = 22.0      # onde ele para, em frente à base
@export var ride_seconds: float = 30.0

@export_group("Testes")
@export var skip_intro: bool = false  # marque para começar já fora do ônibus

const SEATED_CAMERA_Y := 1.15

var camera: Camera3D
var fade: ColorRect
var shake_noise := FastNoiseLite.new()
var riding := false
var t := 0.0


func _ready() -> void:
	if player == null:
		player = get_node_or_null("../Player")
	if bus == null:
		bus = get_node_or_null("../Onibus")
	if player == null or bus == null:
		push_error("[Intro] Não achei o Player ou o Onibus. Arraste-os para os campos no Inspetor.")
		return

	camera = player.get_node("Camera3D")
	shake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	shake_noise.frequency = 1.0

	_make_fade()
	_make_road()

	if skip_intro:
		fade.color.a = 0.0
		bus.position = Vector3(0.0, 0.0, stop_z)
		return

	bus.position = Vector3(0.0, 0.0, start_z)
	_play_intro()


func _process(delta: float) -> void:
	if not riding:
		return
	# Tremor leve da câmera enquanto o ônibus anda
	t += delta
	camera.h_offset = shake_noise.get_noise_2d(t * 14.0, 0.0) * 0.012
	camera.v_offset = shake_noise.get_noise_2d(0.0, t * 14.0 + 50.0) * 0.012


func _play_intro() -> void:
	await get_tree().process_frame   # espera o ônibus terminar de se montar

	var stand_y := camera.position.y
	var corpo := player.get_node_or_null("Corpo") as Node3D

	# 1) Coloca o jogador sentado dentro do ônibus
	player.reparent(bus, false)
	player.position = Onibus.SEAT_POS
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.position.y = SEATED_CAMERA_Y
	if corpo:
		corpo.visible = false
	player.set_frozen(true)
	riding = true

	# 2) Tela preta -> imagem
	var fade_in := create_tween()
	fade_in.tween_property(fade, "color:a", 0.0, 3.0)

	# 3) Viagem: acelera, anda e freia suavemente
	var drive := create_tween()
	drive.tween_property(bus, "position:z", stop_z, ride_seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await drive.finished
	riding = false
	camera.h_offset = 0.0
	camera.v_offset = 0.0

	# 4) Chegada: porta abre
	await get_tree().create_timer(1.0).timeout
	bus.open_door()
	await get_tree().create_timer(1.5).timeout

	# 5) Jogador levanta e vai para o corredor
	var stand := create_tween().set_parallel(true)
	stand.tween_property(camera, "position:y", stand_y, 1.2)
	stand.tween_property(player, "position", Onibus.AISLE_POS, 1.2)
	await stand.finished

	# 6) Devolve o controle
	if corpo:
		corpo.visible = true
	player.reparent(get_tree().current_scene, true)
	player.set_frozen(false)


func _make_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color(0.0, 0.0, 0.0, 1.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)


func _make_road() -> void:
	var z_near := stop_z - 8.0
	var z_far := start_z + 5.0

	# Faixa escura da estrada
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.32, 0.33, 0.37)
	road_mat.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.0, z_far - z_near)
	var road := MeshInstance3D.new()
	road.mesh = plane
	road.material_override = road_mat
	road.position = Vector3(0.0, 0.03, (z_near + z_far) / 2.0)
	add_child(road)

	# Postes de sinalização (típicos das estradas no inverno norueguês)
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.04
	post_mesh.bottom_radius = 0.04
	post_mesh.height = 2.2
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(1.0, 0.45, 0.05)
	post_mat.emission_enabled = true
	post_mat.emission = Color(1.0, 0.35, 0.0)
	post_mat.emission_energy_multiplier = 0.8

	var z := z_near
	while z < z_far:
		for x in [-4.5, 4.5]:
			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.material_override = post_mat
			post.position = Vector3(x, 1.1, z)
			add_child(post)
		z += 18.0
