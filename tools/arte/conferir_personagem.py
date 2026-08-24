# -*- coding: utf-8 -*-
"""Confere o personagem exportado por medida, nao por olho.

Rodar:
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" ^
        --background --python tools/arte/conferir_personagem.py

Sai com codigo 1 se alguma conferencia reprovar.

## O que ela sabe, e o que nao sabe

Sabe se o pe esta no chao, se o boneco tem o tamanho de gente, se as animacoes
que o jogo chama pelo nome existem no arquivo, e se cada uma se MEXE. Nao sabe
se ficou bonito — para isso e `renderizar_previa.py` e olho humano.

A que mais paga a conta e a do chao. Um esqueleto sem IK levanta o quadril e
os dois pes sobem junto; a animacao continua rodando, o exportador continua
exportando, e o defeito so aparece como "o personagem desliza no ar". Ja
aconteceu: a primeira caminhada subia o quadril 4,5 cm na passada e tirava os
dois pes do chao, e nenhuma das outras ferramentas notou.
"""

from __future__ import annotations

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import regra_da_folga  # noqa: E402  (depende do sys.path acima)

## Quanto o ponto mais baixo do corpo pode ficar longe de z=0 numa animacao de
## chao, em metros. Um centimetro e meio e menos que a espessura do sapato.
TOLERANCIA_DO_CHAO = 0.015
## As animacoes em que o boneco DEVE sair do chao, e o minimo que ele sobe.
NO_AR = {"salto": 0.25, "correndo": 0.04}
## **As variantes conjuradas em movimento SAO a corrida por baixo** (§5 de
## `docs/11`), entao herdam o voo dela em vez de declarar um numero proprio.
## Escrever 0,04 de novo aqui seria o mesmo literal em tres lugares, e o
## `CLAUDE.md` registra cinco recorrencias dessa especie.
for _variante in ("arremesso_a_frente", "arremesso_atras"):
	NO_AR[_variante] = NO_AR["correndo"]
## Quanto uma animacao precisa mexer para contar como animacao, em metros —
## medido na maior AMPLITUDE de um vertice, de um extremo ao outro do ciclo.
##
## Amplitude, e nao passo entre quadros vizinhos: a primeira versao media a
## distancia de um quadro para o seguinte e reprovava a respiracao do `parado`,
## que percorre pouco por quadro justamente por ser lenta. Medir o que se quer
## saber — "isso se mexe?" — e medir de onde ate onde.
MOVIMENTO_MINIMO = 0.03
## O que o codigo de jogo chama pelo nome. `GestoDeConjuracao.Gesto` escolhe
## entre os cinco gestos; a locomocao usa os tres primeiros.
##
## **Esta lista tem que ser a mesma de `VocabularioDeAnimacao.TODOS`**, que e o
## que o jogo pede, e a mesma que o `.glb` tem. Quem confere as tres e
## `tools/conferir_numeros.py` — e ele existe porque o jogo passou a pedir oito
## nomes do Royal Crown que nunca estiveram no nosso arquivo, com todas as
## outras ferramentas verdes.
NOMES_EXIGIDOS = [
	"parado", "andando", "correndo",
	"levou_dano",
	"atordoado",
	"morte",
	"caido",
	"rastejando",
	"colhendo",
	"pegando",
	"cortando",
	"minerando",
	"comendo",
	"bebendo",
	"operando",
	"arremesso",
	"arremesso_a_frente",
	"arremesso_atras",
	"montado",
	"montado_correndo",
	"estocada", "giro", "salto", "erguer", "preparo",
]
## Quais rodam em CICLO — a coluna "Tipo" do §3 de `docs/11`, medida nos 32
## campeoes do original.
##
## Ciclo tem uma obrigacao que "uma vez" nao tem: **o ultimo quadro repete o
## primeiro** (item 3 da lista do §10). Sem isso o corpo salta ao emendar a
## volta, e o salto e tanto mais visivel quanto mais curto o clipe — na corrida
## ele acontece tres vezes por segundo.
EM_CICLO = {"parado", "andando", "correndo", "atordoado", "caido", "rastejando", "colhendo", "cortando", "minerando", "comendo", "bebendo", "operando", "montado", "montado_correndo"}
## Quanto o ultimo quadro de um ciclo pode se afastar do primeiro, em metros —
## medido no vertice que mais se afasta. Publicado em `docs/11` §9.
FECHAMENTO_DO_CICLO = 0.005
## A altura do corpo parado, em metros. Faixa APERTADA de proposito: o boneco
## e autorado com 1,75 exato, entao qualquer desvio significa que uma medida
## saiu de sincronia com as outras. Com a faixa larga de antes (1,60 a 1,90),
## encolher a cabeca inteira passava.
## A altura do corpo parado, em metros. `docs/11` §2 manda 1,75 m para todo
## personagem; a folga aqui e so a espessura de uma caixa.
ALTURA_DA_DIRECAO = 1.75
## A folga da altura, em metros — publicada em `docs/11` §9 e conferida contra
## ele. Escrita solta, alargar ate nada reprovar era uma edicao de um digito.
FOLGA_DA_ALTURA = 0.04
ALTURA_ESPERADA = (ALTURA_DA_DIRECAO - FOLGA_DA_ALTURA,
                   ALTURA_DA_DIRECAO + FOLGA_DA_ALTURA)

