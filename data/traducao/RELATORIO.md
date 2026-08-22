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
| ...com pelo menos um pulso | 964 |
| ...com mais de um pulso | 416 |
| Pulsos gerados | 1687 |
| Efeitos gerados | 3229 |
| Itens traduzidos | **421** |

### As que saíram sem pulso

Uma habilidade sem pulso não é necessariamente uma tradução falha. Separar os três casos é o que permite saber se ainda falta trabalho.

| Caso | Quantas | O que é |
|---|---|---|
| Linha-modelo (`Rank 0`) | 115 | A entrada de interface da habilidade ainda não aprendida. Não referencia impacto **por definição** — os ranques 1 a 5 é que carregam os números. |
| Quebra de combo | 2 | Marcador que interrompe uma corrente de golpes. Não tem efeito porque cancelar é o efeito. |
| **Sem tradução** | **45** | Referencia impacto e nada saiu. São as lacunas da tabela abaixo — `Link`, `UseSkillSlot`, `ReleaseImpact` e as de modo de jogo. |

Ids sem tradução (amostra): 1016250, 1016251, 1016252, 1016253, 1016254, 1018301, 1018302, 1018303, 1018304, 1018305, 1019201, 1019202, 1019203, 1019204, 1019205, 1021850, 1021860, 1022350, 1023350, 1026251

## O que o vocabulário cobriu

| Peça | Vezes |
|---|---|
| `drain_factor` | 1972 |
| `acerto garantido (já é a nossa convenção)` | 1113 |
| `habilidade não critica (já é a nossa convenção)` | 949 |
| `damage:physical` | 906 |
| `damage:magic` | 821 |
| `stat:move_speed` | 498 |
| `tenacidade inferida (sem ApplyToughness)` | 329 |
| `impacto encadeado como pulso` | 320 |
| `receita de fabricação` | 299 |
| `mark` | 289 |
| `cc:SLOW` | 185 |
| `stat:armor` | 181 |
| `stat:magic_resist` | 173 |
| `summon` | 160 |
| `gatilho MARK_MAXED` | 146 |
| `heal` | 139 |
| `cc:STUN` | 136 |
| `shield` | 133 |
| `dissipa em SHIELD_BROKEN` | 130 |
| `cc:AIRBORNE` | 121 |
| `cooldown` | 104 |
| `periodic` | 98 |
| `stat:attack_speed` | 79 |
| `stat:attack_damage` | 79 |
| `stat:magic_damage_amp` | 73 |
| `stat:physical_damage_amp` | 71 |
| `stat:ability_power` | 71 |
| `gatilho BASIC_ATTACK_HIT` | 70 |
| `cast_time` | 61 |
| `damage:percent_hp` | 56 |
| `damage:monster_cap` | 55 |
| `aura como buff simples` | 55 |
| `resource` | 53 |
| `stat:cooldown_reduction` | 51 |
| `stat:max_health` | 45 |
| `passiva de ranque` | 40 |
| `impacto de buff, imediato` | 39 |
| `execute` | 37 |
| `heal:percent_hp` | 34 |
| `damage:siege` | 33 |
| `leque já vem angulado nos impactos` | 30 |
| `stat:out_of_combat_health_regen` | 28 |
| `stat:dodge` | 26 |
| `stat:crit_chance` | 26 |
| `stat:heal_received_amp` | 26 |
| `stat:mana_regen` | 23 |
| `stat:armor_pen_flat` | 22 |
| `raio de área vindo do retículo` | 21 |
| `cc:CHARM` | 21 |
| `stat:armor_pen_percent` | 19 |
| `stat:health_regen_amp` | 19 |
| `stat:magic_pen_flat` | 19 |
| `tempo de ar derivado da altura` | 18 |
| `displacement:cc` | 18 |
| `impacto repetido na habilidade, emitido uma vez` | 16 |
| `dissipa em ABILITY_CAST` | 15 |
| `displacement:teleporte` | 15 |
| `stat:lifesteal` | 15 |
| `stat:out_of_combat_mana_regen` | 14 |
| `stat:sight_range` | 13 |
| `stat:slow_resist` | 13 |
| `stat:max_mana` | 12 |
| `stat:tenacity` | 11 |
| `fura invulnerabilidade` | 11 |
| `stat:crit_damage` | 11 |
| `stat:health_regen` | 9 |
| `damage:hibrido` | 9 |
| `stat:spell_vamp` | 9 |
| `stat:magic_pen_percent` | 9 |
| `gatilho ABILITY_CAST` | 9 |
| `impacto dentro de controle` | 7 |
| `cleanse (RemoveCC)` | 7 |
| `stat:damage_taken_reduction` | 7 |
| `leque de projéteis` | 6 |
| `cc:ROOT` | 6 |
| `cc:INVULNERABLE` | 5 |
| `cc:BLIND` | 5 |
| `gatilho EXPIRED` | 5 |
| `cc:TAUNT` | 5 |
| `stat:item_cooldown_reduction` | 5 |
| `stat:cooldown_reduction_cap` | 5 |
| `stat:crit_avoidance` | 4 |
| `impacto encadeado` | 4 |
| `stat:heal_power` | 4 |
| `stat:weight` | 3 |
| `stat:shield_received_amp` | 3 |
| `gatilho DAMAGE_TAKEN` | 2 |
| `cc:SILENCE` | 1 |
| `cc:POLYMORPH` | 1 |
| `cleanse (RemoveDebuff)` | 1 |
| `gatilho ABILITY_HIT` | 1 |

