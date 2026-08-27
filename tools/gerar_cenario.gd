extends SceneTree

## Gera `res://scenes/cenario_de_treino.tscn` — o greybox de treino — e depois
## PROVA que o artefato salvo carrega e cumpre o que promete.
##
## Por que um gerador e não um `.tscn` escrito à mão: `Transform3D` é
## serializado por LINHAS da matriz de base, e escrever transposto não dá erro
## nenhum — já custou uma sessão inteira (ver "Ao escrever .tscn à mão" no
## `CLAUDE.md`). Aqui só existem `position` e `rotation_degrees`; quem compõe
## as matrizes é a engine, e o `.tscn` sai do `PackedScene.pack()`.
##
## O layout é o embrião do NOSSO mapa em escala 0,4 — o do Royal Crown media
## 300×300 m e este mede 120×120. O vocabulário de POIs vem das tabelas do
## original (AreaClassification/MapIcon): vila com baús e estátua-loja,
## floresta, mina de pedras de mana, arbustos que escondem, rio com ponte,
## portais e forja. Ver a decisão 27 em `docs/02-decisoes-tecnicas.md`.
##
## Determinismo de propósito: TODA posição é literal neste arquivo. Nada de
## aleatório em runtime — a floresta "irregular" é irregular por autoria.
##
## A FILEIRA DE TREINO NÃO MORA AQUI: os 3 bonecos fixos e o móvel são da
## `main.tscn`, e o espaço em torno de (-16, 0, 10) fica LIVRE de propósito —
## o conferidor reprova se algo estático invadir esse retângulo.
##
## Rodar (gera, salva e confere):
##     godot --headless --path . --script res://tools/gerar_cenario.gd
## Só conferir o artefato commitado, sem regerar:
##     godot --headless --path . --script res://tools/gerar_cenario.gd --conferir

const DESTINO: String = "res://scenes/cenario_de_treino.tscn"

## Lado do mapa em metros. O do original media 300; escala 0,4.
const LADO: float = 120.0

## Centro da vila, da floresta (NE = +X, -Z), da mina (SE) e dos arbustos (SW).
const VILA: Vector3 = Vector3(0, 0, -35)
const FLORESTA: Vector3 = Vector3(35, 0, -35)
const MINA: Vector3 = Vector3(35, 0, 35)
const ARBUSTOS: Vector3 = Vector3(-35, 0, 35)

## Posições FIXAS e irregulares (offsets XZ do centro de cada região).
## Espaçamento ~6 m na floresta; nada disto é sorteado.
const OFFSETS_ARVORES: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(6.5, 1.2), Vector2(-5.8, 2.4),
	Vector2(3.1, -6.2), Vector2(-2.7, -7.4), Vector2(9.4, -4.8),
	Vector2(-9.1, -3.5), Vector2(5.9, 7.8), Vector2(-6.3, 8.5),
	Vector2(0.8, 13.1), Vector2(12.2, 3.9), Vector2(-12.6, 1.7),
]
const OFFSETS_PEDRAS: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(3.4, -2.1), Vector2(-2.8, 3.0),
	Vector2(-1.5, -5.4), Vector2(-4.4, -2.6), Vector2(1.2, 5.8),
]
const OFFSETS_ROCHAS: Array[Vector2] = [
	Vector2(-7.5, 0.5), Vector2(7.2, -1.4), Vector2(0.4, -7.8), Vector2(-3.9, 7.4),
]
const OFFSETS_MOITAS: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(5.5, 2.3), Vector2(-4.8, -3.6),
	Vector2(2.6, -5.9), Vector2(-2.2, 6.1),
]

## Rio: faixa z ∈ [-5, 0] para x ∈ [-60, -15]; vão da ponte em x = -30 ± 2.
const RIO_X_MIN: float = -60.0
const RIO_X_MAX: float = -15.0
const RIO_Z_MIN: float = -5.0
const RIO_Z_MAX: float = 0.0
const PONTE_X: float = -30.0
const PONTE_LARGURA: float = 4.0

## A casa: 8×4×8, paredes de 0,5, porta de 2 m (vão de 3 m de altura + verga).
const CASA_LADO: float = 8.0
const CASA_ALTURA: float = 4.0
const PAREDE: float = 0.5
const PORTA_LARGURA: float = 2.0
const PORTA_ALTURA: float = 3.0

## Anel de spawn: raio 55, um marcador a cada 45°. A fase de 22,5° desvia os
## marcadores dos eixos — em fase 0 o marcador de 180° caía na margem do rio.
const SPAWN_RAIO: float = 55.0
const SPAWN_FASE_GRAUS: float = 22.5

var _materiais: Dictionary = {}

func _init() -> void:
	process_frame.connect(_rodar, CONNECT_ONE_SHOT)

