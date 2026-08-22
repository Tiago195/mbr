extends TestCase

## Fase 5.4 — fluxo de partida.
##
## O critério da Fase 5 inteira é "8 pessoas entram, jogam até o fim, e alguém
## ganha". A parte de rede não existe ainda; a lógica de "alguém ganha" cabe
## aqui e é testável hoje.

func _unidade(vida: float = 100.0, posicao: Vector3 = Vector3.ZERO) -> Unit:
	var stats := Stats.new()
	stats.set_base(Stat.Id.MAX_HEALTH, vida)
	var unit := Unit.new(stats, 0)
	unit.position = posicao
	return unit

func _matar(unit: Unit) -> void:
	unit.receive_damage(null, 99999.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)

func _zona_rapida() -> Zone:
	return Zone.new([
		Zone.Phase.new(50.0, Vector3.ZERO, 1.0, 1.0, 20.0),
		Zone.Phase.new(5.0, Vector3.ZERO, 1.0, 1.0, 50.0),
	])

# ---------------------------------------------------------------- ciclo

func test_comeca_no_lobby() -> void:
	var partida := MatchState.new([_unidade(), _unidade()])
	assert_eq(partida.phase, MatchState.Phase.LOBBY)
	assert_eq(partida.alive_count(), 2)
	assert_false(partida.is_over())

func test_start_dispara_o_sinal_e_liga_a_zona() -> void:
	var zona := _zona_rapida()
	var partida := MatchState.new([_unidade(), _unidade()], zona)
	var inicios: Array[int] = []
	partida.started.connect(func() -> void: inicios.append(1))

	partida.start()

	assert_eq(partida.phase, MatchState.Phase.PLAYING)
	assert_eq(inicios.size(), 1)
	assert_eq(zona.state, Zone.State.WARNING, "a partida ligou a zona")

func test_zona_nao_anda_antes_da_partida_comecar() -> void:
	var zona := _zona_rapida()
	var partida := MatchState.new([_unidade(), _unidade()], zona)
	partida.advance_time(5.0)

	assert_eq(zona.state, Zone.State.IDLE)
	assert_almost_eq(partida.elapsed(), 0.0)

func test_tempo_so_corre_durante_a_partida() -> void:
	var partida := MatchState.new([_unidade(), _unidade()])
	partida.start()
	partida.advance_time(3.0)
	assert_almost_eq(partida.elapsed(), 3.0)

# ---------------------------------------------------------------- eliminação

func test_morte_tira_do_vivo_e_registra_colocacao() -> void:
	var a := _unidade()
	var b := _unidade()
	var c := _unidade()
	var partida := MatchState.new([a, b, c])
	partida.start()

	_matar(c)
	partida.advance_time(0.1)

	assert_eq(partida.alive_count(), 2)
	assert_eq(partida.placement_of(c), 3, "primeiro a morrer, pior colocação")
	assert_false(partida.is_over())

func test_sinal_de_eliminacao_carrega_a_colocacao() -> void:
	var a := _unidade()
	var b := _unidade()
	var partida := MatchState.new([a, b])
	var registro: Array = []
	partida.eliminated.connect(
		func(unit: Unit, pos: int) -> void: registro.append([unit, pos])
	)
	partida.start()

	_matar(b)
	partida.advance_time(0.1)

	assert_eq(registro.size(), 1)
	assert_eq(registro[0][1], 2)

func test_colocacoes_saem_da_pior_para_a_melhor() -> void:
	var unidades: Array[Unit] = []
	for _i: int in 4:
		unidades.append(_unidade())
	var partida := MatchState.new(unidades)
	partida.start()

	_matar(unidades[0])
	partida.advance_time(0.1)
	_matar(unidades[1])
	partida.advance_time(0.1)
	_matar(unidades[2])
	partida.advance_time(0.1)

	assert_eq(partida.placement_of(unidades[0]), 4)
	assert_eq(partida.placement_of(unidades[1]), 3)
	assert_eq(partida.placement_of(unidades[2]), 2)
	assert_eq(partida.placement_of(unidades[3]), 1, "o sobrevivente")

