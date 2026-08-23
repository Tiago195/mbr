class_name ActorProfile
extends RefCounted

## Quem é um personagem: atributos, crescimento e kit — a peça que faltava.
##
## As tabelas de habilidade do original dizem O QUE cada habilidade faz.
## Nenhuma delas diz QUEM a tem. Isso mora em `actor_xml`, e é o que este
## perfil traduz. Sem ele o corpus de 1126 habilidades é um catálogo que
## ninguém empunha — que era exatamente a objeção do usuário ao fim da
## tradução: *"eu não as consigo ver nem testar no jogo"*.
##
## Continua em `core/`: `RefCounted`, sem nó, sem cena. Monta um `Unit` e
## abastece um `AbilityBook`, e as duas coisas já rodavam headless.
##
## A convenção de espaço vem do original e foi medida, não suposta:
## `DefaultSkillId_1` é o ataque básico (`InstantTarget`, recarga abaixo de um
## segundo em todos os campeões), `_2`/`_3`/`_4` são Q, W e E, e
## `UltimateSkill` é o R.

## Identificador ASCII estável: `leo`, `bella`, `rc_actor_5010000`.
var id: StringName = &""
var source_id: int = 0
var display_name: String = ""

## `Player`, `Monster`, `AIPlayer`, `ActorObject`... como o original classifica.
## Fica separado de `nature` porque a nossa natureza junta casos que lá são
## distintos, e perder a distinção impediria de listar "só os campeões".
var usage: StringName = &""
var nature: Unit.Nature = Unit.Nature.MONSTER

## `FIGHTER`, `MARKSMAN`, `TANK`... Informativo: nada no motor lê isto.
var role: StringName = &""
var enabled: bool = true

## Em que nível o bloco de atributos base vale. 1 para campeão; os mobs do
## original nascem prontos num nível maior.
var base_level: int = 1

## `Stat.Id` -> valor no `base_level`.
var base_stats: Dictionary = {}
## `Stat.Id` -> quanto o atributo ganha por nível acima do `base_level`.
var growth: Dictionary = {}

## Grupos de habilidade. **Grupo, não habilidade**: a tabela de atores aponta
## para a linha-modelo (`Rank 0`), que não tem pulso nenhum. O ranque jogável
## sai de `AbilityCatalog.rank_for_level()` com o nível do personagem.
var basic_attack_group: StringName = &""
## Q, W e E, nessa ordem.
var ability_groups: Array[StringName] = []
var ultimate_group: StringName = &""

## A suprema do original não tem recarga: ela enche AGINDO. `ultimate_cooldown`
## é o número inventado que sobrou para o caso degenerado — suprema sem carga e
## sem recarga —, e hoje vale para um ator só.
var ultimate_uses_charge: bool = false
var ultimate_cooldown: float = 0.0

## Quanta carga a suprema exige. 1000 nos 31 campeões que a têm.
##
## Entra em `base_stats` como `MAX_ULTIMATE_CHARGE`, então viaja pelo mesmo
## caminho de todo atributo — nada precisa saber que ele é especial.
var ultimate_charge_cost: float = 0.0

## Quanta carga o ataque básico deste personagem rende: 200 nos 31.
var ultimate_charge_on_attack: float = 0.0

## Passiva do personagem, já traduzida. Aplicada por `apply_passives()`.
var passive_effects: Array[AbilityEffect] = []

var body_radius: float = 0.5
var body_height: float = 2.0
var damageable: bool = true
var targetable: bool = true
var able_combat: bool = true

## Taxonomia de comportamento do original (`playeraggressive`, `dragonai`...).
## Nada lê isto ainda; é o que a IA de mob vai consumir.
var ai_profile: StringName = &""
var max_summons: int = 0

## Habilidades presas a momentos, não a teclas. Ainda sem consumidor.
var on_spawn_group: StringName = &""
var on_death_group: StringName = &""
var on_combat_start_group: StringName = &""
var on_return_group: StringName = &""

# ---------------------------------------------------------------- atributos

