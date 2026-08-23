# -*- coding: utf-8 -*-
"""A regra que transforma faixa medida em tolerancia. Python puro, sem Blender.

## Por que e um modulo separado

Ela e usada por duas ferramentas que rodam em interpretadores diferentes:
`conferir_personagem.py` roda DENTRO do Blender e `conferir_numeros.py` roda no
Python do sistema. Enquanto a funcao morava so no primeiro, a segunda nao tinha
como conferi-la — e uma revisao mostrou o preco: trocar `* 0.5` por `* 50.0`
abria as dez tolerancias de uma vez e `conferir_numeros.py` continuava verde.

O passo esta publicado em `docs/11-direcao-de-arte.md` e e conferido contra o
documento; a FORMULA passou a ser conferida aqui, por quem quer que importe
este arquivo.
"""

from __future__ import annotations

## O passo do arredondamento da folga, em fracao da altura. Publicado no §9 de
## `docs/11-direcao-de-arte.md`.
PASSO_DA_FOLGA = 0.005


def folga_de(faixa) -> float:
	"""Meia faixa medida, arredondada para cima no passo declarado.

	`faixa` e `(mediana, minimo, maximo)` — a mediana nao entra na conta, e esta
	na tupla porque e assim que as tabelas guardam a medida.
	"""
	meia = (faixa[2] - faixa[1]) * 0.5
	passos = int(meia / PASSO_DA_FOLGA)
	if meia - passos * PASSO_DA_FOLGA > 1e-9:
		passos += 1
	return passos * PASSO_DA_FOLGA


## `(faixa, folga esperada)`. Os dois casos discriminam: o primeiro cai no meio
## de um passo e tem que arredondar para cima, o segundo cai em cima do passo e
## tem que ficar onde esta. Uma formula errada erra pelo menos um dos dois.
## As medianas sao diferentes entre si e diferentes de zero de proposito: com
## `(0.0, min, max)` nos dois, uma formula que lesse `faixa[0]` por engano so
## seria pega pela magnitude, e fixture degenerado e cobertura falsa.
CASOS = (
	((0.485, 0.417, 0.512), 0.050),
	((0.110, 0.100, 0.120), 0.010),
	((0.900, 0.100, 0.120), 0.010),
)


def conferir_a_regra() -> list:
	"""A regra contra os casos que a distinguem. Devolve os motivos de reprova."""
	motivos = []
	for faixa, esperada in CASOS:
		obtida = folga_de(faixa)
		if abs(obtida - esperada) > 1e-9:
			motivos.append(
				"a regra da folga esta quebrada — faixa %.3f a %.3f deveria dar "
				"%.3f e deu %.3f" % (faixa[1], faixa[2], esperada, obtida)
			)
	return motivos
