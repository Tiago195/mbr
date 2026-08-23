extends TestCase

## A suprema que enche agindo, e não com o tempo.
##
## No original a suprema **não tem recarga**: `CoolTime = 0` em 31 das 32, e
## `LevelUpUltimateCharge = 1000` diz quanto ela custa. Enquanto o sistema não
## existia, ela recebia uma recarga inventada de 45 segundos — um número que não
## vinha de lugar nenhum e que fazia a suprema ser uma questão de esperar, e não
## de jogar.
##
## O que estes testes protegem é a inversão: **a suprema é um recurso que se
## ganha agindo**. Se o portão sumir, ela vira instantânea; se o ganho sumir,
## ela vira inalcançável. Os dois são silenciosos.

func _unit(carga_maxima: float = 1000.0) -> Unit:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.MAX_HEALTH: 1000.0,
		Stat.Id.ATTACK_DAMAGE: 100.0,
		Stat.Id.MAX_ULTIMATE_CHARGE: carga_maxima,
	})
	var unit := Unit.new(stats, 0)
	# Nasce vazia: `ResourcePool` enche no `_init`, e para a carga isso estaria
	# errado — daria a suprema de graça no primeiro segundo da partida.
	unit.ultimate_charge.current = 0.0
	return unit

func _suprema(custo_de_carga: bool = true) -> Ability:
	var ability := Ability.new()
	ability.id = &"suprema"
	ability.aim = Ability.Aim.SELF
	ability.cooldown = 0.0
	ability.uses_ultimate_charge = custo_de_carga
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 3.0
	pulse.hits_self = true
	var cura := HealEffect.new()
	cura.recipient = AbilityEffect.Recipient.CASTER
	cura.base_heal = 1.0
	pulse.effects = [cura]
	return ability

func _comum(ganho: float) -> Ability:
	var ability := Ability.new()
	ability.id = &"comum"
	ability.aim = Ability.Aim.SELF
	ability.cooldown = 0.0
	ability.ultimate_charge_gain = ganho
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 3.0
	pulse.hits_self = true
	var cura := HealEffect.new()
	cura.recipient = AbilityEffect.Recipient.CASTER
	cura.base_heal = 1.0
	pulse.effects = [cura]
	return ability

# ---------------------------------------------------------------- o portão

func test_a_suprema_nasce_indisponivel() -> void:
	var caster: Unit = _unit()
	assert_almost_eq(caster.ultimate_charge.current, 0.0)
	assert_false(caster.ultimate_is_ready(), "a suprema começou pronta")

	var result := AbilityEngine.cast(
		AbilityBook.new(), _suprema(), AbilityCast.on_self(caster), [caster]
	)
	assert_eq(result.status, CastResult.Status.NO_CHARGE)
	assert_almost_eq(result.charge_missing, 1000.0, "o que falta é informado")

func test_a_suprema_sai_com_a_carga_cheia_e_zera_depois() -> void:
	var caster: Unit = _unit()
	caster.gain_ultimate_charge(1000.0)
	assert_true(caster.ultimate_is_ready())

	var book := AbilityBook.new()
	var result := AbilityEngine.cast(
		book, _suprema(), AbilityCast.on_self(caster), [caster]
	)
	assert_true(result.succeeded(), "recusou com a carga cheia")
	assert_almost_eq(caster.ultimate_charge.current, 0.0, "não gastou a carga")
	assert_false(caster.ultimate_is_ready(), "continuou pronta depois de sair")

func test_carga_parcial_nao_basta() -> void:
	# Meia carga é o caso que separa "recurso" de "cooldown com outro nome".
	var caster: Unit = _unit()
	caster.gain_ultimate_charge(999.0)
	var result := AbilityEngine.cast(
		AbilityBook.new(), _suprema(), AbilityCast.on_self(caster), [caster]
	)
	assert_eq(result.status, CastResult.Status.NO_CHARGE)
	assert_almost_eq(result.charge_missing, 1.0)

func test_quem_nao_tem_carga_maxima_conjura_a_suprema_de_graca() -> void:
	# Mob, boneco de treino e habilidade feita à mão. Mesma convenção da mana:
	# `MAX_MANA` zero quer dizer "não usa recurso", não "nunca pode".
	var caster: Unit = _unit(0.0)
	var result := AbilityEngine.cast(
		AbilityBook.new(), _suprema(), AbilityCast.on_self(caster), [caster]
	)
	assert_true(result.succeeded(), "sem carga máxima, a suprema é livre")

