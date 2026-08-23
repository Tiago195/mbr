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
@export var sobe_e_desce: float = 0.045
## Quanto o corpo se inclina para a frente ao andar, em graus.
@export var inclinacao: float = 6.0

## Abaixo desta velocidade o personagem é considerado parado.
@export var velocidade_minima: float = 0.15

var _corpo: CharacterBody3D
var _boneco: Boneco
var _gesto: GestoDeConjuracao
var _fase: float = 0.0
var _base_y: float = 0.0

func _ready() -> void:
	_corpo = get_parent() as CharacterBody3D
	_boneco = _achar(Boneco) as Boneco
	_gesto = _achar(GestoDeConjuracao) as GestoDeConjuracao
	if _corpo == null or _boneco == null:
		push_warning("GestoDeCaminhada sem corpo em '%s'." % get_parent().name)
	else:
		_base_y = _boneco.position.y

func _process(delta: float) -> void:
	if _corpo == null or _boneco == null:
		return
	# **Conjurar tem prioridade.** Sobrepor caminhada e golpe faz o braço
	# tremer no meio do gesto, e o golpe é a informação mais importante das
	# duas — é ele que o jogador está tentando ler.
	if _gesto != null and _gesto.esta_gesticulando():
		_fase = 0.0
		return

	var plana := Vector3(_corpo.velocity.x, 0.0, _corpo.velocity.z)
	var rapidez: float = plana.length()
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
		# Sem esqueleto: o que dá é o quique e a inclinação. Feio, e ainda
		# assim resolve o deslizamento.
		_boneco.position.y = _base_y + absf(sin(_fase)) * sobe_e_desce
		_boneco.rotation_degrees.x = -inclinacao

func _repousar() -> void:
	if _boneco.tem_membros():
		_boneco.repousar()
		return
	_boneco.position.y = _base_y
	_boneco.rotation_degrees.x = 0.0

func _achar(tipo: Variant) -> Node:
	var host: Node = get_parent()
	if host == null:
		return null
	for child: Node in host.get_children():
		if is_instance_of(child, tipo):
			return child
	return null
