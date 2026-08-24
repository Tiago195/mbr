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

### O escopo, dito antes dos números

Toda contagem de animação daqui vem de **um arquivo**: `_animation.pak`, o
bundle de animação de personagem. O jogo inteiro tem mais clipe do que isso —
cenário, efeito, interface. E o **controlador base de partida não está nesse
bundle**: os 32 controladores de campeão apontam para um `m_PathID` externo, o
que significa que os nomes de ESTADO da máquina de animação não aparecem em
lugar nenhum desta medição. O que se mede aqui são **nomes de clipe**, não
nomes de estado.

---

## 1. A proporção, e as três coisas que fazem o olhar

Medido em **27 campeões**. Ficam de fora:

- **Bella**, cuja malha desce 22 cm abaixo do chão — é vestido, e a altura não
  é comparável;
- **Fisher, Harang, Kane e Thief**, que não têm malha nem avatar nos bundles
  locais — conferido varrendo os 1666 nomes de malha e os 201 de avatar, sob
  qualquer nome. *Por que* eles faltam **não está medido**: a instalação não tem
  os artefatos típicos de Addressables (`aa/`, `catalog_*.json`), e o
  `patch_data.json` que existe não cita campeão nenhum. A hipótese de que eram
  servidos pela rede é razoável e não é medição.

Alturas como fração da altura total:

| Osso | Mediana | Faixa medida | Em 1,75 m | Humano real |
|---|---|---|---|---|
| dedos do pé | 0,015 | -0,009 – 0,018 | 0,026 | ~0,010 |
| tornozelo | 0,093 | 0,057 – 0,123 | 0,163 | 0,039 |
| joelho | 0,283 | 0,253 – 0,328 | 0,495 | 0,285 |
| quadril | 0,485 | 0,417 – 0,512 | 0,849 | 0,543 |
| lombar | 0,557 | 0,476 – 0,575 | 0,975 | — |
| peito | 0,656 | 0,602 – 0,687 | 1,148 | — |
| base do pescoço | 0,763 | 0,708 – 0,795 | 1,335 | 0,823 |
| base do crânio | 0,797 | 0,737 – 0,821 | 1,395 | 0,840 |
| ombro / cotovelo / mão | 0,725 | 0,672 – 0,753 | 1,269 | — |

> Ombro, cotovelo e mão saem na **mesma altura** porque a pose de repouso é T.
> Isso não é defeito da medição: é o que confirma que ela leu a pose certa.

E as larguras:

| Medida | Mediana | Faixa medida | Humano real |
|---|---|---|---|
| separação dos ombros / altura | **0,175** | 0,162 – 0,241 | 0,229 |
| separação dos quadris / altura | 0,129 | 0,105 – 0,145 | ~0,13 |
| vão das mãos / altura | **0,629** | 0,588 – 0,703 | ~0,78 |
| envergadura / altura | **0,895** | 0,808 – 0,966 | ~1,00 |
| cabeças de altura¹ | 4,22 | 3,43 – 4,88 | 5,65 |
| altura da cabeça / altura | 0,237 | 0,205 – 0,292 | 0,177 |

¹ *Cabeça = tudo acima da base do pescoço.* A definição importa mais que o
número: medindo do crânio dá 4,93, e sem dizer qual é a conta o valor não é
comparável com nada.

### Vão das mãos e envergadura são medidas diferentes

**São dois números e não um, e confundi-los custou caro.** O vão das mãos é
junta a junta e **para no pulso**: 0,629. A envergadura é ponta a ponta da
malha e **inclui a mão**: 0,895. A diferença — 0,266 da altura, 13% por lado —
é mão.

Ou seja: **o original tem braço curto e mão grande.** Do ombro ao pulso são
0,227 da altura (0,397 m em 1,75); da mão são mais 0,133 (0,233 m). Um humano
tem a mão em torno de 0,11 da altura.

