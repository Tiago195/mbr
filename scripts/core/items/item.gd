class_name Item
extends Resource

## Um item declarado como dado — Fase 5.2.
##
## Mesma escolha da decisão 9: `Resource` serializável em `.tres`, editável no
## Inspector, revisável em diff. Item novo é arquivo novo.
##
## O que um item faz com atributos **não** é um sistema novo: são
## `StatModifier` com origem `item:<id>`, os mesmos que buff de habilidade usa.
## `03-sistemas-de-jogo.md` é explícito — "não construa um segundo sistema
## paralelo".

enum Slot {
	## Não equipa; ocupa espaço na mochila. Poção, ingrediente.
	NONE,
	WEAPON,
	ARMOR,
	HELMET,
	BOOTS,
	ACCESSORY,
}

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: Slot = Slot.NONE
@export var rarity: Rarity = Rarity.COMMON

## Quantas unidades cabem num espaço da mochila. 1 = não empilha.
@export var max_stack: int = 1

@export_group("Atributos")
## Bônus planos: { Stat.Id: valor }.
@export var flat_bonuses: Dictionary = {}
## Bônus percentuais: { Stat.Id: fração }. 0.15 = +15%.
@export var percent_bonuses: Dictionary = {}

@export_group("Combinação")
## Ids dos itens que se fundem neste. Vazio = item base.
##
## Existe desde já mesmo com crafting fora do escopo da Fase 1, porque
## `03-sistemas-de-jogo.md` pede que o modelo preveja combinação para não
## exigir reescrita depois.
@export var built_from: Array[StringName] = []

func is_equippable() -> bool:
	return slot != Slot.NONE

func stacks() -> bool:
	return max_stack > 1

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

func describe() -> String:
	var partes: PackedStringArray = []
	for stat: Stat.Id in flat_bonuses:
		partes.append("%s +%.0f" % [Stat.name_of(stat), flat_bonuses[stat]])
	for stat: Stat.Id in percent_bonuses:
		partes.append("%s +%.0f%%" % [
			Stat.name_of(stat), float(percent_bonuses[stat]) * 100.0
		])
	return "%s [%s] %s" % [
		display_name if not display_name.is_empty() else String(id),
		Rarity.keys()[rarity].to_lower(),
		", ".join(partes),
	]
