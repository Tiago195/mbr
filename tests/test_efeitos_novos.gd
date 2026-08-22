extends TestCase

## Os efeitos que a tradução do original acrescentou ao vocabulário: periódico,
## gatilho, invocação, execução, recurso e purificação. Mais os campos novos de
## dano — percentual da vida do alvo, teto contra mob e restrição por espécie.
##
## O `03-sistemas-de-jogo.md` já listava SUMMON e TRIGGER e nenhum dos dois
## existia. Os outros quatro vieram das colunas de `impact_xml` que não cabiam
## em nada do que havia.

func _unit(values: Dictionary = {}, team: int = 0) -> Unit:
	var s := Stats.new()
	s.set_bases(values)
	return Unit.new(s, team)

func _damage(amount: float) -> DamageEffect:
	var effect := DamageEffect.new()
	effect.base_damage = amount
	effect.damage_type = Damage.Type.TRUE
	return effect

func _heal(amount: float) -> HealEffect:
	var effect := HealEffect.new()
	effect.base_heal = amount
	return effect

# ---------------------------------------------------------------- periódico

func test_periodico_bate_a_cada_intervalo() -> void:
	var caster: Unit = _unit()
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	var poison := PeriodicEffect.new()
	poison.effects = [_damage(10.0)]
	poison.interval = 1.0
	poison.duration = 3.0
	poison.apply(AbilityCast.on_unit(caster, victim), victim)

	assert_almost_eq(victim.health.current, 1000.0, "não bate ao aplicar")
	victim.advance_time(1.0)
	assert_almost_eq(victim.health.current, 990.0)
	victim.advance_time(1.0)
	victim.advance_time(1.0)
	assert_almost_eq(victim.health.current, 970.0, "três tiques em três segundos")

func test_periodico_para_no_prazo() -> void:
	var caster: Unit = _unit()
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	var poison := PeriodicEffect.new()
	poison.effects = [_damage(10.0)]
	poison.interval = 1.0
	poison.duration = 2.0
	poison.apply(AbilityCast.on_unit(caster, victim), victim)
	for i: int in range(10):
		victim.advance_time(1.0)
	assert_almost_eq(victim.health.current, 980.0, "só os dois tiques do prazo")
	assert_eq(victim.periodic.count(), 0)

func test_primeiro_tique_imediato_e_opcional() -> void:
	var caster: Unit = _unit()
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	var burn := PeriodicEffect.new()
	burn.effects = [_damage(10.0)]
	burn.interval = 1.0
	burn.duration = 2.0
	burn.ticks_on_apply = true
	burn.apply(AbilityCast.on_unit(caster, victim), victim)
	victim.advance_time(0.5)
	assert_almost_eq(victim.health.current, 990.0, "o primeiro sai no meio-tique")

func test_tique_longo_nao_perde_repeticao() -> void:
	# Um servidor de tick lento não pode aplicar menos veneno que um rápido.
	var caster: Unit = _unit()
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	var poison := PeriodicEffect.new()
	poison.effects = [_damage(10.0)]
	poison.interval = 0.5
	poison.duration = 2.0
	poison.apply(AbilityCast.on_unit(caster, victim), victim)
	victim.advance_time(2.0)
	assert_almost_eq(victim.health.current, 960.0, "quatro tiques num passo só")

func test_reaplicar_veneno_renova_em_vez_de_somar() -> void:
	var caster: Unit = _unit()
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	var poison := PeriodicEffect.new()
	poison.effects = [_damage(10.0)]
	poison.interval = 1.0
	poison.duration = 3.0
	var cast: AbilityCast = AbilityCast.on_unit(caster, victim)
	poison.apply(cast, victim)
	poison.apply(cast, victim)
	assert_eq(victim.periodic.count(), 1)
	victim.advance_time(1.0)
	assert_almost_eq(victim.health.current, 990.0, "um tique, não dois")