Publicar só a envergadura foi um erro material da primeira versão deste
documento: o nosso boneco batia o número esticando o antebraço 60% além do que
o original tem, e a conferência aprovava porque o total fechava. **Número certo
pelo motivo errado.**

### As três coisas que fazem o olhar

1. **A cabeça é grande** — 23,7% da altura, contra 17,7% de um humano. Um terço
   maior, proporcionalmente.
2. **Os ombros são estreitos** — 0,175 contra 0,229. Isso é o que mais separa
   "boneco" de "atleta", e é a medida que passa despercebida.
3. **A mão é grande e o braço é curto** — envergadura 0,895 da altura contra
   1,00, mas com 13% dela em mão. Braço curto encurta o gesto; mão grande dá
   ao gesto uma ponta que o olho segue de longe.

**E as pernas são o caso misto, não o caso limpo.** O joelho está em 0,283
contra 0,285 de um humano — igual. O **tornozelo está em 0,093 contra 0,039 —
2,4 vezes**, que é bota grossa, e os dedos ficam em 0,015 contra 0,010. Ou
seja: a coxa e a canela são quase humanas, e o pé é caricato. Concluir "não é
chibi de cabeça-e-pés" olhando só o joelho seria escolher a linha que convém.

### Duas armadilhas que já custaram medição errada

- **A malha é Z para cima; o esqueleto é Y para cima.** Medir altura pelo Y da
  caixa envolvente da malha devolve a PROFUNDIDADE do corpo, e a razão
  cabeça/corpo sai 100% sem nenhum erro aparecer na tela.
- **`UpperChest` ocupa a posição 9 de `m_HumanBoneIndex`.** Esquecê-lo desloca
  em um TODOS os ossos acima do peito. O sintoma foi mão, pé e braço caindo na
  mesma altura — repetição impossível, e foi ela que denunciou.

E uma terceira, que só apareceu na revisão: **a malha do corpo nem sempre se
chama `X_Body`.** Odri e Rukh nomeiam a delas só com o nome do campeão, e a
primeira versão do censo os descartava calada. Sozinho, o Rukh baixa o mínimo
da envergadura de 0,855 para 0,808 — e é desse mínimo que sai a folga com que a
conferência do nosso boneco julga.

---

## 2. O elenco inteiro tem a mesma altura

**1,647 a 1,899, mediana 1,764** — 15% de variação entre o menor e o maior
campeão, num elenco de 27.

Isso é decisão de jogo, não de estilo. Num battle royale isométrico com 30+
jogadores, **o tamanho na tela é informação de alcance**: se um campeão fosse
metade do outro, a distância percebida mentiria. Eles pagaram a variedade em
silhueta e cor, não em escala.

**Nossa regra:** todo personagem tem **1,75 m**. Variedade vem de forma e cor.

---

## 3. O vocabulário de animação

Dentro de `_animation.pak` há **1350 clipes**, **3 controladores base** — os de
saguão e de queda — e **93 controladores de substituição**, um por campeão e por
contexto. Cada campeão preenche de **50 a 67 vagas** (mediana 56).

**22 clipes existem em todos os 32 campeões** — não em "quase todos": o censo
mede as duas coisas e as duas dão 22.

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
| `ride_idle` | 1,33 / 1,33 / 1,33 s | ciclo | montado, parado |
| `ride_run` | 0,60 / 0,60 / 0,60 s | ciclo | montado, andando |
| `ride2_idle` | 1,33 / 1,33 / 1,33 s | ciclo | segunda montaria, parado |
| `ride2_run` | 0,60 / 0,60 / 1,33 s | ciclo | segunda montaria, andando |

**Sete desses 22 são verbos de MUNDO** — `collect`, `cut`, `mine`, `loot`,
`eat`, `drink`, `operate`. Um battle royale gasta um terço do vocabulário
obrigatório em interagir com o cenário, e nenhum deles é combate. É o que
separa o gênero de um MOBA, e nós não temos nenhum.

### Quanto disto o nosso boneco já tem

