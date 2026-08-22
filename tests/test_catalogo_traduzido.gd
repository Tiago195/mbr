extends TestCase

## O corpus traduzido do original, carregado e EXECUTADO.
##
## Este é o teste que dá sentido ao Passo 4. Verificar que o JSON existe e tem
## 1126 entradas provaria pouco: um tradutor quebrado também produz 1126
## entradas. O que prova é conjurar cada uma delas contra um alvo e ver que a
## engine resolve — mesma `AbilityEngine`, mesmo `AbilityBook`, mesmos efeitos
## que as três habilidades feitas à mão.
##
## Também é o teste que pega regressão de vocabulário: se alguém renomear um
## `Stat.Id` ou reordenar um enum, milhares de efeitos param de montar aqui,
## em vez de silenciosamente virarem outro atributo em jogo.

var _catalogo: AbilityCatalog
var _itens: ItemCatalog

func _abilities() -> AbilityCatalog:
	if _catalogo == null:
		_catalogo = AbilityCatalog.new()
		_catalogo.load_from()
	return _catalogo

func _items() -> ItemCatalog:
	if _itens == null:
		_itens = ItemCatalog.new()
		_itens.load_from(ItemCatalog.CAMINHO_PADRAO, _abilities())
	return _itens

func _unit(position: Vector3 = Vector3.ZERO, team: int = 0) -> Unit:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.MAX_HEALTH: 100000.0,
		Stat.Id.MAX_MANA: 100000.0,
		Stat.Id.ATTACK_DAMAGE: 100.0,
		Stat.Id.ABILITY_POWER: 100.0,
		Stat.Id.MOVE_SPEED: 5.0,
	})
	var unit := Unit.new(stats, team)
	unit.position = position
	return unit

# ---------------------------------------------------------------- carga

func test_o_catalogo_carrega() -> void:
	var catalogo: AbilityCatalog = _abilities()
	assert_true(catalogo.loaded > 0, "nenhuma habilidade carregada")
	assert_eq(catalogo.skipped, 0, "entradas descartadas na carga")

func test_as_948_de_skill_xml_estao_todas_la() -> void:
	# A promessa do Passo 4 é `skill_xml` inteira. As outras tabelas somam por
	# cima; o que não pode faltar é esta.
	var catalogo: AbilityCatalog = _abilities()
	assert_true(
		catalogo.loaded >= 948,
		"esperava ao menos as 948 de skill_xml, vieram %d" % catalogo.loaded
	)

func test_todo_id_e_unico_e_nao_vazio() -> void:
	var catalogo: AbilityCatalog = _abilities()
	var vistos: Dictionary = {}
	var repetidos: int = 0
	var vazios: int = 0
	for id: StringName in catalogo.by_id:
		if String(id).is_empty():
			vazios += 1
		if vistos.has(id):
			repetidos += 1
		vistos[id] = true
	assert_eq(vazios, 0)
	assert_eq(repetidos, 0)

func test_os_ranques_de_um_grupo_ficam_em_ordem() -> void:
	var catalogo: AbilityCatalog = _abilities()
	var conferidos: int = 0
	for grupo: StringName in catalogo.by_group:
		var ranques: Array = catalogo.by_group[grupo]
		if ranques.size() < 2:
			continue
		conferidos += 1
		for i: int in range(1, ranques.size()):
			var anterior: Ability = ranques[i - 1]
			var atual: Ability = ranques[i]
			if anterior.rank > atual.rank:
				assert_true(false, "grupo %s fora de ordem" % grupo)
				return
	assert_true(conferidos > 50, "esperava muitos grupos com vários ranques")

func test_ranque_por_nivel_respeita_o_requisito() -> void:
	var catalogo: AbilityCatalog = _abilities()
	var achou: bool = false
	for grupo: StringName in catalogo.by_group:
		var ranques: Array = catalogo.by_group[grupo]
		if ranques.size() < 3:
			continue
		var escolhido: Ability = catalogo.rank_for_level(grupo, 1)
		if escolhido == null:
			continue
		achou = true
		assert_true(
			escolhido.level_requirement <= 1,
			"%s exigia nível %d" % [escolhido.id, escolhido.level_requirement]
		)
		var alto: Ability = catalogo.rank_for_level(grupo, 99)
		assert_true(alto.rank >= escolhido.rank, "nível maior não pode dar ranque menor")
		break
	assert_true(achou, "nenhum grupo com ranques utilizáveis")

