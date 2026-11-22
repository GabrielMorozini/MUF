class_name Onibus
extends Node3D

## Emitido quando o ônibus para e os passageiros começam a descer.
signal stopped

# Origem do ônibus = chão, no centro. Frente = -Z. Porta = lado direito (+X).
const SEAT_POS := Vector3(-0.8, 0.5, 0.6)   # onde o jogador senta
const AISLE_POS := Vector3(0.0, 0.5, 0.6)   # corredor, para onde ele vai ao levantar
const SUB := CSGShape3D.OPERATION_SUBTRACTION

# Posições dos bancos de passageiros
const ROW_Z := [-1.2, 0.6, 2.4]
const COL_X := [-0.8, 0.8]
const DRIVER_POS := Vector3(-0.8, 0.0, -3.6)

# Desembarque (coordenadas locais do ônibus)
const PORTA_POS := Vector3(1.1, 0.0, -3.2)  # centro do vão da porta (usa X e Z)
const SAIDA_X := 3.2                        # até onde o passageiro anda lá fora
const ANIM_ANDAR := &"andar"
const ANIM_LEVANTAR := &"levantar"
const ANIM_SENTADO := &"sentado"

@export_group("Passageiros")
## Arraste aqui os modelos dos personagens (.fbx / .glb / .tscn) vindos dos packs.
@export var modelos: Array[PackedScene] = []
## Chance de cada banco estar ocupado (0 a 1).
@export_range(0.0, 1.0) var chance_ocupado: float = 0.65
## Altura final dos personagens, em metros. O código mede o modelo e ajusta sozinho.
## Use 0 para desligar o ajuste automático e usar só a Escala Modelo.
@export var altura_alvo: float = 1.75
## Multiplicador extra em cima da Altura Alvo (1.0 = nenhum).
@export var escala_modelo: float = 1.0
## Rotação extra, em graus, somada à orientação automática (0 = olhando para a frente).
@export var rotacao_modelo: float = 0.0
## Altura (Y) do chão do ônibus. Com a pose sentada, deixe em 0.5.
@export var altura_assento: float = 0.5
## Nome da animação de sentado, se um modelo tiver uma (tem prioridade sobre a pose por ossos).
@export var animacao_sentado: StringName = &"sit"
## 0 = sorteio diferente a cada partida. Outro número = sempre a mesma disposição.
@export var semente: int = 0
## Arraste aqui um FBX com a animação de sentado (ex.: "Sitting Idle" do Mixamo).
## Se estiver preenchido, ele tem prioridade sobre a pose feita pelos ossos.
@export var cena_sentado: PackedScene
## Ajuste fino da posição do passageiro com a animação sentada (X, Y, Z em metros).
## Use se ele ficar afundado no banco, flutuando ou longe do encosto.
@export var offset_sentado: Vector3 = Vector3.ZERO

@export_subgroup("Pose sentada")
## Liga a pose sentada feita pelos ossos (modelos Mixamo).
@export var sentar_passageiros: bool = true
## Quanto as coxas sobem (90 = coxa na horizontal).
@export_range(0.0, 120.0) var angulo_coxa: float = 90.0
## Move o passageiro para trás (encosto). Aumente se ele estiver longe do encosto.
@export var recuo_assento: float = 0.05
## Coloca as mãos no colo.
@export var bracos_no_colo: bool = true
## Ângulo do braço (ombro) para a frente, em graus.
@export_range(0.0, 60.0) var angulo_braco: float = 15.0
## Ângulo do antebraço (cotovelo) para a frente, em graus.
@export_range(0.0, 120.0) var angulo_antebraco: float = 60.0

@export_subgroup("Diagnóstico")
## Imprime animações e ossos do primeiro personagem na aba Saída.
@export var debug_modelo: bool = false

