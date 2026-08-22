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
| `docs/10-traducao-do-original.md` | **O original traduzido para o nosso vocabulário** — o mapeamento, o que cresceu e as lacunas |

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

**Medido, não suposto (22/08/2026):**
- O vocabulário de efeitos de `03-sistemas-de-jogo.md` **aguenta um jogo real**:
  as 948 habilidades e os 421 itens do original cabem nele, e o que não cabe
  está listado com nome e contagem em `docs/10-traducao-do-original.md`

**Corrigido pela prática (22/08/2026):**
- ~~"o processo de extração depende de o build ser Mono ou IL2CPP"~~ — o build
  é IL2CPP, e não importou: os dados saíram sem tocar em código. Ver
  `docs/05-extracao-dados-apk.md`
- ~~"nenhum código deste repositório foi executado"~~ — tudo roda, com suíte
  automatizada. O número de testes muda a cada sessão e vive na seção
  "Estado atual", que é conferida por `tools/conferir_numeros.py`; repeti-lo
  aqui só criaria um segundo lugar para ficar desatualizado — e ficou

**Opinião de engenharia, não fato:** arquitetura, roadmap, ordem das fases,
design dos sistemas. Vale o que valer o argumento — discuta, não obedeça.

## Estado atual

> Última atualização: **22/08/2026**. Repositório em `github.com:Tiago195/mbr`,
> branch `master`. **338 testes, 926 asserções**, todos verdes, stderr limpo.

### Onde parar de ler e começar a trabalhar

O Passo 4 — traduzir o original para o nosso vocabulário — **está concluído**.
Leia `docs/10-traducao-do-original.md` e depois decida o próximo passo com a
seção *"O que o usuário disse que falta"*, mais abaixo.

Na leitura desta sessão, o próximo passo com mais retorno é **oposição**: mobs
com IA simples usando o mesmo `Combatant`, `AbilityBook` e `AbilityEngine` do
jogador — inclusive conjurando, agora que há 1126 habilidades prontas para
eles. Depois disso, ligar à cena o que já existe só como lógica (zona, loot,
fluxo de partida).

### Os dados do original estão extraídos E traduzidos

