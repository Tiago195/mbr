extends TestCase

## As últimas quatro peças que a tradução exigiu: marca com pilhas, ajuste de
## recarga, teleporte e escalonamento pelo maior atributo. Mais a redução plana
## de dano sofrido.
##
## Todas nasceram de uma coluna do original que não cabia em nada do que havia
## — e todas foram escolhidas para caber no vocabulário em vez de virarem
## sistema próprio. É a regra do projeto: habilidade nova não escreve classe
## nova, e quando escreve, a classe vira vocabulário para todas as seguintes.

func _unit(values: Dictionary = {}, team: int = 0) -> Unit:
	var s := Stats.new()
	s.set_bases(values)
	return Unit.new(s, team)

# ---------------------------------------------------------------- marca

func test_marca_acumula_ate_o_teto() -> void:
	var alvo: Unit = _unit()
	assert_eq(alvo.marks.apply(&"resolucao", 5.0, 3), 1)
	assert_eq(alvo.marks.apply(&"resolucao", 5.0, 3), 2)
	assert_eq(alvo.marks.apply(&"resolucao", 5.0, 3), 3)
	assert_eq(alvo.marks.apply(&"resolucao", 5.0, 3), 3, "não passa do teto")
	assert_true(alvo.marks.is_full(&"resolucao"))

func test_reaplicar_marca_renova_o_prazo() -> void:
	var alvo: Unit = _unit()
	alvo.marks.apply(&"marca", 5.0, 3)
	alvo.advance_time(4.0)
	assert_almost_eq(alvo.marks.remaining(&"marca"), 1.0)
	alvo.marks.apply(&"marca", 5.0, 3)
	assert_almost_eq(alvo.marks.remaining(&"marca"), 5.0, "o prazo volta ao cheio")
	assert_eq(alvo.marks.stacks_of(&"marca"), 2, "e a pilha soma")

func test_marca_expira_no_prazo() -> void:
	var alvo: Unit = _unit()
	alvo.marks.apply(&"marca", 2.0)
	alvo.advance_time(1.0)
	assert_true(alvo.marks.has(&"marca"))
	alvo.advance_time(1.5)
	assert_false(alvo.marks.has(&"marca"))

func test_marca_permanente_nao_expira() -> void:
	var alvo: Unit = _unit()
	alvo.marks.apply(&"postura", -1.0)
	alvo.advance_time(999.0)
	assert_true(alvo.marks.has(&"postura"))

func test_consumir_gasta_pilha_a_pilha() -> void:
	var alvo: Unit = _unit()
	alvo.marks.apply(&"marca", 5.0, 3)
	alvo.marks.apply(&"marca", 5.0, 3)
	alvo.marks.apply(&"marca", 5.0, 3)
	assert_eq(alvo.marks.consume(&"marca", 2), 1)
	assert_true(alvo.marks.has(&"marca"))
	assert_eq(alvo.marks.consume(&"marca"), 0)
	assert_false(alvo.marks.has(&"marca"), "zerou, sumiu")

func test_efeito_de_marca_aplica_e_limpa() -> void:
	var alvo: Unit = _unit()
	var marcar := MarkEffect.new()
	marcar.mark = &"caca"
	marcar.duration = 4.0
	marcar.max_stacks = 2
	marcar.apply(AbilityCast.on_self(alvo), alvo)
	assert_eq(alvo.marks.stacks_of(&"caca"), 1)

	var limpar := MarkEffect.new()
	limpar.mark = &"caca"
	limpar.mode = MarkEffect.Mode.CLEAR
	limpar.apply(AbilityCast.on_self(alvo), alvo)
	assert_false(alvo.marks.has(&"caca"))

func test_encher_a_marca_dispara_o_gatilho() -> void:
	# "Acerte três vezes e o quarto atordoa" — a composição que justifica a
	# marca existir, montada só com peças do vocabulário.
	var heroi: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0})
	heroi.health.current = 100.0

	var cura := HealEffect.new()
	cura.base_heal = 60.0
	cura.recipient = AbilityEffect.Recipient.CASTER
	var gatilho := TriggerEffect.new()
	gatilho.event = TriggerSet.Event.MARK_MAXED
	gatilho.effects = [cura]
	gatilho.apply(AbilityCast.on_self(heroi), heroi)

	var marcar := MarkEffect.new()
	marcar.mark = &"combo"
	marcar.max_stacks = 3
	marcar.duration = 10.0
	var mira: AbilityCast = AbilityCast.on_self(heroi)

	marcar.apply(mira, heroi)
	marcar.apply(mira, heroi)
	assert_almost_eq(heroi.health.current, 100.0, "duas pilhas ainda não enchem")
	marcar.apply(mira, heroi)
	assert_almost_eq(heroi.health.current, 160.0, "a terceira encheu e disparou")

