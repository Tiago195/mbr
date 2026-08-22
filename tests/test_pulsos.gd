extends TestCase

## Habilidade de vários golpes — a mudança estrutural que a tradução do
## original exigiu.
##
## Uma `Skill` de lá referencia até 12 `Impact`, cada um com `StartTime`,
## `StartPosition`, raio e alvos próprios — e cada impacto ainda pode encadear
## outro. Antes disso, `Ability` tinha uma forma só, e traduzir obrigaria a
## descartar impactos ou fundi-los — e fundir está errado, porque o segundo
## golpe sai depois, noutro lugar, e só pega quem ficou.

func _unit(position: Vector3 = Vector3.ZERO, team: int = 0) -> Unit:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.MAX_HEALTH: 1000.0,
		Stat.Id.ABILITY_POWER: 100.0,
	})
	var unit := Unit.new(stats, team)
	unit.position = position
	return unit

func _dano(valor: float) -> DamageEffect:
	var effect := DamageEffect.new()
	effect.base_damage = valor
	effect.damage_type = Damage.Type.TRUE
	return effect

func _pulso(form: AbilityPulse.Form, dano: float) -> AbilityPulse:
	var pulse := AbilityPulse.new()
	pulse.form = form
	pulse.effects = [_dano(dano)]
	return pulse

# ---------------------------------------------------------------- vários golpes

func test_dois_pulsos_imediatos_saem_juntos() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(2, 0, 0), 1)

	var ability := Ability.new()
	ability.id = &"duplo"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	var a: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 30.0)
	a.radius = 3.0
	var b: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 20.0)
	b.radius = 3.0
	ability.pulses = [a, b]

	var book := AbilityBook.new()
	var result: CastResult = AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [alvo]
	)
	assert_true(result.succeeded())
	assert_almost_eq(alvo.health.current, 950.0, "os dois golpes bateram")
	assert_eq(result.targets.size(), 1, "o mesmo alvo não conta duas vezes")

func test_pulso_atrasado_espera_o_tempo() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(2, 0, 0), 1)

	var ability := Ability.new()
	ability.id = &"atrasado"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	var agora: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 30.0)
	agora.radius = 3.0
	var depois: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 50.0)
	depois.radius = 3.0
	depois.delay = 0.5
	ability.pulses = [agora, depois]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [alvo]
	)
	assert_almost_eq(alvo.health.current, 970.0, "só o primeiro saiu")
	assert_true(book.has_scheduled())

	book.advance_time(0.3, caster)
	AbilityEngine.resolve_scheduled(book, [alvo])
	assert_almost_eq(alvo.health.current, 970.0, "ainda não venceu")

	book.advance_time(0.3, caster)
	var late: Array[CastResult] = AbilityEngine.resolve_scheduled(book, [alvo])
	assert_eq(late.size(), 1)
	assert_almost_eq(alvo.health.current, 920.0, "o segundo golpe saiu")
	assert_false(book.has_scheduled())

func test_pulso_atrasado_so_pega_quem_ficou() -> void:
	var caster: Unit = _unit()
	var fugiu: Unit = _unit(Vector3(2, 0, 0), 1)
	var ficou: Unit = _unit(Vector3(2, 0, 1), 1)

	var ability := Ability.new()
	ability.id = &"bomba"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	var explosao: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 100.0)
	explosao.radius = 3.0
	explosao.delay = 1.0
	ability.pulses = [explosao]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [fugiu, ficou]
	)
	fugiu.position = Vector3(30, 0, 0)

	book.advance_time(1.0, caster)
	AbilityEngine.resolve_scheduled(book, [fugiu, ficou])
	assert_almost_eq(fugiu.health.current, 1000.0, "quem saiu do círculo escapou")
	assert_almost_eq(ficou.health.current, 900.0)