func _rodar() -> void:
	# `Variant`, e o `quit()` fora da função que pode estourar: erro em tempo
	# de execução aborta só a função onde ocorreu, e um `SceneTree` headless
	# sem `quit` roda para sempre (mesmo padrão de `sondar_kaykit.gd`).
	var falhas: Variant = await _executar()
	print("")
	if not falhas is Array:
		print("  [FALHOU] o gerador/conferidor estourou (veja SCRIPT ERROR acima)")
		quit(1)
		return
	var lista: Array = falhas as Array
	if lista.is_empty():
		print("  [ok] cenário de treino gerado e conferido")
		quit(0)
		return
	for falha: String in lista:
		print("  [FALHOU] %s" % falha)
	quit(1)

func _executar() -> Array[String]:
	var so_conferir: bool = OS.get_cmdline_args().has("--conferir")
	if not so_conferir:
		var falhas_geracao: Array[String] = _gerar_e_salvar()
		if not falhas_geracao.is_empty():
			return falhas_geracao
	return await _conferir()

# ---------------------------------------------------------------------------
# Geração
# ---------------------------------------------------------------------------

func _gerar_e_salvar() -> Array[String]:
	var raiz: Node3D = _montar()
	_adotar(raiz, raiz)
	var pacote: PackedScene = PackedScene.new()
	if pacote.pack(raiz) != OK:
		raiz.free()
		return ["PackedScene.pack() recusou a árvore montada"] as Array[String]
	var erro: Error = ResourceSaver.save(pacote, DESTINO)
	raiz.free()
	if erro != OK:
		return ["ResourceSaver.save() falhou com erro %d" % erro] as Array[String]
	print("  cena salva em %s" % DESTINO)
	return [] as Array[String]

func _montar() -> Node3D:
	var raiz: Node3D = Node3D.new()
	raiz.name = "CenarioDeTreino"
	# Sem câmera e sem luz de propósito: isto é sub-cena; quem ilumina e
	# enquadra é a cena que a instanciar.

	_montar_chao_e_muro(raiz)
	_montar_vila(raiz)
	_montar_floresta(raiz)
	_montar_mina(raiz)
	_montar_arbustos(raiz)
	_montar_rio(raiz)
	_montar_portais(raiz)
	_montar_marcadores(raiz)
	return raiz

func _montar_chao_e_muro(raiz: Node3D) -> void:
	var chao: StaticBody3D = StaticBody3D.new()
	chao.name = "Chao"
	raiz.add_child(chao)
	var malha_chao: MeshInstance3D = MeshInstance3D.new()
	malha_chao.name = "Malha"
	var plano: PlaneMesh = PlaneMesh.new()
	plano.size = Vector2(LADO, LADO)
	malha_chao.mesh = plano
	malha_chao.material_override = _material("chao", Color(0.45, 0.5, 0.4))
	chao.add_child(malha_chao)
	var forma_chao: CollisionShape3D = CollisionShape3D.new()
	forma_chao.name = "Forma"
	forma_chao.shape = WorldBoundaryShape3D.new()
	chao.add_child(forma_chao)

	var muro: Node3D = Node3D.new()
	muro.name = "Muro"
	raiz.add_child(muro)
	var meia: float = LADO / 2.0
	var comprido: Vector3 = Vector3(LADO + 1.0, 1.5, 1.0)
	var de_lado: Vector3 = Vector3(1.0, 1.5, LADO + 1.0)
	_caixa_estatica(muro, "MuroNorte", comprido, Vector3(0, 0.75, -meia), "muro")
	_caixa_estatica(muro, "MuroSul", comprido, Vector3(0, 0.75, meia), "muro")
	_caixa_estatica(muro, "MuroLeste", de_lado, Vector3(meia, 0.75, 0), "muro")
	_caixa_estatica(muro, "MuroOeste", de_lado, Vector3(-meia, 0.75, 0), "muro")

