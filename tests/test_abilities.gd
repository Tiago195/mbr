extends TestCase

## Fase 3.2 — motor de habilidade.
##
## O último teste do arquivo é o critério de saída da Fase 3.3, verificado
## antecipadamente: declarar uma habilidade nova usando **só** configuração.

func _unit(position: Vector3 = Vector3.ZERO, team: int = 0) -> Unit:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.MAX_HEALTH: 500.0,
		Stat.Id.ABILITY_POWER: 100.0,
		Stat.Id.MOVE_SPEED: 5.0,
	})
	var unit := Unit.new(stats, team)
	unit.position = position
	return unit

func _dano(valor: float = 100.0) -> DamageEffect:
	var effect := DamageEffect.new()
	effect.base_damage = valor
	effect.damage_type = Damage.Type.TRUE
	return effect

## Habilidade de área no chão, o caso mais comum.
func _area(radius: float = 3.0, dano: float = 100.0) -> Ability:
	var ability := Ability.new()
	ability.id = &"area"
	ability.aim = Ability.Aim.POINT
	ability.single_pulse().form = AbilityPulse.Form.CIRCLE
	ability.single_pulse().radius = radius
	ability.cast_range = 10.0
	ability.cooldown = 5.0
	ability.single_pulse().effects = [_dano(dano)]
	return ability

# ---------------------------------------------------------------- forma

func test_circulo_pega_quem_esta_dentro_do_raio() -> void:
	var caster := _unit()
	var perto := _unit(Vector3(5, 0, 0), 1)
	var longe := _unit(Vector3(9, 0, 0), 1)

	var book := AbilityBook.new()
	var result := AbilityEngine.cast(
		book, _area(3.0), AbilityCast.at_point(caster, Vector3(5, 0, 0)),
		[perto, longe]
	)

	assert_true(result.succeeded())
	assert_eq(result.targets.size(), 1)
	assert_almost_eq(perto.health.current, 400.0)
	assert_almost_eq(longe.health.current, 500.0, "fora do raio")

func test_cone_pega_na_frente_e_ignora_atras() -> void:
	var caster := _unit()
	var frente := _unit(Vector3(0, 0, -4), 1)
	var atras := _unit(Vector3(0, 0, 4), 1)
	var lado := _unit(Vector3(4, 0, 0), 1)

	var ability := _area()
	ability.aim = Ability.Aim.DIRECTION
	ability.single_pulse().form = AbilityPulse.Form.CONE
	ability.single_pulse().length = 6.0
	ability.single_pulse().cone_angle = 60.0

	var book := AbilityBook.new()
	var result := AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)),
		[frente, atras, lado]
	)

	assert_eq(result.targets.size(), 1, "só quem está no setor")
	assert_almost_eq(frente.health.current, 400.0)
	assert_almost_eq(atras.health.current, 500.0)
	assert_almost_eq(lado.health.current, 500.0, "60 graus não alcança o lado")

func test_linha_pega_na_faixa_e_ignora_o_que_esta_fora_da_largura() -> void:
	var caster := _unit()
	var no_eixo := _unit(Vector3(0, 0, -5), 1)
	var perto_do_eixo := _unit(Vector3(0.6, 0, -5), 1)
	var fora := _unit(Vector3(3, 0, -5), 1)
	var alem := _unit(Vector3(0, 0, -12), 1)

	var ability := _area()
	ability.aim = Ability.Aim.DIRECTION
	ability.single_pulse().form = AbilityPulse.Form.LINE
	ability.single_pulse().length = 8.0
	ability.single_pulse().width = 2.0

	var book := AbilityBook.new()
	var result := AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)),
		[no_eixo, perto_do_eixo, fora, alem]
	)

	assert_eq(result.targets.size(), 2)
	assert_almost_eq(no_eixo.health.current, 400.0)
	assert_almost_eq(perto_do_eixo.health.current, 400.0, "dentro da meia-largura")
	assert_almost_eq(fora.health.current, 500.0, "fora da largura")
	assert_almost_eq(alem.health.current, 500.0, "além do comprimento")