func test_ancora_congela_no_ponto_mirado() -> void:
	# A área fica onde caiu. Recalcular a âncora depois faria a explosão
	# perseguir o alvo, e área no chão não persegue ninguém.
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(5, 0, 0), 1)

	var ability := Ability.new()
	ability.id = &"marcado"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 20.0
	var tardio: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 100.0)
	tardio.radius = 2.0
	tardio.delay = 0.5
	ability.pulses = [tardio]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(5, 0, 0)), [alvo]
	)
	caster.position = Vector3(50, 0, 50)
	book.advance_time(0.5, caster)
	AbilityEngine.resolve_scheduled(book, [alvo])
	assert_almost_eq(alvo.health.current, 900.0, "a área ficou onde caiu")

func test_ancora_no_conjurador_acompanha_a_conjuracao() -> void:
	var caster: Unit = _unit(Vector3(10, 0, 0))
	var perto: Unit = _unit(Vector3(11, 0, 0), 1)
	var longe: Unit = _unit(Vector3(1, 0, 0), 1)

	var ability := Ability.new()
	ability.id = &"nova"
	ability.aim = Ability.Aim.SELF
	ability.cast_range = 0.0
	var nova: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 40.0)
	nova.radius = 3.0
	nova.origin = AbilityPulse.Origin.CASTER
	ability.pulses = [nova]

	var book := AbilityBook.new()
	AbilityEngine.cast(book, ability, AbilityCast.on_self(caster), [perto, longe])
	assert_almost_eq(perto.health.current, 960.0)
	assert_almost_eq(longe.health.current, 1000.0)

func test_pulso_encadeado_usa_a_ancora_anterior() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(6, 0, 0), 1)

	var ability := Ability.new()
	ability.id = &"encadeado"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 20.0
	# O primeiro se ancora no ponto mirado; o segundo herda a mesma âncora,
	# mesmo com o conjurador longe.
	var primeiro: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 10.0)
	primeiro.radius = 2.0
	primeiro.origin = AbilityPulse.Origin.AIM_POINT
	var segundo: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 20.0)
	segundo.radius = 2.0
	segundo.origin = AbilityPulse.Origin.PREVIOUS
	ability.pulses = [primeiro, segundo]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(6, 0, 0)), [alvo]
	)
	assert_almost_eq(alvo.health.current, 970.0, "os dois pegaram no mesmo lugar")

# ---------------------------------------------------------------- repetição

func test_area_que_dura_bate_varias_vezes() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(2, 0, 0), 1)

	var ability := Ability.new()
	ability.id = &"chamas"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	var chamas: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 10.0)
	chamas.radius = 3.0
	chamas.duration = 2.0
	chamas.loop_interval = 1.0
	ability.pulses = [chamas]
	assert_eq(chamas.repeat_count(), 3, "instante 0, 1s e 2s")

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [alvo]
	)
	assert_almost_eq(alvo.health.current, 990.0, "o primeiro tique é imediato")

	for i: int in range(4):
		book.advance_time(1.0, caster)
		AbilityEngine.resolve_scheduled(book, [alvo])
	assert_almost_eq(alvo.health.current, 970.0, "três tiques no total")
	assert_false(book.has_scheduled())

func test_golpe_unico_nao_marca_nada() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(2, 0, 0), 1)
	var ability := Ability.new()
	ability.id = &"simples"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 3.0
	pulse.effects = [_dano(50.0)]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [alvo]
	)
	assert_false(book.has_scheduled())
	assert_eq(AbilityEngine.resolve_scheduled(book, [alvo]).size(), 0)

func test_interromper_nao_cancela_o_que_ja_saiu() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(2, 0, 0), 1)
	var ability := Ability.new()
	ability.id = &"bomba"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	var explosao: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 100.0)
	explosao.radius = 3.0
	explosao.delay = 1.0
	ability.pulses = [explosao]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [alvo]
	)
	book.interrupt()
	book.advance_time(1.0, caster)
	AbilityEngine.resolve_scheduled(book, [alvo])
	assert_almost_eq(alvo.health.current, 900.0, "a bomba já estava no ar")

