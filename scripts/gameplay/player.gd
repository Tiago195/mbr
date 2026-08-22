extends CharacterBody3D

## Movimento por clique no chão — Fases 1.1 e 1.2.
##
## Botão DIREITO move, seguindo o esquema do League of Legends. O esquerdo
## fica reservado para seleção e UI. Ver decisão 7 em
## `docs/02-decisoes-tecnicas.md`.
##
## Clicar define um destino; manter pressionado faz o personagem perseguir o
## cursor continuamente.
##
## O clique vira um ponto do mundo por raycast contra um plano na altura do
## personagem. A mesma conversão tela -> mundo será reusada pela mira de
## habilidade na Fase 3 — lá disparada por tecla, não por clique.

@export var speed: float = 5.0
@export var arrival_threshold: float = 0.2

var target_position: Vector3

func _ready() -> void:
	target_position = global_position

func _unhandled_input(event: InputEvent) -> void:
	# O clique isolado é tratado aqui, e não só pelo estado do botão em
	# `_physics_process`, para que um clique muito curto — mais rápido que um
	# tick de física — não se perca.
	if event is InputEventMouseButton \
			and event.is_pressed() \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_aim_at_screen_point(event.position)

func _physics_process(_delta: float) -> void:
	# Botão segurado: o destino acompanha o cursor a cada tick.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_aim_at_screen_point(get_viewport().get_mouse_position())

	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	if to_target.length() > arrival_threshold:
		velocity = to_target.normalized() * speed
		look_at(global_position + to_target, Vector3.UP)
	else:
		velocity = Vector3.ZERO
	move_and_slide()

## Converte um ponto da tela no ponto correspondente do chão e o adota como
## destino. Ignora silenciosamente cliques que não cruzam o plano — acontece
## quando se mira acima da linha do horizonte.
func _aim_at_screen_point(screen_point: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var ray_origin: Vector3 = camera.project_ray_origin(screen_point)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_point)
	var ground := Plane(Vector3.UP, global_position.y)
	var hit: Variant = ground.intersects_ray(ray_origin, ray_dir)
	# `is Vector3` e não `if hit:` — Vector3.ZERO avalia como falso, e um
	# clique na origem do mundo seria silenciosamente ignorado.
	if hit is Vector3:
		target_position = hit
