# -*- coding: utf-8 -*-
"""Quebra a concordancia documento<->codigo<->artefato e exige reprovacao."""
import io
import os
import re
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
    ## A lista de nomes que o JOGO pede. Ela entrou nos alvos junto com a
    ## conferencia que a compara com o gerador e com o `.glb`: enquanto nao
    ## havia essa conferencia, o jogo pediu oito clipes do Royal Crown que
    ## nunca existiram no nosso arquivo, com tudo verde.
    "vocabulario": os.path.join(
        RAIZ, "scripts", "gameplay", "vocabulario_de_animacao.gd"),
    ## E um dos consumidores, para provar que nome escrito a mao reprova.
    "caminhada": os.path.join(
        RAIZ, "scripts", "gameplay", "gesto_de_caminhada.gd"),
    ## A camada que TOCA os clipes de reacao. Sem ela nos alvos, "o clipe
    ## existe" e tudo que o projeto sabia — e existir nao e ser tocado.
    "reacao": os.path.join(RAIZ, "scripts", "gameplay", "gesto_de_reacao.gd"),
    ## Quem escolhe o clipe da conjuracao.
    "conjuracao": os.path.join(
        RAIZ, "scripts", "gameplay", "gesto_de_conjuracao.gd"),
    ## E quem poe os ciclos em ciclo ao carregar.
    "boneco": os.path.join(RAIZ, "scripts", "gameplay", "boneco.gd"),
    ## A roda que percorre o vocabulario inteiro — o unico consumidor de
    ## metade dos clipes, e a unica conferencia que toca TODOS eles.
    "roda": os.path.join(RAIZ, "scripts", "gameplay", "roda_de_animacao.gd"),
}
## **Todo artefato rastreado que o gerador escreve.** Restaurar so o `.glb`
## deixava o `.blend` da ultima mutacao no disco, e ele foi commitado assim —
## a mesma falha que esta lista corrigiu para o `.glb`, no irmao dele.
ARTEFATOS = [
    os.path.join(RAIZ, "arte", "personagem.glb"),
    os.path.join(RAIZ, "arte", "fonte", "personagem.blend"),
]

