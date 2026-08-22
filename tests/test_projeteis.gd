extends TestCase

## O projétil que voa de verdade.
##
## Existe por um relato do usuário testando o jogo: *"os projéteis estão
## causando dano assim que é clicado, e não se realmente acerta o alvo"*. Ele
## estava certo, e o código admitia em comentário — a esfera na tela fazia sua
## própria viagem enquanto o dano já tinha saído.
##
## O que estes testes protegem não é "existe um objeto voando": é que **acertar
## depende de estar no caminho quando o projétil passa**. Sem isso, mira é
## decoração.

const TIQUE: float = 1.0 / 60.0

func _unit(position: Vector3 = Vector3.ZERO, team: int = 0) -> Unit:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.MAX_HEALTH: 500.0,
		Stat.Id.ATTACK_DAMAGE: 100.0,
		Stat.Id.ABILITY_POWER: 100.0,
		Stat.Id.MOVE_SPEED: 5.0,
	})
	var unit := Unit.new(stats, team)
	unit.position = position
	return unit

## Uma habilidade de um pulso de projétil, com dano fixo.
func _tiro(
		length: float = 10.0,
		speed: float = 12.0,
		width: float = 1.0,
		pierces: bool = false
) -> Ability:
	var ability := Ability.new()
	ability.id = &"tiro"
	ability.aim = Ability.Aim.DIRECTION
	ability.cooldown = 0.0

	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.PROJECTILE
	pulse.length = length
	pulse.width = width
	pulse.projectile_speed = speed
	pulse.pierces = pierces

	var dano := DamageEffect.new()
	dano.base_damage = 100.0
	dano.scaling_ratio = 0.0
	dano.damage_type = Damage.Type.TRUE
	pulse.effects = [dano]
	return ability

func _cast(book: AbilityBook, ability: Ability, caster: Unit, candidatos: Array) -> CastResult:
	return AbilityEngine.cast(
		book, ability, AbilityCast.toward(caster, Vector3(0, 0, -1)), candidatos
	)

## Avança um tique e devolve os impactos daquele tique.
func _tique(book: AbilityBook, candidatos: Array) -> Array[CastResult]:
	return AbilityEngine.advance_projectiles(book, TIQUE, candidatos)

## Voa até nada mais estar no ar. Devolve quantos tiques levou.
func _voar(book: AbilityBook, candidatos: Array, limite: int = 2000) -> int:
	var tiques: int = 0
	while not book.projectiles.is_empty() and tiques < limite:
		_tique(book, candidatos)
		tiques += 1
	return tiques

# ------------------------------------------------- o dano não sai no clique

func test_o_dano_nao_sai_no_clique() -> void:
	# O relato do usuário, virado teste.
	var caster := _unit()
	var alvo := _unit(Vector3(0, 0, -5), 1)
	var book := AbilityBook.new()

	var result: CastResult = _cast(book, _tiro(), caster, [alvo])

	assert_true(result.succeeded(), "a conjuração saiu")
	assert_eq(result.launched, 1, "um projétil no ar")
	assert_almost_eq(alvo.health.current, 500.0, "ninguém levou dano no clique")
	assert_eq(book.projectiles.count(), 1)

	_voar(book, [alvo])
	assert_almost_eq(alvo.health.current, 400.0, "o dano saiu no impacto")

func test_o_tempo_ate_o_impacto_bate_com_a_velocidade() -> void:
	# 6 metros a 12 m/s são meio segundo. Um projétil que chegasse na hora
	# errada é indistinguível de um que não voa.
	var caster := _unit()
	var alvo := _unit(Vector3(0, 0, -6), 1)
	var book := AbilityBook.new()
	_cast(book, _tiro(10.0, 12.0), caster, [alvo])

	var tiques: int = 0
	var acertou_em: int = -1
	while not book.projectiles.is_empty() and tiques < 200:
		tiques += 1
		if not _tique(book, [alvo]).is_empty():
			acertou_em = tiques

	assert_true(acertou_em > 0, "nunca acertou")
	var segundos: float = float(acertou_em) * TIQUE
	# Tolerância de um tique: o impacto é detectado no fim do trecho varrido.
	assert_true(
		absf(segundos - 0.5) <= TIQUE * 2.0,
		"levou %.3fs para andar 6m a 12m/s" % segundos
	)

