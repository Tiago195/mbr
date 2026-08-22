class_name AbilityTelegraph
extends Node3D

## Telegrafia visual de habilidade — Fase 3.4.
##
## Formas primitivas que aparecem e somem, para dar para entender o que
## aconteceu numa luta. Feio de propósito: sem partícula, sem shader, sem som.
##
## Vive solto na cena, nunca preso ao conjurador — se fosse filho dele, a marca
## no chão andaria junto e deixaria de marcar o lugar onde a habilidade caiu.

## Quanto tempo uma marca fica na tela. Constante nomeada para
## `tools/sondar_campeoes.gd` poder conferir a vida de cada marca sem instanciar
## nó — uma marca que pisca por um milésimo é indistinguível de nenhuma marca.
const VIDA_PADRAO: float = 0.45

## Camadas de render da malha. `0` tira a marca de toda câmera — ela existe na
## árvore, tem posição e tamanho certos, e não aparece. Nomeada porque
## `tools/sondar_campeoes.gd` a confere.
const CAMADAS_DE_RENDER: int = 1

@export var lifetime: float = VIDA_PADRAO

## Altura em que a esfera do projétil voa. Só aparência: a lógica é no plano.
const ALTURA_DO_VOO: float = 1.0

## Altura de uma marca de chão. Um pelo acima do plano: coplanar provoca
## z-fighting, que aparece como a marca piscando em faixas.
const ALTURA_DO_CHAO: float = 0.03

## Espessura de uma marca de chão. Ela é uma MARCA, não um bloco — um valor
## alto põe um muro opaco no meio da luta.
const ESPESSURA: float = 0.06

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

## Verdadeiro quando esta marca é a esfera colada num projétil.
##
## Existe porque quem conta marcas precisa separar as duas espécies: a esfera
## do projétil e a marca de chão de um pulso. A conferência de
## `tools/sondar_campeoes.gd` contava as duas juntas e comparava com um
## esperado que excluía projétil — então a esfera tapava o buraco de um golpe
## que tivesse parado de aparecer. Quatro de cinco casos passavam mascarados.
func follows_projectile() -> bool:
	return _shot != null

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
	var node := _build(parent, disc_mesh(radius), color)
	node.global_position = Vector3(center.x, ALTURA_DO_CHAO, center.z)
	return node

## Disco achatado de raio `radius`.
##
## Público — como toda malha daqui — porque `tools/sondar_campeoes.gd` monta a
## expectativa com a MESMA função que o desenho usa. Enquanto ela remontava a
## malha por conta própria, a conferência concordava com uma cópia; enquanto
## comparava propriedade por propriedade escolhida a dedo, cada rodada de
## revisão achava mais uma propriedade fora da lista — altura do nó, espessura
## da caixa, altura do cilindro.
static func disc_mesh(radius: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = ESPESSURA
	return mesh

## Faixa retangular saindo do conjurador. Marca LINE e PROJECTILE.
static func line(
		parent: Node, origin: Vector3, direction: Vector3,
		length: float, width: float, color: Color
) -> AbilityTelegraph:
	var node := _build(parent, strip_mesh(width, length), color)
	var center: Vector3 = origin + direction * (length * 0.5)
	node.global_position = Vector3(center.x, ALTURA_DO_CHAO, center.z)
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
## O raio com que um projétil é desenhado.
##
## Público e numa fonte só porque `tools/sondar_campeoes.gd` confere o tamanho
## da esfera contra ele. Duplicar a conta na sonda faria a conferência
## concordar com uma cópia em vez de com o desenho — e um dia as duas
## divergiriam sem ninguém ver.
static func sphere_radius(pulse: AbilityPulse) -> float:
	return clampf(pulse.width * 0.5, 0.15, 1.5)

## Esfera do projétil. `height` é o diâmetro: uma `SphereMesh` com altura
## diferente do dobro do raio é um ovo.
static func sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh

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
	var node := _build(parent, sphere_mesh(sphere_radius(shot.pulse)), color)
	node._shot = shot
	# Margem sobre o tempo de voo: é guarda contra esfera órfã, não o relógio
	# do projétil. Quem manda no fim é `shot.spent`.
	node.lifetime = shot.flight_time() + 0.5
	node.global_position = Vector3(
		shot.position.x, ALTURA_DO_VOO, shot.position.z
	)
	return node

## Faixa retangular achatada.
static func strip_mesh(width: float, length: float) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, ESPESSURA, length)
	return mesh