func test_projetil_que_nao_atravessa_para_no_primeiro() -> void:
	var caster := _unit()
	var primeiro := _unit(Vector3(0, 0, -3), 1)
	var segundo := _unit(Vector3(0, 0, -6), 1)

	var ability := _area()
	ability.aim = Ability.Aim.DIRECTION
	ability.single_pulse().form = AbilityPulse.Form.PROJECTILE
	ability.single_pulse().length = 10.0
	ability.single_pulse().width = 1.5
	ability.single_pulse().pierces = false

	var book := AbilityBook.new()
	var candidatos: Array = [segundo, primeiro]
	var result := AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)), candidatos
	)

	# O tiro SAIU e não acertou ninguém ainda. Antes, o dano saía no mesmo
	# quadro do clique e a esfera na tela era enfeite.
	assert_eq(result.launched, 1, "um projétil no ar")
	assert_eq(result.targets.size(), 0, "ninguém foi atingido na conjuração")
	assert_almost_eq(primeiro.health.current, 500.0, "ninguém levou dano ainda")

	var impactos: Array[CastResult] = _voar(book, candidatos)
	assert_eq(impactos.size(), 1, "um impacto")
	assert_almost_eq(primeiro.health.current, 400.0, "o mais próximo")
	assert_almost_eq(segundo.health.current, 500.0)

func test_teto_de_alvos_pega_os_mais_proximos() -> void:
	var caster := _unit()
	var a := _unit(Vector3(1, 0, 0), 1)
	var b := _unit(Vector3(2, 0, 0), 1)
	var c := _unit(Vector3(3, 0, 0), 1)

	var ability := _area(10.0)
	ability.single_pulse().max_targets = 2

	var book := AbilityBook.new()
	var result := AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3.ZERO), [c, b, a]
	)

	assert_eq(result.targets.size(), 2)
	assert_almost_eq(a.health.current, 400.0)
	assert_almost_eq(b.health.current, 400.0)
	assert_almost_eq(c.health.current, 500.0, "o mais distante ficou de fora")

# ---------------------------------------------------------------- filtro

func test_por_padrao_atinge_inimigo_e_poupa_aliado_e_a_si_mesmo() -> void:
	var caster := _unit()
	var aliado := _unit(Vector3(1, 0, 0), 0)
	var inimigo := _unit(Vector3(2, 0, 0), 1)

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, _area(10.0), AbilityCast.at_point(caster, Vector3.ZERO),
		[aliado, inimigo, caster]
	)

	assert_almost_eq(inimigo.health.current, 400.0)
	assert_almost_eq(aliado.health.current, 500.0)
	assert_almost_eq(caster.health.current, 500.0)

func test_cura_em_area_atinge_aliados_e_a_si_mesmo() -> void:
	var caster := _unit()
	var aliado := _unit(Vector3(1, 0, 0), 0)
	var inimigo := _unit(Vector3(2, 0, 0), 1)
	caster.receive_damage(null, 200.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)
	aliado.receive_damage(null, 200.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)

	var cura := HealEffect.new()
	cura.base_heal = 150.0

	var ability := _area(10.0)
	ability.id = &"cura_em_area"
	ability.single_pulse().hits_enemies = false
	ability.single_pulse().hits_allies = true
	ability.single_pulse().hits_self = true
	ability.single_pulse().effects = [cura]

	var book := AbilityBook.new()
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3.ZERO),
		[aliado, inimigo, caster]
	)

	assert_almost_eq(caster.health.current, 450.0)
	assert_almost_eq(aliado.health.current, 450.0)
	assert_almost_eq(inimigo.health.current, 500.0, "inimigo não é curado")

func test_alvo_morto_nao_entra_na_conta() -> void:
	var caster := _unit()
	var morto := _unit(Vector3(1, 0, 0), 1)
	morto.receive_damage(null, 999.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)

	var book := AbilityBook.new()
	var result := AbilityEngine.cast(
		book, _area(10.0), AbilityCast.at_point(caster, Vector3.ZERO), [morto]
	)

	assert_true(result.succeeded(), "skillshot sai mesmo sem acertar")
	assert_eq(result.targets.size(), 0, "mas o cadáver não conta como alvo")