## ------------------------------------------------------------------ arte
##
## Daqui para baixo a conferencia deixa de perguntar "quebrou?" e passa a
## perguntar "**esta na direcao de arte?**". As faixas sao as medidas em 27
## campeoes do original, em `docs/11-direcao-de-arte.md`, com folga.
##
## Sem isto o documento seria decoracao: ninguem o executa, e na terceira
## sessao o boneco anda para um lado e o texto para o outro. Ja aconteceu com
## prosa neste projeto quatro vezes seguidas.

## `medida: (mediana, minimo, maximo)` — os tres numeros que `docs/11` publica,
## medidos em 27 campeoes do original.
##
## **A folga nao e escrita, e DERIVADA:** meia faixa medida, arredondada para
## cima em passos de meio ponto percentual. Escrever a folga a mao foi um erro
## real — `VAO_DOS_QUADRIS` tinha 0,035 onde a regra dava 0,020, e a docstring
## logo acima dele afirmava que a folga seguia a regra. Justificativa gravada
## que era falsa, terceira ocorrencia neste projeto.
##
## E derivar fecha uma classe inteira: com a folga escrita, alargar a tolerancia
## ate nada reprovar era uma edicao de um digito que passava por tudo.
FAIXA_MEDIDA = {
	"pe_D": (0.093, 0.057, 0.123),      # tornozelo
	"canela_D": (0.283, 0.253, 0.328),  # joelho
	"coxa_D": (0.485, 0.417, 0.512),    # quadril
	"peito": (0.656, 0.602, 0.687),     # peito
	"cabeca": (0.763, 0.708, 0.795),    # base do pescoco
	"braco_D": (0.725, 0.672, 0.753),   # junta do ombro
}
FAIXA_DAS_LARGURAS = {
	"ombros": (0.175, 0.162, 0.241),
	"quadris": (0.129, 0.105, 0.145),
	# Junta a junta, parando no punho.
	"maos": (0.629, 0.588, 0.703),
	# Ponta a ponta da malha, mao inclusa.
	"envergadura": (0.895, 0.808, 0.966),
}
## A regra da folga vive em `regra_da_folga.py`, que e Python puro e sem
## Blender — e por isso `conferir_numeros.py` tambem consegue confer-la. Ela
## morava aqui dentro, e enquanto morou a formula so era protegida por quem
## tivesse o Blender instalado.
def _autoteste_da_folga() -> None:
	for motivo in regra_da_folga.conferir_a_regra():
		print("[confere] REPROVA: %s" % motivo)
		raise SystemExit(1)


PASSO_DA_FOLGA = regra_da_folga.PASSO_DA_FOLGA
folga_de = regra_da_folga.folga_de


PROPORCAO_ESPERADA = {
	osso: (faixa[0], folga_de(faixa)) for osso, faixa in FAIXA_MEDIDA.items()
}
VAO_DOS_OMBROS = (FAIXA_DAS_LARGURAS["ombros"][0], folga_de(FAIXA_DAS_LARGURAS["ombros"]))
VAO_DOS_QUADRIS = (FAIXA_DAS_LARGURAS["quadris"][0], folga_de(FAIXA_DAS_LARGURAS["quadris"]))
VAO_DAS_MAOS = (FAIXA_DAS_LARGURAS["maos"][0], folga_de(FAIXA_DAS_LARGURAS["maos"]))
ENVERGADURA = (FAIXA_DAS_LARGURAS["envergadura"][0],
               folga_de(FAIXA_DAS_LARGURAS["envergadura"]))

