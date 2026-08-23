# 11 — Direção de arte

> **Este é o documento que decide como o jogo se parece e como ele se move.**
> Ele não descreve gosto: descreve medida. Cada número aqui saiu de
> `py tools/arte/censo_do_original.py`, que lê os bundles da instalação do
> Royal Crown e imprime exatamente estas contas.

---

## O que este documento é, e o que ele não é

O Royal Crown resolveu, com 32 campeões, um problema que nós ainda não
resolvemos: **como um personagem visto de longe, numa câmera isométrica
travada, diz o que está fazendo.** Este documento mede como eles resolveram e
transforma isso em regra nossa.

**Entra:** proporção, duração, cadência, estrutura de estado, contagem,
saturação média. Números e estrutura.

**Não entra:** malha, textura, som, clipe, código. É a linha de
`docs/01-visao-e-escopo.md`, a mesma que vale para as 113 tabelas XML, e ela não
se move porque agora o assunto é arte em vez de balanceamento.

Reproduzir: `py tools/arte/censo_do_original.py`. Ele precisa da instalação da
Steam, que não está neste repositório e não vai estar; sem ela sai com código 2
— que é diferente de reprovar. **Nenhum asset é escrito em disco.**

---

## 1. A proporção, e as três coisas que fazem o olhar

Medido em **25 campeões** (a Bella fica de fora: a malha dela desce 22 cm
abaixo do chão, é vestido, e a altura não é comparável).

Alturas como fração da altura total, mediana entre os 25:

| Osso | Fração | Em 1,75 m | Humano real |
|---|---|---|---|
| dedos do pé | 0,015 | 0,026 | ~0,010 |
| tornozelo | 0,096 | 0,168 | 0,040 |
| joelho | 0,287 | 0,502 | 0,285 |
| quadril | 0,486 | 0,851 | 0,543 |
| lombar | 0,560 | 0,980 | — |
| peito | 0,657 | 1,150 | — |
| base do pescoço | 0,763 | 1,335 | 0,823 |
| base do crânio | 0,806 | 1,411 | 0,840 |
| ombro / cotovelo / mão | 0,727 | 1,273 | — |

> Ombro, cotovelo e mão saem na **mesma altura** porque a pose de repouso é T.
> Isso não é defeito da medição: é o que confirma que ela leu a pose certa.

E as larguras:

| Medida | Mediana | Faixa | Humano real |
|---|---|---|---|
| separação dos ombros / altura | **0,175** | 0,162 – 0,241 | 0,229 |
| separação dos quadris / altura | 0,129 | — | ~0,13 |
| envergadura / altura | **0,901** | 0,855 – 0,966 | ~1,00 |
| cabeças de altura¹ | **4,23** | 3,58 – 4,88 | 5,65 |
| altura da cabeça / altura | **0,237** | 0,205 – 0,280 | 0,177 |

¹ *Cabeça = tudo acima da base do pescoço.* A definição importa mais que o
número: medindo do crânio dá 5,16, e sem dizer qual é a conta o valor não é
comparável com nada.

**As três coisas que fazem o olhar, e é só isso:**

1. **A cabeça é grande** — 23,7% da altura, contra 17,7% de um humano. Um terço
   maior, proporcionalmente.
2. **Os ombros são estreitos** — 0,175 contra 0,229. Isso é o que mais separa
   "boneco" de "atleta", e é a medida que passa despercebida.
3. **Os braços são curtos** — envergadura 0,90 da altura, contra 1,00. Braço
   curto encurta o gesto, e gesto curto lê melhor de longe.

O que **não** é caricato: as pernas. Joelho em 0,287 contra 0,285 do humano —
igual. Quadril mais baixo (0,486 contra 0,543), o que dá tronco mais longo. Não
é chibi de cabeça-e-pés; é um corpo quase certo com a cabeça aumentada.

### Duas armadilhas que já custaram medição errada

- **A malha é Z para cima; o esqueleto é Y para cima.** Medir altura pelo Y da
  caixa envolvente da malha devolve a PROFUNDIDADE do corpo, e a razão
  cabeça/corpo sai 100% sem nenhum erro aparecer na tela.
