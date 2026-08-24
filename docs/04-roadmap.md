# 04 — Roadmap

> **Este é o documento operacional. É por aqui que se começa cada sessão.**

## Como ler este roadmap

Cada fase tem um **critério de conclusão verificável**. Se não dá para
responder "sim" à pergunta do critério, a fase não acabou.

**Toda fase termina com o jogo rodando.** Não existe fase que deixa o projeto
quebrado esperando a próxima.

A ordem foi escolhida para **atacar o risco primeiro**. As coisas que podem
inviabilizar o projeto vêm antes das coisas que só dão trabalho.

---

## FASE 1 — Fundação local

*Objetivo: entender a engine e ter um personagem se movendo.*

### 1.1 — Cápsula andando

Cena com chão, cápsula, câmera isométrica e luz. Clicar no chão move a cápsula
até lá.

Cobre quatro conceitos de uma vez: como cena e nó funcionam, como script se
conecta a um nó, como converter clique em ponto do mundo (raycast contra plano),
e como mover um corpo com colisão.

Passo a passo completo em `07-primeira-cena.md`.

> **Recomendação:** fazer esta etapa **à mão**, sem IA, mesmo sendo mais lento.
> São ~30 minutos e dá o modelo mental da engine. Sem isso, não há como revisar
> com critério o que a IA escreve depois. É o que separa a IA de muleta a
> acelerador.

**Critério:** a cápsula anda até onde eu clico?

### 1.2 — Obstáculos

Paredes que bloqueiam a passagem. A cápsula desliza ao encostar em vez de
travar.

**Critério:** consigo contornar uma parede?

### 1.3 — Câmera

Câmera segue o jogador com suavização. Ajustar ângulo e distância até ficar
jogável — não bonito, jogável: dá para ver quem se aproxima?

**Critério:** consigo jogar sem perder o personagem de vista?

### 1.4 — Pathfinding (opcional aqui)

NavMesh para o movimento contornar obstáculos automaticamente em vez de ficar
preso na parede.

Pode ser adiado. Mas será necessário para a IA dos mobs na Fase 6.

---

## FASE 2 — Motor de combate

*Objetivo: os números funcionando, testados, isolados.*

Esta fase é **lógica de negócio pura** — território conhecido. Sem render, sem
rede, sem engine. Roda em teste unitário.

### 2.1 — Atributos e modificadores

Classe de stats, sistema de modificadores com origem, duração e stacking.

**Critério:** equipar e desequipar uma fonte de modificador devolve os atributos
exatamente ao estado anterior?

### 2.2 — Cálculo de dano

Função pura completa: crítico, armadura, penetração, escudo, roubo de vida,
tipos de dano.

**Critério:** a suíte de testes cobre os casos de borda listados em
`03-sistemas-de-jogo.md` e passa?

### 2.3 — Vida, morte e integração

Ligar o motor ao personagem da Fase 1. Ataque básico com alcance e velocidade de
ataque. Um segundo alvo (boneco parado) que toma dano e morre.

**Critério:** consigo matar um boneco de treino clicando nele?

### 2.4 — Leitura de combate

> **Fase acrescentada em 21/08/2026.** Não estava no roadmap original, e a
> ausência era um vão: a 3.4 cobre telegrafia de habilidade (área no chão,
> projétil, indicador de mira) e a Fase 6 cobre "UI de verdade". Barra de vida
> e número de dano não estavam em nenhuma das duas.

Barra de vida sobre cada combatente e número de dano subindo no impacto.

O argumento para trazer isto para cá, e não deixar no polimento, está no
próprio `03-sistemas-de-jogo.md`:

> O que consome tempo aqui **não é escrever, é balancear** — descobrir que 200
> de armadura deixa o jogo chato, que roubo de vida está quebrado.

Não se balanceia o que não se enxerga. Isto é **instrumentação**, não
polimento — e instrumentação chega antes de fazer falta, não depois. Enquanto
a única leitura de combate for `print` no console, todo ajuste de número é às
cegas.

Continua feio de propósito: dois quads e um `Label3D`, sem animação de UI,
sem ícone, sem moldura.

**Critério:** consigo ver a vida caindo e o dano saindo sem olhar o console?

---

## FASE 3 — Habilidades

*Objetivo: o sistema que vai sustentar 60 habilidades.*

### 3.1 — Vocabulário de efeitos

Implementar os efeitos base: dano, cura, escudo, modificador de atributo,
controle de grupo, deslocamento.

### 3.2 — Motor de habilidade

Cooldown, tempo de conjuração, custo, alvo, forma, filtro. A habilidade lida
como **dado**, não como classe.

### 3.3 — Três habilidades reais

Escolher três que exercitem partes diferentes do sistema. Sugestão:

