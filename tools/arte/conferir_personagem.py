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
## perguntar "**esta na direcao de arte?**". As faixas sao as medidas em 25
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
## O passo do arredondamento da folga, em fracao da altura.
PASSO_DA_FOLGA = 0.005


def folga_de(faixa: tuple) -> float:
	"""Meia faixa medida, arredondada para cima no passo declarado."""
	meia = (faixa[2] - faixa[1]) * 0.5
	passos = int(meia / PASSO_DA_FOLGA)
	if meia - passos * PASSO_DA_FOLGA > 1e-9:
		passos += 1
	return passos * PASSO_DA_FOLGA


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
	}


def _fundo_do_grupo(malha, grupo: str):
	"""O ponto mais baixo dos vertices presos a um osso, em repouso."""
	if grupo not in malha.vertex_groups:
		return None
	indice = malha.vertex_groups[grupo].index
	mundo = malha.matrix_world
	alturas = [
		(mundo @ v.co).z for v in malha.data.vertices
		if any(g.group == indice and g.weight > 0.5 for g in v.groups)
	]
	return min(alturas) if alturas else None


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

	def alcance(rotulo, ate, alvo):
		if ate is None:
			reprovas.append("nao consegui medir %s" % rotulo)
			return
		v = ombros + 2.0 * (ossos["braco_D"].head_local.z - ate) / altura
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
	alcance("vao maos", ossos["mao_D"].head_local.z, VAO_DAS_MAOS)
	# **A ponta vem da MALHA, nao do osso.** O glTF nao guarda o comprimento de
	# um osso, so a posicao da junta, e o importador do Blender INVENTA a cauda.
	# Lendo `tail_local` a envergadura saia 0,857 onde a construcao da 0,895.
	alcance("envergad.", _fundo_do_grupo(malha, "mao_D"), ENVERGADURA)
	return reprovas


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
	reprovas.extend(conferir_proporcao(armature, malha))
	for nome in NOMES_EXIGIDOS:
		m = medir(armature, malha, acoes[nome])
		print(
			"[confere] %-9s %5.2f s  chao %+.3f..%+.3f  topo %.2f  movimento %.2f"
			% (nome, m["duracao"], m["chao_minimo"], m["chao_maximo"],
			   m["topo"], m["movimento"])
		)

		faixa = DURACAO_ESPERADA.get(nome)
		if faixa and not faixa[0] <= m["duracao"] <= faixa[1]:
			reprovas.append(
				"'%s' dura %.2f s, fora da faixa %.2f--%.2f da direcao de arte"
				% (nome, m["duracao"], faixa[0], faixa[1])
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
