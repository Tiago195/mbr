# -*- coding: utf-8 -*-
"""Gera o personagem do jogo — malha, esqueleto e animações — no Blender.

Rodar:
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" ^
        --background --python tools/arte/gerar_personagem.py

Saída: `arte/personagem.glb`, que a Godot importa já com `Skeleton3D` e
`AnimationPlayer` montados, e `arte/fonte/personagem.blend`, que é o arquivo
para ABRIR e olhar — fora do alcance do importador da engine, de propósito.

## Por que existe

O usuário não conseguia testar o motor: *"não sei se estou usando a mesma
habilidade ou se são habilidades diferentes, tudo que vejo são formas"*, e
depois *"não consigo testar sem ver os personagens"*. As tentativas anteriores
— cápsula animada por procedimento, corpo de caixas articulado, malha extraída
do original — resolviam pedaços e nenhuma resolvia o todo: nenhuma tinha
ESQUELETO, e sem osso o gesto move a malha inteira, que lê como empurrão.

Este arquivo é a resposta, e é **conteúdo nosso**: nasce de código, entra no
repositório, e não depende de asset de ninguém.

## Feio de propósito

Caixas parenteadas rigidamente a ossos, sem deformação suave — um boneco de
madeira. É o critério declarado da Fase 1 (*"feio de propósito, um único modelo
para todos"*), e para a pergunta que precisa ser respondida — *o personagem fez
o quê?* — caixa com osso basta. Trocar isto por um modelo bonito depois é
trocar o `.glb`, sem tocar em código de jogo.

## Para onde ele olha, e por que isso tem cara

O boneco encara **-Y**, que a exportação glTF vira o **-Z** da Godot, que é a
frente lá. Nariz e viseira existem por isso: a primeira coisa que o usuário
reportou ao ver o personagem na tela foi *"está andando de costas"*, e num
corpo de caixas simétrico não há como o olho saber a diferença. Pé apontando
para a frente é a segunda pista, e funciona mesmo de longe.

## As poses são escritas em eixos do MUNDO

`X` inclina para a frente, `Y` tomba para o lado, `Z` gira em pé — sempre, para
qualquer osso. Não é o que o Blender guarda: lá a rotação é no espaço do osso,
onde o eixo que corre ao longo do osso é o `Y`, e o que é "girar em pé" para o
quadril é "abrir o braço" para o braço.

A primeira versão deste arquivo escreveu as poses direto no espaço do osso
achando que `Z` era o giro. O resultado passou por todas as ferramentas e só
apareceu ao renderizar: a estocada tombava o corpo de lado em vez de girar o
ombro. `_para_o_osso` faz a conversão, e por isso cada pose aqui pode ser lida
como "inclina 16 graus para a frente" sem depender de qual osso é.

## O que é gerado por número, e por quê

Cada animação é uma função de tempo escrita aqui. Ajustar amplitude é mudar uma
constante e rodar de novo — que é exatamente o ciclo que faltou quando a
caminhada procedural saiu com 4,5 cm de quique e ficou invisível na tela.
"""

from __future__ import annotations

import math
import os
import subprocess
import sys

import bpy
from mathutils import Euler, Vector

# --------------------------------------------------------------------------
# Medidas do corpo. **Nada aqui é gosto: é `docs/11-direcao-de-arte.md`.**
#
# `PROPORCAO` é a mediana medida em 27 campeões do original por
# `tools/arte/censo_do_original.py`, como fração da altura total. Mudar um
# número aqui muda o boneco E reprova `conferir_personagem.py` se sair da
# faixa medida — que é o que impede a direção de arte de virar enfeite.
#
# A altura de 1,75 m é a mediana do elenco (1,764) arredondada, e ela é a mesma
# para todo personagem de propósito: num battle royale isométrico o tamanho na
# tela é informação de alcance.
# --------------------------------------------------------------------------
ALTURA = 1.75

PROPORCAO = {
	"tornozelo": 0.093,
	"joelho": 0.283,
	"quadril": 0.485,
	"peito": 0.656,
	"pescoco": 0.763,
	"ombro": 0.725,        # altura da junta do ombro (pose T do original)
	"vao_dos_ombros": 0.175,
	"vao_dos_quadris": 0.129,
	# **Duas medidas, e elas não são a mesma.** `vao_das_maos` é junta a junta,
	# e para no PULSO; `envergadura` é ponta a ponta da malha e inclui a mão.
	# A diferença entre as duas — 0,266 da altura, 13% por lado — é mão, e é
	# muita mão: o original tem punho curto e mão grande.
	#
	# Publicar só a envergadura foi um erro caro: o boneco batia o número
	# esticando o antebraço 60% além do que o original tem, e a conferência
	# aprovava porque o total fechava. Número certo pelo motivo errado.
	"vao_das_maos": 0.629,
	"envergadura": 0.895,
}

Y_TORNOZELO = PROPORCAO["tornozelo"] * ALTURA
Y_JOELHO = PROPORCAO["joelho"] * ALTURA
Y_QUADRIL = PROPORCAO["quadril"] * ALTURA
Y_PEITO = PROPORCAO["peito"] * ALTURA
Y_PESCOCO = PROPORCAO["pescoco"] * ALTURA
Y_TOPO = ALTURA
Y_OMBRO = PROPORCAO["ombro"] * ALTURA
X_OMBRO = PROPORCAO["vao_dos_ombros"] * ALTURA * 0.5
X_QUADRIL = PROPORCAO["vao_dos_quadris"] * ALTURA * 0.5

# Do ombro ao PULSO sai do vão das mãos; do pulso à ponta, da envergadura.
# São dois ossos e uma mão, e não um braço comprido.
COMPRIMENTO_ATE_O_PULSO = (
	(PROPORCAO["vao_das_maos"] - PROPORCAO["vao_dos_ombros"]) * ALTURA * 0.5
)
COMPRIMENTO_DA_MAO = (
	(PROPORCAO["envergadura"] - PROPORCAO["vao_das_maos"]) * ALTURA * 0.5
)
Y_COTOVELO = Y_OMBRO - COMPRIMENTO_ATE_O_PULSO * 0.47
Y_PULSO = Y_OMBRO - COMPRIMENTO_ATE_O_PULSO
Y_PONTA_DA_MAO = Y_PULSO - COMPRIMENTO_DA_MAO

COMPRIMENTO_DO_PE = 0.24
COMPRIMENTO_DA_COXA = Y_QUADRIL - Y_JOELHO
COMPRIMENTO_DA_CANELA = Y_JOELHO - Y_TORNOZELO