# ---------------------------------------------------------------- recarga

func test_recarga_bloqueia_a_segunda_conjuracao() -> void:
	var caster := _unit()
	var alvo := _unit(Vector3(1, 0, 0), 1)
	var book := AbilityBook.new()
	var ability := _area(10.0)

	assert_true(AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3.ZERO), [alvo]
	).succeeded())

	var segunda := AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3.ZERO), [alvo]
	)
	assert_eq(segunda.status, CastResult.Status.ON_COOLDOWN)
	assert_almost_eq(segunda.cooldown_remaining, 5.0)

	book.advance_time(5.1, caster)
	assert_true(book.is_ready(ability), "recarregou")

func test_reducao_de_recarga_encurta_a_espera() -> void:
	var caster := _unit()
	caster.stats.set_base(Stat.Id.COOLDOWN_REDUCTION, 0.40)
	var alvo := _unit(Vector3(1, 0, 0), 1)
	var book := AbilityBook.new()
	var ability := _area(10.0)

	AbilityEngine.cast(book, ability, AbilityCast.at_point(caster, Vector3.ZERO), [alvo])
	assert_almost_eq(book.remaining_cooldown(ability), 3.0, "5s com 40% de redução")

func test_reducao_de_recarga_e_limitada() -> void:
	var caster := _unit()
	caster.stats.set_base(Stat.Id.COOLDOWN_REDUCTION, 5.0)
	var ability := _area(10.0)
	assert_almost_eq(ability.cooldown_for(caster), 0.5, "teto de 90%")

func test_skillshot_errado_gasta_a_recarga() -> void:
	# Errar faz parte. Devolver a recarga de quem errou tornaria mira
	# irrelevante.
	var caster := _unit()
	var longe := _unit(Vector3(50, 0, 0), 1)
	var book := AbilityBook.new()
	var ability := _area(3.0)

	var result := AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3.ZERO), [longe]
	)

	assert_true(result.succeeded())
	assert_eq(result.targets.size(), 0, "não acertou ninguém")
	assert_false(book.is_ready(ability), "e mesmo assim gastou")

func test_alvo_unico_sem_alvo_e_recusado_sem_custo() -> void:
	# O outro lado da regra: sem alguém apontado não há comando a emitir.
	var caster := _unit()
	var book := AbilityBook.new()
	var ability := _area(3.0)
	ability.aim = Ability.Aim.UNIT
	ability.single_pulse().form = AbilityPulse.Form.SINGLE

	var result := AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3.ZERO), []
	)

	assert_eq(result.status, CastResult.Status.NO_TARGET)
	assert_true(book.is_ready(ability), "não desperdiçou")

func test_instantanea_e_com_tempo_gastam_a_recarga_igual_ao_errar() -> void:
	# Já foi diferente: a instantânea era devolvida e a com tempo de
	# conjuração não, porque a recarga da segunda começa ao iniciar. Dois
	# comportamentos para a mesma situação.
	var caster := _unit()
	var instantanea := _area(3.0)
	var demorada := _area(3.0)
	demorada.id = &"demorada"
	demorada.cast_time = 0.5

	var livro_a := AbilityBook.new()
	AbilityEngine.cast(livro_a, instantanea, AbilityCast.at_point(caster, Vector3.ZERO), [])
	assert_false(livro_a.is_ready(instantanea), "instantânea gastou")

	var livro_b := AbilityBook.new()
	AbilityEngine.cast(livro_b, demorada, AbilityCast.at_point(caster, Vector3.ZERO), [])
	livro_b.advance_time(0.6, caster)
	AbilityEngine.resolve_pending(livro_b, [])
	assert_false(livro_b.is_ready(demorada), "com tempo também gastou")

# ---------------------------------------------------------------- alcance

