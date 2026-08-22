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

## Decisões ainda em aberto

| Questão | Quando decidir |
|---|---|
| ~~Renderer: Forward+ ou Compatibility~~ | **Resolvido: Forward+** (GPU dedicada, RX 7600 XT) |
| ~~Botão direito segurado = movimento contínuo?~~ | **Resolvido: sim** (Fase 1.2) |
| Ângulo e distância da câmera | Ajustar por sensação; `offset` e `smoothing` são `@export` |
| Smart cast vs. indicador + confirmação | Fase 3 |
| Formato de persistência dos dados de habilidade/item | Fase 3 |
| Onde hospedar o servidor dedicado | Fase 5 |
| Godot exportado para web vs. executável distribuído | Fase 5 |
