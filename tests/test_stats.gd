extends TestCase

## Fase 2.1 — atributos e modificadores.
##
## O teste que dá nome ao critério da fase é `test_equipar_e_desequipar_*`.

func _stats_com_ad(base: float = 50.0) -> Stats:
	var stats := Stats.new()
	stats.set_base(Stat.Id.ATTACK_DAMAGE, base)
	return stats

# ---------------------------------------------------------------- base

func test_atributo_sem_base_usa_o_padrao() -> void:
	var stats := Stats.new()
	assert_almost_eq(stats.get_value(Stat.Id.MAX_HEALTH), 100.0, "padrão de vida")
	assert_almost_eq(stats.get_value(Stat.Id.CRIT_DAMAGE), 1.75, "padrão de crítico")
	assert_almost_eq(stats.get_value(Stat.Id.ARMOR), 0.0, "sem padrão declarado = 0")

func test_set_bases_define_varios() -> void:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.ATTACK_DAMAGE: 60.0,
		Stat.Id.ARMOR: 30.0,
	})
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 60.0)
	assert_almost_eq(stats.get_value(Stat.Id.ARMOR), 30.0)

# ---------------------------------------------------------------- composição

func test_modificador_flat_soma() -> void:
	var stats := _stats_com_ad(50.0)
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 30.0, &"item:espada"
	))
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 80.0)

func test_modificador_percentual_multiplica() -> void:
	var stats := _stats_com_ad(50.0)
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.PERCENT, 0.15, &"buff:furia"
	))
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 57.5)

func test_flat_soma_antes_do_percentual() -> void:
	var stats := _stats_com_ad(50.0)
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 30.0, &"item:espada"
	))
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.PERCENT, 0.15, &"buff:furia"
	))
	# (50 + 30) * 1.15, e não 50 * 1.15 + 30
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 92.0)

func test_ordem_de_equipar_nao_muda_o_resultado() -> void:
	# Sem isto, a ordem de clique no inventário mudaria o dano do personagem.
	var flat := func() -> StatModifier: return StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 30.0, &"item:espada"
	)
	var pct := func() -> StatModifier: return StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.PERCENT, 0.15, &"buff:furia"
	)

	var a := _stats_com_ad(50.0)
	a.add_modifier(flat.call())
	a.add_modifier(pct.call())

	var b := _stats_com_ad(50.0)
	b.add_modifier(pct.call())
	b.add_modifier(flat.call())

	assert_almost_eq(
		a.get_value(Stat.Id.ATTACK_DAMAGE),
		b.get_value(Stat.Id.ATTACK_DAMAGE),
		"flat-depois-percentual vs percentual-depois-flat"
	)

# ------------------------------------------------- CRITÉRIO DA FASE 2.1

func test_equipar_e_desequipar_devolve_ao_estado_anterior() -> void:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.ATTACK_DAMAGE: 50.0,
		Stat.Id.ARMOR: 20.0,
		Stat.Id.MAX_HEALTH: 600.0,
	})

	var antes: Dictionary = {}
	for id: Stat.Id in Stat.NAMES:
		antes[id] = stats.get_value(id)

	# Um item que mexe em três atributos, com flat e percentual misturados.
	const ITEM: StringName = &"item:armadura_do_colosso"
	stats.add_modifier(StatModifier.new(Stat.Id.ARMOR, StatModifier.Kind.FLAT, 45.0, ITEM))
	stats.add_modifier(StatModifier.new(Stat.Id.MAX_HEALTH, StatModifier.Kind.FLAT, 300.0, ITEM))
	stats.add_modifier(StatModifier.new(Stat.Id.MAX_HEALTH, StatModifier.Kind.PERCENT, 0.10, ITEM))
	stats.add_modifier(StatModifier.new(Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.PERCENT, 0.05, ITEM))

	assert_almost_eq(stats.get_value(Stat.Id.ARMOR), 65.0, "equipado")
	assert_almost_eq(stats.get_value(Stat.Id.MAX_HEALTH), 990.0, "equipado")

	var removidos: int = stats.remove_source(ITEM)
	assert_eq(removidos, 4, "quantidade removida")

	for id: Stat.Id in Stat.NAMES:
		assert_almost_eq(
			stats.get_value(id), float(antes[id]), "atributo %s" % Stat.name_of(id)
		)
	assert_eq(stats.modifier_count(), 0, "nenhum modificador residual")

