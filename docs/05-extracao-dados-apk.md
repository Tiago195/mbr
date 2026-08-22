# 05 — Extração dos dados de design do jogo original

> **Sondagem realizada em 22/08/2026** sobre o build Steam instalado em
> `C:\Program Files (x86)\Steam\steamapps\common\Royal Crown`.
> O resultado está na seção "Passo 0 — o que a sondagem encontrou", no fim
> deste documento. Leia-a antes do resto: várias suposições daqui foram
> confirmadas, e uma foi superada.

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

### Passo 4 — tradução para o vocabulário próprio

Mapear cada habilidade do original para o vocabulário de efeitos definido em
`03-sistemas-de-jogo.md`. Onde não couber, o vocabulário precisa crescer — e
isso é informação valiosa sobre o sistema.

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

### As tabelas estão cifradas — o que já se sabe da cifra

| Observação | Medição | O que elimina |
|---|---|---|
| XOR de duas cifras tem 50% de bytes ≥ 0x80 | 4 pares testados | Não é cifra de fluxo |
| Prefixo idêntico entre arquivos | exatos **48 bytes** = 3 blocos | Chave e IV **fixos** |
| Blocos de 16 bytes repetidos num arquivo | **0** em 205.729 | Não é ECB — é **CBC** |
| O prefixo comum sobrevive | sim | **Não há compressão** antes de cifrar |

O metadata IL2CPP tem uma classe própria chamada **`AESEncryptor`**. Todo o
resto de material criptográfico ali é BouncyCastle, vindo do BestHTTP — ruído.

**Chave: ainda não encontrada.** Descartadas por teste direto:

- Todas as 160 mil strings do metadata, mais MD5 e SHA-256 de cada uma
  (297 mil candidatas, AES-ECB e AES-CBC)
- As candidatas de aparência óbvia: `9B65E372FCD68EF20FA7111F9E4AFF73`,
  `175c951fec709c44fa2f26b8ab78b8dd`, `499A234DCF76E3FED135F9BB`,
  `9FC61D2FC0EB06E3`

Em andamento: varredura de **bytes crus** do metadata e do `GameAssembly.dll`,
porque chave em C# se declara como `byte[] { ... }` e nesse caso não vira
string nenhuma.

O teste usado dispensa conhecer o IV: em CBC,
`texto₂ = AES_decifra(cifra₂) XOR cifra₁`, e `cifra₁` está no arquivo.

Se a varredura falhar, sobra ler o `AESEncryptor` no Ghidra — outra ordem de
esforço.

### Correção ao que este documento supunha

O doc dizia para procurar as tabelas em `StreamingAssets` esperando "texto
puro, às vezes só compactado ou com XOR simples", e tratava `resources.assets`
e o AssetRipper como o passo seguinte e mais caro.

Na prática: os bundles abrem trivialmente e **o AssetRipper não é necessário
para os dados** — ele só faria falta para código. O obstáculo real não era o
empacotamento, era a cifra por cima do conteúdo, que o doc não previa.