1. Uma **área no chão** com dano (alvo POINT, forma CIRCLE)
2. Um **projétil linear** que para no primeiro alvo (alvo DIRECTION, forma
   PROJECTILE)
3. Um **dash** com escudo (alvo DIRECTION, efeitos DISPLACEMENT + SHIELD)

**Critério:** consigo adicionar uma quarta habilidade escrevendo só
configuração, sem tocar em código de sistema? **Se não, o sistema não está
pronto — não avance.**

### 3.4 — Feedback visual mínimo

Formas primitivas indicando área de habilidade, projétil como esfera,
indicador de mira. Feio de propósito.

**Critério:** dá para entender o que está acontecendo numa luta?

---

## FASE 4 — Multiplayer

*Objetivo: a validação de risco mais importante do projeto.*

> **Esta fase existe cedo por um motivo:** se o netcode não funcionar, o projeto
> não existe. É melhor descobrir agora do que depois de construir 15
> personagens.

### 4.1 — Duas cápsulas em rede

Servidor autoritativo. Dois clientes, cada um vê o outro se mover. Sem combate,
sem nada. Conexão direta por IP.

**Critério:** dois computadores diferentes, na mesma rede, veem um ao outro se
movendo?

### 4.2 — Tick e interpolação

Servidor a 20–30 ticks/s. Cliente interpola posição entre ticks para movimento
suave. **Sem** predição (ver decisão 4 em `02-decisoes-tecnicas.md`).

**Critério:** o movimento do outro jogador parece suave, não aos trancos?

### 4.3 — Combate em rede

Ataque, dano e morte sincronizados. Servidor decide tudo; cliente só envia
intenção.

**Critério:** consigo matar um amigo pela internet?

### 4.4 — Habilidades em rede

Todo o sistema da Fase 3, autoritativo.

**Critério:** as habilidades funcionam igual em rede e em single-player?

### 4.5 — Servidor headless

Exportar o projeto como servidor sem gráficos. Rodar num container.

**Critério:** o servidor sobe sem GPU e aceita conexões de fora?

### 4.6 — Área de interesse

> Adicionado após verificação: o original rodava com **30 a 60 jogadores por
> partida** (ver `01-visao-e-escopo.md`). Isso muda a arquitetura de rede.

Cada cliente recebe apenas o estado do que está **perto dele**, não do mapa
inteiro. Sem isso, a largura de banda por cliente cresce linearmente com o
número de jogadores e o custo de serialização no servidor cresce
quadraticamente.

Não precisa ser sofisticado no protótipo — um grid espacial simples com raio de
interesse já resolve. O que **não** pode acontecer é a Fase 4 inteira ser
escrita assumindo "todo mundo recebe tudo", porque isso é caro de desfazer.

**Critério:** com 8 jogadores forçando raio de interesse pequeno, cada cliente
recebe só os vizinhos e o jogo continua correto?

---

## FASE 5 — Partida completa

*Objetivo: sair de "sandbox" para "jogo".*

### 5.1 — Mapa
Layout com obstáculos, áreas e pontos de spawn. Usa o editor visual da Godot.

> O original tinha **arbustos para se esconder** e **árvores derrubáveis que
> abrem caminho**. São mecânicas de posicionamento que mudam bastante o
> combate — vale prototipar os arbustos cedo, porque afetam o design do mapa.
> Árvores destrutíveis podem ficar para a Fase 6.

### 5.2 — Itens e inventário
Loot no chão, coletar, equipar, efeito nos atributos.

### 5.3 — Zona
Encolhimento em fases, dano fora da zona.

> **Lógica implementada fora de ordem em 22/08/2026**, enquanto a extração dos
> dados do original rodava em segundo plano. `scripts/core/match/zone.gd`,
> 18 testes. Falta a camada visual — o círculo desenhado no mapa — e ligar ao
> fluxo de partida da 5.4.
>
> Cada fase tem tempo de **aviso** (próximo círculo visível, zona parada) e de
> **encolhimento** (zona viajando). Separar os dois é o que cria a decisão que
> define o gênero: rotacionar agora e ceder posição, ou ficar e pagar dano.

### 5.4 — Fluxo de partida
Início, spawn de todos, condição de vitória, fim, voltar ao lobby.

### 5.5 — Lobby e matchmaking
Serviço fora da engine (Node/Spring) que junta N jogadores e sobe uma instância
do servidor.

### 5.6 — Deploy
Servidor hospedado. Distribuição do cliente para os amigos.

**Critério da Fase 5 (e da validação inteira):**
> **8 pessoas entram numa partida pela internet, jogam do começo ao fim, e
> alguém ganha.**

