class_name MarkEffect
extends AbilityEffect

## MARCA — põe (ou consome) um estado com nome, prazo e pilhas.
##
## Não faz nada sozinha, e é esse o ponto. Marca é o substrato de tudo que
## precisa de memória curta: "acerte três vezes e o quarto atordoa", "já
## recebeu o escudo, espere 10s", "está na postura de espada".
##
## Sem ela, cada uma dessas viraria uma classe própria. Com ela, viram um
## `MarkEffect` mais um `TriggerEffect` esperando `MARK_MAXED` — duas peças do
## vocabulário, zero código novo.
##
## Veio dos buffs do original que não concedem nada: nem atributo, nem dano,
## nem controle. **62 deles têm literalmente só `Line`, `Rank` e `Duration`**, e
## 114 caem no caso mais amplo (sem atributo, sem escudo, sem impacto). Depois
## de traduzidos viram **30 marcas distintas**, em 260 aplicações.
##
## Eram invisíveis para o tradutor e desapareciam.

enum Mode {
	## Põe a marca, ou soma uma pilha se já houver.
	APPLY,
	## Tira uma pilha. A marca some quando zera.
	CONSUME,
	## Tira a marca inteira, com quantas pilhas tiver.
	CLEAR,
}

@export var mark: StringName = &""
@export var mode: Mode = Mode.APPLY

## Segundos até sumir. Negativo dura até alguém tirar.
@export var duration: float = 5.0

## Teto de pilhas. Chegar nele emite `maxed`, que é o que um `TriggerEffect`
## de `MARK_MAXED` espera.
@export var max_stacks: int = 1

## Quantas pilhas por aplicação — ou quantas consumir.
@export var amount: int = 1

func apply(_cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive() or mark.is_empty():
		return
	match mode:
		Mode.CONSUME:
			target.marks.consume(mark, amount)
		Mode.CLEAR:
			target.marks.clear(mark)
		_:
			var antes: bool = target.marks.is_full(mark)
			target.marks.apply(mark, duration, max_stacks, amount)
			# O gatilho sai daqui, e não de dentro do `MarkSet`: aquele é
			# estrutura de dado e não conhece `TriggerSet`. Só dispara na
			# TRANSIÇÃO para cheio — senão toda reaplicação no teto dispararia
			# de novo, e "ao acumular três" viraria "a cada acerto depois de
			# três".
			if not antes and target.marks.is_full(mark):
				target.triggers.fire(TriggerSet.Event.MARK_MAXED, target, null)

func describe() -> String:
	match mode:
		Mode.CONSUME:
			return "consome %d de %s" % [amount, mark]
		Mode.CLEAR:
			return "limpa %s" % mark
		_:
			if max_stacks > 1:
				return "marca %s (%d/%d) por %.1fs" % [
					mark, amount, max_stacks, duration
				]
			return "marca %s por %.1fs" % [mark, duration]
