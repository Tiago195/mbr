class_name GestoDeConjuracao
extends Node

## O personagem FAZ alguma coisa ao conjurar — animação, não texto.
##
## Existe por uma correção do usuário, em 23/08/2026, e ela estava certa:
##
## > *"quando você fala 'isso é informação, não animação', você esquece que eu
## > sou um humano vendo uma tela; para mim informação É a animação do
## > personagem gastando a habilidade"*
##
## Num jogo, o gesto é como a informação chega. Um registro de texto serve para
## depurar; ninguém lê um combate assim. Enquanto não há modelo com esqueleto —
## quem não gerou `arte/personagem.glb` —, a cápsula anima **por procedimento**:
## é como os
## jogos comunicavam antes de haver animação esquelética, e é 100% nosso.
##
## O que faz um gesto ser legível não é a forma: é o TEMPO em três partes —
## antecipação (recua e encolhe), ação (o golpe, rápido) e recuperação (volta
## devagar). Sem antecipação o golpe parece teleporte; sem recuperação parece
## que travou.
##
## Cada forma de pulso ganha um gesto diferente, porque é isso que responde à
## pergunta que travou o teste: *era a mesma habilidade ou outra?*
##
## Mexe na MALHA, nunca no corpo: a colisão e a posição de jogo continuam
## exatamente onde `core/` as pôs. É camada visual pura.

## Que gesto o corpo faz.
enum Gesto {
	## Estocada à frente. Linha, cone, trapézio — tudo que sai para a frente.
	ESTOCADA,
	## Giro sobre o próprio eixo. Área em volta de quem conjura.
	GIRO,
	## Agachar e saltar. Deslocamento.
	SALTO,
	## Erguer-se e baixar. Suprema, e o que vem de cima.
	ERGUER,
	## Encolher e voltar. Conjuração com tempo — é o aviso de que algo vem.
	PREPARO,

	# **Valor novo entra no FIM, sempre.** `Gesto` é chave de um dicionário
	# exportado, e a Godot serializa enum como INTEIRO: inserir no meio trocaria
	# o gesto de tudo que já estivesse salvo, em silêncio. É a armadilha que o
	# `CLAUDE.md` anota em cada enum exportado deste projeto.

	## Arremesso por cima do ombro. Projétil.
	##
	## Era ESTOCADA, e a diferença não é cosmética: são **359 pulsos de
	## projétil no corpus, em 223 habilidades** — a forma mais comum sem gesto
	## próprio —, e desenhar um arremesso como estocada fazia lançar parecer
	## esfaquear. `throw` é a conjuração universal do original justamente
	## porque essa é a forma que todo campeão tem.
	ARREMESSO,

	## Escudada: a habilidade que EMPURRA os outros.
	##
	## Era SALTO, e SALTO estava errado nos dois lados: deslocamento que move
	## A SI (dash) é o corpo indo; deslocamento que move OS OUTROS é o corpo
	## batendo — e desenhar o R do Leo como pulo dizia que ele fugiu, quando
	## ele deu escudada. Quem separa os dois é o `recipient` do efeito.
	EMPURRAO,
}

## Quanto o gesto inteiro dura, em segundos.
@export var duracao: float = 0.34

## Fração da duração gasta na antecipação. O resto é ação e recuperação.
@export_range(0.0, 0.6) var fatia_de_antecipacao: float = 0.25

## Quanto a estocada avança, em metros.
@export var avanco: float = 0.55
## Quanto o giro roda, em voltas.
@export var voltas: float = 1.0
## Quanto o salto sobe, em metros.
@export var altura_do_salto: float = 0.7

@export_group("Clipes do esqueleto")
## Clipe do ataque básico.
##
## O auto-ataque era a única ação do jogo sem gesto nenhum — o personagem batia
## e não mexia um dedo. É a `estocada`, que é o mesmo gesto das habilidades que
## saem para a frente: no original o golpe básico é clipe PRÓPRIO de campeão, e
## clipe próprio é exatamente o que o nosso vocabulário resolve por forma.
##
## **Era uma lista de dois, alternada, e os dois nomes eram do Royal Crown** —
## `swing` e `swing2`, herdados da pasta de assets que foi removida. Nenhum dos
## dois existia no nosso arquivo, e como `tocar` falhava calado, o
## comportamento visível era o mesmo de não haver gesto nenhum.
@export var clipe_de_ataque: StringName = VocabularioDeAnimacao.ESTOCADA