func test_periodico_de_cura_e_regeneracao() -> void:
	var healer: Unit = _unit()
	var wounded: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0})
	wounded.health.current = 100.0
	var regen := PeriodicEffect.new()
	regen.effects = [_heal(20.0)]
	regen.interval = 1.0
	regen.duration = 3.0
	regen.apply(AbilityCast.on_unit(healer, wounded), wounded)
	wounded.advance_time(3.0)
	assert_almost_eq(wounded.health.current, 160.0, "mesmo efeito, outra mecânica")

func test_periodico_permanente_nao_expira() -> void:
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	var aura := PeriodicEffect.new()
	aura.effects = [_damage(1.0)]
	aura.interval = 1.0
	aura.duration = -1.0
	aura.apply(AbilityCast.on_self(victim), victim)
	victim.advance_time(50.0)
	assert_eq(victim.periodic.count(), 1, "duração negativa é permanente")

func test_periodico_sai_pela_origem() -> void:
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	var aura := PeriodicEffect.new()
	aura.effects = [_damage(1.0)]
	aura.duration = -1.0
	aura.source_tag = &"botas"
	aura.apply(AbilityCast.on_self(victim), victim)
	assert_eq(victim.periodic.remove_source(&"periodico:botas"), 1)
	assert_eq(victim.periodic.count(), 0)

func test_periodico_nao_bate_em_morto() -> void:
	var caster: Unit = _unit()
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 15.0}, 1)
	var poison := PeriodicEffect.new()
	poison.effects = [_damage(10.0)]
	poison.interval = 1.0
	poison.duration = 5.0
	poison.apply(AbilityCast.on_unit(caster, victim), victim)
	victim.advance_time(5.0)
	assert_almost_eq(victim.health.current, 0.0, "para no zero, não vira negativo eterno")

# ---------------------------------------------------------------- gatilho

func test_gatilho_dispara_no_evento() -> void:
	var hero: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 10.0})
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0}, 1)
	var shield := ShieldEffect.new()
	shield.base_shield = 50.0
	shield.duration = 10.0
	var trigger := TriggerEffect.new()
	trigger.event = TriggerSet.Event.BASIC_ATTACK_HIT
	trigger.effects = [shield]
	shield.recipient = AbilityEffect.Recipient.CASTER
	trigger.apply(AbilityCast.on_self(hero), hero)

	assert_almost_eq(hero.health.shield, 0.0)
	hero.basic_attack(victim)
	assert_almost_eq(hero.health.shield, 50.0, "acertar deu escudo")

func test_gatilho_gasta_carga_e_sai() -> void:
	var hero: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 10.0})
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0}, 1)
	var heal := _heal(5.0)
	heal.recipient = AbilityEffect.Recipient.CASTER
	var trigger := TriggerEffect.new()
	trigger.effects = [heal]
	trigger.charges = 2
	trigger.apply(AbilityCast.on_self(hero), hero)

	hero.basic_attack(victim)
	hero.basic_attack(victim)
	assert_eq(hero.triggers.count(), 0, "duas cargas, duas vezes")
	hero.basic_attack(victim)
	assert_eq(hero.triggers.count(), 0)

func test_gatilho_de_dano_recebido() -> void:
	var hero: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0})
	var attacker: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 20.0}, 1)
	var speed := StatModEffect.new()
	speed.stat = Stat.Id.MOVE_SPEED
	speed.kind = StatModifier.Kind.PERCENT
	speed.value = 0.3
	speed.recipient = AbilityEffect.Recipient.CASTER
	var trigger := TriggerEffect.new()
	trigger.event = TriggerSet.Event.DAMAGE_TAKEN
	trigger.effects = [speed]
	trigger.apply(AbilityCast.on_self(hero), hero)

	hero.stats.set_base(Stat.Id.MOVE_SPEED, 100.0)
	attacker.basic_attack(hero)
	assert_almost_eq(hero.stats.get_value(Stat.Id.MOVE_SPEED), 130.0)