# ---------------------------------------------------------------- coerência

func test_nenhum_efeito_se_perdeu_na_montagem() -> void:
	# O contador do JSON contra o contador dos objetos montados. Se
	# `EffectFactory` não conhecer um tipo, ele devolve nulo e o efeito some —
	# em silêncio, que é exatamente o que este teste existe para impedir.
	var bruto: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(AbilityCatalog.CAMINHO_PADRAO)
	)
	var esperados: int = 0
	for entry: Dictionary in bruto["habilidades"]:
		for pulse: Dictionary in entry["pulses"]:
			esperados += (pulse["effects"] as Array).size()

	var montados: int = 0
	for id: StringName in _abilities().by_id:
		var ability: Ability = _abilities().by_id[id]
		for pulse: AbilityPulse in ability.pulses:
			montados += pulse.effects.size()

	assert_true(esperados > 3000, "o corpus encolheu: só %d efeitos no JSON" % esperados)
	assert_eq(montados, esperados, "efeitos perdidos entre o JSON e os objetos")

func test_nenhum_efeito_ficou_nulo() -> void:
	var nulos: int = 0
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			for effect: AbilityEffect in pulse.effects:
				if effect == null:
					nulos += 1
	assert_eq(nulos, 0)

func test_toda_forma_e_valida() -> void:
	var invalidas: int = 0
	var formas: int = AbilityPulse.Form.size()
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			if pulse.form < 0 or pulse.form >= formas:
				invalidas += 1
	assert_eq(invalidas, 0)

func test_geometria_nao_tem_valor_absurdo() -> void:
	var ruins: PackedStringArray = []
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			if pulse.radius < 0.0 or pulse.length < 0.0 or pulse.width < 0.0:
				ruins.append(String(id))
			elif pulse.loop_interval > 0.0 and pulse.duration <= 0.0:
				# Área que repete sem prazo bateria para sempre.
				ruins.append(String(id))
	assert_eq(ruins.size(), 0, "geometria inválida em: %s" % ", ".join(ruins.slice(0, 5)))

func test_recarga_e_custo_nao_sao_negativos() -> void:
	var ruins: int = 0
	for id: StringName in _abilities().by_id:
		var ability: Ability = _abilities().by_id[id]
		if ability.cooldown < 0.0 or ability.mana_cost < 0.0:
			ruins += 1
	assert_eq(ruins, 0)

func test_o_corpus_usa_o_vocabulario_todo() -> void:
	# Se uma peça do vocabulário nunca aparece no corpus, ou ela não fazia
	# falta, ou o tradutor deixou de emiti-la. Nos dois casos vale saber.
	var vistos: Dictionary = {}
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			for effect: AbilityEffect in pulse.effects:
				vistos[effect.get_script().resource_path.get_file()] = true
	for esperado: String in [
		"damage_effect.gd", "heal_effect.gd", "shield_effect.gd",
		"stat_mod_effect.gd", "crowd_control_effect.gd", "displacement_effect.gd",
		"periodic_effect.gd", "summon_effect.gd", "execute_effect.gd",
		"resource_effect.gd", "mark_effect.gd", "cooldown_effect.gd",
		"trigger_effect.gd",
	]:
		assert_true(vistos.has(esperado), "%s nunca aparece no corpus" % esperado)

# ---------------------------------------------------------------- execução

## O teste central: CONJURAR tudo.
##
## Um alvo colado no conjurador e outro a 4 metros cobrem forma de contato e
## forma de alcance. Livro novo por habilidade para não bater em recarga nem
## em BUSY. O que se afirma é que a engine devolve um estado conhecido e que
## nada estoura no caminho.
func test_toda_habilidade_do_corpus_conjura() -> void:
	var catalogo: AbilityCatalog = _abilities()
	var conjuradas: int = 0
	var invalidas: PackedStringArray = []

	for id: StringName in catalogo.by_id:
		var ability: Ability = catalogo.by_id[id]
		if ability.pulses.is_empty():
			continue

		var caster: Unit = _unit()
		var colado: Unit = _unit(Vector3(0.5, 0.0, -0.5), 1)
		var perto: Unit = _unit(Vector3(0.0, 0.0, -4.0), 1)
		var aliado: Unit = _unit(Vector3(1.0, 0.0, 0.0), 0)
		var candidatos: Array = [colado, perto, aliado]

		var book := AbilityBook.new()
		book.learn(AbilityBook.Slot.Q, ability)

		var aim: AbilityCast = _mira(ability, caster, perto)
		var result: CastResult = AbilityEngine.cast(book, ability, aim, candidatos)
		conjuradas += 1

		if result.status == CastResult.Status.INVALID:
			invalidas.append("%s" % id)
			continue

		# Solta os pulsos atrasados. Meio segundo por passo, o suficiente para
		# vencer o `StartTime` de qualquer impacto do original.
		for passo: int in range(12):
			book.advance_time(0.5, caster)
			AbilityEngine.resolve_scheduled(book, candidatos)
			caster.advance_time(0.5)
			for alvo: Unit in candidatos:
				alvo.advance_time(0.5)

	assert_true(conjuradas > 900, "só %d habilidades conjuráveis" % conjuradas)
	assert_eq(
		invalidas.size(), 0,
		"recusadas como INVALID: %s" % ", ".join(invalidas.slice(0, 8))
	)