## A faixa de duracao de cada animacao, em segundos, tirada do vocabulario do
## original. As tres de locomocao usam a faixa do clipe equivalente; os cinco
## gestos usam os quartis dos clipes de habilidade (p25 0,83 -- p75 1,40).
## As faixas de locomocao sao a faixa MEDIDA do clipe equivalente, sem folga:
## sao publicadas em `docs/11` e conferidas contra ela. Com folga inventada,
## alargar uma delas ate nada reprovar passava por tudo.
DURACAO_ESPERADA = {
	"parado": (1.27, 5.33),      # `idle`  medido nos 32
	"andando": (1.07, 1.60),     # `walk`  medido nos 32
	"correndo": (0.67, 1.13),    # `run`   medido nos 32
	"levou_dano": (1.00, 1.00),  # `beaten` medido nos 32 — ponto, nao faixa
	"atordoado": (0.50, 1.00),  # `stun`  medido nos 32
	"morte": (1.13, 3.33),  # `death` medido nos 32
	"caido": (1.33, 1.33),  # `knockout_idle` medido nos 32
	"rastejando": (1.13, 1.33),  # `knockout_run` medido nos 32
	"colhendo": (0.67, 0.67),  # `collect` medido nos 32
	"pegando": (0.50, 0.50),  # `loot` medido nos 32 — uma vez
	"cortando": (1.50, 1.50),  # `cut` medido nos 32 — 1,50 s exatos
	"minerando": (1.50, 1.50),  # `mine` medido nos 32 — 1,50 s exatos
	"comendo": (6.57, 6.57),  # `eat` medido nos 32 — o mais longo do vocabulario
	"bebendo": (1.00, 3.00),  # `drink` medido nos 32
	"operando": (1.00, 1.00),  # `operate` medido nos 32
	"arremesso": (0.80, 1.37),  # `throw` medido nos 32 — a conjuracao universal
	"arremesso_a_frente": (0.73, 1.50),  # `throw_f` medido nos 32 — dura um ciclo de corrida
	"arremesso_atras": (0.73, 1.13),  # `throw_b` medido nos 32 — dura um ciclo de corrida
	"montado": (1.33, 1.33),  # `ride_idle` medido nos 32
	"montado_correndo": (0.60, 0.60),  # `ride_run` medido nos 32 — o mais curto do vocabulario
	"estocada": (0.83, 1.40),
	"giro": (0.83, 1.40),
	"salto": (0.83, 1.40),
	"erguer": (0.83, 1.40),
	"preparo": (0.83, 1.40),
}
## O original roda a 30 quadros por segundo em 1344 dos 1350 clipes.
CADENCIA = 30.0
COLECAO_AUXILIAR = "glTF_not_exported"


def importar(glb: str) -> tuple:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	# **A cadencia ANTES da importacao.** O glTF guarda tempo em SEGUNDOS, e e o
	# importador que converte para quadro usando a cadencia da cena. Acertando
	# depois, a conversao ja aconteceu a 24: uma animacao de 2,00 s era medida
	# como 1,60 s, e o erro e de escala — nao aparece como quebra, aparece como
	# "tudo esta 20% rapido demais", que e facil de acreditar.
	bpy.context.scene.render.fps = int(CADENCIA)
	bpy.ops.import_scene.gltf(filepath=glb)
	for objeto in list(bpy.data.objects):
		if any(c.name == COLECAO_AUXILIAR for c in objeto.users_collection):
			bpy.data.objects.remove(objeto, do_unlink=True)
	armature = None
	for objeto in bpy.data.objects:
		if objeto.type == "ARMATURE":
			armature = objeto
	malha = None
	for objeto in bpy.data.objects:
		if objeto.type != "MESH":
			continue
		for modificador in objeto.modifiers:
			if modificador.type == "ARMATURE" and modificador.object is armature:
				malha = objeto
	return armature, malha


def usar(armature, acao) -> None:
	if armature.animation_data is None:
		armature.animation_data_create()
	armature.animation_data.action = acao
	if hasattr(armature.animation_data, "action_slot") and len(acao.slots) > 0:
		armature.animation_data.action_slot = acao.slots[0]