# ------------------------------------------------------------- varredura

func test_projetil_rapido_nao_atravessa_alvo_estreito() -> void:
	# O defeito clássico de projétil, e o que amostrar em vez de varrer causa:
	# a 60 m/s um tique de 60 Hz anda 1 metro, e um alvo de meio metro cabe
	# inteiro no meio do salto. Não dá erro — o tiro simplesmente passa direto.
	var caster := _unit()
	var alvo := _unit(Vector3(0, 0, -7.5), 1)
	var book := AbilityBook.new()
	_cast(book, _tiro(20.0, 60.0, 0.4), caster, [alvo])

	_voar(book, [alvo])
	assert_almost_eq(alvo.health.current, 400.0, "o tiro rápido atravessou o alvo")

func test_alvo_fora_da_largura_nao_leva() -> void:
	var caster := _unit()
	var alvo := _unit(Vector3(2.0, 0, -5), 1)
	var book := AbilityBook.new()
	_cast(book, _tiro(10.0, 12.0, 1.0), caster, [alvo])

	_voar(book, [alvo])
	assert_almost_eq(alvo.health.current, 500.0, "acertou quem estava 2m ao lado")

# ------------------------------------------------ mira passa a valer alguma coisa

func test_quem_sai_do_caminho_nao_leva_dano() -> void:
	# O que o modelo antigo tornava impossível: no clique o alvo estava na
	# linha, e ele saiu antes de a esfera chegar. Antes, levava dano do mesmo
	# jeito — e é isso que fazia desviar não querer dizer nada.
	var caster := _unit()
	var alvo := _unit(Vector3(0, 0, -9), 1)
	var book := AbilityBook.new()
	_cast(book, _tiro(12.0, 6.0, 1.0), caster, [alvo])

	# Meio segundo depois o projétil ainda está longe; o alvo se afasta.
	for _passo: int in 30:
		_tique(book, [alvo])
	assert_almost_eq(alvo.health.current, 500.0, "não devia ter chegado ainda")
	alvo.position = Vector3(5.0, 0, -9)

	_voar(book, [alvo])
	assert_almost_eq(alvo.health.current, 500.0, "quem desviou levou dano")

func test_quem_entra_no_caminho_leva_dano() -> void:
	# O outro lado da mesma moeda: no clique não havia ninguém na linha.
	var caster := _unit()
	var alvo := _unit(Vector3(6.0, 0, -9), 1)
	var book := AbilityBook.new()
	var result: CastResult = _cast(book, _tiro(12.0, 6.0, 1.0), caster, [alvo])
	assert_eq(result.targets.size(), 0, "não havia ninguém na linha")

	alvo.position = Vector3(0.0, 0, -9)
	_voar(book, [alvo])
	assert_almost_eq(alvo.health.current, 400.0, "quem entrou na frente não levou")

# ------------------------------------------------------------- perfuração

func test_sem_perfurar_para_no_primeiro() -> void:
	var caster := _unit()
	var perto := _unit(Vector3(0, 0, -3), 1)
	var longe := _unit(Vector3(0, 0, -6), 1)
	var book := AbilityBook.new()
	_cast(book, _tiro(12.0, 12.0, 1.0, false), caster, [longe, perto])

	_voar(book, [longe, perto])
	assert_almost_eq(perto.health.current, 400.0, "o da frente leva")
	assert_almost_eq(longe.health.current, 500.0, "o de trás fica ileso")

