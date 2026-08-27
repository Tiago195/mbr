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
- 1547 arquivos gerados afogariam o `git diff` de qualquer mudança futura no
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

## 13. O campeão vem de dado, e os `.tres` feitos à mão continuam valendo

**Decidido em 22/08/2026.**

`ChampionSelector` (em `gameplay/`) lê `ActorCatalog` + `AbilityCatalog` e
escreve os atributos no `Combatant` e o kit no `AbilityCaster`. As habilidades
`.tres` do Inspector continuam sendo o padrão: esvaziar `champion_id` volta a
elas, e as duas fontes passam pelo mesmo `AbilityBook`.

**Por quê:** um caminho só levaria a jogar fora as três habilidades feitas à
mão, que são o que se edita para experimentar design. Duas fontes com um
destino comum custam um `if` e preservam o modo rápido de testar uma ideia.

**Três consequências que não são óbvias:**

- **`DefaultSkillId_N` aponta para a linha-modelo do grupo, não para a
  habilidade.** `Rank 0` existe para a interface mostrar a habilidade ainda não
  aprendida e não referencia impacto nenhum. O perfil guarda o **grupo**; o
  ranque sai de `AbilityCatalog.rank_for_level()` com o nível. Guardar o id
  daria um Q que aperta, gasta mana e não faz nada.
- **Trocar de personagem SUBSTITUI o conjunto de atributos, não soma.**
  `ActorProfile.apply_stats_to` reescreve tudo, com um `fallback` para o que só
  o Inspector declara (`crit_chance`, `ability_power`). Somar deixava resíduo
  invisível: 28 dos 33 campeões declaram `out_of_combat_health_regen` e cinco
  não.
- **A suprema recebe uma recarga inventada de 45 s.** 31 das 32 supremas do
  original têm `CoolTime = 0` porque enchem batendo, e carga de suprema é
  lacuna registrada. Copiar o zero daria uma suprema disparável a cada quadro.
  Quando a carga existir, o número sai — e `ActorProfile.ultimate_uses_charge`
  já marca quem depende dele.

## 14. Alcance e cadência de ataque vêm da habilidade, não dos atributos

**Decidido em 22/08/2026.** Não é escolha de arquitetura: é como o original
guarda o dado, e demorou a aparecer.

`AI_SkillRange` e `CoolTime` da habilidade `DefaultSkillId_1` são o alcance e o
intervalo entre ataques básicos do personagem — 2 m e 0,8 s no Leo, 6 m e
0,73 s na Bella. **Nenhum dos dois está em `StatType_N`.**

**Por que registrar:** sem ler de lá, todo campeão herdaria o padrão da classe
(2,5 m, um ataque por segundo) e a atiradora do original viraria corpo a corpo
— sem erro, sem lacuna, sem sintoma até alguém comparar dois campeões. É a
terceira vez que essa espécie de defeito aparece neste projeto, e todas as três
foram achadas conferindo se o RESULTADO faz sentido, nunca se a coluna foi
lida.

## 15. Projétil voa; o dano acontece no impacto

**Decidido em 22/08/2026**, depois de o usuário testar: *"os projéteis estão
causando dano assim que é clicado, e não se realmente acerta o alvo"*.

Ele estava certo, e o código admitia em comentário: *"o dano já saiu quando a
esfera parte. É mentira visual, e é consciente"*. A forma `PROJECTILE` era
resolvida como uma linha, no instante do clique, e a esfera na tela fazia uma
viagem paralela que não decidia nada.

Agora `ProjectileSet` (em `core/`) guarda os projéteis no ar. A cada tique cada
um avança `projectile_speed * delta`, e quem estiver no trecho percorrido é
atingido. `AbilityEngine.advance_projectiles()` aplica os efeitos no impacto.

**Por quê:** com dano no clique, mira não vale nada. Quem estava na linha
naquele milissegundo levava dano mesmo saindo de lá, e quem entrasse na frente
depois não levava nada — as duas coisas que o jogador tenta fazer num MOBA.
São 359 pulsos de projétil no corpus traduzido, em 223 habilidades.

**Cinco consequências que não são óbvias:**

- **Varredura, não amostra.** Testar só a posição do fim do tique faz um
  projétil rápido atravessar alvo estreito: a 60 m/s um tique de 60 Hz anda
  1 metro, e um alvo de meio metro cabe inteiro no meio do salto. Não dá erro —
  o tiro passa direto. Há teste, e ele fica vermelho se a varredura virar
  amostra.
- **Cada flecha do leque voa sozinha.** Antes, `spread_count = 3` era uma forma
  que perguntava "está dentro de alguma das três direções?", e o teto de um
  alvo valia para o leque inteiro: três flechas acertavam uma pessoa só.
- **Efeito do CONJURADOR sai no lançamento; efeito de ALVO sai no impacto.** O
  escudo de quem atira não depende de a flecha acertar — se dependesse, seria
  um gatilho, e o vocabulário já tem `TriggerEffect` para isso. Sem separar, o
  escudo saía de novo a cada inimigo perfurado.
- **`CastResult.targets` vazio deixou de querer dizer "errou"**; quer dizer
  "ainda não se sabe". Daí `CastResult.launched` e `in_flight()`.
- **A esfera na tela segue o projétil de verdade**, e o raio dela sai de
  `pulse.width`. Uma esfera menor que a colisão faz o jogador achar que errou
  quando acertou.

**O que ele NÃO faz, e é decisão:** parar em parede. `core/` não conhece
colisor, e resolver isso exigiria a camada de gameplay responder a cada tique.
`ThroughObstacle` já é lacuna registrada do original; o projétil entra nela em
vez de inventar meia solução.

## 16. Toda telegrafia é conferida por assinatura, e a conferência se testa

**Decidido em 22/08/2026**, ao fechar a lacuna dos golpes invisíveis, depois de
**oito rodadas de revisão adversarial — sete reprovando**.

A tela desenhava só o primeiro pulso de cada habilidade. `CastResult` passou a
dizer qual pulso saiu e onde, e `AbilityCaster` desenha todos — cada golpe
atrasado no momento em que sai, não na conjuração (anunciar todos entregaria ao
adversário onde o segundo cai). Cone e trapézio ganharam malha de verdade;
eram desenhados como faixa retangular.

**O que vale além desta lacuna é como ela foi conferida.** `tools/sondar_campeoes.gd`
compara uma ASSINATURA de cada marca contra o que a engine declarou ter
resolvido. A assinatura chegou à forma atual perdendo sete versões mais fracas,
e cada perda foi o mesmo formato de erro:

| Versão | O que deixava passar |
|---|---|
| contar nós | cone desenhado como faixa |
| classe da malha | cone com o raio do círculo e ângulo qualquer |
| geometria da malha | marca no lugar errado, apontando para o lado errado |
| lugar e lado | marca a 1% do tamanho — a escala não entra na malha |
| caixa da malha | faixa virando muro de 8 m, disco virando tubo de 40 |
| transform do nó | **o `MeshInstance3D` filho**, que é quem renderiza |

A forma que fechou: **classe + caixa no mundo do nó que renderiza + vértices +
lugar + lado + visibilidade em árvore + camadas de render + vida**.

**Três regras que saíram disso e valem para qualquer conferência do projeto:**

1. **Quem junta o dado não decide.** Toda função que devolvia veredito pôde ser
   esvaziada sem ruído. As que devolvem a MEDIÇÃO, não — quem decide é o laço
   que chama, e o piso de trabalho é sobre o mesmo dado que ele lê.
2. **Fixture degenerado é cobertura falsa.** O conjurador nascia na origem do
   mundo e mirava no eixo: 17 de 20 âncoras davam (0,0) e todas as direções
   davam a mesma. Mutação que plantasse toda marca na origem era um no-op
   literal. Três dimensões da conferência nasceram cegas por isso, não por
   falta de código.
