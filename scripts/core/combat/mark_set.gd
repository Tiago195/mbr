class_name MarkSet
extends RefCounted

## Marcas com nome, prazo e acúmulo — o substrato de "estado sem efeito".
##
## A tradução do original topou com 114 buffs que não concedem atributo nenhum,
## não causam dano e não controlam — **62 deles têm literalmente só `Line`,
## `Rank` e `Duration`**, mais um efeito visual. São **marcadores**. O jogo consulta a marca em outro lugar —
## "já está marcado?", "acumulou três?", "está em qual postura?".
##
## Sem esta peça, esses buffs viravam nada na tradução, e com eles sumia uma
## camada inteira do design: a marca do caçador, o passo do combo, a postura da
## arma, o "não pode receber isto de novo por 10s" que o próprio Leo usa.
##
## É deliberadamente burro: guarda nome, contagem e prazo. Quem dá sentido é
## quem consulta — um `TriggerEffect` que espera `MARK_MAXED`, uma condição de
## habilidade, a IA. Marca que soubesse o que significa seria um sistema
## paralelo ao de efeitos, e é isso que `03-sistemas-de-jogo.md` proíbe.

signal applied(mark: StringName, stacks: int)
signal maxed(mark: StringName)
signal expired(mark: StringName)

class Entry extends RefCounted:
	var stacks: int = 1
	var max_stacks: int = 1
	var remaining: float = 0.0

	func is_permanent() -> bool:
		return remaining < 0.0

	func is_full() -> bool:
		return max_stacks > 0 and stacks >= max_stacks

var _marks: Dictionary = {}

## Aplica ou reforça uma marca.
##
## Reaplicar SOMA pilha e RENOVA o prazo — as duas coisas, e é a convenção que
## faz "acerte três vezes em 5 segundos" funcionar como o jogador espera. Um
## prazo que não renovasse tornaria o terceiro acerto refém do primeiro.
##
## Devolve quantas pilhas ficaram valendo.
func apply(
		mark: StringName,
		duration: float = 5.0,
		max_stacks: int = 1,
		stacks: int = 1
) -> int:
	var entry: Entry = _marks.get(mark)
	if entry == null:
		entry = Entry.new()
		entry.stacks = 0
		_marks[mark] = entry
	entry.max_stacks = maxi(max_stacks, 1)
	entry.remaining = duration
	entry.stacks = mini(entry.stacks + maxi(stacks, 1), entry.max_stacks)
	applied.emit(mark, entry.stacks)
	if entry.is_full():
		maxed.emit(mark)
	return entry.stacks

func has(mark: StringName) -> bool:
	return _marks.has(mark)

func stacks_of(mark: StringName) -> int:
	var entry: Entry = _marks.get(mark)
	return entry.stacks if entry != null else 0

func is_full(mark: StringName) -> bool:
	var entry: Entry = _marks.get(mark)
	return entry != null and entry.is_full()

func remaining(mark: StringName) -> float:
	var entry: Entry = _marks.get(mark)
	return entry.remaining if entry != null else 0.0

func count() -> int:
	return _marks.size()

## Tira uma marca inteira. Devolve se havia.
func clear(mark: StringName) -> bool:
	if not _marks.has(mark):
		return false
	_marks.erase(mark)
	expired.emit(mark)
	return true

## Gasta pilhas sem tirar a marca toda. Devolve quantas sobraram.
##
## É o caminho de "consome as marcas para causar dano extra": o consumidor tira
## o que precisa, e a marca só some quando zera.
func consume(mark: StringName, amount: int = 1) -> int:
	var entry: Entry = _marks.get(mark)
	if entry == null:
		return 0
	entry.stacks -= maxi(amount, 1)
	if entry.stacks <= 0:
		clear(mark)
		return 0
	return entry.stacks

func clear_all() -> void:
	for mark: StringName in _marks.keys():
		expired.emit(mark)
	_marks.clear()

## Avança os prazos. Devolve quantas marcas venceram.
func advance_time(delta: float) -> int:
	if _marks.is_empty():
		return 0
	var done: Array[StringName] = []
	for mark: StringName in _marks:
		var entry: Entry = _marks[mark]
		if entry.is_permanent():
			continue
		entry.remaining -= delta
		if entry.remaining <= 0.0:
			done.append(mark)
	for mark: StringName in done:
		_marks.erase(mark)
		expired.emit(mark)
	return done.size()