func test_gatilho_de_abate() -> void:
	var hero: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 500.0})
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 10.0}, 1)
	var heal := _heal(40.0)
	heal.recipient = AbilityEffect.Recipient.CASTER
	var trigger := TriggerEffect.new()
	trigger.event = TriggerSet.Event.KILL
	trigger.effects = [heal]
	trigger.apply(AbilityCast.on_self(hero), hero)

	hero.stats.set_base(Stat.Id.MAX_HEALTH, 200.0)
	hero.health.current = 100.0
	hero.basic_attack(victim)
	assert_almost_eq(hero.health.current, 140.0)

func test_invocacao_morta_nao_conta_como_abate() -> void:
	var hero: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 500.0})
	var wolf: Unit = _unit({Stat.Id.MAX_HEALTH: 10.0}, 1)
	wolf.nature = Unit.Nature.SUMMON
	var heal := _heal(40.0)
	heal.recipient = AbilityEffect.Recipient.CASTER
	var trigger := TriggerEffect.new()
	trigger.event = TriggerSet.Event.KILL
	trigger.effects = [heal]
	trigger.apply(AbilityCast.on_self(hero), hero)

	hero.stats.set_base(Stat.Id.MAX_HEALTH, 200.0)
	hero.health.current = 100.0
	hero.basic_attack(wolf)
	assert_almost_eq(hero.health.current, 100.0, "matar invocação não é abate")

func test_gatilho_de_escudo_quebrado() -> void:
	var hero: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0})
	var attacker: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 100.0}, 1)
	hero.health.add_shield(30.0)
	var burst := _damage(0.0)
	var trigger := TriggerEffect.new()
	trigger.event = TriggerSet.Event.SHIELD_BROKEN
	trigger.effects = [burst]
	trigger.apply(AbilityCast.on_self(hero), hero)
	var fired: Array[String] = []
	hero.triggers.fired.connect(func(_e: TriggerSet.Event, source: StringName) -> void:
		fired.append(String(source))
	)
	attacker.basic_attack(hero)
	assert_true(fired.size() >= 1, "quebrar o escudo disparou")

func test_gatilho_expira_e_solta_o_de_saida() -> void:
	var hero: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0})
	hero.health.current = 100.0
	var heal := _heal(50.0)
	heal.recipient = AbilityEffect.Recipient.CASTER
	var trigger := TriggerEffect.new()
	trigger.effects = [_damage(0.0)]
	trigger.on_expire = [heal]
	trigger.duration = 2.0
	trigger.apply(AbilityCast.on_self(hero), hero)

	hero.advance_time(1.0)
	assert_almost_eq(hero.health.current, 100.0, "ainda não venceu")
	hero.advance_time(1.5)
	assert_almost_eq(hero.health.current, 150.0, "ao vencer, explodiu")
	assert_eq(hero.triggers.count(), 0)

func test_rearmar_gatilho_nao_duplica() -> void:
	var hero: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 10.0, Stat.Id.MAX_HEALTH: 500.0})
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0}, 1)
	hero.health.current = 100.0
	var heal := _heal(10.0)
	heal.recipient = AbilityEffect.Recipient.CASTER
	var trigger := TriggerEffect.new()
	trigger.effects = [heal]
	var cast: AbilityCast = AbilityCast.on_self(hero)
	trigger.apply(cast, hero)
	trigger.apply(cast, hero)
	assert_eq(hero.triggers.count(), 1)
	hero.basic_attack(victim)
	assert_almost_eq(hero.health.current, 110.0, "curou uma vez, não duas")

func test_gatilho_de_habilidade_nao_dispara_com_ataque() -> void:
	var hero: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 10.0, Stat.Id.MAX_HEALTH: 500.0})
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0}, 1)
	hero.health.current = 100.0
	var heal := _heal(10.0)
	heal.recipient = AbilityEffect.Recipient.CASTER
	var trigger := TriggerEffect.new()
	trigger.event = TriggerSet.Event.ABILITY_HIT
	trigger.effects = [heal]
	trigger.apply(AbilityCast.on_self(hero), hero)
	hero.basic_attack(victim)
	assert_almost_eq(hero.health.current, 100.0)