## Censo de colunas — o que nunca foi olhado

A tabela de lacunas abaixo só sabe do que o tradutor **tentou** mapear. Uma coluna que o código nunca menciona não gera lacuna nenhuma — ela some, e a ausência fica indistinguível de uma decisão. Este censo varre as colunas presentes no XML e lista as que não estão nem em `CONSULTADAS` nem em `IGNORADAS`. Ele cobre **todas** as tabelas que o tradutor abre — inclusive a de receitas, que ficou de fora na primeira versão.

**Nenhuma.** Toda coluna das 6 tabelas que o tradutor lê (`buff`, `craft_recipe`, `crowd_control`, `equipment`, `impact`, `skill`) ou é consultada, ou está declarada em `IGNORADAS` com o motivo.

### Chaves de `UI_Params` sem leitura nem decisão

| Chave | Habilidades |
|---|---|
| `CastDirectionalSquareArea_Distance` | 6 |
| `CastDirectionalSquareArea_Width` | 6 |
| `CastDirection_Height` | 6 |
| `CastCurveDirection_Offset_X` | 6 |
| `CastCurveDirection_Width` | 6 |
| `CastSquare_Height` | 1 |
| `CastSquare_Width` | 1 |

## Lacunas — o que o original diz e nós ainda não

Cada linha é uma coluna do original que o tradutor encontrou e não soube converter. **Isto é informação sobre o sistema, não erro** — o critério para fechar uma lacuna é ela valer o sistema que exige, e várias abaixo não valem.

