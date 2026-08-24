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

## Emitido depois de um dash, empurrão ou puxão ser aplicado ao corpo.
##
## Existe porque a ordem de movimento anterior fica obsoleta: quem tinha um
## destino guardado voltaria andando para lá assim que o dash terminasse.
signal displaced(offset: Vector3)
## O golpe básico SAIU. A camada visual escuta para desenhar o gesto: sem isto
## o auto-ataque era a única ação do jogo sem animação nenhuma.
signal atacou()

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

## Os atributos que vieram do Inspector. Guardados porque `adopt_profile`
## precisa deles como piso: o perfil do original não declara `crit_chance` nem
## `ability_power`, e sem o piso o campeão nasceria com zero dos dois.
var _bases_do_inspector: Dictionary = {}

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

	_bases_do_inspector = {
		Stat.Id.MAX_HEALTH: max_health,
		Stat.Id.ATTACK_DAMAGE: attack_damage,
		Stat.Id.ABILITY_POWER: ability_power,
		Stat.Id.ARMOR: armor,
		Stat.Id.MAGIC_RESIST: magic_resist,
		Stat.Id.ATTACK_SPEED: attack_speed,
		Stat.Id.ATTACK_RANGE: attack_range,
		Stat.Id.CRIT_CHANCE: crit_chance,
		Stat.Id.LIFESTEAL: lifesteal,
	}
	var built := Stats.new()
	built.set_bases(_bases_do_inspector)

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

## Substitui os atributos do Inspector pelos de um campeão do original.
##
## Escreve POR CIMA do `Stats` que já existe, e não troca o `Unit`: `Health`,
## `ResourcePool`, `CombatFeedback` e o `AbilityBook` já guardam referência ao
## que está aí. Trocar o objeto os deixaria apontando para um conjunto morto —
## a barra de vida continuaria mostrando o máximo antigo, sem erro nenhum.
##
## O que os `@export var max_health`, `attack_damage` e companhia continuam
## fazendo: são o padrão de quem NÃO é campeão do original. O boneco de treino
## é declarado assim, e continua sendo.
func adopt_profile(profile: ActorProfile, level: int) -> void:
	ensure_ready()
	if profile == null or unit == null:
		return
	profile.apply_stats_to(unit.stats, level, _bases_do_inspector)
	unit.nature = profile.nature

	# Trocar de campeão é renascer, não continuar. Sem esta limpeza o
	# personagem herda o estado do anterior: uma sonda automática pegou um
	# campeão recusando a suprema com CANNOT_CAST porque carregava um controle
	# de grupo deixado pelo campeão de antes, três trocas atrás.
	unit.status.clear_all()
	unit.periodic.clear()
	unit.triggers.clear()
	unit.marks.clear_all()
	unit.stats.remove_temporary()
	unit.pending_displacement = Vector3.ZERO
	# A cadência do ataque também: renascer não herda o meio-tempo do ataque
	# do campeão anterior.
	unit.reset_attack_cooldown()
	unit.consume_summons()
	unit.consume_cooldown_adjustments()

	# Vida e mana são cheias a partir do máximo NOVO. Sem isto, trocar de um
	# campeão de 2000 para um de 2600 deixaria o segundo nascer com 2000.
	unit.health.current = unit.health.maximum()
	unit.health.changed.emit(unit.health.current, unit.health.maximum())
	unit.mana.current = unit.mana.maximum()
	unit.mana.changed.emit(unit.mana.current, unit.mana.maximum())

	# A carga da suprema é o contrário: nasce VAZIA e se ganha jogando.
	unit.ultimate_charge_on_attack = profile.ultimate_charge_on_attack
	unit.ultimate_charge.current = 0.0
	unit.ultimate_charge.changed.emit(
		0.0, unit.ultimate_charge.maximum()
	)

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
	displaced.emit(push)

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
	var resultado: DamageResult = unit.basic_attack(target.unit)
	if resultado != null:
		atacou.emit()
	return resultado

## Encontra o Combatant preso a um corpo. Devolve nulo se o corpo não for um
## combatente — parede, chão.
static func of(node: Node) -> Combatant:
	if node == null:
		return null
	for child: Node in node.get_children():
		if child is Combatant:
			return child
	return null
