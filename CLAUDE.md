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
| Arte 3D | **Gerada por script no Blender**, neste repositório — decisão 24 |
| Controles | **Esquema do League of Legends** (ver decisão 7) |

## Controles

O jogo copia o esquema do **League of Legends**. O que isso obriga:

- **Botão direito anda.** O esquerdo é de seleção e UI — **não usar para
  movimento**, mesmo sendo o gesto mais natural
- **Habilidades são Q/W/E/R miradas no cursor**, não cliques. Na Fase 3, o
  raycast tela → mundo é disparado lendo a posição do mouse, não um evento
  de clique
- As quatro teclas estão registradas em `project.godot` por `physical_keycode`
  — o `R` entrou junto com o kit dos campeões
- **Page Down / Page Up trocam de campeão em jogo.** É provisório e é de
  propósito: a Fase 1 não tem tela de seleção, e sem isso testar 27 campeões
  exigiria 27 edições da cena

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
| `docs/08-arte-e-assets.md` | **O pipeline de arte: geração por script no Blender** |
| `docs/09-glossario.md` | Termos de game dev traduzidos |
| `docs/10-traducao-do-original.md` | **O original traduzido para o nosso vocabulário** — o mapeamento, o que cresceu e as lacunas |
| `docs/11-direcao-de-arte.md` | **Proporção, ritmo e vocabulário de animação**, medidos em 25 campeões e 1350 clipes do original |

## Confiabilidade desta documentação

Escrita por um assistente cujo conhecimento de treino é anterior à Godot 4.7.
Classificação honesta do conteúdo:

**Verificado contra fontes (agosto/2026):**
- Fatos sobre o Royal Crown original (datas, campeões, jogadores, mecânicas)
- APIs de GDScript usadas em `07-primeira-cena.md`
- Breaking changes da 4.6→4.7 (nenhum afeta o código aqui)
- ~~Integração MCP da Meshy~~ — descartada em 24/08/2026 (decisão 24)

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

> Última atualização: **26/08/2026**. Repositório em `github.com:Tiago195/mbr`,
> branch `master`. **478 testes, 1304 asserções**, todos verdes, stderr limpo.

### Onde parar de ler e começar a trabalhar

> **PARE AQUI E LEIA.** Esta seção é o ponto de partida da próxima sessão.

### 26/08/2026: o boneco do jogo virou um asset CC0 — decisão 25