@export_group("Desembarque")
## Arraste aqui o Walking.fbx (de preferência baixado do Mixamo com "In Place").
@export var cena_andar: PackedScene
## Opcional: um FBX com a animação de levantar (ex.: "Sit To Stand" do Mixamo).
## Se ficar vazio, o passageiro apenas se levanta rapidamente e começa a andar.
@export var cena_levantar: PackedScene
## Se o próprio modelo do passageiro já tiver animações dentro dele (ex.: office_worker.tscn),
## escreva aqui o nome delas. Veja os nomes ligando "Debug Modelo". Vazio = não usar.
@export var animacao_andar: StringName = &""
@export var animacao_levantar: StringName = &""
## Se uma Cena Sentado/Andar/Levantar tiver várias animações, escreva qual usar (vazio = a primeira).
@export var escolher_anim_sentado: StringName = &""
@export var escolher_anim_andar: StringName = &""
@export var escolher_anim_levantar: StringName = &""
## Velocidade de caminhada, em metros por segundo.
@export var velocidade_andar: float = 1.2
## Atraso aleatório máximo (segundos) para os passageiros não levantarem todos juntos.
@export var atraso_max: float = 1.5
## Remove o passageiro da cena depois que ele sai pela porta.
@export var remover_ao_sair: bool = true
## Para testar: aperta G para o ônibus parar e os passageiros descerem.
@export var tecla_teste: bool = true
## Para testar sem teclado: o ônibus para sozinho depois de X segundos (0 = desligado).
## Quando o jogo estiver pronto, ponha 0 e chame parar() pelo código.
@export var teste_parar_apos: float = 6.0

var body: CSGBox3D
var door: CSGBox3D
var passengers: Node3D
var _debug_feito := false
var _parado := false
var _sentados: Array[Dictionary] = []
var _anim_sentado: Animation
var _anim_andar: Animation
var _anim_levantar: Animation


func _ready() -> void:
	_build_body()
	_build_door()
	_build_interior()
	_build_wheels()
	_build_lights()
	_build_passengers()
	print("Onibus: script carregado (versão com desembarque). Passageiros sentados: %d" % _sentados.size())
	if teste_parar_apos > 0.0:
		await get_tree().create_timer(teste_parar_apos).timeout
		parar()


func _input(event: InputEvent) -> void:
	if tecla_teste and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_G:
		parar()


func open_door() -> void:
	var tw := create_tween()
	tw.tween_property(door, "position:z", door.position.z + 1.3, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Chame isto quando o ônibus chegar na parada.
## Emite o sinal, abre a porta e faz os passageiros levantarem e andarem até a saída.
func parar() -> void:
	if _parado:
		return
	_parado = true
	print("Onibus: parar() chamado -> %d passageiros vão descer." % _sentados.size())
	stopped.emit()
	open_door()
	_desembarcar_todos()


# ---------- construção ----------

func _build_body() -> void:
	var paint := _mat(Color(0.85, 0.45, 0.10))
	var inner := _mat(Color(0.72, 0.72, 0.70))

	body = CSGBox3D.new()
	body.size = Vector3(2.6, 2.6, 9.0)
	body.position = Vector3(0.0, 1.65, 0.0)
	body.material = paint
	body.use_collision = true
	add_child(body)

	# Esvazia o interior
	_csg_box(body, Vector3(2.4, 2.3, 8.8), Vector3.ZERO, SUB, inner)
	# Janelas (cada caixa fura os dois lados)
	for z in [-1.2, 0.6, 2.4]:
		_csg_box(body, Vector3(2.8, 0.8, 1.3), Vector3(0.0, 0.35, z), SUB, inner)
	# Parabrisa
	_csg_box(body, Vector3(2.0, 0.9, 0.4), Vector3(0.0, 0.4, -4.45), SUB, inner)
	# Buraco da porta (lado direito)
	_csg_box(body, Vector3(0.6, 2.0, 1.1), Vector3(1.1, -0.15, -3.2), SUB, inner)


func _build_door() -> void:
	door = CSGBox3D.new()
	door.size = Vector3(0.08, 2.0, 1.1)
	door.position = Vector3(1.34, 1.5, -3.2)
	door.material = _mat(Color(0.6, 0.65, 0.7), 0.4)
	door.use_collision = true
	add_child(door)


func _build_interior() -> void:
	var fabric := _mat(Color(0.18, 0.20, 0.28))
	var dark := _mat(Color(0.08, 0.08, 0.09))

	# Bancos de passageiros (só visuais, sem colisão)
	for z in ROW_Z:
		for x in COL_X:
			_visual(_box(Vector3(0.7, 0.45, 0.5)), Vector3(x, 0.725, z), fabric)
			_visual(_box(Vector3(0.7, 0.7, 0.1)), Vector3(x, 1.3, z + 0.3), fabric)

	# Banco do motorista (a pessoa é criada em _build_passengers)
	_visual(_box(Vector3(0.7, 0.45, 0.5)), Vector3(-0.8, 0.725, -3.6), fabric)
	_visual(_box(Vector3(0.7, 0.7, 0.1)), Vector3(-0.8, 1.3, -3.3), fabric)
	# Volante
	_visual(_box(Vector3(0.4, 0.04, 0.4)), Vector3(-0.8, 1.35, -4.0), dark, Vector3(-60.0, 0.0, 0.0))


func _build_wheels() -> void:
	var tire := _mat(Color(0.05, 0.05, 0.05))
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 0.35
	for z in [-1.8, 2.6]:
		for x in [-1.45, 1.45]:
			_visual(cyl, Vector3(x, 0.5, z), tire, Vector3(0.0, 0.0, 90.0))


func _build_lights() -> void:
	# Faróis
	for x in [-0.8, 0.8]:
		var spot := SpotLight3D.new()
		spot.position = Vector3(x, 1.0, -4.6)
		spot.spot_range = 60.0
		spot.spot_angle = 22.0
		spot.light_energy = 6.0
		add_child(spot)
	# Luz interna
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, 2.4, 0.0)
	lamp.omni_range = 7.0
	lamp.light_energy = 0.8
	lamp.light_color = Color(1.0, 0.9, 0.7)
	add_child(lamp)


