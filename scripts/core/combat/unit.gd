class_name Unit
extends RefCounted

## Um combatente completo, sem engine — Fase 3.1.
##
## Junta atributos, vida, controles de grupo e posição num objeto só. Existe
## porque efeito de habilidade precisa de tudo isso e **não pode** depender de
## nó: o servidor headless resolve habilidade sem árvore de cena, e o teste
## unitário também.
##
## `Combatant` (em `gameplay/`) passa a ser a ponte: possui um `Unit`,
## sincroniza a posição com o corpo e repassa os sinais para a camada visual.
## Regra que isso preserva: **a lógica decide, o nó observa**.

signal damaged(result: DamageResult)
signal healed(amount: float)

## NÃO existe um `signal died` aqui, e a ausência é deliberada.
##
## Repassá-lo exigiria `health.died.connect(func(): died.emit())`, e esse lambda
## faz o `Health` guardar uma referência de volta ao `Unit` que o possui. Dois
## `RefCounted` apontando um para o outro nunca chegam a contagem zero: a Godot
## não coleta ciclos. O sintoma é "ObjectDB instances were leaked at exit" e
## cada combatente morto ficando na memória para sempre.
##
## Quem quer saber da morte conecta em `unit.health.died` — uma referência só,
## na direção que já existe.

var team: int = 0
var stats: Stats
var health: Health
var status: StatusSet

## Posição no mundo. Quem tem corpo mantém isto sincronizado a cada tick;
## em teste, é só um Vector3.
var position: Vector3 = Vector3.ZERO

## Direção que o combatente encara. Usada por forma de cone e por habilidade
## de alvo DIRECTION quando não há mira explícita.
var facing: Vector3 = Vector3.FORWARD

## Deslocamento pedido por efeito de dash/knockback, ainda não aplicado.
## A camada de gameplay consome isto e move o corpo com colisão — resolver
## colisão aqui exigiria conhecer a física, que é justamente o que esta classe
## evita.
var pending_displacement: Vector3 = Vector3.ZERO

func _init(unit_stats: Stats = null, unit_team: int = 0) -> void:
	stats = unit_stats if unit_stats != null else Stats.new()
	team = unit_team
	health = Health.new(stats)
	status = StatusSet.new()

# ---------------------------------------------------------------- estado

func is_alive() -> bool:
	return health.is_alive()

func is_hostile_to(other: Unit) -> bool:
	return other != null and other.team != team

func can_move() -> bool:
	return is_alive() \
		and not status.has(StatusSet.Kind.STUN) \
		and not status.has(StatusSet.Kind.ROOT)

func can_attack() -> bool:
	return is_alive() \
		and not status.has(StatusSet.Kind.STUN) \
		and not status.has(StatusSet.Kind.DISARM)

func can_cast() -> bool:
	return is_alive() \
		and not status.has(StatusSet.Kind.STUN) \
		and not status.has(StatusSet.Kind.SILENCE)

## Distância no plano do chão. Altura ignorada de propósito: alcance num MOBA
## é medido no chão, senão alvo em rampa ficaria fora de alcance sem motivo
## visível.
func ground_distance_to(other: Unit) -> float:
	return ground_distance_to_point(other.position)

func ground_distance_to_point(point: Vector3) -> float:
	var delta: Vector3 = point - position
	delta.y = 0.0
	return delta.length()

# ---------------------------------------------------------------- combate

## Ataque básico. Usa `attack_damage`, tipo físico, fonte de ataque básico —
## e portanto pode crititar e devolve `lifesteal`.
func basic_attack(target: Unit) -> DamageResult:
	return target.receive_damage(
		self,
		stats.get_value(Stat.Id.ATTACK_DAMAGE),
		Damage.Type.PHYSICAL,
		Damage.Source.BASIC_ATTACK
	)

## Recebe dano já com a situação montada. `attacker` pode ser nulo — dano de
## zona não tem dono.
func receive_damage(
		attacker: Unit,
		raw_damage: float,
		type: Damage.Type,
		source: Damage.Source
) -> DamageResult:
	var attacker_stats: Stats = attacker.stats if attacker != null else null
	var result: DamageResult = Damage.resolve(
		attacker_stats, stats, health.current, health.shield,
		raw_damage, type, source
	)
	health.apply(result)
	if attacker != null and result.lifesteal_healed > 0.0:
		attacker.receive_heal(result.lifesteal_healed)
	damaged.emit(result)
	return result

func receive_heal(amount: float) -> float:
	# Nome diferente do sinal `healed` de propósito: variável local com o mesmo
	# nome o sombrearia, e `healed.emit()` deixaria de compilar.
	var restored: float = health.heal(amount)
	if restored > 0.0:
		healed.emit(restored)
	return restored

## Segundos entre ataques básicos.
func attack_interval() -> float:
	return 1.0 / maxf(stats.get_value(Stat.Id.ATTACK_SPEED), 0.01)

# ---------------------------------------------------------------- tempo

## Avança tudo que expira: modificadores temporários, controles de grupo e
## camadas de escudo. Chamado pelo tick do servidor — um ponto só, para não
## haver estado que envelhece e estado que não.
func advance_time(delta: float) -> void:
	stats.advance_time(delta)
	status.advance_time(delta)
	health.advance_time(delta)

## Entrega o deslocamento acumulado e zera o acumulador.
func consume_displacement() -> Vector3:
	var value: Vector3 = pending_displacement
	pending_displacement = Vector3.ZERO
	return value
