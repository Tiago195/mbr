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

## Prefixo `p_` nos parâmetros para não sombrear os membros de mesmo nome —
## a Godot avisa, e sombreamento silencioso é como se escreve no campo errado
## sem perceber.
static func at_point(p_caster: Unit, p_point: Vector3) -> AbilityCast:
	var made := AbilityCast.new()
	made.caster = p_caster
	made.point = p_point
	made.direction = _flat_direction(p_caster.position, p_point, p_caster.facing)
	return made

static func toward(p_caster: Unit, p_direction: Vector3) -> AbilityCast:
	var made := AbilityCast.new()
	made.caster = p_caster
	made.direction = _normalize_flat(p_direction, p_caster.facing)
	made.point = p_caster.position
	return made

static func on_unit(p_caster: Unit, p_target: Unit) -> AbilityCast:
	var made := AbilityCast.new()
	made.caster = p_caster
	made.unit_target = p_target
	made.point = p_target.position
	made.direction = _flat_direction(
		p_caster.position, p_target.position, p_caster.facing
	)
	return made

static func on_self(p_caster: Unit) -> AbilityCast:
	var made := AbilityCast.new()
	made.caster = p_caster
	made.unit_target = p_caster
	made.point = p_caster.position
	made.direction = _normalize_flat(p_caster.facing, Vector3.FORWARD)
	return made

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