# ---------------------------------------------------------------- invocação

func test_invocacao_entra_na_fila_de_quem_conjurou() -> void:
	var hero: Unit = _unit()
	hero.position = Vector3(5.0, 0.0, 0.0)
	var summon := SummonEffect.new()
	summon.actor_id = &"lobo"
	summon.lifetime = 12.0
	summon.origin = SummonEffect.Origin.CASTER
	summon.recipient = AbilityEffect.Recipient.CASTER
	summon.apply(AbilityCast.on_self(hero), hero)

	var requests: Array[Unit.SummonRequest] = hero.consume_summons()
	assert_eq(requests.size(), 1)
	assert_eq(requests[0].actor_id, &"lobo")
	assert_almost_eq(requests[0].lifetime, 12.0)
	assert_almost_eq(requests[0].position.x, 5.0)
	assert_eq(hero.consume_summons().size(), 0, "a fila esvazia ao consumir")

func test_invocacao_no_ponto_mirado() -> void:
	var hero: Unit = _unit()
	var summon := SummonEffect.new()
	summon.actor_id = &"totem"
	summon.recipient = AbilityEffect.Recipient.CASTER
	summon.apply(AbilityCast.at_point(hero, Vector3(0.0, 0.0, 8.0)), hero)
	assert_almost_eq(hero.consume_summons()[0].position.z, 8.0)

func test_invocacao_em_cima_do_alvo_fica_na_fila_do_conjurador() -> void:
	var hero: Unit = _unit()
	var victim: Unit = _unit({}, 1)
	victim.position = Vector3(0.0, 0.0, 4.0)
	var summon := SummonEffect.new()
	summon.actor_id = &"marca"
	summon.origin = SummonEffect.Origin.RECIPIENT
	summon.apply(AbilityCast.on_unit(hero, victim), victim)
	assert_eq(victim.pending_summons.size(), 0, "não é o inimigo que materializa")
	assert_almost_eq(hero.consume_summons()[0].position.z, 4.0)

func test_invocacao_herda_o_time() -> void:
	var hero: Unit = _unit({}, 7)
	var summon := SummonEffect.new()
	summon.actor_id = &"torre"
	summon.recipient = AbilityEffect.Recipient.CASTER
	summon.apply(AbilityCast.on_self(hero), hero)
	assert_eq(hero.consume_summons()[0].team, 7)

func test_invocacao_no_ponto_dispensa_alvo() -> void:
	var summon := SummonEffect.new()
	summon.origin = SummonEffect.Origin.AIM_POINT
	assert_false(summon.needs_target(), "armadilha no chão não precisa acertar ninguém")

# ---------------------------------------------------------------- execução

func test_execucao_mata_abaixo_do_limiar() -> void:
	var hero: Unit = _unit()
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	victim.health.current = 150.0
	var execute := ExecuteEffect.new()
	execute.health_threshold = 0.2
	execute.apply(AbilityCast.on_unit(hero, victim), victim)
	assert_false(victim.is_alive())

func test_execucao_poupa_acima_do_limiar() -> void:
	var hero: Unit = _unit()
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	victim.health.current = 300.0
	var execute := ExecuteEffect.new()
	execute.health_threshold = 0.2
	execute.apply(AbilityCast.on_unit(hero, victim), victim)
	assert_almost_eq(victim.health.current, 300.0)

func test_execucao_respeita_escudo() -> void:
	var hero: Unit = _unit()
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 1000.0}, 1)
	victim.health.current = 50.0
	victim.health.add_shield(400.0)
	var execute := ExecuteEffect.new()
	execute.apply(AbilityCast.on_unit(hero, victim), victim)
	assert_true(victim.is_alive(), "quem tem 400 de escudo não está caindo")

