# 02 — Decisões Técnicas

Este documento registra **o que foi decidido e por quê**. O "por quê" importa:
quando aparecer a tentação de mudar de rumo, é aqui que está o custo de cada
alternativa.

---

## Decisão 1: Godot 4 como engine

### Alternativas avaliadas

| Opção | Veredito |
|---|---|
| **Godot 4** | ✅ **Escolhida** |
| Unity | Defensável, mas perde no fluxo com IA |
| Unreal | Descartada — C++/Blueprints, foco em AAA, curva íngreme |
| Three.js + Colyseus (web) | Descartada para este escopo |
| bevy (Rust), Stride, Flax | Descartadas — comunidade/cobertura insuficiente |

### Por que Godot venceu

**1. O projeto inteiro é arquivo de texto.** Cena, script, configuração — tudo
legível, versionável no Git, e **editável por uma IA**. No Unity, boa parte da
configuração vive em `.meta` e YAML que se monta clicando no editor. Uma IA não
clica.

Essa foi a razão decisiva. Existe diferença entre *"a IA conhece a ferramenta"*
e *"a IA consegue trabalhar nela"*:

- **Conhecimento:** Unity ganha por larga margem (décadas de C# público e Stack
  Overflow). Godot é bem coberta, mas com a pegadinha de a IA às vezes misturar
  API da 3.x com a 4.x — contornável dizendo explicitamente "Godot 4"
- **Capacidade de agir:** Godot ganha por muito mais. Claude Code apontado para
  a pasta lê e escreve cenas, scripts e configuração — ele *constrói*. No Unity
  ele escreve o script mas não arrasta o componente, não configura o prefab,
  não liga a referência no Inspector. Metade do trabalho volta para o
  desenvolvedor, e é a metade tediosa

Para o fluxo desejado — descrever a mecânica e revisar o resultado — a segunda
vantagem vale mais que a primeira. Conhecimento desatualizado se corrige;
incapacidade de agir não.

**2. Servidor headless de primeira classe.** O mesmo projeto exporta como
servidor sem gráficos, roda em container, e a lógica é literalmente a mesma dos
dois lados. Escreve-se o cálculo de dano uma vez e ele roda idêntico no cliente
e no servidor — sem risco de divergência entre duas implementações. No Unity dá
para fazer, mas é mais burocrático.

**3. Peso.** ~100 MB, abre em segundos, um executável só. Unity são dezenas de
GB mais um Hub gerenciando versões.

### O que se perde ao não escolher Unity

Registrado honestamente, porque é real:

- **Volume de material**: 20 anos de tutoriais, cursos, Asset Store gigante
- **Netcode maduro**: Mirror e FishNet são bibliotecas testadas em jogos
  comerciais, com predição e reconciliação **prontas**. Isso é uma vantagem
  específica e relevante para este tipo de jogo
- **C#**, que seria mais familiar vindo de Java

Unity seria a escolha certa se o multiplayer com predição fosse prioridade
desde já. Não é — ver Decisão 4.

---

## Decisão 2: 3D, não 2D nem pixel art

### O raciocínio

"3D" e "bonito" são independentes. O caro é **arte** — modelo, textura,
animação, iluminação. O 3D em si, com formas primitivas, custa quase nada a mais
que 2D.

Uma cápsula cinza com um indicador de direção, andando num plano verde, já
parece muito menos feia que um círculo 2D, e dá praticamente o mesmo trabalho.

### Pixel art: descartado

Sedutor e enganoso. Pixel art **bom** é altamente artesanal — cada frame é
posicionamento consciente de pixel. IA gera "imagens com aparência de pixel art"
sem paleta consistente nem grid alinhado, e o problema de coerência entre frames
continua idêntico. Trocaria-se trabalho de artista 3D por trabalho de pixel
artist, sem ganhar nada em consistência.

### O custo real do 3D sobre o 2D

Cerca de **2 a 3 dias a mais**, concentrados em:

- **Câmera** (o custo real): posição, ângulo, distância, suavização. E o ângulo
  muda a jogabilidade — muito inclinada e não se vê quem chega por trás. Volta a
  ser ajustada várias vezes
- **Conversão tela ↔ mundo**: o mouse dá um ponto 2D; é preciso saber que ponto
  do chão aquilo representa. Resolve-se com raycast contra o plano do chão
- **Luz**: sem ela, tudo fica preto. Duas linhas resolvem

### Onde o 3D fica caro (e não é agora)

Quando se trocar as cápsulas por bonecos de verdade: esqueleto, animações que
combinam entre si (parar de andar no meio de um ataque sem dar tranco),
personagem virando suavemente, sombras. Nada disso precisa ser feito agora, e a
troca é indolor depois — é substituir o objeto visual, a lógica não muda.

---

## Decisão 3: consistência do personagem vem do 3D, não da IA

