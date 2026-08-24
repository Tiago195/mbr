# -*- coding: utf-8 -*-
"""O boneco de teste: UMA pele contínua, gerada a partir das medidas.

Rodar:
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" ^
        --background --python tools/arte/gerar_boneco.py

## Por que este arquivo existe, e por que ele não conserta o anterior

O gerador anterior montava **um sólido fechado por osso** — dezessete caixas e
prismas independentes, cada um grudado num osso. Medido em repouso, oito pares
de peças se cruzavam sem serem vizinhas, e a mão ficava enterrada dentro da
coxa. Palavras do usuário ao ver na tela: *"várias peças dele entra uma dentro
da outra, até com ele parado"*.

Aquilo não era defeito de implementação. Partes rígidas são uma técnica real —
Minecraft, Roblox, os jogos de LEGO —, mas ela exige proporções escolhidas PARA
ela, com as peças passando por fora umas das outras. As nossas proporções vêm
de `docs/11-direcao-de-arte.md`, medidas em 27 campeões do original, que são
malhas contínuas: ombro estreito e coxa grossa pressupõem carne que se funde no
ombro e no quadril. Rebatidas em blocos, essas mesmas medidas obrigam a colisão.

E `docs/01-visao-e-escopo.md` declara o alvo: **visual chibi cartunizado**.
Chibi é pele contínua. Bloco rígido é outra estética.

Por isso este arquivo começa do zero em vez de remendar o outro: a diferença
não é de forma das peças, é de **não haver peças**.

## Como uma pele contínua é gerada por script

Pelo **Skin Modifier**. A entrada é um esqueleto de ARESTAS — vértices ligados
por linhas, seguindo os ossos —, e cada vértice carrega um RAIO. O modificador
costura uma superfície fechada em volta disso, e as junções entre membro e
tronco saem contínuas porque os dois compartilham o vértice do ombro.

Depois vem `Subdivision`, que arredonda. Nenhuma das duas etapas é uma escolha
estética minha: são as duas ferramentas que o Blender tem para exatamente este
trabalho, e a contagem de polígonos é controlada pelo nível da subdivisão.

## O que ele NÃO faz

Não gera animação. As animações entram uma a uma, depois, e só as que têm
consumidor no jogo — a regra do usuário em 24/08/2026: nada de ataque, nada de
pulo, e nada que ficaria órfão hoje, como cortar árvore e minerar.
"""

from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Euler, Vector

# O conferidor vive ao lado, e o Blender nao poe o diretorio do script no
# caminho de importacao.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import conferir_boneco

# --------------------------------------------------------------------------
# As medidas. Todas de `docs/11-direcao-de-arte.md`, medidas em 27 campeões.
# --------------------------------------------------------------------------

ALTURA = 1.75

## Altura de cada junta, como fração da altura total.
PROPORCAO = {
	"tornozelo": 0.093,
	"joelho": 0.283,
	"quadril": 0.485,
	"peito": 0.656,
	"pescoco": 0.763,
	"ombro": 0.725,
	"vao_dos_ombros": 0.175,
	"vao_dos_quadris": 0.129,
	"vao_das_maos": 0.629,
	"envergadura": 0.895,
}

## Espessura sobre COMPRIMENTO do osso, por região: `(mediana, mínimo, máximo)`.
##
## Medida em `m_BonesAABB` dos 27 campeões: a caixa dos vértices que cada osso
## influencia. É razão e não valor absoluto porque o skinning suave faz a caixa
## de um osso invadir a do vizinho — por ali a coxa dava 0,266 da altura, o que
## poria duas coxas em 0,53 num quadril de 0,33, geometricamente impossível.
##
## **A mediana e a faixa moram no mesmo lugar de propósito.** Elas já estiveram
## em dois dicionários, e dois lugares para a mesma medida é um deles ficar para
## trás — é a regra que o `CLAUDE.md` repete e que este projeto já pagou.
##
## `cabeca`, `peito` e `quadril` estão aqui porque foram medidas e porque a
## conferência do artefato as usa; o gerador NÃO deriva raio delas. A cabeça
## converge pela largura, e o tronco sai do vão dos ombros e do dos quadris —
## ver `_esqueleto_de_arestas`.
FAIXA_DA_ESBELTEZ = {
	"cabeca": (0.778, 0.508, 0.988),
	"peito": (0.779, 0.474, 0.985),
	"quadril": (0.676, 0.482, 0.812),
	"braco": (0.758, 0.544, 0.941),
	"antebraco": (0.716, 0.413, 0.942),
	"mao": (0.752, 0.525, 0.951),
	"coxa": (0.575, 0.435, 0.936),
	"canela": (0.494, 0.349, 0.857),
	"pe": (0.672, 0.532, 0.823),
}

## A mediana de cada região, derivada da faixa. Um lugar só.
ESBELTEZ = {nome: faixa[0] for nome, faixa in FAIXA_DA_ESBELTEZ.items()}


Y_TORNOZELO = PROPORCAO["tornozelo"] * ALTURA
Y_JOELHO = PROPORCAO["joelho"] * ALTURA
Y_QUADRIL = PROPORCAO["quadril"] * ALTURA
Y_PEITO = PROPORCAO["peito"] * ALTURA
Y_PESCOCO = PROPORCAO["pescoco"] * ALTURA
Y_OMBRO = PROPORCAO["ombro"] * ALTURA
Y_TOPO = ALTURA

X_OMBRO = PROPORCAO["vao_dos_ombros"] * ALTURA * 0.5
X_QUADRIL = PROPORCAO["vao_dos_quadris"] * ALTURA * 0.5

## Do ombro ao PULSO sai do vão das mãos; do pulso à ponta, da envergadura.
## São dois ossos e uma mão, e não um braço comprido — publicar só a
## envergadura já deixou um boneco acertar o número com antebraço esticado e
## nenhuma mão.
ATE_O_PULSO = (PROPORCAO["vao_das_maos"] - PROPORCAO["vao_dos_ombros"]) * ALTURA * 0.5
COMPRIMENTO_DA_MAO = (PROPORCAO["envergadura"] - PROPORCAO["vao_das_maos"]) * ALTURA * 0.5
## Onde o cotovelo cai ao longo do braço. **Não sai do original**: lá ombro,
## cotovelo e mão ficam na mesma altura na pose T, então a medição não separa os
## dois ossos. 0,47 é a proporção de um braço humano, e é um dos poucos números
## deste arquivo sem origem medida.
FRACAO_ATE_O_COTOVELO = 0.47

## O pé, como fração da altura. **Era 0,24 em metro absoluto**, o que fazia o
## sapato não acompanhar uma mudança de `ALTURA` — o único comprimento do corpo
## que não escalava com o resto. 0,137 × 1,75 dá os mesmos 0,24 de antes.
COMPRIMENTO_DO_PE = 0.137 * ALTURA

## Quanto o braço abre para fora do corpo, em graus.
##
## **Geométrico, não estético.** Com o braço caindo reto do ombro, a mão ocupa o
## mesmo espaço da coxa: ombro a 0,153 do eixo, coxa indo até 0,215, mão de
## 0,066 a 0,241. Para a mão passar por fora com o braço vertical, o centro dela
## teria que estar a 0,30 — o dobro do vão dos ombros, que é medido.
##
## Numa pele contínua o preço de errar isso é pior do que em peças soltas: em
## vez de a mão ATRAVESSAR a coxa, ela FUNDE com ela, e o boneco sai com o braço
## grudado na perna. Vinte graus é o mínimo que separa as duas.
## **Vinte era o mínimo, e ninguém tinha perguntado quanto o máximo comprava.**
##
## A constante nasceu como piso — "vinte graus é o mínimo que separa as duas" —
## e por três versões nada limitou o outro lado e nada mediu o ângulo. O revisor
## adversarial varreu, e a autointerseção da axila é quase inteiramente função
## dela:
##
##     abertura   repouso   pior quadro animado   largura
##       20°        78              79             0,823
##       24°        58              54             0,897
##       28°        10              13             0,970
##       32°         0              13             1,039
##
## As três tentativas registradas de fechar a axila — estreitar o peito, pôr
## clavícula, voxelizar — todas mexiam na COSTURA. Abrir o braço não estava
## entre elas, e resolve 87% do defeito sem tocar na malha.
##
## Por que 28 e não 32, que zera: 32° dá 1,039 de largura num corpo de 1,75, e
## a pose deixa de ser um A para virar quase um T. O original é medido em pose
## T, mas o que o jogador vê é o `parado`, que parte daqui. 28° troca os 78
## pares por 10 e mantém a silhueta de alguém em pé.
##
## **Os 13 que sobram em movimento não são da axila.** Medidos pelo revisor,
## 13 deles estão em z~0,5, do lado esquerdo: é a mão recuada entrando na
## nádega, e ela APARECE na tela — ao contrário dos da axila, que ficam dentro
## da malha. É defeito visual conhecido e não fechado; ver a lista do que
## exige olho humano no `CLAUDE.md`.
ABERTURA_DO_BRACO = 28.0


def _no_braco(lado: float, distancia: float) -> Vector:
	"""Um ponto da corrente do braço, a `distancia` do ombro ao longo dela."""
	seno = math.sin(math.radians(ABERTURA_DO_BRACO))
	cosseno = math.cos(math.radians(ABERTURA_DO_BRACO))
	return Vector((lado * (X_OMBRO + distancia * seno),
	               0.0, Y_OMBRO - distancia * cosseno))


def _raio(regiao: str, comprimento: float, fatores: dict = None) -> float:
	"""Metade da espessura da região — é isso que o Skin Modifier pede.

	`fatores` corrige o encolhimento da subdivisão, e vem de `convergir`. O raio
	do Skin Modifier é meia-largura da GAIOLA de controle, e Catmull-Clark puxa
	a superfície para dentro dela: sem correção o corpo sai sistematicamente
	magro — medido, a coxa 23% e o pé 28% abaixo do declarado.
	"""
	fator = (fatores or {}).get(regiao, 1.0)
	return ESBELTEZ[regiao] * comprimento * 0.5 * fator


# --------------------------------------------------------------------------
# O esqueleto de arestas, que é a entrada do Skin Modifier.
#
# `(nome, posicao, pai, raio)`. O pai é o nome de outro nó, ou None para a
# raiz. Cada par pai→filho vira uma ARESTA, e é em volta das arestas que a pele
# é costurada.
# --------------------------------------------------------------------------

COMPRIMENTO_DA_COXA = Y_QUADRIL - Y_JOELHO
COMPRIMENTO_DA_CANELA = Y_JOELHO - Y_TORNOZELO
COMPRIMENTO_DO_BRACO = ATE_O_PULSO * FRACAO_ATE_O_COTOVELO
COMPRIMENTO_DO_ANTEBRACO = ATE_O_PULSO - COMPRIMENTO_DO_BRACO
COMPRIMENTO_DA_CABECA = Y_TOPO - Y_PESCOCO

## A cabeça é uma bola de raio igual a meia altura dela — 0,237 da altura do
## corpo, medido em 27 campeões. É o achado nº 1 do §1 de `docs/11`: a cabeça
## do original é 23,7% da altura contra 17,7% de um humano, um terço maior.
RAIO_DA_CABECA = COMPRIMENTO_DA_CABECA * 0.5

## O pescoço, em fração do vão dos ombros. Fino o bastante para a cabeça ler
## como peça própria, grosso o bastante para não sumir na subdivisão.
RAIO_DO_PESCOCO = X_OMBRO * 0.34

## O peito, em fração do meio-vão dos ombros. Ver o comentário na montagem.
FRACAO_DO_PEITO = 0.72


## O punho estrangula e a mão infla, em fração do raio da mão. São o que
## transforma o braço de salsicha em braço com ponta.
ESTREITAMENTO_DO_PULSO = 0.45
ENGROSSAMENTO_DA_MAO = 1.35