## O valor de um atributo num nível. Abaixo do `base_level` não encolhe: o
## bloco base é o piso, não um ponto no meio de uma reta.
func stat_at(stat: Stat.Id, level: int) -> float:
	var valor: float = base_stats.get(stat, Stat.default_of(stat))
	var por_nivel: float = growth.get(stat, 0.0)
	if por_nivel != 0.0:
		valor += por_nivel * float(maxi(level - base_level, 0))
	return valor

## Todo atributo que este perfil define, no nível pedido.
##
## Devolve só o que o perfil declara. Atributo que ele não menciona fica com o
## padrão de `Stat.DEFAULTS`, e é isso que faz um mob sem `attack_speed`
## atacar uma vez por segundo em vez de nunca.
func stats_at(level: int) -> Dictionary:
	var valores: Dictionary = {}
	for stat: Stat.Id in base_stats:
		valores[stat] = stat_at(stat, level)
	for stat: Stat.Id in growth:
		if not valores.has(stat):
			valores[stat] = stat_at(stat, level)
	return valores

## Escreve os atributos do perfil num `Stats` que já existe.
##
## Escreve em cima em vez de trocar o objeto de propósito: `Health`,
## `ResourcePool` e todo modificador ativo guardam a referência ao `Stats`, e
## substituí-lo os deixaria apontando para um conjunto morto — o personagem
## ficaria com a vida máxima antiga e ninguém veria erro nenhum.
##
## **Substitui o conjunto inteiro**, e não só o que este perfil declara. Sem
## isso, trocar de personagem herda os atributos que o anterior tinha e este
## não menciona: 28 dos 33 campeões declaram `out_of_combat_health_regen` e
## cinco não, e a regeneração do anterior ficava colada nos cinco.
##
## `fallback` é o que vale para atributo que NENHUM dos dois declara — os
## `@export` do Inspector, no caso do `Combatant`.
func apply_stats_to(stats: Stats, level: int, fallback: Dictionary = {}) -> void:
	if stats == null:
		return
	var combinado: Dictionary = fallback.duplicate()
	combinado.merge(stats_at(level), true)
	stats.reset_bases(combinado)

func build_unit(level: int, team: int = 0) -> Unit:
	var stats := Stats.new()
	stats.set_bases(stats_at(level))
	var unit := Unit.new(stats, team)
	unit.nature = nature
	unit.ultimate_charge_on_attack = ultimate_charge_on_attack
	# **A suprema nasce vazia.** `ResourcePool` enche no `_init`, como a mana
	# faz — e para a mana isso está certo. Para a carga não: começar cheia daria
	# a suprema de graça no primeiro segundo da partida, que é o oposto de um
	# recurso que se ganha jogando.
	unit.ultimate_charge.current = 0.0
	return unit

func is_champion() -> bool:
	return usage == &"Player" and ability_groups.size() >= 3

# ---------------------------------------------------------------- passiva

## Aplica a passiva do personagem. Mesmo contrato de `Ability.apply_passives`.
func apply_passives(owner: Unit) -> void:
	if owner == null or passive_effects.is_empty():
		return
	var cast: AbilityCast = AbilityCast.on_self(owner)
	for effect: AbilityEffect in passive_effects:
		if effect != null:
			effect.apply(cast, owner)

func remove_passives(owner: Unit) -> void:
	if owner == null or passive_effects.is_empty():
		return
	var tag: StringName = _passive_tag()
	# Os prefixos são os que cada efeito escreve ao aplicar: `StatModEffect`
	# guarda como `buff:<tag>`, `PeriodicEffect` como `periodico:<tag>` e
	# `TriggerEffect` como `gatilho:<tag>`. Remover pela tag nua não acharia
	# nada, e o bônus do campeão anterior ficaria colado para sempre.
	owner.stats.remove_source(&"buff:%s" % tag)
	owner.periodic.remove_source(&"periodico:%s" % tag)
	owner.triggers.remove_source(&"gatilho:%s" % tag)

## Carimba a etiqueta de origem em toda passiva. Sem ela, trocar de campeão
## deixaria o bônus do anterior colado no personagem para sempre.
func stamp_passives() -> void:
	for effect: AbilityEffect in passive_effects:
		if effect != null and &"source_tag" in effect:
			effect.set(&"source_tag", _passive_tag())

