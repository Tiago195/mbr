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
## responder é *"o personagem fez o quê?"*, e para isso membro basta. Este nó
## sai inteiro quando `arte/personagem.glb` carrega, porque aí há esqueleto de
## verdade e o `GestoDeConjuracao` mexe nos ossos. Ele é o caminho de quem não
## gerou o arquivo — e não um estágio anterior a um modelo comprado.
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
##
## Vale para o corpo de caixas montado aqui. O modelo de `arte/personagem.glb`
## traz a altura dele próprio — 1,75 m, que é o §2 de `docs/11` — e é ela que
## manda quando ele carrega.
@export var altura: float = 1.8

## O nosso personagem, gerado por `tools/arte/gerar_personagem.py` a partir de
## `docs/11-direcao-de-arte.md`.
##
## **Ele existia e não era usado.** Era gerado, conferido pela direção de arte,
## conferido de novo sem o Blender por `conferir_numeros.py`, e rastreado no
## repositório — enquanto o jogo montava o corpo de caixas abaixo e pedia
## clipes com nomes que nunca existiram. Quatro ferramentas verdes, e nenhuma
## delas ABRIA o jogo: lição 9 do `CLAUDE.md`.
##
## Um caminho, e não um `PackedScene`: assim o projeto continua abrindo numa
## máquina onde o arquivo não foi gerado — cai no corpo de caixas e segue.
@export var modelo: String = "res://arte/personagem.glb"

## Meia volta, para a frente do modelo bater com a frente da Godot.
##
## **Isto não é gosto, é conversão de eixo, e ela estava faltando.** Ver o
## comentário de `_montar_modelo`. Fica exposto porque é medível: a sonda de
## campeões projeta o rosto sobre o `-basis.z` do corpo e reprova se ele estiver
## atrás, então trocar este número por zero fica VERMELHO em vez de silencioso —
## que foi como o defeito chegou até a tela do usuário.
@export var giro_do_modelo: Vector3 = Vector3(0.0, 180.0, 0.0)

@export_group("Andaime de teste")
## Malhas a carregar em vez de montar o boneco de caixas, se existirem.
##
## **A lista nasce VAZIA, e isso é o estado normal.** Ela já apontou para uma
## pasta de andaime com malhas extraídas da instalação do Royal Crown, para o
## desenvolvedor conseguir testar vendo um personagem. Aquilo era declarado
## como temporário e foi removido: não resolveu o problema, e o caminho nosso é
## `arte/personagem.glb`, gerado por `tools/arte/gerar_personagem.py` a partir
## de `docs/11-direcao-de-arte.md`.
##
## Continua sendo uma lista de CAMINHOS e não de recursos: um
## `@export var PackedScene` quebraria a cena de quem não tem o arquivo, e o
## ponto de um andaime é sumir sem deixar rastro.
@export var malhas_externas: PackedStringArray = PackedStringArray()
## Correção de eixo, para malha que precisar.
##
## Malha vinda de ferramenta Z-up olhando para +Z anda de costas sem o giro —
## já aconteceu. O que sai do nosso gerador **não** precisa: ele exporta em
## Y-up olhando para -Z, que é a frente da Godot.
@export var giro_externo_graus: Vector3 = Vector3(-90.0, 180.0, 0.0)
## Quanto multiplicar a malha externa para ela ficar na altura declarada.
@export var escala_externa: float = 1.25
## Caminhos que já vêm no sistema de eixos da Godot e não levam giro nem escala.
@export var externas_ja_corrigidas: PackedStringArray = PackedStringArray()
@export var pes_abaixo_do_centro: float = 1.0

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

## O tocador de animação da malha externa, quando ela tem esqueleto.
var _animador: AnimationPlayer = null

## O esqueleto da malha externa, quando ela tem um.
var _esqueleto: Skeleton3D = null

## Nomes de clipe que já reclamaram por não existir. Uma reclamação por nome:
## o pedido acontece a cada quadro, e sem isto o console viraria um muro.
var _reclamados: Dictionary = {}

## Verdadeiro quando o corpo tem membros animáveis. Falso quando é uma malha
## externa inteiriça — e aí o gesto move o corpo todo, que é o que dá para
## fazer sem esqueleto.
func tem_membros() -> bool:
	return quadril != null

func _ready() -> void:
	if _montar_modelo():
		return
	if _montar_externas():
		return
	_montar()

