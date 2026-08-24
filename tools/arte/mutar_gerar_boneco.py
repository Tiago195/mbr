# -*- coding: utf-8 -*-
"""Quebra `gerar_boneco.py` e `conferir_boneco.py` de proposito e exige reprova.

Rodar:
    py tools/arte/mutar_gerar_boneco.py

## Por que ela existe

Porque ate agora **nenhuma ferramenta do repositorio executava uma linha desta
pipeline.** `tools/arte/mutar_boneco.py` — as "75 mutacoes, 75 pegas" —
aponta para `gerar_personagem.py` e `conferir_personagem.py`, que sao o outro
boneco. Um `grep` por `gerar_boneco|conferir_boneco|boneco.glb` fora dos dois
arquivos dava zero ocorrencias no repositorio inteiro.

E as conferencias que elas carregam nao sao poucas nem baratas: duas revisoes
adversariais acharam onze achados materiais, e cada conserto virou uma
conferencia. Conferencia que ninguem roda e conferencia que ninguem sabe se
ainda confere — a licao 9 do `CLAUDE.md`, na forma mais pura.

## O que ela prova, e o que ela nao prova

Ela prova que cada conferencia DISTINGUE alguma coisa: quebra o que a
conferencia deveria pegar e exige vermelho. Nao prova que a animacao ficou boa
— isso e olho, e o §10 de `docs/11` diz qual item e.

**Toda mutacao restaura no fim, e a restauracao e conferida por leitura.** Uma
suite que restaura errado deixa o repositorio sujo em silencio, e ja deixou
neste projeto.
"""

from __future__ import annotations

import io
import os
import subprocess
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BLENDER = os.environ.get(
    "BLENDER_PATH",
    os.path.join("C:\\Program Files", "Blender Foundation",
                 "Blender 5.2", "blender.exe"),
)
ALVOS = {
    "gerador": os.path.join(RAIZ, "tools", "arte", "gerar_boneco.py"),
    "conferidor": os.path.join(RAIZ, "tools", "arte", "conferir_boneco.py"),
}
ARTEFATOS = [
    os.path.join(RAIZ, "arte", "boneco.glb"),
    os.path.join(RAIZ, "arte", "fonte", "boneco.blend"),
]

## Enquanto este arquivo existe, o repositorio esta MUTADO. Ele impede duas
## suites ao mesmo tempo — elas mexem nos mesmos arquivos — e serve de aviso
## para quem encontrar a arvore suja.
TRAVA = os.path.join(RAIZ, ".mutacao-em-curso")


