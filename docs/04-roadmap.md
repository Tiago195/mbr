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
- Modelos 3D reais (Meshy + Mixamo — ver `08-arte-e-assets.md`)
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

## Registro de progresso

Atualizar ao fim de cada sessão. Manter também o "Estado atual" no `CLAUDE.md`.

| Fase | Status | Data | Notas |
|---|---|---|---|
| 1.1 | ✅ Concluída | 21/08/2026 | Critério verificado: anda até o clique, `FrontMarker` na direção certa. Feita **com** IA, contra a recomendação do doc — decisão consciente. Movimento no **botão direito** (decisão 7) |
| 1.2 | ✅ Concluída | 21/08/2026 | Validado: contorna a parede e desliza ao encostar. Botão direito segurado move continuamente |
| 1.3 | ✅ Concluída | 21/08/2026 | Validado: câmera presa ao personagem, sem perdê-lo de vista |
| 1.4 | ⏭️ Adiada | | NavMesh. O doc já a marcava como opcional aqui; só vira necessária para a IA dos mobs na Fase 6 |
| 2.1 | ✅ Concluída | 21/08/2026 | `Stat`, `StatModifier`, `Stats`. Critério verificado por `test_equipar_e_desequipar_devolve_ao_estado_anterior` |
| 2.2 | ✅ Concluída | 21/08/2026 | `Damage` como função pura. 42 testes, 115 asserções, todos os casos de borda do doc de design. Convenções em aberto fechadas na decisão 8 |
| 2.3 | 🟡 Aguardando validação | 21/08/2026 | `Health`, `Combatant`, boneco de treino. Ataque com alcance e cadência. 10 testes cobrem a vida; o clique em si precisa de olho humano |
