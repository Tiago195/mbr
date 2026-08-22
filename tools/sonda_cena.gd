extends SceneTree

## Sonda: instancia a cena principal, roda alguns quadros DE VERDADE e sai.
##
## Serve para pegar erro de tempo de execução que só aparece com a cena montada
## e andando — nó faltando, `@export` apontando para o nada, sinal conectado a
## método que não existe, `_ready`/`_physics_process` estourando. A suíte de
## teste não pega nada disso: ela só toca em `core/`.
##
## **Já foi teatro.** A primeira versão tinha um laço `for i in range(30)` que
## não avançava quadro nenhum — só instanciava e imprimia. Provava carga de
## recurso, não execução, e o nome dizia outra coisa. Agora o avanço vem de
## `_process`, que é o único jeito de um `SceneTree` deixar o motor rodar.
##
## Uso: godot --headless --path . --script res://tools/sonda_cena.gd

const QUADROS: int = 30

var _quadros: int = 0
var _cena: Node = null

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		print("[sonda] FALHOU: main.tscn não carregou")
		quit(1)
		return
	_cena = packed.instantiate()
	root.add_child(_cena)
	current_scene = _cena

## Devolver `true` encerra o laço principal. Contamos quadros de verdade: cada
## chamada é um `_process` do motor, com `_physics_process` dos nós já tendo
## rodado.
func _process(_delta: float) -> bool:
	_quadros += 1
	if _quadros < QUADROS:
		return false
	_relatar()
	quit(0)
	return true

func _relatar() -> void:
	if _cena == null:
		return
	print("[sonda] %d quadros rodados, cena com %d filhos" % [
		_quadros, _cena.get_child_count()
	])
	var caster: Node = _cena.find_child("AbilityCaster", true, false)
	if caster == null:
		print("[sonda] AVISO: nenhum AbilityCaster na cena")
		return
	for slot: String in ["ability_q", "ability_w", "ability_e"]:
		var ability := caster.get(slot) as Ability
		if ability == null:
			print("[sonda] %s: VAZIO" % slot)
			continue
		print("[sonda] %s -> %s" % [slot, ability.describe()])