Atingido isso, a ideia está validada. Tudo daqui em diante é melhoria.

---

## FASE 6 — Conteúdo e polimento

*Só começa depois que a Fase 5 provou que o jogo é divertido.*

- Os outros 12–17 personagens (agora barato — é configuração)
- Modelos 3D melhores, **gerados no Blender por script** (ver
  `08-arte-e-assets.md`). Não é mais uma fase de compra: o gerador já roda, e
  o boneco de teste é o primeiro artefato dele
- Máquina de animação: transições entre andar, atacar, morrer
- Mobs neutros com IA, incluindo mobs de nível alto genuinamente perigosos
- Crafting: coleta de ingredientes, cozimento, mineração
- Árvores derrubáveis
- Modo Squad de 3
- Som, iluminação, UI de verdade
- Predição de cliente, se o ping incomodar
- Escalar de 8 para 30+ jogadores por partida

---

## O que NÃO fazer

- ❌ Construir os 15 personagens antes de 1 funcionar completamente
- ❌ Fazer arte antes da Fase 6
- ❌ Otimizar performance antes de ter gargalo medido
- ❌ Implementar predição de cliente na Fase 4
- ❌ Adiar a Fase 4 (multiplayer) — é o maior risco técnico do projeto
- ❌ Construir um sistema inteiro sem integrá-lo ao jogo na mesma fase

---

## Sobre a Fase 4 ter sido adiada

Decisão do usuário em 22/08/2026: *"pode pular o multiplayer, pra q
multiplayer no estágio q o game se encontra?"*.

A objeção foi levantada antes, com o argumento deste próprio documento — a
fase existe cedo porque *"se o netcode não funcionar, o projeto não existe"*.
O usuário reafirmou, e a decisão é dele.

**O contrapeso honesto, que pesou na conversa:** boa parte do risco que
justificava a ordem já foi paga. Todo o `core/` — atributos, dano, vida,
habilidades, zona, itens, partida — não conhece nó da engine e roda headless.
O medo do documento é lógica embolada com render, e isso não aconteceu.

O risco que sobra é menor e específico: *"o netcode da Godot dá conta?"*. Isso
se responde com a **4.1 sozinha** — duas cápsulas se vendo por IP direto, uma
sessão curta — sem fazer a fase inteira. Vale guardar como sonda para quando o
jogo estiver perto de valer a pena jogar acompanhado.

## Registro de progresso

Atualizar ao fim de cada sessão. Manter também o "Estado atual" no `CLAUDE.md`.

Legenda: ✅ concluída e validada · 🟨 lógica pronta, falta camada visual ou
integração · 🟡 aguardando validação humana · ⏭️ adiada

| Fase | Status | Data | Notas |
|---|---|---|---|
| 1.1 | ✅ Concluída | 21/08/2026 | Critério verificado: anda até o clique, `FrontMarker` na direção certa. Feita **com** IA, contra a recomendação do doc — decisão consciente. Movimento no **botão direito** (decisão 7) |
| 1.2 | ✅ Concluída | 21/08/2026 | Validado: contorna a parede e desliza ao encostar. Botão direito segurado move continuamente |
| 1.3 | ✅ Concluída | 21/08/2026 | Validado: câmera presa ao personagem, sem perdê-lo de vista |
| 1.4 | ⏭️ Adiada | | NavMesh. O doc já a marcava como opcional aqui; só vira necessária para a IA dos mobs na Fase 6 |
| 2.1 | ✅ Concluída | 21/08/2026 | `Stat`, `StatModifier`, `Stats`. Critério verificado por `test_equipar_e_desequipar_devolve_ao_estado_anterior` |
| 2.2 | ✅ Concluída | 21/08/2026 | `Damage` como função pura. 42 testes, 115 asserções, todos os casos de borda do doc de design. Convenções em aberto fechadas na decisão 8 |
| 2.3 | ✅ Concluída | 21/08/2026 | Validado: mata o boneco clicando. Fórmula conferida no log — 50 normal, 87.5 crítico, contra 20 de armadura |
| 2.4 | ✅ Concluída | 21/08/2026 | Validado após corrigir a barra, que deslizava em vez de encolher (billboard descarta escala do nó) |
| 3.1 | ✅ Concluída | 21/08/2026 | Vocabulário de efeitos: DAMAGE, HEAL, SHIELD, STAT_MOD, CROWD_CONTROL, DISPLACEMENT. `Unit` reúne atributos, vida e estados fora da árvore de cena. 71 testes |
| 3.2 | ✅ Concluída | 21/08/2026 | `Ability` como Resource, `AbilityShape`, `AbilityBook`, `AbilityEngine`. 99 testes. Critério da 3.3 já verificado por teste — ver nota abaixo |
| 3.3 | ✅ Concluída | 22/08/2026 | Três habilidades em Q/W/E, declaradas em `data/abilities/*.tres`. Validado em jogo. Veredito do usuário: funciona, mas ainda não é divertido — falta oposição e conteúdo |
| 3.4 | ✅ Concluída | 22/08/2026 | Telegrafia primitiva: disco no chão, faixa, esfera viajando. Recusas vão para o console |
| **4** | ⏭️ **Adiada por decisão do usuário** | 22/08/2026 | Multiplayer. Ver a nota abaixo da tabela — a objeção foi levantada e a decisão é dele |
| 5.2 | 🟨 Lógica pronta | 22/08/2026 | `Item` e `Inventory` em `core/items/`, 16 testes. Falta loot no chão, coleta e UI |
| 5.3 | 🟨 Lógica pronta | 22/08/2026 | `Zone` em `core/match/`, 18 testes. Falta o círculo desenhado e trocar `damage_per_second` por buff |
| 5.4 | 🟨 Lógica pronta | 22/08/2026 | `MatchState` em `core/match/`, 15 testes. Governa a zona e decide o vencedor. Falta spawn, respawn de lobby e ligação com a cena |
| **Passo 5** | ✅ Concluída | 22/08/2026 | **Os campeões do original em jogo.** `actor_xml` traduzida: 384 atores, 33 campeões com kit, 28 com as quatro habilidades conjuráveis. `ChampionSelector` amarra atributos e kit ao jogador; Q/W/E/R e troca por Page Down. Sonda em `tools/sondar_campeoes.gd` |
| **Passo 4** | ✅ Concluída | 22/08/2026 | **Tradução do original.** 948 habilidades + 421 itens no nosso vocabulário. Atributos 18→45, estados de controle 4→10 (e opções de `CrowdControlEffect` 5→11), efeitos 6→14, `Ability` virou lista de pulsos. Corpus carregável e conjurável em `data/traducao/`. Ver `docs/10-traducao-do-original.md` |