func test_morrer_limpa_os_pulsos_marcados() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(2, 0, 0), 1)
	var ability := Ability.new()
	ability.id = &"bomba"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	var explosao: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 100.0)
	explosao.radius = 3.0
	explosao.delay = 1.0
	ability.pulses = [explosao]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [alvo]
	)
	assert_eq(book.clear_scheduled(), 1)
	book.advance_time(1.0, caster)
	AbilityEngine.resolve_scheduled(book, [alvo])
	assert_almost_eq(alvo.health.current, 1000.0)

# ---------------------------------------------------------------- leque

func test_leque_pega_quem_esta_de_lado() -> void:
	# Três flechas a 60 graus de abertura: -30, 0 e +30. Quem está a 30 graus
	# é pego pela flecha da ponta, e sem leque escaparia.
	var caster: Unit = _unit()
	var reto: Unit = _unit(Vector3(0, 0, -5), 1)
	# 30 graus a partir de -Z, num raio de 5: (-2.5, 0, -4.33)
	var de_lado: Unit = _unit(Vector3(-2.5, 0, -4.33), 1)

	var ability := Ability.new()
	ability.id = &"leque"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var flechas: AbilityPulse = _pulso(AbilityPulse.Form.LINE, 40.0)
	flechas.origin = AbilityPulse.Origin.CASTER
	flechas.length = 8.0
	flechas.width = 1.0
	flechas.spread_count = 3
	flechas.spread_angle = 60.0
	ability.pulses = [flechas]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)),
		[reto, de_lado]
	)
	assert_almost_eq(reto.health.current, 960.0, "a flecha do meio")
	assert_almost_eq(de_lado.health.current, 960.0, "a flecha da ponta")

func test_sem_leque_a_flecha_de_lado_erra() -> void:
	var caster: Unit = _unit()
	var de_lado: Unit = _unit(Vector3(-2.5, 0, -4.33), 1)
	var ability := Ability.new()
	ability.id = &"unica"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var flecha: AbilityPulse = _pulso(AbilityPulse.Form.LINE, 40.0)
	flecha.origin = AbilityPulse.Origin.CASTER
	flecha.length = 8.0
	flecha.width = 1.0
	ability.pulses = [flecha]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)), [de_lado]
	)
	assert_almost_eq(de_lado.health.current, 1000.0)

func test_leque_nao_soma_dano_em_quem_esta_no_meio() -> void:
	# Três flechas, um alvo no eixo. Ele é pego por uma e leva UM dano —
	# acertar em mais de uma direção não multiplica.
	var caster: Unit = _unit()
	var reto: Unit = _unit(Vector3(0, 0, -3), 1)
	var ability := Ability.new()
	ability.id = &"leque"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var flechas: AbilityPulse = _pulso(AbilityPulse.Form.LINE, 40.0)
	flechas.origin = AbilityPulse.Origin.CASTER
	flechas.length = 8.0
	flechas.width = 4.0
	flechas.spread_count = 3
	flechas.spread_angle = 20.0
	ability.pulses = [flechas]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)), [reto]
	)
	assert_almost_eq(reto.health.current, 960.0, "um dano, não três")

func test_cone_respeita_o_proprio_alcance() -> void:
	# A propriedade que o bug do cone violava: `length` É o alcance, e quem
	# está além dele não é atingido, por mais alinhado que esteja.
	#
	# Não havia teste disso — o único teste de cone usava alcance 6 com alvos a
	# 4m, e uma mutação que ignorasse `length` passava despercebida.
	var caster: Unit = _unit()
	var dentro: Unit = _unit(Vector3(0, 0, -3), 1)
	var fora: Unit = _unit(Vector3(0, 0, -9), 1)

	var ability := Ability.new()
	ability.id = &"cone"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var cone: AbilityPulse = _pulso(AbilityPulse.Form.CONE, 40.0)
	cone.origin = AbilityPulse.Origin.CASTER
	cone.length = 5.0
	cone.cone_angle = 90.0
	ability.pulses = [cone]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)),
		[dentro, fora]
	)
	assert_almost_eq(dentro.health.current, 960.0, "3m num cone de 5m")
	assert_almost_eq(fora.health.current, 1000.0, "9m num cone de 5m — fora")

