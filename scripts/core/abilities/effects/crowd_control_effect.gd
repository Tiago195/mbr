class_name CrowdControlEffect
extends AbilityEffect

## CROWD_CONTROL — atordoar, prender, silenciar, desarmar, cegar, encantar,
## provocar, arremessar, transformar e reduzir velocidade.
##
## Os estados booleanos vão para o `StatusSet`. O **slow** não: ele é um
## modificador percentual de `move_speed`, aplicado pelo mesmo sistema dos
## itens. Lentidão É um atributo reduzido por um tempo — modelá-la como estado
## próprio duplicaria a lógica de acúmulo e de expiração sem ganhar nada.
##
## O vocabulário do doc lista slow junto dos outros, então ele continua sendo
## uma opção deste efeito. A diferença é só de implementação.
##
## O original tem 13 tipos em `crowd_control_xml` e nós temos 11 opções aqui
## (dez estados mais `SLOW`, que é modificador de atributo): a
## tabela de equivalência, com o que virou o quê e por quê, está em
## `docs/10-traducao-do-original.md`.

## NÃO chamar este enum de `Control`: é o nome de uma classe embutida da Godot
## (o nó de UI), e `@export var control: Control` resolveria para ela em vez de
## para o enum. O erro aparece como "cannot be assigned to a variable of type
## Control", que não sugere colisão de nome nenhuma.
##
## Inclui SLOW, que `StatusSet.Kind` não tem — lentidão vira modificador de
## atributo, não estado. Valor novo entra no FIM: isto é exportado para `.tres`
## como inteiro.
enum Kind {
	STUN,
	ROOT,
	SILENCE,
	DISARM,
	SLOW,
	BLIND,
	CHARM,
	TAUNT,
	## Arremesso ao ar. Costuma vir acompanhado de um `DisplacementEffect` na
	## mesma habilidade — aqui só entra o estado, o empurrão é do outro efeito.
	AIRBORNE,
	POLYMORPH,
	## Imune a dano. Não é controle — é o oposto — mas vive aqui pelo mesmo
	## motivo que vive em `StatusSet`: é um estado booleano com prazo, e um
	## segundo caminho para aplicá-lo seria duplicação.
	##
	## Faltava, e a falta era pior que uma lacuna: o tradutor emitia
	## `INVULNERABLE`, a fábrica não reconhecia, caía no padrão, e "fica
	## invulnerável 1,6s" virava "fica atordoado 1,6s" — no próprio conjurador.
	## Silêncio que inverte o sentido é o pior tipo de silêncio.
	INVULNERABLE,
}

@export var control: Kind = Kind.STUN
@export var duration: float = 1.0

## Só para SLOW. 0.3 = 30% mais lento.
@export_range(0.0, 1.0) var slow_amount: float = 0.3

## Ignora a tenacidade do alvo. É o que o original marca como `HardStun`, e o
## que faz sentido para arremesso: um controle que a build defensiva não
## encurta é o que garante que o time com muita tenacidade ainda possa ser
## pego. Use com parcimônia — é justamente o que não tem contrajogo.
@export var ignores_tenacity: bool = false

@export var source_tag: StringName = &"habilidade"

func apply(_cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return
	if control == Kind.SLOW:
		_apply_slow(target)
		return
	target.status.apply(_status_kind(), _reduced_duration(target))

## Lentidão passa por `slow_resist`, não por tenacidade. São coisas separadas
## no original (`SlowResist` e `Toughness` são atributos distintos) e faz
## sentido: resistir a lentidão é de bota, resistir a atordoamento é de elmo.
##
## `slow_resist` corta a INTENSIDADE, não a duração — 50% de resistência
## transforma uma lentidão de 40% numa de 20%, e não numa de 40% que dura
## metade. É a leitura que casa com `StatValue` ser a intensidade lá.
func _apply_slow(target: Unit) -> void:
	var resist: float = clampf(target.stats.get_value(Stat.Id.SLOW_RESIST), 0.0, 1.0)
	var amount: float = slow_amount * (1.0 - resist)
	if amount <= 0.0:
		return
	target.stats.add_modifier(StatModifier.new(
		Stat.Id.MOVE_SPEED, StatModifier.Kind.PERCENT, -amount,
		&"slow:%s" % source_tag, duration
	))

## Tenacidade encurta o controle duro. Teto de 0.8 pelo mesmo motivo do teto
## de recarga: imunidade completa a controle não é um estado que o jogo deva
## alcançar por acúmulo de item.
func _reduced_duration(target: Unit) -> float:
	# Invulnerabilidade é benefício, não controle: tenacidade do ALVO cortá-la
	# seria punir quem se defende de controle por se defender de dano.
	if ignores_tenacity or control == Kind.INVULNERABLE:
		return duration
	var tenacity: float = clampf(target.stats.get_value(Stat.Id.TENACITY), 0.0, 0.8)
	return duration * (1.0 - tenacity)

func _status_kind() -> StatusSet.Kind:
	match control:
		Kind.ROOT:
			return StatusSet.Kind.ROOT
		Kind.SILENCE:
			return StatusSet.Kind.SILENCE
		Kind.DISARM:
			return StatusSet.Kind.DISARM
		Kind.BLIND:
			return StatusSet.Kind.BLIND
		Kind.CHARM:
			return StatusSet.Kind.CHARM
		Kind.TAUNT:
			return StatusSet.Kind.TAUNT
		Kind.AIRBORNE:
			return StatusSet.Kind.AIRBORNE
		Kind.POLYMORPH:
			return StatusSet.Kind.POLYMORPH
		Kind.INVULNERABLE:
			return StatusSet.Kind.INVULNERABLE
		_:
			return StatusSet.Kind.STUN

func describe() -> String:
	if control == Kind.SLOW:
		return "lentidão de %.0f%% por %.1fs" % [slow_amount * 100.0, duration]
	return "%s por %.1fs" % [Kind.keys()[control].to_lower(), duration]