| Lacuna | Ocorrências | Exemplo |
|---|---|---|
| área que acompanha o alvo em vez de ficar no chão (`FollowTarget` em impact) | 1967 |  |
| arbusto que se pode atacar (não há arbusto) (`BeAbleToAttackBush` em impact) | 1523 |  |
| UltimateCharge (carga de suprema) | 534 | skill 1000000 |
| habilidade que zera a cadência do ataque básico (`ResetAttackCoolTime` em skill) | 521 |  |
| atravessar parede (não há sistema de obstáculo em core/) (`ThroughObstacle` em crowd_control) | 263 |  |
| ricochete para outro inimigo (`TargetCondition` em impact) | 181 |  |
| atravessar parede (não há sistema de obstáculo em core/) (`ThroughObstacle` em skill) | 167 |  |
| curva de deslocamento (MoveCurve) | 154 | skill 1000200 |
| TriggerTiming=Arrived no pulso (aproximado pelo atraso e pela velocidade do projétil) | 143 |  |
| geometria inventada: largura do projétil (o original guarda o colisor fora do XML) | 139 | skill 1000800 |
| ComboSkillInfo (corrente de combo) | 125 | skill 1000000 |
| projétil teleguiado (`TrackingMode` em skill) | 118 |  |
| tempo de ar do arremesso (o original guarda a subida numa curva fora do XML; usamos 0.9s) | 103 | skill 1000800 |
| a investida que PARA ao acertar (OnImpactEnemy / OnDamage / OnLostTarget) — nosso dash sempre completa (`StopCondition` em skill) | 100 |  |
| janela de cancelamento por tempo | 72 | skill 1000000 |
| TriggerTiming=ImpactFinish no pulso (aproximado pelo atraso e pela velocidade do projétil) | 71 |  |
| atravessar parede (não há sistema de obstáculo em core/) (`ThroughObstacle` em impact) | 56 |  |
| dash que persegue o alvo (`TrackDistanceForMovingSkill` em skill) | 53 |  |
| Link (corrente que liga dois alvos e rompe na distância) | 47 | skill 1003201 |
| BuffReleaseCondition=SkillFinish | 41 | skill 1001301 |
| UseSkillSlot (troca a habilidade de um espaço) | 27 | skill 1007351 |
| geometria inventada: largura da linha (o original guarda o colisor fora do XML) | 25 | skill 1001301 |
| modificador só deste golpe: DamageAmpPerDistance (temos modificador por personagem, não por golpe) | 25 | skill 1005101 |
| conjurar mesmo sob controle (`EnableSkillOnCC` em skill) | 24 |  |
| PingList (aviso na interface, não é combate) | 22 | skill 3001000 |
| StatType=PhysicalDamageAmp_SkillE | 21 | skill 1025101 |
| modificador só deste golpe: PhysicalPenetrationRatio (temos modificador por personagem, não por golpe) | 20 | skill 1005101 |
| RecoverDataType=RegenHealth sem valor legível (os números vivem no texto localizado) | 19 | equipment 5000000 |
| RecoverDataType=RegenAll sem valor legível (os números vivem no texto localizado) | 19 | equipment 7308001 |
| alcance do ricochete (`TargetRange` em impact) | 19 |  |
| o gancho que arrebenta quando estica demais (`LimitSourceDistance` em crowd_control) | 17 |  |
| BuffReleaseCondition=InteractionStart | 16 | skill 1003401 |
| habilidade que dispara um ataque básico ao terminar (`ReleaseAutoAttack` em skill) | 15 |  |
| TriggerTiming=OnHitWall no pulso (sem aproximação) | 10 |  |
| TriggerTiming=OnHitActorObject no pulso (sem aproximação) | 10 |  |
| geometria inventada: alcance do projétil (o original guarda o colisor fora do XML) | 9 | skill 1001201 |
| TriggerTiming=OnEvasion | 8 | skill 1014301 |
| RemoveCC só de Slow traduzido como purificação ampla | 6 | skill 1012200 |
| ReleaseImpact (cancela impacto em curso) | 6 | skill 1016250 |
| geometria inventada: velocidade do projétil (o original guarda o colisor fora do XML) | 5 | skill 1001201 |
| TriggerTiming=OnEvasion no pulso (sem aproximação) | 5 |  |
| modificador só deste golpe: PhysicalDrain (temos modificador por personagem, não por golpe) | 5 | skill 1025301 |
| RecoverDataType=RegenMana sem valor legível (os números vivem no texto localizado) | 5 | equipment 5000001 |
| por quanto tempo o dash persegue (`TrackPersistTime` em skill) | 5 |  |
| BuffReleaseCondition=OnStartSkill | 4 | skill 3301030 |
| TriggerTiming=DoCriticalDamage | 4 | equipment 1000507 |
| modificador só deste golpe: MagicalPenetrationRatio (temos modificador por personagem, não por golpe) | 3 | skill 3400400 |
| BuffReleaseCondition=Move | 3 | skill 3400600 |
| TriggerTiming=DoKillMonster | 3 | equipment 1001100 |
| TriggerTiming=OnCrowdControl | 3 | equipment 3100600 |
| TriggerTiming=DoDropOut | 3 | equipment 3101300 |
| TriggerTiming=ActivateActiveSkillByMoving | 3 | equipment 3101900 |
| TriggerTiming=ActivateActiveSkillByHaste | 3 | equipment 3101900 |
| modificador só deste golpe: MagicalDrain (temos modificador por personagem, não por golpe) | 2 | skill 1002800 |
| modificador só deste golpe: PhysicalDamagePerPhysicalDefense (temos modificador por personagem, não por golpe) | 2 | skill 1026000 |
| crowd_control ausente | 2 | skill 9101100 -> 1010101 |
| TriggerTiming=DoAttackDamage no pulso (sem aproximação) | 1 |  |
| TriggerTiming=DoSkillDamage no pulso (sem aproximação) | 1 |  |
| BuffReleaseCondition=OnCCMoved | 1 | skill 3400600 |
| SummonRedzone (modo de jogo específico) | 1 | skill 3401601 |
| StatType=VehicleHasteRatio | 1 | skill 3401700 |
| TakeOnVehicle (modo de jogo específico) | 1 | skill 3401800 |
| TriggerTiming=OutCombat | 1 | equipment 1060004 |