**113 tabelas XML em `C:\Godot\rc-referencia\xml\`** — fora deste repositório,
de propósito. São referência de design, não asset do projeto: números e
estrutura entram, arte, som, código e texto não (`docs/01-visao-e-escopo.md`).

Cifra resolvida: **DES-CBC**, chave `5d0b249faa9fd875`, IV `e950d93408855ed3`.
Detalhes e inventário das tabelas em `docs/05-extracao-dados-apk.md`.

**A tradução está em `data/traducao/`** — 1126 habilidades e 421 itens no
vocabulário de `docs/03-sistemas-de-jogo.md`, carregáveis por `AbilityCatalog`
e `ItemCatalog` e conjuráveis pela mesma `AbilityEngine` das habilidades feitas
à mão. Regerar: `py tools/traducao/traduzir.py`.

O que o vocabulário ganhou para caber: atributos **18 → 44**, controles de
grupo **4 → 10** estados (e as opções de `CrowdControlEffect` de 5 para 11),
efeitos **6 → 14**, e `Ability` deixou de ter uma forma para
ter uma **lista de pulsos** (decisão 10). O mapeamento coluna a coluna e as
lacunas que sobraram estão em `docs/10-traducao-do-original.md`.

### O que está pronto e jogável

Fases 1.1 a 1.3, 2.1 a 2.4, e 3.1 a 3.4 — todas validadas em execução.

Dá para: andar clicando com o botão direito, contornar obstáculos, atacar
bonecos de treino, e usar três habilidades em Q/W/E (área no chão, projétil
que para no primeiro, dash com escudo). Barra de vida com escudo e números de
dano flutuantes.

**Veredito do usuário sobre a diversão:** *"pro que nós temos agora é
impossível isso ser divertido, ainda falta muito"*. Justo — não há oposição
que revide, nem mapa, nem loot, nem progressão.

### O que está pronto só como lógica

Existem em `core/`, com teste, mas **não estão ligados à cena nem têm camada
visual**:

| Sistema | Arquivo | O que falta |
|---|---|---|
| Zona que fecha | `core/match/zone.gd` | Círculo desenhado; trocar `damage_per_second` por buff, como o original faz |
| Itens e inventário | `core/items/` | Loot no chão, coleta, UI |
| Fluxo de partida | `core/match/match_state.gd` | Spawn, lobby, ligação com a cena |
| Corpus traduzido | `data/traducao/` | Nada obriga a usá-lo; é referência de balanceamento, não conteúdo |

E, dentro do combate, peças com teste mas sem consumidor visual ainda: mana
(`ResourcePool`), marcas (`MarkSet`), invocações (`Unit.pending_summons` espera
quem materialize) e ajuste de recarga (`AbilityBook.apply_cooldown_requests`
precisa ser chamado pela camada de gameplay).

### O que foi adiado, e por decisão de quem

- **Fase 4 (multiplayer) — adiada pelo usuário** em 22/08/2026. A objeção foi
  levantada com o argumento do próprio roadmap e ele reafirmou. Ver a nota
  em `docs/04-roadmap.md`. Guardar a **4.1 sozinha** como sonda barata de
  risco quando o jogo valer a pena jogar acompanhado.
- **Fase 1.4 (NavMesh)** — o roadmap já a marcava opcional; só é necessária
  para a IA dos mobs.

### Três sistemas que a tradução revelou e o roadmap não previa

Achados por medição, não por memória. Nenhum é urgente; todos são refinamento
de sensação, e o que falta antes continua sendo oposição, mapa e loot.

- **Carga de suprema** — 534 habilidades do original. A suprema não tem
  recarga: enche batendo e apanhando.
- **Corrente de combo** — 125. Conjurar A dentro de uma janela troca A por B.
- **Janelas de cancelamento** — 72. Nós temos um booleano `cancelable`; o
  original tem quatro instantes por habilidade.

### O que o usuário disse que falta

Palavras dele: *"nós precisamos de todos — itens, loot, inventário, mapa de
verdade, personagens e kits, e isso é só o começo; falta a mecânica do battle
royale inteira"*.

Na leitura desta sessão, o que mais falta para deixar de ser sandbox não é
conteúdo, é **oposição**: um boneco parado não é adversário, e nenhuma
quantidade de habilidade nova conserta isso.

### Como este projeto trabalha

O usuário conduz por validação, não por micro-decisão: *"vc sempre vai tomar a
frente, eu vou apenas validar e testar o q vc n consegue, pode ir seguindo
para as próximas fases, só pare quando precisar q eu teste ou valide algo"*.

Ou seja: avançar sem pedir autorização a cada etapa, commitar e fazer push ao
fim de cada uma, e **parar só quando o critério exigir olho humano** — coisa
visual, sensação de jogabilidade, teste multi-máquina. Erro de console, teste
unitário e lógica pura eu fecho sozinho.

Ao tomar uma decisão que a documentação marcava como "em aberto", registrá-la
em `docs/02-decisoes-tecnicas.md` e dizer que tomou — ele reverte se discordar.


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

### Número em documento é asserção

```
py tools/conferir_numeros.py
```

Confere os números afirmados em `CLAUDE.md` e em `docs/` contra o código e
contra o corpus traduzido. **Rodar antes de commitar documentação.**

Existe porque três revalidações seguidas do Passo 4 reprovaram pela mesma
espécie de erro, e nunca pelo mesmo número: "atributos 18 → 44" certo e
"controle 4 → 10" errado; "o censo sai vazio" contra o relatório gerado no
mesmo commit dizendo que não; "dois bugs" numa seção com cinco itens.

Corrigir um de cada vez não resolve — o que resolve é a afirmação passar a ser
verificável por máquina. Se um número muda no código, a ferramenta acusa o
documento que ficou para trás.

Afirmação nova em documento: acrescentar a conferência dela ali. Se o texto
mudar de forma e o padrão parar de casar, a ferramenta também acusa — uma
conferência órfã é tão ruim quanto nenhuma.

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
- **Enum exportado serializa como INTEIRO no `.tres`.** Inserir um valor no
  meio de `Stat.Id`, `CrowdControlEffect.Kind` ou qualquer enum exportado
  renumera tudo que vem depois e troca, **em silêncio**, o atributo ou o
  controle de toda habilidade e todo item já salvos. Valor novo entra no fim,
  sempre. Está anotado em cada enum afetado
- **`call()` não funciona numa classe sem instância.** Uma tabela de despacho
  `{nome: método}` resolvida com `MinhaClasse.call(tabela[nome])` não compila:
  "Cannot call non-static function `call()` on the class directly". Usar
  `match` explícito — que ainda por cima quebra em tempo de compilação quando
  alguém acrescenta um caso e esquece de tratá-lo

Particularidade do ambiente: a chave SSH do GitHub está **só no WSL2**.
Commit funciona no Windows; o push precisa passar pelo WSL:
`wsl -e bash -lc "cd /mnt/c/Godot/projetos/mbr && git push"`

> Mantenha esta seção atualizada ao fim de cada sessão.