func test_cone_estreito_ignora_quem_esta_de_lado() -> void:
	var caster: Unit = _unit()
	var na_frente: Unit = _unit(Vector3(0, 0, -3), 1)
	var de_lado: Unit = _unit(Vector3(3, 0, 0), 1)
	var ability := Ability.new()
	ability.id = &"cone"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var cone: AbilityPulse = _pulso(AbilityPulse.Form.CONE, 40.0)
	cone.origin = AbilityPulse.Origin.CASTER
	cone.length = 5.0
	cone.cone_angle = 40.0
	ability.pulses = [cone]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)),
		[na_frente, de_lado]
	)
	assert_almost_eq(na_frente.health.current, 960.0)
	assert_almost_eq(de_lado.health.current, 1000.0, "90 graus fora de um cone de 40")

func test_desvio_de_direcao_gira_o_pulso() -> void:
	# É o `Angle` do impacto: o leque da Violet é feito assim, com três pulsos
	# a -18, 0 e +18 graus, e não com uma forma que abre em três.
	var caster: Unit = _unit()
	# 40 graus à direita de -Z, a 5m: (3.21, 0, -3.83)
	var na_diagonal: Unit = _unit(Vector3(3.21, 0, -3.83), 1)

	var ability := Ability.new()
	ability.id = &"angulado"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var pulse: AbilityPulse = _pulso(AbilityPulse.Form.LINE, 40.0)
	pulse.origin = AbilityPulse.Origin.CASTER
	pulse.length = 8.0
	pulse.width = 1.0
	pulse.direction_offset = 40.0
	ability.pulses = [pulse]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)), [na_diagonal]
	)
	assert_almost_eq(na_diagonal.health.current, 960.0, "o pulso girou 40 graus")

func test_sem_desvio_a_diagonal_escapa() -> void:
	var caster: Unit = _unit()
	var na_diagonal: Unit = _unit(Vector3(3.21, 0, -3.83), 1)
	var ability := Ability.new()
	ability.id = &"reto"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var pulse: AbilityPulse = _pulso(AbilityPulse.Form.LINE, 40.0)
	pulse.origin = AbilityPulse.Origin.CASTER
	pulse.length = 8.0
	pulse.width = 1.0
	ability.pulses = [pulse]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)), [na_diagonal]
	)
	assert_almost_eq(na_diagonal.health.current, 1000.0)

func test_direcoes_do_leque_sao_simetricas() -> void:
	var pulse := AbilityPulse.new()
	pulse.spread_count = 3
	pulse.spread_angle = 60.0
	var direcoes: Array[Vector3] = pulse.spread_directions(Vector3.FORWARD)
	assert_eq(direcoes.size(), 3)
	assert_almost_eq(
		rad_to_deg(direcoes[0].angle_to(Vector3.FORWARD)), 30.0, "", 0.01
	)
	assert_almost_eq(
		rad_to_deg(direcoes[1].angle_to(Vector3.FORWARD)), 0.0, "", 0.01
	)
	assert_almost_eq(
		rad_to_deg(direcoes[2].angle_to(Vector3.FORWARD)), 30.0, "", 0.01
	)

func test_sem_leque_devolve_a_mira() -> void:
	var pulse := AbilityPulse.new()
	var direcoes: Array[Vector3] = pulse.spread_directions(Vector3.FORWARD)
	assert_eq(direcoes.size(), 1)
	assert_almost_eq(direcoes[0].z, Vector3.FORWARD.z)

# ---------------------------------------------------------------- âncora deslocada

func test_deslocamento_para_a_frente_move_a_area() -> void:
	# `StartPositionZ` do original: a explosão que nasce adiante dos pés.
	# Sem o deslocamento, o alvo a 6m ficaria fora de um raio de 2.
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(0, 0, -6), 1)

	var ability := Ability.new()
	ability.id = &"adiante"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var pulse: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 40.0)
	pulse.origin = AbilityPulse.Origin.CASTER
	pulse.radius = 2.0
	pulse.forward_offset = 6.0
	ability.pulses = [pulse]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)), [alvo]
	)
	assert_almost_eq(alvo.health.current, 960.0, "a área andou 6m para a frente")