func test_perfurante_pega_os_dois_e_nao_bate_duas_vezes_no_mesmo() -> void:
	# Bater duas vezes no mesmo é o defeito que aparece quando o projétil é
	# lento: ele fica dentro do alvo por vários tiques.
	var caster := _unit()
	var perto := _unit(Vector3(0, 0, -3), 1)
	var longe := _unit(Vector3(0, 0, -6), 1)
	var book := AbilityBook.new()
	_cast(book, _tiro(12.0, 3.0, 2.0, true), caster, [longe, perto])

	_voar(book, [longe, perto])
	assert_almost_eq(perto.health.current, 400.0, "bateu mais de uma vez no da frente")
	assert_almost_eq(longe.health.current, 400.0, "não perfurou até o de trás")

func test_teto_de_alvos_limita_o_perfurante() -> void:
	var caster := _unit()
	var a := _unit(Vector3(0, 0, -2), 1)
	var b := _unit(Vector3(0, 0, -4), 1)
	var c := _unit(Vector3(0, 0, -6), 1)
	var ability := _tiro(12.0, 12.0, 1.0, true)
	ability.single_pulse().max_targets = 2

	var book := AbilityBook.new()
	_cast(book, ability, caster, [c, b, a])
	_voar(book, [c, b, a])

	assert_almost_eq(a.health.current, 400.0)
	assert_almost_eq(b.health.current, 400.0)
	assert_almost_eq(c.health.current, 500.0, "passou do teto de 2 alvos")

# ------------------------------------------------------------- alcance

func test_expira_no_alcance_sem_acertar_quem_esta_alem() -> void:
	var caster := _unit()
	var longe := _unit(Vector3(0, 0, -15), 1)
	var book := AbilityBook.new()
	_cast(book, _tiro(8.0, 20.0, 1.0), caster, [longe])

	var tiques: int = _voar(book, [longe])
	assert_true(tiques > 0, "o projétil nem chegou a existir")
	assert_true(book.projectiles.is_empty(), "ficou preso no ar")
	assert_almost_eq(longe.health.current, 500.0, "acertou além do alcance")

func test_o_projetil_para_onde_acertou() -> void:
	# A esfera na tela segue esta posição. Se ela seguisse até o fim do
	# alcance, o jogador veria o tiro passar direto por quem levou dano.
	var caster := _unit()
	var alvo := _unit(Vector3(0, 0, -4), 1)
	var book := AbilityBook.new()
	_cast(book, _tiro(12.0, 8.0, 1.0), caster, [alvo])

	var onde: Vector3 = Vector3.ZERO
	while not book.projectiles.is_empty():
		var voando: Array[ProjectileSet.Projectile] = book.projectiles.flying()
		onde = voando[0].position
		if not _tique(book, [alvo]).is_empty():
			onde = voando[0].position
			break
	# Para ao ENCOSTAR, não ao chegar no centro: com largura 1,0 o contato
	# acontece meia largura antes, em z ≈ -3,5. Exigir -4,0 seria exigir que a
	# esfera entrasse dentro do alvo antes de explodir.
	assert_true(
		absf(onde.z + 3.5) <= 0.25,
		"parou em z=%.2f; o alvo está em z=-4 e a largura é 1,0" % onde.z
	)

# ------------------------------------------------------------- filtro

func test_nao_acerta_aliado() -> void:
	var caster := _unit()
	var aliado := _unit(Vector3(0, 0, -3), 0)
	var inimigo := _unit(Vector3(0, 0, -6), 1)
	var book := AbilityBook.new()
	_cast(book, _tiro(12.0, 12.0, 1.0), caster, [aliado, inimigo])

	_voar(book, [aliado, inimigo])
	assert_almost_eq(aliado.health.current, 500.0, "o projétil feriu o próprio time")
	assert_almost_eq(inimigo.health.current, 400.0, "parou no aliado em vez de passar")

# ------------------------------------------------------------- leque

func test_leque_lanca_um_projetil_por_direcao() -> void:
	var caster := _unit()
	var ability := _tiro(12.0, 12.0, 1.0)
	ability.single_pulse().spread_count = 3
	ability.single_pulse().spread_angle = 60.0

	var book := AbilityBook.new()
	var result: CastResult = _cast(book, ability, caster, [])
	assert_eq(result.launched, 3, "três direções, três projéteis")
	assert_eq(book.projectiles.count(), 3)

