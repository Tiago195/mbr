# -*- coding: utf-8 -*-
"""Mede a direcao de arte do Royal Crown a partir dos bundles da instalacao.

    py tools/arte/censo_do_original.py

Imprime os numeros que `docs/11-direcao-de-arte.md` afirma. **E ele que torna
aquele documento reproduzivel** — sem isto, cada numero de la seria memoria.

## O que entra e o que nao entra

Sai NUMERO: proporcao, duracao, contagem, nome de estado, saturacao media.
Nao sai ASSET: nenhuma malha, textura, som ou clipe e escrito em disco. E a
linha de `docs/01-visao-e-escopo.md`, a mesma que vale para as 113 tabelas XML.

## Precisa da instalacao

Le `C:\\Program Files (x86)\\Steam\\steamapps\\common\\Royal Crown`, que nao
esta neste repositorio e nao vai estar. Sem ela o script diz que nao achou e
sai com 2 — o que distingue "nao consegui medir" de "medi e deu diferente".

## Duas armadilhas ja pagas, e as duas davam numero plausivel

1. **A malha e Z para cima; o esqueleto e Y para cima.** Medir altura pelo Y da
   caixa envolvente da malha da a PROFUNDIDADE do corpo, e a razao cabeca/corpo
   sai 100% sem nenhum erro aparecer.
2. **Cada malha tem espaco local proprio... exceto que nao.** As duas medidas
   batem no chao (z=0) e na escala, e e isso que autoriza cruzar as duas. A
   conferencia esta em `_conferir_espacos`.
"""

from __future__ import annotations

import colorsys
import io
import math
import os
import re
import statistics
import sys
from collections import Counter, defaultdict

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

BASE = (r"C:\Program Files (x86)\Steam\steamapps\common\Royal Crown"
        r"\RoyalCrown_Data\StreamingAssets")

## Os 32 campeoes com controlador de partida. `Ballista_Catapult`, `Elma_Bato`
## e `Miru_Cat` sao FORMAS de campeao, nao campeoes, e por isso ficam de fora:
## tem 5 a 8 clipes cada e afundariam qualquer mediana.
PERSONAGENS = [
	"Alicia", "Ballista", "Bastine", "Bella", "Chao", "Cheff", "Coric", "Cro",
	"Eden", "Elma", "Fisher", "Harang", "Kaiba", "Kane", "Kara", "Leo", "Melia",
	"Miru", "Morgan", "Neva", "Nina", "Odri", "Rody", "Rukh", "Sasha", "Selkie",
	"Siu", "Sonya", "Spark", "Stepan", "Thief", "Violet",
]
FORMAS = {"Ballista_Catapult", "Elma_Bato", "Miru_Cat"}

## Bella tem a base da malha 22 cm ABAIXO do chao — vestido longo — e por isso a
## altura dela nao e comparavel com a dos outros. Excluida das medianas de
## proporcao, e dita em voz alta em vez de sumir em silencio.
FORA_DA_PROPORCAO = {"Bella"}

## A ordem canonica de `m_HumanBoneIndex`. **`UpperChest` esta na posicao 9**,
## e esquece-lo desloca em um TODOS os ossos acima do peito — o que faz a mao,
## o pe e o braco cairem na mesma altura sem nenhum erro aparecer. Foi essa
## repeticao impossivel que denunciou; a lista certa ja tinha sido paga em
## `import_local/extrair_leo.py`.
OSSOS_HUMANOS = [
	"Hips", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
	"LeftFoot", "RightFoot", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm",
	"LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand",
	"LeftToes", "RightToes", "LeftEye", "RightEye", "Jaw",
]

## Humano adulto de 1,75 m, para ter contra o que comparar. Nao e medicao do
## jogo: e a regua. `pescoco` e a base do pescoco, `cranio` a base do cranio.
HUMANO = {
	"LeftToes": 0.010, "LeftFoot": 0.039, "LeftLowerLeg": 0.285,
	"LeftUpperLeg": 0.543, "Hips": 0.543, "Neck": 1.44 / 1.75,
	"Head": 1.47 / 1.75, "pescoco": 1.44 / 1.75, "cranio": 1.47 / 1.75,
	"quadril": 0.95 / 1.75, "ombros": 0.40 / 1.75,
}


