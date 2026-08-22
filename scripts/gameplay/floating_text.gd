class_name FloatingText
extends Label3D

## Número de dano que sobe e some — Fase 2.4.
##
## Vive solto na cena, não preso ao alvo: se fosse filho do corpo, o número
## acompanharia quem levou o golpe e ficaria ilegível quando o alvo se move ou
## morre. Nasce na posição do impacto e a partir daí é independente.

var _lifetime: float = 0.9
var _elapsed: float = 0.0
var _rise_speed: float = 1.2

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _lifetime:
		queue_free()
		return
	position.y += _rise_speed * delta
	# Some só na segunda metade da vida: sumir desde o primeiro frame deixa o
	# número ilegível justamente quando ele importa.
	var progress: float = _elapsed / _lifetime
	modulate.a = 1.0 if progress < 0.5 else 1.0 - (progress - 0.5) * 2.0

## Cria e insere um número na cena.
##
## `parent` deve ser um nó estável — a raiz da cena — e não o alvo do golpe.
static func spawn(
		parent: Node,
		at: Vector3,
		content: String,
		color: Color,
		emphasis: bool = false,
		lifetime: float = 0.9
) -> FloatingText:
	var label := FloatingText.new()
	label.text = content
	label.modulate = color
	label._lifetime = lifetime
	label.font_size = 96 if emphasis else 64
	label.outline_size = 24 if emphasis else 16
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Sem teste de profundidade: número atrás de parede ainda precisa ser lido,
	# senão o jogador perde a informação exatamente na hora da luta confusa.
	label.no_depth_test = true
	label.render_priority = 10
	label.outline_render_priority = 9
	parent.add_child(label)
	label.global_position = at
	return label