func _montar_vila(raiz: Node3D) -> void:
	var vila: Node3D = Node3D.new()
	vila.name = "Vila"
	raiz.add_child(vila)

	# As portas olham para o eixo da praça: casa a oeste gira +90° NÃO —
	# quem decide é a engine. A casa é autorada com a porta na frente local
	# (-Z); o giro leva essa frente para ±X, na direção da praça.
	_casa(vila, "Casa1", Vector3(-12, 0, -28), -90.0)
	_casa(vila, "Casa2", Vector3(12, 0, -28), 90.0)
	_casa(vila, "Casa3", Vector3(-12, 0, -42), -90.0)
	_casa(vila, "Casa4", Vector3(12, 0, -42), 90.0)

	var pedestal: StaticBody3D = _caixa_estatica(
		vila, "Pedestal", Vector3(2, 0.5, 2), VILA + Vector3(0, 0.25, 0), "pedestal"
	)
	assert(pedestal != null)

	# A estátua-loja: cápsula sobre o pedestal, como o vendedor de vila do
	# original (MapIcon `store_statue`).
	var estatua: StaticBody3D = StaticBody3D.new()
	estatua.name = "EstatuaLoja"
	estatua.position = VILA + Vector3(0, 1.75, 0)
	vila.add_child(estatua)
	var malha_estatua: MeshInstance3D = MeshInstance3D.new()
	malha_estatua.name = "Malha"
	var capsula: CapsuleMesh = CapsuleMesh.new()
	capsula.radius = 0.5
	capsula.height = 2.5
	malha_estatua.mesh = capsula
	malha_estatua.material_override = _material("estatua", Color(0.85, 0.7, 0.3))
	estatua.add_child(malha_estatua)
	var forma_estatua: CollisionShape3D = CollisionShape3D.new()
	forma_estatua.name = "Forma"
	var forma_capsula: CapsuleShape3D = CapsuleShape3D.new()
	forma_capsula.radius = 0.5
	forma_capsula.height = 2.5
	forma_estatua.shape = forma_capsula
	estatua.add_child(forma_estatua)

	# A forja, com chaminé só de malha em cima do corpo.
	var forja: StaticBody3D = StaticBody3D.new()
	forja.name = "Forja"
	forja.position = Vector3(0, 0, -48)
	vila.add_child(forja)
	_caixa_com_colisao(forja, "Corpo", Vector3(3, 2, 3), Vector3(0, 1, 0), "forja")
	var chamine: MeshInstance3D = MeshInstance3D.new()
	chamine.name = "Chamine"
	var tubo: CylinderMesh = CylinderMesh.new()
	tubo.top_radius = 0.3
	tubo.bottom_radius = 0.3
	tubo.height = 2.0
	chamine.mesh = tubo
	chamine.material_override = _material("forja", Color(0.3, 0.28, 0.3))
	chamine.position = Vector3(1, 3, -1)
	forja.add_child(chamine)

	# Dois baús na praça — SÓ malha, sem corpo e sem sistema: o loot vem
	# depois, e um baú que colide sem abrir só atrapalharia o teste.
	_bau(vila, "Bau1", Vector3(2.5, 0.35, -33.5))
	_bau(vila, "Bau2", Vector3(-2.5, 0.35, -36.5))

## Casa oca 8×4×8: fundo, duas laterais, frente em dois panos com porta de
## 2 m (vão de 3 m) e verga por cima. Sem teto de propósito: a câmera é
## isométrica e um teto esconderia o interior.
func _casa(pai: Node3D, nome: String, pos: Vector3, giro_graus: float) -> void:
	var casa: StaticBody3D = StaticBody3D.new()
	casa.name = nome
	casa.position = pos
	casa.rotation_degrees = Vector3(0, giro_graus, 0)
	pai.add_child(casa)
	var meia: float = CASA_LADO / 2.0 - PAREDE / 2.0  # 3.75
	var meio_y: float = CASA_ALTURA / 2.0
	_caixa_com_colisao(
		casa, "ParedeFundo",
		Vector3(CASA_LADO, CASA_ALTURA, PAREDE), Vector3(0, meio_y, meia), "parede"
	)
	_caixa_com_colisao(
		casa, "ParedeOeste",
		Vector3(PAREDE, CASA_ALTURA, CASA_LADO), Vector3(-meia, meio_y, 0), "parede"
	)
	_caixa_com_colisao(
		casa, "ParedeLeste",
		Vector3(PAREDE, CASA_ALTURA, CASA_LADO), Vector3(meia, meio_y, 0), "parede"
	)
	var pano: float = (CASA_LADO - PORTA_LARGURA) / 2.0  # 3.0
	var centro_pano: float = PORTA_LARGURA / 2.0 + pano / 2.0  # 2.5
	_caixa_com_colisao(
		casa, "FrenteOeste",
		Vector3(pano, CASA_ALTURA, PAREDE), Vector3(-centro_pano, meio_y, -meia), "parede"
	)
	_caixa_com_colisao(
		casa, "FrenteLeste",
		Vector3(pano, CASA_ALTURA, PAREDE), Vector3(centro_pano, meio_y, -meia), "parede"
	)
	var altura_verga: float = CASA_ALTURA - PORTA_ALTURA  # 1.0
	_caixa_com_colisao(
		casa, "Verga",
		Vector3(PORTA_LARGURA, altura_verga, PAREDE),
		Vector3(0, PORTA_ALTURA + altura_verga / 2.0, -meia), "parede"
	)

func _bau(pai: Node3D, nome: String, pos: Vector3) -> void:
	var malha: MeshInstance3D = MeshInstance3D.new()
	malha.name = nome
	var caixa: BoxMesh = BoxMesh.new()
	caixa.size = Vector3(1.0, 0.7, 0.7)
	malha.mesh = caixa
	malha.material_override = _material("bau", Color(0.5, 0.35, 0.2))
	malha.position = pos
	pai.add_child(malha)

