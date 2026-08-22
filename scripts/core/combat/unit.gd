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

## Que espécie de combatente é. Existe porque a tradução do original topou com
## três regras que dependem disso e não do time: `MaxPhysicalDamageForMonster`
## (teto de dano contra mob neutro), `SiegeDamage` (dano só contra estrutura) e
## o fato de invocação não contar como abate. Sem isto, cada uma dessas viraria
## uma checagem improvisada no lugar errado.
enum Nature {
	## Campeão. Conta como abate, sofre dano normal.
	CHAMPION,
	## Mob neutro. O original limita quanto uma habilidade pode tirar deles,
	## para que farmar não vire o caminho mais rápido de escalar.
	MONSTER,
	## Estrutura, barril, porta. Só sofre dano marcado como de cerco.
	STRUCTURE,
	## Torreta invocada, lobo, totem. Some quando o prazo acaba.
	SUMMON,
}

## Uma invocação pedida e ainda não materializada. Mesmo desenho de
## `pending_displacement`: `core/` não instancia cena, então pede e a camada de
## gameplay atende.
class SummonRequest extends RefCounted:
	var actor_id: StringName = &""
	var position: Vector3 = Vector3.ZERO
	var lifetime: float = 0.0
	var team: int = 0

var team: int = 0
var nature: Nature = Nature.CHAMPION
var stats: Stats
var health: Health
var status: StatusSet
## Mana. Vale 0 de máximo para quem não usa recurso, e aí tudo é de graça.
var mana: ResourcePool
## Venenos, regenerações e auras ativas.
var periodic: PeriodicSet
## Efeitos armados esperando um evento.
var triggers: TriggerSet

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

## Invocações pedidas e ainda não materializadas.
var pending_summons: Array[SummonRequest] = []

func _init(unit_stats: Stats = null, unit_team: int = 0) -> void:
	stats = unit_stats if unit_stats != null else Stats.new()
	team = unit_team
	health = Health.new(stats)
	status = StatusSet.new()
	mana = ResourcePool.new(stats)
	periodic = PeriodicSet.new()
	triggers = TriggerSet.new()

# ---------------------------------------------------------------- estado

func is_alive() -> bool:
	return health.is_alive()

func is_hostile_to(other: Unit) -> bool:
	return other != null and other.team != team

## Cada regra abaixo lista os controles que a impedem. O critério para um
## controle entrar numa lista e não noutra é comportamento, não tema — a
## tabela de equivalência com os 13 tipos do original está em `StatusSet`.

const _BLOCKS_MOVE: Array[StatusSet.Kind] = [
	StatusSet.Kind.STUN, StatusSet.Kind.ROOT, StatusSet.Kind.AIRBORNE,
]

## CHARM e POLYMORPH desarmam; TAUNT não — quem foi provocado ataca, e é
## justamente isso que o torna perigoso perto de quem provocou.
const _BLOCKS_ATTACK: Array[StatusSet.Kind] = [
	StatusSet.Kind.STUN, StatusSet.Kind.DISARM, StatusSet.Kind.AIRBORNE,
	StatusSet.Kind.CHARM, StatusSet.Kind.POLYMORPH,
]

const _BLOCKS_CAST: Array[StatusSet.Kind] = [
	StatusSet.Kind.STUN, StatusSet.Kind.SILENCE, StatusSet.Kind.AIRBORNE,
	StatusSet.Kind.CHARM, StatusSet.Kind.TAUNT, StatusSet.Kind.POLYMORPH,
]

func can_move() -> bool:
	return is_alive() and not status.has_any(_BLOCKS_MOVE)

func can_attack() -> bool:
	return is_alive() and not status.has_any(_BLOCKS_ATTACK)

func can_cast() -> bool:
	return is_alive() and not status.has_any(_BLOCKS_CAST)

## Verdadeiro quando a ordem de quem joga ainda vale. Falso sob atordoamento,
## arremesso, encanto ou provocação — nesses a camada de gameplay deve parar
## de obedecer ao clique, não só travar o corpo.
func has_agency() -> bool:
	return is_alive() and not status.has_any(StatusSet.LOSES_CONTROL)

## Cegueira: o ataque básico sai e erra. Fica separado de `can_attack()` de
## propósito — o personagem gasta a cadência do ataque do mesmo jeito, e é
## isso que diferencia cegar de desarmar.
func attacks_miss() -> bool:
	return status.has(StatusSet.Kind.BLIND)

