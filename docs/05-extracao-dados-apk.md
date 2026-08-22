# 05 — Extração dos dados de design do jogo original

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
