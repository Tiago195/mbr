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

## Quanto o ponto mais baixo do corpo pode ficar longe de z=0 numa animacao de
## chao, em metros. Um centimetro e meio e menos que a espessura do sapato.
TOLERANCIA_DO_CHAO = 0.015
## As animacoes em que o boneco DEVE sair do chao, e o minimo que ele sobe.
NO_AR = {"salto": 0.25, "correndo": 0.04}
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
NOMES_EXIGIDOS = [
	"parado", "andando", "correndo",
	"estocada", "giro", "salto", "erguer", "preparo",
]
## A altura do corpo parado, em metros. Faixa APERTADA de proposito: o boneco
## e autorado com 1,75 exato, entao qualquer desvio significa que uma medida
## saiu de sincronia com as outras. Com a faixa larga de antes (1,60 a 1,90),
## encolher a cabeca inteira passava.
ALTURA_ESPERADA = (1.70, 1.82)
COLECAO_AUXILIAR = "glTF_not_exported"


def importar(glb: str) -> tuple:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=glb)
	# O glTF guarda tempo em SEGUNDOS. Sem acertar a cadencia, a cena importada
	# fica em 24 quadros por segundo e uma animacao de 60 quadros e medida com
	# 49 — o arquivo esta certo, e a medida e que fica torta.
	bpy.context.scene.render.fps = 30
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
		"quadros": fim - inicio + 1,
	}


def main() -> int:
	raiz = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
	glb = os.path.join(raiz, "arte", "personagem.glb")
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
	for nome in NOMES_EXIGIDOS:
		m = medir(armature, malha, acoes[nome])
		print(
			"[confere] %-9s %2d quadros  chao %+.3f..%+.3f  topo %.2f  movimento %.2f"
			% (nome, m["quadros"], m["chao_minimo"], m["chao_maximo"],
			   m["topo"], m["movimento"])
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