Problema levantado: manter o personagem idêntico em todas as etapas da animação.

Geradores de imagem 2D são péssimos em coerência quadro a quadro — cada imagem é
gerada do zero, a IA não "lembra" a anterior. Existem paliativos (ControlNet com
pose de referência, LoRA treinado no personagem), mas é briga constante.

**A solução não é uma IA melhor: é gerar o personagem uma vez, em 3D, e animar
o esqueleto.** Aí a consistência não é *mantida*, é estruturalmente impossível
de quebrar — é a mesma malha em todos os frames.

Detalhes de execução em `08-arte-e-assets.md`.

---

## Decisão 4: sem predição de cliente no protótipo

Netcode "de verdade" tem previsão de movimento no cliente e reconciliação com o
servidor — é o que faz um jogo profissional parecer instantâneo mesmo com ping.
É complexo e é onde iniciante em netcode afunda.

**Decisão: pular isso na Fase 1.** O servidor manda em tudo, o cliente só
desenha o que recebe.

- Consequência: 50–100 ms de atraso perceptível no comando
- Para validar se as habilidades são divertidas, isso é irrelevante
- Adiciona-se predição depois, **se** o projeto provar que merece

Mitigação barata: servidor a **20–30 ticks/s** e **interpolação** da posição no
cliente entre os ticks. Só isso já deixa o movimento suave.

---

## Decisão 5: lobby e matchmaking fora da engine

A Godot traz rede, mas não traz matchmaking nem lobby.

Isso é um serviço pequeno e é exatamente o terreno do desenvolvedor: um serviço
em Node ou Spring que junta N jogadores e sobe uma instância do servidor Godot
headless.

Fica para a Fase 5. Na Fase 4, conexão direta por IP entre amigos já basta.

---

## Decisão 6: ambiente Windows-first

Godot roda no Windows; o projeto vive no filesystem do Windows. Detalhes e a
armadilha de performance do WSL em `06-setup-ambiente.md`.

---

## Decisão 7: esquema de controle igual ao do League of Legends

O jogo usa o esquema de controle do **LoL**, não uma invenção própria.

### Por que

É o vocabulário que o público-alvo já tem no dedo. Todo jogador de MOBA sabe
que botão direito anda, que QWER são as habilidades e que o esquerdo é para
selecionar. Copiar isso elimina uma barreira de entrada inteira — e "esquema de
controle original" não é onde este projeto quer gastar novidade.

O Royal Crown, sendo um BR com influência de MOBA, seguia a mesma convenção.

### O mapeamento

| Entrada | Ação | Fase |
|---|---|---|
| **Botão direito** | Mover até o ponto do chão | **1.1 — feito** |
| Botão direito **em inimigo** | Ataque básico | 2.3 |
| Botão direito **segurado** | Movimento contínuo, seguindo o cursor | a decidir |
| **Botão esquerdo** | Selecionar alvo, interagir com UI | — |
| **Q / W / E / R** | Habilidades, miradas na posição do cursor | 3.x |
| **A** + clique | Attack-move | 6 |
| **S** | Parar | 2.3 |
| **Espaço / Y** | Centralizar e travar câmera no personagem | 1.3 |
| Cursor na borda da tela | Pan da câmera | 1.3 |

### Consequência que importa para a arquitetura

O botão esquerdo fica **reservado**. É tentador usá-lo para "clicar para andar"
porque é o gesto mais natural — mas ele é o botão de seleção e de UI, e roubá-lo
agora custa caro depois, quando houver HUD, inventário e alvo selecionável.

Para a mira de habilidade da Fase 3, a implicação é que **habilidade não é
clique**: é tecla + posição do cursor. O raycast tela → mundo do
`07-primeira-cena.md` continua sendo a peça reusada, mas disparado por
`_process` lendo a posição do mouse, não por um evento de clique.

### O que ainda não está decidido

- ~~**Botão direito segurado**~~ — **decidido na Fase 1.2:** implementado. Manter
  pressionado faz o personagem perseguir o cursor a cada tick de física. O
  clique isolado continua tratado por evento, para que um clique mais curto que
  um tick não se perca. Contornar obstáculo é justamente onde esse gesto
  aparece, então não fazia sentido adiar
- **Smart cast** (habilidade dispara na posição do cursor sem confirmação) vs.
  cast com indicador e clique de confirmação. No LoL é configurável; aqui,
  decidir na Fase 3

---

## Decisão 8: convenções de combate fechadas na Fase 2

`03-sistemas-de-jogo.md` deixou pontos em aberto no cálculo de dano. Fechados
assim, todos cobertos por teste:

### Crítico não se aplica a habilidade

O doc perguntava explicitamente. **Só ataque básico critita.** É a convenção do
LoL e tem uma razão prática: se habilidade crititasse, todo escalonamento
teria que ser balanceado contra a variância do crítico, e o dano de burst
viraria loteria.