## `(nome, cabeça, cauda, pai)`. A cauda de um osso é onde o próximo começa —
## é ela que dá a direção da rotação.
OSSOS = [
	("quadril",     (0.0, 0.0, Y_QUADRIL), (0.0, 0.0, Y_PEITO), None),
	("peito",       (0.0, 0.0, Y_PEITO), (0.0, 0.0, Y_PESCOCO), "quadril"),
	("cabeca",      (0.0, 0.0, Y_PESCOCO), (0.0, 0.0, Y_TOPO), "peito"),
	("braco_D",     (X_OMBRO, 0.0, Y_OMBRO), (X_OMBRO, 0.0, Y_COTOVELO), "peito"),
	("antebraco_D", (X_OMBRO, 0.0, Y_COTOVELO), (X_OMBRO, 0.0, Y_PULSO), "braco_D"),
	("mao_D",       (X_OMBRO, 0.0, Y_PULSO), (X_OMBRO, 0.0, Y_PONTA_DA_MAO), "antebraco_D"),
	("braco_E",     (-X_OMBRO, 0.0, Y_OMBRO), (-X_OMBRO, 0.0, Y_COTOVELO), "peito"),
	("antebraco_E", (-X_OMBRO, 0.0, Y_COTOVELO), (-X_OMBRO, 0.0, Y_PULSO), "braco_E"),
	("mao_E",       (-X_OMBRO, 0.0, Y_PULSO), (-X_OMBRO, 0.0, Y_PONTA_DA_MAO), "antebraco_E"),
	("coxa_D",      (X_QUADRIL, 0.0, Y_QUADRIL), (X_QUADRIL, 0.0, Y_JOELHO), "quadril"),
	("canela_D",    (X_QUADRIL, 0.0, Y_JOELHO), (X_QUADRIL, 0.0, Y_TORNOZELO), "coxa_D"),
	("pe_D",        (X_QUADRIL, 0.0, Y_TORNOZELO),
	                (X_QUADRIL, -COMPRIMENTO_DO_PE, Y_TORNOZELO), "canela_D"),
	("coxa_E",      (-X_QUADRIL, 0.0, Y_QUADRIL), (-X_QUADRIL, 0.0, Y_JOELHO), "quadril"),
	("canela_E",    (-X_QUADRIL, 0.0, Y_JOELHO), (-X_QUADRIL, 0.0, Y_TORNOZELO), "coxa_E"),
	("pe_E",        (-X_QUADRIL, 0.0, Y_TORNOZELO),
	                (-X_QUADRIL, -COMPRIMENTO_DO_PE, Y_TORNOZELO), "canela_E"),
]

## `(osso, largura, profundidade)`. A caixa de cada osso vai da cabeça à cauda
## dele; só a espessura é declarada aqui. Vale para osso VERTICAL — o pé, que
## aponta para a frente, é desenhado como adorno.
CAIXAS = {
	"quadril": (0.26, 0.19),
	# O peito não passa do vão dos ombros: ombro largo é o que mais separa
	# "atleta" de "boneco", e o original está em 0,175 da altura contra 0,229
	# de um humano.
	"peito": (X_OMBRO * 2.0, 0.21),
	# Cabeça quase tão larga quanto alta. É ela que carrega a leitura de longe.
	"cabeca": (0.36, 0.34),
	"braco_D": (0.12, 0.12),
	"antebraco_D": (0.11, 0.11),
	# A mão é a peça mais grossa do braço, e é assim no original: punho curto,
	# mão grande. É ela que o olho segue durante o golpe.
	"mao_D": (0.145, 0.13),
	"braco_E": (0.12, 0.12),
	"antebraco_E": (0.11, 0.11),
	"mao_E": (0.145, 0.13),
	"coxa_D": (0.155, 0.155),
	"canela_D": (0.135, 0.135),
	"coxa_E": (0.155, 0.155),
	"canela_E": (0.135, 0.135),
}

## Onde a cabeça está e onde é a cara dela, DERIVADO das medidas acima.
##
## Estes números já foram escritos à mão, e o teste de mutação achou o preço:
## encolhendo a cabeça, o rosto ficava para trás, flutuando no ar acima dela —
## sem erro nenhum, e a conferência de altura aprovava porque a viseira solta
## continuava contando como o topo do corpo.
Z_DA_CABECA = (Y_PESCOCO + Y_TOPO) * 0.5
FRENTE_DA_CABECA = -CAIXAS["cabeca"][1] * 0.5

## `(osso, centro, tamanho, material)`. Caixas soltas, presas a um osso mas com
## posição própria — o que não cabe em "vai da cabeça à cauda".
ADORNOS = [
	# O sapato vai do calcanhar à ponta e tem a altura do tornozelo, então a
	# sola encosta em z=0 por construção.
	("pe_D", (X_QUADRIL, (0.06 - COMPRIMENTO_DO_PE) * 0.5, Y_TORNOZELO * 0.5),
	 (0.145, COMPRIMENTO_DO_PE + 0.06, Y_TORNOZELO), "sapato"),
	("pe_E", (-X_QUADRIL, (0.06 - COMPRIMENTO_DO_PE) * 0.5, Y_TORNOZELO * 0.5),
	 (0.145, COMPRIMENTO_DO_PE + 0.06, Y_TORNOZELO), "sapato"),
	# Viseira e nariz. São a diferença entre "de frente" e "de costas" num
	# corpo simétrico, e o usuário já reportou o personagem andando de costas.
	("cabeca", (0.0, FRENTE_DA_CABECA - 0.005, Z_DA_CABECA + 0.045),
	 (0.25, 0.02, 0.08), "rosto"),
	("cabeca", (0.0, FRENTE_DA_CABECA - 0.02, Z_DA_CABECA - 0.03),
	 (0.07, 0.06, 0.06), "pele"),
]

## Uma cor por região, e elas não são enfeite: a mão colorida é o que o olho
## segue durante o golpe, e o rosto é o que diz para onde o personagem olha.
CORES = {
	"pele": (0.85, 0.72, 0.60, 1.0),
	"roupa": (0.35, 0.45, 0.62, 1.0),
	"membro": (0.28, 0.34, 0.46, 1.0),
	"mao": (0.90, 0.52, 0.22, 1.0),
	"sapato": (0.15, 0.17, 0.21, 1.0),
	"rosto": (0.10, 0.11, 0.14, 1.0),
}
MATERIAL_DO_OSSO = {
	"quadril": "roupa", "peito": "roupa", "cabeca": "pele",
	"braco_D": "membro", "braco_E": "membro",
	"antebraco_D": "membro", "antebraco_E": "membro",
	"mao_D": "mao", "mao_E": "mao",
	"coxa_D": "membro", "coxa_E": "membro",
	"canela_D": "membro", "canela_E": "membro",
}

QUADROS_POR_SEGUNDO = 30


def limpar_cena() -> None:
	"""Cena vazia. `--background` abre o arquivo padrão, que tem cubo e luz."""
	bpy.ops.wm.read_factory_settings(use_empty=True)


def criar_material(nome: str, cor: tuple) -> bpy.types.Material:
	material = bpy.data.materials.new(nome)
	material.use_nodes = True
	bsdf = material.node_tree.nodes.get("Principled BSDF")
	if bsdf is not None:
		bsdf.inputs["Base Color"].default_value = cor
		# Sem brilho: a Fase 1 não tem luz decente, e specular em caixa lê como
		# sujeira.
		if "Roughness" in bsdf.inputs:
			bsdf.inputs["Roughness"].default_value = 0.9
	# **A cor de viewport tambem, e nao e redundancia.** O render Workbench —
	# que e o que a previa usa — le `diffuse_color`, nao o no. Sem esta linha o
	# boneco sai colorido (o glTF ida-e-volta preenche as duas) e o chao sai
	# branco, que foi exatamente o que aconteceu.
	material.diffuse_color = cor
	return material


