class_name ResourceEffect
extends AbilityEffect

## RECURSO — devolve ou queima mana.
##
## O original tem `ImpactStatType: Mana` em 52 impactos, com valores dos dois
## sinais: negativos são o custo cobrado pelo próprio impacto, positivos são
## poção e habilidade de suporte que devolvem recurso.
##
## Devolver e queimar são o mesmo efeito com sinal trocado, mas passam por
## caminhos diferentes no pote: devolver respeita o teto, queimar leva o que
## houver sem poder ser recusado.

@export var amount: float = 0.0

## Fração da mana MÁXIMA do alvo. Soma-se ao valor fixo. Existe pelo mesmo
## motivo da cura percentual: um número fixo que é generoso para quem tem 200
## de mana é irrelevante para quem tem 900.
@export_range(-1.0, 1.0) var percent_of_max: float = 0.0

func apply(_cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return
	var total: float = amount + target.mana.maximum() * percent_of_max
	if total > 0.0:
		target.mana.restore(total)
	elif total < 0.0:
		target.mana.drain(-total)

func describe() -> String:
	var total: String = "%+.0f" % amount
	if percent_of_max != 0.0:
		total += " %+.0f%% do máximo" % (percent_of_max * 100.0)
	return "mana %s" % total
