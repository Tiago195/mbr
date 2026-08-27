extends SceneTree

## O modelo padrão do jogo responde ao vocabulário INTEIRO?
##
## Existe pela mesma ferida de sempre — lição 9 do `CLAUDE.md`: o apelido de
## clipe (`Boneco._apelidar_clipes`) é camada que nenhuma outra ferramenta
## roda. `arte/personagem.glb` era gerado, conferido e rastreado, e o jogo não
## o carregava; um mapa `NO_KAYKIT` com um nome errado reproduziria o mesmo
## defeito — `tocar` devolvendo `false` calado para um verbo — sem que suíte,
## sonda de campeões ou `conferir_numeros.py` ficassem vermelhos.
##
## O que ela confere, sobre o `Boneco` REAL montado pelo caminho real:
##   1. o modelo padrão carrega com esqueleto e `AnimationPlayer`;
##   2. cada um dos verbos de `VocabularioDeAnimacao.TODOS` toca — apelidado
##      ou nativo — e tem duração positiva;
##   3. ciclo é ciclo e golpe é golpe: o `loop_mode` de cada verbo bate com
##      `CICLOS`. Isto também pega o par de verbos que divide um clipe e
##      DISCORDA sobre ser ciclo — o loop mora no recurso compartilhado, e o
##      segundo a escrever venceria em silêncio;
##   4. o corpo tem altura de personagem (1,4 a 2,8 m — ver o comentário na
##      medição), medida por `global_transform * AABB` de cada malha — o
##      termo que engloba, não a lista de propriedades (lição 10).
##
## O que ela NÃO sabe: se a silhueta diz o que o clipe é, e para onde o rosto
## aponta — o Knight não tem as caixas nomeadas que `sondar_campeoes.gd` mede
## no boneco gerado. Frente de modelo novo é conferência de olho humano, e o
## `CLAUDE.md` guarda a cicatriz.
##
## Rodar:
##     godot --headless --path . --script res://tools/sondar_kaykit.gd

func _init() -> void:
	process_frame.connect(_rodar, CONNECT_ONE_SHOT)

func _rodar() -> void:
	# `Variant`, e o `quit()` fora da função que pode estourar: erro em tempo
	# de execução aborta só a função onde ocorreu, e um `SceneTree` headless
	# sem `quit` roda para sempre.
	var falhas: Variant = _sondar()
	print("")
	if not falhas is Array:
		print("  [FALHOU] a sonda do modelo estourou (veja SCRIPT ERROR acima)")
		quit(1)
		return
	var lista: Array = falhas as Array
	if lista.is_empty():
		print("  [ok] o modelo padrão fala o vocabulário inteiro")
		quit(0)
		return
	for falha: String in lista:
		print("  [FALHOU] %s" % falha)
	quit(1)

func _sondar() -> Array[String]:
	var falhas: Array[String] = []

	var boneco: Boneco = (load("res://scripts/gameplay/boneco.gd") as GDScript).new()
	root.add_child(boneco)

	var animador: AnimationPlayer = boneco.animador()
	if animador == null:
		return ["o modelo padrão carregou sem AnimationPlayer"] as Array[String]
	if boneco.esqueleto() == null:
		falhas.append("o modelo padrão carregou sem Skeleton3D")

	print("  modelo: %s" % boneco.modelo)
	print("  clipes na biblioteca: %d" % animador.get_animation_list().size())

	for nome: StringName in VocabularioDeAnimacao.TODOS:
		if not animador.has_animation(nome):
			falhas.append("o verbo '%s' não toca em nada" % nome)
			continue
		if boneco.duracao_de(nome) <= 0.0:
			falhas.append("o verbo '%s' tem duração zero" % nome)
		var clipe: Animation = animador.get_animation(nome)
		var em_ciclo: bool = clipe.loop_mode != Animation.LOOP_NONE
		var devia: bool = VocabularioDeAnimacao.CICLOS.has(nome)
		if em_ciclo != devia:
			falhas.append(
				"o verbo '%s' %s ciclo e o clipe %s" % [
					nome,
					"é" if devia else "não é",
					"roda em laço" if em_ciclo else "toca uma vez",
				]
			)

	var caixa: AABB = _caixa_do_corpo(boneco)
	var altura: float = caixa.size.y
	print("  caixa do corpo: %.3f x %.3f x %.3f m (pé em y=%.3f)" % [
		caixa.size.x, altura, caixa.size.z, caixa.position.y,
	])
	# A faixa era 1,2–2,4 quando o alvo era os 1,75 m da direção de arte — e
	# o usuário reprovou o 1,75 na tela em quinze segundos: numa câmera de
	# MOBA o chibi lia com metade da cápsula de treino (2,0 m). O alvo passou
	# a ser o tamanho autorado do pack, 2,467 m, e a faixa acompanha: piso
	# acima da metade da cápsula, teto pouco acima do autorado.
	if altura < 1.4 or altura > 2.8:
		falhas.append(
			"o corpo mede %.2f m — fora da faixa de personagem (1,4 a 2,8)"
			% altura
		)

	return falhas

## A caixa de TUDO que o corpo desenha, no espaço do próprio `Boneco`.
##
## `global_transform * AABB`, malha a malha — o termo que engloba raio,
## largura, altura e posição de uma vez, em vez de enumerá-los (lição 10).
func _caixa_do_corpo(boneco: Node3D) -> AABB:
	var caixa: AABB = AABB()
	var primeira: bool = true
	var fila: Array[Node] = [boneco]
	while not fila.is_empty():
		var no: Node = fila.pop_back()
		fila.append_array(no.get_children())
		var malha: MeshInstance3D = no as MeshInstance3D
		if malha == null or malha.mesh == null:
			continue
		# Malha escondida não desenha — as opções de empunhadura que o
		# `Boneco` apaga não entram na medida do corpo.
		if not malha.is_visible_in_tree():
			continue
		var no_mundo: AABB = malha.global_transform * malha.mesh.get_aabb()
		if primeira:
			caixa = no_mundo
			primeira = false
		else:
			caixa = caixa.merge(no_mundo)
	return caixa