O usuário, vendo o custo da geração por script (*"nesse ritimo vai demorar
quase 1~2 anos"*), pediu pesquisa extensa sobre como gamedevs usam IA para
personagem e animação. Quatro varreduras depois, o achado central: **autorar
malha, rig e clipes por `bpy` não tem precedente encontrado como pipeline de
produção** — a comunidade usa script para exportar e VALIDAR, e resolve
personagem chibi rigado com biblioteca CC0. IA não muda isso em 2026: auto-rig
colapsa nas juntas, Mixamo está sem manutenção, mocap falha nos pés.

O que mudou (tudo na decisão 25 de `docs/02`): o jogo carrega
`arte/kaykit/Knight.glb` (CC0, 41 ossos, 76 clipes embutidos, escala 1,0 —
os 2,467 m autorados; o 1,75 da direção de arte lia minúsculo na câmera e o
usuário reprovou), `VocabularioDeAnimacao.NO_KAYKIT` verte os nossos verbos para os
clipes dele por APELIDO na `AnimationLibrary`, e `tools/sondar_kaykit.gd` +
`_conferir_o_modelo_kaykit` em `conferir_numeros.py` conferem — com três
mutações pegas no dia do nascimento. Os geradores e as suítes de mutação deles
FICAM, como instrumento e reserva.

O usuário viu e recusou as alternativas de elenco (styloo, VRoid, packs pagos):
*"n gostei de nenhum, vamos voltar aos kaykit por enquanto!"* — o "por
enquanto" é literal, a identidade anime-chibi fica para a fase de arte.

**Atenção: a sessão "Boneco de teste do projeto mbr" trabalha em paralelo**
no gerador (`gerar_boneco.py`) e deixou o HEAD com 4 números discordando de
`docs/11` (`conferir_numeros.py` os lista). São dela; esta sessão não os
tocou de propósito — duas sessões editando o mesmo arquivo é conflito, e o
trabalho dela agora é instrumento, não bloqueio.

### O que a sessão de 24/08 fez, e o buraco que ela achou primeiro

**`arte/personagem.glb` era gerado, conferido, rastreado — e o jogo não o
carregava.** `Boneco` montava o corpo de caixas, e os nomes que a camada de
jogo pedia (`run`, `idle`, `swing`, `swing2`, `comboslash`, `shieldrush`,
`shieldthrow`, `shieldwall`) eram do Leo do Royal Crown, herdados da pasta de
assets extraídos que foi removida. Nenhum dos oito existia no nosso arquivo, e
`Boneco.tocar` devolvia `false` calado. Quatro ferramentas verdes, e nenhuma
perguntava *o jogo consegue tocar isto?* — lição 9, na forma mais pura.

Fechado isso, o boneco passou a falar o vocabulário do original: **20 dos 22
verbos universais** medidos no §3 de `docs/11`, mais os cinco gestos e o
arremesso — **25 clipes**. Os dois que faltam para 22 são `ride2_idle` e
`ride2_run`, que dividem o clipe com `ride_idle` e `ride_run` pela regra do
próprio documento: mesma forma, mesmo gesto. Ver a decisão 22 em
`docs/02-decisoes-tecnicas.md`.

**E ele estava DE COSTAS.** O usuário abriu na Godot e disse: *"além de uma
animação ruim, nem de frente o boneco tá"*. Medido dentro da engine, a viseira e
o nariz ficavam em `z = +0,165 a +0,185` e o bico do sapato ia a `z = +0,240` —
o rosto olhava para **+Z**, e a frente de um nó na Godot é **-Z**, que é para
onde `player.gd` aponta o corpo com `look_at`. O personagem andava para trás,
golpeava para trás, e todas as 25 animações eram lidas ao contrário.

**O `.glb` não estava errado**: a especificação do glTF diz que a frente de um
asset é +Z, e o exportador do Blender entrega exatamente isso a partir do -Y em
que o boneco é autorado. Quem discorda é a Godot. A conversão faltava, e agora
mora em `Boneco.giro_do_modelo` — o único ponto em que os dois sistemas de eixo
se encostam. Ver a decisão 23 em `docs/02-decisoes-tecnicas.md`.

**O que deixou isso passar é a lição 9 outra vez, num eixo novo.** As quatro
ferramentas mediam TAMANHO — proporção, duração, fechamento de ciclo, pé no
chão — e nenhuma perguntava *para que lado a cara aponta*. Pior: o comentário de
`boneco.gd` AFIRMAVA a resposta, e a afirmação estava errada. Hoje
`sondar_campeoes.gd` projeta o centro das caixas do rosto sobre o `-basis.z` do
corpo e reprova abaixo de 10 cm; medido, dá +0,143 m, e zerar o giro dá -0,143.

**Home e End percorrem os 25 clipes em jogo** (`RodaDeAnimacao`). Existe porque
metade do vocabulário não tem sistema que a dispare — sete dos 22 verbos
universais são de mundo, e não temos loot, árvore nem minério — e sem um jeito
de olhá-los eles seriam conteúdo que existe e ninguém pede, que é exatamente
onde o `.glb` inteiro estava.

---

O usuário testou os campeões em jogo e disse: *"achei vários problemas com as
skills, várias não estão funcionando como deveria"*. Medido, não era bug de
tradução — eram as lacunas registradas. Elas viraram uma tabela de trabalho, e
**as seis lacunas estão resolvidas**: cinco fechadas por decisão e uma
classificada como arte.

**A tabela acabou. O próximo trabalho não sai dela.** O que falta para o jogo
deixar de ser sandbox continua sendo o que sempre foi — **oposição, mapa e
loot** —, e nenhuma quantidade de refinamento de habilidade conserta um boneco
parado.

O que existe traduzido para começar por oposição: **99 mobs**, dos quais
**28 têm kit** (`ability_groups`, o mesmo sentido de "campeões com kit"),
**97 têm ataque básico** e **98 têm `AIPath`** — que está guardada e **ainda
sem consumidor**. Ou seja: há de onde partir, e não é um sistema pronto
esperando ser ligado.

**O que exige o usuário, e vem antes.** Em **23/08/2026** ele testou em jogo e
validou a telegrafia, a carga de suprema e o ritmo do reset de auto-ataque
(*"bom, melhorou"*). Falta ele ver:

1. **o Knight do KayKit em jogo** (decisão 25, 26/08/2026): andar, correr,
   golpear, conjurar, apanhar, morrer — o corpo agora toca clipes de verdade
   de um asset CC0, e Home e End percorrem o vocabulário. A sonda sabe que
   cada verbo toca; não sabe se LÊ bem na câmera do jogo, nem se a frente,
   a escala e a espada convencem;
2. **a perseguição da âncora e a corrente de combo** — as duas são sensação de
   jogo, e as sondas sabem que não quebrou, não que ficou bom;
3. **os 25 clipes de `arte/personagem.glb`**, com Home e End — carregável de
   volta esvaziando `Boneco.modelo` no Inspector (ele é o reserva). As sondas
   conferem que cada um existe, dura o que a direção de arte manda, fecha o
   ciclo, mantém o pé no chão e é tocado pelo evento certo. Nenhuma delas sabe
   se a silhueta diz o que a animação é — que é o item 7 do §10, e o único que
   não se automatiza;
4. **os três clipes de `arte/boneco.glb`** — `parado`, `andando` e `morte`. Ele
   ainda não tem consumidor no jogo, então isto é olhar no Blender, não jogar.
   O que nenhuma ferramenta mede: **a pintura sai rasgada** em degraus de face
   nos ombros, no peito e na virilha, e o `rosto` é um retângulo chapado de
   bordas em escada.

   A casca também se atravessa em movimento, mas **isso a ferramenta mede e
   nomeia** — rode o gerador e leia as linhas `N entre <osso>, <osso>`. Este
   item já mandou olhar o lugar errado: dizia "a mão entra na nádega" quando o
   defeito é o joelho, 35 cm abaixo. Uma lista que manda olhar aponta para onde
   a ferramenta disser, não para onde a memória achar.

É a lista completa do que falta de olho humano; não há outra.

**O item 4 nasceu de uma reprovação adversarial**, e a lição é sobre esta lista
e não sobre o boneco: um clipe novo entrou no repositório e não entrou aqui,
numa seção que afirma de si mesma ser completa. Lista que se declara completa e
não é conferida por nada é a mesma classe de "documentação discordando de si
mesma" que já custou quatro rodadas.

**E ele não conseguiu testá-las.** Palavras dele: *"não sei se estou usando a
mesma habilidade ou se são habilidades diferentes, tudo que vejo são formas"*.
O diagnóstico estava certo e a causa não era falta de arte: **a tela não dizia
nada**. `AbilityCaster._report` já contava tudo — no console, que quem joga não
vê. Daí saíram três coisas, todas camada visual pura:

- `scripts/gameplay/combat_log.gd` — o relato na tela: qual tecla, qual
  habilidade, **se a corrente de combo trocou o elo**, quantos alvos, quanto de
  dano, e o motivo quando a conjuração é recusada
- **Cor por tecla na telegrafia** (`AbilityCaster.cor_por_espaco`), com uma
  quinta cor para o elo de combo. Com Q, W, E e R saindo todos laranja, duas
  conjurações seguidas eram indistinguíveis sempre que a forma coincidia — e
  CIRCLE é a forma de boa parte do corpus
- `scripts/gameplay/marcador_de_alcance.gd` — anéis de alcance no chão. Alcance
  varia de 2 m a 6 m entre campeões e era invisível; sem ele, "a mira estava
  torta" e "o alvo estava longe demais" têm a mesma aparência: nada acontece
- `scripts/gameplay/gesto_de_conjuracao.gd` — **o corpo faz alguma coisa ao
  conjurar**. Estocada, giro, salto, erguer, arremesso, e um preparo que dura a
  conjuração inteira, escolhidos pela forma do primeiro pulso com efeito.
  Conjurar ANDANDO tem clipe próprio, como no original — `throw_f` e `throw_b`,
  que duram exatamente um ciclo de corrida (§5)
- `scripts/gameplay/gesto_de_reacao.gd` — **o corpo reage ao que fazem com
  ele**: levou dano, atordoado e morte. As outras duas camadas desenham o que o
  jogador MANDA; num jogo de luta o que o adversário faz é a outra metade
- `scripts/gameplay/gesto_de_caminhada.gd` — passada em vez de deslizamento

**E existe uma direção de arte agora, medida e executável.** O usuário pediu
para entender *"o padrão de animação"* do original e transformar isso num
arquivo que dirija a arte daqui para frente. Saiu `docs/11-direcao-de-arte.md`,
com `tools/arte/censo_do_original.py` medindo os bundles da instalação da Steam
— **números e estrutura entram, asset não**, a mesma linha das 113 tabelas XML.

O que ele mede: proporção em **27 campeões**, vocabulário em **93
controladores** de `_animation.pak`, ritmo em **1350 clipes**. E o que saiu
disso muda o boneco: pescoço a 0,763 da altura (humano 0,823), quadril a 0,485,
ombros a 0,175 (humano 0,229), vão das mãos 0,629 e envergadura 0,895 (humano
~1,00). **Cabeça grande, ombros estreitos, braço curto e mão grande** — e a
perna é o caso misto: joelho igual ao humano, tornozelo 2,4 vezes mais alto.

Três achados que valem além da arte:

- **3 NOMES de clipe de partida em 235 têm evento de animação** (96 instâncias
  de 1843), e são `collect`, `cut` e `mine`. Nenhum de combate. A leitura mais
  econômica é que o tempo do dano **não sai da animação** — mas é inferência a
  partir de ausência, não observação do motor deles.
- **`throw_b` dura o ciclo de `run` em 30 dos 32 campeões, e `throw_f` em 29.**
  São as versões conjuradas em movimento, cortadas no tamanho da passada.
- **6 dos 32 campeões não têm clipe exclusivo nenhum** — Bastine, Eden, Fisher,
  Harang, Thief e Violet. Cada um divide as habilidades com um parceiro, mas
  **dividir não é ser igual**: só Thief e Violet têm conjuntos idênticos; o
  Harang divide 9 dos 12 dele com o Stepan, que tem 15. Habilidade com a mesma
  FORMA divide o gesto, que é o que `GestoDeConjuracao` já faz.

`tools/arte/conferir_personagem.py` reprova o boneco quando ele sai da direção
— e o gerador o chama sozinho ao terminar —, e `tools/conferir_numeros.py`
reprova quando documento e código discordam, mediana E faixa.
**103 mutações, 103 pegas** — 17 no boneco, 58 na concordância e
28 no boneco novo.

**E isto foi REPROVADO DUAS VEZES por um validador adversarial**, com 17 e 12
achados. A segunda rodada achou o pior de todos, e era de processo: **o `.glb`
commitado não vinha do gerador commitado.** A suíte de mutação restaurava o
código-fonte no fim e deixava o artefato da última mutação no disco, e ele foi
commitado assim — `parado` de 1,00 s onde o gerador diz 2,00 —, reprovando a
própria conferência. Nenhuma das ferramentas via, porque todas liam CÓDIGO e
nenhuma abria o arquivo exportado. Hoje `conferir_numeros.py` lê o `.glb` em
Python puro (o cabeçalho de um glTF é JSON) e compara com as chaves do gerador,
o que torna o artefato conferível **sem o Blender** e, portanto, em toda
execução.

Da primeira rodada, 17 achados. Quatro mudaram número: duas malhas de corpo eram descartadas em
silêncio por não se chamarem `X_Body` (Odri e Rukh), duas texturas de corpo
eram descartadas pelo prefixo, o quinto comprimento mais comum era 60 quadros e
não 32, e "os pares dividem o kit inteiro" era falso em três dos quatro pares.
Dois foram estruturais e valem para tudo: **conferir só a mediana e não a faixa
deixava alargar qualquer tolerância até nada reprovar** — dez mutações desse
tipo passaram —, e **`envergadura` eram duas medidas com o mesmo nome**, o que
fazia o boneco acertar o número com antebraço comprido e nenhuma mão.

**E o anel de alcance nasceu MENTINDO.** Ele mostrava `cast_range`, que vem de
`AI_SkillRange` do original — a distância em que a IA *decide usar* a
habilidade, não até onde ela pega. Em **43 dos 119 espaços** com alcance
declarado os dois divergem, às vezes por 7 metros. Foi o que fez o usuário
reportar o R do Leo como *"impossível de acertar"*: o anel dizia 4 m, o projétil
nasce 2 m atrás e voa 5, então pega até 3.

`Ability.effective_range()` calcula da geometria dos pulsos, e é ele que o anel
desenha. **Não é bug de tradução** — medido, o sinal do deslocamento está certo
(269 dos 293 são positivos) e trocar a regra consertaria o Leo quebrando o
Bastine, cujo alcance real bate com o declarado.

**E a correção que gerou o último item vale guardar.** A primeira resposta dele
foi um registro de texto, com o argumento de que *"isso é informação, não
animação"*. A réplica do usuário:

> *"você esquece que eu sou um humano vendo uma tela; para mim informação É a
> animação do personagem gastando a habilidade"*

Está certo, e o erro foi meu duas vezes: tratar texto como substituto do gesto,
e responder a uma confusão que ele não cometeu — quando ele disse "importamos
os bonecos", falava do KIT, e funcionalmente as habilidades são o personagem.
Enquanto não há esqueleto (Fase 6), a cápsula anima por procedimento: é como
os jogos comunicavam antes de haver animação esquelética, e é nosso.

**Ele pediu para importar os bonecos e as animações do original**, argumentando
que as tabelas já foram importadas. A premissa não se sustenta e a resposta
está registrada aqui porque vai voltar: **o repositório não tem um único
asset** — 79 scripts, 13 documentos, 3 JSONs, 2 cenas, zero imagens, malhas ou
sons. O que a tradução guarda de uma habilidade é `cooldown: 0.8`,
`cast_range: 2.0` e o NOME de um ícone. Número de recarga é fato funcional;
malha e animação são obra expressiva, e é a linha de `docs/01`. O caminho dos
bonecos é **gerá-los no Blender**, aqui — decisão 24.

#### A tabela, e como ela terminou

| Quantas | O que o original faz e nós não | Estado |
|---|---|---|
| ~~61~~ | Vários golpes, e a tela desenhava só o primeiro | **fechada** (decisão 16) |
| ~~65~~ | Alimentam a carga da suprema, que não existia | **fechada** (decisão 17) |
| ~~43~~ | Deveriam **zerar a cadência do ataque básico** | **fechada** (decisão 18) — 44 pelo caminho do jogo |
| ~~35~~ | Área que **acompanha o alvo**; a nossa planta no chão | **fechada** (decisão 19) — 27 pelo caminho do jogo |
| ~~24~~ | Deslocamento em **arco** | **fora de escopo** (decisão 20) — é asset, e `docs/10` já dizia |
| ~~14~~ | **Corrente de combo**: apertar Q de novo vira outra habilidade | **fechada** (decisão 21) — 4 pelo caminho do jogo |

A contagem vem de varrer `skill_xml` + `impact_xml` pelas colunas de
`ORFAS_QUE_SAO_LACUNA`. **Cuidado ao remedir:** `"False"` é string não-vazia e
`if d.get(coluna)` a conta como presente — foi assim que a primeira medição deu
123 ocorrências de `FollowTarget` em 124 habilidades. Foi também o que fez o
reset de auto-ataque parecer 521 quando são 259.

**Ao fechar cada lacuna, a primeira coisa é REMEDIR pelo caminho que o jogo
percorre** — `rank_for_level` sobre os espaços de campeão. As cinco fechadas
mudaram de número: **61 → 79**, **65 → 67**, **43 → 44**, **35 → 27**,
**14 → 4**. E duas mudaram de NATUREZA: a do arco é asset (decisão 20), e a
do combo perdeu o ataque básico porque o segundo golpe dele é idêntico ao
primeiro no nosso vocabulário. Os números da tabela
vieram de varrer o XML por outro caminho e **não são reproduzíveis**: nenhuma
tentativa de reconstruir o 43 chega nele (o caminho do jogo dá 44 em todos os
níveis de 1 a 18, `ranques[-1]` dá 46, habilidades distintas dão 34). Os três
recontados são afirmados por `tools/conferir_numeros.py`; os da tabela não são,
e é por isso que servem só para ordenar o trabalho.

#### O modo de trabalho que o usuário pediu, em 22/08/2026

> *"volte as lacunas q deixamos... quando vc achar q resolveu uma lacuna,
> dispare um subagent validador/reviewer e vai lhe aprovar ou reprovar, caso
> seja reprovado, corrija oq o subagent pegou que vc deixou passar, caso seja
> aprovado siga para o proximo item da sua tabela"*

Ou seja: implementar → disparar validador adversarial → corrigir o que ele achar
→ repetir até aprovar → próximo item. **Continuar o mesmo subagente pelo `id`**
(`SendMessage`), não abrir um novo: ele tem o contexto das rodadas anteriores e
isso é metade do valor.

Como escrever o comando do validador está em [[revalidacao-adversarial]] e no
histórico das duas lacunas fechadas: dar o trabalho, os comandos para conferir,
o contexto do projeto, e a instrução de **tentar reprovar**, pedindo veredito
numa linha só.

**Custo medido, por lacuna:** a 1 levou 8 rodadas (7 reprovando), a 2 levou 5
(4 reprovando), a 3 levou 6 (5 reprovando), a 4 levou 8 (7 reprovando), e as
decisões 20+21 juntas levaram 5 (4 reprovando).
**Toda rodada achou algo material**
— e nas rodadas 3, 4 e 5 da lacuna 3 o achado estava dentro da conferência
acrescentada na rodada anterior. Orçar uma lacuna por "umas duas rodadas" nunca
bateu com a medição.

**O que as lacunas 5 e 6 ensinaram, e é diferente:** as quatro reprovações
foram todas em **prosa do próprio `CLAUDE.md`** — item fechado numa tabela e
aberto noutra, sistema riscado num documento e não noutro, o parágrafo de
abertura dizendo que o trabalho está em curso, e um número escrito à mão que
estava errado por 71. Nenhuma tocou a mecânica. A saída foi a mesma das
contagens: **derivar em vez de escrever**. Hoje a abertura da seção tem os
números lidos de `atores.json` e do corpus, e as tabelas se conferem entre si.

**O que a lacuna 3 ensinou sobre o próprio loop:** as três reprovações do meio
não foram sobre a mecânica — foram sobre **justificativa gravada que era
falsa** (um número copiado de medição descartada, uma mutação creditada à
conferência errada, uma constante justificada pelo motivo oposto) e sobre
**conferência que falhava aberta** (padrão órfão virando aprovação, desconto
escrito para uma ausência e não para a irmã). E uma foi sobre generalização que
custou poder: trocar "desconta o número exato" por "dispensa tudo" fechou a
classe e deixou passar a perda de 27 conferências.

#### Como conferir que nada quebrou

```
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tools/sondar_campeoes.gd
godot --headless --path . --script res://tools/sondar_ritmo.gd
godot --headless --path . --script res://tools/sondar_kaykit.gd
py tools/conferir_numeros.py
```

A quarta é da decisão 25: confere que o **modelo padrão do jogo**
(`arte/kaykit/Knight.glb`) fala o vocabulário inteiro — presença, duração,
ciclo e altura — porque o apelido de clipe é camada que nenhuma das outras
roda.

E, para o boneco e a direção de arte, mais duas — que precisam do **Blender**,
não da Godot:

```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --python tools/arte/gerar_personagem.py
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --python tools/arte/gerar_boneco.py
py tools/arte/censo_do_original.py
```

As duas primeiras geram um boneco cada **e rodam a conferência dele**, e só
publicam os artefatos se ele passar. A terceira mede o original e regrava
`data/direcao-de-arte.json`; ela só funciona onde a instalação da Steam
existir, e sem ela sai com 2 — que é diferente de reprovar.

**São DOIS bonecos gerados, e desde a decisão 25 NENHUM deles é o que o jogo
carrega** — o modelo padrão é `arte/kaykit/Knight.glb` (asset CC0), e
`arte/personagem.glb` é o reserva declarado em `Boneco.reservas`.
`gerar_personagem.py` faz `arte/personagem.glb`: cápsulas e caixas, com
os 25 clipes do vocabulário universal. `gerar_boneco.py` faz `arte/boneco.glb`,
o boneco novo — malha contínua por Skin Modifier, na proporção medida, com
`parado`, `andando` e `morte`. **Ele ainda não tem consumidor**: nada na camada de jogo
o carrega, e ligá-lo é trabalho que não foi feito.

`gerar_boneco.py` abre a malha DEFORMADA em **cada quadro de cada animação** —
hoje **136** (`parado` 41, `morte` 56, `andando` 39) —, e é isso que domina o
custo dele. Uma grade esparsa erra o pior quadro: duas grades de seis amostras
erraram, uma minha e uma do revisor.

**Este parágrafo não publica mais um tempo em segundos, e a razão é que o
número apodreceu três vezes.** Ele disse 3m35s quando o medido era 33 s (sete
vezes), depois 33 s quando o medido era 69 s (duas vezes, porque o clipe novo
entrou e ninguém remediu). Nas três, o número sobreviveu porque tempo de
execução não é conferível por máquina — depende da máquina. **A contagem de
quadros é**, e `tools/conferir_numeros.py` a confere contra as durações
declaradas no gerador. Trocar a afirmação frágil pela verificável é o que este
projeto faz quando um número erra duas vezes; eu tinha deixado passar.

**E o `andando` está autorado para uma velocidade muito menor que a do jogo.**
O gerador mede a passada e imprime a velocidade que ela implica — a linha
`-> o ciclo implica X m/s`, com as duas parcelas ao lado. O jogo translada o
personagem a **3,3 a 5,0 m/s** (`player.gd`). Ligado como está, o ciclo
deslizaria vários múltiplos — pior que o `gesto_de_caminhada.gd` procedural,
que existe justamente porque o usuário reclamou de deslizamento.

O número não é repetido aqui de propósito: **ele já foi publicado errado duas
vezes** — 0,406 m/s, que era o recuo de UM pé dividido pelo ciclo inteiro, com
uma aritmética que nem a esse valor levava. Quem quiser o número roda o
gerador.

Não é bug hoje, porque `arte/boneco.glb` não tem consumidor. Vira bug no minuto
em que tiver. **E não há nada no repositório que resolva:** `grep -rn
"speed_scale" --include=*.gd .` dá zero ocorrências. Quem for ligar este boneco
precisa, antes, de um jeito de casar cadência de clipe com velocidade de
translação — ou reautorar a passada para a velocidade do jogo.

**E dois defeitos VISUAIS conhecidos, que nenhuma ferramenta mede.** Os dois
foram achados por um revisor adversarial abrindo o `.glb` e olhando, que é a
única forma que existe hoje:

- **a pintura sai rasgada em degraus de face** — nos ombros, no peito, na
  virilha e no punho —, e o `rosto` lê como um retângulo escuro chapado de
  bordas em escada, não como a frente de um personagem. Isto importa porque é
  exatamente o argumento com que `VOXELIZAR = False` se justifica: que voxelizar
  deixaria *"a viseira em farrapo e a borda do tronco picotada"*. A versão **não**
  voxelizada tem as duas coisas, então aquela comparação media diferença de
  grau, não de espécie;
- **a casca se atravessa em movimento**, e o gerador imprime onde: rode
  `gerar_boneco.py` e leia as linhas `N entre <osso>, <osso>` logo abaixo de
  cada `travessia da casca`.

Este segundo item **já foi escrito errado três vezes** — "sempre no mesmo
lugar, sempre em repouso", depois "no quadril", depois "a mão recuada entra na
nádega" — e a terceira sobreviveu em dois arquivos ao commit que existia para
corrigi-la. Por isso ele não nomeia mais nada: enquanto a ferramenta contava
pares e a prosa nomeava o lugar, o nome errava. **A prosa não sabe; a
ferramenta sabe.**

Nenhum dos dois é medido por ferramenta nenhuma. A autointerseção tem CONTAGEM
com teto e nunca LUGAR — e foi por confiar na contagem que o comentário dela
afirmou por duas versões que o defeito era *"sempre no mesmo lugar, sempre em
repouso"*, o que é falso nos dois termos.

O `.blend` **não é rastreado**, e a razão é medida: exportá-lo duas vezes do
mesmo código dá dois arquivos diferentes, então ele não se confere por
reprodução e rastreá-lo sujava a árvore a cada geração. Ele nasce local em dez
segundos. O `.glb`, que é o que o jogo consome, é determinístico, rastreado e
conferido.

As defesas têm suítes de mutação próprias, e elas estão no repositório:

```
py tools/arte/mutar_boneco.py
py tools/mutar_direcao.py
py tools/arte/mutar_gerar_boneco.py
```

**103 mutações, 103 pegas.** Elas mexem nos arquivos e restauram no fim, **os dois
artefatos inclusive** — restaurar só o código-fonte já deixou um `.glb`
commitado vindo de uma mutação, e restaurar só o `.glb` deixou o `.blend`.
**Rodar uma de cada vez:** elas mutam os mesmos arquivos, e sobrepô-las
corrompe as duas. `mutar_gerar_boneco.py` planta a trava `.mutacao-em-curso`
enquanto roda, e **enquanto ela existe o repositório está mutado** — não editar
arquivo nenhum do projeto até ela sair.

São **cinco**, e `py tools/conferir_numeros.py` sozinho já roda os quatro
primeiros: ele executa a suíte E as três sondas, e trata `SCRIPT ERROR` no
stderr, código de saída e ausência da marca de sucesso como falha. Rodar os
cinco à mão continua valendo quando se quer ler a saída de um deles.

**E ele confere `arte/boneco.glb` também**, chamando `conferir_boneco.conferir`
sobre o artefato commitado. Antes disso, um `grep` por `gerar_boneco` ou
`conferir_boneco` fora dos três arquivos novos dava zero ocorrências no
repositório inteiro: a única defesa do boneco novo era alguém lembrar de digitar
o comando. É a lição 11, e foi achado do revisor adversarial.

**Sonda que estoura no meio imprime `[ok]`.** Um acesso a propriedade
inexistente não aborta a função: empurra erro, devolve nulo e o laço segue.
Medido: `EXIT=0`, 323 bytes de stderr, `[ok]` no stdout. Por isso o stderr
delas passou a ser lido por máquina.

Estado ao fim desta sessão: **478 testes, 1304 asserções**, stderr 0 bytes,
sonda verde (127 espaços tentados, 126 conferidos, 9667 assinaturas,
44 espaços zerando a cadência do ataque e 83 mantendo; os cinco são PISO
conferido por `conferir_numeros.py`, que lê a saída da própria sonda),
**403 afirmações numéricas** (é PISO, não igualdade: a ferramenta reprova
se cair abaixo, e não obriga a mexer no documento quando cresce).

#### O que ainda exige olho humano, e por que não dá para automatizar

**A lista está na abertura desta seção, e é a única.** Havia duas aqui, com
escopos diferentes — esta ainda pedia teste da telegrafia e da carga de
suprema, que o usuário já validou em 23/08/2026 junto com o reset de
auto-ataque. Duas listas do que pedir dão duas respostas à mesma pergunta, e
foi assim que a documentação deste projeto errou quatro rodadas seguidas.

O que as sondas sabem e não substitui olho humano: que cada golpe virou marca
com a forma certa, no lugar certo, apontando para o lado certo, visível e pelo
tempo certo. Não sabem se o jogador entende o que aquilo quer dizer, nem se o
ritmo ficou bom.

---

### O que a revisão adversarial ensinou, e vale para tudo daqui em diante

Três temporadas — a tradução do original e as lacunas de habilidade, uma a
uma. **Toda rodada achou algo material.** O total por lacuna está no "Custo
medido" acima, que é onde ele serve para alguma coisa; aqui ele só envelheceria
a cada rodada, e envelheceu: dizia "catorze (doze reprovando)" quando a própria
aritmética do documento já dava outra coisa.

1. **Cobertura silenciosa é indistinguível de cobertura errada.** Todo achado
   veio de medir, nunca de reler. Daí o censo de colunas do tradutor, o
   contador de valores desconhecidos da `EffectFactory`, e a guarda que recusa
   emitir efeito que o motor descartaria.
2. **Número em documento é asserção.** `tools/conferir_numeros.py` existe por
   isso — **rodar antes de commitar documentação**.
3. **Padrão que cobre dado ausente é a armadilha mais cara.** Um cone lendo
   coluna inexistente alcançava 1 metro; um arremesso copiando `Duration = 0`
   não fazia nada. Nenhum dos dois dava erro. O que pega é conferir se o
   RESULTADO faz sentido, não se a coluna foi lida.
4. **Teste de mutação, sempre.** Quebrar de propósito e exigir vermelho é a
   única prova de que uma conferência confere.
5. **Verde por não ter mudado nada é indistinguível de verde por estar certo.**
   Patch que não aplicou, script cujo `write_text` foi cortado, comando atrás
   de um `&&` que não rodou, fixture que entrega a resposta certa pelo motivo
   errado. Depois de aplicar patch, **conferir por `grep` que o texto novo está
   no arquivo** — não confiar no "ok" do script. E há uma forma a mais, a mais
   sutil de todas: conferência cujo padrão ficou ÓRFÃO e cuja comparação
   transforma "não achei" em aprovação. `_numero` devolve -1, e
   `if publicado > conferidas` com -1 passa sempre — reescrever a frase no
   documento desligava a conferência sem ruído.
11. **Defesa que depende de alguém lembrar não é defesa.** O custo que um ramo
   degradado declara ao piso publicado errou CINCO vezes, e cada correção
   trocou o literal por outro: um número, uma localização, um argumento
   opcional. O que fechou foi a REGIÃO decidir — `with
   c.dependendo_da_engine()` faz tudo contado lá dentro contar como tal. E o
   que explica as cinco: o defeito é **verde na máquina que o escreve** e
   vermelho só na que não tem a engine.
6. **A conferência recém-adicionada é a que ninguém confere.** Toda vez que uma
   dimensão nova entrou numa comparação, ela nasceu cega, e foi sempre a rodada
   seguinte que descobriu. Conferência nova nasce com a mutação que a derrube.
7. **Quem junta o dado não decide.** Função que devolve VEREDITO pode devolver
   o veredito errado sem ruído; função que devolve a MEDIÇÃO, não. Quem decide
   é o laço que chama, e o piso de trabalho é sobre o mesmo dado que ele lê.
8. **Fixture degenerado é cobertura falsa.** Se todos os casos têm o mesmo
   valor, a mutação que troca esse valor é um no-op literal. Já aconteceu com
   posição (tudo na origem), direção (tudo no mesmo eixo) e carga (tudo zero).
9. **A camada que nenhuma ferramenta RODA é onde o defeito mora.** A suíte não
   alcança `gameplay/`; a sonda de campeões roda num `process_frame` só e nunca
   chama `_physics_process`. No vão entre as duas dava para apagar a cadência
   do ataque inteira com tudo verde. Antes de dizer que algo está coberto,
   perguntar **qual ferramenta executa aquela linha** — e se a resposta for
   nenhuma, a ferramenta que falta é o trabalho.
10. **Parar de enumerar propriedades.** Uma comparação que lista o que olhar
   rende um achado por rodada, sempre uma propriedade fora da lista. O que
   fecha a classe é um termo que englobe todas — `global_transform * AABB` no
   lugar de raio, largura, altura e posição, uma a uma.

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

E **384 atores** traduzidos em `atores.json`, carregados por `ActorCatalog`:
campeão, mob, bot, lacaio, baú e árvore, com atributos base, crescimento por
nível, kit e passiva. É a tabela que responde *quem tem quais habilidades* — a
única que responde, e a que faltava para o corpus virar personagem jogável.

Dela saem **33 campeões com kit** e **28 deles com as quatro habilidades**
conjuráveis. Os cinco que faltam citam um grupo cuja habilidade cai numa lacuna
registrada; `data/traducao/RELATORIO.md` nomeia cada um. **Toda contagem de
ator aqui é DEDUPLICADA por Id** — `actor_xml` e `actor_2_xml` repetem linhas, e
somá-las cruas já produziu "58 campeões" onde havia 40.

O que o vocabulário ganhou para caber: atributos **18 → 45**, controles de
grupo **4 → 10** estados (e as opções de `CrowdControlEffect` de 5 para 11),
efeitos **6 → 14**, e `Ability` deixou de ter uma forma para
ter uma **lista de pulsos** (decisão 10). O mapeamento coluna a coluna e as
lacunas que sobraram estão em `docs/10-traducao-do-original.md`.

### O que está pronto e jogável

Fases 1.1 a 1.3, 2.1 a 2.4, e 3.1 a 3.4 — todas validadas em execução.

Dá para: andar clicando com o botão direito, contornar obstáculos, atacar
bonecos de treino, e **ser um campeão do original com o kit dele em Q/W/E/R**,
trocando de campeão com Page Down. **Projétil voa**: o dano sai no impacto, e
sair da frente funciona. Barra de vida com escudo e números de dano
flutuantes.

As três habilidades feitas à mão (`meteoro`, `raio`, `investida`) continuam no
Inspector do `AbilityCaster` e voltam a valer esvaziando o `champion_id` do
`ChampionSelector`. As duas fontes passam pelo mesmo `AbilityBook`.

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

### O veredito do usuário sobre as habilidades em jogo (22/08/2026)

> *"achei vários problemas com as skills dos personagens, várias não estão
> funcionando como deveria, mas acho q por hora tá tudo bem"*

**Um deles já foi fechado, e era o pior:** o projétil causava dano no instante
do clique — *"e não se realmente acerta o alvo"*. Hoje ele voa, e quem sai da
frente não leva. Ver a decisão 15 em `docs/02-decisoes-tecnicas.md`. São
**359 pulsos de projétil** no corpus, em **223 habilidades**.

**O resto não é bug de tradução — são as lacunas registradas, medidas por
campeão.**
Das 124 habilidades dos 31 campeões com suprema:

| Quantas | O que falta |
|---|---|
| ~~65~~ | ~~Alimentam a carga da suprema, que não existe~~ — **fechada**: a suprema enche agindo e os 45 s inventados morreram. Pelo caminho que o jogo usa são **67 dos 127 espaços** |
| ~~61~~ | ~~Vários golpes, e a tela desenhava só o primeiro~~ — **fechada**: cada golpe é desenhado quando sai, e cone e trapézio ganharam forma de verdade. Recontado pelo caminho que o jogo usa, são **79 dos 127 espaços**; o 61 contava referências de impacto do XML, que é outra medida |
| ~~43~~ | ~~Deveriam **zerar a cadência do ataque básico**~~ — **fechada**: conjurar solta o próximo ataque básico na hora. Recontado pelo caminho que o jogo usa, são **44 dos 127 espaços**, em 22 campeões. Ver a decisão 18 |
| ~~35~~ | ~~Área que **acompanha o alvo**~~ — **fechada**: e a lacuna estava mal descrita. `FollowTarget` não é booleana (`None` 1552, `User` 353, `Target` 62), a maioria acompanha o CONJURADOR, e só muda algo em pulso ATRASADO: **27 dos 127 espaços**. Ver a decisão 19 |
| ~~24~~ | ~~Deslocamento em **arco**~~ — **fora de escopo**: `ZMoveCurvePath` não contém números, contém caminhos de asset de animação, e `docs/10` já a listava como "precisa de sistema que não é de combate". Ver a decisão 20 |
| ~~14~~ | ~~**Corrente de combo**~~ — **fechada**: o elo seguinte sai sem esperar a recarga do primeiro. São **4 dos 127 espaços**; o ataque básico ficou de fora porque o elo 2 dele é idêntico ao elo 1 no nosso vocabulário. Ver a decisão 21 |

Na medição de 22/08/2026, quando as seis estavam abertas, 26 dos 31 campeões
tinham ao menos uma afetada. Regerar aquela medição é uma varredura de
`skill_xml` + `impact_xml` pelas colunas de `ORFAS_QUE_SAO_LACUNA` — mas ela
descreve um estado que não existe mais.

**As seis estão resolvidas** — cinco fechadas e uma classificada como arte. O
que sobrou de habilidade não é lacuna de tradução: é conteúdo que o original
tem e nós não fomos buscar, e conteúdo não se ataca por tabela.

**As duas tabelas desta seção listam as MESMAS seis lacunas**, e
`conferir_numeros.py` exige que concordem sobre o estado de cada uma. A
conferência existe porque elas discordaram: a de cima marcava o arco como fora
de escopo e a de baixo continuava a listar como trabalho aberto, no mesmo
commit em que a decisão 20 explicava que documentação discordando é o defeito.

### Três sistemas que a tradução revelou e o roadmap não previa

Achados por medição, não por memória. Nenhum é urgente; todos são refinamento
de sensação, e o que falta antes continua sendo oposição, mapa e loot.

- ~~**Carga de suprema**~~ — **fechada em 22/08/2026**. 517 habilidades do
  original declaram quanto rendem, o ataque básico rende 200 e a suprema custa
  1000. Ela deixou de ter recarga e passou a encher agindo, o que apagou o
  número inventado de 45 s — que valia para 31 campeões e hoje vale para 1.
  Ver a decisão 17.
- ~~**Corrente de combo**~~ — **fechada em 23/08/2026**. Conjurar A dentro da
  janela troca A por B, e o elo seguinte sai sem esperar a recarga do primeiro.
  125 no XML, 89 emitidas no corpus, **4 dos 127 espaços** de campeão. O ataque
  básico ficou de fora porque o elo 2 dele é idêntico ao elo 1 no nosso
  vocabulário. Ver a decisão 21.
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

**O que está em `gameplay/` tem DUAS sondas**, porque a suíte não o alcança:

```
godot --headless --path . --script res://tools/sondar_campeoes.gd
```

Carrega `main.tscn` de verdade, troca de campeão nos 33, conjura os 127 espaços
e confere que **cada golpe virou marca na tela com a geometria do pulso, no
lugar dele, apontando para o lado dele, visível e pelo tempo certo** — e
nenhuma marca a mais. Oito rodadas de revisão adversarial construíram essa
conferência; o histórico está em `docs/02-decisoes-tecnicas.md`, decisão 16.

**A sonda testa a si mesma antes de julgar.** Ela cria uma marca-cobaia, mexe
numa propriedade de cada vez e confere que a assinatura muda. Piso de contagem
não bastava: `_estado` devolvendo sempre "visível" não muda contagem nenhuma.
O que prova que uma conferência distingue algo é mexer nesse algo e ver o
veredito mudar.

Não substitui olho humano: ela sabe se quebrou, não se ficou bom.

E ela **não roda quadro de física**: tudo acontece dentro de um único
`process_frame`, de propósito — é essa hipótese que faz as marcas não expirarem
no meio da conferência. O preço é que `_physics_process` nunca é chamado, e
portanto o **laço de combate** fica fora do alcance dela. É a segunda sonda:

```
godot --headless --path . --script res://tools/sondar_ritmo.gd
```

Avança quadros de física de verdade, põe o jogador batendo num boneco e confere
o RITMO: quantos golpes saem na janela e o espaçamento entre eles. Existe
porque dava para trocar `if unit.attack_is_ready()` por `if true` em
`player.gd` — 120 golpes em dois segundos no lugar de 3 — com as outras três
ferramentas verdes. Ela também fecha o reset de auto-ataque ponta a ponta, com
o par obrigatório: a habilidade que zera produz golpe no quadro seguinte, e a
que não zera não produz.

### Número em documento é asserção

```
py tools/conferir_numeros.py
```

Confere os números afirmados em `CLAUDE.md` e em `docs/` contra o código e
contra o corpus traduzido. **Rodar antes de commitar documentação.**

Ela também **exige a suíte verde**, e isso é mais recente do que parece: por
duas revisões ela lia a contagem de testes da saída da suíte e ignorava o
veredito — uma suíte vermelha publicava "431 testes, 1206 asserções" e a
ferramenta dizia "todas batem". Hoje ela lê stdout, stderr e código de saída,
e trata `SCRIPT ERROR`, `leaked at exit`, código diferente de zero, ausência de
resumo e travamento como falha. **Encontrar a engine é a fronteira**: depois
disso, tudo é falha da suíte, nunca "não consegui conferir".

E ela **se confere primeiro**: `_autoteste()` roda a classificação contra os
sete cenários que já a enganaram. Foi ali dentro que nasceram os três
bloqueantes de uma revisão inteira, e enquanto a classificação vivia colada ao
`subprocess` só dava para conferi-la fabricando executáveis falsos à mão.

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
- **GDScript não concatena literais de string adjacentes.** Em Python,
  `"abc"
"def"` vira uma string só; aqui é erro de sintaxe — e a mensagem
  ("Expected closing \")\" after call arguments") não menciona string. Custou
  três interrupções na mesma sessão. Usar `+` explícito
- **Nó fora da árvore não tem `global_position` nem `look_at`.** Os dois
  imprimem erro no stderr e devolvem lixo. E `Engine.get_main_loop()` é NULO
  enquanto `run_tests.gd` roda, porque a suíte inteira acontece dentro do
  `_init()` dele — então teste unitário não consegue pôr nó na árvore. O que
  depende de árvore vai para `tools/sondar_campeoes.gd`, que monta a cena
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
