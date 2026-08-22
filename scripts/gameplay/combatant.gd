class_name Combatant
extends Node

## Ponte entre um corpo na cena e um `Unit` de `core/` — Fases 2.3 e 3.1.
##
## É um Node solto, filho do corpo, e não uma classe base: o jogador é
## `CharacterBody3D` e o boneco de treino é `StaticBody3D`. Herança forçaria os
## dois a compartilhar um tipo de corpo que não têm em comum.
##
## Toda a regra de combate vive no `unit`. Este nó faz três coisas e só:
## sincroniza a posição do corpo para o `Unit`, aplica o deslocamento que os
## efeitos pediram, e repassa os sinais para a camada visual.

signal damaged(result: DamageResult)
signal died()

## Times diferentes são inimigos. 0 = jogador, 1 = hostil.
@export var team: int = 0

@export_group("Atributos base")
@export var max_health: float = 600.0
@export var attack_damage: float = 60.0
@export var ability_power: float = 0.0
@export var armor: float = 30.0
@export var magic_resist: float = 30.0
## Ataques por segundo.
@export var attack_speed: float = 1.0
## Distância máxima do ataque básico, em metros.
@export var attack_range: float = 2.5
@export_range(0.0, 1.0) var crit_chance: float = 0.0
@export_range(0.0, 1.0) var lifesteal: float = 0.0

var unit: Unit

## Atalhos para o que o `unit` possui. Existem para não obrigar todo chamador
## a escrever `combatant.unit.health`.
var stats: Stats
var health: Health

## Grupo de todos os combatentes da cena. É como a resolução de habilidade
## descobre os candidatos sem precisar de referência direta a cada um.
const GROUP: StringName = &"combatants"

func _ready() -> void:
	ensure_ready()
	add_to_group(GROUP)

## Todos os `Unit` vivos da cena. É o que `AbilityShape` filtra por forma.
##
## Varrer o grupo inteiro é aceitável com 8 jogadores e alguns bonecos. Com
## 30+ combatentes e habilidades disparando o tempo todo, isto vira o grid
## espacial da Fase 4.6 — a mesma estrutura que a área de interesse vai pedir.
static func all_units(tree: SceneTree) -> Array:
	var units: Array = []
	for node: Node in tree.get_nodes_in_group(GROUP):
		var combatant := node as Combatant
		if combatant != null and combatant.unit != null:
			units.append(combatant.unit)
	return units

## Constrói o `Unit` se ainda não existir.
##
## É público porque outros nós — o de feedback visual, por exemplo — precisam
## de `health` no `_ready()` deles, e a ordem em que a Godot chama `_ready()`
## entre irmãos depende da ordem na cena. Depender disso é receita para um bug
## que só aparece quando alguém arrasta um nó no editor.
func ensure_ready() -> void:
	if unit != null:
		return

	var built := Stats.new()
	built.set_bases({
		Stat.Id.MAX_HEALTH: max_health,
		Stat.Id.ATTACK_DAMAGE: attack_damage,
		Stat.Id.ABILITY_POWER: ability_power,
		Stat.Id.ARMOR: armor,
		Stat.Id.MAGIC_RESIST: magic_resist,
		Stat.Id.ATTACK_SPEED: attack_speed,
		Stat.Id.ATTACK_RANGE: attack_range,
		Stat.Id.CRIT_CHANCE: crit_chance,
		Stat.Id.LIFESTEAL: lifesteal,
	})

	unit = Unit.new(built, team)
	stats = unit.stats
	health = unit.health

	var host: Node3D = body()
	if host != null:
		unit.position = host.global_position

	# Conectar na morte via `unit.health`, e não via um sinal repassado pelo
	# `Unit`: o repasse criaria um ciclo de referência entre dois RefCounted.
	# Ver o comentário em `unit.gd`.
	unit.damaged.connect(func(result: DamageResult) -> void: damaged.emit(result))
	unit.health.died.connect(func() -> void: died.emit())

func _physics_process(delta: float) -> void:
	if unit == null:
		return
	unit.advance_time(delta)

	var host: Node3D = body()
	if host == null:
		return

	unit.position = host.global_position
	unit.facing = -host.global_transform.basis.z

	var push: Vector3 = unit.consume_displacement()
	if push.length_squared() > 0.000001:
		_apply_displacement(host, push)

## Aplica o deslocamento que um efeito pediu.
##
## É aqui, e não em `core/`, porque só esta camada tem física: um dash tem que
## parar na parede em vez de atravessá-la, e `core/` não conhece colisor.
func _apply_displacement(host: Node3D, push: Vector3) -> void:
	if host is CharacterBody3D:
		(host as CharacterBody3D).move_and_collide(push)
	else:
		host.global_position += push
	unit.position = host.global_position

# ---------------------------------------------------------------- atalhos

func body() -> Node3D:
	return get_parent() as Node3D

func is_alive() -> bool:
	return unit != null and unit.is_alive()

func is_hostile_to(other: Combatant) -> bool:
	return other != null and other.unit != null and unit.is_hostile_to(other.unit)

func ground_distance_to(other: Combatant) -> float:
	if other == null or other.unit == null:
		return INF
	return unit.ground_distance_to(other.unit)

func basic_attack(target: Combatant) -> DamageResult:
	return unit.basic_attack(target.unit)

func attack_interval() -> float:
	return unit.attack_interval()

## Encontra o Combatant preso a um corpo. Devolve nulo se o corpo não for um
## combatente — parede, chão.
static func of(node: Node) -> Combatant:
	if node == null:
		return null
	for child: Node in node.get_children():
		if child is Combatant:
			return child
	return null
