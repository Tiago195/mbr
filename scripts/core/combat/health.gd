class_name Health
extends RefCounted

## Vida e escudos de um combatente — Fases 2.3 e 3.1.
##
## Continua em `core/`: emite sinal, não desenha. Quem observa decide o que
## fazer na tela.
##
## `Damage.resolve()` calcula sem alterar nada; é aqui que o resultado vira
## estado. A separação existe para o servidor poder resolver, validar e só
## então aplicar.

signal changed(current: float, maximum: float)
signal died()

var current: float = 0.0

## Total de escudo disponível. Soma das camadas ativas.
var shield: float:
	get:
		var total: float = 0.0
		for layer: Dictionary in _shields:
			total += layer["amount"]
		return total

var _stats: Stats

## Camadas de escudo, cada uma com prazo próprio. Lista e não float único
## porque `03-sistemas-de-jogo.md` especifica SHIELD com valor **e duração**:
## dois escudos de fontes diferentes expiram em momentos diferentes.
var _shields: Array[Dictionary] = []

func _init(stats: Stats) -> void:
	_stats = stats
	current = maximum()

func maximum() -> float:
	return _stats.get_value(Stat.Id.MAX_HEALTH)

func is_alive() -> bool:
	return current > 0.0

## 0.0 a 1.0. Serve para barra de vida e para IA decidir recuar.
func fraction() -> float:
	var max_value: float = maximum()
	if max_value <= 0.0:
		return 0.0
	return clampf(current / max_value, 0.0, 1.0)

## Aplica um resultado de dano já calculado.
##
## O clamp em zero mora aqui, não no cálculo: `Damage` devolve vida negativa
## de propósito, para que sobrekill continue mensurável.
func apply(result: DamageResult) -> void:
	var was_alive: bool = is_alive()
	_consume_shields(result.absorbed_by_shield)
	current = maxf(result.health_after, 0.0)
	changed.emit(current, maximum())
	if was_alive and not is_alive():
		died.emit()

## Gasta escudo começando pela camada que expira **antes**.
##
## A ordem importa: gastar a de prazo mais longo primeiro desperdiçaria a
## curta, que sumiria sem ter absorvido nada.
func _consume_shields(amount: float) -> void:
	var remaining: float = amount
	while remaining > 0.0 and not _shields.is_empty():
		var layer: Dictionary = _shields[0]
		var taken: float = minf(layer["amount"], remaining)
		layer["amount"] -= taken
		remaining -= taken
		if layer["amount"] <= 0.0:
			_shields.remove_at(0)
		else:
			break

func heal(amount: float) -> float:
	if amount <= 0.0 or not is_alive():
		return 0.0
	var before: float = current
	current = minf(current + amount, maximum())
	var restored: float = current - before
	if restored > 0.0:
		changed.emit(current, maximum())
	return restored

## Adiciona uma camada de escudo. `duration <= 0` é escudo sem prazo, que só
## sai quando consumido.
func add_shield(amount: float, duration: float = 0.0) -> void:
	if amount <= 0.0:
		return
	_shields.append({"amount": amount, "remaining": duration})
	_sort_shields()
	changed.emit(current, maximum())

## Avança o prazo das camadas e descarta as vencidas.
## Devolve quanto de escudo expirou sem ser usado.
func advance_time(delta: float) -> float:
	if _shields.is_empty():
		return 0.0
	var wasted: float = 0.0
	var kept: Array[Dictionary] = []
	for layer: Dictionary in _shields:
		if layer["remaining"] <= 0.0:
			kept.append(layer)
			continue
		layer["remaining"] -= delta
		if layer["remaining"] <= 0.0:
			wasted += layer["amount"]
		else:
			kept.append(layer)
	if wasted > 0.0:
		_shields = kept
		changed.emit(current, maximum())
	return wasted

## Camadas com prazo primeiro, da mais curta para a mais longa; as sem prazo
## no fim, porque não correm risco de sumir.
func _sort_shields() -> void:
	_shields.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_perm: bool = a["remaining"] <= 0.0
		var b_perm: bool = b["remaining"] <= 0.0
		if a_perm != b_perm:
			return not a_perm
		return a["remaining"] < b["remaining"]
	)

## Devolve ao estado inicial. Usado pelo boneco de treino ao renascer.
func reset() -> void:
	current = maximum()
	_shields.clear()
	changed.emit(current, maximum())