def _esqueleto_de_arestas(ajuste_topo: float = 0.0,
                          ajuste_base: float = 0.0,
                          fator_da_cabeca: float = 1.0,
                          ajuste_do_braco: float = 0.0,
                          fatores: dict = None) -> list:
	"""Os nós da linha do corpo, com o raio de cada um.

	**O tronco não deriva da esbeltez, e a exclusão é medida.** Nós cortamos o
	tronco em dois trechos curtos; no original as caixas de influência de `Hips`
	e `Chest` cobrem o tronco inteiro, então dividir espessura por um
	comprimento que significa outra coisa mede a nossa segmentação e não a forma
	deles — por esse caminho o peito dava 1,78 vez a esbeltez do original.

	A largura do tronco sai de onde ela é medida de verdade: o vão dos ombros e
	o dos quadris.
	"""
	nos = []

	# O tronco, de baixo para cima. A raiz é o quadril.
	nos.append(("quadril", Vector((0.0, 0.0, Y_QUADRIL)), None, X_QUADRIL * 1.15))
	# **O peito é mais estreito que o vão dos ombros, e a diferença é medida.**
	#
	# Com 0,95 do vão, a superfície do peito chega a 0,145 do eixo e o ombro
	# nasce em 0,153: os dois quase se encostam, e o Skin Modifier fecha essa
	# junção rasa dobrando a superfície para dentro. Medido, a malha se
	# auto-intersectava 36 vezes EM REPOUSO, todas na axila, e os pesos
	# automáticos atribuíam o volume da dobra ao braço — que por isso saía com
	# esbeltez 1,140 contra um máximo medido de 0,941.
	#
	# Casca única não impede auto-interseção: uma superfície só pode atravessar
	# a si mesma, e foi o que aconteceu.
	nos.append(("peito", Vector((0.0, 0.0, Y_PEITO)), "quadril",
	            X_OMBRO * FRACAO_DO_PEITO))
	# **O pescoço é FINO de propósito.** Ele é o que separa a cabeça do tronco;
	# com o raio do peito, os dois viram uma massa só e o boneco fica encapuzado
	# — foi o que a primeira versão desta pele produziu.
	# **O nó do pescoço sobe para DENTRO da bola da cabeça, e some.**
	#
	# Deixado na base do pescoço, ele fica 14 cm abaixo do centro da cabeça, e o
	# Skin Modifier interpola o raio ao longo dessa distância: de 0,052 a 0,194
	# em 14 cm é um CONE. Medido em 27 anéis, o ponto mais largo saía 9,3 cm
	# acima do centro e a malha ficava 37% mais estreita que uma esfera na base
	# — na tela, uma lâmpada. Pôr uma segunda bola em cima arredondou o topo e
	# não desfez o cone, porque o cone estava embaixo.
	#
	# Com o nó dentro da esfera, a transição acontece dentro da massa da cabeça
	# e não aparece. O personagem fica sem pescoço visível, que é o que chibi é:
	# `docs/01` pede *"chibi cartunizado"*, e cabeça grande apoiada direto no
	# ombro é a forma canônica dele.
	nos.append(("pescoco", Vector((0.0, 0.0, Y_PESCOCO)), "peito",
	            RAIO_DO_PESCOCO))
	# **A cabeça fica no CENTRO dela, não no topo do corpo.** O Skin Modifier
	# costura uma bola de `raio` em volta do nó, então um nó em `Y_TOPO` põe
	# metade da cabeça acima da altura declarada. Centrada, o topo da bola cai
	# exatamente em 1,75.
	#
	# E o raio sai da ALTURA da cabeça, não da esbeltez. Os dois números medem
	# coisas diferentes: a esbeltez responde "quão grosso é o osso", e aqui a
	# cabeça não é um osso — é a massa que carrega a leitura de longe. O §1 de
	# `docs/11` mede `altura_da_cabeca / altura = 0,237`, e é o primeiro dos
	# três achados que fazem o olhar do original: *a cabeça é grande*.
	# **A cabeça são DOIS nós, e o motivo foi medido.** Com um nó só ela é a
	# ponta da corrente, e o Skin Modifier fecha a ponta com uma tampa: o
	# resultado é um funil — cone subindo do pescoço e domo achatado em cima.
	# Medido em 27 anéis, o ponto mais largo ficava 9,3 cm ACIMA do centro, e a
	# malha era 37% mais estreita que uma esfera em z=1,43 e 39% mais larga em
	# z=1,74. Na tela lê como lâmpada.
	#
	# Dois nós do mesmo raio fazem uma cápsula, que é redonda nos dois extremos.
	# A conferência antiga não podia pegar isso: ela comparava a largura MÁXIMA
	# com o alvo, e dois extremos não distinguem uma bola de um cone.
	# **A BASE da cabeça é ancorada e só o TOPO se move.**
	#
	# Enquanto `ajuste_topo` transladava a cabeça inteira, cada volta da
	# convergência reabria o vão entre o pescoço e a bola, e o Skin Modifier
	# interpolava o raio ao longo dele: um cone de 9 cm. Medido por anel, o
	# ponto mais largo ficava a 72–84% da altura da cabeça — lâmpada, não bola.
	#
	# Com a base presa logo acima do pescoço, o vão não pode crescer: a
	# transição do fino para o grosso acontece sempre nos mesmos 6 cm, e o
	# ajuste de altura vira alongamento do topo, que é onde ele não estraga a
	# leitura.
	raio_da_cabeca = RAIO_DA_CABECA * fator_da_cabeca
	base_da_cabeca = Y_PESCOCO + COMPRIMENTO_DA_CABECA * 0.14
	nos.append(("cabeca", Vector((0.0, 0.0, base_da_cabeca)), "pescoco",
	            raio_da_cabeca))
	nos.append(("cabeca_topo",
	            Vector((0.0, 0.0, Y_TOPO - raio_da_cabeca * 0.5 + ajuste_topo)),
	            "cabeca", raio_da_cabeca))

	for lado, sufixo in ((1.0, "D"), (-1.0, "E")):
		# O braço nasce no PEITO, e isto já esteve errado: preso ao pescoço, o
		# ombro subia até a altura da cabeça e a bola da cabeça fundia com os
		# dois braços — na tela saía um corpo encapuzado, sem cabeça.
		#
		# O ombro fica em 0,725 da altura e o pescoço em 0,763; são 6,6 cm de
		# diferença, e numa pele contínua 6,6 cm é a diferença entre "cabeça
		# apoiada no pescoço" e "cabeça derretida no ombro".
		nos.append(("ombro_%s" % sufixo, _no_braco(lado, 0.0), "peito",
		            _raio("braco", COMPRIMENTO_DO_BRACO, fatores)))
		nos.append(("cotovelo_%s" % sufixo, _no_braco(lado, COMPRIMENTO_DO_BRACO),
		            "ombro_%s" % sufixo,
		            _raio("antebraco", COMPRIMENTO_DO_ANTEBRACO, fatores)))
		# **Punho FINO e mão GORDA.** Medido, a versão anterior era uma
		# salsicha de raio constante 0,069 com um inchaço de 12% na ponta: sem
		# cotovelo, sem pulso e sem mão. O achado nº 3 do §1 de `docs/11` é
		# *"mão grande dá ao gesto uma ponta que o olho segue de longe"*, e sem
		# o estreitamento do punho não há ponta nenhuma para seguir.
		nos.append(("pulso_%s" % sufixo, _no_braco(lado, ATE_O_PULSO),
		            "cotovelo_%s" % sufixo,
		            _raio("mao", COMPRIMENTO_DA_MAO, fatores) * ESTREITAMENTO_DO_PULSO))
		nos.append(("mao_%s" % sufixo,
		            _no_braco(lado, ATE_O_PULSO
		                      + COMPRIMENTO_DA_MAO * 0.55 + ajuste_do_braco),
		            "pulso_%s" % sufixo,
		            _raio("mao", COMPRIMENTO_DA_MAO, fatores) * ENGROSSAMENTO_DA_MAO))

		# A perna, do quadril para baixo.
		nos.append(("virilha_%s" % sufixo,
		            Vector((lado * X_QUADRIL, 0.0, Y_QUADRIL)), "quadril",
		            _raio("coxa", COMPRIMENTO_DA_COXA, fatores)))
		nos.append(("joelho_%s" % sufixo,
		            Vector((lado * X_QUADRIL, 0.0, Y_JOELHO)), "virilha_%s" % sufixo,
		            _raio("canela", COMPRIMENTO_DA_CANELA, fatores)))
		nos.append(("tornozelo_%s" % sufixo,
		            Vector((lado * X_QUADRIL, 0.0, Y_TORNOZELO)),
		            "joelho_%s" % sufixo, _raio("canela", COMPRIMENTO_DA_CANELA, fatores) * 0.8))
		# O pé aponta para -Y, que é a frente no Blender.
		nos.append(("pe_%s" % sufixo,
		            Vector((lado * X_QUADRIL, -COMPRIMENTO_DO_PE,
		                    Y_TORNOZELO * 0.7 + ajuste_base)),
		            "tornozelo_%s" % sufixo, _raio("pe", COMPRIMENTO_DO_PE, fatores)))

	return nos


## Níveis de subdivisão. Dois já lê como curva na câmera isométrica, que está a
## metros de distância; mais que isso é vértice gasto num boneco de teste.
SUBDIVISOES = 2


def limpar_cena() -> None:
	# **Volta para o modo Objeto antes de qualquer coisa.**
	#
	# Uma execução que aborte dentro de `criar_animacao` deixa o Blender em modo
	# Pose, e aí `select_all` falha com "context is incorrect" — o gerador
	# passaria a depender do estado em que a sessão anterior o deixou. Um script
	# que só roda quando a cena está limpa não é um script, é um ritual.
	if bpy.context.mode != "OBJECT":
		bpy.ops.object.mode_set(mode="OBJECT")
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete(use_global=False)
	for bloco in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions,
	              bpy.data.materials):
		for item in list(bloco):
			bloco.remove(item)


def criar_pele(ajuste_topo: float = 0.0, ajuste_base: float = 0.0,
               fator_da_cabeca: float = 1.0, ajuste_do_braco: float = 0.0,
               fatores: dict = None) -> bpy.types.Object:
	"""A pele contínua, a partir do esqueleto de arestas.

	`ajuste_topo` sobe o nó da cabeça e `ajuste_base` desce o do pé. São a
	compensação do encolhimento da subdivisão, e quem os calcula é `convergir`.
	"""
	nos = _esqueleto_de_arestas(ajuste_topo, ajuste_base, fator_da_cabeca,
	                            ajuste_do_braco, fatores)
	indice_de = {nome: i for i, (nome, _p, _pai, _r) in enumerate(nos)}
	vertices = [posicao for _n, posicao, _pai, _r in nos]
	arestas = [(indice_de[pai], i)
	           for i, (_n, _p, pai, _r) in enumerate(nos) if pai is not None]

	malha = bpy.data.meshes.new("Pele")
	malha.from_pydata([tuple(v) for v in vertices], arestas, [])
	malha.update()
	corpo = bpy.data.objects.new("Corpo", malha)
	bpy.context.collection.objects.link(corpo)
	bpy.context.view_layer.objects.active = corpo
	corpo.select_set(True)

	pele = corpo.modifiers.new(name="pele", type="SKIN")
	# Sem isto o modificador arredonda as pontas e o pé vira uma bola.
	pele.use_smooth_shade = True

	# O raio por vértice. `skin_vertices` só existe depois que o modificador
	# entra, e é uma camada da MALHA, não do modificador.
	camada = corpo.data.skin_vertices[0].data
	for i, (_n, _p, _pai, raio) in enumerate(nos):
		camada[i].radius = (raio, raio)
	# A raiz da pele tem que ser declarada, senão o modificador escolhe uma
	# sozinho e a topologia sai imprevisível.
	camada[indice_de["quadril"]].use_root = True

	suave = corpo.modifiers.new(name="suave", type="SUBSURF")
	suave.levels = SUBDIVISOES
	suave.render_levels = SUBDIVISOES
	return corpo


## O lado do voxel, em metros, e quanto da malha sobra depois de reduzir.
##
## **A voxelização é o que torna a auto-interseção impossível**, e não uma
## escolha de acabamento. O Skin Modifier costura um casco em cada junção, e
## quando dois ramos saem perto um do outro com raios diferentes os cascos se
## atravessam: medido, a casca cruzava a si mesma em 78 pares na axila, em
## repouso — o mesmo defeito que motivou a reescrita, agora numa superfície só.
##
## Tentei fechar a junção estreitando o peito (0,95 → 0,72 do meio-vão) e
## acrescentando uma clavícula. O primeiro foi de 36 para 40 pares; o segundo
## para 85, e mudou o defeito de lugar. Junção rasa não se conserta ajustando
## quem entra nela.
##
## Uma superfície reconstruída a partir de voxels **não pode** se atravessar: o
## algoritmo caminha a fronteira de um volume, e volume não tem dois lados no
## mesmo lugar. Ela também arredonda as junções, que é o que chibi pede.
##
## O lado do voxel é o que decide a contagem de polígonos; a redução traz de
## volta para a ordem de um boneco de teste.
## **Desligada, e a decisão foi tomada olhando as duas.**
##
## Voxelizar fecha a auto-interseção por construção — uma superfície
## reconstruída da fronteira de um volume não pode se atravessar. Mas ela
## devolve triângulos uniformes, sem relação com a estrutura do corpo, e a
## pintura, que decide face a face, sai rasgada: gerado dos dois jeitos e
## comparado na tela, a viseira vira máscara esfarrapada e a borda do tronco
## fica picotada.
##
## **A auto-interseção fica DENTRO da malha e ninguém a vê; a pintura rasgada
## está na cara do boneco.** Trocar defeito invisível por defeito visível não é
## progresso. Ela continua medida e com teto — ver `TETO_DE_AUTOINTERSECAO` em
## `conferir_boneco.py` —, então não pode crescer calada.
VOXELIZAR = False
LADO_DO_VOXEL = 0.022
SOBRA_DA_REDUCAO = 0.35


def aplicar(corpo: bpy.types.Object) -> tuple:
	"""Aplica pele, subdivisão, voxelização e redução.

	Devolve `(base, topo)` do que saiu.
	"""
	bpy.context.view_layer.objects.active = corpo
	for modificador in list(corpo.modifiers):
		bpy.ops.object.modifier_apply(modifier=modificador.name)

	if not VOXELIZAR:
		alturas = [v.co.z for v in corpo.data.vertices]
		return min(alturas), max(alturas)

	voxel = corpo.modifiers.new(name="voxel", type="REMESH")
	voxel.mode = "VOXEL"
	voxel.voxel_size = LADO_DO_VOXEL
	# Sem suavização o resultado sai escadinha de cubo, que é justamente o
	# visual de que estamos fugindo.
	voxel.use_smooth_shade = True
	bpy.ops.object.modifier_apply(modifier=voxel.name)

	reduzir = corpo.modifiers.new(name="reduzir", type="DECIMATE")
	reduzir.ratio = SOBRA_DA_REDUCAO
	bpy.ops.object.modifier_apply(modifier=reduzir.name)
	alturas = [v.co.z for v in corpo.data.vertices]
	return min(alturas), max(alturas)


## Quantas vezes tentar acertar, e com que folga parar.
TENTATIVAS = 240
FOLGA_DA_ALTURA = 0.002

## Quanto de cada correção é aplicado por volta. Ver `convergir`.
AMORTECIMENTO = 0.5

## A espessura corrige mais forte, e o motivo é acoplamento.
##
## O raio no MEIO de um osso é puxado pelos raios dos dois nós das pontas, e
## cada ponta pertence a outra região: o meio do braço depende do nó do ombro e
## do nó do cotovelo. Com meio passo, o erro caía 1,2% por volta e o teto
## chegava antes do alvo — medido, 0,18 virava 0,068 em quarenta voltas e
## continuava caindo.
##
## **E 0,9 DIVERGE.** Medido: com nove décimos de correção por volta o laço
## caminhou até a volta 97 e explodiu — topo 3,19 m, base -2,46. A guarda de
## divergência pegou, que é para isso que ela existe.
##
## Meio passo é estável e monotônico; o preço é volta, e volta é barata: cada
## uma custa dois décimos de segundo. O teto é generoso de propósito.
AMORTECIMENTO_DA_ESPESSURA = 0.5
FOLGA_DA_CABECA = 0.006

## Onde a cabeça começa, para medi-la. É o pescoço, e não um número escolhido:
## tudo acima da base do pescoço é cabeça, que é a definição que o §1 de
## `docs/11` usa — e a definição importa mais que o número, porque medindo do
## crânio a mesma população dá 4,93 cabeças de altura em vez de 4,22.
BASE_DA_CABECA = Y_PESCOCO

## A largura que a cabeça tem que ter.
##
## A altura dela é medida — 0,237 da altura do corpo. A razão entre altura e
## largura também: 1,065 nas 28 cabeças do original, que é quase uma bola. Daí
## a largura sai por divisão, e não por escolha.
LARGURA_DA_CABECA = (Y_TOPO - Y_PESCOCO) / 1.065

## Do ombro à ponta do braço. Sai da envergadura menos o vão dos ombros, por
## dois — o mesmo caminho que `docs/11` usa, e o mesmo que o conferidor mede.
ALCANCE_DO_BRACO = (PROPORCAO["envergadura"]
                    - PROPORCAO["vao_dos_ombros"]) * ALTURA * 0.5
FOLGA_DO_BRACO = 0.004