func test_cada_flecha_do_leque_acerta_a_sua() -> void:
	# O ganho concreto do voo separado. Antes, uma habilidade de projétil sem
	# perfuração tinha teto de UM alvo para o leque inteiro: três flechas
	# acertavam uma pessoa só. Agora cada flecha carrega o próprio teto.
	var caster := _unit()
	var ability := _tiro(12.0, 12.0, 1.0)
	ability.single_pulse().spread_count = 3
	ability.single_pulse().spread_angle = 60.0

	# Um alvo em cada raio: -30°, 0° e +30°, a 5 metros.
	var esquerda := _unit(Vector3(-2.5, 0, -4.33), 1)
	var centro := _unit(Vector3(0, 0, -5), 1)
	var direita := _unit(Vector3(2.5, 0, -4.33), 1)
	var candidatos: Array = [esquerda, centro, direita]

	var book := AbilityBook.new()
	_cast(book, ability, caster, candidatos)
	_voar(book, candidatos)

	var atingidos: int = 0
	for unit: Unit in [esquerda, centro, direita] as Array[Unit]:
		if unit.health.current < 500.0:
			atingidos += 1
	assert_eq(atingidos, 3, "só %d das três flechas acertaram" % atingidos)

# --------------------------------------------------- efeito no conjurador

func test_o_efeito_do_conjurador_sai_no_lancamento_e_uma_vez_so() -> void:
	# O escudo de quem atira não depende de a flecha acertar — e não pode sair
	# de novo a cada inimigo perfurado.
	var caster := _unit()
	var a := _unit(Vector3(0, 0, -3), 1)
	var b := _unit(Vector3(0, 0, -5), 1)

	var ability := _tiro(12.0, 12.0, 1.0, true)
	var escudo := ShieldEffect.new()
	escudo.recipient = AbilityEffect.Recipient.CASTER
	escudo.base_shield = 50.0
	escudo.scaling_ratio = 0.0
	escudo.duration = 30.0
	ability.single_pulse().effects.append(escudo)

	var book := AbilityBook.new()
	_cast(book, ability, caster, [a, b])
	assert_almost_eq(caster.health.shield, 50.0, "o escudo devia sair no lançamento")

	_voar(book, [a, b])
	assert_almost_eq(caster.health.shield, 50.0, "o escudo saiu de novo a cada acerto")
	assert_almost_eq(a.health.current, 400.0)
	assert_almost_eq(b.health.current, 400.0)

# ------------------------------------------------------------- degenerados

func test_projetil_sem_direcao_nao_sai() -> void:
	# Mira sobre os próprios pés. Cair num `Vector3.FORWARD` padrão mandaria o
	# tiro para o norte do mundo, que é pior do que não sair.
	var caster := _unit()
	var conjunto := ProjectileSet.new()
	var ability := _tiro()
	var lancado: ProjectileSet.Projectile = conjunto.launch(
		ability, ability.single_pulse(), AbilityCast.on_self(caster),
		Vector3.ZERO, Vector3.ZERO
	)
	assert_null(lancado)
	assert_eq(conjunto.count(), 0)

func test_nada_voando_nao_custa_nada() -> void:
	var book := AbilityBook.new()
	assert_true(book.projectiles.is_empty())
	assert_eq(AbilityEngine.advance_projectiles(book, TIQUE, []).size(), 0)

func test_alvo_morto_no_meio_do_voo_nao_e_atingido() -> void:
	var caster := _unit()
	var alvo := _unit(Vector3(0, 0, -8), 1)
	var book := AbilityBook.new()
	_cast(book, _tiro(12.0, 6.0, 1.0), caster, [alvo])

	for _passo: int in 20:
		_tique(book, [alvo])
	alvo.health.current = 0.0

	_voar(book, [alvo])
	assert_almost_eq(alvo.health.current, 0.0, "bateu em cadáver")
