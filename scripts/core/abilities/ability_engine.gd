class_name AbilityEngine
extends RefCounted

## Resolve conjurações — Fase 3.2, por pulso desde a tradução do original.
##
## Função pura sobre dados: recebe habilidade, mira e a lista de combatentes
## candidatos; devolve o que aconteceu. Não conhece nó, não consulta física,
## não desenha. É o mesmo código no cliente e no servidor headless.
##
## As regras de estado que `03-sistemas-de-jogo.md` manda definir **uma vez no
## sistema, não por habilidade**, moram aqui:
##
## - Stun e silêncio impedem conjurar; stun no meio da conjuração corta
## - Habilidade nova cancela a anterior? **Não** — conjuração em curso recusa
##   nova tentativa com BUSY. Cancelar exige o pedido explícito
## - Recarga começa ao iniciar a conjuração, não ao terminar: cortar a
##   conjuração de alguém não devolve a habilidade
## - Mana é cobrada ao INICIAR, junto da recarga, e pelo mesmo motivo
##
## O que a tradução mudou: uma habilidade tem vários pulsos, com tempos
## próprios. Os de tempo zero saem na hora; os demais ficam marcados no livro,
## e `resolve_scheduled()` os solta quando vencem. Quem chama tem que chamá-la
## a cada tique.
##
## **Pulso de forma PROJECTILE não resolve na conjuração.** Ele põe um projétil
## no ar (`ProjectileSet`) e o dano acontece quando a esfera encontra alguém.
## Antes, o dano saía no instante do clique e a esfera era enfeite — o que
## tornava mira irrelevante: quem estava na linha naquele milissegundo levava
## dano mesmo saindo de lá. Isso obriga quem chama a ticar também
## `advance_projectiles()`, e são os dois únicos acréscimos ao contrato da
## camada de gameplay.

## Tenta conjurar.
##
## Com `cast_time` zero, resolve na hora e devolve SUCCESS. Com tempo, devolve
## CASTING — quem chama tica o livro e chama `resolve_pending()` quando
## `cast_is_ready()`.
##
## O parâmetro se chama `aim` e não `cast` porque sombrearia esta própria
## função, e a Godot avisa. `Ability.aim` é o TIPO de mira; isto é a mira.
static func cast(
		book: AbilityBook,
		ability: Ability,
		aim: AbilityCast,
		candidates: Array
) -> CastResult:
	var refusal: CastResult = _check(book, ability, aim)
	if refusal != null:
		return refusal

	if ability.cast_time > 0.0:
		book.begin_cast(ability, aim, aim.caster)
		_charge(ability, aim.caster)
		return CastResult.of(CastResult.Status.CASTING, ability)

	return _apply(book, ability, aim, candidates, true)

## Conclui uma conjuração com tempo. Chamar quando `book.cast_is_ready()`.
##
## Os candidatos são pedidos de novo, e não guardados no início: entre o começo
## e o fim da conjuração o mundo se mexeu, e acertar quem já saiu da área seria
## errado.
static func resolve_pending(book: AbilityBook, candidates: Array) -> CastResult:
	if not book.cast_is_ready():
		return CastResult.of(CastResult.Status.INVALID)

	var pending: Dictionary = book.take_pending()
	var ability := pending["ability"] as Ability
	var aim := pending["cast"] as AbilityCast

	if not aim.caster.is_alive():
		return CastResult.of(CastResult.Status.DEAD, ability)

	# A recarga e a mana já foram cobradas em `cast`.
	return _apply(book, ability, aim, candidates, false)

## Solta os pulsos marcados que venceram. Devolve um resultado por pulso.
##
## Chamar a cada tique, depois de `book.advance_time()`. Uma habilidade de
## golpe único nunca marca nada e isto devolve lista vazia — o custo de chamar
## sempre é uma comparação.
static func resolve_scheduled(book: AbilityBook, candidates: Array) -> Array[CastResult]:
	var results: Array[CastResult] = []
	if book == null or not book.has_scheduled():
		return results

	for entry: AbilityBook.Scheduled in book.take_due():
		if entry.cast == null or entry.cast.caster == null:
			continue
		# O conjurador morrer não desfaz o que já foi lançado, mas efeito que
		# escala com atributo dele passa a ler um morto. É o mesmo critério do
		# veneno em `PeriodicSet`: o golpe sai, o dono não importa mais.
		results.append(_fire(
			book, entry.ability, entry.pulse, entry.cast, entry.anchor, candidates
		))
	return results

