extends TestCase

## Fase 2.3 — vida, escudo e morte.
##
## A integração com o personagem exige olho humano, mas a máquina de estado da
## vida é lógica pura e cabe aqui.

func _health(max_health: float = 100.0, armor: float = 0.0) -> Health:
	var stats := Stats.new()
	stats.set_bases({Stat.Id.MAX_HEALTH: max_health, Stat.Id.ARMOR: armor})
	return Health.new(stats)

func _hit(health: Health, amount: float) -> DamageResult:
	var result := Damage.resolve(
		null, Stats.new(), health.current, health.shield,
		amount, Damage.Type.TRUE, Damage.Source.ENVIRONMENT
	)
	health.apply(result)
	return result

func test_nasce_com_a_vida_cheia() -> void:
	var health := _health(750.0)
	assert_almost_eq(health.current, 750.0)
	assert_almost_eq(health.fraction(), 1.0)
	assert_true(health.is_alive())

func test_dano_reduz_a_vida() -> void:
	var health := _health(100.0)
	_hit(health, 30.0)
	assert_almost_eq(health.current, 70.0)
	assert_almost_eq(health.fraction(), 0.7)
	assert_true(health.is_alive())

func test_vida_nunca_fica_negativa() -> void:
	# `Damage` devolve vida negativa de propósito; o clamp mora aqui.
	var health := _health(100.0)
	var result := _hit(health, 500.0)
	assert_almost_eq(result.health_after, -400.0, "o cálculo mantém o sobrekill")
	assert_almost_eq(health.current, 0.0, "o estado clampa")
	assert_false(health.is_alive())

func test_sinal_de_morte_dispara_uma_vez_so() -> void:
	var health := _health(100.0)
	var mortes: Array[int] = []
	health.died.connect(func() -> void: mortes.append(1))

	_hit(health, 100.0)
	assert_eq(mortes.size(), 1, "morreu")

	_hit(health, 50.0)
	assert_eq(mortes.size(), 1, "bater em cadáver não mata de novo")

func test_sinal_de_mudanca_carrega_os_valores() -> void:
	var health := _health(200.0)
	var recebido: Array[float] = []
	# `recebido.append(...)` e não `recebido = [...]`: a lambda captura a
	# variável por valor, então reatribuir dentro dela não sai para fora.
	# Mutar o array funciona porque a referência é a mesma.
	health.changed.connect(
		func(current: float, maximum: float) -> void:
			recebido.append(current)
			recebido.append(maximum)
	)
	_hit(health, 50.0)
	assert_eq(recebido.size(), 2, "o sinal chegou")
	assert_almost_eq(recebido[0], 150.0)
	assert_almost_eq(recebido[1], 200.0)

func test_escudo_absorve_antes_da_vida() -> void:
	var health := _health(100.0)
	health.add_shield(40.0)
	_hit(health, 30.0)
	assert_almost_eq(health.shield, 10.0)
	assert_almost_eq(health.current, 100.0, "vida intacta")

func test_cura_nao_passa_do_maximo() -> void:
	var health := _health(100.0)
	_hit(health, 30.0)
	var curado: float = health.heal(100.0)
	assert_almost_eq(curado, 30.0, "curou só o que faltava")
	assert_almost_eq(health.current, 100.0)

func test_cura_em_morto_nao_ressuscita() -> void:
	var health := _health(100.0)
	_hit(health, 200.0)
	var curado: float = health.heal(50.0)
	assert_almost_eq(curado, 0.0)
	assert_false(health.is_alive(), "ressurreição é efeito próprio, não cura")

func test_reset_devolve_ao_estado_inicial() -> void:
	var health := _health(300.0)
	health.add_shield(50.0)
	_hit(health, 400.0)
	assert_false(health.is_alive())

	health.reset()
	assert_true(health.is_alive())
	assert_almost_eq(health.current, 300.0)
	assert_almost_eq(health.shield, 0.0, "escudo não sobrevive ao renascimento")

func test_maximo_acompanha_modificador_de_atributo() -> void:
	var stats := Stats.new()
	stats.set_base(Stat.Id.MAX_HEALTH, 100.0)
	var health := Health.new(stats)

	stats.add_modifier(StatModifier.new(
		Stat.Id.MAX_HEALTH, StatModifier.Kind.FLAT, 100.0, &"item:vitalidade"
	))
	assert_almost_eq(health.maximum(), 200.0, "equipar item aumenta o teto")
	assert_almost_eq(health.fraction(), 0.5, "a vida atual não sobe junto")

	stats.remove_source(&"item:vitalidade")
	assert_almost_eq(health.maximum(), 100.0)
	assert_almost_eq(health.fraction(), 1.0)
