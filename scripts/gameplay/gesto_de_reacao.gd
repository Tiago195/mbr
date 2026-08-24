class_name GestoDeReacao
extends Node

## O corpo reage ao que ACONTECE com ele — levar dano, morrer, ser controlado.
##
## É a terceira camada visual do corpo, e a que faltava. As outras duas
## desenham o que o jogador MANDA fazer: `GestoDeConjuracao` desenha a
## habilidade, `GestoDeCaminhada` desenha o deslocamento. Nenhuma das duas
## desenha o que o adversário faz com você, e num jogo de luta essa é metade da
## informação: sem ela, o personagem que está apanhando parece o mesmo que o
## personagem que está batendo.
##
## No original isto é vocabulário obrigatório: `beaten`, `stun` e `death` estão
## nos 32 campeões, medidos em `docs/11-direcao-de-arte.md` §3.
##
## ## Quem manda no corpo
##
## Três componentes disputam o mesmo esqueleto, e a ordem é esta:
##
##     morte > atordoado > conjuração > levou dano > caminhada
##
## A morte é a única que não solta o corpo: ela termina deitada e fica.
##
## **Levar dano NÃO interrompe a conjuração**, e isso é decisão de jogo: no
## esquema do League of Legends tomar dano não cancela habilidade, e cancelar
## a animação faria o jogador achar que cancelou. Já controle de grupo e morte
## ganham de tudo, porque aí o personagem realmente não está mais fazendo o que
## queria.
##
## Camada visual pura: lê sinal, toca clipe. Não decide nada de combate.

## O corpo. Sem esqueleto este nó não faz nada — o corpo de caixas é o que
## sobra numa máquina que não gerou `arte/personagem.glb`, e ele nunca teve
## reação nenhuma.
var _boneco: Boneco
var _combatente: Combatant
var _conjuracao: GestoDeConjuracao

## Quanto falta do clipe de reação em curso.
var _restante: float = 0.0

## Os estados que o corpo desenha como `atordoado`.
##
## **`AIRBORNE` divide o clipe com `STUN`, e dividir é a regra**: o §3 de
## `docs/11` mede que duas coisas com a mesma FORMA dividem o gesto, e que 6
## dos 32 campeões do original não têm clipe exclusivo nenhum por causa disso.
## Um arremesso ao ar merece gesto próprio no dia em que houver deslocamento
## vertical para acompanhá-lo; hoje não há, e um clipe novo seria inventar.
##
## Os outros controles ficam de fora de propósito: quem está enfeitiçado ou
## provocado ANDA — só que para onde não quer —, e desenhá-lo parado seria
## mentir sobre o que está acontecendo.
const PARALISADO: Array[StatusSet.Kind] = [
	StatusSet.Kind.STUN, StatusSet.Kind.AIRBORNE,
]

## Se o corpo está desenhando o atordoamento agora.
var _atordoado: bool = false

## Morreu. **Não volta**, e é o único estado assim.
var _morto: bool = false

func _ready() -> void:
	_boneco = _irmao(Boneco) as Boneco
	_combatente = _irmao(Combatant) as Combatant
	_conjuracao = _irmao(GestoDeConjuracao) as GestoDeConjuracao
	if _combatente == null or _boneco == null:
		push_warning("GestoDeReacao sem corpo em '%s'." % get_parent().name)
		return
	_combatente.damaged.connect(_ao_levar_dano)
	_combatente.died.connect(_ao_morrer)

## Verdadeiro enquanto uma reação está sendo desenhada.
##
## `GestoDeCaminhada` consulta isto para dar passagem: retomar a caminhada no
## quadro seguinte ao golpe apagaria a reação inteira, que é exatamente o que
## acontecia com o clipe de ataque antes de ele passar a segurar o corpo.
func esta_reagindo() -> bool:
	return _morto or _atordoado or _restante > 0.0

func _process(delta: float) -> void:
	# Morto não reage a mais nada: o clipe termina deitado e fica.
	if _morto:
		return
	if _restante > 0.0:
		_restante -= delta
	_desenhar_o_controle()

## Morreu. O corpo cai e **fica caído** — nenhuma outra camada desenha por
## cima, porque `esta_reagindo()` continua verdadeiro para sempre.
##
## Sem esse "para sempre" a caminhada retomava o corpo assim que o clipe
## terminasse, e o personagem morto voltava a respirar de pé.
func _ao_morrer() -> void:
	_morto = true
	_atordoado = false
	_restante = 0.0
	if _boneco != null and _boneco.animador() != null:
		_boneco.tocar(VocabularioDeAnimacao.MORTE, true)

## Atordoado é ESTADO, não evento, e por isso é lido a cada quadro em vez de
## pendurado num sinal.
##
## O atordoamento dura o que a habilidade mandar — pode ser encurtado por
## tenacidade, limpo por outra habilidade, ou renovado. Um sinal diria quando
## começou; o que o corpo precisa saber é se AINDA está, e é isso que `has`
## responde. É também por isso que o clipe é ciclo.
func _desenhar_o_controle() -> void:
	if _combatente == null or _combatente.unit == null:
		return
	var preso: bool = _combatente.unit.status.has_any(PARALISADO)
	if preso == _atordoado:
		return
	_atordoado = preso
	if preso:
		_tocar(VocabularioDeAnimacao.ATORDOADO)
	else:
		# Solta o corpo na hora: o clipe é ciclo e não termina sozinho.
		_restante = 0.0

## Verdadeiro enquanto uma reação está sendo desenhada.
func _esta_preso() -> bool:
	return _atordoado

func _ao_levar_dano(_resultado: DamageResult) -> void:
	# Morte, atordoado e conjurar ganham, nessa ordem: ver o cabeçalho.
	if _morto:
		return
	if _atordoado:
		return
	if _conjuracao != null and _conjuracao.esta_gesticulando():
		return
	_tocar(VocabularioDeAnimacao.LEVOU_DANO)

## Toca um clipe de reação e segura o corpo pelo tempo dele. Devolve se tocou.
func _tocar(clipe: StringName) -> bool:
	if _boneco == null or _boneco.animador() == null:
		return false
	if not _boneco.tocar(clipe, true):
		return false
	# **Ciclo não tem fim, e por isso não entra no relógio.** Quem termina o
	# atordoamento é o estado deixar de valer, não o clipe acabar; pôr um ciclo
	# aqui faria o corpo largar a pose no meio do controle e voltar a andar.
	_restante = (
		0.0 if VocabularioDeAnimacao.CICLOS.has(clipe)
		else maxf(_boneco.duracao_de(clipe), 0.05)
	)
	return true

func _irmao(tipo: Variant) -> Node:
	var host: Node = get_parent()
	if host == null:
		return null
	for filho: Node in host.get_children():
		if is_instance_of(filho, tipo):
			return filho
	return null
