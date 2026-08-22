class_name AbilityShape
extends RefCounted

## Resolve quem uma forma atinge — Fase 3.2, por pulso desde a tradução.
##
## Geometria pura, no plano do chão. Não consulta física: recebe a lista de
## candidatos e devolve quem está dentro. Isso é o que permite o servidor
## headless resolver habilidade sem cena, e o teste rodar sem engine.
##
## A altura é ignorada em tudo, pelo mesmo motivo do alcance de ataque: área
## num MOBA é medida no chão.
##
## Recebe `AbilityPulse` e não `Ability` porque cada golpe tem sua própria
## forma — a mesma habilidade pode cortar em linha e depois explodir em
## círculo. A âncora vem de fora: quem sabe encadear pulsos é a engine.

## Devolve os atingidos, já filtrados por time e limitados por teto, ordenados
## do mais próximo ao mais distante da âncora.
static func resolve(
		pulse: AbilityPulse,
		cast: AbilityCast,
		candidates: Array,
		anchor: Vector3
) -> Array[Unit]:
	var inside: Array[Unit] = []
	if pulse == null or cast == null or cast.caster == null:
		return inside

	for candidate: Variant in candidates:
		var unit := candidate as Unit
		if unit == null or not unit.is_alive():
			continue
		if not _passes_filter(pulse, cast.caster, unit):
			continue
		if _is_inside(pulse, cast, anchor, unit):
			inside.append(unit)

	inside.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.ground_distance_to_point(anchor) < b.ground_distance_to_point(anchor)
	)

	var cap: int = pulse.effective_max_targets()
	if cap > 0 and inside.size() > cap:
		inside = inside.slice(0, cap)
	return inside

# ---------------------------------------------------------------- filtro

static func _passes_filter(pulse: AbilityPulse, caster: Unit, unit: Unit) -> bool:
	if unit == caster:
		return pulse.hits_self
	if caster.is_hostile_to(unit):
		return pulse.hits_enemies
	return pulse.hits_allies

# ---------------------------------------------------------------- geometria

static func _is_inside(
		pulse: AbilityPulse, cast: AbilityCast, anchor: Vector3, unit: Unit
) -> bool:
	match pulse.form:
		AbilityPulse.Form.SINGLE:
			# Sem área: só quem foi apontado. Sem alvo apontado, o conjurador.
			var picked: Unit = cast.unit_target if cast.unit_target != null else cast.caster
			return unit == picked
		AbilityPulse.Form.CIRCLE:
			return unit.ground_distance_to_point(anchor) <= pulse.radius
		AbilityPulse.Form.CONE:
			return _in_cone(pulse, cast, anchor, unit)
		AbilityPulse.Form.TRAPEZOID:
			return _in_trapezoid(pulse, cast, anchor, unit)
		_:
			# LINE e PROJECTILE compartilham a geometria; o que muda entre
			# eles é o voo, que é assunto da camada de gameplay.
			return _in_line(pulse, cast, anchor, unit)

static func _in_cone(
		pulse: AbilityPulse, cast: AbilityCast, anchor: Vector3, unit: Unit
) -> bool:
	var to_unit: Vector3 = _flat(unit.position - anchor)
	var distance: float = to_unit.length()
	if distance > pulse.length:
		return false
	# Quem está exatamente em cima da âncora conta como dentro: não há ângulo
	# definido, e excluí-lo criaria um ponto cego colado no corpo.
	if distance <= 0.0001:
		return true
	var half_angle: float = deg_to_rad(pulse.cone_angle) * 0.5
	return to_unit.normalized().angle_to(cast.direction) <= half_angle

static func _in_line(
		pulse: AbilityPulse, cast: AbilityCast, anchor: Vector3, unit: Unit
) -> bool:
	var to_unit: Vector3 = _flat(unit.position - anchor)
	# Projeção sobre a direção da mira: quanto o alvo avançou ao longo da
	# linha. Negativo significa atrás da âncora.
	var along: float = to_unit.dot(cast.direction)
	if along < 0.0 or along > pulse.length:
		return false
	# O que sobra depois de tirar a componente ao longo da linha é a distância
	# perpendicular ao eixo.
	var perpendicular: float = (to_unit - cast.direction * along).length()
	return perpendicular <= pulse.width * 0.5

## Trapézio: um retângulo cuja largura interpola entre `near_width` e
## `far_width` conforme a distância. Quem está antes de `near_distance` fica
## de fora — é isso que dá o "buraco colado nos pés" do tiro de longo alcance,
## e é a diferença entre ele e um cone comum.
static func _in_trapezoid(
		pulse: AbilityPulse, cast: AbilityCast, anchor: Vector3, unit: Unit
) -> bool:
	var to_unit: Vector3 = _flat(unit.position - anchor)
	var along: float = to_unit.dot(cast.direction)
	if along < pulse.near_distance or along > pulse.length:
		return false

	var span: float = pulse.length - pulse.near_distance
	# Comprimento degenerado: sem faixa onde interpolar, vale a largura de
	# perto. Sem esta guarda, seria uma divisão por zero na borda.
	var progress: float = 0.0 if span <= 0.0001 \
		else (along - pulse.near_distance) / span
	var half_width: float = lerpf(pulse.near_width, pulse.far_width, progress) * 0.5

	var perpendicular: float = (to_unit - cast.direction * along).length()
	return perpendicular <= half_width

static func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)