# ---------------------------------------------------------------- o ganho

func test_conjurar_enche_a_suprema() -> void:
	var caster: Unit = _unit()
	var book := AbilityBook.new()
	AbilityEngine.cast(book, _comum(266.0), AbilityCast.on_self(caster), [caster])
	assert_almost_eq(caster.ultimate_charge.current, 266.0)

func test_o_ganho_para_no_teto() -> void:
	var caster: Unit = _unit()
	var book := AbilityBook.new()
	for _vez: int in 6:
		book.clear_cooldowns()
		AbilityEngine.cast(book, _comum(266.0), AbilityCast.on_self(caster), [caster])
	assert_almost_eq(
		caster.ultimate_charge.current, 1000.0, "a carga passou do custo"
	)

func test_o_ataque_basico_que_acerta_enche() -> void:
	# 200 por acerto nos 31 campeões — é o que mantém a suprema subindo quando
	# não há nada para conjurar.
	var caster: Unit = _unit()
	caster.ultimate_charge_on_attack = 200.0
	var alvo: Unit = _unit(0.0)
	alvo.team = 1

	caster.basic_attack(alvo)
	assert_almost_eq(caster.ultimate_charge.current, 200.0)
	caster.basic_attack(alvo)
	assert_almost_eq(caster.ultimate_charge.current, 400.0)

func test_o_ataque_basico_que_erra_nao_enche() -> void:
	# Cegueira. É a mesma linha que separa cegar de desarmar no resto do
	# sistema: o ataque sai, gasta a cadência, e não produz nada.
	var caster: Unit = _unit()
	caster.ultimate_charge_on_attack = 200.0
	caster.status.apply(StatusSet.Kind.BLIND, 5.0)
	var alvo: Unit = _unit(0.0)
	alvo.team = 1

	var result: DamageResult = caster.basic_attack(alvo)
	assert_true(result.missed, "o cego devia errar")
	assert_almost_eq(
		caster.ultimate_charge.current, 0.0, "ataque errado encheu a suprema"
	)

func test_o_ataque_esquivado_nao_enche() -> void:
	# Cegueira sai cedo em `basic_attack` e nunca chega na conta da carga; a
	# ESQUIVA não — ela vira `missed` lá dentro, e é o caso que o `if not
	# result.missed` existe para cobrir. Sem este teste, remover a checagem
	# passava verde.
	#
	# A esquiva é um sorteio, então a asserção não é "errou tantas vezes": é
	# **carga == 200 × acertos**.
	#
	# É o ÚNICO teste da suíte que cai no `randf()` global. `Damage.resolve`
	# aceita um gerador semeado, e `test_mitigacao.gd` usa isso em todos os
	# pontos probabilísticos dele — mas `Unit.basic_attack` não tem por onde
	# injetar semente. A consequência honesta: se um dia este teste falhar, a
	# falha não é reproduzível rodando de novo.
	#
	# E o teto do pote precisa ser folgado, senão a igualdade é FALSA — foi o
	# defeito desta versão: com teto 1000 e 40 ataques, ela só valia até 5
	# acertos, e `P(acertos >= 6) = 0,206`. A suíte falhava uma rodada em cinco,
	# e a mensagem de falha acusava "ataque errado encheu" quando a carga tinha
	# vindo de MENOS, por causa do teto. Mensagem de falha que aponta para o
	# lugar errado é pior que asserção fraca.
	var caster: Unit = _unit(100000.0)
	caster.ultimate_charge_on_attack = 200.0
	caster.ultimate_charge.current = 0.0

	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.MAX_HEALTH: 1000000.0,
		# Teto da esquiva. Em 40 ataques, nunca errar tem chance de 1e-40.
		Stat.Id.DODGE: 0.9,
	})
	var alvo := Unit.new(stats, 1)

	var acertos: int = 0
	for _vez: int in 40:
		if not caster.basic_attack(alvo).missed:
			acertos += 1
	assert_true(acertos < 40, "ninguém esquivou com 90% de esquiva")
	assert_almost_eq(
		caster.ultimate_charge.current, 200.0 * float(acertos),
		"a carga não bate com os acertos: ataque errado encheu"
	)

