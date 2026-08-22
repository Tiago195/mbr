extends TestCase

## A forma DESENHADA tem que ser a forma que ACERTA.
##
## Cone e trapézio eram desenhados como faixa retangular: um golpe que pega 90°
## à frente aparecia como uma linha fina, e o jogador aprendia a mirar num
## formato que não era o do golpe. Foram corrigidos — e a correção passou verde
## em toda a suíte e na sonda de cena mesmo depois de `cone()` ser mutado para
## devolver exatamente o que `line()` devolvia. Cobertura zero.
##
## Estes testes fecham isso sem cena: a malha é matemática pura sobre
## `PackedVector3Array`, e dá para conferi-la contra `AbilityShape`, que é quem
## decide o acerto.
##
## As malhas nascem ao longo do **-Z**, porque é para lá que `look_at` aponta.

const EPS: float = 0.001

func _vertices(mesh: ArrayMesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array

func _unit(position: Vector3 = Vector3.ZERO, team: int = 0) -> Unit:
	var stats := Stats.new()
	stats.set_bases({Stat.Id.MAX_HEALTH: 100.0})
	var unit := Unit.new(stats, team)
	unit.position = position
	return unit

## Ângulo, em graus, entre um ponto e o -Z (a frente da forma).
func _abertura(ponto: Vector3) -> float:
	var plano := Vector3(ponto.x, 0.0, ponto.z)
	if plano.length_squared() <= 0.000001:
		return 0.0
	return rad_to_deg(plano.normalized().angle_to(Vector3.FORWARD))

## Quem `AbilityShape` acerta com esta forma, mirando para o -Z a partir da
## origem. É o lado "acerta" da comparação.
func _acerta(pulse: AbilityPulse, alvo: Vector3) -> bool:
	var caster: Unit = _unit()
	var unit: Unit = _unit(alvo, 1)
	var cast: AbilityCast = AbilityCast.toward(caster, Vector3.FORWARD)
	return not AbilityShape.resolve(pulse, cast, [unit], Vector3.ZERO).is_empty()

func _cone(length: float, angle: float) -> AbilityPulse:
	var pulse := AbilityPulse.new()
	pulse.form = AbilityPulse.Form.CONE
	pulse.length = length
	pulse.cone_angle = angle
	pulse.effects = [DamageEffect.new()]
	return pulse

# ---------------------------------------------------------------- cone

func test_a_cunha_nao_passa_do_alcance_do_cone() -> void:
	var vertices: PackedVector3Array = _vertices(
		AbilityTelegraph.wedge_mesh(6.0, 90.0)
	)
	assert_true(vertices.size() >= 9, "malha vazia: %d vértices" % vertices.size())
	var maior: float = 0.0
	for v: Vector3 in vertices:
		maior = maxf(maior, v.length())
	assert_almost_eq(maior, 6.0, "a cunha desenhada não chega ao alcance do cone")

func test_a_cunha_tem_a_abertura_do_cone() -> void:
	var vertices: PackedVector3Array = _vertices(
		AbilityTelegraph.wedge_mesh(5.0, 80.0)
	)
	var maior: float = 0.0
	for v: Vector3 in vertices:
		if v.length() > EPS:
			maior = maxf(maior, _abertura(v))
	# A borda da cunha fica na metade da abertura, para cada lado.
	assert_almost_eq(maior, 40.0, "abertura desenhada em desacordo com cone_angle")

func test_a_cunha_e_desenhada_dos_dois_lados_da_mira() -> void:
	# Uma cunha só de um lado teria a mesma abertura máxima e estaria errada.
	var vertices: PackedVector3Array = _vertices(
		AbilityTelegraph.wedge_mesh(5.0, 80.0)
	)
	var esquerda: bool = false
	var direita: bool = false
	for v: Vector3 in vertices:
		if v.x < -EPS:
			esquerda = true
		elif v.x > EPS:
			direita = true
	assert_true(esquerda and direita, "a cunha saiu só de um lado da mira")

func test_o_que_a_cunha_cobre_e_o_que_o_cone_acerta() -> void:
	# A conferência que importa: mesmo alcance, mesma abertura, mesmo veredito.
	var pulse: AbilityPulse = _cone(6.0, 90.0)
	# Dentro: à frente, e na borda angular por dentro.
	assert_true(_acerta(pulse, Vector3(0, 0, -3)), "não acerta bem na frente")
	assert_true(
		_acerta(pulse, Vector3(-1.4, 0, -1.6)), "não acerta perto da borda de 45°"
	)
	# Fora: além do alcance, e além da abertura.
	assert_false(_acerta(pulse, Vector3(0, 0, -7)), "acertou além do alcance")
	assert_false(_acerta(pulse, Vector3(-3.0, 0, -1.0)), "acertou fora da abertura")

	# E a malha concorda com os dois vereditos.
	var vertices: PackedVector3Array = _vertices(
		AbilityTelegraph.wedge_mesh(pulse.length, pulse.cone_angle)
	)
	var maior_raio: float = 0.0
	var maior_abertura: float = 0.0
	for v: Vector3 in vertices:
		maior_raio = maxf(maior_raio, v.length())
		if v.length() > EPS:
			maior_abertura = maxf(maior_abertura, _abertura(v))
	assert_almost_eq(maior_raio, pulse.length)
	assert_almost_eq(maior_abertura, pulse.cone_angle * 0.5)

# ---------------------------------------------------------------- trapézio

func test_o_trapezio_desenhado_tem_as_quatro_medidas() -> void:
	var vertices: PackedVector3Array = _vertices(
		AbilityTelegraph.trapezoid_mesh(2.0, 1.0, 8.0, 4.0)
	)
	var perto_z: float = 0.0
	var longe_z: float = 0.0
	var perto_x: float = 0.0
	var longe_x: float = 0.0
	for v: Vector3 in vertices:
		if absf(v.z + 2.0) < EPS:
			perto_z = v.z
			perto_x = maxf(perto_x, absf(v.x))
		elif absf(v.z + 8.0) < EPS:
			longe_z = v.z
			longe_x = maxf(longe_x, absf(v.x))
	assert_almost_eq(perto_z, -2.0, "a borda de perto não está em near_distance")
	assert_almost_eq(longe_z, -8.0, "a borda de longe não está em length")
	assert_almost_eq(perto_x, 0.5, "near_width errada")
	assert_almost_eq(longe_x, 2.0, "far_width errada")

func test_o_trapezio_desenhado_alarga_como_o_que_acerta() -> void:
	var pulse := AbilityPulse.new()
	pulse.form = AbilityPulse.Form.TRAPEZOID
	pulse.near_distance = 2.0
	pulse.near_width = 1.0
	pulse.length = 8.0
	pulse.far_width = 4.0
	pulse.effects = [DamageEffect.new()]

	# O buraco colado nos pés é o que distingue trapézio de cone.
	assert_false(_acerta(pulse, Vector3(0, 0, -1)), "acertou antes de near_distance")
	assert_true(_acerta(pulse, Vector3(0.4, 0, -2.1)), "não acertou dentro do perto")
	assert_false(_acerta(pulse, Vector3(1.5, 0, -2.1)), "acertou fora da largura de perto")
	assert_true(_acerta(pulse, Vector3(1.8, 0, -7.9)), "não acertou dentro do longe")

	var vertices: PackedVector3Array = _vertices(
		AbilityTelegraph.trapezoid_mesh(
			pulse.near_distance, pulse.near_width, pulse.length, pulse.far_width
		)
	)
	var largura_no_longe: float = 0.0
	var largura_no_perto: float = 0.0
	for v: Vector3 in vertices:
		if absf(v.z + pulse.length) < EPS:
			largura_no_longe = maxf(largura_no_longe, absf(v.x) * 2.0)
		elif absf(v.z + pulse.near_distance) < EPS:
			largura_no_perto = maxf(largura_no_perto, absf(v.x) * 2.0)
	assert_almost_eq(largura_no_perto, pulse.near_width)
	assert_almost_eq(largura_no_longe, pulse.far_width)

# ---------------------------------------------------- raio do projétil

## `AbilityTelegraph.sphere_radius` é fonte ÚNICA: o desenho a usa e a sonda de
## cena a usa para montar a expectativa. Isso evita as duas cópias divergirem —
## e, em troca, torna a função invisível para a sonda: mudá-la move os dois
## lados juntos e a comparação não vê nada. Uma revisão adversarial mediu
## exatamente isso (raio fixo em 1,5: sonda verde).
##
## Então ela é conferida aqui, onde é matemática pura. A regra que importa está
## no comentário de `follow()`: a esfera tem que ter o tamanho da COLISÃO —
## menor faz o jogador achar que errou quando acertou, maior o contrário.

func _com_largura(largura: float) -> AbilityPulse:
	var pulse := AbilityPulse.new()
	pulse.form = AbilityPulse.Form.PROJECTILE
	pulse.width = largura
	return pulse

func test_a_esfera_tem_o_tamanho_da_colisao() -> void:
	# Meia largura: é o raio com que o projétil realmente acerta.
	assert_almost_eq(AbilityTelegraph.sphere_radius(_com_largura(1.0)), 0.5)
	assert_almost_eq(AbilityTelegraph.sphere_radius(_com_largura(2.4)), 1.2)

func test_a_esfera_acompanha_a_largura_do_projetil() -> void:
	# Um raio constante passaria nos dois testes de valor se eles fossem
	# escolhidos com azar; o que prova acompanhamento é a ordem.
	var estreito: float = AbilityTelegraph.sphere_radius(_com_largura(0.6))
	var largo: float = AbilityTelegraph.sphere_radius(_com_largura(2.0))
	assert_true(
		largo > estreito,
		"projétil mais largo tem que desenhar esfera maior: %.2f vs %.2f"
			% [largo, estreito]
	)

func test_a_esfera_tem_piso_e_teto() -> void:
	# Sem piso, um projétil de largura 0,1 vira um ponto invisível; sem teto,
	# um de largura 8 vira uma bola que tapa a tela.
	assert_almost_eq(AbilityTelegraph.sphere_radius(_com_largura(0.01)), 0.15)
	assert_almost_eq(AbilityTelegraph.sphere_radius(_com_largura(20.0)), 1.5)

# ------------------------------------------- marca de chão é MARCA, não bloco

## As fábricas de malha são fonte única: o desenho as usa e
## `tools/sondar_campeoes.gd` as usa para montar a expectativa. Isso impede as
## duas divergirem — e, em troca, torna cada fábrica invisível para a sonda,
## porque mutá-la move os dois lados juntos. A contrapartida mora aqui.
##
## A regra que importa é uma: **marca de chão é achatada**. Uma faixa de 8
## metros de altura vira um muro opaco no meio da luta, e um disco de 40 vira
## um tubo. As duas passaram verdes numa revisão adversarial.

func test_toda_marca_de_chao_e_achatada() -> void:
	var malhas: Array[Mesh] = [
		AbilityTelegraph.disc_mesh(3.0),
		AbilityTelegraph.strip_mesh(1.5, 8.0),
		AbilityTelegraph.wedge_mesh(6.0, 90.0),
		AbilityTelegraph.trapezoid_mesh(2.0, 1.0, 8.0, 4.0),
	]
	for mesh: Mesh in malhas:
		var altura: float = mesh.get_aabb().size.y
		assert_true(
			altura <= 0.1,
			"%s tem %.2fm de altura — é bloco, não marca" % [
				mesh.get_class(), altura
			]
		)

func test_o_disco_tem_o_diametro_do_raio_pedido() -> void:
	var caixa: Vector3 = AbilityTelegraph.disc_mesh(2.5).get_aabb().size
	assert_almost_eq(caixa.x, 5.0, "largura do disco")
	assert_almost_eq(caixa.z, 5.0, "profundidade do disco")

func test_a_faixa_tem_a_largura_e_o_comprimento_pedidos() -> void:
	var caixa: Vector3 = AbilityTelegraph.strip_mesh(1.5, 8.0).get_aabb().size
	assert_almost_eq(caixa.x, 1.5, "largura da faixa")
	assert_almost_eq(caixa.z, 8.0, "comprimento da faixa")

func test_a_esfera_e_esfera_e_nao_ovo() -> void:
	# `SphereMesh.height` diferente do dobro do raio dá um ovo, e o tamanho na
	# tela deixa de ser o da colisão em uma das direções.
	#
	# A caixa não bate no diâmetro exato — a malha é facetada, e os vértices
	# ficam por dentro da esfera ideal (1,398 para diâmetro 1,4). Por isso a
	# afirmação é de PROPORÇÃO: comparar com o número redondo reprovaria
	# geometria correta.
	var caixa: Vector3 = AbilityTelegraph.sphere_mesh(0.7).get_aabb().size
	assert_true(
		absf(caixa.x - caixa.z) < 0.01,
		"largura e profundidade diferentes: %.3f vs %.3f" % [caixa.x, caixa.z]
	)
	assert_true(
		absf(caixa.y - caixa.x) < 0.02,
		"altura fora do diâmetro: %.3f contra %.3f de largura" % [
			caixa.y, caixa.x
		]
	)
	assert_true(
		absf(caixa.x - 1.4) < 0.02,
		"raio 0,7 devia dar cerca de 1,4 de largura, deu %.3f" % caixa.x
	)

# --------------------------------- as constantes de apresentação têm regra

## `ALTURA_DO_CHAO`, `ESPESSURA` e `VIDA_PADRAO` são fonte única: o desenho as
## usa e a sonda de cena as usa para montar a expectativa. Mutá-las move os
## dois lados juntos, então a sonda é cega para elas por construção — e as três
## carregam uma regra de projeto que, quebrada, apaga a marca da tela.

func test_a_marca_fica_acima_do_chao_mas_rente_a_ele() -> void:
	# Zero devolve o z-fighting que a constante existe para evitar: a marca
	# pisca em faixas. Alto demais e ela deixa de ler como marca no chão.
	assert_true(
		AbilityTelegraph.ALTURA_DO_CHAO > 0.0,
		"marca coplanar com o chão volta a piscar em faixas"
	)
	assert_true(
		AbilityTelegraph.ALTURA_DO_CHAO <= 0.1,
		"%.2fm acima do chão deixa de ler como marca de chão"
			% AbilityTelegraph.ALTURA_DO_CHAO
	)

func test_a_marca_fica_em_alguma_camada_de_render() -> void:
	# `layers = 0` tira a malha de toda câmera: ela existe na árvore, com
	# posição e tamanho certos, e não aparece. É invisibilidade que nenhuma
	# conferência de geometria pega, porque a geometria está correta.
	assert_true(
		AbilityTelegraph.CAMADAS_DE_RENDER != 0,
		"marca fora de toda camada de render não é desenhada por câmera nenhuma"
	)

func test_a_marca_fica_na_tela_tempo_de_ser_vista() -> void:
	# 0,2s são doze quadros a 60 Hz. Abaixo disso a marca vira um piscar, que é
	# indistinguível de marca nenhuma — o mesmo desfecho do defeito que esta
	# lacuna corrigiu.
	assert_true(
		AbilityTelegraph.VIDA_PADRAO >= 0.2,
		"marca de %.3fs não dá para ver" % AbilityTelegraph.VIDA_PADRAO
	)

# ------------------------------------------- onde esta suíte NÃO alcança

## Que `cone()` de fato USE `wedge_mesh` — e não devolva a faixa de `line()` —
## não dá para conferir aqui: as fábricas chamam `global_position` e `look_at`,
## que exigem o nó dentro da árvore, e `Engine.get_main_loop()` é nulo enquanto
## `run_tests.gd` roda (a suíte inteira acontece dentro do `_init` dele, antes
## de o laço principal existir).
##
## Essa conferência mora em `tools/sondar_campeoes.gd`, que monta a cena de
## verdade e compara a MALHA de cada marca com a forma do pulso que a gerou.
## Está registrado aqui para a divisão ser explícita: uma suíte que se cala
## sobre o que não cobre é indistinguível de uma que cobre tudo.
