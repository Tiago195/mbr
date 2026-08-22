class_name SummonEffect
extends AbilityEffect

## SUMMON — põe uma criatura, torreta ou armadilha no mundo.
##
## Estava no vocabulário de `03-sistemas-de-jogo.md` e não existia. O original
## usa em 100 impactos (`SummonActorId` + `SummonPersistTime`): lobo, totem,
## bomba com prazo, parede.
##
## Não invoca nada. **Pede.** `core/` não instancia cena — o mesmo contrato do
## deslocamento, e pelo mesmo motivo: quem sabe checar se o chão está livre é
## a camada que tem física. A fila fica em `Unit.pending_summons` e é
## consumida por quem tem árvore de cena.
##
## O destinatário quase sempre é `CASTER`: quem invoca é quem conjurou, e o
## invocado aparece perto dele. Com `TARGETS`, a invocação nasce em cima de
## cada atingido — que é como se expressa "planta uma marca em cada inimigo".

## Identificador da criatura no catálogo de invocações. Nome, não número:
## quem lê o `.tres` precisa entender do que se trata sem consultar tabela.
@export var actor_id: StringName = &""

## Segundos de vida. 0 = permanente, e permanente numa partida de battle
## royale quer dizer "até morrer".
@export var lifetime: float = 10.0

## De onde a invocação nasce.
enum Origin {
	## No ponto mirado. É o caso da armadilha e da parede.
	AIM_POINT,
	## Colada em quem recebe o efeito.
	RECIPIENT,
	## Colada no conjurador, mesmo quando o efeito cai em outro.
	CASTER,
}

@export var origin: Origin = Origin.AIM_POINT

## Deslocamento na direção da mira, a partir da origem escolhida. Serve para a
## parede que nasce à frente em vez de em cima dos pés.
@export var forward_offset: float = 0.0

## Time da invocação. Vazio herda o de quem conjurou — que é o certo em
## praticamente todo caso, e o campo existe para o resto.
@export var inherits_caster_team: bool = true
@export var explicit_team: int = 0

func apply(cast: AbilityCast, target: Unit) -> void:
	if target == null or actor_id.is_empty():
		return
	var request := Unit.SummonRequest.new()
	request.actor_id = actor_id
	request.lifetime = lifetime
	request.position = _origin_point(cast, target) + cast.direction * forward_offset
	request.team = cast.caster.team if \
		(inherits_caster_team and cast.caster != null) else explicit_team

	# A fila é de quem CONJUROU, não de quem recebeu o efeito. Sem isto, uma
	# invocação com destinatário TARGETS ficaria pendurada no inimigo, e quem
	# consome a fila é o dono do combatente — o inimigo materializaria a
	# invocação do adversário.
	var owner: Unit = cast.caster if cast.caster != null else target
	owner.pending_summons.append(request)

func _origin_point(cast: AbilityCast, target: Unit) -> Vector3:
	match origin:
		Origin.RECIPIENT:
			return target.position
		Origin.CASTER:
			return cast.caster.position if cast.caster != null else target.position
		_:
			return cast.point

## Uma invocação no ponto mirado não precisa acertar ninguém — o mesmo caso do
## dash. Só a que nasce em cima do alvo depende de haver alvo.
func needs_target() -> bool:
	return origin == Origin.RECIPIENT and recipient == Recipient.TARGETS

func describe() -> String:
	if lifetime <= 0.0:
		return "invoca %s" % actor_id
	return "invoca %s por %.0fs" % [actor_id, lifetime]
