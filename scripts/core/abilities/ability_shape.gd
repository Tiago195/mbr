class_name AbilityShape
extends RefCounted

## Resolve quem uma forma atinge — Fase 3.2.
##
## Geometria pura, no plano do chão. Não consulta física: recebe a lista de
## candidatos e devolve quem está dentro. Isso é o que permite o servidor
## headless resolver habilidade sem cena, e o teste rodar sem engine.
##
## A altura é ignorada em tudo, pelo mesmo motivo do alcance de ataque: área
## num MOBA é medida no chão.

## Devolve os atingidos, já filtrados por time e limitados por teto, ordenados
## do mais próximo ao mais distante do epicentro.
static func resolve(ability: Ability, cast: AbilityCast, candidates: Array) -> Array[Unit]:
	var origin: Vector3 = cast.caster.position
	var inside: Array[Unit] = []

	for candidate: Variant in candidates:
		var unit := candidate as Unit
		if unit == null or not unit.is_alive():
			continue
		if not _passes_filter(ability, cast.caster, unit):
			continue
		if _is_inside(ability, cast, origin, unit):
			inside.append(unit)

	var epicenter: Vector3 = cast.point if ability.form == Ability.Form.CIRCLE else origin
	inside.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.ground_distance_to_point(epicenter) < b.ground_distance_to_point(epicenter)
	)

	var cap: int = ability.effective_max_targets()
	if cap > 0 and inside.size() > cap:
		inside = inside.slice(0, cap)
	return inside

# ---------------------------------------------------------------- filtro

static func _passes_filter(ability: Ability, caster: Unit, unit: Unit) -> bool:
	if unit == caster:
		return ability.hits_self
	if caster.is_hostile_to(unit):
		return ability.hits_enemies
	return ability.hits_allies

# ---------------------------------------------------------------- geometria

static func _is_inside(
		ability: Ability, cast: AbilityCast, origin: Vector3, unit: Unit
) -> bool:
	match ability.form:
		Ability.Form.SINGLE:
			# Sem área: só quem foi apontado. Sem alvo apontado, o conjurador.
			var picked: Unit = cast.unit_target if cast.unit_target != null else cast.caster
			return unit == picked
		Ability.Form.CIRCLE:
			return unit.ground_distance_to_point(cast.point) <= ability.radius
		Ability.Form.CONE:
			return _in_cone(ability, cast, origin, unit)
		_:
			# LINE e PROJECTILE compartilham a geometria; o que muda entre
			# eles é o voo, que é assunto da camada de gameplay.
			return _in_line(ability, cast, origin, unit)

static func _in_cone(
		ability: Ability, cast: AbilityCast, origin: Vector3, unit: Unit
) -> bool:
	var to_unit: Vector3 = _flat(unit.position - origin)
	var distance: float = to_unit.length()
	if distance > ability.length:
		return false
	# Quem está exatamente em cima do conjurador conta como dentro: não há
	# ângulo definido, e excluí-lo criaria um ponto cego colado no corpo.
	if distance <= 0.0001:
		return true
	var half_angle: float = deg_to_rad(ability.cone_angle) * 0.5
	return to_unit.normalized().angle_to(cast.direction) <= half_angle

static func _in_line(
		ability: Ability, cast: AbilityCast, origin: Vector3, unit: Unit
) -> bool:
	var to_unit: Vector3 = _flat(unit.position - origin)
	# Projeção sobre a direção da mira: quanto o alvo avançou ao longo da
	# linha. Negativo significa atrás do conjurador.
	var along: float = to_unit.dot(cast.direction)
	if along < 0.0 or along > ability.length:
		return false
	# O que sobra depois de tirar a componente ao longo da linha é a distância
	# perpendicular ao eixo.
	var perpendicular: float = (to_unit - cast.direction * along).length()
	return perpendicular <= ability.width * 0.5

static func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)