## Clipe do deslocamento, tocado quando o corpo é de fato empurrado.
##
## Disparar no APERTO da tecla não bastava: entre conjurar e sair do lugar há a
## janela de conjuração, e a animação terminava antes de o personagem se mexer.
## Quem sabe a hora certa é o próprio deslocamento.
##
## Era `SALTO` (`Jump_Full_Short`), e dash não sobe: lia como pulo. `ESQUIVA`
## é verbo do vocabulário ESTENDIDO — num corpo que não o fala, `Boneco.tocar`
## resolve a reserva universal dele (o salto, de novo) sozinho.
@export var clipe_de_deslocamento: StringName = (
	VocabularioDeAnimacao.Estendido.ESQUIVA
)

## Que clipe toca em cada gesto de habilidade.
##
## **É dado, não código** — a regra 5 do `CLAUDE.md`. Os nomes saem de
## `VocabularioDeAnimacao`, que é a única lista que `conferir_numeros.py`
## compara com o `.glb` exportado: nome escrito à mão aqui volta a ser um nome
## que ninguém confere.
@export var clipes_por_gesto: Dictionary = {
	Gesto.ESTOCADA: VocabularioDeAnimacao.ESTOCADA,
	Gesto.GIRO: VocabularioDeAnimacao.GIRO,
	Gesto.SALTO: VocabularioDeAnimacao.SALTO,
	Gesto.ERGUER: VocabularioDeAnimacao.ERGUER,
	Gesto.PREPARO: VocabularioDeAnimacao.PREPARO,
	Gesto.ARREMESSO: VocabularioDeAnimacao.ARREMESSO,
	Gesto.EMPURRAO: VocabularioDeAnimacao.Estendido.EMPURRAO,
}

## Os dois elos da corrente de golpes, alternados.
##
## Uma habilidade com VÁRIOS pulsos de golpe (o Q do Leo: dois cones, a 0,27 e
## 0,55 s) tocava um gesto único no aperto da tecla — e a segunda marca nascia
## na tela com o corpo já parado, que é como "bate duas vezes" vira "desenhou
## errado". Agora cada momento de golpe toca um elo, na hora em que o pulso
## SAI — a hora vem do `resolved` do `AbilityCaster`, nunca de um relógio
## próprio desta camada (regra 3 do `CLAUDE.md`).
@export var elos_de_golpe: Array[StringName] = [
	VocabularioDeAnimacao.Estendido.GOLPE_A,
	VocabularioDeAnimacao.Estendido.GOLPE_B,
]

## Abaixo desta velocidade o personagem está parado, e conjura o gesto normal.
##
## Acima dela ele conjura **em movimento**, e aí quem desenha é `throw_f` ou
## `throw_b` — o corpo de cima do arremesso sobre as pernas que continuam
## correndo. É a estrutura do original: os três `throw` são universais, e os
## clipes próprios de campeão vêm por cima deles.
@export var velocidade_para_conjurar_andando: float = 0.15

## O corpo articulado, quando existe. Com ele, o gesto move BRAÇO e PERNA;
## sem ele, move a malha inteira — que foi o que travou o teste do usuário,
## porque mover o corpo todo lê como empurrão e não como golpe.
var _boneco: Boneco
var _malha: Node3D

## O combatente dono do corpo — é dele que sai a cadência do ataque.
var _combatente: Node = null

## Verdadeiro quando o gesto em curso é de ATAQUE BÁSICO, e não de habilidade.
##
## A distinção existe porque andar cancela um e não o outro: no esquema do
## LoL, mover-se durante o golpe básico corta a animação e o corpo volta a
## correr, mas o gesto de uma habilidade é a telegrafia dela — cortá-lo
## apagaria exatamente o que o jogador precisa ler.
var _de_ataque: bool = false
var _caster: AbilityCaster
var _base_posicao: Vector3
var _base_escala: Vector3
var _gesto: Gesto = Gesto.ESTOCADA
var _restante: float = 0.0
var _total: float = 0.0

