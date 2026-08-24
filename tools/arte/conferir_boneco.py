# -*- coding: utf-8 -*-
"""Confere `arte/boneco.glb` — o ARTEFATO, sem Blender e sem Godot.

Rodar:
    py tools/arte/conferir_boneco.py [caminho.glb]

## Por que ele lê o arquivo, e nao a cena do Blender

Porque foi olhando a cena que um defeito passou. As seis cores do boneco saiam
do exportador como o cinza padrao `[0.8, 0.8, 0.8, 1]`, todas iguais — e todo
screenshot do Blender mostrava o boneco colorido, porque `diffuse_color` pinta a
viewport enquanto quem vai para o `.glb` e o no do material. **Olhar a tela do
Blender nao e olhar o artefato**, e este arquivo existe para essa frase ter uma
maquina por tras.

## E por que ele nao usa o Blender

Uma conferencia que so roda na maquina que tem o Blender instalado nao e
conferencia — e o mesmo argumento de `tools/conferir_numeros.py`, que le o
`.glb` do outro boneco em Python puro pelo mesmo motivo. O cabecalho de um glTF
e JSON e a geometria e um bloco de floats; nada aqui precisa de engine.
"""

from __future__ import annotations

import io
import json
import math
import os
import struct
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PADRAO = os.path.join(RAIZ, "arte", "boneco.glb")

ALTURA = 1.75
FOLGA_DA_ALTURA = 0.01
## Quanto a escala acumulada da arvore de nos pode fugir de 1. E aperto de
## proposito: o exportador do Blender escreve 1,0 exato, e qualquer outra
## coisa e alguem escalando o no em vez da geometria.
ESCALA_TOLERADA = 0.001

## As cores que `gerar_boneco.py` declara. Repetidas aqui de proposito: uma
## conferencia que importa a constante do arquivo conferido aprova qualquer
## valor, porque compara o numero com ele mesmo.
CORES = {
	"pele": (0.85, 0.72, 0.60),
	"roupa": (0.35, 0.45, 0.62),
	"membro": (0.17, 0.21, 0.31),
	"mao": (0.90, 0.52, 0.22),
	"sapato": (0.55, 0.50, 0.44),
	"rosto": (0.10, 0.11, 0.14),
}
FOLGA_DA_COR = 0.02

## A faixa de esbeltez medida em 27 campeoes do original, por regiao.
## `(mediana, minimo, maximo)`. A mediana entra porque e dela que sai o CERCO
## da medicao — a janela de "ate onde ainda e esta peca". Usar o maximo da faixa
## abre a janela o bastante para o tronco entrar na conta do braco: medido
## assim, a esbeltez do braco deu 1,124, que e mais grosso que comprido.
FAIXA_DA_ESBELTEZ = {
	"braco": (0.758, 0.544, 0.941),
	"antebraco": (0.716, 0.413, 0.942),
	"mao": (0.752, 0.525, 0.951),
	"coxa": (0.575, 0.435, 0.936),
	"canela": (0.494, 0.349, 0.857),
	"pe": (0.672, 0.532, 0.823),
}
OSSO_DA_REGIAO = {
	"braco": "braco_D", "antebraco": "antebraco_D", "mao": "mao_D",
	"coxa": "coxa_D", "canela": "canela_D", "pe": "pe_D",
}
## Quantos vertices uma regiao precisa ter para a medida dela valer.
##
## Nao e zelo: com o cerco geometrico da versao anterior, a "mao" chegou a ser
## decidida por UM vertice e a conferencia aprovou. Medida decidida por punhado
## de pontos mede o acaso, nao a peca.
AMOSTRA_MINIMA = 12

## `nome: (duracao em segundos, e ciclo?)`. As duracoes sao a MEDIANA medida
## nos 1350 clipes do original — §4 de `docs/11` —, repetidas aqui de proposito:
## uma conferencia que importa a constante do arquivo conferido compara o numero
## consigo mesmo.
ANIMACOES_EXIGIDAS = {
	"parado": (1.33, True),
	"andando": (1.27, True),
	"morrer": (1.82, False),
}

## O nome do mesmo verbo no original, para a duracao poder ser conferida contra
## o instantaneo do censo em vez de so contra o gerador.
NOME_NO_ORIGINAL = {
	"parado": "idle",
	"andando": "walk",
	"morrer": "death",
}


def _ritmo_do_instantaneo() -> dict:
	"""`verbo do original -> mediana medida`, de `data/direcao-de-arte.json`.

	**A ordem la e `[minimo, mediana, maximo]`**, e nao `[mediana, min, max]`
	como nas outras secoes — `censo_do_original.py` monta a de animacao com
	`v[0], median(v), v[-1]`. Ler na ordem errada da uma duracao errada sem nada
	acusar, e este projeto ja leu.
	"""
	caminho = os.path.join(RAIZ, "data", "direcao-de-arte.json")
	try:
		dados = json.loads(io.open(caminho, encoding="utf-8").read())
	except (OSError, ValueError):
		return {}
	saida = {}
	for verbo, faixa in (dados.get("ritmo", {}).get("universais", {})).items():
		if isinstance(faixa, list) and len(faixa) == 3:
			saida[verbo] = faixa[1]
	return saida
FOLGA_DA_DURACAO = 0.05
## Quanto duas quaternioes podem diferir e ainda contar como a mesma pose.
FOLGA_DO_CICLO = 0.002