func _montar_floresta(raiz: Node3D) -> void:
	var floresta: Node3D = Node3D.new()
	floresta.name = "FlorestaNE"
	floresta.position = FLORESTA
	raiz.add_child(floresta)
	for i: int in OFFSETS_ARVORES.size():
		var offset: Vector2 = OFFSETS_ARVORES[i]
		var arvore: StaticBody3D = StaticBody3D.new()
		arvore.name = "Arvore%d" % (i + 1)
		arvore.position = Vector3(offset.x, 0, offset.y)
		floresta.add_child(arvore)

		var tronco: MeshInstance3D = MeshInstance3D.new()
		tronco.name = "Tronco"
		var cilindro: CylinderMesh = CylinderMesh.new()
		cilindro.top_radius = 0.4
		cilindro.bottom_radius = 0.4
		cilindro.height = 2.0
		tronco.mesh = cilindro
		tronco.material_override = _material("tronco", Color(0.4, 0.28, 0.15))
		tronco.position = Vector3(0, 1, 0)
		arvore.add_child(tronco)

		var copa: MeshInstance3D = MeshInstance3D.new()
		copa.name = "Copa"
		var esfera: SphereMesh = SphereMesh.new()
		esfera.radius = 1.8
		esfera.height = 3.6
		copa.mesh = esfera
		copa.material_override = _material("copa", Color(0.2, 0.55, 0.2))
		copa.position = Vector3(0, 3.2, 0)
		arvore.add_child(copa)

		# Colisão só no tronco: a copa fica acima da cabeça e não bloqueia.
		var forma: CollisionShape3D = CollisionShape3D.new()
		forma.name = "Forma"
		var forma_tronco: CylinderShape3D = CylinderShape3D.new()
		forma_tronco.radius = 0.4
		forma_tronco.height = 2.0
		forma.shape = forma_tronco
		forma.position = Vector3(0, 1, 0)
		arvore.add_child(forma)

func _montar_mina(raiz: Node3D) -> void:
	var mina: Node3D = Node3D.new()
	mina.name = "MinaSE"
	mina.position = MINA
	raiz.add_child(mina)
	for i: int in OFFSETS_PEDRAS.size():
		var offset: Vector2 = OFFSETS_PEDRAS[i]
		var pedra: StaticBody3D = StaticBody3D.new()
		pedra.name = "PedraDeMana%d" % (i + 1)
		pedra.position = Vector3(offset.x, 0.4, offset.y)
		mina.add_child(pedra)
		var malha: MeshInstance3D = MeshInstance3D.new()
		malha.name = "Malha"
		var esfera: SphereMesh = SphereMesh.new()
		esfera.radius = 0.8
		esfera.height = 0.8  # achatada: metade da altura natural
		malha.mesh = esfera
		malha.material_override = _material("mana", Color(0.3, 0.8, 0.9))
		pedra.add_child(malha)
		var forma: CollisionShape3D = CollisionShape3D.new()
		forma.name = "Forma"
		var caixa: BoxShape3D = BoxShape3D.new()
		caixa.size = Vector3(1.6, 0.8, 1.6)
		forma.shape = caixa
		pedra.add_child(forma)
	for i: int in OFFSETS_ROCHAS.size():
		var offset: Vector2 = OFFSETS_ROCHAS[i]
		_caixa_estatica(
			mina, "Rocha%d" % (i + 1), Vector3(2, 1.5, 2),
			Vector3(offset.x, 0.75, offset.y), "rocha"
		)

func _montar_arbustos(raiz: Node3D) -> void:
	var regiao: Node3D = Node3D.new()
	regiao.name = "ArbustosSW"
	regiao.position = ARBUSTOS
	raiz.add_child(regiao)
	for i: int in OFFSETS_MOITAS.size():
		var offset: Vector2 = OFFSETS_MOITAS[i]
		var moita: Node3D = Node3D.new()
		moita.name = "Moita%d" % (i + 1)
		moita.position = Vector3(offset.x, 0, offset.y)
		regiao.add_child(moita)
		var malha: MeshInstance3D = MeshInstance3D.new()
		malha.name = "Malha"
		var cilindro: CylinderMesh = CylinderMesh.new()
		cilindro.top_radius = 1.5
		cilindro.bottom_radius = 1.5
		cilindro.height = 1.2
		malha.mesh = cilindro
		malha.material_override = _material_translucido(
			"arbusto", Color(0.2, 0.6, 0.25, 0.45)
		)
		malha.position = Vector3(0, 0.6, 0)
		moita.add_child(malha)
		# Area3D: NÃO colide (área nunca bloqueia movimento) — a forma existe
		# para o futuro sistema de esconder detectar quem entrou. Nome claro
		# de propósito: quem for ligar o sistema procura por "AreaDeArbusto".
		var area: Area3D = Area3D.new()
		area.name = "AreaDeArbusto"
		moita.add_child(area)
		var forma: CollisionShape3D = CollisionShape3D.new()
		forma.name = "Forma"
		var forma_cilindro: CylinderShape3D = CylinderShape3D.new()
		forma_cilindro.radius = 1.5
		forma_cilindro.height = 1.2
		forma.shape = forma_cilindro
		forma.position = Vector3(0, 0.6, 0)
		area.add_child(forma)