def convergir() -> tuple:
	"""Gera o corpo até ele medir 1,75 m com o pé no chão.

	**Esta função existe no lugar de uma normalização por escala, e a diferença
	é a lição da iteração anterior.**

	A subdivisão de Catmull-Clark não move os nós do esqueleto de arestas: ela
	puxa a SUPERFÍCIE para dentro, em direção à malha de controle. Ou seja, o
	quadril, o joelho e o ombro continuam exatamente onde a direção de arte os
	declara; o que encolhe são as pontas — o alto da cabeça e a sola do pé.

	Esticar o corpo inteiro para recuperar a altura, que foi a primeira
	tentativa, conserta o número e ESTRAGA a anatomia: tudo que estava na
	posição declarada sai dela. O sintoma foi o esqueleto ficando 27 cm mais
	alto que a pele, e a deformação do braço destruída.

	Aqui só as pontas se movem, e elas se movem por medição: gera, mede o que
	faltou, corrige, repete. O número de voltas é impresso a cada execução — e
	não afirmado aqui, porque ele muda a cada alvo novo que entra no laço —, e há teto
	para não girar para sempre se a geometria mudar de comportamento.
	"""
	ajuste_topo = 0.0
	ajuste_base = 0.0
	fator_da_cabeca = 1.0
	ajuste_do_braco = 0.0
	fatores = {}
	anteriores = []
	for volta in range(TENTATIVAS):
		limpar_cena()
		corpo = criar_pele(ajuste_topo, ajuste_base, fator_da_cabeca,
		                   ajuste_do_braco, fatores)
		bpy.context.view_layer.update()
		base, topo = aplicar(corpo)
		limpar_soltos(corpo)
		cabeca = _largura_da_cabeca(corpo)
		braco = _alcance_do_braco(corpo)
		# Veste para medir: a espessura é medida pelos pesos, e peso só existe
		# depois da pele estar presa ao esqueleto.
		esqueleto = criar_esqueleto(corpo, ajuste_base, ajuste_do_braco)
		vestir(corpo, esqueleto)
		entregue = _esbeltez_entregue(corpo, _ossos(ajuste_base, ajuste_do_braco))
		gorda = max((_fora_da_faixa(r, entregue[r]) for r in entregue),
		            default=1.0)
		if (abs(topo - ALTURA) <= FOLGA_DA_ALTURA
				and abs(base) <= FOLGA_DA_ALTURA
				and abs(cabeca - LARGURA_DA_CABECA) <= FOLGA_DA_CABECA
				and abs(braco - ALCANCE_DO_BRACO) <= FOLGA_DO_BRACO
				and gorda <= 0.0):
			print("[boneco] convergiu em %d volta(s): topo %.4f  base %.4f  "
			      "cabeca %.3f (alvo %.3f)  braco %.3f (alvo %.3f)"
			      % (volta + 1, topo, base, cabeca, LARGURA_DA_CABECA,
			         braco, ALCANCE_DO_BRACO))
			for regiao in sorted(entregue):
				faixa = FAIXA_DA_ESBELTEZ[regiao]
				print("[boneco]   esbeltez %-10s %.3f  (faixa %.3f a %.3f)"
				      % (regiao, entregue[regiao], faixa[1], faixa[2]))
			return corpo, esqueleto, ajuste_base, ajuste_do_braco, fatores
		# **Todas as correções são AMORTECIDAS, e isso não é zelo.**
		#
		# As quatro se puxam: engordar a cabeça também a levanta, e empurrar a
		# mão para fora move a ponta mais do que o empurrão, porque a bola da
		# mão se estende além do nó. Com correção cheia nas quatro ao mesmo
		# tempo o laço DIVERGE — medido, em doze voltas o topo foi de 1,75 para
		# 144,6 e a base para -142,4. Não oscilou: explodiu.
		#
		# Meio passo por volta troca velocidade por estabilidade, e velocidade
		# aqui não vale nada: são cinco a oito voltas de dez segundos.
		print("[boneco]   volta %2d: topo %8.4f  base %8.4f  cabeca %7.4f  "
		      "braco %7.4f  esbeltez erra %.4f em %s"
		      % (volta + 1, topo, base, cabeca, braco, gorda,
		         max(entregue, key=lambda r: _fora_da_faixa(r, entregue[r]))
		         if entregue else "?"))
		# **Divergir é falha imediata, e não quarenta voltas de lixo.** Um laço
		# que se afasta do alvo não vai voltar sozinho, e as quarenta linhas de
		# número crescendo escondem a volta em que ele virou.
		# **Medida imóvel enquanto o ajuste se move é defeito, não paciência.**
		# Se o braço não reage a três correções seguidas, quem está sendo medido
		# não é o braço; continuar até o teto só produz quarenta linhas iguais.
		anteriores.append(braco)
		# **Parado LONGE do alvo é defeito; parado EM CIMA dele é sucesso.**
		# A primeira versão desta guarda não distinguia os dois e abortava a
		# geração no momento em que o braço acertava 0,6300 e ficava lá — que é
		# exatamente o que se quer que aconteça.
		longe = abs(braco - ALCANCE_DO_BRACO) > FOLGA_DO_BRACO
		if (longe and len(anteriores) > 3
				and len(set("%.5f" % v for v in anteriores[-4:])) == 1):
			raise RuntimeError(
				"o alcance do braco ficou parado em %.4f, longe do alvo %.4f, "
				"por 4 voltas enquanto o ajuste mudava — a medida esta lendo "
				"outra parte do corpo" % (braco, ALCANCE_DO_BRACO)
			)
		if topo > ALTURA * 2.0 or base < -ALTURA or braco > ALTURA:
			raise RuntimeError(
				"a convergencia DIVERGIU na volta %d — topo %.3f, base %.3f, "
				"braco %.3f. Alguma medicao esta lendo a parte errada do corpo."
				% (volta + 1, topo, base, braco)
			)
		ajuste_topo += AMORTECIMENTO * (ALTURA - topo)
		ajuste_base += AMORTECIMENTO * (0.0 - base)
		# A envergadura também encolhe, e só em Z era metade da conta: a versão
		# anterior compensava topo e base e nunca a ponta do braço. Medida, a
		# envergadura saía 0,807 da altura contra um PISO de 0,808 nos 27
		# campeões — fora da faixa inteira do elenco.
		if braco <= 0.001:
			raise RuntimeError(
				"nao achei o braco para medir o alcance — a malha nao tem "
				"vertice alem do ombro, e somar a correcao cega faria o laco "
				"fugir em vez de fechar"
			)
		ajuste_do_braco += AMORTECIMENTO * (ALCANCE_DO_BRACO - braco)
		if cabeca > 0.001:
			fator_da_cabeca *= 1.0 + AMORTECIMENTO * (
				LARGURA_DA_CABECA / cabeca - 1.0)
		for regiao, valor in entregue.items():
			# Corrige só quem está FORA, e em direção à borda mais próxima.
			# Empurrar quem já está dentro em direção à mediana é o que fazia
			# uma região sair para a outra entrar.
			if valor <= 0.001 or _fora_da_faixa(regiao, valor) <= 0.0:
				continue
			# **Mira na MEDIANA, e não na borda mais próxima.**
			#
			# Corrigindo em direção à borda, o laço para no instante em que
			# cruza: medido, o pé parava em 0,532005 contra um piso de 0,532 —
			# margem de cinco milionésimos — e o braço encostava no teto. A
			# linha impressa parecia uma medida que concorda com a direção de
			# arte, e era a condição de parada impressa de volta.
			#
			# Mirando no meio, ele entra na faixa com folga dos dois lados, e
			# qualquer mudança em subdivisão, altura ou voxel não o joga para
			# fora de novo.
			mediana, _minimo, _maximo = FAIXA_DA_ESBELTEZ[regiao]
			alvo = mediana
			fatores[regiao] = fatores.get(regiao, 1.0) * (
				1.0 + AMORTECIMENTO_DA_ESPESSURA * (alvo / valor - 1.0))
	raise RuntimeError(
		"o corpo nao convergiu em %d voltas — topo %.4f, base %.4f, cabeca "
		"%.4f, braco %.4f" % (TENTATIVAS, topo, base, cabeca, braco)
	)


def _alcance_do_braco(corpo: bpy.types.Object) -> float:
	"""Do ombro à ponta do braço, MEDIDO AO LONGO DO EIXO DELE.

	**Filtro por caixa não serve, e as duas tentativas anteriores provaram
	isso.** Cortar por `x > X_OMBRO` põe a cabeça na conta, porque a cabeça
	deste boneco é mais larga que o vão dos ombros — 0,386 contra 0,306, que é
	o achado nº 1 do §1 de `docs/11` funcionando. Acrescentar `z < Y_OMBRO` põe
	a PERNA na conta: o pé fica a 1,2 m do ombro e passa nos dois cortes.
	Medido, a função devolvia 1,2035 onde o alvo é 0,63, e o laço empurrava a
	mão para dentro do corpo, voltas 5 a 40, até o topo chegar a 114 mil metros.

	O braço é um cilindro em volta de um eixo conhecido. Projetar no eixo e
	descartar o que está longe dele exclui perna, tronco e cabeça por
	construção, em vez de por uma lista de exceções que a próxima mudança de
	forma invalida.
	"""
	ombro = _no_braco(1.0, 0.0)
	eixo = (_no_braco(1.0, 1.0) - ombro).normalized()
	alcance = 0.0
	for vertice in corpo.data.vertices:
		relativo = vertice.co - ombro
		ao_longo = relativo.dot(eixo)
		if ao_longo <= 0.0:
			continue
		if (relativo - eixo * ao_longo).length > RAIO_DO_TUBO_DO_BRACO:
			continue
		alcance = max(alcance, ao_longo)
	return alcance


## Até que distância do eixo do braço um vértice ainda conta como braço.
##
## **Medido, e a margem é estreita — está declarado aqui porque é.** A mão é a
## peça mais grossa da corrente e chega a 0,118 do eixo. A coxa, que é o
## vizinho mais próximo, passa a 0,172. São 5,4 cm de separação entre os dois
## grupos, e o corte fica no meio.
##
## Com 0,20 a coxa entrava: a medida do braço travava em 0,6598 e não se mexia
## em quarenta voltas, porque o máximo vinha da perna e não da mão. Número
## imóvel enquanto o ajuste muda é a assinatura de uma medida que está lendo a
## parte errada do corpo — e é isso que a guarda `anteriores`, dentro de
## `convergir`, passou a acusar.
RAIO_DO_TUBO_DO_BRACO = 0.145


def limpar_soltos(corpo: bpy.types.Object) -> int:
	"""Apaga vértices sem aresta e sem face, e diz quantos eram.

	O Skin Modifier deixa restos degenerados exatamente nas junções — medidos,
	cinco: três no pescoço e dois nos ombros, nas coordenadas dos raios daquelas
	junções. Eles não aparecem na tela, recebem peso do `bone heat` e iriam para
	o `.glb`. Vértice solto num arquivo de personagem é lixo que atravessa o
	pipeline inteiro sem ninguém ver.
	"""
	usados = set()
	for aresta in corpo.data.edges:
		usados.update(aresta.vertices)
	for face in corpo.data.polygons:
		usados.update(face.vertices)
	soltos = [v.index for v in corpo.data.vertices if v.index not in usados]
	if not soltos:
		return 0
	import bmesh
	malha = bmesh.new()
	malha.from_mesh(corpo.data)
	malha.verts.ensure_lookup_table()
	bmesh.ops.delete(malha, geom=[malha.verts[i] for i in soltos], context="VERTS")
	malha.to_mesh(corpo.data)
	malha.free()
	corpo.data.update()
	return len(soltos)


## As regiões cuja espessura entregue é medida e corrigida.
##
## Tronco e cabeça ficam de fora: o tronco porque a nossa segmentação não é
## comparável à do original (ver `_esqueleto_de_arestas`), e a cabeça porque ela
## já converge pela largura.
OSSO_DA_REGIAO = {
	"braco": "braco_D", "antebraco": "antebraco_D", "mao": "mao_D",
	"coxa": "coxa_D", "canela": "canela_D", "pe": "pe_D",
}
## O alvo da espessura é a FAIXA, e não a mediana — ver `FAIXA_DA_ESBELTEZ`.
##
## Perseguir a mediana não fecha: o raio no meio de um osso é puxado pelos nós
## das duas pontas, que pertencem a outras regiões, e o sistema satura. Medido,
## o erro do braço estacionou em 0,148 e não se moveu em duzentas voltas — mais
## correção só o fez divergir.
##
## E era o alvo errado desde o começo. Os 27 campeões variam muito: o antebraço
## vai de 0,413 a 0,942, mais do que o dobro. Exigir que o nosso corpo acerte a
## mediana de uma população tão espalhada é exigir precisão que a própria
## referência não tem. É o mesmo critério que `docs/11` usa para proporção, onde
## a tolerância é derivada da faixa.


def _fora_da_faixa(regiao: str, valor: float) -> float:
	"""Quanto o valor passou da borda da faixa. Zero quando está dentro."""
	_mediana, minimo, maximo = FAIXA_DA_ESBELTEZ[regiao]
	if valor < minimo:
		return minimo - valor
	if valor > maximo:
		return valor - maximo
	return 0.0
## Até quantos raios declarados um vértice ainda conta como daquela peça. Dois
## engloba a peça inteira com folga e exclui o vizinho — a outra coxa, por
## exemplo, passa a 1,4 raio do eixo desta.
## Quantos vértices uma região precisa ter para a medida dela valer. Medida
## decidida por punhado de pontos mede o acaso: com a janela anterior, a "mão"
## chegou a ser decidida por UM vértice.
AMOSTRA_MINIMA = 12


def _esbeltez_entregue(corpo: bpy.types.Object, ossos: list) -> dict:
	"""A espessura que a malha REALMENTE tem, por região, sobre o comprimento.

	**Mede pelos PESOS da pele, que é o mesmo termo de `conferir_boneco.py`.**

	Antes ela usava um substituto geométrico — o osso mais próximo em raios
	dele — porque os pesos só existem depois de vestir. O preço foi medido: o
	gerador publicava braço 0,828 e o conferidor, lendo `WEIGHTS_0` do arquivo,
	1,291. Dois números para a mesma grandeza, e ninguém comparando; o gerador
	convergia contra um alvo que o conferidor não reconhecia.

	A diferença não era ruído: o peso automático atribui a massa do ombro ao
	BRAÇO, e o substituto geométrico a atribuía ao peito. Quem decide é a pele,
	porque é ela que a engine vai deformar.

	Por isso o laço veste o corpo a cada volta. Custa alguns segundos no total,
	e compra que gerador e conferidor não possam discordar.
	"""
	por_nome = {nome: (cabeca, cauda) for nome, cabeca, cauda, _p in ossos}
	grupos = {g.index: g.name for g in corpo.vertex_groups}
	meus = {}
	for vertice in corpo.data.vertices:
		melhor, peso = None, 0.0
		for atribuicao in vertice.groups:
			if atribuicao.weight > peso:
				peso, melhor = atribuicao.weight, grupos.get(atribuicao.group)
		if melhor is not None:
			meus.setdefault(melhor, []).append(vertice.co)

	saida = {}
	for regiao, osso in OSSO_DA_REGIAO.items():
		if osso not in por_nome:
			continue
		cabeca, cauda = por_nome[osso]
		eixo = cauda - cabeca
		comprimento = eixo.length
		if comprimento <= 0.0:
			continue
		direcao = eixo / comprimento
		distancias = []
		for ponto in meus.get(osso, []):
			relativo = ponto - cabeca
			ao_longo = relativo.dot(direcao) / comprimento
			if not 0.3 <= ao_longo <= 0.7:
				continue
			distancias.append(
				(relativo - direcao * (ao_longo * comprimento)).length)
		# Poucos pontos medem o acaso, não a peça.
		if len(distancias) >= AMOSTRA_MINIMA:
			saida[regiao] = 2.0 * max(distancias) / comprimento
	return saida


def _largura_da_cabeca(corpo: bpy.types.Object) -> float:
	"""A maior largura acima da base do pescoço."""
	acima = [v.co for v in corpo.data.vertices if v.co.z >= BASE_DA_CABECA]
	if not acima:
		return 0.0
	return max(p.x for p in acima) - min(p.x for p in acima)


def perfil(corpo: bpy.types.Object, quantas: int = 14) -> list:
	"""A LARGURA do corpo a cada altura — a silhueta, em números.

	Existe porque "a cabeça não está lendo" é uma frase, e frase não se compara
	com a direção de arte. A largura por faixa diz onde está a massa, e é ela
	que responde se a cabeça é maior que o ombro — que é o achado nº 1 do §1 de
	`docs/11`, e o que separa chibi de boneco genérico.
	"""
	pontos = [v.co for v in corpo.data.vertices]
	saida = []
	for i in range(quantas):
		de = ALTURA * i / quantas
		ate = ALTURA * (i + 1) / quantas
		faixa = [p for p in pontos if de <= p.z < ate]
		if not faixa:
			saida.append((de, ate, 0.0))
			continue
		saida.append((de, ate,
		              max(p.x for p in faixa) - min(p.x for p in faixa)))
	return saida