## `(titulo, [(alvo, velho, novo)])`. Cada uma tem que fazer o gerador SAIR
## COM CODIGO 1 — que e o que ele faz quando a conferencia reprova.
MUTACOES = [
    # --- o corpo ---
    # **Mutar `RAIO_DA_CABECA` nao morde**: `convergir` corrige a largura da
    # cabeca ate o alvo, entao o laco desfaz a mutacao. Quem nao se conserta
    # sozinho e a PROPORCAO, que e a origem de tudo.
    ("o pescoco muda de altura",
     [("gerador", '	"pescoco": 0.763,', '	"pescoco": 0.690,')]),
    ("os ombros alargam",
     [("gerador", '"vao_dos_ombros": 0.175,', '"vao_dos_ombros": 0.260,')]),
    ("a coxa engorda",
     [("gerador", '"coxa": (0.575, 0.435, 0.936),',
       '"coxa": (1.400, 0.435, 0.936),')]),
    # **Virar `use_nodes` nao reproduz o cinza** — medido, o exportador ainda
    # le `diffuse_color` quando nao ha no. O defeito original era outro, e a
    # conferencia que nasceu dele compara VALOR de cor; e o valor que se muta.
    ("o membro sai da cor declarada",
     [("gerador", '	"membro": (0.17, 0.21, 0.31, 1.0),',
       '	"membro": (0.55, 0.60, 0.70, 1.0),')]),
    ("o rosto nao e pintado",
     [("gerador", "\t\tface.material_index = indices[\"rosto\"]\n\t\tpintadas += 1",
       "\t\tpintadas += 1")]),
    ("o corpo deixa de assentar no chao",
     [("gerador", "\t\t\"assentar\": True,", "\t\t\"assentar\": False,")]),

    # --- as animacoes ---
    ("a cadencia nao chega na cena",
     [("gerador", "\tbpy.context.scene.render.fps = CADENCIA",
       "\tbpy.context.scene.render.fps = 24")]),
    ("o `parado` dura o dobro",
     [("gerador", "\t\t\"duracao\": 1.33,", "\t\t\"duracao\": 2.66,")]),
    ("o `andando` dura o que quiser",
     [("gerador", "\t\t\"duracao\": 1.27,", "\t\t\"duracao\": 2.10,")]),
    ("o ciclo do `parado` deixa de fechar",
     [("gerador",
       "			(1.0, pose(peito=(3, 0, 0), cabeca=(3, 0, 0),\n"
       "			           braco_D=(2, -3, 0), braco_E=(2, 3, 0),\n"
       "			           antebraco_D=(-4, 0, 0), antebraco_E=(-4, 0, 0))),",
       "			(1.0, pose(peito=(9, 0, 0), cabeca=(3, 0, 0),\n"
       "			           braco_D=(2, -3, 0), braco_E=(2, 3, 0),\n"
       "			           antebraco_D=(-4, 0, 0), antebraco_E=(-4, 0, 0))),")]),
    # Zerar UMA chave de braco nao para o braco: as outras sete continuam. O
    # que para e o ombro na montagem do ciclo.
    ("os bracos param de balancar",
     [("gerador",
       "\t\t\tbraco_D=(braco_D, -4, 0), antebraco_D=(antebraco_D, 0, 0),",
       "\t\t\tbraco_D=(0, -4, 0), antebraco_D=(0, 0, 0),")]),
    ("a bascula lateral some",
     [("gerador", "\t\t\t\t(0.250, 4, -3, 5),", "\t\t\t\t(0.250, 4, -3, 0),")]),
    ("a perna esquerda manca",
     [("gerador", "		coxa_E, canela_E, pe_E = em(pernas, instante + 0.5)",
       "		coxa_E, canela_E, pe_E = [v * 0.85 for v in em(pernas, instante + 0.5)]")]),
    ("as duas pernas andam em fase",
     [("gerador", "		coxa_E, canela_E, pe_E = em(pernas, instante + 0.5)",
       "		coxa_E, canela_E, pe_E = em(pernas, instante + 0.0)")]),
    ("o pe que balanca deixa de levantar",
     [("gerador", "\t\t\t\t(0.625, 4, 74, -24),    # levanta: joelho no máximo, dedo acima",
       "\t\t\t\t(0.625, 4, 6, 0),    # levanta: joelho no máximo, dedo acima")]),
    ("a passada estica e o quadril mergulha",
     [("gerador", "\t\t\t\t(0.000, -17, 2, -10),   # contato: calcanhar, perna esticada",
       "\t\t\t\t(0.000, -30, 2, -10),   # contato: calcanhar, perna esticada")]),
    ("uma chave e escrita duas vezes",
     [("gerador", "\t\t\t\t(0.250, -2, 6, 0),      # passagem: vertical, sustentando",
       "\t\t\t\t(0.250, -2, 6, 0),      # passagem: vertical, sustentando\n"
       "\t\t\t\t(0.250, 40, 80, 30),")]),

    # --- as conferencias acrescentadas na rodada do revisor adversarial ---
    # **Congelar UM braco ja era mutacao; congelar os DOIS nao era**, e era
    # justamente o caso que escapava: a regiao guarda o maximo dos dois lados,
    # entao com um lado vivo o numero se sustentava, e com os dois mortos o
    # deslocamento no mundo ainda dava 0,14 m de carona do tronco. So a
    # articulacao ANGULAR do proprio osso distingue os dois casos.
    ("os DOIS bracos param de balancar",
     [("gerador",
       "\t\tbraco_D, antebraco_D = em(bracos, instante)\n"
       "\t\tbraco_E, antebraco_E = em(bracos, instante + 0.5)",
       "\t\tbraco_D, antebraco_D = 10.0, -20.0\n"
       "\t\tbraco_E, antebraco_E = 10.0, -20.0")]),
    # O conferidor media espessura, cor, ciclo e duracao — e nada do
    # ESQUELETO. Encurtar o braco publicava, e o laco de convergencia
    # construia um corpo consistente com o numero errado.
    ("o braco fica curto",
     [("gerador", '\t"envergadura": 0.895,', '\t"envergadura": 0.760,')]),
    # Fora da populacao inteira dos 27 campeoes (0,057 a 0,123), mas dentro
    # da folga unica de 0,050 que valia para as oito medidas.
    ("o tornozelo sai da populacao medida",
     [("gerador", '\t"tornozelo": 0.093,', '\t"tornozelo": 0.140,')]),
    # Idem: 0,160 esta fora da faixa (0,105 a 0,145) e dentro da folga antiga.
    ("o vao dos quadris sai da faixa",
     [("gerador", '\t"vao_dos_quadris": 0.129,',
       '\t"vao_dos_quadris": 0.160,')]),

    # --- o conferidor: quebrar a CONFERENCIA tambem tem que reprovar ---
    # Tirar `rosto` so de `CORES` nao desliga a conferencia: a presenca dele
    # continua exigida por outra. Defesa em profundidade e boa — a mutacao e
    # que tem de derrubar as DUAS para provar alguma coisa.
    ("o conferidor deixa de exigir o rosto",
     [("conferidor", '\t"rosto": (0.10, 0.11, 0.14),', ""),
      ("conferidor", 'falhas.append("o `.glb` nao tem faces com o material',
       'pass  # (')]),
    ("o conferidor deixa de conferir duracao",
     [("conferidor", '\t"andando": (1.27, True),', '\t"andando": (2.10, True),')]),
]


