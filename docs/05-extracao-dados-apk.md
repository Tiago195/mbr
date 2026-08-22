# 05 — Extração dos dados de design do jogo original

> **EXTRAÇÃO CONCLUÍDA em 22/08/2026.** As 113 tabelas de design do original
> estão decifradas em `C:\Godot\rc-referencia\xml\` — **fora deste
> repositório**, de propósito.
>
> Pule para a seção **"Passo 0 — o que a sondagem encontrou"**, no fim deste
> documento: ela tem a chave da cifra, o inventário das tabelas e o que os
> dados revelaram. O texto antes dela é o plano original, mantido por
> contexto — várias suposições dele foram confirmadas e uma estava errada.
>
> **O Passo 4 também está concluído** (22/08/2026): as 948 habilidades e os
> 421 itens estão traduzidos para o vocabulário de `03-sistemas-de-jogo.md`,
> e o vocabulário cresceu onde precisou. O mapeamento coluna a coluna, o que
> cresceu e as lacunas que sobraram estão em **`10-traducao-do-original.md`**.

## Por que isso existe

O jogo fechou em 2022. Mesmo lembrando bem do original, descrever de memória
todos os kits, números e curvas para reconstruir o design deixaria buracos por
todo lado.

**A boa notícia: em jogo Unity, boa parte do design está armazenada como dado,
não como código.** Balanceamento, stats de personagem, tabela de loot, curva de
XP, receitas de crafting — isso normalmente vive em ScriptableObjects, CSV ou
JSON, justamente porque o time de design precisava editar sem recompilar.

Ou seja: não depende de memória nem de engenharia reversa pesada.

## Enquadramento

Isto é **referência de estudo**. Os assets e dados continuam sendo propriedade
da LINE/Meerkat. Servem para entender o design e ter ponto de partida numérico
— **não vão junto no build**.

---

## O que sai limpo dos arquivos

### Tabelas de balanceamento

Procurar primeiro em:
- Build Steam: `RoyalCrown_Data/StreamingAssets/`
- APK: `assets/bin/Data/`

Muita coisa costuma estar ali como texto puro — às vezes só compactado ou com
XOR simples. Depois disso, `resources.assets` e os bundles de Addressables, que
exigem ferramenta.

### Localização — o achado mais subestimado

O arquivo de strings tem as descrições de **todas** as habilidades, itens e
passivas, **com os placeholders de fórmula** (`{0}% de AP`, escalonamento por
nível).

Só a tabela de localização reconstrói os kits dos ~15 personagens quase
inteiros.

### Animações

Os `.anim` saem com duração real, curvas e eventos. Dá para ler **cast time,
recovery e timing de impacto** — exatamente o "feel" que não se descreve de
memória.

### Prefabs de UI e mapa

Layout de HUD, hierarquia de telas, geometria e spawns do mapa como cena
navegável.

---

## O que NÃO sai

Lógica de comportamento continua em binário:
- A fórmula de dano final
- A máquina de estado da IA dos mobs
- O algoritmo da zona

Você terá os **parâmetros**, mas não necessariamente como são combinados.

Na prática isso importa pouco: com os números em mãos, define-se a própria
fórmula. Este é um jogo novo.

---

## Toolchain

### AssetRipper — o principal

Reconstrói um projeto Unity abrível no editor, com os ScriptableObjects
**desserializados e nomes de campo preservados**, mesmo em builds IL2CPP (roda
Cpp2IL internamente para recuperar os tipos).

Essa é a diferença entre ver `damageBase: 65, apRatio: 0.45` e ver um blob
binário.

### Complementos

| Ferramenta | Uso |
|---|---|
| **AssetStudio** | Varredura rápida; export de meshes, texturas, animações |
| **UABEA** | Abrir asset bundles individuais no braço |
| **Il2CppDumper** | Recuperar nomes e assinaturas de classes (não os corpos) |

### Mono vs IL2CPP

Fator que muda o esforço:
- **Mono** (raro em mobile, possível no build Steam): os `.dll` em `Managed/`
  abrem no ILSpy/dnSpy e dá C# praticamente legível
- **IL2CPP** (o provável): recupera-se estrutura e nomes, mas os corpos dos
  métodos são assembly no Ghidra

---

## Processo recomendado

### Passo 0 — sondagem (uma tarde)

Extrair **apenas** o arquivo de localização e o conteúdo de `StreamingAssets`.

Isso responde a pergunta que define o tamanho de todo o resto: **o jogo guardava
as tabelas em texto, ou vai precisar do AssetRipper completo?**

Não pule esta etapa. Ela custa uma tarde e pode economizar semanas.

### Passo 1 — extração completa

AssetRipper sobre o build. Resultado: milhares de arquivos.

### Passo 2 — inventário

O gargalo aqui não é conceitual, é **volume**: milhares de arquivos JSON/YAML
com nomes de campo coreanos ou abreviados, espalhados sem documentação.

Tarefa para o Claude Code:
1. Inventariar os tipos presentes
2. Escrever parsers que varrem e normalizam
3. Consolidar em tabelas legíveis
4. Cruzar localização × dados numéricos

### Passo 3 — interpretação

"Estes 15 arquivos são personagens, estes campos são escalonamento, esta curva é
XP por nível."

O design doc sai **dos dados**, com os números reais.

### Passo 4 — tradução para o vocabulário próprio ✅

**Concluído em 22/08/2026.** Mapear cada habilidade do original para o
vocabulário de efeitos definido em `03-sistemas-de-jogo.md`. Onde não couber,
o vocabulário precisa crescer — e isso é informação valiosa sobre o sistema.

Foi o que aconteceu: atributos de 18 para 44, controles de 4 para 10, efeitos
de 6 para 14, e `Ability` deixou de ter uma forma para ter uma lista de pulsos.
1126 habilidades e 421 itens em `data/traducao/`, carregáveis e conjuráveis.

**O detalhe todo está em `10-traducao-do-original.md`.** Inclusive as lacunas,
que são o produto mais valioso: carga de suprema, corrente de combo e janelas
de cancelamento são sistemas que o original tem e nós não, achados por medição
em vez de por memória.

---

## O que sobra para a memória

Só a camada que não está em arquivo nenhum:

- Por que o jogo era gostoso
- O que funcionava e o que irritava
- Ritmo de partida, sensação de poder, momentos memoráveis

Que é justamente a parte que se lembra bem — e a parte que mais importa para
decidir o que copiar e o que mudar.

---

## Passo 0 — o que a sondagem encontrou (22/08/2026)

Build Steam `13.0.13`, Unity **2019.4.17f1**, **IL2CPP** (há `GameAssembly.dll`
de 35 MB e nenhuma pasta `Managed/` — então não existe C# legível, como o doc
previa).

### Os `.pak` são AssetBundles comuns

Os arquivos de `RoyalCrown_Data/StreamingAssets/` têm extensão `.pak` mas
começam com o magic **`UnityFS`**. São AssetBundles padrão, só renomeados.
Abrem com **UnityPy** sem nenhum trabalho de engenharia reversa.

`patch_data.json` está em texto puro e é o manifesto completo: nome, hash,
CRC, tamanho e dependências de cada bundle.

### O design inteiro está em `_xml.pak`

**115 TextAssets.** Os nomes já são um mapa dos sistemas de um BR/MOBA que
chegou a shipar:

| Área | Tabelas |
|---|---|
| Habilidades | `skill_xml` (1,4 MB), `skill_2_xml`, `impact_xml` (2,1 MB), `impact_2_xml`, `effect_xml`, `buff_xml`, `crowd_control_xml` |
| Personagens | `actor_xml`, `actor_2_xml`, `actorattribute_xml`, `champion_level_xml`, `ingamelevel_xml` |
| Itens e loot | `equipment_xml`, `item_xml`, `usable_xml`, `drop_table_xml`, `drop_group_xml`, `lootpreset_xml`, `craft_recipe_xml`, `craft_xml`, `forge_craft_xml` |
| Partida | **`magnetic_field_xml`** (a zona), `redzone_xml`, `supply_xml`, `resurrection_xml`, `matchrule_xml`, `GameMode_xml`, `gamemodemodifier_xml` |
| Mapa | `map_xml`, `AreaClassification_xml`, `warp_xml`, `MapIcon_xml`, `vehicle_xml` |
| Mobs e IA | `ai_player_xml`, `ai_preset_xml`, `ai_drop_table_xml`, `goblin_xml`, `Merchant_xml` |
| Progressão | `user_level_xml`, `const_xml`, `Professions_xml`, `rank_tier` |

**Mesmo sem decifrar, essa lista tem valor:** ela diz quais sistemas
existiram e como o time original os separou.

### A cifra — RESOLVIDA

```
algoritmo : DES-CBC      (bloco de 8 bytes)
chave     : 5d0b249faa9fd875
IV        : e950d93408855ed3
```

A chave estava como bloco de bytes crus no `global-metadata.dat`, offset
10231585 — não como string, por isso a varredura de strings não a achou.

O IV se recupera de texto conhecido: o primeiro bloco claro é BOM de UTF-8
seguido de `<?xml`, então `IV = D(cifra₁) XOR texto₁`.

**113 das 115 tabelas extraídas** para `C:\Godot\rc-referencia\xml\`.
Não decifraram: `metafile_keeper` (2 bytes, não cifrado) e `chat_abuse`
(outro formato).

Para reextrair: venv com `UnityPy` e `pycryptodome`; abrir `_xml.pak` com
UnityPy, pegar os `TextAsset`, decifrar com DES-CBC, remover enchimento PKCS7.

> **O erro que custou uma hora, registrado para não se repetir.**
>
> A conclusão inicial foi "AES", tirada do prefixo comum de 48 bytes lido como
> 3 blocos de 16. Mas 48 também é 6 blocos de 8 — e o dado que decidia estava
> à vista desde a primeira medição: os tamanhos das tabelas são todos
> múltiplos de 8 e **metade não é múltipla de 16**, o que é impossível com
> bloco de 16.
>
> O nome da classe no metadata é `AESEncryptor`, e é pista falsa. Custou 177
> milhões de posições varridas procurando chave de 16, 24 e 32 bytes.
>
> Lição: medição que contradiz a hipótese não vira nota de rodapé.

### O que se sabia da cifra antes de resolver

| Observação | Medição | O que elimina |
|---|---|---|
| XOR de duas cifras tem 50% de bytes ≥ 0x80 | 4 pares testados | Não é cifra de fluxo |
| Prefixo idêntico entre arquivos | exatos **48 bytes** = 3 blocos | Chave e IV **fixos** |
| Blocos de 16 bytes repetidos num arquivo | **0** em 205.729 | Não é ECB — é **CBC** |
| O prefixo comum sobrevive | sim | **Não há compressão** antes de cifrar |

O metadata IL2CPP tem uma classe própria chamada **`AESEncryptor`**. Todo o
resto de material criptográfico ali é BouncyCastle, vindo do BestHTTP — ruído.

O teste que achou a chave dispensa conhecer o IV: em CBC,
`texto₂ = D(cifra₂) XOR cifra₁`, e `cifra₁` está no arquivo. Com bloco de 8
bytes, verificar um bloco só dá 1 falso positivo a cada ~2.500 — inútil. Mas
o prefixo comum de 48 bytes dá **cinco** blocos conhecidos, e exigir os 40
bytes imprimíveis derruba o falso positivo para ~10⁻¹⁷: zero ruído.

---

## O que as tabelas revelaram

### A zona (`magnetic_field_xml`) — 9 fases

| Fase | Raio | Espera | Encolhe |
|---|---|---|---|
| 1 | 380 → 290 | 190s | 60s |
| 2 | 290 → 215 | 140s | 50s |
| 3 | 215 → 160 | 100s | 40s |
| 4 | 160 → 120 | 70s | 50s |
| 5 | 120 → 80 | 50s | 35s |
| 6 | 80 → 55 | 40s | 20s |
| 7 | 55 → 35 | 40s | 20s |
| 8 | 35 → 22 | 40s | 15s |

A estrutura bate com `scripts/core/match/zone.gd`: `DurationTime` é o tempo de
aviso, `DecreaseTime` é o de encolhimento. **Duas coisas o original faz
melhor:**

- **`Buffid` em vez de dano solto.** O dano da zona é um buff, reusando o
  vocabulário de efeitos. É o princípio que `03-sistemas-de-jogo.md` prega e
  que a nossa `Zone` ainda não segue — ela tem `damage_per_second` direto.
- **`CenterPointLogic: RandomInside`.** O próximo centro é sorteado dentro do
  círculo atual, não predefinido. É o que faz cada partida ser diferente.

Campos extras: `BonusExp` por fase (XP escala conforme a partida avança),
`AISurvivalRate`, `StatueInteractionTime`.

### Atributos (`actorattribute_xml`) — 66 contra os nossos 18

Vários apontam sistemas inteiros que não estavam no radar:

| Atributo | Sistema que implica |
|---|---|
| `MP`, `MaxMP`, `MPRegen` | Recurso de conjuração — o roadmap dizia "custo, se houver" |
| `GroggyHp`, `MaxGroggyHp` | Atordoamento por acúmulo |
| `SightRange` | Névoa de guerra (há um `_fogofwar.pak`) |
| `Accuracy`, `Agility`, `Flexibility` | Acerto e esquiva |
| `QSkillLevel`, `WSkillLevel`, `ESkillLevel` | Nível por habilidade |
| `WoodWorkSkillCDReduction`, `AlchemySkillCDReduction` | Profissões |
| `Toughness`, `SlowResist`, `HasteRatio` | Resistência a controle |
| `MaxShieldPerPhysicalDamage`, `DamageAmpPerDistance` | Atributos derivados |

### Habilidades (`skill_xml`) — 948

Campos de timing que o próprio doc dizia não se descrever de memória:
`CoolTime`, `Duration`, `AimDuration`, `MoveCancelableTime`,
`SkillCancelableTime`, `CancelForbidStartTime/EndTime`,
`ComboSkillInfo_SkillID/StartTime/LimitTime`.

`TargetType` vem no formato `TargetAlly(11), TargetEnemy(1,2,3,5,10,11)` — um
sistema de camadas de alvo mais fino que o nosso filtro de três booleanos.

### Personagens (`actor_xml` + `actor_2_xml`) — 116 registros

`DefaultSkillId_1..4`, `UltimateSkill`, `PassiveBuffs`, e pares
`StatType_N`/`StatValue_N`. É exatamente o modelo "personagem = kit +
atributos" que já adotamos.

### Itens (`equipment_xml`) — 421

`StatType_N`/`StatValue_N`, `MaxStackCount`, `Socket`, `Rarity`,
`DropCount` — valida o modelo de `scripts/core/items/item.gd`.

### Outras de interesse imediato

`impact_xml` (2 MB) e `effect_xml` são o vocabulário de efeitos deles.
`drop_table_xml` (696) e `lootpreset_xml` são o loot. `ai_preset_xml` é a IA
dos mobs. `ingamelevel_xml` é a progressão dentro da partida.

### Correção ao que este documento supunha

O doc dizia para procurar as tabelas em `StreamingAssets` esperando "texto
puro, às vezes só compactado ou com XOR simples", e tratava `resources.assets`
e o AssetRipper como o passo seguinte e mais caro.

Na prática: os bundles abrem trivialmente e **o AssetRipper não é necessário
para os dados** — ele só faria falta para código. O obstáculo real não era o
empacotamento, era a cifra por cima do conteúdo, que o doc não previa.