# ---------- passageiros ----------

func _build_passengers() -> void:
	var rng := RandomNumberGenerator.new()
	if semente == 0:
		rng.randomize()
	else:
		rng.seed = semente

	passengers = Node3D.new()
	passengers.name = "Passageiros"
	add_child(passengers)

	_anim_sentado = _carregar_anim(cena_sentado, true, escolher_anim_sentado)
	if cena_sentado == null:
		print("Onibus: o campo 'Cena Sentado' está vazio -> usando a pose por ossos.")
	elif _anim_sentado == null:
		push_warning("Onibus: 'Cena Sentado' (%s) não trouxe nenhuma animação -> usando a pose por ossos." % cena_sentado.resource_path)
	else:
		print("Onibus: animação de sentado carregada (%.2f s)." % _anim_sentado.length)

	# Motorista: sempre presente (e nunca desce)
	_seat_person(Vector3(DRIVER_POS.x, altura_assento, DRIVER_POS.z), rng, false)

	# Passageiros
	for z in ROW_Z:
		for x in COL_X:
			# Não senta ninguém no banco do jogador
			if Vector2(x, z).distance_to(Vector2(SEAT_POS.x, SEAT_POS.z)) < 0.2:
				continue
			if rng.randf() > chance_ocupado:
				continue
			_seat_person(Vector3(x, altura_assento, z), rng)


