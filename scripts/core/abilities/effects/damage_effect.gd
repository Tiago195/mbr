class_name DamageEffect
extends AbilityEffect

## DAMAGE — dano com escalonamento por atributo.
##
## `base + atributo * proporção` é a forma canônica de MOBA: um valor fixo que
## domina cedo, mais uma fração de um atributo que domina tarde. Manter os dois
## separados é o que permite balancear início e fim de partida de forma
## independente.

@export var base_damage: float = 0.0

## De qual atributo do CONJURADOR o dano escala.
@export var scaling_stat: Stat.Id = Stat.Id.ABILITY_POWER

## Quanto do atributo entra. 0.6 = 60% do poder de habilidade.
@export var scaling_ratio: float = 0.0

@export var damage_type: Damage.Type = Damage.Type.MAGIC

func apply(cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return
	target.receive_damage(
		cast.caster, _raw_for(cast.caster), damage_type, Damage.Source.ABILITY
	)

func _raw_for(caster: Unit) -> float:
	var raw: float = base_damage
	if caster != null and scaling_ratio != 0.0:
		raw += caster.stats.get_value(scaling_stat) * scaling_ratio
	return raw

func describe() -> String:
	if scaling_ratio == 0.0:
		return "dano %.0f" % base_damage
	return "dano %.0f + %.0f%% de %s" % [
		base_damage, scaling_ratio * 100.0, Stat.name_of(scaling_stat)
	]