## Avança os projéteis no ar e aplica o que eles acertaram.
##
## Chamar a cada tique, como `resolve_scheduled()`. Devolve um resultado por
## impacto; lista vazia quando nada está voando — o custo de chamar sempre é
## uma comparação.
##
## Os candidatos são pedidos a cada tique, e não guardados no lançamento: entre
## o tiro e o impacto o mundo se mexeu, e é justamente isso que faz desviar de
## um projétil querer dizer alguma coisa.
static func advance_projectiles(
		book: AbilityBook, delta: float, candidates: Array
) -> Array[CastResult]:
	var results: Array[CastResult] = []
	if book == null or book.projectiles.is_empty():
		return results

	for impact: ProjectileSet.Impact in book.projectiles.advance_time(delta, candidates):
		var shot: ProjectileSet.Projectile = impact.projectile
		# Só os efeitos de alvo. Os do conjurador já saíram no lançamento —
		# ver `_launch`.
		_apply_effects(shot.pulse, shot.cast, impact.targets, false)
		var result: CastResult = CastResult.of(CastResult.Status.SUCCESS, shot.ability)
		result.targets = impact.targets
		# `pulse`/`anchor` de propósito NÃO preenchidos: nada os lê no impacto
		# de projétil, e `_draw_pulse` recusaria um pulso de forma PROJECTILE
		# de qualquer jeito — quem o desenha é a esfera que o segue. Preenchê-los
		# dava impressão de cobertura que não existe, que é o mesmo motivo pelo
		# qual `actor_xml` já foi removida do índice de tabelas uma vez.
		results.append(result)
	return results

# ---------------------------------------------------------------- checagens

## Devolve o motivo da recusa, ou nulo se pode conjurar.
static func _check(book: AbilityBook, ability: Ability, aim: AbilityCast) -> CastResult:
	if ability == null or aim == null or aim.caster == null:
		return CastResult.of(CastResult.Status.INVALID, ability)
	if not ability.has_pulses():
		return CastResult.of(CastResult.Status.INVALID, ability)

	var caster: Unit = aim.caster
	if not caster.is_alive():
		return CastResult.of(CastResult.Status.DEAD, ability)
	if not caster.can_cast():
		return CastResult.of(CastResult.Status.CANNOT_CAST, ability)
	if book.is_casting():
		return CastResult.of(CastResult.Status.BUSY, ability)

	if not book.is_ready(ability):
		var refused: CastResult = CastResult.of(CastResult.Status.ON_COOLDOWN, ability)
		refused.cooldown_remaining = book.remaining_cooldown(ability)
		return refused

	# Mana antes do alcance: ficar sem recurso é uma informação diferente de
	# estar longe, e quem mira precisa saber qual das duas é.
	if not caster.mana.can_afford(ability.mana_cost):
		return CastResult.of(CastResult.Status.NO_RESOURCE, ability)

	# Antes do alcance: sem ninguém apontado, o motivo é falta de alvo e não
	# distância. Medir a distância até um alvo inexistente daria a mensagem
	# errada na tela.
	if ability.aim == Ability.Aim.UNIT and aim.unit_target == null:
		return CastResult.of(CastResult.Status.NO_TARGET, ability)

	if not _in_range(ability, aim):
		return CastResult.of(CastResult.Status.OUT_OF_RANGE, ability)

	return null

static func _in_range(ability: Ability, aim: AbilityCast) -> bool:
	if ability.cast_range <= 0.0:
		return true
	match ability.aim:
		Ability.Aim.SELF, Ability.Aim.DIRECTION:
			# Sem ponto para medir: direção não tem alcance de mira, o alcance
			# dela é o comprimento da forma.
			return true
		Ability.Aim.UNIT:
			# `_check` já garantiu que há alvo antes de chegar aqui.
			return aim.caster.ground_distance_to(aim.unit_target) <= ability.cast_range
		_:
			return aim.caster.ground_distance_to_point(aim.point) <= ability.cast_range

static func _charge(ability: Ability, caster: Unit) -> void:
	if ability.mana_cost > 0.0:
		caster.mana.spend(ability.mana_cost)

# ---------------------------------------------------------------- aplicação

