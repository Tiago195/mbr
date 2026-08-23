# -*- coding: utf-8 -*-
"""Quebra a concordancia documento<->codigo<->artefato e exige reprovacao."""
import io
import os
import shutil
import subprocess
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
## Onde esta o Blender. A variavel de ambiente ganha do caminho padrao,
## para a ferramenta rodar em maquina que o instalou noutro lugar.
BLENDER = os.environ.get(
    "BLENDER_PATH",
    os.path.join("C:\\Program Files", "Blender Foundation",
                 "Blender 5.2", "blender.exe"),
)
ALVOS = {
    "gerador": os.path.join(RAIZ, "tools", "arte", "gerar_personagem.py"),
    "conferidor": os.path.join(RAIZ, "tools", "arte", "conferir_personagem.py"),
    "doc": os.path.join(RAIZ, "docs", "11-direcao-de-arte.md"),
    "instantaneo": os.path.join(RAIZ, "data", "direcao-de-arte.json"),
    "claude": os.path.join(RAIZ, "CLAUDE.md"),
    "regra": os.path.join(RAIZ, "tools", "arte", "regra_da_folga.py"),
}
GLB = os.path.join(RAIZ, "arte", "personagem.glb")

## `(titulo, [(alvo, velho, novo), ...], regerar_o_glb)`
MUTACOES = [
    ("o gerador muda a proporcao e o resto nao", [
        ("gerador", '"pescoco": 0.763,', '"pescoco": 0.790,')], False),
    ("o documento muda a proporcao e o codigo nao", [
        ("doc", "| base do pescoço | 0,763 | 0,708",
         "| base do pescoço | 0,790 | 0,708")], False),
    ("some uma linha da tabela de proporcao", [
        ("doc", "| envergadura / altura | **0,895** |",
         "| envergadura / altura (removida) | **0,895** |")], False),
    # --- FAIXA, e agora tambem contra o instantaneo medido ---
    ("a faixa e alargada so no conferidor", [
        ("conferidor", '"coxa_D": (0.485, 0.417, 0.512),',
         '"coxa_D": (0.485, 0.017, 0.912),')], False),
    ("a faixa e alargada no documento E no conferidor", [
        ("doc", "| envergadura / altura | **0,895** | 0,808 – 0,966 |",
         "| envergadura / altura | **0,895** | 0,108 – 1,966 |"),
        ("conferidor", '"envergadura": (0.895, 0.808, 0.966),',
         '"envergadura": (0.895, 0.108, 1.966),')], False),
    # --- o passo da folga: um digito abria TODAS as tolerancias ---
    ("o passo da folga vira meio", [
        ("regra", "PASSO_DA_FOLGA = 0.005", "PASSO_DA_FOLGA = 0.5")], False),
    ("a formula da folga multiplica por cem", [
        ("regra", "meia = (faixa[2] - faixa[1]) * 0.5",
         "meia = (faixa[2] - faixa[1]) * 50.0")], False),
    ("a folga da altura vira meio metro", [
        ("conferidor", "FOLGA_DA_ALTURA = 0.04", "FOLGA_DA_ALTURA = 0.50")], False),
    ("a tolerancia do chao vira um metro e meio", [
        ("conferidor", "TOLERANCIA_DO_CHAO = 0.015", "TOLERANCIA_DO_CHAO = 1.5")], False),
    ("a amplitude minima vira zero", [
        ("conferidor", "MOVIMENTO_MINIMO = 0.03", "MOVIMENTO_MINIMO = 0.0")], False),
    ("o salto deixa de precisar sair do chao", [
        ("conferidor", '"salto": 0.25', '"salto": 0.0')], False),
    # --- a lista do que e medido ---
    ("uma animacao sai da lista do que e conferido", [
        ("conferidor", '\t"parado", "andando", "correndo",',
         '\t"parado", "andando",')], False),
    # --- faixas de duracao ---
    ("a faixa da corrida e alargada", [
        ("conferidor", '"correndo": (0.67, 1.13),', '"correndo": (0.01, 9.99),')], False),
    ("a faixa de um gesto sai dos quartis", [
        ("conferidor", '"giro": (0.83, 1.40),', '"giro": (0.60, 1.40),')], False),
    ("o documento muda os quartis e o codigo nao", [
        ("doc", "p25 **0,83** · p75 **1,40**", "p25 **0,60** · p75 **1,40**")], False),
    # --- altura e cadencia ---
    ("o gerador encolhe o personagem", [
        ("gerador", "ALTURA = 1.75", "ALTURA = 1.20")], False),
    ("a cadencia do conferidor deixa de ser 30", [
        ("conferidor", "CADENCIA = 30.0", "CADENCIA = 24.0")], False),
    # --- os numeros DERIVADOS do documento ---
    ("o pulso derivado no documento fica errado", [
        ("doc", "| pulso 0,872 |", "| pulso 0,999 |")], False),
    ("a coluna em metros do tornozelo fica errada", [
        ("doc", "| tornozelo | 0,093 | 0,057 – 0,123 | 0,163 |",
         "| tornozelo | 0,093 | 0,057 – 0,123 | 9,999 |")], False),
    ("a altura mediana do elenco fica errada", [
        ("doc", "mediana 1,764** — 15% de variação",
         "mediana 9,999** — 15% de variação")], False),
    # --- byte de controle em texto ---
    ("um byte de controle entra num arquivo publicado", [
        ("claude", "Blender Foundation", "Blender\x08Foundation")], False),
    # --- o ARTEFATO ---
    #
    # A guarda nova (exportar para um temporario e so publicar se passar) faz o
    # gerador se RECUSAR a deixar artefato ruim no disco — o que e a defesa
    # funcionando, e o que impede a mutacao de produzir a divergencia pelo
    # caminho normal. Para testar a conferencia do artefato, a mutacao desliga
    # a guarda de proposito e depois devolve o codigo ao normal.
    ("o boneco exportado tem outra duracao que o gerador", [
        ("gerador", "(60, pose(peito=(2, 0, 0), cabeca=(1.5, 0, 0),",
         "(20, pose(peito=(2, 0, 0), cabeca=(1.5, 0, 0),"),
        ("gerador", "	return resultado.returncode", "	return 0")], True),
    ("o boneco exportado tem outra proporcao que o gerador", [
        ("gerador", '"pescoco": 0.763,', '"pescoco": 0.790,'),
        ("gerador", "	return resultado.returncode", "	return 0")], True),

    # --- a faixa de DURACAO, alargada nos dois lugares (o instantaneo ancora) ---
    ("a faixa de duracao e alargada no documento E no conferidor", [
        ("doc", "| `run` | 0,67 / 0,80 / 1,13 s |", "| `run` | 0,10 / 0,80 / 9,13 s |"),
        ("conferidor", '"correndo": (0.67, 1.13),', '"correndo": (0.10, 9.13),')], False),
    ("os quartis sao alargados nos dois lugares", [
        ("doc", "p25 **0,83** · p75 **1,40**", "p25 **0,10** · p75 **9,00**"),
        ("conferidor", '"estocada": (0.83, 1.40),', '"estocada": (0.10, 9.00),')], False),
    # --- byte de controle vizinho do que motivou a conferencia ---
    ("um byte 0x0B entra num arquivo publicado", [
        ("claude", "Blender Foundation", "Blender" + chr(11) + "Foundation")], False),
]

