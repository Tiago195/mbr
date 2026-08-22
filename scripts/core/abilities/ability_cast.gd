class_name AbilityCast
extends RefCounted

## A mira de uma conjuração — Fase 3.1.
##
## Carrega quem conjurou e para onde. Existe para que um efeito consiga saber
## a direção do dash ou o centro da área sem ter que perguntar à engine —
## quem monta isto é a camada de gameplay, a partir do cursor.

var caster: Unit

## Ponto do chão mirado. Vale para alvo POINT e é o centro das formas.
var point: Vector3 = Vector3.ZERO

## Direção horizontal normalizada. Vale para alvo DIRECTION e para cone.
var direction: Vector3 = Vector3.FORWARD

## Alvo escolhido a dedo. Vale para alvo UNIT.
var unit_target: Unit = null

static func at_point(caster: Unit, point: Vector3) -> AbilityCast:
	var cast := AbilityCast.new()
	cast.caster = caster
	cast.point = point
	cast.direction = _flat_direction(caster.position, point, caster.facing)
	return cast

static func toward(caster: Unit, direction: Vector3) -> AbilityCast:
	var cast := AbilityCast.new()
	cast.caster = caster
	cast.direction = _normalize_flat(direction, caster.facing)
	cast.point = caster.position
	return cast

static func on_unit(caster: Unit, target: Unit) -> AbilityCast:
	var cast := AbilityCast.new()
	cast.caster = caster
	cast.unit_target = target
	cast.point = target.position
	cast.direction = _flat_direction(caster.position, target.position, caster.facing)
	return cast

static func on_self(caster: Unit) -> AbilityCast:
	var cast := AbilityCast.new()
	cast.caster = caster
	cast.unit_target = caster
	cast.point = caster.position
	cast.direction = _normalize_flat(caster.facing, Vector3.FORWARD)
	return cast

## Direção de um ponto a outro, achatada no plano do chão.
## Cai no `fallback` quando os pontos coincidem — mirar nos próprios pés não
## pode produzir um vetor zero que quebraria normalização adiante.
static func _flat_direction(from: Vector3, to: Vector3, fallback: Vector3) -> Vector3:
	return _normalize_flat(to - from, fallback)

static func _normalize_flat(vector: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(vector.x, 0.0, vector.z)
	if flat.length_squared() <= 0.000001:
		flat = Vector3(fallback.x, 0.0, fallback.z)
	if flat.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return flat.normalized()