## A altura de cada junta, como fracao da altura total. Medida em 27 campeoes;
## §1 de `docs/11-direcao-de-arte.md`. Repetida aqui de proposito: conferencia
## que importa a constante do arquivo conferido compara o numero consigo mesmo.
## **A folga e de CADA medida, e nao a mais larga aplicada a todas.**
##
## O §9 manda: "cada uma e meia faixa medida, arredondada para cima em passos
## de 0,005". A versao anterior calculava meia faixa da regiao mais larga e
## repetia esse numero nas oito — o comentario ate citava a regra que estava
## violando, e dizia "a mais larga das seis" governando oito. O custo era
## medido: para o vao dos quadris a tolerancia (0,050) ficava MAIOR que a
## faixa inteira dos 27 campeoes (0,040), e um tornozelo em 0,140 — acima do
## maximo de 0,123 da populacao — publicava.
##
## `osso: (fracao da altura, folga)`. Faixas de `data/direcao-de-arte.json`,
## que guarda `[mediana, minimo, maximo]`.
PROPORCAO_EXIGIDA = {
	"pe_D": (0.093, 0.035),      # tornozelo, 0,057 a 0,123
	"canela_D": (0.283, 0.040),  # joelho,    0,253 a 0,328
	"coxa_D": (0.485, 0.050),    # quadril,   0,417 a 0,512
	"peito": (0.656, 0.045),     #            0,602 a 0,687
	"cabeca": (0.763, 0.045),    # pescoco,   0,708 a 0,795
	"braco_D": (0.725, 0.045),   # ombro,     0,672 a 0,753
}

## `rotulo: (osso, osso, fracao da altura, folga)`.
VAOS_EXIGIDOS = {
	"ombros": ("braco_D", "braco_E", 0.175, 0.040),   # 0,162 a 0,241
	"quadris": ("coxa_D", "coxa_E", 0.129, 0.020),    # 0,105 a 0,145
}

## **O COMPRIMENTO do braco, que nenhuma das duas acima mede.**
##
## As alturas de junta e os vaos deixavam passar um braco curto: medido pelo
## revisor, encurtar a envergadura de 0,895 para 0,760 — abaixo do minimo dos
## 27 campeoes — publicava com rc=0, porque o laco de convergencia constroi um
## corpo consistente com o numero errado e a esbeltez afina o raio junto.
##
## Sao DUAS medidas, e a separacao e a licao de uma reprovacao anterior: com
## so a envergadura, o boneco acertava o numero com antebraco esticado e
## nenhuma mao. `vao_das_maos` para no PULSO; `envergadura` vai ate a ponta.
##
## `rotulo: (fracao da altura, folga)`. Medido no publicado: 0,6294 e 0,8949.
COMPRIMENTOS_EXIGIDOS = {
	"vao_das_maos": (0.629, 0.060),   # 0,588 a 0,703
	"envergadura": (0.895, 0.080),    # 0,808 a 0,966
}

## Os quinze ossos que o corpo tem que ter, e que a camada de jogo nomeia.
OSSOS_EXIGIDOS = [
	"quadril", "peito", "cabeca",
	"braco_D", "antebraco_D", "mao_D", "braco_E", "antebraco_E", "mao_E",
	"coxa_D", "canela_D", "pe_D", "coxa_E", "canela_E", "pe_E",
]


def ler_glb(caminho: str) -> tuple:
	bruto = io.open(caminho, "rb").read()
	if bruto[:4] != b"glTF":
		raise ValueError("nao e um glTF binario")
	total = struct.unpack_from("<I", bruto, 8)[0]
	deslocamento, cabecalho, binario = 12, None, b""
	while deslocamento < total:
		tamanho, tipo = struct.unpack_from("<II", bruto, deslocamento)
		pedaco = bruto[deslocamento + 8:deslocamento + 8 + tamanho]
		if tipo == 0x4E4F534A:
			cabecalho = json.loads(pedaco.decode("utf-8"))
		else:
			binario = pedaco
		deslocamento += 8 + tamanho
	if cabecalho is None:
		raise ValueError("o glTF nao tem cabecalho JSON")
	return cabecalho, binario


def ler_vetores(g: dict, b: bytes, indice: int) -> list:
	acesso = g["accessors"][indice]
	vista = g["bufferViews"][acesso["bufferView"]]
	base = vista.get("byteOffset", 0) + acesso.get("byteOffset", 0)
	passo = vista.get("byteStride") or 12
	return [struct.unpack_from("<3f", b, base + i * passo)
	        for i in range(acesso["count"])]


def ler_indices(g: dict, b: bytes, indice: int) -> list:
	acesso = g["accessors"][indice]
	vista = g["bufferViews"][acesso["bufferView"]]
	base = vista.get("byteOffset", 0) + acesso.get("byteOffset", 0)
	formato = {5121: "<B", 5123: "<H", 5125: "<I"}[acesso["componentType"]]
	tamanho = struct.calcsize(formato)
	return [struct.unpack_from(formato, b, base + i * tamanho)[0]
	        for i in range(acesso["count"])]


def _quat_vezes_quat(a, b):
	ax, ay, az, aw = a
	bx, by, bz, bw = b
	return (aw * bx + ax * bw + ay * bz - az * by,
	        aw * by - ax * bz + ay * bw + az * bx,
	        aw * bz + ax * by - ay * bx + az * bw,
	        aw * bw - ax * bx - ay * by - az * bz)


def _quat_vezes_vetor(q, v):
	x, y, z, w = q
	# v' = v + 2w(q x v) + 2(q x (q x v))
	tx = 2.0 * (y * v[2] - z * v[1])
	ty = 2.0 * (z * v[0] - x * v[2])
	tz = 2.0 * (x * v[1] - y * v[0])
	return (v[0] + w * tx + (y * tz - z * ty),
	        v[1] + w * ty + (z * tx - x * tz),
	        v[2] + w * tz + (x * ty - y * tx))