def criar_armature() -> bpy.types.Object:
	armature = bpy.data.armatures.new("Esqueleto")
	objeto = bpy.data.objects.new("Esqueleto", armature)
	bpy.context.collection.objects.link(objeto)
	bpy.context.view_layer.objects.active = objeto
	bpy.ops.object.mode_set(mode="EDIT")

	for nome, cabeca, cauda, pai in OSSOS:
		osso = armature.edit_bones.new(nome)
		osso.head = Vector(cabeca)
		osso.tail = Vector(cauda)
		if pai is not None:
			osso.parent = armature.edit_bones[pai]
			# Sem `use_connect`: braço e perna partem de um ponto que não é a
			# cauda do pai, e conectar os arrastaria para o lugar errado.
			osso.use_connect = False

	bpy.ops.object.mode_set(mode="OBJECT")
	return objeto


def _caixa(nome: str, centro: Vector, tamanho: Vector, material, grupo: str):
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
	parte = bpy.context.active_object
	parte.name = "malha_" + nome
	parte.scale = tamanho
	parte.location = centro
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	parte.data.materials.append(material)
	vertices = parte.vertex_groups.new(name=grupo)
	vertices.add(range(len(parte.data.vertices)), 1.0, "REPLACE")
	return parte


def criar_corpo(armature: bpy.types.Object) -> bpy.types.Object:
	"""Uma caixa por osso, tudo junto numa malha só, com peso 1 no osso dele.

	Peso 1 e não pesos suaves de propósito: a caixa acompanha o osso RÍGIDA,
	como boneco de madeira. Deformação suave numa silhueta de caixas produz
	amassados que leem como defeito, e o estilo aqui é assumidamente duro.
	"""
	materiais = {nome: criar_material(nome, cor) for nome, cor in CORES.items()}
	partes = []

	for nome, cabeca, cauda, _pai in OSSOS:
		if nome not in CAIXAS:
			continue
		c = Vector(cabeca)
		t = Vector(cauda)
		largura, profundidade = CAIXAS[nome]
		partes.append(_caixa(
			nome, (c + t) * 0.5,
			Vector((largura, profundidade, (t - c).length)),
			materiais[MATERIAL_DO_OSSO[nome]], nome,
		))

	for indice, (osso, centro, tamanho, material) in enumerate(ADORNOS):
		partes.append(_caixa(
			"adorno%d" % indice, Vector(centro), Vector(tamanho),
			materiais[material], osso,
		))

	# Junta tudo numa malha só. A Godot lida melhor com um `MeshInstance3D` do
	# que com treze, e os grupos de vértices sobrevivem à junção.
	bpy.ops.object.select_all(action="DESELECT")
	for parte in partes:
		parte.select_set(True)
	bpy.context.view_layer.objects.active = partes[0]
	bpy.ops.object.join()
	corpo = bpy.context.active_object
	corpo.name = "Corpo"

	# `ARMATURE_NAME` usa os grupos que acabamos de criar, em vez de calcular
	# pesos automáticos — que numa malha de caixas dá resultado imprevisível.
	corpo.select_set(True)
	armature.select_set(True)
	bpy.context.view_layer.objects.active = armature
	bpy.ops.object.parent_set(type="ARMATURE_NAME")
	return corpo


# --------------------------------------------------------------------------
# Animações
#
# Cada uma é uma lista de `(quadro, {osso: (rx, ry, rz)})`, em GRAUS e em eixos
# do MUNDO, mais um deslocamento opcional do quadril.
#
#     +X inclina para a FRENTE      (o topo do osso vai para -Y)
#     +Y tomba para o lado
#     +Z gira em pé, para a direita do personagem
#
# Consequência que parece contraintuitiva e não é: num osso que aponta para
# baixo — braço, coxa — o +X manda a ponta para TRÁS, porque é a mesma rotação
# que manda o topo para a frente. Perna à frente é -X.
# --------------------------------------------------------------------------

def pose(**ossos) -> dict:
	return ossos


def fim_de(dados: dict) -> int:
	"""O ultimo quadro da animacao — que e o da ultima chave, e so.

	Ja houve um campo `"quadros"` ao lado das chaves dizendo a mesma coisa. Dois
	lugares para o mesmo fato e um lugar para eles discordarem: encurtar o campo
	sem encurtar as chaves nao encurtava nada, e a conferencia de duracao
	aprovava porque a animacao continuava do tamanho de antes. Foi um teste de
	mutacao que achou — a mutacao era literalmente um no-op.
	"""
	return dados["chaves"][-1][0]


def pe(coxa: float, canela: float, extra: float = 0.0) -> tuple:
	"""O ângulo que deixa o pé plano no chão, dada a perna.

	Coxa, canela e pé giram todos em torno do mesmo eixo do mundo, então as
	rotações somam: desfazer a soma é o que mantém a sola paralela ao chão.
	`extra` é para quando não se quer plano — a ponta do pé ao impulsionar.
	"""
	return (-(coxa + canela) + extra, 0.0, 0.0)


def _menor_z(malha: bpy.types.Object) -> float:
	"""O ponto mais baixo do corpo DEFORMADO, no quadro atual."""
	profundidade = bpy.context.evaluated_depsgraph_get()
	avaliada = malha.evaluated_get(profundidade)
	temporaria = avaliada.to_mesh()
	mundo = avaliada.matrix_world
	menor = min((mundo @ vertice.co).z for vertice in temporaria.vertices)
	avaliada.to_mesh_clear()
	return menor


def _voo(pontos: dict, quadro: int) -> float:
	"""Quanto o corpo sobe ALEM do chao neste quadro, em metros.

	Interpolacao suave entre os pontos declarados. E aqui que mora o pulo — a
	unica altura que a geometria nao pode descobrir sozinha, porque um corpo no
	ar nao tem pe encostado de onde deduzi-la.
	"""
	if not pontos:
		return 0.0
	quadros = sorted(pontos)
	if quadro <= quadros[0]:
		return pontos[quadros[0]]
	if quadro >= quadros[-1]:
		return pontos[quadros[-1]]
	for anterior, seguinte in zip(quadros, quadros[1:]):
		if anterior <= quadro <= seguinte:
			fatia = (quadro - anterior) / float(seguinte - anterior)
			suave = fatia * fatia * (3.0 - 2.0 * fatia)
			return pontos[anterior] * (1.0 - suave) + pontos[seguinte] * suave
	return 0.0


