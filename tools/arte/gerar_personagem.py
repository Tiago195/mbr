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
from mathutils import Euler, Quaternion, Vector

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
## Quanto o braço abre para fora do corpo no REPOUSO, em graus.
##
## **Não é estilo, é a única saída geométrica.** Com o braço caindo reto do
## ombro, a mão do boneco ficava DENTRO da coxa: ombro a 0,153 do centro, coxa
## indo até 0,215, mão ocupando de 0,066 a 0,241. Medido em repouso, oito pares
## de peças se cruzavam sem serem vizinhas, e a pior era essa. Foi o que o
## usuário viu na tela: *"várias peças dele entra uma dentro da outra, até com
## ele parado"*.
##
## E não havia como resolver engrossando ou afinando: para a mão passar por
## fora da coxa com o braço na vertical, o centro dela teria que estar a 0,30
## do eixo — o dobro do vão dos ombros, que é medido e vale 0,175 da altura.
## Braço vertical mais coxa medida é uma colisão obrigatória.
##
## Vinte graus é o mínimo que faz a borda interna da mão passar por fora da
## borda externa da coxa, com folga. Modelador chama isso de pose em A, e é a
## pose de repouso padrão para personagem exatamente por este motivo.
ABERTURA_DO_BRACO = 20.0

_SENO_DO_BRACO = math.sin(math.radians(ABERTURA_DO_BRACO))
_COSSENO_DO_BRACO = math.cos(math.radians(ABERTURA_DO_BRACO))


def _no_braco(lado: float, distancia: float) -> tuple:
	"""Um ponto da corrente do braço, a `distancia` do ombro, ao longo dela."""
	return (lado * (X_OMBRO + distancia * _SENO_DO_BRACO),
	        0.0, Y_OMBRO - distancia * _COSSENO_DO_BRACO)


## Onde o cotovelo cai ao longo do braço. O original põe ombro, cotovelo e mão
## na mesma altura na pose T, então a divisão não sai de lá; 0,47 é a proporção
## de um braço humano, e é o que sobrou de escrito à mão aqui.
FRACAO_ATE_O_COTOVELO = 0.47
COMPRIMENTO_DO_BRACO = COMPRIMENTO_ATE_O_PULSO * FRACAO_ATE_O_COTOVELO

COMPRIMENTO_DO_PE = 0.24
COMPRIMENTO_DA_COXA = Y_QUADRIL - Y_JOELHO
COMPRIMENTO_DA_CANELA = Y_JOELHO - Y_TORNOZELO

## `(nome, cabeça, cauda, pai)`. A cauda de um osso é onde o próximo começa —
## é ela que dá a direção da rotação.
OSSOS = [
	("quadril",     (0.0, 0.0, Y_QUADRIL), (0.0, 0.0, Y_PEITO), None),
	("peito",       (0.0, 0.0, Y_PEITO), (0.0, 0.0, Y_PESCOCO), "quadril"),
	("cabeca",      (0.0, 0.0, Y_PESCOCO), (0.0, 0.0, Y_TOPO), "peito"),
	("braco_D",     _no_braco(1.0, 0.0), _no_braco(1.0, COMPRIMENTO_DO_BRACO), "peito"),
	("antebraco_D", _no_braco(1.0, COMPRIMENTO_DO_BRACO),
	                _no_braco(1.0, COMPRIMENTO_ATE_O_PULSO), "braco_D"),
	("mao_D",       _no_braco(1.0, COMPRIMENTO_ATE_O_PULSO),
	                _no_braco(1.0, COMPRIMENTO_ATE_O_PULSO + COMPRIMENTO_DA_MAO),
	                "antebraco_D"),
	("braco_E",     _no_braco(-1.0, 0.0), _no_braco(-1.0, COMPRIMENTO_DO_BRACO), "peito"),
	("antebraco_E", _no_braco(-1.0, COMPRIMENTO_DO_BRACO),
	                _no_braco(-1.0, COMPRIMENTO_ATE_O_PULSO), "braco_E"),
	("mao_E",       _no_braco(-1.0, COMPRIMENTO_ATE_O_PULSO),
	                _no_braco(-1.0, COMPRIMENTO_ATE_O_PULSO + COMPRIMENTO_DA_MAO),
	                "antebraco_E"),
	("coxa_D",      (X_QUADRIL, 0.0, Y_QUADRIL), (X_QUADRIL, 0.0, Y_JOELHO), "quadril"),
	("canela_D",    (X_QUADRIL, 0.0, Y_JOELHO), (X_QUADRIL, 0.0, Y_TORNOZELO), "coxa_D"),
	("pe_D",        (X_QUADRIL, 0.0, Y_TORNOZELO),
	                (X_QUADRIL, -COMPRIMENTO_DO_PE, Y_TORNOZELO), "canela_D"),
	("coxa_E",      (-X_QUADRIL, 0.0, Y_QUADRIL), (-X_QUADRIL, 0.0, Y_JOELHO), "quadril"),
	("canela_E",    (-X_QUADRIL, 0.0, Y_JOELHO), (-X_QUADRIL, 0.0, Y_TORNOZELO), "coxa_E"),
	("pe_E",        (-X_QUADRIL, 0.0, Y_TORNOZELO),
	                (-X_QUADRIL, -COMPRIMENTO_DO_PE, Y_TORNOZELO), "canela_E"),
]

## A ESBELTEZ de cada região: espessura dividida pelo COMPRIMENTO do osso.
##
## **Isto é a medida que faltava, e a falta tinha nome.** `PROPORCAO`, logo
## acima, tem dez números e todos são altura de junta ou vão entre juntas — ou
## seja, ela descreve o ESQUELETO. A espessura, que é o que faz a silhueta, era
## escrita à mão e derivada de nada. O boneco passava nas nove conferências de
## proporção e ainda assim era uma pilha de lajes finas, porque nenhuma delas
## olhava para a carne. Palavras do usuário ao ver na tela: *"o próprio boneco
## de teste tá ruim, ele foge da direção de arte, totalmente quadrado"*.
##
## Medida em **27 campeões** por `tools/arte/censo_do_original.py`, que lê
## `m_BonesAABB` — a caixa envolvente dos vértices que cada osso influencia.
##
## **É razão, e não espessura absoluta, por uma razão medida.** Com skinning
## suave a caixa de um osso invade a do vizinho, e o absoluto sai inflado: por
## ali a coxa dava 0,266 da altura, o que faria duas coxas ocuparem 0,53 num
## quadril de 0,33 — geometricamente impossível. A inflação empurra os três
## lados da caixa, então a RAZÃO entre eles sobrevive. É ela que responde
## *"isto é um palito ou é um toco?"*, que é a pergunta do usuário.
ESBELTEZ = {
	"cabeca": 0.778,
	"braco": 0.758,
	"antebraco": 0.716,
	"mao": 0.752,
	"coxa": 0.575,
	"canela": 0.494,
	"pe": 0.672,
	# **As duas do tronco são medidas e NÃO são usadas.** Ficam aqui porque o
	# censo as publica e `conferir_numeros.py` exige que as nove batam com o
	# instantâneo; a decisão de não derivar delas está em `CAIXAS_DO_TRONCO`.
	"peito": 0.779,
	"quadril": 0.676,
}

