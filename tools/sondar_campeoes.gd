extends SceneTree

## Percorre todos os campeões na CENA DE VERDADE, e conjura o kit de cada um.
##
## A suíte de `tests/` só alcança `scripts/core/` — é a parte que não conhece
## nó. `ChampionSelector`, `Combatant` e `AbilityCaster` moram em `gameplay/` e
## ficariam sem nenhuma cobertura automática. Esta sonda fecha esse buraco por
## cima: carrega `main.tscn`, troca de campeão em todos eles, conjura Q, W, E e
## R de cada um, e falha se alguma coisa quebrar.
##
## Não substitui olho humano — ela não sabe se ficou divertido, nem se a
## telegrafia aparece no lugar certo. O que ela sabe é se quebrou.
##
## Rodar:
##     godot --headless --path . --script res://tools/sondar_campeoes.gd

const CENA: String = "res://scenes/main.tscn"

var _raiz: Node

## Montar e sondar são quadros DIFERENTES, e têm que ser.
##
## `add_child()` dentro do `_init()` de um `SceneTree` não chama `_ready()` na
## hora — ele fica para o começo do primeiro quadro. A primeira versão desta
## sonda reprovava com "os catálogos não carregaram", e o `_ready()` que os
## carrega imprimia DEPOIS do veredito.
func _init() -> void:
	var cena: PackedScene = load(CENA) as PackedScene
	if cena != null:
		_raiz = cena.instantiate()
		root.add_child(_raiz)
	process_frame.connect(_rodar, CONNECT_ONE_SHOT)

func _rodar() -> void:
	# `Variant` e não `Array[String]` de propósito: erro em tempo de execução
	# aborta só a função onde ocorreu e devolve nulo a quem chamou. Se o
	# estouro derrubasse TAMBÉM esta função, o `quit()` nunca aconteceria — e
	# um `SceneTree` headless sem `quit` roda para sempre.
	var falhas: Variant = _sondar()
	print("")
	if not falhas is Array:
		print("  [FALHOU] a sonda estourou (veja SCRIPT ERROR acima)")
		quit(1)
		return
	var lista: Array = falhas as Array
	if lista.is_empty():
		print("  [ok] todos os campeões trocaram e conjuraram sem erro")
	else:
		for falha: String in lista:
			print("  [FALHOU] %s" % falha)
		print("")
		print("  %d FALHA(S)." % lista.size())
	quit(1 if not lista.is_empty() else 0)

func _sondar() -> Array[String]:
	var falhas: Array[String] = []

	if _raiz == null:
		return ["%s não carregou" % CENA] as Array[String]

	var selector: ChampionSelector = _achar(_raiz) as ChampionSelector
	if selector == null:
		return ["a cena não tem ChampionSelector"] as Array[String]
	if selector.actors == null or selector.abilities == null:
		return ["os catálogos não carregaram"] as Array[String]

	var caster: AbilityCaster = selector.caster()
	var combatant: Combatant = selector.combatant()
	if caster == null or combatant == null or combatant.unit == null:
		return ["o seletor não achou Combatant ou AbilityCaster"] as Array[String]
	var unit: Unit = combatant.unit

	var campeoes: Array[ActorProfile] = selector.actors.champions()
	print("")
	print("  sondando %d campeões" % campeoes.size())

	for profile: ActorProfile in campeoes:
		if not selector.select(profile.id):
			falhas.append("%s: não selecionou" % profile.id)
			continue

		var vida: float = unit.stats.get_value(Stat.Id.MAX_HEALTH)
		if vida <= 100.0:
			falhas.append(
				"%s: nasceu com %.0f de vida — os atributos não foram aplicados"
					% [profile.id, vida]
			)
		# O perfil do original NÃO declara chance de crítico nem poder de
		# habilidade: os dois vêm do Inspector da cena. Uma primeira versão
		# trocava o conjunto inteiro de atributos e apagava os dois em
		# silêncio — vida e ataque continuavam certos, e nada acusava.
		if unit.stats.get_value(Stat.Id.CRIT_CHANCE) <= 0.0:
			falhas.append(
				"%s: a chance de crítico do Inspector sumiu na troca" % profile.id
			)
		if unit.stats.get_value(Stat.Id.ABILITY_POWER) <= 0.0:
			falhas.append(
				"%s: o poder de habilidade do Inspector sumiu na troca" % profile.id
			)

		# Mana e recarga zeradas a cada conjuração: o que se sonda é se a
		# habilidade EXECUTA, não se o custo é justo.
		for slot: AbilityBook.Slot in [
			AbilityBook.Slot.Q, AbilityBook.Slot.W,
			AbilityBook.Slot.E, AbilityBook.Slot.R,
		]:
			var ability: Ability = caster.book.ability_in(slot)
			if ability == null:
				continue
			caster.book.clear_cooldowns()
			unit.mana.current = unit.mana.maximum()
			var resultado: CastResult = AbilityEngine.cast(
				caster.book, ability, _mirar(ability, unit),
				Combatant.all_units(self)
			)
			if resultado == null:
				falhas.append("%s %s: a engine não devolveu resultado" % [
					profile.id, AbilityBook.Slot.keys()[slot]
				])
				continue
			if resultado.status == CastResult.Status.CANNOT_CAST:
				falhas.append("%s %s: recusada — o campeão anterior deixou um controle?" % [
					profile.id, AbilityBook.Slot.keys()[slot]
				])

		# Os pulsos atrasados também têm que sair sem estourar.
		for _passo: int in 60:
			caster.book.advance_time(0.1, unit)
			unit.advance_time(0.1)
			AbilityEngine.resolve_scheduled(caster.book, Combatant.all_units(self))

	if campeoes.is_empty():
		return ["o catálogo não tem campeão nenhum"] as Array[String]

	# Passar por todos não pode deixar bônus acumulado. Cada campeão aplica a
	# passiva dele; se a anterior não saísse, o último herdaria todas.
	var ultimo: ActorProfile = campeoes[campeoes.size() - 1]
	selector.select(ultimo.id)
	var do_zero: float = ultimo.build_unit(selector.level).stats.get_value(
		Stat.Id.MAX_HEALTH
	)
	var na_cena: float = unit.stats.get_value(Stat.Id.MAX_HEALTH)
	if absf(na_cena - do_zero) > 1.0:
		falhas.append(
			("passar por %d campeões deixou resíduo: %.0f de vida na cena, "
			+ "contra %.0f montando o mesmo campeão do zero")
				% [campeoes.size(), na_cena, do_zero]
		)

	return falhas

func _mirar(ability: Ability, unit: Unit) -> AbilityCast:
	match ability.aim:
		Ability.Aim.SELF:
			return AbilityCast.on_self(unit)
		Ability.Aim.DIRECTION:
			return AbilityCast.toward(unit, Vector3.FORWARD)
		_:
			return AbilityCast.at_point(unit, unit.position + Vector3.FORWARD * 3.0)

func _achar(node: Node) -> Node:
	if node is ChampionSelector:
		return node
	for child: Node in node.get_children():
		var achado: Node = _achar(child)
		if achado != null:
			return achado
	return null
