class_name DisplacementEffect
extends AbilityEffect

## DISPLACEMENT — dash, empurrão e puxão.
##
## Não move ninguém: **acumula** o deslocamento pedido em `pending_displacement`
## e devolve o controle. Quem move é a camada de gameplay, que tem física e
## sabe o que fazer quando o dash bate numa parede.
##
## Resolver colisão aqui exigiria conhecer a engine, que é justamente o que
## `core/` evita — e é o que permite o servidor headless rodar o mesmo código.

enum Mode {
	## Empurra o CONJURADOR na direção da mira.
	DASH,
	## Empurra o ALVO para longe do conjurador.
	KNOCKBACK,
	## Puxa o ALVO na direção do conjurador.
	PULL,
}

@export var mode: Mode = Mode.DASH
@export var distance: float = 4.0

## Se verdadeiro, o deslocamento ignora imobilização (root). Dash de fuga
## normalmente não ignora; empurrão sofrido, sim.
@export var ignores_root: bool = false

func apply(cast: AbilityCast, target: Unit) -> void:
	match mode:
		Mode.DASH:
			_push(cast.caster, cast.direction * distance)
		Mode.KNOCKBACK:
			if target == null:
				return
			_push(target, _away_from(cast.caster, target) * distance)
		Mode.PULL:
			if target == null:
				return
			_push(target, -_away_from(cast.caster, target) * distance)

func needs_target() -> bool:
	# Dash age no próprio conjurador: não faz sentido descartar a conjuração
	# só porque a forma não pegou ninguém.
	return mode != Mode.DASH

func _push(unit: Unit, delta: Vector3) -> void:
	if unit == null or not unit.is_alive():
		return
	if not ignores_root and not unit.can_move():
		return
	unit.pending_displacement += delta

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
	return "%s de %.1fm" % [Mode.keys()[mode].to_lower(), distance]