O nosso boneco tem **20 dos 22** verbos universais, mais os cinco gestos de
habilidade e um arremesso — 25 clipes ao todo. Os nomes nossos, e a tradução de
cada um para o nome do original, vivem em
`scripts/gameplay/vocabulario_de_animacao.gd` — que é a lista que o JOGO usa.
`tools/conferir_numeros.py` exige que ela seja exatamente a mesma lista do
gerador e a mesma do `.glb` publicado, nos dois sentidos.

**Os dois que faltam para 22 são `ride2_idle` e `ride2_run`**, a segunda
montaria, e a falta é a REGRA e não uma lacuna: eles têm a mesma forma e as
mesmas durações medianas de `ride_idle` e `ride_run` — 1,33 s e 0,60 s —, e
duas coisas com a mesma forma dividem o gesto. É exatamente o que o original
faz no extremo dos seis campeões sem clipe exclusivo nenhum.

E os dois clipes de montaria são autorados **no chão**, como todos os outros. A
altura da sela é a medida que decidiria a pose de um corpo montado, e ela não
existe enquanto a montaria não existir; quem levanta o personagem até a sela é a
CENA, no dia em que houver uma. Isso mantém o item 5 do §10 valendo — o pé
encosta no chão e a conferência mede — em vez de abrir uma exceção cuja folga
seria inventada.

Essa conferência existe por um buraco medido: o jogo pedia `run`, `idle`,
`swing`, `swing2`, `comboslash`, `shieldrush`, `shieldthrow` e `shieldwall` —
nomes do Royal Crown, herdados de uma pasta de assets que foi removida — e
nenhum dos oito existia no nosso arquivo. `Boneco.tocar` devolvia `false` sem
dizer nada, e as quatro ferramentas do projeto ficavam verdes, porque nenhuma
delas perguntava *o jogo consegue tocar isto?*.

**Fora dos 22, um campeão tem de 2 a 14 clipes próprios** (mediana 6, contando
só os 26 que têm algum) — as habilidades. **162 nomes** aparecem em um campeão
só.

### Seis campeões não têm clipe exclusivo nenhum

São **Bastine, Eden, Fisher, Harang, Thief e Violet**. Cada um divide as
animações de habilidade com um parceiro — mas **dividir não é ser igual**, e a
medida exata importa. Contando "habilidade" pela linha de corte declarada no §4
— clipe de no máximo dois campeões —, que é a mesma que o censo imprime:

| Divide | com | e o parceiro tem |
|---|---|---|
| Bastine: 5 de 5 | Fisher | 6 |
| Eden: 5 de 5 | Kane | 7 |
| Fisher: 5 de 6 | Bastine | 5 |
| Harang: 9 de 12 | Stepan | 15 |
| Thief: 9 de 9 | Violet | 9 |
| Violet: 9 de 9 | Thief | 9 |

Só **Thief e Violet** têm conjuntos idênticos. Bastine e Eden são subconjuntos
próprios dos parceiros. **Harang e Stepan não são nem uma coisa nem outra:**
cada um tem clipes que o outro não tem — 12 contra 15, com 9 em comum. E Kane e
Stepan **têm** clipes exclusivos, e por isso não estão entre os seis.

> **A regra que sai disto:** duas habilidades com a mesma FORMA podem dividir o
> gesto. É exatamente o que `GestoDeConjuracao` já faz ao escolher pela forma do
> primeiro pulso — e agora se sabe que é o que o original também faz, no
> extremo de um campeão inteiro sem gesto próprio.

> **E a outra:** um campeão novo não é um conjunto de animações novo. São
> **três de locomoção que ele herda** e **meia dúzia de gestos que são dele**.
> Se um personagem novo exigir animação de mundo nova, o vocabulário está
> errado — generalize antes de continuar. É a regra 5 do `CLAUDE.md` aplicada a
> movimento em vez de habilidade.

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

