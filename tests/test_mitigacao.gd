extends TestCase

## Atributos que a tradução do original trouxe e que mexem no cálculo de dano,
## de cura e de escudo — esquiva, resistência a crítico, amplificação, poder de
## cura, teto de escudo, tenacidade, resistência a lentidão e massa.
##
## Todos foram escritos com o padrão neutro em mente: sem o atributo definido,
## o resultado tem que ser IDÊNTICO ao de antes da tradução. Um atributo novo
## que muda o jogo de quem não o equipou é um bug, não uma funcionalidade.

func _stats(values: Dictionary = {}) -> Stats:
	var s := Stats.new()
	s.set_bases(values)
	return s

func _unit(values: Dictionary = {}, team: int = 0) -> Unit:
	return Unit.new(_stats(values), team)

## RNG semeado para o sorteio de esquiva e de crítico sair reprodutível.
func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

# ---------------------------------------------------------------- esquiva

func test_sem_esquiva_nada_muda() -> void:
	var result: DamageResult = Damage.resolve(
		_stats(), _stats(), 100.0, 0.0, 50.0,
		Damage.Type.TRUE, Damage.Source.BASIC_ATTACK, _rng(1)
	)
	assert_false(result.missed, "sem o atributo, ninguém esquiva")
	assert_almost_eq(result.final_damage, 50.0)

func test_esquiva_total_erra_sempre() -> void:
	# 0.9 é o teto; com ele, qualquer sorteio abaixo de 0.9 erra. Rodo várias
	# vezes para não depender de uma semente sortuda.
	var missed: int = 0
	for i: int in range(40):
		var result: DamageResult = Damage.resolve(
			_stats(), _stats({Stat.Id.DODGE: 1.0}), 100.0, 0.0, 50.0,
			Damage.Type.TRUE, Damage.Source.BASIC_ATTACK, _rng(i)
		)
		if result.missed:
			missed += 1
	assert_true(missed >= 34, "esperava quase tudo errando, errou %d/40" % missed)

func test_esquiva_nao_gasta_escudo_nem_cura() -> void:
	var target: Stats = _stats({Stat.Id.DODGE: 1.0})
	var attacker: Stats = _stats({Stat.Id.LIFESTEAL: 1.0})
	var result: DamageResult = Damage.resolve(
		attacker, target, 100.0, 80.0, 50.0,
		Damage.Type.TRUE, Damage.Source.BASIC_ATTACK, _rng(3)
	)
	assert_true(result.missed)
	assert_almost_eq(result.shield_after, 80.0, "escudo intacto ao errar")
	assert_almost_eq(result.health_after, 100.0, "vida intacta ao errar")
	assert_almost_eq(result.lifesteal_healed, 0.0, "errar não rouba vida")

func test_precisao_anula_esquiva() -> void:
	# Precisão 1.5 contra esquiva 0.4: 0.4 - 0.5 = negativo, ninguém erra.
	var missed: int = 0
	for i: int in range(20):
		var result: DamageResult = Damage.resolve(
			_stats({Stat.Id.ACCURACY: 1.5}), _stats({Stat.Id.DODGE: 0.4}),
			100.0, 0.0, 50.0,
			Damage.Type.TRUE, Damage.Source.BASIC_ATTACK, _rng(i)
		)
		if result.missed:
			missed += 1
	assert_eq(missed, 0, "precisão suficiente não deve errar nunca")

func test_habilidade_nao_e_esquivavel() -> void:
	var result: DamageResult = Damage.resolve(
		_stats(), _stats({Stat.Id.DODGE: 1.0}), 100.0, 0.0, 50.0,
		Damage.Type.TRUE, Damage.Source.ABILITY, _rng(2)
	)
	assert_false(result.missed, "esquivar de habilidade é sair do caminho")

# ---------------------------------------------------------------- crítico

func test_resistencia_a_critico_reduz_a_chance() -> void:
	var crits: int = 0
	for i: int in range(30):
		var result: DamageResult = Damage.resolve(
			_stats({Stat.Id.CRIT_CHANCE: 0.5}),
			_stats({Stat.Id.CRIT_AVOIDANCE: 0.5}),
			100.0, 0.0, 50.0,
			Damage.Type.TRUE, Damage.Source.BASIC_ATTACK, _rng(i)
		)
		if result.was_critical:
			crits += 1
	assert_eq(crits, 0, "50%% de chance contra 50%% de esquiva de crítico = 0")