func test_mortes_no_mesmo_tick_empatam() -> void:
	# Não há como ordenar dentro de um tick, e inventar ordem seria pior.
	var a := _unidade()
	var b := _unidade()
	var c := _unidade()
	var partida := MatchState.new([a, b, c])
	partida.start()

	_matar(a)
	_matar(b)
	partida.advance_time(0.1)

	assert_eq(partida.placement_of(a), 3)
	assert_eq(partida.placement_of(b), 3, "mesma faixa")
	assert_eq(partida.placement_of(c), 1, "e c venceu")

# ---------------------------------------------------------------- vitória

func test_ultimo_vivo_vence() -> void:
	var a := _unidade()
	var b := _unidade()
	var partida := MatchState.new([a, b])
	var vencedores: Array = []
	partida.finished.connect(func(w: Unit) -> void: vencedores.append(w))
	partida.start()

	_matar(b)
	partida.advance_time(0.1)

	assert_true(partida.is_over())
	assert_eq(partida.winner, a)
	assert_eq(partida.placement_of(a), 1)
	assert_eq(vencedores.size(), 1)

func test_partida_encerrada_para_de_avancar() -> void:
	var a := _unidade()
	var b := _unidade()
	var zona := _zona_rapida()
	var partida := MatchState.new([a, b], zona)
	partida.start()
	_matar(b)
	partida.advance_time(0.1)

	var tempo_no_fim: float = partida.elapsed()
	partida.advance_time(10.0)
	assert_almost_eq(partida.elapsed(), tempo_no_fim, "relógio parou")

func test_partida_de_um_jogador_ja_nasce_decidida() -> void:
	var a := _unidade()
	var partida := MatchState.new([a])
	partida.start()
	assert_true(partida.is_over())
	assert_eq(partida.winner, a)

# ---------------------------------------------------------------- zona

func test_zona_mata_e_a_partida_contabiliza_no_mesmo_tick() -> void:
	# A ordem importa: a zona machuca ANTES da checagem de fim. Se fosse
	# depois, a morte por zona só contaria um tick adiante.
	var dentro := _unidade(100.0, Vector3.ZERO)
	var fora := _unidade(100.0, Vector3(500, 0, 0))
	var zona := _zona_rapida()
	var partida := MatchState.new([dentro, fora], zona)
	partida.start()

	# 20 de dano por segundo, 100 de vida: 5 segundos matam.
	partida.advance_time(6.0)

	assert_false(fora.is_alive(), "a zona matou")
	assert_true(partida.is_over())
	assert_eq(partida.winner, dentro)
	assert_eq(partida.placement_of(fora), 2)

func test_quem_fica_dentro_nao_toma_dano_de_zona() -> void:
	var a := _unidade(100.0, Vector3.ZERO)
	var b := _unidade(100.0, Vector3(1, 0, 0))
	var partida := MatchState.new([a, b], _zona_rapida())
	partida.start()
	partida.advance_time(1.5)

	assert_almost_eq(a.health.current, 100.0)
	assert_almost_eq(b.health.current, 100.0)
	assert_false(partida.is_over())

func test_a_zona_avanca_de_fase_durante_a_partida() -> void:
	var zona := _zona_rapida()
	var partida := MatchState.new([_unidade(), _unidade()], zona)
	partida.start()
	assert_almost_eq(zona.radius, 50.0)

	partida.advance_time(2.5)
	assert_eq(zona.phase_index(), 1, "avançou")
	assert_almost_eq(zona.radius, 5.0)

func test_partida_sem_zona_funciona() -> void:
	# Treino e teste de combate não precisam de zona.
	var a := _unidade()
	var b := _unidade()
	var partida := MatchState.new([a, b])
	partida.start()
	partida.advance_time(100.0)

	assert_false(partida.is_over(), "ninguém morre sem zona nem combate")
	assert_almost_eq(a.health.current, 100.0)