## A corrente de golpes armada: id da habilidade, quantos momentos de golpe
## faltam e o delay do último elo tocado — pulsos que saem no MESMO instante
## são um golpe só, e é o delay que os agrupa.
var _golpes_da_habilidade: StringName = &""
var _golpes_restantes: int = 0
var _elo: int = 0
var _delay_do_ultimo_elo: float = -1.0

func _ready() -> void:
	_boneco = _achar_boneco()
	_combatente = _achar_irmao("Combatant")
	if _combatente != null:
		if _combatente.has_signal("atacou"):
			_combatente.connect("atacou", _ao_atacar)
		if _combatente.has_signal("displaced"):
			_combatente.connect("displaced", _ao_deslocar)
	_malha = _achar_malha()
	if _boneco != null:
		_malha = _boneco
	if _malha == null:
		push_warning("GestoDeConjuracao sem corpo em '%s'." % get_parent().name)
		return
	_base_posicao = _malha.position
	_base_escala = _malha.scale

	_caster = _achar_caster()
	if _caster != null:
		_caster.cast_attempted.connect(_ao_conjurar)
		# É por aqui que a corrente de golpes sabe A HORA de cada elo: o
		# pulso atrasado emite `resolved` quando SAI, e o gesto acompanha o
		# dado em vez de manter um relógio paralelo que dessincronizaria.
		_caster.resolved.connect(_ao_resolver)

## O golpe básico saiu: o corpo bate — NO RITMO da cadência.
##
## O clipe do pack é mais lento que a cadência de vários campeões (a Bella
## bate a cada 0,43 s num clipe de ~1 s), e tocá-lo em velocidade natural
## produzia o que o usuário reportou em 26/08: *"o boneco alvo sofre dano
## várias vezes enquanto a primeira animação de atack básico ainda nem
## terminou"* — e o dano parecia sair antes de a espada encostar, porque o
## contato visual do clipe ficava muito depois do tick. O dano continua
## saindo no tick, como no original (o censo mediu: nenhum clipe de combate
## de lá tem evento de animação); o que muda é o golpe visual caber no
## intervalo entre dois ticks.
func _ao_atacar() -> void:
	# Sem esqueleto, o ataque usa o mesmo gesto de estocada das habilidades.
	_gesto = Gesto.ESTOCADA
	_de_ataque = true
	if _tocar_no_ritmo_do_ataque():
		return
	_total = duracao
	_restante = _total

## O clipe do golpe básico DESTE corpo: quem empunha besta dispara, quem
## empunha lâmina estoca. Quem sabe a arma é o `Boneco`, que vestiu o
## equipamento do campeão — perguntar a ele é o que faz a Bella atirar sem
## esta camada conhecer campeão nenhum.
func _clipe_do_ataque() -> StringName:
	if _boneco != null and _boneco.ataque_e_disparo():
		return VocabularioDeAnimacao.Estendido.DISPARO
	return clipe_de_ataque

## Toca o clipe de ataque acelerado para caber no intervalo da cadência.
## Devolve se tocou.
func _tocar_no_ritmo_do_ataque() -> bool:
	if _boneco == null or _boneco.animador() == null:
		return false
	var roda: RodaDeAnimacao = _achar_roda()
	if roda != null and roda.esta_mostrando():
		return false
	var clipe: StringName = _clipe_do_ataque()
	var do_clipe: float = _boneco.duracao_de(clipe)
	if do_clipe <= 0.0:
		return false
	# Nunca DESacelerar: clipe mais rápido que a cadência vira pausa entre
	# golpes, que é como o ataque lento deve ler.
	var velocidade: float = maxf(do_clipe / _intervalo_do_ataque(), 1.0)
	if not _boneco.tocar(clipe, true, velocidade):
		return false
	_total = maxf(do_clipe / velocidade, 0.05)
	_restante = _total
	return true