3. **Fonte única troca uma cegueira por outra.** Malha e raio virarem função
   compartilhada elimina a divergência entre desenho e expectativa — e torna a
   função invisível para quem compara os dois. A contrapartida vai para
   `tests/`, onde ela é matemática pura: é por isso que `test_telegrafia.gd`
   afirma que marca de chão é achatada, fica acima do chão, dura o bastante
   para ser vista e está em alguma camada de render.

**E a circularidade que não se resolve medindo mais.** A âncora do desenho e a
âncora do acerto são a MESMA: trocar `Origin.PREVIOUS` pelo ponto mirado deixa
marca e dano concordando, os dois errados. O que quebra isso é afirmar a
CONSEQUÊNCIA de projeto — dois bonecos em posições conhecidas e a pergunta
"qual dos dois?". Está em `tests/test_pulsos.gd`.

**Dois defeitos de jogo caíram no caminho, e nenhuma releitura os teria
achado:** quatro projéteis de velocidade zero na suprema do Kaiba (que ficavam
no ar para sempre, com a esfera parada na tela), e todo projétil que acertava
dentro do próprio tique em que nascia — os rápidos e de curto alcance — nunca
sendo desenhado.

## 17. A suprema não tem recarga: ela enche agindo

**Decidido em 22/08/2026**, fechando a lacuna mais cara da tradução.

No original a suprema tem `CoolTime = 0` em 31 das 32, e `LevelUpUltimateCharge
= 1000` diz quanto ela custa.

**Os "31 das 32" são linhas DEDUPLICADAS.** `actor_xml` e `actor_2_xml` repetem
Ids, e somar as duas cruas dá 50 supremas e 48 com recarga zero. Contando como
o jogo conta — um ator por Id —, são 40 jogadores, 32 com suprema, 31 com
recarga zero e 31 com carga. É a mesma ambiguidade que já produziu "58
campeões" onde havia 40; toda contagem de ator neste projeto é deduplicada. O ganho vem de `UltimateCharge`, declarado em
**517 habilidades**: o ataque básico rende **200 nos 31 campeões**, as demais
rendem de **33 a 600**, e a suprema rende 0 — ela consome.

Enquanto o sistema não existia, a suprema recebia uma recarga **inventada de
45 segundos**. Isso não era só impreciso: invertia o que ela é. Uma suprema com
recarga é uma questão de esperar; uma suprema com carga é uma questão de jogar.

**A carga é um `ResourcePool`**, o mesmo pote da mana com outro teto
(`Stat.Id.MAX_ULTIMATE_CHARGE`) e sem atributo de regeneração. Máximo zero
desliga o sistema — mob, boneco de treino e habilidade feita à mão ficam de
fora sem um caso especial em lugar nenhum, exatamente como `MAX_MANA` já fazia.

**Cinco consequências que não são óbvias:**

- **A carga nasce VAZIA.** `ResourcePool` enche no `_init`, o que está certo
  para mana e é o oposto do certo aqui: a suprema pronta no primeiro segundo da
  partida é o contrário de um recurso que se ganha.
- **Enche ao CONJURAR, não ao acertar.** A coluna é da habilidade, não do
  impacto — o original não tem granularidade por acerto, e "só enche se
  acertar" seria invenção nossa. O ataque básico é a exceção, e por dado, não
  por gosto: ele não passa pelo motor de habilidade, e `Unit.basic_attack` sabe
  se errou. Ataque cego ou esquivado não rende.
- **"Ser a suprema" é papel no kit, não propriedade da habilidade.**
  `uses_ultimate_charge` é marcado na CÓPIA que `ActorProfile.ultimate_for`
  entrega, nunca no corpus: o catálogo dá a mesma instância a todos, e a mesma
  habilidade emprestada a um mob não seria suprema de ninguém.
- **A recusa tem status próprio** (`NO_CHARGE`), e não `ON_COOLDOWN`. O que
  falta é AGIR, não esperar — dizer "em recarga" mandaria o jogador parar
  justamente quando ele deveria bater.
- **O número inventado sobreviveu, para um ator.** Suprema que não declara
  carga E tem `CoolTime = 0` sairia a cada quadro; ela continua com os 45 s
  declarados como lacuna. Eram 31; é 1.

**Uma armadilha paga aqui:** o pote da carga não era tickado por
`Unit.advance_time`, e por isso a guarda que impedia a regeneração era código
morto — mutá-la passava verde. O pote passou a ser tickado, a guarda virou
desnecessária (`Stats.get_value` de um id que não é atributo já devolve zero) e
saiu. Guarda que nunca roda é indistinguível de guarda que não funciona.

## 18. A cadência do ataque básico mora no `Unit`, e habilidade a zera

**Decidido em 22/08/2026**, fechando a terceira lacuna da tabela das seis.

`ResetAttackCoolTime` do original: conjurar solta o próximo ataque básico na
hora, em vez de esperar a velocidade de ataque. **259 habilidades declaram
verdadeiro e 262 declaram falso**; pelo caminho que o jogo percorre, são
**44 dos 127 espaços de campeão**, em **22 campeões**.

**O 521 anterior contava outra coisa.** O censo de colunas do tradutor conta a
COLUNA presente, e `"False"` é string não-vazia — 259 + 262. É a mesma
armadilha que já deu "123 `FollowTarget` em 124 habilidades". As duas medidas
são afirmadas separadamente em `tools/conferir_numeros.py`, direto no XML, para
que confundi-las de novo dê vermelho.

### O que mudou de lugar, e por quê

A cadência era um `float` privado dentro de `player.gd`. Ela virou
`Unit.attack_cooldown`, em `core/`. **Não é arrumação:** `AbilityEngine` é
estática, roda no servidor headless e não conhece nó — ela não tem como zerar
um contador guardado numa cena. Enquanto a cadência morasse lá, esta lacuna era
inimplementável sem furar a regra de ouro 3.

Três consequências que caíram de graça:

- **A cadência agora é testável.** `tests/` só alcança `scripts/core/`, e o
  laço de ataque nunca teve teste nenhum.
- **O ataque básico ficou autoritativo.** `basic_attack()` é quem recomeça a
  cadência; quem manda atacar só pergunta `attack_is_ready()`. Antes, quem
  chamasse `basic_attack` duas vezes no mesmo tique batia duas vezes.
- **Cegar continua diferente de desarmar.** O ramo do cego sai cedo de
  `basic_attack`, e gasta a cadência do mesmo jeito: o ataque saiu e errou.

### Ao conjurar, não ao acertar

Mesma leitura de `ultimate_charge_gain`, e pelo mesmo motivo: a coluna é da
habilidade, não do impacto. O original **não tem onde declarar** "só se
acertar", e inventar essa condição tornaria o reset inútil justamente nas
habilidades em que ele mais importa — as de projétil, cujo acerto acontece
segundos depois do clique, quando a janela do ataque já passou.

O reset sai dentro de `_charge`, junto da mana e da recarga, e por isso herda a
regra que já valia para as duas: **quem tem a conjuração cortada no meio não
recupera nada, e conjuração RECUSADA não gasta nem devolve nada.** Essa segunda
metade é a que tem consequência de jogo: sem ela, apertar Q com Q em recarga
seria um reset de auto-ataque de graça — dano extra por apertar botão inútil.

### Como isto é conferido

- `tests/test_reset_de_ataque.gd`: 18 testes, dos quais **4** são sobre quem
  **não** tem o direito de zerar: recarga, mana, controle de grupo e suprema
  sem carga. (Dizia "metade deles", que seriam nove; são quatro, e o número
  agora é conferido.)