## `(nome, cabeça, cauda, pai)`. Os nomes são os mesmos do gerador anterior,
## porque quem os lê é a camada de jogo e ela não deve saber que o corpo mudou.
def _ossos(ajuste_base: float = 0.0, ajuste_do_braco: float = 0.0) -> list:
	return [
		("quadril", Vector((0.0, 0.0, Y_QUADRIL)), Vector((0.0, 0.0, Y_PEITO)), None),
		("peito", Vector((0.0, 0.0, Y_PEITO)), Vector((0.0, 0.0, Y_PESCOCO)), "quadril"),
		("cabeca", Vector((0.0, 0.0, Y_PESCOCO)), Vector((0.0, 0.0, Y_TOPO)), "peito"),
	] + [
		osso
		for lado, sufixo in ((1.0, "D"), (-1.0, "E"))
		for osso in (
			("braco_" + sufixo, _no_braco(lado, 0.0),
			 _no_braco(lado, COMPRIMENTO_DO_BRACO), "peito"),
			("antebraco_" + sufixo, _no_braco(lado, COMPRIMENTO_DO_BRACO),
			 _no_braco(lado, ATE_O_PULSO), "braco_" + sufixo),
			# **A cauda cai no NÓ da malha, não no fim teórico do osso.** Medido
			# com `closest_point_on_mesh`, a cauda da mão ficava 76,9 mm FORA da
			# pele e a do pé 51,1 mm — o pé inteiro girava em torno de um eixo
			# acima do dedo. As cabeças de osso estavam todas certas, e foi só
			# isso que a versão anterior conferiu.
			("mao_" + sufixo, _no_braco(lado, ATE_O_PULSO),
			 _no_braco(lado, ATE_O_PULSO + COMPRIMENTO_DA_MAO * 0.55
			           + ajuste_do_braco),
			 "antebraco_" + sufixo),
			("coxa_" + sufixo, Vector((lado * X_QUADRIL, 0.0, Y_QUADRIL)),
			 Vector((lado * X_QUADRIL, 0.0, Y_JOELHO)), "quadril"),
			("canela_" + sufixo, Vector((lado * X_QUADRIL, 0.0, Y_JOELHO)),
			 Vector((lado * X_QUADRIL, 0.0, Y_TORNOZELO)), "coxa_" + sufixo),
			("pe_" + sufixo, Vector((lado * X_QUADRIL, 0.0, Y_TORNOZELO)),
			 Vector((lado * X_QUADRIL, -COMPRIMENTO_DO_PE,
			         Y_TORNOZELO * 0.7 + ajuste_base)),
			 "canela_" + sufixo),
		)
	]


def _dentro_da_pele(corpo: bpy.types.Object, ponto: Vector) -> bool:
	"""O ponto está DENTRO da casca? Por paridade de raio.

	`closest_point_on_mesh` não responde isto: ela devolve a distância até a
	superfície, e um ponto no meio do quadril está a 10 cm dela justamente por
	estar bem dentro. Usá-la para decidir dentro/fora acusa o corpo inteiro.
	"""
	cruzamentos = 0
	origem = ponto.copy()
	for _ in range(64):
		alcancou, batida, _normal, _indice = corpo.ray_cast(
			origem, Vector((0.0, 0.0, 1.0)))
		if not alcancou:
			break
		cruzamentos += 1
		origem = batida + Vector((0.0, 0.0, 1e-4))
	return cruzamentos % 2 == 1


## Quantos passos dar ao puxar uma cauda para dentro, e o quanto sobra de folga.
PASSOS_PARA_DENTRO = 12


def _cauda_dentro(corpo: bpy.types.Object, cabeca: Vector, cauda: Vector) -> Vector:
	"""Recua a cauda em direção à cabeça do osso até ela ficar dentro da pele.

	**Um osso tem que estar dentro da carne que ele deforma.** Medido, cinco
	caudas ficavam de fora — as duas mãos, os dois pés e a cabeça —, e o pé era
	o pior: o osso corria reto em `z = 0,163` enquanto a malha do pé ocupava
	`z 0,014` a `0,125`, ou seja, o pé girava em torno de um eixo acima do dedo
	inteiro.

	A causa não é descuido, é a própria convergência: ela empurra o nó da malha
	para fora até a SUPERFÍCIE alcançar o alvo, e a superfície fica para dentro
	do nó. Então o nó, que é onde a cauda estava, sobra do lado de fora.

	Recuar em vez de escolher um fator: fator escolhido a olho é número mágico,
	e ele mudaria junto com o nível da subdivisão sem ninguém perceber.
	"""
	for passo in range(PASSOS_PARA_DENTRO):
		candidata = cabeca.lerp(cauda, 1.0 - passo / float(PASSOS_PARA_DENTRO))
		if _dentro_da_pele(corpo, candidata):
			return candidata
	return cabeca.lerp(cauda, 0.5)


def criar_esqueleto(corpo: bpy.types.Object, ajuste_base: float = 0.0,
                    ajuste_do_braco: float = 0.0) -> bpy.types.Object:
	"""O esqueleto, nas posições que a direção de arte declara.

	Sem transformação nenhuma, e isso é consequência de `convergir`: como só as
	pontas do corpo se movem, a anatomia interna fica onde `PROPORCAO` a põe, e
	o rig pode ser escrito direto a partir dela.
	"""
	dados = bpy.data.armatures.new("Esqueleto")
	objeto = bpy.data.objects.new("Esqueleto", dados)
	bpy.context.collection.objects.link(objeto)
	bpy.context.view_layer.objects.active = objeto
	bpy.ops.object.mode_set(mode="EDIT")
	for nome, cabeca, cauda, pai in _ossos(ajuste_base, ajuste_do_braco):
		osso = dados.edit_bones.new(nome)
		osso.head = cabeca
		osso.tail = _cauda_dentro(corpo, cabeca, cauda)
		if pai is not None:
			osso.parent = dados.edit_bones[pai]
			# Sem `use_connect`: braço e perna partem de um ponto que não é a
			# cauda do pai, e conectá-los os arrastaria para o lugar errado.
			osso.use_connect = False
	bpy.ops.object.mode_set(mode="OBJECT")
	return objeto


def vestir(corpo: bpy.types.Object, esqueleto: bpy.types.Object) -> None:
	"""Prende a pele ao esqueleto com PESOS AUTOMÁTICOS.

	Pesos automáticos e não peso 1 por osso, e a diferença é o ponto desta
	versão: com peso 1 rígido, cada vértice acompanha um osso só e a superfície
	RASGA na dobra. Numa pele contínua o cotovelo tem que amassar, não partir —
	é para isso que existe deformação suave.
	"""
	bpy.ops.object.select_all(action="DESELECT")
	corpo.select_set(True)
	esqueleto.select_set(True)
	bpy.context.view_layer.objects.active = esqueleto
	bpy.ops.object.parent_set(type="ARMATURE_AUTO")



# --------------------------------------------------------------------------
# Cor e rosto
# --------------------------------------------------------------------------

## Uma cor por região. **O contraste é de VALOR, não de matiz.**
##
## Numa silhueta contínua o olho não tem quina para separar braço de tronco: se
## os dois tiverem o mesmo brilho, o braço some dentro do corpo. Foi o que
## aconteceu no boneco anterior, e a peça que dava para seguir era a única com
## cor própria — a mão.
##
## Valores aproximados (0,30·R + 0,59·G + 0,11·B): sapato 0,17, rosto 0,11,
## membro 0,23, roupa 0,44, pele 0,74, mão 0,60.
CORES = {
	"pele": (0.85, 0.72, 0.60, 1.0),
	"roupa": (0.35, 0.45, 0.62, 1.0),
	"membro": (0.17, 0.21, 0.31, 1.0),
	"mao": (0.90, 0.52, 0.22, 1.0),
	# O sapato precisa se separar do MEMBRO, e os dois eram quase o mesmo
	# brilho — 0,17 contra 0,23. Clareando a bota, o pé ganha silhueta própria
	# no fim de uma perna escura.
	"sapato": (0.55, 0.50, 0.44, 1.0),
	"rosto": (0.10, 0.11, 0.14, 1.0),
}

## Que região pinta cada osso.
MATERIAL_DO_OSSO = {
	"quadril": "roupa", "peito": "roupa", "cabeca": "pele",
	"braco_D": "membro", "antebraco_D": "membro", "mao_D": "mao",
	"braco_E": "membro", "antebraco_E": "membro", "mao_E": "mao",
	"coxa_D": "membro", "canela_D": "membro", "pe_D": "sapato",
	"coxa_E": "membro", "canela_E": "membro", "pe_E": "sapato",
}

## A grossura de cada osso, para a pintura saber a quantos raios dele um ponto
## está. Sai das mesmas medidas que dão os raios da malha — um lugar só.
def _raio_do_osso(fatores: dict = None) -> dict:
	"""A grossura de cada osso, para a pintura saber a quantos raios dele um
	ponto está. Sai das mesmas medidas que dão os raios da malha — um lugar só.

	É função e não dicionário de módulo porque os raios passaram a depender dos
	fatores de correção da subdivisão, que só existem depois de `convergir`.
	"""
	return {
		"quadril": X_QUADRIL * 1.15,
		"peito": X_OMBRO * FRACAO_DO_PEITO,
		"cabeca": RAIO_DA_CABECA,
		"braco_D": _raio("braco", COMPRIMENTO_DO_BRACO, fatores),
		"braco_E": _raio("braco", COMPRIMENTO_DO_BRACO, fatores),
		"antebraco_D": _raio("antebraco", COMPRIMENTO_DO_ANTEBRACO, fatores),
		"antebraco_E": _raio("antebraco", COMPRIMENTO_DO_ANTEBRACO, fatores),
		"mao_D": _raio("mao", COMPRIMENTO_DA_MAO, fatores) * ENGROSSAMENTO_DA_MAO,
		"mao_E": _raio("mao", COMPRIMENTO_DA_MAO, fatores) * ENGROSSAMENTO_DA_MAO,
		"coxa_D": _raio("coxa", COMPRIMENTO_DA_COXA, fatores),
		"coxa_E": _raio("coxa", COMPRIMENTO_DA_COXA, fatores),
		"canela_D": _raio("canela", COMPRIMENTO_DA_CANELA, fatores),
		"canela_E": _raio("canela", COMPRIMENTO_DA_CANELA, fatores),
		"pe_D": _raio("pe", COMPRIMENTO_DO_PE, fatores),
		"pe_E": _raio("pe", COMPRIMENTO_DO_PE, fatores),
	}

## A ordem em que os materiais entram na malha. Fixa, e não a de iteração de um
## dicionário: `material_index` é um número, e um número que muda de significado
## entre execuções produz um boneco diferente do mesmo código.
ORDEM_DAS_CORES = ["pele", "roupa", "membro", "mao", "sapato", "rosto"]


def criar_materiais(corpo: bpy.types.Object) -> dict:
	indices = {}
	for indice, nome in enumerate(ORDEM_DAS_CORES):
		material = bpy.data.materials.new(nome)
		# **A cor vai no NÓ, e é ela que o `.glb` carrega.**
		#
		# Este bloco já esteve escrito ao contrário, com `use_nodes = False` e
		# um comentário afirmando que o exportador lia `diffuse_color`. É falso,
		# e o preço foi medido: as seis cores saíram do exportador como o cinza
		# padrão `[0.8, 0.8, 0.8, 1]`, todas iguais. O boneco que o jogo
		# receberia era monocromático — inclusive o rosto, que existe justamente
		# para o corpo ter frente.
		#
		# E o defeito era INVISÍVEL pelo caminho que eu usava para conferir:
		# `diffuse_color` pinta a viewport, então todo screenshot do Blender
		# mostrava o boneco colorido enquanto o arquivo saía cinza. Olhar a tela
		# do Blender não é olhar o artefato.
		material.use_nodes = True
		bsdf = material.node_tree.nodes.get("Principled BSDF")
		if bsdf is not None:
			bsdf.inputs["Base Color"].default_value = CORES[nome]
			# Sem brilho: a Fase 1 não tem luz decente, e specular lê como
			# sujeira.
			if "Roughness" in bsdf.inputs:
				bsdf.inputs["Roughness"].default_value = 0.9
		# E a cor de viewport também, que é o que o render Workbench da prévia
		# lê. As duas, porque são dois consumidores diferentes.
		material.diffuse_color = CORES[nome]
		corpo.data.materials.append(material)
		indices[nome] = indice
	return indices


def _distancia_ao_osso(ponto: Vector, cabeca: Vector, cauda: Vector) -> float:
	"""Distância de um ponto ao SEGMENTO do osso, não à reta dele."""
	eixo = cauda - cabeca
	comprimento = eixo.length_squared
	if comprimento <= 0.0:
		return (ponto - cabeca).length
	t = max(0.0, min(1.0, (ponto - cabeca).dot(eixo) / comprimento))
	return (ponto - (cabeca + eixo * t)).length


def pintar(corpo: bpy.types.Object, indices: dict,
           ajuste_base: float = 0.0, ajuste_do_braco: float = 0.0,
           fatores: dict = None) -> None:
	"""Cada face recebe a cor do osso mais PRÓXIMO dela.

	A malha é contínua e não tem peças, então não há de onde herdar cor.

	**Por distância, e não por peso.** A primeira versão perguntava qual osso
	dominava os vértices da face, e o resultado tinha a fronteira serrilhada:
	os pesos automáticos sangram entre ossos vizinhos, e perto da divisa a face
	troca de dono a cada polígono. Na tela saía um babador de bordas picotadas
	no meio do peito.

	Distância ao segmento do osso é uma função contínua do espaço, então a
	divisa entre duas cores é uma curva lisa por construção — não porque os
	números deram certo.
	"""
	ossos = _ossos(ajuste_base, ajuste_do_braco)
	raios = _raio_do_osso(fatores)
	for face in corpo.data.polygons:
		centro = face.center
		melhor, perto = None, None
		for nome, cabeca, cauda, _pai in ossos:
			# **Dividido pela GROSSURA do osso.** Distância crua não serve: o
			# osso do peito é uma linha fina no eixo do corpo, e os ossos dos
			# braços passam por fora, perto da superfície do peito. Em
			# distância pura o braço reivindica quase todo o tronco, e sobra
			# uma tira picotada de roupa no meio — foi o babador que apareceu
			# na tela.
			#
			# Dividir pela grossura mede "a quantos raios deste osso eu estou",
			# que é o que separa carne de vizinho: o tronco é gordo e alcança
			# longe, o braço é fino e alcança perto.
			distancia = (_distancia_ao_osso(centro, cabeca, cauda)
			             / raios[nome])
			if perto is None or distancia < perto:
				melhor, perto = nome, distancia
		face.material_index = indices[MATERIAL_DO_OSSO.get(melhor, "roupa")]
	_alisar_pintura(corpo)


## Quantas passadas de voto da vizinhança. Duas tiram a poeira sem apagar
## região pequena; mais que isso comeria o rosto.
PASSADAS_DE_ALISAMENTO = 2