## Segundos entre dois ataques básicos deste corpo. `duracao` quando não há
## como saber — que é o comportamento de antes.
func _intervalo_do_ataque() -> float:
	if _combatente == null:
		return duracao
	var unidade: Variant = _combatente.get("unit")
	if unidade == null:
		return duracao
	return maxf(unidade.attack_interval(), 0.05)

## Andar cancela o golpe básico — e SÓ ele.
##
## `GestoDeCaminhada` chama isto quando o corpo se move com um gesto em
## curso. Habilidade não é cancelada: o gesto dela é a telegrafia, e é
## exatamente o que o jogador está tentando ler.
func cancelar_ataque_em_movimento() -> void:
	if not _de_ataque or _restante <= 0.0:
		return
	_repousar()


## O corpo foi deslocado: a animação de investida acompanha o deslocamento em
## vez de acontecer antes dele.
func _ao_deslocar(_offset: Vector3) -> void:
	_tocar(clipe_de_deslocamento)


## Toca um clipe do esqueleto e SEGURA o corpo pelo tempo dele. Devolve se
## tocou.
##
## **Segurar é metade do trabalho.** `GestoDeCaminhada` reescreve a animação a
## cada quadro, e sem `esta_gesticulando()` verdadeiro o clipe de ataque vivia
## exatamente um quadro antes de a caminhada retomar o corpo. Quem sabe quanto
## tempo segurar é o próprio clipe — daí `duracao_de`, e não um número escrito
## aqui que envelheceria junto com a animação.
func _tocar(clipe: StringName) -> bool:
	if _boneco == null or _boneco.animador() == null or clipe == &"":
		return false
	# Com a roda de animação ligada, o jogador está olhando um clipe.
	var roda: RodaDeAnimacao = _achar_roda()
	if roda != null and roda.esta_mostrando():
		return false
	if not _boneco.tocar(clipe, true):
		return false
	_total = maxf(_boneco.duracao_de(clipe), 0.05)
	_restante = _total
	return true


func _achar_irmao(classe: String) -> Node:
	var host: Node = get_parent()
	if host == null:
		return null
	for filho: Node in host.get_children():
		if filho.get_class() == classe or filho.name == classe:
			return filho
	return null


## Verdadeiro enquanto um gesto de conjuração está em curso.
##
## `GestoDeCaminhada` consulta isto para dar passagem: sobrepor as duas
## animações faz o braço tremer no meio do golpe, e o golpe é a informação que
## o jogador está tentando ler.
func esta_gesticulando() -> bool:
	return _restante > 0.0

func _process(delta: float) -> void:
	if _malha == null or _restante <= 0.0:
		return
	_restante -= delta
	if _restante <= 0.0:
		_repousar()
		return
	# `t` vai de 0 (começo) a 1 (fim).
	_aplicar(1.0 - _restante / _total)

# ---------------------------------------------------------------- gatilho

