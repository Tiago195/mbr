class_name AbilityTelegraph
extends Node3D

## Telegrafia visual de habilidade — Fase 3.4.
##
## Formas primitivas que aparecem e somem, para dar para entender o que
## aconteceu numa luta. Feio de propósito: sem partícula, sem shader, sem som.
##
## Vive solto na cena, nunca preso ao conjurador — se fosse filho dele, a marca
## no chão andaria junto e deixaria de marcar o lugar onde a habilidade caiu.

@export var lifetime: float = 0.45

var _elapsed: float = 0.0
var _material: StandardMaterial3D

var _travels: bool = false
var _travel_from: Vector3 = Vector3.ZERO
var _travel_to: Vector3 = Vector3.ZERO

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return

	var progress: float = _elapsed / lifetime
	if _material != null:
		_material.albedo_color.a = (1.0 - progress) * 0.55
	if _travels:
		# Interpolação no `_process` e não no `_physics_process`: isto é
		# puramente visual, e a convenção do projeto reserva o tick fixo para
		# lógica de jogo.
		global_position = _travel_from.lerp(_travel_to, progress)

# ---------------------------------------------------------------- fábricas

## Disco no chão. Marca área de habilidade com forma CIRCLE.
static func circle(
		parent: Node, center: Vector3, radius: float, color: Color
) -> AbilityTelegraph:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.06

	var node := _build(parent, mesh, color)
	# Levemente acima do chão: coplanar com o plano provoca z-fighting, que
	# aparece como a marca piscando em faixas.
	node.global_position = Vector3(center.x, 0.03, center.z)
	return node

## Faixa retangular saindo do conjurador. Marca LINE e PROJECTILE.
static func line(
		parent: Node, origin: Vector3, direction: Vector3,
		length: float, width: float, color: Color
) -> AbilityTelegraph:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.06, length)

	var node := _build(parent, mesh, color)
	var center: Vector3 = origin + direction * (length * 0.5)
	node.global_position = Vector3(center.x, 0.03, center.z)
	# `look_at` em vez de montar a matriz de rotação à mão: escrever a base
	# transposta já custou uma sessão de depuração neste projeto. O -Z local é
	# a frente e a caixa tem o comprimento no eixo Z, então apontar o -Z para a
	# direção alinha a faixa.
	var target: Vector3 = node.global_position + direction
	if node.global_position.distance_squared_to(target) > 0.000001:
		node.look_at(target, Vector3.UP)
	return node

## Esfera que viaja do conjurador ao ponto de impacto.
##
## O dano já foi aplicado quando ela sai — ver a nota sobre projétil
## instantâneo em `ability_caster.gd`.
static func projectile(
		parent: Node, origin: Vector3, destination: Vector3,
		speed: float, color: Color
) -> AbilityTelegraph:
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.56

	var node := _build(parent, mesh, color)
	node._travels = true
	node._travel_from = Vector3(origin.x, 1.0, origin.z)
	node._travel_to = Vector3(destination.x, 1.0, destination.z)
	node.global_position = node._travel_from
	node.lifetime = maxf(node._travel_from.distance_to(node._travel_to) / maxf(speed, 0.1), 0.05)
	return node

# ---------------------------------------------------------------- interno

static func _build(parent: Node, mesh: Mesh, color: Color) -> AbilityTelegraph:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.55)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Sem descarte de face: a marca no chão deve ser visível mesmo se a câmera
	# um dia passar por baixo dela.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material

	var node := AbilityTelegraph.new()
	node._material = material
	node.add_child(instance)
	parent.add_child(node)
	return node