> **"Habilidade" é uma linha de corte, e ela é esta:** clipe que aparece em no
> máximo **dois** campeões. Dois e não um porque quatro pares dividem quase todo
> o kit, e exigir dono único jogaria fora metade das habilidades desses oito.
> Com dono único a mediana vira 1,17 e o p75 vira 1,47 — e são esses quartis que
> viram a faixa de duração dos nossos gestos, então a linha de corte muda a
> regra.

Em quadros a 30 fps, os comprimentos mais escolhidos são **30, 24, 40, 20, 60 e
35** — ou seja **1,00 s, 0,80 s, 1,33 s, 0,67 s, 2,00 s e 1,17 s**.

**Nossa regra:** um gesto de habilidade vive entre **0,83 s e 1,40 s**, e a
primeira escolha é **1,00 s**. Abaixo de 0,67 s o olho não separa antecipação de
golpe; acima de 2,00 s o jogo parece travado — e 2,00 s é, não por acaso, o
quinto comprimento mais comum: é a fronteira, não o meio.

---

## 5. Conjurar andando dura exatamente um ciclo de corrida

`throw_b` tem a **mesma duração de `run`** em **30 dos 32** campeões, e
`throw_f` em **29**. As exceções são **Thief e Violet** nos dois casos, mais a
**Neva** no `throw_f`.

Não é coincidência: são as versões **conjuradas em movimento**, e o corpo de
cima é sobreposto às pernas que continuam correndo. Se o comprimento não
casasse, o passo dava um salto no meio do arremesso.

> As exceções não têm uma explicação só. Thief e Violet correm em 0,67 s — a
> corrida **mais curta** do elenco — e mantêm o arremesso em 0,80. A Neva é o
> oposto: a corrida dela, 1,13 s, é a **mais longa** de todas.

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

Dos **235 nomes** de clipe de partida, **3 carregam evento de animação**:
`collect`, `cut` e `mine` — a batida na árvore, a batida na pedra. Contando
instâncias em vez de nomes são **96 de 1843**, porque cada um dos três está nos
32 campeões. **Nenhum clipe de combate tem evento.**

**Isto é uma inferência a partir de ausência, e vale dizê-lo.** O que está
medido é que os clipes de combate não carregam marca de tempo. A conclusão —
que o instante do dano vem da tabela — é a leitura mais econômica disso, e bate
com o que as tabelas de `docs/03` já descrevem, mas não foi observada
diretamente no motor deles.

Se estiver certa, confirma a regra 3 do `CLAUDE.md` — lógica de jogo é agnóstica
de render — e tem uma consequência prática forte: **nossa camada de gesto pode
ser trocada inteira sem tocar em combate**, e um gesto que atrasa não atrasa o
dano.

---

## 8. A paleta

Cada campeão tem uma textura de corpo de **2048×2048**, mais uma variante `_lod`
e, quando tem arma, uma textura de arma.

**A amostra é pequena e é o que existe:** só **6 dos 32** campeões têm textura
de corpo nos bundles locais. Por que os outros faltam é a mesma pergunta em
aberto do §1 — o fato é a ausência, não a explicação dela.

| | Saturação mediana | Brilho mediano | Pixels quase-cinza |
|---|---|---|---|
| Bastine | 0,43 | 0,42 | 31% |
| Leo | 0,38 | 0,73 | 35% |
| Odri | 0,36 | 0,73 | 33% |
| Selkie | 0,40 | 0,74 | 25% |
| Violet | 0,26 | 0,76 | 32% |
| Morgan | 0,11 | 0,56 | 64% |
| **mediana** | **0,37** | **0,73** | **33%** |

Saturação média e **um terço da área quase sem cor**. Não é paleta saturada de
desenho: é uma base neutra com **manchas de cor concentradas**, que é o que
permite a cor identificar o campeão sem que a tela vire confete quando há 30
deles.

O brilho **não** é uniformemente alto: vai de 0,42 (Bastine) a 0,76 (Violet). O
Morgan é o contraexemplo declarado — quase monocromático, e é a leitura de
personagem sombrio.

