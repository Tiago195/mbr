class_name AbilityPulse
extends Resource

## Um golpe dentro de uma habilidade — a peça que a tradução do original
## provou faltar.
##
## Até aqui, `Ability` tinha **uma** forma, **um** filtro e **uma** lista de
## efeitos. Isso cobre "meteoro cai num círculo" e não cobre nada do que o
## original faz de interessante: uma `Skill` de lá referencia até 12 `Impact`,
## e cada impacto tem tempo, posição, raio e alvos próprios. Um impacto ainda
## pode encadear outro, com geometria e tempo próprios. Depois de traduzido,
## **416 das habilidades do original têm mais de um pulso**.
##
## Sem esta peça, traduzir uma habilidade de vários golpes obrigaria a
## escolher entre descartar impactos ou fundi-los num só — e fundir está
## errado: o segundo golpe de uma investida sai meio segundo depois, num raio
## menor, e só pega quem ficou.
##
## Com ela, "corta na frente, depois explode em volta de mim" é um `.tres` com
## dois pulsos, sem uma linha de código novo. Que é a regra do projeto.

## A região que efetivamente atinge. Mora aqui e não em `Ability` porque cada
## pulso tem a sua: o primeiro golpe pode ser uma linha e o segundo um círculo.
enum Form {
	## Só o alvo apontado, sem área.
	SINGLE,
	## Círculo centrado na âncora.
	CIRCLE,
	## Setor circular a partir da âncora.
	CONE,
	## Retângulo a partir da âncora, na direção mirada.
	LINE,
	## Como LINE, mas quem resolve o voo é a camada de gameplay.
	## Aqui só se calcula quem o projétil atingiria.
	PROJECTILE,
	## Retângulo de largura variável, começando e terminando a distâncias
	## diferentes. É o `CastTrapezoid` do original — o cone de tiro que não
	## encosta nos próprios pés e alarga com a distância.
	TRAPEZOID,
}

## Onde a forma se ancora. É o `StartPosition` do original.
enum Origin {
	## No conjurador. O padrão de cone, linha e projétil.
	CASTER,
	## No ponto mirado. O padrão de círculo.
	AIM_POINT,
	## Em cima do alvo apontado. Cai no ponto mirado se não houver alvo.
	TARGET_UNIT,
	## Onde o pulso anterior se ancorou. É o `ParentImpactPosition`, e é o que
	## permite "explode onde a flecha parou" sem a habilidade precisar saber
	## onde ela parou.
	PREVIOUS,
}

@export var form: Form = Form.CIRCLE
@export var origin: Origin = Origin.AIM_POINT

@export_group("Tempo")
## Segundos depois do fim da conjuração até este pulso sair. 0 = imediato.
## É o `StartTime` do original.
@export var delay: float = 0.0

## Segundos que a área fica ativa reaplicando. 0 = golpe único.
@export var duration: float = 0.0

## Segundos entre reaplicações enquanto a área dura. Só vale com `duration`.
@export var loop_interval: float = 0.0

@export_group("Geometria")
## CIRCLE e PROJECTILE.
@export var radius: float = 2.5
## CONE, LINE, PROJECTILE e TRAPEZOID (comprimento total).
@export var length: float = 8.0
## LINE e PROJECTILE.
@export var width: float = 1.5
## CONE. Ângulo total de abertura, em graus.
@export var cone_angle: float = 60.0
## PROJECTILE. Metros por segundo — só a camada visual usa.
@export var projectile_speed: float = 18.0
## PROJECTILE. Se falso, para no primeiro atingido.
@export var pierces: bool = false

@export_group("Deslocamento da âncora")
## Metros à frente, na direção da mira. `StartPositionZ` do original, diferente
## de zero em 293 impactos: é a explosão que nasce um pouco adiante dos pés, e
## sem isso ela nasce em cima deles.
@export var forward_offset: float = 0.0
## Metros para o lado, **positivo à direita** de quem conjura. `StartPositionX`,
## em 28 impactos — o golpe que sai da mão direita.
##
## Mirando para -Z, que é a frente na convenção da Godot, a direita é +X:
## `frente.cross(UP)` de (0,0,-1) dá (1,0,0).
@export var side_offset: float = 0.0

@export_group("Trapézio")
## Distância onde o trapézio começa. Antes disso, não pega ninguém.
@export var near_distance: float = 1.0
@export var near_width: float = 1.0
@export var far_width: float = 4.0

@export_group("Filtro")
@export var hits_enemies: bool = true
@export var hits_allies: bool = false
@export var hits_self: bool = false
## Teto de alvos atingidos, dos mais próximos para os mais distantes.
## 0 = sem teto.
@export var max_targets: int = 0

@export_group("Efeitos")
## Aplicados em ordem a cada alvo.
@export var effects: Array[AbilityEffect] = []

## Onde a forma se planta. `previous` é a âncora do pulso anterior — quem
## encadeia é a engine, porque só ela conhece a ordem.
func anchor_for(cast: AbilityCast, previous: Vector3) -> Vector3:
	return _base_anchor(cast, previous) + _offset(cast)

func _base_anchor(cast: AbilityCast, previous: Vector3) -> Vector3:
	match origin:
		Origin.CASTER:
			return cast.caster.position if cast.caster != null else previous
		Origin.TARGET_UNIT:
			return cast.unit_target.position if cast.unit_target != null else cast.point
		Origin.PREVIOUS:
			return previous
		_:
			return cast.point

## Frente é a direção da mira; lado é perpendicular a ela, no plano do chão.
## Sem deslocamento declarado, devolve zero e nada muda — o caso de 1376 dos
## 1602 impactos de `impact_xml`, e de 1403 dos 1687 pulsos traduzidos.
func _offset(cast: AbilityCast) -> Vector3:
	if is_zero_approx(forward_offset) and is_zero_approx(side_offset):
		return Vector3.ZERO
	var frente: Vector3 = Vector3(cast.direction.x, 0.0, cast.direction.z)
	if frente.length_squared() <= 0.000001:
		frente = Vector3.FORWARD
	frente = frente.normalized()
	var lado: Vector3 = frente.cross(Vector3.UP)
	return frente * forward_offset + lado * side_offset

## Se um projétil que não atravessa, o teto de alvos é 1 por construção.
func effective_max_targets() -> int:
	if form == Form.PROJECTILE and not pierces:
		return 1
	return max_targets

## Verdadeiro quando todo efeito deste pulso depende de acertar alguém.
func requires_target() -> bool:
	for effect: AbilityEffect in effects:
		if effect != null and not effect.needs_target():
			return false
	return not effects.is_empty()

## Quantas vezes este pulso sai no total, contando a primeira.
##
## Área que dura 4s com intervalo de 1s bate 5 vezes: no instante 0 e nos
## quatro intervalos. É a convenção que casa com o original, onde
## `ActiveDuration` conta a partir do primeiro tique.
func repeat_count() -> int:
	if duration <= 0.0 or loop_interval <= 0.0:
		return 1
	return 1 + int(floor(duration / loop_interval))

func describe() -> String:
	var parts: PackedStringArray = []
	for effect: AbilityEffect in effects:
		if effect != null:
			parts.append(effect.describe())
	var when: String = "" if delay <= 0.0 else "+%.2fs " % delay
	return "%s[%s] %s" % [when, Form.keys()[form].to_lower(), ", ".join(parts)]
