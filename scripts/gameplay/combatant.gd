class_name Combatant
extends Node

## Componente que dá atributos, vida e combate a um corpo — Fase 2.3.
##
## É um Node solto, filho do corpo, e não uma classe base: o jogador é
## `CharacterBody3D` e o boneco de treino é `StaticBody3D`. Herança forçaria
## os dois a compartilhar um tipo de corpo que não têm em comum. Composição
## resolve, e é o que vai permitir dar combate a mob, torre ou barril.
##
## A lógica de verdade mora em `core/`; este nó só a conecta à árvore de cena.

signal damaged(result: DamageResult)
signal died()

## Times diferentes são inimigos. 0 = jogador, 1 = hostil.
@export var team: int = 0

@export_group("Atributos base")
@export var max_health: float = 600.0
@export var attack_damage: float = 60.0
@export var armor: float = 30.0
@export var magic_resist: float = 30.0
## Ataques por segundo.
@export var attack_speed: float = 1.0
## Distância máxima do ataque básico, em metros.
@export var attack_range: float = 2.5
@export_range(0.0, 1.0) var crit_chance: float = 0.0
@export_range(0.0, 1.0) var lifesteal: float = 0.0

var stats: Stats
var health: Health

func _ready() -> void:
	ensure_ready()

## Constrói atributos e vida se ainda não existirem.
##
## Existe como método público porque outros nós — o de feedback visual, por
## exemplo — precisam de `health` no `_ready()` deles, e a ordem em que a Godot
## chama `_ready()` entre irmãos depende da ordem na cena. Depender disso é
## receita para um bug que só aparece quando alguém arrasta um nó no editor.
func ensure_ready() -> void:
	if stats != null:
		return
	stats = Stats.new()
	stats.set_bases({
		Stat.Id.MAX_HEALTH: max_health,
		Stat.Id.ATTACK_DAMAGE: attack_damage,
		Stat.Id.ARMOR: armor,
		Stat.Id.MAGIC_RESIST: magic_resist,
		Stat.Id.ATTACK_SPEED: attack_speed,
		Stat.Id.ATTACK_RANGE: attack_range,
		Stat.Id.CRIT_CHANCE: crit_chance,
		Stat.Id.LIFESTEAL: lifesteal,
	})
	health = Health.new(stats)
	health.died.connect(_on_died)

## O corpo ao qual este componente está preso. É de onde sai a posição.
func body() -> Node3D:
	return get_parent() as Node3D

func is_alive() -> bool:
	return health != null and health.is_alive()

func is_hostile_to(other: Combatant) -> bool:
	return other != null and other.team != team

## Distância no plano do chão. A altura é ignorada de propósito: alcance de
## ataque num MOBA é medido no chão, senão um alvo em rampa ficaria fora de
## alcance sem motivo visível.
func ground_distance_to(other: Combatant) -> float:
	var from: Node3D = body()
	var to: Node3D = other.body()
	if from == null or to == null:
		return INF
	var delta: Vector3 = to.global_position - from.global_position
	delta.y = 0.0
	return delta.length()

## Ataque básico contra outro combatente. Devolve o resultado para quem quiser
## desenhar número flutuante ou registrar log.
func basic_attack(target: Combatant) -> DamageResult:
	return target.receive_damage(
		self,
		stats.get_value(Stat.Id.ATTACK_DAMAGE),
		Damage.Type.PHYSICAL,
		Damage.Source.BASIC_ATTACK
	)

## Recebe dano. `attacker` pode ser nulo — dano de zona não tem dono.
func receive_damage(
		attacker: Combatant,
		raw_damage: float,
		type: Damage.Type,
		source: Damage.Source
) -> DamageResult:
	var attacker_stats: Stats = attacker.stats if attacker != null else null
	var result: DamageResult = Damage.resolve(
		attacker_stats,
		stats,
		health.current,
		health.shield,
		raw_damage,
		type,
		source
	)
	health.apply(result)
	if attacker != null and result.lifesteal_healed > 0.0:
		attacker.health.heal(result.lifesteal_healed)
	damaged.emit(result)
	return result

## Segundos entre ataques, derivado de `attack_speed`.
func attack_interval() -> float:
	var speed: float = stats.get_value(Stat.Id.ATTACK_SPEED)
	return 1.0 / maxf(speed, 0.01)

## Encontra o Combatant preso a um corpo. Devolve nulo se o corpo não for um
## combatente — parede, chão.
static func of(node: Node) -> Combatant:
	if node == null:
		return null
	for child: Node in node.get_children():
		if child is Combatant:
			return child
	return null

func _on_died() -> void:
	died.emit()