func test_marca_cheia_nao_dispara_de_novo() -> void:
	var heroi: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0})
	heroi.health.current = 100.0
	var cura := HealEffect.new()
	cura.base_heal = 10.0
	cura.recipient = AbilityEffect.Recipient.CASTER
	var gatilho := TriggerEffect.new()
	gatilho.event = TriggerSet.Event.MARK_MAXED
	gatilho.effects = [cura]
	gatilho.apply(AbilityCast.on_self(heroi), heroi)

	var marcar := MarkEffect.new()
	marcar.mark = &"combo"
	marcar.max_stacks = 1
	marcar.duration = 10.0
	var mira: AbilityCast = AbilityCast.on_self(heroi)
	marcar.apply(mira, heroi)
	marcar.apply(mira, heroi)
	marcar.apply(mira, heroi)
	assert_almost_eq(
		heroi.health.current, 110.0,
		"só a TRANSIÇÃO para cheio dispara, não toda reaplicação no teto"
	)

# ---------------------------------------------------------------- recarga

func _habilidade(id: StringName, grupo: StringName, recarga: float) -> Ability:
	var ability := Ability.new()
	ability.id = id
	ability.group_id = grupo
	ability.cooldown = recarga
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 3.0
	var dano := DamageEffect.new()
	dano.base_damage = 10.0
	dano.damage_type = Damage.Type.TRUE
	pulse.effects = [dano]
	return ability

func test_efeito_de_recarga_encurta_o_grupo_certo() -> void:
	var heroi: Unit = _unit()
	var investida: Ability = _habilidade(&"investida", &"g_investida", 12.0)
	var raio: Ability = _habilidade(&"raio", &"g_raio", 8.0)
	var book := AbilityBook.new()
	book.learn(AbilityBook.Slot.Q, investida)
	book.learn(AbilityBook.Slot.W, raio)
	book.start_cooldown(investida, heroi)
	book.start_cooldown(raio, heroi)

	var efeito := CooldownEffect.new()
	efeito.group_ids = [&"g_investida"]
	efeito.seconds = -5.0
	efeito.apply(AbilityCast.on_self(heroi), heroi)
	assert_eq(book.apply_cooldown_requests(heroi), 1)

	assert_almost_eq(book.remaining_cooldown(investida), 7.0)
	assert_almost_eq(book.remaining_cooldown(raio), 8.0, "o outro não foi tocado")

func test_recarga_sem_grupo_alcanca_todas() -> void:
	var heroi: Unit = _unit()
	var a: Ability = _habilidade(&"a", &"ga", 10.0)
	var b: Ability = _habilidade(&"b", &"gb", 10.0)
	var book := AbilityBook.new()
	book.learn(AbilityBook.Slot.Q, a)
	book.learn(AbilityBook.Slot.W, b)
	book.start_cooldown(a, heroi)
	book.start_cooldown(b, heroi)

	var efeito := CooldownEffect.new()
	efeito.seconds = -3.0
	efeito.apply(AbilityCast.on_self(heroi), heroi)
	book.apply_cooldown_requests(heroi)
	assert_almost_eq(book.remaining_cooldown(a), 7.0)
	assert_almost_eq(book.remaining_cooldown(b), 7.0)

func test_recarga_proporcional_le_o_total() -> void:
	var heroi: Unit = _unit()
	var lenta: Ability = _habilidade(&"lenta", &"g", 40.0)
	var book := AbilityBook.new()
	book.learn(AbilityBook.Slot.Q, lenta)
	book.start_cooldown(lenta, heroi)

	var efeito := CooldownEffect.new()
	efeito.seconds = -0.5
	efeito.proportional = true
	efeito.apply(AbilityCast.on_self(heroi), heroi)
	book.apply_cooldown_requests(heroi)
	assert_almost_eq(book.remaining_cooldown(lenta), 20.0)

func test_recarga_positiva_estende() -> void:
	var heroi: Unit = _unit()
	var a: Ability = _habilidade(&"a", &"ga", 10.0)
	var book := AbilityBook.new()
	book.learn(AbilityBook.Slot.Q, a)
	book.start_cooldown(a, heroi)

	var efeito := CooldownEffect.new()
	efeito.seconds = 4.0
	efeito.apply(AbilityCast.on_self(heroi), heroi)
	book.apply_cooldown_requests(heroi)
	assert_almost_eq(book.remaining_cooldown(a), 14.0, "punição por errar")

func test_recarga_nunca_fica_negativa() -> void:
	var heroi: Unit = _unit()
	var a: Ability = _habilidade(&"a", &"ga", 5.0)
	var book := AbilityBook.new()
	book.learn(AbilityBook.Slot.Q, a)
	book.start_cooldown(a, heroi)

	var efeito := CooldownEffect.new()
	efeito.seconds = -99.0
	efeito.apply(AbilityCast.on_self(heroi), heroi)
	book.apply_cooldown_requests(heroi)
	assert_almost_eq(book.remaining_cooldown(a), 0.0)
	assert_true(book.is_ready(a))