def pontos(malha) -> list:
	"""Os vertices do corpo DEFORMADO, em coordenadas de mundo.

	`evaluated_get` e o que aplica o modificador de esqueleto. Ler
	`malha.data.vertices` direto devolve a malha em repouso — e uma conferencia
	lendo dali aprovaria qualquer animacao, inclusive uma que nao anima.
	"""
	profundidade = bpy.context.evaluated_depsgraph_get()
	avaliada = malha.evaluated_get(profundidade)
	temporaria = avaliada.to_mesh()
	mundo = avaliada.matrix_world
	saida = [mundo @ vertice.co for vertice in temporaria.vertices]
	avaliada.to_mesh_clear()
	return saida


def medir(armature, malha, acao) -> dict:
	usar(armature, acao)
	inicio, fim = int(acao.frame_range[0]), int(acao.frame_range[1])
	chao_por_quadro = []
	topo = 0.0
	menor = None
	maior = None
	for quadro in range(inicio, fim + 1):
		bpy.context.scene.frame_set(quadro)
		locais = pontos(malha)
		chao_por_quadro.append(min(p.z for p in locais))
		topo = max(topo, max(p.z for p in locais))
		if menor is None:
			menor = [p.copy() for p in locais]
			maior = [p.copy() for p in locais]
		else:
			for indice, ponto in enumerate(locais):
				for eixo in range(3):
					menor[indice][eixo] = min(menor[indice][eixo], ponto[eixo])
					maior[indice][eixo] = max(maior[indice][eixo], ponto[eixo])
	amplitude = 0.0
	for indice in range(len(menor)):
		amplitude = max(amplitude, (maior[indice] - menor[indice]).length)
	return {
		"chao_minimo": min(chao_por_quadro),
		"chao_maximo": max(chao_por_quadro),
		"topo": topo,
		"movimento": amplitude,
		"duracao": (fim - inicio) / CADENCIA,
		"fechamento": _fechamento(malha, inicio, fim),
	}


def _fechamento(malha, inicio: int, fim: int) -> float:
	"""Quanto o ULTIMO quadro se afasta do primeiro, em metros.

	O vertice que mais se afasta, no corpo ja deformado. Um ciclo cujo ultimo
	quadro nao repete o primeiro salta ao emendar a volta — item 3 da lista de
	checagem do §10 de `docs/11`.

	Medido em VERTICE e nao em angulo de osso de proposito: e o mesmo termo que
	o resto desta ferramenta usa, e ele pega qualquer diferenca de pose sem
	precisar enumerar quais propriedades olhar. Enumerar propriedade e a
	armadilha que mais rendeu achado neste projeto.
	"""
	bpy.context.scene.frame_set(inicio)
	primeiro = pontos(malha)
	bpy.context.scene.frame_set(fim)
	ultimo = pontos(malha)
	if len(primeiro) != len(ultimo) or not primeiro:
		return float("inf")
	return max((a - b).length for a, b in zip(primeiro, ultimo))


def _mais_longe_do_grupo(malha, grupo: str, origem):
	"""A DISTANCIA do ponto mais afastado de um grupo ate `origem`, em repouso.

	**Era o ponto mais BAIXO, e isso embutia uma hipotese de pose.** Enquanto o
	braco caia reto do ombro, "mais baixo" e "mais afastado do ombro" davam o
	mesmo numero; com o repouso em A eles deixam de dar, e a envergadura sairia
	menor sem nada parecer errado. Distancia nao depende de para onde o braco
	aponta, que e o que a medida quer dizer.
	"""
	if grupo not in malha.vertex_groups:
		return None
	indice = malha.vertex_groups[grupo].index
	mundo = malha.matrix_world
	distancias = [
		((mundo @ v.co) - origem).length for v in malha.data.vertices
		if any(g.group == indice and g.weight > 0.5 for g in v.groups)
	]
	return max(distancias) if distancias else None


## A esbeltez que o GERADOR declara, por regiao. Conferir contra ela, e nao
## contra a faixa medida no original, e uma escolha com motivo.
##
## **A faixa do original nao serve como tolerancia aqui.** Ela e larga — o
## braco vai de 0,544 a 0,941 entre 27 campeoes, o que da folga +-0,200 pela
## regra. Com essa folga, o boneco ANTERIOR, que tinha braco 0,603 e foi o que
## o usuario reprovou na tela, passaria. Uma conferencia que aprova o defeito
## que acabou de ser corrigido nao e conferencia.
##
## O laco e fechado em DOIS pontos apertados, e nao num largo:
##
## 1. aqui, a malha exportada tem que bater com o que `ESBELTEZ` declara — e
##    ela e a origem de `CAIXAS`, entao qualquer espessura mexida a mao reprova;
## 2. em `tools/conferir_numeros.py`, `ESBELTEZ` tem que bater com a mediana
##    medida em `data/direcao-de-arte.json` E cair dentro da faixa medida.
##
## Nenhum dos dois sozinho fecha: o primeiro aprovaria um numero inventado, e o
## segundo aprovaria um numero certo que a malha nao usa.
ESBELTEZ_DECLARADA = {
	"cabeca": 0.778, "braco": 0.758, "antebraco": 0.716, "mao": 0.752,
	"coxa": 0.575, "canela": 0.494, "quadril": 0.676, "peito": 0.779,
}