- **`UpperChest` ocupa a posição 9 de `m_HumanBoneIndex`.** Esquecê-lo desloca
  em um TODOS os ossos acima do peito. O sintoma foi mão, pé e braço caindo na
  mesma altura — repetição impossível, e foi ela que denunciou.

---

## 2. O elenco inteiro tem a mesma altura

**1,647 a 1,899, mediana 1,764** — 15% de variação entre o menor e o maior
campeão, num elenco de 25.

Isso é decisão de jogo, não de estilo. Num battle royale isométrico com 30+
jogadores, **o tamanho na tela é informação de alcance**: se um campeão fosse
metade do outro, a distância percebida mentiria. Eles pagaram a variedade em
silhueta e cor, não em escala.

**Nossa regra:** todo personagem tem **1,75 m**. Variedade vem de forma e cor.

---

## 3. O vocabulário de animação

O original tem **1350 clipes**, **3 controladores base** e **93 controladores de
substituição** — um por campeão e por contexto. Cada campeão preenche de **50 a
67 vagas** (mediana 56) do mesmo controlador.

**22 clipes existem em todos os 32 campeões.** É o vocabulário obrigatório:

| Clipe | Duração min/mediana/max | Tipo | O que é |
|---|---|---|---|
| `idle` | 1,27 / 1,33 / 5,33 s | ciclo | parado |
| `walk` | 1,07 / 1,27 / 1,60 s | ciclo | andando |
| `run` | 0,67 / 0,80 / 1,13 s | ciclo | correndo |
| `beaten` | 1,00 / 1,00 / 1,00 s | uma vez | levou dano |
| `stun` | 0,50 / 0,50 / 1,00 s | ciclo | atordoado |
| `death` | 1,13 / 1,82 / 3,33 s | uma vez | morreu |
| `knockout_idle` | 1,33 / 1,33 / 1,33 s | ciclo | caído, esperando |
| `knockout_run` | 1,13 / 1,13 / 1,33 s | ciclo | caído, rastejando |
| `collect` | 0,67 / 0,67 / 0,67 s | ciclo | colhendo |
| `cut` | 1,50 / 1,50 / 1,50 s | ciclo | cortando árvore |
| `mine` | 1,50 / 1,50 / 1,50 s | ciclo | minerando |
| `loot` | 0,50 / 0,50 / 0,50 s | uma vez | pegando do chão |
| `eat` | 6,57 / 6,57 / 6,57 s | ciclo | comendo |
| `drink` | 1,00 / 1,00 / 3,00 s | ciclo | bebendo |
| `operate` | 1,00 / 1,00 / 1,00 s | ciclo | operando máquina |
| `throw` | 0,80 / 0,80 / 1,37 s | uma vez | arremesso parado |
| `throw_f` | 0,73 / 0,80 / 1,50 s | uma vez | arremesso indo à frente |
| `throw_b` | 0,73 / 0,80 / 1,13 s | uma vez | arremesso indo atrás |
| `ride_idle` | 1,33 s | ciclo | montado, parado |
| `ride_run` | 0,60 s | ciclo | montado, andando |
| `ride2_idle` | 1,33 s | ciclo | segunda montaria, parado |
| `ride2_run` | 0,60 / 0,60 / 1,33 s | ciclo | segunda montaria, andando |

**Sete desses 22 são verbos de MUNDO** — `collect`, `cut`, `mine`, `loot`,
`eat`, `drink`, `operate`. Um battle royale gasta um terço do vocabulário
obrigatório em interagir com o cenário, e nenhum deles é combate. É o que
separa o gênero de um MOBA, e nós não temos nenhum.

**Fora dos 22, um campeão tem de 2 a 14 clipes próprios** (mediana 6) — as
habilidades. **162 nomes** aparecem em um campeão só.

**E seis dos 32 campeões não têm clipe exclusivo NENHUM.** Bastine e Fisher,
Eden e Kane, Thief e Violet, Harang e Stepan: cada par divide o conjunto inteiro
de animação de habilidade, e a identidade vem de malha, textura e efeito. A
média de "6 clipes próprios" esconde isso, porque é calculada só sobre quem
tem algum — por isso o censo imprime os seis pelo nome.

