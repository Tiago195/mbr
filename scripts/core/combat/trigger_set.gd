class_name TriggerSet
extends RefCounted

## Efeitos armados que esperam um evento — o `TRIGGER` que
## `03-sistemas-de-jogo.md` listava no vocabulário e que ainda não existia.
##
## A tradução do original tornou obrigatório: `TriggerTiming` aparece em todo
## impacto, com **22 valores atômicos distintos**, e `BuffReleaseCondition` diz
## quando um buff se desfaz (`ShieldExhaust`, `SkillFinish`, `MaxStack`).
## Passiva de campeão é quase toda feita disto — "ao acertar três vezes, ganha
## escudo" é literalmente um gatilho com carga.
##
## Mesma disciplina de `PeriodicSet` contra ciclo de referência: quem armou
## entra como `WeakRef`, e o dono é passado em `fire()`.

## O que pode disparar. Nem todo `TriggerTiming` do original tem equivalente
## aqui — a tabela completa dos 22, com o que cada um virou e por que doze
## deles ficaram de fora, está na seção "TriggerTiming" de
## `docs/10-traducao-do-original.md`. O critério: só entra evento que a camada
## `core/` consegue emitir sozinha, sem depender de cena.
##
## Valor novo entra no FIM: isto é exportado para `.tres` como inteiro.
enum Event {
	## O dono acertou um ataque básico.
	BASIC_ATTACK_HIT,
	## O dono acertou alguém com uma habilidade.
	ABILITY_HIT,
	## O dono levou dano de alguém.
	DAMAGE_TAKEN,
	## O dono matou alguém.
	KILL,
	## O escudo do dono foi todo consumido.
	SHIELD_BROKEN,
	## O dono foi curado.
	HEALED,
	## O dono usou uma habilidade — acertando ou não.
	ABILITY_CAST,
	## As cargas acabaram ou o prazo venceu. Dispara ao sair, e é assim que se
	## expressa "quando o buff acabar, explode".
	EXPIRED,
	## Uma marca do dono chegou ao teto de pilhas. É o `TriggerTiming: MaxStack`
	## do original, e o que faz "acerte três vezes e o quarto atordoa" caber no
	## vocabulário sem uma classe própria.
	MARK_MAXED,
}

signal fired(event: Event, source: StringName)

class Entry extends RefCounted:
	var event: Event = Event.BASIC_ATTACK_HIT
	var effects: Array[AbilityEffect] = []
	## Quantas vezes ainda dispara. 0 = ilimitado enquanto durar.
	var charges: int = 0
	## Segundos de validade. Negativo = até gastar as cargas.
	var remaining: float = 0.0
	var source: StringName = &""
	var caster_ref: WeakRef = null
	## Efeitos a aplicar quando a entrada sai — o `EXPIRED` do original.
	var on_expire: Array[AbilityEffect] = []

	func caster() -> Unit:
		if caster_ref == null:
			return null
		return caster_ref.get_ref() as Unit

	func is_permanent() -> bool:
		return remaining < 0.0

var _entries: Array[Entry] = []

func arm(
		event: Event,
		effects: Array[AbilityEffect],
		source: StringName,
		duration: float = -1.0,
		charges: int = 0,
		caster: Unit = null,
		on_expire: Array[AbilityEffect] = []
) -> Entry:
	var entry := Entry.new()
	entry.event = event
	entry.effects = effects
	entry.source = source
	entry.remaining = duration
	entry.charges = maxi(charges, 0)
	entry.caster_ref = weakref(caster) if caster != null else null
	entry.on_expire = on_expire
	_entries.append(entry)
	return entry

func count() -> int:
	return _entries.size()

func has_source(source: StringName) -> bool:
	for entry: Entry in _entries:
		if entry.source == source:
			return true
	return false

## Dispara tudo que espera por este evento. Devolve quantas entradas rodaram.
##
## `other` é o outro lado do evento: quem levou o ataque, quem causou o dano,
## quem foi morto. Pode ser nulo — nem todo evento tem dois lados.
##
## A lista é copiada antes de percorrer porque um efeito disparado pode armar
## outro gatilho no mesmo dono, e mutar `_entries` durante a iteração é como
## se perde um disparo sem nenhum erro no console.
func fire(event: Event, owner: Unit, other: Unit = null) -> int:
	if _entries.is_empty() or owner == null:
		return 0

	var matching: Array[Entry] = []
	for entry: Entry in _entries:
		if entry.event == event:
			matching.append(entry)
	if matching.is_empty():
		return 0

	var ran: int = 0
	var spent: Array[Entry] = []
	for entry: Entry in matching:
		_apply(entry, entry.effects, owner, other)
		ran += 1
		fired.emit(event, entry.source)
		if entry.charges > 0:
			entry.charges -= 1
			if entry.charges == 0:
				spent.append(entry)

	for entry: Entry in spent:
		_expire(entry, owner)
	return ran

## Avança o prazo das entradas temporárias. Devolve quantas venceram.
func advance_time(delta: float, owner: Unit) -> int:
	if _entries.is_empty():
		return 0
	var done: Array[Entry] = []
	for entry: Entry in _entries:
		if entry.is_permanent():
			continue
		entry.remaining -= delta
		if entry.remaining <= 0.0:
			done.append(entry)
	for entry: Entry in done:
		_expire(entry, owner)
	return done.size()

func remove_source(source: StringName) -> int:
	var kept: Array[Entry] = []
	var removed: int = 0
	for entry: Entry in _entries:
		if entry.source == source:
			removed += 1
		else:
			kept.append(entry)
	_entries = kept
	return removed

func clear() -> void:
	_entries.clear()

## Tira a entrada e roda o que ela deixou marcado para a saída.
##
## A ordem importa: a entrada sai da lista ANTES de os efeitos de saída
## rodarem. Um efeito de saída que rearme o mesmo gatilho — "quando acabar,
## reaplica" — entraria em recursão infinita se a remoção viesse depois.
func _expire(entry: Entry, owner: Unit) -> void:
	if not _entries.has(entry):
		return
	_entries.erase(entry)
	if owner != null and not entry.on_expire.is_empty():
		_apply(entry, entry.on_expire, owner, null)
	fired.emit(Event.EXPIRED, entry.source)

func _apply(
		entry: Entry, effects: Array[AbilityEffect], owner: Unit, other: Unit
) -> void:
	var caster: Unit = entry.caster()
	if caster == null:
		caster = owner
	# O outro lado do evento é o alvo natural; sem ele, o próprio dono.
	var subject: Unit = other if other != null else owner
	var cast: AbilityCast = AbilityCast.on_unit(caster, subject)
	for effect: AbilityEffect in effects:
		if effect == null:
			continue
		var recipient: Unit = owner if \
			effect.recipient == AbilityEffect.Recipient.CASTER else subject
		effect.apply(cast, recipient)