func test_a_carga_nao_sobe_com_a_regeneracao_de_mana() -> void:
	# O pote da carga é o mesmo `ResourcePool` da mana, com outro teto e SEM
	# atributo de regeneração. Ligá-lo em `MANA_REGEN` por engano faria a
	# suprema voltar a ser questão de esperar, e o teste do tempo não pegaria:
	# ele roda com regeneração zero.
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.MAX_MANA: 1000.0,
		Stat.Id.MANA_REGEN: 100.0,
		Stat.Id.MAX_ULTIMATE_CHARGE: 1000.0,
	})
	var caster := Unit.new(stats, 0)
	caster.mana.current = 0.0
	caster.ultimate_charge.current = 0.0

	for _tique: int in 60:
		caster.advance_time(1.0 / 60.0)

	assert_almost_eq(caster.mana.current, 100.0, "a mana devia regenerar")
	assert_almost_eq(
		caster.ultimate_charge.current, 0.0,
		"a carga regenerou junto com a mana"
	)

func test_a_carga_nao_sobe_com_o_tempo() -> void:
	# É a diferença entre carga e mana. Se ela regenerasse, a suprema voltaria a
	# ser uma questão de esperar — que é exatamente o que este sistema desfaz.
	var caster: Unit = _unit()
	caster.gain_ultimate_charge(300.0)
	for _tique: int in 600:
		caster.advance_time(1.0 / 60.0)
	assert_almost_eq(
		caster.ultimate_charge.current, 300.0,
		"a carga subiu sozinha em dez segundos"
	)

# ------------------------------------------------------- o corpus traduzido

func test_o_corpus_traz_o_ganho_de_carga() -> void:
	var catalogo := AbilityCatalog.new()
	catalogo.load_from()
	var com_ganho: int = 0
	for id: StringName in catalogo.by_id:
		if (catalogo.by_id[id] as Ability).ultimate_charge_gain > 0.0:
			com_ganho += 1
	assert_true(
		com_ganho > 500,
		"só %d habilidades enchem a suprema; o original tem 517" % com_ganho
	)

func test_todo_campeao_tem_como_encher_a_propria_suprema() -> void:
	# A conferência que fecha o laço: um campeão cuja suprema custa 1000 e cujo
	# kit rende zero teria uma suprema inalcançável — e nada acusaria, porque
	# cada peça isolada está certa.
	var atores := ActorCatalog.new()
	atores.load_from()
	var habilidades := AbilityCatalog.new()
	habilidades.load_from()

	var travados: Array[String] = []
	for profile: ActorProfile in atores.champions():
		if not profile.ultimate_uses_charge:
			continue
		var unit: Unit = profile.build_unit(9)
		var book := AbilityBook.new()
		profile.equip_book(book, habilidades, unit, 9)

		var por_rodada: float = unit.ultimate_charge_on_attack
		for ability: Ability in book.known_abilities():
			por_rodada += ability.ultimate_charge_gain
		if por_rodada <= 0.0:
			travados.append(String(profile.id))
	assert_eq(
		travados.size(), 0,
		"campeões com suprema inalcançável: %s" % str(travados.slice(0, 5))
	)

func test_o_ataque_basico_do_campeao_rende_carga() -> void:
	var atores := ActorCatalog.new()
	atores.load_from()
	var habilidades := AbilityCatalog.new()
	habilidades.load_from()
	var leo: ActorProfile = atores.get_profile(&"leo")
	assert_not_null(leo)
	if leo == null:
		return

	var unit: Unit = leo.build_unit(9)
	var book := AbilityBook.new()
	leo.equip_book(book, habilidades, unit, 9)
	assert_almost_eq(
		unit.ultimate_charge_on_attack, 200.0,
		"o ganho do ataque básico não chegou ao Unit"
	)
	assert_almost_eq(
		unit.ultimate_charge.maximum(), 1000.0,
		"o custo da suprema não virou atributo"
	)
	# **Nasce vazia.** `ResourcePool` enche no `_init` — o certo para a mana, e o
	# oposto do certo aqui: a suprema pronta no primeiro segundo da partida é o
	# contrário de um recurso que se ganha jogando.
	assert_almost_eq(
		unit.ultimate_charge.current, 0.0,
		"o campeão nasceu com a suprema pronta"
	)
