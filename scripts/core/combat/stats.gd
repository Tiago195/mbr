class_name Stats
extends RefCounted

## Conjunto de atributos de um combatente — Fase 2.1.
##
## Ordem de aplicação, fixada aqui e não negociável por modificador:
##
##     final = (base + soma_dos_flats) * (1 + soma_dos_percentuais)
##
## É a convenção usual de MOBA. O ponto de tê-la única e documentada é que
## `+30 AD` e `+15% AD` produzem o mesmo resultado independentemente da ordem
## em que foram equipados — sem isso, a ordem de clique no inventário mudaria
## o dano.
##
## Recalcula a cada consulta, sem cache. `03-sistemas-de-jogo.md` recomenda
## começar assim; cache com invalidação entra quando houver gargalo medido.

var _base: Dictionary = {}
var _modifiers: Array[StatModifier] = []

# ---------------------------------------------------------------- base

func set_base(id: Stat.Id, value: float) -> void:
	_base[id] = value

func get_base(id: Stat.Id) -> float:
	return _base.get(id, Stat.default_of(id))

## Define vários de uma vez. Conveniência para declarar personagem em dado.
func set_bases(values: Dictionary) -> void:
	for id: Stat.Id in values:
		set_base(id, float(values[id]))

# ---------------------------------------------------------------- consulta

func get_value(id: Stat.Id) -> float:
	var flat: float = 0.0
	var percent: float = 0.0
	for mod: StatModifier in _modifiers:
		if mod.stat != id:
			continue
		if mod.kind == StatModifier.Kind.FLAT:
			flat += mod.value
		else:
			percent += mod.value
	return (get_base(id) + flat) * (1.0 + percent)

# ---------------------------------------------------------------- modificadores

## Aplica um modificador respeitando as regras de acúmulo.
##
## Devolve o modificador que passou a valer: o próprio `mod` quando foi
## adicionado, ou o já existente quando houve apenas refresh de duração.
func add_modifier(mod: StatModifier) -> StatModifier:
	var occupying: Array[StatModifier] = []
	for existing: StatModifier in _modifiers:
		if existing.same_slot_as(mod):
			occupying.append(existing)

	if not mod.stacks:
		# Não acumula: a reaplicação substitui. Cobre o buff que "reseta".
		if not occupying.is_empty():
			var kept: StatModifier = occupying[0]
			kept.value = mod.value
			kept.duration = mod.duration
			# Se por algum motivo havia mais de um, o excesso sai agora.
			for extra: StatModifier in occupying.slice(1):
				_modifiers.erase(extra)
			return kept
		_modifiers.append(mod)
		return mod

	# Acumula, mas pode ter teto.
	if mod.max_stacks > 0 and occupying.size() >= mod.max_stacks:
		# No teto, a convenção é renovar as durações em vez de recusar em
		# silêncio — é o que o jogador percebe como "o stack não caiu".
		for existing: StatModifier in occupying:
			existing.duration = mod.duration
		return occupying[0]

	_modifiers.append(mod)
	return mod

func remove_modifier(mod: StatModifier) -> bool:
	var index: int = _modifiers.find(mod)
	if index == -1:
		return false
	_modifiers.remove_at(index)
	return true

## Remove tudo que veio de uma origem. É o caminho de desequipar um item.
## Devolve quantos saíram.
func remove_source(source: StringName) -> int:
	# Laço explícito em vez de `filter()`: `Array.filter` devolve um Array sem
	# tipo, e atribuí-lo de volta a `Array[StatModifier]` falha em runtime.
	var kept: Array[StatModifier] = []
	var removed: int = 0
	for mod: StatModifier in _modifiers:
		if mod.source == source:
			removed += 1
		else:
			kept.append(mod)
	_modifiers = kept
	return removed

func modifiers_from(source: StringName) -> Array[StatModifier]:
	var found: Array[StatModifier] = []
	for mod: StatModifier in _modifiers:
		if mod.source == source:
			found.append(mod)
	return found

func modifier_count() -> int:
	return _modifiers.size()

func has_source(source: StringName) -> bool:
	for mod: StatModifier in _modifiers:
		if mod.source == source:
			return true
	return false

# ---------------------------------------------------------------- tempo

## Avança as durações e descarta o que expirou. Chamado pelo tick do servidor,
## não por `_process` — esta classe não conhece a engine.
## Devolve quantos modificadores expiraram.
func advance_time(delta: float) -> int:
	var expired: Array[StatModifier] = []
	for mod: StatModifier in _modifiers:
		if mod.is_permanent():
			continue
		mod.duration -= delta
		if mod.duration <= 0.0:
			expired.append(mod)
	for mod: StatModifier in expired:
		_modifiers.erase(mod)
	return expired.size()
