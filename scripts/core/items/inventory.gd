class_name Inventory
extends RefCounted

## Mochila e equipamento de um combatente — Fase 5.2.
##
## Lógica pura. Aplica e remove modificadores nos `Stats` que recebe, e a
## rastreabilidade por origem — construída lá na Fase 2.1 — é o que garante que
## desequipar devolva os atributos ao estado exato anterior.
##
## Não guarda referência ao dono: recebe os `Stats` no construtor. Guardar o
## `Unit` criaria o ciclo entre RefCounted que já vazou memória neste projeto.

signal changed()
signal equipped(item: Item, slot: Item.Slot)
signal unequipped(item: Item, slot: Item.Slot)

## Uma pilha de itens iguais ocupando um espaço.
class Stack extends RefCounted:
	var item: Item
	var count: int

	func _init(p_item: Item, p_count: int = 1) -> void:
		item = p_item
		count = p_count

	func room_left() -> int:
		return maxi(0, item.max_stack - count)

## Espaços da mochila. Limite existe para forçar a decisão de o que largar.
var capacity: int = 6

var _stats: Stats
var _bag: Array = []
var _equipped: Dictionary = {}

func _init(stats: Stats, p_capacity: int = 6) -> void:
	_stats = stats
	capacity = p_capacity

# ---------------------------------------------------------------- mochila

func bag() -> Array:
	return _bag.duplicate()

func used_slots() -> int:
	return _bag.size()

func is_full() -> bool:
	return _bag.size() >= capacity

func count_of(id: StringName) -> int:
	var total: int = 0
	for pilha: Stack in _bag:
		if pilha.item.id == id:
			total += pilha.count
	return total

## Guarda um item na mochila. Devolve quantos NÃO couberam.
##
## Empilha no que já existe antes de ocupar espaço novo — senão duas poções
## iguais gastariam dois espaços de uma mochila de seis.
func add(item: Item, count: int = 1) -> int:
	var restante: int = count
	if item.stacks():
		for pilha: Stack in _bag:
			if restante <= 0:
				break
			if pilha.item.id != item.id:
				continue
			var cabe: int = mini(pilha.room_left(), restante)
			pilha.count += cabe
			restante -= cabe

	while restante > 0 and not is_full():
		var nesta: int = mini(item.max_stack, restante)
		_bag.append(Stack.new(item, nesta))
		restante -= nesta

	if restante < count:
		changed.emit()
	return restante

## Tira unidades da mochila. Devolve quantas saíram de fato.
func remove(id: StringName, count: int = 1) -> int:
	var restante: int = count
	var mantidas: Array = []
	for pilha: Stack in _bag:
		if restante > 0 and pilha.item.id == id:
			var tirado: int = mini(pilha.count, restante)
			pilha.count -= tirado
			restante -= tirado
		if pilha.count > 0:
			mantidas.append(pilha)
	var saiu: int = count - restante
	if saiu > 0:
		_bag = mantidas
		changed.emit()
	return saiu

# ---------------------------------------------------------------- equipar

func equipped_in(slot: Item.Slot) -> Item:
	return _equipped.get(slot, null) as Item

func is_equipped(id: StringName) -> bool:
	for slot: Item.Slot in _equipped:
		if (_equipped[slot] as Item).id == id:
			return true
	return false

## Equipa um item que está na mochila.
##
## O item já equipado no mesmo espaço volta para a mochila. Se a mochila
## estiver cheia, a troca é recusada inteira — trocar de arma não pode fazer a
## anterior evaporar.
func equip(item: Item) -> bool:
	if item == null or not item.is_equippable():
		return false
	if count_of(item.id) <= 0:
		return false

	var anterior: Item = equipped_in(item.slot)
	if anterior != null and is_full() and count_of(item.id) <= 1:
		# A mochila só libera espaço ao remover o novo item, e ele é o único
		# da pilha: sem espaço para devolver o antigo, a troca não acontece.
		return false

	remove(item.id, 1)
	if anterior != null:
		_unequip_internal(anterior)
		add(anterior, 1)

	_equipped[item.slot] = item
	for mod: StatModifier in item.build_modifiers():
		_stats.add_modifier(mod)
	equipped.emit(item, item.slot)
	changed.emit()
	return true

## Desequipa e devolve para a mochila. Falso se não couber — nesse caso o item
## continua equipado, que é melhor que sumir.
func unequip(slot: Item.Slot) -> bool:
	var item: Item = equipped_in(slot)
	if item == null:
		return false
	if is_full():
		return false
	_unequip_internal(item)
	add(item, 1)
	unequipped.emit(item, slot)
	changed.emit()
	return true

func _unequip_internal(item: Item) -> void:
	_equipped.erase(item.slot)
	# Remoção por ORIGEM, não por valor: é o que garante tirar exatamente o
	# que este item deu, mesmo com outro item concedendo o mesmo bônus.
	_stats.remove_source(item.source())

## Tira tudo. Usado ao morrer, quando o loot cai no chão.
func unequip_all() -> Array:
	var soltos: Array = []
	for slot: Item.Slot in _equipped.keys():
		var item: Item = _equipped[slot]
		_unequip_internal(item)
		soltos.append(item)
	if not soltos.is_empty():
		changed.emit()
	return soltos

## Tudo que o combatente carrega, equipado e na mochila. É o que vira loot no
## chão quando ele morre.
func drop_everything() -> Array:
	var tudo: Array = unequip_all()
	for pilha: Stack in _bag:
		for _i: int in pilha.count:
			tudo.append(pilha.item)
	_bag.clear()
	changed.emit()
	return tudo
