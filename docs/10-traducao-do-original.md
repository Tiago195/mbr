# 10 — Tradução do original para o vocabulário próprio

> **Passo 4 de `05-extracao-dados-apk.md`, concluído em 22/08/2026.**
>
> As 948 habilidades de `skill_xml` e os 421 itens de `equipment_xml` estão
> traduzidos para o vocabulário de `03-sistemas-de-jogo.md`. Onde não coube, o
> vocabulário cresceu — e o que continua não cabendo está listado no fim, com
> o motivo.

## O que é isto, e o que não é

**É** um mapeamento: cada coluna das tabelas do original, lida uma vez, com a
decisão de para onde ela vai no nosso modelo — ou o registro de que não vai a
lugar nenhum e por quê.

**Não é** um clone. Os números do original são ponto de partida de
balanceamento e prova de que o vocabulário aguenta um jogo real. Arte, som,
código e texto continuam sendo da LINE/Meerkat e não entram no build
(`01-visao-e-escopo.md`). É por isso que o corpus traduzido não carrega nome
nem descrição do original: o `display_name` de cada entrada é o identificador
do ícone, em inglês, que é estrutura e não conteúdo.

## Como rodar

```
py tools/traducao/traduzir.py
```

Lê `C:\Godot\rc-referencia\xml` (fora deste repositório, de propósito) e
escreve em `data/traducao/`:

| Arquivo | O que é |
|---|---|
| `habilidades.json` | 1126 habilidades no nosso vocabulário |
| `itens.json` | 421 itens |
| `RELATORIO.md` | Cobertura e lacunas, **gerado — não editar** |

`AbilityCatalog` e `ItemCatalog` carregam esses arquivos e devolvem `Ability` e
`Item` de verdade. **A tradução é executável**: `tests/test_catalogo_traduzido.gd`
conjura as **964 que têm pulso** pela mesma `AbilityEngine` das habilidades
feitas à mão, e equipa e desequipa os 421 itens conferindo que nenhum
modificador fica para trás.

As outras 162 não são conjuráveis **por construção** — 115 são linha-modelo de
ranque 0, 2 são marcador de quebra de combo, e 45 caem em lacuna registrada. A
contagem de cada caso está no `RELATORIO.md`, e a tabela de cobertura mais
abaixo explica cada uma.

### Por que JSON e não 948 arquivos `.tres`

- `.tres` é o formato de quem edita à mão. Corpus gerado não se edita à mão —
  se editasse, a execução seguinte apagaria a edição.
- 1547 arquivos gerados afogariam o `git diff` de qualquer mudança futura no
  vocabulário. Em JSON, uma mudança de vocabulário é um diff legível.
- O JSON nomeia as **nossas** peças. Não é um despejo do original.

---

## O modelo do original, em uma passada

Foi a primeira surpresa útil: o original não guarda "uma habilidade" num lugar
só. Ele espalha em quatro tabelas, e a forma dessa divisão é boa.

```
Skill  (948)   ativação, mira, recarga, custo
  └─ Impact (1602)   uma região que aparece num lugar e num tempo
       ├─ ImpactStat*   o que ela faz com quem pegou
       ├─ Impact        outro impacto, com geometria e tempo PRÓPRIOS
       ├─ Buff (487)         atributo, escudo, periódico, marcador
       └─ CrowdControl (283)  atordoar, prender, arremessar, lentidão
```

Um `Impact` é exatamente o que passamos a chamar de **pulso**: forma, tempo,
âncora e alvos próprios. Uma `Skill` referencia até **doze** deles
(`Impact1`..`Impact12`), e cada impacto ainda pode **encadear** outro.

---

## O que cresceu, e por qual coluna

### Atributos: 18 → 44

Cada um entrou porque uma tabela do original **concede o valor**, e sem ele o
dado não é traduzível.

