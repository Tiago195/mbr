# Relatório da tradução do original

> **Gerado por `tools/traducao/traduzir.py`. Não editar à mão.**  
> Rodar de novo: `py tools/traducao/traduzir.py`

## Cobertura

| | |
|---|---|
| Habilidades traduzidas | **1126** |
| ...de `skill_2_xml` | 176 |
| ...de `skill_4_xml` | 2 |
| ...de `skill_xml` | 948 |
| ...com pelo menos um pulso | 963 |
| ...com mais de um pulso | 330 |
| Pulsos gerados | 1501 |
| Efeitos gerados | 3197 |
| Itens traduzidos | **421** |

### As que saíram sem pulso

Uma habilidade sem pulso não é necessariamente uma tradução falha. Separar os três casos é o que permite saber se ainda falta trabalho.

| Caso | Quantas | O que é |
|---|---|---|
| Linha-modelo (`Rank 0`) | 116 | A entrada de interface da habilidade ainda não aprendida. Não referencia impacto **por definição** — os ranques 1 a 5 é que carregam os números. |
| Quebra de combo | 2 | Marcador que interrompe uma corrente de golpes. Não tem efeito porque cancelar é o efeito. |
| **Sem tradução** | **45** | Referencia impacto e nada saiu. São as lacunas da tabela abaixo — `Link`, `UseSkillSlot`, `ReleaseImpact` e as de modo de jogo. |

Ids sem tradução (amostra): 1016250, 1016251, 1016252, 1016253, 1016254, 1018301, 1018302, 1018303, 1018304, 1018305, 1019201, 1019202, 1019203, 1019204, 1019205, 1021850, 1021860, 1022350, 1023350, 1026251

## O que o vocabulário cobriu

| Peça | Vezes |
|---|---|
| `damage:physical` | 900 |
| `damage:magic` | 813 |
| `stat:move_speed` | 493 |
| `periodic` | 370 |
| `impacto encadeado` | 324 |
| `receita de fabricação` | 299 |
| `mark` | 289 |
| `cc:SLOW` | 185 |
| `stat:armor` | 181 |
| `stat:magic_resist` | 173 |
| `summon` | 171 |
| `heal` | 137 |
| `cc:STUN` | 130 |
| `shield` | 129 |
| `dissipa em SHIELD_BROKEN` | 126 |
| `cc:AIRBORNE` | 120 |
| `cooldown` | 100 |
| `stat:attack_damage` | 74 |
| `stat:magic_damage_amp` | 73 |
| `stat:physical_damage_amp` | 71 |
| `stat:ability_power` | 71 |
| `stat:attack_speed` | 69 |
| `damage:percent_hp` | 56 |
| `damage:monster_cap` | 55 |
| `aura como buff simples` | 55 |
| `resource` | 53 |
| `stat:max_health` | 45 |
| `stat:cooldown_reduction` | 41 |
| `execute` | 37 |
| `heal:percent_hp` | 34 |
| `damage:siege` | 33 |
| `stat:out_of_combat_health_regen` | 28 |
| `stat:dodge` | 26 |
| `stat:heal_received_amp` | 25 |
| `stat:mana_regen` | 23 |
| `stat:armor_pen_flat` | 22 |
| `cc:CHARM` | 21 |
| `stat:crit_chance` | 21 |
| `stat:health_regen_amp` | 19 |
| `stat:magic_pen_flat` | 19 |
| `displacement:cc` | 18 |
| `dissipa em ABILITY_CAST` | 15 |
| `displacement:teleporte` | 15 |
| `stat:lifesteal` | 15 |
| `stat:out_of_combat_mana_regen` | 14 |
| `stat:sight_range` | 13 |
| `stat:slow_resist` | 13 |
| `stat:max_mana` | 12 |
| `stat:tenacity` | 11 |
| `stat:crit_damage` | 11 |
| `stat:health_regen` | 9 |
| `damage:hibrido` | 9 |
| `stat:spell_vamp` | 9 |
| `stat:armor_pen_percent` | 9 |
| `stat:magic_pen_percent` | 9 |
| `stat:damage_taken_reduction` | 7 |
| `cc:ROOT` | 6 |
| `cc:INVULNERABLE` | 5 |
| `cc:BLIND` | 5 |
| `cc:TAUNT` | 5 |
| `stat:item_cooldown_reduction` | 5 |
| `stat:cooldown_reduction_cap` | 5 |
| `stat:crit_avoidance` | 4 |
| `stat:heal_power` | 4 |
| `stat:weight` | 3 |
| `stat:shield_received_amp` | 3 |
| `cc:SILENCE` | 1 |
| `cc:POLYMORPH` | 1 |

## Lacunas — o que o original diz e nós ainda não

Cada linha é uma coluna do original que o tradutor encontrou e não soube converter. **Isto é informação sobre o sistema, não erro** — o critério para fechar uma lacuna é ela valer o sistema que exige, e várias abaixo não valem.

| Lacuna | Ocorrências | Exemplo |
|---|---|---|
| UltimateCharge (carga de suprema) | 534 | skill 1000000 |
| curva de deslocamento (MoveCurve) | 154 | skill 1000200 |
| ComboSkillInfo (corrente de combo) | 125 | skill 1000000 |
| janela de cancelamento por tempo | 72 | skill 1000000 |
| Link (corrente que liga dois alvos e rompe na distância) | 47 | skill 1003201 |
| BuffReleaseCondition=SkillFinish | 35 | skill 1001301 |
| UseSkillSlot (troca a habilidade de um espaço) | 27 | skill 1007351 |
| PingList (aviso na interface, não é combate) | 22 | skill 3001000 |
| StatType=PhysicalDamageAmp_SkillE | 21 | skill 1025101 |
| RecoverDataType=RegenHealth sem valor legível (os números vivem no texto localizado) | 19 | equipment 5000000 |
| RecoverDataType=RegenAll sem valor legível (os números vivem no texto localizado) | 19 | equipment 7308001 |
| BuffReleaseCondition=InteractionStart | 16 | skill 1003401 |
| ReleaseImpact (cancela impacto em curso) | 6 | skill 1016250 |
| RecoverDataType=RegenMana sem valor legível (os números vivem no texto localizado) | 5 | equipment 5000001 |
| BuffReleaseCondition=OnStartSkill | 4 | skill 3301030 |
| BuffReleaseCondition=Move | 3 | skill 3400600 |
| crowd_control ausente | 2 | skill 9101100 -> 1010101 |
| BuffReleaseCondition=OnCCMoved | 1 | skill 3400600 |
| SummonRedzone (modo de jogo específico) | 1 | skill 3401601 |
| StatType=VehicleHasteRatio | 1 | skill 3401700 |
| TakeOnVehicle (modo de jogo específico) | 1 | skill 3401800 |
