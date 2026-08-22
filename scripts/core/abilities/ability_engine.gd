class_name AbilityEngine
extends RefCounted

## Resolve conjurações — Fase 3.2.
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

## Tenta conjurar.
##
## Com `cast_time` zero, resolve na hora e devolve SUCCESS. Com tempo, devolve
## CASTING — quem chama tica o livro e chama `resolve_pending()` quando
## `cast_is_ready()`.
static func cast(
		book: AbilityBook,
		ability: Ability,
		cast: AbilityCast,
		candidates: Array
) -> CastResult:
	var refusal: CastResult = _check(book, ability, cast)
	if refusal != null:
		return refusal

	if ability.cast_time > 0.0:
		book.begin_cast(ability, cast, cast.caster)
		return CastResult.of(CastResult.Status.CASTING, ability)

	return _apply(book, ability, cast, candidates, true)

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
	var cast := pending["cast"] as AbilityCast

	if not cast.caster.is_alive():
		return CastResult.of(CastResult.Status.DEAD, ability)

	# A recarga já foi iniciada em `begin_cast`.
	return _apply(book, ability, cast, candidates, false)

# ---------------------------------------------------------------- checagens

## Devolve o motivo da recusa, ou nulo se pode conjurar.
static func _check(book: AbilityBook, ability: Ability, cast: AbilityCast) -> CastResult:
	if ability == null or cast == null or cast.caster == null:
		return CastResult.of(CastResult.Status.INVALID, ability)
	if ability.effects.is_empty():
		return CastResult.of(CastResult.Status.INVALID, ability)

	var caster: Unit = cast.caster
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

	if not _in_range(ability, cast):
		return CastResult.of(CastResult.Status.OUT_OF_RANGE, ability)

	return null

static func _in_range(ability: Ability, cast: AbilityCast) -> bool:
	if ability.cast_range <= 0.0:
		return true
	match ability.aim:
		Ability.Aim.SELF, Ability.Aim.DIRECTION:
			# Sem ponto para medir: direção não tem alcance de mira, o alcance
			# dela é o comprimento da forma.
			return true
		Ability.Aim.UNIT:
			if cast.unit_target == null:
				return false
			return cast.caster.ground_distance_to(cast.unit_target) <= ability.cast_range
		_:
			return cast.caster.ground_distance_to_point(cast.point) <= ability.cast_range

# ---------------------------------------------------------------- aplicação

static func _apply(
		book: AbilityBook,
		ability: Ability,
		cast: AbilityCast,
		candidates: Array,
		start_cooldown: bool
) -> CastResult:
	var targets: Array[Unit] = AbilityShape.resolve(ability, cast, candidates)

	if targets.is_empty() and ability.requires_target():
		# Não pegou ninguém e todo efeito precisa de alvo: recusa sem gastar a
		# recarga. Uma habilidade que também age no conjurador — dash com
		# escudo — não cai aqui, e sai mesmo em área vazia.
		return CastResult.of(CastResult.Status.NO_TARGET, ability)

	for effect: AbilityEffect in ability.effects:
		if effect == null:
			continue
		if effect.recipient == AbilityEffect.Recipient.CASTER:
			# Sai uma vez só, não uma por alvo: senão um dash com três
			# inimigos na frente andaria o triplo.
			effect.apply(cast, cast.caster)
			continue
		for target: Unit in targets:
			effect.apply(cast, target)

	if start_cooldown:
		book.start_cooldown(ability, cast.caster)

	var result: CastResult = CastResult.of(CastResult.Status.SUCCESS, ability)
	result.targets = targets
	return result