def _alisar_pintura(corpo: bpy.types.Object) -> None:
	"""Cada face adota a cor da MAIORIA das vizinhas, quando ela é maioria.

	**A voxelização trocou um problema por outro.** Ela fecha a auto-interseção
	por construção, mas devolve triângulos uniformes que não têm relação
	nenhuma com a estrutura do corpo — e aí uma decisão tomada face a face
	alterna na divisa e sai em farrapo. Na tela virou máscara rasgada no rosto e
	borda picotada no tronco.

	Voto da vizinhança é o remédio padrão para ruído de rótulo: uma face isolada
	com cor diferente das vizinhas é quase certamente erro de amostragem, não
	uma região de uma face. Duas passadas bastam, e regiões de verdade
	sobrevivem porque elas TÊM vizinhança.
	"""
	vizinhas = {}
	por_aresta = {}
	for face in corpo.data.polygons:
		for chave in face.edge_keys:
			por_aresta.setdefault(chave, []).append(face.index)
	for lista in por_aresta.values():
		for a in lista:
			for b in lista:
				if a != b:
					vizinhas.setdefault(a, set()).add(b)

	for _passada in range(PASSADAS_DE_ALISAMENTO):
		atual = [f.material_index for f in corpo.data.polygons]
		novo = list(atual)
		for indice, face in enumerate(corpo.data.polygons):
			contagem = {}
			for outra in vizinhas.get(indice, ()):
				contagem[atual[outra]] = contagem.get(atual[outra], 0) + 1
			if not contagem:
				continue
			campea = max(contagem, key=contagem.get)
			# Só troca quando a maioria é ESTRITA e maior que os próprios
			# vizinhos da cor atual — senão duas cores empatadas piscam entre
			# as passadas em vez de assentar.
			if (campea != atual[indice]
					and contagem[campea] > contagem.get(atual[indice], 0)):
				novo[indice] = campea
		for indice, face in enumerate(corpo.data.polygons):
			face.material_index = novo[indice]


## Quanto da frente da cabeça vira rosto, em fração do raio dela.
FUNDO_DO_ROSTO = 0.55
## E a partir de que altura da cabeça, para o rosto não descer no queixo.
ALTURA_DO_ROSTO = 0.25


def pintar_rosto(corpo: bpy.types.Object, indices: dict) -> int:
	"""Pinta a frente da cabeça, e devolve quantas faces pegou.

	**Isto não é enfeite: é o que dá FRENTE ao corpo.** A malha é simétrica em
	Y tirando os pés, então sem o rosto não há como o olho — nem a sonda — saber
	para que lado o personagem olha. `tools/sondar_campeoes.gd` reprova o
	boneco quando o material `rosto` não existe, e essa conferência nasceu de o
	personagem ter andado de costas por 25 animações sem nada acusar.

	A frente do Blender é **-Y**. A conversão para o -Z da Godot é feita na
	engine, por `Boneco.giro_do_modelo`.
	"""
	acima = [v.co for v in corpo.data.vertices if v.co.z >= Y_PESCOCO]
	if not acima:
		return 0
	topo = max(p.z for p in acima)
	base = min(p.z for p in acima)
	raio = max(abs(p.y) for p in acima)
	pintadas = 0
	for face in corpo.data.polygons:
		centro = face.center
		if centro.z < base + (topo - base) * ALTURA_DO_ROSTO:
			continue
		if centro.z > topo - (topo - base) * 0.12:
			continue
		if centro.y > -raio * FUNDO_DO_ROSTO:
			continue
		face.material_index = indices["rosto"]
		pintadas += 1
	_alisar_pintura(corpo)
	return sum(1 for f in corpo.data.polygons
	           if f.material_index == indices["rosto"])


def exportar(caminho: str) -> None:
	"""Grava o `.glb`.

	**O gerador anterior desta sessão não fazia isto**, e foi o achado nº 1 do
	validador: ele imprimia, devolvia zero, e o jogo continuava carregando o
	arquivo antigo. Gerar sem gravar é a lição 5 do `CLAUDE.md` na forma
	literal — verde por não ter mudado nada.

	Grava em `arte/boneco.glb`, e NÃO em `arte/personagem.glb`, que é o que o
	jogo carrega.

	**O motivo mudou, e o antigo está registrado porque venceu.** Ele era "este
	corpo não tem animação, então trocar tiraria o `AnimationPlayer` do jogo" —
	falso desde que `parado` e `andando` existem. O motivo de hoje é aritmético:
	são DOIS clipes contra os 25 que o jogo já toca, e o vocabulário que a
	camada de jogo pede tem 25 nomes. Trocar agora apagaria 23 verbos.

	`arte/boneco.glb` ainda não tem consumidor nenhum: só este gerador escreve e
	`conferir_boneco.py` lê. Isso é estado, não descuido — ele substitui o outro
	quando cobrir o vocabulário.
	"""
	os.makedirs(os.path.dirname(caminho), exist_ok=True)
	bpy.ops.export_scene.gltf(
		filepath=caminho,
		export_format="GLB",
		# Ligadas desde ja: quando as animacoes entrarem, elas saem no arquivo
		# sem ninguem precisar lembrar de mexer aqui.
		export_animations=True,
		export_animation_mode="ACTIONS",
		export_apply=False,
		export_yup=True,
		# **Os ossos de ponta precisam existir no arquivo.** O glTF nao guarda
		# "cauda de osso": ele guarda uma arvore, e a cauda de um osso e a
		# cabeca do filho. Sem folha, `mao_D` e `pe_D` saem sem filho e nenhuma
		# ferramenta que leia so o `.glb` consegue medir o comprimento deles —
		# `conferir_boneco.py` reprovava com "nao achei o osso".
		export_leaf_bone=True,
	)




# --------------------------------------------------------------------------
# Animação
#
# As poses são escritas em eixos do MUNDO — `X` inclina para a frente, `Y`
# tomba para o lado, `Z` gira em pé —, para qualquer osso. Não é o que o
# Blender guarda: lá a rotação vive no espaço do osso, onde o eixo que corre ao
# longo dele é o `Y`, e "girar em pé" para o quadril é "abrir o braço" para o
# braço. `_para_o_osso` faz a conversão, e por isso cada pose aqui pode ser
# lida como "inclina 6 graus para a frente" sem depender de qual osso é.
# --------------------------------------------------------------------------

## Quadros por segundo. Medido nos 1350 clipes do original — §4 de `docs/11`.
CADENCIA = 30


def _para_o_osso(armature: bpy.types.Object, nome: str, graus: tuple) -> Euler:
	"""A rotação de mundo `graus`, escrita no espaço em que o osso a guarda.

	`matrix_basis` de um osso de pose vive na base de REPOUSO dele. A mesma
	rotação, noutra base, é a conjugação `B⁻¹ R B` — e é isso e só isso.
	"""
	base = armature.data.bones[nome].matrix_local.to_3x3()
	mundo = Euler([math.radians(g) for g in graus], "XYZ").to_matrix()
	return (base.inverted() @ mundo @ base).to_euler("XYZ")


def curvas_de(acao: bpy.types.Action):
	"""As curvas de uma ação, nas duas APIs.

	O Blender 4.4 trocou `Action.fcurves` pelo sistema de camadas com slots, e a
	partir da 5.x o atributo antigo não existe mais: as curvas vivem em
	`acao.layers[].strips[].channelbags[].fcurves`. Aceitar as duas formas faz o
	gerador funcionar em qualquer versão instalada, o que importa num script que
	não é rodado toda hora.
	"""
	if hasattr(acao, "fcurves"):
		return list(acao.fcurves)
	curvas = []
	for camada in acao.layers:
		for trecho in camada.strips:
			for saco in getattr(trecho, "channelbags", []):
				curvas.extend(saco.fcurves)
	return curvas


def pose(**ossos) -> dict:
	"""Açúcar: `pose(peito=(6, 0, 0))` em vez de um dicionário à mão."""
	return ossos


def _ciclo_de_pernas(pernas: list, bracos: list, tronco: list) -> list:
	"""Monta um ciclo de locomoção a partir de UM lado.

	`pernas` é `(instante, coxa, canela, pé)` da direita; `bracos` é
	`(instante, braço, antebraço)` da direita; `tronco` é
	`(instante, peito, cabeça)`. O lado esquerdo é o direito defasado em meio
	ciclo, e o braço direito acompanha a perna ESQUERDA.

	**Existe para o espelho não ser escrito duas vezes.** A primeira versão da
	caminhada tinha os dois lados à mão e saiu com os joelhos invertidos — a
	perna que sustentava dobrada e a que passava esticada, o inverso do que uma
	perna faz. Um sinal errado em dezesseis números é fácil; num só, não.
	"""
	def em(tabela, instante):
		"""O valor da tabela no instante, INTERPOLANDO e fechando a volta.

		Cada tabela tem a resolução que ela precisa: a perna precisa de oito
		instantes para o joelho não esticar cedo, o braço e o tronco precisam de
		quatro. Exigir chave exata obrigaria a mais fina a ditar as outras, e
		obrigaria a escrever à mão valores que a interpolação dá de graça.
		"""
		alvo = instante % 1.0
		pontos = sorted(tabela)
		# **Duplicado e fora de ordem REPROVAM.** Como os instantes viram um
		# conjunto, toda consulta cai exatamente sobre um ponto da grade, e um
		# duplicado é o extremo colapsado de um segmento de largura zero: a
		# chave escrita a mais some sem uma palavra. Medido, uma linha com 42
		# graus de diferença publicou com saída idêntica ao último dígito. E
		# `0.375` digitado como `0.250` é um caractere.
		quando = [ponto[0] for ponto in pontos]
		if len(set(quando)) != len(quando):
			raise RuntimeError(
				"a tabela tem instante repetido: %s — uma das chaves seria "
				"engolida em silencio" % quando)
		if [p[0] for p in tabela] != quando:
			raise RuntimeError(
				"a tabela nao esta em ordem de instante: %s"
				% [p[0] for p in tabela])
		# **E instante fora de `[0, 1)` reprova.** Ele não era recusado, e
		# virava quadro-chave além do ciclo; foi pego por acaso, por outra
		# conferência. Acaso não é defesa.
		if quando[0] < 0.0 or quando[-1] >= 1.0:
			raise RuntimeError(
				"a tabela tem instante fora de [0, 1): %s — o ciclo e uma "
				"volta, e 1,0 e o mesmo ponto que 0,0" % quando)
		# A volta fecha: depois do último instante vem o primeiro, mais um
		# ciclo. Sem isto, tudo entre 0,875 e 1,0 ficaria sem entrada.
		primeiro = pontos[0]
		pontos = pontos + [(primeiro[0] + 1.0,) + tuple(primeiro[1:])]
		for indice in range(len(pontos) - 1):
			antes, depois = pontos[indice], pontos[indice + 1]
			if antes[0] - 1e-9 <= alvo <= depois[0] + 1e-9:
				vao = depois[0] - antes[0]
				peso = 0.0 if vao <= 0.0 else (alvo - antes[0]) / vao
				return [a + (d - a) * peso
				        for a, d in zip(antes[1:], depois[1:])]
		raise KeyError("o instante %.3f caiu fora da tabela" % alvo)

	instantes = sorted({q for q, *_ in pernas} | {q for q, *_ in bracos}
	                   | {q for q, *_ in tronco})
	chaves = []
	for instante in instantes + [1.0]:
		coxa_D, canela_D, pe_D = em(pernas, instante)
		coxa_E, canela_E, pe_E = em(pernas, instante + 0.5)
		# O braço acompanha a perna do lado oposto: o braço direito vai com a
		# perna esquerda, e por isso ele lê a tabela defasada.
		braco_D, antebraco_D = em(bracos, instante)
		braco_E, antebraco_E = em(bracos, instante + 0.5)
		peito, cabeca, bascula = em(tronco, instante)
		chaves.append((instante, pose(
			coxa_D=(coxa_D, 0, 0), canela_D=(canela_D, 0, 0),
			pe_D=(pe_D, 0, 0),
			coxa_E=(coxa_E, 0, 0), canela_E=(canela_E, 0, 0),
			pe_E=(pe_E, 0, 0),
			braco_D=(braco_D, -4, 0), antebraco_D=(antebraco_D, 0, 0),
			braco_E=(braco_E, 4, 0), antebraco_E=(antebraco_E, 0, 0),
			peito=(peito, 0, 0), cabeca=(cabeca, 0, 0),
			# **A báscula do quadril.** `Y` tomba para o lado, e é ela que o
			# projeto já chamava de o que mais lê como caminhada:
			# `gesto_de_caminhada.gd` manda `bamboleio: 7.0` justamente porque
			# sem transferência lateral de peso o corpo parece deslizar sobre
			# trilhos. O clipe que veio substituí-lo tinha zero.
			quadril=(0, bascula, 0))))
	return chaves


