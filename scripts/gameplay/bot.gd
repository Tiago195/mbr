class_name Mob
extends CharacterBody3D

## A primeira OPOSIÇÃO do jogo: um mob que percebe, persegue, bate e morre.
##
## Espelha o laço de combate de `player.gd` (`_pursue_and_attack`) sem a camada
## de input: em vez de um clique dizer quem é o alvo, um raio de percepção diz.
## A cadência continua onde sempre esteve — no `Unit` —, e este nó só pergunta
## `attack_is_ready()`, exatamente como o jogador faz. Nenhuma regra de combate
## mora aqui.
##
## Quem decide o COMPORTAMENTO é o perfil do original: `SpawnerDeMobs` traduz
## `ActorProfile.ai_profile` (a `AIPath` guardada e até agora sem consumidor)
## para `agressivo`, e os atributos entram por `Combatant.adopt_profile` — os
## exports do Inspector ficam de piso para o que o perfil não declara, que é o
## caso do `attack_range` de todos os mobs.
##
## Morte: sai da camada de colisão (o mesmo que `training_dummy.gd` faz) e o
## corpo some depois de `sumir_apos`. Renascer é instância NOVA, de propósito:
## `GestoDeReacao._morto` nunca volta, e um corpo reaproveitado ficaria
## deitado para sempre.

## Distância de chegada ao voltar para o ponto de spawn. O mesmo papel do
## `arrival_threshold` do jogador.
const ARRIVAL_THRESHOLD: float = 0.2

## Falso = não caça: só revida quando apanha. É o `playernonaggressive` do
## original; o `playeraggressive` liga isto em verdadeiro.
@export var agressivo: bool = true

## Raio de percepção em metros. Zero usa o atributo `SIGHT_RANGE` do perfil —
## que todo mob do original declara (`sight_range`, 98 dos 99). O export
## existe para sobrepor em teste sem mexer no catálogo.
@export var raio_de_percepcao: float = 0.0

## A que distância do ponto de spawn o mob desiste, larga o alvo e volta.
## Sem leash, um mob agressivo seguiria o jogador pelo mapa inteiro.
@export var raio_de_desistencia: float = 14.0

## Segundos entre morrer e o corpo sumir da cena.
@export var sumir_apos: float = 3.0

## Velocidade de quem não declara `move_speed` no perfil. O mesmo papel do
## `speed` do jogador.
@export var speed: float = 3.0

## O ponto ao qual o leash amarra. Capturado no `_ready` — por isso o spawner
## posiciona o corpo ANTES de o pôr na árvore. Público porque a sonda de ritmo
## teleporta o mob para perto do jogador e precisa levar a âncora junto.
var origem: Vector3

var _combatant: Combatant
var _target: Combatant = null

## Voltando ao spawn depois de desistir. Enquanto volta, não caça — sem isto,
## reperceber o jogador no caminho de volta viraria um vaivém infinito na
## borda do leash.
var _voltando: bool = false

var _morto: bool = false
var _sumir_restante: float = 0.0

func _ready() -> void:
	_combatant = Combatant.of(self)
	if _combatant == null:
		push_warning("Mob sem Combatant em '%s'." % name)
		set_physics_process(false)
		return
	_combatant.ensure_ready()
	origem = global_position
	_combatant.died.connect(_ao_morrer)
	_combatant.damaged.connect(_ao_levar_dano)

func _physics_process(delta: float) -> void:
	if _morto:
		_sumir_restante -= delta
		if _sumir_restante <= 0.0:
			queue_free()
		return

	# Alvo que morreu ou sumiu deixa de ser alvo — o mesmo que `player.gd` faz,
	# e pelo mesmo motivo: bater em cadáver.
	if _target != null and (not is_instance_valid(_target) or not _target.is_alive()):
		_target = null

	# Leash: longe demais de casa, desiste e volta.
	if _target != null and _distancia_no_chao(origem) > raio_de_desistencia:
		_target = null
		_voltando = true

	if _voltando:
		_voltar()
		move_and_slide()
		return

	if _target == null and agressivo:
		_target = _percebido(_raio_de_percepcao())

	if _target != null:
		_pursue_and_attack()
	else:
		velocity = Vector3.ZERO
	move_and_slide()