func test_reducao_de_dano_critico_corta_so_o_excesso() -> void:
	# Multiplicador 2.0, redução 0.5 -> 1 + (2-1)*0.5 = 1.5
	var result: DamageResult = Damage.resolve(
		_stats({Stat.Id.CRIT_CHANCE: 1.0, Stat.Id.CRIT_DAMAGE: 2.0}),
		_stats({Stat.Id.CRIT_DAMAGE_REDUCTION: 0.5}),
		1000.0, 0.0, 100.0,
		Damage.Type.TRUE, Damage.Source.BASIC_ATTACK, _rng(7)
	)
	assert_true(result.was_critical)
	assert_almost_eq(result.final_damage, 150.0)

func test_reducao_de_critico_nunca_bate_menos_que_normal() -> void:
	var result: DamageResult = Damage.resolve(
		_stats({Stat.Id.CRIT_CHANCE: 1.0, Stat.Id.CRIT_DAMAGE: 2.0}),
		_stats({Stat.Id.CRIT_DAMAGE_REDUCTION: 5.0}),
		1000.0, 0.0, 100.0,
		Damage.Type.TRUE, Damage.Source.BASIC_ATTACK, _rng(7)
	)
	assert_almost_eq(result.final_damage, 100.0, "o piso do crítico é o acerto normal")

# ---------------------------------------------------------------- amplificação

func test_amplificacao_fisica_multiplica_depois_da_defesa() -> void:
	# Armadura 100 -> multiplicador 0.5. Amp 0.2 -> x1.2. 100*0.5*1.2 = 60
	var result: DamageResult = Damage.resolve(
		_stats({Stat.Id.PHYSICAL_DAMAGE_AMP: 0.2}),
		_stats({Stat.Id.ARMOR: 100.0}),
		1000.0, 0.0, 100.0,
		Damage.Type.PHYSICAL, Damage.Source.ABILITY
	)
	assert_almost_eq(result.final_damage, 60.0)

func test_amplificacao_magica_nao_afeta_dano_fisico() -> void:
	var result: DamageResult = Damage.resolve(
		_stats({Stat.Id.MAGIC_DAMAGE_AMP: 1.0}),
		_stats(),
		1000.0, 0.0, 100.0,
		Damage.Type.PHYSICAL, Damage.Source.ABILITY
	)
	assert_almost_eq(result.final_damage, 100.0, "amp mágica não toca dano físico")

func test_dano_verdadeiro_nao_amplifica() -> void:
	var result: DamageResult = Damage.resolve(
		_stats({Stat.Id.PHYSICAL_DAMAGE_AMP: 1.0, Stat.Id.MAGIC_DAMAGE_AMP: 1.0}),
		_stats(),
		1000.0, 0.0, 100.0,
		Damage.Type.TRUE, Damage.Source.ABILITY
	)
	assert_almost_eq(result.final_damage, 100.0, "verdadeiro já ignora tudo")

# ---------------------------------------------------------------- cura

func test_poder_de_cura_e_de_quem_cura() -> void:
	var healer: Unit = _unit({Stat.Id.HEAL_POWER: 0.5})
	var wounded: Unit = _unit({Stat.Id.MAX_HEALTH: 500.0})
	wounded.health.current = 100.0
	assert_almost_eq(wounded.receive_heal(100.0, healer), 150.0)

func test_cura_recebida_e_de_quem_recebe() -> void:
	var wounded: Unit = _unit({
		Stat.Id.MAX_HEALTH: 500.0, Stat.Id.HEAL_RECEIVED_AMP: -0.4
	})
	wounded.health.current = 100.0
	assert_almost_eq(wounded.receive_heal(100.0), 60.0, "cura reduzida em 40%%")

func test_os_dois_multiplicadores_se_compoem() -> void:
	var healer: Unit = _unit({Stat.Id.HEAL_POWER: 1.0})
	var wounded: Unit = _unit({
		Stat.Id.MAX_HEALTH: 900.0, Stat.Id.HEAL_RECEIVED_AMP: 0.5
	})
	wounded.health.current = 100.0
	assert_almost_eq(wounded.receive_heal(100.0, healer), 300.0)

func test_cura_percentual_le_a_vida_do_alvo() -> void:
	var caster: Unit = _unit()
	var big: Unit = _unit({Stat.Id.MAX_HEALTH: 2000.0})
	big.health.current = 100.0
	var effect := HealEffect.new()
	effect.percent_of_max_health = 0.1
	var cast := AbilityCast.on_self(caster)
	effect.apply(cast, big)
	assert_almost_eq(big.health.current, 300.0, "10%% de 2000 = 200")

# ---------------------------------------------------------------- escudo