Habilidade que *deva* crititar é exceção declarada no efeito, não regra geral.
Na API isso é o parâmetro `Damage.Source`.

### Roubo de vida incide sobre o dano pós-mitigação, escudo incluso

O doc diz "sobre o dano final aplicado, não sobre o bruto". O contraste que ele
estabelece é com o **bruto**, então bater num escudo ainda cura — que é a
convenção de MOBA. Se a intenção fosse "só o que saiu da vida", o teste
`test_bater_em_escudo_ainda_cura` é onde inverter.

`lifesteal` vale para ataque básico, `spell_vamp` para habilidade. A separação
é pela **fonte**, não pelo tipo de dano: habilidade que causa dano verdadeiro
ainda devolve spell vamp.

### Penetração: percentual primeiro, flat depois, nunca abaixo de zero

`defesa_efetiva = max(0, defesa * (1 - pen%) - pen_flat)`. A ordem importa e é
a convenção usual. Penetração zera a defesa, não a inverte.

### Defesa negativa amplifica com retorno decrescente

Redução de armadura pode levar a defesa abaixo de zero. Em vez de deixar a
fórmula `100/(100+d)` explodir, usa-se `2 - 100/(100-d)` — simétrica e
limitada. Sem isso, -100 de armadura daria divisão por zero.

### Ordem de aplicação de modificador

`final = (base + soma_dos_flats) * (1 + soma_dos_percentuais)`.

O ponto de fixar isso não é a fórmula em si: é que a **ordem em que os itens
foram equipados não pode mudar o resultado**. Sem convenção única, a ordem de
clique no inventário mudaria o dano do personagem.

### Sem GUT: arnês de teste próprio

O GUT é o framework de teste padrão da Godot, mas é addon externo a versionar.
Para lógica pura em `RefCounted`, descobrir métodos `test_` por reflexão e
contar falhas resolve em ~90 linhas (`tests/test_case.gd`).

Se a suíte passar a precisar de fixtures, mocks ou testes parametrizados,
trocar por GUT é barato — os testes em si mudam pouco.

---

## Decisão 9: habilidade como `Resource`, salva em `.tres`

Fecha a questão "formato de persistência dos dados de habilidade/item", que
estava marcada para a Fase 3.

Efeitos e habilidades estendem **`Resource`**, não `RefCounted`. Ganha-se:

- Serialização em `.tres`, que é **texto** — versionável no Git, revisável em
  diff, editável fora da engine
- Edição no Inspector, com `@export` tipado
- Sem escrever parser: a Godot já lê e valida

`Resource` **não é nó**. Continua rodando em teste unitário e no servidor
headless, que é a restrição que `03-sistemas-de-jogo.md` impõe a `core/`.

A alternativa era JSON com parser próprio. Só valeria se os dados viessem de
fora da engine — não é o caso.

### Um `Unit` para juntar as peças

`Stats`, `Health` e `StatusSet` estavam soltos, e quem os juntava era o
`Combatant`, que é Node. Efeito de habilidade precisa de um combatente
completo **sem** árvore de cena.

`Unit` (em `core/combat/`) reúne os três mais posição e direção. `Combatant`
passa a ser ponte: sincroniza a posição do corpo, aplica os deslocamentos
pedidos e repassa sinais. É o que permite testar habilidade sem abrir a engine
e é pré-requisito da Fase 4.5.

### Lentidão não é estado, é modificador de atributo

O vocabulário do doc lista `slow` junto de stun e root. Na implementação ele
não vai para o `StatusSet`: vira um modificador percentual de `move_speed`,
pelo mesmo sistema que os itens usam.

Lentidão **é** um atributo reduzido por um tempo. Modelá-la como estado
próprio duplicaria stacking e expiração sem ganhar nada — e o doc é explícito
sobre não construir um segundo sistema paralelo.

### Errar skillshot gasta a recarga

Descoberto testando a Fase 3.3. A regra original era "não pegou ninguém,
recusa sem custo", e ela produzia dois comportamentos para a mesma situação:
habilidade instantânea era devolvida, habilidade com tempo de conjuração não —
porque a recarga da segunda começa ao **iniciar**.

Regra corrigida: **só alvo único recusa**. Sem alguém apontado não há comando
a emitir, e recusar é o certo. Skillshot — `POINT` e `DIRECTION` — sai e gasta
mesmo errando.

O motivo é de design, não de implementação: devolver a recarga de quem errou
tornaria mira irrelevante. Num jogo cuja graça é acertar habilidade em alvo
que se move, isso destrói a mecânica central.

### Cada efeito declara quem recebe

Descoberto ao escrever o teste do critério da Fase 3.3, antes de a fase
começar: a terceira habilidade que `03-sistemas-de-jogo.md` sugere é **"um dash
com escudo"**, e o vocabulário não sabia expressá-la. O escudo ia para quem a
forma pegou — o inimigo.