func _ao_conjurar(
		_slot: AbilityBook.Slot, pedida: Ability, result: CastResult
) -> void:
	if _malha == null or pedida == null or result == null:
		return
	# Recusa não anima: o personagem não fez nada, e fingir que fez é mentir
	# para quem está tentando entender o que aconteceu.
	if not (result.succeeded() or result.started()):
		return

	# Gesto de habilidade não é cancelável por movimento — ver `_de_ataque`.
	_de_ataque = false
	var saiu: Ability = result.ability if result.ability != null else pedida
	_gesto = Gesto.PREPARO if result.started() else _gesto_para(saiu)
	# Conjurar ANDANDO tem clipe próprio, é universal no original — e GANHA da
	# corrente de golpes: `throw_f`/`throw_b` são a conjuração em movimento dos
	# 32 campeões (§5 de `docs/11`), e `sondar_ritmo.gd` confere a regra.
	var em_movimento: StringName = _clipe_em_movimento()
	_armar_corrente_de_golpes(saiu if em_movimento == &"" else null)
	if _golpes_restantes > 0 and not result.started():
		# Habilidade de VÁRIOS golpes: nenhum gesto único agora. O corpo arma
		# a postura e fica seguro até o último elo; cada elo toca quando o
		# pulso dele SAI — `_ao_resolver`, com a hora vinda do motor. A
		# postura é o `parado`, e não sobra do clipe anterior: o que estivesse
		# tocando viraria a cara da habilidade por 0,27 s.
		if _boneco != null:
			_boneco.tocar(VocabularioDeAnimacao.PARADO)
		_total = maxf(_prazo_da_corrente(saiu), 0.05)
		_restante = _total
		return
	# Com esqueleto, o gesto vira CLIPE. O nome sai do mesmo `_gesto` que o
	# corpo de caixas usa, para os dois caminhos concordarem sobre o que a
	# habilidade parece.
	var clipe: StringName = StringName(clipes_por_gesto.get(_gesto, &""))
	if em_movimento != &"" and not result.started():
		clipe = em_movimento
	var tocou: bool = _tocar(clipe)
	# O gesto de uma conjuração com tempo dura o tempo dela: é ele que avisa
	# que algo vem vindo, e avisar por um terço de segundo não avisa nada.
	#
	# **A conjuração com tempo ganha do clipe**, e só ela: `_tocar` já tinha
	# ajustado a janela para a duração do `preparo`, mas o que o jogador precisa
	# ver é o corpo junto até o canto terminar. A Godot estica o clipe pelo
	# tempo de conjuração.
	if result.started() or not tocou:
		_total = maxf(saiu.cast_time if result.started() else duracao, 0.05)
		_restante = _total

## O clipe de conjurar em MOVIMENTO, ou vazio se o personagem está parado.
##
## Frente ou atrás sai do sinal de `velocidade · frente`: quem se afasta do
## lado para onde olha está recuando, e é `throw_b` que desenha isso. No
## original as duas variantes existem nos 32 campeões e duram exatamente um
## ciclo de corrida — o corpo de cima é sobreposto às pernas, e um comprimento
## diferente faria o passo saltar no meio do arremesso (§5 de `docs/11`).
##
## **A conjuração com tempo não usa isto**: quem está canalizando fica parado,
## e o `preparo` é o aviso de que algo vem.
func _clipe_em_movimento() -> StringName:
	var corpo: CharacterBody3D = get_parent() as CharacterBody3D
	if corpo == null:
		return &""
	var plana := Vector3(corpo.velocity.x, 0.0, corpo.velocity.z)
	if plana.length() < velocidade_para_conjurar_andando:
		return &""
	var frente: Vector3 = -corpo.global_transform.basis.z
	frente.y = 0.0
	if plana.dot(frente) >= 0.0:
		return VocabularioDeAnimacao.ARREMESSO_A_FRENTE
	return VocabularioDeAnimacao.ARREMESSO_ATRAS


# ------------------------------------------------------- corrente de golpes

## Verdadeiro para um pulso frontal de golpe: forma de lâmina, com efeito, e
## que não desloca ninguém — deslocamento tem gesto próprio (o dash desenha a
## si; o empurrão é `EMPURRAO`).
static func _e_pulso_de_golpe(pulse: AbilityPulse) -> bool:
	if pulse == null or pulse.effects.is_empty():
		return false
	match pulse.form:
		AbilityPulse.Form.CONE, AbilityPulse.Form.LINE, \
		AbilityPulse.Form.TRAPEZOID:
			pass
		_:
			return false
	for efeito: AbilityEffect in pulse.effects:
		if efeito is DisplacementEffect:
			return false
	return true

## Os INSTANTES de golpe de uma habilidade: os delays distintos dos pulsos de
## golpe, em ordem. Dois pulsos no mesmo instante são um golpe só — um corpo
## não bate duas vezes ao mesmo tempo.
static func _momentos_de_golpe(ability: Ability) -> Array[float]:
	var momentos: Array[float] = []
	for pulse: AbilityPulse in ability.pulses:
		if not _e_pulso_de_golpe(pulse):
			continue
		var momento: float = maxf(pulse.delay, 0.0)
		var novo: bool = true
		for visto: float in momentos:
			if absf(visto - momento) < 0.01:
				novo = false
		if novo:
			momentos.append(momento)
	momentos.sort()
	return momentos

