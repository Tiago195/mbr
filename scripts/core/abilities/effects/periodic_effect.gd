class_name PeriodicEffect
extends AbilityEffect

## PERIÓDICO — veneno, queimadura, regeneração, aura.
##
## Não faz nada por si: **embrulha** outros efeitos e os reaplica a cada
## intervalo. É por isso que não é um "efeito de dano ao longo do tempo": um
## periódico de `DamageEffect` é veneno, de `HealEffect` é regeneração, de
## `StatModEffect` é uma aura que renova. Um efeito só, três mecânicas — que é
## a regra do projeto sobre habilidade nova não escrever classe nova.
##
## É assim que o original faz: lá, veneno é um `Buff` com `LoopInterval` que
## carrega um `Impact`, e o impacto é a mesma coisa que qualquer outro impacto.

## Os efeitos que saem a cada tique. Aninhar `PeriodicEffect` dentro de
## `PeriodicEffect` funciona e é uma péssima ideia — o número de tiques
## multiplica.
@export var effects: Array[AbilityEffect] = []

## Segundos entre tiques.
@export var interval: float = 1.0

## Segundos de duração total. Negativo dura até alguém remover pela origem —
## é o caso da aura de item equipado.
@export var duration: float = 3.0

## Se o primeiro tique sai na hora de aplicar ou só depois de um intervalo.
## As duas convenções existem no original e a diferença é de um tique inteiro,
## que em veneno de 3 tiques é um terço do dano.
@export var ticks_on_apply: bool = false

## Reaplicar substitui em vez de somar. É a convenção de veneno: acertar duas
## vezes renova, não empilha dois venenos. Desligue para acúmulo explícito.
@export var refreshes: bool = true

@export var source_tag: StringName = &"habilidade"

func apply(cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive() or effects.is_empty():
		return
	var source: StringName = &"periodico:%s" % source_tag
	if refreshes:
		target.periodic.remove_source(source)
	target.periodic.add(
		effects, interval, duration, source, cast.caster, ticks_on_apply
	)

## Um periódico de `HealEffect` cura o alvo e não depende de quem ele é, mas o
## que decide se a conjuração pode sair sem acertar ninguém continua sendo o
## destinatário — a base já responde certo.
func describe() -> String:
	var parts: PackedStringArray = []
	for effect: AbilityEffect in effects:
		if effect != null:
			parts.append(effect.describe())
	return "a cada %.1fs por %.1fs: %s" % [
		interval, duration, ", ".join(parts)
	]
