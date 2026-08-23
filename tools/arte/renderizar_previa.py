# -*- coding: utf-8 -*-
"""Renderiza folhas de contato do personagem, para OLHAR antes de integrar.

Rodar:
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" ^
        --background --python tools/arte/renderizar_previa.py

Saida: `arte/previa/*.png` — uma imagem por animacao, com seis instantes dela
lado a lado, mais `pose.png` com o repouso de frente, de lado e de tres-quartos.

## Por que existe

`gerar_personagem.py` imprimiu "11 ossos, 8 animacoes, 88 KB" e isso nao diz
NADA sobre o boneco estar de pe, ter proporcao de gente ou o salto sair do
chao. E a licao 1 do projeto aplicada a arte: cobertura silenciosa e
indistinguivel de cobertura errada, e a unica forma de saber se um desenho
ficou bom e desenhar e olhar.

## Ele importa o `.glb`, nao a cena

De proposito. Renderizar a cena que o gerador acabou de montar provaria que o
gerador monta; renderizar o ARQUIVO EXPORTADO prova o que a Godot vai receber
— nome de osso, nome de animacao, eixo de cima e tudo que a exportacao pode ter
perdido no caminho.

## A folha de contato e uma cena so

Seis copias do boneco, cada uma congelada num instante diferente da animacao,
enfileiradas. E um render so por animacao, e o olho le o movimento inteiro numa
imagem — que e o que video nao da quando se quer comparar o quadro 4 com o 13.
"""

from __future__ import annotations

import math
import os
import sys

import bpy

AMOSTRAS = 6
## Distancia entre as copias da folha de contato, em metros. Um pouco mais que
## a largura do boneco: encostadas, as silhuetas se confundem.
PASSO = 1.1
## Altura do enquadramento, em metros. Tem que caber o salto, que sobe 55 cm
## acima de um corpo de 1,75 m.
ALTURA_DA_CENA = 2.9
## Quanto do subsolo entra no enquadramento, em metros. Sem folga o pe fica
## exatamente na borda de baixo e nao da para ver se ele toca o chao.
FOLGA_ABAIXO = 0.30
LARGURA_POR_AMOSTRA = 260
## Giro das copias nas folhas de animacao, em graus. Nao e capricho: de frente,
## um golpe que avanca para -Y vem na direcao da camera e some por
## encurtamento. Tres-quartos mostra o avanco E a silhueta.
GIRO_DA_ANIMACAO = 70.0


def caminho_raiz() -> str:
	return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


## O importador de glTF do Blender deixa objetos auxiliares numa coleção com
## este nome. Aqui ele cria uma `Icosphere` de 2 m na origem — e ela ESTÁ na
## cena, então entra no render.
COLECAO_AUXILIAR = "glTF_not_exported"


def importar(glb: str) -> tuple:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=glb)

	# Sem isto a bolha auxiliar aparece no meio da folha de contato. Já
	# apareceu: seis dela, e a primeira leitura foi "as cópias estão saindo
	# deformadas" — porque a escolha da malha abaixo era "a última que achar",
	# e a última era ela.
	for objeto in list(bpy.data.objects):
		if any(c.name == COLECAO_AUXILIAR for c in objeto.users_collection):
			bpy.data.objects.remove(objeto, do_unlink=True)

	armature = None
	malha = None
	for objeto in bpy.data.objects:
		if objeto.type == "ARMATURE":
			armature = objeto
	for objeto in bpy.data.objects:
		# A malha do personagem é a que o ESQUELETO deforma. Escolher por tipo
		# aceita qualquer malha que exista na cena por acidente; escolher pelo
		# modificador só aceita a certa.
		if objeto.type != "MESH":
			continue
		for modificador in objeto.modifiers:
			if modificador.type == "ARMATURE" and modificador.object is armature:
				malha = objeto
	if armature is None or malha is None:
		raise SystemExit("[previa] o .glb nao trouxe esqueleto com malha presa nele")
	return armature, malha


def acoes_do(armature: bpy.types.Object) -> list:
	"""As acoes do arquivo, com o nome que a Godot vai ver.

	O importador de glTF prefixa o nome do objeto (`Esqueleto|andando`) quando
	a animacao vem de uma acao nomeada. O que interessa e o sufixo — e ele que
	o `AnimationPlayer` expoe.
	"""
	achadas = []
	for acao in bpy.data.actions:
		nome = acao.name.split("|")[-1]
		achadas.append((nome, acao))
	achadas.sort(key=lambda par: par[0])
	return achadas