func _seat_person(pos: Vector3, rng: RandomNumberGenerator, pode_descer: bool = true) -> void:
	var person: Node3D = null

	if not modelos.is_empty():
		var scene: PackedScene = modelos[rng.randi() % modelos.size()]
		if scene != null:
			person = scene.instantiate() as Node3D

	var is_model := person != null
	var ap: AnimationPlayer = null

	if is_model:
		# Mede o modelo e ajusta para a altura alvo (antes de aplicar qualquer escala)
		var fator := 1.0
		if altura_alvo > 0.0:
			var altura_modelo := _calc_aabb(person, Transform3D.IDENTITY).size.y
			if altura_modelo > 0.01:
				fator = altura_alvo / altura_modelo
		person.scale = Vector3.ONE * fator * escala_modelo
		person.rotation_degrees.y = rotacao_modelo

		ap = person.find_child("AnimationPlayer", true, false) as AnimationPlayer

		if debug_modelo and not _debug_feito:
			_debug_feito = true
			_imprimir_diagnostico(person, ap)
	else:
		person = _fallback_person(rng)

	# Pivô: posição no banco + leve variação de direção
	var pivot := Node3D.new()
	pivot.position = pos + Vector3(0.0, 0.0, recuo_assento)
	pivot.rotation_degrees.y = rng.randf_range(-8.0, 8.0)
	pivot.add_child(person)
	passengers.add_child(pivot)

	# Altura do personagem em pé (antes da pose sentada mexer nela)
	var pos_em_pe := person.position
	var y_em_pe := person.position.y

	# Pose (depois de entrar na árvore)
	if is_model:
		if _anim_sentado != null:
			var ap_s := _garantir_ap(person)
			_instalar_anim(ap_s, ANIM_SENTADO, _anim_sentado)
			person.position += offset_sentado
			ap_s.play(ANIM_SENTADO)
		elif ap != null and ap.has_animation(animacao_sentado):
			ap.play(animacao_sentado)
		elif sentar_passageiros:
			if ap != null:
				ap.stop()
			_sentar_por_ossos(person)

	if pode_descer:
		_sentados.append({
			"pivot": pivot,
			"person": person,
			"is_model": is_model,
			"y_em_pe": y_em_pe,
			"pos_em_pe": pos_em_pe,
			"fila": ROW_Z.find(pos.z),
			"corredor_x": rng.randf_range(-0.08, 0.08),
		})


# Cria a pose sentada dobrando os ossos (rig Mixamo)
func _sentar_por_ossos(person: Node3D) -> void:
	var sk := person.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return

	# Descobre o prefixo dos ossos (ex.: "mixamorig_")
	var hips := -1
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).ends_with("Hips"):
			hips = i
			break
	if hips < 0:
		return
	var prefix := sk.get_bone_name(hips).trim_suffix("Hips")

	var l_up := sk.find_bone(prefix + "LeftUpLeg")
	var r_up := sk.find_bone(prefix + "RightUpLeg")
	var l_leg := sk.find_bone(prefix + "LeftLeg")
	var r_leg := sk.find_bone(prefix + "RightLeg")
	var l_foot := sk.find_bone(prefix + "LeftFoot")
	var r_foot := sk.find_bone(prefix + "RightFoot")
	var l_toe := sk.find_bone(prefix + "LeftToeBase")
	var r_toe := sk.find_bone(prefix + "RightToeBase")
	if l_up < 0 or r_up < 0 or l_leg < 0 or r_leg < 0 or l_foot < 0 or r_foot < 0:
		return

	# Transformação do esqueleto -> espaço do personagem
	var xf := Transform3D.IDENTITY
	var n: Node = sk
	while n != null and n != person:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()

	# Para onde o personagem olha (pela direção dos pés, na pose original)
	var fwd := Vector3(0.0, 0.0, 1.0)
	if l_toe >= 0:
		var p_toe := xf * sk.get_bone_global_rest(l_toe).origin
		var p_foot := xf * sk.get_bone_global_rest(l_foot).origin
		var d := p_toe - p_foot
		d.y = 0.0
		if d.length() > 0.001:
			fwd = d.normalized()

	# Gira para a frente do ônibus (-Z)
	person.rotation.y = fwd.signed_angle_to(Vector3.FORWARD, Vector3.UP) + deg_to_rad(rotacao_modelo)

	# Eixo da dobra (espaço do personagem -> espaço do esqueleto)
	var eixo_p := fwd.cross(Vector3.UP).normalized()
	var eixo := (xf.basis.inverse() * eixo_p).normalized()

	# Altura original dos pés (para colocar no chão depois)
	var ref_osso := l_toe if l_toe >= 0 else l_foot
	var y_antes := (xf * sk.get_bone_global_rest(ref_osso).origin).y

	# Coxas sobem; canelas e pés voltam à orientação original (verticais, apoiados)
	var a := deg_to_rad(angulo_coxa)
	_osso_global(sk, l_up, eixo, a)
	_osso_global(sk, r_up, eixo, a)
	for b in [l_leg, r_leg, l_foot, r_foot, l_toe, r_toe]:
		if b >= 0:
			_osso_global(sk, b, eixo, 0.0)

	# Mãos no colo: em vez de girar em torno de um eixo fixo (que não move um braço
	# esticado para o lado), apontamos cada osso na direção desejada.
	if bracos_no_colo:
		var l_arm := sk.find_bone(prefix + "LeftArm")
		var r_arm := sk.find_bone(prefix + "RightArm")
		var l_fore := sk.find_bone(prefix + "LeftForeArm")
		var r_fore := sk.find_bone(prefix + "RightForeArm")
		var l_hand := sk.find_bone(prefix + "LeftHand")
		var r_hand := sk.find_bone(prefix + "RightHand")
		# Direções desejadas (espaço do personagem -> espaço do esqueleto)
		var a_braco := deg_to_rad(angulo_braco)
		var a_ante := deg_to_rad(angulo_braco + angulo_antebraco)
		var dir_braco := (xf.basis.inverse() * (Vector3.DOWN * cos(a_braco) + fwd * sin(a_braco))).normalized()
		var dir_ante := (xf.basis.inverse() * (Vector3.DOWN * cos(a_ante) + fwd * sin(a_ante))).normalized()
		for lado in [[l_arm, l_fore, l_hand], [r_arm, r_fore, r_hand]]:
			var arm: int = lado[0]
			var fore: int = lado[1]
			var hand: int = lado[2]
			if arm < 0 or fore < 0:
				continue
			_aplicar_arco(sk, arm, _arco(sk, arm, fore, dir_braco))
			if hand >= 0:
				var q_ante := _arco(sk, fore, hand, dir_ante)
				_aplicar_arco(sk, fore, q_ante)
				_aplicar_arco(sk, hand, q_ante)

	# Desce o personagem até os pés tocarem o chão
	var y_depois := (xf * sk.get_bone_global_pose(ref_osso).origin).y
	person.position.y += (y_antes - y_depois) * person.scale.y