def _achando(alvo, padrao, troca):
    """Monta `(velho, novo)` a partir do texto ATUAL do arquivo.

    **Padrao literal envelhece, e a suite so pode acusar isso DEPOIS.** Quatro
    mutacoes escaparam de uma rodada inteira por casar ZERO vezes: o
    vocabulario cresceu de 8 clipes para 25, e com ele a linha de `TODOS`, o
    conjunto `EM_CICLO` e o numero de cobertura publicado no §3 — os tres
    escritos a mao aqui. Nenhuma delas testou nada, e o placar disse "escapou",
    que e a leitura certa e tardia.

    Derivando o literal na hora, o padrao acompanha o arquivo. Se um dia ele
    parar de achar, isto morre em voz alta em vez de virar mutacao vazia.
    """
    fonte = io.open(ALVOS[alvo], encoding="utf-8").read()
    achado = re.search(padrao, fonte)
    if achado is None:
        raise SystemExit(
            "a mutacao nao acha o padrao em %s: %s" % (alvo, padrao))
    return (achado.group(0), troca(achado))


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
    # --- o INSTANTANEO: a terceira fonte tambem precisa de prova ---
    ("o instantaneo mede outra coisa que o documento", [
        ("instantaneo", "   0.763,", "   0.790,")], False),
    # --- a tabela de LARGURAS, que ficou sem ancora uma rodada inteira ---
    ("cabecas de altura fica se conferindo sozinha", [
        ("doc", "| cabeças de altura¹ | 4,22 | 3,43 – 4,88 |",
         "| cabeças de altura¹ | 9,99 | 3,43 – 4,88 |")], False),
    ("a altura da cabeca fica se conferindo sozinha", [
        ("doc", "| altura da cabeça / altura | 0,237 | 0,205 – 0,292 |",
         "| altura da cabeça / altura | 0,900 | 0,205 – 0,292 |")], False),
    ("uma linha de largura perde a ancora", [
        ("doc", "| vão das mãos / altura |", "| vao das maos (renomeada) |")], False),
    # --- as ancoras das duas tabelas ---
    ("a fracao do §9 deixa de ser a do gerador", [
        ("doc", "| tornozelo 0,163 | 0,093 × altura |",
         "| tornozelo 0,350 | 0,200 × altura |")], False),
    ("uma linha do §1 sem ancora fica se conferindo sozinha", [
        ("doc", "| lombar | 0,557 | 0,476 – 0,575 | 0,975 |",
         "| lombar | 0,900 | 0,476 – 0,575 | 1,575 |")], False),
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
    # --- o VOCABULARIO: o que o jogo pede contra o que o boneco tem ---
    #
    # Nenhuma destas era pega antes, e o buraco que elas fecham nao era
    # hipotetico: o jogo pedia `run`, `idle`, `swing`, `swing2`, `comboslash`,
    # `shieldrush`, `shieldthrow` e `shieldwall`, e nenhum dos oito existia.
    # **A ancora e a linha de TODOS, e nao a dos cinco gestos**: aquela aparece
    # duas vezes no arquivo — em `TODOS` e em `GESTOS` —, e uma mutacao com
    # padrao ambiguo nao muta nada. A suite acusa isso como PADRAO INVALIDO em
    # vez de contar como pega, que e o comportamento certo: quem esta errada e
    # a mutacao, nao a defesa.
    ("o jogo passa a pedir um clipe que o boneco nao tem", [
        ("vocabulario", *_achando(
            "vocabulario", r"const TODOS: Array\[StringName\] = \[",
            lambda m: m.group(0) + "\n\tINVENTADO,")),
        ("vocabulario", 'const ERGUER: StringName = &"erguer"',
         'const ERGUER: StringName = &"erguer"\n'
         'const INVENTADO: StringName = &"inventado"')], False),
    ("o jogo deixa de conhecer um clipe que o boneco tem", [
        ("vocabulario", *_achando(
            "vocabulario",
            r"const TODOS: Array\[StringName\] = \[\n\tPARADO, ",
            lambda m: "const TODOS: Array[StringName] = [\n\t"))], False),
    ("uma constante do vocabulario fica fora de TODOS", [
        ("vocabulario", 'const PREPARO: StringName = &"preparo"',
         'const PREPARO: StringName = &"preparo"\n'
         'const ORFAO: StringName = &"orfao"')], False),
    ("um nome de clipe volta a ser escrito a mao", [
        ("caminhada", "_boneco.tocar(_clipe_de_locomocao(rapidez))",
         '_boneco.tocar("run")')], False),
    # --- ciclo x uma vez, nas quatro fontes ---
    ("o jogo poe em ciclo algo que o gerador nao poe", [
        ("vocabulario", "const CICLOS: Array[StringName] = [\n\tPARADO, ANDANDO, CORRENDO,",
         "const CICLOS: Array[StringName] = [\n\tPARADO, ANDANDO,")], False),
    ("o conferidor deixa de exigir que um ciclo feche", [
        ("conferidor", *_achando(
            "conferidor", r'EM_CICLO = \{"parado", ',
            lambda m: 'EM_CICLO = {'))], False),
    ("a folga de fechamento de ciclo vira meio metro", [
        ("conferidor", "FECHAMENTO_DO_CICLO = 0.005",
         "FECHAMENTO_DO_CICLO = 0.5")], False),
    ("o documento diz que a corrida nao e ciclo", [
        ("doc", "| 0,67 / 0,80 / 1,13 s | ciclo |",
         "| 0,67 / 0,80 / 1,13 s | uma vez |")], False),
    # --- a INTEGRACAO: o clipe existe e o jogo o toca? ---
    #
    # As duas de baixo passam pela sonda de ritmo, que e a unica ferramenta que
    # abre o jogo. Sem elas, "levou_dano existe no `.glb`" era tudo que o
    # projeto sabia sobre a reacao — e o buraco entre existir e ser tocado e
    # exatamente onde estavam os oito nomes do Royal Crown.
    ("o corpo deixa de reagir ao dano", [
        ("reacao", "\t_combatente.damaged.connect(_ao_levar_dano)",
         "\tpass")], False),
    ("o corpo nao desenha o atordoamento", [
        ("reacao", "\t\t_tocar(VocabularioDeAnimacao.ATORDOADO)",
         "\t\tpass")], False),
    # **Entrar sem sair.** O corpo entra no atordoamento e nunca larga a pose,
    # e a conferencia de ENTRADA aprova isso — foi o par que faltou.
    ("o corpo entra no atordoamento e nao sai", [
        ("reacao", "\tvar preso: bool = _combatente.unit.status.has_any(PARALISADO)",
         "\tvar preso: bool = _atordoado or _combatente.unit.status.has_any(PARALISADO)")],
     False),
    ("o corpo nao cai ao morrer", [
        ("reacao", "\t\t_boneco.tocar(VocabularioDeAnimacao.MORTE, true)",
         "\t\tpass")], False),
    ("o morto volta a andar", [
        ("reacao", "\treturn _morto or _atordoado or _restante > 0.0",
         "\treturn _atordoado or _restante > 0.0")], False),
    ("a roda nao toca o clipe que anuncia", [
        ("roda", "\t_boneco.tocar(nome, true)", "\tpass")], False),
    ("a caminhada nao da passagem para a roda", [
        ("caminhada", "\tif _roda != null and _roda.esta_mostrando():\n\t\treturn",
         "\tif false:\n\t\treturn")], False),
    ("a roda perde a posicao desligada", [
        ("roda", "\tvar quantas: int = VocabularioDeAnimacao.TODOS.size()",
         "\tvar quantas: int = VocabularioDeAnimacao.TODOS.size() - 1")], False),
    # --- para onde o boneco OLHA ---
    #
    # **Nenhuma ferramenta media isto**, e o defeito chegou a tela do usuario:
    # *"nem de frente o boneco ta"*. A viseira e o bico do sapato apontam para
    # +Z no `.glb` — que e o que a especificacao do glTF manda —, e a frente de
    # um no na Godot e -Z. Quatro conferencias verdes mediam TAMANHO; nenhuma
    # perguntava para que lado a cara aponta.
    ("o boneco volta a andar de costas", [
        ("boneco",
         "@export var giro_do_modelo: Vector3 = Vector3(0.0, 180.0, 0.0)",
         "@export var giro_do_modelo: Vector3 = Vector3(0.0, 0.0, 0.0)")], False),
    # E o par obrigatorio: a conferencia nao pode aprovar por NAO ACHAR o
    # rosto. Sem o material a projecao nao tem o que medir, e "nao achei" tem
    # que reprovar — a armadilha do padrao orfao, que este projeto ja pagou.
    ("o rosto perde o material que o identifica", [
        ("gerador", '(0.25, 0.02, 0.08), "rosto"),',
         '(0.25, 0.02, 0.08), "pele"),')], True),
    ("os ciclos deixam de ser postos em ciclo ao carregar", [
        ("boneco", "\t\t_animador.get_animation(nome).loop_mode = Animation.LOOP_LINEAR",
         "\t\tpass")], False),
    # --- a regra do §5: conjurar andando dura um ciclo de corrida ---
    ("o arremesso em movimento deixa de durar um ciclo de corrida", [
        ("gerador", "\t\t\t(24, pose(\n\t\t\t\tcoxa_D=(-38, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-38, 14, -12),\n\t\t\t\tcoxa_E=(34, 0, 0), canela_E=(10, 0, 0), pe_E=pe(34, 10, 10),\n\t\t\t\tbraco_D=(46, -8, 0), antebraco_D=(-78, 0, 0),\n\t\t\t\tbraco_E=(-46, 8, 0), antebraco_E=(-78, 0, 0),\n\t\t\t\tpeito=(15, 0, 0), cabeca=(-8, 0, 0))),\n\t\t],\n\t},\n\t# Arremesso indo atr",
         "\t\t\t(30, pose(\n\t\t\t\tcoxa_D=(-38, 0, 0), canela_D=(14, 0, 0), pe_D=pe(-38, 14, -12),\n\t\t\t\tcoxa_E=(34, 0, 0), canela_E=(10, 0, 0), pe_E=pe(34, 10, 10),\n\t\t\t\tbraco_D=(46, -8, 0), antebraco_D=(-78, 0, 0),\n\t\t\t\tbraco_E=(-46, 8, 0), antebraco_E=(-78, 0, 0),\n\t\t\t\tpeito=(15, 0, 0), cabeca=(-8, 0, 0))),\n\t\t],\n\t},\n\t# Arremesso indo atr")], False),
    ("conjurar andando deixa de escolher o clipe de andando", [
        ("conjuracao", "\tif em_movimento != &\"\" and not result.started():",
         "\tif false:")], False),
    ("conjurar andando escolhe sempre o mesmo lado", [
        ("conjuracao", "\tif plana.dot(frente) >= 0.0:", "\tif true:")], False),
    ("o projetil volta a ser desenhado como estocada", [
        ("conjuracao", "\t\t\t\treturn Gesto.ARREMESSO",
         "\t\t\t\treturn Gesto.ESTOCADA")], False),
    # --- os dois numeros novos do documento ---
    ("a contagem de tolerancias do §9 fica errada", [
        ("doc", "6 números não saem de faixa nenhuma",
         "5 números não saem de faixa nenhuma")], False),
    ("a cobertura publicada no §3 fica errada", [
        ("doc", *_achando(
            "doc", r"nosso boneco tem \*\*\d+ dos 22\*\*",
            lambda m: "nosso boneco tem **9 dos 22**"))], False),
    # **O alvo desta mutacao mudou de lugar, e o motivo vale registrar.** Ela
    # renomeava a entrada `"mao_E"` de `CAIXAS`, que era escrita a mao. `CAIXAS`
    # passou a ser DERIVADA da esbeltez medida, aquela linha sumiu, e a suite
    # acusou padrao orfao — que e o comportamento certo, e foi como isto foi
    # descoberto antes de rodar 40 minutos.
    #
    # Hoje ela some com a peca no LACO que monta o corpo, e nao numa
    # declaracao. E de proposito: mutar `REGIAO_DO_OSSO` mudaria os dois lados
    # da conta ao mesmo tempo — a peca sumiria E o numero esperado cairia
    # junto —, e a conferencia passaria. Mutacao que se cancela nao prova nada.
    ("o corpo exportado perde uma peca", [
        ("gerador", "		if nome not in CAIXAS:",
         "		if nome not in CAIXAS or nome == \"mao_E\":"),
        ("gerador", "	return resultado.returncode", "	return 0")], True),
]

