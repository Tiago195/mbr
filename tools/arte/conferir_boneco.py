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
CERCO_DA_PECA = 1.2

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


def mundo_dos_nos(g: dict) -> dict:
	"""A posicao de cada no, ja composta pela cadeia de pais."""
	pai = {}
	for indice, no in enumerate(g.get("nodes", [])):
		for filho in no.get("children", []) or []:
			pai[filho] = indice

	def posicao(indice):
		x, y, z = 0.0, 0.0, 0.0
		atual = indice
		while atual is not None:
			t = g["nodes"][atual].get("translation") or [0.0, 0.0, 0.0]
			x, y, z = x + t[0], y + t[1], z + t[2]
			atual = pai.get(atual)
		return (x, y, z)

	return {g["nodes"][i].get("name", "?"): posicao(i)
	        for i in range(len(g.get("nodes", [])))}


def _menos(a, b):
	return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _norma(v):
	return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


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

	# --------------------------------------------------------- o esqueleto
	nos = mundo_dos_nos(g)
	faltando = [o for o in OSSOS_EXIGIDOS if o not in nos]
	if faltando:
		falhas.append("faltam ossos no `.glb`: %s" % ", ".join(faltando))

	# ------------------------------------------------------- a espessura
	#
	# Medida no meio do osso, pelo mesmo termo com que o original foi medido, e
	# comparada com a FAIXA e nao com a mediana: os 27 campeoes variam muito, e
	# exigir a mediana de uma populacao espalhada e exigir precisao que a
	# referencia nao tem.
	for regiao, (mediana, minimo, maximo) in sorted(FAIXA_DA_ESBELTEZ.items()):
		osso = OSSO_DA_REGIAO[regiao]
		filho = _cauda_do_osso(g, nos, osso)
		if osso not in nos or filho is None:
			falhas.append("nao achei o osso `%s` para medir a esbeltez" % osso)
			continue
		cabeca, cauda = nos[osso], filho
		eixo = _menos(cauda, cabeca)
		comprimento = _norma(eixo)
		if comprimento <= 0.0:
			falhas.append("o osso `%s` nao tem comprimento" % osso)
			continue
		direcao = tuple(v / comprimento for v in eixo)
		cerco = mediana * comprimento * 0.5 * CERCO_DA_PECA
		maior = 0.0
		for ponto in pontos:
			relativo = _menos(ponto, cabeca)
			ao_longo = sum(relativo[i] * direcao[i] for i in range(3)) / comprimento
			if not 0.3 <= ao_longo <= 0.7:
				continue
			perpendicular = _norma(tuple(
				relativo[i] - direcao[i] * ao_longo * comprimento
				for i in range(3)))
			if perpendicular > cerco:
				continue
			maior = max(maior, perpendicular)
		if maior <= 0.0:
			falhas.append("nao achei carne em volta de `%s`" % osso)
			continue
		esbeltez = 2.0 * maior / comprimento
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