func _montar_rio(raiz: Node3D) -> void:
	var rio: Node3D = Node3D.new()
	rio.name = "Rio"
	raiz.add_child(rio)

	var centro_x: float = (RIO_X_MIN + RIO_X_MAX) / 2.0
	var comprimento: float = RIO_X_MAX - RIO_X_MIN
	var centro_z: float = (RIO_Z_MIN + RIO_Z_MAX) / 2.0
	var largura: float = RIO_Z_MAX - RIO_Z_MIN

	# Água: só malha, fininha, logo acima do chão. Quem impede a travessia
	# são as MARGENS; a lâmina d'água é legibilidade, não física.
	var agua: MeshInstance3D = MeshInstance3D.new()
	agua.name = "Agua"
	var caixa_agua: BoxMesh = BoxMesh.new()
	caixa_agua.size = Vector3(comprimento, 0.1, largura)
	agua.mesh = caixa_agua
	agua.material_override = _material("agua", Color(0.25, 0.45, 0.85))
	agua.position = Vector3(centro_x, 0.05, centro_z)
	rio.add_child(agua)

	# Margens intransponíveis nas duas bordas, com o vão da ponte em x = -30.
	var vao_min: float = PONTE_X - PONTE_LARGURA / 2.0
	var vao_max: float = PONTE_X + PONTE_LARGURA / 2.0
	var trecho_oeste: float = vao_min - RIO_X_MIN
	var trecho_leste: float = RIO_X_MAX - vao_max
	var centro_oeste: float = RIO_X_MIN + trecho_oeste / 2.0
	var centro_leste: float = vao_max + trecho_leste / 2.0
	for lado: Array in [["Norte", RIO_Z_MIN - 0.15], ["Sul", RIO_Z_MAX + 0.15]]:
		var sufixo: String = lado[0]
		var z: float = lado[1]
		_caixa_estatica(
			rio, "Margem%sOeste" % sufixo, Vector3(trecho_oeste, 1.0, 0.3),
			Vector3(centro_oeste, 0.5, z), "margem"
		)
		_caixa_estatica(
			rio, "Margem%sLeste" % sufixo, Vector3(trecho_leste, 1.0, 0.3),
			Vector3(centro_leste, 0.5, z), "margem"
		)
	# O rio termina em x = -15 dentro do mapa: sem esta tampa dava para
	# entrar na água contornando a ponta. Em x = -60 quem tampa é o MuroOeste.
	_caixa_estatica(
		rio, "MargemTampaLeste", Vector3(0.3, 1.0, largura + 0.6),
		Vector3(RIO_X_MAX + 0.15, 0.5, centro_z), "margem"
	)

	# A ponte: só malha, fininha, sobre o vão. Transitável porque o VÃO nas
	# margens é transitável — o chão embaixo é quem carrega o passo; um
	# tablado com colisão viraria um degrau que CharacterBody3D não sobe.
	var ponte: MeshInstance3D = MeshInstance3D.new()
	ponte.name = "Ponte"
	var tablado: BoxMesh = BoxMesh.new()
	tablado.size = Vector3(PONTE_LARGURA, 0.08, largura + 1.0)
	ponte.mesh = tablado
	ponte.material_override = _material("ponte", Color(0.55, 0.4, 0.25))
	ponte.position = Vector3(PONTE_X, 0.04, centro_z)
	rio.add_child(ponte)

func _montar_portais(raiz: Node3D) -> void:
	var portais: Node3D = Node3D.new()
	portais.name = "Portais"
	raiz.add_child(portais)
	var posicoes: Array[Vector3] = [Vector3(-50, 0, -50), Vector3(50, 0, 50)]
	for i: int in posicoes.size():
		var portal: Node3D = Node3D.new()
		portal.name = "Portal%d" % (i + 1)
		portal.position = posicoes[i]
		portais.add_child(portal)
		var anel: MeshInstance3D = MeshInstance3D.new()
		anel.name = "Anel"
		var toro: TorusMesh = TorusMesh.new()
		toro.inner_radius = 1.25
		toro.outer_radius = 1.75  # anel de raio 1,5 com tubo de 0,25
		anel.mesh = toro
		anel.material_override = _material("portal", Color(0.6, 0.3, 0.8))
		anel.rotation_degrees = Vector3(90, 0, 0)  # de deitado para em pé
		anel.position = Vector3(0, 1.75, 0)
		portal.add_child(anel)
		# Nome claro pela mesma razão do arbusto: o teleporte liga depois.
		var area: Area3D = Area3D.new()
		area.name = "AreaDePortal"
		portal.add_child(area)
		var forma: CollisionShape3D = CollisionShape3D.new()
		forma.name = "Forma"
		var caixa: BoxShape3D = BoxShape3D.new()
		caixa.size = Vector3(3, 3.5, 1)
		forma.shape = caixa
		forma.position = Vector3(0, 1.75, 0)
		area.add_child(forma)