def desembrulha(v):
	while isinstance(v, dict) and set(v.keys()) == {"data"}:
		v = v["data"]
	return v


def q_mul_v(q, v):
	x, y, z, w = q
	vx, vy, vz = v
	tx = 2 * (y * vz - z * vy)
	ty = 2 * (z * vx - x * vz)
	tz = 2 * (x * vy - y * vx)
	return (vx + w * tx + (y * tz - z * ty),
	        vy + w * ty + (z * tx - x * tz),
	        vz + w * tz + (x * ty - y * tx))


def q_mul(a, b):
	ax, ay, az, aw = a
	bx, by, bz, bw = b
	return (aw * bx + ax * bw + ay * bz - az * by,
	        aw * by - ax * bz + ay * bw + az * bx,
	        aw * bz + ax * by - ay * bx + az * bw,
	        aw * bw - ax * bx - ay * by - az * bz)


def faixa(nome, valores, casas=2):
	if not valores:
		return "%-34s (sem dado)" % nome
	v = sorted(valores)
	return "%-34s n=%-4d min %.*f  mediana %.*f  max %.*f" % (
		nome, len(v), casas, v[0], casas, statistics.median(v), casas, v[-1])


# ------------------------------------------------------------------ animacao

def censo_de_animacao(UnityPy):
	env = UnityPy.load(os.path.join(BASE, "_animation.pak"))
	clipes = {}
	overrides = {}
	tipos = Counter()
	objetos = list(env.objects)

	# **Duas passadas, e nao uma.** O controlador aponta para o clipe por
	# `m_PathID`, e a ordem dentro do bundle nao e a de dependencia: numa
	# passada so, todo controlador lido antes dos clipes dele perdia os pares
	# em silencio. Sem erro: as medianas so ficavam menores. Foi assim que este
	# censo publicou "0 clipes universais" onde ha 22.
	for obj in objetos:
		tipos[obj.type.name] += 1
		if obj.type.name != "AnimationClip":
			continue
		d = obj.read_typetree()
		mc = d.get("m_MuscleClip") or {}
		clipes[obj.path_id] = {
			"nome": d.get("m_Name"),
			"duracao": mc.get("m_StopTime"),
			"loop": bool(mc.get("m_LoopTime")),
			"taxa": d.get("m_SampleRate"),
			"eventos": len(d.get("m_Events") or []),
		}
	bases = []
	for obj in objetos:
		if obj.type.name == "AnimatorController":
			bases.append(obj.read_typetree().get("m_Name") or "?")
	perdidos = 0
	for obj in objetos:
		if obj.type.name != "AnimatorOverrideController":
			continue
		d = obj.read_typetree()
		pares = []
		for par in (d.get("m_Clips") or []):
			novo = clipes.get((par.get("m_OverrideClip") or {}).get("m_PathID"))
			if novo:
				pares.append(novo)
			else:
				perdidos += 1
		overrides[d.get("m_Name") or "?"] = pares
	# Um clipe referenciado que nao existe no bundle e uma medida faltando, e
	# medida faltando tem que APARECER.
	if perdidos:
		print("  AVISO: %d referencias de clipe nao resolvidas" % perdidos)

	print("== ANIMACAO ==")
	# **Este censo le UM bundle.** `_animation.pak` guarda a animacao de
	# personagem; o jogo inteiro tem mais clipe do que isto (cenario, efeito,
	# interface). Dizer "o original tem 1350 clipes" sem o escopo e afirmar
	# sobre o jogo o que se mediu num arquivo.
	print("  escopo: _animation.pak, so ele")
	print("  objetos no _animation.pak:", dict(tipos))
	taxas = Counter(c["taxa"] for c in clipes.values())
	print("  cadencia dos clipes:", taxas.most_common())
	print("  ciclo x uma vez:", Counter(c["loop"] for c in clipes.values()).most_common())
	print(" ", faixa("duracao de TODOS os clipes (s)",
	                 [c["duracao"] for c in clipes.values() if c["duracao"]]))

	partida, caindo, saguao = {}, {}, {}
	for nome, pares in overrides.items():
		curto = nome[len("NLAniCtrl_"):] if nome.startswith("NLAniCtrl_") else nome
		if curto.endswith("_Falling"):
			caindo[curto[:-len("_Falling")]] = pares
		elif curto.endswith("_Lobby"):
			saguao[curto[:-len("_Lobby")]] = pares
		elif curto not in FORMAS:
			partida[curto] = pares

	print("  campeoes com controlador de partida:", len(partida))
	# Os tres `AnimatorController` deste bundle sao os de saguao e queda. O
	# controlador base de PARTIDA vive fora daqui, e por isso os nomes de
	# ESTADO nao aparecem em lugar nenhum deste censo — so os nomes de clipe.
	print("  controladores base neste bundle:", sorted(bases))
	print("  formas de campeao ignoradas:", sorted(FORMAS))
	print(" ", faixa("vagas preenchidas por campeao", [len(p) for p in partida.values()], 0))

	donos = defaultdict(set)
	dur = defaultdict(list)
	loop = defaultdict(list)
	for k, pares in partida.items():
		for p in pares:
			donos[p["nome"]].add(k)
			if p["duracao"]:
				dur[p["nome"]].append(p["duracao"])
			loop[p["nome"]].append(p["loop"])

	# O limiar e >=30 de 32; quantos estao em TODOS e outra conta, e e ela que
	# o documento afirma. Publicar so o limiar deixava a afirmacao sem teste.
	universais = sorted(n for n, s in donos.items() if len(s) >= 30)
	em_todos = sorted(n for n in universais if len(donos[n]) == len(partida))
	print("  clipes UNIVERSAIS (>=30 dos %d campeoes): %d, dos quais %d estao em TODOS"
	      % (len(partida), len(universais), len(em_todos)))
	for n in universais:
		v = sorted(dur[n])
		lp = Counter(loop[n])
		print("    %-18s %2d pers  %.2f / %.2f / %.2f s  %s" % (
			n, len(donos[n]), v[0], statistics.median(v), v[-1],
			"ciclo" if lp[True] > lp[False] else "uma vez"))

	proprios = [n for n, s in donos.items() if len(s) == 1]
	por_pers = Counter()
	for n in proprios:
		por_pers[list(donos[n])[0]] += 1
	print("  clipes PROPRIOS de um campeao so: %d nomes" % len(proprios))
	print(" ", faixa("clipes proprios por campeao", list(por_pers.values()), 0))

	# **Campeao sem NENHUM clipe exclusivo divide o kit inteiro com outro.** E
	# uma decisao de producao visivel na tabela, e a media de "clipes proprios"
	# a esconde: ela e calculada sobre quem tem algum.
	sem = sorted(k for k in partida if k not in por_pers)
	print("  campeoes SEM clipe exclusivo: %d  %s" % (len(sem), ", ".join(sem)))
	for k in sem:
		raros = {p["nome"] for p in partida[k] if len(donos[p["nome"]]) <= 4}
		par = max(((len(raros & {q["nome"] for q in partida[j]}), j)
		           for j in partida if j != k), default=(0, "?"))
		# **Quanto dividem, sobre quantos tem.** "Divide 11" sem o denominador
		# vira "divide o kit inteiro" na primeira vez que alguem resume — e
		# virou. Harang divide 11 de 16, o que nao e o conjunto inteiro.
		outros = {q["nome"] for q in partida[par[1]] if len(donos[q["nome"]]) <= 4}
		print("    %-10s divide %d dos %d clipes pouco-comuns dele com %s "
		      "(que tem %d)" % (k, par[0], len(raros), par[1], len(outros)))

	# **O limiar e uma decisao, e ela aparece.** "Habilidade" aqui e clipe de no
	# maximo DOIS campeoes: quatro pares dividem quase todo o kit, e exigir um
	# dono so jogaria fora metade das habilidades desses oito. Com `== 1` a
	# mediana vai de 1,07 para 1,17 e o p75 de 1,40 para 1,47 — e sao esses
	# quartis que viram a faixa de duracao dos nossos gestos.
	LIMIAR_DE_HABILIDADE = 2
	hab = sorted(x for n, s in donos.items()
	             if len(s) <= LIMIAR_DE_HABILIDADE for x in dur[n])
	print("  habilidade = clipe de no maximo %d campeoes" % LIMIAR_DE_HABILIDADE)
	print(" ", faixa("duracao dos clipes de HABILIDADE (s)", hab))
	print("    quartis: p25 %.2f  p75 %.2f  p90 %.2f" % (
		hab[len(hab) // 4], hab[len(hab) * 3 // 4], hab[len(hab) * 9 // 10]))
	quadros = Counter(round(x * 30) for x in hab)
	print("    em quadros a 30 fps, os mais comuns:", quadros.most_common(6))

	# A conferencia do _f/_b: conjurar andando dura o ciclo de corrida. Os DOIS
	# sao medidos — publicar so o `_f` ja fez o documento dizer "29 dos 32" de
	# uma regra que o `_b` cumpre em 30.
	corridas = {}
	for sufixo in ("throw_f", "throw_b"):
		bate, total, fora = 0, 0, []
		for k, pares in partida.items():
			nomes = {p["nome"]: p["duracao"] for p in pares}
			if "run" not in nomes or sufixo not in nomes:
				continue
			total += 1
			corridas[k] = nomes["run"]
			if abs((nomes[sufixo] or 0) - (nomes["run"] or 0)) < 0.02:
				bate += 1
			else:
				fora.append(k)
		print("  %s com a MESMA duracao de run: %d de %d campeoes  (fora: %s)"
		      % (sufixo, bate, total, ", ".join(sorted(fora)) or "ninguem"))
	if corridas:
		ordenadas = sorted(corridas.items(), key=lambda x: x[1])
		print("    corrida mais CURTA: %s %.2f s;  mais LONGA: %s %.2f s"
		      % (ordenadas[0][0], ordenadas[0][1], ordenadas[-1][0], ordenadas[-1][1]))

	# Nomes e INSTANCIAS sao contas diferentes, e o documento ja usou a palavra
	# "clipes" para as duas no mesmo paragrafo.
	com_evento = {p["nome"] for pares in partida.values() for p in pares if p["eventos"]}
	distintos = {p["nome"] for pares in partida.values() for p in pares}
	inst_com = sum(1 for pares in partida.values() for p in pares if p["eventos"])
	inst_tot = sum(len(pares) for pares in partida.values())
	print("  NOMES de clipe de partida com evento: %d de %d  ->  %s" % (
		len(com_evento), len(distintos), ", ".join(sorted(com_evento))))
	print("  INSTANCIAS com evento: %d de %d" % (inst_com, inst_tot))

	for rotulo, grupo in (("QUEDA", caindo), ("SAGUAO", saguao)):
		d2 = defaultdict(set)
		v2 = defaultdict(list)
		l2 = defaultdict(list)
		for k, pares in grupo.items():
			for p in pares:
				d2[p["nome"]].add(k)
				if p["duracao"]:
					v2[p["nome"]].append(p["duracao"])
				l2[p["nome"]].append(p["loop"])
		print("  == %s == (%d controladores)" % (rotulo, len(grupo)))
		for n in sorted(d2, key=lambda x: -len(d2[x])):
			if len(d2[n]) < 5:
				continue
			v = sorted(v2[n])
			lp = Counter(l2[n])
			print("    %-24s %2d pers  %.2f / %.2f / %.2f s  %s" % (
				n, len(d2[n]), v[0], statistics.median(v), v[-1],
				"ciclo" if lp[True] > lp[False] else "uma vez"))
	return {"campeoes": len(partida), "universais": universais}


# ---------------------------------------------------------------- proporcao

def _bundles_de_modelo():
	dup = os.path.join(BASE, "duplicated")
	alvos = [os.path.join(dup, n) for n in sorted(os.listdir(dup))]
	alvos.append(os.path.join(BASE, "prefabs", "_model.pak"))
	return alvos


def censo_de_proporcao(UnityPy):
	malhas = {}
	avatares = {}
	for caminho in _bundles_de_modelo():
		try:
			env = UnityPy.load(caminho)
		except Exception:
			continue
		for obj in env.objects:
			if obj.type.name == "Mesh":
				d = obj.read_typetree()
				aabb = d.get("m_LocalAABB") or {}
				c, e = aabb.get("m_Center") or {}, aabb.get("m_Extent") or {}
				malhas[(d.get("m_Name") or "?").lower()] = {
					"centro": (c.get("x"), c.get("y"), c.get("z")),
					"meia": (e.get("x"), e.get("y"), e.get("z")),
					"verts": (d.get("m_VertexData") or {}).get("m_VertexCount"),
					"ossos": len(d.get("m_BindPose") or []),
				}
			elif obj.type.name == "Avatar":
				d = obj.read_typetree()
				av = d.get("m_Avatar") or {}
				esq = desembrulha(av.get("m_AvatarSkeleton") or {})
				pose = desembrulha(av.get("m_AvatarSkeletonPose") or {})
				nos, xs = esq.get("m_Node") or [], pose.get("m_X") or []
				if not nos or len(xs) != len(nos):
					continue
				pos, rot = [None] * len(nos), [None] * len(nos)
				for i, no in enumerate(nos):
					x = xs[i]
					t = (x["t"]["x"], x["t"]["y"], x["t"]["z"])
					q = (x["q"]["x"], x["q"]["y"], x["q"]["z"], x["q"]["w"])
					pai = no["m_ParentId"]
					if pai < 0:
						pos[i], rot[i] = t, q
					else:
						pos[i] = tuple(a + b for a, b in zip(pos[pai], q_mul_v(rot[pai], t)))
						rot[i] = q_mul(rot[pai], q)
				hum = desembrulha(av.get("m_Human") or {})
				if not hum:
					continue
				hs = desembrulha(hum.get("m_Skeleton") or {})
				indice = desembrulha(hum.get("m_HumanBoneIndex") or [])
				por_hash = {h: i for i, h in enumerate(esq.get("m_ID") or [])}
				ossos = {}
				for k, n in enumerate(OSSOS_HUMANOS):
					if k < len(indice) and indice[k] >= 0:
						alvo = por_hash.get((hs.get("m_ID") or [])[indice[k]])
						if alvo is not None:
							ossos[n] = pos[alvo]
				if "Head" in ossos and "Hips" in ossos:
					avatares[(d.get("m_Name") or "?").lower()] = {
						"nos": len(nos), "ossos": ossos,
					}

	print()
	print("== PROPORCAO ==")
	print("  malhas lidas: %d   avatares humanoides lidos: %d" % (len(malhas), len(avatares)))

	linhas = []
	faltaram = []
	for p in PERSONAGENS:
		# **Nem todo corpo se chama `X_Body`.** Odri e Rukh nomeiam a malha do
		# corpo so com o nome do campeao, e a versao anterior os descartava
		# calada — dois campeoes a menos numa mediana que o documento publica.
		# O Rukh, sozinho, baixa o minimo da envergadura de 0,855 para 0,808, e
		# e desse minimo que sai a folga da conferencia do nosso boneco.
		corpo = malhas.get((p + "_body").lower()) or malhas.get(p.lower())
		cabeca = malhas.get((p + "_head").lower())
		avatar = avatares.get((p + "avatar").lower())
		if not corpo or not cabeca or not avatar:
			faltaram.append("%s (%s)" % (p, ", ".join(
				rotulo for rotulo, tem in
				(("corpo", corpo), ("cabeca", cabeca), ("avatar", avatar))
				if not tem)))
			continue
		# **Vertical e o Z.** A malha e autorada Z para cima; o Y da caixa e a
		# profundidade do corpo.
		topo = max(corpo["centro"][2] + corpo["meia"][2], cabeca["centro"][2] + cabeca["meia"][2])
		base = min(corpo["centro"][2] - corpo["meia"][2], cabeca["centro"][2] - cabeca["meia"][2])
		altura = topo - base
		oss = avatar["ossos"]
		pescoco = oss["Neck"][1] - base
		cranio = oss["Head"][1] - base
		quadril = oss["Hips"][1] - base
		ombros = (abs(oss["LeftUpperArm"][0] - oss["RightUpperArm"][0])
		          if "LeftUpperArm" in oss and "RightUpperArm" in oss else None)
		quadris = (abs(oss["LeftUpperLeg"][0] - oss["RightUpperLeg"][0])
		           if "LeftUpperLeg" in oss and "RightUpperLeg" in oss else None)
		# **O vao das MAOS, e ele nao e a envergadura.** A envergadura da malha
		# vai ponta a ponta e inclui a mao inteira; o vao das juntas para no
		# punho. Publicar so um dos dois deixa qualquer copia nossa acertar o
		# numero alongando o antebraco no lugar de ter mao.
		maos = (abs(oss["LeftHand"][0] - oss["RightHand"][0])
		        if "LeftHand" in oss and "RightHand" in oss else None)
		escada = {n: (v[1] - base) / altura for n, v in oss.items()}
		linhas.append({
			"pers": p, "altura": altura, "escada": escada,
			"pescoco": pescoco / altura, "cranio": cranio / altura,
			"quadril": quadril / altura,
			"ombros": (ombros / altura) if ombros else None,
			"quadris": (quadris / altura) if quadris else None,
			"maos": (maos / altura) if maos else None,
			"envergadura": corpo["meia"][0] * 2 / altura,
			"nos": avatar["nos"], "verts": corpo["verts"], "base": base,
		})

	# **Quem cai fora tem que APARECER.** Um campeao descartado em silencio e
	# uma mediana calculada sobre outra populacao que a declarada, e nenhuma
	# das duas aparece errada.
	if faltaram:
		print("  sem malha ou avatar nos bundles locais: %s" % "; ".join(faltaram))

	_conferir_espacos(linhas)

	bons = [l for l in linhas if l["pers"] not in FORA_DA_PROPORCAO]
	print("  campeoes medidos: %d (fora: %s)" % (len(bons), ", ".join(sorted(FORA_DA_PROPORCAO))))
	print("  -- a escada de alturas, como fracao da altura total --")
	for osso in ("LeftToes", "LeftFoot", "LeftLowerLeg", "LeftUpperLeg", "Hips",
	             "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm",
	             "LeftHand"):
		vals = [l["escada"][osso] for l in bons if osso in l["escada"]]
		if not vals:
			continue
		ref = HUMANO.get(osso)
		print("    %-14s n=%-3d med %.3f  (min %.3f  max %.3f)   em 1,75 m: %.3f%s" % (
			osso, len(vals), statistics.median(vals), min(vals), max(vals),
			statistics.median(vals) * 1.75,
			"   humano %.3f" % ref if ref else ""))
	print(" ", faixa("altura total (unidades)", [l["altura"] for l in bons], 3))
	print(" ", faixa("base do PESCOCO / altura", [l["pescoco"] for l in bons], 3),
	      "   humano %.3f" % HUMANO["pescoco"])
	print(" ", faixa("base do CRANIO / altura", [l["cranio"] for l in bons], 3),
	      "   humano %.3f" % HUMANO["cranio"])
	print(" ", faixa("quadril / altura", [l["quadril"] for l in bons], 3),
	      "   humano %.3f" % HUMANO["quadril"])
	print(" ", faixa("ombros / altura", [l["ombros"] for l in bons if l["ombros"]], 3),
	      "   humano %.3f" % HUMANO["ombros"])
	print(" ", faixa("vao dos quadris / altura", [l["quadris"] for l in bons if l["quadris"]], 3))
	print(" ", faixa("vao das MAOS / altura (juntas)",
	                 [l["maos"] for l in bons if l["maos"]], 3))
	print(" ", faixa("envergadura / altura (malha, ponta a ponta)",
	                 [l["envergadura"] for l in bons], 3), "   humano ~1.00")
	# **A definicao importa mais que o numero.** "Cabecas de altura" so quer
	# dizer alguma coisa com a linha de corte declarada: aqui, cabeca e tudo o
	# que fica ACIMA DA BASE DO PESCOCO. Medir do cranio da outro numero, e sem
	# dizer qual dos dois e a conta o valor nao e comparavel com nada.
	unidades = [1.0 / (1.0 - l["pescoco"]) for l in bons]
	print(" ", faixa("cabecas de altura (acima do pescoco)", unidades),
	      "   humano %.2f" % (1.0 / (1.0 - HUMANO["pescoco"])))
	print(" ", faixa("nos do esqueleto", [l["nos"] for l in bons], 0))
	print(" ", faixa("vertices do corpo", [l["verts"] for l in bons if l["verts"]], 0))
	return bons


def _conferir_espacos(linhas):
	"""Malha e esqueleto medem no mesmo chao? Sem isto nao da para cruzar.

	Se as duas leituras nao concordassem sobre onde e z=0, toda razao daqui
	seria a divisao de duas reguas diferentes — e sairia um numero plausivel.
	"""
	fundo = [abs(l["base"]) for l in linhas if l["pers"] not in FORA_DA_PROPORCAO]
	if not fundo:
		return
	pior = max(fundo)
	print("  base da malha em z=0: pior desvio %.3f  %s" % (
		pior, "ok" if pior < 0.02 else "SUSPEITO — as duas leituras discordam do chao"))


# ------------------------------------------------------------------- paleta

def censo_de_paleta(UnityPy):
	dup = os.path.join(BASE, "duplicated")
	alvos = [os.path.join(dup, n) for n in sorted(os.listdir(dup))]
	alvos.append(os.path.join(BASE, "_texture.pak"))
	nomes = set(p.lower() for p in PERSONAGENS)
	achadas = {}
	resolucoes = Counter()
	for caminho in alvos:
		try:
			env = UnityPy.load(caminho)
		except Exception:
			continue
		for obj in env.objects:
			if obj.type.name != "Texture2D":
				continue
			d = obj.read_typetree()
			n = (d.get("m_Name") or "").lower()
			for p in nomes:
				if re.search(r"(^|[_-])" + re.escape(p) + r"($|[_-])", n) or n.startswith(p):
					resolucoes[(d.get("m_Width"), d.get("m_Height"))] += 1
					break
			# **Nem toda textura de corpo tem o prefixo `tex_`.** `bastine` e
			# `odri` sao 2048x2048 de corpo e o filtro antigo as jogava fora,
			# o que fazia a paleta ser publicada sobre 4 campeoes em vez de 6 —
			# e o brilho minimo passar de 0,56 para 0,42.
			alvo = n[4:] if n.startswith("tex_") else n
			if (alvo in nomes and alvo not in achadas
					and d.get("m_Width") == 2048 and d.get("m_Height") == 2048):
				try:
					img = obj.read().image
				except Exception:
					img = None
				if img is not None:
					achadas[alvo] = img

	print()
	print("== PALETA ==")
	print("  resolucoes de textura ligadas a personagem:", resolucoes.most_common(6))
	# Quantos campeoes tem QUALQUER textura aqui — o resto mora nos
	# Addressables do servidor, que morreu. Sem este numero, "cada campeao tem
	# uma textura 2048" generaliza de 6 para 32.
	print("  campeoes com textura de corpo 2048 nos bundles locais: %d de %d"
	      % (len(achadas), len(PERSONAGENS)))
	sats, brilhos, cinzas = [], [], []
	for p in sorted(achadas):
		px = list(achadas[p].convert("RGBA").resize((64, 64)).getdata())
		hsv = [colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
		       for r, g, b, a in px if a >= 40]
		if not hsv:
			continue
		s = sorted(x[1] for x in hsv)
		v = sorted(x[2] for x in hsv)
		sats.append(statistics.median(s))
		brilhos.append(statistics.median(v))
		cinzas.append(sum(1 for x in hsv if x[1] < 0.15) / len(hsv))
		print("    %-10s %-10s saturacao %.2f  brilho %.2f  quase-cinza %.0f%%" % (
			p, "%dx%d" % achadas[p].size, statistics.median(s), statistics.median(v),
			cinzas[-1] * 100))
	print(" ", faixa("saturacao mediana", sats))
	print(" ", faixa("brilho mediano", brilhos))
	print(" ", faixa("fracao quase-cinza", cinzas))


def main() -> int:
	if not os.path.isdir(BASE):
		print("[censo] nao achei a instalacao em %s" % BASE)
		print("[censo] este script mede o ORIGINAL; sem ele nao ha o que medir.")
		return 2
	try:
		import UnityPy
	except ImportError:
		print("[censo] falta UnityPy:  py -m pip install UnityPy")
		return 2

	censo_de_animacao(UnityPy)
	censo_de_proporcao(UnityPy)
	censo_de_paleta(UnityPy)
	print()
	print("[censo] fim. Nenhum asset foi escrito em disco.")
	return 0


if __name__ == "__main__":
	sys.exit(main())