## Arma a corrente quando a habilidade tem DOIS ou mais instantes de golpe.
## Genérico pelos delays dos pulsos, não por campeão: qualquer habilidade do
## corpus com essa estrutura ganha a alternância de graça.
func _armar_corrente_de_golpes(ability: Ability) -> void:
	_golpes_restantes = 0
	_golpes_da_habilidade = &""
	_elo = 0
	_delay_do_ultimo_elo = -1.0
	# Sem esqueleto não há elo para tocar: o corpo de caixas fica com o gesto
	# único de sempre.
	if ability == null or _boneco == null or _boneco.animador() == null:
		return
	var momentos: Array[float] = _momentos_de_golpe(ability)
	if momentos.size() < 2:
		return
	_golpes_da_habilidade = ability.id
	_golpes_restantes = momentos.size()

## Quanto segurar o corpo: do aperto da tecla até o fim do clipe do último
## elo. O instante do último golpe vem dos pulsos; a duração do elo, do clipe.
func _prazo_da_corrente(ability: Ability) -> float:
	var momentos: Array[float] = _momentos_de_golpe(ability)
	var ultimo: float = 0.0
	if not momentos.is_empty():
		ultimo = momentos[momentos.size() - 1]
	var clipe: StringName = &""
	if not elos_de_golpe.is_empty():
		clipe = elos_de_golpe[0]
	return ultimo + maxf(_boneco.duracao_de(clipe), 0.05)

## Um resultado saiu do motor. Se a corrente está armada e o pulso é de golpe,
## toca o próximo elo — é assim que o segundo cone do Q do Leo ganha um corpo
## batendo no instante em que a marca dele nasce.
func _ao_resolver(result: CastResult) -> void:
	if _golpes_restantes <= 0 or result == null or result.ability == null:
		return
	if result.ability.id != _golpes_da_habilidade:
		return
	if result.pulse != null:
		_tocar_elo(result.pulse)
		return
	for parte: CastResult in result.parts:
		if parte != null and parte.pulse != null:
			_tocar_elo(parte.pulse)

func _tocar_elo(pulse: AbilityPulse) -> void:
	if _golpes_restantes <= 0 or not _e_pulso_de_golpe(pulse):
		return
	var momento: float = maxf(pulse.delay, 0.0)
	# Pulsos do MESMO instante dividem o elo — ver `_momentos_de_golpe`.
	if _delay_do_ultimo_elo >= 0.0 and absf(momento - _delay_do_ultimo_elo) < 0.01:
		return
	_delay_do_ultimo_elo = momento
	_golpes_restantes -= 1
	if elos_de_golpe.is_empty():
		return
	var clipe: StringName = elos_de_golpe[_elo % elos_de_golpe.size()]
	_elo += 1
	_de_ataque = false
	_gesto = Gesto.ESTOCADA
	_tocar(clipe)

## Que gesto cabe a esta habilidade.
##
## Decidido pelo PRIMEIRO pulso com efeito, que é o golpe que o jogador
## associa ao aperto da tecla. `match` explícito e não tabela: valor novo em
## `Form` não compila até ser tratado aqui.
static func _gesto_para(ability: Ability) -> Gesto:
	for pulse: AbilityPulse in ability.pulses:
		if pulse == null or pulse.effects.is_empty():
			continue
		for efeito: AbilityEffect in pulse.effects:
			if efeito is DisplacementEffect:
				# Quem é movido decide o gesto: `CASTER` é o dash — o corpo
				# vai —, `TARGETS` é empurrão ou puxão — o corpo BATE. O R do
				# Leo empurra os outros e saía desenhado como pulo.
				if efeito.recipient == AbilityEffect.Recipient.CASTER:
					return Gesto.SALTO
				return Gesto.EMPURRAO
		match pulse.form:
			AbilityPulse.Form.CIRCLE:
				# Área em volta de quem conjura gira; área plantada longe é
				# um gesto de arremesso, que aqui lê como estocada.
				return (
					Gesto.GIRO if pulse.origin == AbilityPulse.Origin.CASTER
					else Gesto.ESTOCADA
				)
			AbilityPulse.Form.LINE, AbilityPulse.Form.CONE, \
			AbilityPulse.Form.TRAPEZOID:
				return Gesto.ESTOCADA
			AbilityPulse.Form.PROJECTILE:
				return Gesto.ARREMESSO
			_:
				return Gesto.ERGUER
	return Gesto.ERGUER

