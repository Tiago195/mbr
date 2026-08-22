class_name PeriodicSet
extends RefCounted

## Efeitos que repetem no tempo — veneno, queimadura, regeneração, aura.
##
## Vem direto da tradução do original: lá, dano ao longo do tempo é um `Buff`
## que carrega um `Impact` e um `LoopInterval`, e o motor reaplica o impacto a
## cada intervalo. 68 impactos usam `LoopInterval` e 113 buffs carregam um
## `Impact1`. Sem isto, todo veneno e toda aura do original viravam um dano
## instantâneo na tradução — o que muda o design, não só o número.
##
## **Ciclo de referência é o risco real aqui.** Uma entrada guarda quem
## aplicou; se guardasse uma referência forte, dois combatentes se envenenando
## mutuamente nunca chegariam a contagem zero, e a Godot não coleta ciclo.
## Por isso o conjurador entra como `WeakRef`, e o ALVO não é guardado: ele é
## passado em `advance_time()` por quem já o possui.

signal ticked(source: StringName)
signal finished(source: StringName)

## Uma repetição registrada. Classe interna pelo mesmo motivo de `Zone.Phase`:
## é dado desta classe, não vocabulário do jogo.
class Entry extends RefCounted:
	var effects: Array[AbilityEffect] = []
	var interval: float = 1.0
	## Segundos restantes. Negativo = não expira; sai por remoção explícita.
	var remaining: float = 0.0
	## Quanto falta para o próximo disparo.
	var until_next: float = 0.0
	var source: StringName = &""
	var caster_ref: WeakRef = null

	func caster() -> Unit:
		if caster_ref == null:
			return null
		return caster_ref.get_ref() as Unit

	func is_permanent() -> bool:
		return remaining < 0.0

var _entries: Array[Entry] = []

## Registra uma repetição. `duration` negativa dura até alguém remover.
##
## `first_tick_immediately` existe porque as duas convenções aparecem no
## original: veneno que já dói ao aplicar e regeneração que só começa depois
## do primeiro intervalo. Deixar isso implícito daria diferença de um tique
## entre habilidades parecidas, e ninguém acharia a causa.
func add(
		effects: Array[AbilityEffect],
		interval: float,
		duration: float,
		source: StringName,
		caster: Unit = null,
		first_tick_immediately: bool = false
) -> Entry:
	var entry := Entry.new()
	entry.effects = effects
	entry.interval = maxf(interval, 0.01)
	entry.remaining = duration
	entry.until_next = 0.0 if first_tick_immediately else entry.interval
	entry.source = source
	entry.caster_ref = weakref(caster) if caster != null else null
	_entries.append(entry)
	return entry

func count() -> int:
	return _entries.size()

func has_source(source: StringName) -> bool:
	for entry: Entry in _entries:
		if entry.source == source:
			return true
	return false

## Remove tudo que veio de uma origem. Devolve quantas entradas saíram.
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

## Avança o tempo e dispara o que vencer. Devolve quantos tiques saíram.
##
## `owner` é quem sofre os efeitos, e vem por parâmetro justamente para esta
## classe não guardar referência de volta a ele.
##
## O laço interno cobre `delta` maior que o intervalo: com tique de 0.5s e um
## passo de 2s, saem quatro tiques, não um. Sem isso, um servidor com tick
## lento aplicaria menos veneno que um rápido — a mesma habilidade valendo
## coisas diferentes conforme a carga da máquina.
func advance_time(delta: float, owner: Unit) -> int:
	if _entries.is_empty() or owner == null:
		return 0

	var fired: int = 0
	var done: Array[Entry] = []

	for entry: Entry in _entries:
		if not entry.is_permanent():
			entry.remaining -= delta
		entry.until_next -= delta

		var guard: int = 0
		while entry.until_next <= 0.0 and guard < 64:
			guard += 1
			entry.until_next += entry.interval
			if owner.is_alive():
				_fire(entry, owner)
				fired += 1
				ticked.emit(entry.source)

		if not entry.is_permanent() and entry.remaining <= 0.0:
			done.append(entry)

	for entry: Entry in done:
		_entries.erase(entry)
		finished.emit(entry.source)

	return fired

func _fire(entry: Entry, owner: Unit) -> void:
	# O conjurador pode ter morrido e sido liberado no meio do veneno. Nesse
	# caso o efeito continua — o veneno não some porque quem o aplicou caiu —
	# mas sem escalonamento por atributo, porque não há de quem ler.
	var caster: Unit = entry.caster()
	var cast: AbilityCast = AbilityCast.on_unit(caster, owner) if caster != null \
		else AbilityCast.on_self(owner)
	for effect: AbilityEffect in entry.effects:
		if effect == null:
			continue
		var recipient: Unit = caster if \
			effect.recipient == AbilityEffect.Recipient.CASTER else owner
		if recipient != null:
			effect.apply(cast, recipient)
