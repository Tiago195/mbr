#!/usr/bin/env python3
"""Traduz as tabelas de design do Royal Crown para o nosso vocabulário.

Passo 4 de `docs/05-extracao-dados-apk.md`. Lê as 113 tabelas XML extraídas
(que vivem FORA deste repositório, em `C:\\Godot\\rc-referencia\\xml`) e emite,
em `data/traducao/`, as 948 habilidades e os 421 itens do original expressos
nas peças de `docs/03-sistemas-de-jogo.md`: `Ability`, `AbilityPulse`,
`DamageEffect`, `CrowdControlEffect`, `Item` e companhia.

Por que JSON e não 948 arquivos `.tres`:

- `.tres` é o formato de quem edita à mão. Um corpus gerado por ferramenta não
  se edita à mão — se editasse, a próxima execução do tradutor apagaria a
  edição.
- 1369 arquivos gerados afogariam o `git diff` de qualquer mudança futura no
  vocabulário. Em JSON, uma mudança de vocabulário é um diff legível.
- O JSON nomeia as NOSSAS classes e os NOSSOS enums. Ele não é um despejo do
  original: é a tradução, e o que não coube está registrado como lacuna em vez
  de sumir em silêncio.

`AbilityCatalog` e `ItemCatalog` (em `scripts/core/`) leem esse JSON e devolvem
`Ability` e `Item` de verdade — a tradução é executável, não um documento.

Uso:
    py tools/traducao/traduzir.py [--xml CAMINHO] [--saida CAMINHO]
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

XML_PADRAO = Path(r"C:\Godot\rc-referencia\xml")
SAIDA_PADRAO = Path(__file__).resolve().parents[2] / "data" / "traducao"


# --------------------------------------------------------------------------
# Leitura das tabelas
# --------------------------------------------------------------------------

class Tabelas:
    """As tabelas do original, indexadas por Id.

    O original espalha uma habilidade por quatro tabelas — `skill`, `impact`,
    `buff` e `crowd_control` — e o `_2` de cada uma é continuação, não versão
    alternativa. Juntar tudo aqui, uma vez, evita que cada tradutor tenha que
    lembrar disso.
    """

    def __init__(self, raiz: Path) -> None:
        self.raiz = raiz
        self.skills = self._indexar("skill_xml", "skill_2_xml", "skill_3_xml", "skill_4_xml")
        self.impacts = self._indexar("impact_xml", "impact_2_xml", "impact_3_xml", "impact_4_xml")
        self.buffs = self._indexar("buff_xml", "buff_2_xml", "buff_3_xml", "buff_4_xml")
        self.ccs = self._indexar("crowd_control_xml")
        self.equipment = self._indexar("equipment_xml")
        self.actors = self._indexar("actor_xml", "actor_2_xml", "actor_3_xml", "actor_4_xml")
        self.recipes = self._indexar("craft_recipe_xml")

    def _linhas(self, nome: str) -> list[ET.Element]:
        caminho = self.raiz / f"{nome}.xml"
        if not caminho.exists():
            return []
        try:
            return list(ET.parse(caminho).getroot())
        except ET.ParseError:
            return []

    def _indexar(self, *nomes: str) -> dict[str, dict[str, str]]:
        indice: dict[str, dict[str, str]] = {}
        for nome in nomes:
            for linha in self._linhas(nome):
                registro = {
                    filho.tag.strip(): (filho.text or "").strip()
                    for filho in linha
                }
                # De qual arquivo a linha veio. Serve ao relatório: a promessa
                # do Passo 4 fala em 948 habilidades, que é o tamanho de
                # `skill_xml`; as outras tabelas somam por cima, e misturar as
                # duas contagens esconderia se a promessa foi cumprida.
                registro["__tabela"] = nome
                chave = registro.get("Id", "")
                if chave:
                    # A ordem importa: `skill_xml` tem prioridade sobre
                    # `skill_2_xml` quando o mesmo Id aparece nas duas, porque
                    # a segunda é continuação e não substituição.
                    indice.setdefault(chave, registro)
        return indice


def num(texto: str | None, padrao: float = 0.0) -> float:
    if texto is None or texto == "":
        return padrao
    try:
        return float(texto)
    except ValueError:
        return padrao


def inteiro(texto: str | None, padrao: int = 0) -> int:
    return int(num(texto, padrao))


def booleano(texto: str | None, padrao: bool = False) -> bool:
    if not texto:
        return padrao
    return texto.strip().lower() == "true"


def id_e_pilha(bruto: str) -> tuple[str, int]:
    """Separa `3302000(5)` em id do buff e quantas pilhas aplicar.

    O original usa esse formato em 48 referencias de buff. Sem separar, o id
    vira uma string que nao existe em tabela nenhuma e o buff inteiro se
    perde — foi exatamente o que aconteceu na primeira execucao do tradutor.
    """
    achado = re.match(r"\s*(\d+)\s*(?:\((\d+)\))?\s*$", bruto or "")
    if not achado:
        return (bruto or "").strip(), 1
    return achado.group(1), int(achado.group(2) or 1)


def lista_ids(texto: str | None) -> list[str]:
    if not texto:
        return []
    return [p.strip() for p in texto.split(",") if p.strip()]


# --------------------------------------------------------------------------
# Mapas de vocabulário
# --------------------------------------------------------------------------

## `StatType` do original -> (nome do nosso atributo, é percentual?)
##
## As entradas com valor `None` NÃO viram atributo: viram outra coisa, e cada
## uma está tratada explicitamente onde importa. Deixá-las fora do mapa faria
## o tradutor reportá-las como desconhecidas, e elas não são.
STATS = {
    "PhysicalDamage": ("attack_damage", False),
    "MagicalDamage": ("ability_power", False),
    "PhysicalDefense": ("armor", False),
    "MagicalDefense": ("magic_resist", False),
    "MaxHP": ("max_health", False),
    "HP": ("max_health", False),
    "MaxMP": ("max_mana", False),
    "MP": ("max_mana", False),
    "HPRegen": ("health_regen", False),
    "MPRegen": ("mana_regen", False),
    "NoncombatHPRegen": ("out_of_combat_health_regen", False),
    "NoncombatMPRegen": ("out_of_combat_mana_regen", False),
    "AttackSpeedRate": ("attack_speed", True),
    "MaxAttackSpeedRate": ("attack_speed_cap", True),
    "MovingSpeed": ("move_speed", False),
    "MaxMoveSpeed": ("move_speed_cap", False),
    # Aceleração e lentidão são o MESMO atributo com sinais opostos. Modelar
    # `SlowRatio` como atributo próprio criaria duas fontes de verdade para a
    # velocidade, e a soma delas teria que ser resolvida em algum lugar.
    "HasteRatio": ("move_speed", True),
    "SlowRatio": ("move_speed", True),
    "SlowResist": ("slow_resist", False),
    "Toughness": ("tenacity", False),
    "CriticalRatio": ("crit_chance", False),
    "CriticalDamageAmp": ("crit_damage", True),
    "CriticalDamageDefense": ("crit_damage_reduction", False),
    "Flexibility": ("crit_avoidance", False),
    "Accuracy": ("accuracy", False),
    "Agility": ("dodge", False),
    "PhysicalDrain": ("lifesteal", False),
    "MagicalDrain": ("spell_vamp", False),
    "PhysicalPenetration": ("armor_pen_flat", False),
    "MagicalPenetration": ("magic_pen_flat", False),
    "PhysicalPenetrationRatio": ("armor_pen_percent", False),
    "MagicalPenetrationRatio": ("magic_pen_percent", False),
    "CDReductionRatio": ("cooldown_reduction", False),
    "MaxCDReductionRatio": ("cooldown_reduction_cap", False),
    "UsableCDReductionRatio": ("item_cooldown_reduction", False),
    "PhysicalDamageAmp": ("physical_damage_amp", False),
    "MagicalDamageAmp": ("magic_damage_amp", False),
    # `Base...Amp` amplifica o atributo base em vez do dano final. No nosso
    # modelo isso é literalmente um modificador percentual do atributo.
    "BasePhysicalDamageAmp": ("attack_damage", True),
    "BaseMagicalDamageAmp": ("ability_power", True),
    # Redução de defesa é debuff no ALVO, não penetração do atacante. Vira
    # armadura negativa, que a fórmula de dano já sabe tratar.
    "PhysicalDefenseReduce": ("armor", False),
    "MagicalDefenseReduce": ("magic_resist", False),
    "PhysicalDefenseReduceRatio": ("armor", True),
    "MagicalDefenseReduceRatio": ("magic_resist", True),
    "HealAmp": ("heal_power", False),
    "ReceivedHealAmp": ("heal_received_amp", False),
    "HealReduceRatio": ("heal_received_amp", False),
    "HPRegenAmp": ("health_regen_amp", False),
    "HPReganReduceRatio": ("health_regen_amp", False),
    "ReceivedShieldAmp": ("shield_received_amp", False),
    "ShieldRegen": ("shield_regen", False),
    "SightRange": ("sight_range", False),
    "MaxGroggyHp": ("max_stagger", False),
    "GroggyHp": ("max_stagger", False),
    "Weight": ("weight", False),
    "AllDamageReduce": ("damage_taken_reduction", False),
}

## Atributos que INVERTEM o sinal na tradução. `SlowRatio: 0.3` quer dizer
## "30% mais lento", e no nosso modelo isso é `move_speed` com -0.3.
STATS_INVERTIDOS = {
    "SlowRatio",
    "PhysicalDefenseReduce",
    "MagicalDefenseReduce",
    "PhysicalDefenseReduceRatio",
    "MagicalDefenseReduceRatio",
    "HealReduceRatio",
    "HPReganReduceRatio",
}

## `StatType` que vira ESCUDO, não atributo. O valor é o tamanho do escudo, e
## as variantes `...Per...` são o escalonamento dele.
STATS_ESCUDO = {
    "MaxShield": None,
    "MaxShieldPerPhysicalDamage": "attack_damage",
    "MaxShieldPerMagicalDamage": "ability_power",
    "MaxShieldPerMaxHP": "max_health",
    "MaxShieldPerPhysicalDefense": "armor",
}

## `UI_Type` -> como o jogador aponta.
MIRA = {
    "None": "SELF",
    "InstantTarget": "UNIT",
    "CastTarget": "UNIT",
    "CastArea": "POINT",
    "CastTargetArea": "POINT",
    "CastAreaSummon": "POINT",
    "CastAreaCurveDirection": "POINT",
    "CastDirection": "DIRECTION",
    "CastDirectionAfterCircle": "DIRECTION",
    "CastDirectionalSquareArea": "DIRECTION",
    "CastCircularSector": "DIRECTION",
    "CastTrapezoid": "DIRECTION",
    "CastSquare": "POINT",
}

## `StartPosition` -> onde a forma se ancora.
ANCORA = {
    "User": "CASTER",
    "Mine": "CASTER",
    "TargetPosition": "AIM_POINT",
    "Target": "TARGET_UNIT",
    "ParentImpactPosition": "PREVIOUS",
}

## `Type` de `crowd_control_xml` -> nosso `CrowdControlEffect.Kind`.
##
## 13 tipos viram 8 porque o critério é COMPORTAMENTO: `HardStun` e `Freeze`
## atordoam igual a `Stun`, e `ThrowUp` e `Airborne` são o mesmo arremesso.
## Espelhar os 13 daria cinco caminhos para o mesmo `can_move() == false`.
CONTROLE = {
    "Slow": "SLOW",
    "Stun": "STUN",
    "HardStun": "STUN",
    "Freeze": "STUN",
    "ThrowUp": "AIRBORNE",
    "Airborne": "AIRBORNE",
    "Root": "ROOT",
    "Silence": "SILENCE",
    "Blind": "BLIND",
    "Charmed": "CHARM",
    "Taunt": "TAUNT",
    "Polymorph": "POLYMORPH",
    # `KnockBack` é empurrão puro: nenhum estado, só deslocamento. Ele aparece
    # aqui com valor nulo para dizer "conhecido, e de propósito não vira
    # estado" — o empurrão sai pelo `DisplacementEffect` logo abaixo.
    "KnockBack": None,
    "None": None,
}

## Controles que a tenacidade não encurta.
CONTROLE_DURO = {"HardStun", "ThrowUp", "Airborne", "KnockBack"}

## `Type` de `equipment_xml` -> (nossa espécie, nosso espaço).
ITEM_TIPO = {
    "Weapon": ("EQUIPMENT", "WEAPON"),
    "Armor": ("EQUIPMENT", "ARMOR"),
    "Helmet": ("EQUIPMENT", "HELMET"),
    "Boots": ("EQUIPMENT", "BOOTS"),
    "Glove": ("EQUIPMENT", "GLOVE"),
    "Trinket": ("EQUIPMENT", "TRINKET"),
    "UsableItem": ("CONSUMABLE", "NONE"),
    "Material": ("MATERIAL", "NONE"),
    "TalentCard": ("TALENT", "NONE"),
}

RARIDADE = {
    "Common": "COMMON",
    "Uncommon": "UNCOMMON",
    "Rare": "RARE",
    "Epic": "EPIC",
    "Legend": "LEGENDARY",
    "None": "COMMON",
}

## `RecoverDataType` -> o que a poção devolve.
RECUPERACAO = {
    "RegenHealth": ("health",),
    "RegenMana": ("mana",),
    "RegenAll": ("health", "mana"),
}


# --------------------------------------------------------------------------
# Relatório
# --------------------------------------------------------------------------

class Relatorio:
    """Contabilidade do que coube e do que não coube.

    Existe porque uma tradução silenciosa é indistinguível de uma tradução
    errada. Toda coluna do original que o tradutor encontra e não sabe
    converter entra aqui, com quantas vezes apareceu — e é essa lista que diz
    se o vocabulário ainda precisa crescer.
    """

    def __init__(self) -> None:
        self.lacunas: collections.Counter[str] = collections.Counter()
        self.usos: collections.Counter[str] = collections.Counter()
        self.exemplos: dict[str, list[str]] = collections.defaultdict(list)

    def usou(self, chave: str) -> None:
        self.usos[chave] += 1

    def lacuna(self, chave: str, onde: str = "") -> None:
        self.lacunas[chave] += 1
        if onde and len(self.exemplos[chave]) < 5:
            self.exemplos[chave].append(onde)


# --------------------------------------------------------------------------
# Tradução de efeitos
# --------------------------------------------------------------------------

def _slug(texto: str) -> str:
    """Identificador ASCII a partir de um caminho de ícone do original.

    Os nomes das tabelas são coreanos e não entram neste repositório — nome e
    descrição são conteúdo do original, não número nem estrutura, e a regra de
    `docs/01-visao-e-escopo.md` deixa de fora o que é conteúdo. O caminho do
    ícone, por outro lado, é um identificador em inglês (`skill_leo_attack`) e
    serve perfeitamente para navegar o catálogo.
    """
    limpo = re.sub(r"[^a-z0-9]+", "_", (texto or "").lower()).strip("_")
    return limpo


def _quem(registro: dict[str, str]) -> str:
    """De quem é esta habilidade, pelo atlas de ícone."""
    atlas = registro.get("AtlasName", "")
    achado = re.search(r"skill_([a-z0-9]+)$", atlas.lower())
    return achado.group(1) if achado else ""


class Tradutor:
    def __init__(self, tabelas: Tabelas, relatorio: Relatorio) -> None:
        self.t = tabelas
        self.r = relatorio

    # ---------------------------------------------------------- controle

    def controle(self, cc_id: str, alvo: str, onde: str) -> list[dict]:
        """Um `CrowdControl` do original vira estado + empurrão."""
        cc = self.t.ccs.get(cc_id)
        if cc is None:
            self.r.lacuna("crowd_control ausente", f"{onde} -> {cc_id}")
            return []

        tipo = cc.get("Type", "None")
        efeitos: list[dict] = []

        if tipo not in CONTROLE:
            self.r.lacuna(f"CrowdControl.Type={tipo}", onde)
        else:
            nosso = CONTROLE[tipo]
            if nosso is not None:
                self.r.usou(f"cc:{nosso}")
                efeito = {
                    "type": "crowd_control",
                    "recipient": alvo,
                    "control": nosso,
                    "duration": num(cc.get("Duration")),
                    "ignores_tenacity": tipo in CONTROLE_DURO,
                    "source_tag": f"rc_cc_{cc_id}",
                }
                if nosso == "SLOW":
                    # A intensidade da lentidão está em `StatType_1/StatValue_1`,
                    # não em `Duration`. Sem isso toda lentidão sairia com o
                    # nosso padrão de 30%, e o balanceamento do original se
                    # perderia justamente no controle mais comum dele.
                    efeito["slow_amount"] = self._intensidade_lentidao(cc, onde)
                efeitos.append(efeito)

        empurrao = self._empurrao(cc, alvo, onde)
        if empurrao:
            efeitos.append(empurrao)

        # Um controle pode carregar atributos além da lentidão — `SightRange`
        # reduzido é a cegueira parcial do original.
        for indice in range(1, 5):
            nome = cc.get(f"StatType_{indice}")
            if not nome or nome in ("SlowRatio",):
                continue
            mod = self._modificador(
                nome, num(cc.get(f"StatValue_{indice}")),
                num(cc.get("Duration")), alvo, f"rc_cc_{cc_id}", onde
            )
            if mod:
                efeitos.append(mod)
        return efeitos

    def _intensidade_lentidao(self, cc: dict[str, str], onde: str) -> float:
        for indice in range(1, 5):
            if cc.get(f"StatType_{indice}") == "SlowRatio":
                return num(cc.get(f"StatValue_{indice}"), 0.3)
        self.r.lacuna("Slow sem SlowRatio", onde)
        return 0.3

    def _empurrao(self, cc: dict[str, str], alvo: str, onde: str) -> dict | None:
        distancia = num(cc.get("Distance"))
        if distancia <= 0.0:
            return None
        direcao = cc.get("Direction", "Front")
        # ASSUNÇÃO registrada: `Backward` puxa, o resto empurra. O original não
        # documenta o eixo, e as entradas com `Distance` são quase todas
        # arremesso — que empurra. Se um dia isto se provar invertido, o
        # conserto é uma linha e vale para todas as 20 entradas de uma vez.
        modo = "TOWARD_CASTER" if direcao == "Backward" else "AWAY_FROM_CASTER"
        self.r.usou("displacement:cc")
        return {
            "type": "displacement",
            "recipient": alvo,
            "mode": modo,
            "distance": distancia,
            # Empurrão sofrido atravessa imobilização: quem está preso ao chão
            # ainda é arremessado. É o oposto do dash, que a imobilização corta.
            "ignores_root": True,
        }

    # ---------------------------------------------------------- buff

    def buff(
        self, bruto: str, alvo: str, onde: str, visitados: frozenset = frozenset()
    ) -> list[dict]:
        """Um `Buff` do original vira modificadores, escudo e periódicos.

        `visitados` é guarda de CICLO, não limite de profundidade. Buff que
        aponta para impacto que aponta para buff é comum e legítimo no
        original — cortar por profundidade descartava 66 habilidades inteiras.
        O que não pode é voltar ao mesmo nó.
        """
        buff_id, pilhas = id_e_pilha(bruto)
        marca = f"b{buff_id}"
        if marca in visitados:
            return []
        visitados = visitados | {marca}
        registro = self.t.buffs.get(buff_id)
        if registro is None:
            self.r.lacuna("buff ausente", f"{onde} -> {buff_id}")
            return []

        duracao = num(registro.get("Duration"), 0.0)
        # `-1` no original é "até alguém tirar". No nosso vocabulário isso é
        # duração negativa também, e `0` é instantâneo.
        if duracao == 0.0:
            duracao = 0.1
        tag = f"rc_buff_{buff_id}"
        efeitos: list[dict] = []

        escudo = self._escudo(registro, alvo, duracao, onde)
        if escudo:
            efeitos.append(escudo)

        for indice in range(1, 5):
            nome = registro.get(f"StatType{indice}")
            if not nome or nome in STATS_ESCUDO:
                continue
            mod = self._modificador(
                nome, num(registro.get(f"StatValue{indice}")) * pilhas,
                duracao, alvo, tag, onde,
                acumula=inteiro(registro.get("MaxStackCount"), 1),
            )
            if mod:
                efeitos.append(mod)

        if booleano(registro.get("IsInvincibility")) or booleano(registro.get("DamageImmunity")):
            self.r.usou("cc:INVULNERABLE")
            efeitos.append({
                "type": "crowd_control",
                "recipient": alvo,
                "control": "INVULNERABLE",
                "duration": duracao,
                "ignores_tenacity": True,
                "source_tag": tag,
            })

        # Buff que carrega impacto é dano-ao-longo-do-tempo, aura ou
        # regeneração — os três são o mesmo periódico com efeitos diferentes.
        for indice in (1, 2):
            impact_id = registro.get(f"Impact{indice}")
            if not impact_id:
                continue
            internos = self._efeitos_de_impacto(impact_id, onde, visitados)
            if not internos:
                continue
            impacto = self.t.impacts.get(impact_id, {})
            intervalo = num(impacto.get("LoopInterval"), 0.0) or 1.0
            self.r.usou("periodic")
            efeitos.append({
                "type": "periodic",
                "recipient": alvo,
                "interval": intervalo,
                "duration": duracao,
                "ticks_on_apply": False,
                "refreshes": True,
                "source_tag": tag,
                "effects": internos,
            })

        if registro.get("AffectType") == "Aura":
            # Aura no original é um buff que se propaga a quem está perto. Nós
            # aplicamos o efeito ao alvo e nada mais: o alcance da aura mora no
            # impacto que a distribui, e ele já foi traduzido como forma.
            self.r.usou("aura como buff simples")
        ajuste = self._ajuste_de_recarga(registro, alvo, onde)
        if ajuste:
            efeitos.append(ajuste)
        efeitos.extend(self._dissipar_no_evento(registro, alvo, tag, onde))

        # Buff sem atributo, sem impacto e sem controle é MARCADOR: o jogo
        # consulta a marca em outro lugar. 30 buffs do original são só isso, e
        # sem `MarkEffect` eles traduziam para nada — a marca do caçador, o
        # passo do combo e a postura da arma sumiam juntos.
        if not efeitos and registro.get("Line"):
            self.r.usou("mark")
            efeitos.append({
                "type": "mark",
                "recipient": alvo,
                "mark": f"rc_line_{registro['Line']}",
                "mode": "APPLY",
                "duration": duracao,
                "max_stacks": inteiro(registro.get("MaxStackCount"), 1),
                "amount": 1,
            })
        return efeitos

    def _ajuste_de_recarga(
        self, registro: dict, alvo: str, onde: str
    ) -> dict | None:
        """`AdjustCDSkillIds` + `AdjustCDTime` -> `CooldownEffect`.

        Os ids listados são de HABILIDADE, e vêm sempre em conjunto de cinco —
        os cinco ranques da mesma. No nosso modelo o alcance certo é o GRUPO:
        citar o ranque atingiria só um nível, e ninguém quer "reduz a recarga
        do seu Q, mas só no nível 3".
        """
        alvos = lista_ids(registro.get("AdjustCDSkillIds"))
        segundos = num(registro.get("AdjustCDTime"))
        if not alvos or segundos == 0.0:
            return None
        grupos: list[str] = []
        for skill_id in alvos:
            skill = self.t.skills.get(skill_id)
            grupo = f"rc_g_{skill.get('SkillGroupID', skill_id)}" if skill \
                else f"rc_g_{skill_id}"
            if grupo not in grupos:
                grupos.append(grupo)
        self.r.usou("cooldown")
        return {
            "type": "cooldown",
            "recipient": alvo,
            "group_ids": grupos,
            "seconds": segundos,
            "proportional": False,
        }

    ## `BuffReleaseCondition` -> evento em que o buff se desfaz.
    ##
    ## Só entram os que a camada `core/` sabe emitir sozinha. Os outros
    ## dependeriam de eventos de animação e de interação com o cenário, que não
    ## existem — e inventá-los para fechar a lacuna no papel seria pior que
    ## deixá-la aberta.
    DISSIPA_EM = {
        "ShieldExhaust": "SHIELD_BROKEN",
        "SkillActivated": "ABILITY_CAST",
    }

    def _dissipar_no_evento(
        self, registro: dict, alvo: str, tag: str, onde: str
    ) -> list[dict]:
        bruto = registro.get("BuffReleaseCondition")
        if not bruto:
            return []
        efeitos: list[dict] = []
        for condicao in [c.strip() for c in bruto.split(",") if c.strip()]:
            evento = self.DISSIPA_EM.get(condicao)
            if evento is None:
                self.r.lacuna(f"BuffReleaseCondition={condicao}", onde)
                continue
            self.r.usou(f"dissipa em {evento}")
            # Um gatilho de carga única cuja única função é apagar o buff que
            # o armou. "A aceleração dura até seu escudo quebrar" vira
            # exatamente isto, sem nenhuma peça nova.
            efeitos.append({
                "type": "trigger",
                "recipient": alvo,
                "event": evento,
                "charges": 1,
                "duration": -1.0,
                "source_tag": f"{tag}_fim",
                "effects": [{
                    "type": "cleanse",
                    "recipient": "CASTER",
                    "scope": "BUFFS",
                    "only_source": tag,
                    "strips_shield": False,
                }],
                "on_expire": [],
            })
        return efeitos

    def _escudo(
        self, registro: dict[str, str], alvo: str, duracao: float, onde: str
    ) -> dict | None:
        """Junta `MaxShield` e as variantes `...Per...` num escudo só.

        No original elas são linhas separadas do mesmo buff: um valor fixo mais
        uma fração de um atributo. É exatamente a forma do nosso `ShieldEffect`,
        e emitir dois escudos separados daria duas camadas onde havia uma.
        """
        base = 0.0
        escala_stat = ""
        escala = 0.0
        achou = False
        for indice in range(1, 5):
            nome = registro.get(f"StatType{indice}")
            if nome not in STATS_ESCUDO:
                continue
            achou = True
            valor = num(registro.get(f"StatValue{indice}"))
            atributo = STATS_ESCUDO[nome]
            if atributo is None:
                base += valor
            else:
                escala_stat = atributo
                escala += valor
        if not achou:
            return None
        self.r.usou("shield")
        return {
            "type": "shield",
            "recipient": alvo,
            "base_shield": base,
            "scaling_stat": escala_stat or "ability_power",
            "scaling_ratio": escala,
            "duration": duracao,
        }

    def _modificador(
        self,
        nome: str,
        valor: float,
        duracao: float,
        alvo: str,
        tag: str,
        onde: str,
        acumula: int = 1,
    ) -> dict | None:
        if nome not in STATS:
            self.r.lacuna(f"StatType={nome}", onde)
            return None
        atributo, percentual = STATS[nome]
        if nome in STATS_INVERTIDOS:
            valor = -valor
        self.r.usou(f"stat:{atributo}")
        return {
            "type": "stat_mod",
            "recipient": alvo,
            "stat": atributo,
            "kind": "PERCENT" if percentual else "FLAT",
            "value": valor,
            "duration": duracao,
            "stacks": acumula > 1,
            "max_stacks": acumula if acumula > 1 else 0,
            "source_tag": tag,
        }

    # ---------------------------------------------------------- impacto

    def _efeitos_de_impacto(
        self, impact_id: str, onde: str, visitados: frozenset = frozenset()
    ) -> list[dict]:
        """Traduz só as colunas `ImpactStat*` — sem a forma.

        Serve para o impacto encadeado e para o impacto pendurado num buff,
        que não têm forma própria a resolver: eles herdam quem já foi atingido.
        """
        marca = f"i{impact_id}"
        if marca in visitados:
            return []
        registro = self.t.impacts.get(impact_id)
        if registro is None:
            self.r.lacuna("impacto ausente", f"{onde} -> {impact_id}")
            return []
        return self._traduzir_stats(registro, onde, visitados | {marca})

    def _traduzir_stats(
        self, impacto: dict[str, str], onde: str, visitados: frozenset
    ) -> list[dict]:
        efeitos: list[dict] = []
        # Dano e cura são acumulados antes de virar efeito: o original separa a
        # parte que escala da parte fixa em duas linhas (`PhysicalAttack` e
        # `PhysicalConstDamage`), e emitir dois efeitos daria duas instâncias
        # de dano onde havia uma — dois números na tela, dois roubos de vida,
        # dois gatilhos de "ao acertar".
        dano: dict[str, dict] = {}
        cura: dict[str, dict] = {}

        for indice in range(1, 9):
            tipo = impacto.get(f"ImpactStatType{indice}")
            if not tipo:
                continue
            bruto = impacto.get(f"ImpactStatValue{indice}", "")
            alvo = "CASTER" if impacto.get(
                f"ImpactStatTargetType{indice}"
            ) == "User" else "TARGETS"

            for parte in [p.strip() for p in tipo.split(",") if p.strip()]:
                self._uma_coluna(
                    parte, bruto, alvo, dano, cura, efeitos, onde, visitados
                )

        # Invocação vem de colunas próprias, e NÃO de `ImpactStat`. Isto vivia
        # dentro do laço de colunas, e por isso nunca saía num impacto que só
        # invoca — 61 impactos do original são exatamente isso, e vinham
        # traduzidos como vazios.
        if impacto.get("SummonActorId"):
            self.r.usou("summon")
            efeitos.append({
                "type": "summon",
                "recipient": "CASTER",
                "actor_id": f"rc_actor_{impacto['SummonActorId']}",
                "lifetime": num(impacto.get("SummonPersistTime"), 10.0),
                "origin": "AIM_POINT",
                "forward_offset": 0.0,
                "inherits_caster_team": True,
                "explicit_team": 0,
            })

        # Ordem: dano e cura primeiro, depois controle e buff. É a ordem em que
        # o jogador percebe, e importa de verdade num caso — executar antes de
        # atordoar torna o atordoamento irrelevante.
        return list(dano.values()) + list(cura.values()) + efeitos

    def _uma_coluna(
        self,
        tipo: str,
        bruto: str,
        alvo: str,
        dano: dict[str, dict],
        cura: dict[str, dict],
        efeitos: list[dict],
        onde: str,
        visitados: frozenset,
    ) -> None:
        valor = num(bruto)

        def bloco_dano(chave: str, escala: str, tipo_dano: str) -> dict:
            if chave not in dano:
                dano[chave] = {
                    "type": "damage",
                    "recipient": alvo,
                    "base_damage": 0.0,
                    "scaling_stat": escala,
                    "scaling_stat_alt": escala,
                    "scaling_ratio": 0.0,
                    "damage_type": tipo_dano,
                    "percent_of_target_max_health": 0.0,
                    "monster_damage_cap": 0.0,
                    "restriction": "ANY",
                }
            return dano[chave]

        def bloco_cura(chave: str, escala: str) -> dict:
            if chave not in cura:
                cura[chave] = {
                    "type": "heal",
                    "recipient": alvo,
                    "base_heal": 0.0,
                    "scaling_stat": escala,
                    "scaling_ratio": 0.0,
                    "percent_of_max_health": 0.0,
                }
            return cura[chave]

        match tipo:
            case "PhysicalAttack":
                bloco_dano("fis", "attack_damage", "PHYSICAL")["scaling_ratio"] += valor
                self.r.usou("damage:physical")
            case "PhysicalConstDamage":
                bloco_dano("fis", "attack_damage", "PHYSICAL")["base_damage"] += valor
                self.r.usou("damage:physical")
            case "MagicalAttack":
                bloco_dano("mag", "ability_power", "MAGIC")["scaling_ratio"] += valor
                self.r.usou("damage:magic")
            case "MagicalConstDamage":
                bloco_dano("mag", "ability_power", "MAGIC")["base_damage"] += valor
                self.r.usou("damage:magic")
            case "PhysicalAttackPerTargetMaxHp":
                bloco_dano("fis", "attack_damage", "PHYSICAL")[
                    "percent_of_target_max_health"] += valor
                self.r.usou("damage:percent_hp")
            case "MagicalAttackPerTargetMaxHp":
                bloco_dano("mag", "ability_power", "MAGIC")[
                    "percent_of_target_max_health"] += valor
                self.r.usou("damage:percent_hp")
            case "MaxPhysicalDamageForMonster":
                bloco_dano("fis", "attack_damage", "PHYSICAL")["monster_damage_cap"] = valor
                self.r.usou("damage:monster_cap")
            case "MaxMagicalDamageForMonster":
                bloco_dano("mag", "ability_power", "MAGIC")["monster_damage_cap"] = valor
                self.r.usou("damage:monster_cap")
            case "SiegeDamage":
                # O valor é um multiplicador de cerco; o que interessa é que
                # este dano só vale contra estrutura.
                alvo_dano = bloco_dano("cerco", "attack_damage", "PHYSICAL")
                alvo_dano["restriction"] = "STRUCTURES_ONLY"
                alvo_dano["base_damage"] += valor
                self.r.usou("damage:siege")
            case "MagicalHeal":
                bloco_cura("mag", "ability_power")["scaling_ratio"] += valor
                self.r.usou("heal")
            case "MagicalConstHeal":
                bloco_cura("mag", "ability_power")["base_heal"] += valor
                self.r.usou("heal")
            case "PhysicalHeal":
                bloco_cura("fis", "attack_damage")["scaling_ratio"] += valor
                self.r.usou("heal")
            case "PhysicalConstHeal":
                bloco_cura("fis", "attack_damage")["base_heal"] += valor
                self.r.usou("heal")
            case "HealPerMaxHP":
                bloco_cura("pct", "ability_power")["percent_of_max_health"] += valor
                self.r.usou("heal:percent_hp")
            case "Mana":
                self.r.usou("resource")
                efeitos.append({
                    "type": "resource",
                    "recipient": alvo,
                    "amount": valor,
                    "percent_of_max": 0.0,
                })
            case "Die":
                self.r.usou("execute")
                efeitos.append({
                    "type": "execute",
                    "recipient": alvo,
                    "health_threshold": 1.0,
                    "respects_shield": True,
                    "affects_champions": True,
                })
            case "FixedHeal":
                bloco_cura("fixa", "ability_power")["base_heal"] += valor
                self.r.usou("heal")
            case "BetterAtkStat":
                # Escala pelo MAIOR entre ataque físico e poder de habilidade.
                # É a coluna que fez `scaling_stat_alt` existir.
                hibrido = bloco_dano("hibrido", "attack_damage", "MAGIC")
                hibrido["scaling_stat_alt"] = "ability_power"
                hibrido["scaling_ratio"] += valor
                self.r.usou("damage:hibrido")
            case "Buff":
                efeitos.extend(self.buff(bruto, alvo, onde, visitados))
            case "CrowdControl":
                efeitos.extend(self.controle(bruto, alvo, onde))
            case "Impact":
                # Impacto encadeado: os efeitos dele caem em quem este já pegou.
                efeitos.extend(self._efeitos_de_impacto(bruto, onde, visitados))
                self.r.usou("impacto encadeado")
            case "Warp" | "MoveToPosition":
                self.r.usou("displacement:teleporte")
                efeitos.append({
                    "type": "displacement",
                    "recipient": alvo,
                    "mode": "TO_AIM_POINT",
                    "distance": 0.0,
                    "ignores_root": False,
                })
            case "Link":
                self.r.lacuna(
                    "Link (corrente que liga dois alvos e rompe na distância)", onde
                )
            case "UseSkillSlot":
                self.r.lacuna("UseSkillSlot (troca a habilidade de um espaço)", onde)
            case "ReleaseImpact":
                self.r.lacuna("ReleaseImpact (cancela impacto em curso)", onde)
            case "PingList":
                self.r.lacuna("PingList (aviso na interface, não é combate)", onde)
            case "SummonRedzone" | "TakeOnVehicle":
                self.r.lacuna(f"{tipo} (modo de jogo específico)", onde)
            case _:
                self.r.lacuna(f"ImpactStatType={tipo}", onde)

    # ---------------------------------------------------------- pulso

    def pulso(
        self, impact_id: str, skill: dict[str, str], onde: str
    ) -> dict | None:
        impacto = self.t.impacts.get(impact_id)
        if impacto is None:
            self.r.lacuna("impacto ausente", f"{onde} -> {impact_id}")
            return None

        efeitos = self._traduzir_stats(impacto, onde, frozenset({f"i{impact_id}"}))
        if not efeitos:
            return None

        forma, geometria = self._forma(impacto, skill)
        alvos = self._filtro(impacto.get("TargetType", ""))
        atraso = num(impacto.get("StartTime")) + num(impacto.get("ColliderActiveDelay"))
        laco = num(impacto.get("LoopInterval"))

        pulso = {
            "form": forma,
            "origin": ANCORA.get(impacto.get("StartPosition", "User"), "CASTER"),
            "delay": round(atraso, 3),
            # `ActiveDuration` só vira duração de área quando há laço: sem
            # laço ela é o tempo que o colisor fica ligado, que para nós é
            # instantâneo — quem entrar depois não é atingido de novo.
            "duration": num(impacto.get("ActiveDuration")) if laco > 0 else 0.0,
            "loop_interval": laco,
            "max_targets": inteiro(impacto.get("ImpactCount"), 0),
            "effects": efeitos,
        }
        pulso.update(geometria)
        pulso.update(alvos)
        return pulso

    def _forma(
        self, impacto: dict[str, str], skill: dict[str, str]
    ) -> tuple[str, dict]:
        parametros = self._ui_params(skill)
        raio = num(impacto.get("Radius"), 1.0)
        ui = skill.get("UI_Type", "None")

        # Projétil primeiro: a coluna de voo é a evidência mais forte, e ela
        # convive com qualquer `UI_Type`.
        if impacto.get("ProjectileEffectId") or num(impacto.get("MoveDistance")) > 0:
            distancia = num(impacto.get("MoveDistance"), 8.0)
            return "PROJECTILE", {
                "radius": raio,
                "length": distancia,
                "width": max(raio * 2.0, 0.5),
                "projectile_speed": num(impacto.get("MoveSpeedZ"), 15.0),
                # `ImpactCount` 0 quer dizer "sem teto", e um projétil sem teto
                # é um que atravessa.
                "pierces": inteiro(impacto.get("ImpactCount"), 0) != 1,
            }

        if ui == "CastCircularSector":
            return "CONE", {
                "length": num(parametros.get("CircularSector_Range"), raio or 6.0),
                "cone_angle": num(parametros.get("CircularSector_Angle"), 60.0),
                "radius": raio,
            }

        if ui == "CastTrapezoid":
            perto = num(parametros.get("CastTrapezoid_Start_Distance"), 1.0)
            longe = num(parametros.get("CastTrapezoid_End_Distance"), 8.0)
            return "TRAPEZOID", {
                "near_distance": perto,
                "length": longe,
                "near_width": num(parametros.get("CastTrapezoid_Start_Width"), 1.0),
                "far_width": num(parametros.get("CastTrapezoid_End_Width"), 4.0),
                "radius": raio,
            }

        if ui in ("CastDirection", "CastDirectionalSquareArea", "CastDirectionAfterCircle"):
            return "LINE", {
                "length": num(skill.get("AI_SkillRange"), 8.0),
                "width": num(parametros.get("CastDirection_Width"), max(raio, 1.0)),
                "radius": raio,
            }

        if impacto.get("Radius"):
            return "CIRCLE", {"radius": raio}

        # Sem raio e sem direção: acerta quem foi apontado, e mais ninguém.
        return "SINGLE", {"radius": raio}

    @staticmethod
    def _ui_params(skill: dict[str, str]) -> dict[str, str]:
        cru = skill.get("UI_Params", "")
        saida: dict[str, str] = {}
        for parte in cru.split(","):
            if "=" in parte:
                chave, _, valor = parte.partition("=")
                saida[chave.strip()] = valor.strip()
        return saida

    @staticmethod
    def _filtro(target_type: str) -> dict:
        """`TargetType` -> quem a forma pega.

        O original escreve `Enemy(1,2,3,5,20)` — o nome diz o lado e os números
        dizem que espécies de ator. As espécies não entram: a nossa `Nature`
        cobre o que importa (campeão, mob, estrutura, invocação) e a lista
        numérica do original é uma taxonomia interna que não temos.
        """
        texto = target_type or ""
        inimigos = "Enemy" in texto
        aliados = "Ally" in texto
        proprio = "Mine" in texto or "Self" in texto
        if not (inimigos or aliados or proprio):
            inimigos = True
        return {
            "hits_enemies": inimigos,
            "hits_allies": aliados,
            "hits_self": proprio,
        }

    # ---------------------------------------------------------- habilidade

    def habilidade(self, skill: dict[str, str]) -> dict:
        skill_id = skill["Id"]
        onde = f"skill {skill_id}"
        dono = _quem(skill)
        icone = _slug(skill.get("ButtonIconPath", ""))

        pulsos: list[dict] = []
        for indice in range(1, 9):
            impact_id = skill.get(f"Impact{indice}")
            if not impact_id:
                continue
            pulso = self.pulso(impact_id, skill, onde)
            if pulso is not None:
                pulsos.append(pulso)

        ui = skill.get("UI_Type", "None")
        if ui not in MIRA:
            self.r.lacuna(f"UI_Type={ui}", onde)
        mira = MIRA.get(ui, "POINT")

        if skill.get("ComboSkillInfo_SkillID"):
            self.r.lacuna("ComboSkillInfo (corrente de combo)", onde)
        if skill.get("ZMoveCurvePath") or skill.get("YMoveCurvePath"):
            self.r.lacuna("curva de deslocamento (MoveCurve)", onde)
        if skill.get("CancelForbidStartTime"):
            self.r.lacuna("janela de cancelamento por tempo", onde)
        if skill.get("UltimateCharge"):
            self.r.lacuna("UltimateCharge (carga de suprema)", onde)

        # Ranque 0 é a linha-modelo do grupo: existe para a interface mostrar a
        # habilidade ainda não aprendida, e por isso não referencia impacto
        # nenhum. Marcá-la evita que o relatório conte 115 modelos como 115
        # falhas de tradução.
        marcador_de_combo = booleano(skill.get("UseChainBreak"))
        modelo = inteiro(skill.get("Rank"), 1) == 0

        return {
            "id": f"rc_{skill_id}",
            "source_id": int(skill_id),
            "source_table": skill.get("__tabela", "skill_xml"),
            "is_template": modelo,
            "is_chain_break": marcador_de_combo,
            "owner": dono,
            "icon": icone,
            "display_name": icone or f"rc_{skill_id}",
            "group_id": f"rc_g_{skill.get('SkillGroupID', skill_id)}",
            "rank": inteiro(skill.get("Rank"), 1),
            "level_requirement": inteiro(skill.get("LevelRequirement"), 0),
            "cooldown": num(skill.get("CoolTime")),
            # O original não trava a conjuração como um MOBA clássico: ele usa
            # a animação, com janelas de cancelamento. O que corresponde ao
            # nosso `cast_time` é o atraso do PRIMEIRO impacto, e esse já está
            # no `delay` do pulso. Deixar `cast_time` em zero e o atraso no
            # pulso é o que preserva o timing sem inventar um travamento.
            "cast_time": 0.0,
            "can_move_while_casting": booleano(skill.get("MovingOnSkill")),
            "cancelable": skill.get("SkillCancelableTime") is not None,
            "mana_cost": num(skill.get("CostValue")),
            "aim": mira,
            "cast_range": num(skill.get("AI_SkillRange"), 0.0),
            "pulses": pulsos,
        }

    # ---------------------------------------------------------- item

    def item(self, equip: dict[str, str]) -> dict:
        equip_id = equip["Id"]
        onde = f"equipment {equip_id}"
        tipo = equip.get("Type", "Material")
        if tipo not in ITEM_TIPO:
            self.r.lacuna(f"Equipment.Type={tipo}", onde)
        especie, espaco = ITEM_TIPO.get(tipo, ("MATERIAL", "NONE"))

        planos: dict[str, float] = {}
        percentuais: dict[str, float] = {}
        for indice in range(1, 9):
            nome = equip.get(f"StatType_{indice}")
            if not nome:
                continue
            if nome not in STATS:
                self.r.lacuna(f"StatType={nome}", onde)
                continue
            atributo, percentual = STATS[nome]
            valor = num(equip.get(f"StatValue_{indice}"))
            if nome in STATS_INVERTIDOS:
                valor = -valor
            destino = percentuais if percentual else planos
            destino[atributo] = destino.get(atributo, 0.0) + valor
            self.r.usou(f"stat:{atributo}")

        passivas: list[dict] = []
        for buff_id in lista_ids(equip.get("PassiveBuffs")):
            passivas.extend(self.buff(buff_id, "CASTER", onde))

        # Poção e comida: `RecoverDataType` diz o que devolve, e os valores
        # ficam em `DescParam`, que é texto de interface localizado. Sem os
        # números, a recuperação vira uma lacuna honesta em vez de um valor
        # inventado.
        recuperacao = equip.get("RecoverDataType")
        if recuperacao:
            if recuperacao in RECUPERACAO:
                self.r.lacuna(
                    f"RecoverDataType={recuperacao} sem valor legível "
                    "(os números vivem no texto localizado)", onde
                )
            else:
                self.r.lacuna(f"RecoverDataType={recuperacao}", onde)

        ativa = equip.get("SkillId")
        ativa_id = f"rc_{ativa}" if ativa and ativa != "0" else ""
        if ativa_id and ativa not in self.t.skills:
            self.r.lacuna("SkillId de item aponta para habilidade ausente", onde)
            ativa_id = ""

        return {
            "id": f"rc_item_{equip_id}",
            "source_id": int(equip_id),
            "icon": _slug(equip.get("IconPath", "")),
            "display_name": _slug(equip.get("IconPath", "")) or f"rc_item_{equip_id}",
            "kind": especie,
            "slot": espaco,
            "rarity": RARIDADE.get(equip.get("Rarity", "Common"), "COMMON"),
            "max_stack": inteiro(equip.get("MaxStackCount"), 1),
            "line_id": f"rc_line_{equip.get('EquipLine', equip_id)}",
            "sockets": inteiro(equip.get("Socket"), 0),
            "charges": inteiro(equip.get("UsableItemCount"), 0),
            "flat_bonuses": planos,
            "percent_bonuses": percentuais,
            "passive_effects": passivas,
            "active_ability_id": ativa_id,
            "built_from": [],
            "enabled": equip.get("Enable", "Release") == "Release",
        }


# --------------------------------------------------------------------------
# Receitas de fabricação
# --------------------------------------------------------------------------

def ligar_receitas(itens: list[dict], tabelas: Tabelas, relatorio: Relatorio) -> None:
    """Preenche `built_from` a partir de `craft_recipe_xml`.

    O modelo de item já previa combinação desde a Fase 5.2, por instrução de
    `03-sistemas-de-jogo.md`. Esta é a primeira vez que o campo recebe dado.
    """
    por_id = {item["source_id"]: item for item in itens}
    ligadas = 0
    for receita in tabelas.recipes.values():
        resultado = receita.get("ResultId")
        if not resultado:
            continue
        alvo = por_id.get(inteiro(resultado, -1))
        if alvo is None:
            continue
        ingredientes: list[str] = []
        for indice in range(1, 9):
            material = receita.get(f"RawMaterialId_{indice}")
            if not material or material == "0":
                continue
            quantas = inteiro(receita.get(f"RawMaterialCount_{indice}"), 1)
            # A quantidade vira repetição do id. `built_from` é uma lista de
            # ingredientes, e "duas barras de ferro" é literalmente o id duas
            # vezes — não exige um campo de contagem que só este caso usaria.
            ingredientes.extend([f"rc_item_{material}"] * max(quantas, 1))
        if ingredientes:
            alvo["built_from"] = ingredientes
            ligadas += 1
    if ligadas:
        for _ in range(ligadas):
            relatorio.usou("receita de fabricação")
    else:
        relatorio.lacuna("craft_recipe_xml sem coluna de resultado reconhecida")


# --------------------------------------------------------------------------
# Relatório em texto
# --------------------------------------------------------------------------

def escrever_relatorio(
    caminho: Path, habilidades: list[dict], itens: list[dict], r: Relatorio
) -> None:
    total_pulsos = sum(len(h["pulses"]) for h in habilidades)
    sem_pulso = [h for h in habilidades if not h["pulses"]]
    modelos = [h for h in sem_pulso if h["is_template"]]
    quebra_combo = [
        h for h in sem_pulso if h["is_chain_break"] and not h["is_template"]
    ]
    faltando = [
        h for h in sem_pulso
        if not h["is_template"] and not h["is_chain_break"]
    ]
    com_varios = [h for h in habilidades if len(h["pulses"]) > 1]
    total_efeitos = sum(
        len(p["effects"]) for h in habilidades for p in h["pulses"]
    )
    por_tabela = collections.Counter(h["source_table"] for h in habilidades)

    linhas: list[str] = []
    linhas.append("# Relatório da tradução do original")
    linhas.append("")
    linhas.append(
        "> **Gerado por `tools/traducao/traduzir.py`. Não editar à mão.**  "
    )
    linhas.append(
        "> Rodar de novo: `py tools/traducao/traduzir.py`"
    )
    linhas.append("")
    linhas.append("## Cobertura")
    linhas.append("")
    linhas.append("| | |")
    linhas.append("|---|---|")
    linhas.append(f"| Habilidades traduzidas | **{len(habilidades)}** |")
    for tabela, quantas in sorted(por_tabela.items()):
        linhas.append(f"| ...de `{tabela}` | {quantas} |")
    linhas.append(f"| ...com pelo menos um pulso | {len(habilidades) - len(sem_pulso)} |")
    linhas.append(f"| ...com mais de um pulso | {len(com_varios)} |")
    linhas.append(f"| Pulsos gerados | {total_pulsos} |")
    linhas.append(f"| Efeitos gerados | {total_efeitos} |")
    linhas.append(f"| Itens traduzidos | **{len(itens)}** |")
    linhas.append("")

    linhas.append("### As que saíram sem pulso")
    linhas.append("")
    linhas.append(
        "Uma habilidade sem pulso não é necessariamente uma tradução falha. "
        "Separar os três casos é o que permite saber se ainda falta trabalho."
    )
    linhas.append("")
    linhas.append("| Caso | Quantas | O que é |")
    linhas.append("|---|---|---|")
    linhas.append(
        f"| Linha-modelo (`Rank 0`) | {len(modelos)} | A entrada de interface "
        "da habilidade ainda não aprendida. Não referencia impacto **por "
        "definição** — os ranques 1 a 5 é que carregam os números. |"
    )
    linhas.append(
        f"| Quebra de combo | {len(quebra_combo)} | Marcador que interrompe "
        "uma corrente de golpes. Não tem efeito porque cancelar é o efeito. |"
    )
    linhas.append(
        f"| **Sem tradução** | **{len(faltando)}** | Referencia impacto e nada "
        "saiu. São as lacunas da tabela abaixo — `Link`, `UseSkillSlot`, "
        "`ReleaseImpact` e as de modo de jogo. |"
    )
    linhas.append("")
    if faltando:
        amostra = ", ".join(str(h["source_id"]) for h in faltando[:20])
        linhas.append(f"Ids sem tradução (amostra): {amostra}")
        linhas.append("")

    linhas.append("## O que o vocabulário cobriu")
    linhas.append("")
    linhas.append("| Peça | Vezes |")
    linhas.append("|---|---|")
    for chave, quantas in r.usos.most_common():
        linhas.append(f"| `{chave}` | {quantas} |")
    linhas.append("")

    linhas.append("## Lacunas — o que o original diz e nós ainda não")
    linhas.append("")
    if not r.lacunas:
        linhas.append("Nenhuma. Toda coluna encontrada tem tradução.")
    else:
        linhas.append(
            "Cada linha é uma coluna do original que o tradutor encontrou e "
            "não soube converter. **Isto é informação sobre o sistema, não "
            "erro** — o critério para fechar uma lacuna é ela valer o sistema "
            "que exige, e várias abaixo não valem."
        )
        linhas.append("")
        linhas.append("| Lacuna | Ocorrências | Exemplo |")
        linhas.append("|---|---|---|")
        for chave, quantas in r.lacunas.most_common():
            exemplo = r.exemplos.get(chave, [""])[0]
            linhas.append(f"| {chave} | {quantas} | {exemplo} |")
    linhas.append("")

    caminho.write_text("\n".join(linhas), encoding="utf-8")


# --------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xml", type=Path, default=XML_PADRAO)
    parser.add_argument("--saida", type=Path, default=SAIDA_PADRAO)
    args = parser.parse_args()

    if not args.xml.exists():
        print(
            f"[traducao] tabelas do original não encontradas em {args.xml}\n"
            "Elas vivem FORA deste repositório de propósito — ver "
            "docs/05-extracao-dados-apk.md.",
            file=sys.stderr,
        )
        return 2

    tabelas = Tabelas(args.xml)
    relatorio = Relatorio()
    tradutor = Tradutor(tabelas, relatorio)

    habilidades = [
        tradutor.habilidade(skill)
        for skill in sorted(tabelas.skills.values(), key=lambda s: int(s["Id"]))
    ]
    itens = [
        tradutor.item(equip)
        for equip in sorted(tabelas.equipment.values(), key=lambda e: int(e["Id"]))
    ]
    ligar_receitas(itens, tabelas, relatorio)

    args.saida.mkdir(parents=True, exist_ok=True)
    _escrever_json(args.saida / "habilidades.json", {
        "fonte": "Royal Crown 13.0.13 (referência de design — ver docs/01)",
        "vocabulario": "docs/03-sistemas-de-jogo.md",
        "total": len(habilidades),
        "habilidades": habilidades,
    })
    _escrever_json(args.saida / "itens.json", {
        "fonte": "Royal Crown 13.0.13 (referência de design — ver docs/01)",
        "vocabulario": "docs/03-sistemas-de-jogo.md",
        "total": len(itens),
        "itens": itens,
    })
    escrever_relatorio(args.saida / "RELATORIO.md", habilidades, itens, relatorio)

    print(f"[traducao] {len(habilidades)} habilidades, {len(itens)} itens")
    print(f"[traducao] {len(relatorio.lacunas)} espécies de lacuna registradas")
    print(f"[traducao] saída em {args.saida}")
    return 0


def _escrever_json(caminho: Path, dados: dict) -> None:
    # `sort_keys` e indentação fixa para o diff ser legível: um corpus gerado
    # que muda de ordem a cada execução é impossível de revisar.
    caminho.write_text(
        json.dumps(dados, ensure_ascii=False, indent=1, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    raise SystemExit(main())
