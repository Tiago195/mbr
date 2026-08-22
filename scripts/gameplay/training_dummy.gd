extends StaticBody3D

## Boneco de treino — Fase 2.3.
##
## Existe para responder ao critério da fase: "consigo matar um boneco de
## treino clicando nele?". Não ataca, não se move, não pensa.
##
## O retorno visual é deliberadamente cru — escurecer e sumir. Indicador de
## verdade é Fase 3.4.

## Segundos até renascer. <= 0 mantém morto até reiniciar a cena.
## Existe para o teste ser repetível sem rodar o jogo de novo a cada morte.
@export var respawn_delay: float = 4.0

## Cor com vida cheia e cor à beira da morte.
@export var healthy_color: Color = Color(0.80, 0.78, 0.72)
@export var hurt_color: Color = Color(0.55, 0.10, 0.08)

@onready var _combatant: Combatant = $Combatant
@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _material: StandardMaterial3D
var _respawn_timer: float = 0.0

func _ready() -> void:
	# Duplicar o material: sem isto, todos os bonecos compartilham a mesma
	# instância e escurecem juntos quando um leva dano.
	var source: Material = _mesh.material_override
	if source is StandardMaterial3D:
		_material = (source as StandardMaterial3D).duplicate()
	else:
		_material = StandardMaterial3D.new()
	_mesh.material_override = _material

	_combatant.damaged.connect(_on_damaged)
	_combatant.health.changed.connect(_on_health_changed)
	_combatant.died.connect(_on_died)
	_refresh_color()

func _process(delta: float) -> void:
	if _respawn_timer <= 0.0:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn()

func _on_damaged(result: DamageResult) -> void:
	# Console em vez de número flutuante: nesta fase o que importa é conferir
	# que a fórmula está sendo exercida com os valores certos.
	print("[dummy] -%.1f%s  vida %.1f/%.1f%s" % [
		result.damage_to_health,
		" CRIT" if result.was_critical else "",
		_combatant.health.current,
		_combatant.health.maximum(),
		"  MORREU" if result.killed else "",
	])

func _on_health_changed(_current: float, _maximum: float) -> void:
	_refresh_color()

func _on_died() -> void:
	visible = false
	# Sai da camada de colisão para não bloquear passagem nem ser mirado
	# enquanto está morto.
	collision_layer = 0
	if respawn_delay > 0.0:
		_respawn_timer = respawn_delay

func _respawn() -> void:
	_combatant.health.reset()
	collision_layer = 2
	visible = true
	print("[dummy] renasceu")

func _refresh_color() -> void:
	if _material == null:
		return
	_material.albedo_color = hurt_color.lerp(
		healthy_color, _combatant.health.fraction()
	)