def usar(armature: bpy.types.Object, acao: bpy.types.Action) -> None:
	if armature.animation_data is None:
		armature.animation_data_create()
	armature.animation_data.action = acao
	# **Blender 4.4+ exige o slot.** Atribuir a acao sem ligar o slot deixa o
	# esqueleto parado e o render sai com seis copias identicas — que parece
	# animacao sem amplitude, nao erro de API.
	if hasattr(armature.animation_data, "action_slot") and len(acao.slots) > 0:
		armature.animation_data.action_slot = acao.slots[0]


def congelar(armature, malha, deslocamento: float, giro: float = 0.0) -> list:
	"""Uma copia do boneco na pose ATUAL, parada, deslocada para o lado."""
	copia_arm = armature.copy()
	copia_arm.data = armature.data
	bpy.context.collection.objects.link(copia_arm)
	# Sem isto a copia continua ligada a acao e se move junto com a cena — as
	# seis ficariam na mesma pose, a do ultimo quadro renderizado.
	copia_arm.animation_data_clear()

	for osso in copia_arm.pose.bones:
		origem = armature.pose.bones[osso.name]
		osso.rotation_mode = origem.rotation_mode
		osso.rotation_euler = origem.rotation_euler
		osso.rotation_quaternion = origem.rotation_quaternion
		osso.location = origem.location
		osso.scale = origem.scale

	copia_malha = malha.copy()
	copia_malha.data = malha.data
	bpy.context.collection.objects.link(copia_malha)
	copia_malha.parent = copia_arm
	copia_malha.matrix_parent_inverse = malha.matrix_parent_inverse.copy()
	for modificador in copia_malha.modifiers:
		if modificador.type == "ARMATURE":
			modificador.object = copia_arm

	copia_arm.location.x += deslocamento
	# **Modo de rotacao antes do angulo.** O importador de glTF deixa os
	# objetos em QUATERNION, e escrever `rotation_euler` nesse modo nao faz
	# nada — nem erro. Foi assim que a folha de repouso saiu com as tres
	# colunas identicas, todas de frente.
	copia_arm.rotation_mode = "XYZ"
	copia_arm.rotation_euler.z = math.radians(giro)
	return [copia_arm, copia_malha]


def montar_chao(largura: float) -> bpy.types.Object:
	"""Uma faixa escura em z=0.

	Nao e enfeite: sem uma linha de chao nao da para julgar se o salto sobe, se
	o quique da caminhada existe, nem se o boneco esta afundado no piso — que e
	o erro de eixo mais comum ao exportar.
	"""
	# **Caixa, não plano.** A câmera é ortográfica e olha na horizontal: um plano
	# em z=0 fica exatamente de perfil e some. A primeira versão era plano, e a
	# imagem saiu sem chão nenhum — sem erro, sem aviso.
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=(largura * 0.5, 0.0, -0.03))
	chao = bpy.context.active_object
	chao.name = "Chao"
	chao.scale = (largura + 4.0, 4.0, 0.06)
	material = bpy.data.materials.new("chao")
	material.use_nodes = True
	bsdf = material.node_tree.nodes.get("Principled BSDF")
	if bsdf is not None:
		bsdf.inputs["Base Color"].default_value = (0.18, 0.19, 0.22, 1.0)
	# O Workbench le a cor de viewport, nao o no. Sem isto o chao sai branco.
	material.diffuse_color = (0.18, 0.19, 0.22, 1.0)
	chao.data.materials.append(material)
	return chao


def montar_camera(largura: float) -> bpy.types.Object:
	bpy.ops.object.camera_add(
		location=(largura * 0.5, -12.0, ALTURA_DA_CENA * 0.5 - FOLGA_ABAIXO)
	)
	camera = bpy.context.active_object
	camera.rotation_euler = (1.5707963, 0.0, 0.0)
	camera.data.type = "ORTHO"
	camera.data.ortho_scale = largura + 0.6
	bpy.context.scene.camera = camera
	return camera