def _conferir_os_padroes() -> bool:
    """Todo padrao casa exatamente uma vez? Padrao que nao aplica nao prova nada."""
    ruins = []
    for titulo, edicoes in MUTACOES:
        for alvo, velho, _novo in edicoes:
            fonte = io.open(ALVOS[alvo], encoding="utf-8").read()
            quantas = fonte.count(velho)
            if quantas != 1:
                ruins.append("  %-52s casa %d vezes em %s"
                             % (titulo, quantas, alvo))
    if ruins:
        print("PADROES QUE NAO TESTAM NADA:")
        print("\n".join(ruins))
        print("conserte-os antes de rodar: uma mutacao que nao aplica nao "
              "prova defesa nenhuma.")
    return not ruins


def _gerar() -> int:
    """Roda o gerador no Blender headless. Devolve o codigo de saida."""
    resultado = subprocess.run(
        [BLENDER, "--background", "--python", ALVOS["gerador"]],
        capture_output=True, cwd=RAIZ)
    saida = (resultado.stdout or b"").decode("utf-8", "replace")
    # **O Blender sai com 0 mesmo quando o script estoura.** Quem decide e a
    # marca de sucesso do proprio gerador; sem isto, toda mutacao "passaria".
    return 0 if "[boneco] gravado:" in saida else 1


def _fatia(argv) -> tuple:
    """`(de, ate)` a partir da linha de comando. Sem argumento, tudo.

    **A suite existe em fatias porque uma execucao inteira nao cabe.** Cada
    mutacao regera o boneco, e o gerador custa 3m35s desde que a travessia da
    casca passou a ser medida em TODOS os quadros: 24 execucoes dao ~86
    minutos, e o executor em segundo plano matou a suite no meio disso. Uma
    suite morta no meio **deixa o repositorio mutado** — foi o que aconteceu, e
    so nao custou nada porque o trabalho estava commitado.

    Rodar `py tools/arte/mutar_gerar_boneco.py 0 8` faz as oito primeiras.
    Sempre UMA fatia de cada vez: a trava e o repositorio inteiro, nao a fatia.
    """
    if len(argv) >= 3:
        return int(argv[1]), int(argv[2])
    if len(argv) == 2:
        return int(argv[1]), len(MUTACOES)
    return 0, len(MUTACOES)


def main() -> int:
    if os.path.exists(TRAVA):
        print("ja ha uma suite de mutacao em curso (%s)" % TRAVA)
        return 1
    if not os.path.exists(BLENDER):
        print("nao achei o Blender em %s" % BLENDER)
        return 2
    # **Os padroes sao conferidos INTEIROS, mesmo rodando uma fatia.** Um
    # padrao orfao numa mutacao que esta fora da fatia continua sendo uma
    # conferencia desligada, e descobri-lo tres fatias depois e tarde.
    if not _conferir_os_padroes():
        return 1
    de, ate = _fatia(sys.argv)
    escolhidas = MUTACOES[de:ate]
    if not escolhidas:
        print("a fatia [%d:%d] esta vazia — sao %d mutacoes"
              % (de, ate, len(MUTACOES)))
        return 1
    if (de, ate) != (0, len(MUTACOES)):
        print("fatia [%d:%d] de %d mutacoes" % (de, ate, len(MUTACOES)))

    originais = {alvo: io.open(caminho, "rb").read()
                 for alvo, caminho in ALVOS.items()}
    guardados = {c: io.open(c, "rb").read() for c in ARTEFATOS
                 if os.path.exists(c)}
    io.open(TRAVA, "w", encoding="utf-8").write(
        "mutar_gerar_boneco.py esta mexendo nos arquivos deste repositorio\n")

    escaparam = []
    try:
        print("conferindo que o gerador passa ANTES de mutar...")
        if _gerar() != 0:
            print("o gerador ja reprova sem mutacao nenhuma — conserte antes")
            return 1

        for titulo, edicoes in escolhidas:
            pendentes = {}
            for alvo, velho, novo in edicoes:
                fonte = pendentes.get(alvo, originais[alvo].decode("utf-8"))
                pendentes[alvo] = fonte.replace(velho, novo, 1)
            for alvo, texto in pendentes.items():
                io.open(ALVOS[alvo], "w", encoding="utf-8",
                        newline="").write(texto)

            codigo = _gerar()

            for alvo, caminho in ALVOS.items():
                io.open(caminho, "wb").write(originais[alvo])
            if codigo == 0:
                print("ESCAPOU  %s" % titulo)
                escaparam.append(titulo)
            else:
                print("pegou    %s" % titulo)
    finally:
        for alvo, caminho in ALVOS.items():
            io.open(caminho, "wb").write(originais[alvo])
            if io.open(caminho, "rb").read() != originais[alvo]:
                print("ATENCAO: nao consegui restaurar %s" % caminho)
        for caminho, bruto in guardados.items():
            io.open(caminho, "wb").write(bruto)
        os.remove(TRAVA)
        print("regerando o boneco a partir do fonte restaurado...")
        _gerar()

    if escaparam:
        print("\n%d de %d ESCAPARAM: %s"
              % (len(escaparam), len(escolhidas), escaparam))
        return 1
    print("\ntodas as %d mutacoes desta fatia foram pegas (%d de %d no total)"
          % (len(escolhidas), ate - de, len(MUTACOES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