- `tools/sondar_campeoes.gd`: planta a cadência num valor não-zero antes de
  cada conjuração e exige que ela fique em zero exatamente nos espaços que
  declaram o reset. **A sentinela é o ponto:** com a cadência já em zero,
  "zerou" e "não mexeu" seriam a mesma leitura, e a mutação que zera tudo seria
  um no-op literal — foi o que já aconteceu com posição, direção e carga.
- `tools/sondar_ritmo.gd`, **sonda nova**, explicada abaixo.
- Cada mutação foi aplicada uma de cada vez e a ferramenta que deveria
  enxergá-la foi exigida em vermelho — inclusive a que arranca a sentinela da
  própria sonda. Nenhuma delas reprova as três ferramentas: cada uma reprova a
  sua, e é essa correspondência que se está testando.

### A sonda de ritmo, e o buraco que ela fecha

A revisão adversarial derrubou a primeira versão desta decisão com uma mutação
de uma linha: trocar `if _combatant.unit.attack_is_ready()` por `if true` em
`player.gd` — apagando a cadência do jogo inteiro — deixava **as três
ferramentas verdes**. O comportamento real: 120 golpes em dois segundos no
lugar de 3.

Nenhuma das duas conferências podia pegar isso. A suíte não alcança
`gameplay/`; `sondar_campeoes.gd` roda tudo dentro de um único `process_frame`
de propósito, e por isso `_physics_process` nunca é chamado lá. E o buraco
tinha acabado de ficar mais perigoso: quem PERGUNTA se pode bater passou a
morar em `Player._physics_process` e quem faz o contador andar mora em
`Combatant._physics_process` — duas metades que precisam continuar se
encontrando, e nada as via juntas.

`tools/sondar_ritmo.gd` avança quadros de física de verdade, conta golpes e
mede o espaçamento entre eles. Duas coisas que ela ensinou no caminho:

- **Folga generosa é o mesmo que não conferir.** Com uma folga de um golpe
  para cada lado, `advance_time(0.0)` — que faz o personagem bater uma vez e
  travar para sempre — passava verde com 1 golpe onde se esperavam 2,66. O que
  fechou esse buraco foi apertar a faixa para `floor(N)` ou `floor(N)+1`.
- **E o espaçamento fecha a classe, mas é outra conferência e outra mutação.**
  A que a alcança é `advance_time(delta * 0.5)`: saem 2 golpes — número que a
  faixa ACEITA — nos quadros `[0, 91]`, e só o vão denuncia. A primeira versão
  desta decisão creditava o espaçamento pelo escape do `advance_time(0.0)`, que
  produz um golpe só e portanto vão nenhum. **Justificativa gravada é
  afirmação**, e essa estava errada dentro do texto escrito para consertar um
  erro do mesmo tipo.
- **O par de controle é obrigatório.** A sonda confere que uma habilidade
  zeradora produz golpe no quadro seguinte E que uma não-zeradora não produz.
  Sem a segunda metade, a primeira não prova nada sobre o reset.

### O que sobrou sabido, e não fechado

Duas observações da revisão que não bloqueiam e ficam registradas em vez de
sumirem:

- A varredura de avisos de `conferir_numeros.py` não pega um ramo que copie
  **exatamente** a linha que `avisar()` usa para montar o rótulo. Medido: um
  ramo assim ainda faz a ferramenta sair 1, porque o piso o cobra — degrada
  para o piso, e o piso falha fechado. É a diferença entre não detectar e
  aprovar por engano.
- O desconto do ramo da engine é `1` escrito à mão, enquanto o do XML é
  contado no fonte. Está certo hoje e foi conferido por um caminho
  independente: com as DUAS ausências ao mesmo tempo, exigidas e conferidas
  batem em 126 — o que não bateria se o `1` estivesse errado. Fechá-lo é pôr
  marcadores no ramo da suíte e contar, o mesmo truque do bloco do XML.

## 19. A âncora persegue quando o dado manda, e só em golpe atrasado

**Decidido em 23/08/2026**, fechando a quarta lacuna da tabela das seis.

**A lacuna estava mal descrita, e remedir foi o trabalho.** Ela vivia como
"área que acompanha o alvo, `FollowTarget`, 1967". Três coisas estavam erradas:

1. **A coluna não é booleana.** Vale `None` em 1552 impactos, `User` em 353 e
   `Target` em 62. O 1967 era a soma dos três — o censo da coluna presente, a
   mesma armadilha do `ResetAttackCoolTime` que parecia 521 e era 259.
2. **A maioria acompanha o CONJURADOR, não o alvo.** 353 contra 62. "Área que
   acompanha o alvo" descrevia a minoria.
3. **Só muda alguma coisa em pulso ATRASADO.** Num pulso instantâneo a âncora
   já é calculada no lugar certo, e perseguir por zero segundo é um no-op.
   Dos **354 pulsos** que declaram perseguição no corpus, **258 são atrasados**
   — e são esses que mudam de comportamento; os outros **96** já saíam certos.

   **Este número já esteve errado, e o erro é instrutivo.** A primeira versão
   dizia "353 são instantâneos", medido por `duration == 0`. Mas a definição de
   instantâneo é a que a própria frase dá e a que o motor usa — `delay > 0`
   decide sozinho entre sair agora e ficar agendado (`ability_engine.gd`). Pelo
   eixo certo são 96, não 353. E o 353 não era um dígito solto: é exatamente a
   contagem de `User` do item 1, ou seja, eu tinha medido a coluna outra vez em
   vez de medir o comportamento. **Escolher o eixo errado dá um número que
   parece plausível e conta a história oposta:** com 353 de 354 instantâneos, a
   mudança seria marginal; com 258 atrasados, ela é ampla.

Pelo caminho que o jogo percorre, a lacuna vale para **27 dos 127 espaços de
campeão**, em **18 campeões** — não 35.

### O que muda

`AbilityPulse.Follow` (`NONE` / `CASTER` / `TARGET`). Em `resolve_scheduled`, a
âncora é recalculada no instante em que o golpe sai, e o deslocamento
(`forward_offset`, `side_offset`) é reaplicado sobre a base nova.

**A âncora congelada continua sendo o padrão, e isso é metade da decisão.** São
940 dos 1198 pulsos atrasados do corpus: área no chão não persegue ninguém, e
foi assim que ela foi projetada de propósito. O que mudou é que quem declara
perseguição deixou de herdar esse comportamento.

Sintoma que isso corrige: um combo de dois golpes em que o personagem anda no
meio. Com atrasos de 0,04 a 2,0 s e passo de 3,3 m/s, meio segundo são 1,6 m —
o segundo golpe saía de onde o personagem esteve, não de onde ele está.

### Como isto é conferido

- `tests/test_perseguicao.gd`: 10 testes, e a metade que mais importa é a que
  confere que quem **não** declara continua congelado. A conferência decisiva
  não é a coordenada: é **quem leva o dano** — o conjurador anda até um segundo
  alvo e o golpe tem que trocar de vítima.
- `tools/sondar_campeoes.gd`: o conjurador **salta 30 m** depois de conjurar e
  antes de os golpes atrasados saírem. Sem o salto, "acompanhou" e "ficou
  congelada" são a mesma leitura.
  Medido: **48 seguiram o conjurador** e **160 ficaram**.
- **O tamanho do salto é medido, não escolhido.** A comparação é por distância
  relativa e cega quando o deslocamento do pulso passa de meio salto: forçando
  todos os pulsos a perseguir, um salto de 4 m flagrava 156 dos 160 que deviam
  ficar; 12 m, 159; 30 m, **160**.
- **A soma tem que fechar.** `Follow.TARGET` ficou fora de todos os ramos da
  conferência numa revisão — nem conferido nem publicado —, e nenhum piso viu,
  porque os pisos contavam categorias e o que escapava não estava em categoria
  nenhuma. Hoje o total de golpes atrasados que chegam é comparado com a soma
  das cinco contas, e isso pega qualquer valor novo do enum que alguém
  acrescente sem tratar.