`AbilityEffect.recipient` resolve: `TARGETS` (cada atingido) ou `CASTER` (o
conjurador, uma vez só, mesmo em área vazia). Foi a regra do projeto operando
como devia — generalizar em vez de escrever classe nova.

De quebra, isso separou dois eixos que estavam grudados no deslocamento:
**quem** é movido (`recipient`) e **para onde** (`mode`). Dash, empurrão e
puxão viraram combinações dos dois, e apareceu uma quarta de graça — empurrar
todos os alvos na direção da mira, em vez de para longe do conjurador.

### Deslocamento é pedido, não executado

`DisplacementEffect` não move ninguém: acumula em `pending_displacement`. Quem
move é a camada de gameplay, que tem física e sabe o que fazer quando o dash
bate na parede. Resolver colisão em `core/` exigiria conhecer a engine.

---

## Decisões ainda em aberto

| Questão | Quando decidir |
|---|---|
| ~~Renderer: Forward+ ou Compatibility~~ | **Resolvido: Forward+** (GPU dedicada, RX 7600 XT) |
| ~~Botão direito segurado = movimento contínuo?~~ | **Resolvido: sim** (Fase 1.2) |
| Ângulo e distância da câmera | Ajustar por sensação; `offset` e `smoothing` são `@export` |
| Smart cast vs. indicador + confirmação | Fase 3 |
| ~~Formato de persistência dos dados de habilidade/item~~ | **Resolvido: `Resource` em `.tres`** (decisão 9) |
| Onde hospedar o servidor dedicado | Fase 5 |
| Godot exportado para web vs. executável distribuído | Fase 5 |

---

## 10. Habilidade é uma lista de pulsos, não uma forma

**Decidido em 22/08/2026, na tradução do original.**

`Ability` passou a ser *ativação + mira + `Array[AbilityPulse]`*. Forma, filtro
e efeitos moram no pulso.

**Por quê:** uma `Skill` do original referencia até doze `Impact`, cada um com
`StartTime`, `StartPosition`, raio e alvos próprios — e cada impacto ainda pode
encadear outro, com geometria própria. 416 das habilidades traduzidas usam mais
de um pulso. Com uma forma só, traduzir obrigaria a descartar
golpes ou a fundi-los — e fundir muda a habilidade.

**Custa caro reverter?** Sim, e por isso está registrado. Todo `.tres` de
habilidade e toda leitura de `ability.form` na camada de gameplay dependem
disso. Foi feito com três habilidades no jogo; fazer depois de trinta seria
outra conversa.

**O que veio junto:**
- A âncora do pulso é calculada na conjuração e **congelada**. Recalcular
  faria a explosão perseguir quem saiu de perto.
- Pulso atrasado fica no `AbilityBook`, e sai por
  `AbilityEngine.resolve_scheduled()`. Quem tica precisa chamá-la.
- Interromper a conjuração **não** cancela pulso já disparado.

## 11. O corpus traduzido é JSON, e não 948 `.tres`

**Decidido em 22/08/2026.**

`data/traducao/*.json` guarda as 1126 habilidades e os 421 itens; os
carregadores (`AbilityCatalog`, `ItemCatalog`, `EffectFactory`) transformam em
`Ability` e `Item` sob demanda.

**Por quê:**
- `.tres` é o formato de quem edita à mão, e corpus gerado não se edita à mão.
- 1369 arquivos gerados afogariam o `git diff` de qualquer mudança futura no
  vocabulário. Em JSON, uma mudança de vocabulário é um diff legível.
- Carregar 2 MB e ~3200 efeitos a cada partida, para usar três habilidades,
  seria caro pelo motivo errado. Quem quer, chama.

**O que isso NÃO significa:** que habilidade do jogo vira JSON. As nossas
continuam `.tres`, editáveis no Inspector, uma por arquivo (decisão 9). O JSON
é o corpus de **referência**.

## 12. Marca é vocabulário, não sistema

**Decidido em 22/08/2026.**

`MarkSet` guarda estados com nome, prazo e pilhas, e não sabe o que eles
significam. Quem dá sentido é quem consulta.

**Por quê:** 114 buffs do original não concedem atributo, não causam dano e não
controlam; **62 deles têm literalmente só `Line`, `Rank` e `Duration`**. São
marcadores, e o jogo os consulta em outro lugar. Sem esta peça, a marca do caçador, o passo do combo e
a postura da arma traduziam para nada.

Uma marca que soubesse o que significa seria um sistema paralelo ao de efeitos,
e é isso que `03-sistemas-de-jogo.md` proíbe. Composta com `TriggerEffect` no
evento `MARK_MAXED`, ela dá "acerte três vezes e o quarto atordoa" sem uma
linha de código nova.