**Nossa regra:** corpo em tom neutro, e a cor reservada para **o que precisa ser
lido**: mão que golpeia, rosto que aponta a direção, e a telegrafia.

---

## 9. Como isto vira o nosso boneco

`tools/arte/gerar_personagem.py` deriva as medidas desta tabela. As proporções
saem de `PROPORCAO`, e mudar um número lá muda o boneco e reprova a conferência
se sair da faixa.

| Nossa medida | Vem de |
|---|---|
| altura 1,75 m | mediana 1,764 do elenco |
| tornozelo 0,163 | 0,093 × altura |
| joelho 0,495 | 0,283 × altura |
| quadril 0,849 | 0,485 × altura |
| peito 1,148 | 0,656 × altura |
| pescoço 1,335 | 0,763 × altura |
| ombro (junta) 1,269 | 0,725 × altura |
| ombro ±0,153 | 0,175 × altura ÷ 2 |
| quadril ±0,113 | 0,129 × altura ÷ 2 |
| pulso 0,872 | ombro − (0,629 − 0,175) × altura ÷ 2 |
| ponta da mão 0,639 | pulso − (0,895 − 0,629) × altura ÷ 2 |

As durações também: `parado`, `andando` e `correndo` caem nas faixas do
vocabulário universal, e os cinco gestos caem entre p25 e p75 das habilidades.

**`tools/arte/conferir_personagem.py` reprova quando não caem, e o gerador o
chama sozinho ao terminar** — antes disso a frase "é executado toda vez" era
falsa, e ele só rodava quando alguém lembrava a linha de comando do Blender.
Defesa que depende de alguém lembrar não é defesa.

E o gerador **exporta para um nome temporário e só publica se passar**: antes
ele gravava o arquivo definitivo e conferia depois, então toda execução
reprovada deixava um boneco ruim no disco — e foi assim que um deles chegou a
ser commitado.

O artefato também é conferido **sem o Blender**. `tools/conferir_numeros.py` lê
o `.glb` em Python puro — o cabeçalho de um glTF é JSON — e compara as oito
durações e nove proporções com o que o gerador descreve. É o que impede o
arquivo exportado de envelhecer em silêncio enquanto o código anda. O `.blend`
**não é rastreado**, e a razão é medida: exportá-lo duas vezes do mesmo código dá
dois arquivos diferentes, então ele não pode ser conferido por reprodução e
rastreá-lo faria toda geração sujar a árvore. Ele nasce local em dez segundos, é
salvo sem compressão para poder ser lido, e quando existe a conferência confirma
que tem os 15 ossos, as 8 animações e as seis alturas de osso do gerador.

E as defesas têm suas próprias suítes de mutação, no repositório:
`tools/arte/mutar_boneco.py` quebra o gerador e a regra da folga,
`tools/mutar_direcao.py` quebra a concordância entre documento, código,
instantâneo e artefato, e `tools/arte/mutar_gerar_boneco.py` quebra o
gerador do boneco novo e o conferidor dele. **103 mutações, 103 pegas.**

6 números não saem de faixa nenhuma e por isso são declarados aqui, para
poderem ser conferidos: a altura vale com folga de **4 cm**, o pé encosta no
chão com folga de **1,5 cm**, uma animação precisa de amplitude de pelo menos
**3 cm** para contar como animação, o salto sobe pelo menos **25 cm**, a
corrida sai do chão pelo menos **4 cm**, e um ciclo fecha com folga de
**0,5 cm** — o último quadro tem que repetir o primeiro, e quem mede é o
vértice que mais se afasta entre os dois.

**A contagem faz parte da afirmação.** Ela era "cinco" e não era conferida
contra nada: acrescentar um sexto número deixava a frase errada em silêncio, e
documento discordando de si mesmo já reprovou quatro rodadas seguidas aqui.