def roda_conferidor():
    return subprocess.run([sys.executable, "tools/conferir_numeros.py"],
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace", cwd=RAIZ)


def main():
    originais = {k: io.open(v, "rb").read() for k, v in ALVOS.items()}
    glb_original = io.open(GLB, "rb").read()
    escaparam = []
    try:
        for titulo, edicoes, regerar in MUTACOES:
            invalida = False
            # **Acumula por arquivo.** Duas edicoes no mesmo alvo partindo do
            # original cada uma perdiam a primeira — a mutacao aplicada era
            # metade da que o titulo dizia, e passar virava informacao falsa.
            pendentes = {}
            for alvo, velho, novo in edicoes:
                fonte = pendentes.get(alvo, originais[alvo].decode("utf-8"))
                if fonte.count(velho) != 1:
                    print("PADRAO INVALIDO (%d): %s" % (fonte.count(velho), titulo))
                    escaparam.append(titulo)
                    invalida = True
                    break
                pendentes[alvo] = fonte.replace(velho, novo, 1)
            for alvo, texto in pendentes.items():
                io.open(ALVOS[alvo], "w", encoding="utf-8", newline="").write(texto)
            if invalida:
                for k, v in ALVOS.items():
                    io.open(v, "wb").write(originais[k])
                continue

            if regerar:
                # Gera o `.glb` a partir do codigo MUTADO e depois devolve o
                # codigo ao normal — que e exatamente o estado que ja foi
                # commitado uma vez: artefato de um lado, fonte do outro.
                subprocess.run([BLENDER, "--background", "--python",
                                ALVOS["gerador"]], capture_output=True, cwd=RAIZ)
                for k, v in ALVOS.items():
                    io.open(v, "wb").write(originais[k])

            r = roda_conferidor()

            for k, v in ALVOS.items():
                io.open(v, "wb").write(originais[k])
            if regerar:
                io.open(GLB, "wb").write(glb_original)

            if r.returncode == 0:
                print("ESCAPOU  %s" % titulo)
                escaparam.append(titulo)
            else:
                motivo = [l.strip() for l in (r.stderr or "").splitlines()
                          if l.strip().startswith("-")]
                print("pegou    %-56s -> %s"
                      % (titulo, motivo[0][:100] if motivo else "?"))
    finally:
        for k, v in ALVOS.items():
            io.open(v, "wb").write(originais[k])
        io.open(GLB, "wb").write(glb_original)

    if escaparam:
        print("\n%d de %d escaparam: %s" % (len(escaparam), len(MUTACOES), escaparam))
        return 1
    print("\ntodas as %d mutacoes foram pegas" % len(MUTACOES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