static func _apply(
		book: AbilityBook,
		ability: Ability,
		aim: AbilityCast,
		candidates: Array,
		charge_now: bool
) -> CastResult:
	if charge_now:
		_charge(ability, aim.caster)

	# As âncoras são todas calculadas AGORA, mesmo as dos pulsos atrasados.
	# `Origin.PREVIOUS` encadeia aqui, na ordem declarada, e o resultado fica
	# congelado. Recalcular depois faria a explosão do segundo pulso perseguir
	# um alvo que já saiu de perto — e área no chão não persegue ninguém.
	var anchor: Vector3 = aim.point
	var immediate: Array[AbilityPulse] = []
	var anchors: Array[Vector3] = []
	var delayed: Array[AbilityPulse] = []
	var delayed_anchors: Array[Vector3] = []

	for pulse: AbilityPulse in ability.pulses:
		if pulse == null or pulse.effects.is_empty():
			continue
		anchor = pulse.anchor_for(aim, anchor)
		if pulse.delay > 0.0:
			delayed.append(pulse)
			delayed_anchors.append(anchor)
		else:
			immediate.append(pulse)
			anchors.append(anchor)

	# A recusa por falta de alvo é decidida ANTES de marcar qualquer pulso.
	# Marcar primeiro e recusar depois deixaria pulsos órfãos na fila de uma
	# conjuração que oficialmente não aconteceu — e eles sairiam mesmo assim.
	if ability.refuses_without_target() and _hits_nobody(immediate, anchors, aim, candidates):
		return CastResult.of(CastResult.Status.NO_TARGET, ability)

	for index: int in range(delayed.size()):
		var late: AbilityPulse = delayed[index]
		book.schedule(
			ability, late, aim, delayed_anchors[index], late.delay, late.repeat_count()
		)

	var all_targets: Array[Unit] = []
	var partes: Array[CastResult] = []
	var lancados: int = 0
	for index: int in range(immediate.size()):
		var pulse: AbilityPulse = immediate[index]
		var result: CastResult = _fire(
			book, ability, pulse, aim, anchors[index], candidates
		)
		lancados += result.launched
		partes.append(result)
		for hit: Unit in result.targets:
			if not all_targets.has(hit):
				all_targets.append(hit)
		# Pulso que repete e começa agora: a primeira saída foi imediata, as
		# outras entram na fila.
		if pulse.repeat_count() > 1:
			book.schedule(
				ability, pulse, aim, anchors[index],
				pulse.loop_interval, pulse.repeat_count() - 1
			)

	if charge_now:
		book.start_cooldown(ability, aim.caster)

	aim.caster.triggers.fire(TriggerSet.Event.ABILITY_CAST, aim.caster, null)

	var final: CastResult = CastResult.of(CastResult.Status.SUCCESS, ability)
	final.targets = all_targets
	final.launched = lancados
	final.parts = partes
	final.direction = aim.direction
	return final

## Verdadeiro quando nenhum pulso imediato pega ninguém. Só serve para a
## recusa por falta de alvo, e por isso resolve as formas sem aplicar nada.
static func _hits_nobody(
		pulses: Array[AbilityPulse],
		anchors: Array[Vector3],
		aim: AbilityCast,
		candidates: Array
) -> bool:
	for index: int in range(pulses.size()):
		if not AbilityShape.resolve(pulses[index], aim, candidates, anchors[index]).is_empty():
			return false
	return true

## Um pulso saindo: acha quem pega e aplica os efeitos.
##
## Projétil é o caso à parte — ele não pega ninguém agora, ele decola.
static func _fire(
		book: AbilityBook,
		ability: Ability,
		pulse: AbilityPulse,
		aim: AbilityCast,
		anchor: Vector3,
		candidates: Array
) -> CastResult:
	if pulse.form == AbilityPulse.Form.PROJECTILE and book != null:
		return _launch(book, ability, pulse, aim, anchor)

	var targets: Array[Unit] = AbilityShape.resolve(pulse, aim, candidates, anchor)
	_apply_effects(pulse, aim, targets, true)

	var result: CastResult = CastResult.of(CastResult.Status.SUCCESS, ability)
	result.targets = targets
	result.pulse = pulse
	result.anchor = anchor
	result.direction = aim.direction
	return result

## Põe no ar um projétil por direção do leque.
##
## **Um por direção, e não uma forma que testa todas.** É a correção que o voo
## de verdade trouxe de graça: antes, três flechas em leque eram uma única
## checagem "está dentro de alguma das três", e quem estivesse entre duas delas
## levava dano de um tiro que não passou por ele.
##
## Os efeitos do CONJURADOR saem agora, não no impacto. O escudo de quem atira
## não depende de a flecha acertar; se dependesse, seria um gatilho, e o
## vocabulário já tem `TriggerEffect` para isso.
static func _launch(
		book: AbilityBook,
		ability: Ability,
		pulse: AbilityPulse,
		aim: AbilityCast,
		anchor: Vector3
) -> CastResult:
	var result: CastResult = CastResult.of(CastResult.Status.SUCCESS, ability)
	result.pulse = pulse
	result.anchor = anchor
	result.direction = aim.direction
	for direction: Vector3 in pulse.spread_directions(aim.direction):
		if book.projectiles.launch(ability, pulse, aim, anchor, direction) != null:
			result.launched += 1

	if result.launched > 0:
		_apply_effects(pulse, aim, [] as Array[Unit], true)
	return result

## Aplica os efeitos de um pulso. `include_caster` separa quem já foi servido.
##
## Existe porque o projétil aplica em dois momentos: o que é do conjurador sai
## no lançamento, o que é do alvo sai no impacto. Sem separar, o escudo do
## atirador saía de novo a cada inimigo acertado.
static func _apply_effects(
		pulse: AbilityPulse,
		aim: AbilityCast,
		targets: Array[Unit],
		include_caster: bool
) -> void:
	for effect: AbilityEffect in pulse.effects:
		if effect == null:
			continue
		if effect.recipient == AbilityEffect.Recipient.CASTER:
			# Sai uma vez só, não uma por alvo: senão um dash com três
			# inimigos na frente andaria o triplo.
			if include_caster:
				effect.apply(aim, aim.caster)
			continue
		for target: Unit in targets:
			effect.apply(aim, target)
