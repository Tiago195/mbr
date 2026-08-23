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

import contextlib
import json
import re
import struct
import subprocess
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
        ## Quantas das afirmações só aconteceram porque a engine estava por
        ## perto. Contado por REGIÃO, não por lembrança de quem escreve.
        self.com_engine = 0
        self._na_regiao_da_engine = False

    @contextlib.contextmanager
    def dependendo_da_engine(self):
        """Tudo que for contado aqui dentro conta como dependente da engine.

        **É a região que decide, e não um argumento.** A versão anterior pedia
        `contar(com_engine=True)` em cada sítio, e isso era o quinto disfarce
        do mesmo defeito: `len(SONDAS)` acreditava num número, os colchetes
        numa localização, e o argumento opcional acreditava na MEMÓRIA de quem
        escrevesse a próxima afirmação. Uma afirmação nova dentro do portão que
        já existia, chamando `contar()` sem o argumento, passava pelas três
        defesas — verde na máquina que a escreve e vermelha só na máquina sem
        a Godot, que é exatamente por que esta espécie recorreu cinco vezes.
        """
        anterior = self._na_regiao_da_engine
        self._na_regiao_da_engine = True
        try:
            yield
        finally:
            self._na_regiao_da_engine = anterior

    def contar(self, quantas: int = 1) -> None:
        """Registra afirmações feitas — e, quando for o caso, que elas só
        aconteceram porque a engine da Godot estava por perto.

        **O gasto é registrado ONDE a afirmação acontece.** A versão anterior
        o derivava de dois intervalos delimitados à mão no corpo de `main()`, e
        isso era um literal com outra roupa: `len(SONDAS)` acreditava num
        número, e os colchetes acreditavam numa LOCALIZAÇÃO. Uma afirmação
        dependente da engine posta fora deles gastava sem entrar na conta, e a
        mesma falha voltava — quarta recorrência da mesma espécie.
        """
        self.conferidas += quantas
        if self._na_regiao_da_engine:
            self.com_engine += quantas

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

        Dentro de `dependendo_da_engine()` ela conta como dependente da
        engine sem precisar dizer nada — ver `contar()`, por onde TODO
        incremento passa.
        """
        self.contar()
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
        self.contar()
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
        # `FollowTarget` NÃO é booleana, e foi por isso que a lacuna ficou mal
        # descrita: os três valores são contados separados.
        "segue_nada": sum(
            1 for r in impactos_todos
            if (r.get("FollowTarget") or "").strip() == "None"
        ),
        "segue_conjurador": sum(
            1 for r in impactos_todos
            if (r.get("FollowTarget") or "").strip() == "User"
        ),
        "segue_alvo": sum(
            1 for r in impactos_todos
            if (r.get("FollowTarget") or "").strip() == "Target"
        ),
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


def _achar_godot() -> str | None:
    """Onde a engine está, ou `None`. Fronteira entre incapacidade e falha.

    Depois daqui, tudo é FALHA da coisa executada — nunca "não consegui
    conferir".
    """
    import os
    import shutil

    godot = os.environ.get("GODOT_PATH") or shutil.which("godot")
    if godot is not None:
        return godot
    for candidato in (
        r"C:\Godot\Godot_v4.7.2-stable_win64.exe",
        r"C:\Godot\Godot.exe",
    ):
        if Path(candidato).exists():
            return candidato
    return None


## As sondas de cena, com a marca que cada uma imprime quando passa.
##
## Elas existem porque a suíte de `tests/` só alcança `scripts/core/`. E são
## rodadas AQUI porque, até esta revisão, **nada lia o stderr delas**: um
## `SCRIPT ERROR` no meio de uma sonda não aborta a função que o causou —
## empurra um erro, devolve nulo e o laço segue —, então ela imprimia `[ok]` e
## saía com zero numa execução que parcialmente não aconteceu. Foi medido, com
## um acesso a propriedade inexistente: `EXIT=0`, 323 bytes de stderr, `[ok]`.
SONDAS = [
    ("sonda de campeões", "res://tools/sondar_campeoes.gd",
     "todos os campeões trocaram e conjuraram sem erro"),
    ("sonda de ritmo", "res://tools/sondar_ritmo.gd",
     "o ataque básico respeita a cadência"),
]


## Os limites que uma sonda imprime a cada execução e um documento republica.
##
## `(rótulo, script da sonda, padrão na saída dela, [(documento, padrão)…])`.
##
## Existe porque a republicação envelhece em silêncio: "8735 assinaturas" no
## `CLAUDE.md` contra 9667 medidos, depois de a lacuna 4 mover o número duas
## vezes. **E a primeira versão desta tabela fechou a classe só para o
## `CLAUDE.md`** — os quatro números que a decisão 19 republica podiam ir a
## 480/30/1600/170 com a ferramenta dizendo "todas batem". Enumerar o arquivo
## em vez da classe é a mesma forma do desconto que foi escrito para uma
## ausência benigna e não para a irmã.
##
## A lista de documentos por limite é o que fecha: republicar num arquivo novo
## é acrescentar um par, e não escrever código.
##
## **Cada limite é chaveado à SUA sonda.** Hoje os vocabulários das duas não se
## cruzam, mas depender disso seria depender de coincidência: um dia a sonda de
## ritmo imprime "assinaturas comparadas" e o cruzamento pega a linha errada.
##
## O que NÃO entra aqui: número medido uma vez e registrado como história —
## "156/159/160 conforme o salto", "x=1293", "27 a 32 golpes". Reproduzi-los
## exige aplicar uma mutação, e por isso eles não derivam sozinhos. O que
## entra é o que a sonda reimprime em toda execução.
LIMITES_DA_SONDA = [
    ("espaços tentados", "res://tools/sondar_campeoes.gd",
     r"espaços de campeão tentados: (\d+)",
     [("CLAUDE.md", r"\((\d+) espaços tentados")]),
    ("espaços conferidos", "res://tools/sondar_campeoes.gd",
     r"foram conferidos: (\d+)",
     [("CLAUDE.md", r"(\d+) conferidos")]),
    # `(?![\w-])` e não só `assinaturas`: sem isso, reescrever o documento
    # para "9667 assinaturas-comparadas" continuava casando, e a mutação que
    # deveria acusar padrão órfão passava verde.
    ("assinaturas comparadas", "res://tools/sondar_campeoes.gd",
     r"assinaturas comparadas: (\d+)",
     [("CLAUDE.md", r"(\d+) assinaturas(?![\w-])")]),
    ("espaços que zeram a cadência", "res://tools/sondar_campeoes.gd",
     r"medida: (\d+) espaços zeraram",
     [("CLAUDE.md", r"(\d+) espaços zerando a cadência")]),
    ("espaços que mantêm a cadência", "res://tools/sondar_campeoes.gd",
     r"zeraram, (\d+) mantiveram",
     [("CLAUDE.md", r"e (\d+) mantendo")]),
    ("golpes que seguiram o conjurador", "res://tools/sondar_campeoes.gd",
     r"atrasado: (\d+) seguiram o conjurador",
     [("docs/02-decisoes-tecnicas.md", r"\*\*(\d+) seguiram o conjurador\*\*")]),
    ("golpes que seguiram o alvo", "res://tools/sondar_campeoes.gd",
     r"conjurador, (\d+) seguiram o alvo",
     [("docs/02-decisoes-tecnicas.md", r"\*\*(\d+) seguiram o alvo\*\*")]),
    ("golpes que ficaram", "res://tools/sondar_campeoes.gd",
     r"o alvo, (\d+) ficaram",
     [("docs/02-decisoes-tecnicas.md", r"\*\*(\d+) ficaram\*\*")]),
    ("golpes fora do alcance da sonda", "res://tools/sondar_campeoes.gd",
     r"alcance: (\d+) de conjuração com tempo",
     [("docs/02-decisoes-tecnicas.md",
       r"\*\*(\d+) golpes ficam fora do alcance")]),
]


def _afirmacoes_que_dependem_da_engine() -> int:
    """Quantas afirmações só acontecem com a engine da Godot por perto.

    **DERIVADA das estruturas que os laços percorrem, e não escrita à mão.**

    A versão anterior declarava `len(SONDAS)`, que responde "quantas sondas" —
    e a pergunta é "quanto deste bloco depende da engine". Ela quebrou no
    primeiro crescimento que não foi uma sonda: os nove pares
    `(limite, documento)` entraram no mesmo ramo e ficaram fora do custo, e
    quem não tinha a Godot passou a ver a ferramenta sair 1 acusando o
    `CLAUDE.md` de publicar um número que estava certo.

    É a terceira vez que esta espécie de defeito aparece. O lado do XML nunca
    a sofreu porque `_afirmacoes_que_dependem_do_xml()` CONTA o próprio fonte
    em vez de acreditar num literal — absorveu a mesma expansão sem uma edição.
    Aqui a contagem textual não serviria (os incrementos estão dentro de
    laços), então a derivação é sobre as listas que os laços percorrem, e
    `main()` confere a soma contra o trabalho de verdade quando a engine está
    presente.
    """
    pares = sum(len(documentos) for _r, _s, _p, documentos in LIMITES_DA_SONDA)
    # +2: a conferência das contagens de teste do `CLAUDE.md`, que vive no ramo
    # da suíte, e a autoconferência deste próprio custo, que só roda quando a
    # engine está presente. Ela conta por si mesma pelo mesmo motivo que a do
    # bloco do XML conta: some junto com o bloco.
    return len(SONDAS) + pares + 2


def _rodar_sonda(godot: str, script: str, marca: str) -> dict:
    """Roda uma sonda de cena e classifica com a MESMA disciplina da suíte."""
    import subprocess

    try:
        processo = subprocess.run(
            [godot, "--headless", "--path", str(RAIZ), "--script", script],
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=900,
        )
    except subprocess.TimeoutExpired:
        return {"passou": False, "motivo": "TRAVOU (900s sem terminar)"}
    except Exception as erro:
        return {"passou": False, "motivo": "não chegou a rodar: %s" % erro}
    veredito = _classificar_sonda(
        processo.returncode, processo.stdout or "", processo.stderr or "", marca
    )
    # A SAÍDA volta junto: os limites que a sonda publica ("assinaturas
    # comparadas", "espaços conferidos") são afirmados no `CLAUDE.md`, e o
    # único jeito de conferi-los é lendo o que ela imprimiu.
    veredito["saida"] = processo.stdout or ""
    return veredito


def _classificar_sonda(codigo: int, saida: str, erros: str, marca: str) -> dict:
    """O que a execução de uma sonda quer dizer. PURA, e exercitada no autoteste.

    Três coisas, e a do meio é a que faltava no projeto inteiro:

    1. código de saída zero;
    2. **stderr limpo** — `SCRIPT ERROR` e `leaked at exit`;
    3. a marca de sucesso impressa, para uma sonda que morra calada não passar
       por aprovada.
    """
    motivos: list[str] = []
    if codigo != 0:
        motivos.append("saiu com código %d" % codigo)
    if "[FALHOU]" in saida:
        motivos.append("reportou falha")
    for sinal in ("SCRIPT ERROR", "leaked at exit"):
        if sinal in erros:
            motivos.append("`%s` no stderr" % sinal)
    if marca not in saida:
        motivos.append("não imprimiu a marca de sucesso")
    return {"passou": not motivos, "motivo": "; ".join(motivos)}


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
    import subprocess

    godot = _achar_godot()
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
## A marca fictícia usada pelo autoteste do classificador de sonda.
MARCA_DE_TESTE = "tudo certo por aqui"

## Quantos `godot is (not) None` existem no fonte, fora de `_achar_godot` e do
## `_rodar_suite`. Um a mais obriga quem o escrever a declarar o custo.
PORTOES_DA_ENGINE = 4

## Os sistemas já fechados, pelo nome com que os documentos os citam.
##
## `(nome, decisão)`. Existe porque o mesmo item ficou **aberto num documento e
## fechado noutro** duas vezes seguidas: o arco entre as duas tabelas do
## `CLAUDE.md`, e a corrente de combo entre o `CLAUDE.md` e o
## `docs/04-roadmap.md`. Nos dois casos o arquivo desatualizado era o
## `CLAUDE.md` — o que toda sessão é mandada ler inteiro, e primeiro.
##
## A conferência exige que, onde o nome aparecer numa linha de lista ou de
## tabela, ele esteja RISCADO. É a mesma disciplina das duas tabelas, agora
## entre arquivos.
SISTEMAS_FECHADOS = [
    ("Carga de suprema", 17),
    ("Corrente de combo", 21),
]

## Onde os sistemas fechados são citados.
DOCUMENTOS_DE_ESTADO = [
    "CLAUDE.md",
    "docs/04-roadmap.md",
    "docs/10-traducao-do-original.md",
]


def _lacunas_da_tabela(claude: str) -> list[int]:
    """Os números das seis lacunas, LIDOS da primeira tabela.

    Derivado e não escrito à mão: uma lacuna nova entraria nas tabelas e não
    na lista, e passaria sem conferência — o mesmo resíduo de
    `PORTOES_DA_ENGINE`, que continua literal por não ter de onde derivar.
    """
    # Casa o cabeçalho pelo começo: o resto dele descreve o ESTADO da tabela
    # e muda quando o estado muda — foi assim que esta leitura ficou órfã ao
    # "onde ela está" virar "como ela terminou".
    achado = re.search(r"^#### A tabela,.*$", claude, re.M)
    inicio = achado.start() if achado else -1
    if inicio < 0:
        return []
    numeros: list[int] = []
    for linha in claude[inicio:].splitlines():
        if linha.startswith("####") and numeros:
            break
        achado = re.match(r"\| ~?~?\*?\*?(\d+)\*?\*?~?~? \|", linha)
        if achado:
            numeros.append(int(achado.group(1)))
    return numeros

## Os jeitos de uma sonda mentir. O primeiro é o que aconteceu de verdade: um
## acesso a propriedade inexistente empurra erro, devolve nulo, o laço segue, e
## a sonda imprime `[ok]` com `EXIT=0`.
CENARIOS_DA_SONDA = [
    ("sonda verde", 0, "  [ok] tudo certo por aqui", "", True),
    ("SCRIPT ERROR com [ok] no stdout", 0, "  [ok] tudo certo por aqui",
     "SCRIPT ERROR: Invalid access to property 'cast'", False),
    ("vazamento de memória", 0, "  [ok] tudo certo por aqui",
     "ObjectDB instances were leaked at exit", False),
    ("reportou falha", 1, "  [FALHOU] alguma coisa", "", False),
    ("morreu calada", 0, "", "", False),
    ("código diferente de zero com a marca impressa", 2,
     "  [ok] tudo certo por aqui", "", False),
]

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
    c.contar()
    fonte = Path(__file__).read_text(encoding="utf-8")
    # **Todo incremento passa por `contar()`.**
    #
    # Sem isto, `c.conferidas += 1` escrito dentro de um bloco dependente da
    # engine gasta sem entrar na conta — medido: a ferramenta saía 0 com a
    # engine e cobrava a mais sem ela. `contar()` é o único lugar onde o campo
    # é mexido, e quem chama tem que decidir, ali mesmo, se aquilo depende da
    # engine.
    c.contar()
    crus = sum(
        1 for linha in fonte.splitlines()
        if not linha.strip().startswith("#")
        # Montados, para estas duas linhas não se contarem — mesmo truque dos
        # marcadores do bloco do XML e do rótulo de aviso.
        and ("conferidas" + " +=") in linha
        and ("self.conferidas" + " += quantas") not in linha
    )
    if crus:
        c.falhas.append(
            "há %d incremento(s) de `conferidas` fora de `contar()`; use "
            "`c.contar()`, e dentro de `with c.dependendo_da_engine()` "
            "quando a afirmação só acontece com a engine" % crus
        )

    # **Nenhum portão da engine pode nascer sem registrar o gasto.**
    #
    # Contar no site resolve o gasto de quem passa por `contar(com_engine=…)`,
    # mas não impede alguém de abrir uma REGIÃO nova dependente da engine e
    # esquecer de marcá-la — e foi exatamente assim que a quarta recorrência
    # aconteceu, com a afirmação fora dos colchetes.
    #
    # `main()` tem dois portões: o `if godot is None:` das sondas e a
    # autoconferência do custo. Um terceiro obriga quem o escrever a passar
    # por aqui e a decidir conscientemente se ele gasta. É a mesma disciplina
    # da varredura de avisos logo abaixo, e nasce do mesmo defeito.
    c.contar()
    # Só linhas de CÓDIGO: o comentário acima cita o portão, e contar
    # comentário faria a varredura reclamar de quem a documenta.
    portoes = sum(
        1 for linha in fonte.splitlines()
        if not linha.strip().startswith("#")
        and re.search("godot is (?:not )?None", linha)
    )
    if portoes != PORTOES_DA_ENGINE:
        c.falhas.append(
            "há %d portões de engine no fonte e o esperado é %d; se o novo faz "
            "afirmação, ela tem que ficar dentro de "
            "`with c.dependendo_da_engine()` — "
            "senão o piso vai cobrar o que a execução degradada não podia "
            "fazer" % (portoes, PORTOES_DA_ENGINE)
        )

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

    # E o classificador das SONDAS, contra os mesmos truques.
    for rotulo, codigo, saida, erros, deve_passar in CENARIOS_DA_SONDA:
        c.contar()
        veredito = _classificar_sonda(codigo, saida, erros, MARCA_DE_TESTE)
        if bool(veredito["passou"]) == deve_passar:
            continue
        c.falhas.append(
            "autoteste do classificador de sonda: `%s` devia %s e %s (%s)" % (
                rotulo, "passar" if deve_passar else "reprovar",
                "passou" if veredito["passou"] else "reprovou",
                veredito["motivo"] or "nenhum motivo",
            )
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
        c.contar()
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
    c.contar()
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



# --------------------------------------------------- a direção de arte

## Rótulo na tabela de `docs/11` → chave de `PROPORCAO` no gerador → nome da
## medida em `conferir_personagem.py`. As três fontes têm que dizer o mesmo
## número, e cada seta é uma chance de elas se separarem.
DIRECAO_LINHAS = {
    "tornozelo": ("tornozelo", "pe_D"),
    "joelho": ("joelho", "canela_D"),
    "quadril": ("quadril", "coxa_D"),
    "peito": ("peito", "peito"),
    "base do pescoço": ("pescoco", "cabeca"),
    "ombro / cotovelo / mão": ("ombro", "braco_D"),
    "separação dos ombros / altura": ("vao_dos_ombros", "ombros"),
    "separação dos quadris / altura": ("vao_dos_quadris", "quadris"),
    "vão das mãos / altura": ("vao_das_maos", "maos"),
    "envergadura / altura": ("envergadura", "envergadura"),
}

## As três animações de locomoção usam a faixa do clipe equivalente do original,
## publicada na tabela do §3. Sem esta amarração dava para alargar a faixa da
## corrida até nada reprovar, e nenhuma ferramenta notava.
DIRECAO_LOCOMOCAO = {"parado": "idle", "andando": "walk", "correndo": "run"}


def _decimal(texto: str) -> float:
    return float(texto.replace(",", "."))


def _tabela_do_documento(doc: str, rotulo: str):
    """`(mediana, mínimo, máximo)` de uma linha das tabelas de `docs/11`."""
    achado = re.search(
        r"\| %s \| \*{0,2}(-?[0-9],[0-9]+)\*{0,2} \| (-?[0-9],[0-9]+) – (-?[0-9],[0-9]+) \|"
        % re.escape(rotulo), doc
    )
    if achado is None:
        return None
    return tuple(_decimal(achado.group(i)) for i in (1, 2, 3))


def _proporcao_do_gerador(fonte: str) -> dict:
    """Os valores de `PROPORCAO`, lidos do texto do gerador.

    Lidos do TEXTO e não importados: `gerar_personagem.py` faz `import bpy` no
    topo, e esta ferramenta roda em Python comum. Importar aqui exigiria o
    Blender, e uma conferência que só roda numa máquina não é conferência.
    """
    trecho = re.search(r"PROPORCAO = \{(.*?)^\}", fonte, re.S | re.M)
    if trecho is None:
        return {}
    return {
        chave: float(valor)
        for chave, valor in re.findall(r'"(\w+)":\s*([0-9.]+)', trecho.group(1))
    }


def _faixas_do_conferidor(fonte: str) -> dict:
    """`medida → (mediana, mínimo, máximo)`, das duas tabelas do conferidor."""
    saida = {}
    for bloco in ("FAIXA_MEDIDA", "FAIXA_DAS_LARGURAS"):
        trecho = re.search(r"%s = \{(.*?)^\}" % bloco, fonte, re.S | re.M)
        if trecho is None:
            continue
        for nome, a, b, d in re.findall(
            r'"(\w+)": \(([0-9.]+), (-?[0-9.]+), ([0-9.]+)\)', trecho.group(1)
        ):
            saida[nome] = (float(a), float(b), float(d))
    return saida



def _duracoes_do_gerador(fonte: str) -> dict:
    """`animação → duração em segundos`, lida das chaves do gerador."""
    saida = {}
    for bloco in re.finditer(r'^\t"(\w+)": \{(.*?)^\t\},', fonte, re.S | re.M):
        quadros = [int(q) for q in re.findall(r"\((\d+), pose\(", bloco.group(2))]
        if quadros:
            saida[bloco.group(1)] = max(quadros) / 30.0
    return saida


def _duracoes_do_glb(caminho: str) -> dict:
    """`animação → duração`, lida do `.glb` EXPORTADO, sem Blender.

    O cabeçalho de um `.glb` é JSON puro, e o tempo de cada animação está no
    `max` do acessor de entrada dos samplers. Ler daqui é o que torna o
    ARTEFATO conferível pela mesma ferramenta que roda em todo commit — e sem
    isso ele não era conferido por nada.
    """
    dados = (RAIZ / caminho).read_bytes()
    if dados[:4] != b"glTF":
        raise ValueError("%s não é um .glb" % caminho)
    tamanho = struct.unpack("<I", dados[12:16])[0]
    cabecalho = json.loads(dados[20:20 + tamanho].decode("utf-8"))
    saida = {}
    for animacao in cabecalho.get("animations", []):
        fim = 0.0
        for sampler in animacao.get("samplers", []):
            acessor = cabecalho["accessors"][sampler["input"]]
            if acessor.get("max"):
                fim = max(fim, float(acessor["max"][0]))
        saida[animacao.get("name", "?")] = fim
    return saida


def _conferir_o_artefato(c: "Conferencia") -> None:
    """O `.glb` que está no repositório contra o gerador que o produz.

    **Existe porque o artefato commitado já REPROVOU o próprio conferidor.** A
    suíte de mutação restaurava o código-fonte no fim e deixava o `.glb` da
    última mutação no disco; ele foi commitado assim, com `parado` de 1,00 s
    onde o gerador diz 2,00. Nenhuma das ferramentas notava, porque todas liam
    CÓDIGO e nenhuma abria o arquivo exportado.

    Ler o glTF em Python puro é o que permite conferir isso sem o Blender, e
    portanto em toda execução, e não só na máquina de quem tem a engine de arte
    instalada.
    """
    try:
        gerador = ler("tools/arte/gerar_personagem.py")
        do_glb = _duracoes_do_glb("arte/personagem.glb")
    except (OSError, ValueError) as erro:
        c.contar()
        c.falhas.append("o boneco exportado não pôde ser lido: %s" % erro)
        return

    do_codigo = _duracoes_do_gerador(gerador)
    c.contar()
    if set(do_glb) != set(do_codigo):
        c.falhas.append(
            "o `.glb` tem as animações %s e o gerador define %s"
            % (sorted(do_glb), sorted(do_codigo))
        )
        return
    for nome in sorted(do_codigo):
        c.contar()
        # Meio quadro de folga: o glTF guarda tempo em ponto flutuante.
        if abs(do_glb[nome] - do_codigo[nome]) > 1.0 / 60.0:
            c.falhas.append(
                "`%s` dura %.3f s no `.glb` commitado e %.3f s no gerador — o "
                "artefato não veio deste código"
                % (nome, do_glb[nome], do_codigo[nome])
            )


## Bytes que não podem existir em arquivo de texto rastreado. O `\b` de
## `\blender.exe`, escrito por um script que interpretou a sequência, virou
## byte 0x08 dentro de um comando publicado no `CLAUDE.md` — quem copiasse o
## comando não conseguia rodá-lo.
EXTENSOES_DE_TEXTO = (".md", ".py", ".gd", ".json", ".cfg", ".tscn", ".tres")


def _conferir_bytes_de_controle(c: "Conferencia") -> None:
    saida = subprocess.run(
        ["git", "ls-files"], capture_output=True, text=True, cwd=str(RAIZ)
    )
    c.contar()
    if saida.returncode != 0:
        c.falhas.append("não consegui listar os arquivos rastreados")
        return
    sujos = []
    for caminho in saida.stdout.splitlines():
        if not caminho.endswith(EXTENSOES_DE_TEXTO):
            continue
        try:
            bruto = (RAIZ / caminho).read_bytes()
        except OSError:
            continue
        for indice, byte in enumerate(bruto):
            if byte < 9 or (13 < byte < 32):
                sujos.append("%s byte 0x%02x em %d" % (caminho, byte, indice))
                break
    if sujos:
        c.falhas.append("byte de controle em arquivo de texto: %s" % "; ".join(sujos))


def _conferir_direcao_de_arte(c: "Conferencia") -> None:
    """`docs/11` contra `tools/arte/`, nos dois sentidos, MEDIANA E FAIXA.

    Os números do ORIGINAL naquele documento não são conferidos aqui: eles
    dependem da instalação da Steam, e quem os reproduz é
    `tools/arte/censo_do_original.py`. O que é conferido é o que o documento
    afirma sobre NÓS — e é aí que documento e código se separam.

    **A faixa é conferida junto com a mediana, e isso não é zelo.** A tolerância
    do conferidor do boneco é derivada da faixa; conferindo só a mediana, abrir
    a tolerância até nada reprovar era uma edição de um dígito que passava por
    todas as ferramentas. Foram dez mutações desse tipo, e as dez passaram.
    """
    try:
        doc = ler("docs/11-direcao-de-arte.md")
        gerador = ler("tools/arte/gerar_personagem.py")
        conferidor = ler("tools/arte/conferir_personagem.py")
    except OSError as erro:
        # Falta de arquivo é FALHA, não degradação benigna: a versão anterior
        # tinha um `c.avisar()` aqui que era inalcançável, porque `ler()`
        # levanta em vez de devolver vazio. Caminho documentado que era ficção.
        c.contar()
        c.falhas.append("a direção de arte não pôde ser lida: %s" % erro)
        return

    proporcao = _proporcao_do_gerador(gerador)
    faixas = _faixas_do_conferidor(conferidor)
    # **A terceira fonte.** Documento e conferidor podiam ser alargados juntos,
    # numa edição visível mas em dois lugares, e nada automatizado sustentava a
    # faixa — ela é uma medida do ORIGINAL, que esta ferramenta não lê. O
    # instantâneo é escrito por `censo_do_original.py` a partir dos bundles, e
    # é ele que ancora os outros dois.
    try:
        medidas = json.loads(ler("data/direcao-de-arte.json"))["proporcao"]
    except (OSError, KeyError, ValueError) as erro:
        medidas = {}
        c.contar()
        c.falhas.append(
            "o instantâneo das medidas do original não pôde ser lido (%s) — "
            "regere com `py tools/arte/censo_do_original.py`" % erro
        )
    c.contar()
    if len(proporcao) != len(DIRECAO_LINHAS):
        c.falhas.append(
            "`PROPORCAO` do gerador tem %d chaves e a tabela de `docs/11` "
            "descreve %d — uma delas foi mexida sem a outra"
            % (len(proporcao), len(DIRECAO_LINHAS))
        )

    for rotulo, (chave, medida) in sorted(DIRECAO_LINHAS.items()):
        c.contar()
        linha = _tabela_do_documento(doc, rotulo)
        if linha is None:
            c.falhas.append(
                "docs/11: a linha `%s` sumiu das tabelas — a conferência ficou "
                "órfã" % rotulo
            )
            continue
        mediana, minimo, maximo = linha
        if chave not in proporcao:
            c.falhas.append("`PROPORCAO` do gerador não tem `%s`" % chave)
        elif abs(mediana - proporcao[chave]) > 1e-9:
            c.falhas.append(
                "docs/11 diz %s = %.3f e o gerador usa %.3f"
                % (rotulo, mediana, proporcao[chave])
            )
        c.contar()
        if chave in medidas:
            do_censo = tuple(medidas[chave])
            if (abs(do_censo[0] - mediana) > 5e-4
                    or abs(do_censo[1] - minimo) > 5e-4
                    or abs(do_censo[2] - maximo) > 5e-4):
                c.falhas.append(
                    "docs/11 publica %s = %.3f (%.3f a %.3f) e o instantâneo "
                    "medido no original diz %.3f (%.3f a %.3f)"
                    % (rotulo, mediana, minimo, maximo, *do_censo)
                )
        elif medidas:
            c.falhas.append(
                "o instantâneo não tem `%s` — a medida perdeu a âncora no "
                "original" % chave
            )
        c.contar()
        if medida not in faixas:
            c.falhas.append(
                "o conferidor do boneco não tem a faixa de `%s` — a medida "
                "deixou de ser julgada" % medida
            )
            continue
        if (abs(faixas[medida][0] - mediana) > 1e-9
                or abs(faixas[medida][1] - minimo) > 1e-9
                or abs(faixas[medida][2] - maximo) > 1e-9):
            c.falhas.append(
                "docs/11 publica %s = %.3f (%.3f a %.3f) e o conferidor usa "
                "%.3f (%.3f a %.3f)" % (rotulo, mediana, minimo, maximo,
                                        faixas[medida][0], faixas[medida][1],
                                        faixas[medida][2])
            )

    # A altura, que o §2 manda e o gerador e o conferidor obedecem.
    c.afirma("docs/11 altura do personagem", doc,
             r"todo personagem tem \*\*1,(\d+) m\*\*", 75)
    c.contar()
    alt_g = re.search(r"^ALTURA = ([0-9.]+)", gerador, re.M)
    alt_c = re.search(r"^ALTURA_DA_DIRECAO = ([0-9.]+)", conferidor, re.M)
    if alt_g is None or alt_c is None:
        c.falhas.append("a altura sumiu do gerador ou do conferidor do boneco")
    elif abs(float(alt_g.group(1)) - 1.75) > 1e-9 or abs(float(alt_c.group(1)) - 1.75) > 1e-9:
        c.falhas.append(
            "docs/11 manda 1,75 m; gerador diz %s e conferidor diz %s"
            % (alt_g.group(1), alt_c.group(1))
        )

    # A cadência, que o documento afirma e a conferência usa.
    c.afirma("docs/11 cadência", doc, r"\*\*(\d+) quadros por segundo\*\*", 30)
    c.afirma("conferidor cadência", conferidor, r"CADENCIA = (\d+)\.0", 30)

    # ------------------------------------------------ os números DERIVADOS
    #
    # A coluna "Em 1,75 m" do §1 e a tabela inteira do §9 são a ponte entre a
    # fração medida e o metro que o boneco tem. Ninguém os conferia: trocar
    # "pulso 0,872" por "0,999" passava por tudo. São aritmética pura, e
    # aritmética pura é exatamente o que uma máquina confere melhor que um
    # leitor.
    for rotulo, (chave, _medida) in sorted(DIRECAO_LINHAS.items()):
        linha = _tabela_do_documento(doc, rotulo)
        if linha is None or "altura" in rotulo:
            continue
        c.contar()
        emmetros = re.search(
            r"\| %s \| \*{0,2}-?[0-9],[0-9]+\*{0,2} \| -?[0-9],[0-9]+ – -?[0-9],[0-9]+ "
            r"\| (-?[0-9],[0-9]+) \|" % re.escape(rotulo), doc
        )
        if emmetros is None:
            c.falhas.append(
                "docs/11: a coluna em metros da linha `%s` sumiu" % rotulo
            )
        elif abs(_decimal(emmetros.group(1)) - round(linha[0] * 1.75, 3)) > 5e-4:
            c.falhas.append(
                "docs/11: `%s` é %.3f da altura, o que dá %.3f m em 1,75 — e a "
                "tabela diz %s" % (rotulo, linha[0], linha[0] * 1.75,
                                   emmetros.group(1))
            )

    # A tabela do §9, que traduz cada fração para o número que o gerador usa.
    for rotulo, formula, conta in (
        ("tornozelo", "tornozelo", lambda v: v["tornozelo"] * 1.75),
        ("joelho", "joelho", lambda v: v["joelho"] * 1.75),
        ("quadril", "quadril", lambda v: v["quadril"] * 1.75),
        ("peito", "peito", lambda v: v["peito"] * 1.75),
        ("pescoço", "pescoco", lambda v: v["pescoco"] * 1.75),
        ("pulso", None, lambda v: (v["ombro"] * 1.75
                                   - (v["vao_das_maos"] - v["vao_dos_ombros"]) * 1.75 / 2)),
        ("ponta da mão", None, lambda v: (
            v["ombro"] * 1.75
            - (v["vao_das_maos"] - v["vao_dos_ombros"]) * 1.75 / 2
            - (v["envergadura"] - v["vao_das_maos"]) * 1.75 / 2)),
    ):
        c.contar()
        achado = re.search(r"\| %s ([0-9],[0-9]+) \|" % re.escape(rotulo), doc)
        if achado is None:
            c.falhas.append("docs/11 §9: a linha `%s` sumiu da tabela" % rotulo)
            continue
        if not proporcao:
            continue
        esperado = round(conta(proporcao), 3)
        if abs(_decimal(achado.group(1)) - esperado) > 5e-4:
            c.falhas.append(
                "docs/11 §9 diz `%s` = %s e a conta com a proporção do gerador "
                "dá %.3f" % (rotulo, achado.group(1), esperado)
            )

    # A altura mediana do elenco, que o §2 publica e o instantâneo mede.
    c.contar()
    no_doc = re.search(r"mediana ([0-9],[0-9]+)\*\* — 15% de variação", doc)
    if no_doc is None:
        c.falhas.append("docs/11 §2: a altura mediana do elenco sumiu")
    elif medidas and abs(_decimal(no_doc.group(1)) - medidas["altura"][0]) > 5e-4:
        c.falhas.append(
            "docs/11 §2 diz mediana %s e o instantâneo mede %.3f"
            % (no_doc.group(1), medidas["altura"][0])
        )

    # O passo do arredondamento da folga. **É o último lugar onde uma edição de
    # um dígito abre TODAS as tolerâncias de uma vez** — derivar a folga tirou o
    # número de dez lugares e o pôs em um só, e um lugar sem conferência é um
    # lugar.
    c.contar()
    no_doc = re.search(r"passos de \*\*0,(\d+)\*\*", doc)
    no_codigo = re.search(r"PASSO_DA_FOLGA = ([0-9.]+)", conferidor)
    if no_doc is None or no_codigo is None:
        c.falhas.append("o passo da folga sumiu de `docs/11` ou do conferidor")
    elif abs(_decimal("0," + no_doc.group(1)) - float(no_codigo.group(1))) > 1e-9:
        c.falhas.append(
            "docs/11 diz passo de 0,%s e o conferidor usa %s"
            % (no_doc.group(1), no_codigo.group(1))
        )

    # Quanto o corpo tem que sair do chão em cada animação de voo. Era a única
    # conferência que exigia que o salto saltasse, e não era publicada.
    for nome, padrao in (("salto", r"o salto sobe pelo menos \*\*(\d+) cm\*\*"),
                         ("correndo", r"corrida sai do chão pelo menos \*\*(\d+) cm\*\*")):
        c.contar()
        no_doc = re.search(padrao, doc)
        no_codigo = re.search(r'"%s": ([0-9.]+)' % nome, conferidor)
        if no_doc is None or no_codigo is None:
            c.falhas.append("o voo de `%s` sumiu de `docs/11` ou do conferidor" % nome)
        elif abs(float(no_doc.group(1)) / 100.0 - float(no_codigo.group(1))) > 1e-9:
            c.falhas.append(
                "docs/11 diz %s cm de voo para `%s` e o conferidor usa %s m"
                % (no_doc.group(1), nome, no_codigo.group(1))
            )

    # A lista do que o conferidor exige tem que ser a lista do que o gerador
    # produz. Sem isto, tirar um nome de `NOMES_EXIGIDOS` fazia a animação
    # inteira deixar de ser medida — duração, chão e amplitude — sem uma falha.
    c.contar()
    do_gerador = sorted(_duracoes_do_gerador(gerador))
    exigidos = re.search(r"NOMES_EXIGIDOS = \[(.*?)\]", conferidor, re.S)
    if exigidos is None:
        c.falhas.append("`NOMES_EXIGIDOS` sumiu do conferidor do boneco")
    else:
        pedidos = sorted(re.findall(r'"(\w+)"', exigidos.group(1)))
        if pedidos != do_gerador:
            c.falhas.append(
                "o gerador produz %s e o conferidor exige %s — o que sobra não "
                "é medido por ninguém" % (do_gerador, pedidos)
            )

    # As três tolerâncias que não saem de faixa nenhuma, e por isso são
    # declaradas no §9 para poderem ser conferidas. Sem isto, alargar qualquer
    # uma até nada reprovar era uma edição de um dígito.
    for rotulo, no_doc_padrao, no_codigo_padrao in (
        ("altura", r"a altura vale com folga de \*\*([0-9]) cm\*\*",
         r"FOLGA_DA_ALTURA = ([0-9.]+)"),
        ("chão", r"chão com folga de \*\*([0-9],[0-9]) cm\*\*",
         r"TOLERANCIA_DO_CHAO = ([0-9.]+)"),
        ("amplitude", r"amplitude de pelo menos\s+\*\*([0-9]) cm\*\*",
         r"MOVIMENTO_MINIMO = ([0-9.]+)"),
    ):
        c.contar()
        no_doc = re.search(no_doc_padrao, doc)
        no_codigo = re.search(no_codigo_padrao, conferidor)
        if no_doc is None or no_codigo is None:
            c.falhas.append(
                "a tolerância de %s sumiu de `docs/11` ou do conferidor" % rotulo
            )
        elif abs(_decimal(no_doc.group(1)) / 100.0 - float(no_codigo.group(1))) > 1e-9:
            c.falhas.append(
                "docs/11 diz %s cm de tolerância de %s e o conferidor usa %s m"
                % (no_doc.group(1), rotulo, no_codigo.group(1))
            )

    # As três de locomoção: a faixa do conferidor é a faixa publicada do clipe
    # equivalente do original, sem folga inventada.
    for nossa, deles in sorted(DIRECAO_LOCOMOCAO.items()):
        c.contar()
        no_doc = re.search(
            r"\| `%s` \| ([0-9],[0-9]+) / [0-9],[0-9]+ / ([0-9],[0-9]+) s \|" % deles, doc
        )
        no_codigo = re.search(
            r'"%s": \(([0-9.]+), ([0-9.]+)\)' % nossa, conferidor
        )
        if no_doc is None:
            c.falhas.append("docs/11: a linha de `%s` sumiu do vocabulário" % deles)
        elif no_codigo is None:
            c.falhas.append("a faixa de `%s` sumiu do conferidor do boneco" % nossa)
        elif (abs(_decimal(no_doc.group(1)) - float(no_codigo.group(1))) > 1e-9
              or abs(_decimal(no_doc.group(2)) - float(no_codigo.group(2))) > 1e-9):
            c.falhas.append(
                "docs/11 publica `%s` de %s a %s e a faixa de `%s` é %s--%s"
                % (deles, no_doc.group(1), no_doc.group(2), nossa,
                   no_codigo.group(1), no_codigo.group(2))
            )

    # Os cinco gestos: a faixa é o par de quartis publicado.
    quartis = re.search(r"p25 \*\*([0-9],[0-9]+)\*\* · p75 \*\*([0-9],[0-9]+)\*\*", doc)
    c.contar()
    if quartis is None:
        c.falhas.append("docs/11: os quartis dos clipes de habilidade sumiram")
    else:
        p25, p75 = _decimal(quartis.group(1)), _decimal(quartis.group(2))
        for gesto in ("estocada", "giro", "salto", "erguer", "preparo"):
            c.contar()
            achado = re.search(
                r'"%s": \(([0-9.]+), ([0-9.]+)\)' % gesto, conferidor
            )
            if achado is None:
                c.falhas.append(
                    "a faixa de duração de `%s` sumiu do conferidor" % gesto
                )
            elif (abs(float(achado.group(1)) - p25) > 1e-9
                  or abs(float(achado.group(2)) - p75) > 1e-9):
                c.falhas.append(
                    "docs/11 publica quartis %.2f--%.2f e a faixa de `%s` é "
                    "%s--%s" % (p25, p75, gesto, achado.group(1), achado.group(2))
                )


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
    # Espaços cujo pulso ATRASADO acompanha alguém. Pulso instantâneo não
    # conta: a âncora dele já sai no lugar certo, e perseguir por zero segundo
    # não muda nada. Foi essa distinção que reformulou a lacuna.
    espacos_que_perseguem = 0
    campeoes_que_perseguem: set = set()
    # Espaços cuja habilidade abre corrente de combo. O tradutor só emite
    # corrente quando o destino faz alguma coisa — ver `_corrente`.
    espacos_com_corrente = 0
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
            if any(
                p.get("follow", "NONE") != "NONE"
                and float(p.get("delay", 0.0)) > 0.0
                and p["effects"]
                for p in escolhida["pulses"]
            ):
                espacos_que_perseguem += 1
                campeoes_que_perseguem.add(a["id"])
            if escolhida.get("combo_next_id"):
                espacos_com_corrente += 1
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
    c.contar()
    if len(custos) != 1 or 1000.0 not in custos:
        c.falhas.append(
            "o custo da suprema deixou de ser 1000 para todos: %s" % sorted(custos)
        )
    c.contar()
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

    # -------------------------------- o anel de alcance dizia a verdade?
    #
    # `cast_range` vem de `AI_SkillRange`, que é a distância em que a IA usa a
    # habilidade — e não até onde ela pega. Pintar um anel com ele enganou o
    # usuário: o R do Leo anuncia 4 m, pega até 3, e virou "impossível de
    # acertar". Este número é a extensão do engano.
    def alcance_efetivo(a: dict) -> float:
        maior = 0.0
        for p in a["pulses"]:
            if not p["effects"]:
                continue
            base = 0.0 if p["origin"] == "CASTER" else a["cast_range"]
            off = float(p.get("forward_offset", 0.0))
            if p["form"] in ("PROJECTILE", "LINE", "CONE", "TRAPEZOID"):
                alcance = base + off + float(p.get("length", 0.0))
            elif p["form"] == "SINGLE":
                alcance = a["cast_range"]
            else:
                alcance = base + off + float(p.get("radius", 0.0))
            maior = max(maior, alcance)
        return maior if maior > 0.0 else a["cast_range"]

    com_alcance = 0
    anel_mentia = 0
    for a in atores:
        if a["usage"] != "Player" or not a["ability_groups"]:
            continue
        grupos = list(a["ability_groups"])
        if a["ultimate_group"]:
            grupos.append(a["ultimate_group"])
        for grupo in grupos:
            escolhida = rank_for_level(grupo, NIVEL_DE_REFERENCIA)
            if escolhida is None or escolhida["cast_range"] <= 0.0:
                continue
            com_alcance += 1
            if alcance_efetivo(escolhida) < escolhida["cast_range"] - 0.05:
                anel_mentia += 1
    c.afirma("ability.gd espaços em que o anel mentia", ability_gd,
             r"em \*\*(\d+) dos \d+ espaços\*\* de campeão com alcance",
             anel_mentia)
    c.afirma("ability.gd espaços com alcance declarado", ability_gd,
             r"em \*\*\d+ dos (\d+) espaços\*\* de campeão com alcance",
             com_alcance)

    # ------------------------------------------- corrente de combo
    c.afirma("ability.gd espaços com corrente", ability_gd,
             r"vale para \*\*(\d+) dos \d+ espaços de campeão\*\*",
             espacos_com_corrente)
    c.afirma("docs/02 espaços com corrente", doc02_ritmo,
             r"\*\*(\d+) dos 127 espaços\*\* abrem corrente",
             espacos_com_corrente)
    # E o corpus tem que concordar com o contador do tradutor.
    c.contar()
    do_corpus = sum(1 for h in habilidades if h.get("combo_next_id"))
    # O contador de emissões conta o que o tradutor EMITIU; a poda vem depois,
    # com o corpus pronto. Comparar sem descontar acusaria a poda de ser um
    # defeito — e é ela que impede a corrente para o vazio.
    podadas = _emissoes_lacuna(
        relatorio, "corrente de combo podada (o elo traduzido ficou sem efeito)"
    )
    do_relatorio = _emissoes(relatorio, "corrente de combo") - podadas
    if do_corpus != do_relatorio:
        c.falhas.append(
            "corrente de combo: o corpus tem %d e o RELATORIO conta %d "
            "(emitidas menos %d podadas)" % (do_corpus, do_relatorio, podadas)
        )
    # A guarda que recusa corrente para elo sem efeito é o que impede a
    # mecânica de virar armadilha; se ela parar de disparar, o número cai.
    c.afirma("docs/02 correntes podadas", doc02_ritmo,
             r"\*\*poda (\d+) correntes\*\*",
             _emissoes_lacuna(
                 relatorio,
                 "corrente de combo podada (o elo traduzido ficou sem efeito)"))
    c.afirma("docs/02 correntes recusadas", doc02_ritmo,
             r"\*\*(\d+) correntes\*\* foram recusadas",
             _emissoes_lacuna(
                 relatorio,
                 "corrente de combo para elo sem efeito "
                 "(o golpe caiu em lacuna)"))

    # -------------------------------------------- perseguição da âncora
    pulso_gd = ler("scripts/core/abilities/ability_pulse.gd")
    atrasados = [
        p for h in habilidades for p in h["pulses"]
        if float(p.get("delay", 0.0)) > 0.0 and p["effects"]
    ]
    perseguem = [p for p in atrasados if p.get("follow", "NONE") != "NONE"]
    c.afirma("ability_pulse.gd pulsos atrasados que ficam", pulso_gd,
             r"\*\*(\d+) dos \d+ pulsos atrasados\*\*",
             len(atrasados) - len(perseguem))
    c.afirma("ability_pulse.gd pulsos atrasados", pulso_gd,
             r"\*\*\d+ dos (\d+) pulsos atrasados\*\*", len(atrasados))
    c.afirma("ability_engine.gd pulsos que perseguem",
             ler("scripts/core/abilities/ability_engine.gd"),
             r"(\d+) dos \d+ pulsos atrasados", len(perseguem))
    c.afirma("ability_pulse.gd espaços que perseguem", pulso_gd,
             r"\*\*(\d+) dos \d+ espaços de campeão\*\*", espacos_que_perseguem)
    c.afirma("docs/10 espaços que perseguem", doc10,
             r"são (\d+) dos \d+ espaços de campeão", espacos_que_perseguem)
    # A decisão 19, inteira. Todos os quatro números da reformulação, incluindo
    # o eixo em que "instantâneo" é medido: a primeira versão dizia 353 porque
    # media `duration == 0`, e o motor decide por `delay > 0`.
    todos_que_seguem = sum(
        1 for h in habilidades for p in h["pulses"]
        if p.get("follow", "NONE") != "NONE"
    )
    c.afirma("docs/02 pulsos que perseguem", doc02_ritmo,
             r"\*\*(\d+) pulsos\*\* que declaram perseguição", todos_que_seguem)
    c.afirma("docs/02 perseguem e são atrasados", doc02_ritmo,
             r"\*\*(\d+) são atrasados\*\*", len(perseguem))
    c.afirma("docs/02 perseguem e são instantâneos", doc02_ritmo,
             r"os outros \*\*(\d+)\*\* já saíam certos",
             todos_que_seguem - len(perseguem))
    c.afirma("docs/02 campeões que perseguem", doc02_ritmo,
             r"em \*\*(\d+) campeões\*\* — não 35",
             len(campeoes_que_perseguem))
    # E o corpus tem que concordar com o contador do tradutor, como no reset.
    c.contar()
    do_corpus = sum(
        1 for h in habilidades for p in h["pulses"]
        if p.get("follow", "NONE") != "NONE"
    )
    do_relatorio = (
        _emissoes(relatorio, "perseguição da âncora (FollowTarget=CASTER)")
        + _emissoes(relatorio, "perseguição da âncora (FollowTarget=TARGET)")
    )
    if do_corpus != do_relatorio:
        c.falhas.append(
            "perseguição da âncora: o corpus tem %d e o RELATORIO conta %d"
            % (do_corpus, do_relatorio)
        )
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
    c.afirma("CLAUDE.md reconto: perseguição", claude,
             r"\*\*35 → (\d+)\*\*", espacos_que_perseguem)
    # ------------------- as duas tabelas das seis lacunas têm que concordar
    #
    # O `CLAUDE.md` lista as seis lacunas DUAS vezes, e as duas listas
    # discordaram: a de cima marcava o arco como fora de escopo e a de baixo
    # continuava a listar como trabalho aberto — no mesmo commit em que a
    # decisão 20 explica que documentação discordando é o defeito, e no arquivo
    # que toda sessão é mandada ler inteiro.
    #
    # Nada pegava: as linhas fechadas carregam números que esta ferramenta
    # confere, e a única que ficou para trás não tinha número nenhum.
    # **O parágrafo de ABERTURA da seção também é afirmação.**
    #
    # Ele dizia "a sessão está no meio dela" com as seis linhas da tabela
    # riscadas — e é o texto que a próxima sessão lê PRIMEIRO, sob um banner
    # que manda parar e ler. Quatro rodadas seguidas de revisão caíram nesta
    # mesma classe, e três delas foram em prosa, que nenhuma varredura de
    # linha de lista alcança.
    c.contar()
    riscadas_na_tabela = len(re.findall(r"\| ~~\d+~~ \|", claude))
    lead = re.search(
        r"\*\*as (uma|duas|três|quatro|cinco|seis) lacunas estão resolvidas\*\*",
        claude, re.I
    )
    if lead is None:
        c.falhas.append(
            "o parágrafo de abertura de `Onde parar de ler` não diz mais "
            "quantas lacunas estão resolvidas; a conferência ficou órfã"
        )
    else:
        dito = {"uma": 1, "duas": 2, "três": 3, "quatro": 4,
                "cinco": 5, "seis": 6}[lead.group(1).lower()]
        # As duas tabelas repetem cada lacuna, daí a metade.
        if dito != riscadas_na_tabela // 2:
            c.falhas.append(
                "a abertura diz `%s lacunas estão resolvidas` e as tabelas têm "
                "%d linhas riscadas (%d lacunas)"
                % (lead.group(1), riscadas_na_tabela, riscadas_na_tabela // 2)
            )

    # **Os números da abertura, derivados do corpus.**
    #
    # A reescrita da abertura introduziu uma afirmação NOVA e errada — "os 99
    # mobs já estão traduzidos com kit", quando 28 dos 99 têm `ability_groups`,
    # que é o que "com kit" significa nas outras quatro ocorrências do
    # repositório. Não era prosa envelhecida: era falsidade nova, na frase que
    # aponta o próximo passo, sob o banner "PARE AQUI E LEIA".
    mobs = [a for a in atores if a["usage"] == "Monster"]
    c.afirma("CLAUDE.md mobs traduzidos", claude,
             r"\*\*(\d+) mobs\*\*", len(mobs))
    c.afirma("CLAUDE.md mobs com kit", claude,
             r"\*\*(\d+) têm kit\*\*",
             sum(1 for a in mobs if a["ability_groups"]))
    c.afirma("CLAUDE.md mobs com ataque básico", claude,
             r"\*\*(\d+) têm ataque básico\*\*",
             sum(1 for a in mobs if a.get("basic_attack_group")))
    c.afirma("CLAUDE.md mobs com AIPath", claude,
             r"\*\*(\d+) têm `AIPath`\*\*",
             sum(1 for a in mobs if a.get("ai_profile")))

    lacunas_da_tabela = _lacunas_da_tabela(claude)
    c.contar()
    if len(lacunas_da_tabela) != 6:
        c.falhas.append(
            "a primeira tabela das lacunas tem %d linhas e a seção fala em "
            "seis; a leitura dela ficou órfã" % len(lacunas_da_tabela)
        )
    for lacuna in lacunas_da_tabela:
        c.contar()
        riscadas = len(re.findall(r"\| ~~%d~~ \|" % lacuna, claude))
        abertas = len(re.findall(r"\| \*?\*?%d\*?\*? \|" % lacuna, claude))
        if riscadas == 2 and abertas == 0:
            continue
        c.falhas.append(
            "a lacuna %d aparece %d vez(es) riscada e %d aberta nas duas "
            "tabelas do `CLAUDE.md`; elas têm que concordar sobre o estado"
            % (lacuna, riscadas, abertas)
        )

    # ------------------- sistema fechado tem que estar fechado em TODO lugar
    for nome, decisao in SISTEMAS_FECHADOS:
        for documento in DOCUMENTOS_DE_ESTADO:
            c.contar()
            texto = ler(documento)
            # "Riscado em qualquer lugar da linha" e não "riscado no nome":
            # numa tabela o traço costuma cair sobre o NÚMERO da lacuna, e
            # exigi-lo no nome acusaria linhas que já estão fechadas.
            abertos = [
                linha.strip() for linha in texto.splitlines()
                if ("**%s**" % nome) in linha
                and (linha.startswith("- ") or linha.startswith("| "))
                and "~~" not in linha
            ]
            if abertos:
                c.falhas.append(
                    "`%s` ainda lista `%s` como aberto (%d linha(s)), e a "
                    "decisão %d o fechou: %s"
                    % (documento, nome, len(abertos), decisao, abertos[0][:70])
                )

    # O numeral por extenso contra a lista que ele conta. Já foi "três" sobre
    # cinco pares, e o mesmo defeito já existiu em `docs/10` com "Dois bugs".
    c.contar()
    frase = re.search(
        r"As (uma|duas|três|quatro|cinco|seis) fechadas\s+mudaram de número:"
        r"([^.]*)", claude, re.S
    )
    if frase is None:
        c.falhas.append("a frase dos recontos sumiu do `CLAUDE.md`")
    else:
        escrito = {"uma": 1, "duas": 2, "três": 3, "quatro": 4,
                   "cinco": 5, "seis": 6}[frase.group(1)]
        pares = len(re.findall(r"→", frase.group(2)))
        if escrito != pares:
            c.falhas.append(
                "o `CLAUDE.md` diz `%s fechadas` e lista %d recontos"
                % (frase.group(1), pares)
            )

    c.afirma("CLAUDE.md reconto: corrente de combo", claude,
             r"\*\*14 → (\d+)\*\*", espacos_com_corrente)
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
    c.contar()
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
    c.contar()
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
    c.contar()

    if eventos < 9:
        c.falhas.append("TriggerSet.Event encolheu para %d" % eventos)
    c.contar()

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

        # Os TRÊS valores de `FollowTarget`, medidos no XML. Contá-los juntos
        # é o que produziu a lacuna mal descrita: "área que acompanha o alvo"
        # para uma coluna cuja maioria acompanha o CONJURADOR.
        pulso_xml = ler("scripts/core/abilities/ability_pulse.gd")
        c.afirma("ability_pulse.gd FollowTarget=None", pulso_xml,
                 r"em (\d+) impactos, `User`", medido["segue_nada"])
        c.afirma("ability_pulse.gd FollowTarget=User", pulso_xml,
                 r"`User` em (\d+)", medido["segue_conjurador"])
        c.afirma("ability_pulse.gd FollowTarget=Target", pulso_xml,
                 r"`Target` em (\d+)", medido["segue_alvo"])
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
        c.contar()
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
    # A do combo saiu quando a lacuna fechou: ela apontava para uma linha do
    # relatório que deixou de existir, e ficaria órfã — reprovando por um
    # motivo que não é o defeito. O que o roadmap diz sobre o combo agora é
    # conferido pelo bloco da decisão 21.
    for rotulo, chave, padrao in (
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
        (r"e três irmãs, (\d+)", ["janela de cancelamento por tempo"]),
        (r"`Link`, (\d+)",
         ["Link (corrente que liga dois alvos e rompe na distância)"]),
        (r"`UseSkillSlot`, (\d+)",
         ["UseSkillSlot (troca a habilidade de um espaço)"]),
        (r"`PhysicalDamageAmp_SkillE`, (\d+)",
         ["StatType=PhysicalDamageAmp_SkillE"]),
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
        #
        # O custo declarado aqui é 1 — a conferência das contagens do
        # `CLAUDE.md`. O resto do que a engine gata foi declarado no bloco das
        # sondas, e a soma dos dois é `_afirmacoes_que_dependem_da_engine()`.
        c.avisar(
            "%s; a contagem de ASSERÇÕES ficou sem conferir "
            "(defina GODOT_PATH para fechar)" % suite["motivo"],
            1,
        )
    elif not suite["passou"]:
        with c.dependendo_da_engine():
            # **Falha, não aviso.** Afirmar contagem de teste contra uma suíte
            # vermelha é pior que não afirmar nada: publica um número que descreve
            # um resultado que não vale.
            c.contar()
            c.falhas.append(
                "a suíte NÃO está verde (%s) — as contagens de `CLAUDE.md` não "
                "foram conferidas contra ela" % suite["motivo"]
            )
    else:
        with c.dependendo_da_engine():
            # **TODAS as ocorrências, não a primeira.** `re.search` ancora só a
            # primeira, e o `CLAUDE.md` repete o par em dois lugares — a segunda
            # podia envelhecer em silêncio, que é o defeito que esta ferramenta
            # inteira existe para não deixar acontecer.
            pares = re.findall(r"\*\*(\d+) testes, (\d+) asserções\*\*", claude)
            c.contar()
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

    # ---------------------------------------------------- sondas de cena
    #
    # As duas são a ÚNICA cobertura automática de `gameplay/`, e até esta
    # revisão nada lia o stderr delas. Rodam aqui, com o mesmo classificador
    # da suíte: código de saída, stderr e marca de sucesso.
    godot = _achar_godot()
    if godot is None:
        c.avisar(
            "Godot não encontrada; as %d sondas de cena e os %d limites "
            "publicados ficaram sem conferir" % (
                len(SONDAS),
                sum(len(d) for _r, _s, _p, d in LIMITES_DA_SONDA),
            ),
            _afirmacoes_que_dependem_da_engine() - 1,
        )
    else:
        with c.dependendo_da_engine():
            saida_por_sonda: dict = {}
            for nome, script, marca in SONDAS:
                c.contar()
                veredito = _rodar_sonda(godot, script, marca)
                saida_por_sonda[script] = veredito.get("saida", "")
                if not veredito["passou"]:
                    c.falhas.append("a %s NÃO passou (%s)" % (nome, veredito["motivo"]))

            # **Os limites que a sonda PUBLICA também são afirmação.**
            #
            # O `CLAUDE.md` os repete, e um deles ficou para trás: dizia "8735
            # assinaturas" enquanto a sonda media 9667 — número que a lacuna 4
            # moveu duas vezes, nas mesmas três linhas em que a contagem de testes
            # foi atualizada. Nenhuma conferência os cobria, ao contrário de todos
            # os outros números publicados por este projeto.
            #
            # PISO, e não igualdade, pela mesma razão do total de afirmações:
            # cobertura que cresce não pode obrigar a mexer no documento, mas
            # cobertura que encolhe tem que doer.
            for rotulo, script, padrao_da_sonda, documentos in LIMITES_DA_SONDA:
                medido = _numero(saida_por_sonda.get(script, ""), padrao_da_sonda)
                for documento, padrao_do_doc in documentos:
                    c.contar()
                    publicado = _numero(ler(documento), padrao_do_doc)
                    if medido < 0 or publicado < 0:
                        c.falhas.append(
                            "o limite `%s` ficou órfão (sonda=%d, %s=%d): um dos "
                            "dois textos mudou" % (rotulo, medido, documento, publicado)
                        )
                    elif publicado > medido:
                        c.falhas.append(
                            "`%s` publica %d de `%s` e a sonda mede %d"
                            % (documento, publicado, rotulo, medido)
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
    c.contar()
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

    # ------------------- a declaração de custo, conferida contra o trabalho
    #
    # **É esta conferência que faltou nas três vezes.** O custo que um ramo
    # benigno declara já ficou errado três vezes — o desconto escrito para uma
    # ausência e não para a irmã, a dispensa que jogava fora a quantidade, e
    # `len(SONDAS)` sobrevivendo ao bloco crescer nove afirmações. Declarar não
    # basta: a declaração tem que ser comparada com o que o bloco FEZ.
    #
    # Roda só com a engine presente, que é quando o trabalho de verdade
    # acontece. É o mesmo desenho da autoconferência do bloco do XML.
    # **A condição é a ENGINE, e não "não houve aviso".** Atrelada a
    # `not c.avisos`, esta conferência sumia junto com a ausência do XML — que
    # não tem nada a ver com ela — e o piso passava a cobrar uma afirmação a
    # mais do que podia acontecer. Cada degradação tem que afrouxar só o que
    # ela própria impede.
    if godot is not None and suite["rodou"]:
        with c.dependendo_da_engine():
            c.contar()
            declarado = _afirmacoes_que_dependem_da_engine()
            feito = c.com_engine
            if declarado != feito:
                c.falhas.append(
                    "o custo declarado da engine é %d e o bloco fez %d afirmações; "
                    "sem a Godot por perto o piso vai cobrar o que não podia "
                    "acontecer" % (declarado, feito)
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
    _conferir_direcao_de_arte(c)
    _conferir_o_artefato(c)
    _conferir_bytes_de_controle(c)

    c.contar()
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
