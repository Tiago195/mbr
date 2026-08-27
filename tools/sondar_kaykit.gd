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
##      termo que engloba, não a lista de propriedades (lição 10);
##   5. o vocabulário ESTENDIDO (`VocabularioDeAnimacao.Estendido`) toca, não
##      roda em laço, e cada verbo declara reserva universal;
##   6. o equipamento por campeão veste: espada no padrão, espada e escudo no
##      Leo, besta e aljava presas por osso no MARKSMAN — com MALHA dentro do
##      prendedor, porque prendedor vazio é arma invisível sem erro.
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

	# O vocabulário ESTENDIDO (decisão 25, camada nova): o modelo padrão fala
	# cada verbo, nenhum roda em laço — golpe que se repete sozinho não é
	# golpe —, e cada um declara reserva UNIVERSAL, que é o que mantém o
	# corpo gerado funcional quando pede `disparo` sem ter besta.
	for nome: StringName in VocabularioDeAnimacao.Estendido.VERBOS:
		if not animador.has_animation(nome):
			falhas.append("o verbo estendido '%s' não toca em nada" % nome)
			continue
		if boneco.duracao_de(nome) <= 0.0:
			falhas.append("o verbo estendido '%s' tem duração zero" % nome)
		if animador.get_animation(nome).loop_mode != Animation.LOOP_NONE:
			falhas.append(
				"o verbo estendido '%s' roda em laço — golpe não repete" % nome
			)
		var reserva: Variant = VocabularioDeAnimacao.RESERVA_DO_ESTENDIDO.get(nome)
		if reserva == null or not VocabularioDeAnimacao.TODOS.has(reserva):
			falhas.append(
				"o verbo estendido '%s' está sem reserva universal" % nome
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

	falhas.append_array(_sondar_equipamentos(boneco))

	return falhas

## A arma por campeão: o corpo veste o que o papel — ou a exceção — manda.
##
## Depois da medição da caixa, de propósito: a caixa é do corpo COMUM, e uma
## besta presa entraria na medida. No fim, o corpo volta ao equipamento
## padrão pela mesma razão.
func _sondar_equipamentos(boneco: Boneco) -> Array[String]:
	var falhas: Array[String] = []

	# O padrão: espada na mão, escudo guardado, golpe de lâmina.
	if not _prop_visivel(boneco, &"1H_Sword"):
		falhas.append("o equipamento padrão está sem a espada visível")
	if _prop_visivel(boneco, &"Round_Shield"):
		falhas.append("o equipamento padrão mostra escudo sem campeão pedir")
	if boneco.ataque_e_disparo():
		falhas.append("o equipamento padrão não deveria atacar com disparo")

	# A exceção por campeão: o E do Leo ARREMESSA o escudo, então o corpo
	# dele precisa ter um escudo para arremessar.
	boneco.equipar_para(&"leo", &"FIGHTER")
	if not _prop_visivel(boneco, &"1H_Sword"):
		falhas.append("o Leo está sem a espada")
	if not _prop_visivel(boneco, &"Round_Shield"):
		falhas.append("o Leo está sem o escudo — o E dele arremessa o quê?")

	# A regra por papel: MARKSMAN larga a espada e ganha besta no encaixe da
	# mão e aljava no peito — props EXTERNOS, presos por BoneAttachment3D.
	boneco.equipar_para(&"bella", &"MARKSMAN")
	if _prop_visivel(boneco, &"1H_Sword"):
		falhas.append("MARKSMAN ainda segura a espada")
	if not boneco.ataque_e_disparo():
		falhas.append("MARKSMAN deveria atacar com disparo")
	for osso: String in ["handslot.r", "chest"]:
		if not _tem_prop_preso(boneco, osso):
			falhas.append("MARKSMAN sem prop preso no osso '%s'" % osso)

	boneco.equipar_para(&"", &"")
	if not _prop_visivel(boneco, &"1H_Sword"):
		falhas.append("o corpo não voltou ao equipamento padrão")
	return falhas

func _prop_visivel(boneco: Boneco, nome: StringName) -> bool:
	var no: MeshInstance3D = boneco.no_de_prop(nome)
	return no != null and no.visible

## Há um `BoneAttachment3D` neste osso com uma MALHA dentro? Malha, e não só
## filho: um `.gltf` que falhou ao instanciar deixaria o prendedor vazio, e
## prendedor vazio é besta invisível sem erro nenhum.
func _tem_prop_preso(boneco: Boneco, osso: String) -> bool:
	var esqueleto: Skeleton3D = boneco.esqueleto()
	if esqueleto == null:
		return false
	for filho: Node in esqueleto.get_children():
		var preso: BoneAttachment3D = filho as BoneAttachment3D
		if preso == null:
			continue
		var nome: String = String(preso.bone_name).replace("_", ".")
		if nome != osso.replace("_", "."):
			continue
		if _tem_malha(preso):
			return true
	return false

func _tem_malha(no: Node) -> bool:
	if no is MeshInstance3D and (no as MeshInstance3D).mesh != null:
		return true
	for filho: Node in no.get_children():
		if _tem_malha(filho):
			return true
	return false

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
