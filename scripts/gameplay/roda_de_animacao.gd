class_name RodaDeAnimacao
extends Node

## Uma tecla que percorre TODO o vocabulário de animação, em jogo.
##
## ## Por que existe
##
## Porque metade do vocabulário não tem sistema que a dispare. `colhendo`,
## `cortando`, `minerando`, `pegando`, `comendo`, `bebendo` e `operando` são
## sete dos 22 verbos universais do original — um terço do vocabulário
## obrigatório é interagir com o cenário — e nós não temos loot, nem árvore,
## nem minério. `caido` e `rastejando` esperam o estado de abatido. `montado`
## espera montaria.
##
## Sem isto, essas animações seriam **conteúdo que ninguém consegue olhar**: a
## folha de contato do Blender mostra a pose, mas não mostra o boneco na
## câmera isométrica, no tamanho em que se joga, no meio da cena. E o critério
## do §10 — *"a silhueta diz o que é?"* — só se responde vendo.
##
## É a mesma ideia do Page Down que troca de campeão: provisório, de propósito,
## e existe porque testar 20 clipes sem ele exigiria 20 edições de cena.
##
## **Home e End**, vizinhos de Page Up e Page Down no teclado, e pela mesma
## razão: a roda dos campeões e a roda das animações são o mesmo gesto.

## Índice na roda. -1 é "desligado", que é o estado normal do jogo.
var _indice: int = -1

var _boneco: Boneco
var _log: Node

func _ready() -> void:
	_boneco = _irmao(Boneco) as Boneco
	_log = _irmao_por_nome("CombatLog")

## Verdadeiro enquanto a roda está mostrando um clipe.
##
## As três camadas visuais consultam isto e dão passagem: com a roda ligada,
## quem manda no corpo é ela. Sem essa passagem, andar ou apanhar apagaria o
## clipe que se está tentando olhar.
func esta_mostrando() -> bool:
	return _indice >= 0

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var passo: int = 0
	if event.is_action("animacao_next"):
		passo = 1
	elif event.is_action("animacao_prev"):
		passo = -1
	else:
		return
	# A roda tem uma posição a mais que o vocabulário: a de estar desligada.
	# Passar do fim devolve o corpo ao jogo, que é como se sai sem uma terceira
	# tecla.
	var quantas: int = VocabularioDeAnimacao.TODOS.size()
	_indice = wrapi(_indice + 1 + passo, 0, quantas + 1) - 1
	_mostrar()

func _mostrar() -> void:
	if _boneco == null or _boneco.animador() == null:
		return
	if _indice < 0:
		_escrever("roda de animação: desligada")
		return
	var nome: StringName = VocabularioDeAnimacao.TODOS[_indice]
	_boneco.tocar(nome, true)
	_escrever("animação %d/%d: %s%s" % [
		_indice + 1, VocabularioDeAnimacao.TODOS.size(), nome,
		"  (ciclo)" if VocabularioDeAnimacao.CICLOS.has(nome) else "",
	])

func _process(_delta: float) -> void:
	if _indice < 0 or _boneco == null or _boneco.animador() == null:
		return
	# **Repete o que é de uma VEZ.** Um gesto de 1 s toca e para, e o que sobra
	# na tela é a última pose — que não é o que se está tentando olhar. Aqui a
	# roda o repõe, porque o ponto dela é ver o movimento, não o fim dele.
	var animador: AnimationPlayer = _boneco.animador()
	if not animador.is_playing():
		_boneco.tocar(VocabularioDeAnimacao.TODOS[_indice], true)

func _escrever(texto: String) -> void:
	if _log != null and _log.has_method("_escrever"):
		_log.call("_escrever", Color(0.75, 0.85, 1.0), texto)
	print("[roda] %s" % texto)

func _irmao(tipo: Variant) -> Node:
	var host: Node = get_parent()
	if host == null:
		return null
	for filho: Node in host.get_children():
		if is_instance_of(filho, tipo):
			return filho
	return null

func _irmao_por_nome(nome: String) -> Node:
	var host: Node = get_parent()
	if host == null:
		return null
	for filho: Node in host.get_children():
		if filho.name == nome:
			return filho
	return null
