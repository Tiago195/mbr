extends TestCase

## Fase 5.2 — itens e inventário.
##
## O teste que dá nome à fase é `test_equipar_e_desequipar_devolve_os_atributos`:
## é a promessa da Fase 2.1 sendo cobrada pelo sistema que a motivou.

func _item(id: StringName, slot: Item.Slot, flat: Dictionary = {},
		percent: Dictionary = {}, pilha: int = 1) -> Item:
	var item := Item.new()
	item.id = id
	item.display_name = String(id)
	item.slot = slot
	item.flat_bonuses = flat
	item.percent_bonuses = percent
	item.max_stack = pilha
	return item

func _espada() -> Item:
	return _item(&"espada", Item.Slot.WEAPON, {Stat.Id.ATTACK_DAMAGE: 40.0})

func _machado() -> Item:
	return _item(&"machado", Item.Slot.WEAPON, {Stat.Id.ATTACK_DAMAGE: 55.0})

func _peitoral() -> Item:
	return _item(&"peitoral", Item.Slot.ARMOR,
		{Stat.Id.ARMOR: 30.0, Stat.Id.MAX_HEALTH: 200.0},
		{Stat.Id.MAX_HEALTH: 0.10})

func _pocao() -> Item:
	return _item(&"pocao", Item.Slot.NONE, {}, {}, 5)

func _stats() -> Stats:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.ATTACK_DAMAGE: 60.0,
		Stat.Id.ARMOR: 20.0,
		Stat.Id.MAX_HEALTH: 600.0,
	})
	return stats

# ---------------------------------------------------------------- mochila

func test_guarda_e_conta() -> void:
	var inv := Inventory.new(_stats())
	assert_eq(inv.add(_espada()), 0, "coube inteiro")
	assert_eq(inv.count_of(&"espada"), 1)
	assert_eq(inv.used_slots(), 1)

func test_itens_iguais_empilham_em_vez_de_ocupar_espacos() -> void:
	# Sem isso, cinco poções gastariam cinco dos seis espaços.
	var inv := Inventory.new(_stats())
	inv.add(_pocao(), 3)
	assert_eq(inv.used_slots(), 1, "uma pilha só")
	assert_eq(inv.count_of(&"pocao"), 3)

	inv.add(_pocao(), 2)
	assert_eq(inv.used_slots(), 1, "ainda cabe na mesma pilha")
	assert_eq(inv.count_of(&"pocao"), 5)

func test_pilha_cheia_abre_espaco_novo() -> void:
	var inv := Inventory.new(_stats())
	inv.add(_pocao(), 7)
	assert_eq(inv.used_slots(), 2, "5 + 2")
	assert_eq(inv.count_of(&"pocao"), 7)

func test_mochila_cheia_devolve_o_que_nao_coube() -> void:
	var inv := Inventory.new(_stats(), 2)
	var sobra: int = inv.add(_espada(), 5)
	assert_eq(inv.used_slots(), 2, "só dois espaços")
	assert_eq(sobra, 3, "três ficaram de fora")

func test_remover_tira_a_quantidade_pedida() -> void:
	var inv := Inventory.new(_stats())
	inv.add(_pocao(), 4)
	assert_eq(inv.remove(&"pocao", 3), 3)
	assert_eq(inv.count_of(&"pocao"), 1)
	assert_eq(inv.remove(&"pocao", 9), 1, "só saiu o que havia")
	assert_eq(inv.used_slots(), 0, "pilha vazia some")

# ---------------------------------------------------------------- equipar

func test_equipar_aplica_os_bonus() -> void:
	var stats := _stats()
	var inv := Inventory.new(stats)
	var espada := _espada()
	inv.add(espada)

	assert_true(inv.equip(espada))
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 100.0, "60 + 40")
	assert_eq(inv.used_slots(), 0, "saiu da mochila")
	assert_eq(inv.equipped_in(Item.Slot.WEAPON), espada)

func test_bonus_plano_e_percentual_do_mesmo_item() -> void:
	var stats := _stats()
	var inv := Inventory.new(stats)
	var peitoral := _peitoral()
	inv.add(peitoral)
	inv.equip(peitoral)

	assert_almost_eq(stats.get_value(Stat.Id.ARMOR), 50.0)
	# (600 + 200) * 1.10
	assert_almost_eq(stats.get_value(Stat.Id.MAX_HEALTH), 880.0)

func test_nao_equipa_o_que_nao_esta_na_mochila() -> void:
	var inv := Inventory.new(_stats())
	assert_false(inv.equip(_espada()))