## Qual região responde por cada osso. Direito e esquerdo são a mesma região.
REGIAO_DO_OSSO = {
	"cabeca": "cabeca", "peito": "peito", "quadril": "quadril",
	"braco_D": "braco", "braco_E": "braco",
	"antebraco_D": "antebraco", "antebraco_E": "antebraco",
	"mao_D": "mao", "mao_E": "mao",
	"coxa_D": "coxa", "coxa_E": "coxa",
	"canela_D": "canela", "canela_E": "canela",
	"pe_D": "pe", "pe_E": "pe",
}

## O tronco NÃO deriva da esbeltez, e a exclusão é medida, não preguiça.
##
## Nós cortamos o tronco em dois ossos curtos — `quadril` tem 0,30 m e `peito`
## 0,19 m. No original, as caixas de influência de `Hips` e `Chest` cobrem o
## tronco INTEIRO, porque é assim que o skinning suave distribui os vértices.
## Dividir espessura por um comprimento que significa outra coisa mede a nossa
## segmentação, não a forma deles: por esse caminho o peito dava esbeltez 1,78
## vez a do original, que é artefato e não achado.
##
## A largura sai de onde ela é medida de verdade — o vão dos ombros e o dos
## quadris, que estão em `PROPORCAO`. A profundidade continua declarada, e é a
## última medida do boneco que não tem origem. Está registrado como lacuna no
## §11 de `docs/11-direcao-de-arte.md`.
CAIXAS_DO_TRONCO = {
	# O peito não passa do vão dos ombros: ombro largo é o que mais separa
	# "atleta" de "boneco", e o original está em 0,175 da altura contra 0,229
	# de um humano.
	"peito": (X_OMBRO * 2.0, 0.21),
	# E o quadril não pode ser mais estreito que o vão dos quadris, senão as
	# coxas nascem para fora dele.
	"quadril": (max(0.26, X_QUADRIL * 2.0), 0.19),
}


def _comprimento(nome: str) -> float:
	"""O comprimento do osso, da cabeça à cauda dele."""
	for osso, cabeca, cauda, _pai in OSSOS:
		if osso == nome:
			return (Vector(cauda) - Vector(cabeca)).length
	raise KeyError(nome)


def _derivar_caixas() -> dict:
	"""`{osso: (largura, profundidade)}`, da esbeltez vezes o comprimento.

	**Uma linha por osso era o defeito.** Treze pares escritos à mão são treze
	oportunidades de errar em silêncio, e a conferência não podia pegar nenhuma
	porque não havia com o que comparar. Agora há um número por REGIÃO, medido,
	e o osso só escolhe a região dele.
	"""
	saida = {}
	for nome, _cabeca, _cauda, _pai in OSSOS:
		if nome in CAIXAS_DO_TRONCO:
			saida[nome] = CAIXAS_DO_TRONCO[nome]
			continue
		regiao = REGIAO_DO_OSSO.get(nome)
		if regiao is None or regiao not in ESBELTEZ:
			continue
		# O pé é desenhado como adorno, não como caixa de osso.
		if regiao == "pe":
			continue
		espessura = ESBELTEZ[regiao] * _comprimento(nome)
		saida[nome] = (espessura, espessura)
	return saida


