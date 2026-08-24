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
@export var clipe_de_deslocamento: StringName = VocabularioDeAnimacao.SALTO

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
}

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
var _caster: AbilityCaster
var _base_posicao: Vector3
var _base_escala: Vector3
var _gesto: Gesto = Gesto.ESTOCADA
var _restante: float = 0.0
var _total: float = 0.0

func _ready() -> void:
	_boneco = _achar_boneco()
	var combatente: Node = _achar_irmao("Combatant")
	if combatente != null:
		if combatente.has_signal("atacou"):
			combatente.connect("atacou", _ao_atacar)
		if combatente.has_signal("displaced"):
			combatente.connect("displaced", _ao_deslocar)
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

## O golpe básico saiu: o corpo bate.
func _ao_atacar() -> void:
	# Sem esqueleto, o ataque usa o mesmo gesto de estocada das habilidades.
	_gesto = Gesto.ESTOCADA
	if _tocar(clipe_de_ataque):
		return
	_total = duracao
	_restante = _total


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

	var saiu: Ability = result.ability if result.ability != null else pedida
	_gesto = Gesto.PREPARO if result.started() else _gesto_para(saiu)
	# Com esqueleto, o gesto vira CLIPE. O nome sai do mesmo `_gesto` que o
	# corpo de caixas usa, para os dois caminhos concordarem sobre o que a
	# habilidade parece.
	var clipe: StringName = StringName(clipes_por_gesto.get(_gesto, &""))
	# Conjurar ANDANDO tem clipe próprio, e é universal no original.
	var em_movimento: StringName = _clipe_em_movimento()
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
				return Gesto.SALTO
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
		Gesto.ESTOCADA, Gesto.ARREMESSO:
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
		Gesto.ESTOCADA, Gesto.ARREMESSO:
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
		# O marcador da frente é filho separado e NÃO entra: ele existe para
		# mostrar para onde o personagem olha, e girá-lo junto apagaria essa
		# informação justamente durante o gesto.
		if child is MeshInstance3D and child.name != "FrontMarker":
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