- **O ALVO salta também, e por um eixo diferente.** Os 11 pulsos `TARGET` do
  corpus são `Origin.TARGET_UNIT` com deslocamento zero, então a âncora
  congelada já nasce em cima do alvo: mexendo só no conjurador, "acompanhou o
  alvo" e "ficou congelada" davam a mesma leitura, e a conferência **aprovava a
  perseguição do alvo inteiramente desligada**. É o mesmo fixture degenerado
  que o salto do conjurador existe para evitar — cometido de novo, na metade de
  baixo, dentro da revisão que o corrigiu em cima.
- **A mira da sonda passou a apontar unidade** quando a habilidade tem golpe
  que precisa de uma (`Origin.TARGET_UNIT` ou `Follow.TARGET`), mesmo sendo
  habilidade de ponto. Sem isso os 3 espaços `TARGET` chegavam sem alvo e o
  ramo nunca rodava: **3 seguiram o alvo** hoje, contra 0 antes.
- **O fixture é normalizado no COMEÇO de cada espaço, não restaurado no fim.**
  Restaurar no fim depende de todo caminho de saída restaurar, e um deles não
  restaurava: medido, o conjurador chegava ao último campeão em x=1293 em vez
  de x=3 — 43 saltos de 30 m que ninguém desfez. Com coordenadas dessa ordem a
  assinatura das marcas diverge na terceira casa e a telegrafia reprova por
  arredondamento.
- A comparação é **estrita** (`<`, não `>` invertido) justamente para o salto
  ser obrigatório: com salto zero as distâncias empatam e a conferência acusa,
  em vez de passar por empate.
- **17 golpes ficam fora do alcance da sonda**, e o número é publicado: numa
  conjuração com tempo de canto as âncoras nascem quando o canto TERMINA, ou
  seja, já depois do salto. Comparar assim acusava 13 golpes de 2 campeões de
  perseguirem sem declarar — e o defeito era da conferência.

### Duas armadilhas pagas aqui

- **Passo por tique acumulava.** A primeira versão da sonda andava 0,06 m por
  tique; ao longo dos 1200 tiques do orçamento isso virava 72 m, vazava de um
  espaço para o outro até as coordenadas passarem de mil, e aí a assinatura das
  marcas divergia na quarta casa decimal. A telegrafia reprovava por
  arredondamento. Virou salto único — e a restauração ao fim de cada espaço,
  que foi a primeira resposta, também não sobreviveu: ela dependia de todo
  caminho de saída restaurar, e um deles não restaurava. Hoje o fixture é
  normalizado no COMEÇO de cada espaço, como está descrito acima.
- **`"a" + "b" % [...]` aplica o `%` só à segunda parte.** A Godot reclama no
  stderr sem derrubar nada, e o critério deste projeto é stderr de zero bytes.

### E uma coisa que não é da lacuna 4: as sondas passaram a ter o stderr lido

Descoberto no meio desta revisão, e vale para o projeto inteiro.

Um acesso a propriedade inexistente dentro de uma sonda **não aborta a função
que o causou**: empurra um erro, devolve nulo, e o laço segue. A guarda
`falhas is Array` nunca dispara. Medido, com o acesso que eu mesmo escrevi por
engano: `EXIT=0`, 323 bytes de stderr, e `[ok] todos os campeões trocaram e
conjuraram sem erro` no stdout.

As duas sondas são a **única** cobertura automática de `gameplay/`, e nada lia
o stderr delas: `conferir_numeros.py` aplicava o classificador de
`SCRIPT ERROR` / `leaked at exit` / código de saída só a `tests/run_tests.gd`,
e nunca as executava.

Agora executa as duas, com o mesmo rigor e mais um item: **a marca de sucesso
tem que aparecer no stdout**, para uma sonda que morra calada não passar por
aprovada. `_classificar_sonda` é função pura e tem os seis cenários no
autoteste, incluindo o que aconteceu de verdade. Reproduzido: com o acesso ruim
de volta, `exit 1` e "a sonda de campeões NÃO passou (`SCRIPT ERROR` no
stderr)"; apagando a marca de sucesso da sonda de ritmo, "não imprimiu a marca
de sucesso".

Custo: `py tools/conferir_numeros.py` passou a rodar três processos da engine.
É lento e é o preço de a ferramenta ser o lugar onde tudo se encontra.

### E daí saiu uma categoria nova: limite publicado

Um número que uma sonda imprime **a cada execução** e um documento republica é
uma classe própria, e ela envelhece sozinha. Foi o caso de "8735 assinaturas"
no `CLAUDE.md` contra 9667 medidos — número que esta lacuna moveu duas vezes,
nas mesmas três linhas em que a contagem de testes foi atualizada.

`LIMITES_DA_SONDA` cruza cada um com a saída da própria sonda, **na mesma
execução**. Piso e não igualdade, e órfão dos dois lados é falha.

**A primeira versão dessa tabela fechou a classe só para o `CLAUDE.md`**, e os
quatro números que esta decisão republica podiam ir a 480/30/1600/170 com a
ferramenta dizendo "todas batem" — enumerar o arquivo em vez da classe é a
mesma forma do desconto que foi escrito para uma ausência benigna e não para a
irmã. Hoje cada limite carrega a lista de documentos onde é republicado, e cada
um é chaveado à SUA sonda, para a segurança não depender de os vocabulários das
duas não se cruzarem.

A fronteira é nítida, e vale registrá-la porque ela impede que isto vire "todo
número de documento":

| espécie | exemplo | como se confere |
|---|---|---|
| derivado do corpus | 354, 258, 96, 27, 18 | `c.afirma` contra o JSON |
| **impresso pela sonda toda execução** | **48, 3, 160, 17, 9667** | `LIMITES_DA_SONDA` |
| medição histórica, não re-derivável | 156/159/160 conforme o salto, x=1293, 27 a 32 golpes | não se confere, e está certo: reproduzi-los exige aplicar a mutação |

Varri as duas sondas atrás do que sobrou: fora esses, todo número de resumo que
aparece num documento é coincidência de valor (o `33` de "sondando 33 campeões"
é o mesmo 33 de "campeões com kit", que já é conferido contra o corpus; o `120`
da sonda de ritmo é o mesmo 120 da mutação, já conferido por derivação).

### A terceira recorrência, e a peça que faltava

O custo que um ramo benigno declara ao piso publicado já ficou errado **três
vezes**, sempre do mesmo jeito e nunca pelo mesmo motivo:

1. O desconto foi escrito para a ausência do XML e não para a da engine.
2. Trocado por "qualquer aviso dispensa o piso inteiro", ficou estritamente
   mais fraco: dava para perder 27 conferências junto com uma ausência benigna.
3. Passou a declarar `len(SONDAS)`, que responde *"quantas sondas"* quando a
   pergunta é *"quanto deste bloco depende da engine"* — e quebrou no primeiro
   crescimento que não foi uma sonda, os nove pares `(limite, documento)`.

O lado do XML nunca sofreu nenhuma das três, e o motivo é estrutural:
`_afirmacoes_que_dependem_do_xml()` **conta o próprio fonte** entre marcadores
em vez de acreditar num literal. Ele absorveu a mesma expansão desta lacuna sem
uma edição — era 16, virou 19, e ninguém precisou saber.

Do lado da engine a contagem textual não serve, porque os incrementos estão
dentro de laços. Então a derivação é sobre as **listas que os laços percorrem**
— `len(SONDAS)` mais a soma dos pares de `LIMITES_DA_SONDA` — e, o que faltava
nas três vezes, **a declaração é conferida contra o trabalho**: com a engine
presente, o que o bloco realmente gastou tem que bater com o que ele diz custar.

