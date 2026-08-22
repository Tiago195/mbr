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
    return {
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


def _rodar_suite() -> tuple[int, int] | None:
    """(testes, asserções) rodando a suíte de verdade. `None` se não der.

    A contagem de testes dá para tirar estaticamente contando `func test_`; a
    de ASSERÇÕES não — ela é dinâmica. Ficava sem conferência, e uma
    revalidação mostrou que dava para trocar 936 por 9936 sem ninguém notar.
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
        return None

    try:
        saida = subprocess.run(
            [godot, "--headless", "--path", str(RAIZ),
             "--script", "res://tests/run_tests.gd"],
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=300,
        ).stdout
    except Exception:
        return None

    # A ÚLTIMA ocorrência é o total; as anteriores são uma por suíte. Pegar a
    # primeira dava "17 testes, 120 asserções" — o `test_stats` sozinho.
    achados = re.findall(r"(\d+) testes, (\d+) asserções", saida or "")
    if not achados:
        return None
    return int(achados[-1][0]), int(achados[-1][1])


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
    if medido is None:
        print(
            "[números] AVISO: as tabelas do original não estão em "
            "C:\\Godot\\rc-referencia\\xml; 8 afirmações ficaram sem conferir"
        )
    else:
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
    for rotulo, chave, padrao in (
        ("suprema", "UltimateCharge (carga de suprema)",
         r"\*\*Carga de suprema\*\* \((\d+) habilidades"),
        ("combo", "ComboSkillInfo (corrente de combo)",
         r"\*\*Corrente de combo\*\* \((\d+)\)"),
        ("cancelamento", "janela de cancelamento por tempo",
         r"\*\*Janelas de cancelamento\*\* \((\d+)\)"),
    ):
        c.afirma("docs/04 lacuna %s" % rotulo, roadmap, padrao,
                 _emissoes_lacuna(relatorio, chave))

    # --------------------------------- as tabelas de lacuna de docs/10
    #
    # Dezessete números, e foi exatamente aqui que um deles se escondeu por
    # quatro revalidações: a linha de `BuffReleaseCondition` dizia 58 quando o
    # relatório somava 60, porque uma das parcelas subiu numa correção e o
    # documento ficou. Bloco numérico grande sem conferência é onde o próximo
    # vai se esconder.
    #
    # Cada par é (rótulo na tabela do doc, chave no RELATORIO.md). Quando a
    # linha soma várias lacunas, a lista tem mais de uma chave.
    LACUNAS_DO_DOC = [
        (r"`UltimateCharge`, (\d+) habilidades",
         ["UltimateCharge (carga de suprema)"]),
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
        (r"`ResetAttackCoolTime`, (\d+)",
         ["habilidade que zera a cadência do ataque básico "
          "(`ResetAttackCoolTime` em skill)"]),
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

    suite = _rodar_suite()
    if suite is None:
        print(
            "[números] AVISO: Godot não encontrada; a contagem de ASSERÇÕES "
            "ficou sem conferir (defina GODOT_PATH para fechar)"
        )
    else:
        c.afirma("CLAUDE.md testes (suíte real)", claude,
                 r"\*\*(\d+) testes, \d+ asserções\*\*", suite[0])
        c.afirma("CLAUDE.md asserções", claude,
                 r"\*\*\d+ testes, (\d+) asserções\*\*", suite[1])

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
    print("[números] %d afirmações conferidas" % c.conferidas)
    if not c.falhas:
        print("[números] todas batem")
        return 0
    print("[números] %d NÃO batem:" % len(c.falhas), file=sys.stderr)
    for falha in c.falhas:
        print("  - %s" % falha, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