| Coluna do original | Vira | Observação |
|---|---|---|
| `PhysicalDamage`, `MagicalDamage` | `attack_damage`, `ability_power` | |
| `PhysicalDefense`, `MagicalDefense` | `armor`, `magic_resist` | |
| `HasteRatio`, `SlowRatio` | `move_speed` percentual | Mesmo atributo, sinais opostos |
| `SlowResist`, `Toughness` | `slow_resist`, `tenacity` | Resistências separadas: bota e elmo |
| `Agility`, `Accuracy`, `Flexibility` | `dodge`, `accuracy`, `crit_avoidance` | Esquiva de verdade, com `missed` no resultado |
| `MaxMP`, `MPRegen` | `max_mana`, `mana_regen` | Recurso de conjuração |
| `PhysicalDamageAmp` | `physical_damage_amp` | Multiplica **depois** da defesa |
| `HealAmp` × `ReceivedHealAmp` | `heal_power` × `heal_received_amp` | Dois lados, e é o que permite "cura reduzida" |
| `MaxCDReductionRatio` | `cooldown_reduction_cap` | O teto virou atributo, e agora um item pode elevá-lo |
| `Weight` | `weight` | Resiste a empurrão sofrido, não ao próprio dash |
| `AllDamageReduce` | `damage_taken_reduction` | Única mitigação que alcança dano verdadeiro |
| `SightRange`, `MaxGroggyHp` | `sight_range`, `max_stagger` | **Inertes**: existem para o item ser traduzível, sem consumidor ainda |

**Não viraram atributo, de propósito:**

- `PhysicalDefenseReduce` — é debuff no alvo, não penetração do atacante.
  Vira armadura **negativa**, que a fórmula de dano já sabe tratar.
- `MaxShield` e as variantes `MaxShieldPer...` — são o tamanho de um escudo
  concedido, não um atributo. Viram um `ShieldEffect`, com as `Per...` como
  escalonamento dele. Emitir dois escudos daria duas camadas onde havia uma.
- `BasePhysicalDamageAmp` — amplifica o atributo base, o que no nosso modelo é
  literalmente um modificador percentual do atributo.

### Controle de grupo: 4 → 10 estados

Duas contagens, porque são duas listas e elas não têm o mesmo tamanho:

- **`StatusSet.Kind`** — os estados de verdade que um combatente carrega:
  **4 → 10**.
- **`CrowdControlEffect.Kind`** — o que uma habilidade pode declarar: **5 → 11**.
  Tem um a mais porque `SLOW` é declarável mas não é estado — vira modificador
  de `move_speed`.

`crowd_control_xml` tem 13 tipos. Doze deles viram **9** dos nossos, e o
décimo terceiro (`KnockBack`) não vira estado nenhum — é empurrão puro. O
critério é **comportamento, não tema**:

| Original | Nosso | Por quê |
|---|---|---|
| `Stun`, `HardStun`, `Freeze` | `STUN` | Os três travam tudo. `HardStun` vira `ignores_tenacity` |
| `ThrowUp`, `Airborne` | `AIRBORNE` | Mesmo arremesso. Estado próprio porque tenacidade não o encurta e a camada visual precisa distingui-lo |
| `KnockBack` | *(nenhum)* | Empurrão puro: só deslocamento, nenhum estado |
| `Slow` | `SLOW` | Modificador de `move_speed`, não estado |
| `Root`, `Silence`, `Blind`, `Charmed`, `Taunt`, `Polymorph` | idem | |

Espelhar os 13 daria **cinco** caminhos diferentes para o mesmo
`can_move() == false` — `Stun`, `HardStun`, `Freeze`, `ThrowUp` e `Airborne` —
e cada regra de interação teria que lembrar dos cinco.

Junto vieram as regras: cegueira deixa atacar **e errar** (diferente de
desarmar), provocação deixa atacar (é o que a torna perigosa), transformação
deixa andar. `has_agency()` diz quando a ordem de quem joga deixou de valer.

### Efeitos: 6 → 14

Os dois primeiros já estavam prometidos em `03-sistemas-de-jogo.md` e não
existiam:

