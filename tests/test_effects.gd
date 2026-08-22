extends TestCase

## Fase 3.1 — vocabulário de efeitos.
##
## Cada peça do vocabulário é exercida isolada. O que a Fase 3.2 vai testar é
## a composição delas numa habilidade.

func _unit(bases: Dictionary = {}, team: int = 0) -> Unit:
	var stats := Stats.new()
	stats.set_base(Stat.Id.MAX_HEALTH, 500.0)
	stats.set_base(Stat.Id.MOVE_SPEED, 5.0)
	stats.set_bases(bases)
	return Unit.new(stats, team)

func _cast(caster: Unit, target: Unit = null) -> AbilityCast:
	if target != null:
		return AbilityCast.on_unit(caster, target)
	return AbilityCast.on_self(caster)

# ---------------------------------------------------------------- DAMAGE

func test_dano_soma_base_e_escalonamento() -> void:
	var caster := _unit({Stat.Id.ABILITY_POWER: 200.0})
	var target := _unit({Stat.Id.MAGIC_RESIST: 0.0}, 1)

	var effect := DamageEffect.new()
	effect.base_damage = 80.0
	effect.scaling_stat = Stat.Id.ABILITY_POWER
	effect.scaling_ratio = 0.6
	effect.damage_type = Damage.Type.MAGIC

	effect.apply(_cast(caster, target), target)
	# 80 + 200*0.6 = 200, sem resistência
	assert_almost_eq(target.health.current, 300.0)

func test_dano_de_habilidade_nao_critita() -> void:
	var caster := _unit({
		Stat.Id.ABILITY_POWER: 0.0,
		Stat.Id.CRIT_CHANCE: 1.0,
		Stat.Id.CRIT_DAMAGE: 2.0,
	})
	var target := _unit({}, 1)

	var effect := DamageEffect.new()
	effect.base_damage = 100.0
	effect.damage_type = Damage.Type.TRUE
	effect.apply(_cast(caster, target), target)

	assert_almost_eq(target.health.current, 400.0, "sem dobrar")

func test_dano_em_alvo_morto_nao_faz_nada() -> void:
	var caster := _unit()
	var target := _unit({Stat.Id.MAX_HEALTH: 50.0}, 1)
	target.receive_damage(null, 999.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)
	assert_false(target.is_alive())

	var effect := DamageEffect.new()
	effect.base_damage = 100.0
	effect.apply(_cast(caster, target), target)
	assert_almost_eq(target.health.current, 0.0)

# ---------------------------------------------------------------- HEAL

func test_cura_escala_com_atributo() -> void:
	var caster := _unit({Stat.Id.ABILITY_POWER: 100.0})
	var target := _unit()
	target.receive_damage(null, 300.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)

	var effect := HealEffect.new()
	effect.base_heal = 50.0
	effect.scaling_ratio = 0.5
	effect.apply(_cast(caster, target), target)

	# 200 de vida + 50 + 100*0.5 = 300
	assert_almost_eq(target.health.current, 300.0)

# ---------------------------------------------------------------- SHIELD

func test_escudo_absorve_e_expira() -> void:
	var caster := _unit()
	var target := _unit()

	var effect := ShieldEffect.new()
	effect.base_shield = 120.0
	effect.duration = 3.0
	effect.apply(_cast(caster, target), target)
	assert_almost_eq(target.health.shield, 120.0)

	target.receive_damage(null, 50.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)
	assert_almost_eq(target.health.shield, 70.0, "consumiu")
	assert_almost_eq(target.health.current, 500.0, "vida intacta")

	target.advance_time(3.5)
	assert_almost_eq(target.health.shield, 0.0, "expirou")

