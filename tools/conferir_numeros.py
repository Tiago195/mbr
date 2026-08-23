#!/usr/bin/env python3
"""Confere os números afirmados na documentação contra o código e os dados.

Existe porque três revalidações seguidas do Passo 4 reprovaram pela **mesma**
espécie de erro: um número escrito num documento contradizendo o código ao
lado. Nunca foi o mesmo número — foi sempre outro. Corrigir um de cada vez não
resolve; o que resolve é a afirmação passar a ser verificável por máquina.

A regra que isto impõe: **número em documento é asserção, e asserção sem
verificação é palpite.** Se um número muda no código, esta ferramenta acusa o
documento que ficou para trás.

Uso:
    py tools/conferir_numeros.py

Sai com código 1 se alguma afirmação não bater. Roda junto da suíte, antes de
commitar documentação.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]


def ler(caminho: str) -> str:
    return (RAIZ / caminho).read_text(encoding="utf-8")


def enum_de(caminho: str, nome: str) -> list[str]:
    """Os valores de um enum GDScript, na ordem."""
    texto = ler(caminho)
    bloco = re.search(r"enum %s \{(.*?)\n\}" % nome, texto, re.S)
    if bloco is None:
        # Enum de uma linha só: `enum Kind { A, B, C }`
        uma_linha = re.search(r"enum %s \{([^}]*)\}" % nome, texto)
        if uma_linha is None:
            return []
        return [v.strip() for v in uma_linha.group(1).split(",") if v.strip()]
    return re.findall(r"^\t([A-Z_]+),", bloco.group(1), re.M)


class Conferencia:
    def __init__(self) -> None:
        self.falhas: list[str] = []
        self.conferidas = 0
        ## Todo motivo pelo qual esta execução conferiu MENOS do que poderia.
        ##
        ## Duas ausências são degradação benigna e estão documentadas como
        ## tal: as tabelas do original (que vivem fora do repositório) e a
        ## engine da Godot. As duas fazem a ferramenta pular afirmações e
        ## ainda assim sair com zero.
        ##
        ## Isto existe porque o **piso publicado** não pode ser cobrado numa
        ## execução degradada, e tratar isso ausência por ausência já falhou:
        ## o desconto foi escrito para o XML e não para a engine, e sem a
        ## Godot por perto a ferramenta acusava o `CLAUDE.md` de publicar um
        ## número que estava certo.
        ##
        ## Cada aviso traz **quanto** ele dispensa, e o piso desconta a soma.
        ## A versão anterior dispensava o piso INTEIRO ao primeiro aviso, e com
        ## isso ficou estritamente mais fraca do que o desconto que substituiu:
        ## sem as tabelas do original dava para perder 27 conferências de
        ## verdade e ainda ler "todas batem". Generalizar não pode custar poder
        ## de detecção — o número já estava calculado, e era só não jogá-lo
        ## fora.
        self.avisos: list[tuple[str, int]] = []

    def avisar(self, texto: str, dispensa: int = 0) -> None:
        """Degradação benigna: imprime, registra, e diz QUANTAS afirmações
        deixaram de acontecer por causa dela.

        **Todo aviso desta ferramenta tem que passar por aqui**, e todo ramo
        benigno novo entra na conta declarando o próprio custo. Um `print`
        solto degrada a execução sem que o piso saiba, e foi assim que a
        segunda ausência escapou.

        `dispensa` zero é legítimo: um aviso que não impede conferência
        nenhuma não precisa afrouxar piso nenhum.
        """
        self.avisos.append((texto, dispensa))
        # O rótulo é montado, e não escrito inteiro, para esta linha — a ÚNICA
        # legítima — não casar com a varredura de `_autoteste`, que procura
        # avisos impressos por fora. Mesmo truque dos marcadores do bloco do
        # XML, e pelo mesmo motivo: código que se lê precisa não se encontrar.
        print("[números] %s: %s" % ("AVISO", texto))

    def dispensadas(self) -> int:
        """Quantas afirmações as degradações desta execução dispensam."""
        return sum(quantas for _texto, quantas in self.avisos)

    def afirma(self, onde: str, texto: str, padrao: str, esperado: int) -> None:
        """O documento diz `padrao` com um número; ele tem que ser `esperado`.

        `padrao` é uma regex com **um** grupo de captura numérico.
        """
        self.conferidas += 1
        achado = re.search(padrao, texto)
        if achado is None:
            self.falhas.append(
                "%s: a afirmação não foi encontrada — o texto mudou e a "
                "conferência ficou órfã. Padrão: %s" % (onde, padrao)
            )
            return
        valor = int(achado.group(1))
        if valor != esperado:
            self.falhas.append(
                "%s: o documento diz %d, o código diz %d (%s)"
                % (onde, valor, esperado, padrao)
            )

    def contem(self, onde: str, texto: str, agulha: str) -> None:
        self.conferidas += 1
        if agulha not in texto:
            self.falhas.append("%s: esperava encontrar %r" % (onde, agulha))


def _contar_testes() -> int:
    """Quantos métodos `test_` existem em `tests/`.

    É exatamente o que o arnês descobre por reflexão: um método sem argumentos
    cujo nome começa com `test_`. Contar estaticamente evita ter que rodar a
    Godot só para conferir um número de documento.
    """
    total = 0
    for arquivo in (RAIZ / "tests").glob("test_*.gd"):
        total += len(re.findall(
            r"^func (test_\w+)\(", arquivo.read_text(encoding="utf-8"), re.M
        ))
    return total


def _marcas_distintas(habilidades: list) -> int:
    marcas: set[str] = set()

    def varre(efeitos: list) -> None:
        for efeito in efeitos:
            if efeito.get("type") == "mark":
                marcas.add(efeito["mark"])
            for chave in ("effects", "on_expire"):
                if isinstance(efeito.get(chave), list):
                    varre(efeito[chave])

    for h in habilidades:
        for pulso in h["pulses"]:
            varre(pulso["effects"])
    return len(marcas)


def _sem_offset_no_corpus(habilidades: list) -> int:
    return sum(
        1
        for h in habilidades
        for pulso in h["pulses"]
        if not pulso.get("forward_offset") and not pulso.get("side_offset")
    )


def _afirmacoes_que_dependem_do_xml() -> int:
    """Quantas afirmações só existem quando o XML do original está por perto.

    Contada no PRÓPRIO fonte, entre os marcadores `<bloco-do-xml>`, e não
    escrita à mão: escrita à mão ela já ficou errada, dizendo 12 onde havia 15.
    """
    # Os marcadores são MONTADOS, e não escritos inteiros: escritos inteiros,
    # a primeira ocorrência de cada um no arquivo é a desta própria função, e
    # a fatia entre elas não contém afirmação nenhuma. A conferência logo
    # abaixo pegou isso na primeira execução — "anuncia 0 e o bloco faz 15".
    abre = "# <" + "bloco-do-xml>"
    fecha = "# </" + "bloco-do-xml>"
    texto = Path(__file__).read_text(encoding="utf-8")
    # O `+ 1` é a autoconferência logo depois do bloco, que some junto com ele.
    # Sem ela a conta não fecha com a queda observável em "N conferidas".
    return texto.count("c.afirma(", texto.index(abre), texto.index(fecha)) + 1


def _numero(texto: str, padrao: str) -> int:
    """O número que um padrão captura, ou -1 quando ele não casa.

    `-1` e não `None` de propósito: quem compara devolve desigualdade em vez
    de estourar, e um padrão que parou de casar vira falha visível em vez de
    conferência que sumiu.

    **Quem usa isto TEM que tratar o -1 como falha, explicitamente.** Uma
    comparação do tipo `if lido > esperado` transforma o -1 em aprovação
    silenciosa, e foi assim que o piso publicado passou a aceitar o próprio
    padrão ficar órfão. `Conferencia.afirma` já trata; comparação escrita à
    mão, não.
    """
    achado = re.search(padrao, texto)
    return int(achado.group(1)) if achado else -1


def _testes_da_secao(caminho: str, titulo: str) -> int:
    """Quantos `func test_` há entre um cabeçalho de seção e o próximo.

    Devolve -1 quando o cabeçalho não existe OU quando não há cabeçalho
    seguinte: sem o de baixo a contagem iria até o fim do arquivo e engoliria
    as seções vizinhas, dando um número maior sem nenhum sinal. Quem chama
    trata o -1 como falha.

    Lê por `ler()`, e não por `Path(caminho)`: com caminho relativo a
    ferramenta estourava `FileNotFoundError` ao ser chamada de fora da raiz do
    repositório — o resto do arquivo é ancorado em `RAIZ` justamente por isso.
    """
    texto = ler(caminho)
    inicio = texto.find(titulo)
    if inicio < 0:
        return -1
    linhas = texto[inicio:].splitlines()[1:]
    quantos = 0
    fechou = False
    for linha in linhas:
        # O próximo cabeçalho de seção fecha a contagem.
        if linha.startswith("# ---"):
            fechou = True
            break
        if linha.startswith("func test_"):
            quantos += 1
    if not fechou:
        return -1
    return quantos


def _emissoes_lacuna(relatorio: str, lacuna: str) -> int:
    """Quantas ocorrências o relatório registra para uma lacuna nomeada."""
    achado = re.search(
        r"\| %s \| (\d+) \|" % re.escape(lacuna), relatorio
    )
    return int(achado.group(1)) if achado else -1


def _emissoes(relatorio: str, peca: str) -> int:
    achado = re.search(r"\| `%s` \| (\d+) \|" % re.escape(peca), relatorio)
    return int(achado.group(1)) if achado else -1


def _medir_no_original() -> dict | None:
    """Mede direto no XML do original. `None` se ele não estiver por perto.

    As tabelas vivem FORA do repositório de propósito, então quem clonar sem
    elas ainda roda o resto da conferência. O que se perde nesse caso está
    dito na saída, para a ausência não parecer aprovação.
    """
    import xml.etree.ElementTree as ET

    xml = Path(r"C:\Godot\rc-referencia\xml")
    if not xml.exists():
        return None

    def linhas(*nomes: str) -> list[dict]:
        saida: list[dict] = []
        for nome in nomes:
            caminho = xml / ("%s.xml" % nome)
            if not caminho.exists():
                continue
            for linha in ET.parse(caminho).getroot():
                saida.append({
                    f.tag.strip(): (f.text or "").strip() for f in linha
                })
        return saida

    skills = linhas(
        "skill_xml", "skill_2_xml", "skill_3_xml", "skill_4_xml"
    )
    impactos_todos = linhas(
        "impact_xml", "impact_2_xml", "impact_3_xml", "impact_4_xml"
    )
    impactos_um = linhas("impact_xml")
    buffs = linhas("buff_xml", "buff_2_xml", "buff_3_xml", "buff_4_xml")

    timings: set[str] = set()
    for r in impactos_todos:
        for parte in (r.get("TriggerTiming") or "").split(","):
            if parte.strip():
                timings.add(parte.strip())

    def marcador(r: dict) -> bool:
        tem_stat = any(r.get("StatType%d" % n) for n in range(1, 5))
        tem_impacto = r.get("Impact1") or r.get("Impact2")
        return bool(r.get("Line")) and not tem_stat and not tem_impacto

    ruido = {
        "Id", "Name", "Desc", "DescParam", "AtlasName", "IconPath",
        "ShowIcon", "Sound", "Line", "Rank", "Duration", "MaxStackCount",
    }
    # `ResetAttackCoolTime` medido de duas formas de propósito: quantas dizem
    # VERDADEIRO e quantas declaram a coluna. As duas são afirmadas em
    # documento, e a diferença entre elas é a armadilha — `"False"` é string
    # não-vazia, e por isso o censo de colunas dá quase o dobro.
    def reset(valor: str) -> bool:
        return (valor or "").strip().lower() == "true"

    return {
        "reset_ataque": sum(1 for r in skills if reset(r.get("ResetAttackCoolTime"))),
        "reset_declarado": sum(
            1 for r in skills if r.get("ResetAttackCoolTime") is not None
        ),
        "timings": len(timings),
        "marcadores": sum(1 for r in buffs if marcador(r)),
        "so_linha": sum(1 for r in buffs if not set(r) - ruido),
        "ajuste_cd": sum(1 for r in buffs if r.get("AdjustCDSkillIds")),
        "impactos": len(impactos_um),
        "sem_offset": sum(
            1 for r in impactos_um
            if r.get("StartPositionX", "0") in ("", "0")
            and r.get("StartPositionZ", "0") in ("", "0")
        ),
    }


def _rodar_suite() -> dict:
    """Roda a suíte e devolve o que ela disse, com o veredito SEPARADO.

    Devolve `{"rodou", "passou", "motivo", "testes", "assercoes"}`.

    **Os três estados são distintos, e confundi-los já custou uma revisão.**
    Isto devolvia `None` tanto para "não consegui rodar a Godot" quanto para
    "rodei e a suíte falhou" — e `main()` tratava `None` como aviso benigno.
    Resultado: a ferramenta imprimia "a SUÍTE FALHOU", imprimia "todas batem",
    e saía com 0. Ela reprovava por número errado num comentário e aprovava
    por suíte vermelha.

    Também lê o **stderr** e o **código de saída**. `SCRIPT ERROR` no console
    com "tudo passou" no resumo é o buraco do arnês que o `CLAUDE.md` descreve:
    erro em tempo de execução aborta só a função onde ocorreu, e um teste que
    estoura DEPOIS da primeira asserção conta como sucesso. Ler só o stdout
    deixava isso passar.
    """
    import os
    import shutil
    import subprocess

    godot = os.environ.get("GODOT_PATH") or shutil.which("godot")
    if godot is None:
        for candidato in (
            r"C:\Godot\Godot_v4.7.2-stable_win64.exe",
            r"C:\Godot\Godot.exe",
        ):
            if Path(candidato).exists():
                godot = candidato
                break
    if godot is None:
        return {"rodou": False, "motivo": "Godot não encontrada"}

    # **Daqui para baixo, tudo é FALHA, não incapacidade.**
    #
    # A engine foi encontrada. Se ela sai com código diferente de zero, morre
    # sem imprimir o resumo, ou trava, isso é a suíte quebrada — não "não
    # consegui conferir". A versão anterior devolvia `rodou: False` nos três
    # casos, e `main()` os tratava como aviso benigno: `EXIT=0`, "todas batem".
    #
    # A trava é o pior deles, e não é hipótese: o `CLAUDE.md` registra que um
    # `SceneTree` headless sem `quit` roda para sempre, e que a suíte trava em
    # vez de falhar. O único modo de falha que este projeto já sofreu era
    # justamente o que a ferramenta deixava passar.
    try:
        processo = subprocess.run(
            [godot, "--headless", "--path", str(RAIZ),
             "--script", "res://tests/run_tests.gd"],
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=300,
        )
    except subprocess.TimeoutExpired:
        return {
            "rodou": True, "passou": False,
            "motivo": "a suíte TRAVOU (300s sem terminar)",
        }
    except Exception as erro:
        return {
            "rodou": True, "passou": False,
            "motivo": "a suíte não chegou a rodar: %s" % erro,
        }

    return _classificar(
        processo.returncode, processo.stdout or "", processo.stderr or ""
    )


def _classificar(codigo: int, saida: str, erros: str) -> dict:
    """O que a execução da suíte quer dizer. Função PURA, e é de propósito.

    Os três bloqueantes desta revisão nasceram aqui dentro, misturados ao
    `subprocess`: a trava que detectava e descartava, os detectores que a ordem
    tornava inalcançáveis, e o motivo fantasma de `SCRIPT ERROR`. Enquanto a
    classificação só existia colada à chamada da engine, conferi-la exigia
    fabricar executáveis falsos à mão — e por isso ela nunca era conferida.

    Separada, ela é exercitável em memória, e `_autoteste()` a exercita a cada
    execução.
    """
    motivos: list[str] = []
    if "FALHA" in saida:
        motivos.append("a suíte reportou falha")
    if codigo != 0:
        motivos.append("a suíte saiu com código %d" % codigo)
    # Só no STDERR. O runner imprime a string "SCRIPT ERROR" no stdout dentro
    # das próprias mensagens de falha ("procure SCRIPT ERROR no console"), e
    # procurar nos dois dava um motivo fantasma em toda falha de asserção.
    for marca in ("SCRIPT ERROR", "leaked at exit"):
        if marca in erros:
            motivos.append("`%s` no console" % marca)

    # A ÚLTIMA ocorrência é o total; as anteriores são uma por suíte. Pegar a
    # primeira dava "17 testes, 120 asserções" — o `test_stats` sozinho.
    achados = re.findall(r"(\d+) testes, (\d+) asserções", saida)
    if not achados:
        motivos.append("a suíte não imprimiu o resumo")
        return {"rodou": True, "passou": False, "motivo": "; ".join(motivos)}

    return {
        "rodou": True,
        "passou": not motivos,
        "motivo": "; ".join(motivos),
        "testes": int(achados[-1][0]),
        "assercoes": int(achados[-1][1]),
    }


## Os cenários que já enganaram esta ferramenta, um por linha.
##
## `(rótulo, código, stdout, stderr, tem que passar?)`. Cada um custou uma
## rodada de revisão adversarial, e a lista é o resumo do que ela ensinou:
## **a ferramenta que confere os outros também precisa de quem a confira.**
CENARIOS_DA_SUITE = [
    ("suíte verde", 0, "  431 testes, 1206 asserções — tudo passou.", "", True),
    ("suíte vermelha", 1, "  431 testes, 1206 asserções — 2 FALHA(S).", "", False),
    # A suíte diz "tudo passou" e sai com 0: só o stderr denuncia. É o buraco
    # do arnês que o `CLAUDE.md` descreve — erro em tempo de execução aborta só
    # a função onde ocorreu, e um teste que estoura depois da primeira asserção
    # conta como sucesso.
    ("estouro em runtime com resumo verde", 0,
     "  431 testes, 1206 asserções — tudo passou.",
     "SCRIPT ERROR: Cannot call method on a null value", False),
    ("vazamento de memória", 0,
     "  431 testes, 1206 asserções — tudo passou.",
     "ObjectDB instances were leaked at exit", False),
    # A engine rodou e morreu sem imprimir nada. Já foi classificado como "não
    # consegui rodar", que em `main()` é aviso benigno.
    ("engine morre sem resumo", 3, "", "SCRIPT ERROR: Parse Error", False),
    ("código diferente de zero com resumo verde", 2,
     "  431 testes, 1206 asserções — tudo passou.", "", False),
    # O runner imprime a string "SCRIPT ERROR" no PRÓPRIO stdout, dentro das
    # mensagens de falha. Procurar nos dois dava motivo fantasma.
    ("falha de asserção não inventa SCRIPT ERROR", 1,
     "  [FALHOU] x — (procure SCRIPT ERROR no console)\n"
     "  431 testes, 1206 asserções — 1 FALHA(S).", "", False),
]


def _autoteste(c: "Conferencia") -> None:
    """Confere a classificação da suíte contra os cenários que já a enganaram.

    Roda sempre, e não atrás de um sinalizador: conferência opcional é
    conferência que ninguém roda.
    """
    # **Todo aviso passa por `Conferencia.avisar`.**
    #
    # O piso publicado deixa de ser cobrado quando houve aviso, e é assim que
    # ele para de reclamar de execução degradada — mas só funciona enquanto
    # nenhum ramo imprimir aviso por fora. Esta varredura é o que impede o
    # terceiro caso de escapar como o segundo escapou: a ausência da engine
    # tinha aviso e não tinha desconto, e a mensagem de falha nem sugeria a
    # causa.
    c.conferidas += 1
    fonte = Path(__file__).read_text(encoding="utf-8")
    # Casa o TEXTO do aviso, e não a FORMA da chamada. A primeira versão era
    # uma regex sobre `print(` seguido de aspas, e por isso uma f-string
    # escapava — sendo que os DOIS avisos existentes interpolam, então
    # f-string é exatamente como o terceiro seria escrito. `avisar()` monta o
    # rótulo em duas partes, e por isso não aparece nesta conta; este
    # comentário também não pode escrevê-lo inteiro, pela mesma razão.
    soltos = fonte.count("[números] " + "AVISO")
    if soltos:
        c.falhas.append(
            "há %d ocorrência(s) do texto de aviso fora de "
            "`Conferencia.avisar`; o piso publicado não as enxerga e vai "
            "cobrar cobertura que a execução não podia ter — use "
            "`c.avisar(texto, quantas)`" % soltos
        )

    for rotulo, codigo, saida, erros, deve_passar in CENARIOS_DA_SUITE:
        # **`rodou` é conferido junto com `passou`, e não é detalhe.**
        #
        # Nos sete cenários a engine RODOU — o que muda é o veredito. Devolver
        # `rodou: False` num deles manda o caso para o ramo benigno de
        # `main()`, que só avisa, e foi assim que "a engine morreu sem imprimir
        # o resumo" atravessou uma rodada inteira. Um autoteste que olhasse só
        # `passou` aceitaria a regressão de volta: sem `passou`, `.get()`
        # devolve `None`, que é falso, que parece "reprovou corretamente".
        c.conferidas += 1
        veredito = _classificar(codigo, saida, erros)
        if not veredito.get("rodou"):
            c.falhas.append(
                "autoteste da ferramenta: `%s` foi classificado como ENGINE "
                "QUE NÃO RODOU; em `main()` isso vira aviso benigno" % rotulo
            )
            continue
        if bool(veredito.get("passou")) == deve_passar:
            continue
        c.falhas.append(
            "autoteste da ferramenta: `%s` devia %s e %s (motivo: %s)" % (
                rotulo,
                "passar" if deve_passar else "reprovar",
                "passou" if veredito.get("passou") else "reprovou",
                veredito.get("motivo") or "nenhum",
            )
        )
    # O motivo fantasma tem conferência PRÓPRIA: o cenário acima já reprova por
    # outros motivos, então "reprovou" não prova que o fantasma sumiu.
    c.conferidas += 1
    fantasma = _classificar(
        1, "  [FALHOU] x — (procure SCRIPT ERROR no console)\n"
        "  431 testes, 1206 asserções — 1 FALHA(S).", ""
    )
    if "SCRIPT ERROR" in fantasma["motivo"]:
        c.falhas.append(
            "autoteste da ferramenta: `SCRIPT ERROR` no stdout do runner virou "
            "motivo; a busca tem que ser só no stderr"
        )


## Nível em que os espaços de campeão são contados. 9 é onde todo ranque do
## original está disponível, e é o padrão do `ChampionSelector`.
##
## **Medido: os números não dependem dele.** 127 e 79 saem iguais nos níveis 1,
## 9 e 18, porque todo grupo de campeão tem ranque disponível já no nível 1 e o
## número de pulsos não muda com o ranque. O nível fica porque medir pelo
## caminho do jogo é o princípio — não porque este valor sustente algum número.
NIVEL_DE_REFERENCIA = 9


def main() -> int:
    c = Conferencia()

    # ---------------------------------------------------------- medições
    atributos = len(re.findall(
        r"^\tId\.([A-Z_]+): &", ler("scripts/core/combat/stat.gd"), re.M
    ))
    estados = len(enum_de("scripts/core/combat/status_set.gd", "Kind"))
    controles = len(enum_de(
        "scripts/core/abilities/effects/crowd_control_effect.gd", "Kind"
    ))
    efeitos = len(list((RAIZ / "scripts/core/abilities/effects").glob("*.gd")))
    eventos = len(enum_de("scripts/core/combat/trigger_set.gd", "Event"))

    corpus = json.loads(ler("data/traducao/habilidades.json"))
    itens = json.loads(ler("data/traducao/itens.json"))
    habilidades = corpus["habilidades"]
    com_pulso = [h for h in habilidades if h["pulses"]]
    varios = [h for h in habilidades if len(h["pulses"]) > 1]
    total_pulsos = sum(len(h["pulses"]) for h in habilidades)
    total_efeitos = sum(len(p["effects"]) for h in habilidades for p in h["pulses"])
    de_skill_xml = [h for h in habilidades if h["source_table"] == "skill_xml"]

    atores = json.loads(ler("data/traducao/atores.json"))["atores"]
    # "Campeão" é mais estreito que `UsageType == Player`, e a diferença é o
    # ponto: 40 linhas de jogador, 33 com kit, 28 com as quatro conjuráveis.
    # Publicar só a primeira daria 40 campeões onde há 28 jogáveis.
    campeoes = [
        a for a in atores
        if a["usage"] == "Player" and len(a["ability_groups"]) >= 3
    ]
    grupos_jogaveis = {h["group_id"] for h in habilidades if h["pulses"]}
    completos = [
        a for a in campeoes
        if all(
            g in grupos_jogaveis
            for g in list(a["ability_groups"]) + [a["ultimate_group"]]
        )
    ]
    com_carga = [a for a in atores if a["ultimate_uses_charge"]]
    enchem_a_suprema = [
        h for h in habilidades if float(h.get("ultimate_charge_gain", 0.0)) > 0.0
    ]
    custos = {
        float(a["ultimate_charge_cost"]) for a in atores
        if float(a.get("ultimate_charge_cost", 0.0)) > 0.0
    }
    ganho_do_basico = {
        float(a["ultimate_charge_on_attack"]) for a in atores
        if a["usage"] == "Player" and float(a.get("ultimate_charge_on_attack", 0.0)) > 0.0
    }
    # A recarga inventada que sobrou depois da carga existir.
    ainda_inventadas = [
        a for a in atores
        if a["usage"] == "Player" and float(a.get("ultimate_cooldown", 0.0)) > 0.0
    ]

    pulsos = [p for h in habilidades for p in h["pulses"]]
    pulsos_projetil = sum(1 for p in pulsos if p["form"] == "PROJECTILE")
    com_duracao = [p for p in pulsos if float(p.get("duration", 0.0)) > 0.0]
    com_leque = [p for p in pulsos if int(p.get("spread_count", 1)) > 1]
    leque_nao_projetil = [p for p in com_leque if p["form"] != "PROJECTILE"]
    conjuracao_longa = [h for h in habilidades if float(h["cast_time"]) > 0.45]

    # Espaços de campeão (Q/W/E/R dos que têm kit) e quantos carregam
    # habilidade de vários golpes. É o número que a lacuna da telegrafia cita,
    # e ele conta ESPAÇOS, não habilidades distintas — dois campeões com o
    # mesmo kit contam duas vezes, porque a lacuna é sobre o que se vê jogando.
    #
    # Duas armadilhas pagas aqui, as duas achadas por revisão adversarial:
    #
    # 1. Descartar campeão SEM SUPREMA descartava também os Q/W/E dele. Era um
    #    campeão (`sasha_1990000`, três espaços, os três de vários golpes), e o
    #    resultado — 124/76 — ficou ancorado por nove afirmações antes de
    #    alguém contar de novo. Âncora firme em número errado é pior que
    #    nenhuma.
    # 2. O ranque era escolhido por `ranques[-1]`, e o JOGO escolhe por
    #    `AbilityCatalog.rank_for_level()`. Hoje os dois dão o mesmo total, mas
    #    divergem num grupo — medir por caminho diferente do que o jogo
    #    percorre é como o número errado nasce.
    por_grupo: dict = {}
    for h in habilidades:
        por_grupo.setdefault(h["group_id"], []).append(h)

    def rank_for_level(grupo: str, nivel: int) -> dict | None:
        # Réplica de `AbilityCatalog.rank_for_level`.
        escolhido = None
        for x in sorted(por_grupo.get(grupo, []), key=lambda x: x["rank"]):
            if x["level_requirement"] <= nivel and x["pulses"]:
                escolhido = x
        return escolhido

    espacos_de_campeao = 0
    espacos_com_varios_golpes = 0
    # Espaços cuja habilidade zera a cadência do ataque básico, e quantos
    # campeões distintos têm ao menos um. Medido pelo MESMO caminho dos
    # outros dois — `rank_for_level`, o que o jogo percorre — porque medir
    # por caminho diferente é como o número errado nasce.
    espacos_com_reset = 0
    campeoes_com_reset: set = set()
    # Espaços cuja habilidade enche a carga da suprema. É o reconto da lacuna
    # 2 pelo caminho do jogo, e ele NÃO tinha conferência: o `CLAUDE.md` dizia
    # "65 → 65" e são 67. Reconto sem asserção é o mesmo que sem reconto.
    espacos_com_carga = 0
    for a in atores:
        if a["usage"] != "Player" or not a["ability_groups"]:
            continue
        grupos = list(a["ability_groups"])
        if a["ultimate_group"]:
            grupos.append(a["ultimate_group"])
        for grupo in grupos:
            escolhida = rank_for_level(grupo, NIVEL_DE_REFERENCIA)
            if escolhida is None:
                continue
            espacos_de_campeao += 1
            com_efeito = [p for p in escolhida["pulses"] if p["effects"]]
            if len(com_efeito) > 1:
                espacos_com_varios_golpes += 1
            if float(escolhida.get("ultimate_charge_gain", 0.0)) > 0.0:
                espacos_com_carga += 1
            if escolhida.get("resets_attack_cooldown"):
                espacos_com_reset += 1
                campeoes_com_reset.add(a["id"])
    hab_projetil = [
        h for h in habilidades
        if any(p["form"] == "PROJECTILE" for p in h["pulses"])
    ]

    relatorio = ler("data/traducao/RELATORIO.md")
    doc10 = ler("docs/10-traducao-do-original.md")
    claude = ler("CLAUDE.md")

    # ---------------------------------------------------------- docs/10
    c.afirma("docs/10 atributos", doc10, r"### Atributos: 18 → (\d+)", atributos)
    c.afirma("docs/10 estados", doc10, r"\*\*4 → (\d+)\*\*", estados)
    c.afirma("docs/10 controles", doc10, r"\*\*5 → (\d+)\*\*", controles)
    c.afirma("docs/10 efeitos", doc10, r"### Efeitos: 6 → (\d+)", efeitos)
    c.afirma("docs/10 corpus", doc10,
             r"\| Habilidades traduzidas \| \*\*(\d+)\*\*", len(habilidades))
    c.afirma("docs/10 com pulso", doc10,
             r"\| \.\.\.com pelo menos um pulso \| (\d+) \|", len(com_pulso))
    c.afirma("docs/10 vários pulsos", doc10,
             r"\| \.\.\.com mais de um pulso \| (\d+) \|", len(varios))
    c.afirma("docs/10 pulsos", doc10, r"\| Pulsos \| (\d+) \|", total_pulsos)
    c.afirma("docs/10 efeitos gerados", doc10,
             r"\| Efeitos \| (\d+) \|", total_efeitos)
    c.afirma("docs/10 itens", doc10,
             r"\| Itens \| \*\*(\d+)\*\*", itens["total"])
    c.afirma("docs/10 conjuráveis", doc10,
             r"conjura as \*\*(\d+) que têm pulso\*\*", len(com_pulso))
    c.afirma("docs/10 skill_xml", doc10,
             r"as (\d+) de `skill_xml`", len(de_skill_xml))

    # ---------------------------------------------------------- relatório
    c.afirma("RELATORIO cobertura", relatorio,
             r"\| Habilidades traduzidas \| \*\*(\d+)\*\*", len(habilidades))
    c.afirma("RELATORIO com pulso", relatorio,
             r"\| \.\.\.com pelo menos um pulso \| (\d+) \|", len(com_pulso))
    c.afirma("RELATORIO atores", relatorio,
             r"\| Atores traduzidos \| \*\*(\d+)\*\*", len(atores))
    c.afirma("RELATORIO campeões com kit", relatorio,
             r"\| Campeões com Q, W e E \| \*\*(\d+)\*\*", len(campeoes))
    c.afirma("RELATORIO campeões completos", relatorio,
             r"\| \.\.\.com \*\*as quatro\*\* habilidades conjuráveis \| "
             r"\*\*(\d+)\*\*", len(completos))

    # ---------------------------------------------------------- atores
    c.afirma("CLAUDE.md atores", claude,
             r"\*\*(\d+) atores\*\* traduzidos", len(atores))
    c.afirma("CLAUDE.md campeões com kit", claude,
             r"(\d+) campeões com kit", len(campeoes))
    c.afirma("CLAUDE.md campeões jogáveis", claude,
             r"\*\*(\d+) deles com as quatro habilidades\*\*", len(completos))
    c.afirma("docs/10 atores", doc10,
             r"\| Atores \| \*\*(\d+)\*\*", len(atores))
    c.afirma("docs/10 campeões com kit", doc10,
             r"\| \.\.\.campeões com kit \| (\d+) \|", len(campeoes))
    c.afirma("docs/10 campeões completos", doc10,
             r"\| \.\.\.com as quatro conjuráveis \| (\d+) \|", len(completos))
    c.afirma("docs/10 supremas por carga", doc10,
             r"(\d+) supremas enchem batendo", len(com_carga))
    # ---------------------------------------------------------- projéteis
    c.afirma("CLAUDE.md pulsos de projétil", claude,
             r"\*\*(\d+) pulsos de projétil\*\*", pulsos_projetil)
    c.afirma("CLAUDE.md habilidades com projétil", claude,
             r"\*\*(\d+) habilidades\*\*\.", len(hab_projetil))
    c.afirma("docs/02 pulsos de projétil",
             ler("docs/02-decisoes-tecnicas.md"),
             r"São (\d+) pulsos de projétil no corpus", pulsos_projetil)
    c.afirma("docs/02 habilidades com projétil",
             ler("docs/02-decisoes-tecnicas.md"),
             r"pulsos de projétil no corpus traduzido, em (\d+) habilidades",
             len(hab_projetil))

    # ---------------------------------------------------- carga de suprema
    ability = ler("scripts/core/abilities/ability.gd")
    stat = ler("scripts/core/combat/stat.gd")
    unidade = ler("scripts/core/combat/unit.gd")
    c.afirma("ability.gd habilidades que enchem", ability,
             r"\*\*(\d+) habilidades\*\* declaram", len(enchem_a_suprema))
    # A FAIXA também. Ela entrou em três documentos como "133 a 433" e o
    # medido era 33 a 600 — a afirmação nova tinha sido ancorada pela metade,
    # que é a mesma espécie de erro que esta ferramenta existe para pegar.
    ganhos = [float(h["ultimate_charge_gain"]) for h in enchem_a_suprema]
    # Cada padrão carrega o CONTEXTO da frase, e não só o `**n a n**`. Um
    # padrão posicional casaria a primeira ocorrência do arquivo, e um futuro
    # "**1 a 5**" escrito antes sequestraria a conferência sem ruído.
    for onde, texto, prefixo in (
        ("ability.gd", ability, "declaram, de "),
        ("docs/02", ler("docs/02-decisoes-tecnicas.md"), "rendem de "),
        ("docs/10", ler("docs/10-traducao-do-original.md"), "demais de "),
    ):
        c.afirma("%s ganho mínimo" % onde, texto,
                 re.escape(prefixo) + r"\*\*(\d+) a \d+\*\*", int(min(ganhos)))
        c.afirma("%s ganho máximo" % onde, texto,
                 re.escape(prefixo) + r"\*\*\d+ a (\d+)\*\*", int(max(ganhos)))
    c.afirma("stat.gd campeões com carga", stat,
             r"\*\*1000 nos (\d+) campeões", len(com_carga))
    c.afirma("unit.gd ganho do ataque básico", unidade,
             r"vale \*\*200 nos (\d+)\*\*", len(com_carga))
    # O custo é o MESMO nos 31 — é régua do sistema, não característica de
    # personagem. Se um dia deixar de ser, a afirmação de `stat.gd` mente.
    c.conferidas += 1
    if len(custos) != 1 or 1000.0 not in custos:
        c.falhas.append(
            "o custo da suprema deixou de ser 1000 para todos: %s" % sorted(custos)
        )
    c.conferidas += 1
    if len(ganho_do_basico) != 1 or 200.0 not in ganho_do_basico:
        c.falhas.append(
            "o ganho do ataque básico deixou de ser 200 para todos: %s"
            % sorted(ganho_do_basico)
        )

    # -------------------------------------------------------- telegrafia
    caster = ler("scripts/gameplay/ability_caster.gd")
    resultado = ler("scripts/core/abilities/cast_result.gd")
    c.afirma("ability_caster.gd espaços de campeão", caster,
             r"\*\*(\d+) espaços de campeão\*\*", espacos_de_campeao)
    c.afirma("ability_caster.gd espaços com vários golpes", caster,
             r"\*\*(\d+) têm vários golpes\*\*", espacos_com_varios_golpes)
    c.afirma("cast_result.gd espaços com vários golpes", resultado,
             r"\*\*(\d+) dos \d+\*\* espaços de campeão", espacos_com_varios_golpes)
    c.afirma("cast_result.gd espaços de campeão", resultado,
             r"\*\*\d+ dos (\d+)\*\* espaços de campeão", espacos_de_campeao)
    c.afirma("ability_caster.gd pulsos do corpus", caster,
             r"\*\*(\d+) pulsos\*\* do corpus", len(pulsos))
    c.afirma("ability_caster.gd pulsos com duração", caster,
             r"\*\*(\d+) declaram duração\*\*", len(com_duracao))
    c.afirma("ability_caster.gd pulsos com leque", caster,
             r"\*\*(\d+) pulsos com leque\*\*", len(com_leque))
    c.afirma("ability_caster.gd leque não-projétil", caster,
             r"\*\*(\d+) não são projétil\*\*", len(leque_nao_projetil))
    c.afirma("projectile_set.gd projéteis sem velocidade",
             ler("scripts/core/abilities/projectile_set.gd"),
             r"\*\*(\d+) pulsos de projétil sem velocidade\*\*",
             sum(1 for p in pulsos
                 if p["form"] == "PROJECTILE"
                 and float(p.get("projectile_speed", 0.0)) <= 0.0))
    # O reset de auto-ataque, do lado do corpus. A contagem do XML é conferida
    # noutro lugar; esta pega o campo sumir do JSON sem o XML mudar — que é o
    # jeito silencioso de a tradução regredir.
    doc02_ritmo = ler("docs/02-decisoes-tecnicas.md")
    ability_gd = ler("scripts/core/abilities/ability.gd")
    c.afirma("ability.gd espaços com reset", ability_gd,
             r"\*\*(\d+) dos \d+ espaços de campeão\*\*", espacos_com_reset)
    c.afirma("ability.gd espaços de campeão", ability_gd,
             r"\*\*\d+ dos (\d+) espaços de campeão\*\*", espacos_de_campeao)
    c.afirma("ability.gd campeões com reset", ability_gd,
             r"\*\*(\d+) campeões\*\* têm ao menos um", len(campeoes_com_reset))
    c.afirma("unit.gd espaços com reset",
             ler("scripts/core/combat/unit.gd"),
             r"(\d+) dos \d+ espaços de campeão", espacos_com_reset)
    # A linha dos três recontos do `CLAUDE.md`, afirmada inteira. Ela existe
    # justamente para dizer que o número da tabela não é o número do jogo — e
    # uma das três parcelas estava errada.
    c.afirma("CLAUDE.md reconto: vários golpes", claude,
             r"\*\*61 → (\d+)\*\*", espacos_com_varios_golpes)
    c.afirma("CLAUDE.md reconto: carga de suprema", claude,
             r"\*\*65 → (\d+)\*\*", espacos_com_carga)
    c.afirma("CLAUDE.md reconto: reset de ataque", claude,
             r"\*\*43 → (\d+)\*\*", espacos_com_reset)
    c.afirma("CLAUDE.md espaços que enchem a carga", claude,
             r"\*\*(\d+) dos \d+ espaços\*\*\s*\|", espacos_com_carga)

    # ------------------------------- a sonda de ritmo e o que ela afirma
    #
    # Três arquivos citam a MESMA medição — quantos golpes saem quando a trava
    # de cadência de `player.gd` é apagada. Ela já divergiu: 119 na sonda, 120
    # nos dois documentos, e nenhum dos três conferido.
    #
    # **E o número é DERIVÁVEL, não só comparável.** Sem a trava sai um golpe
    # por quadro de física, então são `JANELA × physics_ticks_per_second`. Uma
    # primeira versão desta conferência só exigia que os três concordassem —
    # três arquivos errados do mesmo jeito passariam. Amarrar ao que produz o
    # número é o que a torna verdadeira em vez de coerente.
    ritmo = ler("tools/sondar_ritmo.gd")
    janela = _numero(ritmo, r"const JANELA: float = (\d+)\.0")
    por_segundo = _numero(
        ler("project.godot"), r"physics_ticks_per_second=(\d+)"
    )
    if por_segundo < 0:
        # `project.godot` só grava o que difere do padrão da engine.
        por_segundo = 60
    golpes = {
        "derivado de JANELA": janela * por_segundo if janela > 0 else -1,
        "sondar_ritmo.gd": _numero(ritmo, r"\*\*(\d+) golpes\*\* em dois segundos"),
        "CLAUDE.md": _numero(claude, r"— (\d+) golpes em dois segundos"),
        "docs/02": _numero(doc02_ritmo, r"real: (\d+) golpes em dois segundos"),
    }
    c.conferidas += 1
    # Órfã e divergente são coisas diferentes, e dizer "divergem" quando o
    # padrão sumiu manda o leitor comparar arquivos que estão iguais.
    # `Conferencia.afirma` já separa as duas; comparação escrita à mão, não —
    # e esta é escrita à mão porque compara quatro fontes, não uma.
    orfas = [nome for nome, valor in golpes.items() if valor < 0]
    if orfas:
        c.falhas.append(
            "a conferência dos golpes ficou órfã em %s: o padrão não casa "
            "mais, e o texto por lá mudou" % ", ".join(orfas)
        )
    elif len(set(golpes.values())) != 1:
        c.falhas.append(
            "os golpes sob a mutação da trava divergem entre os arquivos: %s"
            % golpes
        )

    # Quantos testes da suíte do reset são sobre quem NÃO pode zerar. Escrito
    # à mão dizia "metade deles" — nove — e são quatro.
    c.afirma("docs/02 testes de quem não pode zerar", doc02_ritmo,
             r"dos quais \*\*(\d+)\*\* são sobre quem",
             _testes_da_secao("tests/test_reset_de_ataque.gd",
                              "quem NÃO tem o direito de zerar"))

    doc02_reset = ler("docs/02-decisoes-tecnicas.md")
    c.afirma("docs/02 espaços com reset", doc02_reset,
             r"\*\*(\d+) dos \d+ espaços de campeão\*\*", espacos_com_reset)
    c.afirma("docs/02 espaços de campeão (reset)", doc02_reset,
             r"\*\*\d+ dos (\d+) espaços de campeão\*\*", espacos_de_campeao)
    c.afirma("docs/02 campeões com reset", doc02_reset,
             r"\*\*(\d+) campeões\*\*", len(campeoes_com_reset))
    # Quantos testes a suíte do reset tem, afirmado na decisão 18. Contar
    # `func test_` no arquivo é a mesma medida que o runner usa.
    c.afirma("docs/02 testes do reset", doc02_reset,
             r"`tests/test_reset_de_ataque\.gd`: (\d+) testes",
             ler("tests/test_reset_de_ataque.gd").count("\nfunc test_"))
    c.afirma("docs/10 espaços com reset", doc10,
             r"o jogo percorre, são (\d+) dos", espacos_com_reset)
    c.afirma("docs/10 espaços de campeão (reset)", doc10,
             r"o jogo percorre, são \d+ dos (\d+) espaços", espacos_de_campeao)
    # E o corpus tem que concordar com o contador de emissões do tradutor: o
    # campo pode existir no JSON e estar sempre falso.
    c.conferidas += 1
    do_corpus = sum(1 for h in habilidades if h.get("resets_attack_cooldown"))
    do_relatorio = _emissoes(relatorio, "reset de auto-ataque (ResetAttackCoolTime)")
    if do_corpus != do_relatorio:
        c.falhas.append(
            "reset de auto-ataque: o corpus tem %d e o RELATORIO conta %d"
            % (do_corpus, do_relatorio)
        )

    c.afirma("ability_caster.gd conjuração longa", caster,
             r"\*\*(\d+) habilidades com conjuração longa\*\*",
             len(conjuracao_longa))

    c.afirma("actor_profile.gd campeões completos",
             ler("scripts/gameplay/champion_selector.gd"),
             r"Cinco dos (\d+) têm um espaço", len(campeoes))

    # ---------------------------------------------------------- CLAUDE.md
    c.afirma("CLAUDE.md atributos", claude,
             r"atributos \*\*18 → (\d+)\*\*", atributos)
    c.afirma("CLAUDE.md estados", claude, r"grupo \*\*4 → (\d+)\*\*", estados)
    c.afirma("CLAUDE.md controles", claude,
             r"`CrowdControlEffect` de 5 para (\d+)", controles)
    c.afirma("CLAUDE.md efeitos", claude, r"efeitos \*\*6 → (\d+)\*\*", efeitos)
    c.afirma("CLAUDE.md corpus", claude,
             r"— (\d+) habilidades e 421 itens no", len(habilidades))

    # ---------------------------------------------------------- coerência
    # O censo tem que sair vazio: é a promessa central do Passo 4.
    c.contem(
        "RELATORIO censo",
        relatorio,
        "**Nenhuma.** Toda coluna das",
    )
    # E o doc não pode afirmar isso sem o relatório concordar.
    if "Hoje o censo sai vazio" in doc10 and "**Nenhuma.**" not in relatorio:
        c.falhas.append(
            "docs/10 diz que o censo sai vazio, e o RELATORIO.md gerado lista "
            "colunas órfãs. Foi exatamente este o erro da segunda revalidação."
        )
    c.conferidas += 1

    if eventos < 9:
        c.falhas.append("TriggerSet.Event encolheu para %d" % eventos)
    c.conferidas += 1

    # ------------------------------------------- números medidos no original
    #
    # A primeira versão comparava "São **22 valores" com o literal 22 — ou
    # seja, detectava o TEXTO mudar, não o FATO mudar. Conferência tautológica
    # passa sempre, e passar sempre é justamente o que se quer evitar aqui.
    medido = _medir_no_original()
    antes_do_xml = c.conferidas
    if medido is None:
        c.avisar(
            "as tabelas do original não estão em "
            "C:\\Godot\\rc-referencia\\xml; %d afirmações ficaram sem "
            "conferir" % _afirmacoes_que_dependem_do_xml(),
            _afirmacoes_que_dependem_do_xml(),
        )
    else:
        # <bloco-do-xml>
        mark_effect = ler("scripts/core/abilities/effects/mark_effect.gd")
        cooldown_effect = ler("scripts/core/abilities/effects/cooldown_effect.gd")
        pulse = ler("scripts/core/abilities/ability_pulse.gd")

        c.afirma("docs/10 valores de TriggerTiming", doc10,
                 r"São \*\*(\d+) valores", medido["timings"])
        c.afirma("docs/10 buffs marcadores", doc10,
                 r"(\d+) buffs do original caem nesse caso", medido["marcadores"])
        c.afirma("docs/02 buffs marcadores", ler("docs/02-decisoes-tecnicas.md"),
                 r"\*\*Por quê:\*\* (\d+) buffs do original", medido["marcadores"])
        c.afirma("mark_set.gd buffs marcadores",
                 ler("scripts/core/combat/mark_set.gd"),
                 r"topou com (\d+) buffs", medido["marcadores"])
        c.afirma("mark_effect.gd só Line/Rank/Duration", mark_effect,
                 r"\*\*(\d+) deles têm literalmente", medido["so_linha"])
        c.afirma("cooldown_effect.gd buffs", cooldown_effect,
                 r"\*\*(\d+) buffs\*\* do original", medido["ajuste_cd"])
        c.afirma("ability_pulse.gd impactos sem deslocamento", pulse,
                 r"o caso de (\d+) dos", medido["sem_offset"])
        c.afirma("ability_pulse.gd total de impactos", pulse,
                 r"(\d+) impactos de `impact_xml`", medido["impactos"])

        # Reset de auto-ataque, medido no XML e não no corpus: é o que pega o
        # tradutor deixar de ler a coluna. As DUAS contagens são afirmadas
        # porque a diferença entre elas é a armadilha do `"False"`.
        ability = ler("scripts/core/abilities/ability.gd")
        c.afirma("ability.gd reset: declaram verdadeiro", ability,
                 r"\*\*(\d+)\*\* dizem verdadeiro",
                 medido["reset_ataque"])
        c.afirma("ability.gd reset: declaram falso", ability,
                 r"dizem verdadeiro e \*\*(\d+)\*\*",
                 medido["reset_declarado"] - medido["reset_ataque"])
        c.afirma("ability.gd reset: censo da coluna", ability,
                 r"tradutor contava (\d+) porque contava outra coisa",
                 medido["reset_declarado"])
        c.afirma("docs/10 reset de auto-ataque", doc10,
                 r"`ResetAttackCoolTime`, (\d+)", medido["reset_ataque"])
        doc02 = ler("docs/02-decisoes-tecnicas.md")
        c.afirma("docs/02 reset: declaram verdadeiro", doc02,
                 r"\*\*(\d+) habilidades declaram", medido["reset_ataque"])
        c.afirma("docs/02 reset: declaram falso", doc02,
                 r"verdadeiro e (\d+) declaram falso",
                 medido["reset_declarado"] - medido["reset_ataque"])
        c.afirma("docs/02 reset: censo da coluna", doc02,
                 r"\*\*O (\d+) anterior contava", medido["reset_declarado"])
        # </bloco-do-xml>
        # **O número do aviso é ele próprio uma afirmação.** Ele dizia 8, e
        # estava certo; a mudança seguinte escreveu 12 onde havia 15, e nada
        # acusou — é a lição 6 ao pé da letra, a conferência recém-acrescentada
        # sendo a que ninguém confere. Agora ele é CONTADO no próprio fonte, e
        # quando o XML está por perto o contador é comparado com o trabalho
        # que o bloco realmente fez.
        #
        # A própria autoconferência CONTA. Ela também desaparece quando o XML
        # desaparece, e por isso entra dos dois lados: assim o número anunciado
        # é exatamente a queda que se vê em "N afirmações conferidas" ao rodar
        # sem as tabelas. Anunciar 15 com queda de 16 é como o "12" começou.
        c.conferidas += 1
        anunciadas = _afirmacoes_que_dependem_do_xml()
        feitas = c.conferidas - antes_do_xml
        if anunciadas != feitas:
            c.falhas.append(
                "o aviso de XML ausente anuncia %d afirmações e o bloco faz %d"
                % (anunciadas, feitas)
            )

    # ----------------------------------------------- números vindos do corpus
    mark_effect = ler("scripts/core/abilities/effects/mark_effect.gd")
    cooldown_effect = ler("scripts/core/abilities/effects/cooldown_effect.gd")
    pulse = ler("scripts/core/abilities/ability_pulse.gd")
    marcas = _marcas_distintas(habilidades)

    c.afirma("mark_effect.gd marcas distintas", mark_effect,
             r"\*\*(\d+) marcas distintas\*\*", marcas)
    c.afirma("docs/10 marcas distintas", doc10,
             r"corpus acaba com (\d+) marcas distintas", marcas)
    c.afirma("cooldown_effect.gd emissões", cooldown_effect,
             r"efeito sai (\d+)", _emissoes(relatorio, "cooldown"))
    c.afirma("ability_pulse.gd pulsos sem deslocamento", pulse,
             r"e de (\d+) dos", _sem_offset_no_corpus(habilidades))
    c.afirma("ability_pulse.gd total de pulsos", pulse,
             r"dos (\d+) pulsos traduzidos", total_pulsos)
    c.afirma("ability_pulse.gd habilidades com vários pulsos", pulse,
             r"\*\*(\d+) das habilidades do original têm mais de um pulso\*\*",
             len(varios))

    # ------------------------------- quantos .tres teriam sido, se fossem
    #
    # Já ficou defasado: dizia 1369 (o total de antes) em três arquivos.
    # É um número hipotético, e por isso mesmo ninguém o revisita sozinho.
    quantos_tres = len(habilidades) + itens["total"]
    for onde, caminho in (
        ("docs/02", "docs/02-decisoes-tecnicas.md"),
        ("docs/10", "docs/10-traducao-do-original.md"),
        ("traduzir.py", "tools/traducao/traduzir.py"),
    ):
        c.afirma("%s arquivos .tres hipotéticos" % onde, ler(caminho),
                 r"- (\d+) arquivos gerados afogariam", quantos_tres)

    # ------------------------------------------------- roadmap
    roadmap = ler("docs/04-roadmap.md")
    c.afirma("docs/04 atributos", roadmap, r"Atributos 18→(\d+)", atributos)
    c.afirma("docs/04 estados", roadmap,
             r"estados de controle 4→(\d+)", estados)
    c.afirma("docs/04 controles", roadmap,
             r"`CrowdControlEffect` 5→(\d+)", controles)
    c.afirma("docs/04 efeitos", roadmap, r"efeitos 6→(\d+)", efeitos)
    # A carga de suprema saiu desta lista quando deixou de ser lacuna: a
    # conferência apontava para uma linha do relatório que não existe mais, e
    # conferência órfã é tão ruim quanto nenhuma — ela reprova por um motivo
    # que não é o defeito.
    for rotulo, chave, padrao in (
        ("combo", "ComboSkillInfo (corrente de combo)",
         r"\*\*Corrente de combo\*\* \((\d+)\)"),
        ("cancelamento", "janela de cancelamento por tempo",
         r"\*\*Janelas de cancelamento\*\* \((\d+)\)"),
    ):
        c.afirma("docs/04 lacuna %s" % rotulo, roadmap, padrao,
                 _emissoes_lacuna(relatorio, chave))

    # --------------------------------- as tabelas de lacuna de docs/10
    #
    # Um bloco inteiro de números, e foi exatamente aqui que um deles se
    # escondeu por
    # quatro revalidações: a linha de `BuffReleaseCondition` dizia 58 quando o
    # relatório somava 60, porque uma das parcelas subiu numa correção e o
    # documento ficou. Bloco numérico grande sem conferência é onde o próximo
    # vai se esconder.
    #
    # Cada par é (rótulo na tabela do doc, chave no RELATORIO.md). Quando a
    # linha soma várias lacunas, a lista tem mais de uma chave.
    LACUNAS_DO_DOC = [
        (r"`ComboSkillInfo`, (\d+)", ["ComboSkillInfo (corrente de combo)"]),
        (r"e três irmãs, (\d+)", ["janela de cancelamento por tempo"]),
        (r"`Link`, (\d+)",
         ["Link (corrente que liga dois alvos e rompe na distância)"]),
        (r"`UseSkillSlot`, (\d+)",
         ["UseSkillSlot (troca a habilidade de um espaço)"]),
        (r"`PhysicalDamageAmp_SkillE`, (\d+)",
         ["StatType=PhysicalDamageAmp_SkillE"]),
        (r"`FollowTarget`, (\d+)",
         ["área que acompanha o alvo em vez de ficar no chão "
          "(`FollowTarget` em impact)"]),
        (r"`BeAbleToAttackBush`, (\d+)",
         ["arbusto que se pode atacar (não há arbusto) "
          "(`BeAbleToAttackBush` em impact)"]),
        (r"`TrackingMode`, (\d+)",
         ["projétil teleguiado (`TrackingMode` em skill)"]),
        (r"`StopCondition`, (\d+)",
         ["a investida que PARA ao acertar (OnImpactEnemy / OnDamage / "
          "OnLostTarget) — nosso dash sempre completa (`StopCondition` em skill)"]),
        (r"`LimitSourceDistance`, (\d+)",
         ["o gancho que arrebenta quando estica demais "
          "(`LimitSourceDistance` em crowd_control)"]),
        (r"`MoveCurve`, (\d+)", ["curva de deslocamento (MoveCurve)"]),
        (r"`RecoverDataType`, (\d+)", [
            "RecoverDataType=RegenHealth sem valor legível "
            "(os números vivem no texto localizado)",
            "RecoverDataType=RegenAll sem valor legível "
            "(os números vivem no texto localizado)",
            "RecoverDataType=RegenMana sem valor legível "
            "(os números vivem no texto localizado)",
        ]),
        (r"`PingList`, (\d+)",
         ["PingList (aviso na interface, não é combate)"]),
        (r"— \*\*(\d+)\*\* \| Dependem de eventos", [
            "BuffReleaseCondition=SkillFinish",
            "BuffReleaseCondition=InteractionStart",
            "BuffReleaseCondition=OnStartSkill",
            "BuffReleaseCondition=Move",
            "BuffReleaseCondition=OnCCMoved",
        ]),
    ]
    for padrao, chaves in LACUNAS_DO_DOC:
        soma = sum(_emissoes_lacuna(relatorio, k) for k in chaves)
        c.afirma("docs/10 lacuna %s" % chaves[0][:34], doc10, padrao, soma)

    # As parcelas nomeadas na linha de `BuffReleaseCondition` também são
    # conferidas uma a uma: somar certo com parcela errada ainda é errado.
    for nome, chave in (
        ("SkillFinish", "BuffReleaseCondition=SkillFinish"),
        ("InteractionStart", "BuffReleaseCondition=InteractionStart"),
        ("OnStartSkill", "BuffReleaseCondition=OnStartSkill"),
        ("Move", "BuffReleaseCondition=Move"),
        ("OnCCMoved", "BuffReleaseCondition=OnCCMoved"),
    ):
        c.afirma("docs/10 parcela %s" % nome, doc10,
                 r"`%s` (\d+)" % nome, _emissoes_lacuna(relatorio, chave))

    # --------------------------------- cabeçalho duplicado de docs/10
    #
    # `docs/10:111` repete o fato do `:116` fora do padrão conferido, e mutar
    # só o cabeçalho passava despercebido. Ancorar os dois.
    c.afirma("docs/10 cabeçalho de controle", doc10,
             r"### Controle de grupo: 4 → (\d+) estados", estados)

    # ------------------------------------------------- contagem de testes
    c.afirma("CLAUDE.md testes", claude,
             r"\*\*(\d+) testes, \d+ asserções\*\*", _contar_testes())

    # A ferramenta se confere antes de conferir os outros.
    _autoteste(c)

    suite = _rodar_suite()
    if not suite["rodou"]:
        # Aviso, e não falha: quem não tem a engine à mão ainda pode conferir
        # tudo que sai do corpus e dos documentos.
        c.avisar(
            "%s; a contagem de ASSERÇÕES ficou sem conferir "
            "(defina GODOT_PATH para fechar)" % suite["motivo"],
            # A contagem de testes e a de asserções do `CLAUDE.md`. As duas
            # vivem no ramo em que a suíte rodou E passou.
            1,
        )
    elif not suite["passou"]:
        # **Falha, não aviso.** Afirmar contagem de teste contra uma suíte
        # vermelha é pior que não afirmar nada: publica um número que descreve
        # um resultado que não vale.
        c.conferidas += 1
        c.falhas.append(
            "a suíte NÃO está verde (%s) — as contagens de `CLAUDE.md` não "
            "foram conferidas contra ela" % suite["motivo"]
        )
    else:
        # **TODAS as ocorrências, não a primeira.** `re.search` ancora só a
        # primeira, e o `CLAUDE.md` repete o par em dois lugares — a segunda
        # podia envelhecer em silêncio, que é o defeito que esta ferramenta
        # inteira existe para não deixar acontecer.
        pares = re.findall(r"\*\*(\d+) testes, (\d+) asserções\*\*", claude)
        c.conferidas += 1
        if not pares:
            c.falhas.append("`CLAUDE.md` não diz mais quantos testes existem")
        for indice, (testes, assercoes) in enumerate(pares):
            if int(testes) == suite["testes"] and int(assercoes) == suite["assercoes"]:
                continue
            c.falhas.append(
                "`CLAUDE.md` diz `%s testes, %s asserções` na ocorrência %d e "
                "a suíte dá %d/%d"
                % (testes, assercoes, indice + 1,
                   suite["testes"], suite["assercoes"])
            )

    # ------------------------- a tabela de cobertura do relatório
    #
    # Só a tabela de COBERTURA, que é computada a partir do corpus. A tabela
    # "o que o vocabulário cobriu" conta EMISSÕES do tradutor — uma habilidade
    # com `MagicalHeal` e `MagicalConstHeal` emite dois `usou("heal")` e um
    # efeito só. Comparar as duas produziria alarme falso, e alarme falso
    # ensina a ignorar o alarme.
    #
    # O que protege aquela outra tabela é ela ser gerada: regenerar e olhar o
    # `git status` acusa qualquer edição à mão.
    c.afirma("RELATORIO vários pulsos", relatorio,
             r"\| \.\.\.com mais de um pulso \| (\d+) \|", len(varios))
    c.afirma("RELATORIO pulsos", relatorio,
             r"\| Pulsos gerados \| (\d+) \|", total_pulsos)
    c.afirma("RELATORIO efeitos", relatorio,
             r"\| Efeitos gerados \| (\d+) \|", total_efeitos)
    c.afirma("RELATORIO itens", relatorio,
             r"\| Itens traduzidos \| \*\*(\d+)\*\*", itens["total"])

    # ------------------------------------------------- cabeçalho x lista
    #
    # Já foi falso: uma seção intitulada "Dois bugs do tradutor" com cinco
    # itens na lista. Contar os itens é mais barato que confiar no cabeçalho.
    c.conferidas += 1
    cabecalho = re.search(r"## (Dois|Três|Quatro|Cinco|Seis) bugs do tradutor", doc10)
    if cabecalho is None:
        c.falhas.append("docs/10: a seção de bugs do tradutor sumiu")
    else:
        por_extenso = {"Dois": 2, "Três": 3, "Quatro": 4, "Cinco": 5, "Seis": 6}
        dito = por_extenso[cabecalho.group(1)]
        itens = len(re.findall(r"^\d+\. \*\*", doc10, re.M))
        if dito != itens:
            c.falhas.append(
                "docs/10: o cabeçalho diz %d bugs e a lista tem %d itens"
                % (dito, itens)
            )

    # ---------------------------------------------------------- veredito
    #
    # **Piso sobre a COBERTURA.** `conferidas` nunca era afirmado contra nada:
    # perder metade das conferências saía como um número menor impresso e
    # "todas batem". Foi esse sintoma — 110 caindo para 108 — que denunciou um
    # defeito que ninguém tinha procurado.
    if c.conferidas < 100:
        c.falhas.append(
            "só %d afirmações foram conferidas; a ferramenta perdeu cobertura"
            % c.conferidas
        )
    # E o piso que o `CLAUDE.md` publica. É PISO e não igualdade de propósito:
    # acrescentar conferência não pode obrigar a mexer no documento, mas
    # perder conferência tem que doer. O número era escrito no documento e não
    # era conferido por nada — o mesmo estado em que estavam as "12
    # afirmações" que eram 15.
    c.conferidas += 1
    publicado = _numero(
        ler("CLAUDE.md"), r"\*\*(\d+) afirmações numéricas\*\*"
    )
    if publicado < 0:
        # **Órfã é falha, não aprovação.** `if publicado > c.conferidas` com
        # `publicado = -1` passava sempre: reescrever a frase no documento
        # desligava a conferência em silêncio. Era a única da ferramenta que
        # aprovava ao perder o próprio padrão.
        c.falhas.append(
            "`CLAUDE.md` não publica mais o número de afirmações numéricas; "
            "a conferência do piso ficou órfã"
        )
    else:
        # **O piso é descontado pelo que as degradações declararam custar.**
        #
        # Duas versões erradas antes desta, e as duas em direções opostas. A
        # primeira descontava só a ausência do XML: sem a engine da Godot a
        # ferramenta reprovava o `CLAUDE.md` por publicar um número certo. A
        # segunda dispensava o piso INTEIRO ao primeiro aviso, e aí perder 27
        # conferências de verdade junto com uma ausência benigna passava
        # verde — generalizar custou o poder de detecção que existia.
        #
        # O critério que fecha a classe sem pagar esse preço: quem degrada
        # declara QUANTO. Um ramo benigno novo entra na conta dizendo o próprio
        # custo, e não por existir.
        exigido = publicado - c.dispensadas()
        if c.avisos:
            print(
                "[números] piso publicado %d, exigidas %d aqui (%s)"
                % (publicado, exigido,
                   "; ".join(texto for texto, _q in c.avisos))
            )
        if exigido > c.conferidas:
            c.falhas.append(
                "`CLAUDE.md` publica %d afirmações numéricas (exigidas %d "
                "nesta execução) e só %d foram conferidas. Se um ramo novo "
                "degradou de propósito, ele tem que chamar "
                "`c.avisar(texto, quantas)` em vez de imprimir aviso solto."
                % (publicado, exigido, c.conferidas)
            )
    print("[números] %d afirmações conferidas (piso publicado: %d)" % (
        c.conferidas, publicado
    ))
    if not c.falhas:
        print("[números] todas batem")
        return 0
    print("[números] %d NÃO batem:" % len(c.falhas), file=sys.stderr)
    for falha in c.falhas:
        print("  - %s" % falha, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