func test_sem_deslocamento_a_area_fica_nos_pes() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(0, 0, -6), 1)
	var ability := Ability.new()
	ability.id = &"nos_pes"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var pulse: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 40.0)
	pulse.origin = AbilityPulse.Origin.CASTER
	pulse.radius = 2.0
	ability.pulses = [pulse]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)), [alvo]
	)
	assert_almost_eq(alvo.health.current, 1000.0, "sem deslocamento, não alcança")

func test_deslocamento_lateral_e_perpendicular_a_mira() -> void:
	var caster: Unit = _unit()
	# Positivo é à DIREITA de quem conjura. Mirando para -Z (a frente da Godot),
	# a direita é +X: `frente.cross(UP)` de (0,0,-1) dá (1,0,0).
	var alvo: Unit = _unit(Vector3(5, 0, 0), 1)
	var esquerda: Unit = _unit(Vector3(-5, 0, 0), 1)
	var ability := Ability.new()
	ability.id = &"lado"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var pulse: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 40.0)
	pulse.origin = AbilityPulse.Origin.CASTER
	pulse.radius = 1.5
	pulse.side_offset = 5.0
	ability.pulses = [pulse]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)),
		[alvo, esquerda]
	)
	assert_almost_eq(alvo.health.current, 960.0, "a área foi para a direita")
	assert_almost_eq(esquerda.health.current, 1000.0, "e não para os dois lados")

# ---------------------------------------------------------------- trapézio

func test_trapezio_ignora_quem_esta_colado() -> void:
	var caster: Unit = _unit()
	var colado: Unit = _unit(Vector3(0, 0, -0.5), 1)
	var meio: Unit = _unit(Vector3(0, 0, -5), 1)

	var ability := Ability.new()
	ability.id = &"tiro"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var tiro: AbilityPulse = _pulso(AbilityPulse.Form.TRAPEZOID, 50.0)
	tiro.origin = AbilityPulse.Origin.CASTER
	tiro.near_distance = 2.0
	tiro.length = 10.0
	tiro.near_width = 1.0
	tiro.far_width = 5.0
	ability.pulses = [tiro]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)), [colado, meio]
	)
	assert_almost_eq(colado.health.current, 1000.0, "antes da distância mínima")
	assert_almost_eq(meio.health.current, 950.0)

func test_trapezio_alarga_com_a_distancia() -> void:
	var caster: Unit = _unit()
	# Nos 2m iniciais a meia-largura é 0.5; nos 10m é 2.5.
	var perto_fora: Unit = _unit(Vector3(1.2, 0, -2.0), 1)
	var longe_dentro: Unit = _unit(Vector3(1.2, 0, -10.0), 1)

	var ability := Ability.new()
	ability.id = &"tiro"
	ability.aim = Ability.Aim.DIRECTION
	ability.cast_range = 0.0
	var tiro: AbilityPulse = _pulso(AbilityPulse.Form.TRAPEZOID, 50.0)
	tiro.origin = AbilityPulse.Origin.CASTER
	tiro.near_distance = 2.0
	tiro.length = 10.0
	tiro.near_width = 1.0
	tiro.far_width = 5.0
	ability.pulses = [tiro]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)),
		[perto_fora, longe_dentro]
	)
	assert_almost_eq(perto_fora.health.current, 1000.0, "estreito perto")
	assert_almost_eq(longe_dentro.health.current, 950.0, "largo longe")

# ---------------------------------------------------------------- mana

func test_habilidade_cobra_mana() -> void:
	var caster: Unit = _unit()
	caster.stats.set_base(Stat.Id.MAX_MANA, 100.0)
	caster.mana.reset()
	var alvo: Unit = _unit(Vector3(2, 0, 0), 1)

	var ability := Ability.new()
	ability.id = &"cara"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	ability.mana_cost = 40.0
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 3.0
	pulse.effects = [_dano(10.0)]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [alvo]
	)
	assert_almost_eq(caster.mana.current, 60.0)