> **A regra que sai disto:** duas habilidades com a mesma FORMA podem dividir o
> gesto. É exatamente o que `GestoDeConjuracao` já faz ao escolher pela forma do
> primeiro pulso — e agora se sabe que é o que o original também faz, com o
> elenco inteiro.

> **A regra que sai disto:** um campeão novo não é um conjunto de animações
> novo. São **três de locomoção que ele herda** e **meia dúzia de gestos que são
> dele**. Se um personagem novo exigir animação de mundo nova, o vocabulário
> está errado — generalize antes de continuar. É a regra 5 do `CLAUDE.md`
> aplicada a movimento em vez de habilidade.

---

## 4. O ritmo

**30 quadros por segundo**, em 1344 dos 1350 clipes. Os 6 restantes a 60.

| Medida | Valor |
|---|---|
| duração de todos os clipes | 0,33 / **1,20** / 6,57 s |
| clipes em ciclo | 808 (60%) |
| clipes de uma vez | 542 (40%) |
| duração dos clipes de habilidade | 0,40 / **1,07** / 5,27 s |
| quartis das habilidades | p25 **0,83** · p75 **1,40** · p90 2,00 |

Em quadros a 30 fps, os comprimentos mais escolhidos são **30, 24, 40, 20, 32 e
35** — ou seja **1,00 s, 0,80 s, 1,33 s, 0,67 s, 1,07 s e 1,17 s**.

**Nossa regra:** um gesto de habilidade vive entre **0,83 s e 1,40 s**, e a
primeira escolha é **1,00 s**. Abaixo de 0,67 s o olho não separa antecipação de
golpe; acima de 2,00 s o jogo parece travado.

---

## 5. Conjurar andando dura exatamente um ciclo de corrida

`throw_f` e `throw_b` têm a **mesma duração de `run`** em **29 dos 32
campeões** — e nos três que faltam (Thief, Violet, Neva) a corrida é mais rápida
que a média.

Não é coincidência: são as versões **conjuradas em movimento**, e o corpo de
cima é sobreposto às pernas que continuam correndo. Se o comprimento não
casasse, o passo dava um salto no meio do arremesso.

**A mesma ideia aparece na queda:** `glider`, `glider_left` e `glider_right`
têm todos **2,00 s exatos**, para os 28 campeões. A variante direcional é uma
INCLINAÇÃO do mesmo movimento, não um movimento diferente.

**Nossa regra:** variante direcional de um gesto tem o comprimento do gesto. Se
precisar ser mais longa, não é variante — é outro gesto.

---

## 6. Entrada, laço, e distração

O saguão tem três estados, e é a estrutura mais reaproveitável do original:

| Clipe | Duração | Tipo |
|---|---|---|
| `lobby_idle_start` | 2,00 / 4,00 / 6,50 s | uma vez |
| `lobby_idle_loop` | 1,33 / 2,00 / 4,80 s | ciclo |
| `lobby_idle_neglect` | 2,33 / 2,33 / 4,67 s | uma vez, em 5 campeões |

**Entrada uma vez, laço, e uma distração ocasional** para quem ficar parado
tempo demais. É o que faz um personagem parado parecer vivo em vez de pausado, e
custa um clipe.

A queda tem a mesma forma: `fall` (2,67 s, ciclo) → `glider` (2,00 s, ciclo, com
esquerda e direita) → `glider_impact` (1,00 s, uma vez) → `land` (1,00 s, uma
vez) → `land_interpolation` (ciclo). **Cinco estados para descer de um
paraquedas** — o battle royale gasta mais animação em ENTRAR na partida do que
em qualquer habilidade.

---

## 7. O tempo do dano não sai da animação

**Apenas 3 clipes de partida em 235 carregam evento de animação**, e são
`collect`, `cut` e `mine` — a batida na árvore, a batida na pedra. **Nenhum
clipe de combate tem evento.**

Ou seja: no original, quando o dano acontece **não é a animação que decide**. A
animação lê; quem decide é a tabela.