## De qual regiao e cada grupo de vertices do boneco.
REGIAO_DO_GRUPO = {
	"cabeca": "cabeca", "peito": "peito", "quadril": "quadril",
	"braco_D": "braco", "braco_E": "braco",
	"antebraco_D": "antebraco", "antebraco_E": "antebraco",
	"mao_D": "mao", "mao_E": "mao",
	"coxa_D": "coxa", "coxa_E": "coxa",
	"canela_D": "canela", "canela_E": "canela",
}

## Quanto a esbeltez medida na malha pode se afastar da declarada.
##
## E apertada de proposito: a peca e construida a partir do numero, entao bater
## e o normal e qualquer distancia e defeito.
##
## **Ela ja foi 0,06 e isso escondia um vies.** Os quatro membros mediam
## 0,924 vez o declarado — nao ruido, e sim `cos(pi/8)`: o prisma de oito lados
## nascia inscrito e apresentava a face, nao a quina, aos eixos. A folga
## engolia os 7,6% e a conferencia dizia "ok". Corrigido o raio no gerador, a
## folga pode voltar a ser o que uma folga deve ser: pequena o bastante para
## que qualquer desvio real apareca.
FOLGA_DA_ESBELTEZ = 0.02

## A cabeca e a excecao, e a excecao tem causa medida.
##
## O grupo dela carrega a VISEIRA e o NARIZ, que sao adornos: eles engordam a
## caixa envolvente sem sair do osso, e a derivacao nao os controla. Medida
## assim ela da 0,838 contra 0,778 declarados, e a diferenca e exatamente a
## cara. Apertar aqui seria exigir que a peca derivada compensasse o adorno,
## acoplando um numero ao outro.
##
## A folga dela e a da POPULACAO — meia faixa medida, pela regra do §9 — e isso
## e comparavel pelo motivo certo: as cabecas do original tambem vem com
## cabelo, chapeu e orelha, e e por isso que a faixa delas vai de 0,508 a 0,988,
## a mais larga das nove.
FOLGA_DA_CABECA = folga_de((0.778, 0.508, 0.988))

## As regioes que NAO derivam da esbeltez, e por isso nao sao conferidas contra
## ela. Ver `CAIXAS_DO_TRONCO` no gerador: nos cortamos o tronco em dois ossos
## curtos e o original distribui os vertices dele pelo tronco inteiro, entao a
## razao mede a nossa segmentacao e nao a forma deles.
FORA_DA_ESBELTEZ = {"peito", "quadril"}