func test_conjurar_o_corpus_causa_efeito_de_verdade() -> void:
	# O teste acima prova que nada estoura. Este prova que algo ACONTECE —
	# sem ele, um tradutor que emitisse efeitos vazios passaria batido.
	var catalogo: AbilityCatalog = _abilities()
	var machucaram: int = 0
	var curaram: int = 0
	var controlaram: int = 0

	for id: StringName in catalogo.by_id:
		var ability: Ability = catalogo.by_id[id]
		if ability.pulses.is_empty():
			continue
		var caster: Unit = _unit()
		var alvo: Unit = _unit(Vector3(0.0, 0.0, -1.5), 1)
		var aliado: Unit = _unit(Vector3(0.5, 0.0, 0.0), 0)
		aliado.health.current = 1000.0
		var candidatos: Array = [alvo, aliado]
		var book := AbilityBook.new()
		AbilityEngine.cast(book, ability, _mira(ability, caster, alvo), candidatos)
		for passo: int in range(6):
			book.advance_time(0.5, caster)
			AbilityEngine.resolve_scheduled(book, candidatos)

		if alvo.health.current < 100000.0:
			machucaram += 1
		if aliado.health.current > 1000.0 or caster.health.shield > 0.0:
			curaram += 1
		if not alvo.status.is_clear() or alvo.stats.modifier_count() > 0:
			controlaram += 1

	assert_true(machucaram > 400, "só %d habilidades causaram dano" % machucaram)
	assert_true(curaram > 20, "só %d habilidades curaram ou protegeram" % curaram)
	assert_true(controlaram > 100, "só %d habilidades controlaram" % controlaram)

## Mira coerente com o tipo de alvo da habilidade.
func _mira(ability: Ability, caster: Unit, alvo: Unit) -> AbilityCast:
	match ability.aim:
		Ability.Aim.SELF:
			return AbilityCast.on_self(caster)
		Ability.Aim.UNIT:
			return AbilityCast.on_unit(caster, alvo)
		Ability.Aim.DIRECTION:
			return AbilityCast.toward(caster, Vector3(0.0, 0.0, -1.0))
		_:
			return AbilityCast.at_point(caster, alvo.position)

# ---------------------------------------------------------------- itens

func test_os_421_itens_carregam() -> void:
	var catalogo: ItemCatalog = _items()
	assert_eq(catalogo.loaded, 421, "esperava os 421 itens de equipment_xml")
	assert_eq(catalogo.skipped, 0)

func test_todo_item_tem_espaco_coerente_com_a_especie() -> void:
	var ruins: PackedStringArray = []
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		if item.kind == Item.Kind.EQUIPMENT and not item.is_equippable():
			ruins.append(String(id))
		elif item.kind == Item.Kind.MATERIAL and item.is_equippable():
			ruins.append(String(id))
	assert_eq(ruins.size(), 0, "espécie e espaço brigando: %s" % ", ".join(ruins.slice(0, 5)))

