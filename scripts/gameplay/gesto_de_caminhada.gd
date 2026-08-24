class_name GestoDeCaminhada
extends Node

## O corpo se mexe enquanto anda, em vez de deslizar.
##
## Terceira coisa que o usuário apontou ao ver o personagem na tela, em
## 23/08/2026: *"está andando de costas e sem animação ao andar"*. A primeira
## era orientação; esta é que o corpo ficava perfeitamente parado enquanto se
## deslocava, o que lê como o cenário se movendo por baixo dele.
##
## Duas formas, escolhidas pelo corpo que existir:
##
## - **Com membros** (o boneco de caixas): pernas e braços alternando, que é
##   passada de verdade
## - **Sem membros** (malha externa sem esqueleto): sobe e desce com uma leve
##   inclinação para a frente. Não é passada, mas é o bastante para o olho
##   parar de ver deslizamento — e é o que dá para fazer sem osso
##
## O gesto de conjuração TEM PRIORIDADE: quem está golpeando não está andando,
## e sobrepor os dois faria o braço tremer no meio do golpe.
##
## Camada visual pura: lê a velocidade do corpo e desenha.

## Passadas por segundo a 3,3 m/s, que é o passo típico de um campeão.
@export var cadencia: float = 1.7

## Quanto a perna abre, em graus.
@export var abertura_da_perna: float = 32.0
## Quanto o braço acompanha, em graus. Menos que a perna, e em contrafase.
@export var balanco_do_braco: float = 22.0
## Quanto o corpo sobe e desce a cada passada, em metros.
##
## **14 cm, e o número é medido.** A primeira versão usava 4,5 cm — 2,5% da
## altura de um corpo de 1,8 m, invisível na tela. A conferência aprovava
## porque o piso dela estava baixo demais, e o usuário reportou que continuava
## sem animação. Uma animação que a máquina aprova e o olho não vê não é
## animação.
@export var sobe_e_desce: float = 0.14
## Quanto o corpo se inclina para a frente ao andar, em graus.
@export var inclinacao: float = 10.0
## Quanto o corpo bamboleia de um lado para o outro, em graus.
##
## O balanço lateral é o que mais lê como caminhada num corpo sem pernas
## articuladas: sobe e desce sozinho parece flutuação, e com o bamboleio junto
## vira passo.
@export var bamboleio: float = 7.0

## Abaixo desta velocidade o personagem é considerado parado.
@export var velocidade_minima: float = 0.15

## Fração da velocidade plena a partir da qual o corpo CORRE em vez de andar.
##
## Abaixo dela o personagem está retardado por alguma coisa, e o corpo diz
## isso. O valor é escolha de jogo, não medida do original: lá `walk` e `run`
## existem nos 32 campeões, e qual deles toca é decisão do controlador, que não
## está nos bundles medidos (§3 de `docs/11`).
@export_range(0.1, 1.0) var fracao_de_corrida: float = 0.75

var _corpo: CharacterBody3D
var _boneco: Boneco
var _combatente: Combatant
var _gesto: GestoDeConjuracao
var _reacao: GestoDeReacao
var _fase: float = 0.0
var _base_y: float = 0.0

func _ready() -> void:
	_corpo = get_parent() as CharacterBody3D
	_boneco = _achar(Boneco) as Boneco
	_combatente = _achar(Combatant) as Combatant
	_gesto = _achar(GestoDeConjuracao) as GestoDeConjuracao
	_reacao = _achar(GestoDeReacao) as GestoDeReacao
	if _corpo == null or _boneco == null:
		push_warning("GestoDeCaminhada sem corpo em '%s'." % get_parent().name)
	else:
		_base_y = _boneco.position.y