## As animações, uma por verbo do jogo.
##
## **Só entram verbos com CONSUMIDOR.** Regra do usuário em 24/08/2026: nada de
## ataque, nada de pulo, e nada que ficaria órfão hoje — cortar árvore e minerar
## não têm sistema que os dispare, e conteúdo que existe e ninguém pede é
## exatamente onde o `.glb` inteiro já esteve.
##
## As durações são a MEDIANA medida nos 1350 clipes do original, §4 de
## `docs/11`. Não são escolha: `idle` mede 1,33 s em 93 controladores.
ANIMACOES = {
	"parado": {
		"ciclo": True,
		"duracao": 1.33,
		# As regiões que esta animação TEM que mover, e elas são as que o
		# jogador VÊ. Sem isto, o piso de amplitude olha só o máximo do corpo —
		# que é sempre a extremidade mais distante do pivô — e aprova um corpo
		# em que só a ponta se mexe: medido, uma perna levantada o clipe inteiro
		# publicava os mesmos 0,123 m.
		# **`mao` saiu daqui, e a saida e um achado.** Medida a articulacao do
		# proprio osso, a mao girava 0,00 grau: ela nunca teve chave nenhuma,
		# e os 0,123 m publicados como prova de vida eram carona do braco. A
		# regua antiga lia deslocamento no mundo e nao sabia a diferenca.
		"movem": ["cabeca", "braco", "antebraco"],
		"pes_plantados": True,
		# **Quem carrega a leitura é a CABEÇA e a MÃO, não o peito.**
		#
		# Este comentário já afirmou o contrário, e a afirmação foi medida e
		# desmentida. O que ele dizia: que o boneco anterior girava o peito 2,5
		# graus e a cabeça 1,5, e que aqui o peito ia a 6 e o braço a 7, "o
		# dobro do que o olho precisa". Medido nos dois arquivos:
		#
		#   peito      4,50° -> 6,00°   (+33%, não o dobro)
		#   cabeça     2,50° -> 4,50°
		#   braço      7,81° -> 7,81°   IDÊNTICO
		#   amplitude  0,116 m -> 0,123 m   (+6%)
		#
		# Os "2,5 e 1,5" eram o valor da segunda CHAVE, lido como se fosse a
		# excursão. E o braço — que é quem produz os 0,123 m publicados como
		# prova de vida — não mudou nada em relação ao clipe que o comentário
		# chamava de estátua. Os 12 cm citados como prova de estátua e os 12,3
		# publicados como prova de vida são o mesmo número.
		#
		# O que de fato mudou foi a DURAÇÃO: 2,00 s para 1,33 s, a mediana
		# medida. A mesma excursão em dois terços do tempo.
		#
		# E na câmera do jogo — personagem a 43 px de altura — o peito se move
		# 0,44 px. É sub-pixel: ninguém o vê. Quem se vê são as duas mãos, a
		# 3,0 px, e a cabeça, a 2,3. Por isso `movem` não lista peito: exigir
		# movimento de uma região invisível seria exigir exagero para
		# satisfazer uma régua.
		#
		# Mas a mão que se vê a 3,0 px é levada pelo BRAÇO e pelo ANTEBRAÇO, e
		# são eles que `movem` nomeia. O antebraço ganhou chave nesta rodada:
		# um respiro em que o cotovelo não acompanha lê como manequim, e sem
		# ele a única articulação do membro inteiro era o ombro.
		#
		# O quadril continua parado de propósito: as pernas são rígidas, sem
		# joelho dobrando para compensar, e levantá-lo tira os dois pés do chão.
		"chaves": [
			(0.0, pose(peito=(3, 0, 0), cabeca=(3, 0, 0),
			           braco_D=(2, -3, 0), braco_E=(2, 3, 0),
			           antebraco_D=(-4, 0, 0), antebraco_E=(-4, 0, 0))),
			(0.5, pose(peito=(-3, 0, 0), cabeca=(-3, 0, 0),
			           braco_D=(-4, -8, 0), braco_E=(-4, 8, 0),
			           antebraco_D=(-11, 0, 0), antebraco_E=(-11, 0, 0))),
			(1.0, pose(peito=(3, 0, 0), cabeca=(3, 0, 0),
			           braco_D=(2, -3, 0), braco_E=(2, 3, 0),
			           antebraco_D=(-4, 0, 0), antebraco_E=(-4, 0, 0))),
		],
	},
	"andando": {
		"ciclo": True,
		"duracao": 1.27,
		# **A PERNA tem que se mexer, e é só ela que precisa.** Sem isto o piso
		# de amplitude aprovaria uma caminhada em que só o braço balança.
		#
		# A cabeça saiu desta lista depois de medida: ela anda 0,042 m numa
		# caminhada, porque o que a move é o quique do corpo e não uma ação
		# própria. Exigir 0,05 dela seria exigir que o boneco balançasse a
		# cabeça ao andar para satisfazer uma régua.
		# **O braço entra aqui, e a ausência dele custou uma reprovação.** Com
		# `movem` listando só a perna, congelar os dois braços publicava com
		# rc=0 — e a tabela de braço morta que a revisão anterior reprovou
		# voltava sem uma linha no console.
		# `mao` saiu, `braco` entrou, pelo mesmo motivo do `parado`: medida a
		# articulacao do proprio osso, a mao gira 0,00 grau nos dois clipes —
		# ela nunca teve chave. Quem balanca o membro e o ombro, a 52 graus.
		"movem": ["coxa", "canela", "pe", "braco", "antebraco"],
		# E a báscula, no eixo dela. Medida: 0,033 m de lado no peito.
		"balanca": {"peito": 0.020},
		# **Um pé de cada vez sai do chão, e é isso que separa andar de pular.**
		# `parado` exige os dois plantados; aqui a exigência é que sempre haja
		# ao menos UM no chão. Um clipe em que os dois saem ao mesmo tempo é um
		# salto, e salto é justamente o que o usuário mandou não construir.
		"pes_plantados": False,
		"sempre_um_pe_no_chao": True,
		"passada": True,
		# **O quadril assenta.** Sem isso, girar a perna enfia o pé no chão na
		# passada e levanta o boneco no ar na troca.
		"assentar": True,
		# `+X` inclina para a frente, e num osso que aponta para BAIXO isso
		# manda a ponta para trás — por isso perna à frente é `-X`.
		#
		# Braço e perna do MESMO lado vão em sentidos opostos: é o que o corpo
		# faz para não girar em torno do próprio eixo, e é o que separa uma
		# caminhada de um boneco de corda.
		# **A perna de apoio fica RETA e a que balança dobra MUITO.**
		#
		# A primeira versão tinha o contrário — joelho dobrado na perna que
		# sustenta e quase reto na que passa — e o preço foi medido: a perna que
		# balançava roçava o chão indo para a frente, e o pé apoiado arrastava
		# 0,424 m no sentido do movimento. O corpo patinava.
		#
		# Perna reta sustenta o corpo alto; joelho dobrado tira o pé do caminho.
		# É por isso que o joelho existe.
		#
		# **E são OITO instantes, não quatro.** Com quatro, o joelho esticava
		# cedo demais na volta: medido quadro a quadro, o pé que balançava
		# voltava a tocar o chão no quadro 32 de 38 — 16% antes do contato — e
		# arrastava 0,301 m para a frente. O joelho precisa continuar dobrado
		# até quase o fim do balanço, e isso é um instante que não existia.
		#
		# O ciclo é gerado por `_ciclo_de_pernas`, que constrói a perna esquerda
		# defasando a direita em meio ciclo. Escrever os dois lados à mão é
		# escrever duas vezes a chance de errar um sinal — e foi assim que a
		# primeira versão saiu com os joelhos invertidos.
		"chaves": _ciclo_de_pernas(
			# (instante, coxa, canela) da perna DIREITA. A esquerda sai daqui.
			# **O pé entra na tabela porque o joelho sozinho não levanta.**
			#
			# Medido isolando o osso: dobrar o joelho 60 graus levanta a sola
			# apenas 7 cm, e o quadril desce junto na troca de apoio. Com folga
			# de 7 cm o pé que balança voltava a tocar o chão nos quadros 30 a
			# 33 de 38 e arrastava 0,266 m para a frente.
			#
			# Dedo para cima tira a ponta do caminho sem mexer na altura do
			# corpo, que é o que uma pessoa faz ao passar o pé.
			[
				# **Calcanhar primeiro.** Dedo para cima no contato alonga o
				# alcance da perna sem esticar o joelho, e é o que impede o
				# quadril de afundar quando o pé toca. Sem isso o quique era
				# 7% da altura contra 2,6% de uma pessoa.
				# **A passada encurtou de 24 para 17 graus, e o motivo é o
				# mergulho.** Medido quadro a quadro, o quique não era
				# ondulação: era uma queda brusca de 0,888 para 0,770 no
				# instante da troca de apoio, quando as DUAS pernas estão
				# anguladas e portanto as duas ficam curtas. Quanto maior o
				# ângulo, mais fundo o corpo cai ali. É geometria, não estilo.
				(0.000, -17, 2, -10),   # contato: calcanhar, perna esticada
				(0.125, -11, 10, -2),   # recebe o peso: pé assenta
				# **O joelho de apoio dobra na passagem**, e isso não é
				# enfeite: reto, o corpo sobe ao máximo justo quando a perna
				# fica vertical, e o quique do quadril media 0,121 m — 7% da
				# altura, contra 4 a 5 cm de uma pessoa, 2,5 vezes demais. É o
				# joelho que absorve, e sem ele o corpo cai e escala.
				(0.250, -2, 6, 0),      # passagem: vertical, sustentando
				(0.375, 8, 6, 6),       # empurra
				(0.500, 15, 6, 14),     # desprende: calcanhar sai primeiro
				(0.625, 4, 74, -24),    # levanta: joelho no máximo, dedo acima
				(0.750, -10, 68, -24),  # passa por cima, ainda dobrado
				(0.875, -19, 44, -16),  # estende, mas SEM tocar
			],
			# (instante, braço, antebraço) do braço DIREITO. Ele acompanha a
			# perna do lado OPOSTO — é o que impede o corpo de girar sobre o
			# próprio eixo.
			#
			# **O cotovelo era morto: ia de -12 a -14, dois graus.** Medido na
			# tela, os braços ficavam colados no tronco e as mãos presas na
			# altura do quadril, e a justificativa gravada creditava à contrafase
			# a função de separar a caminhada de um boneco de corda — função dada
			# a um movimento que não acontecia. Um braço humano balança 25 a 30
			# graus no ombro e dobra o cotovelo visivelmente na volta.
			[
				(0.000, 26, -14),   # atrás, esticando
				(0.125, 20, -26),
				(0.250, 4, -38),    # passa junto ao corpo, dobrado
				(0.375, -12, -44),
				(0.500, -26, -40),  # à frente, no alto
				(0.625, -18, -30),
				(0.750, -2, -18),
				(0.875, 14, -12),
			],
			# E o tronco: inclinação, cabeça, e a BÁSCULA lateral do quadril.
			#
			# A báscula acompanha o apoio — o quadril cai para o lado da perna
			# que balança, que é o que uma pessoa faz para o pé passar. Duas
			# vezes por ciclo, defasada meio ciclo da perna.
			[
				(0.000, 3, -2, 0),
				(0.250, 4, -3, 5),
				(0.500, 3, -2, 0),
				(0.750, 4, -3, -5),
			],
		),
	},
}


## O quanto o vértice que mais anda precisa andar para a animação contar como
## animação, em metros.
##
## **Não é um alvo de qualidade, é um piso contra clipe morto.** O original não
## publica amplitude — o censo mediu duração e ciclo, não excursão —, então não
## há mediana para perseguir. Este número existe para pegar "gerou chaves e o
## corpo não se mexeu", que é um defeito que passa em toda conferência de
## duração e de fechamento.
##
## Se a animação lê bem ou não, quem responde é o olho: é o item que não se
## automatiza, e está declarado como tal.
AMPLITUDE_MINIMA = 0.05
## Quantos GRAUS um osso listado em `movem` tem de girar para contar como
## animado. E angulo, nao metro, porque metro nao distingue articular de ser
## carregado — ver o comentario de `giros` em `medir_animacao`.
##
## **Aqui viveu uma conferencia de SIMETRIA, e ela foi removida por nao poder
## falhar.** Ela exigia que os dois lados de um osso par articulassem dentro de
## 5% um do outro. Medido pelo revisor adversarial, os dez pares dos dois
## clipes dao o mesmo numero ate a segunda decimal — 0,00% de desvio em 10 de
## 10 — e nao por acaso: `_ciclo_de_pernas` deriva o lado esquerdo do direito e
## a tabela do `parado` e espelhada a mao. A excursao e identica por
## CONSTRUCAO, entao nao ha clipe que o projeto consiga autorar hoje em que ela
## pudesse reprovar.
##
## E o terreno dela ja estava coberto duas vezes. Desligando-a, a unica mutacao
## assimetrica da suite — `a perna esquerda manca` — continua sendo pega, por
## `DESEQUILIBRIO`, que compara altura do passo e passada. E `os bracos param
## de balancar` e pega por este piso aqui, cujo laco roda ANTES dela.
##
## E a licao 8 do `CLAUDE.md` em letra de forma: *"Fixture degenerado e
## cobertura falsa. Se todos os casos tem o mesmo valor, a mutacao que troca
## esse valor e um no-op literal."* Conferencia que nao pode reprovar e pior
## que nenhuma, porque LE como cobertura.
ARTICULACAO_MINIMA = 5.0

## Quanto o pé pode sair do chão numa animação que não é de pulo.
FOLGA_DO_CHAO = 0.015

## Quantos pontos da sola são olhados para decidir se há vértice perdido, e
## quanto eles podem se espalhar em altura.
##
## A sola do boneco tem cerca de 2 cm entre o ponto mais baixo e o décimo
## segundo — ela é uma bola achatada, não um plano. Um vértice bem abaixo disso
## não é sola: é malha quebrada, e `assentar` por ele levantaria o corpo todo.
AMOSTRAS_DA_SOLA = 12
ESPALHAMENTO_DA_SOLA = 0.05

## Quanto o pé apoiado pode andar PARA A FRENTE enquanto está no chão.
##
## **Este é o defeito clássico de caminhada, e nada aqui o media.** Num ciclo
## que anda no lugar, o pé apoiado tem que recuar de forma monótona uma
## passada inteira — é esse recuo que a translação do jogo cancela. Se ele
## volta para a frente com a sola no chão, o personagem patina.
##
## Medido no primeiro clipe, rerodando-o com esta mesma função: recuo **0,417**
## e arrasto **0,424**. O corpo andava no lugar.
##
## **Este comentário já afirmou 0,301 e 0,316, e nenhum dos dois reproduz.** O
## 0,301 era o arrasto de uma versão intermediária que nunca foi commitada, e o
## 0,316 não existe em versão nenhuma — a própria tabela do commit que o
## introduziu dizia 0,424/0,417 duas linhas abaixo. Número gravado que não
## reproduz é a classe de defeito que este projeto mais repete.
##
## `gesto_de_caminhada.gd` existe porque o usuário reclamou de deslizamento.
DESLIZE_PARA_A_FRENTE = 0.01


## O quanto o pé apoiado tem que recuar, em metros. Uma passada curta ainda é
## passada; nenhuma é andar no lugar.
PASSADA_MINIMA = 0.15

## Quanto os dois pés podem diferir, em fração, em qualquer das três medidas.
##
## **Já foi 0,25 comparando só a contagem de quadros, e nunca disparou.** Uma
## perna com 0,85 da amplitude da outra passava: 18 quadros contra 22 é 18%. O
## defeito não era a constante, era a medida.
DESEQUILIBRIO = 0.12

## Quanto do ciclo cada pé tem que passar sustentando o corpo SOZINHO.
##
## Numa caminhada humana o apoio simples é cerca de 40% do ciclo por perna, com
## dois trechos curtos de apoio duplo entre eles. Um quinto é folgado o bastante
## para não brigar com o estilo e apertado o bastante para reprovar um clipe em
## que as duas pernas fazem a mesma coisa.
APOIO_SIMPLES_MINIMO = 0.20

## Quanto o quadril pode subir e descer, em fração da altura.
##
## **Isto é teto de REGRESSÃO, e não o alvo.** O alvo é 2,3 a 2,9% — os 4 a 5 cm
## de uma pessoa de 1,75 m. Estamos em 5,6%, e a distância é conhecida.
##
## O que ela custa está medido: o quique não é ondulação, é um mergulho brusco
## no instante da troca de apoio, quando as DUAS pernas estão anguladas e as
## duas ficam curtas ao mesmo tempo. Medido quadro a quadro, o quadril ia de
## 0,888 a 0,770 em dois quadros. Encurtar a passada de 24 para 17 graus levou
## 7,1% a 5,6%; fechar o resto exige o que uma perna rígida não tem — tornozelo
## que rola do calcanhar à ponta, e bacia que gira no plano transversal.
##
## O teto é o valor medido. Já foi 6,0%, e isso não era o "mesmo tratamento de
## `TETO_DE_AUTOINTERSECAO`" que o comentário prometia: aquele é o valor exato,
## 78 contra 78, folga zero. Teto arredondado para cima é espaço para piorar
## sem ninguém ver.
##
## **E o próprio comentário violava a regra que enunciava**, achado do revisor:
## ele dizia "sem folga — 5,6%" enquanto o medido é 5,5762%, ou seja arredondado
## para cima justamente como ele condenava duas linhas antes. Hoje o teto é
## 5,578%, que é o medido arredondado na QUARTA casa — 0,04 mm de folga num
## corpo de 1,75 m, e o `.glb` sai byte a byte igual entre execuções, então nem
## isso seria preciso.
##
## Ele continua reprovando a regressão que motivou a correção — a tabela de
## pernas anterior mede 7,3%.
QUIQUE_MAXIMO = 0.05578


def _passada(alturas: list, posicoes: list) -> tuple:
	"""`(recuo, arrasto para a frente)` do pé enquanto ele está no chão.

	A frente é -Y, então recuar é Y crescer. O que se mede é a soma dos passos
	em cada sentido dentro das janelas de apoio — e não o total, porque um pé
	que vai e volta tem total zero e desliza o caminho inteiro.
	"""
	recuo = 0.0
	avanco = 0.0
	for indice in range(1, len(alturas)):
		if alturas[indice] > FOLGA_DO_CHAO or alturas[indice - 1] > FOLGA_DO_CHAO:
			continue
		passo = posicoes[indice] - posicoes[indice - 1]
		if passo >= 0.0:
			recuo += passo
		else:
			avanco += -passo
	return recuo, avanco