Isso confirma a regra 3 do `CLAUDE.md` — lógica de jogo é agnóstica de render —
e tem uma consequência prática forte: **nossa camada de gesto pode ser trocada
inteira sem tocar em combate**, e um gesto que atrasa não atrasa o dano. É o que
já vale para `GestoDeConjuracao`, e é bom que valha por medição e não por sorte.

---

## 8. A paleta

Cada campeão tem uma textura de corpo de **2048×2048**, mais uma variante `_lod`
e, quando tem arma, uma textura de arma. Medido em 4 campeões cujas texturas
estão nos bundles locais:

| | Saturação mediana | Brilho mediano | Pixels quase-cinza |
|---|---|---|---|
| Leo | 0,38 | 0,73 | 35% |
| Selkie | 0,40 | 0,74 | 25% |
| Violet | 0,26 | 0,76 | 32% |
| Morgan | 0,11 | 0,56 | 64% |
| **mediana** | **0,32** | **0,74** | **34%** |

Brilho alto e saturação média, com **um terço da área quase sem cor**. Não é
paleta saturada de desenho: é uma base neutra clara com **manchas de cor
concentradas**, que é o que permite a cor identificar o campeão sem que a tela
vire confete quando há 30 deles.

O Morgan é o contraexemplo declarado — quase monocromático, e é a leitura de
personagem sombrio.

**Nossa regra:** corpo em tom neutro claro, e a cor reservada para **o que
precisa ser lido**: mão que golpeia, rosto que aponta a direção, e a telegrafia.

---

## 9. Como isto vira o nosso boneco

`tools/arte/gerar_personagem.py` deriva as medidas desta tabela. As proporções
saem de `PROPORCAO`, e mudar um número lá muda o boneco e reprova a conferência
se sair da faixa.

| Nossa medida | Vem de |
|---|---|
| altura 1,75 m | mediana 1,764 do elenco |
| tornozelo 0,168 | 0,096 × altura |
| joelho 0,502 | 0,287 × altura |
| quadril 0,851 | 0,486 × altura |
| peito 1,150 | 0,657 × altura |
| pescoço 1,335 | 0,763 × altura |
| ombro ±0,153 | 0,175 × altura ÷ 2 |
| quadril ±0,113 | 0,129 × altura ÷ 2 |

As durações também: `parado`, `andando` e `correndo` caem nas faixas do
vocabulário universal, e os cinco gestos caem entre p25 e p75 das habilidades.

**`tools/arte/conferir_personagem.py` reprova quando não caem.** Um documento de
direção de arte que ninguém executa envelhece na primeira sessão — este é
executado toda vez que o boneco é gerado.

---

## 10. A lista de checagem, ao criar animação nova

1. **É verbo universal ou é gesto de campeão?** Universal entra no vocabulário
   de todo mundo; gesto de campeão não pode exigir osso que os outros não têm.
2. **Cabe na faixa?** Locomoção nas faixas do vocabulário; gesto entre 0,83 s e
   1,40 s, e comece por 1,00 s.
3. **Ciclo ou uma vez?** Se é ciclo, o último quadro repete o primeiro.
4. **Tem antecipação?** Sem recuo antes do golpe, o gesto lê como teleporte.
5. **O pé encosta no chão?** A conferência mede; não confie no olho.
6. **Tem variante direcional?** Se tiver, ela dura o mesmo que o gesto.
7. **A silhueta diz o que é?** Feche os olhos para a cor: um contorno preto no
   quadro do impacto tem que ser diferente do contorno do repouso.
8. **Nada de evento de animação para combate.** Dano é tabela.

---

## Confiabilidade

| Afirmação | Como foi obtida |
|---|---|
| proporções, alturas, larguras | medidas em 25 avatares e malhas, reprodutível |
| vocabulário e durações | medidos em 93 controladores, reprodutível |
| cadência, ciclo, eventos | medidos em 1350 clipes, reprodutível |
| paleta | medida em 4 texturas — **amostra pequena**, é o que existe nos bundles locais |
| "as três coisas que fazem o olhar" | **interpretação minha** sobre número medido |
| as regras nossas | **decisão de engenharia**, derivada mas não medida |