## Imune a dano. Separado de `is_alive()` porque um alvo invulnerável continua
## sendo alvo válido: a habilidade acerta, os controles pegam, só o dano é
## anulado.
func is_invulnerable() -> bool:
	return status.has(StatusSet.Kind.INVULNERABLE)

## Só campeão conta para abate, colocação e a condição de vitória. Invocação
## morta não elimina ninguém, e mob neutro não é jogador derrotado.
func counts_as_kill() -> bool:
	return nature == Nature.CHAMPION

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
	if attacks_miss():
		var missed := DamageResult.new()
		missed.raw_damage = stats.get_value(Stat.Id.ATTACK_DAMAGE)
		missed.missed = true
		missed.health_after = target.health.current
		missed.shield_after = target.health.shield
		return missed
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
	if is_invulnerable():
		var blocked := DamageResult.new()
		blocked.raw_damage = raw_damage
		blocked.health_after = health.current
		blocked.shield_after = health.shield
		damaged.emit(blocked)
		return blocked

	var attacker_stats: Stats = attacker.stats if attacker != null else null
	var had_shield: bool = health.shield > 0.0
	var result: DamageResult = Damage.resolve(
		attacker_stats, stats, health.current, health.shield,
		raw_damage, type, source
	)
	health.apply(result)
	if attacker != null and result.lifesteal_healed > 0.0:
		# Sem `healer`: roubo de vida não é cura conjurada, e não deve ser
		# multiplicado de novo pelo poder de cura de quem bateu.
		attacker.receive_heal(result.lifesteal_healed)
	damaged.emit(result)

	# Os gatilhos saem DEPOIS do dano estar aplicado. Um gatilho que cure em
	# resposta precisa ver a vida já reduzida, senão a cura seria desperdiçada
	# no teto e o dano cairia por cima.
	if not result.missed:
		triggers.fire(TriggerSet.Event.DAMAGE_TAKEN, self, attacker)
		if had_shield and health.shield <= 0.0:
			triggers.fire(TriggerSet.Event.SHIELD_BROKEN, self, attacker)
		if attacker != null:
			attacker.triggers.fire(_hit_event(source), attacker, self)
			if result.killed and counts_as_kill():
				attacker.triggers.fire(TriggerSet.Event.KILL, attacker, self)
	return result

static func _hit_event(source: Damage.Source) -> TriggerSet.Event:
	if source == Damage.Source.ABILITY:
		return TriggerSet.Event.ABILITY_HIT
	return TriggerSet.Event.BASIC_ATTACK_HIT

## Recebe cura. `healer` pode ser nulo — regeneração e cura de item não têm
## autor.
##
## Dois multiplicadores, e são coisas diferentes: `heal_power` é de quem cura,
## `heal_received_amp` é de quem recebe. Separá-los é o que permite existir um
## debuff de "cura reduzida" — o antídoto clássico contra composição de time
## que só se sustenta — sem enfraquecer o curandeiro para todo mundo.
func receive_heal(amount: float, healer: Unit = null) -> float:
	# Nome diferente do sinal `healed` de propósito: variável local com o mesmo
	# nome o sombrearia, e `healed.emit()` deixaria de compilar.
	var scaled: float = amount
	if healer != null:
		scaled *= 1.0 + healer.stats.get_value(Stat.Id.HEAL_POWER)
	scaled *= 1.0 + stats.get_value(Stat.Id.HEAL_RECEIVED_AMP)
	var restored: float = health.heal(maxf(scaled, 0.0))
	if restored > 0.0:
		healed.emit(restored)
		triggers.fire(TriggerSet.Event.HEALED, self, healer)
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
	mana.advance_time(delta)
	# Periódicos e gatilhos por último: os dois podem causar dano ou cura, e
	# devem ver o estado do tique já atualizado.
	periodic.advance_time(delta, self)
	triggers.advance_time(delta, self)

## Entrega o deslocamento acumulado e zera o acumulador.
func consume_displacement() -> Vector3:
	var value: Vector3 = pending_displacement
	pending_displacement = Vector3.ZERO
	return value

## Entrega as invocações pedidas e esvazia a fila. Mesmo contrato do
## deslocamento: quem tem cena materializa, `core/` só pede.
func consume_summons() -> Array[SummonRequest]:
	var requests: Array[SummonRequest] = pending_summons
	pending_summons = []
	return requests