def _conferir_os_padroes(pares):
    """Todo padrao casa exatamente uma vez, ANTES de rodar qualquer coisa.

    **Padrao que nao casa nao testa nada, e a suite so descobria no fim.** Numa
    rodada, quatro mutacoes casaram zero vezes porque os arquivos cresceram, e
    isso custou os quarenta minutos inteiros para aparecer — no placar, como
    "escapou", que e a palavra certa e a hora errada.

    Aqui a mesma informacao sai em um segundo, e sai como ERRO: uma suite de
    mutacao com padrao morto e uma suite que mede menos do que diz medir.
    """
    ruins = []
    for titulo, alvo, velho in pares:
        quantas = io.open(alvo, encoding="utf-8").read().count(velho)
        if quantas != 1:
            ruins.append("  %-56s casa %d vezes" % (titulo, quantas))
    if ruins:
        print("PADROES QUE NAO TESTAM NADA:")
        print("\n".join(ruins))
        print("conserte-os antes de rodar: uma mutacao que nao aplica nao "
              "prova defesa nenhuma.")
    return not ruins


def _restaurar(artefatos, ausentes):
    """Devolve cada artefato ao byte, e apaga o que nao existia antes.

    **E confere que conseguiu.** Uma suite que restaura errado deixa o
    repositorio sujo em silencio, e ja deixou: uma delas restaurava texto
    convertendo LF em CRLF, o que nao produz hunk nenhum no `git diff` — ou
    seja, o metodo com que eu conferia nao podia ter visto.
    """
    for caminho, bruto in artefatos.items():
        io.open(caminho, "wb").write(bruto)
        if io.open(caminho, "rb").read() != bruto:
            print("ATENCAO: nao consegui restaurar %s" % caminho)
    for caminho in ausentes:
        if os.path.exists(caminho):
            os.remove(caminho)


