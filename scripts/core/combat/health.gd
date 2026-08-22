class_name Health
extends RefCounted

## Vida e escudo de um combatente — Fase 2.3.
##
## Continua em `core/`: emite sinal, não desenha. Quem observa decide o que
## fazer na tela. Estende RefCounted, então roda em teste e no servidor
## headless.
##
## `Damage.resolve()` calcula sem alterar nada; é aqui que o resultado vira
## estado. A separação existe para o servidor poder resolver, validar e só
## então aplicar.

signal changed(current: float, maximum: float)
signal died()

var current: float = 0.0
var shield: float = 0.0

var _stats: Stats

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
## de propósito, para que sobrekill continue mensurável (útil para log de
## combate e para efeitos de execução).
func apply(result: DamageResult) -> void:
	var was_alive: bool = is_alive()
	shield = maxf(result.shield_after, 0.0)
	current = maxf(result.health_after, 0.0)
	changed.emit(current, maximum())
	if was_alive and not is_alive():
		died.emit()

func heal(amount: float) -> float:
	if amount <= 0.0 or not is_alive():
		return 0.0
	var before: float = current
	current = minf(current + amount, maximum())
	var healed: float = current - before
	if healed > 0.0:
		changed.emit(current, maximum())
	return healed

func add_shield(amount: float) -> void:
	if amount <= 0.0:
		return
	shield += amount
	changed.emit(current, maximum())

## Devolve ao estado inicial. Usado pelo boneco de treino ao renascer.
func reset() -> void:
	current = maximum()
	shield = 0.0
	changed.emit(current, maximum())