**As demais tolerâncias são derivadas, não escritas.** Cada uma é meia faixa
medida, arredondada para cima em passos de **0,005**. Escrever a folga à mão já
produziu uma que violava a própria regra que o comentário ao lado dela
declarava.

Isso não fecha a classe sozinho — **põe o número num lugar só em vez de dez**, e
esse lugar é conferido junto com os outros cinco. Dizer que derivar "fecha uma
classe inteira" foi otimismo: com o passo do arredondamento fora da conferência,
trocá-lo por 0,5 abria todas as tolerâncias de uma vez.

---

### Os números livres da pipeline do boneco novo

Os que **não saem de faixa medida nenhuma** — escolhidos por engenharia,
não derivados do original. Declarados aqui porque número que decide se um
clipe publica e que ninguém declara é número que ninguém confere: um revisor
adversarial alargou seis tolerâncias de uma vez e a rotina inteira ficou
verde.

`tools/conferir_numeros.py` confere esta tabela nos **dois sentidos** —
constante sem linha reprova, linha sem constante reprova, e valor diferente
reprova. Uma constante nova nasce vermelha até ser explicada aqui.

**Duas honestidades sobre esta tabela**, as duas achadas por revisão
adversarial. A primeira: ela lista o que a máquina consegue ENXERGAR, que são
constantes de módulo com valor numérico — mais o caso especial de um dicionário
de uma entrada. Números escritos inline no meio de uma expressão (`X_OMBRO *
0.34`, `/ 1.065`, `profundidade * 0.5`) não estão aqui e não são conferidos por
nada; são forma, não limiar, mas a distinção é minha e não é medida.

A segunda: nem tudo nesta tabela é livre. `ALTURA` sai da mediana medida dos 27
campeões, e está listado porque a varredura o alcança. Uma tabela que se
chamasse só "os livres" e incluísse um derivado seria a mesma classe de defeito
que ela existe para fechar.