def _regiao_do_osso(nome: str) -> str:
	"""`braco_D` e `braco_E` são a mesma região. Derivado, não tabelado.

	Uma segunda tabela de nomes é um segundo lugar para ficar desatualizado, e
	este arquivo já declara a correspondência em `OSSO_DA_REGIAO`.
	"""
	if nome.endswith("_D") or nome.endswith("_E"):
		return nome[:-2]
	return nome


def medir_animacao(armature: bpy.types.Object, corpo: bpy.types.Object,
                   nome: str, ultimo: int) -> tuple:
	"""`(amplitude, amplitude por região, altura e posição de cada pé)`.

	Mede no corpo DEFORMADO — `evaluated_get` é o que aplica o esqueleto. Ler
	`corpo.data.vertices` direto devolve a malha em repouso, e uma conferência
	daí aprovaria qualquer animação, inclusive uma que não anima.
	"""
	acao = bpy.data.actions.get(nome)
	if acao is None:
		raise RuntimeError("a acao `%s` sumiu antes de ser medida" % nome)
	armature.animation_data.action = acao
	if hasattr(armature.animation_data, "action_slot") and acao.slots:
		armature.animation_data.action_slot = acao.slots[0]

	# De quem é cada vértice, pelo peso. É o mesmo termo que a esbeltez usa.
	grupos = {g.index: g.name for g in corpo.vertex_groups}
	dono = []
	for vertice in corpo.data.vertices:
		melhor, peso = None, 0.0
		for atribuicao in vertice.groups:
			if atribuicao.weight > peso:
				peso, melhor = atribuicao.weight, grupos.get(atribuicao.group)
		dono.append(melhor)

	## A altura do quadril, quadro a quadro, para o quique ter teto.
	alturas_do_quadril = []
	menor = maior = None
	# **O chão é medido POR PÉ, e não no corpo inteiro.**
	#
	# `min(z)` de todos os vértices responde "algum ponto do corpo toca o
	# chão", que não é o que o item 5 do §10 promete. Medido: uma coxa a -30
	# graus o clipe inteiro — o pé direito no ar do começo ao fim — saía com
	# `chao +0,0009 a +0,0009` e era publicado. E os próximos clipes são
	# `andando` e `correndo`, que são exatamente aqueles em que um pé de cada
	# vez sai do chão.
	chao = {"pe_D": [], "pe_E": []}
	## Onde cada pé está em Y, quadro a quadro. A frente é -Y.
	marcha = {"pe_D": [], "pe_E": []}
	## **A rotação LOCAL de cada osso, quadro a quadro.**
	##
	## `matrix_basis` é o desvio do osso em relação ao repouso DELE, no espaço
	## do pai. Um osso que não articula tem essa matriz constante, e isso não
	## depende de quem o carrega — que é o defeito que derrubou as duas
	## tentativas anteriores. A primeira mediu deslocamento no mundo: um braço
	## congelado no ombro ainda anda 0,14 m de carona. A segunda descontou o
	## quadril: em `parado` o quadril não tem chave nenhuma, então ela não
	## descontava nada, e quem carregava o braço era o peito — a margem para
	## publicar um braço morto era de 1,3 mm, e um grau a mais de báscula a
	## apagava. Descontar um osso escolhido à mão não fecha a classe; medir a
	## articulação do próprio osso fecha.
	giros = {osso.name: [] for osso in armature.pose.bones}
	## `[pior contagem, quadro em que ela ocorreu]` de travessia da casca.
	travessia = [0, 0]
	for quadro in range(0, ultimo + 1):
		bpy.context.scene.frame_set(quadro)
		avaliado = corpo.evaluated_get(bpy.context.evaluated_depsgraph_get())
		temporaria = avaliado.to_mesh()
		pontos = [avaliado.matrix_world @ v.co for v in temporaria.vertices]
		for nome in chao:
			meus = [p for p, d in zip(pontos, dono) if d == nome]
			chao[nome].append(min(p.z for p in meus) if meus else 0.0)
			# E onde ele está, para a conferência de deslize. A frente é -Y.
			marcha[nome].append(
				sum(p.y for p in meus) / len(meus) if meus else 0.0)
		if menor is None:
			menor = [p.copy() for p in pontos]
			maior = [p.copy() for p in pontos]
		else:
			for indice, ponto in enumerate(pontos):
				for eixo in range(3):
					menor[indice][eixo] = min(menor[indice][eixo], ponto[eixo])
					maior[indice][eixo] = max(maior[indice][eixo], ponto[eixo])
		quadril = armature.matrix_world @ armature.pose.bones["quadril"].head
		for osso in armature.pose.bones:
			# **Para onde o osso APONTA, e não a rotação inteira.**
			#
			# `matrix_basis` vive na base de repouso do osso, onde o próprio
			# osso corre ao longo de +Y. Girar em torno de Y é ROLAR o osso em
			# torno do próprio comprimento — e num membro que é superfície de
			# revolução isso é invisível. Aplicar a rotação a +Y descarta
			# exatamente essa componente e guarda as outras duas.
			#
			# Medido pelo revisor adversarial na régua anterior, que usava o
			# quaternion inteiro: trocar a flexão do antebraço do `parado` por
			# rotação em torno do eixo vertical — rolagem pura, num braço que
			# pende — dava os MESMOS 7,00 graus e publicava. A régua de metros
			# contava carona como articulação; a de quaternion trocou esse
			# ponto cego pelo espelho dele e passou a contar torção como
			# movimento. `movem` promete "as regiões que o jogador VÊ".
			giros[osso.name].append(
				osso.matrix_basis.to_quaternion() @ Vector((0.0, 1.0, 0.0)))
		# **A travessia da casca, no mesmo passe.** Ver
		# `TETO_DA_TRAVESSIA_ANIMADA`. Ela viveu num segundo passe sobre os
		# quadros por uma versão, e o segundo `evaluated_get` custava nove
		# vezes o que a medição em si custa.
		temporaria.calc_loop_triangles()
		quantos = len(conferir_boneco.auto_intersecoes(
			[tuple(p) for p in pontos],
			[tuple(t.vertices) for t in temporaria.loop_triangles]))
		if quantos > travessia[0]:
			travessia[0], travessia[1] = quantos, quadro
		avaliado.to_mesh_clear()
		alturas_do_quadril.append(quadril.z)
	bpy.context.scene.frame_set(0)

	# **A amplitude POR REGIÃO, e não só o máximo do corpo.**
	#
	# O máximo global é sempre a extremidade mais distante do pivô — no
	# `parado`, a mão. Medido, apagar peito e cabeça inteiros deixaria o número
	# publicado idêntico: uma perna levantada o clipe todo saiu com os mesmos
	# 0,123 m. O piso global pega "nada se mexeu"; é cego a "só a ponta se
	# mexeu", que é o defeito de uma respiração que morreu.
	por_regiao = {}
	## A amplitude de cada OSSO, para os dois lados serem comparados.
	por_osso = {}
	## E a excursão LATERAL, separada. Ela é a báscula do quadril, e sem ela o
	## corpo desliza sobre trilhos — mas ela some dentro da amplitude total, que
	## é dominada pelo avanço das pernas.
	lateral = {}
	for indice, nome in enumerate(dono):
		if nome is None:
			continue
		regiao = _regiao_do_osso(nome)
		anda = (maior[indice] - menor[indice]).length
		por_regiao[regiao] = max(por_regiao.get(regiao, 0.0), anda)
		# **E por OSSO também**, que é o que distingue os dois lados. A região
		# junta `braco_D` e `braco_E` no máximo dos dois: medido, congelar o
		# braço direito inteiro publicava, porque o esquerdo sozinho sustentava
		# o número. É a mesma cegueira que a manqueira explorava na perna.
		por_osso[nome] = max(por_osso.get(nome, 0.0), anda)
		lateral[regiao] = max(lateral.get(regiao, 0.0),
		                      maior[indice].x - menor[indice].x)
	amplitude = max((maior[i] - menor[i]).length for i in range(len(menor)))

	## Quantos GRAUS a direção de cada osso varreu, do quadro em que ela menos
	## se afastou ao em que mais se afastou. É a maior distância angular entre
	## dois quadros quaisquer — comparar só com o primeiro quadro subestima um
	## osso que vai e volta.
	articulacao = {}
	for osso, lista in giros.items():
		pior = 0.0
		for i in range(len(lista)):
			for j in range(i + 1, len(lista)):
				produto = max(-1.0, min(1.0, lista[i].dot(lista[j])))
				pior = max(pior, math.degrees(math.acos(produto)))
		articulacao[osso] = pior

	return (amplitude, por_regiao, articulacao, lateral, chao, marcha,
	        alturas_do_quadril, tuple(travessia))


## Quantos pares de face podem se atravessar num quadro ANIMADO.
##
## **A pose de repouso tinha teto e o movimento não tinha nenhum**, e a queixa
## que abriu este trabalho era exatamente sobre peças se atravessando andando —
## *"várias peças dele entra uma dentro da outra, até com ele parado"*. O
## conferidor lê o acessor `POSITION` do `.glb`, que é a malha em REPOUSO:
## nenhuma ferramenta abria a malha deformada. Achado do revisor adversarial.
##
## **Medido em TODOS os quadros, e a exaustão não é zelo.** O revisor amostrou
## seis quadros e achou 66; eu amostrei outros seis e achei 68; varrendo os 38
## de `andando` o pior era **79, no quadro 5**, e nenhuma das duas grades o
## continha. Uma grade esparsa aqui não mede o corpo, mede quais quadros
## alguém escolheu.
##
## Com o braço aberto a 28° o pior caiu para **13**, e esses 13 são de outro
## sítio — a mão na nádega, não a axila. Ver `ABERTURA_DO_BRACO`.
##
## **E ela custa quase nada, agora que mede no passe certo.** A primeira
## versão abria a malha deformada num SEGUNDO passe sobre os quadros, e a
## geração passou de 33 s para 3m35s — o que fez a suíte de mutação
## estourar o tempo do executor e morrer no meio, deixando o repositório
## mutado, duas vezes. `medir_animacao` já avalia cada quadro; medir junto
## custa os 0,28 s de `auto_intersecoes` por quadro e mais nada.
##
## O teto é o pior valor medido, sem folga, pelo mesmo argumento de
## `TETO_DE_AUTOINTERSECAO` — e pelo argumento que `QUIQUE_MAXIMO` enunciava e
## descumpria: teto arredondado para cima é espaço para piorar sem ninguém ver.
TETO_DA_TRAVESSIA_ANIMADA = 13


def assentar(armature: bpy.types.Object, ultimo: int) -> list:
	"""Baixa ou levanta o quadril até o ponto mais baixo do corpo tocar o chão.

	**Sem isto, girar a perna enfia o pé no chão.** Uma coxa a 22 graus encurta
	a distância do quadril ao pé; o corpo inteiro continua na mesma altura, e a
	sola atravessa o piso. Na troca de passada acontece o contrário e o boneco
	flutua.

	É medido no corpo DEFORMADO, quadro a quadro, e não calculado por
	trigonometria: a distância do quadril ao chão depende de coxa, canela, pé e
	de como a pele se deforma na dobra, e uma conta fechada erraria em todos
	esses termos ao mesmo tempo.

	Vai no `location` do osso raiz, no eixo `Y` DELE — que é o eixo ao longo do
	osso, e como o quadril aponta para cima, é o `Z` do mundo.
	"""
	corpo = None
	for filho in armature.children:
		if filho.type == "MESH":
			corpo = filho
			break
	if corpo is None:
		raise RuntimeError("o esqueleto nao tem malha para assentar")

	quadril = armature.pose.bones.get("quadril")
	if quadril is None:
		raise RuntimeError("nao achei o osso `quadril` para assentar")
	deslocamentos = []

	for quadro in range(0, ultimo + 1):
		bpy.context.scene.frame_set(quadro)
		quadril.location = (0.0, 0.0, 0.0)
		bpy.context.view_layer.update()
		avaliado = corpo.evaluated_get(bpy.context.evaluated_depsgraph_get())
		temporaria = avaliado.to_mesh()
		alturas = sorted((avaliado.matrix_world @ v.co).z
		                 for v in temporaria.vertices)
		avaliado.to_mesh_clear()
		# **O chão é o ponto mais baixo, e o vértice perdido é OUTRO defeito.**
		#
		# Isto já foi o 12º ponto mais baixo, para o assentamento não repousar
		# num vértice só. Medido, a troca não sustentava peso: afundar 1, 11, 12
		# ou 24 vértices em 8 mm escapava identicamente, e o caso de 15 cm era
		# pego por outra conferência. O que ela comprava era zero, e o que
		# custava era real — **a sola ficava 2,07 cm ENTERRADA no piso o ciclo
		# inteiro**, porque a própria sola tem 2 cm de altura entre o primeiro e
		# o décimo segundo ponto dela.
		#
		# Ancorar no mínimo é a resposta certa para "onde está o chão". Um
		# vértice perdido lá embaixo é uma malha quebrada, e malha quebrada se
		# acusa como malha quebrada — `_vertice_perdido`, abaixo — em vez de se
		# acomodar dentro de uma conferência que responde outra pergunta.
		perdido = alturas[0] < alturas[min(len(alturas), AMOSTRAS_DA_SOLA) - 1] 			- ESPALHAMENTO_DA_SOLA
		if perdido:
			raise RuntimeError(
				"no quadro %d ha vertice %.3f m abaixo da sola (espalhamento "
				"maximo %.3f) — a malha tem ponto perdido, e assentar por ele "
				"levantaria o corpo inteiro"
				% (quadro, alturas[min(len(alturas), AMOSTRAS_DA_SOLA) - 1]
				   - alturas[0], ESPALHAMENTO_DA_SOLA))
		menor = alturas[0]
		quadril.location = (0.0, -menor, 0.0)
		quadril.keyframe_insert("location", frame=quadro)
		deslocamentos.append(-menor)
	bpy.context.scene.frame_set(0)
	return deslocamentos


def criar_animacao(armature: bpy.types.Object, nome: str,
                   dados: dict) -> int:
	"""Uma ação com as chaves declaradas, interpolada em Bézier.

	`AUTO_CLAMPED` e não `AUTO`: a alça automática do Blender ultrapassa a chave
	para suavizar a curva, e num ciclo isso faz a pose passar do extremo
	declarado entre duas chaves que estão ambas certas.
	"""
	bpy.context.view_layer.objects.active = armature
	bpy.ops.object.mode_set(mode="POSE")

	acao = bpy.data.actions.new(nome)
	# Sem `use_fake_user` o Blender descarta a ação ao trocar de contexto e o
	# exportador não acha nada.
	acao.use_fake_user = True
	if armature.animation_data is None:
		armature.animation_data_create()
	armature.animation_data.action = acao

	for osso in armature.pose.bones:
		osso.rotation_mode = "XYZ"

	ultimo = 0
	for instante, poses in dados["chaves"]:
		quadro = int(round(instante * dados["duracao"] * CADENCIA))
		ultimo = max(ultimo, quadro)
		for osso in armature.pose.bones:
			osso.rotation_euler = _para_o_osso(
				armature, osso.name, poses.get(osso.name, (0.0, 0.0, 0.0)))
			osso.keyframe_insert("rotation_euler", frame=quadro)

	if dados.get("assentar"):
		assentar(armature, ultimo)

	for curva in curvas_de(acao):
		for ponto in curva.keyframe_points:
			ponto.interpolation = "BEZIER"
			ponto.handle_left_type = "AUTO_CLAMPED"
			ponto.handle_right_type = "AUTO_CLAMPED"

	bpy.ops.object.mode_set(mode="OBJECT")
	return ultimo



