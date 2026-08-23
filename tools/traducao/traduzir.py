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
- 1547 arquivos gerados afogariam o `git diff` de qualquer mudança futura no
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

    Só entra tabela que é REALMENTE lida. `actor_xml` já esteve aqui, indexada
    e nunca usada — código morto que dava a impressão de cobertura que não
    existia. Voltou agora que campeão e mob são traduzidos, e voltou **junto
    com o censo de colunas**: indexar sem censar é exatamente o buraco que a
    remoção tinha fechado.
    """

    def __init__(self, raiz: Path) -> None:
        self.raiz = raiz
        self.skills = self._indexar("skill_xml", "skill_2_xml", "skill_3_xml", "skill_4_xml")
        self.impacts = self._indexar("impact_xml", "impact_2_xml", "impact_3_xml", "impact_4_xml")
        self.buffs = self._indexar("buff_xml", "buff_2_xml", "buff_3_xml", "buff_4_xml")
        self.ccs = self._indexar("crowd_control_xml")
        self.equipment = self._indexar("equipment_xml")
        self.recipes = self._indexar("craft_recipe_xml")
        self.actors = self._indexar(
            "actor_xml", "actor_2_xml", "actor_3_xml", "actor_4_xml"
        )

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


def _linha_do_item(equip: dict, equip_id: str) -> str:
    linha = (equip.get("EquipLine") or "").strip()
    if not linha or linha == "0":
        return f"rc_line_{equip_id}"
    return f"rc_line_{linha}"


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
## Doze dos 13 tipos viram 9 dos nossos, e `KnockBack` não vira estado nenhum.
## O critério é COMPORTAMENTO, não tema: `HardStun` e `Freeze`
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

## Controles cujo `Duration` no original é sempre 0 — o tempo mora noutro
## lugar. São `ThrowUp` (48 linhas) e `Airborne` (10), e apenas eles: os outros
## 11 tipos trazem duração de verdade.
CONTROLE_SEM_DURACAO = {"ThrowUp", "Airborne"}

## Gravidade usada para derivar tempo de ar a partir de `MaxHeight`.
##
## Não é a gravidade do nosso jogo (que ainda não existe) nem a da Godot: é a
## constante que faz a conta de balística fechar em números plausíveis de
## arremesso. Altura 1 dá 0,90 s; altura 5 dá 2,02 s.
GRAVIDADE_DO_ARREMESSO = 9.8

## Tempo de ar quando nem `MaxHeight` existe — 38 das 58 linhas de arremesso,
## que guardam a trajetória numa curva (`YMoveCurvePath`) que não está no XML.
##
## É a mediana dos 20 casos deriváveis. Inventado, e contado como tal.
TEMPO_DE_AR_PADRAO = 0.9

## `TriggerTiming` de `impact_xml` -> evento do nosso `TriggerSet`.
##
## Só entram os que a camada `core/` sabe emitir sozinha. `Start` é ausência de
## gatilho: o impacto sai junto com a habilidade.
GATILHO = {
    "MaxStack": "MARK_MAXED",
    "DoAttackDamage": "BASIC_ATTACK_HIT",
    "DoSkillDamage": "ABILITY_HIT",
    "DoSkillDamageOnce": "ABILITY_HIT",
    "OnHitDamage": "DAMAGE_TAKEN",
    "Expire": "EXPIRED",
    "ActivateActiveSkill": "ABILITY_CAST",
}

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
        ## Colunas presentes no XML que ninguém consulta nem declara ignorar.
        ## `{tabela: {coluna: quantas linhas a têm}}`
        self.nao_consultadas: dict[str, collections.Counter] = {}
        ## Toda coluna vista no XML, para achar declaração que nunca dispara.
        self.colunas_vistas: set[str] = set()
        ## Chaves de `UI_Params` que ninguém lê nem declara ignorar.
        self.chaves_orfas: collections.Counter = collections.Counter()

    def usou(self, chave: str) -> None:
        self.usos[chave] += 1

    def lacuna(self, chave: str, onde: str = "") -> None:
        self.lacunas[chave] += 1
        if onde and len(self.exemplos[chave]) < 5:
            self.exemplos[chave].append(onde)

    def censo(self, tabelas: Tabelas) -> None:
        """Varre as colunas do XML e acha as que ninguém olhou.

        Existe porque `lacuna()` só registra o que o tradutor **tentou**
        mapear. Uma coluna que o código nunca menciona não gera lacuna
        nenhuma — ela some, e a ausência é indistinguível de uma decisão.
        Este censo transforma "não sei o que estou perdendo" em uma lista.
        """
        fontes = {
            "skill": tabelas.skills,
            "impact": tabelas.impacts,
            "buff": tabelas.buffs,
            "crowd_control": tabelas.ccs,
            "equipment": tabelas.equipment,
            "craft_recipe": tabelas.recipes,
            "actor": tabelas.actors,
        }
        for nome, tabela in fontes.items():
            presentes: collections.Counter = collections.Counter()
            for registro in tabela.values():
                for coluna in registro:
                    presentes[coluna] += 1
            sobrando = collections.Counter()
            for coluna, quantas in presentes.items():
                if coluna in CONSULTADAS.get(nome, set()):
                    continue
                if coluna in IGNORADAS:
                    continue
                if coluna in ORFAS_QUE_SAO_LACUNA:
                    # Vira lacuna nomeada, com a contagem real de linhas.
                    self.lacunas[
                        f"{ORFAS_QUE_SAO_LACUNA[coluna]} (`{coluna}` em {nome})"
                    ] += quantas
                    continue
                sobrando[coluna] = quantas
            self.nao_consultadas[nome] = sobrando
            self.colunas_vistas |= set(presentes)

        # `UI_Params` é UMA coluna com várias chaves dentro. O censo de colunas
        # a dá por consultada e não vê o que há lá — foi assim que
        # `CastDirection_Count` (leque de projéteis) ficou dois commits sem
        # tradução. Chave também é dado, e também precisa de censo.
        chaves: collections.Counter = collections.Counter()
        for registro in tabelas.skills.values():
            for parte in (registro.get("UI_Params") or "").split(","):
                if "=" in parte:
                    chaves[parte.split("=")[0].strip()] += 1
        self.chaves_orfas = collections.Counter({
            k: n for k, n in chaves.items() if k not in CHAVES_DE_UI
        })


## Chaves de `UI_Params` que o tradutor lê ou declara ignorar, com o motivo.
##
## Existe porque `UI_Params` é uma coluna só, com pares `chave=valor` dentro.
## O censo de colunas a marca como consultada e fica cego para o conteúdo —
## e foi exatamente aí que o leque de projéteis se escondeu.
CHAVES_DE_UI = {
    "CastDirection_Width": "lido: largura da linha",
    "CastDirection_Count": "lido: quantos projéteis no leque",
    "CastDirection_Angle": "lido: abertura do leque",
    "CircularSector_Angle": "lido: abertura do cone",
    "CastTrapezoid_Start_Width": "lido",
    "CastTrapezoid_End_Width": "lido",
    "CastTrapezoid_Start_Distance": "lido",
    "CastTrapezoid_End_Distance": "lido",
    # `CastArea_Bound` é o retículo de mira. Medido: 258 habilidades o
    # declaram, com 15 valores distintos entre 0,5 e 6 — a primeira versão
    # deste comentário dizia "2 em todas as 186", e estava errada nos dois
    # números.
    #
    # Quando o impacto declara `Radius`, é ele que acerta. Quando NÃO declara —
    # 139 dos 410 impactos dessas habilidades —, o retículo passa a ser a
    # melhor estimativa disponível, e é lido. Sem isso a habilidade de área
    # virava alvo único.
    "CastArea_Bound": "retículo de mira; lido como raio quando o impacto não "
                      "declara o dele",
}

## Colunas que o tradutor CONSULTA, por tabela. Mantida à mão e conferida pelo
## censo: se uma coluna sai do código e fica aqui, o censo não acusa nada — mas
## se uma coluna nova aparece no XML e não está nem aqui nem em
## `IGNORADAS`, o relatório grita.
CONSULTADAS = {
    "skill": {
        "Id", "SkillGroupID", "Rank", "LevelRequirement", "CoolTime", "CostValue",
        "UI_Type", "UI_Params", "AI_SkillRange", "MovingOnSkill",
        "SkillCancelableTime", "AtlasName", "ButtonIconPath", "CastingTime",
        "RemoveCC", "RemoveDebuff", "UseChainBreak", "UltimateCharge",
        "ResetAttackCoolTime",
        "__tabela",
    } | {f"Impact{n}" for n in range(1, 13)}
      | {f"StatType{n}" for n in range(1, 5)}
      | {f"StatValue{n}" for n in range(1, 5)},
    "impact": {
        "Id", "TriggerTiming", "TargetType", "StartPosition", "StartTime",
        "ColliderActiveDelay", "ActiveDuration", "Radius", "LoopInterval",
        "ImpactCount", "ProjectileEffectId", "MoveDistance", "MoveSpeedZ",
        "SummonActorId", "SummonPersistTime", "DrainFactor",
        "IgnoreInvincibility", "StartPositionX", "StartPositionZ", "Angle",
        "__tabela",
    } | {f"StatType{n}" for n in range(1, 5)}
      | {f"StatValue{n}" for n in range(1, 5)}
      | {f"ImpactStatType{n}" for n in range(1, 9)}
      | {f"ImpactStatValue{n}" for n in range(1, 9)}
      | {f"ImpactStatTargetType{n}" for n in range(1, 9)},
    "buff": {
        "Id", "Duration", "MaxStackCount", "Line", "AdjustCDSkillIds",
        "AdjustCDTime", "BuffReleaseCondition", "AffectType", "IsInvincibility",
        "DamageImmunity", "Impact1", "Impact2", "__tabela",
    } | {f"StatType{n}" for n in range(1, 5)}
      | {f"StatValue{n}" for n in range(1, 5)},
    "crowd_control": {
        "Id", "Type", "Duration", "Distance", "Direction", "ApplyToughness",
        "Impact1", "__tabela",
    } | {f"StatType_{n}" for n in range(1, 5)}
      | {f"StatValue_{n}" for n in range(1, 5)},
    "equipment": {
        "Id", "Type", "Rarity", "MaxStackCount", "EquipLine", "Socket",
        "UsableItemCount", "PassiveBuffs", "SkillId", "RecoverDataType",
        "IconPath", "Enable", "__tabela",
    } | {f"StatType_{n}" for n in range(1, 9)}
      | {f"StatValue_{n}" for n in range(1, 9)},
    "craft_recipe": {
        "Id", "ResultId", "__tabela",
    } | {f"RawMaterialId_{n}" for n in range(1, 9)}
      | {f"RawMaterialCount_{n}" for n in range(1, 9)},
    # `actor` é a tabela de QUEM: campeão, mob, bot, torre, baú. É ela que
    # responde "quem tem quais habilidades", que nenhuma das outras responde.
    "actor": {
        "Id", "Enable", "UsageType", "LootPreset", "Level", "Rarity",
        "AIPath", "AbleCombat", "EnableDamage", "EnableTarget",
        "ControllerRadius", "ControllerHeight",
        "InfoPosition", "InfoDamageType", "SummonActorMaxCount",
        "LevelUpUltimateCharge", "PassiveBuffs", "UltimateSkill",
        "ActivationSkillId", "SlainSkillId", "CombatStartSkill",
        "ReturnFinishSkill", "__tabela",
    } | {f"DefaultSkillId_{n}" for n in range(1, 5)}
      | {f"StatType_{n}" for n in range(1, 14)}
      | {f"StatValue_{n}" for n in range(1, 14)}
      | {f"LevelUpStatType_{n}" for n in range(1, 8)}
      | {f"LevelUpStatValue_{n}" for n in range(1, 8)},
}

## Colunas que o tradutor NÃO lê **de propósito**, com o motivo. Estar aqui é
## uma decisão registrada; não estar em lugar nenhum é perda silenciosa.
IGNORADAS = {
    # --- `actor`: apresentação e física do motor original ----------------
    # A tabela de atores é 90% aparência. O que dela vira jogo — atributos,
    # kit, natureza — está em `CONSULTADAS["actor"]`; o que é sistema que não
    # temos está em `ORFAS_QUE_SAO_LACUNA`. O resto é isto.
    "DefaultActorResourceId": "malha e animações do ator",
    "DefaultWeaponSkinId": "modelo da arma", "Skins": "skins",
    "ViewStateType": "que barra de vida a interface desenha",
    "ShowMiniMap": "interface", "ShowWorldMap": "interface",
    "ShowDamageText": "interface", "ShowName": "interface",
    "NameHeight": "interface", "HideHPBar": "interface",
    "HpBarType": "interface", "ShowGuidebook": "interface",
    "GuidebookGroupActorId": "interface", "GuidebookOrder": "interface",
    "ShowOnCollection": "interface (galeria de campeões)",
    "InteractionAnimation": "animação", "InteractionSound": "som",
    "UseDieAnimation": "animação", "LookAtTargetOnDie": "animação",
    "UseWorldOrientationOnDie": "animação",
    "DestroyDelayTime": "quanto o cadáver fica na tela",
    "FollowSpawnerDirection": "orientação inicial do modelo",
    "PositionY": "altura do modelo", "SyncVisibilityWithParent": "render",
    # As sete barrinhas da tela de seleção de campeão — "Ataque 2, Defesa 3".
    # São editoriais, não derivadas dos atributos, e não alimentam nada.
    "InfoAttackType": "barra da tela de seleção",
    "InfoDifficulty": "barra da tela de seleção",
    "InfoAttack": "barra da tela de seleção",
    "InfoDefense": "barra da tela de seleção",
    "InfoMobility": "barra da tela de seleção",
    "InfoCrowdControl": "barra da tela de seleção",
    "InfoSupport": "barra da tela de seleção",
    "InfoSubPosition": "barra da tela de seleção",
    "Mode": "vale 0 em todas as 88 linhas que a declaram",
    "PickingRadius": "raio do clique do mouse sobre o ator",
    "PickingHeight": "altura do clique do mouse sobre o ator",
    "ImpactTargetLayer": "camada de física do motor original",
    "IgnoreCollision": "camada de física do motor original",

    # --- apresentação: som, animação, efeito visual, ícone --------------
    "Sound": "som", "SoundOnHit1": "som", "SoundOnHit2": "som",
    "Animation": "animação", "UseLoopAni": "animação",
    "SkillSpeed": "animação",
    # Medido, não presumido: `Duration` é MAIOR que o `StartTime` do último
    # impacto em 892 das 966 habilidades comparáveis, igual em 71 e menor em 3.
    # É comprimento de clipe de animação, não canalização — canalização seria
    # `CastingTime`, que é coluna própria e agora é lida.
    "Duration": "comprimento do clipe de animação (medido: maior que o último "
                "impacto em 892 de 966 habilidades)",
    "UseEquipModel": "modelo", "HideAttachmentSlots": "modelo",
    "ShowAttachmentSlots": "modelo", "UsePolymorphSkin": "modelo",
    "PolymorphActorId": "modelo",
    "AtlasName": "ícone", "IconAtlasName": "ícone", "IconPath": "ícone",
    "ShowIcon": "ícone", "EffectTexturePath": "efeito visual",
    "HitEffectId1": "efeito visual", "HitEffectId2": "efeito visual",
    "EffectOnDestroy": "efeito visual", "Release_Effects_Id1": "efeito visual",
    "UseHitRim": "efeito visual", "HitCamera": "câmera",
    "UseFakeBeaten": "reação visual", "HitOrientation1": "reação visual",
    "HitTarget1": "reação visual", "HitTarget2": "reação visual",
    "TargetDummy": "reação visual", "ColliderPath": "colisor de cena",
    "InheritanceParentScale": "escala visual",
    "StartScaleX": "escala visual", "EndScaleX": "escala visual",
    "StartScaleZ": "escala visual", "EndScaleZ": "escala visual",
    "FollowDirection": "orientação visual",
    "Desc": "texto localizado", "DescParam": "texto localizado",
    "Name": "texto localizado",
    "ConditionMessageID": "texto localizado",
    "Mobile_UI_Type": "interface de celular",
    "UI_BoundHUDRadius": "interface", "IsHiding": "interface",
    # --- economia e progressão fora de partida --------------------------
    "LootPriority": "tabela de loot",
    "DropTableExtraCondition": "tabela de loot", "DropCount": "tabela de loot",
    "UseDropAssetData": "tabela de loot", "Consume": "regra de consumo",
    "AcquisitionActorIDs": "onde se acha", "EtcAcquisitionActorIDs": "onde se acha",
    "HuntAcquisitionActorIDs": "onde se acha",
    "AcquisitionMapiconIDs": "onde se acha",
    "ValidVersionData": "versionamento", "Enable": "liga/desliga do original",
    "Order": "ordenação de tabela", "Tier": "ordenação de tabela",
    # --- infraestrutura do motor do original ----------------------------
    "CoolTimeLine": "agrupamento de recarga do original",
    "ComboLine": "agrupamento de combo do original",
    "IsSeedSkill": "marcador interno",     # Em `equipment` é encaixe de gema e é lido. Em `skill` é outra coisa com
    # o mesmo nome, e vale `1` nas 844 linhas — constante, portanto sem
    # informação.
    "Socket": "em equipment é encaixe e é lido; em skill é homônimo com valor "
              "constante 1 nas 844 linhas",
    "PersistRankOnCC": "marcador interno", "PersistStartTime": "marcador interno",
    "PersistEndTime": "marcador interno", "Persistence": "marcador interno",
    "SummonProperPosition": "ajuste de posição da invocação",
    "ForceUltimateCharge": "força a suprema a encher de uma vez; o que temos é o ganho por conjuração, e forçar seria efeito de item",
    "UltimateCharge": "carga de suprema (lacuna registrada)",
    "ApplyOnKnockOut": "regra de nocaute", "ReleaseOnKnockout": "regra de nocaute",
    "ReleaseOnDie": "regra de morte", 
    
    "AttackCancelableTime": "janela de cancelamento (lacuna registrada)",
    "MoveCancelableTime": "janela de cancelamento (lacuna registrada)",
    "TrackCancelableTime": "janela de cancelamento (lacuna registrada)",
    "CancelForbidStartTime": "janela de cancelamento (lacuna registrada)",
    "CancelForbidEndTime": "janela de cancelamento (lacuna registrada)",
    "ComboSkillInfo_SkillID": "corrente de combo (lacuna registrada)",
    "ComboSkillInfo_StartTime": "corrente de combo (lacuna registrada)",
    "ComboSkillInfo_LimitTime": "corrente de combo (lacuna registrada)",
    "ZMoveCurvePath": "curva de deslocamento (lacuna registrada)",
    "YMoveCurvePath": "curva de deslocamento (lacuna registrada)",
    "MoveCurvePath": "curva de deslocamento (lacuna registrada)",
    "ParabolaCurvePath": "curva de deslocamento (lacuna registrada)",
    "TransverseParabolaCurvePath": "curva de deslocamento (lacuna registrada)",
    "AdjustCDSkillIds": "lido em buff", "AdjustCDTime": "lido em buff",
    "ApplyCDReductionRatio": "recarga do próprio buff — sem consumidor ainda",
    "StackType": "acúmulo entre linhas de buff — sem consumidor ainda",
    "ChangeMode": "postura — vira marca",
    "BuffType": "rótulo de buff/debuff, sem efeito mecânico",
    "AlwaysMaintain": "persistência entre partidas",
    "AimDuration": "tempo de mira, ligado à interface",
    "FixedDirection": "trava de direção durante a animação",
    "LookAtTargetDirection": "trava de direção durante a animação",
    
    
    "SkillType": "rótulo Moving/Haste do original",
    
    "IgnoreEnableSkillOnCC": "exceção de controle",
    "IgnoreMiss": "acerto garantido — sem consumidor ainda",
    "ArriveTime": "tempo de voo, aproximado por MoveSpeedZ",
    "StartPositionY": "altura, ignorada como o resto da altura",
    "MaxHeight": "altura do arremesso, visual",
    "MoveSpeed": "velocidade do arremesso, visual",
        # NÃO é redundante com `StartPosition`: `crowd_control_xml` não tem essa
    # coluna. Diz de onde o empurrão irradia — do ponto de impacto (157) ou do
    # conjurador (113). Nós sempre empurramos para longe do conjurador, o que é
    # simplificação, e está registrado como assunção em docs/10.
    "SourceType": "de onde o empurrão irradia; simplificamos sempre para longe "
                  "do conjurador — assunção registrada em docs/10",
    
    "SkillCancelableTime": "lido em skill",
    # --- receita de fabricação -----------------------------------------
    # Conferidas inertes no dado real, não presumidas: `CraftTime` é 0 nas 383
    # linhas, `SuccessRate` só existe nas 84 sem material (as não-fabricáveis)
    # e `ResultItemCount` é 1 nas 299 reais.
    "CraftTime": "0 em todas as 383 linhas",
    "SuccessRate": "só nas 84 linhas sem material, que são as não-fabricáveis",
    "ResultItemCount": "1 nas 299 receitas reais",
    "RecipeType": "valor único `Normal`",
    "Category": "`Equipment` ou `NonCraftable`; a segunda já se identifica por "
                "não ter material nenhum",
    "DisableGameModes": "modo de jogo (fora do escopo)",
    # --- fechadas depois do primeiro censo -----------------------------
    # Cada uma abaixo apareceu como órfã na primeira varredura. Estar aqui é
    # uma decisão registrada; não estar em lugar nenhum era perda silenciosa.
    "ActivationType": "quando a recarga começa no original (OnStart / "
                      "OnFirstImpact / OnLastImpact). Nós começamos sempre ao "
                      "conjurar — decisão da Fase 3.2, e mudá-la por "
                      "habilidade daria dois comportamentos para a mesma coisa",
    "CostType": "sempre `ManaCost` nas 684 ocorrências; o valor é lido",
    "CostReq": "requisito de custo do original, sem equivalente",
    "TargetType": "em skill é redundante: quem resolve quem é atingido é o "
                  "`TargetType` de cada impacto, que é lido",
    "UsableDataType": "redundante com `SkillId` e `RecoverDataType`, os dois lidos",
    "Effects_Id1": "efeito visual", "Effects_Id2": "efeito visual",
    "Effects_Id3": "efeito visual", "Effects_Id4": "efeito visual",
    "Effects_Id5": "efeito visual", "Effects_Id6": "efeito visual",
    "Effects_Id7": "efeito visual",
    "SoundDelay": "som", "SoundOnDestroy": "som",
    "EndPosition": "destino do projétil; aproximado por `MoveDistance`, que é lido",
    "ImpactType": "taxonomia de colisor do motor do original",
    "UseCollider": "taxonomia de colisor do motor do original",
    "TriggingRatio": "limiar interno do original: 9999 em 126 casos e 1 em 9. "
                     "Não é chance percentual, e não há leitura que faça sentido",
    "AccFactor": "fator de acúmulo de carga de suprema — cai na lacuna de "
                 "`UltimateCharge`, registrada",
    "Rank": "em buff é o degrau dentro da `Line`; a linha vira marca e o "
            "acúmulo dela cobre o degrau",
    "PersistRank": "marcador interno do original",
    "ZActionCurvePath": "curva de deslocamento (lacuna registrada)",
    "MoveCancelableEndTime": "janela de cancelamento (lacuna registrada)",
    "Overlap": "corrente de combo (lacuna registrada)",
    "ChainType": "corrente de combo (lacuna registrada)",
    "ChainCondition": "corrente de combo (lacuna registrada)",
    "IgnoreActivateTrigger": "corrente de combo (lacuna registrada)",
    
    
    "MoveType": "rótulo de tipo de movimento do original",
    "EnableSkillOnVehicle": "veículo (lacuna registrada)",
}

## Colunas órfãs que viram LACUNA em vez de decisão: o original tem um sistema
## ali e nós não. Diferente de `IGNORADAS`, que são coisas que decidimos não
## precisar. `{coluna: descrição}`.
ORFAS_QUE_SAO_LACUNA = {
    # As nove abaixo já estiveram em `IGNORADAS`, filadas como decisão. Uma
    # revalidação apontou que são sistemas de verdade escondidos atrás de um
    # rótulo curto — "cadência de ataque" para o reset de auto-ataque, que é
    # mecânica central de MOBA; "condição de parada do dash" para a investida
    # que trava ao acertar. Rótulo curto não é justificativa; virou lacuna.
    "StopCondition": "a investida que PARA ao acertar (OnImpactEnemy / "
                     "OnDamage / OnLostTarget) — nosso dash sempre completa",
    "ReleaseAutoAttack": "habilidade que dispara um ataque básico ao terminar",
    "TrackingMode": "projétil teleguiado",
    "TrackDistanceForMovingSkill": "dash que persegue o alvo",
    "TrackPersistTime": "por quanto tempo o dash persegue",
    "FollowTarget": "área que acompanha o alvo em vez de ficar no chão",
    "BeAbleToAttackBush": "arbusto que se pode atacar (não há arbusto)",
    "LimitSourceDistance": "o gancho que arrebenta quando estica demais",
    "ThroughObstacle": "atravessar parede (não há sistema de obstáculo em core/)",
    "EnableSkillOnCC": "conjurar mesmo sob controle",
    "TargetCondition": "ricochete para outro inimigo",
    "TargetRange": "alcance do ricochete",

    # --- de `actor`: sistemas inteiros que o original tem e nós não ------
    "ImpactRadius": "hitbox do alvo — nossas formas medem ponto a ponto, "
                    "então acertar um dragão é tão difícil quanto acertar um "
                    "campeão",
    "ImpactHeight": "altura da hitbox do alvo",
    "VisibilityInFow": "névoa de guerra",
    "VisibilityInBush": "arbusto que esconde",
    "VisionBlockage": "obstáculo que bloqueia visão",
    "HasBushRole": "o ator É um arbusto",
    "HasDetectingRole": "quem enxerga o que está escondido",
    "HasInteractionRole": "sistema de interação (baú, forja, vendedor)",
    "InteractionType": "que interação o ator oferece",
    "InteractionTime": "quanto tempo a interação leva",
    "InteractionRadius": "de quão perto dá para interagir",
    "InteractionSubject": "quem pode interagir",
    "MultiInteraction": "vários interagindo ao mesmo tempo",
    "UseInteractionDirectLoot": "loot que cai direto no inventário",
    "InteractionStartBuffId": "buff enquanto a interação corre",
    "InteractionEndBuffId": "buff ao terminar a interação",
    "InteractionEndSkillId": "habilidade ao terminar a interação",
    "HasForgeRole": "forja (crafting no mapa)",
    "HasSupplyRole": "caixa de suprimento",
    "HasVendorRole": "vendedor",
    "BuyGoldCost": "preço em ouro",
    "PackageItemActorID": "pacote de itens que o ator entrega",
    "DropItemRate": "tabela de loot: chance de dropar",
    "DropItemTableIDs": "tabela de loot: o que dropa",
    "DropGroupId": "tabela de loot: grupo de drop",
    "UseSummonerStat": "invocação que herda os atributos do invocador",
    "UseSummonerDamageTrigger": "invocação que dispara os gatilhos do dono",
    "DieWithSummoner": "invocação que morre junto com o dono",
    "FamiliarId": "familiar que acompanha o campeão",
    "FamiliarPosition": "onde o familiar fica",
    "Bulletproof": "imune a projétil",
}

## `UsageType` do original -> `Unit.Nature`.
##
## Não é decoração: `Unit.Nature` decide teto de dano contra mob, filtro de
## `SiegeDamage` e se a morte conta como abate. Errar aqui faz um baú valer
## uma eliminação.
NATUREZA = {
    "Player": "CHAMPION",
    # Bot é campeão: mesmo kit, mesmos atributos, e morrer para um bot tem que
    # contar igual. O que muda é quem dá as ordens, e isso não mora aqui.
    "AIPlayer": "CHAMPION",
    "Monster": "MONSTER",
    # Lacaio de torre e familiar existem enquanto quem os criou existir.
    "Minion": "SUMMON",
    "Familiar": "SUMMON",
    # Baú, árvore, veio de minério, porta. `STRUCTURE` no nosso vocabulário.
    "ActorObject": "STRUCTURE",
}

## `InfoPosition` -> papel. Puramente informativo: nada no motor lê isto.
## Existe para dar para listar "os tanques" sem reabrir o XML.
PAPEL = {
    "Fighter": "FIGHTER",
    "ADCarry": "MARKSMAN",
    "Assassin": "ASSASSIN",
    "Support": "SUPPORT",
    "AP": "MAGE",
    "Tanker": "TANK",
}

## Recarga para a suprema que não tem NEM carga NEM recarga no original.
##
## Nasceu valendo para todas, quando a carga de suprema era lacuna. Hoje a
## carga existe (decisão 17) e cobre os 31 campeões que declaram
## `LevelUpUltimateCharge`; isto sobrou para o caso degenerado — suprema com
## `CoolTime = 0` e sem carga, que sairia a cada quadro. Hoje vale para 1 ator
## só, contra os 31 de antes.
##
## O número continua INVENTADO e registrado como tal no relatório.
RECARGA_DE_SUPREMA_SEM_CARGA = 45.0

## Velocidade de um projétil cujo `MoveSpeedZ` o original não declara, ou
## declara zero. **Inventado**, e registrado como tal no relatório.
##
## Não há valor neutro possível aqui: zero não é "devagar", é "nunca chega".
## 15 m/s é a mediana grosseira dos que declaram.
VELOCIDADE_DE_PROJETIL_PADRAO = 15.0


def apelidos_de_ator(registros: list[dict[str, str]]) -> dict[str, str]:
    """Id do ator -> identificador ASCII estável e único.

    `LootPreset` é o nome do personagem escrito em INGLÊS (`Leo`, `Violet`) —
    identificador, não texto localizado, e portanto entra pela mesma regra que
    deixou `AtlasName` entrar nas habilidades. O `Name` da tabela é coreano e
    é conteúdo do original: fica de fora (`docs/01-visao-e-escopo.md`).

    O apelido **não é único no dado**: `Leo` aparece em dois atores e `Bella`
    em três — variantes de tutorial que repetem o kit. Quem chega primeiro em
    ordem de Id fica com o nome limpo; os outros carregam o Id atrás. Sem isso
    um campeão sobrescreveria o outro no catálogo, em silêncio.
    """
    por_slug: dict[str, list[str]] = collections.defaultdict(list)
    for registro in sorted(registros, key=lambda r: int(r["Id"])):
        por_slug[_slug(registro.get("LootPreset", ""))].append(registro["Id"])

    apelidos: dict[str, str] = {}
    for base, ids in por_slug.items():
        for posicao, ator_id in enumerate(ids):
            if not base:
                apelidos[ator_id] = f"rc_actor_{ator_id}"
            elif posicao == 0:
                apelidos[ator_id] = base
            else:
                apelidos[ator_id] = f"{base}_{ator_id}"
    return apelidos


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
                # `ApplyToughness` responde DIRETO se a tenacidade se aplica.
                # Antes isto era inferido por `CONTROLE_DURO`, e a inferência
                # discordava do dado em quatro entradas. Palpite perde para
                # coluna quando a coluna existe.
                aplica = cc.get("ApplyToughness")
                if aplica is not None:
                    duro = aplica.strip().lower() != "true"
                else:
                    duro = tipo in CONTROLE_DURO
                    self.r.usou("tenacidade inferida (sem ApplyToughness)")
                duracao = self._duracao_do_controle(cc, tipo, onde)
                efeito = {
                    "type": "crowd_control",
                    "recipient": alvo,
                    "control": nosso,
                    "duration": duracao,
                    "ignores_tenacity": duro,
                    "source_tag": f"rc_cc_{cc_id}",
                }
                if duracao <= 0.0:
                    # Controle com duração zero é descartado pelo `StatusSet`.
                    # Emiti-lo seria anunciar cobertura que não existe — foi
                    # exatamente o que aconteceu com o arremesso.
                    self.r.lacuna(
                        f"controle {tipo} sem duração aproveitável", onde
                    )
                    efeitos.pop()
                elif nosso == "SLOW":
                    # A intensidade da lentidão está em `StatType_1/StatValue_1`,
                    # não em `Duration`. Sem isso toda lentidão sairia com o
                    # nosso padrão de 30%, e o balanceamento do original se
                    # perderia justamente no controle mais comum dele.
                    efeito["slow_amount"] = self._intensidade_lentidao(cc, onde)
                efeitos.append(efeito)

        empurrao = self._empurrao(cc, alvo, onde)
        if empurrao:
            efeitos.append(empurrao)

        # O controle pode carregar um impacto próprio — 7 entradas fazem isso.
        # Sem ler, o dano da parede que arremessa some junto com a parede.
        impacto_do_cc = cc.get("Impact1")
        if impacto_do_cc:
            internos = self._efeitos_de_impacto(impacto_do_cc, onde)
            if internos:
                self.r.usou("impacto dentro de controle")
                efeitos.extend(internos)

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

    ## Duração do controle, com o arremesso tratado à parte.
    ##
    ## `ThrowUp` e `Airborne` têm `Duration = 0` nas 58 linhas do original: o
    ## tempo de ar não mora ali, mora na altura e na curva de subida. Copiar o
    ## zero literalmente produzia 121 efeitos que o motor descarta — todo
    ## arremesso do jogo era inerte, e o relatório contava isso como cobertura.
    ##
    ## Onde há `MaxHeight`, o tempo sai da balística: subir e cair de uma
    ## altura h leva `2·sqrt(2h/g)`. Onde não há, entra um padrão declarado, e
    ## ele é contado como número inventado.
    def _duracao_do_controle(
        self, cc: dict[str, str], tipo: str, onde: str
    ) -> float:
        declarada = num(cc.get("Duration"))
        if tipo not in CONTROLE_SEM_DURACAO:
            return declarada
        if declarada > 0.0:
            return declarada

        altura = num(cc.get("MaxHeight"))
        if altura > 0.0:
            self.r.usou("tempo de ar derivado da altura")
            return round(
                2.0 * (2.0 * altura / GRAVIDADE_DO_ARREMESSO) ** 0.5, 2
            )

        self.r.lacuna(
            "tempo de ar do arremesso (o original guarda a subida numa curva "
            "fora do XML; usamos %.1fs)" % TEMPO_DE_AR_PADRAO,
            onde,
        )
        return TEMPO_DE_AR_PADRAO

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

        # Buff que carrega impacto é uma de TRÊS coisas, e `TriggerTiming` diz
        # qual. Tratar as três como periódico — que era o que se fazia — dava
        # veneno a coisas que na verdade esperam um evento.
        for indice in (1, 2):
            impact_id = registro.get(f"Impact{indice}")
            if not impact_id:
                continue
            internos = self._efeitos_de_impacto(impact_id, onde, visitados)
            if not internos:
                continue
            impacto = self.t.impacts.get(impact_id, {})
            laco = num(impacto.get("LoopInterval"), 0.0)
            evento = self._evento_de(impacto, onde)

            if evento is not None:
                self.r.usou(f"gatilho {evento}")
                efeitos.append({
                    "type": "trigger",
                    "recipient": alvo,
                    "event": evento,
                    "charges": 0,
                    "duration": duracao,
                    "source_tag": tag,
                    "effects": internos,
                    "on_expire": [],
                })
            elif laco > 0.0:
                self.r.usou("periodic")
                efeitos.append({
                    "type": "periodic",
                    "recipient": alvo,
                    "interval": laco,
                    "duration": duracao,
                    "ticks_on_apply": False,
                    "refreshes": True,
                    "source_tag": tag,
                    "effects": internos,
                })
            else:
                # Sem laço e sem gatilho: o impacto sai uma vez, quando o buff
                # é aplicado. Envolvê-lo num periódico faria bater repetido.
                self.r.usou("impacto de buff, imediato")
                efeitos.extend(internos)

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
        # consulta a marca em outro lugar. 114 buffs caem aqui — 62 deles têm
        # literalmente só `Line`, `Rank` e `Duration` —, e
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

    ## `TriggerTiming` -> evento, ou `None` quando é `Start` (sem gatilho).
    ## Timing que existe e não temos vira lacuna, não silêncio.
    def _evento_de(self, impacto: dict, onde: str) -> str | None:
        bruto = impacto.get("TriggerTiming", "Start")
        for parte in [t.strip() for t in bruto.split(",") if t.strip()]:
            if parte == "Start":
                continue
            if parte in GATILHO:
                return GATILHO[parte]
            self.r.lacuna(f"TriggerTiming={parte}", onde)
        return None

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
        self,
        impacto: dict[str, str],
        onde: str,
        visitados: frozenset,
        encadeados: list | None = None,
    ) -> list[dict]:
        """Traduz as colunas `ImpactStat*` de um impacto.

        `encadeados`, quando dado, RECOLHE os ids de `ImpactStatType: Impact`
        em vez de fundir os efeitos deles aqui. É a diferença entre "o golpe
        seguinte vira um pulso com o tempo e o raio dele" e "os efeitos dos
        dois viram um só" — e fundir está errado pelo mesmo motivo que o doc
        da tradução dá para não fundir impactos irmãos.

        Sem `encadeados` (contexto de buff, onde não há forma a resolver), o
        comportamento antigo continua: funde, porque não existe pulso onde
        pendurar o filho.
        """
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
                if parte == "Impact" and encadeados is not None:
                    # Recolhe para virar pulso próprio lá em cima.
                    filho, _ = id_e_pilha(bruto)
                    if filho and filho not in encadeados:
                        encadeados.append(filho)
                    self.r.usou("impacto encadeado como pulso")
                    continue
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

        self._modificadores_do_impacto(impacto, onde)

        # `DrainFactor` e `IgnoreInvincibility` são do IMPACTO, não da coluna
        # de stat: valem para todo dano que ele causar. Aplicados aqui, uma vez,
        # em vez de repetidos em cada `case` do dano.
        dreno = impacto.get("DrainFactor")
        fura = booleano(impacto.get("IgnoreInvincibility"))
        if dreno is not None or fura:
            for bloco in dano.values():
                if dreno is not None:
                    bloco["drain_factor"] = num(dreno, 1.0)
                bloco["pierces_invulnerability"] = fura
            if dreno is not None:
                self.r.usou("drain_factor")
            if fura:
                self.r.usou("fura invulnerabilidade")

        # Ordem: dano e cura primeiro, depois controle e buff. É a ordem em que
        # o jogador percebe, e importa de verdade num caso — executar antes de
        # atordoar torna o atordoamento irrelevante.
        return list(dano.values()) + list(cura.values()) + efeitos

    ## `StatType1..4` do IMPACTO: modificadores que valem só para aquele golpe.
    ##
    ## Dois deles não são lacuna nenhuma — são as nossas próprias convenções,
    ## escritas por eles. `Accuracy: 1` diz "este golpe sempre acerta", que é o
    ## que `Damage.resolve` já faz com habilidade. `CriticalRatio: -9999` diz
    ## "este golpe não critica", que é a decisão 8 palavra por palavra.
    ##
    ## Achar isso foi a melhor confirmação de que as convenções fechadas na
    ## Fase 2.2 sem consultar o original bateram com ele.
    def _modificadores_do_impacto(self, impacto: dict, onde: str) -> None:
        for indice in range(1, 5):
            nome = impacto.get(f"StatType{indice}")
            if not nome:
                continue
            valor = num(impacto.get(f"StatValue{indice}"))
            if nome == "Accuracy":
                self.r.usou("acerto garantido (já é a nossa convenção)")
            elif nome == "CriticalRatio" and valor < 0:
                self.r.usou("habilidade não critica (já é a nossa convenção)")
            else:
                self.r.lacuna(
                    f"modificador só deste golpe: {nome} "
                    "(temos modificador por personagem, não por golpe)", onde
                )

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
                    "drain_factor": 1.0,
                    "pierces_invulnerability": False,
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

    def pulsos(
        self,
        impact_id: str,
        skill: dict[str, str],
        onde: str,
        visitados: frozenset = frozenset(),
        atraso_herdado: float = 0.0,
        ancora_pai: str | None = None,
        emitidos: set | None = None,
    ) -> list[dict]:
        """Um impacto e seus encadeados, cada um como pulso próprio.

        O impacto filho de `ImpactStatType: Impact` tem `StartTime`, `Radius` e
        `StartPosition` PRÓPRIOS — 300 das 320 referências encadeadas diferem
        do pai em pelo menos um dos três. Fundir os efeitos dele no pai
        descartaria essa geometria, que é exatamente o erro que a estrutura de
        pulsos existe para não cometer.

        O atraso do filho acumula o do pai: ele nasce quando o pai sai.
        `ParentImpactPosition` vira `Origin.PREVIOUS`, que é o pulso do pai —
        e quando o pai não gerou pulso (só encadeava), o filho herda a âncora
        que o pai teria tido.
        """
        marca = f"i{impact_id}"
        if marca in visitados:
            return []
        visitados = visitados | {marca}

        # `emitidos` atravessa toda a habilidade; `visitados` só a cadeia atual.
        # Os dois existem porque protegem de coisas diferentes: um de repetir o
        # mesmo golpe, o outro de laço infinito.
        if emitidos is not None:
            if impact_id in emitidos:
                self.r.usou("impacto repetido na habilidade, emitido uma vez")
                return []
            emitidos.add(impact_id)

        impacto = self.t.impacts.get(impact_id)
        if impacto is None:
            self.r.lacuna("impacto ausente", f"{onde} -> {impact_id}")
            return []

        encadeados: list[str] = []
        efeitos = self._traduzir_stats(impacto, onde, visitados, encadeados)

        atraso_proprio = (
            atraso_herdado
            + num(impacto.get("StartTime"))
            + num(impacto.get("ColliderActiveDelay"))
        )
        ancora = ANCORA.get(impacto.get("StartPosition", "User"), "CASTER")
        if ancora == "PREVIOUS" and ancora_pai is not None:
            # O pai não virou pulso: não há "anterior" para apontar.
            ancora = ancora_pai

        saida: list[dict] = []
        if efeitos:
            saida.append(self._montar_pulso(
                impacto, skill, efeitos, atraso_proprio, ancora
            ))

        for filho in encadeados:
            saida.extend(self.pulsos(
                filho, skill, onde, visitados, atraso_proprio,
                None if efeitos else ancora, emitidos,
            ))
        return saida

    def _montar_pulso(
        self,
        impacto: dict[str, str],
        skill: dict[str, str],
        efeitos: list[dict],
        atraso: float,
        ancora: str,
    ) -> dict:
        # `TriggerTiming` no caminho de pulso: a coluna estava declarada como
        # consultada e só era lida no caminho de buff. 212 impactos alcançáveis
        # por habilidade têm timing diferente de `Start` e viravam pulso
        # imediato — o censo calava porque a coluna constava como lida.
        self._timing_do_pulso(impacto)

        forma, geometria = self._forma(impacto, skill)
        alvos = self._filtro(impacto.get("TargetType", ""))
        laco = num(impacto.get("LoopInterval"))

        pulso = {
            # Procedência: de qual `Impact` do original este pulso veio.
            # Não é vocabulário de habilidade — o carregador ignora — mas é o
            # que permite provar por teste que nenhum impacto virou dois
            # pulsos, e é o primeiro lugar a olhar quando um número não bate.
            "source_impact": int(impacto.get("Id", 0)),
            "form": forma,
            "origin": ancora,
            "delay": round(atraso, 3),
            # `ActiveDuration` só vira duração de área quando há laço: sem
            # laço ela é o tempo que o colisor fica ligado, que para nós é
            # instantâneo — quem entrar depois não é atingido de novo.
            "duration": num(impacto.get("ActiveDuration")) if laco > 0 else 0.0,
            "loop_interval": laco,
            "direction_offset": num(impacto.get("Angle")),
            "forward_offset": num(impacto.get("StartPositionZ")),
            "side_offset": num(impacto.get("StartPositionX")),
            "max_targets": inteiro(impacto.get("ImpactCount"), 0),
            "effects": efeitos,
        }
        pulso.update(geometria)
        pulso.update(alvos)
        self._conferir_geometria(pulso, skill)
        return pulso

    ## Acusa forma direcional que saiu com alcance ridículo.
    ##
    ## Existe porque o ramo do cone leu por muito tempo uma coluna inexistente
    ## e caía num padrão de 1 metro — sem erro, sem lacuna, e sem o censo ver
    ## nada, porque as colunas envolvidas constavam como consultadas. O que
    ## pega esse tipo de defeito não é conferir coluna: é conferir se o
    ## resultado faz sentido ao lado do alcance da habilidade.
    def _conferir_geometria(self, pulso: dict, skill: dict[str, str]) -> None:
        if pulso["form"] not in ("CONE", "LINE", "TRAPEZOID", "PROJECTILE"):
            return
        alcance = num(skill.get("AI_SkillRange"), 0.0)
        if pulso.get("length", 0.0) <= 1.0 and alcance >= 3.0:
            self.r.lacuna(
                "forma %s com alcance de %.1fm numa habilidade de %.1fm — "
                "geometria suspeita" % (pulso["form"], pulso["length"], alcance),
                f"skill {skill['Id']}",
            )

    ## Registra o que o timing do impacto diz e o pulso não expressa.
    ##
    ## `Arrived` e `ImpactFinish` são aproximados pelo `delay` do pulso e pela
    ## velocidade do projétil — dá para viver com isso, mas é aproximação e
    ## precisa estar escrito. O resto não tem aproximação nenhuma.
    def _timing_do_pulso(self, impacto: dict[str, str]) -> None:
        bruto = impacto.get("TriggerTiming", "Start")
        for parte in [t.strip() for t in bruto.split(",") if t.strip()]:
            if parte == "Start":
                continue
            if parte in ("Arrived", "ImpactFinish"):
                self.r.lacuna(
                    f"TriggerTiming={parte} no pulso "
                    "(aproximado pelo atraso e pela velocidade do projétil)"
                )
                continue
            self.r.lacuna(f"TriggerTiming={parte} no pulso (sem aproximação)")

    ## Registra um número de geometria que NÃO veio do original.
    ##
    ## Inventar é às vezes inevitável — o colisor de verdade do original vive
    ## em `ColliderPath`, um prefab que não está no XML. O que não é aceitável
    ## é inventar calado: uma largura fabricada é indistinguível de uma
    ## traduzida quando ninguém conta.
    def _inventado(self, campo: str, skill: dict[str, str]) -> None:
        self.r.lacuna(
            "geometria inventada: %s (o original guarda o colisor fora do XML)"
            % campo,
            "skill %s" % skill.get("Id", "?"),
        )

    def _forma(
        self, impacto: dict[str, str], skill: dict[str, str]
    ) -> tuple[str, dict]:
        parametros = self._ui_params(skill)
        raio = num(impacto.get("Radius"), 1.0)
        ui = skill.get("UI_Type", "None")

        # Projétil primeiro: a coluna de voo é a evidência mais forte, e ela
        # convive com qualquer `UI_Type`.
        if impacto.get("ProjectileEffectId") or num(impacto.get("MoveDistance")) > 0:
            if num(impacto.get("MoveDistance")) <= 0.0:
                self._inventado("alcance do projétil", skill)
            # `"0"` é uma string verdadeira em Python — sem o teste numérico,
            # quatro projéteis com velocidade zero passavam por "declarada".
            #
            # E a primeira correção parou na METADE: registrava a invenção e
            # continuava emitindo o zero, porque `num(coluna, padrão)` só usa o
            # padrão quando a coluna está AUSENTE. Sete pulsos saíam com
            # velocidade 0 — quatro deles na suprema do Kaiba — e um projétil
            # de velocidade zero nunca chega: fica no ar para sempre, com a
            # esfera parada na tela. Uma sonda de cena pegou.
            velocidade = num(impacto.get("MoveSpeedZ"))
            if velocidade <= 0.0:
                self._inventado("velocidade do projétil", skill)
                velocidade = VELOCIDADE_DE_PROJETIL_PADRAO
            distancia = num(impacto.get("MoveDistance"), 8.0)

            # A largura vem de `CastDirection_Width`, a MESMA chave que o ramo
            # `LINE` usa — o `UI_Type` das duas é `CastDirection`. Antes vinha
            # de `Radius * 2`, que falta em 323 dos 359 impactos de projétil e
            # caía num 2.0 fabricado; 195 pulsos saíam com largura
            # CONTRADIZENDO o XML, que declarava 1,0 ou 1,4.
            largura = num(parametros.get("CastDirection_Width"), 0.0)
            if largura <= 0.0:
                largura = raio * 2.0 if impacto.get("Radius") else 0.0
            if largura <= 0.0:
                self._inventado("largura do projétil", skill)
                largura = 1.0

            return "PROJECTILE", {
                "radius": raio,
                "length": distancia,
                "width": largura,
                "projectile_speed": velocidade,
                # `ImpactCount` 0 quer dizer "sem teto", e um projétil sem teto
                # é um que atravessa.
                "pierces": inteiro(impacto.get("ImpactCount"), 0) != 1,
            } | self._leque(parametros, skill)

        if ui == "CastCircularSector":
            # O alcance do cone vem de `AI_SkillRange`, como no ramo `LINE`.
            #
            # Isto já leu `CircularSector_Range` — uma coluna que **não existe
            # em nenhuma das 18 habilidades de cone do original**. O padrão
            # caía em `raio`, que por sua vez caía em 1.0 quando o impacto não
            # declara `Radius`; 15 das 18 não declaram. Resultado: 20 dos 25
            # pulsos de cone alcançavam 1 metro onde o original alcança 4 ou 5.
            #
            # Não era decorativo: `AbilityShape._in_cone` usa `length` como
            # alcance, e o cone do Leo virava um golpe colado no corpo.
            return "CONE", {
                "length": num(skill.get("AI_SkillRange"), max(raio, 4.0)),
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
            if not skill.get("AI_SkillRange"):
                self._inventado("alcance da linha", skill)
            if not parametros.get("CastDirection_Width"):
                self._inventado("largura da linha", skill)
            return "LINE", {
                "length": num(skill.get("AI_SkillRange"), 8.0),
                "width": num(parametros.get("CastDirection_Width"), max(raio, 1.0)),
                "radius": raio,
            } | self._leque(parametros, skill)

        if impacto.get("Radius"):
            return "CIRCLE", {"radius": raio}

        # Habilidade de área cujo impacto não declara raio: o raio é o do
        # retículo, `CastArea_Bound`. Sem isto, 139 impactos de habilidade de
        # ÁREA viravam alvo único — que é outra habilidade.
        if ui in ("CastArea", "CastTargetArea", "CastAreaSummon",
                  "CastAreaCurveDirection", "CastSquare"):
            limite = num(parametros.get("CastArea_Bound"), 0.0)
            if limite > 0.0:
                self.r.usou("raio de área vindo do retículo")
                return "CIRCLE", {"radius": limite}

        # Sem raio e sem direção: acerta quem foi apontado, e mais ninguém.
        return "SINGLE", {"radius": raio}

    ## `CastDirection_Count` + `CastDirection_Angle` -> leque.
    ##
    ## Sete habilidades do original disparam 3 ou 5 projéteis abertos em leque.
    ## O tradutor lia só a largura e emitia UM projétil — os outros dois ou
    ## quatro sumiam sem nada avisar, porque a chave vive dentro de `UI_Params`
    ## e o censo de colunas só enxerga a coluna inteira.
    ##
    ## Foi o que motivou o censo de CHAVES de `UI_Params`, logo abaixo.
    def _leque(self, parametros: dict[str, str], skill: dict[str, str]) -> dict:
        quantos = inteiro(parametros.get("CastDirection_Count"), 1)
        if quantos <= 1:
            return {}

        # **O leque pode já estar nos impactos.** A Violet tem três impactos com
        # `Angle` -18, 0 e +18: o leque dela é feito de pulsos angulados, e o
        # `CastDirection_Count` é só o retículo que a interface desenha.
        # Aplicar os dois dava NOVE direções onde havia três — bug introduzido
        # quando o leque foi traduzido pela primeira vez.
        if self._impactos_ja_angulados(skill):
            self.r.usou("leque já vem angulado nos impactos")
            return {}

        self.r.usou("leque de projéteis")
        return {
            "spread_count": quantos,
            "spread_angle": num(parametros.get("CastDirection_Angle"), 0.0),
        }

    def _impactos_ja_angulados(self, skill: dict[str, str]) -> bool:
        for indice in range(1, 13):
            impact_id = skill.get(f"Impact{indice}")
            if not impact_id:
                continue
            impacto = self.t.impacts.get(impact_id)
            if impacto is not None and num(impacto.get("Angle")) != 0.0:
                return True
        return False

    @staticmethod
    def _ui_params(skill: dict[str, str]) -> dict[str, str]:
        cru = skill.get("UI_Params", "")
        saida: dict[str, str] = {}
        for parte in cru.split(","):
            if "=" in parte:
                chave, _, valor = parte.partition("=")
                saida[chave.strip()] = valor.strip()
        return saida

    ## Espécies do original que são CAMPEÃO ou coisa que se joga.
    ##
    ## O ataque básico declara `TargetAlly(11), TargetEnemy(1,2,3,5,10,11)`: do
    ## lado aliado só a espécie 11, que não é campeão — cura e escudo de
    ## verdade usam `Ally(1,2)`. Ler só o nome do lado, ignorando a lista,
    ## fazia 76 pulsos de ataque básico saírem acertando o próprio time.
    ESPECIES_JOGAVEIS = {"1", "2"}

    @classmethod
    def _filtro(cls, target_type: str) -> dict:
        """`TargetType` -> quem a forma pega.

        O original escreve `Enemy(1,2,3,5,20)`: o nome diz o LADO e os números
        dizem as ESPÉCIES. A lista numérica inteira é uma taxonomia interna que
        não temos — mas a distinção entre "espécie jogável" e "o resto"
        importa, e é ela que separa um ataque básico de uma cura.
        """
        texto = target_type or ""
        inimigos = "Enemy" in texto
        aliados = cls._alcanca_jogavel(texto, "Ally")
        proprio = "Mine" in texto or "Self" in texto
        if not (inimigos or aliados or proprio):
            inimigos = True
        return {
            "hits_enemies": inimigos,
            "hits_allies": aliados,
            "hits_self": proprio,
        }

    ## Verdadeiro quando o lado citado inclui espécie jogável.
    ##
    ## `Ally(1,2)` sim; `TargetAlly(11)` não. Um lado citado sem lista nenhuma
    ## conta como sim — é o caso genérico, e recusar seria perder alvo.
    @classmethod
    def _alcanca_jogavel(cls, texto: str, lado: str) -> bool:
        achou = False
        for trecho in re.finditer(r"(\w*%s)\s*\(([^)]*)\)" % lado, texto):
            achou = True
            especies = {e.strip() for e in trecho.group(2).split(",") if e.strip()}
            if especies & cls.ESPECIES_JOGAVEIS:
                return True
        if achou:
            return False
        return lado in texto

    # ---------------------------------------------------------- habilidade

    def habilidade(self, skill: dict[str, str]) -> dict:
        skill_id = skill["Id"]
        onde = f"skill {skill_id}"
        dono = _quem(skill)
        icone = _slug(skill.get("ButtonIconPath", ""))

        # `Impact1` a `Impact12`. Parava em 8 e perdia 13 impactos inteiros de
        # 8 habilidades, com dano e cura de verdade — e sem virar lacuna,
        # porque o laço nem chegava a olhar a coluna.
        # `vistos` é da HABILIDADE inteira, não de uma cadeia.
        #
        # 16 habilidades listam um impacto em `ImpactN` **e** o encadeiam a
        # partir de outro. Sem esta guarda o mesmo golpe sai duas vezes, com
        # atrasos ligeiramente diferentes — e o dano dobra sem que nada no dado
        # diga isso. A leitura adotada é que a repetição é redundância da
        # tabela, não intenção; vale a primeira ocorrência, e a contagem entra
        # no relatório para a suposição ficar auditável.
        pulsos: list[dict] = []
        vistos: set[str] = set()
        for indice in range(1, 13):
            impact_id = skill.get(f"Impact{indice}")
            if not impact_id:
                continue
            if impact_id in vistos:
                self.r.usou("impacto repetido na habilidade, emitido uma vez")
                continue
            # `pulsos()` já registra em `vistos` ao entrar; não há o que
            # acrescentar aqui. A versão anterior tinha um `if` que nunca era
            # verdadeiro — resto de uma tentativa mais complicada.
            pulsos.extend(self.pulsos(impact_id, skill, onde, emitidos=vistos))

        # `RemoveCC` é purificação, e `CleanseEffect` já existia. Sai como um
        # pulso no próprio conjurador, antes dos outros: purificar depois de
        # apanhar de novo não faria sentido.
        limpeza = self._purificacao(skill, onde)
        if limpeza is not None:
            pulsos.insert(0, limpeza)

        ui = skill.get("UI_Type", "None")
        if ui not in MIRA:
            self.r.lacuna(f"UI_Type={ui}", onde)
        mira = MIRA.get(ui, "POINT")

        # `CastingTime` existe em 61 habilidades, com valores de 0,3 a 5
        # segundos. A afirmação de que "o original não trava a conjuração"
        # estava errada: ele trava, só não em toda habilidade.
        tempo_de_conjuracao = num(skill.get("CastingTime"), 0.0)
        if tempo_de_conjuracao > 0.0:
            self.r.usou("cast_time")

        # `StatType1`/`StatValue1` da SKILL é o bônus que a habilidade dá por
        # existir naquele ranque — o Q que concede 2%/4%/6%/8%/10% de redução
        # de recarga conforme sobe. Não é o que ela faz ao ser conjurada, e por
        # isso não vira pulso: vira `Ability.passive_effects`.
        passivas: list[dict] = []
        for indice in range(1, 5):
            nome = skill.get(f"StatType{indice}")
            if not nome:
                continue
            mod = self._modificador(
                nome, num(skill.get(f"StatValue{indice}")),
                -1.0, "CASTER", f"rc_{skill_id}", onde,
            )
            if mod is not None:
                self.r.usou("passiva de ranque")
                passivas.append(mod)

        if skill.get("ComboSkillInfo_SkillID"):
            self.r.lacuna("ComboSkillInfo (corrente de combo)", onde)
        if skill.get("ZMoveCurvePath") or skill.get("YMoveCurvePath"):
            self.r.lacuna("curva de deslocamento (MoveCurve)", onde)
        if skill.get("CancelForbidStartTime"):
            self.r.lacuna("janela de cancelamento por tempo", onde)

        # Ranque 0 é a linha-modelo do grupo: existe para a interface mostrar a
        # habilidade ainda não aprendida, e por isso não referencia impacto
        # nenhum. Marcá-la evita que o relatório conte 115 modelos como 115
        # falhas de tradução.
        zera_cadencia = booleano(skill.get("ResetAttackCoolTime"))
        if zera_cadencia:
            self.r.usou("reset de auto-ataque (ResetAttackCoolTime)")
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
            # `CastingTime` quando existe; zero quando não. A maioria das
            # habilidades do original NÃO trava a conjuração — ela usa a
            # animação com janelas de cancelamento, e o timing do golpe vem do
            # `StartTime` de cada impacto, que virou o `delay` do pulso. As 61
            # que travam trazem a coluna, e agora ela é lida.
            "cast_time": tempo_de_conjuracao,
            "can_move_while_casting": booleano(skill.get("MovingOnSkill")),
            "cancelable": skill.get("SkillCancelableTime") is not None,
            "mana_cost": num(skill.get("CostValue")),
            "aim": mira,
            "cast_range": num(skill.get("AI_SkillRange"), 0.0),
            # `UltimateCharge`: quanto esta habilidade enche a suprema. Era
            # lacuna registrada — a suprema não tem recarga no original, ela
            # enche agindo, e sem isto ela recebia um número inventado.
            "ultimate_charge_gain": num(skill.get("UltimateCharge"), 0.0),
            # `ResetAttackCoolTime`: conjurar zera a cadência do ataque básico.
            # Era lacuna registrada — e é o que dá ritmo ao corpo a corpo, onde
            # encaixar a habilidade entre dois golpes é a jogada.
            "resets_attack_cooldown": zera_cadencia,
            "pulses": pulsos,
            "passive_effects": passivas,
        }

    def _purificacao(self, skill: dict[str, str], onde: str) -> dict | None:
        """`RemoveCC` e `RemoveDebuff` -> um pulso de purificação no conjurador."""
        bruto = skill.get("RemoveCC")
        limpa_buff = booleano(skill.get("RemoveDebuff"))
        if not bruto and not limpa_buff:
            return None
        efeitos: list[dict] = []

        if limpa_buff:
            # `RemoveDebuff` tira efeito negativo; `RemoveCC` tira controle.
            # A única habilidade que tem os dois tinha o segundo descartado
            # porque a função devolvia no primeiro ramo que casasse.
            self.r.usou("cleanse (RemoveDebuff)")
            efeitos.append({
                "type": "cleanse", "recipient": "CASTER",
                "scope": "BUFFS", "only_source": "", "strips_shield": False,
            })

        tipos = [t.strip() for t in (bruto or "").split(",") if t.strip()]
        # Lista com Stun e companhia é purificação ampla; só `Slow` é a
        # estreita. Nosso `CleanseEffect` de escopo CROWD_CONTROL cobre as
        # duas — ele tira controle e lentidão juntos, e separar exigiria um
        # escopo por tipo que nenhuma outra habilidade usaria.
        if tipos:
            self.r.usou("cleanse (RemoveCC)")
            if len(tipos) == 1 and tipos[0] == "Slow":
                self.r.lacuna(
                    "RemoveCC só de Slow traduzido como purificação ampla", onde
                )
            efeitos.append({
                "type": "cleanse",
                "recipient": "CASTER",
                "scope": "CROWD_CONTROL",
                "only_source": "",
                "strips_shield": False,
            })

        return {
            "form": "SINGLE",
            "origin": "CASTER",
            "delay": 0.0,
            "duration": 0.0,
            "loop_interval": 0.0,
            "radius": 0.0,
            "max_targets": 0,
            "hits_enemies": False,
            "hits_allies": False,
            "hits_self": True,
            "effects": efeitos,
        }

    # ---------------------------------------------------------- item

    # ------------------------------------------------------------- ator

    def ator(self, registro: dict[str, str], apelido: str) -> dict:
        """Uma linha de `actor_xml` vira um perfil de personagem.

        É a peça que faltava para o corpus virar jogo. As tabelas de
        habilidade dizem O QUE cada habilidade faz; nenhuma delas diz QUEM a
        tem. Está aqui, e só aqui.
        """
        ator_id = registro["Id"]
        onde = f"actor {ator_id}"

        uso = registro.get("UsageType", "")
        if uso not in NATUREZA:
            self.r.lacuna(f"UsageType={uso}", onde)
        self.r.usou(f"ator:{uso or 'sem UsageType'}")

        papel = registro.get("InfoPosition", "")
        if papel and papel not in PAPEL:
            self.r.lacuna(f"InfoPosition={papel}", onde)

        base = self._atributos_do_ator(
            registro, "StatType_%d", "StatValue_%d", 14, onde
        )
        crescimento = self._atributos_do_ator(
            registro, "LevelUpStatType_%d", "LevelUpStatValue_%d", 8, onde
        )
        self._ataque_basico(registro, base, onde)

        passivas: list[dict] = []
        for buff_id in lista_ids(registro.get("PassiveBuffs")):
            passivas.extend(self.buff(buff_id, "CASTER", onde))

        # Q, W e E saem de `DefaultSkillId_2..4`, nessa ordem. O `_1` é o
        # ataque básico — medido: `UI_Type = InstantTarget` e recarga de menos
        # de um segundo em todos os 34 campeões e nos 97 mobs que o declaram.
        # Amarrá-lo a um espaço de habilidade daria ao jogador um Q que é o
        # próprio ataque que ele já tem no clique.
        espacos: list[str] = []
        for indice in (2, 3, 4):
            grupo = self._grupo_da_skill(
                registro.get(f"DefaultSkillId_{indice}"), onde
            )
            if grupo:
                espacos.append(grupo)

        suprema = self._grupo_da_skill(registro.get("UltimateSkill"), onde)
        # `LevelUpUltimateCharge` é o CUSTO da suprema, e vale 1000 nos 31
        # campeões que a têm. Já foi lido como booleano ("usa carga?") enquanto
        # o sistema não existia; agora é o número.
        custo_da_suprema = num(registro.get("LevelUpUltimateCharge"), 0.0)
        por_carga = custo_da_suprema > 0.0
        if por_carga:
            self.r.usou("carga de suprema")
        # A recarga inventada morreu junto com a lacuna. O que sobrou é o
        # caso do ator que tem suprema e NÃO declara carga: aí a recarga do
        # original vale, e se ela também for zero a suprema sai a cada quadro.
        recarga_no_original = self._recarga_da_skill(registro.get("UltimateSkill"))
        recarga_da_suprema = 0.0
        if suprema and not por_carga and recarga_no_original <= 0.0:
            recarga_da_suprema = RECARGA_DE_SUPREMA_SEM_CARGA
            self.r.lacuna(
                "suprema sem carga E sem recarga — %.0fs inventados no lugar"
                % RECARGA_DE_SUPREMA_SEM_CARGA,
                onde,
            )

        perfil = {
            "id": apelido,
            "source_id": int(ator_id),
            "source_table": registro.get("__tabela", "actor_xml"),
            "display_name": apelido,
            "usage": uso,
            "nature": NATUREZA.get(uso, "MONSTER"),
            "role": PAPEL.get(papel, ""),
            "damage_type": registro.get("InfoDamageType", ""),
            "rarity": RARIDADE.get(registro.get("Rarity", "Common"), "COMMON"),
            "enabled": registro.get("Enable", "Release") == "Release",
            # Em que nível o bloco de atributos acima vale. Ausente em todo
            # campeão (começam no 1) e presente nos mobs, que nascem prontos.
            "base_level": max(1, inteiro(registro.get("Level"), 1)),
            "base_stats": base,
            "growth": crescimento,
            "basic_attack_group": self._grupo_da_skill(
                registro.get("DefaultSkillId_1"), onde
            ),
            "ability_groups": espacos,
            "ultimate_group": suprema,
            "ultimate_uses_charge": por_carga,
            "ultimate_charge_cost": custo_da_suprema,
            # Quanto o ataque básico rende. Sai da habilidade
            # `DefaultSkillId_1`, e não dos atributos — o ataque básico não
            # passa pelo motor de habilidade, então o `Unit` precisa carregar
            # este número.
            "ultimate_charge_on_attack": self._carga_da_skill(
                registro.get("DefaultSkillId_1")
            ),
            "ultimate_cooldown": recarga_da_suprema,
            "passive_effects": passivas,
            "body_radius": num(registro.get("ControllerRadius"), 0.5),
            "body_height": num(registro.get("ControllerHeight"), 2.0),
            "damageable": booleano(registro.get("EnableDamage"), True),
            "targetable": booleano(registro.get("EnableTarget"), True),
            # `AbleCombat` está AUSENTE em todo campeão e todo bot, e o
            # padrão literal (`False`) faria os 100 personagens jogáveis
            # nascerem incapazes de lutar. Quando a coluna não fala, quem
            # responde é a natureza: só estrutura não briga.
            "able_combat": booleano(
                registro.get("AbleCombat"),
                NATUREZA.get(uso, "MONSTER") != "STRUCTURE",
            ),
            # `AI/PlayerAggressive` -> `playeraggressive`. É a taxonomia de
            # comportamento do original, de graça, para quando os mobs
            # ganharem IA. Nada lê isto ainda.
            "ai_profile": _slug(registro.get("AIPath", "").split("/")[-1]),
            "max_summons": inteiro(registro.get("SummonActorMaxCount"), 0),
            "on_spawn_group": self._grupo_da_skill(
                registro.get("ActivationSkillId"), onde
            ),
            "on_death_group": self._grupo_da_skill(
                registro.get("SlainSkillId"), onde
            ),
            "on_combat_start_group": self._grupo_da_skill(
                registro.get("CombatStartSkill"), onde
            ),
            "on_return_group": self._grupo_da_skill(
                registro.get("ReturnFinishSkill"), onde
            ),
        }
        self._conferir_ator(perfil, registro)
        return perfil

    ## Alcance e cadência do ataque básico, que NÃO estão nos atributos.
    ##
    ## Medido, e o achado importa: `AI_SkillRange` da habilidade
    ## `DefaultSkillId_1` vale 2 para o Leo (guerreiro), 2,4 para a Morgan e 6
    ## para a Bella (atiradora). O `CoolTime` da mesma linha é o intervalo
    ## entre ataques — 0,8s no Leo, 0,73s na Bella.
    ##
    ## Nenhum dos dois aparece em `StatType_N`. Sem ler daqui, todo campeão
    ## herdaria o padrão da classe — 2,5m de alcance e um ataque por segundo —
    ## e a atiradora do original viraria corpo a corpo sem uma linha de erro
    ## em lugar nenhum. É a armadilha da rodada 5 outra vez: o dado existe, só
    ## não está onde se olhou.
    def _ataque_basico(
        self, registro: dict[str, str], base: dict[str, float], onde: str
    ) -> None:
        skill_id = registro.get("DefaultSkillId_1")
        if not skill_id or skill_id == "0":
            return
        skill = self.t.skills.get(skill_id)
        if skill is None:
            return

        alcance = num(skill.get("AI_SkillRange"), 0.0)
        if alcance > 0.0:
            base["attack_range"] = alcance
            self.r.usou("stat:attack_range")
        else:
            self.r.lacuna("ataque básico sem alcance declarado", onde)

        intervalo = num(skill.get("CoolTime"), 0.0)
        if intervalo > 0.0:
            base["attack_speed"] = round(1.0 / intervalo, 4)
            self.r.usou("stat:attack_speed")

    ## Acusa perfil que saiu sem fazer sentido, e não só sem coluna lida.
    ##
    ## É a lição da rodada 7 aplicada aqui: um arremesso com duração zero não
    ## dava erro nenhum e o relatório o contava como cobertura. Um campeão com
    ## 0 de vida, ou com o kit vazio, tem exatamente a mesma cara — o dado foi
    ## lido, o campo existe, e o resultado não serve para jogar.
    def _conferir_ator(self, perfil: dict, registro: dict[str, str]) -> None:
        onde = f"actor {registro['Id']}"
        combatente = perfil["nature"] in ("CHAMPION", "MONSTER", "SUMMON")
        if combatente and perfil["base_stats"].get("max_health", 0.0) <= 0.0:
            self.r.lacuna("ator combatente sem vida máxima", onde)
        if perfil["usage"] != "Player":
            return
        # Campeão sem kit não é campeão. 33 dos 40 `Player` têm os três
        # espaços; os outros são bonecos de tutorial e cascas de teste, e é
        # justamente por isso que a contagem tem que aparecer.
        if len(perfil["ability_groups"]) < 3:
            self.r.lacuna("campeão com menos de três habilidades (Q/W/E)", onde)
        if not perfil["ultimate_group"]:
            self.r.lacuna("campeão sem suprema", onde)
        # Um campeão que caísse no padrão de alcance da classe seria um
        # campeão de dado incompleto passando por completo.
        if perfil["base_stats"].get("attack_range", 0.0) <= 0.0:
            self.r.lacuna("campeão sem alcance de ataque básico", onde)

    ## `UltimateCharge` de uma habilidade citada pelo ator, ou zero.
    def _carga_da_skill(self, skill_id: str | None) -> float:
        if not skill_id or skill_id == "0":
            return 0.0
        return num((self.t.skills.get(skill_id) or {}).get("UltimateCharge"), 0.0)

    ## `CoolTime` de uma habilidade citada pelo ator, ou zero.
    def _recarga_da_skill(self, skill_id: str | None) -> float:
        if not skill_id or skill_id == "0":
            return 0.0
        return num((self.t.skills.get(skill_id) or {}).get("CoolTime"), 0.0)

    ## Id de habilidade do original -> `group_id` do nosso corpus.
    ##
    ## A tabela de atores aponta para a LINHA-MODELO do grupo (`Rank 0`), que
    ## não referencia impacto nenhum: é a entrada de interface da habilidade
    ## ainda não aprendida. Guardar esse id daria ao jogador um Q que não faz
    ## nada, sem erro nenhum no caminho. O que serve é o GRUPO — o ranque sai
    ## depois de `AbilityCatalog.rank_for_level()`, com o nível do personagem.
    def _grupo_da_skill(self, skill_id: str | None, onde: str) -> str:
        if not skill_id or skill_id == "0":
            return ""
        skill = self.t.skills.get(skill_id)
        if skill is None:
            self.r.lacuna(
                "ator aponta para habilidade ausente", f"{onde} -> {skill_id}"
            )
            return ""
        return f"rc_g_{skill.get('SkillGroupID', skill_id)}"

    ## `StatType_N`/`StatValue_N` de um ator -> `{nosso_atributo: valor}`.
    ##
    ## Serve para os atributos BASE e para o crescimento por nível, que usam o
    ## mesmo formato com prefixo diferente.
    ##
    ## O sinalizador de percentual do mapa `STATS` é ignorado aqui **de
    ## propósito**: base é base. `MaxAttackSpeedRate = 2` num ator quer dizer
    ## "o teto dele são 2 ataques por segundo", não "+200%" — e num item, que
    ## é onde o sinalizador vale, o mesmo nome quer dizer a segunda coisa.
    def _atributos_do_ator(
        self,
        registro: dict[str, str],
        molde_tipo: str,
        molde_valor: str,
        ate: int,
        onde: str,
    ) -> dict[str, float]:
        valores: dict[str, float] = {}
        for indice in range(1, ate):
            nome = registro.get(molde_tipo % indice)
            if not nome:
                continue
            if nome not in STATS:
                self.r.lacuna(f"StatType={nome}", onde)
                continue
            atributo, _percentual = STATS[nome]
            valor = num(registro.get(molde_valor % indice))
            if nome in STATS_INVERTIDOS:
                valor = -valor
            valores[atributo] = valores.get(atributo, 0.0) + valor
            self.r.usou(f"stat:{atributo}")
        return valores

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
            # `EquipLine = 0` é o marcador de "sem linha", não uma linha
            # chamada zero. Copiá-lo literalmente juntava nove itens sem
            # parentesco nenhum — três elmos, quatro luvas e duas botas — numa
            # "linha de melhoria" de nove degraus que não existe.
            "line_id": _linha_do_item(equip, equip_id),
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
    caminho: Path,
    habilidades: list[dict],
    itens: list[dict],
    atores: list[dict],
    r: Relatorio,
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
    linhas.append(f"| Atores traduzidos | **{len(atores)}** |")
    linhas.append("")

    linhas.extend(_secao_de_atores(atores, habilidades))

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

    linhas.append("## Censo de colunas — o que nunca foi olhado")
    linhas.append("")
    linhas.append(
        "A tabela de lacunas abaixo só sabe do que o tradutor **tentou** "
        "mapear. Uma coluna que o código nunca menciona não gera lacuna "
        "nenhuma — ela some, e a ausência fica indistinguível de uma decisão. "
        "Este censo varre as colunas presentes no XML e lista as que não estão "
        "nem em `CONSULTADAS` nem em `IGNORADAS`. Ele cobre **todas** as "
        "tabelas que o tradutor abre — inclusive a de receitas, que ficou de "
        "fora na primeira versão."
    )
    linhas.append("")
    total_orfas = sum(len(c) for c in r.nao_consultadas.values())
    if total_orfas == 0:
        linhas.append(
            "**Nenhuma.** Toda coluna das %d tabelas que o tradutor lê (%s) "
            "ou é consultada, ou está declarada em `IGNORADAS` com o motivo."
            % (
                len(r.nao_consultadas),
                ", ".join(f"`{n}`" for n in sorted(r.nao_consultadas)),
            )
        )
    else:
        linhas.append("| Tabela | Coluna | Linhas que a têm |")
        linhas.append("|---|---|---|")
        for tabela, colunas in r.nao_consultadas.items():
            for coluna, quantas in colunas.most_common():
                linhas.append(f"| `{tabela}` | `{coluna}` | {quantas} |")
    linhas.append("")

    orfas_declaradas = sorted(
        k for k in IGNORADAS if k not in r.colunas_vistas
    )
    if orfas_declaradas:
        linhas.append("### Declarações que nunca disparam")
        linhas.append("")
        linhas.append(
            "Entradas de `IGNORADAS` que nomeiam colunas inexistentes nas "
            "tabelas lidas. Não fazem mal, mas inflam a lista e dão impressão "
            "de cobertura que não existe — uma justificativa que nunca é usada "
            "é uma justificativa que ninguém conferiu."
        )
        linhas.append("")
        for chave in orfas_declaradas:
            linhas.append(f"- `{chave}`")
        linhas.append("")

    if r.chaves_orfas:
        linhas.append("### Chaves de `UI_Params` sem leitura nem decisão")
        linhas.append("")
        linhas.append("| Chave | Habilidades |")
        linhas.append("|---|---|")
        for chave, quantas in r.chaves_orfas.most_common():
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


def _secao_de_atores(atores: list[dict], habilidades: list[dict]) -> list[str]:
    """Quem tem quais habilidades — a parte do original que faltava.

    A contagem por `UsageType` e a de campeões COM KIT são números diferentes,
    e a diferença é o ponto: `actor_xml` e `actor_2_xml` repetem Ids, e há
    `Player` que é boneco de tutorial. Publicar só o total daria 58 campeões
    onde há 33 jogáveis.
    """
    por_uso: collections.Counter[str] = collections.Counter(
        a["usage"] or "(sem UsageType)" for a in atores
    )
    campeoes = [
        a for a in atores if a["usage"] == "Player" and len(a["ability_groups"]) >= 3
    ]
    com_suprema = [a for a in campeoes if a["ultimate_group"]]
    com_crescimento = [a for a in atores if a["growth"]]
    com_passiva = [a for a in atores if a["passive_effects"]]

    # Grupo que tem ao menos um ranque conjurável. Um campeão cujo W caia num
    # grupo sem isso nasce com um espaço morto — e a contagem de "33 campeões"
    # esconderia esse caso se ela fosse a única publicada.
    jogaveis = {h["group_id"] for h in habilidades if h["pulses"]}
    def armado(a: dict) -> bool:
        citados = list(a["ability_groups"]) + [a["ultimate_group"]]
        return all(g in jogaveis for g in citados)
    plenos = [a for a in campeoes if armado(a)]
    mancos = [a for a in campeoes if not armado(a)]

    linhas = ["### Atores", ""]
    linhas.append(
        "`actor_xml` é a tabela de QUEM. Nenhuma outra responde quais "
        "habilidades cada personagem tem — é por ela que o corpus deixa de "
        "ser catálogo e vira personagem jogável."
    )
    linhas.append("")
    linhas.append("| `UsageType` | Quantos |")
    linhas.append("|---|---|")
    for uso, quantos in por_uso.most_common():
        linhas.append(f"| `{uso}` | {quantos} |")
    linhas.append("")
    linhas.append("| | |")
    linhas.append("|---|---|")
    linhas.append(
        f"| Campeões com Q, W e E | **{len(campeoes)}** |"
    )
    linhas.append(f"| ...desses, com suprema | {len(com_suprema)} |")
    linhas.append(
        f"| ...com **as quatro** habilidades conjuráveis | **{len(plenos)}** |"
    )
    linhas.append(f"| Atores com crescimento por nível | {len(com_crescimento)} |")
    linhas.append(f"| Atores com passiva | {len(com_passiva)} |")
    linhas.append("")
    if mancos:
        linhas.append(
            "Os %d abaixo citam um grupo de habilidade que não tem nenhum "
            "ranque conjurável — a habilidade do original cai numa lacuna já "
            "registrada, e o espaço fica vazio em vez de receber um botão que "
            "não faz nada." % len(mancos)
        )
        linhas.append("")
        linhas.append("| Campeão | Grupo sem ranque conjurável |")
        linhas.append("|---|---|")
        for a in mancos:
            faltando = [
                g for g in list(a["ability_groups"]) + [a["ultimate_group"]]
                if g not in jogaveis
            ]
            linhas.append(f"| `{a['id']}` | {', '.join(f'`{g}`' for g in faltando)} |")
        linhas.append("")
    return linhas


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

    brutos = sorted(tabelas.actors.values(), key=lambda a: int(a["Id"]))
    apelidos = apelidos_de_ator(brutos)
    atores = [tradutor.ator(bruto, apelidos[bruto["Id"]]) for bruto in brutos]

    relatorio.censo(tabelas)

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
    _escrever_json(args.saida / "atores.json", {
        "fonte": "Royal Crown 13.0.13 (referência de design — ver docs/01)",
        "vocabulario": "docs/03-sistemas-de-jogo.md",
        "total": len(atores),
        "atores": atores,
    })
    escrever_relatorio(
        args.saida / "RELATORIO.md", habilidades, itens, atores, relatorio
    )

    campeoes = [a for a in atores if a["usage"] == "Player" and a["ability_groups"]]
    print(
        f"[traducao] {len(habilidades)} habilidades, {len(itens)} itens, "
        f"{len(atores)} atores ({len(campeoes)} campeões com kit)"
    )
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