# ---------------------------------------------------------------- percepção

## O hostil vivo mais próximo dentro do raio, ou nulo. Varre o mesmo grupo que
## a resolução de habilidade varre — aceitável nesta escala, e vira o grid
## espacial da Fase 4.6 junto com o resto (ver `Combatant.all_units`).
func _percebido(raio: float) -> Combatant:
	var mais_perto: Combatant = null
	var menor: float = raio
	for no: Node in get_tree().get_nodes_in_group(Combatant.GROUP):
		var outro := no as Combatant
		if outro == null or outro == _combatant or not outro.is_alive():
			continue
		if not _combatant.is_hostile_to(outro):
			continue
		var distancia: float = _combatant.ground_distance_to(outro)
		if distancia <= menor:
			menor = distancia
			mais_perto = outro
	return mais_perto

## O raio que vale agora: o export quando sobreposto, senão o `SIGHT_RANGE`
## do perfil.
func _raio_de_percepcao() -> float:
	if raio_de_percepcao > 0.0:
		return raio_de_percepcao
	return _combatant.stats.get_value(Stat.Id.SIGHT_RANGE)

## Apanhou: revida, mesmo o mob pacífico. `DamageResult` não diz QUEM bateu —
## de propósito, ele é o pacote da camada visual —, então a revanche vai no
## hostil mais próximo dentro do leash, que num duelo é quem bateu.
func _ao_levar_dano(resultado: DamageResult) -> void:
	if _morto or _voltando or _target != null:
		return
	if resultado.missed:
		return
	_target = _percebido(raio_de_desistencia)

# ---------------------------------------------------------------- movimento

## Espelho de `Player._pursue_and_attack`: encarar, andar se fora do alcance,
## senão parar e bater quando a cadência vencer.
func _pursue_and_attack() -> void:
	var corpo_do_alvo: Node3D = _target.body()
	if corpo_do_alvo == null:
		_target = null
		velocity = Vector3.ZERO
		return

	var ate_o_alvo: Vector3 = corpo_do_alvo.global_position - global_position
	ate_o_alvo.y = 0.0
	_face(ate_o_alvo)

	if ate_o_alvo.length() > _combatant.stats.get_value(Stat.Id.ATTACK_RANGE):
		velocity = ate_o_alvo.normalized() * _speed()
		return

	velocity = Vector3.ZERO
	# `basic_attack` é quem recomeça a cadência. Aqui só se pergunta se venceu.
	if _combatant.unit.attack_is_ready():
		_combatant.basic_attack(_target)

func _voltar() -> void:
	var ate_casa: Vector3 = origem - global_position
	ate_casa.y = 0.0
	if ate_casa.length() <= ARRIVAL_THRESHOLD:
		velocity = Vector3.ZERO
		_voltando = false
		return
	velocity = ate_casa.normalized() * _speed()
	_face(ate_casa)

## Passo por segundo — do perfil quando ele declara, do export quando não.
## O mesmo desenho de `Player._speed`.
func _speed() -> float:
	var do_perfil: float = _combatant.stats.get_value(Stat.Id.MOVE_SPEED)
	return do_perfil if do_perfil > 0.0 else speed

func _distancia_no_chao(ponto: Vector3) -> float:
	var delta: Vector3 = ponto - global_position
	delta.y = 0.0
	return delta.length()

## A mesma guarda de `Player._face`: `look_at` emite erro quando o alvo
## coincide com a própria posição.
func _face(direction: Vector3) -> void:
	if direction.length_squared() <= 0.000001:
		return
	look_at(global_position + direction, Vector3.UP)

# ---------------------------------------------------------------- morte

func _ao_morrer() -> void:
	_morto = true
	_target = null
	_voltando = false
	velocity = Vector3.ZERO
	# Fora da camada dos combatentes: cadáver não bloqueia passagem nem é
	# mirado — o mesmo que o boneco de treino faz ao morrer.
	collision_layer = 0
	_sumir_restante = sumir_apos
