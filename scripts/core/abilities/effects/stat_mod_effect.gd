class_name StatModEffect
extends AbilityEffect

## STAT_MOD — altera um atributo por um tempo.
##
## Reusa `StatModifier`, o mesmo sistema que os itens usam. É o que
## `03-sistemas-de-jogo.md` pede ao dizer "não construa um segundo sistema
## paralelo": buff de habilidade e bônus de item são a mesma coisa com origens
## diferentes.

@export var stat: Stat.Id = Stat.Id.ATTACK_DAMAGE
@export var kind: StatModifier.Kind = StatModifier.Kind.FLAT
@export var value: float = 0.0
@export var duration: float = 5.0

@export_group("Acúmulo")
@export var stacks: bool = false
@export var max_stacks: int = 0

## Prefixo da origem. Vira `buff:<source_tag>`, o que permite remover tudo que
## veio desta habilidade sem tocar em modificador de item.
@export var source_tag: StringName = &"habilidade"

func apply(_cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return
	target.stats.add_modifier(StatModifier.new(
		stat, kind, value, &"buff:%s" % source_tag,
		duration, stacks, max_stacks
	))

func describe() -> String:
	var suffix: String = "%" if kind == StatModifier.Kind.PERCENT else ""
	return "%s %+.0f%s por %.1fs" % [Stat.name_of(stat), value, suffix, duration]
