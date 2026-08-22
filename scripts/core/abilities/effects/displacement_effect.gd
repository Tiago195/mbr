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
	## Direto para o ponto mirado, qualquer que seja a distância. É o `Warp` e
	## o `MoveToPosition` do original — teleporte, não corrida.
	##
	## Entra como MODO e não como efeito novo porque a diferença entre correr
	## 6 metros e aparecer a 6 metros, no nosso modelo, é só o vetor: quem
	## resolve colisão pelo caminho é a camada de gameplay, e é lá que a
	## distinção importa. `distance` é ignorada neste modo.
	TO_AIM_POINT,
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
	if mode == Mode.TO_AIM_POINT:
		# Vetor absoluto até o ponto, não direção vezes distância. Massa não
		# resiste a teleporte: ou vai, ou não vai.
		var salto: Vector3 = cast.point - target.position
		salto.y = 0.0
		target.pending_displacement += salto
		return
	target.pending_displacement += _direction(cast, target) * _distance_for(target)

## Massa resiste a deslocamento IMPOSTO, não ao próprio.
##
## O critério é o destinatário, não o modo: `recipient == CASTER` é o dash, e
## dash é movimento que o personagem escolheu — pesar mais não deve encurtá-lo.
## `recipient == TARGETS` é empurrão, puxão ou vendaval sofrido, e aí peso é
## exatamente o que deve segurar. O original tem `Weight` como atributo, e é
## esta a leitura que dá a ele um contrajogo.
func _distance_for(target: Unit) -> float:
	if recipient == Recipient.CASTER:
		return distance
	var weight: float = maxf(target.stats.get_value(Stat.Id.WEIGHT), 0.1)
	return distance / weight

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
	if mode == Mode.TO_AIM_POINT:
		return "teleporte para o ponto mirado"
	return "deslocamento %s de %.1fm" % [Mode.keys()[mode].to_lower(), distance]