func test_sem_mana_recusa_antes_de_qualquer_efeito() -> void:
	var caster: Unit = _unit()
	caster.stats.set_base(Stat.Id.MAX_MANA, 100.0)
	caster.mana.reset()
	caster.mana.current = 10.0
	var alvo: Unit = _unit(Vector3(2, 0, 0), 1)

	var ability := Ability.new()
	ability.id = &"cara"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	ability.mana_cost = 40.0
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 3.0
	pulse.effects = [_dano(10.0)]

	var book := AbilityBook.new()
	var result: CastResult = AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [alvo]
	)
	assert_eq(result.status, CastResult.Status.NO_RESOURCE)
	assert_almost_eq(alvo.health.current, 1000.0, "recusada não bate")
	assert_almost_eq(caster.mana.current, 10.0, "recusada não cobra")
	assert_true(book.is_ready(ability), "recusada não gasta recarga")

func test_conjuracao_com_tempo_cobra_ao_iniciar() -> void:
	var caster: Unit = _unit()
	caster.stats.set_base(Stat.Id.MAX_MANA, 100.0)
	caster.mana.reset()
	var alvo: Unit = _unit(Vector3(2, 0, 0), 1)

	var ability := Ability.new()
	ability.id = &"lenta"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	ability.cast_time = 0.5
	ability.mana_cost = 30.0
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 3.0
	pulse.effects = [_dano(10.0)]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [alvo]
	)
	assert_almost_eq(caster.mana.current, 70.0, "cobra ao iniciar, como a recarga")
	book.advance_time(0.6, caster)
	AbilityEngine.resolve_pending(book, [alvo])
	assert_almost_eq(caster.mana.current, 70.0, "não cobra de novo ao terminar")

func test_quem_nao_tem_mana_conjura_de_graca() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(Vector3(2, 0, 0), 1)
	var ability := Ability.new()
	ability.id = &"livre"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 10.0
	ability.mana_cost = 500.0
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 3.0
	pulse.effects = [_dano(10.0)]

	var book := AbilityBook.new()
	var result: CastResult = AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(2, 0, 0)), [alvo]
	)
	assert_true(result.succeeded(), "sem mana máxima, custo é ignorado")

# ---------------------------------------------------------------- ranques

func test_ranque_e_um_recurso_proprio() -> void:
	# O original guarda cada ranque como uma linha separada de `skill_xml`
	# com o mesmo `SkillGroupID`. Ranque não é multiplicador: é outro conjunto
	# de números, e o modelo copia isso.
	var r1 := Ability.new()
	r1.id = &"golpe_r1"
	r1.group_id = &"golpe"
	r1.rank = 1
	r1.level_requirement = 1
	r1.single_pulse().effects = [_dano(50.0)]

	var r3 := Ability.new()
	r3.id = &"golpe_r3"
	r3.group_id = &"golpe"
	r3.rank = 3
	r3.level_requirement = 5
	r3.single_pulse().effects = [_dano(110.0)]

	assert_eq(r1.group_id, r3.group_id, "mesmo grupo")
	assert_true(r3.rank > r1.rank)
	assert_true(r3.level_requirement > r1.level_requirement)

# ---------------------------------------------------------------- descrição

func test_descricao_lista_os_pulsos() -> void:
	var ability := Ability.new()
	ability.display_name = "Combo"
	var a: AbilityPulse = _pulso(AbilityPulse.Form.LINE, 30.0)
	var b: AbilityPulse = _pulso(AbilityPulse.Form.CIRCLE, 60.0)
	b.delay = 0.4
	ability.pulses = [a, b]
	var text: String = ability.describe()
	assert_true(text.contains("line"), text)
	assert_true(text.contains("circle"), text)
	assert_true(text.contains("+0.40s"), text)

func test_tempo_total_conta_o_ultimo_pulso() -> void:
	var ability := Ability.new()
	var a := AbilityPulse.new()
	a.delay = 0.2
	var b := AbilityPulse.new()
	b.delay = 1.0
	b.duration = 2.0
	ability.pulses = [a, b]
	assert_almost_eq(ability.total_pulse_time(), 3.0)
