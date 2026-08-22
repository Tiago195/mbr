class_name TriggerEffect
extends AbilityEffect

## TRIGGER — arma um efeito que espera um evento.
##
## Estava no vocabulário de `03-sistemas-de-jogo.md` desde o começo e não
## existia. A tradução do original tornou obrigatório: passiva de campeão é
## quase toda feita disto, e sem o gatilho ela viraria "um buff que dá stats",
## perdendo o que a torna interessante.
##
## Mesmo desenho do periódico: **embrulha** outros efeitos. Quem decide o que
## acontece são eles; aqui só mora o quando.

## Que evento acorda os efeitos.
@export var event: TriggerSet.Event = TriggerSet.Event.BASIC_ATTACK_HIT

## O que sai quando o evento acontece.
@export var effects: Array[AbilityEffect] = []

## O que sai quando o gatilho termina — cargas gastas ou prazo vencido.
## É como se expressa "quando a marca acabar, ela explode".
@export var on_expire: Array[AbilityEffect] = []

## Quantas vezes dispara. 0 = ilimitado enquanto durar.
@export var charges: int = 0

## Segundos de validade. Negativo = até gastar as cargas; com 0 cargas e
## duração negativa o gatilho é permanente, que é o caso de passiva de campeão
## e de item equipado.
@export var duration: float = -1.0

@export var source_tag: StringName = &"habilidade"

func apply(cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive() or effects.is_empty():
		return
	var source: StringName = &"gatilho:%s" % source_tag
	# Rearmar substitui. Dois gatilhos idênticos na mesma origem disparariam
	# em dobro, e a segunda conjuração da mesma habilidade parecendo mais
	# forte que a primeira é o tipo de bug que só aparece em teste de jogo.
	target.triggers.remove_source(source)
	target.triggers.arm(
		event, effects, source, duration, charges, cast.caster, on_expire
	)

func describe() -> String:
	var parts: PackedStringArray = []
	for effect: AbilityEffect in effects:
		if effect != null:
			parts.append(effect.describe())
	var limit: String = "" if charges <= 0 else " (%dx)" % charges
	return "ao %s%s: %s" % [
		TriggerSet.Event.keys()[event].to_lower(), limit, ", ".join(parts)
	]
