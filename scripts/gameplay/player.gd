extends CharacterBody3D

## Personagem jogável — Fases 1.1, 1.2 e 2.3.
##
## Botão DIREITO faz as duas coisas, conforme o que estiver embaixo do cursor:
## em inimigo, ataca; em chão, anda. É o esquema do League of Legends
## (decisão 7 em `docs/02-decisoes-tecnicas.md`). Manter pressionado repete a
## decisão a cada tick, o que dá perseguição contínua.
##
## O laço de ataque mora aqui, e não num lugar compartilhado, porque hoje só o
## jogador ataca. Quando os mobs ganharem IA (Fase 6) ele sobe para um
## componente — nesse momento o `Combatant` já tem tudo que ele precisa.

## Camada de física dos combatentes. Ver as camadas em `main.tscn`.
const TARGET_MASK: int = 2

## Alcance do raycast de mira, em metros. Maior que a diagonal do mapa.
const AIM_DISTANCE: float = 1000.0

@export var speed: float = 5.0
@export var arrival_threshold: float = 0.2

@onready var _combatant: Combatant = $Combatant

var target_position: Vector3

var _target: Combatant = null
var _attack_cooldown: float = 0.0

func _ready() -> void:
	target_position = global_position
	_combatant.displaced.connect(_on_displaced)

## Depois de um deslocamento — dash, empurrão, puxão — o personagem para onde
## parou.
##
## Sem isto, a ordem de movimento anterior sobrevive ao dash e ele volta
## andando sozinho para onde o jogador tinha clicado antes. O alvo de ataque
## também é solto: perseguir de volta teria o mesmo efeito visível.
func _on_displaced(_offset: Vector3) -> void:
	target_position = global_position
	_target = null
	velocity = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	# O clique isolado é tratado aqui, e não só pelo estado do botão em
	# `_physics_process`, para que um clique mais curto que um tick de física
	# não se perca.
	if event is InputEventMouseButton \
			and event.is_pressed() \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_command_at(event.position)

func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	# Botão segurado: a ordem é reavaliada a cada tick, seguindo o cursor.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_command_at(get_viewport().get_mouse_position())

	# Alvo que morreu deixa de ser alvo, senão o personagem fica batendo em
	# cadáver.
	if _target != null and not _target.is_alive():
		_target = null
		target_position = global_position

	if _target != null:
		_pursue_and_attack()
	else:
		_walk_to_target()

	move_and_slide()

# ---------------------------------------------------------------- comandos

## Decide o que o botão direito significa neste ponto da tela.
func _command_at(screen_point: Vector2) -> void:
	var enemy: Combatant = _enemy_under(screen_point)
	if enemy != null:
		_target = enemy
		return
	_target = null
	_aim_at_screen_point(screen_point)

## Raycast de física contra a camada dos combatentes. Devolve nulo quando o
## cursor não está sobre um inimigo vivo.
func _enemy_under(screen_point: Vector2) -> Combatant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null

	var from: Vector3 = camera.project_ray_origin(screen_point)
	var to: Vector3 = from + camera.project_ray_normal(screen_point) * AIM_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(from, to, TARGET_MASK, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var found: Combatant = Combatant.of(hit["collider"] as Node)
	if found == null or not found.is_alive():
		return null
	if not _combatant.is_hostile_to(found):
		return null
	return found

# ---------------------------------------------------------------- movimento

func _walk_to_target() -> void:
	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	if to_target.length() > arrival_threshold:
		velocity = to_target.normalized() * speed
		_face(to_target)
	else:
		velocity = Vector3.ZERO

## Persegue até entrar no alcance, para, e bate no ritmo da velocidade de
## ataque. Enquanto ataca, continua encarando o alvo.
func _pursue_and_attack() -> void:
	var enemy_body: Node3D = _target.body()
	if enemy_body == null:
		_target = null
		return

	var to_enemy: Vector3 = enemy_body.global_position - global_position
	to_enemy.y = 0.0
	_face(to_enemy)

	if to_enemy.length() > _combatant.stats.get_value(Stat.Id.ATTACK_RANGE):
		velocity = to_enemy.normalized() * speed
		return

	velocity = Vector3.ZERO
	# Parou no alcance: o destino de caminhada vira o lugar atual, senão ao
	# matar o alvo o personagem sairia andando para uma ordem antiga.
	target_position = global_position

	if _attack_cooldown <= 0.0:
		_combatant.basic_attack(_target)
		_attack_cooldown = _combatant.attack_interval()

## `look_at` emite erro quando o alvo coincide com a própria posição.
## Como `to_target.y` já foi zerado e o `up` é `Vector3.UP`, esta guarda de
## comprimento é a única que falta.
func _face(direction: Vector3) -> void:
	if direction.length_squared() <= 0.000001:
		return
	look_at(global_position + direction, Vector3.UP)

# ---------------------------------------------------------------- mira no chão

## Converte um ponto da tela no ponto correspondente do chão e o adota como
## destino. Ignora silenciosamente miras que não cruzam o plano — acontece ao
## apontar acima da linha do horizonte.
##
## Este raycast é contra um plano matemático, não contra a física: é mais
## barato e não depende de haver colisor no chão. A mira de habilidade da
## Fase 3 reusa exatamente isto.
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
