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
## Fase 6, Meshy e Mixamo —, a cápsula anima **por procedimento**: é como os
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
	# O gesto de uma conjuração com tempo dura o tempo dela: é ele que avisa
	# que algo vem vindo, e avisar por um terço de segundo não avisa nada.
	_total = maxf(saiu.cast_time if result.started() else duracao, 0.05)
	_restante = _total

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
				return Gesto.ESTOCADA
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
	# Com membros, o gesto move BRAÇO e PERNA. Sem eles — malha externa
	# inteiriça, sem esqueleto —, move o corpo todo, que é o que dá para fazer.
	if _boneco != null and _boneco.tem_membros():
		_aplicar_nos_membros(peso)
		return
	var frente: Vector3 = -global_frente()
	match _gesto:
		Gesto.ESTOCADA:
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
		Gesto.ESTOCADA:
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
