class_name HealEffect
extends AbilityEffect

## HEAL — cura com escalonamento por atributo.

@export var base_heal: float = 0.0
@export var scaling_stat: Stat.Id = Stat.Id.ABILITY_POWER
@export var scaling_ratio: float = 0.0

## Fração da vida MÁXIMA DO ALVO que a cura recupera. 0.04 = 4%.
##
## Existe porque o original tem `HealPerMaxHP` e ela não é expressável pelo
## escalonamento normal: aquele lê atributo do conjurador, esta lê o alvo.
## Cura percentual é o que mantém um curandeiro relevante para um tanque de
## 3000 de vida sem torná-lo absurdo para um assassino de 900.
@export_range(0.0, 1.0) var percent_of_max_health: float = 0.0

func apply(cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return
	var amount: float = base_heal
	if cast.caster != null and scaling_ratio != 0.0:
		amount += cast.caster.stats.get_value(scaling_stat) * scaling_ratio
	if percent_of_max_health != 0.0:
		amount += target.health.maximum() * percent_of_max_health
	# Passar o conjurador é o que liga `heal_power` — sem isso só a
	# amplificação de quem recebe entraria na conta.
	target.receive_heal(amount, cast.caster)

func describe() -> String:
	if percent_of_max_health > 0.0:
		return "cura %.0f + %.1f%% da vida máxima" % [
			base_heal, percent_of_max_health * 100.0
		]
	return "cura %.0f" % base_heal