Ela achou dois defeitos meus na própria execução em que nasceu: eu media o
intervalo errado (declarado 12, feito 28, porque entre os dois trechos há
dezenas de afirmações que não dependem da engine) e a condição estava atrelada
a *"não houve aviso"* em vez de *"a engine está presente"* — o que a fazia sumir
junto com a ausência do XML, que não tem nada a ver com ela. **Cada degradação
tem que afrouxar só o que ela própria impede.**

Os quatro caminhos são exercitados: com tudo (174), sem a engine (161), sem o
XML (155), sem os dois (142) — todos exit 0.

### A quarta recorrência, e o que finalmente a fechou

A terceira correção derivava o custo de **dois intervalos delimitados à mão** no
corpo de `main()`. Era um literal com outra roupa: `len(SONDAS)` acreditava num
número, e os colchetes acreditavam numa **localização**. Uma afirmação
dependente da engine posta fora deles gastava sem entrar na conta, e a mesma
falha voltava pela quarta vez — com a autoconferência dizendo, satisfeita,
`declarado 13 = feito 13`.

O que fecha é registrar o gasto **onde a afirmação acontece**:
`c.contar(com_engine=True)`. Declaração e trabalho ficam amarrados no mesmo
lugar, que é a propriedade que os marcadores do bloco do XML ganham de graça
por andarem junto com o código.

Sobraram dois modos de escapar, e os dois viraram varredura do próprio fonte:

- **Um portão de engine novo.** `main()` tem quatro `godot is (not) None`; um
  quinto acusa e obriga quem o escrever a decidir se ele gasta.
- **`c.conferidas += 1` cru.** Escrito dentro do bloco existente, gastava sem
  marcar: medido, `exit 0` com a engine e cobrança a mais sem ela. Hoje
  `contar()` é o único lugar que mexe no campo, e a varredura recusa qualquer
  outro. As duas linhas da varredura montam o literal em duas partes para não
  se contarem — mesmo truque dos marcadores do XML.

As sete combinações são exercitadas: os quatro ambientes saem 0; portão novo,
incremento cru e gasto marcado sem atualizar o custo saem 1, cada um com a
mensagem que diz o que fazer.

**A armadilha de bash que isto custou**, e que vale para o projeto: escrever
`\b` numa regex através de um heredoc gravou o byte 0x08 (backspace) no
arquivo. A regex parava de casar, a varredura media zero, e a saída em cp1252
escondeu a linha de falha do meu próprio `grep` por acento. Conferir com
`cat -A` quando uma regex "correta" não casa.

### A quinta, e o que a fechou de vez

Registrar o gasto no site fechou a distância entre **onde o trabalho está** e
**onde ele é contado**. Deixou aberta a distância entre *contado* e *contado
como dependente da engine* — e essa dependia de `com_engine=True`, um argumento
opcional que quem escreve precisa lembrar.

Quinto disfarce do mesmo defeito, e o mais bem escondido:

| versão | acreditava em |
|---|---|
| `len(SONDAS)` | um número |
| os dois colchetes | uma localização |
| `+ 2` | um número que a autoconferência confere |
| `com_engine=True` | **a memória de quem escreve a próxima afirmação** |

A edição que passava pelas três defesas era a mais natural que existe: uma
afirmação nova dentro do portão que já existia, chamando `contar()`. Portões
continuavam quatro, o incremento passava por `contar()`, e `declarado` e
`com_engine` seguiam ambos 13.

**O que fecha é a região decidir, não o argumento.**
`with c.dependendo_da_engine():` envolve cada bloco gated, e tudo que for
contado lá dentro conta como dependente da engine — sem ninguém dizer nada.
"Depende da engine" virou propriedade de **onde o código está**, imposta pelo
objeto, que é a mesma propriedade que os marcadores do bloco do XML têm de
graça por andarem junto com o código.

**O modo de falha é o que tornava isto urgente:** verde na máquina que escreve,
vermelho só na máquina sem a Godot. Quem introduz nunca vê; quem clona, sim. É
essa assimetria que explica as cinco recorrências.

## 20. A "lacuna do arco" não é lacuna de combate: é asset

**Decidido em 23/08/2026**, antes de escrever uma linha — remedindo, como as
quatro lacunas anteriores ensinaram.

`ZMoveCurvePath` e `YMoveCurvePath` **não contêm números**. Contêm caminhos de
arquivo: `GameData/Curve/MoveCurve_AliciaBladeRush`, `CCCurve_KaibaRushZ`. A
curva em si vive num asset que não extraímos e que não é tabela de design — é
animação. Pela regra de escopo (`docs/01`), arte não entra.

Medido pelo caminho que o jogo percorre: **22 dos 127 espaços de campeão**
citam alguma curva — 6 em Y (arco vertical) e 16 só em Z (perfil de velocidade
ao longo do deslocamento). E dentro desses 22 espaços há **3 efeitos de
deslocamento** ao todo. Ou seja, na esmagadora maioria a curva descreve o
movimento da ANIMAÇÃO, não o do combate.

**O projeto já tinha decidido isto, noutro lugar.** `docs/10` lista "Curva de
deslocamento, `MoveCurve`, 154" na seção *"Precisam de sistema que não é de
combate"*, com a justificativa exata: *"É camada visual, e depende de asset"*.
A tabela das seis lacunas a listava assim mesmo, como se fosse trabalho de
combate — duas partes da documentação discordando, e a tabela ganhando por ser
a que se lê primeiro.

O que dela é mecânico já existe: deslocamento existe (`DisplacementEffect`) e
ficar no ar existe (`StatusSet.Kind.AIRBORNE`). O que falta é a **forma** do
movimento, que só se vê com modelo 3D e animação — Fase 6.

**Fica registrada como lacuna de ARTE**, e sai da tabela de trabalho de
combate. Quando os personagens deixarem de ser cápsulas, ela volta com o
sistema que a resolve, que é curva de animação e não vocabulário de habilidade.

## 21. A corrente de combo troca a habilidade ANTES de checar a recarga

**Decidido em 23/08/2026**, fechando a sexta e última lacuna da tabela.

`ComboSkillInfo_SkillID`, `_StartTime` e `_LimitTime`: apertar o mesmo botão
dentro de uma janela conjura **outra habilidade**. O elo seguinte é uma
habilidade inteira e diferente — `Impact1` muda em 121 dos 125 pares, `CoolTime`
em 86, `CostValue` em 75 —, e por isso ele é um id do catálogo e não um
modificador do primeiro.

### O que faz a mecânica valer a pena

A troca acontece **antes de `_check`**, e é a decisão inteira em uma linha. O
elo seguinte tem id próprio, a recarga registrada é a do elo anterior, e por
isso o segundo golpe sai **sem esperar a recarga do primeiro**. Trocar depois
seria cobrar a recarga errada e a corrente viraria decoração: o jogador
apertaria de novo e ouviria "em recarga".

Armar a corrente acontece dentro de `_charge`, junto da mana, da recarga e do
reset de auto-ataque — o instante em que a conjuração deixou de poder ser
recusada. Tentativa recusada não arma nada, pela mesma razão pela qual não
gasta nada.

### O que a medição mudou, de novo

A tabela dizia 14. Medido pelo caminho que o jogo percorre,
**4 dos 127 espaços** abrem corrente — e o caminho até lá tem quatro achados:

- **O ataque básico ficou de fora, e por dado.** 23 dos 34 campeões têm combo
  no básico, o que parecia dobrar o trabalho. Mas o elo 2 é **idêntico ao elo 1
  no nosso vocabulário** nos 23 — mesma forma, mesmo raio, mesmo dano, mesma
  escala. A diferença entre os dois `Impact` é animação e som. Implementá-lo
  não produziria nenhuma diferença observável: é a mesma classe da decisão 20.