func _montar_marcadores(raiz: Node3D) -> void:
	var marcadores: Node3D = Node3D.new()
	marcadores.name = "Marcadores"
	raiz.add_child(marcadores)
	for i: int in 8:
		var angulo: float = deg_to_rad(SPAWN_FASE_GRAUS + 45.0 * float(i))
		var marcador: Marker3D = Marker3D.new()
		marcador.name = "MarcadorDeSpawn%d" % (i + 1)
		marcador.position = Vector3(
			SPAWN_RAIO * cos(angulo), 0, SPAWN_RAIO * sin(angulo)
		)
		marcadores.add_child(marcador)
	# Triângulo equilátero de lado 5 centrado em (35, 0, 0): o raio do
	# círculo circunscrito é lado / raiz de 3.
	var raio_acampamento: float = 5.0 / sqrt(3.0)
	for i: int in 3:
		var angulo: float = deg_to_rad(90.0 + 120.0 * float(i))
		var marcador: Marker3D = Marker3D.new()
		marcador.name = "MarcadorDeAcampamento%d" % (i + 1)
		marcador.position = Vector3(35, 0, 0) + Vector3(
			raio_acampamento * cos(angulo), 0, raio_acampamento * sin(angulo)
		)
		marcadores.add_child(marcador)
	var suprimento: Marker3D = Marker3D.new()
	suprimento.name = "MarcadorDeSuprimento"
	suprimento.position = Vector3(0, 0, 20)
	marcadores.add_child(suprimento)

# --- Tijolos ---------------------------------------------------------------

## StaticBody3D com uma caixa de malha e a forma de colisão idêntica.
func _caixa_estatica(
	pai: Node3D, nome: String, tamanho: Vector3, pos: Vector3, material: String
) -> StaticBody3D:
	var corpo: StaticBody3D = StaticBody3D.new()
	corpo.name = nome
	corpo.position = pos
	pai.add_child(corpo)
	_caixa_com_colisao(corpo, "Malha", tamanho, Vector3.ZERO, material)
	return corpo

## Par malha + forma de caixa, filho de um corpo que já existe.
func _caixa_com_colisao(
	corpo: Node3D, nome: String, tamanho: Vector3, pos: Vector3, material: String
) -> void:
	var malha: MeshInstance3D = MeshInstance3D.new()
	malha.name = nome
	var caixa: BoxMesh = BoxMesh.new()
	caixa.size = tamanho
	malha.mesh = caixa
	malha.material_override = _material(material, _COR_PADRAO.get(material, Color.MAGENTA))
	malha.position = pos
	corpo.add_child(malha)
	var forma: CollisionShape3D = CollisionShape3D.new()
	forma.name = nome + "Forma"
	var forma_caixa: BoxShape3D = BoxShape3D.new()
	forma_caixa.size = tamanho
	forma.shape = forma_caixa
	forma.position = pos
	corpo.add_child(forma)

## Cor chapada por CLASSE de coisa — feio de propósito, mas legível: parede
## não confunde com árvore, minério não confunde com arbusto.
const _COR_PADRAO: Dictionary = {
	"muro": Color(0.35, 0.35, 0.38),
	"parede": Color(0.72, 0.62, 0.5),
	"pedestal": Color(0.6, 0.6, 0.62),
	"forja": Color(0.3, 0.28, 0.3),
	"rocha": Color(0.5, 0.5, 0.5),
	"margem": Color(0.45, 0.45, 0.5),
}

func _material(nome: String, cor: Color) -> StandardMaterial3D:
	if not _materiais.has(nome):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = cor
		_materiais[nome] = material
	return _materiais[nome]

func _material_translucido(nome: String, cor: Color) -> StandardMaterial3D:
	if not _materiais.has(nome):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = cor
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_materiais[nome] = material
	return _materiais[nome]

func _adotar(no: Node, raiz: Node) -> void:
	for filho: Node in no.get_children():
		filho.owner = raiz
		_adotar(filho, raiz)

# ---------------------------------------------------------------------------
# Conferência — sobre o ARTEFATO salvo, lido do disco, nunca sobre a árvore
# que acabou de ser montada em memória (foi assim que um `.glb` mutado ficou
# commitado com tudo verde).
# ---------------------------------------------------------------------------

## Contagens esperadas, como LITERAIS separados das constantes de geração:
## se uma árvore sumir da lista de offsets, o gerador e a expectativa não
## podem concordar em silêncio (lição 7: quem junta o dado não decide).
const _ESPERADO_POR_TIPO: Dictionary = {
	"StaticBody3D": 39,
	"Area3D": 7,
	"Marker3D": 12,
	"MeshInstance3D": 83,
	"CollisionShape3D": 66,
}