def roda_conferidor():
    return subprocess.run([sys.executable, "tools/conferir_numeros.py"],
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace", cwd=RAIZ,
                       # A suite avisa que e ela: a trava e para
                       # gente e revisor, nao para quem a segura.
                       env={**os.environ, "MUTACAO_EM_CURSO": "1"})


## Enquanto este arquivo existe, o repositorio esta MUTADO. Ele serve para duas
## coisas: impedir duas suites ao mesmo tempo — elas mexem nos mesmos arquivos e
## sobrepo-las corrompe as duas — e fazer `conferir_numeros.py` reprovar
## qualquer medicao tirada no meio de uma rodada. Uma medida feita sobre uma
## arvore mutada e pior que medida nenhuma: ela parece uma medida.
TRAVA = os.path.join(RAIZ, ".mutacao-em-curso")


def main():
    if not _conferir_os_padroes([
        (titulo, ALVOS[alvo], velho)
        for titulo, edicoes, _r in MUTACOES
        for alvo, velho, _novo in edicoes
    ]):
        return 1
    if os.path.exists(TRAVA):
        print("ja existe uma rodada de mutacao em curso (%s)." % TRAVA)
        print("se nao existe, apague o arquivo — uma rodada morta o deixa para tras.")
        return 1
    io.open(TRAVA, "w", encoding="utf-8").write(
        "mutar_direcao.py esta mexendo nos arquivos deste repositorio\n")
    originais = {k: io.open(v, "rb").read() for k, v in ALVOS.items()}
    # **Artefato ausente e o estado PADRAO de um clone novo.** O `.blend` nao e
    # rastreado por decisao medida (ele nao e reprodutivel), entao exigir que
    # ele exista fazia a suite morrer com `FileNotFoundError` antes da primeira
    # mutacao — e quem clonasse o repositorio e rodasse o comando publicado no
    # `CLAUDE.md` via um traceback no lugar de 30 de 30.
    artefatos = {caminho: io.open(caminho, "rb").read()
                 for caminho in ARTEFATOS if os.path.exists(caminho)}
    ausentes = [caminho for caminho in ARTEFATOS if caminho not in artefatos]
    if ausentes:
        print("artefatos ausentes (serao apagados no fim se aparecerem): %s"
              % ", ".join(os.path.basename(c) for c in ausentes))
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
                _restaurar(artefatos, ausentes)

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
            if io.open(v, "rb").read() != originais[k]:
                print("ATENCAO: nao consegui restaurar %s" % v)
        _restaurar(artefatos, ausentes)
        os.remove(TRAVA)

    if escaparam:
        print("\n%d de %d escaparam: %s" % (len(escaparam), len(MUTACOES), escaparam))
        return 1
    print("\ntodas as %d mutacoes foram pegas" % len(MUTACOES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