def conferir_esbeltez(armature, malha) -> list:
	"""A malha exportada tem a espessura que o gerador diz que ela tem?

	**Mede pelo MESMO termo que mediu o original**: a caixa envolvente dos
	vertices de cada osso, com os dois lados menores contra o maior. Medir de um
	jeito la e de outro aqui produziria dois numeros que nao se comparam, e a
	comparacao seria decorativa.
	"""
	reprovas = []
	grupos = {g.index: g.name for g in malha.vertex_groups}
	caixas = {}
	mundo = malha.matrix_world
	# **A medida e no eixo do OSSO, nao no do mundo.** Um membro inclinado tem
	# caixa envolvente de mundo maior que a secao dele — o repouso em A fazia os
	# bracos medirem 4% mais grossos sem nada ter engordado. E e tambem o mesmo
	# termo com que o original foi medido: `m_BonesAABB` da Unity e local ao
	# osso. Medir de um jeito la e de outro aqui produziria dois numeros que nao
	# se comparam.
	para_o_osso = {}
	for osso in armature.data.bones:
		para_o_osso[osso.name] = osso.matrix_local.inverted()
	for vertice in malha.data.vertices:
		ponto = mundo @ vertice.co
		for peso in vertice.groups:
			nome = grupos.get(peso.group)
			if nome is None or nome not in para_o_osso:
				continue
			ponto = para_o_osso[nome] @ (mundo @ vertice.co)
			menor, maior = caixas.get(nome, (None, None))
			if menor is None:
				caixas[nome] = ([ponto.x, ponto.y, ponto.z],
				                [ponto.x, ponto.y, ponto.z])
			else:
				for eixo in range(3):
					menor[eixo] = min(menor[eixo], ponto[eixo])
					maior[eixo] = max(maior[eixo], ponto[eixo])

	print("[confere] -- esbeltez, espessura sobre comprimento do osso --")
	vistas = {}
	for grupo, (menor, maior) in sorted(caixas.items()):
		regiao = REGIAO_DO_GRUPO.get(grupo)
		if regiao is None or regiao in FORA_DA_ESBELTEZ:
			continue
		lados = sorted(maior[e] - menor[e] for e in range(3))
		if lados[2] <= 0.0:
			reprovas.append("o grupo '%s' nao tem volume" % grupo)
			continue
		vistas.setdefault(regiao, []).append(
			((lados[0] + lados[1]) * 0.5) / lados[2])

	# **Regiao declarada que a malha nao tem REPROVA.** Uma conferencia que
	# percorre o que achou aprova por ausencia: renomear um grupo desligaria o
	# julgamento dessa peca sem ruido nenhum.
	for regiao, esperada in sorted(ESBELTEZ_DECLARADA.items()):
		if regiao in FORA_DA_ESBELTEZ:
			continue
		if regiao not in vistas:
			reprovas.append(
				"a regiao '%s' e declarada em ESBELTEZ e nao tem vertice nenhum "
				"na malha — a conferencia dela ficou orfa" % regiao
			)
			continue
		medida = sum(vistas[regiao]) / len(vistas[regiao])
		folga = FOLGA_DA_CABECA if regiao == "cabeca" else FOLGA_DA_ESBELTEZ
		ok = abs(medida - esperada) <= folga
		print("[confere]   %-10s %.3f  (gerador %.3f +-%.3f)  %s" % (
			regiao, medida, esperada, folga, "ok" if ok else "FORA"))
		if not ok:
			reprovas.append(
				"a esbeltez de '%s' e %.3f e o gerador declara %.3f +-%.3f — a "
				"espessura da malha nao veio da medicao"
				% (regiao, medida, esperada, folga)
			)
	return reprovas