## Carrega `arte/personagem.glb`. Devolve se entrou.
##
## Vem antes do andaime e do corpo de caixas porque é o corpo DE VERDADE: ele
## tem esqueleto, e sem osso o gesto move a malha inteira, que lê como
## empurrão em vez de golpe.
##
## **Ele entra girado meia volta, e não é remendo — é a conversão que faltava.**
## O parágrafo que estava aqui afirmava o contrário: que o modelo já nascia
## olhando para o -Z da Godot e que girar seria consertar duas vezes. Medido no
## `.glb` publicado, a viseira e o nariz estão em `z = +0,165 a +0,185` e o bico
## do sapato vai até `z = +0,240` — o rosto olha para **+Z**.
##
## A conta é a do exportador: o boneco encara -Y no Blender, e a conversão glTF
## manda `-Y` do Blender para `+Z`. Isso está CERTO — a especificação do glTF diz
## que a frente de um asset é +Z. Quem discorda é a Godot, onde a frente de um nó
## é `-Z`: é para lá que `look_at` aponta, e é o que `player.gd` usa para virar o
## corpo para onde ele anda. Sem esta meia volta o personagem anda de costas.
##
## A correção mora AQUI, e não no gerador, porque este é o único ponto em que o
## sistema de eixos do glTF encosta no da Godot. O `.glb` continua conforme a
## especificação, o Blender continua autorando com a frente dele, e a folha de
## contato continua enquadrando o rosto. Um `giro_do_modelo` em vez de um número
## solto porque `giro_externo_graus` já existe logo acima pelo mesmo motivo, para
## as malhas do andaime — a diferença é que esta não é opcional.
##
## Nada disto muda o COMBATE: quem decide para onde o personagem olha continua
## sendo o corpo (`-basis.z`, em `combatant.gd` e em `player.gd`). O que gira é
## só a malha, dentro dele.
func _montar_modelo() -> bool:
	if modelo == "" or not ResourceLoader.exists(modelo):
		return false
	var recurso: Resource = load(modelo)
	var empacotada: PackedScene = recurso as PackedScene
	if empacotada == null:
		push_warning("Boneco: '%s' não é uma cena." % modelo)
		return false
	var cena: Node3D = empacotada.instantiate() as Node3D
	if cena == null:
		return false
	add_child(cena)
	cena.position = Vector3(0.0, -pes_abaixo_do_centro, 0.0)
	cena.rotation_degrees = giro_do_modelo
	_animador = _achar_animador(cena)
	_esqueleto = _achar_esqueleto(cena)
	_fechar_os_ciclos()
	if _animador == null or _esqueleto == null:
		push_warning(
			"Boneco: '%s' carregou sem esqueleto ou sem AnimationPlayer." % modelo
		)
	return true

## Carrega as malhas do andaime, se existirem. Devolve se alguma entrou.
##
## Para no PRIMEIRO caminho que existir. Carregar os dois personagens de uma vez
## empilharia Leo e Violet no mesmo lugar.
func _montar_externas() -> bool:
	for caminho: String in malhas_externas:
		if not ResourceLoader.exists(caminho):
			continue
		var corrigida: bool = externas_ja_corrigidas.has(caminho)
		var giro: Vector3 = Vector3.ZERO if corrigida else giro_externo_graus
		var escala: float = 1.0 if corrigida else escala_externa
		var recurso: Resource = load(caminho)

		if recurso is PackedScene:
			# `.glb` sempre vira cena; `.obj` também, quando tem mais de um
			# material.
			var cena: Node3D = (recurso as PackedScene).instantiate() as Node3D
			add_child(cena)
			cena.rotation_degrees = giro
			cena.scale = Vector3.ONE * escala
			cena.position = Vector3(0.0, -pes_abaixo_do_centro, 0.0)
			_animador = _achar_animador(cena)
			_esqueleto = _achar_esqueleto(cena)
			return true

		var malha: Mesh = recurso as Mesh
		if malha == null:
			continue
		var no := MeshInstance3D.new()
		no.mesh = malha
		no.rotation_degrees = giro
		no.scale = Vector3.ONE * escala
		# A malha nasce com os pés na origem local; o corpo do jogo tem o
		# centro na cintura, daí o meio passo para baixo.
		no.position = Vector3(0.0, -pes_abaixo_do_centro, 0.0)
		add_child(no)
		return true
	return false


