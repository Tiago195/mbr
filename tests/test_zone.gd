extends TestCase

## Fase 5.3 — a zona que fecha.
##
## Toda a mecânica é lógica pura, então ela cabe inteira em teste. O que vai
## exigir olho humano depois é só o desenho do círculo na tela.

func _fase(raio: float, centro: Vector3, aviso: float, encolhe: float,
		dps: float = 10.0) -> Zone.Phase:
	return Zone.Phase.new(raio, centro, aviso, encolhe, dps)

## Duas fases: um círculo de raio 50 na origem que vira raio 10 em (20,0,0).
func _zona_simples() -> Zone:
	return Zone.new([
		_fase(50.0, Vector3.ZERO, 10.0, 5.0, 10.0),
		_fase(10.0, Vector3(20, 0, 0), 8.0, 4.0, 25.0),
	])

func _unidade(posicao: Vector3, armadura: float = 0.0) -> Unit:
	var stats := Stats.new()
	stats.set_bases({Stat.Id.MAX_HEALTH: 1000.0, Stat.Id.ARMOR: armadura})
	var unit := Unit.new(stats, 0)
	unit.position = posicao
	return unit

# ---------------------------------------------------------------- início

func test_comeca_no_circulo_da_primeira_fase() -> void:
	var zona := _zona_simples()
	assert_eq(zona.state, Zone.State.IDLE, "parada antes de começar")

	zona.start()
	assert_eq(zona.state, Zone.State.WARNING)
	assert_almost_eq(zona.radius, 50.0)
	assert_almost_eq(zona.center.length(), 0.0)

func test_zona_sem_fases_termina_na_hora() -> void:
	var zona := Zone.new([])
	var fins: Array[int] = []
	zona.finished.connect(func() -> void: fins.append(1))
	zona.start()
	assert_eq(zona.state, Zone.State.DONE)
	assert_eq(fins.size(), 1)

# ---------------------------------------------------------------- geometria

func test_dentro_e_fora_ignoram_altura() -> void:
	var zona := _zona_simples()
	zona.start()
	assert_true(zona.contains(Vector3(49, 0, 0)))
	assert_true(zona.contains(Vector3(49, 999, 0)), "altura não conta")
	assert_false(zona.contains(Vector3(51, 0, 0)))

func test_distancia_para_fora() -> void:
	var zona := _zona_simples()
	zona.start()
	assert_almost_eq(zona.distance_outside(Vector3(10, 0, 0)), 0.0, "dentro")
	assert_almost_eq(zona.distance_outside(Vector3(60, 0, 0)), 10.0)

# ---------------------------------------------------------------- fases

func test_durante_o_aviso_a_zona_nao_se_mexe() -> void:
	var zona := _zona_simples()
	zona.start()
	zona.advance_time(9.0)

	assert_eq(zona.state, Zone.State.WARNING)
	assert_almost_eq(zona.radius, 50.0, "ainda não encolheu")
	assert_almost_eq(zona.time_remaining(), 1.0)

func test_o_proximo_circulo_e_visivel_desde_o_aviso() -> void:
	# É o que dá ao jogador a decisão de rotacionar antes da hora.
	var zona := _zona_simples()
	zona.start()
	var proxima: Zone.Phase = zona.next_phase()
	assert_not_null(proxima)
	assert_almost_eq(proxima.radius, 10.0)
	assert_almost_eq(proxima.center.x, 20.0)

func test_encolhimento_interpola_raio_e_centro() -> void:
	var zona := _zona_simples()
	zona.start()
	zona.advance_time(10.0)
	assert_eq(zona.state, Zone.State.SHRINKING)

	# Metade dos 5s de encolhimento.
	zona.advance_time(2.5)
	assert_almost_eq(zona.radius, 30.0, "meio caminho entre 50 e 10")
	assert_almost_eq(zona.center.x, 10.0, "meio caminho entre 0 e 20")

func test_ao_chegar_assume_o_circulo_da_proxima_fase() -> void:
	var zona := _zona_simples()
	zona.start()
	zona.advance_time(10.0)
	zona.advance_time(5.0)

	assert_eq(zona.phase_index(), 1)
	assert_almost_eq(zona.radius, 10.0)
	assert_almost_eq(zona.center.x, 20.0)
	assert_eq(zona.state, Zone.State.DONE, "era a última fase")