- **Corrente para o vazio é pior que corrente nenhuma.** Das 11 correntes que
  chegam aos espaços de campeão, 7 apontam para um elo sem efeito no nosso
  vocabulário — o golpe dele caiu numa lacuna. Encadear esses daria uma
  habilidade que o jogador conjura e que não faz nada, quando hoje ele ao menos
  repete o primeiro golpe. O tradutor recusa: **21 correntes** foram recusadas
  por isso, e a recusa é contada.
- **E a primeira guarda era frouxa.** Ela olhava o XML — se o destino
  referencia algum impacto que existe —, porque é a única coisa disponível
  enquanto as habilidades são traduzidas uma a uma. Mas um impacto pode existir
  e não virar pulso com efeito, quando o que ele fazia caiu numa lacuna: dois
  espaços de campeão passavam pela fresta e entregariam um elo que não faz
  nada. Um passe final, com o corpus pronto, **poda 15 correntes** — e foi a
  asserção numérica que denunciou a diferença entre o 4 que eu tinha medido e
  o 6 que o código emitia.
- **E há habilidade hoje MUDA por causa disso.** O E do Miru tem, no elo 1,
  apenas um efeito de recarga com raio 0,8 — o golpe de verdade (266 de dano
  mais controle) está no elo 2, inalcançável. Rukh e Siu são iguais: o segundo
  golpe é o grande.

No corpus inteiro são **89 habilidades** com corrente emitida.

### Duas armadilhas pagas aqui

- **A chave da corrente é a RAIZ, não o grupo de quem armou.** O jogador aperta
  sempre a mesma tecla, e é a habilidade daquela tecla que a engine recebe: numa
  corrente de três elos, o terceiro aperto chega de novo como o elo 1. Guardando
  sob o grupo do elo 2, a corrente morria no meio — e o comentário que eu tinha
  escrito no código afirmava exatamente o contrário. Quem pegou foi o teste de
  três elos.
- **O elo seguinte mora no LIVRO, não dentro da `Ability`.** `Ability` é
  `Resource`, que é `RefCounted`, e A apontando para B com B apontando para A
  nunca chegaria a contagem zero. Medido: hoje o corpus não tem ciclo, mas
  depender disso seria depender do dado em vez do desenho — e este projeto já
  vazou 150 instâncias por um ciclo assim.

### Como isto é conferido

- `tests/test_combo.gd`: 14 testes, e a metade de baixo é sobre quem **não**
  recebe a corrente — sem corrente, fora da janela, antes de ela abrir.
- `tools/sondar_campeoes.gd` aperta o mesmo espaço uma segunda vez, num ciclo
  **isolado**: recarga limpa, conjura, tica só até a janela ABRIR, aperta de
  novo. Medido: **4 espaços abrem corrente e 4 entregam o elo seguinte.**
- A recarga NÃO é limpa antes do segundo aperto, de propósito: é passar por
  cima dela que faz a corrente valer a pena, e limpá-la esconderia justamente
  o defeito procurado.
- O ciclo é isolado porque a primeira versão o pôs no meio do laço das marcas,
  e a segunda conjuração criava golpes atrasados que contaminavam a conferência
  da perseguição — duas conferências dividindo o mesmo laço se atrapalham.
- Seis mutações, todas exigidas em vermelho. Uma escapou na primeira tentativa:
  o teste do consumo dava ao elo seguinte uma recarga de 10 s, e assim "a
  corrente foi consumida" e "o elo está em recarga" produziam o mesmo
  `ON_COOLDOWN`. **Fixture degenerado outra vez**, e a mutação o pegou.

## 22. O boneco fala o vocabulário inteiro do original, e o JOGO o executa

**Decidido em 24/08/2026.** O boneco tinha três clipes de locomoção e cinco
gestos de habilidade. Agora tem **20 dos 22 verbos universais** que os 32
campeões do original têm (§3 de `docs/11-direcao-de-arte.md`), mais os cinco
gestos e o arremesso — 25 clipes.

### O que estava errado antes de qualquer animação nova

`arte/personagem.glb` era gerado, conferido contra a direção de arte pelo
Blender, conferido de novo sem o Blender por `conferir_numeros.py`, e
rastreado no repositório. **E o jogo não o carregava.** `Boneco` montava o
corpo de caixas, e os nomes que a camada de jogo pedia — `run`, `idle`,
`swing`, `swing2`, `comboslash`, `shieldrush`, `shieldthrow`, `shieldwall` —
eram do Leo do Royal Crown, herdados da pasta de assets extraídos que foi
removida. Nenhum dos oito existia no nosso arquivo, e `Boneco.tocar` devolvia
`false` sem dizer nada.

Quatro ferramentas verdes, e nenhuma perguntava *o jogo consegue tocar isto?*.
É a lição 9 do `CLAUDE.md` na forma mais pura, e a resposta é estrutural:
`VocabularioDeAnimacao` guarda os nomes num lugar só, e `conferir_numeros.py`
exige que cinco listas digam o mesmo — o vocabulário do jogo, `ANIMACOES` do
gerador, as animações do `.glb` publicado, `NOMES_EXIGIDOS` e `EM_CICLO` do
conferidor — e reprova `tocar("literal")`.

### Três decisões que a medição obrigou

- **`ride2_idle` e `ride2_run` dividem o clipe com `ride_idle` e `ride_run`.**
  Mesma forma, mesmas durações medianas (1,33 s e 0,60 s), e duas coisas com a
  mesma forma dividem o gesto — é o que o original faz no extremo dos seis
  campeões sem clipe exclusivo nenhum. É por isso que 20 nomes cobrem 22
  clipes.
- **Os clipes de montaria são autorados no chão.** A altura da sela decidiria a
  pose inteira de um corpo montado e não existe enquanto a montaria não
  existir. Quem levanta o personagem até a sela é a CENA. Assim o item 5 do §10
  continua valendo em vez de virar uma exceção com folga inventada.
- **Reação não tem antecipação.** O item 4 do §10 pede recuo antes do golpe;
  numa reação a regra se inverte, porque antecipar faria o personagem parecer
  que sabia que ia apanhar. O §10 agora diz isso.

### E o arremesso deixou de ser estocada

`throw` é a conjuração UNIVERSAL do original: todo campeão tem `throw`,
`throw_f` e `throw_b`, e os clipes próprios dele vêm por cima. Aqui,
`GestoDeConjuracao` passou a escolher o arremesso para a forma `PROJECTILE` —
**359 pulsos de projétil no corpus, em 223 habilidades**, a forma mais comum
sem gesto próprio, e desenhá-la como estocada fazia lançar parecer esfaquear.

Conjurar em MOVIMENTO usa `throw_f` ou `throw_b`, escolhidos pelo sinal de
`velocidade · frente`. Os dois duram exatamente um ciclo de `correndo`, que é
a regra do §5 medida em 30 e 29 dos 32 campeões — o corpo de cima é sobreposto
às pernas que continuam correndo, e um comprimento diferente faria o passo
saltar no meio do arremesso. `conferir_numeros.py` reprova se as três durações
se separarem.

### Home e End: a roda que dá consumidor a metade do vocabulário

Sete dos 22 verbos universais são de MUNDO — colher, cortar, minerar, pegar,
comer, beber, operar — e não temos loot, árvore nem minério; o par do abatido
espera o estado de abatido; a montaria espera montaria. Sem um jeito de
olhá-los em jogo eles seriam conteúdo que existe e ninguém pede, que é
exatamente onde o `.glb` inteiro estava.

`RodaDeAnimacao` percorre `VocabularioDeAnimacao.TODOS` com Home e End, com uma
posição a mais que é "desligada". As três camadas visuais dão passagem a ela. É
provisória pela mesma razão que o Page Down dos campeões é: sem ela, testar 25
clipes exigiria 25 edições de cena.

