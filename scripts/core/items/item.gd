class_name Item
extends Resource

## Um item declarado como dado — Fase 5.2, ampliado na tradução do original.
##
## Mesma escolha da decisão 9: `Resource` serializável em `.tres`, editável no
## Inspector, revisável em diff. Item novo é arquivo novo.
##
## O que um item faz com atributos **não** é um sistema novo: são
## `StatModifier` com origem `item:<id>`, os mesmos que buff de habilidade usa.
## `03-sistemas-de-jogo.md` é explícito — "não construa um segundo sistema
## paralelo". O mesmo vale para passiva e para uso ativo: reaproveitam o
## vocabulário de efeitos e a `Ability` das habilidades, sem uma segunda
## implementação.

## Que espécie de item é. `equipment_xml` tem 9 valores em `Type`, e eles
## misturam duas perguntas diferentes: o que o item É e ONDE ele entra. Aqui
## as duas ficam separadas — `kind` responde a primeira, `slot` a segunda.
enum Kind {
	## Veste. Ocupa um espaço de equipamento e concede atributos.
	EQUIPMENT,
	## Gasta ao usar. Poção, comida, bomba.
	CONSUMABLE,
	## Só serve para fabricar outra coisa.
	MATERIAL,
	## Carta de talento: modifica o personagem sem ocupar espaço de veste.
	TALENT,
}

enum Slot {
	## Não equipa; ocupa espaço na mochila. Poção, ingrediente.
	NONE,
	WEAPON,
	ARMOR,
	HELMET,
	BOOTS,
	ACCESSORY,
	## Valores novos entram no FIM: isto é exportado para `.tres` como inteiro.
	## `Glove` e `Trinket` do original são espaços próprios lá, e fundi-los em
	## ACCESSORY faria dois itens diferentes brigarem pelo mesmo espaço.
	GLOVE,
	TRINKET,
}

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.EQUIPMENT
@export var slot: Slot = Slot.NONE
@export var rarity: Rarity = Rarity.COMMON

## Quantas unidades cabem num espaço da mochila. 1 = não empilha.
@export var max_stack: int = 1

@export_group("Atributos")
## Bônus planos: { Stat.Id: valor }.
@export var flat_bonuses: Dictionary = {}
## Bônus percentuais: { Stat.Id: fração }. 0.15 = +15%.
@export var percent_bonuses: Dictionary = {}

@export_group("Efeitos")
## Aplicados ao equipar e removidos ao desequipar. É onde mora a passiva —
## `PassiveBuffs` do original — e ela usa exatamente os mesmos efeitos das
## habilidades, inclusive gatilho e periódico.
@export var passive_effects: Array[AbilityEffect] = []

## A habilidade que o item ativa quando usado. Poção, bomba, pergaminho.
## É uma `Ability` de verdade, com recarga e mira próprias: item que conjura e
## campeão que conjura passam pelo mesmo motor.
@export var active_ability: Ability = null

## Usos antes de acabar. 0 = ilimitado (item equipado com ativa).
@export var charges: int = 0

@export_group("Combinação")
## Ids dos itens que se fundem neste. Vazio = item base.
##
## Existe desde já mesmo com crafting fora do escopo da Fase 1, porque
## `03-sistemas-de-jogo.md` pede que o modelo preveja combinação para não
## exigir reescrita depois.
@export var built_from: Array[StringName] = []

## Itens da mesma linha compartilham isto. No original é `EquipLine`: a mesma
## espada existe em Uncommon, Rare e Epic, com os mesmos bônus e números
## maiores. Sem a linha, seriam três itens sem parentesco nenhum, e "melhorar
## o que já tenho" viraria impossível de expressar.
@export var line_id: StringName = &""

## Encaixes para gema. `Socket` do original.
@export var sockets: int = 0

func is_equippable() -> bool:
	return slot != Slot.NONE

func stacks() -> bool:
	return max_stack > 1

func is_usable() -> bool:
	return active_ability != null

## A origem que este item usa em todos os modificadores que aplica.
##
## É por ela que desequipar remove exatamente o que este item deu, e nada
## mais — dois itens com o mesmo bônus são indistinguíveis pelo valor.
func source() -> StringName:
	return &"item:%s" % id

## Constrói os modificadores que este item concede. Quem equipa aplica.
func build_modifiers() -> Array[StatModifier]:
	var mods: Array[StatModifier] = []
	var origem: StringName = source()
	for stat: Stat.Id in flat_bonuses:
		mods.append(StatModifier.new(
			stat, StatModifier.Kind.FLAT, float(flat_bonuses[stat]), origem
		))
	for stat: Stat.Id in percent_bonuses:
		mods.append(StatModifier.new(
			stat, StatModifier.Kind.PERCENT, float(percent_bonuses[stat]), origem
		))
	return mods

## Aplica a passiva a quem equipou. Chamado junto de `build_modifiers()`.
##
## Passa pelo mesmo `AbilityEffect.apply()` das habilidades, com uma mira
## sobre o próprio portador — é isso que permite a passiva de um item ser um
## gatilho ou um periódico sem nenhum código de item.
func apply_passives(wearer: Unit) -> void:
	if wearer == null or passive_effects.is_empty():
		return
	var cast: AbilityCast = AbilityCast.on_self(wearer)
	for effect: AbilityEffect in passive_effects:
		if effect != null:
			effect.apply(cast, wearer)

## Desfaz o que a passiva deixou. Só o que carrega a origem deste item sai —
## o resto de quem desequipou fica intacto.
##
## Cada família de efeito carimba a origem com um prefixo próprio
## (`buff:`, `periodico:`, `gatilho:`), e todos usam a `source_tag` do efeito.
## Daí a convenção: **a `source_tag` de um efeito passivo é o id do item**.
## Sem ela, desequipar não teria como achar o que remover — e o bônus ficaria
## para sempre, que é o pior tipo de bug de inventário.
func remove_passives(wearer: Unit) -> void:
	if wearer == null or passive_effects.is_empty():
		return
	wearer.stats.remove_source(&"buff:%s" % id)
	wearer.stats.remove_source(source())
	wearer.periodic.remove_source(&"periodico:%s" % id)
	wearer.triggers.remove_source(&"gatilho:%s" % id)

## Carimba a `source_tag` de toda passiva com o id do item. Chamar depois de
## montar `passive_effects` em código — quem escreve `.tres` na mão já declara
## a tag certa, e quem gera por ferramenta chama isto e para de pensar nisso.
func stamp_passives() -> void:
	for effect: AbilityEffect in passive_effects:
		if effect != null and &"source_tag" in effect:
			effect.set(&"source_tag", id)

func describe() -> String:
	var partes: PackedStringArray = []
	for stat: Stat.Id in flat_bonuses:
		partes.append("%s +%.0f" % [Stat.name_of(stat), flat_bonuses[stat]])
	for stat: Stat.Id in percent_bonuses:
		partes.append("%s +%.0f%%" % [
			Stat.name_of(stat), float(percent_bonuses[stat]) * 100.0
		])
	for effect: AbilityEffect in passive_effects:
		if effect != null:
			partes.append(effect.describe())
	if active_ability != null:
		partes.append("usa: %s" % active_ability.display_name)
	return "%s [%s] %s" % [
		display_name if not display_name.is_empty() else String(id),
		Rarity.keys()[rarity].to_lower(),
		", ".join(partes),
	]