def mundo_dos_nos(g: dict) -> dict:
	"""A posicao de MUNDO de cada no, compondo translacao, rotacao e escala.

	**A primeira versao somava so `translation`, e o erro foi medido: 12 dos 15
	ossos saiam do lugar, ate 1,76 m num corpo de 1,75 — o pe era colocado
	acima da cabeca.** Com isso, os seis segmentos que a esbeltez mede viravam
	raios verticais atravessando tronco e cabeca, e a "mao" era decidida por UM
	vertice. Trocar `braco_D` por `coxa_D` no arquivo passava sem reprovar.

	Os nos de osso do glTF exportado pelo Blender TEM rotacao — o `braco_D` sai
	com um quaternio de meia volta —, e ignora-la e ler dado local como se fosse
	mundo. E o mesmo defeito que o gerador ja tinha aprendido em espaco do
	Blender, repetido aqui em espaco glTF.
	"""
	pai = {}
	for indice, no in enumerate(g.get("nodes", [])):
		for filho in no.get("children", []) or []:
			pai[filho] = indice

	cache = {}

	def transformacao(indice):
		"""`(posicao, rotacao, escala)` do no, no mundo."""
		if indice in cache:
			return cache[indice]
		no = g["nodes"][indice]
		t = tuple(no.get("translation") or (0.0, 0.0, 0.0))
		r = tuple(no.get("rotation") or (0.0, 0.0, 0.0, 1.0))
		e = tuple(no.get("scale") or (1.0, 1.0, 1.0))
		acima = pai.get(indice)
		if acima is None:
			cache[indice] = (t, r, e)
			return cache[indice]
		pt, pr, pe = transformacao(acima)
		local = tuple(t[k] * pe[k] for k in range(3))
		girado = _quat_vezes_vetor(pr, local)
		cache[indice] = (tuple(pt[k] + girado[k] for k in range(3)),
		                 _quat_vezes_quat(pr, r),
		                 tuple(pe[k] * e[k] for k in range(3)))
		return cache[indice]

	return {g["nodes"][i].get("name", "?"): transformacao(i)[0]
	        for i in range(len(g.get("nodes", [])))}


def escala_das_raizes(g: dict) -> float:
	"""A escala acumulada MAIS LONGE de 1 em toda a arvore.

	**Existe porque escala de no e invisivel para quem so olha vertice.** Um
	`scale = 1.4` na raiz do esqueleto entrega um personagem de 2,45 m na
	engine, e a conferencia de altura, que le posicao local de vertice,
	continuava reportando 1,75 e aprovando.

	**E ela era de UMA VIA SO.** A primeira versao fazia
	`acumulada = max(acumulada, abs(valor))` partindo de 1.0 — um maximo com
	piso em 1, nao um produto. Escala MENOR que 1 nunca podia ser vista, e a
	comparacao `abs(escala - 1.0) > ESCALA_TOLERADA` so disparava para cima.
	Medido pelo revisor adversarial, injetando no no raiz do `.glb`:

	    scale=0.99  ->  1,731 m na engine  ->  PASSAVA
	    scale=0.97  ->  1,696 m na engine  ->  PASSAVA
	    scale=1.01  ->                     ->  pego

	Cinco centimetros de erro, cinco vezes a folga de altura, com "o boneco
	passou" impresso. E a prova que eu tinha gravado no commit era `scale=1.4`
	— a unica direcao que funcionava.

	Hoje e produto de verdade, e o que volta e o extremo mais distante de 1 nos
	dois sentidos.
	"""
	pai = {}
	for indice, no in enumerate(g.get("nodes", [])):
		for filho in no.get("children", []) or []:
			pai[filho] = indice
	pior = 1.0
	for indice in range(len(g.get("nodes", []))):
		atual = indice
		acumulada = [1.0, 1.0, 1.0]
		while atual is not None:
			escala = g["nodes"][atual].get("scale") or (1.0, 1.0, 1.0)
			for eixo in range(3):
				acumulada[eixo] *= abs(escala[eixo])
			atual = pai.get(atual)
		for valor in acumulada:
			if abs(valor - 1.0) > abs(pior - 1.0):
				pior = valor
	return pior


def ler_escalares(g: dict, b: bytes, indice: int) -> list:
	"""Um acessor de floats simples — os tempos de um amostrador."""
	acesso = g["accessors"][indice]
	vista = g["bufferViews"][acesso["bufferView"]]
	base = vista.get("byteOffset", 0) + acesso.get("byteOffset", 0)
	passo = vista.get("byteStride") or 4
	return [struct.unpack_from("<f", b, base + i * passo)[0]
	        for i in range(acesso["count"])]


## Quantos floats tem cada tipo de saida de amostrador.
LARGURA_DO_TIPO = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def ler_saida(g: dict, b: bytes, indice: int) -> list:
	"""A saida de um amostrador, seja rotacao, translacao ou escala.

	**Le qualquer tipo, e isso nao e generalidade gratuita.** A versao anterior
	so lia `VEC4` e devolvia vazio para o resto; quem chamava tratava vazio como
	"nada a conferir", e um ciclo de translacao que saltava na emenda passava.
	"""
	acesso = g["accessors"][indice]
	largura = LARGURA_DO_TIPO.get(acesso.get("type"))
	if largura is None:
		return []
	vista = g["bufferViews"][acesso["bufferView"]]
	base = vista.get("byteOffset", 0) + acesso.get("byteOffset", 0)
	passo = vista.get("byteStride") or 4 * largura
	formato = "<%df" % largura
	return [struct.unpack_from(formato, b, base + i * passo)
	        for i in range(acesso["count"])]