func test_escudo_mais_curto_e_gasto_primeiro() -> void:
	# Gastar o de prazo longo antes desperdiçaria o curto, que sumiria sem ter
	# absorvido nada.
	var caster := _unit()
	var target := _unit()

	var longo := ShieldEffect.new()
	longo.base_shield = 100.0
	longo.duration = 10.0
	longo.apply(_cast(caster, target), target)

	var curto := ShieldEffect.new()
	curto.base_shield = 40.0
	curto.duration = 1.0
	curto.apply(_cast(caster, target), target)

	target.receive_damage(null, 40.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)
	target.advance_time(2.0)

	assert_almost_eq(target.health.shield, 100.0, "o longo sobreviveu inteiro")

# ---------------------------------------------------------------- STAT_MOD

func test_stat_mod_aplica_e_expira() -> void:
	var caster := _unit()
	var target := _unit({Stat.Id.ATTACK_DAMAGE: 50.0})

	var effect := StatModEffect.new()
	effect.stat = Stat.Id.ATTACK_DAMAGE
	effect.kind = StatModifier.Kind.FLAT
	effect.value = 40.0
	effect.duration = 4.0
	effect.source_tag = &"furia"
	effect.apply(_cast(caster, target), target)

	assert_almost_eq(target.stats.get_value(Stat.Id.ATTACK_DAMAGE), 90.0)
	assert_true(target.stats.has_source(&"buff:furia"), "origem rastreável")

	target.advance_time(5.0)
	assert_almost_eq(target.stats.get_value(Stat.Id.ATTACK_DAMAGE), 50.0)

# ---------------------------------------------------------------- CC

func test_stun_impede_tudo() -> void:
	var caster := _unit()
	var target := _unit({}, 1)

	var effect := CrowdControlEffect.new()
	effect.control = CrowdControlEffect.Kind.STUN
	effect.duration = 2.0
	effect.apply(_cast(caster, target), target)

	assert_false(target.can_move())
	assert_false(target.can_attack())
	assert_false(target.can_cast())

	target.advance_time(2.5)
	assert_true(target.can_move(), "expirou")

func test_root_prende_mas_deixa_atacar_e_conjurar() -> void:
	var target := _unit({}, 1)
	var effect := CrowdControlEffect.new()
	effect.control = CrowdControlEffect.Kind.ROOT
	effect.duration = 2.0
	effect.apply(_cast(_unit(), target), target)

	assert_false(target.can_move())
	assert_true(target.can_attack())
	assert_true(target.can_cast())

func test_silence_impede_conjurar_mas_nao_andar() -> void:
	var target := _unit({}, 1)
	var effect := CrowdControlEffect.new()
	effect.control = CrowdControlEffect.Kind.SILENCE
	effect.duration = 2.0
	effect.apply(_cast(_unit(), target), target)

	assert_false(target.can_cast())
	assert_true(target.can_move())
	assert_true(target.can_attack())

func test_slow_e_modificador_de_atributo_nao_estado() -> void:
	# Lentidão reusa o sistema de modificadores em vez de virar um estado
	# próprio — é literalmente um atributo reduzido por um tempo.
	var target := _unit({Stat.Id.MOVE_SPEED: 5.0}, 1)
	var effect := CrowdControlEffect.new()
	effect.control = CrowdControlEffect.Kind.SLOW
	effect.slow_amount = 0.4
	effect.duration = 3.0
	effect.apply(_cast(_unit(), target), target)

	assert_almost_eq(target.stats.get_value(Stat.Id.MOVE_SPEED), 3.0)
	assert_true(target.can_move(), "lentidão não é imobilização")
	assert_true(target.status.is_clear(), "não virou estado")

	target.advance_time(3.5)
	assert_almost_eq(target.stats.get_value(Stat.Id.MOVE_SPEED), 5.0)

func test_cc_reaplicado_pega_a_maior_duracao_e_nao_soma() -> void:
	var target := _unit({}, 1)
	var effect := CrowdControlEffect.new()
	effect.control = CrowdControlEffect.Kind.STUN

	effect.duration = 1.0
	effect.apply(_cast(_unit(), target), target)
	effect.duration = 0.5
	effect.apply(_cast(_unit(), target), target)

	assert_almost_eq(
		target.status.remaining(StatusSet.Kind.STUN), 1.0,
		"a menor não substitui a maior"
	)

	target.advance_time(1.2)
	assert_true(target.status.is_clear(), "1.0s e não 1.5s")

