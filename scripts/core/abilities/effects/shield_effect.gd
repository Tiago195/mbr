class_name ShieldEffect
extends AbilityEffect

## SHIELD — escudo temporário.
##
## `duration <= 0` cria escudo sem prazo, que só sai quando consumido.

@export var base_shield: float = 0.0
@export var scaling_stat: Stat.Id = Stat.Id.ABILITY_POWER
@export var scaling_ratio: float = 0.0
@export var duration: float = 3.0

func apply(cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return
	var amount: float = base_shield
	if cast.caster != null and scaling_ratio != 0.0:
		amount += cast.caster.stats.get_value(scaling_stat) * scaling_ratio
	target.health.add_shield(amount, duration)

func describe() -> String:
	return "escudo %.0f por %.1fs" % [base_shield, duration]
