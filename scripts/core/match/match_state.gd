class_name MatchState
extends RefCounted

## O estado de uma partida — Fase 5.4.
##
## Sabe quem entrou, quem morreu, em que colocação, e quando acabou. Governa a
## zona: é ela quem avança o relógio, porque a zona não deve rodar antes da
## partida começar nem depois de acabar.
##
## Lógica pura. O servidor autoritativo roda isto; o cliente recebe o
## resultado. Nenhum nó, nenhuma física.

signal started()
signal eliminated(unit: Unit, placement: int)
signal finished(winner: Unit)

enum Phase { LOBBY, PLAYING, OVER }

## Colocação de quem morreu, do último ao primeiro. O primeiro a morrer fica
## com a pior colocação — é a convenção de battle royale, e é o que permite
## anunciar "você ficou em 7º de 8" no instante da morte.
var placements: Dictionary = {}

var phase: Phase = Phase.LOBBY
var zone: Zone
var winner: Unit = null

var _all: Array = []
var _alive: Array = []
var _elapsed: float = 0.0

func _init(units: Array = [], match_zone: Zone = null) -> void:
	_all = units.duplicate()
	_alive = units.duplicate()
	zone = match_zone

# ---------------------------------------------------------------- consulta

func total_players() -> int:
	return _all.size()

func alive_count() -> int:
	return _alive.size()

func alive() -> Array:
	return _alive.duplicate()

func elapsed() -> float:
	return _elapsed

func is_over() -> bool:
	return phase == Phase.OVER

func placement_of(unit: Unit) -> int:
	return placements.get(unit, 0)

# ---------------------------------------------------------------- ciclo

func start() -> void:
	if phase != Phase.LOBBY:
		return
	phase = Phase.PLAYING
	_elapsed = 0.0
	if zone != null:
		zone.start()
	started.emit()
	# Partida com um jogador só já nasce decidida.
	_check_end()

## Um tick da partida. Avança tempo, zona, dano de zona, e confere o fim.
##
## A ordem importa: a zona machuca ANTES da checagem de fim, senão a morte
## causada pela zona só seria contabilizada um tick depois — e num tick de
## 50 ms isso é a diferença entre anunciar o vencedor certo ou não.
func advance_time(delta: float) -> void:
	if phase != Phase.PLAYING:
		return
	_elapsed += delta

	if zone != null:
		zone.advance_time(delta)
		zone.damage_outsiders(_alive, delta)

	_collect_deaths()
	_check_end()

## Tira do vivo quem morreu desde o último tick, atribuindo colocação.
##
## Varre em vez de escutar o sinal de morte de cada um: escutar exigiria o
## `MatchState` guardar uma referência de volta em cada `Unit`, e referência
## cruzada entre RefCounted é o ciclo que já vazou memória neste projeto.
func _collect_deaths() -> void:
	var ainda_vivos: Array = []
	var mortos: Array = []
	for candidato: Variant in _alive:
		var unit := candidato as Unit
		if unit != null and unit.is_alive():
			ainda_vivos.append(unit)
		elif unit != null:
			mortos.append(unit)

	if mortos.is_empty():
		return

	# Colocação = quantos restam depois desta leva, mais um por morto ainda
	# não processado. Mortos no mesmo tick dividem a faixa e recebem a mesma
	# colocação — não há como ordenar dentro de um tick, e inventar ordem
	# seria pior que empatar.
	var colocacao: int = ainda_vivos.size() + mortos.size()
	for morto: Variant in mortos:
		placements[morto] = colocacao
		eliminated.emit(morto, colocacao)

	_alive = ainda_vivos

func _check_end() -> void:
	if _alive.size() > 1:
		return
	phase = Phase.OVER
	if _alive.size() == 1:
		winner = _alive[0] as Unit
		placements[winner] = 1
	finished.emit(winner)