def preparar_render(largura_mundo: float, largura_px: int) -> None:
	cena = bpy.context.scene
	# Workbench: rapido, sem GPU, sem ruido, e mostra a SILHUETA — que e o que
	# se esta julgando. EEVEE aqui so acrescentaria variavel.
	cena.render.engine = "BLENDER_WORKBENCH"
	sombreamento = cena.display.shading
	sombreamento.light = "STUDIO"
	sombreamento.color_type = "MATERIAL"
	sombreamento.show_shadows = True
	sombreamento.show_cavity = True
	cena.render.resolution_x = largura_px
	cena.render.resolution_y = max(
		120, int(largura_px * ALTURA_DA_CENA / max(largura_mundo, 0.001))
	)
	cena.render.film_transparent = False
	if cena.world is None:
		cena.world = bpy.data.worlds.new("Mundo")
	cena.world.use_nodes = True
	fundo = cena.world.node_tree.nodes.get("Background")
	if fundo is not None:
		fundo.inputs["Color"].default_value = (0.55, 0.60, 0.68, 1.0)


def limpar_copias(copias: list) -> None:
	for objeto in copias:
		bpy.data.objects.remove(objeto, do_unlink=True)


def quadros_de(acao: bpy.types.Action) -> list:
	inicio, fim = acao.frame_range
	inicio, fim = int(inicio), int(fim)
	if fim <= inicio:
		return [inicio] * AMOSTRAS
	# O ultimo quadro de um ciclo repete o primeiro; amostrar ate ele gastaria
	# uma das seis colunas mostrando de novo o que a primeira ja mostrou.
	ultimo = fim - 1 if fim - inicio > AMOSTRAS else fim
	passo = (ultimo - inicio) / float(AMOSTRAS - 1)
	return [int(round(inicio + passo * i)) for i in range(AMOSTRAS)]


def _render(nome: str, destino: str, armature, malha, copias, colunas: int) -> str:
	# A largura vem do NUMERO DE COLUNAS, nao de uma constante: a folha de
	# repouso tem tres e a de animacao tem seis, e fixar em seis deixava a
	# metade direita da imagem vazia.
	largura = PASSO * (colunas + 1)
	chao = montar_chao(largura)
	camera = montar_camera(largura)
	preparar_render(largura + 0.6, LARGURA_POR_AMOSTRA * colunas)

	# O boneco original fica na cena para as copias lerem a pose dele, mas nao
	# pode APARECER: ele esta na origem, fora da fila, e entraria na imagem
	# como uma setima coluna torta.
	armature.hide_render = True
	malha.hide_render = True
	caminho = os.path.join(destino, nome + ".png")
	bpy.context.scene.render.filepath = caminho
	bpy.ops.render.render(write_still=True)
	armature.hide_render = False
	malha.hide_render = False

	limpar_copias(copias + [chao, camera])
	return caminho


def folha(armature, malha, nome: str, acao, destino: str) -> str:
	usar(armature, acao)
	copias = []
	for coluna, quadro in enumerate(quadros_de(acao)):
		bpy.context.scene.frame_set(quadro)
		copias.extend(congelar(
			armature, malha, PASSO * (coluna + 1), GIRO_DA_ANIMACAO
		))
	return _render(nome, destino, armature, malha, copias, AMOSTRAS)


def folha_de_pose(armature, malha, destino: str) -> str:
	"""Repouso de frente, de lado e de tres-quartos.

	Tres angulos porque proporcao mente de frente: um tronco fino demais so
	aparece de perfil, e um braco colado ao corpo so aparece de vies.
	"""
	if armature.animation_data is not None:
		armature.animation_data.action = None
	for osso in armature.pose.bones:
		osso.rotation_euler = (0.0, 0.0, 0.0)
		osso.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
		osso.location = (0.0, 0.0, 0.0)

	copias = []
	for coluna, giro in enumerate((0.0, 90.0, 45.0)):
		copias.extend(congelar(armature, malha, PASSO * (coluna + 1), giro))
	return _render("pose", destino, armature, malha, copias, 3)


def main() -> int:
	raiz = caminho_raiz()
	glb = os.path.join(raiz, "arte", "personagem.glb")
	if not os.path.exists(glb):
		print("[previa] falta %s — rode gerar_personagem.py antes" % glb)
		return 1

	destino = os.path.join(raiz, "arte", "previa")
	os.makedirs(destino, exist_ok=True)

	armature, malha = importar(glb)
	acoes = acoes_do(armature)
	print("[previa] %d ossos, %d animacoes: %s" % (
		len(armature.pose.bones), len(acoes), ", ".join(n for n, _ in acoes),
	))

	folha_de_pose(armature, malha, destino)
	for nome, acao in acoes:
		folha(armature, malha, nome, acao, destino)

	print("[previa] %d imagens em %s" % (len(acoes) + 1, destino))
	return 0


if __name__ == "__main__":
	sys.exit(main())
