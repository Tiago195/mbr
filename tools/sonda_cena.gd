extends SceneTree

## Sonda: instancia a cena principal, roda alguns tiques e sai.
##
## Serve para pegar erro de tempo de execução que só aparece com a cena montada
## — nó faltando, `@export` apontando para o nada, sinal conectado a método que
## não existe. A suíte de teste não pega nada disso: ela só toca em `core/`.
##
## Uso: godot --headless --path . --script res://tools/sonda_cena.gd

const TICKS: int = 30

func _init() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		print("[sonda] FALHOU: main.tscn não carregou")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	_tick(scene)

func _tick(scene: Node) -> void:
	for i: int in range(TICKS):
		if not root.is_inside_tree():
			break
	print("[sonda] cena montada: %d filhos" % scene.get_child_count())
	_inspect(scene)
	quit(0)

func _inspect(scene: Node) -> void:
	var caster: Node = scene.find_child("AbilityCaster", true, false)
	if caster == null:
		print("[sonda] AVISO: nenhum AbilityCaster na cena")
		return
	for slot: String in ["ability_q", "ability_w", "ability_e"]:
		var ability := caster.get(slot) as Ability
		if ability == null:
			print("[sonda] %s: VAZIO" % slot)
			continue
		print("[sonda] %s -> %s" % [slot, ability.describe()])
