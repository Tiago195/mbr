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

## Um pulso marcado para sair mais tarde.
##
## Existe porque uma habilidade do original tem golpes com tempos diferentes
## dentro da mesma conjuração — o `StartTime` de cada `Impact`. O livro é quem
## guarda, e não a engine, porque a engine é estática e sem estado de
## propósito: é ela que roda igual no cliente e no servidor.
class Scheduled extends RefCounted:
	var ability: Ability
	var pulse: AbilityPulse
	var cast: AbilityCast
	## Onde a forma se planta. Calculada na conjuração e congelada: um pulso
	## atrasado que recalculasse a âncora seguiria o alvo que fugiu, e área no
	## chão não persegue ninguém.
	var anchor: Vector3 = Vector3.ZERO
	var remaining: float = 0.0
	## Quantas saídas ainda faltam, contando a atual.
	var repeats_left: int = 1

var _scheduled: Array[Scheduled] = []

# ---------------------------------------------------------------- slots

## Aprende uma habilidade num espaço.
##
## `owner` é opcional só por compatibilidade com quem não tem passiva de
## ranque; passá-lo é o certo, porque é o que aplica `passive_effects` — o
## bônus que a habilidade dá **por existir**, e que sobe junto com o ranque.
##
## Aprender por cima esquece a anterior primeiro: sem isso, subir de ranque
## empilharia o bônus dos dois.
func learn(slot: Slot, ability: Ability, owner: Unit = null) -> void:
	forget(slot, owner)
	_slots[slot] = ability
	if ability != null and owner != null:
		ability.apply_passives(owner)

func forget(slot: Slot, owner: Unit = null) -> void:
	var anterior := _slots.get(slot, null) as Ability
	if anterior != null and owner != null:
		anterior.remove_passives(owner)
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

## Atende os ajustes de recarga que efeitos deixaram na fila do dono.
##
## Chamar a cada tique, junto de `advance_time`. É a contraparte de
## `CooldownEffect`, que só sabe pedir — o livro é quem sabe quais habilidades
## existem e quanto falta em cada uma.
##
## Devolve quantas recargas foram mexidas.
func apply_cooldown_requests(owner: Unit) -> int:
	if owner == null:
		return 0
	var mexidas: int = 0
	for request: Unit.CooldownRequest in owner.consume_cooldown_adjustments():
		for ability: Ability in known_abilities():
			if not _alcanca(request, ability):
				continue
			if not _cooldowns.has(ability.id):
				continue
			var delta: float = request.seconds
			if request.proportional:
				delta = ability.cooldown_for(owner) * request.seconds
			# O sinal do pedido é o do original: negativo encurta. Somar (em
			# vez de subtrair) é o que deixa um ajuste positivo ESTENDER a
			# recarga, que é como se expressa a punição por errar.
			_cooldowns[ability.id] = maxf(0.0, _cooldowns[ability.id] + delta)
			mexidas += 1
	return mexidas

static func _alcanca(request: Unit.CooldownRequest, ability: Ability) -> bool:
	if request.group_ids.is_empty():
		return true
	return request.group_ids.has(ability.group_id) 		or request.group_ids.has(ability.id)

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
##
## NÃO cancela os pulsos já marcados. Interromper alguém no meio da conjuração
## impede o que ainda não saiu de sair; o que já foi disparado está no mundo e
## segue seu curso — a bomba não volta para a mão de quem a jogou.
func interrupt() -> Dictionary:
	return take_pending()

# ---------------------------------------------------------------- pulsos

## Marca um pulso para sair daqui a `delay` segundos.
func schedule(
		ability: Ability,
		pulse: AbilityPulse,
		cast: AbilityCast,
		anchor: Vector3,
		delay: float,
		repeats: int = 1
) -> Scheduled:
	var entry := Scheduled.new()
	entry.ability = ability
	entry.pulse = pulse
	entry.cast = cast
	entry.anchor = anchor
	entry.remaining = maxf(delay, 0.0)
	entry.repeats_left = maxi(repeats, 1)
	_scheduled.append(entry)
	return entry

func has_scheduled() -> bool:
	return not _scheduled.is_empty()

func scheduled_count() -> int:
	return _scheduled.size()

## Entrega os pulsos que venceram. Quem ainda tem repetição volta para a fila
## com o intervalo do próprio pulso; quem não tem sai.
func take_due() -> Array[Scheduled]:
	var due: Array[Scheduled] = []
	if _scheduled.is_empty():
		return due
	var kept: Array[Scheduled] = []
	for entry: Scheduled in _scheduled:
		if entry.remaining > 0.0:
			kept.append(entry)
			continue
		due.append(entry)
		if entry.repeats_left > 1:
			entry.repeats_left -= 1
			entry.remaining = maxf(entry.pulse.loop_interval, 0.01)
			kept.append(entry)
	_scheduled = kept
	return due

## Descarta os pulsos marcados. Usado ao morrer — área de quem morreu no meio
## da conjuração não deve continuar batendo.
func clear_scheduled() -> int:
	var count: int = _scheduled.size()
	_scheduled.clear()
	return count

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

	for entry: Scheduled in _scheduled:
		entry.remaining -= delta

	if not is_casting():
		return
	if caster != null and not caster.can_cast():
		interrupt()
		return
	_pending["remaining"] = float(_pending["remaining"]) - delta