# Gira um osso em torno de um eixo (espaço do esqueleto), partindo da orientação original
func _osso_global(sk: Skeleton3D, idx: int, eixo: Vector3, angulo: float) -> void:
	var rest_basis := sk.get_bone_global_rest(idx).basis.orthonormalized()
	_definir_global(sk, idx, Basis(eixo, angulo) * rest_basis)


# Rotação que leva a direção original do osso (osso -> filho) até a direção desejada
func _arco(sk: Skeleton3D, idx: int, filho: int, dir_sk: Vector3) -> Quaternion:
	var atual := (sk.get_bone_global_rest(filho).origin - sk.get_bone_global_rest(idx).origin).normalized()
	return Quaternion(atual, dir_sk.normalized())


# Aplica uma rotação (espaço do esqueleto) sobre a orientação original do osso
func _aplicar_arco(sk: Skeleton3D, idx: int, q: Quaternion) -> void:
	var rest_basis := sk.get_bone_global_rest(idx).basis.orthonormalized()
	_definir_global(sk, idx, Basis(q) * rest_basis)


# Define a orientação global de um osso (o pai precisa já estar na pose final)
func _definir_global(sk: Skeleton3D, idx: int, alvo: Basis) -> void:
	var pai := sk.get_bone_parent(idx)
	var pai_basis := Basis.IDENTITY
	if pai >= 0:
		pai_basis = sk.get_bone_global_pose(pai).basis.orthonormalized()
	var local := pai_basis.inverse() * alvo
	sk.set_bone_pose_rotation(idx, local.get_rotation_quaternion())


# ---------- desembarque ----------

func _desembarcar_todos() -> void:
	# Carrega as animações uma vez só e reaproveita em todos os passageiros
	_anim_andar = _carregar_anim(cena_andar, true, escolher_anim_andar)
	_anim_levantar = _carregar_anim(cena_levantar, false, escolher_anim_levantar)

	for d in _sentados:
		# Quem está na frente sai primeiro; a porta leva ~1,2 s para abrir
		var atraso: float = 1.0 + float(d["fila"]) * 0.5 + randf() * atraso_max
		_desembarcar(d, atraso)