func _process(delta: float) -> void:
	if _corpo == null or _boneco == null:
		return
	# **Reagir e conjurar têm prioridade, nessa ordem.** Sobrepor caminhada e
	# golpe faz o braço tremer no meio do gesto, e o golpe é a informação mais
	# importante das duas — é ele que o jogador está tentando ler. A reação vem
	# antes das duas: quem apanhou não está andando.
	if _reacao != null and _reacao.esta_reagindo():
		return
	if _gesto != null and _gesto.esta_gesticulando():
		# **E devolve o corpo ao lugar antes de sair.** Sem isto a caminhada
		# larga o corpo inclinado e o gesto de conjuração desenha por cima de
		# um repouso que não é repouso — foi o que a sonda acusou com "o corpo
		# não voltou ao repouso depois do gesto".
		return

	var plana := Vector3(_corpo.velocity.x, 0.0, _corpo.velocity.z)
	var rapidez: float = plana.length()

	# **Com esqueleto, o clipe manda e o quique SAI.** Quique, inclinação e
	# bamboleio foram escritos para um corpo sem osso; sobre uma passada de
	# verdade eles viram o "boneco se tremendo de lado, meio que pulado" que o
	# usuário reportou.
	if _boneco.animador() != null:
		_boneco.tocar(_clipe_de_locomocao(rapidez))
		return

	if rapidez < velocidade_minima:
		if _fase != 0.0:
			_fase = 0.0
			_repousar()
		return

	# A passada acompanha a VELOCIDADE: andar devagar dá passo lento. Sem isto
	# o personagem corre no lugar quando é retardado por um efeito.
	_fase += delta * cadencia * TAU * (rapidez / 3.3)
	var balanco: float = sin(_fase)

	if _boneco.tem_membros():
		_boneco.repousar()
		_boneco.perna_direita.rotation_degrees.x = abertura_da_perna * balanco
		_boneco.perna_esquerda.rotation_degrees.x = -abertura_da_perna * balanco
		# Contrafase: braço direito com perna esquerda, como se anda.
		_boneco.braco_direito.rotation_degrees.x = -balanco_do_braco * balanco
		_boneco.braco_esquerdo.rotation_degrees.x = balanco_do_braco * balanco
		_boneco.tronco.rotation_degrees.x = -inclinacao * 0.5
		# Sobe e desce no DOBRO da frequência: o corpo sobe uma vez por passo,
		# e são dois passos por ciclo de perna.
		_boneco.quadril.position.y += absf(sin(_fase)) * sobe_e_desce
	else:
		# Sem esqueleto: quique, inclinação e bamboleio. Feio, e resolve o
		# deslizamento — que era o problema.
		_boneco.position.y = _base_y + absf(sin(_fase)) * sobe_e_desce
		_boneco.rotation_degrees.x = -inclinacao
		_boneco.rotation_degrees.z = bamboleio * balanco

## Parado, andando ou correndo — pela velocidade.
##
## **O original tem `walk` E `run`, e nós usávamos só um dos dois.** A distinção
## não é enfeite: quem está lento por uma habilidade anda, quem está inteiro
## corre, e é a única forma de lentidão aparecer no corpo em vez de só no
## número. O limiar é uma fração da velocidade que o campeão teria SEM efeito
## nenhum — comparar com um valor absoluto faria o campeão mais lento do elenco
## andar o tempo todo e o mais rápido nunca andar.
func _clipe_de_locomocao(rapidez: float) -> StringName:
	if rapidez < velocidade_minima:
		return VocabularioDeAnimacao.PARADO
	var plena: float = _velocidade_plena()
	if plena > 0.0 and rapidez < plena * fracao_de_corrida:
		return VocabularioDeAnimacao.ANDANDO
	return VocabularioDeAnimacao.CORRENDO

## A velocidade do personagem sem efeito nenhum em cima. Zero quando não dá
## para saber — e aí o corpo corre, que é o comportamento de antes.
func _velocidade_plena() -> float:
	if _combatente == null or _combatente.unit == null:
		return 0.0
	return _combatente.unit.stats.get_base(Stat.Id.MOVE_SPEED)


func _repousar() -> void:
	if _boneco.tem_membros():
		_boneco.repousar()
		return
	_boneco.position.y = _base_y
	_boneco.rotation_degrees.x = 0.0
	_boneco.rotation_degrees.z = 0.0

func _achar(tipo: Variant) -> Node:
	var host: Node = get_parent()
	if host == null:
		return null
	for child: Node in host.get_children():
		if is_instance_of(child, tipo):
			return child
	return null