## O esqueleto da malha externa, quando ela tem um.
func esqueleto() -> Skeleton3D:
	return _esqueleto


## Pontos NO MUNDO que resumem o que o corpo está fazendo agora.
##
## Existe para a sonda medir movimento sem enumerar propriedade — a armadilha
## que o `CLAUDE.md` registra como a que mais rendeu achado por rodada. Os três
## corpos possíveis mexem coisas diferentes: o de caixas gira `rotation` de
## membro, a malha inteiriça mexe `position` e `rotation` do nó, e o esqueleto
## mexe pose de osso. Nenhum desses nomes aparece aqui: os três viram ponto no
## mundo, e "o corpo se mexeu" passa a ser uma medida só.
func pontos() -> PackedVector3Array:
	var saida := PackedVector3Array()
	if _esqueleto != null:
		var base: Transform3D = _esqueleto.global_transform
		for i in range(_esqueleto.get_bone_count()):
			saida.append(base * _esqueleto.get_bone_global_pose(i).origin)
		return saida
	if tem_membros():
		for membro: Node3D in membros():
			saida.append(membro.global_transform * Vector3.ZERO)
			saida.append(membro.global_transform * Vector3(0.0, -0.3, 0.0))
		return saida
	# Malha inteiriça: quatro pontos bastam para que GIRAR o corpo também
	# apareça como movimento, e não só deslocá-lo.
	var t: Transform3D = global_transform
	for canto: Vector3 in [
		Vector3.ZERO, Vector3(0.3, 0.0, 0.0),
		Vector3(0.0, 0.3, 0.0), Vector3(0.0, 0.0, 0.3),
	]:
		saida.append(t * canto)
	return saida


func _achar_esqueleto(no: Node) -> Skeleton3D:
	if no is Skeleton3D:
		return no as Skeleton3D
	for filho: Node in no.get_children():
		var achado: Skeleton3D = _achar_esqueleto(filho)
		if achado != null:
			return achado
	return null


func _achar_animador(no: Node) -> AnimationPlayer:
	if no is AnimationPlayer:
		return no as AnimationPlayer
	for filho: Node in no.get_children():
		var achado: AnimationPlayer = _achar_animador(filho)
		if achado != null:
			return achado
	return null


## O `AnimationPlayer` da malha externa, ou nulo quando o corpo é o de caixas.
func animador() -> AnimationPlayer:
	return _animador


## Toca um clipe pelo nome, se ele existir. Devolve se tocou.
##
## **Nome que não existe RECLAMA**, uma vez por nome. A versão silenciosa foi
## como o jogo passou a pedir oito clipes do Royal Crown que nunca estiveram no
## nosso arquivo: `tocar` devolvia `false`, ninguém lia o retorno, e o corpo
## ficava parado sem uma linha no console. Ver `VocabularioDeAnimacao`.
func tocar(nome: String, tocar_de_novo: bool = false) -> bool:
	if _animador == null:
		return false
	if not _animador.has_animation(nome):
		if not _reclamados.has(nome):
			_reclamados[nome] = true
			push_warning(
				"Boneco: '%s' não tem o clipe '%s'." % [modelo, nome]
			)
		return false
	if not tocar_de_novo and _animador.current_animation == nome:
		return true
	_animador.play(nome)
	return true

## Quanto dura um clipe, em segundos. Zero quando ele não existe.
##
## Existe para o gesto durar o que o CLIPE dura. Sem isto o gesto de
## conjuração usava um tempo próprio e a caminhada retomava o corpo no meio do
## golpe — o clipe de ataque vivia um quadro.
func duracao_de(nome: String) -> float:
	if _animador == null or not _animador.has_animation(nome):
		return 0.0
	return _animador.get_animation(nome).length

## Põe em ciclo os clipes que o vocabulário declara como ciclo.
##
## **O glTF não guarda essa informação**, então tudo importa como "uma vez":
## sem isto o personagem dava um passo e congelava, e o console não dizia nada.
## Quem sabe o que é ciclo é `VocabularioDeAnimacao.CICLOS`, que copia a coluna
## "Tipo" do §3 de `docs/11` — medida nos 32 campeões do original.
func _fechar_os_ciclos() -> void:
	if _animador == null:
		return
	for nome: StringName in VocabularioDeAnimacao.CICLOS:
		if not _animador.has_animation(nome):
			continue
		_animador.get_animation(nome).loop_mode = Animation.LOOP_LINEAR

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