| Efeito | Nasceu de | O que fecha |
|---|---|---|
| `PeriodicEffect` | `LoopInterval` + buff com `Impact` | Veneno, regeneração, aura. **Embrulha** outros efeitos: um periódico de dano é veneno, de cura é regeneração |
| `TriggerEffect` | `TriggerTiming` + `BuffReleaseCondition` | Passiva de campeão. "Ao acertar três vezes, ganha escudo" |
| `SummonEffect` | `SummonActorId` | Lobo, totem, armadilha, parede |
| `ExecuteEffect` | `Die` | Mata na hora. Não é dano grande: escudo absorveria e resistência reduziria |
| `ResourceEffect` | `Mana` | Devolve e queima recurso |
| `CleanseEffect` | `Release_Effects_Id` | Purificação e dissipação hostil |
| `MarkEffect` | Buff só com `Line` e `Rank` | **Marcador**: estado sem efeito próprio. 114 buffs do original caem nesse caso — 62 deles têm literalmente só `Line`, `Rank` e `Duration` — e o corpus acaba com 30 marcas distintas |
| `CooldownEffect` | `AdjustCDSkillIds` | Acertar X reduz a recarga de Y. **21 buffs** o declaram, e o efeito sai mais vezes que isso porque esses buffs são referenciados por várias habilidades — a contagem exata está no `RELATORIO.md`, que é gerado |

Mais um valor de controle que faltava: **`INVULNERABLE`**. Ele existia em
`StatusSet` e **não** em `CrowdControlEffect`, então o corpus o emitia, a
fábrica não reconhecia e caía no padrão — "fica invulnerável 1,6 s" virava
"fica atordoado 1,6 s", no próprio conjurador. Achado na revalidação, e a
lição virou regra: **valor de enum não reconhecido é contado e falha teste**,
nunca cai no padrão calado.

