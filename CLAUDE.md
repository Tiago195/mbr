# CLAUDE.md

> Este arquivo é lido automaticamente pelo Claude Code ao abrir o projeto.
> Ele define o contexto permanente. Leia-o inteiro antes de qualquer tarefa.

---

## O que é este projeto

Um jogo **battle royale isométrico com elementos de MOBA**, inspirado no
**Royal Crown** (Meerkat Games / LINE Games), cujos servidores fecharam em
28/04/2022. O original: visual chibi, vista isométrica travada, 15→20 campeões
em 6 classes, 30–60 jogadores por partida, solo ou squad de 3, com loot,
crafting, mineração, arbustos, árvores derrubáveis e zona que fecha.

Este **não** é um projeto de reviver o Royal Crown. É um jogo novo, original,
que se inspira nas mecânicas e no design do original. O código, os assets e o
protocolo do jogo original **não** são reutilizados.

## Objetivo atual (Fase 1)

Chegar a um **protótipo jogável entre amigos**:

- Feio de propósito: sem sombras, sem som, texturas repetidas
- **Um único modelo 3D** serve para todos os personagens
- Mas com **todos os sistemas funcionando**: mapa, itens, habilidades,
  atributos, combate, zona, multiplayer

O critério de sucesso não é visual. É: *8 pessoas entram numa partida,
jogam até o fim, e alguém ganha.*

## Stack

| Camada | Escolha |
|---|---|
| Engine | **Godot 4.7.2** (build standard, GDScript — não .NET) |
| Linguagem | **GDScript** |
| Renderer | **Forward+** (GPU dedicada: AMD Radeon RX 7600 XT), driver D3D12 |
| Multiplayer | Godot high-level networking + export headless de servidor |
| Lobby/matchmaking | A definir (provável Node ou Spring — fora da engine) |
| Arte 3D | Meshy (via MCP) + Mixamo — **só na Fase 6** |

## Ambiente

- Godot roda no **Windows**: `C:\Godot\Godot_v4.7.2-stable_win64.exe`
- Projeto: `C:\Godot\projetos\mbr` — filesystem do **Windows**, nunca dentro do WSL
- Claude Code roda **nativamente no Windows**, do mesmo lado da Godot. Sem
  travessia 9P, sem latência. (Foi a alternativa recomendada em
  `docs/06-setup-ambiente.md`, e é a que está em uso.)
- Shell é **PowerShell**, não bash. Caminhos são `C:\...`, não `/mnt/c/...`
- **Nunca** mover o projeto para dentro do WSL: a Godot atravessando a
  fronteira 9P fica inutilizável
- **MCP do Godot** ativo (`@coding-solo/godot-mcp`): dá para rodar o projeto e
  ler o output do console direto, sem copiar e colar erro. O caminho da engine
  vem da variável de usuário `GODOT_PATH`

## Sobre o desenvolvedor

Engenheiro de software full stack com experiência sólida em:

- **Back-end:** Java, Spring Boot, RabbitMQ, microsserviços
- **Front-end:** React, TypeScript, Styled Components
- **Testes:** Jest, Testing Library, JUnit

**Não** tem experiência prévia com game dev, Godot, GDScript ou netcode
de jogo. Explique conceitos de engine e de jogo em tempo real; **não**
explique arquitetura de software, testes ou lógica de negócio — isso é o
terreno dele.

## Como trabalhar neste projeto

### Regras de ouro

1. **Fatia vertical, sempre.** Nunca construir um sistema inteiro antes de
   ele estar sendo usado no jogo. Uma habilidade funcionando end-to-end vale
   mais que um sistema de habilidades completo e não integrado.

2. **Toda fase termina jogável.** Se ao fim de uma sessão o jogo não roda,
   a sessão não terminou.

3. **Lógica de jogo é agnóstica de render.** Cálculo de dano, cooldown,
   efeitos — nada disso pode importar `MeshInstance3D` ou tocar em nó visual.
   Isso é o que permite rodar no servidor headless.