func test_fora_de_alcance_e_recusado() -> void:
	var caster := _unit()
	var book := AbilityBook.new()
	var ability := _area(3.0)
	ability.cast_range = 8.0

	var result := AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(20, 0, 0)), []
	)
	assert_eq(result.status, CastResult.Status.OUT_OF_RANGE)
	assert_true(book.is_ready(ability), "recusa não gasta recarga")

func test_alvo_unico_fora_de_alcance_e_recusado() -> void:
	var caster := _unit()
	var alvo := _unit(Vector3(20, 0, 0), 1)
	var ability := _area(3.0)
	ability.aim = Ability.Aim.UNIT
	ability.single_pulse().form = AbilityPulse.Form.SINGLE
	ability.cast_range = 8.0

	var result := AbilityEngine.cast(
		AbilityBook.new(), ability, AbilityCast.on_unit(caster, alvo), [alvo]
	)
	assert_eq(result.status, CastResult.Status.OUT_OF_RANGE)

# ---------------------------------------------------------------- estados

func test_silenciado_nao_conjura() -> void:
	var caster := _unit()
	caster.status.apply(StatusSet.Kind.SILENCE, 2.0)
	var alvo := _unit(Vector3(1, 0, 0), 1)

	var result := AbilityEngine.cast(
		AbilityBook.new(), _area(10.0),
		AbilityCast.at_point(caster, Vector3.ZERO), [alvo]
	)
	assert_eq(result.status, CastResult.Status.CANNOT_CAST)
	assert_almost_eq(alvo.health.current, 500.0)

func test_stunado_nao_conjura() -> void:
	var caster := _unit()
	caster.status.apply(StatusSet.Kind.STUN, 2.0)
	var result := AbilityEngine.cast(
		AbilityBook.new(), _area(10.0),
		AbilityCast.at_point(caster, Vector3.ZERO), []
	)
	assert_eq(result.status, CastResult.Status.CANNOT_CAST)

func test_morto_nao_conjura() -> void:
	var caster := _unit()
	caster.receive_damage(null, 999.0, Damage.Type.TRUE, Damage.Source.ENVIRONMENT)
	var result := AbilityEngine.cast(
		AbilityBook.new(), _area(10.0),
		AbilityCast.at_point(caster, Vector3.ZERO), []
	)
	assert_eq(result.status, CastResult.Status.DEAD)

# ---------------------------------------------------------------- conjuração

func test_habilidade_com_tempo_so_sai_no_fim() -> void:
	var caster := _unit()
	var alvo := _unit(Vector3(1, 0, 0), 1)
	var book := AbilityBook.new()
	var ability := _area(10.0)
	ability.cast_time = 1.5

	var inicio := AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3.ZERO), [alvo]
	)
	assert_eq(inicio.status, CastResult.Status.CASTING)
	assert_almost_eq(alvo.health.current, 500.0, "ainda não saiu")

	book.advance_time(1.0, caster)
	assert_false(book.cast_is_ready())

	book.advance_time(0.6, caster)
	assert_true(book.cast_is_ready())

	var fim := AbilityEngine.resolve_pending(book, [alvo])
	assert_true(fim.succeeded())
	assert_almost_eq(alvo.health.current, 400.0)

func test_stun_no_meio_da_conjuracao_corta() -> void:
	var caster := _unit()
	var alvo := _unit(Vector3(1, 0, 0), 1)
	var book := AbilityBook.new()
	var ability := _area(10.0)
	ability.cast_time = 2.0

	AbilityEngine.cast(book, ability, AbilityCast.at_point(caster, Vector3.ZERO), [alvo])
	caster.status.apply(StatusSet.Kind.STUN, 1.0)
	book.advance_time(0.5, caster)

	assert_false(book.is_casting(), "cortou")
	assert_almost_eq(alvo.health.current, 500.0, "não saiu")
	assert_false(book.is_ready(ability), "mas a recarga foi gasta")

func test_nao_conjura_duas_ao_mesmo_tempo() -> void:
	var caster := _unit()
	var book := AbilityBook.new()
	var lenta := _area(10.0)
	lenta.cast_time = 2.0
	var outra := _area(10.0)
	outra.id = &"outra"

	AbilityEngine.cast(book, lenta, AbilityCast.at_point(caster, Vector3.ZERO), [])
	var segunda := AbilityEngine.cast(
		book, outra, AbilityCast.at_point(caster, Vector3.ZERO), []
	)
	assert_eq(segunda.status, CastResult.Status.BUSY)