# ---------------------------------------------------------------- DISPLACEMENT

func test_dash_desloca_o_conjurador_e_nao_o_alvo() -> void:
	var caster := _unit()
	var target := _unit({}, 1)
	target.position = Vector3(5, 0, 0)

	var effect := DisplacementEffect.new()
	effect.mode = DisplacementEffect.Mode.DASH
	effect.distance = 4.0

	var cast := AbilityCast.toward(caster, Vector3(1, 0, 0))
	effect.apply(cast, target)

	assert_almost_eq(caster.consume_displacement().x, 4.0)
	assert_almost_eq(target.consume_displacement().length(), 0.0)

func test_knockback_empurra_o_alvo_para_longe() -> void:
	var caster := _unit()
	var target := _unit({}, 1)
	target.position = Vector3(3, 0, 0)

	var effect := DisplacementEffect.new()
	effect.mode = DisplacementEffect.Mode.KNOCKBACK
	effect.distance = 2.0
	effect.apply(AbilityCast.on_unit(caster, target), target)

	assert_almost_eq(target.consume_displacement().x, 2.0, "afastou no +X")

func test_pull_traz_o_alvo_para_perto() -> void:
	var caster := _unit()
	var target := _unit({}, 1)
	target.position = Vector3(3, 0, 0)

	var effect := DisplacementEffect.new()
	effect.mode = DisplacementEffect.Mode.PULL
	effect.distance = 2.0
	effect.apply(AbilityCast.on_unit(caster, target), target)

	assert_almost_eq(target.consume_displacement().x, -2.0, "aproximou")

func test_imobilizado_nao_da_dash() -> void:
	var caster := _unit()
	caster.status.apply(StatusSet.Kind.ROOT, 2.0)

	var effect := DisplacementEffect.new()
	effect.mode = DisplacementEffect.Mode.DASH
	effect.distance = 4.0
	effect.apply(AbilityCast.toward(caster, Vector3(1, 0, 0)), null)

	assert_almost_eq(caster.consume_displacement().length(), 0.0)

func test_empurrao_que_ignora_root_funciona_em_imobilizado() -> void:
	var caster := _unit()
	var target := _unit({}, 1)
	target.position = Vector3(3, 0, 0)
	target.status.apply(StatusSet.Kind.ROOT, 2.0)

	var effect := DisplacementEffect.new()
	effect.mode = DisplacementEffect.Mode.KNOCKBACK
	effect.distance = 2.0
	effect.ignores_root = true
	effect.apply(AbilityCast.on_unit(caster, target), target)

	assert_almost_eq(target.consume_displacement().x, 2.0)

func test_deslocamento_acumula_ate_ser_consumido() -> void:
	var caster := _unit()
	var effect := DisplacementEffect.new()
	effect.mode = DisplacementEffect.Mode.DASH
	effect.distance = 2.0

	var cast := AbilityCast.toward(caster, Vector3(1, 0, 0))
	effect.apply(cast, null)
	effect.apply(cast, null)

	assert_almost_eq(caster.consume_displacement().x, 4.0, "somou os dois")
	assert_almost_eq(caster.consume_displacement().x, 0.0, "consumir zera")

# ---------------------------------------------------------------- mira

func test_mira_em_si_mesmo_nao_produz_direcao_zero() -> void:
	# Mirar nos próprios pés produziria vetor zero, que quebraria a
	# normalização de qualquer forma direcional adiante.
	var caster := _unit()
	caster.facing = Vector3(0, 0, -1)
	var cast := AbilityCast.at_point(caster, caster.position)
	assert_almost_eq(cast.direction.length(), 1.0)