| Arquivo | Constante | Valor | O que ela decide |
|---|---|---|---|
| `gerar_boneco.py` | `ALTURA` | 1.75 | a altura alvo, em metros — **este sai de faixa medida** (mediana 1,764 dos 27 campeões) e está aqui só porque é literal decimal; ver a nota abaixo da tabela |
| `gerar_boneco.py` | `FRACAO_ATE_O_COTOVELO` | 0.47 | onde o cotovelo cai ao longo do braço; **não sai do original**, que mede ombro, cotovelo e mão na mesma altura na pose T |
| `gerar_boneco.py` | `ABERTURA_DO_BRACO` | 28.0 | graus de pose A; 20 era o mínimo que separa braço e coxa, e 28 leva a autointerseção de 78 pares a 10 |
| `gerar_boneco.py` | `FRACAO_DO_PEITO` | 0.72 | o RAIO do nó do peito, em fração do meio-vão dos ombros — não onde ele cai, que é medido e vale 0,656 |
| `gerar_boneco.py` | `ESTREITAMENTO_DO_PULSO` | 0.45 | o pulso é mais fino que o antebraço |
| `gerar_boneco.py` | `ENGROSSAMENTO_DA_MAO` | 1.35 | e a mão é mais grossa que o pulso — o §1 mede mão grande |
| `gerar_boneco.py` | `SUBDIVISOES` | 2 | passes de subdivisão sobre o casco do Skin Modifier |
| `gerar_boneco.py` | `LADO_DO_VOXEL` | 0.022 | só vale se `VOXELIZAR` voltar a ser verdadeiro |
| `gerar_boneco.py` | `SOBRA_DA_REDUCAO` | 0.35 | idem |
| `gerar_boneco.py` | `TENTATIVAS` | 240 | voltas do laço de convergência antes de desistir |
| `gerar_boneco.py` | `FOLGA_DA_ALTURA` | 0.002 | quando a convergência considera a altura fechada |
| `gerar_boneco.py` | `AMORTECIMENTO` | 0.5 | quanto da correção o laço aplica por volta; correção cheia **não oscila, EXPLODE** — medido, topo 144,6 m e base −142,4 |
| `gerar_boneco.py` | `AMORTECIMENTO_DA_ESPESSURA` | 0.5 | o mesmo, para o raio das peças — e 0,9 diverge na volta 97 |
| `gerar_boneco.py` | `FOLGA_DA_CABECA` | 0.006 | quando a largura da cabeça está fechada |
| `gerar_boneco.py` | `FOLGA_DO_BRACO` | 0.004 | quando o alcance do braço está fechado |
| `gerar_boneco.py` | `RAIO_DO_TUBO_DO_BRACO` | 0.145 | o cerco que separa vértice de braço de vértice de coxa; o pé fica a 1,2 m e passava no filtro anterior |
| `gerar_boneco.py` | `AMOSTRA_MINIMA` | 12 | vértices mínimos para uma medida não ser decidida pelo acaso |
| `gerar_boneco.py` | `PASSOS_PARA_DENTRO` | 12 | passos ao puxar uma CAUDA de osso para dentro do corpo, em `_cauda_dentro` |
| `gerar_boneco.py` | `PASSADAS_DE_ALISAMENTO` | 2 | passes de suavização da fronteira de pintura |
| `gerar_boneco.py` | `FUNDO_DO_ROSTO` | 0.55 | quanto da FRENTE da cabeça vira rosto, em fração do raio dela |
| `gerar_boneco.py` | `ALTURA_DO_ROSTO` | 0.25 | e a partir de que ALTURA da cabeça, para o rosto não descer no queixo |
| `gerar_boneco.py` | `CADENCIA` | 30 | quadros por segundo; **medido**, 1344 dos 1350 clipes do original |
| `gerar_boneco.py` | `AMPLITUDE_MINIMA` | 0.05 | metros que o vértice que mais anda precisa andar — é piso GLOBAL, e o piso por região é `ARTICULACAO_MINIMA` |
| `gerar_boneco.py` | `INCLINACAO_DE_DEITADO` | 70.0 | graus da vertical que o tronco tem de atingir num clipe que declara `deitado`; **escolhido**, não derivado — 90 é deitado, 0 é de pé |
| `conferir_boneco.py` | `ARTICULACAO_MINIMA` | 5.0 | o mesmo piso do gerador, do lado que julga o artefato — sem ele, congelar um clipe dentro do `.glb` passava |
| `conferir_boneco.py` | `DEITADAS[morte]` | 70.0 | o mesmo piso, do lado que julga o artefato |
| `gerar_boneco.py` | `ARTICULACAO_MINIMA` | 5.0 | graus que um osso de `movem` precisa girar; ângulo e não metro, porque metro não distingue articular de ser carregado |
| `gerar_boneco.py` | `FOLGA_DO_CHAO` | 0.015 | quando um pé conta como tocando o chão |
| `gerar_boneco.py` | `AMOSTRAS_DA_SOLA` | 12 | vértices da sola usados para detectar um perdido |
| `gerar_boneco.py` | `ESPALHAMENTO_DA_SOLA` | 0.05 | quanto eles podem se espalhar antes de um deles ser considerado perdido |
| `gerar_boneco.py` | `DESLIZE_PARA_A_FRENTE` | 0.01 | metros que o pé apoiado pode arrastar no sentido da marcha |
| `gerar_boneco.py` | `PASSADA_MINIMA` | 0.15 | metros que o pé apoiado tem de recuar |
| `gerar_boneco.py` | `DESEQUILIBRIO` | 0.12 | fração de diferença tolerada entre os dois pés |
| `gerar_boneco.py` | `APOIO_SIMPLES_MINIMO` | 0.20 | fração do ciclo em que cada pé é apoio único |
| `gerar_boneco.py` | `QUIQUE_MAXIMO` | 0.05578 | fração da altura que o quadril sobe e desce ao andar; é o **valor medido**, e o alvo humano é 2,3 a 2,9% |
| `gerar_boneco.py` | `TETO_DA_TRAVESSIA_ANIMADA` | 13 | pares de face que podem se atravessar num quadro animado |
| `conferir_boneco.py` | `ALTURA` | 1.75 | a altura que o artefato tem de ter |
| `conferir_boneco.py` | `FOLGA_DA_ALTURA` | 0.01 | e com que folga; **é 0,04 no outro conferidor**, e a diferença é deliberada |
| `conferir_boneco.py` | `ESCALA_TOLERADA` | 0.001 | quanto a escala acumulada da árvore de nós pode fugir de 1 |
| `conferir_boneco.py` | `FOLGA_DA_COR` | 0.02 | quanto uma cor do `.glb` pode diferir da declarada |
| `conferir_boneco.py` | `AMOSTRA_MINIMA` | 12 | vértices mínimos para uma esbeltez não ser decidida pelo acaso |
| `conferir_boneco.py` | `FOLGA_DA_DURACAO` | 0.05 | segundos que um clipe pode diferir da mediana medida |
| `conferir_boneco.py` | `FOLGA_DO_CICLO` | 0.002 | quanto duas poses podem diferir e ainda contar como a mesma |
| `conferir_boneco.py` | `TETO_DE_AUTOINTERSECAO` | 10 | pares de face que podem se atravessar em repouso |
| `conferir_boneco.py` | `CELULA` | 0.06 | lado da célula da grade espacial da busca de interseção |