func _conferir() -> Array[String]:
	var falhas: Array[String] = []

	var pacote: PackedScene = ResourceLoader.load(
		DESTINO, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if pacote == null:
		return ["o artefato %s não carrega do disco" % DESTINO] as Array[String]
	var cena: Node3D = pacote.instantiate() as Node3D
	if cena == null:
		return ["o artefato não instancia como Node3D"] as Array[String]
	root.add_child(cena)
	# Um quadro de física para os corpos entrarem no espaço antes dos raios.
	await physics_frame

	_conferir_contagens(cena, falhas)
	_conferir_colisoes(cena, falhas)
	_conferir_alturas_e_limites(cena, falhas)
	_conferir_area_de_treino_livre(cena, falhas)
	_conferir_marcadores(cena, falhas)

	var raio: RayCast3D = RayCast3D.new()
	root.add_child(raio)
	_conferir_portas(cena, raio, falhas)
	_conferir_ponte(raio, falhas)
	raio.queue_free()

	cena.queue_free()
	return falhas

func _conferir_contagens(cena: Node3D, falhas: Array[String]) -> void:
	var contagem: Dictionary = {}
	var bordas_do_mundo: int = 0
	for no: Node in _todos(cena):
		var tipo: String = no.get_class()
		contagem[tipo] = int(contagem.get(tipo, 0)) + 1
		var forma: CollisionShape3D = no as CollisionShape3D
		if forma != null and forma.shape is WorldBoundaryShape3D:
			bordas_do_mundo += 1
	for tipo: String in _ESPERADO_POR_TIPO:
		var achado: int = int(contagem.get(tipo, 0))
		var esperado: int = int(_ESPERADO_POR_TIPO[tipo])
		print("  %s: %d (esperado %d)" % [tipo, achado, esperado])
		if achado != esperado:
			falhas.append("%d %s onde se esperavam %d" % [achado, tipo, esperado])
	if bordas_do_mundo != 1:
		falhas.append(
			"%d WorldBoundaryShape3D onde se esperava exatamente 1" % bordas_do_mundo
		)

func _conferir_colisoes(cena: Node3D, falhas: Array[String]) -> void:
	for no: Node in _todos(cena):
		var precisa_de_forma: bool = no is StaticBody3D or no is Area3D
		if not precisa_de_forma:
			continue
		var tem_forma: bool = false
		for filho: Node in no.get_children():
			var forma: CollisionShape3D = filho as CollisionShape3D
			if forma != null and forma.shape != null:
				tem_forma = true
		if not tem_forma:
			falhas.append("'%s' (%s) está sem forma de colisão" % [no.name, no.get_class()])
		if no is Area3D and not String(no.name).begins_with("AreaDe"):
			falhas.append(
				"a área '%s' não tem nome claro (esperado prefixo AreaDe)" % no.name
			)

func _conferir_alturas_e_limites(cena: Node3D, falhas: Array[String]) -> void:
	var caixa_total: AABB = AABB()
	var primeira: bool = true
	for no: Node in _todos(cena):
		var malha: MeshInstance3D = no as MeshInstance3D
		if malha == null or malha.mesh == null:
			continue
		# `global_transform * AABB`: o termo que engloba posição, tamanho e
		# rotação de uma vez (lição 10) — e é a engine compondo a matriz.
		var no_mundo: AABB = malha.global_transform * malha.mesh.get_aabb()
		if no_mundo.position.y < -0.05:
			falhas.append(
				"'%s' está enterrado: fundo da malha em y=%.2f"
				% [malha.name, no_mundo.position.y]
			)
		caixa_total = no_mundo if primeira else caixa_total.merge(no_mundo)
		primeira = false
	print("  caixa do cenário: x %.1f..%.1f, z %.1f..%.1f" % [
		caixa_total.position.x, caixa_total.end.x,
		caixa_total.position.z, caixa_total.end.z,
	])
	# 120×120 mais a meia espessura do muro do perímetro.
	var limite: float = LADO / 2.0 + 0.6
	if caixa_total.position.x < -limite or caixa_total.end.x > limite \
			or caixa_total.position.z < -limite or caixa_total.end.z > limite:
		falhas.append("o cenário vaza o quadrado de %d m" % int(LADO))

## O retângulo em torno de (-16, 0, 10) — a fileira de treino da `main.tscn`
## — tem de ficar livre de estático. O chão fica de fora: ele é o piso de
## tudo, não um obstáculo.
func _conferir_area_de_treino_livre(cena: Node3D, falhas: Array[String]) -> void:
	var zona: Rect2 = Rect2(-22, 4, 12, 12)  # x -22..-10, z 4..16
	for no: Node in _todos(cena):
		var corpo: StaticBody3D = no as StaticBody3D
		if corpo == null or corpo.name == "Chao":
			continue
		for filho: Node in corpo.get_children():
			var malha: MeshInstance3D = filho as MeshInstance3D
			if malha == null or malha.mesh == null:
				continue
			var no_mundo: AABB = malha.global_transform * malha.mesh.get_aabb()
			var pegada: Rect2 = Rect2(
				no_mundo.position.x, no_mundo.position.z,
				no_mundo.size.x, no_mundo.size.z
			)
			if zona.intersects(pegada):
				falhas.append(
					"'%s' invade a área da fileira de treino em torno de (-16, 0, 10)"
					% corpo.name
				)

func _conferir_marcadores(cena: Node3D, falhas: Array[String]) -> void:
	var spawns: Array[Marker3D] = []
	var acampamentos: Array[Marker3D] = []
	var suprimentos: Array[Marker3D] = []
	for no: Node in _todos(cena):
		var marcador: Marker3D = no as Marker3D
		if marcador == null:
			continue
		var nome: String = String(marcador.name)
		if nome.begins_with("MarcadorDeSpawn"):
			spawns.append(marcador)
		elif nome.begins_with("MarcadorDeAcampamento"):
			acampamentos.append(marcador)
		elif nome.begins_with("MarcadorDeSuprimento"):
			suprimentos.append(marcador)
	if spawns.size() != 8:
		falhas.append("%d marcadores de spawn onde se esperavam 8" % spawns.size())
	for marcador: Marker3D in spawns:
		var distancia: float = Vector2(
			marcador.global_position.x, marcador.global_position.z
		).length()
		if absf(distancia - SPAWN_RAIO) > 0.05:
			falhas.append(
				"'%s' está a %.2f m do centro; o anel é de %.0f"
				% [marcador.name, distancia, SPAWN_RAIO]
			)
	if acampamentos.size() != 3:
		falhas.append(
			"%d marcadores de acampamento onde se esperavam 3" % acampamentos.size()
		)
	else:
		for i: int in 3:
			var a: Vector3 = acampamentos[i].global_position
			var b: Vector3 = acampamentos[(i + 1) % 3].global_position
			if absf(a.distance_to(b) - 5.0) > 0.05:
				falhas.append(
					"o triângulo de acampamento tem lado %.2f onde se esperavam 5,00"
					% a.distance_to(b)
				)
	if suprimentos.size() != 1:
		falhas.append(
			"%d marcadores de suprimento onde se esperava 1" % suprimentos.size()
		)
	elif suprimentos[0].global_position.distance_to(Vector3(0, 0, 20)) > 0.05:
		falhas.append("o marcador de suprimento saiu de (0, 0, 20)")

## Cada porta é conferida por DOIS raios, no espaço da própria casa (a
## engine compõe o giro): um pelo vão, que não pode bater em nada, e um de
## controle contra o pano da frente, que TEM de bater — sem o par, um
## raycast que não enxerga nada aprovaria qualquer parede.
func _conferir_portas(cena: Node3D, raio: RayCast3D, falhas: Array[String]) -> void:
	for i: int in 4:
		var casa: Node3D = cena.get_node_or_null("Vila/Casa%d" % (i + 1)) as Node3D
		if casa == null:
			falhas.append("Vila/Casa%d não existe" % (i + 1))
			continue
		var tf: Transform3D = casa.global_transform
		var fora_da_porta: Vector3 = tf * Vector3(0, 1.2, -5.5)
		var centro: Vector3 = tf * Vector3(0, 1.2, 0)
		if _bate(raio, fora_da_porta, centro):
			falhas.append("a porta da Casa%d está obstruída" % (i + 1))
		var fora_do_pano: Vector3 = tf * Vector3(2.5, 1.2, -5.5)
		var atras_do_pano: Vector3 = tf * Vector3(2.5, 1.2, -2.0)
		if not _bate(raio, fora_do_pano, atras_do_pano):
			falhas.append(
				"o raio de controle atravessou a frente da Casa%d "
				% (i + 1) + "— ou a parede sumiu, ou o raycast não enxerga"
			)

## O mesmo par de raios para o rio: cruzar na ponte passa, cruzar fora bate.
func _conferir_ponte(raio: RayCast3D, falhas: Array[String]) -> void:
	if _bate(raio, Vector3(PONTE_X, 0.5, 2.0), Vector3(PONTE_X, 0.5, -7.0)):
		falhas.append("a travessia da ponte em x=%.0f está obstruída" % PONTE_X)
	if not _bate(raio, Vector3(-40, 0.5, 2.0), Vector3(-40, 0.5, -7.0)):
		falhas.append(
			"o raio de controle cruzou o rio fora da ponte — "
			+ "ou a margem sumiu, ou o raycast não enxerga"
		)

func _bate(raio: RayCast3D, de: Vector3, para: Vector3) -> bool:
	raio.global_position = de
	raio.target_position = para - de
	raio.force_raycast_update()
	return raio.is_colliding()

func _todos(cena: Node) -> Array[Node]:
	var lista: Array[Node] = [cena]
	var fila: Array[Node] = [cena]
	while not fila.is_empty():
		var no: Node = fila.pop_back()
		for filho: Node in no.get_children():
			lista.append(filho)
			fila.append(filho)
	return lista