func test_execucao_dispara_o_gatilho_de_abate() -> void:
	var hero: Unit = _unit({Stat.Id.MAX_HEALTH: 400.0})
	hero.health.current = 100.0
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 100.0}, 1)
	var heal := _heal(30.0)
	heal.recipient = AbilityEffect.Recipient.CASTER
	var trigger := TriggerEffect.new()
	trigger.event = TriggerSet.Event.KILL
	trigger.effects = [heal]
	trigger.apply(AbilityCast.on_self(hero), hero)

	var execute := ExecuteEffect.new()
	execute.apply(AbilityCast.on_unit(hero, victim), victim)
	assert_false(victim.is_alive())
	assert_almost_eq(hero.health.current, 130.0, "matar pela execução ainda é matar")

func test_execucao_pode_poupar_campeao() -> void:
	var hero: Unit = _unit()
	var champion: Unit = _unit({Stat.Id.MAX_HEALTH: 100.0}, 1)
	var execute := ExecuteEffect.new()
	execute.affects_champions = false
	execute.apply(AbilityCast.on_unit(hero, champion), champion)
	assert_true(champion.is_alive())

func test_execucao_nao_passa_por_invulnerabilidade() -> void:
	var hero: Unit = _unit()
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 100.0}, 1)
	victim.status.apply(StatusSet.Kind.INVULNERABLE, 2.0)
	ExecuteEffect.new().apply(AbilityCast.on_unit(hero, victim), victim)
	assert_true(victim.is_alive())

# ---------------------------------------------------------------- recurso

func test_mana_e_gasta_e_devolvida() -> void:
	var hero: Unit = _unit({Stat.Id.MAX_MANA: 200.0})
	assert_almost_eq(hero.mana.current, 200.0, "começa cheio")
	assert_true(hero.mana.spend(50.0))
	assert_almost_eq(hero.mana.current, 150.0)
	var restore := ResourceEffect.new()
	restore.amount = 30.0
	restore.apply(AbilityCast.on_self(hero), hero)
	assert_almost_eq(hero.mana.current, 180.0)

func test_sem_mana_maxima_tudo_e_de_graca() -> void:
	var hero: Unit = _unit()
	assert_true(hero.mana.can_afford(999.0))
	assert_true(hero.mana.spend(999.0))
	assert_almost_eq(hero.mana.current, 0.0)

func test_nao_gasta_o_que_nao_tem() -> void:
	var hero: Unit = _unit({Stat.Id.MAX_MANA: 100.0})
	hero.mana.current = 20.0
	assert_false(hero.mana.spend(50.0))
	assert_almost_eq(hero.mana.current, 20.0, "recusar não pode cobrar")

func test_queimar_mana_leva_o_que_houver() -> void:
	var victim: Unit = _unit({Stat.Id.MAX_MANA: 100.0}, 1)
	victim.mana.current = 30.0
	var burn := ResourceEffect.new()
	burn.amount = -80.0
	burn.apply(AbilityCast.on_self(victim), victim)
	assert_almost_eq(victim.mana.current, 0.0, "drenar não é recusável")

func test_mana_percentual_le_o_maximo_do_alvo() -> void:
	var hero: Unit = _unit({Stat.Id.MAX_MANA: 400.0})
	hero.mana.current = 0.0
	var restore := ResourceEffect.new()
	restore.percent_of_max = 0.25
	restore.apply(AbilityCast.on_self(hero), hero)
	assert_almost_eq(hero.mana.current, 100.0)

func test_mana_regenera_no_tempo() -> void:
	var hero: Unit = _unit({Stat.Id.MAX_MANA: 100.0, Stat.Id.MANA_REGEN: 5.0})
	hero.mana.current = 0.0
	hero.advance_time(4.0)
	assert_almost_eq(hero.mana.current, 20.0)