4. **Servidor é autoritativo.** O cliente envia intenção ("quero ir para
   X", "usei a habilidade 2"), nunca resultado. O servidor decide e responde.

5. **Habilidade é dado, não código.** Ver `docs/03-sistemas-de-jogo.md`.
   Quando uma habilidade nova exigir escrever uma classe nova, o sistema
   está errado — generalize antes de continuar.

6. **Nunca assumir que todo cliente recebe o estado de todos.** O protótipo
   roda com 4–8 jogadores, mas o alvo é 30+. Área de interesse é caro de
   retrofitar. Ver Fase 4.6 em `docs/04-roadmap.md`.

### Ao escrever GDScript

- Godot **4.x** — a API mudou muito da 3.x. Se estiver em dúvida entre duas
  formas, verifique qual é a da 4.
- Indentação com **Tab** (não espaços)
- Tipagem estática sempre: `var speed: float = 5.0`, `func foo() -> void:`
- `_physics_process` para lógica de jogo (tick fixo), `_process` só para
  visual/interpolação
- Nomes de nós em PascalCase, arquivos e variáveis em snake_case

### Ao propor mudanças

- Explique **por que**, não só o quê
- Se uma decisão de arquitetura vai custar caro para reverter, diga isso
  explicitamente antes de implementar
- Não faça refactor amplo sem ser pedido

---

## Mapa da documentação

| Arquivo | Conteúdo |
|---|---|
| `docs/01-visao-e-escopo.md` | O que é o jogo, o que é o Royal Crown, escopo |
| `docs/02-decisoes-tecnicas.md` | Stack escolhido e o porquê de cada escolha |
| `docs/03-sistemas-de-jogo.md` | Atributos, dano, habilidades, itens — o design |
| `docs/04-roadmap.md` | **A ordem de execução. Comece por aqui.** |
| `docs/05-extracao-dados-apk.md` | Recuperar as tabelas de design do jogo original |
| `docs/06-setup-ambiente.md` | Godot, WSL, Git, renderer |
| `docs/07-primeira-cena.md` | Passo a passo da Fase 1.1, com código |
| `docs/08-arte-e-assets.md` | Meshy, Mixamo, MCP — só relevante na Fase 6 |
| `docs/09-glossario.md` | Termos de game dev traduzidos |

## Confiabilidade desta documentação

Escrita por um assistente cujo conhecimento de treino é anterior à Godot 4.7.
Classificação honesta do conteúdo:

**Verificado contra fontes (agosto/2026):**
- Fatos sobre o Royal Crown original (datas, campeões, jogadores, mecânicas)
- APIs de GDScript usadas em `07-primeira-cena.md`
- Breaking changes da 4.6→4.7 (nenhum afeta o código aqui)
- Integração MCP da Meshy: comandos, ferramentas, créditos, licença

**Não verificado — tratar como plausível, não como fato:**
- Passo a passo de navegação do editor (nomes de menu podem diferir na 4.7)
- Todo o processo de extração do APK — depende de o build ser Mono ou IL2CPP,
  o que ninguém checou ainda
- Nenhum código deste repositório foi executado

**Opinião de engenharia, não fato:** arquitetura, roadmap, ordem das fases,
design dos sistemas. Vale o que valer o argumento — discuta, não obedeça.

## Estado atual

**Fase 1.1 — não iniciada.** Godot 4.7.2 instalada, projeto `mbr` criado,
documentação instalada, MCP do Godot funcionando. Nenhuma cena, nenhum script.

Pendências de setup ainda abertas:
- Projeto **não é repositório Git** ainda — falta `git init` e o primeiro commit
- `project.godot` não tem `run/main_scene` definido (será definido na Fase 1.1)

> Mantenha esta seção atualizada ao fim de cada sessão.
