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

## Altura em que a esfera do projétil voa. Só aparência: a lógica é no plano.
const ALTURA_DO_VOO: float = 1.0

## Quanto tempo a esfera pisca depois de acertar, antes de sumir.
const CLARAO: float = 0.12

var _elapsed: float = 0.0
var _material: StandardMaterial3D

## O projétil de verdade que esta esfera representa. Quando existe, a posição
## vem DELE — não de uma interpolação paralela.
##
## Antes havia `_travel_from`/`_travel_to` e um `lerp`: a esfera fazia sua
## própria viagem enquanto o dano já tinha saído no clique. Duas verdades sobre
## a mesma coisa, e a que o jogador via era a falsa.
var _shot: ProjectileSet.Projectile = null
var _fade: float = 0.0

func _process(delta: float) -> void:
	if _shot != null:
		_process_shot(delta)
		return

	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return

	var progress: float = _elapsed / lifetime
	if _material != null:
		_material.albedo_color.a = (1.0 - progress) * 0.55

## Segue o projétil enquanto ele voa; pisca e some quando ele acaba.
##
## `lifetime` continua valendo como guarda: projétil que por algum motivo
## ficasse preso não deixaria uma esfera imortal na cena.
func _process_shot(delta: float) -> void:
	global_position = Vector3(
		_shot.position.x, ALTURA_DO_VOO, _shot.position.z
	)
	if not _shot.spent:
		_elapsed += delta
		if _elapsed < lifetime:
			return

	_fade += delta
	if _material != null:
		_material.albedo_color.a = maxf(0.55 * (1.0 - _fade / CLARAO), 0.0)
	if _fade >= CLARAO:
		queue_free()

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
## Uma esfera colada num projétil de verdade.
##
## O raio sai de `pulse.width`, e não de um número bonito: é a largura com que
## o projétil realmente acerta. Uma esfera menor que a colisão faz o jogador
## achar que errou quando acertou; maior, o contrário. Ver a esfera do tamanho
## certo é metade de aprender a mirar.
static func follow(
		parent: Node, shot: ProjectileSet.Projectile, color: Color
) -> AbilityTelegraph:
	if shot == null:
		return null
	var raio: float = clampf(shot.pulse.width * 0.5, 0.15, 1.5)
	var mesh := SphereMesh.new()
	mesh.radius = raio
	mesh.height = raio * 2.0

	var node := _build(parent, mesh, color)
	node._shot = shot
	# Margem sobre o tempo de voo: é guarda contra esfera órfã, não o relógio
	# do projétil. Quem manda no fim é `shot.spent`.
	node.lifetime = shot.flight_time() + 0.5
	node.global_position = Vector3(
		shot.position.x, ALTURA_DO_VOO, shot.position.z
	)
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