func test_mana_nao_passa_do_teto() -> void:
	var hero: Unit = _unit({Stat.Id.MAX_MANA: 100.0, Stat.Id.MANA_REGEN: 50.0})
	hero.advance_time(10.0)
	assert_almost_eq(hero.mana.current, 100.0)

# ---------------------------------------------------------------- purificação

func test_purificacao_tira_controle() -> void:
	var hero: Unit = _unit()
	hero.status.apply(StatusSet.Kind.STUN, 3.0)
	hero.status.apply(StatusSet.Kind.SILENCE, 3.0)
	CleanseEffect.new().apply(AbilityCast.on_self(hero), hero)
	assert_true(hero.status.is_clear())

func test_purificacao_tira_lentidao() -> void:
	var hero: Unit = _unit({Stat.Id.MOVE_SPEED: 100.0})
	var slow := CrowdControlEffect.new()
	slow.control = CrowdControlEffect.Kind.SLOW
	slow.slow_amount = 0.5
	slow.duration = 5.0
	slow.apply(AbilityCast.on_self(hero), hero)
	assert_almost_eq(hero.stats.get_value(Stat.Id.MOVE_SPEED), 50.0)
	CleanseEffect.new().apply(AbilityCast.on_self(hero), hero)
	assert_almost_eq(hero.stats.get_value(Stat.Id.MOVE_SPEED), 100.0)

func test_purificacao_nao_tira_invulnerabilidade() -> void:
	var hero: Unit = _unit()
	hero.status.apply(StatusSet.Kind.INVULNERABLE, 3.0)
	hero.status.apply(StatusSet.Kind.STUN, 3.0)
	CleanseEffect.new().apply(AbilityCast.on_self(hero), hero)
	assert_false(hero.status.has(StatusSet.Kind.STUN))
	assert_true(hero.status.has(StatusSet.Kind.INVULNERABLE))

func test_dissipacao_tira_buff_e_deixa_controle() -> void:
	var victim: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 100.0}, 1)
	victim.status.apply(StatusSet.Kind.STUN, 3.0)
	var buff := StatModEffect.new()
	buff.stat = Stat.Id.ATTACK_DAMAGE
	buff.value = 50.0
	buff.duration = 10.0
	buff.apply(AbilityCast.on_self(victim), victim)
	assert_almost_eq(victim.stats.get_value(Stat.Id.ATTACK_DAMAGE), 150.0)

	var dispel := CleanseEffect.new()
	dispel.scope = CleanseEffect.Scope.BUFFS
	dispel.apply(AbilityCast.on_self(victim), victim)
	assert_almost_eq(victim.stats.get_value(Stat.Id.ATTACK_DAMAGE), 100.0)
	assert_true(victim.status.has(StatusSet.Kind.STUN), "controle fica")

func test_dissipacao_nao_desequipa_ninguem() -> void:
	var hero: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 100.0})
	hero.stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 40.0, &"item:espada"
	))
	var dispel := CleanseEffect.new()
	dispel.scope = CleanseEffect.Scope.EVERYTHING
	dispel.apply(AbilityCast.on_self(hero), hero)
	assert_almost_eq(
		hero.stats.get_value(Stat.Id.ATTACK_DAMAGE), 140.0,
		"bônus permanente de item não é buff"
	)

func test_purificacao_por_origem() -> void:
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0}, 1)
	var poison := PeriodicEffect.new()
	poison.effects = [_damage(10.0)]
	poison.duration = -1.0
	poison.source_tag = &"veneno"
	poison.apply(AbilityCast.on_self(victim), victim)
	var burn := PeriodicEffect.new()
	burn.effects = [_damage(10.0)]
	burn.duration = -1.0
	burn.source_tag = &"fogo"
	burn.apply(AbilityCast.on_self(victim), victim)

	var antidote := CleanseEffect.new()
	antidote.scope = CleanseEffect.Scope.BUFFS
	antidote.only_source = &"veneno"
	antidote.apply(AbilityCast.on_self(victim), victim)
	assert_eq(victim.periodic.count(), 1, "o fogo continua")

