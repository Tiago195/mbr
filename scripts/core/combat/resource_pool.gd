class_name ResourcePool
extends RefCounted

## Mana — o recurso de conjuração, trazido pela tradução do original.
##
## `skill_xml` tem `CostType` em 684 habilidades e o valor é sempre
## `ManaCost`. Sem um pote de recurso, todo custo de habilidade do original
## seria descartado na tradução, e com ele some uma camada inteira de decisão:
## qual habilidade vale a pena gastar agora.
##
## É a mesma forma de `Health` — atual, máximo vindo de `Stats`, regeneração
## por segundo — mas sem escudo, sem morte e sem mitigação. Herdar de `Health`
## para reaproveitar três linhas traria junto `died`, `_shields` e `apply()`,
## que não fazem sentido nenhum aqui.

signal changed(current: float, maximum: float)

var current: float = 0.0

var _stats: Stats

func _init(stats: Stats) -> void:
	_stats = stats
	current = maximum()

func maximum() -> float:
	return _stats.get_value(Stat.Id.MAX_MANA)

## 0.0 a 1.0. Personagem sem mana nenhuma devolve 1.0, não 0.0 — a barra dele
## não deve aparecer vazia, deve não aparecer, e quem desenha decide isso pelo
## máximo ser zero.
func fraction() -> float:
	var max_value: float = maximum()
	if max_value <= 0.0:
		return 1.0
	return clampf(current / max_value, 0.0, 1.0)

## Personagem sem mana máxima conjura de graça. É o que permite um campeão
## sem recurso — e um boneco de treino — usarem o mesmo `AbilityBook` sem um
## caso especial em cada chamada.
func can_afford(cost: float) -> bool:
	if cost <= 0.0 or maximum() <= 0.0:
		return true
	return current >= cost

## Gasta se der. Devolve se gastou — quem chama usa isso para recusar a
## conjuração, e a recusa tem que acontecer ANTES de qualquer efeito sair.
func spend(cost: float) -> bool:
	if not can_afford(cost):
		return false
	if cost <= 0.0 or maximum() <= 0.0:
		return true
	current = maxf(current - cost, 0.0)
	changed.emit(current, maximum())
	return true

## Devolve quanto entrou de fato — o excedente acima do máximo é perdido.
func restore(amount: float) -> float:
	if amount <= 0.0 or maximum() <= 0.0:
		return 0.0
	var before: float = current
	current = minf(current + amount, maximum())
	var gained: float = current - before
	if gained > 0.0:
		changed.emit(current, maximum())
	return gained

## Drena sem a checagem de `spend()`. É o caminho de um efeito hostil que
## queima mana: ele não pode ser recusado por não haver o bastante, só levar
## o que houver.
func drain(amount: float) -> float:
	if amount <= 0.0 or maximum() <= 0.0:
		return 0.0
	var taken: float = minf(current, amount)
	current -= taken
	if taken > 0.0:
		changed.emit(current, maximum())
	return taken

## Regeneração por segundo, vinda do atributo.
func advance_time(delta: float) -> void:
	var regen: float = _stats.get_value(Stat.Id.MANA_REGEN)
	if regen != 0.0:
		restore(regen * delta)

func reset() -> void:
	current = maximum()
	changed.emit(current, maximum())