# ---------------------------------------------------------------- desenho

## O peso do gesto em `t`: negativo na antecipação, sobe até 1 na ação, volta a
## zero na recuperação.
func _peso(t: float) -> float:
	if t < fatia_de_antecipacao:
		# Antecipação: recua um pouco, e acelera para trás.
		var a: float = t / maxf(fatia_de_antecipacao, 0.001)
		return -0.28 * sin(a * PI * 0.5)
	var b: float = (t - fatia_de_antecipacao) / maxf(1.0 - fatia_de_antecipacao, 0.001)
	# Ação e recuperação: sobe depressa e desce devagar.
	return sin(pow(b, 0.45) * PI)

func _aplicar(t: float) -> void:
	var peso: float = _peso(t)
	# **Com esqueleto, quem desenha o golpe é o clipe** — `_ao_conjurar` já o
	# disparou. Empurrar o nó por cima seria desenhar duas vezes: o personagem
	# faria a estocada do original E deslizaria junto, que foi exatamente o
	# "boneco se tremendo de lado" que o usuário reportou.
	if _boneco != null and _boneco.animador() != null:
		return
	# Com membros, o gesto move BRAÇO e PERNA. Sem eles — malha externa
	# inteiriça, sem esqueleto —, move o corpo todo, que é o que dá para fazer.
	if _boneco != null and _boneco.tem_membros():
		_aplicar_nos_membros(peso)
		return
	var frente: Vector3 = -global_frente()
	match _gesto:
		Gesto.ESTOCADA, Gesto.ARREMESSO, Gesto.EMPURRAO:
			# Sem esqueleto os dois avançam o corpo: é o que dá para separar
			# num corpo inteiriço, e o corpo inteiriço é o caminho de quem não
			# gerou `arte/personagem.glb`.
			_malha.position = _base_posicao + frente * avanco * peso
			_malha.scale = _base_escala * Vector3(
				1.0 - 0.12 * peso, 1.0 + 0.10 * peso, 1.0 - 0.12 * peso
			)
		Gesto.GIRO:
			_malha.rotation.y = TAU * voltas * maxf(peso, 0.0)
			_malha.scale = _base_escala * (1.0 + 0.08 * peso)
		Gesto.SALTO:
			_malha.position = _base_posicao + Vector3.UP * altura_do_salto * maxf(peso, 0.0)
			_malha.scale = _base_escala * Vector3(
				1.0 - 0.15 * peso, 1.0 + 0.18 * peso, 1.0 - 0.15 * peso
			)
		Gesto.ERGUER:
			_malha.position = _base_posicao + Vector3.UP * 0.30 * peso
			_malha.scale = _base_escala * Vector3(
				1.0 + 0.10 * peso, 1.0 + 0.22 * peso, 1.0 + 0.10 * peso
			)
		_:
			# PREPARO: encolhe e se agacha enquanto o canto corre. `peso` aqui
			# fica negativo quase o tempo todo, e é de propósito — o corpo se
			# junta antes de soltar.
			var junta: float = 0.18 * (1.0 - t)
			_malha.scale = _base_escala * Vector3(
				1.0 + junta, 1.0 - junta, 1.0 + junta
			)
			_malha.position = _base_posicao - Vector3.UP * junta * 0.5