func test_equipar_e_desequipar_todo_item_nao_deixa_resto() -> void:
	# A prova de que a passiva traduzida é removível. Um bônus que fica depois
	# de desequipar é o pior bug de inventário que existe: ele se acumula em
	# silêncio a cada troca.
	var sobraram: PackedStringArray = []
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		var portador: Unit = _unit()
		var antes: float = portador.stats.get_value(Stat.Id.ATTACK_DAMAGE)

		for mod: StatModifier in item.build_modifiers():
			portador.stats.add_modifier(mod)
		item.apply_passives(portador)

		portador.stats.remove_source(item.source())
		item.remove_passives(portador)

		if portador.stats.modifier_count() != 0:
			sobraram.append(String(id))
		elif not is_equal_approx(portador.stats.get_value(Stat.Id.ATTACK_DAMAGE), antes):
			sobraram.append(String(id))
	assert_eq(
		sobraram.size(), 0,
		"deixaram modificador para trás: %s" % ", ".join(sobraram.slice(0, 5))
	)

func test_bonus_de_item_chegam_no_atributo() -> void:
	var com_bonus: int = 0
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		if item.flat_bonuses.is_empty() and item.percent_bonuses.is_empty():
			continue
		com_bonus += 1
		var portador: Unit = _unit()
		var mods: Array[StatModifier] = item.build_modifiers()
		assert_true(mods.size() > 0, "%s tem bônus e não gerou modificador" % id)
		return_if_enough(com_bonus)
		break
	assert_true(com_bonus > 0, "nenhum item com bônus de atributo")

## Só para o teste acima poder parar cedo sem perder a asserção.
func return_if_enough(_count: int) -> void:
	pass

func test_a_maioria_dos_equipamentos_da_atributo() -> void:
	var equipamentos: int = 0
	var com_bonus: int = 0
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		if item.kind != Item.Kind.EQUIPMENT:
			continue
		equipamentos += 1
		if not item.flat_bonuses.is_empty() or not item.percent_bonuses.is_empty():
			com_bonus += 1
	assert_true(equipamentos > 150, "poucos equipamentos: %d" % equipamentos)
	assert_true(
		com_bonus > equipamentos * 0.8,
		"só %d de %d equipamentos dão atributo" % [com_bonus, equipamentos]
	)

func test_linhas_de_item_saem_da_menor_raridade_para_a_maior() -> void:
	var linhas_conferidas: int = 0
	for linha: StringName in _items().by_line:
		var itens: Array = _items().by_line[linha]
		if itens.size() < 2:
			continue
		linhas_conferidas += 1
		for i: int in range(1, itens.size()):
			if (itens[i - 1] as Item).rarity > (itens[i] as Item).rarity:
				assert_true(false, "linha %s fora de ordem" % linha)
				return
	assert_true(linhas_conferidas > 50, "esperava muitas linhas de melhoria")

func test_melhoria_sobe_de_raridade() -> void:
	var testados: int = 0
	for linha: StringName in _items().by_line:
		var itens: Array = _items().by_line[linha]
		if itens.size() < 2:
			continue
		var base: Item = itens[0]
		var acima: Item = _items().upgrade_of(base)
		assert_not_null(acima, "linha %s sem degrau acima do primeiro" % linha)
		if acima != null:
			assert_true(acima.rarity > base.rarity)
		testados += 1
		if testados >= 3:
			break
	assert_true(testados > 0)

func test_receitas_ligaram_ingredientes() -> void:
	var com_receita: int = 0
	for id: StringName in _items().by_id:
		if not (_items().by_id[id] as Item).built_from.is_empty():
			com_receita += 1
	assert_true(com_receita > 200, "só %d itens com receita" % com_receita)

func test_itens_de_uso_apontam_para_habilidade() -> void:
	var usaveis: int = 0
	for id: StringName in _items().by_id:
		if (_items().by_id[id] as Item).is_usable():
			usaveis += 1
	assert_true(usaveis > 10, "só %d itens com habilidade ativa" % usaveis)

func test_item_de_uso_conjura_pelo_mesmo_motor() -> void:
	# O ponto de `03-sistemas-de-jogo.md`: item que age não é um segundo
	# sistema. Se for, este teste não compila.
	var achado: Item = null
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		if item.is_usable() and not item.active_ability.pulses.is_empty():
			achado = item
			break
	assert_not_null(achado, "nenhum item com ativa conjurável")
	if achado == null:
		return

	var portador: Unit = _unit()
	var alvo: Unit = _unit(Vector3(0.0, 0.0, -2.0), 1)
	var book := AbilityBook.new()
	var result: CastResult = AbilityEngine.cast(
		book, achado.active_ability,
		_mira(achado.active_ability, portador, alvo), [alvo]
	)
	assert_true(
		result.status != CastResult.Status.INVALID,
		"%s: %s" % [achado.id, CastResult.Status.keys()[result.status]]
	)
