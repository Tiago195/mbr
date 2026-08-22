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
| Controles | **Esquema do League of Legends** (ver decisão 7) |

## Controles

O jogo copia o esquema do **League of Legends**. O que isso obriga:

- **Botão direito anda.** O esquerdo é de seleção e UI — **não usar para
  movimento**, mesmo sendo o gesto mais natural
- **Habilidades são Q/W/E/R miradas no cursor**, não cliques. Na Fase 3, o
  raycast tela → mundo é disparado lendo a posição do mouse, não um evento
  de clique

Mapeamento completo e o que ainda está em aberto: decisão 7 em
`docs/02-decisoes-tecnicas.md`.

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

### Ao escrever `.tscn` à mão

Editar a cena como texto é rápido e preciso, mas tem uma armadilha silenciosa:

- **`Transform3D` é serializado por LINHAS da matriz de base**, não por colunas.
  Escrever transposto não gera erro nenhum — para rotação pura, a transposta é
  a inversa, e o resultado é a rotação ao contrário. Já custou uma sessão:
  a câmera olhando para o céu, tela cinza, `errors: []`
- Não calcular a matriz à mão. Perguntar à engine:
  `godot --headless --path <projeto> --script <sonda.gd>` com um `Node3D` de
  `rotation_degrees` conhecido, imprimindo `var_to_str(node.transform)`
- Depois de escrever, **abrir no editor e conferir o Inspector** — é lá que a
  rotação aparece de volta em graus

Corolário geral: o MCP pega erro de sintaxe, referência nula e recurso
faltando. **Não pega "está correto mas aponta para o lugar errado".** Coisa
visual precisa de olho humano na tela.

### Billboard descarta a escala do nó

`billboard_mode` faz o shader trocar a base da matriz de modelo pela
orientação da câmera — e nisso **a escala do nó é descartada**, a menos que
`billboard_keep_scale` esteja ligada. A translação continua valendo.

Sintoma: o objeto anda para o lado em vez de mudar de tamanho. Sem erro no
console. Já aconteceu com a barra de vida da Fase 2.4.

Para redimensionar algo com billboard, mexer na **geometria** (`size` +
`center_offset` da malha), não em `scale`/`position` do nó. `center_offset`
vive no espaço local da malha, que gira junto com o billboard, então continua
correto se a câmera um dia girar — `position` do nó, que é mundo, não.

Ordem de desenho entre materiais com `no_depth_test` é decidida por
`render_priority`, não por deslocamento em Z.

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

**Fase 1.1 — concluída (21/08/2026).** Cena `scenes/main.tscn` com chão,
cápsula, câmera isométrica e luz. Movimento por botão direito, verificado em
execução. Repositório em `github.com:Tiago195/mbr`, branch `master`.

**Fases 1.2 e 1.3 — implementadas, aguardando validação humana.** Obstáculos
em `Walls`, câmera seguindo o jogador (`camera_rig.gd`), botão direito
segurado movendo continuamente. Rodam sem erro; os critérios são visuais.

**Fase 1.4 (NavMesh) adiada** — o roadmap já a marcava como opcional; só vira
necessária para a IA dos mobs na Fase 6.

**Fases 2.1, 2.2 e 2.3 — implementadas (21/08/2026).** Motor de combate em
`scripts/core/combat/` (atributos, modificadores, dano, vida) e a integração
com o personagem via `Combatant`, um componente Node que se pendura tanto no
`CharacterBody3D` do jogador quanto no `StaticBody3D` do boneco de treino.
52 testes passando. Convenções fechadas na decisão 8 de
`docs/02-decisoes-tecnicas.md`.

**Fase 2.4 — acrescentada ao roadmap, implementada e validada (21/08/2026).**
Barra de vida e número de dano. Não estava no roadmap original; entrou porque
é instrumentação para balancear, não polimento.

