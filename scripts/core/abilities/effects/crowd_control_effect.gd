class_name CrowdControlEffect
extends AbilityEffect

## CROWD_CONTROL — stun, root, silence, disarm e slow.
##
## Os quatro primeiros são estados booleanos e vão para o `StatusSet`. O
## **slow** não: ele é um modificador percentual de `move_speed`, aplicado pelo
## mesmo sistema dos itens. Lentidão É um atributo reduzido por um tempo —
## modelá-la como estado próprio duplicaria a lógica de stacking e de expiração
## sem ganhar nada.
##
## O vocabulário do doc lista slow junto dos outros, então ele continua sendo
## uma opção deste efeito. A diferença é só de implementação.

## NÃO chamar este enum de `Control`: é o nome de uma classe embutida da Godot
## (o nó de UI), e `@export var control: Control` resolveria para ela em vez de
## para o enum. O erro aparece como "cannot be assigned to a variable of type
## Control", que não sugere colisão de nome nenhuma.
##
## Inclui SLOW, que `StatusSet.Kind` não tem — lentidão vira modificador de
## atributo, não estado.
enum Kind { STUN, ROOT, SILENCE, DISARM, SLOW }

@export var control: Kind = Kind.STUN
@export var duration: float = 1.0

## Só para SLOW. 0.3 = 30% mais lento.
@export_range(0.0, 1.0) var slow_amount: float = 0.3

@export var source_tag: StringName = &"habilidade"

func apply(_cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return
	if control == Kind.SLOW:
		target.stats.add_modifier(StatModifier.new(
			Stat.Id.MOVE_SPEED, StatModifier.Kind.PERCENT, -slow_amount,
			&"slow:%s" % source_tag, duration
		))
		return
	target.status.apply(_status_kind(), duration)

func _status_kind() -> StatusSet.Kind:
	match control:
		Kind.ROOT:
			return StatusSet.Kind.ROOT
		Kind.SILENCE:
			return StatusSet.Kind.SILENCE
		Kind.DISARM:
			return StatusSet.Kind.DISARM
		_:
			return StatusSet.Kind.STUN

func describe() -> String:
	if control == Kind.SLOW:
		return "lentidão de %.0f%% por %.1fs" % [slow_amount * 100.0, duration]
	return "%s por %.1fs" % [Kind.keys()[control].to_lower(), duration]