func _passive_tag() -> StringName:
	return StringName("actor:%s" % id)

# ---------------------------------------------------------------- kit

## Aprende Q, W, E e R no livro, no ranque que o nível permite.
##
## Devolve quantos espaços foram preenchidos. Um campeão do original preenche
## quatro; um mob preenche o que tiver.
##
## `owner` é passado ao `learn` de propósito: é o que aplica a passiva de
## ranque de cada habilidade — o bônus que ela dá por existir.
func equip_book(
		book: AbilityBook, catalog: AbilityCatalog, owner: Unit, level: int
) -> int:
	if book == null or catalog == null:
		return 0

	var espacos: Array[AbilityBook.Slot] = [
		AbilityBook.Slot.Q, AbilityBook.Slot.W, AbilityBook.Slot.E,
	]
	var preenchidos: int = 0
	for indice: int in espacos.size():
		var grupo: StringName = (
			ability_groups[indice] if indice < ability_groups.size() else &""
		)
		var ability: Ability = ability_for(catalog, grupo, level)
		book.learn(espacos[indice], ability, owner)
		if ability != null:
			preenchidos += 1

	# O ganho de carga do ataque básico NÃO é escrito aqui.
	#
	# Ele já vem de `ultimate_charge_on_attack`, do perfil, e quem o aplica é
	# `build_unit` e `Combatant.adopt_profile`. Havia uma segunda escrita neste
	# ponto, resolvendo a habilidade pelo catálogo — duas fontes de verdade
	# para o mesmo número, e a segunda gravava ZERO por cima quando
	# `rank_for_level` recusava. Medido: as duas divergem em 24 atores, todos
	# estruturas; nos 31 campeões com carga, em nenhum nível de 1 a 18. Era
	# inofensivo hoje e latente amanhã.
	var suprema: Ability = ultimate_for(catalog, level)
	book.learn(AbilityBook.Slot.R, suprema, owner)
	if suprema != null:
		preenchidos += 1
	return preenchidos

## O ranque jogável de um grupo, ou nulo quando o grupo não existe ou o nível
## não alcança nem o primeiro.
static func ability_for(
		catalog: AbilityCatalog, group: StringName, level: int
) -> Ability:
	if catalog == null or group.is_empty():
		return null
	return catalog.rank_for_level(group, level)

## A suprema, já com a recarga que substitui a carga que não temos.
##
## Devolve uma CÓPIA quando precisa mexer na recarga. O catálogo entrega a
## mesma instância a todo mundo, e escrever nela mudaria a suprema de todos os
## personagens que compartilham o grupo — inclusive os que ainda nem existem.
func ultimate_for(catalog: AbilityCatalog, level: int) -> Ability:
	var base: Ability = ability_for(catalog, ultimate_group, level)
	if base == null:
		return null
	var por_carga: bool = ultimate_uses_charge and ultimate_charge_cost > 0.0
	var por_recarga: bool = (
		not por_carga
		and ultimate_cooldown > 0.0
		and not is_equal_approx(base.cooldown, ultimate_cooldown)
	)
	if not por_carga and not por_recarga:
		return base

	var copia: Ability = base.duplicate() as Ability
	# **"Ser a suprema" é papel no kit, não propriedade da habilidade.** A marca
	# vai na CÓPIA, e não no corpus: a mesma habilidade emprestada a um mob não
	# seria suprema de ninguém, e o catálogo entrega a mesma instância a todos.
	copia.uses_ultimate_charge = por_carga
	if por_recarga:
		copia.cooldown = ultimate_cooldown
	return copia

## Todo grupo de habilidade que este perfil cita, em qualquer papel. Serve ao
## teste que confere que nenhum deles ficou órfão do `AbilityCatalog`.
func all_groups() -> Array[StringName]:
	var grupos: Array[StringName] = []
	for grupo: StringName in ability_groups:
		grupos.append(grupo)
	for grupo: StringName in [
		basic_attack_group, ultimate_group, on_spawn_group, on_death_group,
		on_combat_start_group, on_return_group,
	]:
		if not grupo.is_empty():
			grupos.append(grupo)
	return grupos