## Cunha no chão, saindo da âncora. Marca CONE.
##
## Antes o cone era desenhado como uma faixa retangular: um golpe que pega 90°
## à frente aparecia como uma linha fina, e o jogador aprendia a mirar num
## formato que não é o do golpe.
static func cone(
		parent: Node, origin: Vector3, direction: Vector3,
		length: float, angle_degrees: float, color: Color
) -> AbilityTelegraph:
	var node := _build(parent, wedge_mesh(length, angle_degrees), color)
	_plant(node, origin, direction)
	return node

## Trapézio no chão: estreito perto, largo longe, com um buraco colado nos pés.
static func trapezoid(
		parent: Node, origin: Vector3, direction: Vector3,
		near_distance: float, near_width: float,
		length: float, far_width: float, color: Color
) -> AbilityTelegraph:
	var node := _build(
		parent,
		trapezoid_mesh(near_distance, near_width, length, far_width),
		color
	)
	_plant(node, origin, direction)
	return node

# ---------------------------------------------------------------- interno

## Planta um nó na âncora, com o -Z local apontando para a direção.
##
## As malhas de cunha e trapézio são construídas ao longo do -Z porque é para
## lá que `look_at` aponta. Montar a matriz de rotação à mão já custou uma
## sessão neste projeto — ver `CLAUDE.md`.
static func _plant(node: AbilityTelegraph, origin: Vector3, direction: Vector3) -> void:
	node.global_position = Vector3(origin.x, ALTURA_DO_CHAO, origin.z)
	var plana: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if plana.length_squared() <= 0.000001:
		return
	node.look_at(node.global_position + plana.normalized(), Vector3.UP)

## Setor circular achatado, com o vértice na origem e abrindo para o -Z.
##
## Público — e `_trapezoid_mesh` também — porque a geometria DESENHADA tem que
## bater com a geometria que ACERTA (`AbilityShape._in_cone`), e essa é uma
## conferência de matemática pura, sem cena. Sem isso, `cone()` devolvendo o
## mesmo que `line()` passava verde em tudo.
static func wedge_mesh(radius: float, angle_degrees: float) -> ArrayMesh:
	var segmentos: int = clampi(int(angle_degrees / 6.0), 3, 48)
	var meio: float = deg_to_rad(clampf(angle_degrees, 1.0, 359.0)) * 0.5
	var vertices := PackedVector3Array()
	for i: int in segmentos:
		var a0: float = -meio + 2.0 * meio * (float(i) / float(segmentos))
		var a1: float = -meio + 2.0 * meio * (float(i + 1) / float(segmentos))
		vertices.append(Vector3.ZERO)
		vertices.append(Vector3(sin(a0), 0.0, -cos(a0)) * radius)
		vertices.append(Vector3(sin(a1), 0.0, -cos(a1)) * radius)
	return _surface(vertices)

## Quadrilátero que alarga com a distância, em dois triângulos.
static func trapezoid_mesh(
		near_distance: float, near_width: float,
		far_distance: float, far_width: float
) -> ArrayMesh:
	var perto: float = near_width * 0.5
	var longe: float = far_width * 0.5
	var a := Vector3(-perto, 0.0, -near_distance)
	var b := Vector3(perto, 0.0, -near_distance)
	var c := Vector3(longe, 0.0, -far_distance)
	var d := Vector3(-longe, 0.0, -far_distance)
	return _surface(PackedVector3Array([a, b, c, a, c, d]))

## Malha de triângulos sem normal nem UV. O material é `UNSHADED` e sem
## textura, então declarar os dois só ocuparia memória.
static func _surface(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
	instance.layers = CAMADAS_DE_RENDER

	var node := AbilityTelegraph.new()
	node._material = material
	node.add_child(instance)
	parent.add_child(node)
	return node