func test_alvos_sao_recalculados_no_fim_da_conjuracao() -> void:
	# Entre o começo e o fim, o mundo se mexeu. Acertar quem já saiu da área
	# seria errado, então a lista é pedida de novo.
	var caster := _unit()
	var fugitivo := _unit(Vector3(1, 0, 0), 1)
	var book := AbilityBook.new()
	var ability := _area(3.0)
	ability.cast_time = 1.0

	AbilityEngine.cast(book, ability, AbilityCast.at_point(caster, Vector3.ZERO), [fugitivo])
	fugitivo.position = Vector3(30, 0, 0)
	book.advance_time(1.1, caster)

	var fim := AbilityEngine.resolve_pending(book, [fugitivo])
	assert_eq(fim.targets.size(), 0, "saiu da área a tempo")
	assert_almost_eq(fugitivo.health.current, 500.0)

# ---------------------------------------------------------------- efeitos

func test_efeito_no_conjurador_sai_uma_vez_so() -> void:
	# Um dash com três inimigos na frente não pode andar o triplo.
	var caster := _unit()
	var a := _unit(Vector3(0, 0, -2), 1)
	var b := _unit(Vector3(0, 0, -4), 1)
	var c := _unit(Vector3(0, 0, -6), 1)

	var dash := DisplacementEffect.new()
	dash.mode = DisplacementEffect.Mode.ALONG_AIM
	dash.recipient = AbilityEffect.Recipient.CASTER
	dash.distance = 5.0

	var ability := _area(10.0)
	ability.aim = Ability.Aim.DIRECTION
	ability.single_pulse().form = AbilityPulse.Form.LINE
	ability.single_pulse().length = 10.0
	ability.single_pulse().width = 2.0
	ability.single_pulse().effects = [dash, _dano(50.0)]

	AbilityEngine.cast(
		AbilityBook.new(), ability, AbilityCast.toward(caster, Vector3(0, 0, -1)),
		[a, b, c]
	)

	assert_almost_eq(caster.consume_displacement().z, -5.0, "andou uma vez")
	assert_almost_eq(a.health.current, 450.0, "mas o dano pegou os três")
	assert_almost_eq(c.health.current, 450.0)

func test_habilidade_que_age_no_conjurador_sai_em_area_vazia() -> void:
	var caster := _unit()
	var dash := DisplacementEffect.new()
	dash.mode = DisplacementEffect.Mode.ALONG_AIM
	dash.recipient = AbilityEffect.Recipient.CASTER
	dash.distance = 4.0

	var ability := _area(10.0)
	ability.aim = Ability.Aim.DIRECTION
	ability.single_pulse().form = AbilityPulse.Form.LINE
	ability.single_pulse().effects = [dash]

	var result := AbilityEngine.cast(
		AbilityBook.new(), ability, AbilityCast.toward(caster, Vector3(1, 0, 0)), []
	)
	assert_true(result.succeeded(), "dash não depende de acertar ninguém")
	assert_almost_eq(caster.consume_displacement().x, 4.0)

func test_efeitos_saem_na_ordem_declarada() -> void:
	# O escudo entra antes do dano, então absorve. Invertido, o alvo levaria
	# o dano na vida e só depois ganharia escudo.
	var caster := _unit()
	var alvo := _unit(Vector3(1, 0, 0), 0)

	var escudo := ShieldEffect.new()
	escudo.base_shield = 200.0
	escudo.duration = 5.0

	var ability := _area(10.0)
	ability.single_pulse().hits_enemies = false
	ability.single_pulse().hits_allies = true
	ability.single_pulse().effects = [escudo, _dano(100.0)]

	AbilityEngine.cast(
		AbilityBook.new(), ability, AbilityCast.at_point(caster, Vector3.ZERO), [alvo]
	)

	assert_almost_eq(alvo.health.current, 500.0, "o escudo comeu o dano")
	assert_almost_eq(alvo.health.shield, 100.0)

