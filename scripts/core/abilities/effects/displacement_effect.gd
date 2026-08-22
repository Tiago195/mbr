class_name DisplacementEffect
extends AbilityEffect

## DISPLACEMENT — dash, empurrão e puxão.
##
## Quem é deslocado vem de `recipient`, herdado da base. O `mode` daqui decide
## só a **direção**. Os dois eixos são independentes, e é isso que dá as
## combinações de graça:
##
##   dash        = recipient CASTER  + ALONG_AIM
##   empurrão    = recipient TARGETS + AWAY_FROM_CASTER
##   puxão       = recipient TARGETS + TOWARD_CASTER
##   "vendaval"  = recipient TARGETS + ALONG_AIM  (empurra todos na direção
##                 da mira, e não para longe de mim)
##
## Não move ninguém: **acumula** o deslocamento em `pending_displacement` e
## devolve o controle. Quem move é a camada de gameplay, que tem física e sabe
## o que fazer quando o dash bate numa parede. Resolver colisão aqui exigiria
## conhecer a engine, que é justamente o que `core/` evita.

enum Mode {
	## Na direção da mira.
	ALONG_AIM,
	## Para longe do conjurador.
	AWAY_FROM_CASTER,
	## Na direção do conjurador.
	TOWARD_CASTER,
}

@export var mode: Mode = Mode.ALONG_AIM
@export var distance: float = 4.0

## Se verdadeiro, o deslocamento ignora imobilização (root). Dash de fuga
## normalmente não ignora; empurrão sofrido, sim.
@export var ignores_root: bool = false

func apply(cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return
	if not ignores_root and not target.can_move():
		return
	target.pending_displacement += _direction(cast, target) * distance

func _direction(cast: AbilityCast, target: Unit) -> Vector3:
	match mode:
		Mode.AWAY_FROM_CASTER:
			return _away_from(cast.caster, target)
		Mode.TOWARD_CASTER:
			return -_away_from(cast.caster, target)
		_:
			return cast.direction

## Direção do conjurador para o alvo, achatada. Cai na direção da mira quando
## os dois ocupam o mesmo ponto — sem isso, empurrar alguém colado produziria
## um vetor zero.
func _away_from(caster: Unit, target: Unit) -> Vector3:
	if caster == null:
		return Vector3.FORWARD
	var flat: Vector3 = target.position - caster.position
	flat.y = 0.0
	if flat.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return flat.normalized()

func describe() -> String:
	return "deslocamento %s de %.1fm" % [Mode.keys()[mode].to_lower(), distance]
