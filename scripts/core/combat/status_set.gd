class_name StatusSet
extends RefCounted

## Controles de grupo ativos num combatente — Fase 3.1.
##
## Só os estados **booleanos** moram aqui. Lentidão (`slow`) NÃO é um deles:
## é um modificador percentual de `move_speed`, aplicado pelo mesmo sistema de
## `StatModifier` que os itens usam. `03-sistemas-de-jogo.md` é explícito sobre
## não construir um segundo sistema paralelo, e lentidão é literalmente um
## atributo reduzido por um tempo.

enum Kind {
	## Não anda, não ataca, não conjura.
	STUN,
	## Não anda. Ataca e conjura normalmente.
	ROOT,
	## Não conjura. Anda e ataca.
	SILENCE,
	## Não ataca. Anda e conjura.
	DISARM,
}

signal applied(kind: Kind, duration: float)
signal expired(kind: Kind)

var _remaining: Dictionary = {}

## Aplica um controle. Reaplicar não soma duração: prevalece a **maior
## restante**. É a convenção de MOBA — dois stuns de 1s seguidos não viram um
## de 2s, senão foco de time viraria prisão perpétua.
func apply(kind: Kind, duration: float) -> void:
	if duration <= 0.0:
		return
	var current: float = _remaining.get(kind, 0.0)
	if duration <= current:
		return
	_remaining[kind] = duration
	applied.emit(kind, duration)

func has(kind: Kind) -> bool:
	return _remaining.get(kind, 0.0) > 0.0

func remaining(kind: Kind) -> float:
	return _remaining.get(kind, 0.0)

func is_clear() -> bool:
	return _remaining.is_empty()

func clear(kind: Kind) -> void:
	if _remaining.erase(kind):
		expired.emit(kind)

func clear_all() -> void:
	for kind: Kind in _remaining.keys():
		expired.emit(kind)
	_remaining.clear()

## Avança as durações. Devolve quantos expiraram.
func advance_time(delta: float) -> int:
	if _remaining.is_empty():
		return 0
	var done: Array = []
	for kind: Kind in _remaining:
		_remaining[kind] -= delta
		if _remaining[kind] <= 0.0:
			done.append(kind)
	for kind: Kind in done:
		_remaining.erase(kind)
		expired.emit(kind)
	return done.size()