func test_dissipacao_pode_arrancar_escudo() -> void:
	var victim: Unit = _unit({}, 1)
	victim.health.add_shield(200.0)
	var strip := CleanseEffect.new()
	strip.scope = CleanseEffect.Scope.BUFFS
	strip.strips_shield = true
	strip.apply(AbilityCast.on_self(victim), victim)
	assert_almost_eq(victim.health.shield, 0.0)

func test_purificacao_comum_deixa_o_escudo() -> void:
	var hero: Unit = _unit()
	hero.health.add_shield(200.0)
	CleanseEffect.new().apply(AbilityCast.on_self(hero), hero)
	assert_almost_eq(hero.health.shield, 200.0)

# ---------------------------------------------------------------- invulnerável

func test_invulneravel_nao_sofre_dano() -> void:
	var hero: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0})
	var attacker: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 200.0}, 1)
	hero.status.apply(StatusSet.Kind.INVULNERABLE, 2.0)
	attacker.basic_attack(hero)
	assert_almost_eq(hero.health.current, 500.0)

func test_invulneravel_ainda_e_alvo_de_controle() -> void:
	var hero: Unit = _unit()
	hero.status.apply(StatusSet.Kind.INVULNERABLE, 2.0)
	var stun := CrowdControlEffect.new()
	stun.duration = 1.5
	stun.apply(AbilityCast.on_self(hero), hero)
	assert_true(hero.status.has(StatusSet.Kind.STUN), "imune a dano não é imune a tudo")

# ---------------------------------------------------------------- dano novo

func test_dano_percentual_da_vida_do_alvo() -> void:
	var hero: Unit = _unit()
	var tank: Unit = _unit({Stat.Id.MAX_HEALTH: 4000.0}, 1)
	var effect := DamageEffect.new()
	effect.base_damage = 50.0
	effect.percent_of_target_max_health = 0.05
	effect.damage_type = Damage.Type.TRUE
	effect.apply(AbilityCast.on_unit(hero, tank), tank)
	assert_almost_eq(tank.health.current, 3750.0, "50 + 5% de 4000")

func test_teto_contra_mob_corta_o_bruto() -> void:
	var hero: Unit = _unit()
	var mob: Unit = _unit({Stat.Id.MAX_HEALTH: 5000.0}, 1)
	mob.nature = Unit.Nature.MONSTER
	var effect := DamageEffect.new()
	effect.percent_of_target_max_health = 0.1
	effect.monster_damage_cap = 200.0
	effect.damage_type = Damage.Type.TRUE
	effect.apply(AbilityCast.on_unit(hero, mob), mob)
	assert_almost_eq(mob.health.current, 4800.0, "500 virariam 200")

func test_teto_de_mob_nao_afeta_campeao() -> void:
	var hero: Unit = _unit()
	var champ: Unit = _unit({Stat.Id.MAX_HEALTH: 5000.0}, 1)
	var effect := DamageEffect.new()
	effect.percent_of_target_max_health = 0.1
	effect.monster_damage_cap = 200.0
	effect.damage_type = Damage.Type.TRUE
	effect.apply(AbilityCast.on_unit(hero, champ), champ)
	assert_almost_eq(champ.health.current, 4500.0)

func test_dano_de_cerco_so_pega_estrutura() -> void:
	var hero: Unit = _unit()
	var champ: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0}, 1)
	var wall: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0}, 1)
	wall.nature = Unit.Nature.STRUCTURE
	var effect := DamageEffect.new()
	effect.base_damage = 100.0
	effect.damage_type = Damage.Type.TRUE
	effect.restriction = DamageEffect.Restriction.STRUCTURES_ONLY
	effect.apply(AbilityCast.on_unit(hero, champ), champ)
	effect.apply(AbilityCast.on_unit(hero, wall), wall)
	assert_almost_eq(champ.health.current, 500.0, "gente não sofre dano de cerco")
	assert_almost_eq(wall.health.current, 400.0)
