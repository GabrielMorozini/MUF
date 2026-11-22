class_name Jogador
extends CharacterBody3D

@export var speed: float = 6.0
@export var sprint_speed: float = 10.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var frozen: bool = false   # true = parado (cutscene), mas ainda pode olhar em volta


func set_frozen(value: bool) -> void:
	frozen = value
	if value:
		velocity = Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Olhar com o mouse
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	# ESC solta o mouse, clique prende de novo
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if frozen:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var current_speed := sprint_speed if Input.is_physical_key_pressed(KEY_SHIFT) else speed

	if direction != Vector3.ZERO:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)

	move_and_slide()