def assentar(armature, malha, dados: dict, inicio: int, fim: int) -> None:
	"""Poe o quadril, em CADA quadro, na altura que deixa o corpo no chao.

	## Por que nao da para calcular isto das pernas

	A primeira versao derivava a altura do angulo do joelho, por chave. Errou de
	duas formas, e as duas so apareceram na conferencia de chao:

	1. **Quadril e joelho sao curvas separadas.** Entre duas chaves ambas
	   certas, o quadril desce mais rapido do que o joelho dobra, e o pe entra
	   quatro centimetros no piso no meio do agachamento.
	2. **O modelo nao ve o pe.** Ele parava no tornozelo; apontar a ponta do pe
	   para baixo enfia o dedo no chao sem mudar angulo nenhum de perna.

	Medir o ponto mais baixo da malha ja deformada nao tem nenhum dos dois
	problemas: e a resposta exata, no quadro exato, para o corpo inteiro.
	"""
	quadril = armature.pose.bones.get("quadril")
	if quadril is None:
		return
	voo = dados.get("voo", {})
	for quadro in range(inicio, fim + 1):
		bpy.context.scene.frame_set(quadro)
		quadril.location = (0.0, 0.0, 0.0)
		bpy.context.view_layer.update()
		# Y local do osso e a direcao cabeca->cauda, que aqui e para cima.
		quadril.location = (0.0, -_menor_z(malha) + _voo(voo, quadro), 0.0)
		quadril.keyframe_insert("location", frame=quadro)