func test_escudo_recebido_amplificado() -> void:
	var unit: Unit = _unit({Stat.Id.SHIELD_RECEIVED_AMP: 0.5})
	unit.health.add_shield(100.0)
	assert_almost_eq(unit.health.shield, 150.0)

func test_teto_de_escudo_corta_o_excesso() -> void:
	var unit: Unit = _unit({Stat.Id.SHIELD_CAP: 120.0})
	unit.health.add_shield(100.0)
	unit.health.add_shield(100.0)
	assert_almost_eq(unit.health.shield, 120.0, "a segunda camada entra pelo que couber")

func test_teto_zero_nao_e_teto() -> void:
	var unit: Unit = _unit()
	unit.health.add_shield(500.0)
	assert_almost_eq(unit.health.shield, 500.0, "teto 0 é ausência de teto")

# ---------------------------------------------------------------- controle

func test_tenacidade_encurta_o_controle() -> void:
	var target: Unit = _unit({Stat.Id.TENACITY: 0.5})
	var effect := CrowdControlEffect.new()
	effect.control = CrowdControlEffect.Kind.STUN
	effect.duration = 2.0
	effect.apply(AbilityCast.on_self(_unit()), target)
	assert_almost_eq(target.status.remaining(StatusSet.Kind.STUN), 1.0)

func test_controle_duro_ignora_tenacidade() -> void:
	var target: Unit = _unit({Stat.Id.TENACITY: 0.8})
	var effect := CrowdControlEffect.new()
	effect.control = CrowdControlEffect.Kind.AIRBORNE
	effect.duration = 2.0
	effect.ignores_tenacity = true
	effect.apply(AbilityCast.on_self(_unit()), target)
	assert_almost_eq(target.status.remaining(StatusSet.Kind.AIRBORNE), 2.0)

func test_tenacidade_tem_teto() -> void:
	var target: Unit = _unit({Stat.Id.TENACITY: 5.0})
	var effect := CrowdControlEffect.new()
	effect.duration = 2.0
	effect.apply(AbilityCast.on_self(_unit()), target)
	assert_almost_eq(
		target.status.remaining(StatusSet.Kind.STUN), 0.4,
		"teto de 0.8 deixa 20% da duração"
	)

func test_resistencia_a_lentidao_corta_a_intensidade() -> void:
	var target: Unit = _unit({Stat.Id.MOVE_SPEED: 100.0, Stat.Id.SLOW_RESIST: 0.5})
	var effect := CrowdControlEffect.new()
	effect.control = CrowdControlEffect.Kind.SLOW
	effect.slow_amount = 0.4
	effect.duration = 3.0
	effect.apply(AbilityCast.on_self(_unit()), target)
	assert_almost_eq(
		target.stats.get_value(Stat.Id.MOVE_SPEED), 80.0,
		"40%% de lentidão com 50%% de resistência viram 20%%"
	)

func test_resistencia_total_anula_a_lentidao() -> void:
	var target: Unit = _unit({Stat.Id.MOVE_SPEED: 100.0, Stat.Id.SLOW_RESIST: 1.0})
	var effect := CrowdControlEffect.new()
	effect.control = CrowdControlEffect.Kind.SLOW
	effect.slow_amount = 0.6
	effect.apply(AbilityCast.on_self(_unit()), target)
	assert_eq(target.stats.modifier_count(), 0, "não deve nem criar o modificador")

func test_lentidao_nao_e_encurtada_por_tenacidade() -> void:
	var target: Unit = _unit({Stat.Id.MOVE_SPEED: 100.0, Stat.Id.TENACITY: 0.8})
	var effect := CrowdControlEffect.new()
	effect.control = CrowdControlEffect.Kind.SLOW
	effect.slow_amount = 0.5
	effect.duration = 4.0
	effect.apply(AbilityCast.on_self(_unit()), target)
	assert_almost_eq(target.stats.get_value(Stat.Id.MOVE_SPEED), 50.0)

# ---------------------------------------------------------------- estados novos

func test_cegueira_deixa_atacar_e_errar() -> void:
	var blind: Unit = _unit({Stat.Id.ATTACK_DAMAGE: 50.0})
	var victim: Unit = _unit({Stat.Id.MAX_HEALTH: 200.0}, 1)
	blind.status.apply(StatusSet.Kind.BLIND, 2.0)
	assert_true(blind.can_attack(), "cegar não desarma")
	var result: DamageResult = blind.basic_attack(victim)
	assert_true(result.missed)
	assert_almost_eq(victim.health.current, 200.0)

func test_encanto_tira_ataque_e_conjuracao() -> void:
	var charmed: Unit = _unit()
	charmed.status.apply(StatusSet.Kind.CHARM, 1.5)
	assert_false(charmed.can_attack())
	assert_false(charmed.can_cast())
	assert_true(charmed.can_move(), "encantado anda — só não escolhe para onde")
	assert_false(charmed.has_agency())

