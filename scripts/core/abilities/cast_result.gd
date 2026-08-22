class_name CastResult
extends RefCounted

## O que aconteceu numa tentativa de conjuração — Fase 3.2.
##
## O motivo da recusa é dado, não exceção: o cliente usa para mostrar
## "sem alcance" ou "silenciado" na tela, e o servidor usa para registrar
## tentativa inválida sem derrubar o tick.

enum Status {
	## Efeitos aplicados, recarga iniciada.
	SUCCESS,
	## Começou a conjuração; o efeito sai quando `cast_time` acabar.
	CASTING,
	ON_COOLDOWN,
	OUT_OF_RANGE,
	## A forma não pegou ninguém, e a habilidade precisa de alvo.
	NO_TARGET,
	## Stunado ou silenciado.
	CANNOT_CAST,
	## Conjurador morto.
	DEAD,
	## Já está conjurando outra coisa.
	BUSY,
	## Habilidade nula, sem efeitos, ou mira incoerente.
	INVALID,
	## Conjuração cortada no meio.
	INTERRUPTED,
}

var status: Status = Status.INVALID
var ability: Ability = null
var targets: Array[Unit] = []

## Segundos que faltam, quando recusada por recarga.
var cooldown_remaining: float = 0.0

func succeeded() -> bool:
	return status == Status.SUCCESS

func started() -> bool:
	return status == Status.CASTING

static func of(status: Status, ability: Ability = null) -> CastResult:
	var result := CastResult.new()
	result.status = status
	result.ability = ability
	return result

func _to_string() -> String:
	return "CastResult(%s, %d alvo(s))" % [Status.keys()[status], targets.size()]
