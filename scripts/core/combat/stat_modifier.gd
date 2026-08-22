class_name StatModifier
extends RefCounted

## Um modificador de atributo com origem rastreável — Fase 2.1.
##
## A `source` é o que torna possível desequipar um item e devolver os atributos
## exatamente ao estado anterior: remove-se por origem, não por valor. Dois
## itens que dão ambos `+30 attack_damage` são indistinguíveis pelo valor, mas
## não pela origem.

enum Kind {
	## Somado ao valor base. `+30 attack_damage`.
	FLAT,
	## Fração aplicada depois de todos os flats. `0.15` = +15%.
	PERCENT,
}

var stat: Stat.Id
var kind: Kind
var value: float

## De onde veio. Ex.: &"item:espada_longa", &"buff:fúria", &"nivel".
var source: StringName

## Segundos restantes. <= 0 significa permanente (item equipado, bônus de
## nível), que só sai por remoção explícita.
var duration: float

## Se falso, aplicar de novo a mesma origem para o mesmo atributo substitui em
## vez de somar — o caso comum de um buff que "reseta a duração".
var stacks: bool

## Teto de acúmulo quando `stacks` é verdadeiro. 0 = sem limite.
var max_stacks: int

func _init(
		p_stat: Stat.Id,
		p_kind: Kind,
		p_value: float,
		p_source: StringName,
		p_duration: float = 0.0,
		p_stacks: bool = false,
		p_max_stacks: int = 0
) -> void:
	stat = p_stat
	kind = p_kind
	value = p_value
	source = p_source
	duration = p_duration
	stacks = p_stacks
	max_stacks = p_max_stacks

func is_permanent() -> bool:
	return duration <= 0.0

## Dois modificadores ocupam o mesmo "slot" de acúmulo quando vêm da mesma
## origem e mexem no mesmo atributo do mesmo jeito.
func same_slot_as(other: StatModifier) -> bool:
	return source == other.source and stat == other.stat and kind == other.kind

func _to_string() -> String:
	var suffix: String = "%" if kind == Kind.PERCENT else ""
	return "StatModifier(%s %s%s from '%s')" % [
		Stat.name_of(stat), value, suffix, source
	]
