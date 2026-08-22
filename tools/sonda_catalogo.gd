extends SceneTree

## Sonda: carrega o corpus traduzido e imprime o que veio.
##
## A suíte prova que carrega e conjura; isto responde "quanto" e "com que
## cara", que é o que se quer olhar ao mexer no tradutor.
##
## Uso: godot --headless --path . --script res://tools/sonda_catalogo.gd

func _init() -> void:
	var habilidades := AbilityCatalog.new()
	habilidades.load_from()
	var itens := ItemCatalog.new()
	itens.load_from(ItemCatalog.CAMINHO_PADRAO, habilidades)

	print("[cat] habilidades: %d carregadas, %d descartadas, %d grupos" % [
		habilidades.loaded, habilidades.skipped, habilidades.by_group.size()
	])
	print("[cat] itens: %d carregados, %d descartados, %d linhas, %d ativas sem alvo" % [
		itens.loaded, itens.skipped, itens.by_line.size(), itens.unresolved_actives
	])

	var mostrados: int = 0
	for id: StringName in habilidades.by_id:
		var ability: Ability = habilidades.by_id[id]
		if ability.pulses.size() >= 3 and mostrados < 3:
			print("[cat] %s -> %s" % [id, ability.describe()])
			mostrados += 1
	quit(0)