ANIMACOES = {
	# Parado: respiração. Amplitude pequena de propósito — é o único caso em
	# que sutil é o certo, porque ele roda o tempo todo.
	"parado": {
		"ciclo": True,
		# Sem `voo`: respirar nao tira ninguem do chao. A primeira versao
		# levantava o quadril 2 cm aqui e soltava os dois pes — a respiracao
		# mora no peito, nos ombros e na cabeca, e e la que ela ficou.
		"chaves": [
			(0, pose(peito=(2, 0, 0), cabeca=(1.5, 0, 0),
			         braco_D=(3, -4, 0), braco_E=(3, 4, 0))),
			(30, pose(peito=(-2.5, 0, 0), cabeca=(-1, 0, 0),
			          braco_D=(-3, -9, 0), braco_E=(-3, 9, 0))),
			(60, pose(peito=(2, 0, 0), cabeca=(1.5, 0, 0),
			          braco_D=(3, -4, 0), braco_E=(3, 4, 0))),
		],
	},
	# Andando: ciclo de quatro chaves — contato, passagem, contato espelhado,
	# passagem espelhada. Braço em contrafase com a perna do mesmo lado, que é
	# como se anda de verdade.
	"andando": {
		"ciclo": True,
		"chaves": [
			# **A perna de tras e a mais ESTICADA, e nao e capricho.** O quadril
			# fica na altura que a perna mais esticada alcanca; se a de tras
			# for a mais dobrada, o tornozelo dela fica ABAIXO do repouso, e
			# levantar o calcanhar dali enfia a ponta do pe no chao. Esticando
			# a de tras o tornozelo dela sobe, e o calcanhar tem para onde ir.
			(0, pose(
				coxa_D=(-25, 0, 0), canela_D=(10, 0, 0), pe_D=pe(-25, 10, -10),
				coxa_E=(25, 0, 0), canela_E=(0, 0, 0), pe_E=pe(25, 0, 8),
				braco_D=(22, -5, 0), antebraco_D=(-14, 0, 0),
				braco_E=(-22, 5, 0), antebraco_E=(-14, 0, 0),
				peito=(5, 0, 0))),
			(10, pose(
				coxa_D=(0, 0, 0), canela_D=(4, 0, 0), pe_D=pe(0, 4),
				coxa_E=(-16, 0, 0), canela_E=(45, 0, 0), pe_E=pe(-16, 45, 5),
				braco_D=(5, -5, 0), antebraco_D=(-14, 0, 0),
				braco_E=(-5, 5, 0), antebraco_E=(-14, 0, 0),
				peito=(5, 0, 0))),
			(20, pose(
				coxa_E=(-25, 0, 0), canela_E=(10, 0, 0), pe_E=pe(-25, 10, -10),
				coxa_D=(25, 0, 0), canela_D=(0, 0, 0), pe_D=pe(25, 0, 8),
				braco_E=(22, 5, 0), antebraco_E=(-14, 0, 0),
				braco_D=(-22, -5, 0), antebraco_D=(-14, 0, 0),
				peito=(5, 0, 0))),
			(30, pose(
				coxa_E=(0, 0, 0), canela_E=(4, 0, 0), pe_E=pe(0, 4),
				coxa_D=(-16, 0, 0), canela_D=(45, 0, 0), pe_D=pe(-16, 45, 5),
				braco_E=(5, 5, 0), antebraco_E=(-14, 0, 0),
				braco_D=(-5, -5, 0), antebraco_D=(-14, 0, 0),
				peito=(5, 0, 0))),
			(40, pose(
				coxa_D=(-25, 0, 0), canela_D=(10, 0, 0), pe_D=pe(-25, 10, -10),
				coxa_E=(25, 0, 0), canela_E=(0, 0, 0), pe_E=pe(25, 0, 8),
				braco_D=(22, -5, 0), antebraco_D=(-14, 0, 0),
				braco_E=(-22, 5, 0), antebraco_E=(-14, 0, 0),
				peito=(5, 0, 0))),
		],
	},
	# Correndo: a mesma passada, mais aberta, mais rápida e mais inclinada, com
	# os dois pés fora do chão na passagem.
	"correndo": {
		"ciclo": True,
		# Na passagem os DOIS pes saem do chao — e isso que separa correr de
		# andar, e e a unica altura que o chao nao pode ditar.
		"voo": {0: 0.0, 6: 0.14, 12: 0.0, 18: 0.14, 24: 0.0},
		"chaves": [
			(0, pose(
				coxa_D=(-38, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-38, 14, -12),
				coxa_E=(34, 0, 0), canela_E=(10, 0, 0), pe_E=pe(34, 10, 10),
				braco_D=(46, -8, 0), antebraco_D=(-78, 0, 0),
				braco_E=(-46, 8, 0), antebraco_E=(-78, 0, 0),
				peito=(15, 0, 0), cabeca=(-8, 0, 0))),
			(6, pose(
				coxa_D=(-10, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-10, 14),
				coxa_E=(-24, 0, 0), canela_E=(92, 0, 0), pe_E=pe(-24, 92, 20),
				braco_D=(10, -8, 0), antebraco_D=(-78, 0, 0),
				braco_E=(-10, 8, 0), antebraco_E=(-78, 0, 0),
				peito=(15, 0, 0), cabeca=(-8, 0, 0))),
			(12, pose(
				coxa_E=(-38, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-38, 14, -12),
				coxa_D=(34, 0, 0), canela_D=(10, 0, 0), pe_D=pe(34, 10, 10),
				braco_E=(46, 8, 0), antebraco_E=(-78, 0, 0),
				braco_D=(-46, -8, 0), antebraco_D=(-78, 0, 0),
				peito=(15, 0, 0), cabeca=(-8, 0, 0))),
			(18, pose(
				coxa_E=(-10, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-10, 14),
				coxa_D=(-24, 0, 0), canela_D=(92, 0, 0), pe_D=pe(-24, 92, 20),
				braco_E=(10, 8, 0), antebraco_E=(-78, 0, 0),
				braco_D=(-10, -8, 0), antebraco_D=(-78, 0, 0),
				peito=(15, 0, 0), cabeca=(-8, 0, 0))),
			(24, pose(
				coxa_D=(-38, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-38, 14, -12),
				coxa_E=(34, 0, 0), canela_E=(10, 0, 0), pe_E=pe(34, 10, 10),
				braco_D=(46, -8, 0), antebraco_D=(-78, 0, 0),
				braco_E=(-46, 8, 0), antebraco_E=(-78, 0, 0),
				peito=(15, 0, 0), cabeca=(-8, 0, 0))),
		],
	},
	# ------------------------------------------------------------ reações
	#
	# Levou dano: `beaten` no original, **1,00 s exatos nos 32 campeões** — a
	# única duração universal que não varia nada.
	#
	# **É a animação que NÃO tem antecipação, e é de propósito.** O item 4 da
	# lista do §10 pede recuo antes do golpe, porque sem ele o golpe lê como
	# teleporte. Numa reação a regra se inverte: o susto é a informação, e
	# antecipar faria o personagem parecer que sabia que ia apanhar. O tempo
	# aqui é o contrário do de um golpe — instantâneo na entrada, lento na
	# saída.
	"levou_dano": {
		"ciclo": False,
		"chaves": [
			(0, pose()),
			# Quatro quadros até o impacto: 0,13 s, que é o mais rápido que o
			# olho ainda separa de "trocou de pose".
			#
			# **Os braços vão para TRÁS**, e a primeira versão os mandou para a
			# frente. Num osso que aponta para baixo o +X leva a ponta para
			# trás — está escrito no cabeçalho das animações e mesmo assim eu
			# escrevi -38, o que na tela virou o personagem ESTENDENDO as duas
			# mãos como quem alcança alguma coisa. Medição nenhuma pega isso: a
			# duração, o chão e a amplitude estavam todos certos.
			(4, pose(
				quadril=(0, 0, -7), peito=(-24, 0, 0), cabeca=(-16, 0, 0),
				braco_D=(30, -40, 0), antebraco_D=(-35, 0, 0),
				braco_E=(30, 40, 0), antebraco_E=(-35, 0, 0),
				coxa_D=(14, 0, 0), canela_D=(18, 0, 0), pe_D=pe(14, 18),
				coxa_E=(-10, 0, 0), canela_E=(26, 0, 0), pe_E=pe(-10, 26))),
			(11, pose(
				quadril=(0, 0, -3), peito=(-11, 0, 0), cabeca=(-6, 0, 0),
				braco_D=(12, -22, 0), antebraco_D=(-28, 0, 0),
				braco_E=(12, 22, 0), antebraco_E=(-28, 0, 0),
				coxa_D=(8, 0, 0), canela_D=(10, 0, 0), pe_D=pe(8, 10),
				coxa_E=(-6, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-6, 14))),
			# Passa do repouso para a frente antes de voltar: sem esse
			# contragolpe o corpo desinfla em vez de se recompor.
			(20, pose(
				peito=(7, 0, 0), cabeca=(5, 0, 0),
				braco_D=(-8, -9, 0), braco_E=(-8, 9, 0),
				coxa_D=(4, 0, 0), canela_D=(7, 0, 0), pe_D=pe(4, 7),
				coxa_E=(-3, 0, 0), canela_E=(7, 0, 0), pe_E=pe(-3, 7))),
			(30, pose()),
		],
	},
	# Atordoado: `stun`, 0,50 / 0,50 / 1,00 s no original, e CICLO — o
	# atordoamento dura o que a habilidade mandar, então o clipe tem que poder
	# rodar de novo sem emenda visível.
	#
	# A cabeça rola em círculo e é ela que carrega a leitura: com 23,7% da
	# altura, é a peça cujo movimento o olho pega de longe. Os joelhos ficam
	# moles e os braços soltos — o corpo continua de pé mas parou de se
	# sustentar, que é a diferença entre "atordoado" e "parado".
	"atordoado": {
		"ciclo": True,
		"chaves": [
			(0, pose(
				quadril=(0, 5, 0), peito=(9, -5, 0), cabeca=(16, 0, 0),
				braco_D=(2, -9, 0), antebraco_D=(-14, 0, 0),
				braco_E=(2, 9, 0), antebraco_E=(-14, 0, 0),
				coxa_D=(-7, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-7, 14),
				coxa_E=(-7, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-7, 14))),
			(5, pose(
				quadril=(0, 0, 0), peito=(9, -2, 0), cabeca=(3, 17, 0),
				braco_D=(2, -13, 0), antebraco_D=(-18, 0, 0),
				braco_E=(2, 5, 0), antebraco_E=(-10, 0, 0),
				coxa_D=(-9, 0, 0), canela_D=(17, 0, 0), pe_D=pe(-9, 17),
				coxa_E=(-5, 0, 0), canela_E=(11, 0, 0), pe_E=pe(-5, 11))),
			(10, pose(
				quadril=(0, -5, 0), peito=(9, 5, 0), cabeca=(-7, 0, 0),
				braco_D=(2, -9, 0), antebraco_D=(-14, 0, 0),
				braco_E=(2, 9, 0), antebraco_E=(-14, 0, 0),
				coxa_D=(-7, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-7, 14),
				coxa_E=(-7, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-7, 14))),
			(15, pose(
				quadril=(0, 0, 0), peito=(9, 2, 0), cabeca=(3, -17, 0),
				braco_D=(2, -5, 0), antebraco_D=(-10, 0, 0),
				braco_E=(2, 13, 0), antebraco_E=(-18, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(11, 0, 0), pe_D=pe(-5, 11),
				coxa_E=(-9, 0, 0), canela_E=(17, 0, 0), pe_E=pe(-9, 17))),
			# O último quadro REPETE o primeiro — item 3 da lista do §10, e o
			# conferidor mede.
			(20, pose(
				quadril=(0, 5, 0), peito=(9, -5, 0), cabeca=(16, 0, 0),
				braco_D=(2, -9, 0), antebraco_D=(-14, 0, 0),
				braco_E=(2, 9, 0), antebraco_E=(-14, 0, 0),
				coxa_D=(-7, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-7, 14),
				coxa_E=(-7, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-7, 14))),
		],
	},
	# Morte: `death`, 1,13 / 1,82 / 3,33 s no original — a MAIOR variação de
	# todo o vocabulário universal, três vezes entre o mais curto e o mais
	# longo. Faz sentido: é o único clipe que ninguém precisa poder interromper,
	# então cada campeão gastou o que quis. 2,00 s é o quinto comprimento mais
	# escolhido do original e cai no meio da faixa.
	#
	# **Ela termina DEITADA, e é a única do vocabulário que termina.** O corpo
	# gira no osso raiz: -90 graus em X põem o tronco apontando para trás e as
	# pernas para a frente, que é um corpo de costas no chão. `assentar` faz o
	# resto — ele mede o ponto mais baixo da malha já deformada, então não
	# importa que agora o ponto mais baixo seja o ombro em vez do pé.
	"morte": {
		"ciclo": False,
		"chaves": [
			(0, pose()),
			# O golpe: dobra para a frente, joelhos cedem.
			(8, pose(
				peito=(20, 0, 0), cabeca=(14, 0, 0),
				braco_D=(-16, -12, 0), antebraco_D=(-30, 0, 0),
				braco_E=(-16, 12, 0), antebraco_E=(-30, 0, 0),
				coxa_D=(-18, 0, 0), canela_D=(34, 0, 0), pe_D=pe(-18, 34),
				coxa_E=(-18, 0, 0), canela_E=(34, 0, 0), pe_E=pe(-18, 34))),
			# As pernas param de sustentar e o corpo começa a cair para trás.
			(20, pose(
				quadril=(-30, 0, 0), peito=(16, 0, 0), cabeca=(16, 0, 0),
				braco_D=(24, -22, 0), antebraco_D=(-16, 0, 0),
				braco_E=(24, 22, 0), antebraco_E=(-16, 0, 0),
				coxa_D=(-40, 0, 0), canela_D=(74, 0, 0), pe_D=pe(-40, 74),
				coxa_E=(-36, 0, 0), canela_E=(70, 0, 0), pe_E=pe(-36, 70))),
			# Chega ao chão. Os braços abrem — é a leitura de longe: um corpo
			# deitado com os braços colados no tronco vira um tronco.
			(34, pose(
				quadril=(-86, 0, 0), peito=(8, 0, 0), cabeca=(12, 0, 0),
				braco_D=(18, -58, 0), antebraco_D=(-10, 0, 0),
				braco_E=(18, 58, 0), antebraco_E=(-10, 0, 0),
				coxa_D=(14, 0, 0), canela_D=(26, 0, 0), pe_D=pe(14, 26),
				coxa_E=(10, 0, 0), canela_E=(20, 0, 0), pe_E=pe(10, 20))),
			# O quique do peso batendo, e depois nada.
			(43, pose(
				quadril=(-93, 0, 0), peito=(4, 0, 0), cabeca=(8, 0, 0),
				braco_D=(10, -66, 0), braco_E=(10, 66, 0),
				coxa_D=(8, 0, 0), canela_D=(14, 0, 0), pe_D=pe(8, 14),
				coxa_E=(5, 0, 0), canela_E=(10, 0, 0), pe_E=pe(5, 10))),
			(60, pose(
				quadril=(-90, 0, 0), peito=(5, 0, 0), cabeca=(9, 0, 0),
				braco_D=(12, -62, 0), braco_E=(12, 62, 0),
				coxa_D=(9, 0, 0), canela_D=(16, 0, 0), pe_D=pe(9, 16),
				coxa_E=(6, 0, 0), canela_E=(12, 0, 0), pe_E=pe(6, 12))),
		],
	},
	# Os cinco gestos de habilidade, com os mesmos nomes que
	# `GestoDeConjuracao.Gesto` já escolhe pela forma do pulso. Todos têm
	# ANTECIPAÇÃO no começo — sem ela o golpe parece teleporte.
	"estocada": {
		"ciclo": False,
		"chaves": [
			(0, pose()),
			# Recua: ombro direito para trás, peso atrás, braço armado.
			(7, pose(
				quadril=(0, 0, 14), peito=(-8, 0, 0),
				braco_D=(38, 0, 0), antebraco_D=(-62, 0, 0),
				braco_E=(-10, 6, 0),
				coxa_D=(12, 0, 0), canela_D=(10, 0, 0), pe_D=pe(12, 10),
				coxa_E=(6, 0, 0), canela_E=(8, 0, 0), pe_E=pe(6, 8))),
			# Golpe: ombro direito à frente, braço estendido, perna à frente.
			(15, pose(
				quadril=(0, 0, -16), peito=(12, 0, 0), cabeca=(-6, 0, 0),
				braco_D=(-96, 0, 0), antebraco_D=(-6, 0, 0),
				braco_E=(30, 10, 0), antebraco_E=(-40, 0, 0),
				coxa_D=(-30, 0, 0), canela_D=(16, 0, 0), pe_D=pe(-30, 16),
				coxa_E=(20, 0, 0), canela_E=(14, 0, 0), pe_E=pe(20, 14, -12))),
			# Segura um instante — é o que dá peso ao golpe.
			(22, pose(
				quadril=(0, 0, -13), peito=(10, 0, 0),
				braco_D=(-88, 0, 0), antebraco_D=(-10, 0, 0),
				braco_E=(26, 10, 0), antebraco_E=(-38, 0, 0),
				coxa_D=(-26, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-26, 14),
				coxa_E=(18, 0, 0), canela_E=(12, 0, 0), pe_E=pe(18, 12, -10))),
			(30, pose()),
		],
	},
	# Giro: uma volta inteira em pé, com os braços abertos.
	#
	# **Nenhum passo passa de 120 graus, de propósito.** A conversão para o
	# espaço do osso perde a volta: 360 graus e 0 grau são a mesma matriz, e
	# `make_compatible` só escolhe certo enquanto o passo for menor que meia
	# volta. Com chaves de 120 em 120 não há empate.
	"giro": {
		"ciclo": False,
		"chaves": [
			(0, pose()),
			(5, pose(quadril=(0, 0, 40), braco_D=(0, -30, 0), braco_E=(0, 30, 0),
			         peito=(4, 0, 0),
			         coxa_D=(-12, 0, 0), canela_D=(24, 0, 0), pe_D=pe(-12, 24),
			         coxa_E=(-12, 0, 0), canela_E=(24, 0, 0), pe_E=pe(-12, 24))),
			(13, pose(quadril=(0, 0, -80), braco_D=(0, -85, 0), braco_E=(0, 85, 0),
			          peito=(-6, 0, 0))),
			(20, pose(quadril=(0, 0, -200), braco_D=(0, -85, 0), braco_E=(0, 85, 0),
			          peito=(-6, 0, 0))),
			(27, pose(quadril=(0, 0, -320), braco_D=(0, -70, 0), braco_E=(0, 70, 0))),
			(32, pose(quadril=(0, 0, -360), braco_D=(0, -20, 0), braco_E=(0, 20, 0))),
		],
	},
	"salto": {
		"ciclo": False,
		"voo": {0: 0.0, 7: 0.0, 18: 0.55, 26: 0.0, 36: 0.0},
		"chaves": [
			(0, pose()),
			# Agacha para impulsionar.
			(7, pose(
				coxa_D=(-30, 0, 0), canela_D=(62, 0, 0), pe_D=pe(-30, 62),
				coxa_E=(-30, 0, 0), canela_E=(62, 0, 0), pe_E=pe(-30, 62),
				peito=(22, 0, 0), cabeca=(-10, 0, 0),
				braco_D=(30, -6, 0), braco_E=(30, 6, 0))),
			# No ar: pernas encolhidas, braços para cima e à frente.
			(18, pose(
				coxa_D=(-58, 0, 0), canela_D=(88, 0, 0), pe_D=pe(-58, 88, 25),
				coxa_E=(-58, 0, 0), canela_E=(88, 0, 0), pe_E=pe(-58, 88, 25),
				peito=(-4, 0, 0), cabeca=(-8, 0, 0),
				braco_D=(-125, 0, 0), antebraco_D=(-20, 0, 0),
				braco_E=(-125, 0, 0), antebraco_E=(-20, 0, 0))),
			# Aterrissa absorvendo — sem isto o pouso lê como queda de pedra.
			(26, pose(
				coxa_D=(-26, 0, 0), canela_D=(52, 0, 0), pe_D=pe(-26, 52),
				coxa_E=(-26, 0, 0), canela_E=(52, 0, 0), pe_E=pe(-26, 52),
				peito=(18, 0, 0),
				braco_D=(-30, -10, 0), braco_E=(-30, 10, 0))),
			(36, pose()),
		],
	},
	"erguer": {
		"ciclo": False,
		"chaves": [
			(0, pose()),
			(7, pose(braco_D=(32, -6, 0), braco_E=(32, 6, 0), peito=(11, 0, 0),
			         coxa_D=(-12, 0, 0), canela_D=(24, 0, 0), pe_D=pe(-12, 24),
			         coxa_E=(-12, 0, 0), canela_E=(24, 0, 0), pe_E=pe(-12, 24))),
			# Passo intermediário só para o braço não subir 195 graus de uma vez.
			(12, pose(braco_D=(-70, -10, 0), braco_E=(-70, 10, 0), peito=(0, 0, 0))),
			(19, pose(
				braco_D=(-166, -14, 0), antebraco_D=(-12, 0, 0),
				braco_E=(-166, 14, 0), antebraco_E=(-12, 0, 0),
				peito=(-13, 0, 0), cabeca=(-16, 0, 0))),
			(25, pose(
				braco_D=(-160, -14, 0), braco_E=(-160, 14, 0),
				peito=(-11, 0, 0), cabeca=(-14, 0, 0))),
			(32, pose()),
		],
	},
	# Preparo: o corpo se junta e FICA junto — é o aviso de que algo vem vindo,
	# e a Godot estica a duração dele pelo tempo de conjuração.
	"preparo": {
		"ciclo": False,
		"chaves": [
			(0, pose()),
			(13, pose(
				coxa_D=(-28, 0, 0), canela_D=(52, 0, 0), pe_D=pe(-28, 52),
				coxa_E=(-28, 0, 0), canela_E=(52, 0, 0), pe_E=pe(-28, 52),
				peito=(21, 0, 0), cabeca=(-9, 0, 0),
				braco_D=(42, -16, 0), antebraco_D=(-86, 0, 0),
				braco_E=(42, 16, 0), antebraco_E=(-86, 0, 0))),
			(40, pose(
				coxa_D=(-30, 0, 0), canela_D=(55, 0, 0), pe_D=pe(-30, 55),
				coxa_E=(-30, 0, 0), canela_E=(55, 0, 0), pe_E=pe(-30, 55),
				peito=(23, 0, 0), cabeca=(-10, 0, 0),
				braco_D=(45, -17, 0), antebraco_D=(-88, 0, 0),
				braco_E=(45, 17, 0), antebraco_E=(-88, 0, 0))),
		],
	},
}


def curvas_de(acao: bpy.types.Action):
	"""As curvas de uma ação, nas duas APIs.

	O Blender 4.4 trocou `Action.fcurves` pelo sistema de camadas com slots, e
	a partir da 5.x o atributo antigo não existe mais: as curvas vivem em
	`acao.layers[].strips[].channelbags[].fcurves`. Aceitar as duas formas faz
	o gerador funcionar em qualquer versão que alguém tenha instalada, o que
	importa num script que não é rodado toda hora.
	"""
	if hasattr(acao, "fcurves"):
		return list(acao.fcurves)
	curvas = []
	for camada in acao.layers:
		for trecho in camada.strips:
			for saco in getattr(trecho, "channelbags", []):
				curvas.extend(saco.fcurves)
	return curvas


def _para_o_osso(armature: bpy.types.Object, nome: str, graus: tuple) -> Euler:
	"""A rotação de mundo `graus`, escrita no espaço em que o osso a guarda.

	`matrix_basis` de um osso de pose vive na base de REPOUSO dele. A mesma
	rotação, noutra base, é a conjugação `B⁻¹ R B` — e é isso e só isso.
	"""
	base = armature.data.bones[nome].matrix_local.to_3x3()
	mundo = Euler([math.radians(g) for g in graus], "XYZ").to_matrix()
	return (base.inverted() @ mundo @ base).to_euler("XYZ")


def criar_animacao(armature: bpy.types.Object, malha: bpy.types.Object,
                   nome: str, dados: dict) -> None:
	bpy.context.view_layer.objects.active = armature
	bpy.ops.object.mode_set(mode="POSE")

	acao = bpy.data.actions.new(nome)
	# `use_fake_user`: sem isto o Blender descarta a ação ao trocar de contexto
	# e o exportador não encontra nada.
	acao.use_fake_user = True
	if armature.animation_data is None:
		armature.animation_data_create()
	armature.animation_data.action = acao

	for osso in armature.pose.bones:
		osso.rotation_mode = "XYZ"
		osso.rotation_euler = (0.0, 0.0, 0.0)
		osso.location = (0.0, 0.0, 0.0)

	anterior: dict = {}
	for quadro, poses in dados["chaves"]:
		bpy.context.scene.frame_set(quadro)
		# TODO osso a osso: um osso ausente na chave volta ao repouso, e é
		# isso que faz cada chave descrever a pose INTEIRA em vez de um delta.
		for osso in armature.pose.bones:
			local = _para_o_osso(armature, osso.name, poses.get(osso.name, (0.0, 0.0, 0.0)))
			# **Sem isto o giro anda para trás.** A conversão devolve o ângulo
			# na faixa canônica, então uma volta que passa de 180 graus volta
			# como o negativo dela; `make_compatible` escolhe a representação
			# mais próxima da chave anterior, que é a que continua o movimento.
			if osso.name in anterior:
				local.make_compatible(anterior[osso.name])
			anterior[osso.name] = local.copy()
			osso.rotation_euler = local
			osso.keyframe_insert("rotation_euler", frame=quadro)

	# O deslocamento vertical do quadril — o quique da caminhada, o voo do
	# salto. Fica no osso raiz, que é quem carrega o corpo todo.
	# O quadril e assentado DEPOIS, quadro a quadro, por `assentar` — ele
	# precisa das rotacoes ja gravadas para medir onde o corpo encosta.
	assentar(armature, malha, dados, dados["chaves"][0][0], fim_de(dados))

	for curva in curvas_de(acao):
		for ponto in curva.keyframe_points:
			# Interpolação suave: `LINEAR` num boneco de caixas lê como
			# engasgo a cada chave.
			ponto.interpolation = "BEZIER"
			# **`AUTO_CLAMPED`, não `AUTO`.** A alça automática do Blender
			# ultrapassa a chave para suavizar a curva, e num agachamento isso
			# enfia o pé quatro centímetros no chão ENTRE duas chaves que estão
			# ambas certas. Foi a conferência de chão que achou, e nenhuma
			# chave estava errada.
			ponto.handle_left_type = "AUTO_CLAMPED"
			ponto.handle_right_type = "AUTO_CLAMPED"

	bpy.ops.object.mode_set(mode="OBJECT")


def exportar(caminho: str) -> None:
	os.makedirs(os.path.dirname(caminho), exist_ok=True)
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(
		filepath=caminho,
		export_format="GLB",
		export_animations=True,
		# Cada ação vira uma animação com o nome dela, que é o que a Godot
		# expõe no `AnimationPlayer` e o que o código de jogo chama.
		export_animation_mode="ACTIONS",
		export_apply=False,
		export_yup=True,
	)


def salvar_blend(caminho: str) -> None:
	"""Salva a cena para abrir no Blender e OLHAR.

	O gerador roda headless, e headless não mostra nada. Sem este arquivo o
	único jeito de conferir o boneco seria pela impressão do console — que diz
	"13 ossos, 8 animações" e não diz se ele está de pé.

	Abrir e rodar uma animação: abrir `arte/fonte/personagem.blend` e apertar
	espaço; para trocar de animação, um editor em Dope Sheet → Action Editor.

	**Ele mora em `arte/fonte/`, que tem um `.gdignore`.** A Godot 4 importa
	`.blend` chamando o Blender, e sem ele configurado o projeto abre com erro
	de importação numa máquina que só quer rodar o jogo. O `.glb` é o que a
	engine consome; o `.blend` é para humano.
	"""
	os.makedirs(os.path.dirname(caminho), exist_ok=True)
	# **Sem compressão, de propósito.** O `.blend` é rastreado pelo repositório,
	# e artefato rastreado que ninguém consegue conferir é a mesma classe do
	# `.glb` que uma vez foi commitado sem vir do código. Comprimido, nem os
	# nomes das animações dão para ler sem o Blender; cru, `conferir_numeros.py`
	# confirma que ele tem os oito nomes e os quinze ossos.
	bpy.ops.wm.save_as_mainfile(filepath=caminho, compress=False)


def main() -> int:
	limpar_cena()
	bpy.context.scene.render.fps = QUADROS_POR_SEGUNDO
	armature = criar_armature()
	corpo = criar_corpo(armature)

	for nome, dados in ANIMACOES.items():
		criar_animacao(armature, corpo, nome, dados)

	# Deixa uma animação escolhida e o intervalo certo, para quem abrir o
	# arquivo só precisar apertar espaço.
	inicial = "andando"
	if inicial in bpy.data.actions:
		armature.animation_data.action = bpy.data.actions[inicial]
		if hasattr(armature.animation_data, "action_slot"):
			slots = bpy.data.actions[inicial].slots
			if len(slots) > 0:
				armature.animation_data.action_slot = slots[0]
		bpy.context.scene.frame_start = 0
		bpy.context.scene.frame_end = fim_de(ANIMACOES[inicial])

	raiz = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
	destino = os.path.join(raiz, "arte", "personagem.glb")
	# **Exporta para um nome temporário e só publica se passar.** Antes o
	# arquivo era gravado no lugar definitivo e a conferência vinha depois:
	# toda execução reprovada deixava um boneco ruim no disco, e foi assim que
	# um deles chegou a ser commitado. Reprovar não pode publicar nada.
	# **O nome tem que terminar em `.glb`.** O exportador do Blender acrescenta
	# a extensao quando ela falta, e `personagem.glb.novo` virava
	# `personagem.glb.novo.glb` — o arquivo conferido nao era o gravado, e o
	# `os.remove` do caminho errado estourava.
	provisorio = os.path.join(os.path.dirname(destino), "personagem.novo.glb")
	exportar(provisorio)
	blend = os.path.join(raiz, "arte", "fonte", "personagem.blend")
	# **O `.blend` também espera.** Ele é rastreado igual ao `.glb`, e publicar
	# um e segurar o outro só muda de qual artefato o defeito sai: a revisão
	# achou um `.blend` commitado vindo de uma rodada de mutação, no commit que
	# corrigia exatamente isso para o `.glb`. Os dois saem juntos ou nenhum sai.
	#
	# O nome do provisório termina em `.blend` porque o Blender guarda o backup
	# como `<nome>1`, e só `*.blend1` está no `.gitignore`.
	blend_provisorio = os.path.join(os.path.dirname(blend), "personagem_novo.blend")
	salvar_blend(blend_provisorio)

	codigo = conferir(raiz, provisorio)
	if codigo != 0:
		for lixo in (provisorio, blend_provisorio):
			if os.path.exists(lixo):
				os.remove(lixo)
		print("[arte] o boneco NAO foi publicado — %s e %s continuam como estavam"
		      % (destino, blend))
		return codigo
	os.replace(provisorio, destino)
	os.replace(blend_provisorio, blend)
	print("[arte] %d ossos, %d animações -> %s (%.0f KB)" % (
		len(OSSOS), len(ANIMACOES), destino,
		os.path.getsize(destino) / 1024 if os.path.exists(destino) else 0,
	))
	print("[arte] para abrir e olhar: %s" % blend)
	return 0


def conferir(raiz: str, glb: str) -> int:
	"""Roda `conferir_personagem.py` no que acabou de ser exportado.

	**Porque a direcao de arte diz que ele roda toda vez que o boneco e
	gerado**, e antes disso a frase era falsa: o conferidor so rodava se
	alguem lembrasse a linha de comando do Blender. "Defesa que depende de
	alguem lembrar nao e defesa" e a licao 11 do `CLAUDE.md`, e ela ja
	recorreu cinco vezes neste projeto.

	Roda num processo separado de proposito: o conferidor IMPORTA o `.glb`
	numa cena limpa, e importar dentro desta aqui apagaria a cena que acabou
	de ser salva.
	"""
	conferidor = os.path.join(raiz, "tools", "arte", "conferir_personagem.py")
	if not os.path.exists(conferidor):
		print("[arte] FALTA %s — o boneco saiu sem ser conferido" % conferidor)
		return 1
	resultado = subprocess.run(
		[bpy.app.binary_path, "--background", "--python", conferidor, "--", glb],
		capture_output=True, text=True, encoding="utf-8", errors="replace",
	)
	for linha in (resultado.stdout or "").splitlines():
		if linha.startswith("[confere]"):
			print(linha)
	if resultado.returncode != 0:
		print("[arte] o boneco NAO passou na direcao de arte")
	return resultado.returncode


if __name__ == "__main__":
	sys.exit(main())
