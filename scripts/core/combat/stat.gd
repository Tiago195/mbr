class_name Stat
extends RefCounted

## Catálogo de atributos — Fase 2.1.
##
## Nada em `scripts/core/` pode importar nó da engine. Esta classe estende
## RefCounted, não Node, de propósito: ela roda em teste unitário e no servidor
## headless sem árvore de cena.
##
## O identificador é um enum, não uma string: erro de digitação vira erro de
## compilação em vez de atributo silenciosamente zerado. Para arquivos de
## configuração de item e habilidade, que precisam nomear atributos em texto,
## `from_name()` faz a ponte.

enum Id {
	MAX_HEALTH,
	HEALTH_REGEN,
	ATTACK_DAMAGE,
	ABILITY_POWER,
	ARMOR,
	MAGIC_RESIST,
	ATTACK_SPEED,
	ATTACK_RANGE,
	MOVE_SPEED,
	CRIT_CHANCE,
	CRIT_DAMAGE,
	LIFESTEAL,
	SPELL_VAMP,
	COOLDOWN_REDUCTION,
	# Penetração não está na tabela de `03-sistemas-de-jogo.md`, mas o passo 4
	# do cálculo de dano depende dela. Adicionada aqui para não precisar de um
	# canal paralelo de atributos depois.
	ARMOR_PEN_FLAT,
	ARMOR_PEN_PERCENT,
	MAGIC_PEN_FLAT,
	MAGIC_PEN_PERCENT,
}

const NAMES: Dictionary = {
	Id.MAX_HEALTH: &"max_health",
	Id.HEALTH_REGEN: &"health_regen",
	Id.ATTACK_DAMAGE: &"attack_damage",
	Id.ABILITY_POWER: &"ability_power",
	Id.ARMOR: &"armor",
	Id.MAGIC_RESIST: &"magic_resist",
	Id.ATTACK_SPEED: &"attack_speed",
	Id.ATTACK_RANGE: &"attack_range",
	Id.MOVE_SPEED: &"move_speed",
	Id.CRIT_CHANCE: &"crit_chance",
	Id.CRIT_DAMAGE: &"crit_damage",
	Id.LIFESTEAL: &"lifesteal",
	Id.SPELL_VAMP: &"spell_vamp",
	Id.COOLDOWN_REDUCTION: &"cooldown_reduction",
	Id.ARMOR_PEN_FLAT: &"armor_pen_flat",
	Id.ARMOR_PEN_PERCENT: &"armor_pen_percent",
	Id.MAGIC_PEN_FLAT: &"magic_pen_flat",
	Id.MAGIC_PEN_PERCENT: &"magic_pen_percent",
}

## Valores neutros. Um personagem sem nenhum atributo definido não deve morrer
## de divisão por zero nem crititar sempre.
const DEFAULTS: Dictionary = {
	Id.MAX_HEALTH: 100.0,
	Id.CRIT_DAMAGE: 1.75,
	Id.ATTACK_SPEED: 1.0,
}

static func name_of(id: Id) -> StringName:
	return NAMES[id]

## Converte o nome usado em arquivo de configuração no identificador.
## Devolve -1 quando o nome não existe — quem chama decide se isso é erro
## de dado ou entrada opcional.
static func from_name(stat_name: StringName) -> int:
	for id: Id in NAMES:
		if NAMES[id] == stat_name:
			return id
	return -1

## Valor de um atributo quando ninguém o definiu.
static func default_of(id: Id) -> float:
	return DEFAULTS.get(id, 0.0)