## O gesto nos MEMBROS. É o que separa "o personagem golpeou" de "o personagem
## foi empurrado" — e era essa diferença que faltava.
func _aplicar_nos_membros(peso: float) -> void:
	_boneco.repousar()
	match _gesto:
		Gesto.ESTOCADA, Gesto.ARREMESSO, Gesto.EMPURRAO:
			# O braço da frente sobe e desce como quem golpeia; o de trás
			# contrabalança, que é o que dá peso ao movimento.
			_boneco.braco_direito.rotation_degrees.x = -150.0 * peso
			_boneco.braco_esquerdo.rotation_degrees.x = 40.0 * peso
			_boneco.tronco.rotation_degrees.x = -18.0 * peso
			_boneco.quadril.position.z = -0.35 * peso
		Gesto.GIRO:
			# Os dois braços abertos e o corpo rodando: o gesto de quem varre
			# o que está em volta.
			_boneco.quadril.rotation_degrees.y = 360.0 * voltas * maxf(peso, 0.0)
			_boneco.braco_direito.rotation_degrees.z = -80.0 * maxf(peso, 0.0)
			_boneco.braco_esquerdo.rotation_degrees.z = 80.0 * maxf(peso, 0.0)
		Gesto.SALTO:
			_boneco.quadril.position.y = (
				_boneco.altura * 0.42 - _boneco.altura * 0.5
				+ altura_do_salto * maxf(peso, 0.0)
			)
			# Joelhos recolhidos no ar; esticados na antecipação.
			_boneco.perna_direita.rotation_degrees.x = 55.0 * maxf(peso, 0.0)
			_boneco.perna_esquerda.rotation_degrees.x = 55.0 * maxf(peso, 0.0)
			_boneco.braco_direito.rotation_degrees.x = -60.0 * maxf(peso, 0.0)
			_boneco.braco_esquerdo.rotation_degrees.x = -60.0 * maxf(peso, 0.0)
		Gesto.ERGUER:
			# Braços ao alto: o gesto de quem chama algo de cima.
			_boneco.braco_direito.rotation_degrees.x = -170.0 * maxf(peso, 0.0)
			_boneco.braco_esquerdo.rotation_degrees.x = -170.0 * maxf(peso, 0.0)
			_boneco.quadril.position.y += 0.22 * peso
			_boneco.tronco.rotation_degrees.x = 12.0 * peso
		_:
			# PREPARO: agacha e recolhe os braços enquanto o canto corre.
			var junta: float = 0.45 * (1.0 - _restante / maxf(_total, 0.001))
			_boneco.quadril.position.y -= 0.18 * junta
			_boneco.perna_direita.rotation_degrees.x = 25.0 * junta
			_boneco.perna_esquerda.rotation_degrees.x = 25.0 * junta
			_boneco.braco_direito.rotation_degrees.x = -35.0 * junta
			_boneco.braco_esquerdo.rotation_degrees.x = -35.0 * junta

func _repousar() -> void:
	_restante = 0.0
	if _boneco != null and _boneco.tem_membros():
		_boneco.repousar()
		return
	_malha.position = _base_posicao
	_malha.scale = _base_escala
	_malha.rotation.y = 0.0

## A frente do corpo, no plano do chão. `-basis.z` é a convenção da Godot.
func global_frente() -> Vector3:
	var corpo: Node3D = get_parent() as Node3D
	if corpo == null:
		return Vector3.FORWARD
	var frente: Vector3 = corpo.global_transform.basis.z
	frente.y = 0.0
	if frente.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return frente.normalized()

func _achar_roda() -> RodaDeAnimacao:
	var host: Node = get_parent()
	if host == null:
		return null
	for filho: Node in host.get_children():
		if filho is RodaDeAnimacao:
			return filho as RodaDeAnimacao
	return null

func _achar_boneco() -> Boneco:
	var host: Node = get_parent()
	if host == null:
		return null
	for child: Node in host.get_children():
		if child is Boneco:
			return child as Boneco
	return null

func _achar_malha() -> Node3D:
	var host: Node = get_parent()
	if host == null:
		return null
	for child: Node in host.get_children():
		# O `FrontMarker` que já foi excluído por nome aqui saiu da cena em
		# 26/08/2026: o modelo da decisão 25 mostra a frente sozinho, e o
		# usuário apontou o cone vermelho como ruído.
		if child is MeshInstance3D:
			return child as Node3D
	return null

func _achar_caster() -> AbilityCaster:
	var host: Node = get_parent()
	if host == null:
		return null
	for child: Node in host.get_children():
		if child is AbilityCaster:
			return child
	return null
