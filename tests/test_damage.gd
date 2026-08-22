extends TestCase

## Fase 2.2 — cálculo de dano.
##
## Cobre os casos de borda que `03-sistemas-de-jogo.md` lista: armadura zero,
## armadura alta, crítico, escudo parcial, dano verdadeiro, roubo de vida e
## morte exata. Mais penetração e defesa negativa, que a fórmula prevê.

func _atacante(bases: Dictionary = {}) -> Stats:
	var stats := Stats.new()
	stats.set_base(Stat.Id.CRIT_CHANCE, 0.0)
	stats.set_bases(bases)
	return stats

func _alvo(bases: Dictionary = {}) -> Stats:
	var stats := Stats.new()
	stats.set_bases(bases)
	return stats

# ---------------------------------------------------------------- defesa

func test_armadura_zero_passa_o_dano_inteiro() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo({Stat.Id.ARMOR: 0.0}),
		1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_almost_eq(r.final_damage, 100.0)

func test_cem_de_armadura_corta_metade() -> void:
	# 100 / (100 + 100) = 0.5
	var r := Damage.resolve(
		_atacante(), _alvo({Stat.Id.ARMOR: 100.0}),
		1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_almost_eq(r.final_damage, 50.0)

func test_armadura_alta_tem_retorno_decrescente_mas_nunca_imuniza() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo({Stat.Id.ARMOR: 900.0}),
		1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_almost_eq(r.final_damage, 10.0, "100/(100+900)")
	assert_true(r.final_damage > 0.0, "nunca chega a zero")

func test_armadura_negativa_amplifica_com_retorno_decrescente() -> void:
	# 2 - 100/(100+50) = 1.3333...
	var r := Damage.resolve(
		_atacante(), _alvo({Stat.Id.ARMOR: -50.0}),
		1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_almost_eq(r.final_damage, 133.333333, "", 0.001)

func test_resistencia_magica_atua_no_dano_magico() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo({Stat.Id.MAGIC_RESIST: 100.0, Stat.Id.ARMOR: 900.0}),
		1000.0, 0.0, 100.0, Damage.Type.MAGIC, Damage.Source.ABILITY
	)
	assert_almost_eq(r.final_damage, 50.0, "usou MR, ignorou armadura")

func test_dano_verdadeiro_ignora_as_duas_defesas() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo({Stat.Id.ARMOR: 500.0, Stat.Id.MAGIC_RESIST: 500.0}),
		1000.0, 0.0, 100.0, Damage.Type.TRUE
	)
	assert_almost_eq(r.final_damage, 100.0)

# ---------------------------------------------------------------- penetração

