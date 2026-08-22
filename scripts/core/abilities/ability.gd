class_name Ability
extends Resource

## Uma habilidade declarada como dado — Fase 3.2.
##
## Nada aqui é comportamento: é a combinação de peças de um vocabulário
## fechado. Habilidade nova deve ser um `.tres` novo, sem uma linha de código
## de sistema. Se uma habilidade exigir classe nova, o sistema está errado —
## generalize antes de continuar (`03-sistemas-de-jogo.md`).
##
## Nomes dos enums escolhidos para não colidir com classe embutida da Godot:
## `Form` e não `Shape`, `Aim` e não `Target`. Ver a armadilha registrada em
## `CLAUDE.md`.

## Como o jogador aponta.
enum Aim {
	## Sem mira. Age no próprio conjurador.
	SELF,
	## Um ponto do chão.
	POINT,
	## Uma direção a partir do conjurador.
	DIRECTION,
	## Um combatente escolhido a dedo.
	UNIT,
}

## A região que efetivamente atinge.
enum Form {
	## Só o alvo apontado, sem área.
	SINGLE,
	## Círculo centrado no ponto mirado.
	CIRCLE,
	## Setor circular a partir do conjurador.
	CONE,
	## Retângulo a partir do conjurador, na direção mirada.
	LINE,
	## Como LINE, mas quem resolve o voo é a camada de gameplay.
	## Aqui só se calcula quem o projétil atingiria.
	PROJECTILE,
}

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Ativação")
## Segundos de recarga, antes de redução de recarga.
@export var cooldown: float = 6.0
## Segundos parado antes do efeito sair. 0 = instantânea.
@export var cast_time: float = 0.0
## Se falso, conjurar prende o personagem no lugar.
@export var can_move_while_casting: bool = false
## Se falso, nem o próprio jogador cancela depois de começar.
@export var cancelable: bool = true

@export_group("Alvo")
@export var aim: Aim = Aim.POINT
## Distância máxima do ponto ou alvo mirado. 0 = sem limite.
@export var cast_range: float = 8.0

@export_group("Forma")
@export var form: Form = Form.CIRCLE
## CIRCLE e PROJECTILE.
@export var radius: float = 2.5
## CONE, LINE e PROJECTILE.
@export var length: float = 8.0
## LINE e PROJECTILE.
@export var width: float = 1.5
## CONE. Ângulo total de abertura, em graus.
@export var cone_angle: float = 60.0
## PROJECTILE. Metros por segundo — só a camada visual usa.
@export var projectile_speed: float = 18.0
## PROJECTILE. Se falso, para no primeiro atingido.
@export var pierces: bool = false

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

## Recarga já com a redução do conjurador aplicada.
func cooldown_for(caster: Unit) -> float:
	if caster == null:
		return cooldown
	var reduction: float = clampf(
		caster.stats.get_value(Stat.Id.COOLDOWN_REDUCTION), 0.0, 0.9
	)
	return cooldown * (1.0 - reduction)

## Verdadeiro quando todo efeito depende de acertar alguém.
func requires_target() -> bool:
	for effect: AbilityEffect in effects:
		if effect != null and not effect.needs_target():
			return false
	return not effects.is_empty()

## Verdadeiro quando não acertar ninguém deve RECUSAR a conjuração, em vez de
## gastá-la.
##
## Só vale para alvo único: aí não há comando a emitir, e recusar é o certo.
##
## Skillshot — POINT e DIRECTION — **gasta mesmo errando**. Errar é parte do
## jogo, e devolver a recarga de quem errou tornaria mira irrelevante. Isto já
## foi ao contrário: habilidade instantânea era devolvida e habilidade com
## tempo de conjuração não, porque a recarga da segunda começa ao iniciar.
## Dois comportamentos para a mesma situação, sem motivo.
func refuses_without_target() -> bool:
	return aim == Aim.UNIT and requires_target()

## Se um projétil que não atravessa, o teto de alvos é 1 por construção.
func effective_max_targets() -> int:
	if form == Form.PROJECTILE and not pierces:
		return 1
	return max_targets

func describe() -> String:
	var parts: PackedStringArray = []
	for effect: AbilityEffect in effects:
		if effect != null:
			parts.append(effect.describe())
	return "%s [%s/%s] %s" % [
		display_name if not display_name.is_empty() else String(id),
		Aim.keys()[aim].to_lower(),
		Form.keys()[form].to_lower(),
		", ".join(parts),
	]
