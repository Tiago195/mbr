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
	## Sem mana. Valor novo no FIM: `Status` não é exportado para `.tres` hoje,
	## mas a disciplina é a mesma do resto e custa nada.
	NO_RESOURCE,
	## Suprema sem carga cheia. Também no fim, pela mesma disciplina.
	NO_CHARGE,
}

var status: Status = Status.INVALID
var ability: Ability = null
var targets: Array[Unit] = []

## O pulso que este resultado descreve, e onde ele se plantou.
##
## Existem porque a camada visual precisava saber O QUE desenhar e ONDE, e só
## tinha a habilidade inteira. Com isso ela desenhava `primary_pulse()` e mais
## nada — **79 dos 127** espaços de campeão carregam habilidade de vários
## golpes, e do segundo em diante nada aparecia na tela. A habilidade
## funcionava e parecia quebrada.
##
## Nulo no resultado agregado de uma conjuração; preenchido em cada `parts`.
var pulse: AbilityPulse = null
var anchor: Vector3 = Vector3.ZERO
## A direção mirada. O leque sai dela por `AbilityPulse.spread_directions()`.
var direction: Vector3 = Vector3.FORWARD

## Um resultado por pulso que saiu AGORA. Vazio nos resultados por pulso.
##
## Os pulsos atrasados não estão aqui: eles chegam depois, um por um, por
## `AbilityEngine.resolve_scheduled()`. É essa separação que deixa a tela
## mostrar cada golpe **quando ele acontece** em vez de anunciar todos na
## conjuração — anunciar entregaria ao adversário o que ele deveria aprender
## apanhando.
var parts: Array[CastResult] = []

## Quantos projéteis esta conjuração pôs no ar.
##
## Existe porque, com projétil que voa de verdade, `targets` vazio deixou de
## querer dizer "errou": quer dizer "ainda não se sabe". Sem separar os dois, o
## console anunciava erro toda vez que alguém atirava.
var launched: int = 0

## Segundos que faltam, quando recusada por recarga.
var cooldown_remaining: float = 0.0

## Carga que falta, quando recusada por `NO_CHARGE`.
var charge_missing: float = 0.0

func succeeded() -> bool:
	return status == Status.SUCCESS

func started() -> bool:
	return status == Status.CASTING

## Saiu alguma coisa que ainda vai acontecer. O resultado do tiro chega depois,
## por `AbilityEngine.advance_projectiles()`.
func in_flight() -> bool:
	return launched > 0

static func of(p_status: Status, p_ability: Ability = null) -> CastResult:
	var made := CastResult.new()
	made.status = p_status
	made.ability = p_ability
	return made

func _to_string() -> String:
	return "CastResult(%s, %d alvo(s))" % [Status.keys()[status], targets.size()]