def ler_juntas(g: dict, b: bytes, indice: int) -> list:
	"""`JOINTS_0` — os quatro ossos que influenciam cada vertice."""
	acesso = g["accessors"][indice]
	vista = g["bufferViews"][acesso["bufferView"]]
	base = vista.get("byteOffset", 0) + acesso.get("byteOffset", 0)
	formato = {5121: "<4B", 5123: "<4H"}[acesso["componentType"]]
	# **O passo padrao e o TAMANHO do elemento, e nao um literal.** Escrito
	# `byteStride or 8`, um buffer de bytes justapostos e lido de oito em oito e
	# os indices saem embaralhados — defeito ja pago neste projeto.
	tamanho = struct.calcsize(formato)
	passo = vista.get("byteStride") or tamanho
	return [struct.unpack_from(formato, b, base + i * passo)
	        for i in range(acesso["count"])]


def ler_pesos(g: dict, b: bytes, indice: int) -> list:
	acesso = g["accessors"][indice]
	vista = g["bufferViews"][acesso["bufferView"]]
	base = vista.get("byteOffset", 0) + acesso.get("byteOffset", 0)
	passo = vista.get("byteStride") or 16
	return [struct.unpack_from("<4f", b, base + i * passo)
	        for i in range(acesso["count"])]


def _menos(a, b):
	return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _norma(v):
	return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def _cruza(t1, t2) -> bool:
	"""Dois triangulos se atravessam? Por aresta contra triangulo.

	Um cruzamento real entre dois triangulos que nao se tocam nas bordas sempre
	tem pelo menos uma ARESTA de um furando o outro. Coplanares sobrepostos
	escapam, e a ausencia esta declarada: numa casca gerada por subdivisao eles
	nao aparecem, e cobrir esse caso custaria dez vezes mais codigo.
	"""
	for a, b in ((t1, t2), (t2, t1)):
		for i in range(3):
			if _aresta_fura(a[i], a[(i + 1) % 3], b):
				return True
	return False


def _aresta_fura(p, q, tri) -> bool:
	a, b, c = tri
	e1 = _menos(b, a)
	e2 = _menos(c, a)
	direcao = _menos(q, p)
	h = (direcao[1] * e2[2] - direcao[2] * e2[1],
	     direcao[2] * e2[0] - direcao[0] * e2[2],
	     direcao[0] * e2[1] - direcao[1] * e2[0])
	det = sum(e1[i] * h[i] for i in range(3))
	if abs(det) < 1e-12:
		return False
	inverso = 1.0 / det
	s = _menos(p, a)
	u = inverso * sum(s[i] * h[i] for i in range(3))
	if u < 0.0 or u > 1.0:
		return False
	q1 = (s[1] * e1[2] - s[2] * e1[1],
	      s[2] * e1[0] - s[0] * e1[2],
	      s[0] * e1[1] - s[1] * e1[0])
	v = inverso * sum(direcao[i] * q1[i] for i in range(3))
	if v < 0.0 or u + v > 1.0:
		return False
	t = inverso * sum(e2[i] * q1[i] for i in range(3))
	# **As bordas ficam de fora, com folga.** Numa malha costurada, triangulos
	# vizinhos se tocam exatamente na aresta, e sem a folga cada costura do
	# corpo seria contada como auto-intersecao.
	return 1e-9 < t < 1.0 - 1e-9


## Quantos pares de auto-intersecao sao TOLERADOS, e por que ha tolerancia.
##
## **Zero seria o certo, e zero custa caro demais pelo que entrega.** O Skin
## Modifier costura um casco em cada juncao, e na axila — onde o braco sai do
## peito num angulo raso — os cascos se atravessam. Medido, 78 pares, sempre no
## mesmo lugar, sempre em repouso.
##
## Tres tentativas de fechar mexiam na COSTURA: estreitar o peito (36 para 40
## pares), acrescentar clavicula (85, e mudou de lugar), e voxelizar. A
## voxelizacao FECHA — e estraga a pintura, porque devolve triangulos sem
## relacao com a estrutura do corpo. Comparadas as duas na tela, a versao
## voxelizada sai com a viseira em farrapo.
##
## **A quarta tentativa nao mexeu na costura, e foi a que funcionou:** abrir
## o braco de 20 para 28 graus levou 78 pares a 10. Ver `ABERTURA_DO_BRACO`
## em `gerar_boneco.py`, que e onde a medicao esta.
##
## A auto-intersecao fica dentro da malha e nao aparece; a pintura rasgada
## aparece. Entao ela e aceita, com TETO: o numero e impresso a cada execucao e
## crescer reprova. Defeito conhecido e limitado e diferente de defeito
## ignorado.
TETO_DE_AUTOINTERSECAO = 10

## Lado da celula da grade espacial, em metros. So triangulos que caem na mesma
## celula sao comparados — sem isso seriam 2400 x 2400 pares.
CELULA = 0.06