def conferir_proporcao(armature, malha) -> list:
	"""O corpo em repouso, contra `docs/11-direcao-de-arte.md`.

	Mede no ESQUELETO, que tem uma origem so. Caixa envolvente de malha nao
	serve para isto: no original cada malha tem espaco proprio e a razao
	cabeca/corpo sai 100% sem erro nenhum aparecer.
	"""
	reprovas = []
	if armature.animation_data is not None:
		armature.animation_data.action = None
	for osso in armature.pose.bones:
		osso.rotation_euler = (0.0, 0.0, 0.0)
		osso.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
		osso.location = (0.0, 0.0, 0.0)
	bpy.context.view_layer.update()

	locais = pontos(malha)
	topo = max(p.z for p in locais)
	base = min(p.z for p in locais)
	altura = topo - base
	if altura <= 0:
		return ["o corpo nao tem altura"]

	print("[confere] -- proporcao, contra a direcao de arte (altura %.3f) --" % altura)
	ossos = armature.data.bones
	for nome, (esperado, folga) in sorted(PROPORCAO_ESPERADA.items()):
		if nome not in ossos:
			reprovas.append("falta o osso '%s'" % nome)
			continue
		fracao = (ossos[nome].head_local.z - base) / altura
		ok = abs(fracao - esperado) <= folga
		print("[confere]   %-10s %.3f  (direcao %.3f +-%.3f)  %s" % (
			nome, fracao, esperado, folga, "ok" if ok else "FORA"))
		if not ok:
			reprovas.append(
				"'%s' esta em %.3f da altura, fora de %.3f +-%.3f"
				% (nome, fracao, esperado, folga)
			)

	def vao(a, b, rotulo, alvo):
		if a not in ossos or b not in ossos:
			reprovas.append("falta osso para medir %s" % rotulo)
			return None
		v = abs(ossos[a].head_local.x - ossos[b].head_local.x) / altura
		ok = abs(v - alvo[0]) <= alvo[1]
		print("[confere]   %-10s %.3f  (direcao %.3f +-%.3f)  %s" % (
			rotulo, v, alvo[0], alvo[1], "ok" if ok else "FORA"))
		if not ok:
			reprovas.append("%s em %.3f da altura, fora de %.3f +-%.3f"
			                % (rotulo, v, alvo[0], alvo[1]))
		return v

	ombros = vao("braco_D", "braco_E", "ombros", VAO_DOS_OMBROS)
	vao("coxa_D", "coxa_E", "quadris", VAO_DOS_QUADRIS)

	# Envergadura: os bracos ficam CAIDOS no repouso, entao ela nao da para ser
	# lida direto. Somar dois bracos e o vao entre eles da o mesmo numero, e e
	# esse numero que o original mede com os bracos abertos em T.
	# **Duas medidas de braco, e nao uma.** Junta a junta para no pulso;
	# ponta a ponta inclui a mao. Conferir so a segunda deixa o boneco acertar
	# o total com um antebraco comprido e nenhuma mao — foi o que aconteceu, e
	# o numero fechava.
	#
	# Os bracos ficam CAIDOS no repouso, entao nenhuma das duas da para ler
	# direto no eixo X. Somar o vao dos ombros com dois compimentos de braco da
	# o mesmo numero que o original mede com os bracos abertos em T.
	if ombros is None:
		return reprovas

	def alcance(rotulo, comprimento, alvo):
		"""`comprimento` e a distancia do OMBRO ate onde a medida termina.

		O original mede as duas com os bracos abertos em T; nos medimos o
		comprimento da corrente, que da o mesmo numero em qualquer repouso.
		"""
		if comprimento is None:
			reprovas.append("nao consegui medir %s" % rotulo)
			return
		v = ombros + 2.0 * comprimento / altura
		ok = abs(v - alvo[0]) <= alvo[1]
		print("[confere]   %-10s %.3f  (direcao %.3f +-%.3f)  %s" % (
			rotulo, v, alvo[0], alvo[1], "ok" if ok else "FORA"))
		if not ok:
			reprovas.append("%s em %.3f da altura, fora de %.3f +-%.3f"
			                % (rotulo, v, alvo[0], alvo[1]))

	if "mao_D" not in ossos:
		reprovas.append("o boneco nao tem osso de mao — sem ele o alcance do "
		                "braco e o da mao viram o mesmo numero")
		return reprovas
	ombro_direito = ossos["braco_D"].head_local
	alcance("vao maos",
	        (ossos["mao_D"].head_local - ombro_direito).length, VAO_DAS_MAOS)
	# **A ponta vem da MALHA, nao do osso.** O glTF nao guarda o comprimento de
	# um osso, so a posicao da junta, e o importador do Blender INVENTA a cauda.
	# Lendo `tail_local` a envergadura saia 0,857 onde a construcao da 0,895.
	alcance("envergad.",
	        _mais_longe_do_grupo(malha, "mao_D", ombro_direito), ENVERGADURA)
	return reprovas


