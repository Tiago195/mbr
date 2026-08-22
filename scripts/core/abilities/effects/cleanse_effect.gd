class_name CleanseEffect
extends AbilityEffect

## PURIFICAÇÃO — tira controles, modificadores ou periódicos de cima de alguém.
##
## O original expressa isto de três formas diferentes — `Release_Effects_Id`,
## `BuffReleaseCondition` e impactos que removem buff por linha — e todas
## caem na mesma pergunta: o que sai e de quem.
##
## Também é o único jeito de expressar dissipação hostil, que é a mesma peça
## apontada para o outro lado: tirar o escudo e a aceleração de quem fugiu.

## O que este efeito remove.
enum Scope {
	## Só os controles de grupo — atordoamento, prisão, silêncio, lentidão.
	## O uso clássico do item de purificação.
	CROWD_CONTROL,
	## Só os modificadores de atributo temporários e os periódicos.
	## É a dissipação hostil: some o buff, ficam os controles.
	BUFFS,
	## Tudo que é temporário.
	EVERYTHING,
}

@export var scope: Scope = Scope.CROWD_CONTROL

## Quando preenchido, só sai o que veio desta origem. Vazio tira tudo do
## escopo. É o que permite "cancela o próprio veneno" sem limpar o do inimigo.
@export var only_source: StringName = &""

## Se também tira o escudo. Fora por padrão até em `EVERYTHING`: escudo não é
## um estado que se purifica, é vida emprestada, e removê-lo junto faria todo
## item de purificação virar um item de dano.
@export var strips_shield: bool = false

func apply(_cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return

	if scope != Scope.BUFFS:
		_clear_control(target)

	if scope != Scope.CROWD_CONTROL:
		if only_source.is_empty():
			# Sem origem declarada, só o que é temporário sai. Modificador
			# permanente é bônus de item equipado, e purificar não deve
			# desequipar ninguém.
			_clear_temporary_modifiers(target)
			target.periodic.clear()
		else:
			target.stats.remove_source(only_source)
			target.periodic.remove_source(only_source)
			target.triggers.remove_source(only_source)

	if strips_shield:
		target.health.strip_shields()

## Invulnerabilidade não é controle e não sai na purificação — do contrário o
## item de purificação seria também um cancelador de invulnerabilidade alheia.
func _clear_control(target: Unit) -> void:
	var invulnerable: float = target.status.remaining(StatusSet.Kind.INVULNERABLE)
	target.status.clear_all()
	if invulnerable > 0.0:
		target.status.apply(StatusSet.Kind.INVULNERABLE, invulnerable)
	# Lentidão mora em `Stats`, não em `StatusSet` — limpá-la exige varrer os
	# modificadores. É o preço de ter escolhido modelar slow como atributo, e
	# ele se paga aqui e só aqui.
	target.stats.remove_prefixed(&"slow:")

func _clear_temporary_modifiers(target: Unit) -> void:
	target.stats.remove_temporary()

func describe() -> String:
	return "purifica %s" % Scope.keys()[scope].to_lower()
