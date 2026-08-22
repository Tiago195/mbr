class_name AbilityBook
extends RefCounted

## As habilidades de um combatente, suas recargas e a conjuração em curso —
## Fase 3.2.
##
## Um objeto por combatente. Fica fora do `Unit` de propósito: mob e torre têm
## vida e atributos mas nem sempre têm habilidades, e nem todo `Unit` precisa
## carregar um livro vazio.
##
## Não guarda referência ao dono — quem chama passa o `Unit`. Evita o ciclo
## entre RefCounted que já vazou memória neste projeto (ver `unit.gd`).

## Índices de slot, seguindo o esquema do LoL.
enum Slot { Q, W, E, R }

var _slots: Dictionary = {}
var _cooldowns: Dictionary = {}

## Conjuração em curso: { "ability": Ability, "cast": AbilityCast,
## "remaining": float }. Vazio quando não há.
var _pending: Dictionary = {}

# ---------------------------------------------------------------- slots

func learn(slot: Slot, ability: Ability) -> void:
	_slots[slot] = ability

func forget(slot: Slot) -> void:
	_slots.erase(slot)

func ability_in(slot: Slot) -> Ability:
	return _slots.get(slot, null) as Ability

func known_abilities() -> Array[Ability]:
	var found: Array[Ability] = []
	for slot: Slot in _slots:
		var ability := _slots[slot] as Ability
		if ability != null:
			found.append(ability)
	return found

# ---------------------------------------------------------------- recarga

func is_ready(ability: Ability) -> bool:
	return remaining_cooldown(ability) <= 0.0

func remaining_cooldown(ability: Ability) -> float:
	if ability == null:
		return 0.0
	return _cooldowns.get(ability.id, 0.0)

func start_cooldown(ability: Ability, caster: Unit) -> void:
	if ability == null:
		return
	_cooldowns[ability.id] = ability.cooldown_for(caster)

## Tira segundos da recarga de uma habilidade. Efeito de item ou passiva.
func reduce_cooldown(ability: Ability, seconds: float) -> void:
	if ability == null or not _cooldowns.has(ability.id):
		return
	_cooldowns[ability.id] = maxf(0.0, _cooldowns[ability.id] - seconds)

func clear_cooldowns() -> void:
	_cooldowns.clear()

# ---------------------------------------------------------------- conjuração

func is_casting() -> bool:
	return not _pending.is_empty()

func casting_ability() -> Ability:
	return _pending.get("ability", null) as Ability

func casting_remaining() -> float:
	return _pending.get("remaining", 0.0)

## Registra uma conjuração com tempo. A recarga já começa aqui: no LoL, cortar
## a conjuração de alguém não devolve a habilidade.
func begin_cast(ability: Ability, cast: AbilityCast, caster: Unit) -> void:
	_pending = {
		"ability": ability,
		"cast": cast,
		"remaining": ability.cast_time,
	}
	start_cooldown(ability, caster)

## Verdadeiro quando o tempo de conjuração acabou e o efeito deve sair.
func cast_is_ready() -> bool:
	return is_casting() and float(_pending["remaining"]) <= 0.0

## Entrega a conjuração pronta e limpa o estado. Devolve vazio se não houver.
func take_pending() -> Dictionary:
	var pending: Dictionary = _pending
	_pending = {}
	return pending

## Corta a conjuração em curso. Devolve o que foi cortado, ou vazio.
func interrupt() -> Dictionary:
	return take_pending()

# ---------------------------------------------------------------- tempo

## Avança recargas e o tempo de conjuração.
##
## Interrompe sozinho quando o conjurador perde a capacidade de conjurar —
## stun no meio da conjuração corta, que é a regra que
## `03-sistemas-de-jogo.md` manda definir uma vez no sistema e não por
## habilidade.
func advance_time(delta: float, caster: Unit = null) -> void:
	var finished: Array = []
	for id: StringName in _cooldowns:
		_cooldowns[id] -= delta
		if _cooldowns[id] <= 0.0:
			finished.append(id)
	for id: StringName in finished:
		_cooldowns.erase(id)

	if not is_casting():
		return
	if caster != null and not caster.can_cast():
		interrupt()
		return
	_pending["remaining"] = float(_pending["remaining"]) - delta
