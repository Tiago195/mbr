class_name HealEffect
extends AbilityEffect

## HEAL — cura com escalonamento por atributo.

@export var base_heal: float = 0.0
@export var scaling_stat: Stat.Id = Stat.Id.ABILITY_POWER
@export var scaling_ratio: float = 0.0

func apply(cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return
	var amount: float = base_heal
	if cast.caster != null and scaling_ratio != 0.0:
		amount += cast.caster.stats.get_value(scaling_stat) * scaling_ratio
	target.receive_heal(amount)

func describe() -> String:
	return "cura %.0f" % base_heal
