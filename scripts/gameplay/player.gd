extends CharacterBody3D

## Movimento por clique no chão — Fase 1.1.
## O clique vira um ponto do mundo por raycast contra um plano na altura do
## personagem. A mesma conversão tela -> mundo será reusada pela mira de
## habilidade na Fase 3.
##
## Botão DIREITO move, seguindo o esquema do League of Legends. O esquerdo
## fica reservado para seleção e UI. Ver decisão 7 em
## `docs/02-decisoes-tecnicas.md`.

@export var speed: float = 5.0
@export var arrival_threshold: float = 0.2

var target_position: Vector3

func _ready() -> void:
	target_position = global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.is_pressed() \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera == null:
			return
		var ray_origin: Vector3 = camera.project_ray_origin(event.position)
		var ray_dir: Vector3 = camera.project_ray_normal(event.position)
		var ground := Plane(Vector3.UP, global_position.y)
		var hit: Variant = ground.intersects_ray(ray_origin, ray_dir)
		# `is Vector3` e não `if hit:` — Vector3.ZERO avalia como falso, e um
		# clique na origem do mundo seria silenciosamente ignorado.
		if hit is Vector3:
			target_position = hit

func _physics_process(_delta: float) -> void:
	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	if to_target.length() > arrival_threshold:
		velocity = to_target.normalized() * speed
		look_at(global_position + to_target, Vector3.UP)
	else:
		velocity = Vector3.ZERO
	move_and_slide()