func test_penetracao_percentual_antes_da_flat() -> void:
	# 100 de armadura, 30% de pen, 10 de pen flat -> 100*0.7 - 10 = 60
	# 100 / (100 + 60) = 0.625
	var atacante := _atacante({
		Stat.Id.ARMOR_PEN_PERCENT: 0.30,
		Stat.Id.ARMOR_PEN_FLAT: 10.0,
	})
	var r := Damage.resolve(
		atacante, _alvo({Stat.Id.ARMOR: 100.0}),
		1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_almost_eq(r.final_damage, 62.5)

func test_penetracao_nao_torna_defesa_negativa() -> void:
	var atacante := _atacante({Stat.Id.ARMOR_PEN_FLAT: 500.0})
	var r := Damage.resolve(
		atacante, _alvo({Stat.Id.ARMOR: 20.0}),
		1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_almost_eq(r.final_damage, 100.0, "zera a defesa, não a inverte")

# ---------------------------------------------------------------- crítico

func test_critico_multiplica_pelo_crit_damage() -> void:
	var atacante := _atacante({
		Stat.Id.CRIT_CHANCE: 1.0,
		Stat.Id.CRIT_DAMAGE: 2.0,
	})
	var r := Damage.resolve(
		atacante, _alvo(), 1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_true(r.was_critical, "sorteou crítico")
	assert_almost_eq(r.final_damage, 200.0)

func test_sem_chance_nao_critita() -> void:
	var r := Damage.resolve(
		_atacante({Stat.Id.CRIT_CHANCE: 0.0}), _alvo(),
		1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_false(r.was_critical)
	assert_almost_eq(r.final_damage, 100.0)

func test_habilidade_nao_critita_mesmo_com_cem_por_cento() -> void:
	# Convenção fixada na decisão 8: crítico é coisa de ataque básico.
	var atacante := _atacante({
		Stat.Id.CRIT_CHANCE: 1.0,
		Stat.Id.CRIT_DAMAGE: 2.0,
	})
	var r := Damage.resolve(
		atacante, _alvo(), 1000.0, 0.0, 100.0,
		Damage.Type.MAGIC, Damage.Source.ABILITY
	)
	assert_false(r.was_critical)
	assert_almost_eq(r.final_damage, 100.0)

func test_critico_aplica_antes_da_armadura() -> void:
	# 100 * 2 = 200, depois * 0.5 = 100. Se a ordem invertesse daria o mesmo
	# aqui, mas não com penetração no meio — o teste trava a ordem.
	var atacante := _atacante({
		Stat.Id.CRIT_CHANCE: 1.0,
		Stat.Id.CRIT_DAMAGE: 2.0,
	})
	var r := Damage.resolve(
		atacante, _alvo({Stat.Id.ARMOR: 100.0}),
		1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_almost_eq(r.final_damage, 100.0)

# ---------------------------------------------------------------- escudo

func test_escudo_parcial_absorve_e_o_resto_vai_na_vida() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo(), 500.0, 30.0, 100.0, Damage.Type.TRUE
	)
	assert_almost_eq(r.absorbed_by_shield, 30.0)
	assert_almost_eq(r.shield_after, 0.0)
	assert_almost_eq(r.damage_to_health, 70.0)
	assert_almost_eq(r.health_after, 430.0)
	assert_false(r.killed)

func test_escudo_maior_que_o_dano_protege_a_vida_inteira() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo(), 500.0, 250.0, 100.0, Damage.Type.TRUE
	)
	assert_almost_eq(r.absorbed_by_shield, 100.0)
	assert_almost_eq(r.shield_after, 150.0)
	assert_almost_eq(r.damage_to_health, 0.0)
	assert_almost_eq(r.health_after, 500.0)

# ---------------------------------------------------------------- roubo de vida

func test_roubo_de_vida_incide_sobre_o_dano_final_nao_sobre_o_bruto() -> void:
	# 100 bruto, armadura 100 -> 50 final. 20% de lifesteal -> 10, não 20.
	var atacante := _atacante({Stat.Id.LIFESTEAL: 0.20})
	var r := Damage.resolve(
		atacante, _alvo({Stat.Id.ARMOR: 100.0}),
		1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_almost_eq(r.lifesteal_healed, 10.0)

func test_spell_vamp_vale_para_habilidade_e_lifesteal_nao() -> void:
	var atacante := _atacante({
		Stat.Id.LIFESTEAL: 0.50,
		Stat.Id.SPELL_VAMP: 0.10,
	})
	var r := Damage.resolve(
		atacante, _alvo(), 1000.0, 0.0, 100.0,
		Damage.Type.MAGIC, Damage.Source.ABILITY
	)
	assert_almost_eq(r.lifesteal_healed, 10.0, "usou spell_vamp, não lifesteal")

func test_bater_em_escudo_ainda_cura() -> void:
	var atacante := _atacante({Stat.Id.LIFESTEAL: 0.20})
	var r := Damage.resolve(
		atacante, _alvo(), 500.0, 1000.0, 100.0, Damage.Type.TRUE
	)
	assert_almost_eq(r.damage_to_health, 0.0, "o escudo comeu tudo")
	assert_almost_eq(r.lifesteal_healed, 20.0, "mas o roubo de vida vale")

func test_dano_de_ambiente_nao_cura_ninguem() -> void:
	var r := Damage.resolve(
		null, _alvo(), 500.0, 0.0, 100.0,
		Damage.Type.TRUE, Damage.Source.ENVIRONMENT
	)
	assert_almost_eq(r.lifesteal_healed, 0.0)
	assert_almost_eq(r.damage_to_health, 100.0)

func test_atacante_nulo_nao_quebra() -> void:
	# Dano de zona não tem dono.
	var r := Damage.resolve(
		null, _alvo({Stat.Id.ARMOR: 100.0}), 500.0, 0.0, 100.0,
		Damage.Type.PHYSICAL, Damage.Source.ENVIRONMENT
	)
	assert_almost_eq(r.final_damage, 50.0, "armadura do alvo ainda conta")
	assert_false(r.was_critical)

# ---------------------------------------------------------------- morte

func test_morte_exata_conta_como_morte() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo(), 50.0, 0.0, 50.0, Damage.Type.TRUE
	)
	assert_almost_eq(r.health_after, 0.0)
	assert_true(r.killed, "vida exatamente zero é morte")

func test_um_ponto_a_menos_nao_mata() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo(), 50.0, 0.0, 49.0, Damage.Type.TRUE
	)
	assert_almost_eq(r.health_after, 1.0)
	assert_false(r.killed)

func test_excesso_de_dano_deixa_vida_negativa_sem_travar() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo(), 50.0, 0.0, 500.0, Damage.Type.TRUE
	)
	assert_almost_eq(r.health_after, -450.0, "quem clampa é a Fase 2.3")
	assert_true(r.killed)

# ---------------------------------------------------------------- degenerados

func test_dano_zero_nao_faz_nada() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo(), 500.0, 100.0, 0.0, Damage.Type.PHYSICAL
	)
	assert_almost_eq(r.final_damage, 0.0)
	assert_almost_eq(r.health_after, 500.0)
	assert_almost_eq(r.shield_after, 100.0)
	assert_false(r.killed)

func test_dano_negativo_nao_vira_cura() -> void:
	var r := Damage.resolve(
		_atacante(), _alvo(), 500.0, 0.0, -100.0, Damage.Type.TRUE
	)
	assert_almost_eq(r.health_after, 500.0, "cura é efeito HEAL, não dano negativo")

func test_a_resolucao_nao_altera_os_stats_recebidos() -> void:
	# Função pura: chamar duas vezes com a mesma entrada dá a mesma saída.
	var atacante := _atacante({Stat.Id.LIFESTEAL: 0.20})
	var alvo := _alvo({Stat.Id.ARMOR: 100.0})

	var primeira := Damage.resolve(
		atacante, alvo, 1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	var segunda := Damage.resolve(
		atacante, alvo, 1000.0, 0.0, 100.0, Damage.Type.PHYSICAL
	)
	assert_almost_eq(segunda.final_damage, primeira.final_damage)
	assert_almost_eq(alvo.get_value(Stat.Id.ARMOR), 100.0, "alvo intacto")
	assert_eq(atacante.modifier_count(), 0, "atacante intacto")
