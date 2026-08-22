class_name Zone
extends RefCounted

## A zona que fecha — Fase 5.3.
##
## Lógica pura: um círculo no plano do chão que encolhe em fases, e dano por
## segundo a quem estiver fora. Não conhece nó, não desenha, não consulta
## física. O servidor headless roda isto igual ao cliente.
##
## O modelo é o de battle royale consagrado, que o Royal Crown também usava:
## cada fase tem um tempo de **aviso** — em que o próximo círculo já está
## visível mas a zona ainda não se move — e um tempo de **encolhimento**, em
## que ela viaja do círculo atual até o próximo.
##
## Separar os dois é o que dá ao jogador a decisão que define o gênero:
## rotacionar agora e ceder posição, ou ficar e pagar dano.

signal phase_started(index: int)
signal shrink_started(index: int)
signal finished()

enum State {
	## Antes da primeira fase.
	IDLE,
	## Próximo círculo anunciado, zona parada.
	WARNING,
	## Zona viajando até o próximo círculo.
	SHRINKING,
	## Todas as fases concluídas.
	DONE,
}

## Uma fase da zona. Declarada como dado — os números virão de
## `magnetic_field_xml` do original quando forem extraídos.
class Phase extends RefCounted:
	var radius: float
	var center: Vector3
	var warning_time: float
	var shrink_time: float
	## Dano por segundo a quem está fora, durante esta fase.
	var damage_per_second: float

	func _init(
			p_radius: float,
			p_center: Vector3,
			p_warning: float,
			p_shrink: float,
			p_dps: float
	) -> void:
		radius = p_radius
		center = p_center
		warning_time = p_warning
		shrink_time = p_shrink
		damage_per_second = p_dps

var state: State = State.IDLE

## Círculo atual, interpolado durante o encolhimento.
var center: Vector3 = Vector3.ZERO
var radius: float = 0.0

# `Array` sem tipo, e não `Array[Phase]`: tipar array por classe interna é
# terreno instável em GDScript, e um erro de parse aqui derrubaria a suíte
# inteira por um detalhe de sintaxe.
var _phases: Array = []
var _index: int = -1
var _elapsed: float = 0.0
var _from_center: Vector3 = Vector3.ZERO
var _from_radius: float = 0.0

func _init(phases: Array = []) -> void:
	_phases = phases

# ---------------------------------------------------------------- consulta

func phase_count() -> int:
	return _phases.size()

func current_phase() -> Phase:
	if _index < 0 or _index >= _phases.size():
		return null
	return _phases[_index]

func phase_index() -> int:
	return _index

## Dano por segundo a quem está fora, na fase atual. 0 quando parada.
func damage_per_second() -> float:
	var fase: Phase = current_phase()
	return fase.damage_per_second if fase != null else 0.0

## Segundos restantes do estágio atual — aviso ou encolhimento.
func time_remaining() -> float:
	var fase: Phase = current_phase()
	if fase == null:
		return 0.0
	match state:
		State.WARNING:
			return maxf(0.0, fase.warning_time - _elapsed)
		State.SHRINKING:
			return maxf(0.0, fase.shrink_time - _elapsed)
		_:
			return 0.0

## O próximo círculo, para o cliente desenhar o alvo da rotação. Nulo na
## última fase.
func next_phase() -> Phase:
	if _index + 1 >= _phases.size():
		return null
	return _phases[_index + 1]

## Distância no plano do chão. Altura ignorada, como em todo o resto do
## projeto.
func contains(point: Vector3) -> bool:
	return ground_distance(point) <= radius

func ground_distance(point: Vector3) -> float:
	var delta: Vector3 = point - center
	delta.y = 0.0
	return delta.length()

## Quanto o ponto está para fora da borda. 0 quando dentro.
func distance_outside(point: Vector3) -> float:
	return maxf(0.0, ground_distance(point) - radius)

# ---------------------------------------------------------------- ciclo

## Começa a primeira fase. A zona nasce com o raio da fase inicial.
func start() -> void:
	if _phases.is_empty():
		state = State.DONE
		finished.emit()
		return
	_index = 0
	_elapsed = 0.0
	state = State.WARNING
	var fase: Phase = _phases[0]
	center = fase.center
	radius = fase.radius
	_from_center = center
	_from_radius = radius
	phase_started.emit(_index)

## Avança o relógio da zona. Chamado pelo tick do servidor.
func advance_time(delta: float) -> void:
	if state == State.IDLE or state == State.DONE:
		return

	_elapsed += delta
	var fase: Phase = current_phase()

	if state == State.WARNING:
		if _elapsed < fase.warning_time:
			return
		# Sobra do aviso entra no encolhimento, senão um tick longo comeria
		# tempo de jogo.
		_elapsed -= fase.warning_time
		state = State.SHRINKING
		_from_center = center
		_from_radius = radius
		shrink_started.emit(_index)

	if state != State.SHRINKING:
		return

	var alvo: Phase = next_phase()
	if alvo == null:
		# Última fase: não há para onde encolher.
		state = State.DONE
		finished.emit()
		return

	if fase.shrink_time <= 0.0:
		_apply_shrink(alvo, 1.0)
	else:
		_apply_shrink(alvo, clampf(_elapsed / fase.shrink_time, 0.0, 1.0))

	if _elapsed < fase.shrink_time:
		return

	# Chegou. Passa para a próxima fase levando a sobra junto.
	_elapsed -= fase.shrink_time
	_index += 1
	center = alvo.center
	radius = alvo.radius
	if _index >= _phases.size() - 1:
		state = State.DONE
		finished.emit()
		return
	state = State.WARNING
	phase_started.emit(_index)

func _apply_shrink(alvo: Phase, progresso: float) -> void:
	center = _from_center.lerp(alvo.center, progresso)
	radius = lerpf(_from_radius, alvo.radius, progresso)

# ---------------------------------------------------------------- dano

## Aplica o dano da zona a quem está fora. Devolve quantos foram atingidos.
##
## O dano é **verdadeiro** e sem dono: zona ignora armadura e resistência —
## senão o tanque poderia morar fora dela — e não devolve roubo de vida a
## ninguém.
func damage_outsiders(units: Array, delta: float) -> int:
	var dps: float = damage_per_second()
	if dps <= 0.0 or state == State.IDLE:
		return 0

	var atingidos: int = 0
	for candidato: Variant in units:
		var unit := candidato as Unit
		if unit == null or not unit.is_alive():
			continue
		if contains(unit.position):
			continue
		unit.receive_damage(
			null, dps * delta, Damage.Type.TRUE, Damage.Source.ENVIRONMENT
		)
		atingidos += 1
	return atingidos
