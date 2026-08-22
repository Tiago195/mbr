extends Camera3D

## Câmera isométrica travada que segue o alvo — Fase 1.3.
##
## O ângulo NÃO acompanha a rotação do personagem: a vista é travada, como no
## Royal Crown. A câmera só translada. Por isso ela não é filha do Player —
## se fosse, herdaria o `look_at` dele e giraria junto.

## Nó a seguir. Normalmente o Player.
@export var target_path: NodePath = NodePath("../Player")

## Deslocamento fixo em relação ao alvo. Define ângulo e distância da vista.
## O Y e o Z têm que bater com a rotação da câmera na cena, senão o
## enquadramento muda.
@export var offset: Vector3 = Vector3(0, 11, 8)

## Quanto maior, mais rápido a câmera alcança o alvo. 0 = não segue.
@export var smoothing: float = 8.0

var _target: Node3D

func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		push_warning("CameraRig sem alvo em '%s' — a câmera vai ficar parada." % target_path)
		return
	# Começa já enquadrado, senão o primeiro frame mostra a câmera deslizando
	# da origem até o jogador.
	global_position = _target.global_position + offset

func _process(delta: float) -> void:
	if _target == null:
		return
	var desired: Vector3 = _target.global_position + offset
	# Suavização exponencial em vez de `lerp(a, b, 0.1)` direto: esta forma é
	# independente de framerate. Com lerp de peso fixo, a câmera segue mais
	# rápido a 144 fps do que a 60, e o "peso" vira uma configuração que só
	# vale para a máquina onde foi ajustada.
	var weight: float = 1.0 - exp(-smoothing * delta)
	global_position = global_position.lerp(desired, weight)