func _desembarcar(d: Dictionary, atraso: float) -> void:
	await get_tree().create_timer(atraso).timeout

	var pivot: Node3D = d["pivot"]
	var person: Node3D = d["person"]
	if not is_instance_valid(pivot):
		return

	var y_em_pe: float = d["y_em_pe"]
	var pos_em_pe: Vector3 = d["pos_em_pe"]
	var ap: AnimationPlayer = null

	if d["is_model"]:
		ap = _garantir_ap(person)
		_instalar_anim(ap, ANIM_ANDAR, _anim_andar)
		_instalar_anim(ap, ANIM_LEVANTAR, _anim_levantar)
		# Usa a animação externa (se houver) ou a que já vem dentro do modelo
		var nome_andar := _resolver_anim(ap, ANIM_ANDAR, animacao_andar)
		var nome_levantar := _resolver_anim(ap, ANIM_LEVANTAR, animacao_levantar)
		if nome_andar != &"":
			ap.get_animation(nome_andar).loop_mode = Animation.LOOP_LINEAR

		# Desfaz a pose sentada (animação ou ossos)
		ap.stop()
		var sk := person.find_child("Skeleton3D", true, false) as Skeleton3D
		if sk != null:
			sk.reset_bone_poses()
		person.position.x = pos_em_pe.x
		person.position.z = pos_em_pe.z

		if nome_levantar != &"":
			person.position.y = y_em_pe
			ap.play(nome_levantar, 0.1)
			await get_tree().create_timer(ap.get_animation(nome_levantar).length).timeout
		else:
			# Sem animação de levantar: sobe rapidinho até ficar em pé
			var tw := create_tween()
			tw.tween_property(person, "position:y", y_em_pe, 0.35) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			await tw.finished

		if not is_instance_valid(pivot):
			return
		if nome_andar != &"":
			ap.play(nome_andar, 0.2)
		else:
			push_warning("Onibus: nenhuma animação de andar encontrada (preencha 'Cena Andar' ou 'Animacao Andar').")

	# Caminho: seat -> corredor -> porta -> lado de fora
	var y := pivot.position.y
	var cx: float = d["corredor_x"]
	var z_banco := pivot.position.z
	var pontos: Array[Vector3] = [
		Vector3(cx, y, z_banco),
		Vector3(cx, y, PORTA_POS.z),
		Vector3(PORTA_POS.x, y, PORTA_POS.z),
		Vector3(SAIDA_X, y, PORTA_POS.z),
	]
	for p in pontos:
		await _ir_para(pivot, p)
		if not is_instance_valid(pivot):
			return

	if ap != null:
		ap.stop()
	if remover_ao_sair:
		pivot.queue_free()


# Vira o pivô para o destino e anda até lá
func _ir_para(pivot: Node3D, destino: Vector3) -> void:
	var dir := destino - pivot.position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	# O personagem olha para -Z quando a rotação do pivô é 0
	var yaw := atan2(-dir.x, -dir.z)
	var alvo := pivot.rotation.y + angle_difference(pivot.rotation.y, yaw)
	var tw := create_tween()
	tw.tween_property(pivot, "rotation:y", alvo, 0.25)
	tw.tween_property(pivot, "position", destino, dir.length() / velocidade_andar)
	await tw.finished


# Devolve o AnimationPlayer do personagem (cria um se o modelo não tiver)
func _garantir_ap(person: Node3D) -> AnimationPlayer:
	var ap := person.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		ap = AnimationPlayer.new()
		person.add_child(ap)  # root_node padrão ".." = o próprio personagem
	return ap


# Pega uma animação de um FBX/cena: a de nome 'nome' ou, se vazio, a primeira que não seja RESET
func _carregar_anim(cena: PackedScene, em_loop: bool, nome: StringName = &"") -> Animation:
	if cena == null:
		return null
	var inst := cena.instantiate()
	var src := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var resultado: Animation = null
	if src != null:
		print("Onibus: animações em %s: %s" % [cena.resource_path, src.get_animation_list()])
		if nome != &"" and src.has_animation(nome):
			resultado = src.get_animation(nome).duplicate() as Animation
		else:
			if nome != &"":
				push_warning("Onibus: animação '%s' não existe em %s; usando a primeira." % [nome, cena.resource_path])
			for n in src.get_animation_list():
				if n == "RESET":
					continue
				resultado = src.get_animation(n).duplicate() as Animation
				break
	else:
		push_warning("Onibus: '%s' não tem AnimationPlayer." % cena.resource_path)
	inst.free()
	if resultado != null:
		resultado.loop_mode = Animation.LOOP_LINEAR if em_loop else Animation.LOOP_NONE
	return resultado