E a **sonda de ritmo percorre a roda inteira**, conferindo que cada clipe toca
na posição dele e que a caminhada não o atropela. É a única conferência que
executa TODOS os clipes.

### Duas armadilhas pagas aqui, e nenhuma delas era mecânica

- **A Godot não reimporta em `--headless --script`.** Ela serve o que está em
  `.godot/imported/`, refeito só ao abrir o editor: regerar o boneco e rodar a
  sonda em seguida testa o boneco ANTERIOR, com tudo verde. Só apareceu porque
  o clipe novo mudou de NOME; se a mudança fosse de POSE, nada teria acusado.
  `conferir_numeros.py` compara o md5 que a própria Godot grava ao lado do
  artefato importado com o md5 do arquivo no disco.
- **A folha de contato mentia por espaçamento.** O passo entre as cópias era
  1,1 m fixo, escolhido para um boneco de pé, e a primeira animação deitada
  saiu com as seis empilhadas uma sobre a outra — imagem gerada, script dizendo
  "6 imagens", e nada julgável. Hoje o passo sai da largura medida da própria
  animação.

### O que só o olho pegou

Nenhuma medição pega pose errada, e três saíram só na folha de contato:

- em `levou_dano`, os braços iam para a FRENTE: num osso que aponta para baixo
  o +X leva a ponta para trás, e eu escrevi -38. Na tela virou o personagem
  estendendo as duas mãos como quem alcança alguma coisa
- em `colhendo` e `pegando`, a mão parava na altura do peito. O braço tem
  0,40 m do ombro ao pulso e não alcança o chão por rotação nenhuma — quem o
  leva lá é o TRONCO
- em `rastejando`, a perna abria em `Y`. Num corpo de pé o `Y` tomba o membro
  para o lado; num corpo DEITADO a perna já aponta ao longo de `Y` e girá-la em
  torno de `Y` a faz rodar sobre o próprio eixo. Quem abre a perna de um corpo
  deitado é o `Z`, e a compensação errada pôs as duas canelas em pé no ar

Duração, chão e amplitude estavam corretos nos três casos.

---

## 23. A meia volta do modelo mora na Godot, não no Blender

**Decidido em 24/08/2026.** O usuário abriu o jogo depois que o boneco ganhou os
25 clipes e disse: *"além de uma animação ruim, nem de frente o boneco tá"*.

### O que estava acontecendo

Medido dentro da engine, lendo as superfícies do `.glb` carregado:

| superfície | material | z de | z a |
|---|---|---|---|
| 1 | `pele` (cabeça) | -0,170 | **+0,220** |
| 4 | `sapato` (bico do pé) | -0,060 | **+0,240** |
| 5 | `rosto` (viseira e nariz) | **+0,165** | **+0,185** |

O rosto e o bico do pé apontam para **+Z**. A frente de um nó na Godot é
**-Z** — é para lá que `look_at` aponta, e `player.gd` usa `look_at` para virar
o corpo na direção em que ele anda. O personagem andava de costas, e como o
gesto de conjuração também é desenhado a partir do corpo, ele golpeava para
trás. As 25 animações eram lidas ao contrário.

### Nada estava errado no `.glb`

Esta é a parte que decide onde a correção vai. A especificação do glTF diz que
**a frente de um asset é +Z**. O boneco é autorado encarando **-Y** no Blender,
que é a frente de lá, e a conversão do exportador manda `-Y` do Blender para
`+Z` do glTF. Cada etapa está correta pela regra da etapa.

Quem diverge é a Godot, que adota `-Z`. Ou seja: não há defeito a consertar no
gerador — há uma **conversão de sistema de eixos que ninguém fazia**.

### Por que na fronteira, e não na origem

A correção poderia ir no gerador, girando o esqueleto meia volta antes de
exportar. Foi descartado por três motivos, nesta ordem:

1. **Espalharia a mudança.** As poses são escritas em eixos do mundo (`+X`
   inclina para a frente), `assentar` mede o chão, e `renderizar_previa.py`
   enquadra a câmera contando com o rosto em `-Y`. Girar na origem obriga a
   mexer nos três, e o preço de errar num deles é uma pose torta que passa por
   todas as ferramentas — que é exatamente o defeito que estamos consertando.
2. **Quebraria a conformidade do arquivo.** Um `.glb` com a frente em `-Z` está
   errado para qualquer outro consumidor de glTF, e qualquer ferramenta que um
   dia leia ou escreva este arquivo — um visualizador, um validador, outro
   gerador — vai discordar dele pela regra da especificação.
3. **`boneco.gd` já é essa fronteira.** `giro_externo_graus` existe ali há
   sessões, pelo mesmo motivo, para as malhas do andaime.

A decisão: `Boneco.giro_do_modelo`, `Vector3(0, 180, 0)`, aplicado ao instanciar
a cena. Gira só a MALHA. Quem decide para onde o personagem olha continua sendo
o corpo — `-basis.z`, em `combatant.gd` e em `player.gd` —, então combate,
telegrafia e alcance não mudam de comportamento.

### A defesa que faltava, e é o achado que vale mais

Quatro ferramentas verdes, e o defeito chegou à tela. Elas mediam **tamanho**:
proporção contra a direção de arte, duração de clipe, fechamento de ciclo, pé no
chão, nome de animação nos dois sentidos. Nenhuma perguntava *para que lado a
cara aponta*.

E havia coisa pior que ausência: o comentário de `_montar_modelo` **afirmava a
resposta**, dizendo que o modelo já nascia olhando para `-Z` e que girar seria
consertar duas vezes. Justificativa gravada que ninguém mede é afirmação, e esta
estava errada — a mesma classe que já custou cinco rodadas neste projeto.

Hoje `tools/sondar_campeoes.gd` mede, e a medida é uma **projeção, não uma lista
de propriedades**: o centro das caixas de material `rosto` menos o centro do
corpo inteiro, projetado no `-basis.z` do corpo. Positivo quer dizer que a cara
vai na frente. Enumerar eixo, sinal e rotação um a um é a armadilha que mais
rendeu achado aqui; um produto escalar fecha a classe.

Piso de 10 cm contra os 14,3 cm medidos. Duas mutações provam que ela confere:

- **zerar `giro_do_modelo`** dá -0,143 m e reprova — o defeito original;
- **tirar o material `rosto` do gerador** faz a conferência não achar o que
  medir, e ela reprova em vez de aprovar. Sem esse par, um `rename` desligaria
  a defesa em silêncio, que é a armadilha do padrão órfão.

### O que isto NÃO resolve

*"Animação ruim"* é a outra metade da frase do usuário, e ela continua aberta.
Parte dela é consequência disto — um ciclo de caminhada visto ao contrário lê
como deslizamento —, mas nem tudo é: medido, `parado` desloca **0,12 m** em 2 s
no vértice que mais se move, e `montado` desloca 0,05 m. O piso do conferidor é
0,03 m, então os dois passam com folga e mesmo assim leem como corpo congelado.

Não há número do original para ancorar amplitude: o censo mediu duração e
ciclo, não excursão. Enquanto não houver, **quem julga é o olho** — e é por isso
que isto está registrado como pendência, e não corrigido por chute.

---

## 24. A arte é gerada por script no Blender, e não comprada

**Decidido em 24/08/2026, pelo usuário**, com estas palavras:

> *"esquece meshy/mixamo, baixei o blender, vc vai gerar tudo q a gente precisa
> nele, pode remover qualquer espectativa de meshy/mixamo"*

### O que existia antes