Mais campos nos que já existiam: `percent_of_target_max_health` e
`monster_damage_cap` (e o teto contra mob **precisa** existir junto do dano
percentual, senão farmar selva vira o caminho mais rápido de escalar),
`restriction` (o `SiegeDamage`), `scaling_stat_alt` (`BetterAtkStat`, escala
pelo maior entre os dois ataques), `DisplacementEffect.TO_AIM_POINT` (`Warp`),
`drain_factor` (`DrainFactor`: nem toda habilidade devolve vida na mesma
proporção — 0 em 743 impactos, 0,3 em 735, 1 em 122) e
`pierces_invulnerability` (`IgnoreInvincibility`, 11 impactos: a resposta do
original a "invulnerabilidade sem exceção vira um botão de não perco esta
luta").

E no pulso: **deslocamento da âncora**. `StartPositionZ` é diferente de zero em
293 impactos e `StartPositionX` em 28 — é a explosão que nasce um pouco à
frente dos pés, e o golpe que sai da mão direita.

### Habilidade vira lista de pulsos

**A mudança estrutural.** Até aqui `Ability` tinha **uma** forma, **um** filtro
e **uma** lista de efeitos. Uma `Skill` do original referencia até doze
`Impact`, cada um podendo encadear outros, e 416 das traduzidas viram mais de
um pulso.

Traduzir sem isso obrigaria a escolher entre descartar impactos ou fundi-los —
e fundir está errado: o segundo golpe sai meio segundo depois, num raio menor,
e só pega quem ficou.

O caso que convence, direto do corpus:

```
skill_bella_multishot [direction]
  +0.30s [projectile] dano 40 + 50% de attack_damage
  +0.60s [projectile] dano 40 + 50% de attack_damage
  +0.90s [projectile] dano 40 + 50% de attack_damage
  +1.20s [projectile] dano 40 + 50% de attack_damage
```

Quatro flechas, uma a cada 0,3 s. No modelo antigo isso seria uma flecha só
com o dano somado — outra habilidade.

Decisões que vieram junto:

- **A âncora é congelada na conjuração.** Um pulso atrasado que recalculasse a
  posição faria a explosão perseguir quem já saiu de perto, e área no chão não
  persegue ninguém.
- **`Origin.PREVIOUS`** é o `ParentImpactPosition`: "explode onde a flecha
  parou", sem a habilidade precisar saber onde ela parou.
- **Interromper não cancela o que já saiu.** A bomba no ar não volta para a mão.
- **Ranque é recurso próprio, não multiplicador.** O original guarda os cinco
  ranques como cinco linhas de `skill_xml` com o mesmo `SkillGroupID` — ou
  seja, ranque é *outro conjunto de números*, não uma escala em cima. Copiamos.

### Leque de projéteis

`CastDirection_Count` + `CastDirection_Angle`: sete habilidades do original
disparam **três ou cinco projéteis abertos em leque** — três a 20 graus, cinco
a 7. O tradutor lia só a largura e emitia um projétil; os outros sumiam.

Virou `AbilityPulse.spread_count` e `spread_angle`, e `AbilityShape` testa cada
direção do leque. Acertar em uma basta: três flechas não somam dano em quem
está no meio.

**Como isso escapou:** a chave vive dentro de `UI_Params`, que é *uma* coluna
com vários pares `chave=valor` dentro. O censo de colunas a dava por consultada
e ficava cego para o conteúdo. Agora há um censo das **chaves** também.

**E a primeira tradução dele estava errada.** O leque da Violet já vinha nos
impactos: três deles com `Angle` −18, 0 e +18. Aplicar `spread_count` por cima
dava **nove** direções onde havia três. Hoje o `Angle` vira
`AbilityPulse.direction_offset` — o outro jeito de fazer leque, com N pulsos
angulados em vez de uma forma que abre em N — e o `spread` só entra quando os
impactos NÃO trazem ângulo. Das sete habilidades, seis são anguladas e uma
(cinco projéteis a 7 graus) usa mesmo o `Count`.

### O arremesso que não arremessava

`ThrowUp` e `Airborne` são os **únicos** dos 13 tipos de controle do original
com `Duration = 0` — nas 58 linhas, sem exceção. O tempo de ar não mora ali:
mora em `MaxHeight` (20 linhas) e numa curva de subida (`YMoveCurvePath`, 38)
que não está no XML.

O tradutor copiava o zero literalmente. E `StatusSet.apply` descarta duração
não positiva, então **121 arremessos do corpus não faziam nada** — 39 famílias
de habilidade, incluindo o kit inteiro de vários campeões. O relatório contava
os 121 como cobertura, e este documento afirmava o contrário.

Hoje: onde há `MaxHeight`, o tempo sai da balística — subir e cair de uma
altura `h` leva `2·√(2h/g)`, o que dá 0,90 s para altura 1 e 2,02 s para altura
5. Onde não há, entra um padrão de 0,9 s, **registrado como número inventado**.

E entrou uma guarda contra a classe: controle que sairia com duração não
positiva não é emitido, vira lacuna. Emitir um efeito que o motor descarta é
pior que não emitir — anuncia cobertura que não existe.

### `TargetAlly(11)` não é aliado

O ataque básico do original declara `TargetAlly(11), TargetEnemy(1,2,3,5,10,11)`.
Lendo só o nome do lado, isso vira "acerta aliado" — e 76 pulsos de ataque
básico saíam ferindo o próprio time.

A espécie 11 aparece dos **dois** lados, e cura de verdade usa `Ally(1,2)`. Ou
seja: 11 não é campeão. O filtro passou a olhar a lista de espécies, e só
considera aliado quando ela inclui 1 ou 2.

Sobraram 20 pulsos que ferem aliado — e esses são reais: declaram
`Ally(1,2,...)` junto de `Enemy(...)`, habilidades que pegam os dois lados de
propósito.

### Geometria inventada, e por que ela é contada

O colisor de verdade do original vive em `ColliderPath`, um prefab que **não
está no XML**. Então há casos em que o número tem que ser inventado — largura
de projétil sem `Radius`, alcance de linha sem `AI_SkillRange`.

Inventar é aceitável; inventar calado não é. O relatório conta cada um por
categoria, e hoje são 178 — 139 larguras de projétil, 25 larguras de linha, 9
alcances e 5 velocidades.

Foi assim que se descobriu que 195 pulsos saíam com largura **contradizendo** o
XML: o ramo do projétil calculava `Radius × 2` e caía num 2,0 fabricado, quando
`CastDirection_Width` — a mesma chave que o ramo da linha já lia — dizia 1,0 ou
1,4 ali do lado.

### Forma nova: `TRAPEZOID`

`CastTrapezoid`: um retângulo que começa a uma distância mínima e alarga com o
alcance. A diferença para o cone é o buraco colado nos pés — e é ela que
caracteriza o tiro de longo alcance.

### `Unit.Nature`

`MaxPhysicalDamageForMonster`, `SiegeDamage` e "invocação morta não conta como
abate" dependem de **que espécie** é o alvo, não de que time. Daí
`CHAMPION`, `MONSTER`, `STRUCTURE`, `SUMMON`.

---

## Cobertura

Números da última execução (o `RELATORIO.md` gerado tem o detalhe):

| | |
|---|---|
| Habilidades traduzidas | **1126** — as 948 de `skill_xml` + 178 das tabelas de continuação |
| ...com pelo menos um pulso | 964 |
| ...com mais de um pulso | 416 |
| Pulsos | 1687 |
| Efeitos | 3229 |
| Itens | **421**, em 257 linhas de melhoria |

Das 162 sem pulso:

- **115 são linha-modelo** (`Rank 0`): a entrada de interface da habilidade
  ainda não aprendida. Não referencia impacto **por definição**.
- **2 são quebra de combo**: marcador que cancela uma corrente. Não ter efeito
  é o efeito.
- **45 não têm tradução**, e todas caem nas lacunas abaixo.

---

## O censo de colunas — como sabemos que não estamos perdendo nada

A lista de lacunas abaixo tem um limite que não é óbvio: **ela só sabe do que o
tradutor tentou mapear.** Uma coluna que o código nunca menciona não gera
lacuna nenhuma — ela some, e a ausência fica indistinguível de uma decisão.

Foi exatamente o que aconteceu na primeira versão: `Impact9`..`Impact12`,
`CastingTime`, `RemoveCC`, `ApplyToughness`, `DrainFactor` e mais uma dúzia de
colunas eram perdidas sem aparecer em lugar nenhum. Só a revalidação
adversarial pegou.

O conserto foi estrutural: o tradutor mantém duas listas explícitas —
`CONSULTADAS` (o que ele lê) e `IGNORADAS` (o que ele decide não ler, **com o
motivo**) — e o relatório varre as seis tabelas do original atrás de colunas
que não estejam em nenhuma das duas.

**Hoje o censo sai vazio** — e essa frase já foi falsa uma vez. A primeira
versão a escreveu enquanto o relatório do mesmo commit listava 40 linhas de
`skill.StatType1`, que eram bônus passivos por ranque de verdade. A segunda
revalidação pegou, e agora elas são lidas: viraram `Ability.passive_effects`.

O censo cobre as **seis** tabelas que o tradutor abre — `skill`, `impact`,
`buff`, `crowd_control`, `equipment` e `craft_recipe`. A de receitas ficou de
fora na primeira versão, e ficar de fora do censo é exatamente o buraco que o
censo existe para tapar.

Toda coluna dessas seis ou é lida, ou está declarada com uma justificativa
verificável — "valor único `Release`", "0 em todas as 383 linhas", "som",
"texto localizado", "lacuna registrada".

Isso é o que transforma "traduzimos tudo" de afirmação em medição — e é o que
faz a próxima coluna que aparecer numa tabela nova gritar em vez de sumir.

### `TriggerTiming` — a tabela que faltava

`trigger_set.gd` prometia esta tabela e ela não existia. São **22 valores
atômicos** nas quatro tabelas de impacto — a primeira versão desta seção dizia
18, contando errado, e a revalidação pegou. A contagem entre parênteses é de
impactos que usam cada um:

| Original | Nosso `TriggerSet.Event` | Observação |
|---|---|---|
| `Start` (1600) | *(nenhum)* | Ausência de gatilho: sai junto com a habilidade |
| `MaxStack` (27) | `MARK_MAXED` | O que fez `MarkSet` existir |
| `DoAttackDamage` (78) | `BASIC_ATTACK_HIT` | |
| `DoSkillDamage` (36), `DoSkillDamageOnce` (1) | `ABILITY_HIT` | A variante "uma vez só" ainda não distingue |
| `OnHitDamage` (5) | `DAMAGE_TAKEN` | |
| `Expire` (6) | `EXPIRED` | |
| `ActivateActiveSkill` (11) | `ABILITY_CAST` | |
| `Arrived` (141), `ImpactFinish` (67) | *(aproximado)* | Momento de voo do projétil. No caminho de buff é lacuna; no caminho de pulso, o `delay` e a velocidade do projétil aproximam — e **está registrado como aproximação**, não como equivalência |
| `OnEvasion` (6), `DoCriticalDamage` (4), `OnCrowdControl` (3) | *(lacuna)* | Eventos de combate que `core/` não emite |
| `InCombat` (5), `OutCombat` (6) | *(lacuna)* | Não há estado de combate |
| `OnHitWall` (7), `OnHitActorObject` (7) | *(lacuna)* | Não há colisão com cenário em `core/` |
| `DoDropOut` (3), `DoKillMonster` (1) | *(lacuna)* | |
| `ActivateActiveSkillByMoving` (6), `ActivateActiveSkillByHaste` (6) | *(lacuna)* | Conjurar em movimento ou acelerado |
| `InteractionComplete(3000400)` (1) | *(lacuna)* | Interação com objeto específico do cenário |

## Lacunas — o que o original diz e nós ainda não

Estas são o produto mais valioso do Passo 4. Cada uma é um sistema que o
original tem e nós não, achado por medição em vez de por memória.

### Valem a pena, e ainda não existem

| Lacuna | Onde aparece | O que é |
|---|---|---|
| **Carga de suprema** | `UltimateCharge`, 534 habilidades | A suprema não tem recarga: enche batendo e apanhando. Muda o ritmo da partida inteira, e é a lacuna mais cara da lista |
| **Corrente de combo** | `ComboSkillInfo`, 125 | Conjurar A dentro de uma janela troca A por B. É boa parte do que dava textura ao corpo a corpo do original |
| **Janelas de cancelamento** | `MoveCancelableTime` e três irmãs, 72 | Nós temos um booleano `cancelable`. O original tem quatro instantes por habilidade: quando dá para andar, quando dá para conjurar outra, quando dá para atacar. É onde mora o "feel" |
| **Corrente entre dois alvos** | `Link`, 47 | Amarra dois combatentes e rompe na distância |
| **Troca de habilidade no espaço** | `UseSkillSlot`, 27 | Postura que reescreve o que Q e W fazem |
| **Amplificação por habilidade** | `PhysicalDamageAmp_SkillE`, 21 | "+20% no dano do seu E". Exige modificador por habilidade, e hoje só temos por atributo |

### Achadas na segunda revalidação

Estas estavam em `IGNORADAS` do tradutor com um rótulo curto — "cadência de
ataque", "condição de parada do dash" — que soava a decisão e escondia sistema.
Rótulo curto não é justificativa.

| Lacuna | Onde | O que é |
|---|---|---|
| **Área que acompanha o alvo** | `FollowTarget`, 1967 | Nossa área fica onde caiu, sempre. A do original pode grudar em quem foi atingido |
| **Arbusto atacável** | `BeAbleToAttackBush`, 1523 | Não há sistema de arbusto |
| **Reset de auto-ataque** | `ResetAttackCoolTime`, 521 | A habilidade que zera a cadência do ataque básico. É mecânica central de MOBA, e ela sozinha muda a ordem de botões de um kit inteiro |
| **Projétil teleguiado** | `TrackingMode`, 118 | O nosso vai reto |
| **Investida que para ao acertar** | `StopCondition`, 100 | O nosso dash sempre completa a distância. `OnImpactEnemy` faz ele travar no primeiro alvo, que é outra habilidade |
| **Gancho que arrebenta na distância** | `LimitSourceDistance`, 17 | Parente do `Link` |

### Precisam de sistema que não é de combate

| Lacuna | Onde | Por que fica fora |
|---|---|---|
| Curva de deslocamento | `MoveCurve`, 154 | Trajetória de dash como curva editada. É camada visual, e depende de asset |
| `BuffReleaseCondition` de animação | `SkillFinish` 41, `InteractionStart` 16, `OnStartSkill` 4, `Move` 3, `OnCCMoved` 1 — **65** | Dependem de eventos que `core/` não emite. `ShieldExhaust` e `SkillActivated` **foram fechados** — viraram `TriggerEffect` + `CleanseEffect` |
| Valor de poção | `RecoverDataType`, 43 | Os números vivem no texto localizado, que não extraímos. Melhor uma lacuna honesta que um valor inventado |
| Ping | `PingList`, 22 | Interface, não combate |
| Veículo e zona vermelha | 3 | Modo de jogo específico |

### Assunções registradas

Onde o original não documenta e a escolha foi nossa:

- **Direção do empurrão.** `crowd_control_xml` tem `Direction` com quatro
  valores e nenhuma explicação de eixo. Assumimos `Backward` = puxa, o resto
  empurra. Se estiver invertido, o conserto é uma linha e vale para as 20
  entradas de uma vez.
- **`cast_time` vem de `CastingTime`, quando existe.** A afirmação anterior
  aqui — "o original não trava a conjuração" — estava **errada**, e foi
  corrigida na revalidação: existe uma coluna `CastingTime` com valor em 61
  habilidades, de 0,3 a 5 segundos, e o tradutor a ignorava. Agora ela é lida.
  O que continua verdadeiro é que a **maioria** não trava: essas usam a
  animação com janelas de cancelamento, e o timing do golpe vem do `StartTime`
  de cada impacto, que virou o `delay` do pulso.
- **`ActiveDuration` só vira duração de área quando há laço.** Sem laço ela é o
  tempo que o colisor fica ligado, que para nós é instantâneo.
- **Impacto listado duas vezes sai uma vez.** 16 habilidades citam um impacto
  em `ImpactN` **e** o encadeiam a partir de outro. A leitura adotada é que
  isso é redundância da tabela, não intenção de bater duas vezes — vale a
  primeira ocorrência. Se estiver errado, o dano dessas 16 está pela metade, e
  a contagem no `RELATORIO.md` é o fio para puxar.
- **`SourceType` do controle é simplificado.** A coluna diz se o empurrão
  irradia do ponto de impacto (157 linhas) ou do conjurador (113). Nós sempre
  empurramos para longe do conjurador. Para arremesso e empurrão de área a
  diferença é pequena; para um impacto que explode longe do conjurador, não é.

---

## Cinco bugs do tradutor que valeram a lição

Todos silenciosos. Os dois primeiros vieram do relatório de cobertura; os três
seguintes, de revalidação adversarial — um segundo par de olhos com a instrução
explícita de tentar reprovar o trabalho.

1. **Invocação lida dentro do laço de colunas.** Um impacto que *só* invoca não
   tem `ImpactStatType` nenhum, então o laço nunca rodava e a invocação nunca
   saía. 61 impactos traduziam para vazio. A leitura foi para fora do laço.
2. **Limite de profundidade em vez de guarda de ciclo.** Buff que aponta para
   impacto que aponta para buff é comum e legítimo no original. Cortar em
   profundidade 3 descartava 66 habilidades inteiras. Virou conjunto de
   visitados, que é o correto: o que não pode é voltar ao mesmo nó.

3. **`Impact9`..`Impact12` nunca eram lidos.** O laço parava em 8 porque oito
   parecia bastante. Oito habilidades perdiam treze impactos inteiros, com dano
   e cura de verdade — e sem virar lacuna, porque o laço nem chegava a olhar a
   coluna.
4. **Impacto encadeado era fundido no pai.** O filho de `ImpactStatType: Impact`
   tem `StartTime`, `Radius` e `StartPosition` próprios, e 300 das 320
   referências diferem do pai em pelo menos um. Fundir descartava a geometria —
   o mesmo erro que a estrutura de pulsos existe para não cometer, cometido 300
   vezes dentro dela. Agora o filho vira pulso próprio, e é por isso que
   `Origin.PREVIOUS` finalmente aparece no corpus.
5. **`ApplyToughness` era inferido em vez de lido.** A coluna diz literalmente
   se a tenacidade se aplica, e o tradutor usava um palpite que discordava do
   dado em quatro entradas. Palpite perde para coluna quando a coluna existe.

A lição vale além do tradutor: **cobertura silenciosa é indistinguível de
cobertura errada.** O relatório existe por isso, o censo de colunas existe por
isso, e o contador de valores desconhecidos da `EffectFactory` existe por isso.
Juntos, eles transformam "1126 habilidades traduzidas" de afirmação em medição.