## `(osso, largura, profundidade)`. A caixa de cada osso vai da cabeça à cauda
## dele; só a espessura é declarada aqui. Vale para osso VERTICAL — o pé, que
## aponta para a frente, é desenhado como adorno.
CAIXAS = _derivar_caixas()

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
## **O contraste é de VALOR, não de matiz.** O braço e o tronco eram dois azuis
## quase do mesmo brilho — 0,33 contra 0,44 — e na folha de contato do `parado`
## não dava para dizer onde o braço acabava e o corpo começava. A única peça que
## o olho conseguia seguir era a mão, e é a única que tinha cor própria: isso é
## a evidência de que o que faltava era contraste, e não curva na quina.
##
## Os valores aproximados (0,30·R + 0,59·G + 0,11·B), de trás para a frente:
## sapato 0,17, rosto 0,11, membro 0,23, roupa 0,44, pele 0,74, mão 0,60. O
## membro está agora a quase o dobro de distância do tronco.
CORES = {
	"pele": (0.85, 0.72, 0.60, 1.0),
	"roupa": (0.35, 0.45, 0.62, 1.0),
	"membro": (0.17, 0.21, 0.31, 1.0),
	"mao": (0.90, 0.52, 0.22, 1.0),
	"sapato": (0.13, 0.15, 0.19, 1.0),
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


## Quanto da menor dimensão da peça vira chanfro. Zero é o prisma reto que o
## usuário reprovou; um meio arredondaria a peça inteira e apagaria a silhueta.
CHANFRO = 0.22
## Em quantos passos o chanfro é cortado. Dois já lê como curva a três metros
## de distância, que é onde a câmera isométrica está; mais que isso é vértice
## gasto num boneco que é feio de propósito.
SEGMENTOS_DO_CHANFRO = 2
## Quantos vertices cada peca exporta. Sao invariantes da CONSTRUCAO — uma
## caixa chanfrada em dois passos, um prisma de oito lados — e estao declarados
## aqui para `tools/conferir_numeros.py` poder conferir o `.glb` commitado sem
## abrir o Blender. Trocar a forma sem trocar estes numeros reprova, que e o
## ponto: a contagem existe para pegar peca que sumiu do corpo exportado.
VERTICES_DA_CAIXA = 216
VERTICES_DO_TUBO = 48

## Lados do prisma dos membros. Oito lê como cilindro de longe e custa
## dezesseis vértices; quatro é a laje de antes.
LADOS_DO_MEMBRO = 8

## Que osso é desenhado como TUBO em vez de caixa chanfrada.
##
## Membro é a peça que mais precisa: ele é longo e fino, então a quina reta
## corre pelo comprimento inteiro e é ela que dá a leitura de tábua. Tronco e
## cabeça continuam caixa — chanfrada —, porque massa grande arredondada perde
## a orientação e o rosto precisa de uma frente chata onde a viseira assente.
DESENHADOS_COMO_TUBO = {
	"braco_D", "braco_E", "antebraco_D", "antebraco_E",
	"coxa_D", "coxa_E", "canela_D", "canela_E",
}


def _chanfrar(parte, tamanho: Vector) -> None:
	"""Corta as quinas da peça, proporcionalmente ao lado mais fino dela.

	**Proporcional e não em metros.** Um chanfro fixo de 2 cm é 6% da cabeça e
	17% do antebraço — a mesma linha de código produzindo peças com aparências
	diferentes. E um chanfro maior que a metade do lado mais fino consome a
	peça inteira, o que a Godot recebe como malha degenerada sem reclamar.
	"""
	menor = min(abs(v) for v in tamanho)
	largura = menor * CHANFRO
	if largura <= 0.0:
		return
	modificador = parte.modifiers.new(name="chanfro", type="BEVEL")
	modificador.width = largura
	modificador.segments = SEGMENTOS_DO_CHANFRO
	modificador.limit_method = "ANGLE"
	modificador.angle_limit = math.radians(30.0)
	bpy.context.view_layer.objects.active = parte
	bpy.ops.object.modifier_apply(modifier=modificador.name)


def _caixa(nome: str, centro: Vector, tamanho: Vector, material, grupo: str,
           tubo: bool = False, giro_do_osso: Quaternion = None):
	"""Uma peça, presa a um osso, chanfrada ou em forma de tubo.

	**O chanfro não mexe na caixa envolvente**, e isso não é sorte: o
	modificador corta só as ARESTAS e deixa o centro de cada face onde estava.
	Por isso a conferência de proporção continua medindo a mesma coisa que
	media quando cada peça era um prisma reto.
	"""
	if tubo:
		# O prisma nasce com o eixo em Z, que é a direção em que o osso corre.
		# O giro de meio lado põe uma FACE para a frente em vez de uma quina:
		# quina apontando para a câmera é exatamente o brilho que faz um tubo
		# parecer uma caixa girada.
		# **O raio é CIRCUNSCRITO, não inscrito, e a diferença foi medida.**
		# Um prisma de oito lados com o giro de meio lado apresenta a FACE para
		# os eixos, e a face está a `cos(pi/8)` do raio — 0,924. Com raio 0,5 a
		# peça saía 7,6% mais fina que a espessura pedida, sistematicamente, nos
		# quatro membros. A conferência aprovava porque a folga engolia o viés,
		# que é o pior jeito de uma tolerância ser útil: ela deixa de medir
		# defeito e passa a esconder um.
		#
		# Dividindo pelo cosseno, a caixa envolvente da peça volta a ser
		# exatamente a espessura declarada, e a folga volta a ser folga.
		bpy.ops.mesh.primitive_cylinder_add(
			vertices=LADOS_DO_MEMBRO,
			radius=0.5 / math.cos(math.pi / LADOS_DO_MEMBRO), depth=1.0,
			location=(0, 0, 0),
		)
	else:
		bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
	parte = bpy.context.active_object
	parte.name = "malha_" + nome
	parte.scale = tamanho
	# **A peça acompanha o OSSO — a matriz dele, não só a direção dele.**
	#
	# Enquanto todo osso era vertical, peça alinhada ao Z do mundo e peça
	# alinhada ao osso eram a mesma coisa. Com o braço aberto deixam de ser.
	#
	# E alinhar só a DIREÇÃO não basta: um osso tem torção em volta do próprio
	# eixo — o roll —, e um prisma de oito lados torcido em relação a ela volta
	# a apresentar a quina, medindo `1/cos(pi/8)` mais grosso. Foi o que fez os
	# dois braços reprovarem por 8% depois de as pernas já estarem exatas. Quem
	# carrega direção E torção é `matrix_local` do osso; a rotação de -90 graus
	# em X é só o remapeamento do eixo, porque a peça nasce com o comprimento
	# em Z e o osso corre em Y.
	# O giro do octógono e o giro do osso se COMPÕEM, e a ordem importa: o
	# prisma gira meio lado em torno do próprio eixo, e só depois o conjunto vai
	# para a direção do osso. Escritos como duas atribuições, a segunda apagava
	# a primeira — o prisma voltava a apresentar a QUINA aos eixos, e a caixa
	# envolvente dele crescia exatamente `1/cos(pi/8)`, que é 1,082. Foi assim
	# que as quatro pernas e braços reprovaram por 8% de uma vez só.
	giro = giro_do_osso if giro_do_osso is not None else Quaternion(
		(1.0, 0.0, 0.0), 0.0)
	if tubo:
		giro = giro @ Quaternion((0.0, 0.0, 1.0), math.pi / LADOS_DO_MEMBRO)
	parte.rotation_euler = giro.to_euler()
	parte.location = centro
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	if not tubo:
		_chanfrar(parte, tamanho)
	parte.data.materials.append(material)
	vertices = parte.vertex_groups.new(name=grupo)
	vertices.add(range(len(parte.data.vertices)), 1.0, "REPLACE")
	return parte


## Leva o eixo do comprimento da peça (Z) para o eixo do osso (Y).
_DE_Z_PARA_Y = Quaternion((1.0, 0.0, 0.0), -math.pi * 0.5)


def _giro_do_osso(armature: bpy.types.Object, nome: str) -> Quaternion:
	"""A orientação de repouso do osso, já remapeada para o eixo da peça."""
	osso = armature.data.bones.get(nome)
	if osso is None:
		return Quaternion((1.0, 0.0, 0.0), 0.0)
	return osso.matrix_local.to_quaternion() @ _DE_Z_PARA_Y


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
			tubo=nome in DESENHADOS_COMO_TUBO,
			giro_do_osso=_giro_do_osso(armature, nome),
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
	# Caído: `knockout_idle`, **1,33 s nos 32 campeões**, ciclo. É o estado de
	# quem foi derrubado e ainda não morreu — o abatido do battle royale, que
	# espera ser reerguido ou acabado.
	#
	# Divide a POSTURA com a morte de propósito: mesmo corpo de costas, mesma
	# base. O que separa os dois é que este RESPIRA e aquele não, e é essa
	# diferença — não a pose — que diz ao jogador se ainda dá para salvar.
	"caido": {
		"ciclo": True,
		"chaves": [
			(0, pose(
				quadril=(-90, 0, 0), peito=(6, 0, 0), cabeca=(10, 0, 0),
				braco_D=(14, -58, 0), antebraco_D=(-16, 0, 0),
				braco_E=(14, 58, 0), antebraco_E=(-16, 0, 0),
				coxa_D=(-3, -7, 0), canela_D=(0, 0, 0), pe_D=pe(-3, 0),
				coxa_E=(-2, 5, 0), canela_E=(0, 0, 0), pe_E=pe(-2, 0))),
			# Puxa o ar: o peito sobe, a cabeça pende para o lado, uma perna
			# tenta se recolher.
			(13, pose(
				quadril=(-87, 0, 0), peito=(11, 0, 0), cabeca=(6, -9, 0),
				braco_D=(19, -50, 0), antebraco_D=(-24, 0, 0),
				braco_E=(11, 62, 0), antebraco_E=(-11, 0, 0),
				coxa_D=(-7, -10, 0), canela_D=(-8, 0, 0), pe_D=pe(-7, -8),
				coxa_E=(-1, 4, 0), canela_E=(0, 0, 0), pe_E=pe(-1, 0))),
			(26, pose(
				quadril=(-92, 0, 0), peito=(3, 0, 0), cabeca=(12, 6, 0),
				braco_D=(11, -62, 0), antebraco_D=(-12, 0, 0),
				braco_E=(17, 53, 0), antebraco_E=(-21, 0, 0),
				coxa_D=(-1, -5, 0), canela_D=(0, 0, 0), pe_D=pe(-1, 0),
				coxa_E=(-6, 7, 0), canela_E=(-7, 0, 0), pe_E=pe(-6, -7))),
			(40, pose(
				quadril=(-90, 0, 0), peito=(6, 0, 0), cabeca=(10, 0, 0),
				braco_D=(14, -58, 0), antebraco_D=(-16, 0, 0),
				braco_E=(14, 58, 0), antebraco_E=(-16, 0, 0),
				coxa_D=(-3, -7, 0), canela_D=(0, 0, 0), pe_D=pe(-3, 0),
				coxa_E=(-2, 5, 0), canela_E=(0, 0, 0), pe_E=pe(-2, 0))),
		],
	},
	# Rastejando: `knockout_run`, 1,13 / 1,13 / 1,33 s, ciclo. O abatido que se
	# arrasta — a locomoção do estado derrubado.
	#
	# **De bruços, e não de costas como o `caido`.** +90 graus no quadril
	# apontam o tronco para a FRENTE e as pernas para trás; -90 fazem o
	# contrário, que é o corpo de costas. Os dois estados do abatido usam
	# rotações opostas do mesmo osso, e é a única diferença estrutural entre
	# eles.
	#
	# O braço precisa de -150 graus para alcançar à frente: de bruços ele nasce
	# apontando para os pés, e trazê-lo para a frente é quase meia volta. É a
	# mesma conta do `erguer`, que ergue os braços com -166.
	#
	# **E a perna abre em Z, não em Y.** Num corpo de pé o `Y` tomba o membro
	# para o lado; num corpo DEITADO a perna já aponta ao longo do eixo Y, e
	# girá-la em torno de Y a faz rodar sobre si mesma — o que não move nada na
	# tela. Quem abre a perna de um corpo deitado é o `Z`. A primeira versão
	# usou `Y` e compensou com um joelho de -58 graus, e o resultado foram as
	# duas canelas em pé no ar: a folha de contato mostrou um corpo rastejando
	# com as pernas para cima.
	"rastejando": {
		"ciclo": True,
		"chaves": [
			# Braço direito à frente, joelho esquerdo puxado: é a diagonal, que
			# é como um corpo se arrasta de verdade.
			(0, pose(
				quadril=(88, 0, 0), peito=(-16, 0, 0), cabeca=(-34, 0, 0),
				braco_D=(-152, -20, 0), antebraco_D=(-28, 0, 0),
				braco_E=(-96, 22, 0), antebraco_E=(-44, 0, 0),
				coxa_D=(0, 0, -7), canela_D=(-6, 0, 0), pe_D=pe(0, -6),
				coxa_E=(-6, 0, 32), canela_E=(-26, 0, 0), pe_E=pe(-6, -26))),
			# Puxa: o braço da frente traz o corpo, o joelho empurra.
			(9, pose(
				quadril=(90, 0, 0), peito=(-11, 0, 0), cabeca=(-30, 0, 0),
				braco_D=(-124, -14, 0), antebraco_D=(-48, 0, 0),
				braco_E=(-120, 16, 0), antebraco_E=(-30, 0, 0),
				coxa_D=(-3, 0, -20), canela_D=(-16, 0, 0), pe_D=pe(-3, -16),
				coxa_E=(-3, 0, 20), canela_E=(-16, 0, 0), pe_E=pe(-3, -16))),
			# A diagonal trocada.
			(17, pose(
				quadril=(88, 0, 0), peito=(-16, 0, 0), cabeca=(-34, 0, 0),
				braco_E=(-152, 20, 0), antebraco_E=(-28, 0, 0),
				braco_D=(-96, -22, 0), antebraco_D=(-44, 0, 0),
				coxa_E=(0, 0, 7), canela_E=(-6, 0, 0), pe_E=pe(0, -6),
				coxa_D=(-6, 0, -32), canela_D=(-26, 0, 0), pe_D=pe(-6, -26))),
			(26, pose(
				quadril=(90, 0, 0), peito=(-11, 0, 0), cabeca=(-30, 0, 0),
				braco_E=(-124, 14, 0), antebraco_E=(-48, 0, 0),
				braco_D=(-120, -16, 0), antebraco_D=(-30, 0, 0),
				coxa_E=(-3, 0, 20), canela_E=(-16, 0, 0), pe_E=pe(-3, -16),
				coxa_D=(-3, 0, -20), canela_D=(-16, 0, 0), pe_D=pe(-3, -16))),
			(35, pose(
				quadril=(88, 0, 0), peito=(-16, 0, 0), cabeca=(-34, 0, 0),
				braco_D=(-152, -20, 0), antebraco_D=(-28, 0, 0),
				braco_E=(-96, 22, 0), antebraco_E=(-44, 0, 0),
				coxa_D=(0, 0, -7), canela_D=(-6, 0, 0), pe_D=pe(0, -6),
				coxa_E=(-6, 0, 32), canela_E=(-26, 0, 0), pe_E=pe(-6, -26))),
		],
	},
	# Colhendo: `collect`, 0,67 s nos 32, ciclo — o mais curto do vocabulário
	# universal junto com `loot`. Agachado, a mão indo ao chão e voltando.
	#
	# **Quem leva a mão ao chão é o TRONCO, não o ombro.** A primeira versão
	# girava o braço 46 graus para a frente e dobrava o cotovelo, e o resultado
	# foi um personagem agachado APONTANDO para a frente, com a mão na altura do
	# peito. O braço tem 0,40 m do ombro ao pulso — não alcança o chão por
	# rotação nenhuma. Ele fica quase pendurado, e são os 54 graus de peito e os
	# 78 de joelho que descem o ombro até onde a mão chega.
	#
	# **É um dos três clipes do original que carregam evento de animação**, com
	# `cut` e `mine` — os três de bater ou colher, e nenhum de combate (§7).
	# O nosso não tem: dano e colheita vêm da tabela, não do quadro.
	"colhendo": {
		"ciclo": True,
		"chaves": [
			(0, pose(
				peito=(54, 0, 0), cabeca=(-24, 0, 0),
				braco_D=(-4, -11, 0), antebraco_D=(-12, 0, 0),
				braco_E=(8, 17, 0), antebraco_E=(-22, 0, 0),
				coxa_D=(-42, 0, 0), canela_D=(78, 0, 0), pe_D=pe(-42, 78),
				coxa_E=(-42, 0, 0), canela_E=(78, 0, 0), pe_E=pe(-42, 78))),
			# Fecha a mão e traz para junto do corpo.
			(7, pose(
				peito=(34, 0, 0), cabeca=(-14, 0, 0),
				braco_D=(10, -9, 0), antebraco_D=(-78, 0, 0),
				braco_E=(6, 14, 0), antebraco_E=(-18, 0, 0),
				coxa_D=(-30, 0, 0), canela_D=(56, 0, 0), pe_D=pe(-30, 56),
				coxa_E=(-30, 0, 0), canela_E=(56, 0, 0), pe_E=pe(-30, 56))),
			(13, pose(
				peito=(46, 0, 0), cabeca=(-20, 0, 0),
				braco_D=(2, -10, 0), antebraco_D=(-40, 0, 0),
				braco_E=(7, 16, 0), antebraco_E=(-20, 0, 0),
				coxa_D=(-37, 0, 0), canela_D=(69, 0, 0), pe_D=pe(-37, 69),
				coxa_E=(-37, 0, 0), canela_E=(69, 0, 0), pe_E=pe(-37, 69))),
			(20, pose(
				peito=(54, 0, 0), cabeca=(-24, 0, 0),
				braco_D=(-4, -11, 0), antebraco_D=(-12, 0, 0),
				braco_E=(8, 17, 0), antebraco_E=(-22, 0, 0),
				coxa_D=(-42, 0, 0), canela_D=(78, 0, 0), pe_D=pe(-42, 78),
				coxa_E=(-42, 0, 0), canela_E=(78, 0, 0), pe_E=pe(-42, 78))),
		],
	},
	# Pegando: `loot`, 0,50 s nos 32, e **uma vez** — é o único verbo de mundo
	# que não é ciclo. Faz sentido: colher, cortar e minerar são trabalho que
	# continua; pegar do chão acontece uma vez e acaba.
	#
	# 15 quadros é o clipe mais curto do vocabulário inteiro, e por isso ele não
	# tem antecipação nenhuma: em meio segundo não cabe recuo, golpe e volta.
	"pegando": {
		"ciclo": False,
		"chaves": [
			(0, pose()),
			(6, pose(
				peito=(60, 0, 0), cabeca=(-28, 0, 0),
				braco_D=(-8, -12, 0), antebraco_D=(-10, 0, 0),
				braco_E=(12, 22, 0), antebraco_E=(-26, 0, 0),
				coxa_D=(-46, 0, 0), canela_D=(84, 0, 0), pe_D=pe(-46, 84),
				coxa_E=(-32, 0, 0), canela_E=(60, 0, 0), pe_E=pe(-32, 60))),
			# Fecha a mão. O corpo já começa a subir — o objeto sobe com ele,
			# que é o que faz o gesto ler como "pegou" e não como "encostou".
			(10, pose(
				peito=(26, 0, 0), cabeca=(-10, 0, 0),
				braco_D=(14, -9, 0), antebraco_D=(-96, 0, 0),
				braco_E=(8, 14, 0), antebraco_E=(-16, 0, 0),
				coxa_D=(-22, 0, 0), canela_D=(42, 0, 0), pe_D=pe(-22, 42),
				coxa_E=(-16, 0, 0), canela_E=(30, 0, 0), pe_E=pe(-16, 30))),
			(15, pose()),
		],
	},
	# Cortando árvore: `cut`, **1,50 s exatos nos 32 campeões**, ciclo. Junto com
	# `mine` é o clipe mais longo do vocabulário de trabalho, e os dois têm a
	# mesma duração — são a mesma ação com ferramenta diferente.
	#
	# **O que separa `cortando` de `minerando` é o PLANO do golpe**: cortar é
	# horizontal, na altura do peito, e quem o executa é a torção do quadril;
	# minerar é vertical, de cima para baixo, e quem o executa é o ombro. Com o
	# mesmo plano os dois seriam o mesmo clipe com dois nomes.
	"cortando": {
		"ciclo": True,
		"chaves": [
			# Armado: o corpo torcido para a direita, as duas mãos juntas.
			(0, pose(
				quadril=(0, 0, 42), peito=(4, 0, 0), cabeca=(2, -14, 0),
				braco_D=(-72, -20, 0), antebraco_D=(-48, 0, 0),
				braco_E=(-66, 10, 0), antebraco_E=(-58, 0, 0),
				coxa_D=(-13, 0, 0), canela_D=(24, 0, 0), pe_D=pe(-13, 24),
				coxa_E=(-13, 0, 0), canela_E=(24, 0, 0), pe_E=pe(-13, 24))),
			# O golpe atravessa. O quadril chega primeiro e os braços vêm
			# atrás — é o que dá peso, e é por isso que a torção é a chave.
			(14, pose(
				quadril=(0, 0, -32), peito=(15, 0, 0), cabeca=(4, 10, 0),
				braco_D=(-86, -6, 0), antebraco_D=(-18, 0, 0),
				braco_E=(-80, 20, 0), antebraco_E=(-28, 0, 0),
				coxa_D=(-19, 0, 0), canela_D=(34, 0, 0), pe_D=pe(-19, 34),
				coxa_E=(-10, 0, 0), canela_E=(19, 0, 0), pe_E=pe(-10, 19))),
			# A madeira devolve: pequeno repique para trás.
			(22, pose(
				quadril=(0, 0, -14), peito=(9, 0, 0), cabeca=(2, 5, 0),
				braco_D=(-74, -10, 0), antebraco_D=(-32, 0, 0),
				braco_E=(-70, 15, 0), antebraco_E=(-40, 0, 0),
				coxa_D=(-15, 0, 0), canela_D=(28, 0, 0), pe_D=pe(-15, 28),
				coxa_E=(-12, 0, 0), canela_E=(22, 0, 0), pe_E=pe(-12, 22))),
			# Arma de novo, devagar: metade do ciclo é a recarga.
			(33, pose(
				quadril=(0, 0, 20), peito=(6, 0, 0), cabeca=(2, -7, 0),
				braco_D=(-78, -16, 0), antebraco_D=(-42, 0, 0),
				braco_E=(-72, 12, 0), antebraco_E=(-50, 0, 0),
				coxa_D=(-14, 0, 0), canela_D=(26, 0, 0), pe_D=pe(-14, 26),
				coxa_E=(-14, 0, 0), canela_E=(26, 0, 0), pe_E=pe(-14, 26))),
			(45, pose(
				quadril=(0, 0, 42), peito=(4, 0, 0), cabeca=(2, -14, 0),
				braco_D=(-72, -20, 0), antebraco_D=(-48, 0, 0),
				braco_E=(-66, 10, 0), antebraco_E=(-58, 0, 0),
				coxa_D=(-13, 0, 0), canela_D=(24, 0, 0), pe_D=pe(-13, 24),
				coxa_E=(-13, 0, 0), canela_E=(24, 0, 0), pe_E=pe(-13, 24))),
		],
	},
	# Minerando: `mine`, **1,50 s exatos nos 32**, ciclo — a mesma duração de
	# `cut`, e o mesmo trabalho num plano diferente: aqui o golpe é VERTICAL, de
	# cima para baixo, e quem o executa é o ombro em vez da torção.
	"minerando": {
		"ciclo": True,
		"chaves": [
			# Picareta no alto, atrás da cabeça.
			(0, pose(
				peito=(-10, 0, 0), cabeca=(14, 0, 0),
				braco_D=(-168, -12, 0), antebraco_D=(-46, 0, 0),
				braco_E=(-160, 12, 0), antebraco_E=(-52, 0, 0),
				coxa_D=(-11, 0, 0), canela_D=(20, 0, 0), pe_D=pe(-11, 20),
				coxa_E=(-11, 0, 0), canela_E=(20, 0, 0), pe_E=pe(-11, 20))),
			# Desce. O tronco dobra junto — a força vem das costas, não do
			# braço, e sem a dobra o gesto lê como acenar.
			(13, pose(
				peito=(38, 0, 0), cabeca=(-16, 0, 0),
				braco_D=(-16, -10, 0), antebraco_D=(-12, 0, 0),
				braco_E=(-14, 10, 0), antebraco_E=(-14, 0, 0),
				coxa_D=(-30, 0, 0), canela_D=(56, 0, 0), pe_D=pe(-30, 56),
				coxa_E=(-30, 0, 0), canela_E=(56, 0, 0), pe_E=pe(-30, 56))),
			# A pedra devolve.
			(20, pose(
				peito=(28, 0, 0), cabeca=(-12, 0, 0),
				braco_D=(-40, -11, 0), antebraco_D=(-26, 0, 0),
				braco_E=(-38, 11, 0), antebraco_E=(-28, 0, 0),
				coxa_D=(-24, 0, 0), canela_D=(44, 0, 0), pe_D=pe(-24, 44),
				coxa_E=(-24, 0, 0), canela_E=(44, 0, 0), pe_E=pe(-24, 44))),
			(33, pose(
				peito=(4, 0, 0), cabeca=(2, 0, 0),
				braco_D=(-118, -12, 0), antebraco_D=(-40, 0, 0),
				braco_E=(-112, 12, 0), antebraco_E=(-44, 0, 0),
				coxa_D=(-15, 0, 0), canela_D=(28, 0, 0), pe_D=pe(-15, 28),
				coxa_E=(-15, 0, 0), canela_E=(28, 0, 0), pe_E=pe(-15, 28))),
			(45, pose(
				peito=(-10, 0, 0), cabeca=(14, 0, 0),
				braco_D=(-168, -12, 0), antebraco_D=(-46, 0, 0),
				braco_E=(-160, 12, 0), antebraco_E=(-52, 0, 0),
				coxa_D=(-11, 0, 0), canela_D=(20, 0, 0), pe_D=pe(-11, 20),
				coxa_E=(-11, 0, 0), canela_E=(20, 0, 0), pe_E=pe(-11, 20))),
		],
	},
	# Comendo: `eat`, **6,57 s nos 32 campeões**, ciclo — o clipe mais LONGO de
	# todo o `_animation.pak`, cinco vezes a mediana de 1,20 s.
	#
	# A duração é a informação: comer é a ação mais demorada de um battle
	# royale, e quem come está indefeso por seis segundos e meio. Encurtá-la
	# para caber num ritmo de combate seria apagar exatamente o que ela diz.
	#
	# 197 quadros a 30 fps dão 6,567 s, que arredonda para os 6,57 publicados.
	# Não existe número inteiro de quadros que dê 6,57 exatos — é por isso que
	# a conferência compara a duração ARREDONDADA.
	"comendo": {
		"ciclo": True,
		"chaves": [
			# Segurando junto ao peito.
			(0, pose(
				peito=(6, 0, 0), cabeca=(4, 0, 0),
				braco_D=(-18, -12, 0), antebraco_D=(-72, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-24, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			# Leva à boca.
			(32, pose(
				peito=(3, 0, 0), cabeca=(6, 0, 0),
				braco_D=(-46, -15, 0), antebraco_D=(-118, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-24, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			# Morde: a cabeça avança e volta.
			(46, pose(
				peito=(3, 0, 0), cabeca=(15, 0, 0),
				braco_D=(-48, -15, 0), antebraco_D=(-122, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-24, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			# Mastiga: a mão desce um pouco e a cabeça balança devagar. É a
			# parte mais longa, e é o que faz seis segundos e meio passarem.
			(70, pose(
				peito=(5, 0, 0), cabeca=(-2, 0, 0),
				braco_D=(-26, -13, 0), antebraco_D=(-88, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-24, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			(90, pose(
				peito=(6, 0, 0), cabeca=(9, -4, 0),
				braco_D=(-24, -12, 0), antebraco_D=(-84, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-24, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			(110, pose(
				peito=(5, 0, 0), cabeca=(-1, 4, 0),
				braco_D=(-26, -13, 0), antebraco_D=(-88, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-24, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			# Segunda mordida.
			(134, pose(
				peito=(3, 0, 0), cabeca=(6, 0, 0),
				braco_D=(-46, -15, 0), antebraco_D=(-118, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-24, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			(148, pose(
				peito=(3, 0, 0), cabeca=(15, 0, 0),
				braco_D=(-48, -15, 0), antebraco_D=(-122, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-24, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			(172, pose(
				peito=(6, 0, 0), cabeca=(0, 0, 0),
				braco_D=(-22, -12, 0), antebraco_D=(-80, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-24, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			(197, pose(
				peito=(6, 0, 0), cabeca=(4, 0, 0),
				braco_D=(-18, -12, 0), antebraco_D=(-72, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-24, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
		],
	},
	# Bebendo: `drink`, 1,00 / 1,00 / 3,00 s, ciclo. A mediana é 1,00 s e é ela
	# que vale: a faixa até 3,00 vem de poucos campeões.
	#
	# O que separa `bebendo` de `comendo` é a CABEÇA: comer avança o queixo,
	# beber joga a cabeça para trás. São o mesmo braço.
	"bebendo": {
		"ciclo": True,
		"chaves": [
			(0, pose(
				peito=(4, 0, 0), cabeca=(2, 0, 0),
				braco_D=(-20, -12, 0), antebraco_D=(-76, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-20, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			# Leva à boca e joga a cabeça para trás.
			(11, pose(
				peito=(-4, 0, 0), cabeca=(-26, 0, 0),
				braco_D=(-58, -14, 0), antebraco_D=(-112, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-20, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			(19, pose(
				peito=(-7, 0, 0), cabeca=(-38, 0, 0),
				braco_D=(-70, -14, 0), antebraco_D=(-104, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-20, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
			(30, pose(
				peito=(4, 0, 0), cabeca=(2, 0, 0),
				braco_D=(-20, -12, 0), antebraco_D=(-76, 0, 0),
				braco_E=(4, 10, 0), antebraco_E=(-20, 0, 0),
				coxa_D=(-5, 0, 0), canela_D=(9, 0, 0), pe_D=pe(-5, 9),
				coxa_E=(-5, 0, 0), canela_E=(9, 0, 0), pe_E=pe(-5, 9))),
		],
	},
	# Operando: `operate`, 1,00 s nos 32, ciclo. Mexer numa máquina — alavanca,
	# manivela, painel. É o sétimo e último verbo de mundo do original.
	#
	# As duas mãos ficam à frente, na altura do peito, e ALTERNAM. Alternar é o
	# que separa "operando" de "parado com os braços erguidos": o olho lê
	# trabalho quando as duas partes se revezam.
	"operando": {
		"ciclo": True,
		"chaves": [
			(0, pose(
				peito=(11, 0, 0), cabeca=(3, 0, 0),
				braco_D=(-68, -9, 0), antebraco_D=(-38, 0, 0),
				braco_E=(-44, 11, 0), antebraco_E=(-66, 0, 0),
				coxa_D=(-7, 0, 0), canela_D=(13, 0, 0), pe_D=pe(-7, 13),
				coxa_E=(-7, 0, 0), canela_E=(13, 0, 0), pe_E=pe(-7, 13))),
			(10, pose(
				peito=(14, 0, 0), cabeca=(2, 0, 0),
				braco_D=(-44, -11, 0), antebraco_D=(-66, 0, 0),
				braco_E=(-68, 9, 0), antebraco_E=(-38, 0, 0),
				coxa_D=(-10, 0, 0), canela_D=(19, 0, 0), pe_D=pe(-10, 19),
				coxa_E=(-10, 0, 0), canela_E=(19, 0, 0), pe_E=pe(-10, 19))),
			(20, pose(
				peito=(9, 0, 0), cabeca=(4, 0, 0),
				braco_D=(-60, -10, 0), antebraco_D=(-50, 0, 0),
				braco_E=(-52, 10, 0), antebraco_E=(-54, 0, 0),
				coxa_D=(-6, 0, 0), canela_D=(11, 0, 0), pe_D=pe(-6, 11),
				coxa_E=(-6, 0, 0), canela_E=(11, 0, 0), pe_E=pe(-6, 11))),
			(30, pose(
				peito=(11, 0, 0), cabeca=(3, 0, 0),
				braco_D=(-68, -9, 0), antebraco_D=(-38, 0, 0),
				braco_E=(-44, 11, 0), antebraco_E=(-66, 0, 0),
				coxa_D=(-7, 0, 0), canela_D=(13, 0, 0), pe_D=pe(-7, 13),
				coxa_E=(-7, 0, 0), canela_E=(13, 0, 0), pe_E=pe(-7, 13))),
		],
	},
	# ------------------------------------------------------------ arremesso
	#
	# `throw`, 0,80 s de mediana nos 32, uma vez. **É a conjuração universal**:
	# no original todo campeão tem `throw`, `throw_f` e `throw_b`, e os clipes
	# PRÓPRIOS de habilidade — de 2 a 14 por campeão — vêm por cima disso.
	#
	# Aqui ele é o gesto de quem lança alguma coisa, e `GestoDeConjuracao` o
	# escolhe para a forma PROJECTILE. São 359 pulsos de projétil no corpus
	# traduzido, em 223 habilidades: era a forma mais comum sem gesto próprio,
	# e desenhá-la como estocada fazia arremessar parecer esfaquear.
	"arremesso": {
		"ciclo": False,
		"chaves": [
			(0, pose()),
			# Arma: o corpo torce para a direita e o braço vai para trás e para
			# cima. É a antecipação, e num arremesso ela é o gesto inteiro —
			# sem ela a mão só aparece do outro lado.
			(7, pose(
				quadril=(0, 0, 34), peito=(-9, 0, 0), cabeca=(0, -10, 0),
				braco_D=(76, -22, 0), antebraco_D=(-84, 0, 0),
				braco_E=(-34, 16, 0), antebraco_E=(-30, 0, 0),
				coxa_D=(10, 0, 0), canela_D=(14, 0, 0), pe_D=pe(10, 14),
				coxa_E=(-8, 0, 0), canela_E=(15, 0, 0), pe_E=pe(-8, 15))),
			# Solta: o braço passa por cima e a torção se desfaz na frente.
			(14, pose(
				quadril=(0, 0, -26), peito=(16, 0, 0), cabeca=(-4, 8, 0),
				braco_D=(-126, -8, 0), antebraco_D=(-12, 0, 0),
				braco_E=(28, 18, 0), antebraco_E=(-46, 0, 0),
				coxa_D=(-22, 0, 0), canela_D=(16, 0, 0), pe_D=pe(-22, 16),
				coxa_E=(16, 0, 0), canela_E=(12, 0, 0), pe_E=pe(16, 12, -10))),
			# Acompanha: a mão continua descendo depois de soltar.
			(19, pose(
				quadril=(0, 0, -16), peito=(12, 0, 0), cabeca=(-2, 5, 0),
				braco_D=(-78, -10, 0), antebraco_D=(-26, 0, 0),
				braco_E=(20, 14, 0), antebraco_E=(-38, 0, 0),
				coxa_D=(-16, 0, 0), canela_D=(12, 0, 0), pe_D=pe(-16, 12),
				coxa_E=(12, 0, 0), canela_E=(9, 0, 0), pe_E=pe(12, 9, -8))),
			(24, pose()),
		],
	},
	# Arremesso indo à frente: `throw_f`.
	#
	# **Dura EXATAMENTE um ciclo de `correndo`, e isso é regra medida.** No
	# original `throw_b` tem a mesma duração de `run` em 30 dos 32 campeões e
	# `throw_f` em 29 — não é coincidência, é o corpo de cima sobreposto às
	# pernas que continuam correndo. Se o comprimento não casasse, o passo daria
	# um salto no meio do arremesso. É o §5 de `docs/11`, e
	# `conferir_numeros.py` reprova se as três durações se separarem.
	#
	# As pernas são as MESMAS chaves de `correndo`, inclusive o voo: por baixo
	# isto é a corrida. O que muda é da cintura para cima.
	"arremesso_a_frente": {
		"ciclo": False,
		"voo": {0: 0.0, 6: 0.14, 12: 0.0, 18: 0.14, 24: 0.0},
		"chaves": [
			(0, pose(
				coxa_D=(-38, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-38, 14, -12),
				coxa_E=(34, 0, 0), canela_E=(10, 0, 0), pe_E=pe(34, 10, 10),
				braco_D=(46, -8, 0), antebraco_D=(-78, 0, 0),
				braco_E=(-46, 8, 0), antebraco_E=(-78, 0, 0),
				peito=(15, 0, 0), cabeca=(-8, 0, 0))),
			# Arma sem parar de correr: o braço vai para trás e para cima
			# enquanto a perna faz a passagem.
			(6, pose(
				coxa_D=(-10, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-10, 14),
				coxa_E=(-24, 0, 0), canela_E=(92, 0, 0), pe_E=pe(-24, 92, 20),
				braco_D=(74, -20, 0), antebraco_D=(-80, 0, 0),
				braco_E=(-40, 14, 0), antebraco_E=(-40, 0, 0),
				peito=(8, 0, 0), cabeca=(-4, -10, 0))),
			(12, pose(
				coxa_E=(-38, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-38, 14, -12),
				coxa_D=(34, 0, 0), canela_D=(10, 0, 0), pe_D=pe(34, 10, 10),
				braco_D=(-124, -8, 0), antebraco_D=(-14, 0, 0),
				braco_E=(24, 16, 0), antebraco_E=(-50, 0, 0),
				peito=(20, 0, 0), cabeca=(-10, 6, 0))),
			(18, pose(
				coxa_E=(-10, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-10, 14),
				coxa_D=(-24, 0, 0), canela_D=(92, 0, 0), pe_D=pe(-24, 92, 20),
				braco_D=(-40, -9, 0), antebraco_D=(-56, 0, 0),
				braco_E=(-10, 10, 0), antebraco_E=(-70, 0, 0),
				peito=(17, 0, 0), cabeca=(-9, 2, 0))),
			# O último quadro repete o primeiro para a passada emendar de volta
			# na corrida. Ele não é ciclo — mas a perna precisa fechar mesmo
			# assim, porque é para o ciclo dela que o corpo volta.
			(24, pose(
				coxa_D=(-38, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-38, 14, -12),
				coxa_E=(34, 0, 0), canela_E=(10, 0, 0), pe_E=pe(34, 10, 10),
				braco_D=(46, -8, 0), antebraco_D=(-78, 0, 0),
				braco_E=(-46, 8, 0), antebraco_E=(-78, 0, 0),
				peito=(15, 0, 0), cabeca=(-8, 0, 0))),
		],
	},
	# Arremesso indo atrás: `throw_b`, e a mesma duração — um ciclo de corrida.
	#
	# As pernas são as de `correndo` na ordem INVERTIDA, que é o que dá o
	# recuo, e o tronco se inclina para trás em vez de para a frente. O
	# arremesso de cima é o mesmo: é a mesma habilidade saindo, e mudar o gesto
	# do braço faria a mesma conjuração parecer duas.
	"arremesso_atras": {
		"ciclo": False,
		"voo": {0: 0.0, 6: 0.14, 12: 0.0, 18: 0.14, 24: 0.0},
		"chaves": [
			(0, pose(
				coxa_D=(34, 0, 0), canela_D=(10, 0, 0), pe_D=pe(34, 10, 10),
				coxa_E=(-38, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-38, 14, -12),
				braco_D=(46, -8, 0), antebraco_D=(-70, 0, 0),
				braco_E=(-46, 8, 0), antebraco_E=(-70, 0, 0),
				peito=(-12, 0, 0), cabeca=(6, 0, 0))),
			(6, pose(
				coxa_D=(-24, 0, 0), canela_D=(92, 0, 0), pe_D=pe(-24, 92, 20),
				coxa_E=(-10, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-10, 14),
				braco_D=(74, -20, 0), antebraco_D=(-78, 0, 0),
				braco_E=(-40, 14, 0), antebraco_E=(-40, 0, 0),
				peito=(-16, 0, 0), cabeca=(8, -10, 0))),
			(12, pose(
				coxa_E=(34, 0, 0), canela_E=(10, 0, 0), pe_E=pe(34, 10, 10),
				coxa_D=(-38, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-38, 14, -12),
				braco_D=(-124, -8, 0), antebraco_D=(-14, 0, 0),
				braco_E=(24, 16, 0), antebraco_E=(-50, 0, 0),
				peito=(-4, 0, 0), cabeca=(2, 6, 0))),
			(18, pose(
				coxa_E=(-24, 0, 0), canela_E=(92, 0, 0), pe_E=pe(-24, 92, 20),
				coxa_D=(-10, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-10, 14),
				braco_D=(-40, -9, 0), antebraco_D=(-56, 0, 0),
				braco_E=(-10, 10, 0), antebraco_E=(-70, 0, 0),
				peito=(-10, 0, 0), cabeca=(5, 2, 0))),
			(24, pose(
				coxa_D=(34, 0, 0), canela_D=(10, 0, 0), pe_D=pe(34, 10, 10),
				coxa_E=(-38, 0, 0), canela_E=(14, 0, 0), pe_E=pe(-38, 14, -12),
				braco_D=(46, -8, 0), antebraco_D=(-70, 0, 0),
				braco_E=(-46, 8, 0), antebraco_E=(-70, 0, 0),
				peito=(-12, 0, 0), cabeca=(6, 0, 0))),
		],
	},
	# Montado, parado: `ride_idle`, **1,33 s nos 32**, ciclo.
	#
	# A perna vai à frente e o joelho volta para baixo — é a posição de quem
	# monta, e o que a distingue de um agachamento é o TRONCO: aqui ele fica
	# ereto e as mãos ficam à frente, segurando.
	"montado": {
		"ciclo": True,
		"chaves": [
			(0, pose(
				peito=(6, 0, 0), cabeca=(-2, 0, 0),
				braco_D=(-54, -16, 0), antebraco_D=(-40, 0, 0),
				braco_E=(-54, 16, 0), antebraco_E=(-40, 0, 0),
				coxa_D=(-66, -20, 0), canela_D=(62, 0, 0), pe_D=pe(-66, 62),
				coxa_E=(-66, 20, 0), canela_E=(62, 0, 0), pe_E=pe(-66, 62))),
			# O animal respira por baixo: o corpo sobe e desce um pouco.
			(13, pose(
				peito=(3, 0, 0), cabeca=(0, 0, 0),
				braco_D=(-50, -15, 0), antebraco_D=(-44, 0, 0),
				braco_E=(-50, 15, 0), antebraco_E=(-44, 0, 0),
				coxa_D=(-70, -21, 0), canela_D=(68, 0, 0), pe_D=pe(-70, 68),
				coxa_E=(-70, 21, 0), canela_E=(68, 0, 0), pe_E=pe(-70, 68))),
			(26, pose(
				peito=(8, 0, 0), cabeca=(-4, 0, 0),
				braco_D=(-57, -17, 0), antebraco_D=(-37, 0, 0),
				braco_E=(-57, 17, 0), antebraco_E=(-37, 0, 0),
				coxa_D=(-63, -19, 0), canela_D=(58, 0, 0), pe_D=pe(-63, 58),
				coxa_E=(-63, 19, 0), canela_E=(58, 0, 0), pe_E=pe(-63, 58))),
			(40, pose(
				peito=(6, 0, 0), cabeca=(-2, 0, 0),
				braco_D=(-54, -16, 0), antebraco_D=(-40, 0, 0),
				braco_E=(-54, 16, 0), antebraco_E=(-40, 0, 0),
				coxa_D=(-66, -20, 0), canela_D=(62, 0, 0), pe_D=pe(-66, 62),
				coxa_E=(-66, 20, 0), canela_E=(62, 0, 0), pe_E=pe(-66, 62))),
		],
	},
	# Montado, andando: `ride_run`, **0,60 s nos 32**, ciclo — 18 quadros, o
	# clipe mais curto de todo o vocabulário universal.
	#
	# O corpo sobe e desce no ritmo do galope, e quem faz isso é o joelho: sem
	# `voo`, o pé continua encostado e a conferência de chão continua valendo.
	# Um `voo` aqui exigiria declarar quanto o cavaleiro sai da sela, e esse
	# número não existe enquanto a sela não existir.
	"montado_correndo": {
		"ciclo": True,
		"chaves": [
			(0, pose(
				peito=(16, 0, 0), cabeca=(-10, 0, 0),
				braco_D=(-62, -15, 0), antebraco_D=(-34, 0, 0),
				braco_E=(-62, 15, 0), antebraco_E=(-34, 0, 0),
				coxa_D=(-60, -21, 0), canela_D=(52, 0, 0), pe_D=pe(-60, 52),
				coxa_E=(-60, 21, 0), canela_E=(52, 0, 0), pe_E=pe(-60, 52))),
			# Sobe na sela.
			(5, pose(
				peito=(23, 0, 0), cabeca=(-14, 0, 0),
				braco_D=(-70, -14, 0), antebraco_D=(-26, 0, 0),
				braco_E=(-70, 14, 0), antebraco_E=(-26, 0, 0),
				coxa_D=(-74, -19, 0), canela_D=(76, 0, 0), pe_D=pe(-74, 76),
				coxa_E=(-74, 19, 0), canela_E=(76, 0, 0), pe_E=pe(-74, 76))),
			(9, pose(
				peito=(14, 0, 0), cabeca=(-9, 0, 0),
				braco_D=(-58, -16, 0), antebraco_D=(-38, 0, 0),
				braco_E=(-58, 16, 0), antebraco_E=(-38, 0, 0),
				coxa_D=(-56, -22, 0), canela_D=(46, 0, 0), pe_D=pe(-56, 46),
				coxa_E=(-56, 22, 0), canela_E=(46, 0, 0), pe_E=pe(-56, 46))),
			(14, pose(
				peito=(22, 0, 0), cabeca=(-13, 0, 0),
				braco_D=(-69, -14, 0), antebraco_D=(-27, 0, 0),
				braco_E=(-69, 14, 0), antebraco_E=(-27, 0, 0),
				coxa_D=(-73, -19, 0), canela_D=(74, 0, 0), pe_D=pe(-73, 74),
				coxa_E=(-73, 19, 0), canela_E=(74, 0, 0), pe_E=pe(-73, 74))),
			(18, pose(
				peito=(16, 0, 0), cabeca=(-10, 0, 0),
				braco_D=(-62, -15, 0), antebraco_D=(-34, 0, 0),
				braco_E=(-62, 15, 0), antebraco_E=(-34, 0, 0),
				coxa_D=(-60, -21, 0), canela_D=(52, 0, 0), pe_D=pe(-60, 52),
				coxa_E=(-60, 21, 0), canela_E=(52, 0, 0), pe_E=pe(-60, 52))),
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