# ---------------------------------------------------------------- livro

func test_slots_guardam_as_habilidades() -> void:
	var book := AbilityBook.new()
	var q := _area()
	book.learn(AbilityBook.Slot.Q, q)
	assert_eq(book.ability_in(AbilityBook.Slot.Q), q)
	assert_null(book.ability_in(AbilityBook.Slot.R))
	assert_eq(book.known_abilities().size(), 1)

# ---------------------------------------------------------------- dados reais

## As três habilidades da Fase 3.3, carregadas dos `.tres` que o jogo usa.
##
## Sem isto, alguém quebra um recurso — enum trocado, efeito nulo — e só se
## descobre abrindo o jogo e apertando a tecla.
const CAMINHOS: Array[String] = [
	"res://data/abilities/meteoro.tres",
	"res://data/abilities/raio.tres",
	"res://data/abilities/investida.tres",
]

func test_habilidades_do_jogo_carregam() -> void:
	for caminho: String in CAMINHOS:
		var ability := load(caminho) as Ability
		assert_not_null(ability, caminho)
		if ability == null:
			continue
		assert_false(String(ability.id).is_empty(), "%s sem id" % caminho)
		assert_true(ability.has_pulses(), "%s sem pulso com efeito" % caminho)
		for pulse: AbilityPulse in ability.pulses:
			assert_not_null(pulse, "%s com pulso nulo" % caminho)
			if pulse == null:
				continue
			for effect: AbilityEffect in pulse.effects:
				assert_not_null(effect, "%s com efeito nulo" % caminho)

func test_meteoro_causa_dano_em_area() -> void:
	var ability := load("res://data/abilities/meteoro.tres") as Ability
	var caster := _unit()
	var alvo := _unit(Vector3(4, 0, 0), 1)
	var book := AbilityBook.new()

	var inicio := AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(4, 0, 0)), [alvo]
	)
	assert_eq(inicio.status, CastResult.Status.CASTING, "tem tempo de conjuração")

	book.advance_time(ability.cast_time + 0.1, caster)
	var fim := AbilityEngine.resolve_pending(book, [alvo])
	assert_true(fim.succeeded())
	# 90 + 100*0.6 = 150 mágico, sem resistência no alvo de teste
	assert_almost_eq(alvo.health.current, 350.0)

func test_investida_avanca_e_escuda_o_conjurador() -> void:
	var ability := load("res://data/abilities/investida.tres") as Ability
	var caster := _unit()
	var alvo := _unit(Vector3(0, 0, -3), 1)

	var result := AbilityEngine.cast(
		AbilityBook.new(), ability,
		AbilityCast.toward(caster, Vector3(0, 0, -1)), [alvo]
	)

	assert_true(result.succeeded())
	assert_almost_eq(caster.consume_displacement().z, -6.5, "avançou")
	# 90 + 100*0.5 = 140 de escudo, no conjurador
	assert_almost_eq(caster.health.shield, 140.0)
	assert_almost_eq(alvo.health.shield, 0.0, "o inimigo não ganha escudo")
	assert_true(alvo.health.current < 500.0, "e leva dano")

func test_raio_para_no_primeiro_e_deixa_lento() -> void:
	var ability := load("res://data/abilities/raio.tres") as Ability
	var caster := _unit()
	var primeiro := _unit(Vector3(0, 0, -3), 1)
	var segundo := _unit(Vector3(0, 0, -7), 1)

	var book := AbilityBook.new()
	var candidatos: Array = [segundo, primeiro]
	AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)), candidatos
	)
	var impactos: Array[CastResult] = _voar(book, candidatos)

	assert_eq(impactos.size(), 1, "não atravessa")
	assert_almost_eq(segundo.health.current, 500.0, "o de trás fica ileso")
	assert_almost_eq(
		primeiro.stats.get_value(Stat.Id.MOVE_SPEED), 3.25, "5 com 35% de lentidão"
	)

