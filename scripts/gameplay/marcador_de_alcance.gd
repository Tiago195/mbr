class_name MarcadorDeAlcance
extends Node3D

## Anéis no chão dizendo até onde o personagem alcança.
##
## Existe pelo mesmo veredito que o `CombatLog`: *"tudo que vejo são formas"*.
## Alcance é o número que mais muda entre campeões — 2 m no Leo, 6 m na Bella —
## e era completamente invisível. Sem ele não dá para saber se a habilidade
## errou porque a mira estava torta ou porque o alvo estava longe demais, que
## são dois problemas diferentes com a mesma aparência: nada acontece.
##
## Dois anéis:
##
## - **O do ataque básico**, sempre visível, que vem de `attack_range` e é o
##   que decide quando o personagem para de perseguir
## - **O da habilidade apertada por último**, que aparece ao conjurar e some
##   junto com a marca, e vem de `cast_range`
##
## Camada visual pura: observa e desenha, nunca decide.

## Quantos segmentos formam o anel. 48 já não tem quina visível a 8 m.
const SEGMENTOS: int = 48

## Espessura do traço, em metros.
@export var espessura: float = 0.06

## Altura acima do chão. O mesmo valor da telegrafia, para os dois não
## brigarem por profundidade.
@export var altura: float = 0.03

@export var cor_ataque: Color = Color(0.85, 0.85, 0.90, 0.35)
@export var cor_habilidade: Color = Color(1.00, 0.85, 0.35, 0.45)

## Quanto o anel da habilidade fica na tela depois da conjuração.
@export var vida_do_anel: float = 1.2

var _combatant: Combatant
var _caster: AbilityCaster
var _anel_ataque: MeshInstance3D
var _anel_habilidade: MeshInstance3D
var _restante: float = 0.0
var _ultimo_alcance: float = -1.0

func _ready() -> void:
	_combatant = Combatant.of(get_parent())
	if _combatant == null:
		push_warning("MarcadorDeAlcance sem Combatant em '%s'." % get_parent().name)
		return
	_combatant.ensure_ready()

	_anel_ataque = _montar_anel(cor_ataque)
	_anel_habilidade = _montar_anel(cor_habilidade)
	_anel_habilidade.visible = false

	_caster = _achar_caster()
	if _caster != null:
		_caster.cast_attempted.connect(_ao_conjurar)

func _process(delta: float) -> void:
	if _combatant == null or _combatant.unit == null:
		return

	# O alcance do ataque básico muda ao trocar de campeão, e a malha é
	# refeita só quando ele muda — refazer todo quadro seria desperdício num nó
	# que existe para ser barato.
	var alcance: float = _combatant.stats.get_value(Stat.Id.ATTACK_RANGE)
	if not is_equal_approx(alcance, _ultimo_alcance):
		_ultimo_alcance = alcance
		_desenhar(_anel_ataque, alcance)

	if _restante <= 0.0:
		return
	_restante -= delta
	if _restante <= 0.0:
		_anel_habilidade.visible = false

func _ao_conjurar(
		_slot: AbilityBook.Slot, pedida: Ability, result: CastResult
) -> void:
	if pedida == null:
		return
	# A habilidade que SAIU, quando a corrente de combo trocou: é o alcance
	# dela que valeu.
	var saiu: Ability = result.ability if result != null and result.ability != null else pedida
	# **O alcance EFETIVO, não o de mira.** `cast_range` vem de `AI_SkillRange`,
	# que diz a que distância a IA usa a habilidade — não até onde ela pega. Em
	# 43 dos 119 espaços os dois divergem, e o anel com o número errado foi o
	# que fez o R do Leo parecer impossível de acertar: ele anuncia 4 m e pega
	# até 3.
	var alcance: float = saiu.effective_range()
	if alcance <= 0.0:
		# Zero quer dizer "sem limite" — desenhar um anel gigante mentiria.
		_anel_habilidade.visible = false
		_restante = 0.0
		return
	_desenhar(_anel_habilidade, alcance)
	_anel_habilidade.visible = true
	_restante = vida_do_anel

# ---------------------------------------------------------------- desenho

func _montar_anel(cor: Color) -> MeshInstance3D:
	var no := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = cor
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Sem teste de profundidade, como a telegrafia: o anel tem que aparecer
	# por cima do chão sem depender de deslocamento em Z.
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	no.material_override = material
	no.mesh = ArrayMesh.new()
	add_child(no)
	return no

## Refaz a malha do anel num raio dado.
##
## Um anel de triângulos, e não uma linha: `PRIMITIVE_LINES` ignora espessura
## na maioria dos drivers, e um traço de um pixel some no chão claro.
func _desenhar(no: MeshInstance3D, raio: float) -> void:
	var vertices := PackedVector3Array()
	var interno: float = maxf(raio - espessura * 0.5, 0.01)
	var externo: float = raio + espessura * 0.5
	for passo: int in SEGMENTOS:
		var a: float = TAU * float(passo) / float(SEGMENTOS)
		var b: float = TAU * float(passo + 1) / float(SEGMENTOS)
		var ia := Vector3(cos(a) * interno, altura, sin(a) * interno)
		var ea := Vector3(cos(a) * externo, altura, sin(a) * externo)
		var ib := Vector3(cos(b) * interno, altura, sin(b) * interno)
		var eb := Vector3(cos(b) * externo, altura, sin(b) * externo)
		vertices.append_array([ia, ea, eb, ia, eb, ib])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var malha := no.mesh as ArrayMesh
	malha.clear_surfaces()
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _achar_caster() -> AbilityCaster:
	var host: Node = get_parent()
	if host == null:
		return null
	for child: Node in host.get_children():
		if child is AbilityCaster:
			return child
	return null