def auto_intersecoes(pontos: list, triangulos: list) -> list:
	"""Pares de triangulos que se atravessam sem compartilhar vertice.

	**Casca unica NAO impede isto, e a diferenca custou uma reescrita inteira.**
	O boneco anterior era um solido por osso e as pecas se atravessavam; este e
	uma superficie so — e uma superficie so pode atravessar a si mesma. Afirmar
	"nao ha pecas, entao nao ha peca dentro de peca" e um silogismo que nao
	fecha, e a malha o desmentiu na axila, em repouso.

	E o defeito que a reescrita existe para resolver. Sem esta funcao, ninguem
	no projeto o mede.
	"""
	grade = {}
	caixas = []
	# Os vertices de cada triangulo, congelados uma vez. A versao anterior
	# fazia `set(triangulos[a]) & set(triangulos[b])` DENTRO do laco de pares:
	# dois conjuntos construidos por par, milhoes de vezes.
	conjuntos = []
	for indice, tri in enumerate(triangulos):
		pts = [pontos[i] for i in tri]
		menor = tuple(min(p[k] for p in pts) for k in range(3))
		maior = tuple(max(p[k] for p in pts) for k in range(3))
		caixas.append((menor, maior, pts))
		conjuntos.append(frozenset(tri))
		for cx in range(int(menor[0] // CELULA), int(maior[0] // CELULA) + 1):
			for cy in range(int(menor[1] // CELULA), int(maior[1] // CELULA) + 1):
				for cz in range(int(menor[2] // CELULA), int(maior[2] // CELULA) + 1):
					grade.setdefault((cx, cy, cz), []).append(indice)

	# **Este laco roda 81 vezes por geracao** — 80 quadros animados mais o
	# repouso —, e por um commit o custo foi estrutural: a geracao chegou a
	# 3m35s e a suite de mutacao (24 geracoes) estourou o tempo do executor e
	# morreu no meio, deixando o repositorio MUTADO. O que segue nao muda o
	# resultado, so o custo; o teste de regressao sao os numeros publicados,
	# 78 pares em repouso e 79 no quadro 5 de `andando`.
	#
	# Medido depois: `auto_intersecoes` responde em 0,28 s. Os tres minutos
	# eram um segundo `evaluated_get` por quadro, nao esta funcao. Hoje a
	# geracao inteira custa 33 s.
	largura = len(triangulos)
	vistos = set()
	achados = []
	for celula in grade.values():
		quantos = len(celula)
		for i in range(quantos):
			a = celula[i]
			ma, xa, pa = caixas[a]
			ca = conjuntos[a]
			base = a * largura
			for j in range(i + 1, quantos):
				b = celula[j]
				# Chave inteira em vez de tupla: o par so precisa ser visto uma
				# vez, e um triangulo grande cai em varias celulas.
				chave = base + b
				if chave in vistos:
					continue
				vistos.add(chave)
				if not ca.isdisjoint(conjuntos[b]):
					continue
				mb, xb, _pb = caixas[b]
				# Desenrolado de proposito: `any(... for k in range(3))` cria um
				# gerador por par, e sao milhoes de pares.
				if (xa[0] < mb[0] or xb[0] < ma[0]
						or xa[1] < mb[1] or xb[1] < ma[1]
						or xa[2] < mb[2] or xb[2] < ma[2]):
					continue
				if _cruza(pa, caixas[b][2]):
					achados.append((a, b))
	return achados


def conferir(caminho: str) -> list:
	falhas = []
	g, b = ler_glb(caminho)

	# ------------------------------------------------------------ geometria
	pontos, triangulos = [], []
	por_material = {}
	nomes_de_material = [m.get("name", "?") for m in g.get("materials", [])]
	for malha in g.get("meshes", []):
		for primitiva in malha.get("primitives", []):
			deslocamento = len(pontos)
			locais = ler_vetores(g, b, primitiva["attributes"]["POSITION"])
			pontos.extend(locais)
			if "indices" in primitiva:
				crus = ler_indices(g, b, primitiva["indices"])
				triangulos.extend(
					tuple(deslocamento + crus[i + k] for k in range(3))
					for i in range(0, len(crus) - 2, 3))
			indice = primitiva.get("material")
			if indice is not None and indice < len(nomes_de_material):
				por_material.setdefault(nomes_de_material[indice], []).extend(locais)

	if not pontos:
		return ["o `.glb` nao tem geometria nenhuma"]

	# **No glTF o eixo de cima e Y**, e a exportacao converte do Z do Blender.
	alturas = [p[1] for p in pontos]
	# **A escala de no entra ANTES da altura**, porque e ela que decide se o
	# numero medido nos vertices vale alguma coisa.
	#
	# `escala_das_raizes` existia e NAO ERA CHAMADA por ninguem — uma defesa
	# cuja docstring afirmava uma protecao que o arquivo nao executava. Achado
	# do revisor, e e a licao 9 do projeto na forma mais curta possivel: a
	# camada que nenhuma ferramenta roda e onde o defeito mora. Que o caso
	# fosse pego por acidente pela proporcao — que divide posicao de no
	# (escalada) por altura de malha (nao escalada) — nao conta: bastava a
	# proporcao mudar de referencial para a classe reabrir sem ruido.
	escala = escala_das_raizes(g)
	if abs(escala - 1.0) > ESCALA_TOLERADA:
		falhas.append(
			"a arvore de nos tem escala acumulada de %.4f — o `.glb` entrega "
			"um corpo de %.3f m na engine, e a altura medida nos vertices "
			"(%.3f m) nao ve isso" % (escala, (max(alturas) - min(alturas)) *
			                          escala, max(alturas) - min(alturas)))

	altura = max(alturas) - min(alturas)
	if abs(altura - ALTURA) > FOLGA_DA_ALTURA:
		falhas.append("o corpo tem %.3f m e a direcao manda %.2f"
		              % (altura, ALTURA))
	if abs(min(alturas)) > FOLGA_DA_ALTURA:
		falhas.append("o pe nao encosta no chao: o ponto mais baixo esta em %.3f"
		              % min(alturas))

	# ----------------------------------------------------------- as cores
	#
	# **Esta e a conferencia que nasceu de um defeito real.** As seis cores ja
	# sairam identicas, no cinza padrao do exportador, porque o material foi
	# escrito sem no. Na viewport do Blender aparecia tudo colorido.
	materiais = {m.get("name"): m for m in g.get("materials", [])}
	for nome, cor in sorted(CORES.items()):
		if nome not in materiais:
			falhas.append("falta o material `%s` no `.glb`" % nome)
			continue
		saiu = (materiais[nome].get("pbrMetallicRoughness", {})
		        .get("baseColorFactor"))
		if saiu is None:
			falhas.append("o material `%s` saiu sem cor" % nome)
			continue
		if max(abs(saiu[i] - cor[i]) for i in range(3)) > FOLGA_DA_COR:
			falhas.append(
				"o material `%s` saiu %s e o gerador declara %s"
				% (nome, [round(v, 3) for v in saiu[:3]], list(cor)))
	distintas = {tuple(round(v, 3) for v in m.get("pbrMetallicRoughness", {})
	                   .get("baseColorFactor", [0, 0, 0, 1])[:3])
	             for m in g.get("materials", [])}
	if len(g.get("materials", [])) > 1 and len(distintas) == 1:
		falhas.append(
			"as %d cores do `.glb` sao TODAS iguais (%s) — o material foi "
			"exportado sem no, e a viewport do Blender mente sobre isso"
			% (len(g["materials"]), distintas.pop()))

	# ------------------------------------------------------------- o rosto
	#
	# A frente de um asset glTF e +Z, e e a Godot que discorda; a conversao
	# mora em `Boneco.giro_do_modelo`. Aqui o que importa e que o rosto esteja
	# de um lado so, e nao espalhado pela cabeca.
	rosto = por_material.get("rosto") or []
	if not rosto:
		falhas.append("o `.glb` nao tem faces com o material `rosto` — sem ele "
		              "o corpo nao tem frente")
	else:
		corpo = [p for p in pontos]
		centro_z = sum(p[2] for p in corpo) / len(corpo)
		frente = sum(p[2] for p in rosto) / len(rosto)
		if frente - centro_z < 0.05:
			falhas.append(
				"o rosto esta a %.3f m do centro do corpo em Z; ele tem que "
				"ficar na FRENTE (+Z no glTF), e abaixo de 5 cm ele nao "
				"distingue frente de costas" % (frente - centro_z))

	# ------------------------------------------------- vertices e casca
	usados = set()
	for tri in triangulos:
		usados.update(tri)
	soltos = len(pontos) - len(usados)
	if soltos > 0:
		falhas.append("%d vertices soltos, sem triangulo nenhum — lixo do "
		              "gerador que atravessa o pipeline" % soltos)

	# ------------------------------------------------- a casca se atravessa?
	cruzados = auto_intersecoes(pontos, triangulos)
	if cruzados:
		zs = [pontos[triangulos[a][0]][1] for a, _ in cruzados]
		print("[confere] a casca se atravessa em %d pares (teto %d), "
		      "entre y %.3f e %.3f"
		      % (len(cruzados), TETO_DE_AUTOINTERSECAO, min(zs), max(zs)))
	if len(cruzados) > TETO_DE_AUTOINTERSECAO:
		falhas.append(
			"a casca se atravessa em %d pares de faces e o teto conhecido e %d "
			"— o defeito da axila cresceu ou apareceu em outro lugar"
			% (len(cruzados), TETO_DE_AUTOINTERSECAO))

	# ------------------------------------------------------- as animacoes
	#
	# Duracao e fechamento de ciclo sao lidos do ARQUIVO, que e onde o jogo vai
	# le-los. Amplitude e pe no chao precisam avaliar a pose deformada, e quem
	# faz isso e o gerador, dentro do Blender — a divisao esta declarada porque
	# uma conferencia que so existe de um lado e uma que ninguem confere.
	animacoes = {a.get("name"): a for a in g.get("animations", [])}
	# **Nos DOIS sentidos.** Animacao no arquivo que nao esta na lista entra sem
	# conferencia nenhuma: medido, um `andando` de 4,20 s — contra uma faixa de
	# 1,07 a 1,60 — com o ciclo saltando 22 graus na emenda foi publicado sem um
	# aviso, so por nao ter sido lembrado aqui. Conferencia que percorre o que
	# ela conhece aprova por ausencia.
	sobrando = sorted(set(animacoes) - set(ANIMACOES_EXIGIDAS))
	if sobrando:
		falhas.append(
			"o `.glb` tem animacao que ninguem confere: %s — acrescente em "
			"`ANIMACOES_EXIGIDAS` com a duracao medida" % ", ".join(sobrando))
	medido = _ritmo_do_instantaneo()
	for nome, (duracao, ciclo) in sorted(ANIMACOES_EXIGIDAS.items()):
		# **A duracao declarada tem que bater com o censo, e nao so com o
		# gerador.** Ela esta copiada a mao em dois arquivos; sem esta linha, os
		# dois podem ficar para tras juntos e continuar verdes.
		do_original = medido.get(NOME_NO_ORIGINAL.get(nome, ""))
		if do_original is not None and abs(do_original - duracao) > 0.005:
			falhas.append(
				"`%s` esta declarada com %.2f s e o censo mediu %.2f no "
				"original — `data/direcao-de-arte.json` e a origem"
				% (nome, duracao, do_original))
		if nome not in animacoes:
			falhas.append("falta a animacao `%s` no `.glb`" % nome)
			continue
		amostradores = animacoes[nome].get("samplers", [])
		if not amostradores:
			falhas.append("a animacao `%s` nao tem amostrador nenhum" % nome)
			continue
		fim = 0.0
		fecha = True
		for amostrador in amostradores:
			tempos = ler_escalares(g, b, amostrador["input"])
			if tempos:
				fim = max(fim, tempos[-1])
			if not ciclo:
				continue
			# **Rotacao E translacao.** A primeira versao so lia VEC4 e devolvia
			# lista vazia para o resto, deixando `fecha` intacto: medido, um
			# `quadril.location` saltando 10 cm na emenda foi publicado sem uma
			# palavra. E translacao nao e hipotetica — e ela que carrega o quique
			# da caminhada e o voo da corrida, que sao os proximos clipes.
			valores = ler_saida(g, b, amostrador["output"])
			if len(valores) >= 2:
				# O ultimo quadro tem que repetir o primeiro, senao o ciclo
				# salta ao emendar a volta. Item 3 do §10 de `docs/11`.
				if max(abs(valores[0][k] - valores[-1][k])
				       for k in range(len(valores[0]))) > FOLGA_DO_CICLO:
					fecha = False
		if abs(fim - duracao) > FOLGA_DA_DURACAO:
			falhas.append(
				"a animacao `%s` dura %.3f s e a direcao de arte mede %.2f — "
				"a mediana dos 1350 clipes do original"
				% (nome, fim, duracao))
		if ciclo and not fecha:
			falhas.append(
				"a animacao `%s` e ciclo e NAO fecha: o ultimo quadro nao "
				"repete o primeiro, entao ela salta ao emendar a volta" % nome)

	# --------------------------------------------------------- o esqueleto
	nos = mundo_dos_nos(g)
	faltando = [o for o in OSSOS_EXIGIDOS if o not in nos]
	if faltando:
		falhas.append("faltam ossos no `.glb`: %s" % ", ".join(faltando))

	# ------------------------------------------------------- a proporcao
	#
	# **Isto nao existia, e a falta foi provada por mutacao.** Encurtar a
	# envergadura de 0,895 para 0,760 no gerador saia publicado: o laco de
	# convergencia simplesmente construia um corpo consistente com o numero
	# errado, e nenhuma conferencia do ARTEFATO olhava proporcao. O conferidor
	# do outro boneco olha; este nao olhava, e ele e o que julga o `.glb`.
	#
	# As alturas sao fracao da altura total, com o pe em zero. A cabeca de cada
	# osso e a junta: `pe_D` e o tornozelo, `canela_D` o joelho, `coxa_D` o
	# quadril, `braco_D` o ombro.
	for osso, (esperado, folga) in sorted(PROPORCAO_EXIGIDA.items()):
		if osso not in nos:
			falhas.append("falta o osso `%s` para medir a proporcao" % osso)
			continue
		fracao = nos[osso][1] / altura
		if abs(fracao - esperado) > folga:
			falhas.append(
				"`%s` esta em %.3f da altura e a direcao de arte mede %.3f "
				"(folga %.3f)" % (osso, fracao, esperado, folga))
	for rotulo, (a, b_, esperado, folga) in sorted(VAOS_EXIGIDOS.items()):
		if a not in nos or b_ not in nos:
			falhas.append("faltam ossos para medir o vao `%s`" % rotulo)
			continue
		vao = abs(nos[a][0] - nos[b_][0]) / altura
		if abs(vao - esperado) > folga:
			falhas.append(
				"o vao `%s` esta em %.3f da altura e a direcao de arte mede "
				"%.3f (folga %.3f)" % (rotulo, vao, esperado, folga))

	# ------------------------------------------------------- a espessura
	#
	# **Medida pelos PESOS do arquivo, e nao por uma janela geometrica.**
	#
	# A versao anterior decidia "isto ainda e o braco?" por um cerco em volta do
	# eixo do osso, e o cerco tinha dois defeitos que se somavam. Ele saia da
	# MEDIANA, entao o maior valor que a conferencia conseguia reportar era
	# `mediana x 1,2` — abaixo do maximo da faixa em NOVE de nove regioes. A
	# metade "gordo demais" da comparacao estava morta: medido, uma coxa
	# engordada 2,2 vezes, com esbeltez 3,183 contra um maximo de 0,936,
	# PASSAVA.
	#
	# O `.glb` ja diz de quem e cada vertice, em `JOINTS_0` e `WEIGHTS_0`. Usar
	# isso nao tem janela para calibrar, nao tem teto, e nao pode confundir a
	# coxa com o tronco.
	dono = {}
	for regiao, osso in OSSO_DA_REGIAO.items():
		dono[osso] = regiao
	por_osso = {}
	juntas_do_couro = []
	for pele in g.get("skins", []):
		juntas_do_couro = [g["nodes"][i].get("name", "?")
		                   for i in pele.get("joints", [])]
	if not juntas_do_couro:
		falhas.append("o `.glb` nao tem esqueleto — sem `skin` nao da para "
		              "saber de que osso e cada vertice")
	for malha in g.get("meshes", []):
		for primitiva in malha.get("primitives", []):
			atributos = primitiva.get("attributes", {})
			if "JOINTS_0" not in atributos or "WEIGHTS_0" not in atributos:
				continue
			locais = ler_vetores(g, b, atributos["POSITION"])
			js = ler_juntas(g, b, atributos["JOINTS_0"])
			ws = ler_pesos(g, b, atributos["WEIGHTS_0"])
			for k, ponto in enumerate(locais):
				melhor, peso = None, 0.0
				for slot in range(4):
					if ws[k][slot] > peso:
						peso, melhor = ws[k][slot], js[k][slot]
				if melhor is None or melhor >= len(juntas_do_couro):
					continue
				por_osso.setdefault(juntas_do_couro[melhor], []).append(ponto)

	# ------------------------------------- o COMPRIMENTO do braco
	#
	# Medido pelo mesmo caminho que `docs/11` usa: do ombro ate o pulso sai o
	# vao das maos, e do ombro ate a PONTA da mao sai a envergadura, os dois
	# vezes dois mais o vao dos ombros. A ponta nao e osso — e o vertice da mao
	# mais distante do ombro, e por isso esta conferencia vive aqui embaixo,
	# depois de `por_osso`.
	#
	# **Os DOIS lados, um a um.** Um braco curto so de um lado e assimetria que
	# nenhuma outra conferencia deste arquivo ve.
	vao_dos_ombros = None
	if "braco_D" in nos and "braco_E" in nos:
		vao_dos_ombros = abs(nos["braco_D"][0] - nos["braco_E"][0])
	for lado in ("D", "E"):
		ombro, pulso = nos.get("braco_" + lado), nos.get("mao_" + lado)
		if ombro is None or pulso is None or vao_dos_ombros is None:
			falhas.append("faltam ossos para medir o comprimento do braco %s"
			              % lado)
			continue
		maos = por_osso.get("mao_" + lado) or []
		if len(maos) < AMOSTRA_MINIMA:
			falhas.append(
				"so %d vertices sao governados por `mao_%s` (minimo %d) — a "
				"ponta do braco seria decidida pelo acaso"
				% (len(maos), lado, AMOSTRA_MINIMA))
			continue
		medidos = {
			"vao_das_maos": _norma(_menos(pulso, ombro)),
			"envergadura": max(_norma(_menos(v, ombro)) for v in maos),
		}
		for rotulo, (esperado, folga) in sorted(COMPRIMENTOS_EXIGIDOS.items()):
			fracao = (2.0 * medidos[rotulo] + vao_dos_ombros) / altura
			if abs(fracao - esperado) > folga:
				falhas.append(
					"do lado %s a `%s` esta em %.3f da altura e a direcao de "
					"arte mede %.3f (folga %.3f)"
					% (lado, rotulo, fracao, esperado, folga))

	for regiao, (mediana, minimo, maximo) in sorted(FAIXA_DA_ESBELTEZ.items()):
		osso = OSSO_DA_REGIAO[regiao]
		filho = _cauda_do_osso(g, nos, osso)
		if osso not in nos or filho is None:
			falhas.append("nao achei o osso `%s` para medir a esbeltez" % osso)
			continue
		meus = por_osso.get(osso) or []
		# **Poucos vertices REPROVA.** Uma medida decidida por um punhado de
		# pontos nao mede a peca; ela mede o acaso de quais pontos sobraram. Na
		# versao com cerco, a "mao" foi decidida por UM vertice e a conferencia
		# aprovou sem piscar.
		if len(meus) < AMOSTRA_MINIMA:
			falhas.append(
				"so %d vertices sao governados por `%s` (minimo %d) — a "
				"esbeltez dele seria decidida pelo acaso"
				% (len(meus), osso, AMOSTRA_MINIMA))
			continue
		cabeca, cauda = nos[osso], filho
		eixo = _menos(cauda, cabeca)
		comprimento = _norma(eixo)
		if comprimento <= 0.0:
			falhas.append("o osso `%s` nao tem comprimento" % osso)
			continue
		direcao = tuple(v / comprimento for v in eixo)
		distancias = []
		for ponto in meus:
			relativo = _menos(ponto, cabeca)
			ao_longo = sum(relativo[i] * direcao[i] for i in range(3)) / comprimento
			if not 0.3 <= ao_longo <= 0.7:
				continue
			distancias.append(_norma(tuple(
				relativo[i] - direcao[i] * ao_longo * comprimento
				for i in range(3))))
		if len(distancias) < AMOSTRA_MINIMA:
			falhas.append(
				"so %d vertices de `%s` caem no meio do osso (minimo %d)"
				% (len(distancias), osso, AMOSTRA_MINIMA))
			continue
		esbeltez = 2.0 * max(distancias) / comprimento
		if not minimo <= esbeltez <= maximo:
			falhas.append(
				"a esbeltez de `%s` e %.3f, fora da faixa medida %.3f a %.3f"
				% (regiao, esbeltez, minimo, maximo))
	return falhas


def _cauda_do_osso(g: dict, nos: dict, nome: str):
	"""A posicao do filho do osso — que e onde a cauda dele cai.

	O glTF nao guarda cauda de osso; ele guarda uma arvore de nos. A cauda de um
	osso e a cabeca do filho dele, e para os ossos de ponta — mao e pe — o
	exportador cria um no `_end`.
	"""
	indice = None
	for i, no in enumerate(g.get("nodes", [])):
		if no.get("name") == nome:
			indice = i
			break
	if indice is None:
		return None
	filhos = g["nodes"][indice].get("children") or []
	if not filhos:
		return None
	mundo = mundo_dos_nos(g)
	return mundo.get(g["nodes"][filhos[0]].get("name", "?"))


def main() -> int:
	caminho = sys.argv[1] if len(sys.argv) > 1 else PADRAO
	if not os.path.exists(caminho):
		print("[confere] nao achei %s" % caminho)
		return 1
	try:
		falhas = conferir(caminho)
	except (OSError, ValueError, KeyError, struct.error) as erro:
		print("[confere] nao consegui ler o boneco: %s" % erro)
		return 1
	if falhas:
		print("[confere] %d REPROVA(S):" % len(falhas))
		for falha in falhas:
			print("[confere]   - %s" % falha)
		return 1
	print("[confere] o boneco passou: %s" % os.path.basename(caminho))
	return 0


if __name__ == "__main__":
	sys.exit(main())
