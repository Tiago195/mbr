class_name Boneco
extends Node3D

## Um corpo com MEMBROS, montado por código.
##
## Existe porque a cápsula travou o teste. Palavras do usuário, em 23/08/2026:
## *"eu não consigo testar sem ver os personagens"*. Com um corpo único, o
## gesto de conjuração só podia mover a coisa inteira — e mover a coisa inteira
## lê como empurrão, não como golpe. Com ombro e quadril existindo, o braço
## bate e a perna anda.
##
## **Feio de propósito, e isso é o critério da Fase 1**: caixas e cápsulas, um
## corpo só para todos os campeões, sem textura e sem sombra. O que ele precisa
## responder é *"o personagem fez o quê?"*, e para isso membro basta. Quando
## houver modelo com esqueleto de verdade — Meshy e Mixamo, Fase 6 —, este nó
## sai inteiro e o `GestoDeConjuracao` passa a mexer nos ossos.
##
## Montado por código e não em `.tscn` por uma razão medida: a hierarquia tem
## nove `Transform3D` aninhados, e o `CLAUDE.md` registra que escrever matriz
## de rotação à mão em cena já custou uma sessão inteira. Aqui não há matriz —
## há `position` e `rotation_degrees`, que a engine compõe.
##
## **O pivô de cada membro fica na junta.** Um braço cuja malha nasce centrada
## gira em torno do próprio meio, o que parece um bastão flutuando; deslocando
## a malha para baixo do pivô, ele gira a partir do ombro, que é o que o olho
## espera.

## Altura total, do pé ao alto da cabeça.
@export var altura: float = 1.8

@export_group("Andaime de teste")
## Malhas a carregar em vez de montar o boneco de caixas, se existirem.
##
## **É andaime, e some sem deixar rastro.** Apontam para `import_local/`, que o
## `.gitignore` recusa inteira: são assets extraídos da instalação local do
## Royal Crown para o desenvolvedor conseguir testar vendo um personagem, e não
## vão para o build — a regra de `docs/01` continua valendo, e o caminho
## definitivo é Meshy + Mixamo na Fase 6.
##
## Quem clona o repositório não tem a pasta, e cai no boneco de caixas sem
## precisar mexer em nada. É por isso que a lista é de CAMINHOS e não de
## recursos: um `@export var PackedScene` quebraria a cena para quem não os
## tem.
@export var malhas_externas: PackedStringArray = PackedStringArray([
	"res://import_local/Violet_Body.obj",
	"res://import_local/Violet_Head.obj",
])
## Correção de eixo: as malhas do original são Z-up e olham para +Z; a Godot é
## Y-up e olha para -Z. Sem o giro em Y o personagem anda de costas — foi o que
## aconteceu na primeira versão.
@export var giro_externo_graus: Vector3 = Vector3(-90.0, 180.0, 0.0)
## Quanto multiplicar a malha externa para ela ficar na altura declarada.
@export var escala_externa: float = 1.25

@export_group("Cores")
@export var cor_corpo: Color = Color(0.55, 0.60, 0.70)
@export var cor_cabeca: Color = Color(0.85, 0.78, 0.65)
@export var cor_membro: Color = Color(0.45, 0.50, 0.60)
## A mão que empunha. Uma cor só para ela, porque é o que o olho segue durante
## o golpe.
@export var cor_mao: Color = Color(0.95, 0.55, 0.25)

var quadril: Node3D
var tronco: Node3D
var cabeca: Node3D
var braco_direito: Node3D
var braco_esquerdo: Node3D
var perna_direita: Node3D
var perna_esquerda: Node3D

## Guardadas para o gesto poder voltar ao repouso sem recalcular nada.
var _repouso: Dictionary = {}

## Verdadeiro quando o corpo tem membros animáveis. Falso quando é uma malha
## externa inteiriça — e aí o gesto move o corpo todo, que é o que dá para
## fazer sem esqueleto.
func tem_membros() -> bool:
	return quadril != null

func _ready() -> void:
	if _montar_externas():
		return
	_montar()

## Carrega as malhas do andaime, se existirem. Devolve se alguma entrou.
func _montar_externas() -> bool:
	var entrou: bool = false
	for caminho: String in malhas_externas:
		if not ResourceLoader.exists(caminho):
			continue
		var recurso: Resource = load(caminho)
		var malha: Mesh = recurso as Mesh
		if malha == null and recurso is PackedScene:
			# A Godot importa `.obj` como cena quando há mais de um material.
			var cena: Node = (recurso as PackedScene).instantiate()
			add_child(cena)
			(cena as Node3D).rotation_degrees = giro_externo_graus
			(cena as Node3D).scale = Vector3.ONE * escala_externa
			entrou = true
			continue
		if malha == null:
			continue
		var no := MeshInstance3D.new()
		no.mesh = malha
		no.rotation_degrees = giro_externo_graus
		no.scale = Vector3.ONE * escala_externa
		# A malha nasce com os pés na origem local; o corpo do jogo tem o
		# centro na cintura, daí o meio passo para baixo.
		no.position = Vector3(0.0, -altura * 0.5, 0.0)
		add_child(no)
		entrou = true
	return entrou