### O que a tradução do original mudou no roadmap

O Passo 4 não estava na numeração de fases — ele vinha de
`05-extracao-dados-apk.md` — mas mexeu no plano de duas formas que valem
registro:

**O vocabulário de efeitos deixou de ser hipótese.** A Fase 3.1 apostava que
uma lista fechada de peças expressaria a maioria das habilidades de um MOBA.
Agora está medido: as 948 do original cabem, e as que não cabem têm nome. A
regra "habilidade nova não escreve classe nova" passou a ter evidência.

**Apareceram três sistemas que o roadmap não previa**, e todos são de fase
posterior:

- ~~**Carga de suprema**~~ — **fechada em 22/08/2026** (decisão 17). 517
  habilidades declaram quanto rendem; o ataque básico rende 200 e a suprema
  custa 1000. Ela era a lacuna mais cara da lista, e era a que sustentava um
  número inventado — os 45 s de recarga que a suprema recebia por não haver
  carga.
- ~~**Corrente de combo**~~ (125) — **fechada**, decisão 21. Conjurar A dentro de uma janela troca A por B.
  É boa parte do que dava textura ao corpo a corpo do original.
- **Janelas de cancelamento** (72). Nós temos um booleano; o original tem
  quatro instantes por habilidade. É onde mora o "feel".

Nenhum é urgente para o protótipo — os três são refinamento de sensação, e o
que falta antes disso continua sendo oposição, mapa e loot. Ficam registrados
para não serem redescobertos de memória depois.

### O corpus traduzido chegou à cena — fechado em 22/08/2026

O Passo 4 entregou 1126 habilidades conjuráveis **por teste**, e nenhuma delas
em jogo: `AbilityCatalog` não era referenciado fora de `scripts/core/`. Era a
regra de ouro nº 1 cobrando — *"nunca construir um sistema inteiro antes de ele
estar sendo usado no jogo"*.

O que fechou foi traduzir `actor_xml`, a única tabela que responde **quem tem
quais habilidades**, e amarrar o resultado ao `Combatant` e ao `AbilityCaster`.

Uma correção de número que vale registrar: a sondagem anterior dizia **58
campeões**, e são **40** — `actor_xml` e `actor_2_xml` repetem Ids, e a
contagem somava as duas tabelas sem deduplicar. Das 40, 33 têm kit e 28 têm as
quatro habilidades conjuráveis. Foi a mesma espécie de erro que
`tools/conferir_numeros.py` existe para pegar, e o número estava num documento
que a ferramenta não cobria.

O que ainda não está ligado: **itens e inventário**. `ItemCatalog` continua sem
consumidor fora de `core/` — falta loot no chão, coleta e UI (Fase 5.2).