def main() -> int:
	# **A cadência tem que chegar à CENA, e não só à constante.**
	#
	# `CADENCIA` valia 30 no código e o Blender continuava em 24, que é o padrão
	# dele. O exportador usa o da cena: 40 quadros saíam como 1,667 s onde a
	# direção de arte mede 1,33. Declarar um número e não passá-lo adiante é o
	# mesmo que não tê-lo — e foi o conferidor que acusou, na primeira execução
	# em que ele passou a olhar duração.
	bpy.context.scene.render.fps = CADENCIA
	bpy.context.scene.render.fps_base = 1.0

	corpo, esqueleto, ajuste_base, ajuste_do_braco, fatores = convergir()
	indices = criar_materiais(corpo)
	pintar(corpo, indices, ajuste_base, ajuste_do_braco, fatores)
	for nome, dados in ANIMACOES.items():
		quadros = criar_animacao(esqueleto, nome, dados)
		(amplitude, por_regiao, por_osso, lateral, chao, marcha,
		 alturas_do_quadril, travessia) = medir_animacao(  # em graus
			esqueleto, corpo, nome, quadros)
		# **A duração impressa é a MEDIDA, não a declarada.** Ela já imprimiu
		# "1,33 s" com o arquivo saindo em 1,667 — mentindo sobre exatamente o
		# número que o gerador diz ter aprendido a passar adiante.
		cadencia = (bpy.context.scene.render.fps
		            / bpy.context.scene.render.fps_base)
		print("[boneco] animacao `%s`: %.3f s medidos (%.2f declarados), "
		      "%d quadros a %.0f/s, amplitude %.3f m"
		      % (nome, quadros / cadencia, dados["duracao"], quadros,
		         cadencia, amplitude))
		for regiao in sorted(por_regiao):
			print("[boneco]     %-10s anda %.4f m" % (regiao, por_regiao[regiao]))
		for osso in sorted(por_osso):
			print("[boneco]       %-12s articula %6.2f graus"
			      % (osso, por_osso[osso]))

		for regiao in dados.get("movem", ()):
			# **Os DOIS lados, um a um.** Olhando só o máximo da região, um
			# lado congelado passa escondido atrás do outro — medido, o braço
			# direito inteiro parado publicava com rc=0.
			lados = [osso for osso in por_osso
			         if _regiao_do_osso(osso) == regiao]
			if not lados:
				raise RuntimeError(
					"em `%s` a regiao `%s` nao tem osso nenhum na malha — a "
					"conferencia dela ficou orfa" % (nome, regiao))
			for osso in sorted(lados):
				# Rotacao LOCAL do osso: articulacao, nao carona.
				girou = por_osso[osso]
				if girou < ARTICULACAO_MINIMA:
					raise RuntimeError(
						"em `%s` o osso `%s` gira %.2f graus e o piso e %.1f "
						"— a animacao existe, mas a parte que ela deveria "
						"mover nao se move"
						% (nome, osso, girou, ARTICULACAO_MINIMA))
		## **A casca se atravessa ANDANDO?** Ver `TETO_DA_TRAVESSIA_ANIMADA`.
		pior_travessia, quadro_ruim = travessia
		print("[boneco]     travessia da casca: %d pares no pior quadro (%d), "
		      "teto %d"
		      % (pior_travessia, quadro_ruim, TETO_DA_TRAVESSIA_ANIMADA))
		if pior_travessia > TETO_DA_TRAVESSIA_ANIMADA:
			raise RuntimeError(
				"em `%s` a casca se atravessa em %d pares no quadro %d, e o "
				"teto e %d — o corpo entra em si mesmo em movimento"
				% (nome, pior_travessia, quadro_ruim,
				   TETO_DA_TRAVESSIA_ANIMADA))

		for regiao, minimo in dados.get("balanca", {}).items():
			andou = lateral.get(regiao, 0.0)
			print("[boneco]     %-10s balanca %.4f m de lado (minimo %.4f)"
			      % (regiao, andou, minimo))
			# **A báscula lateral tem piso, e não tinha nenhum.** Medido pelo
			# revisor, zerá-la publicava com rc=0 — e o próprio projeto escreve
			# que o balanço lateral é o que mais lê como caminhada. Ela some
			# dentro da amplitude total, que é dominada pelo avanço da perna;
			# por isso é medida em separado, no eixo dela.
			if andou < minimo:
				raise RuntimeError(
					"em `%s` a regiao `%s` balanca %.4f m de lado e o minimo e "
					"%.4f — sem transferencia de peso o corpo desliza sobre "
					"trilhos" % (nome, regiao, andou, minimo))

		if amplitude < AMPLITUDE_MINIMA:
			raise RuntimeError(
				"a animacao `%s` desloca %.3f m e o piso e %.3f — abaixo disso "
				"ela nao e animacao, e um corpo parado com chaves"
				% (nome, amplitude, AMPLITUDE_MINIMA))
		for pe, alturas in sorted(chao.items()):
			enterrou = -min(alturas)
			print("[boneco]     %s: sobe %.4f m, enterra %.4f m"
			      % (pe, max(alturas), enterrou))
			# **Enterrar reprova SEMPRE; flutuar só quando o clipe diz.**
			#
			# As duas metades estavam atrás de `pes_plantados`, e `andando` a
			# põe em falso — então o único clipe com perna em movimento era o
			# único sem teto de penetração. Medido, a sola atravessava o piso
			# 2,07 cm o ciclo inteiro, e nada acusava.
			#
			# **Com `assentar` ligado ele dá zero por identidade**, porque o
			# assentamento ancora o mínimo do corpo em zero. Aqui ele é guarda
			# de regressão DO assentamento — se ele parar de assentar, ou
			# assentar pelo ponto errado, isto acusa — e não medida
			# independente de penetração. Vale para os clipes que não assentam,
			# onde ele mede de verdade.
			if enterrou > FOLGA_DO_CHAO:
				raise RuntimeError(
					"em `%s` o `%s` enterra %.4f m no chao e a folga e %.3f"
					% (nome, pe, enterrou, FOLGA_DO_CHAO))
			if dados.get("pes_plantados", True) and max(alturas) > FOLGA_DO_CHAO:
				raise RuntimeError(
					"em `%s` o `%s` sai %.4f m do chao e a folga e %.3f"
					% (nome, pe, max(alturas), FOLGA_DO_CHAO))
		if dados.get("assentar"):
			quique = max(alturas_do_quadril) - min(alturas_do_quadril)
			print("[boneco]     quique do quadril: %.4f m (%.4f%% da altura)"
			      % (quique, 100.0 * quique / ALTURA))
			# **O quique tem TETO, e ele não tinha.** `quadril anda 0,1310 m`
			# era impresso e comparado só com o piso de amplitude, que não tem
			# teto. Medido, o corpo subia e descia 7% da altura contra 4 a 5 cm
			# de uma pessoa — 2,5 vezes demais, e em dente de serra.
			if quique > QUIQUE_MAXIMO * ALTURA:
				raise RuntimeError(
					"em `%s` o quadril sobe e desce %.4f m, %.1f%% da altura "
					"(maximo %.1f%%) — o corpo cai e escala em vez de andar"
					% (nome, quique, 100.0 * quique / ALTURA,
					   QUIQUE_MAXIMO * 100))

		if dados.get("passada"):
			for pe in sorted(chao):
				recuo, avanco = _passada(chao[pe], marcha[pe])
				print("[boneco]     %s apoiado: recua %.3f m, arrasta %.3f para "
				      "a frente" % (pe, recuo, avanco))
				# **O pé apoiado tem que EMPURRAR o chão para trás.** Se ele
				# volta para a frente com a sola no chão, o personagem patina —
				# e o clipe anterior fazia exatamente isso, 0,316 m.
				if avanco > DESLIZE_PARA_A_FRENTE:
					raise RuntimeError(
						"em `%s` o `%s` arrasta %.3f m para a frente com a sola "
						"no chao (maximo %.3f) — isso e deslizamento"
						% (nome, pe, avanco, DESLIZE_PARA_A_FRENTE))
				# **A velocidade que este clipe implica, publicada — e o
				# buraco que ela expõe.**
				#
				# Este comentário já disse *"quem tem que escalar a cadência
				# pela velocidade é a camada de jogo"*. Isso era promessa, não
				# fato, e foi medido: **`speed_scale` não existe em lugar
				# nenhum do repositório**, e `Boneco.tocar` chama
				# `AnimationPlayer.play(nome)` sem argumento de velocidade.
				#
				# Pior: a ÚNICA linha que escala cadência por velocidade é
				# `_fase += delta * cadencia * TAU * (rapidez / 3.3)`, em
				# `gesto_de_caminhada.gd` — e ela fica DEPOIS do atalho que
				# devolve quando existe animador. Ou seja, o ramo que escala é
				# exatamente o que este clipe desliga.
				#
				# Autorado para 0,40 m/s com o corpo transladando a 3,3–5,0, o
				# deslizamento no mundo é de 8 a 12 vezes — enquanto o arrasto
				# medido DENTRO do clipe é 0,000. A conferência mede a grandeza
				# certa do problema errado, e isso fica dito aqui em vez de
				# descoberto depois.
				print("[boneco]       -> clipe autorado para %.3f m/s"
				      % (recuo / (quadros / cadencia)))
				if recuo < PASSADA_MINIMA:
					raise RuntimeError(
						"em `%s` o `%s` recua so %.3f m apoiado (minimo %.3f) — "
						"sem recuo nao ha passada, o corpo anda no lugar"
						% (nome, pe, recuo, PASSADA_MINIMA))
			# **As duas pernas fazem a mesma coisa, defasadas.** `movem` usa o
			# maximo por regiao e os dois lados caem no mesmo numero: medido,
			# congelar a perna esquerda inteira publicava como caminhada.
			# **Comparados por ALTURA e PASSADA, e não por contagem de
			# quadros.** Contagem é cega às duas dimensões em que uma manqueira
			# aparece: medido, uma perna com 0,85 da amplitude da outra ficava
			# apoiada 18 quadros contra 22 — 18%, abaixo do teto — e publicava,
			# enquanto o pé subia 0,1064 m contra 0,1425, um quarto a menos,
			# todo passo. As duas medidas já eram calculadas e impressas; só
			# não eram comparadas entre si.
			for rotulo, valores in (
					("altura do passo",
					 {pe: max(chao[pe]) for pe in chao}),
					("passada",
					 {pe: _passada(chao[pe], marcha[pe])[0] for pe in chao}),
					("quadros apoiados",
					 {pe: sum(1 for a in chao[pe] if a <= FOLGA_DO_CHAO)
					  for pe in chao})):
				print("[boneco]     %-18s %s" % (rotulo, {
					pe: round(v, 4) for pe, v in valores.items()}))
				menor, maior = min(valores.values()), max(valores.values())
				if maior <= 0 or (maior - menor) / float(maior) > DESEQUILIBRIO:
					raise RuntimeError(
						"em `%s` os dois pes diferem em %s: %.4f contra %.4f "
						"(maximo %.0f%%) — as duas pernas tem que fazer a mesma "
						"coisa, defasadas"
						% (nome, rotulo, menor, maior, DESEQUILIBRIO * 100))

		if dados.get("sempre_um_pe_no_chao"):
			# **O que separa andar de pular é FASE, não altura.**
			#
			# Duas medidas de altura já falharam aqui, pelo mesmo motivo:
			# `assentar` normaliza o corpo ao chão em todo quadro. Medindo
			# depois disso, a resposta é zero por identidade — um pulo de dois
			# pés publicava com "0 no ar". Desfazendo o assentamento e
			# ancorando o ciclo pelo instante mais baixo, a caminhada CERTA
			# acusava 27 quadros de voo, porque o quique natural do corpo passa
			# a contar como voo.
			#
			# Num clipe autorado no lugar, altura absoluta não distingue os
			# dois. O que distingue é que numa caminhada cada pé passa um trecho
			# sustentando o corpo SOZINHO, e num salto nenhum passa: os dois
			# fazem a mesma coisa ao mesmo tempo.
			contato = {pe: [altura <= FOLGA_DO_CHAO for altura in chao[pe]]
			           for pe in chao}
			sozinho = {
				"pe_D": sum(1 for d, e in zip(contato["pe_D"], contato["pe_E"])
				            if d and not e),
				"pe_E": sum(1 for d, e in zip(contato["pe_D"], contato["pe_E"])
				            if e and not d),
			}
			print("[boneco]     quadros de apoio SIMPLES: %s" % sozinho)
			for pe, quantos in sorted(sozinho.items()):
				if quantos < APOIO_SIMPLES_MINIMO * (quadros + 1):
					raise RuntimeError(
						"em `%s` o `%s` nunca sustenta o corpo sozinho (%d de "
						"%d quadros, minimo %.0f%%) — os dois pes fazem a mesma "
						"coisa ao mesmo tempo, e isso e um salto"
						% (nome, pe, quantos, quadros + 1,
						   APOIO_SIMPLES_MINIMO * 100))

	rosto = pintar_rosto(corpo, indices)
	print("[boneco] rosto: %d faces pintadas" % rosto)
	if rosto == 0:
		raise RuntimeError(
			"nenhuma face virou rosto — sem ele o corpo nao tem frente, e "
			"`sondar_campeoes.gd` reprova o `.glb`"
		)

	pontos = [v.co for v in corpo.data.vertices]
	print("[boneco] %d vertices" % len(pontos))
	print("[boneco] altura %.3f m   largura %.3f   profundidade %.3f" % (
		max(p.z for p in pontos) - min(p.z for p in pontos),
		max(p.x for p in pontos) - min(p.x for p in pontos),
		max(p.y for p in pontos) - min(p.y for p in pontos)))
	print("[boneco] -- silhueta: largura por faixa de altura --")
	for de, ate, largura in perfil(corpo):
		barra = "#" * int(largura * 60)
		print("[boneco]   %.2f-%.2f m  %.3f  %s" % (de, ate, largura, barra))

	raiz = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
	destino = os.path.join(raiz, "arte", "boneco.glb")

	# **Exporta para um nome provisório e só publica se passar.**
	#
	# Escrevendo direto no lugar definitivo, toda execução reprovada deixaria um
	# boneco ruim no disco — e no outro gerador deste projeto foi exatamente
	# assim que um artefato defeituoso chegou a ser commitado. Reprovar não pode
	# publicar nada.
	provisorio = os.path.join(os.path.dirname(destino), "boneco.novo.glb")
	exportar(provisorio)

	# O conferidor é Python puro — não importa `bpy` —, então roda aqui dentro
	# sem subprocesso e sem depender de qual interpretador está no caminho.
	falhas = conferir_boneco.conferir(provisorio)
	if falhas:
		os.remove(provisorio)
		print("[boneco] REPROVADO, %d motivo(s):" % len(falhas))
		for falha in falhas:
			print("[boneco]   - %s" % falha)
		print("[boneco] nada foi publicado — %s continua como estava" % destino)
		return 1
	os.replace(provisorio, destino)
	print("[boneco] gravado: %s (%.0f KB)" % (
		destino, os.path.getsize(destino) / 1024))

	# **E o `.blend` também sai daqui.** Ele existia ao lado do `.glb` gravado
	# por outro caminho, e ninguém sabia de qual versão do código ele vinha.
	blend = os.path.join(raiz, "arte", "fonte", "boneco.blend")
	os.makedirs(os.path.dirname(blend), exist_ok=True)
	bpy.ops.wm.save_as_mainfile(filepath=blend)
	print("[boneco] para abrir e olhar: %s" % blend)
	return 0


if __name__ == "__main__":
	sys.exit(main())