## Voa até não haver mais projétil no ar. Devolve os impactos, em ordem.
##
## Passo de 1/60 de propósito: é o tique do jogo, e um passo grande esconderia
## erro de varredura — que é justamente o defeito que projétil rápido tem.
func _voar(book: AbilityBook, candidatos: Array, limite: int = 1200) -> Array[CastResult]:
	var impactos: Array[CastResult] = []
	for _passo: int in limite:
		if book.projectiles.is_empty():
			break
		for r: CastResult in AbilityEngine.advance_projectiles(
				book, 1.0 / 60.0, candidatos
		):
			impactos.append(r)
	return impactos

# ------------------------------------------- CRITÉRIO ANTECIPADO DA FASE 3.3

func test_quarta_habilidade_nasce_so_de_configuracao() -> void:
	## O critério de saída da Fase 3.3: "consigo adicionar uma quarta
	## habilidade escrevendo só configuração, sem tocar em código de sistema?"
	##
	## Esta habilidade não existe em lugar nenhum do código de produção. É
	## montada aqui inteiramente com peças do vocabulário — e se um dia ela
	## exigir uma classe nova, este teste é o que vai avisar.
	##
	## "Investida Trovejante": avança em linha, empurra quem estiver no
	## caminho, causa dano mágico com escalonamento, atordoa por 1s e deixa o
	## conjurador com escudo.
	var investida := Ability.new()
	investida.id = &"investida_trovejante"
	investida.display_name = "Investida Trovejante"
	investida.aim = Ability.Aim.DIRECTION
	investida.single_pulse().form = AbilityPulse.Form.LINE
	investida.single_pulse().length = 7.0
	investida.single_pulse().width = 2.5
	investida.cooldown = 14.0
	investida.cast_range = 0.0
	investida.single_pulse().max_targets = 3

	var dash := DisplacementEffect.new()
	dash.mode = DisplacementEffect.Mode.ALONG_AIM
	dash.recipient = AbilityEffect.Recipient.CASTER
	dash.distance = 7.0

	var escudo := ShieldEffect.new()
	escudo.recipient = AbilityEffect.Recipient.CASTER
	escudo.base_shield = 80.0
	escudo.scaling_stat = Stat.Id.ABILITY_POWER
	escudo.scaling_ratio = 0.4
	escudo.duration = 3.0

	var dano := DamageEffect.new()
	dano.base_damage = 70.0
	dano.scaling_stat = Stat.Id.ABILITY_POWER
	dano.scaling_ratio = 0.5
	dano.damage_type = Damage.Type.MAGIC

	var atordoa := CrowdControlEffect.new()
	atordoa.control = CrowdControlEffect.Kind.STUN
	atordoa.duration = 1.0

	var empurra := DisplacementEffect.new()
	empurra.mode = DisplacementEffect.Mode.AWAY_FROM_CASTER
	empurra.distance = 2.0
	empurra.ignores_root = true

	investida.single_pulse().effects = [dash, dano, atordoa, empurra, escudo]

	var caster := _unit()
	var alvo := _unit(Vector3(0, 0, -3), 1)

	var result := AbilityEngine.cast(
		AbilityBook.new(), investida,
		AbilityCast.toward(caster, Vector3(0, 0, -1)), [alvo]
	)

	assert_true(result.succeeded(), "conjurou")
	assert_almost_eq(caster.consume_displacement().z, -7.0, "avançou")
	# 70 + 100*0.5 = 120, contra 0 de resistência mágica
	assert_almost_eq(alvo.health.current, 380.0, "dano com escalonamento")
	assert_true(alvo.status.has(StatusSet.Kind.STUN), "atordoou")
	assert_almost_eq(alvo.consume_displacement().z, -2.0, "empurrou para longe")
	# O escudo foi para o CONJURADOR, não para o inimigo. É a combinação que
	# o vocabulário não expressava antes de `recipient` existir.
	assert_almost_eq(caster.health.shield, 120.0, "80 + 100*0.4, no conjurador")
	assert_almost_eq(alvo.health.shield, 0.0, "o inimigo não ganhou escudo")