**Fase 3.1 — concluída (21/08/2026).** Vocabulário de efeitos em
`scripts/core/abilities/`. `Unit` (em `core/combat/`) reúne atributos, vida,
estados e posição fora da árvore de cena; `Combatant` virou ponte. 71 testes.
Formato de dado fechado na decisão 9: `Resource` em `.tres`.

**Fase 3.2 — concluída (21/08/2026).** `Ability` (Resource), `AbilityShape`,
`AbilityBook`, `AbilityEngine`. 99 testes, 255 asserções.

Regras de estado definidas **uma vez no sistema**, em `ability_engine.gd`:
stun e silêncio impedem conjurar; stun no meio corta a conjuração; habilidade
nova NÃO cancela a anterior (recusa com BUSY); recarga começa ao **iniciar** a
conjuração, então cortar a conjuração de alguém não devolve a habilidade.

**Próximo: Fase 3.3** — três habilidades reais e o feedback visual da 3.4. O
critério da 3.3 ("quarta habilidade só com configuração") já passa em teste,
mas escolher as três e sentir se são divertidas precisa de humano.

## Testes

Suíte headless, sem abrir o editor. Sai com código 1 se algo falhar:

```
godot --headless --path . --script res://tests/run_tests.gd
```

Se der `Could not find type "TestCase"`, o cache de classes globais está
velho — rodar um passe de importação antes:
`godot --headless --editor --quit --path .`

Todo teste novo entra em `tests/` e é registrado em `SUITES`, dentro de
`tests/run_tests.gd`. Só `scripts/core/` é testável assim: é a parte que não
conhece nó da engine.

**Armadilha do arnês.** GDScript não deixa capturar erro em tempo de execução:
`call()` volta normalmente mesmo quando o método estourou no meio, e um teste
que crashou passaria como sucesso. Duas defesas:

1. Teste que não registra **nenhuma** asserção é contado como falha — pega o
   estouro antes da primeira asserção, e também o teste vazio
2. Um estouro **depois** da primeira asserção ainda escapa. Por isso, ao rodar
   a suíte, tratar `SCRIPT ERROR` no console como falha mesmo com exit 0

Não confiar em suíte verde recém-escrita: quebrar a lógica de propósito e
confirmar que ela fica vermelha. Já pegou um bug real aqui — lambda em
GDScript captura por valor, então reatribuir variável de fora dentro dela não
tem efeito; mutar funciona.

**Ler o stderr, não só o resumo.** `ObjectDB instances were leaked at exit`
significa ciclo de referência, e a suíte passa verde mesmo assim.

### Armadilhas de GDScript já pagas neste projeto

- **Ciclo entre `RefCounted`.** A Godot conta referências e **não coleta
  ciclos**. Conectar um sinal de um objeto possuído a um lambda que referencia
  o dono cria o ciclo, e nenhum dos dois é liberado. Foi o que vazou 150
  instâncias antes de `Unit` parar de repassar `died`. Sinal deve subir por
  quem já tem a referência, nunca voltar
- **Não nomear enum como classe embutida.** `enum Control` colide com o nó de
  UI `Control`, e `@export var x: Control` resolve para a classe da engine. O
  erro — "cannot be assigned to a variable of type Control" — não sugere
  colisão de nome. Vale para `Control`, `Node`, `Timer`, `Label`, `Range`…
- **Erro em tempo de execução aborta só a função onde ocorreu** e devolve o
  controle a quem chamou. Isso é o que permite o runner sobreviver a um teste
  que estoura — mas também significa que código crítico (como o `quit()` do
  runner) não pode dividir função com código que pode estourar. Um `SceneTree`
  headless sem `quit` roda para sempre: a suíte trava em vez de falhar
- **`Array.filter()` devolve `Array` sem tipo.** Atribuir a `Array[T]` estoura
  em runtime; usar laço explícito

Particularidade do ambiente: a chave SSH do GitHub está **só no WSL2**.
Commit funciona no Windows; o push precisa passar pelo WSL:
`wsl -e bash -lc "cd /mnt/c/Godot/projetos/mbr && git push"`

> Mantenha esta seção atualizada ao fim de cada sessão.
