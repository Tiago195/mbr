# -*- coding: utf-8 -*-
"""Quebra o gerador ou o conferidor de proposito e exige reprovacao."""
import io
import os
import subprocess
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
## Onde esta o Blender. A variavel de ambiente ganha do caminho padrao,
## para a ferramenta rodar em maquina que o instalou noutro lugar.
BLENDER = os.environ.get(
    "BLENDER_PATH",
    os.path.join("C:\\Program Files", "Blender Foundation",
                 "Blender 5.2", "blender.exe"),
)
GERADOR = os.path.join(RAIZ, "tools", "arte", "gerar_personagem.py")
CONFERE = os.path.join(RAIZ, "tools", "arte", "conferir_personagem.py")
REGRA = os.path.join(RAIZ, "tools", "arte", "regra_da_folga.py")

## `(titulo, velho, novo)` no gerador, ou `(titulo, velho, novo, arquivo)`.
MUTACOES = [
    ("o quadril nao assenta no chao",
     "quadril.location = (0.0, -_menor_z(malha) + _voo(voo, quadro), 0.0)",
     "quadril.location = (0.0, _voo(voo, quadro), 0.0)"),
    ("as poses nao chegam nos ossos",
     "local = _para_o_osso(armature, osso.name, poses.get(osso.name, (0.0, 0.0, 0.0)))",
     "local = _para_o_osso(armature, osso.name, (0.0, 0.0, 0.0))"),
    ("o salto nao sai do chao",
     '"voo": {0: 0.0, 7: 0.0, 18: 0.55, 26: 0.0, 36: 0.0},',
     '"voo": {0: 0.0, 7: 0.0, 18: 0.02, 26: 0.0, 36: 0.0},'),
    ("uma animacao muda de nome",
     '\t"preparo": {', '\t"preparo_zz": {'),
    ("o boneco encolhe",
     "ALTURA = 1.75", "ALTURA = 1.20"),
    ("a corrida nunca tira os pes do chao",
     '"voo": {0: 0.0, 6: 0.14, 12: 0.0, 18: 0.14, 24: 0.0},',
     '"voo": {0: 0.0, 6: 0.0, 12: 0.0, 18: 0.0, 24: 0.0},'),
    ("o pescoco sobe para a altura humana",
     '"pescoco": 0.763,', '"pescoco": 0.823,'),
    ("os ombros ficam largos como os de um humano",
     '"vao_dos_ombros": 0.175,', '"vao_dos_ombros": 0.229,'),
    ("os bracos ficam compridos como os de um humano",
     '"envergadura": 0.895,', '"envergadura": 1.000,'),
    ("o quadril sobe para a altura humana",
     '"quadril": 0.485,', '"quadril": 0.543,'),
    ("a mao encolhe ate nao existir",
     '"vao_das_maos": 0.629,', '"vao_das_maos": 0.880,'),
    ("o joelho sobe",
     '"joelho": 0.283,', '"joelho": 0.360,'),
    ("a estocada fica rapida demais para ler",
     "(30, pose())", "(18, pose())"),
    ("a corrida fica lenta demais",
     "(24, pose(", "(44, pose("),
    ("o parado vira um piscar",
     "(60, pose(peito=(2, 0, 0), cabeca=(1.5, 0, 0),",
     "(20, pose(peito=(2, 0, 0), cabeca=(1.5, 0, 0),"),
    # A formula de onde saem TODAS as tolerancias, no conferidor.
    ("a formula da folga multiplica por cem",
     "meia = (faixa[2] - faixa[1]) * 0.5",
     "meia = (faixa[2] - faixa[1]) * 50.0", REGRA),
]

QUEBRA = "\n"


def roda(script):
    r = subprocess.run([BLENDER, "--background", "--python", script],
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace", cwd=RAIZ)
    return r.returncode, (r.stdout or "")


def main():
    fontes = {caminho: io.open(caminho, encoding="utf-8").read()
              for caminho in (GERADOR, CONFERE, REGRA)}
    escaparam = []
    try:
        for mutacao in MUTACOES:
            titulo, velho, novo = mutacao[0], mutacao[1], mutacao[2]
            alvo = mutacao[3] if len(mutacao) > 3 else GERADOR
            original = fontes[alvo]
            if original.count(velho) != 1:
                print("PADRAO INVALIDO (%d): %s" % (original.count(velho), titulo))
                escaparam.append(titulo)
                continue
            io.open(alvo, "w", encoding="utf-8").write(
                original.replace(velho, novo, 1))
            try:
                # O gerador chama a conferencia e devolve o codigo dela: sair
                # diferente de zero COM motivo e a defesa funcionando.
                codigo, saida = roda(GERADOR)
                motivos = [l.strip() for l in saida.splitlines() if "REPROVA" in l]
                if codigo == 0:
                    codigo, saida = roda(CONFERE)
                    motivos = [l.strip() for l in saida.splitlines() if "REPROVA" in l]
            finally:
                # **Restaurar SEMPRE, antes do proximo laco.** Deixar o arquivo
                # mutado por causa de um `continue` contaminava todas as
                # mutacoes seguintes, e elas viravam falso-positivo.
                io.open(alvo, "w", encoding="utf-8").write(original)
            if codigo == 0:
                print("ESCAPOU  %s" % titulo)
                escaparam.append(titulo)
            elif not motivos:
                print("QUEBROU SEM REPROVAR: %s" % titulo)
                escaparam.append(titulo + " (sem motivo)")
            else:
                print("pegou    %-46s -> %s" % (titulo, motivos[0]))
    finally:
        for caminho, texto in fontes.items():
            io.open(caminho, "w", encoding="utf-8").write(texto)
        # **Restaurar o FONTE nao basta: o artefato ficou mutado.** O `.glb` no
        # disco e o da ultima mutacao, e ele nao volta sozinho. Foi assim que um
        # boneco com `parado` de 1,00 s chegou a ser commitado, reprovando a
        # propria conferencia.
        print("regerando o boneco a partir do fonte restaurado...")
        codigo, _ = roda(GERADOR)
        if codigo != 0:
            print("ATENCAO: o boneco NAO voltou ao normal")
            escaparam.append("o artefato nao foi restaurado")

    if escaparam:
        print(QUEBRA + "%d de %d escaparam: %s"
              % (len(escaparam), len(MUTACOES), escaparam))
        return 1
    print(QUEBRA + "todas as %d mutacoes foram pegas" % len(MUTACOES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