func test_a_fila_de_recarga_esvazia() -> void:
	var heroi: Unit = _unit()
	var efeito := CooldownEffect.new()
	efeito.seconds = -1.0
	efeito.apply(AbilityCast.on_self(heroi), heroi)
	assert_eq(heroi.pending_cooldown_adjustments.size(), 1)
	assert_eq(heroi.consume_cooldown_adjustments().size(), 1)
	assert_eq(heroi.pending_cooldown_adjustments.size(), 0)

# ---------------------------------------------------------------- teleporte

func test_teleporte_leva_ao_ponto_mirado() -> void:
	var heroi: Unit = _unit()
	heroi.position = Vector3(2.0, 0.0, 3.0)
	var salto := DisplacementEffect.new()
	salto.mode = DisplacementEffect.Mode.TO_AIM_POINT
	salto.recipient = AbilityEffect.Recipient.CASTER
	salto.apply(AbilityCast.at_point(heroi, Vector3(10.0, 0.0, 3.0)), heroi)
	assert_almost_eq(heroi.pending_displacement.x, 8.0)
	assert_almost_eq(heroi.pending_displacement.z, 0.0)

func test_teleporte_ignora_massa() -> void:
	var pesado: Unit = _unit({Stat.Id.WEIGHT: 5.0}, 1)
	var conjurador: Unit = _unit()
	var salto := DisplacementEffect.new()
	salto.mode = DisplacementEffect.Mode.TO_AIM_POINT
	salto.ignores_root = true
	salto.apply(AbilityCast.at_point(conjurador, Vector3(6.0, 0.0, 0.0)), pesado)
	assert_almost_eq(
		pesado.pending_displacement.length(), 6.0,
		"ou vai, ou não vai — peso não encurta teleporte"
	)

# ---------------------------------------------------------------- híbrido

func test_escalonamento_pega_o_maior_atributo() -> void:
	var mago: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 20.0, Stat.Id.ABILITY_POWER: 200.0})
	var alvo: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	var efeito := DamageEffect.new()
	efeito.scaling_stat = Stat.Id.ATTACK_DAMAGE
	efeito.scaling_stat_alt = Stat.Id.ABILITY_POWER
	efeito.scaling_ratio = 0.5
	efeito.damage_type = Damage.Type.TRUE
	efeito.apply(AbilityCast.on_unit(mago, alvo), alvo)
	assert_almost_eq(alvo.health.current, 900.0, "usou os 200 de poder, não os 20")

func test_escalonamento_hibrido_serve_os_dois_lados() -> void:
	var guerreiro: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 300.0, Stat.Id.ABILITY_POWER: 0.0})
	var alvo: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	var efeito := DamageEffect.new()
	efeito.scaling_stat = Stat.Id.ATTACK_DAMAGE
	efeito.scaling_stat_alt = Stat.Id.ABILITY_POWER
	efeito.scaling_ratio = 0.5
	efeito.damage_type = Damage.Type.TRUE
	efeito.apply(AbilityCast.on_unit(guerreiro, alvo), alvo)
	assert_almost_eq(alvo.health.current, 850.0, "a mesma habilidade serve o outro caminho")

func test_sem_alternativo_nada_muda() -> void:
	var heroi: Unit = _unit({Stat.Id.ABILITY_POWER: 100.0})
	var alvo: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	var efeito := DamageEffect.new()
	efeito.scaling_ratio = 0.5
	efeito.damage_type = Damage.Type.TRUE
	efeito.apply(AbilityCast.on_unit(heroi, alvo), alvo)
	assert_almost_eq(alvo.health.current, 950.0)

# ---------------------------------------------------------------- mitigação plana

func test_reducao_plana_corta_todo_dano() -> void:
	var resistente: Unit = _unit({
		Stat.Id.MAX_HEALTH: 1000.0, Stat.Id.DAMAGE_TAKEN_REDUCTION: 0.25
	}, 1)
	var atacante: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 100.0})
	atacante.basic_attack(resistente)
	assert_almost_eq(resistente.health.current, 925.0)

func test_reducao_plana_pega_ate_dano_verdadeiro() -> void:
	var resistente: Unit = _unit({
		Stat.Id.MAX_HEALTH: 1000.0, Stat.Id.DAMAGE_TAKEN_REDUCTION: 0.5
	}, 1)
	resistente.receive_damage(null, 200.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)
	assert_almost_eq(
		resistente.health.current, 900.0,
		"é a única mitigação que alcança dano verdadeiro"
	)

func test_reducao_plana_nao_cura() -> void:
	var absurdo: Unit = _unit({
		Stat.Id.MAX_HEALTH: 1000.0, Stat.Id.DAMAGE_TAKEN_REDUCTION: 3.0
	}, 1)
	absurdo.receive_damage(null, 200.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)
	assert_almost_eq(absurdo.health.current, 1000.0, "o piso é zero, não dano negativo")