func test_desequipar_nao_afeta_outras_origens() -> void:
	var stats := _stats_com_ad(50.0)
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 30.0, &"item:espada"
	))
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 20.0, &"item:adaga"
	))

	stats.remove_source(&"item:espada")

	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 70.0, "sobrou a adaga")
	assert_true(stats.has_source(&"item:adaga"))
	assert_false(stats.has_source(&"item:espada"))

func test_dois_itens_com_o_mesmo_bonus_sao_distinguidos_pela_origem() -> void:
	# O caso que justifica rastrear origem: os valores são idênticos.
	var stats := _stats_com_ad(50.0)
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 30.0, &"item:espada_a"
	))
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 30.0, &"item:espada_b"
	))
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 110.0)

	stats.remove_source(&"item:espada_a")
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 80.0, "saiu exatamente uma")

# ---------------------------------------------------------------- stacking

func test_sem_stack_a_reaplicacao_substitui() -> void:
	var stats := _stats_com_ad(50.0)
	for i: int in 3:
		stats.add_modifier(StatModifier.new(
			Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 10.0, &"buff:golpe", 5.0
		))
	assert_eq(stats.modifier_count(), 1, "não acumulou")
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 60.0)

func test_sem_stack_a_reaplicacao_renova_a_duracao() -> void:
	var stats := _stats_com_ad(50.0)
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 10.0, &"buff:golpe", 5.0
	))
	stats.advance_time(4.0)
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 10.0, &"buff:golpe", 5.0
	))
	stats.advance_time(2.0)
	assert_almost_eq(
		stats.get_value(Stat.Id.ATTACK_DAMAGE), 60.0, "renovou em vez de expirar"
	)

func test_com_stack_acumula_ate_o_teto() -> void:
	var stats := _stats_com_ad(50.0)
	for i: int in 5:
		stats.add_modifier(StatModifier.new(
			Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 10.0, &"buff:frenesi",
			5.0, true, 3
		))
	assert_eq(stats.modifier_count(), 3, "parou no teto")
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 80.0)

func test_com_stack_sem_teto_acumula_sem_limite() -> void:
	var stats := _stats_com_ad(50.0)
	for i: int in 6:
		stats.add_modifier(StatModifier.new(
			Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 10.0, &"buff:sem_teto",
			5.0, true, 0
		))
	assert_eq(stats.modifier_count(), 6)
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 110.0)

# ---------------------------------------------------------------- duração

func test_temporario_expira_sozinho() -> void:
	var stats := _stats_com_ad(50.0)
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 30.0, &"buff:curto", 3.0
	))
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 80.0)

	var expirados: int = stats.advance_time(1.0)
	assert_eq(expirados, 0, "ainda vivo")
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 80.0)

	expirados = stats.advance_time(2.5)
	assert_eq(expirados, 1, "expirou")
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 50.0, "voltou ao base")

func test_permanente_nao_expira() -> void:
	var stats := _stats_com_ad(50.0)
	stats.add_modifier(StatModifier.new(
		Stat.Id.ATTACK_DAMAGE, StatModifier.Kind.FLAT, 30.0, &"item:espada"
	))
	stats.advance_time(3600.0)
	assert_almost_eq(stats.get_value(Stat.Id.ATTACK_DAMAGE), 80.0)

# ---------------------------------------------------------------- nomes

func test_nome_e_id_fazem_ida_e_volta() -> void:
	for id: Stat.Id in Stat.NAMES:
		assert_eq(Stat.from_name(Stat.name_of(id)), id, "ida e volta de %d" % id)

func test_nome_desconhecido_devolve_menos_um() -> void:
	assert_eq(Stat.from_name(&"atributo_que_nao_existe"), -1)