# Nome da animação a tocar: a externa instalada, ou a que já vem no modelo ("" se não houver)
func _resolver_anim(ap: AnimationPlayer, instalada: StringName, propria: StringName) -> StringName:
	if ap.has_animation(instalada):
		return instalada
	if propria != &"" and ap.has_animation(propria):
		return propria
	return &""


# Coloca a animação na biblioteca do personagem (se ainda não estiver lá)
func _instalar_anim(ap: AnimationPlayer, nome: StringName, anim: Animation) -> void:
	if anim == null or ap.has_animation(nome):
		return

	# Aviso útil: se o esqueleto do FBX for diferente, o personagem fica parado/torto
	if anim.get_track_count() > 0:
		var raiz := ap.get_node_or_null(ap.root_node)
		var caminho := String(anim.track_get_path(0).get_concatenated_names())
		if raiz != null and raiz.get_node_or_null(caminho) == null:
			push_warning("Onibus: animação '%s' usa o caminho '%s', que não existe neste personagem (esqueletos diferentes?)." % [nome, caminho])

	var lib: AnimationLibrary
	if ap.has_animation_library(&""):
		lib = ap.get_animation_library(&"")
	else:
		lib = AnimationLibrary.new()
		ap.add_animation_library(&"", lib)
	lib.add_animation(nome, anim)


# ---------- diagnóstico e ajudantes ----------

# Mostra na aba Saída o que o modelo tem (animações e ossos)
func _imprimir_diagnostico(person: Node3D, ap: AnimationPlayer) -> void:
	print("===== DIAGNOSTICO DO PERSONAGEM =====")
	if ap != null:
		print("ANIMS: ", ap.get_animation_list())
	else:
		print("ANIMS: nenhum AnimationPlayer encontrado")

	var sk := person.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk != null:
		var nomes: PackedStringArray = []
		for i in sk.get_bone_count():
			nomes.append(sk.get_bone_name(i))
		print("OSSOS (%d): %s" % [nomes.size(), ", ".join(nomes)])
	else:
		print("OSSOS: nenhum Skeleton3D encontrado")
	print("=====================================")


# Calcula a caixa que envolve todas as malhas de um modelo (em espaço local)
func _calc_aabb(node: Node3D, parent_xf: Transform3D) -> AABB:
	var xf := parent_xf * node.transform
	var box := AABB()
	var has := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		box = xf * (node as MeshInstance3D).mesh.get_aabb()
		has = true
	for c in node.get_children():
		if c is Node3D:
			var cb := _calc_aabb(c as Node3D, xf)
			if cb.size.y > 0.0:
				box = cb if not has else box.merge(cb)
				has = true
	return box


# Boneco simples usado quando nenhum modelo foi configurado
func _fallback_person(rng: RandomNumberGenerator) -> Node3D:
	var colors := [
		Color(0.25, 0.30, 0.22), Color(0.35, 0.20, 0.18),
		Color(0.20, 0.25, 0.35), Color(0.30, 0.28, 0.25),
	]
	var root := Node3D.new()
	var torso_mat := _mat(colors[rng.randi() % colors.size()])
	var head_mat := _mat(Color(0.75, 0.6, 0.5))

	root.add_child(_mesh_inst(_box(Vector3(0.4, 0.6, 0.25)), Vector3(0.0, 0.3, 0.0), torso_mat))
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.26
	root.add_child(_mesh_inst(head, Vector3(0.0, 0.74, 0.0), head_mat))
	return root


func _mat(color: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _csg_box(parent: Node, size: Vector3, pos: Vector3, op: CSGShape3D.Operation, mat: Material) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.operation = op
	b.material = mat
	parent.add_child(b)
	return b


func _mesh_inst(mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	return mi


func _visual(mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := _mesh_inst(mesh, pos, mat, rot)
	add_child(mi)
	return mi