def main() -> int:
	_autoteste_da_folga()
	raiz = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
	# O caminho pode vir da linha de comando, depois de `--`. E o que permite
	# conferir um arquivo AINDA NAO PUBLICADO: o gerador exporta para um nome
	# temporario, chama isto, e so entao poe o arquivo no lugar.
	glb = os.path.join(raiz, "arte", "personagem.glb")
	if "--" in sys.argv:
		resto = sys.argv[sys.argv.index("--") + 1:]
		if resto:
			glb = resto[0]
	if not os.path.exists(glb):
		print("[confere] falta %s" % glb)
		return 1

	armature, malha = importar(glb)
	if armature is None or malha is None:
		print("[confere] REPROVA: o .glb nao tem esqueleto com malha presa")
		return 1

	acoes = {}
	for acao in bpy.data.actions:
		acoes[acao.name.split("|")[-1]] = acao

	reprovas = []
	for nome in NOMES_EXIGIDOS:
		if nome not in acoes:
			reprovas.append("falta a animacao '%s'" % nome)
	if reprovas:
		for aviso in reprovas:
			print("[confere] REPROVA: %s" % aviso)
		return 1

	print("[confere] %d ossos, %d animacoes" % (len(armature.pose.bones), len(acoes)))
	reprovas.extend(conferir_proporcao(armature, malha))
	# **A esbeltez vem DEPOIS da proporcao**, que e quem poe o corpo em repouso.
	# Medir espessura sobre um corpo animado leria a pose, nao a peca.
	reprovas.extend(conferir_esbeltez(armature, malha))
	for nome in NOMES_EXIGIDOS:
		m = medir(armature, malha, acoes[nome])
		print(
			"[confere] %-9s %5.2f s  chao %+.3f..%+.3f  topo %.2f  movimento %.2f"
			"  %s fecha %.3f"
			% (nome, m["duracao"], m["chao_minimo"], m["chao_maximo"],
			   m["topo"], m["movimento"],
			   "ciclo  " if nome in EM_CICLO else "uma vez", m["fechamento"])
		)

		faixa = DURACAO_ESPERADA.get(nome)
		# **Arredondada as mesmas duas casas que o censo publica.** As faixas do
		# vocabulario universal sao medidas e arredondadas por
		# `censo_do_original.py`, e varias delas sao um PONTO — `cut` e 1,50 nos
		# 32 campeoes, `collect` e 0,67, `eat` e 6,57. Um clipe nosso tem um
		# numero INTEIRO de quadros a 30 fps, entao 0,67 s e 20 quadros = 0,6667
		# e nenhuma duracao possivel cai dentro de [0,67; 0,67]. Comparar
		# arredondado nao inventa folga nenhuma: usa a mesma precisao que a
		# medida tem.
		if faixa and not faixa[0] <= round(m["duracao"], 2) <= faixa[1]:
			reprovas.append(
				"'%s' dura %.2f s, fora da faixa %.2f--%.2f da direcao de arte"
				% (nome, m["duracao"], faixa[0], faixa[1])
			)

		# **Ciclo fecha.** O ultimo quadro tem que repetir o primeiro, senao o
		# corpo salta ao emendar a volta. Medido no vertice que mais se afasta
		# entre os dois quadros, no corpo ja deformado — que e o mesmo termo que
		# ja pega qualquer propriedade de pose sem enumerar nenhuma.
		#
		# O contrario nao reprova: um gesto de uma vez que comeca e termina na
		# mesma pose e legitimo, e os cinco gestos voltam ao repouso. O que
		# impede `EM_CICLO` de virar decoracao e `conferir_numeros.py`, que a
		# compara com o gerador, com o vocabulario do jogo e com a coluna
		# "Tipo" do §3.
		if nome in EM_CICLO and m["fechamento"] > FECHAMENTO_DO_CICLO:
			reprovas.append(
				"'%s' e ciclo e nao fecha: o ultimo quadro esta %.3f m do "
				"primeiro (maximo %.3f)"
				% (nome, m["fechamento"], FECHAMENTO_DO_CICLO)
			)

		if m["movimento"] < MOVIMENTO_MINIMO:
			reprovas.append(
				"'%s' quase nao se mexe (%.3f m, minimo %.2f)"
				% (nome, m["movimento"], MOVIMENTO_MINIMO)
			)
		if not ALTURA_ESPERADA[0] <= m["topo"] <= ALTURA_ESPERADA[1] and nome == "parado":
			reprovas.append(
				"parado tem %.2f m de altura, fora de %s" % (m["topo"], ALTURA_ESPERADA)
			)
		# Afundar no chao reprova em qualquer animacao — nao existe motivo para
		# o corpo entrar no piso.
		if m["chao_minimo"] < -TOLERANCIA_DO_CHAO:
			reprovas.append(
				"'%s' afunda %.3f m no chao" % (nome, -m["chao_minimo"])
			)
		if nome in NO_AR:
			if m["chao_maximo"] < NO_AR[nome]:
				reprovas.append(
					"'%s' deveria sair do chao %.2f m e so sobe %.3f"
					% (nome, NO_AR[nome], m["chao_maximo"])
				)
			# Mesmo saindo do chao, tem que VOLTAR: uma animacao que nunca
			# encosta e um boneco flutuando.
			if m["chao_minimo"] > TOLERANCIA_DO_CHAO:
				reprovas.append(
					"'%s' nunca encosta no chao (minimo %.3f)" % (nome, m["chao_minimo"])
				)
		elif m["chao_maximo"] > TOLERANCIA_DO_CHAO:
			reprovas.append(
				"'%s' tira os dois pes do chao (%.3f m)" % (nome, m["chao_maximo"])
			)

	for aviso in reprovas:
		print("[confere] REPROVA: %s" % aviso)
	if reprovas:
		return 1
	print("[confere] ok")
	return 0


if __name__ == "__main__":
	sys.exit(main())