func test_nao_equipa_item_sem_espaco_de_equipamento() -> void:
	var inv := Inventory.new(_stats())
	var pocao := _pocao()
	inv.add(pocao)
	assert_false(inv.equip(pocao), "poção não se equipa")

# ------------------------------------------- O CRITÉRIO QUE A FASE 2.1 PROMETEU

func test_equipar_e_desequipar_devolve_os_atributos() -> void:
	var stats := _stats()
	var inv := Inventory.new(stats)

	var antes: Dictionary = {}
	for id: Stat.Id in Stat.NAMES:
		antes[id] = stats.get_value(id)

	var peitoral := _peitoral()
	inv.add(peitoral)
	inv.equip(peitoral)
	assert_almost_eq(stats.get_value(Stat.Id.MAX_HEALTH), 880.0, "equipado")

	assert_true(inv.unequip(Item.Slot.ARMOR))

	for id: Stat.Id in Stat.NAMES:
		assert_almost_eq(
			stats.get_value(id), float(antes[id]), "atributo %s" % Stat.name_of(id)
		)
	assert_eq(stats.modifier_count(), 0, "nenhum resíduo")
	assert_eq(inv.count_of(&"peitoral"), 1, "voltou para a mochila")

func test_dois_itens_com_o_mesmo_bonus_saem_separados() -> void:
	# O caso que justifica remover por origem e não por valor.
	var stats := _stats()
	var inv := Inventory.new(stats)
	var a := _item(&"anel_a", Item.Slot.ACCESSORY, {Stat.Id.ATTACK_DAMAGE: 25.0})
	var b := _item(&"anel_b", Item.Slot.WEAPON, {Stat.Id.ATTACK_DAMAGE: 25.0})
	inv.add(a)
	inv.add(b)
	inv.equip(a)
	inv.equip(b)
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 110.0)

	inv.unequip(Item.Slot.ACCESSORY)
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 85.0, "saiu um só")

# ---------------------------------------------------------------- troca

func test_equipar_no_mesmo_espaco_troca_e_devolve_o_antigo() -> void:
	var stats := _stats()
	var inv := Inventory.new(stats)
	var espada := _espada()
	var machado := _machado()
	inv.add(espada)
	inv.add(machado)

	inv.equip(espada)
	inv.equip(machado)

	assert_eq(inv.equipped_in(Item.Slot.WEAPON), machado)
	assert_eq(inv.count_of(&"espada"), 1, "a antiga voltou para a mochila")
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 115.0, "60 + 55, sem somar a espada")

func test_troca_e_recusada_quando_nao_ha_onde_devolver_a_antiga() -> void:
	# Trocar de arma não pode fazer a anterior evaporar.
	var stats := _stats()
	var inv := Inventory.new(stats, 1)
	var espada := _espada()
	var machado := _machado()

	inv.add(espada)
	inv.equip(espada)
	inv.add(machado)
	assert_true(inv.is_full())

	assert_false(inv.equip(machado), "recusou a troca")
	assert_eq(inv.equipped_in(Item.Slot.WEAPON), espada, "nada mudou")
	assert_eq(inv.count_of(&"machado"), 1, "o novo continua na mochila")
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 100.0)

func test_desequipar_sem_espaco_e_recusado() -> void:
	var stats := _stats()
	var inv := Inventory.new(stats, 1)
	var espada := _espada()
	inv.add(espada)
	inv.equip(espada)
	inv.add(_pocao())
	assert_true(inv.is_full())

	assert_false(inv.unequip(Item.Slot.WEAPON), "melhor recusar que sumir")
	assert_eq(inv.equipped_in(Item.Slot.WEAPON), espada)
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 100.0)

# ---------------------------------------------------------------- morte

func test_largar_tudo_devolve_equipado_e_mochila() -> void:
	var stats := _stats()
	var inv := Inventory.new(stats)
	inv.add(_espada())
	inv.add(_peitoral())
	inv.add(_pocao(), 3)
	inv.equip(_espada())

	var caiu: Array = inv.drop_everything()

	assert_eq(caiu.size(), 5, "espada + peitoral + 3 poções")
	assert_eq(inv.used_slots(), 0)
	assert_null(inv.equipped_in(Item.Slot.WEAPON))
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 60.0, "voltou ao base")
	assert_eq(stats.modifier_count(), 0)

func test_modelo_preve_combinacao_de_itens() -> void:
	# Crafting está fora do escopo da Fase 1, mas o doc pede que o modelo
	# preveja combinação para não exigir reescrita depois.
	var composto := _item(&"lamina_lendaria", Item.Slot.WEAPON,
		{Stat.Id.ATTACK_DAMAGE: 90.0})
	composto.built_from = [&"espada", &"machado"]
	assert_eq(composto.built_from.size(), 2)