func _montar() -> void:
	var h: float = altura
	# Proporções de boneco, não de humano: cabeça grande e membros curtos leem
	# melhor em cápsula do que proporção realista. É a convenção chibi do
	# original, e aqui ela é escolha de legibilidade.
	var altura_perna: float = h * 0.42
	var altura_tronco: float = h * 0.34
	var raio_cabeca: float = h * 0.13

	quadril = Node3D.new()
	quadril.name = "Quadril"
	quadril.position = Vector3(0.0, altura_perna - h * 0.5, 0.0)
	add_child(quadril)

	tronco = _membro(
		quadril, "Tronco", Vector3.ZERO,
		Vector3(h * 0.30, altura_tronco, h * 0.18), cor_corpo
	)

	cabeca = Node3D.new()
	cabeca.name = "Cabeca"
	cabeca.position = Vector3(0.0, altura_tronco + raio_cabeca * 0.9, 0.0)
	quadril.add_child(cabeca)
	var bola := MeshInstance3D.new()
	bola.mesh = SphereMesh.new()
	(bola.mesh as SphereMesh).radius = raio_cabeca
	(bola.mesh as SphereMesh).height = raio_cabeca * 2.0
	bola.material_override = _material(cor_cabeca)
	cabeca.add_child(bola)
	# Um nariz, e ele não é enfeite: é o que diz para onde o personagem olha
	# quando o corpo é simétrico.
	var nariz := MeshInstance3D.new()
	nariz.mesh = BoxMesh.new()
	(nariz.mesh as BoxMesh).size = Vector3(raio_cabeca * 0.3, raio_cabeca * 0.3, raio_cabeca * 0.7)
	nariz.position = Vector3(0.0, 0.0, -raio_cabeca * 0.85)
	nariz.material_override = _material(cor_mao)
	cabeca.add_child(nariz)

	var ombro: float = altura_tronco * 0.82
	var largura_ombro: float = h * 0.19
	braco_direito = _membro(
		quadril, "BracoDireito", Vector3(largura_ombro, ombro, 0.0),
		Vector3(h * 0.075, h * 0.30, h * 0.075), cor_membro, cor_mao
	)
	braco_esquerdo = _membro(
		quadril, "BracoEsquerdo", Vector3(-largura_ombro, ombro, 0.0),
		Vector3(h * 0.075, h * 0.30, h * 0.075), cor_membro, cor_mao
	)

	var largura_quadril: float = h * 0.09
	perna_direita = _membro(
		quadril, "PernaDireita", Vector3(largura_quadril, 0.0, 0.0),
		Vector3(h * 0.085, altura_perna, h * 0.085), cor_membro
	)
	perna_esquerda = _membro(
		quadril, "PernaEsquerda", Vector3(-largura_quadril, 0.0, 0.0),
		Vector3(h * 0.085, altura_perna, h * 0.085), cor_membro
	)

	for membro: Node3D in membros():
		_repouso[membro] = membro.rotation

## Um membro: um pivô na junta, com a malha pendurada abaixo dele.
##
## `ponta` colore a extremidade — a mão, que é o que o olho segue no golpe.
func _membro(
		pai: Node3D, nome: String, junta: Vector3, tamanho: Vector3,
		cor: Color, ponta: Color = Color(0, 0, 0, 0)
) -> Node3D:
	var pivo := Node3D.new()
	pivo.name = nome
	pivo.position = junta
	pai.add_child(pivo)

	var malha := MeshInstance3D.new()
	malha.mesh = BoxMesh.new()
	(malha.mesh as BoxMesh).size = tamanho
	# **O deslocamento é o que põe o pivô na junta.** Sem ele o membro gira em
	# torno do próprio meio e parece um bastão solto no ar.
	malha.position = Vector3(0.0, -tamanho.y * 0.5, 0.0)
	malha.material_override = _material(cor)
	pivo.add_child(malha)

	if ponta.a > 0.0:
		var mao := MeshInstance3D.new()
		mao.mesh = BoxMesh.new()
		(mao.mesh as BoxMesh).size = Vector3(tamanho.x * 1.25, tamanho.x * 1.25, tamanho.x * 1.25)
		mao.position = Vector3(0.0, -tamanho.y, 0.0)
		mao.material_override = _material(ponta)
		pivo.add_child(mao)
	return pivo

func _material(cor: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = cor
	return material

## Todos os membros animáveis, na ordem em que foram montados. Vazia quando o
## corpo é uma malha externa inteiriça.
func membros() -> Array[Node3D]:
	var lista: Array[Node3D] = []
	for membro: Node3D in [
		tronco, cabeca, braco_direito, braco_esquerdo,
		perna_direita, perna_esquerda,
	]:
		if membro != null:
			lista.append(membro)
	return lista

## Devolve cada membro ao ângulo de repouso.
func repousar() -> void:
	if not tem_membros():
		return
	for membro: Node3D in membros():
		if _repouso.has(membro):
			membro.rotation = _repouso[membro]
	if quadril != null:
		quadril.position.y = altura * 0.42 - altura * 0.5
		quadril.rotation = Vector3.ZERO

## O ângulo de repouso de um membro, ou zero se ele não for daqui.
func repouso_de(membro: Node3D) -> Vector3:
	return _repouso.get(membro, Vector3.ZERO)