func test_sobra_de_tempo_passa_para_o_estagio_seguinte() -> void:
	# Sem isso, um tick longo comeria tempo de jogo — e num servidor a 20 ticks
	# por segundo, sob carga, tick longo acontece.
	var zona := _zona_simples()
	zona.start()
	zona.advance_time(12.5)

	assert_eq(zona.state, Zone.State.SHRINKING)
	assert_almost_eq(zona.radius, 30.0, "os 2.5s de sobra já encolheram")

func test_tres_fases_avancam_em_ordem() -> void:
	var zona := Zone.new([
		_fase(100.0, Vector3.ZERO, 5.0, 5.0),
		_fase(50.0, Vector3(10, 0, 0), 5.0, 5.0),
		_fase(10.0, Vector3(20, 0, 0), 5.0, 5.0),
	])
	var iniciadas: Array[int] = []
	zona.phase_started.connect(func(i: int) -> void: iniciadas.append(i))

	zona.start()
	assert_eq(iniciadas, [0])

	zona.advance_time(10.0)
	assert_eq(zona.phase_index(), 1)
	assert_eq(iniciadas, [0, 1], "sinal de fase nova")

	zona.advance_time(10.0)
	assert_eq(zona.phase_index(), 2)
	assert_eq(zona.state, Zone.State.DONE)
	assert_almost_eq(zona.radius, 10.0)

func test_sinal_de_encolhimento_dispara_ao_sair_do_aviso() -> void:
	var zona := _zona_simples()
	var avisos: Array[int] = []
	zona.shrink_started.connect(func(i: int) -> void: avisos.append(i))

	zona.start()
	zona.advance_time(9.9)
	assert_eq(avisos.size(), 0, "ainda avisando")

	zona.advance_time(0.2)
	assert_eq(avisos, [0], "começou a fechar")

# ---------------------------------------------------------------- dano

func test_dano_atinge_so_quem_esta_fora() -> void:
	var zona := _zona_simples()
	zona.start()

	var dentro := _unidade(Vector3(10, 0, 0))
	var fora := _unidade(Vector3(80, 0, 0))
	var atingidos: int = zona.damage_outsiders([dentro, fora], 1.0)

	assert_eq(atingidos, 1)
	assert_almost_eq(dentro.health.current, 1000.0)
	assert_almost_eq(fora.health.current, 990.0, "10 de dano por segundo")

func test_dano_da_zona_ignora_armadura() -> void:
	# Senão o tanque poderia morar fora da zona.
	var zona := _zona_simples()
	zona.start()

	var frageis := _unidade(Vector3(80, 0, 0), 0.0)
	var couraçado := _unidade(Vector3(80, 0, 0), 500.0)
	zona.damage_outsiders([frageis, couraçado], 1.0)

	assert_almost_eq(frageis.health.current, 990.0)
	assert_almost_eq(couraçado.health.current, 990.0, "armadura não protege")

func test_dano_escala_com_o_tempo_decorrido() -> void:
	var zona := _zona_simples()
	zona.start()
	var fora := _unidade(Vector3(80, 0, 0))

	zona.damage_outsiders([fora], 0.5)
	assert_almost_eq(fora.health.current, 995.0, "meio segundo, metade do dano")

func test_fases_tardias_doem_mais() -> void:
	var zona := _zona_simples()
	zona.start()
	zona.advance_time(15.0)
	assert_eq(zona.phase_index(), 1)

	var fora := _unidade(Vector3(80, 0, 0))
	zona.damage_outsiders([fora], 1.0)
	assert_almost_eq(fora.health.current, 975.0, "25 por segundo na fase 2")

func test_morto_nao_leva_dano_de_zona() -> void:
	var zona := _zona_simples()
	zona.start()
	var morto := _unidade(Vector3(80, 0, 0))
	morto.receive_damage(null, 9999.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)

	var atingidos: int = zona.damage_outsiders([morto], 1.0)
	assert_eq(atingidos, 0)

func test_zona_parada_nao_causa_dano() -> void:
	var zona := _zona_simples()
	var fora := _unidade(Vector3(80, 0, 0))
	var atingidos: int = zona.damage_outsiders([fora], 1.0)

	assert_eq(atingidos, 0, "ainda não começou")
	assert_almost_eq(fora.health.current, 1000.0)

func test_zona_pode_matar() -> void:
	var zona := _zona_simples()
	zona.start()
	var fora := _unidade(Vector3(80, 0, 0))
	var mortes: Array[int] = []
	fora.health.died.connect(func() -> void: mortes.append(1))

	zona.damage_outsiders([fora], 100.0)

	assert_false(fora.is_alive())
	assert_eq(mortes.size(), 1)