## 10. A lista de checagem, ao criar animação nova

1. **É verbo universal ou é gesto de campeão?** Universal entra no vocabulário
   de todo mundo; gesto de campeão não pode exigir osso que os outros não têm.
2. **Cabe na faixa?** Locomoção nas faixas do vocabulário; gesto entre 0,83 s e
   1,40 s, e comece por 1,00 s.
3. **Ciclo ou uma vez?** Se é ciclo, o último quadro repete o primeiro.
4. **Tem antecipação?** Sem recuo antes do golpe, o gesto lê como teleporte.

   **Duas exceções, e as duas por ausência de ação.** A primeira é a
   **reação**: quem leva dano não antecipa nada — o susto é a informação, e
   antecipar faria o personagem parecer que sabia que ia apanhar. Numa reação o
   tempo se inverte: instantâneo na entrada, lento na saída.

   A segunda é o **ciclo de repouso ou de locomoção**. Antecipação existe para
   tornar legível a TRANSIÇÃO para uma ação; um laço que se repete não tem
   ação para anunciar, e pôr recuo nele produz um tique. `parado`, `andando`,
   `correndo` e as montarias não levam antecipação, e a ausência não é
   descuido. A exceção foi escrita depois de o primeiro clipe criado sob esta
   lista — `parado` — ser revisado contra um item que não o cobria.
5. **O pé encosta no chão?** A conferência mede, com tolerância de 1,5 cm;
   não confie no olho.
6. **Tem variante direcional?** Se tiver, ela dura o mesmo que o gesto.
7. **A silhueta diz o que é?** Feche os olhos para a cor: um contorno preto no
   quadro do impacto tem que ser diferente do contorno do repouso.
8. **Nada de evento de animação para combate.** Dano é tabela.

---

## Confiabilidade

| Afirmação | Como foi obtida |
|---|---|
| proporções, alturas, larguras | medidas em 27 avatares e malhas, reprodutível |
| vocabulário e durações | medidos em 93 controladores de `_animation.pak`, reprodutível |
| cadência, ciclo, eventos | medidos em 1350 clipes, reprodutível |
| paleta | medida em 6 texturas — **amostra pequena**, é o que existe nos bundles locais |
| "o tempo do dano vem da tabela" | **inferência a partir de ausência** de evento, não observação |
| "os que faltam eram Addressables" | **hipótese não medida** — o medido é só a ausência |
| "as três coisas que fazem o olhar" | **interpretação minha** sobre número medido |
| as regras nossas | **decisão de engenharia**, derivada mas não medida |
