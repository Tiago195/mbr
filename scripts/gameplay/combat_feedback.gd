class_name CombatFeedback
extends Node3D

## Barra de vida e números de dano de um combatente — Fase 2.4.
##
## Pendura-se no corpo, ao lado do `Combatant`, e só observa: escuta os sinais
## de `Health` e desenha. Nenhuma decisão de jogo passa por aqui — é o
## princípio de `03-sistemas-de-jogo.md`, "o nó visual observa o estado e
## desenha, nunca decide".
##
## A barra é montada em código em vez de virar uma cena `.tscn` porque é
## geometria trivial (dois quads) e um material por instância. Em cena, o
## material compartilhado faria todas as barras mudarem de cor juntas.

@export var bar_size: Vector2 = Vector2(1.1, 0.13)
@export var show_bar: bool = true
@export var show_numbers: bool = true

@export_group("Cores")
@export var color_full: Color = Color(0.25, 0.80, 0.35)
@export var color_empty: Color = Color(0.85, 0.15, 0.15)
@export var color_backdrop: Color = Color(0.05, 0.05, 0.06, 0.85)
@export var color_shield: Color = Color(0.80, 0.88, 0.95)
@export var color_damage: Color = Color(1.0, 0.95, 0.85)
@export var color_crit: Color = Color(1.0, 0.65, 0.15)

var _combatant: Combatant
var _fill: MeshInstance3D
var _fill_mesh: QuadMesh
var _fill_material: StandardMaterial3D
var _shield: MeshInstance3D
var _shield_mesh: QuadMesh

func _ready() -> void:
	_combatant = Combatant.of(get_parent())
	if _combatant == null:
		push_warning("CombatFeedback sem Combatant irmão em '%s'." % get_parent().name)
		return
	# Não depender da ordem de `_ready()` entre irmãos.
	_combatant.ensure_ready()

	if show_bar:
		_build_bar()
	_combatant.health.changed.connect(_on_health_changed)
	_combatant.damaged.connect(_on_damaged)
	_refresh_bar()

# ---------------------------------------------------------------- barra

func _build_bar() -> void:
	# Prioridade menor: o fundo desenha antes. Com `no_depth_test` nos dois,
	# deslocar em Z não decide ordem — quem decide é `render_priority`.
	var backdrop: MeshInstance3D = _make_quad(
		bar_size + Vector2(0.06, 0.06), color_backdrop, 4
	)
	add_child(backdrop)

	_fill = _make_quad(bar_size, color_full, 6)
	_fill_mesh = _fill.mesh as QuadMesh
	_fill_material = _fill.material_override as StandardMaterial3D
	add_child(_fill)

	# Escudo desenhado depois da vida, na mesma barra. Segmento separado e não
	# uma cor diferente do mesmo quad: escudo e vida sobem e descem por regras
	# distintas, e vê-los lado a lado é o que deixa claro quanto dano ainda
	# está absorvido.
	_shield = _make_quad(bar_size, color_shield, 7)
	_shield_mesh = _shield.mesh as QuadMesh
	add_child(_shield)

func _make_quad(size: Vector2, color: Color, priority: int) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	# Sem sombreamento: a barra não deve escurecer conforme o ângulo da luz.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = priority

	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.material_override = material
	return instance

## Encolhe a barra pela direita, ancorada na borda esquerda.
##
## O encolhimento é feito na GEOMETRIA — largura do quad mais `center_offset` —
## e não com `scale`/`position` do nó. Motivo: com `billboard_mode` ligado, o
## shader troca a base da matriz de modelo pela orientação da câmera e
## DESCARTA a escala do nó, a menos que `billboard_keep_scale` esteja ativo.
## O resultado era a barra andar para o lado sem encolher.
##
## Ligar `billboard_keep_scale` resolveria o sintoma, mas deixaria o
## deslocamento no X do mundo e a escala no X do billboard. Hoje coincidem
## porque a câmera não gira; quando girar, a barra deslizaria na diagonal.
## `center_offset` vive no espaço local da malha, que gira junto com o
## billboard — fica correto sob qualquer câmera.
func _refresh_bar() -> void:
	if _fill == null or _combatant == null:
		return
	var health: Health = _combatant.health
	var fraction: float = clampf(health.fraction(), 0.0, 1.0)

	_set_segment(_fill, _fill_mesh, 0.0, fraction)
	_fill_material.albedo_color = color_empty.lerp(color_full, fraction)

	# Escudo é desenhado SOBRE a vida, terminando na borda dela e crescendo
	# para a esquerda. Lê-se como "esta parte do que você tem é escudo".
	#
	# A primeira tentativa foi desenhá-lo no espaço depois da vida, e ela
	# falhava exatamente no caso mais comum: com vida cheia não sobra espaço
	# nenhum, o segmento nascia com largura zero e o escudo ficava invisível.
	# E vida cheia é quando se usa habilidade defensiva — antes de apanhar.
	var maximum: float = health.maximum()
	var shield_span: float = 0.0
	if maximum > 0.0:
		shield_span = clampf(health.shield / maximum, 0.0, 1.0)
	_set_segment(_shield, _shield_mesh, maxf(0.0, fraction - shield_span), fraction)

## Posiciona um trecho da barra entre duas frações, de 0 a 1.
##
## O quad é centrado, então além da largura é preciso deslocar o centro do
## segmento. Tudo na geometria, nunca em `scale`/`position` do nó: com
## billboard ligado a escala do nó é descartada (ver `CLAUDE.md`).
func _set_segment(node: MeshInstance3D, mesh: QuadMesh, from: float, to: float) -> void:
	var span: float = maxf(to - from, 0.0)
	# Quad de largura zero é malha degenerada; some com ele em vez disso.
	node.visible = span > 0.0
	if not node.visible:
		return
	var width: float = bar_size.x * span
	var center: float = (-0.5 + (from + to) * 0.5) * bar_size.x
	mesh.size = Vector2(width, bar_size.y)
	mesh.center_offset = Vector3(center, 0.0, 0.0)

# ---------------------------------------------------------------- sinais

func _on_health_changed(_current: float, _maximum: float) -> void:
	_refresh_bar()

func _on_damaged(result: DamageResult) -> void:
	if not show_numbers:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return

	var shown: float = result.damage_to_health + result.absorbed_by_shield
	FloatingText.spawn(
		scene_root,
		global_position + Vector3(randf_range(-0.25, 0.25), 0.15, 0.0),
		"%d" % roundi(shown),
		color_crit if result.was_critical else color_damage,
		result.was_critical
	)