`docs/08-arte-e-assets.md` descrevia, em 160 linhas, um pipeline de compra:
concept 2D numa IA de imagem → Meshy ou Tripo para virar 3D → auto-rig da Meshy
ou do Mixamo → ajuste no Blender, servido por dois servidores MCP, com créditos
por operação e URLs de download que expiram em três dias. E o roadmap marcava
tudo isso como Fase 6, atrás de *"só começa depois que a Fase 5 provou que o
jogo é divertido"*.

Nada disso vale mais. O documento foi reescrito, e as menções em `CLAUDE.md`,
`docs/04-roadmap.md` e nos comentários de `boneco.gd` e `gesto_de_conjuracao.gd`
foram trocadas.

### Por que a troca não é só de fornecedor

Um modelo comprado tem as proporções que tem. Um modelo gerado tem as
proporções que alguém escreveu — e se elas vierem de uma medição, a conferência
pode reprovar quando o modelo sai da direção. **Não há como conferir um `.fbx`
baixado contra coisa nenhuma**, e este projeto já mede proporção, ritmo,
vocabulário e esbeltez do original em 27 campeões.

Três consequências que valem além do boneco:

1. **Regenerar é barato.** Mudar a altura do elenco é editar uma constante e
   rodar dez segundos. No caminho antigo era refazer personagem e rigging.
2. **Um rig só deixa de depender de disciplina.** A "regra crítica" de
   `docs/08` — definir esqueleto padrão antes do primeiro personagem, senão o
   trabalho de animação é multiplicado — passa a ser consequência da
   construção: existe um `OSSOS`, e não há outro.
3. **O artefato é conferível sem a engine e sem o Blender.**
   `tools/conferir_numeros.py` lê o `.glb` commitado em Python puro. Foi assim
   que se descobriu, uma vez, que o `.glb` do repositório não vinha do gerador
   do repositório.

### E ela deixa de ser Fase 6

O adiamento existia porque o caminho antigo custava dinheiro num jogo que ainda
não provou ser divertido. Um gerador local não tem esse custo. A regra do
roadmap — *"❌ Fazer arte antes da Fase 6"* — continua valendo para o que ela
protege, que é **acabamento**: textura, som, iluminação, variação de elenco. Não
para ter um corpo que o jogador consiga ler, que é requisito de teste e não
enfeite.

### O que isto NÃO autoriza

Continua valendo `docs/01`: do Royal Crown entram **números e estrutura**, nunca
arte, som, código ou texto. Gerar em vez de comprar não muda a fronteira — o
censo lê os bundles da Steam e escreve um JSON de medidas, e nenhum byte de
malha, textura ou animação do original entra neste repositório.

> **Superada em parte pela decisão 25**: o modelo que o jogo carrega passou a
> ser um asset CC0. O que desta decisão continua valendo está listado lá.

## 25. O boneco do jogo é um asset CC0, e o gerador vira instrumento

**Decidido em 26/08/2026, pelo usuário**, depois de uma pesquisa que ele pediu
com estas palavras:

> *"ta parecendo TAO custoso e demorado, nesse ritimo vai demorar quase 1~2
> anos pra eu ter o basico q eu imaginei [...] Quero saber oq estou fazendo de
> errado"*

E, ao ver as alternativas (KayKit, styloo, VRoid, packs pagos):

> *"n gostei de nenhum, vamos voltar aos kaykit por enquanto!"*

### O que a pesquisa mediu

Quatro varreduras (geradores de malha por IA, IA de animação, prática dos devs
solo, pipeline para a Godot), e três achados que decidem:

1. **Autorar malha, rig e clipes por `bpy` não tem precedente encontrado como
   pipeline de produção de jogo.** A comunidade usa script de Blender para
   exportar, converter e VALIDAR — nunca para autorar. O custo que este projeto
   vinha pagando (rasgos de pintura, travessia de casca, rodadas adversariais
   por clipe) é o custo normal desse caminho, não um acidente.
2. **IA não resolve personagem animado em 2026**: o auto-rig da Meshy/Tripo
   colapsa nas juntas acima de ~30° de rotação; Mixamo está sem manutenção da
   Adobe; vídeo→mocap falha exatamente nos pés. Malha estática virou commodity;
   personagem rigado que deforma continua sendo trabalho de gente.
3. **O problema já estava resolvido por CC0**: o pack Adventurers do KayKit
   traz personagens rigados (41 ossos, com root e encaixes de mão) com 76
   clipes embutidos cada — cobrindo os 22 verbos universais do §3 de `docs/11`
   com sobra.

### O que mudou no jogo

- `arte/kaykit/Knight.glb` (CC0, com a licença ao lado) é o modelo padrão de
  `Boneco.modelo`; `arte/personagem.glb` é o reserva declarado.
- O jogo continua falando o NOSSO vocabulário: `VocabularioDeAnimacao.NO_KAYKIT`
  verte cada verbo para o clipe do pack, e `Boneco._apelidar_clipes` registra o
  apelido na `AnimationLibrary` — o mesmo `Animation` sob os dois nomes, sem
  duplicar dado. Verbos que dividem clipe precisam concordar sobre ser ciclo,
  porque o loop mora no recurso compartilhado.
- O Knight é autorado com 2,467 m e entra com escala 1,0 — no tamanho
  autorado. A primeira versão o escalava para os 1,75 m da direção de arte e
  o usuário reprovou em quinze segundos de jogo (*"pequeno de mais, chega a
  ser exagerado"*): proporção chibi concentra a massa na cabeça, e na câmera
  de MOBA ele lia com metade da cápsula de treino de 2,0 m. O 1,75 continua
  sendo a régua do boneco GERADO. As opções de empunhadura (duas espadas,
  quatro escudos, uma de mão inversa, todas visíveis no `.glb`) são
  escondidas ao carregar, menos a espada de uma mão.
- O ataque básico é desenhado NO RITMO da cadência: o clipe acelera para
  caber no intervalo entre dois ticks (`_tocar_no_ritmo_do_ataque`), e andar
  durante o golpe corta a animação e devolve o corpo à corrida — só o
  ataque; o gesto de habilidade é telegrafia e fica. As duas regras saíram do
  mesmo teste de quinze segundos: dois danos dentro de uma estocada, e o
  corpo pregado no chão terminando o golpe de quem já mandou andar.
- `tools/sondar_kaykit.gd` confere que o modelo padrão fala o vocabulário
  INTEIRO — presença, duração, ciclo e altura —, `sondar_campeoes.gd` ganhou a
  medida de frente pelos dedos dos pés para modelo sem o material `rosto`, e
  `_conferir_o_modelo_kaykit` em `conferir_numeros.py` confere tudo isso sem a
  engine, sobre o `.glb` commitado. Cada conferência foi derrubada por mutação
  no dia em que nasceu — e a de números pegou um erro REAL na primeira
  execução: a primeira versão desta decisão publicava "75 clipes" escrito de
  memória, e o arquivo tem 76.

### O que da decisão 24 continua valendo

- **A fronteira de `docs/01`**: nenhum byte do Royal Crown entra. Um asset CC0
  não muda isso.
- **A direção de arte medida** (`docs/11`) continua sendo a régua: é ela que dá
  o 1,75 m da escala e as durações que as sondas cobram.
- **O gerador e as suítes de mutação dele ficam** — como instrumento de medida
  e como reserva, não como fornecedor do modelo do jogo. `gerar_boneco.py` e
  `gerar_personagem.py` continuam rodando e conferindo; o que morreu é a
  obrigação de o JOGO carregar o que eles produzem.

### O "por enquanto" é literal

O usuário viu o KayKit e não o confundiu com o alvo: é chibi-brinquedo, não o
chibi-anime do original. A identidade visual fica para a fase de arte — os
candidatos pesquisados (VRoid para elenco em escala, malha por imagem→3D com
rig próprio) estão registrados na sessão de 26/08/2026. O que esta decisão
compra é o que a Fase 1 pede: um corpo legível com animação de verdade, hoje,
por zero reais.