func test_provocacao_deixa_atacar_mas_nao_conjurar() -> void:
	var taunted: Unit = _unit()
	taunted.status.apply(StatusSet.Kind.TAUNT, 1.5)
	assert_true(taunted.can_attack(), "provocado ataca — é o que o torna perigoso")
	assert_false(taunted.can_cast())
	assert_false(taunted.has_agency())

func test_arremesso_trava_tudo() -> void:
	var airborne: Unit = _unit()
	airborne.status.apply(StatusSet.Kind.AIRBORNE, 1.0)
	assert_false(airborne.can_move())
	assert_false(airborne.can_attack())
	assert_false(airborne.can_cast())

func test_transformacao_deixa_andar() -> void:
	var frog: Unit = _unit()
	frog.status.apply(StatusSet.Kind.POLYMORPH, 2.0)
	assert_true(frog.can_move(), "transformado foge, e é essa a graça")
	assert_false(frog.can_attack())
	assert_false(frog.can_cast())
	assert_true(frog.has_agency(), "continua obedecendo a quem joga")

func test_agencia_intacta_sem_controle() -> void:
	assert_true(_unit().has_agency())

# ---------------------------------------------------------------- massa

func test_massa_resiste_a_empurrao() -> void:
	var caster: Unit = _unit()
	var heavy: Unit = _unit({Stat.Id.WEIGHT: 2.0}, 1)
	heavy.position = Vector3(1.0, 0.0, 0.0)
	var effect := DisplacementEffect.new()
	effect.mode = DisplacementEffect.Mode.AWAY_FROM_CASTER
	effect.distance = 6.0
	effect.ignores_root = true
	effect.apply(AbilityCast.on_self(caster), heavy)
	assert_almost_eq(heavy.pending_displacement.length(), 3.0)

func test_massa_nao_encurta_o_proprio_dash() -> void:
	var heavy: Unit = _unit({Stat.Id.WEIGHT: 4.0})
	var cast: AbilityCast = AbilityCast.toward(heavy, Vector3.FORWARD)
	var effect := DisplacementEffect.new()
	effect.recipient = AbilityEffect.Recipient.CASTER
	effect.mode = DisplacementEffect.Mode.ALONG_AIM
	effect.distance = 5.0
	effect.apply(cast, heavy)
	assert_almost_eq(heavy.pending_displacement.length(), 5.0)

func test_massa_padrao_nao_muda_nada() -> void:
	var caster: Unit = _unit()
	var target: Unit = _unit({}, 1)
	target.position = Vector3(0.0, 0.0, 2.0)
	var effect := DisplacementEffect.new()
	effect.mode = DisplacementEffect.Mode.AWAY_FROM_CASTER
	effect.distance = 4.0
	effect.apply(AbilityCast.on_self(caster), target)
	assert_almost_eq(target.pending_displacement.length(), 4.0)

# ---------------------------------------------------------------- catálogo

func test_todo_atributo_tem_nome() -> void:
	var missing: Array[String] = []
	for id: Stat.Id in Stat.all_ids():
		if not Stat.NAMES.has(id):
			missing.append(str(id))
	assert_eq(missing.size(), 0, "sem nome: %s" % ", ".join(missing))

func test_todo_nome_volta_pelo_from_name() -> void:
	for id: Stat.Id in Stat.all_ids():
		assert_eq(Stat.from_name(Stat.name_of(id)), id)

func test_nomes_sao_unicos() -> void:
	var seen: Dictionary = {}
	for id: Stat.Id in Stat.all_ids():
		var stat_name: StringName = Stat.name_of(id)
		assert_false(seen.has(stat_name), "nome repetido: %s" % stat_name)
		seen[stat_name] = true

func test_teto_de_recarga_sai_do_atributo() -> void:
	var ability := Ability.new()
	ability.cooldown = 10.0
	var greedy: Unit = _unit({
		Stat.Id.COOLDOWN_REDUCTION: 0.95,
		Stat.Id.COOLDOWN_REDUCTION_CAP: 0.5,
	})
	assert_almost_eq(ability.cooldown_for(greedy), 5.0, "o teto do próprio corta")

func test_teto_de_recarga_padrao_continua_noventa() -> void:
	var ability := Ability.new()
	ability.cooldown = 10.0
	var caster: Unit = _unit({Stat.Id.COOLDOWN_REDUCTION: 0.99})
	assert_almost_eq(ability.cooldown_for(caster), 1.0)
