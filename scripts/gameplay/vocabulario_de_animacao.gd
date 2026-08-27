class_name VocabularioDeAnimacao
extends RefCounted

## Os nomes de clipe do nosso boneco, num lugar só.
##
## ## Por que existe
##
## Porque a camada de jogo pedia clipes que não existiam, e **nada acusava**.
## `GestoDeCaminhada` chamava `tocar("run")`, `GestoDeConjuracao` chamava
## `tocar("swing")` — nomes do Royal Crown, herdados de uma pasta de assets
## extraídos que foi removida. O nosso `arte/personagem.glb` nunca teve
## nenhum deles: ele tem `correndo` e `estocada`.
##
## `Boneco.tocar` devolve `false` quando o nome não existe, e ninguém lia o
## retorno. Resultado: gerador conferido, artefato conferido, documento
## conferido — e o jogo pedindo oito nomes que não existiam em lugar nenhum.
## É a lição 9 do `CLAUDE.md` na forma mais pura: *a camada que nenhuma
## ferramenta roda é onde o defeito mora.*
##
## Com os nomes aqui, `tools/conferir_numeros.py` compara três listas — a do
## gerador, a do `.glb` exportado e a daqui — e reprova se qualquer uma se
## separar. E a mesma ferramenta reprova `tocar("algum_literal")`: nome de
## clipe escrito à mão volta a ser um nome que ninguém confere.
##
## ## De onde os nomes vêm
##
## Do §3 de `docs/11-direcao-de-arte.md`: os **22 clipes universais** que os 32
## campeões do original têm, medidos em `_animation.pak`. A coluna "no
## original" abaixo é o nome deles; o nosso é a tradução, do mesmo jeito que
## `data/traducao/` traduz as tabelas.
##
## O que **não** está aqui são os clipes próprios de campeão — de 2 a 14 por
## campeão no original. Eles não viram nome: viram FORMA, e habilidades com a
## mesma forma dividem o gesto. É o que `GestoDeConjuracao` já faz, e o que o
## original faz no extremo de seis campeões sem clipe exclusivo nenhum.

# ---------------------------------------------------------------- locomoção

## `idle` — parado, respirando.
const PARADO: StringName = &"parado"
## `walk` — andando. É o passo de quem está lento, não o de quem se desloca.
const ANDANDO: StringName = &"andando"
## `run` — correndo, que é como um campeão se desloca por padrão.
const CORRENDO: StringName = &"correndo"

# ---------------------------------------------------------------- reações

## `beaten` — levou dano. Dura **1,00 s nos 32 campeões**, sem variação
## nenhuma: é a única duração universal do original que é um ponto e não uma
## faixa.
const LEVOU_DANO: StringName = &"levou_dano"

## `stun` — atordoado. Ciclo, porque o atordoamento dura o que a habilidade
## mandar: o clipe roda quantas vezes for preciso.
##
## Serve também para `AIRBORNE`, que faz tudo que `STUN` faz. Dividir é a
## regra do §3 de `docs/11`: duas coisas com a mesma FORMA dividem o gesto, e
## é assim que 6 dos 32 campeões do original não têm clipe exclusivo nenhum.
const ATORDOADO: StringName = &"atordoado"

## `death` — morreu. Termina DEITADO e fica: é o único clipe do vocabulário
## que não volta ao repouso, e é de propósito.
##
## A faixa dele é a mais larga do original — 1,13 a 3,33 s —, o que é
## coerente com ser o único que ninguém precisa poder interromper.
const MORTE: StringName = &"morte"

## `knockout_idle` — derrubado, esperando. O abatido do battle royale: caiu,
## não morreu, e alguém ainda pode reerguê-lo ou acabar com ele.
##
## Divide a POSTURA com [[morte]] — mesmo corpo de costas — e o que separa os
## dois é que este respira. Nós ainda não temos o estado de abatido; o clipe
## existe porque o vocabulário é do BONECO, não do sistema, e um verbo que
## falta na hora em que o sistema chega é um boneco que trava a fase.
const CAIDO: StringName = &"caido"

## `knockout_run` — derrubado, se arrastando. É a locomoção do abatido, e o par
## de [[caido]]: um espera, o outro anda.
##
## De bruços, ao contrário do `caido`, que é de costas. As duas posturas são o
## MESMO osso girado para lados opostos.
const RASTEJANDO: StringName = &"rastejando"

# ------------------------------------------------------ verbos de mundo
#
# **Sete dos 22 clipes universais do original são estes**, e nenhum é combate:
# colher, cortar, minerar, pegar do chão, comer, beber e operar. Um terço do
# vocabulário obrigatório de um battle royale é interagir com o cenário, e é o
# que mais separa o gênero de um MOBA.
#
# Nós não temos nenhum dos sistemas que os disparam — nem loot, nem árvore, nem
# minério. Eles existem porque o vocabulário é do BONECO, não do sistema: um
# verbo que falta na hora em que o sistema chega é um boneco que trava a fase.
# Enquanto isso, quem os toca é `RodaDeAnimacao`.

## `collect` — colhendo. Ciclo, 0,67 s.
const COLHENDO: StringName = &"colhendo"

## `loot` — pegando do chão. **Uma vez**, e é o único
## verbo de mundo que não é ciclo: colher e minerar são trabalho que continua,
## pegar do chão acontece uma vez e acaba. 0,50 s é o clipe mais curto de todo
## o vocabulário universal.
const PEGANDO: StringName = &"pegando"

## `cut` — cortando árvore. Ciclo, **1,50 s exatos nos
## 32 campeões**. Golpe HORIZONTAL, na altura do peito: é o plano que o separa
## de [[minerando]], que tem a mesma duração.
const CORTANDO: StringName = &"cortando"

## `mine` — minerando. Ciclo, **1,50 s exatos nos 32**,
## a mesma duração de `cut`. Golpe VERTICAL, de cima para baixo.
const MINERANDO: StringName = &"minerando"

## `eat` — comendo. Ciclo, **6,57 s nos 32 campeões**:
## o clipe mais longo de todo o `_animation.pak`, cinco vezes a mediana. A
## duração é a informação — quem come está indefeso por seis segundos e meio.
const COMENDO: StringName = &"comendo"

## `drink` — bebendo. Ciclo. Divide o braço com
## [[comendo]]; o que separa os dois é a CABEÇA — comer avança o queixo, beber
## a joga para trás.
const BEBENDO: StringName = &"bebendo"

## `operate` — operando uma máquina. Ciclo, 1,00 s. O
## sétimo e último verbo de mundo.
const OPERANDO: StringName = &"operando"

# -------------------------------------------------------------- arremesso
#
# **A conjuração universal do original**, e a prova de que os cinco gestos de
# habilidade não bastam: todo campeão tem `throw` parado, `throw_f` indo à
# frente e `throw_b` indo atrás, e só DEPOIS disso vêm os clipes próprios dele.

## `throw` — arremesso parado. `GestoDeConjuracao` o
## escolhe para a forma PROJECTILE: são 359 pulsos de projétil no corpus, em
## 223 habilidades, e desenhá-los como estocada fazia arremessar parecer
## esfaquear.
const ARREMESSO: StringName = &"arremesso"

## `throw_f` — arremesso indo à frente. **Dura
## exatamente um ciclo de [[correndo]]**: é o corpo de cima sobreposto às
## pernas que continuam correndo, e se o comprimento não casasse o passo daria
## um salto no meio do arremesso (§5 de `docs/11`).
const ARREMESSO_A_FRENTE: StringName = &"arremesso_a_frente"

## `throw_b` — arremesso indo atrás. Mesma duração,
## mesma regra: as pernas são as da corrida na ordem invertida.
const ARREMESSO_ATRAS: StringName = &"arremesso_atras"

# ---------------------------------------------------------------- montaria
#
# **A montaria é o único verbo universal que ainda não existe como sistema, e
# o único cuja pose depende de um objeto que não temos.** Um clipe de montado é
# um corpo sentado sobre ALGUMA COISA, e a altura da sela é a medida que
# decide a pose inteira.
#
# A saída é a que a prática de animação usa: o clipe é autorado **no chão**,
# como todos os outros, e quem levanta o personagem até a sela é a CENA, no dia
# em que houver montaria. Isso mantém o item 5 do §10 valendo — o pé encosta no
# chão, e a conferência mede — em vez de abrir uma exceção cuja folga seria
# inventada.
#
# `ride2_idle` e `ride2_run` são a segunda montaria do original, com as MESMAS
# durações medianas: 1,33 s e 0,60 s. Eles dividem estes dois clipes, pela
# regra do §3 — duas coisas com a mesma FORMA dividem o gesto. É por isso que
# o vocabulário fecha em 20 nomes para os 22 clipes.

## `ride_idle` — montado, parado. Serve também para
## `ride2_idle`, a segunda montaria: as duas têm 1,33 s de mediana e a mesma
## FORMA, e dividir o gesto é a regra do §3.
const MONTADO: StringName = &"montado"

## `ride_run` — montado, andando. Serve também para
## `ride2_run`. 0,60 s: o clipe mais curto de todo o vocabulário universal.
const MONTADO_CORRENDO: StringName = &"montado_correndo"

# ------------------------------------------------------- gestos de habilidade

## Os cinco gestos que `GestoDeConjuracao` escolhe pela FORMA do primeiro pulso
## com efeito. Não têm equivalente de nome no original — lá cada campeão tem os
## seus, e é justamente a forma que permite dividi-los.
const ESTOCADA: StringName = &"estocada"
const GIRO: StringName = &"giro"
const SALTO: StringName = &"salto"
const ERGUER: StringName = &"erguer"
const PREPARO: StringName = &"preparo"

## O nome que cada verbo nosso tem no original, medido em `_animation.pak`.
##
## **É uma tradução, do mesmo tipo que `data/traducao/`**: entra o nome e a
## duração, não entra o clipe. É por esta tabela que `conferir_numeros.py`
## acha a linha do §3 de `docs/11` e a faixa do instantâneo que julgam a
## duração de cada animação nossa — sem ela, cada nome novo nasceria sem faixa
## e ninguém notaria.
##
## Os cinco gestos de habilidade **não estão aqui**, e a ausência é a regra: no
## original eles são clipe PRÓPRIO de campeão, de 2 a 14 por campeão, e o que
## nos deixa ter cinco para todos é dividi-los por FORMA.
const NO_ORIGINAL: Dictionary = {
	PARADO: &"idle",
	ANDANDO: &"walk",
	CORRENDO: &"run",
	LEVOU_DANO: &"beaten",
	ATORDOADO: &"stun",
	MORTE: &"death",
	CAIDO: &"knockout_idle",
	RASTEJANDO: &"knockout_run",
	COLHENDO: &"collect",
	PEGANDO: &"loot",
	CORTANDO: &"cut",
	MINERANDO: &"mine",
	COMENDO: &"eat",
	BEBENDO: &"drink",
	OPERANDO: &"operate",
	ARREMESSO: &"throw",
	ARREMESSO_A_FRENTE: &"throw_f",
	ARREMESSO_ATRAS: &"throw_b",
	MONTADO: &"ride_idle",
	MONTADO_CORRENDO: &"ride_run",
}

## Os gestos de habilidade — os que `GestoDeConjuracao` escolhe pela forma.
const GESTOS: Array[StringName] = [
	ESTOCADA, GIRO, SALTO, ERGUER, PREPARO,
]

# ------------------------------------------------------ vocabulário estendido
#
# **Verbos que existem só onde o MODELO os tem.** O vocabulário universal
# (`TODOS`) é o contrato que TODO corpo cumpre — o do pack, o gerado e o
# reserva —, e é contra ele que `conferir_numeros.py` compara o gerador e o
# `.glb`. Estes cinco não entram nele DE PROPÓSITO: são gestos que o Knight do
# KayKit sabe fazer (disparar, encadear dois cortes, esquivar, dar escudada) e
# que obrigariam o gerador a autorar cinco clipes novos só para o modelo padrão
# poder usá-los — nivelar por baixo.
#
# O contrato deles é outro: **cada um declara o verbo UNIVERSAL que o substitui**
# (`RESERVA_DO_ESTENDIDO`). Num corpo que não fala o estendido, `Boneco.tocar`
# toca a reserva — sem aviso, porque aqui a ausência é contrato, não defeito.
# Quem confere que o modelo padrão fala TODOS eles é `tools/sondar_kaykit.gd`,
# e quem confere o mapa sem a engine é `_conferir_o_vocabulario_estendido` em
# `tools/conferir_numeros.py`.
class Estendido:
	## Tiro de arma à distância. O ataque básico de quem empunha besta —
	## estocar com uma besta na mão lia como coronhada.
	const DISPARO: StringName = &"disparo"
	## Primeiro elo de uma corrente de golpes: corte diagonal.
	const GOLPE_A: StringName = &"golpe_a"
	## Segundo elo: talho de cima. O par de [[golpe_a]] — é a alternância que
	## mostra que o Q do Leo bate DUAS vezes, e não uma vez desenhada duas.
	const GOLPE_B: StringName = &"golpe_b"
	## Deslocamento curto rente ao chão — o dash. `SALTO` desenhava isso como
	## pulo, e dash não sobe: esquiva.
	const ESQUIVA: StringName = &"esquiva"
	## Golpe com o escudo: a forma que EMPURRA os outros, distinta do
	## deslocamento que move a si.
	const EMPURRAO: StringName = &"empurrao"

	## Todos os estendidos. `sondar_kaykit.gd` exige que o modelo padrão
	## responda a cada um, e que cada um tenha reserva universal declarada.
	const VERBOS: Array[StringName] = [
		DISPARO, GOLPE_A, GOLPE_B, ESQUIVA, EMPURRAO,
	]

## O verbo UNIVERSAL que cobre cada estendido num corpo que não o fala.
##
## É o que mantém o reserva (`arte/personagem.glb`) funcional sem autorar
## clipe novo: pedir `disparo` a um corpo sem besta animada toca `arremesso`,
## que é o mesmo gesto sem o objeto. Nenhum estendido é ciclo, e nenhuma
## reserva aqui pode ser ciclo — golpe que se repete sozinho não é golpe.
const RESERVA_DO_ESTENDIDO: Dictionary = {
	Estendido.DISPARO: ARREMESSO,
	Estendido.GOLPE_A: ESTOCADA,
	Estendido.GOLPE_B: ESTOCADA,
	Estendido.ESQUIVA: SALTO,
	Estendido.EMPURRAO: ESTOCADA,
}

## O nome que cada verbo nosso tem no pack do KayKit (`arte/kaykit/`).
##
## **É a mesma espécie de tabela que `NO_ORIGINAL`**: o boneco deixou de ser
## gerado por script (decisão 25) e passou a ser um asset CC0 com 75 clipes
## próprios; o jogo continua falando o vocabulário daqui, e quem verte é
## `Boneco._apelidar_clipes`, registrando cada clipe também sob o nosso nome.
##
## Vários verbos apontam para o MESMO clipe, e isso é a regra do §3 de
## `docs/11` (mesma forma divide o gesto) aplicada ao que o pack tem: comer e
## beber são `Use_Item`, as duas montarias são o sentado, e os três arremessos
## são `Throw` enquanto não houver camada que separe tronco de pernas.
##
## Cuidado herdado de `CICLOS`: verbos que dividem clipe precisam CONCORDAR
## sobre ser ciclo — o loop é gravado no recurso compartilhado, e um par
## discordante faria um verbo herdar o loop do outro em silêncio.
## `tools/conferir_numeros.py` confere isso.
const NO_KAYKIT: Dictionary = {
	PARADO: &"Idle",
	ANDANDO: &"Walking_A",
	CORRENDO: &"Running_A",
	LEVOU_DANO: &"Hit_A",
	# Tontura não existe no pack; apanhar em ciclo é o substituto legível.
	ATORDOADO: &"Hit_B",
	MORTE: &"Death_A",
	CAIDO: &"Lie_Idle",
	# Rastejar não existe no pack; deitado respirando é o que há.
	RASTEJANDO: &"Lie_Idle",
	COLHENDO: &"Interact",
	PEGANDO: &"PickUp",
	# Corte HORIZONTAL e mineração VERTICAL, como o §3 separa os dois.
	CORTANDO: &"1H_Melee_Attack_Slice_Horizontal",
	MINERANDO: &"2H_Melee_Attack_Chop",
	COMENDO: &"Use_Item",
	BEBENDO: &"Use_Item",
	OPERANDO: &"Interact",
	ARREMESSO: &"Throw",
	ARREMESSO_A_FRENTE: &"Throw",
	ARREMESSO_ATRAS: &"Throw",
	MONTADO: &"Sit_Chair_Idle",
	MONTADO_CORRENDO: &"Sit_Chair_Idle",
	ESTOCADA: &"1H_Melee_Attack_Stab",
	GIRO: &"2H_Melee_Attack_Spin",
	SALTO: &"Jump_Full_Short",
	ERGUER: &"Spellcast_Raise",
	PREPARO: &"Spellcasting",
	# Os estendidos. `GOLPE_B` seria o corte horizontal — o par natural do
	# diagonal —, mas `1H_Melee_Attack_Slice_Horizontal` já é o clipe de
	# `CORTANDO`, que é CICLO: dois verbos no mesmo clipe têm que concordar
	# sobre ser ciclo (o loop mora no recurso compartilhado), e um golpe de
	# combate que roda em laço não é golpe. O talho de cima é o clipe livre
	# que mantém os dois elos visivelmente diferentes.
	Estendido.DISPARO: &"2H_Ranged_Shoot",
	Estendido.GOLPE_A: &"1H_Melee_Attack_Slice_Diagonal",
	Estendido.GOLPE_B: &"1H_Melee_Attack_Chop",
	Estendido.ESQUIVA: &"Dodge_Forward",
	Estendido.EMPURRAO: &"Block_Attack",
}

## Tudo que o boneco sabe fazer: os verbos universais mais os gestos.
## `conferir_numeros.py` exige que esta lista seja exatamente a união das duas
## de cima, e que ela seja a mesma que o gerador produz e que o `.glb` tem.
const TODOS: Array[StringName] = [
	PARADO, ANDANDO, CORRENDO,
	LEVOU_DANO,
	ATORDOADO,
	ESTOCADA, GIRO, SALTO, ERGUER, PREPARO,
	MORTE,
	CAIDO,
	RASTEJANDO,
	COLHENDO,
	PEGANDO,
	CORTANDO,
	MINERANDO,
	COMENDO,
	BEBENDO,
	OPERANDO,
	ARREMESSO,
	ARREMESSO_A_FRENTE,
	ARREMESSO_ATRAS,
	MONTADO,
	MONTADO_CORRENDO,
]

## Os que rodam em CICLO. Todo o resto toca uma vez e para.
##
## **O glTF não carrega essa informação**, então o importador da Godot traz
## tudo como "uma vez" e o personagem dava um passo e congelava. `Boneco` põe
## estes em `LOOP_LINEAR` ao carregar.
##
## A divisão é medida: é a coluna "Tipo" da tabela do §3 de `docs/11`, tirada
## dos 32 campeões do original. No original 60% dos 1350 clipes são ciclo.
## Os cinco gestos de habilidade não estão aqui porque golpe que se repete
## sozinho não é golpe.
const CICLOS: Array[StringName] = [
	PARADO, ANDANDO, CORRENDO,
	ATORDOADO,
	CAIDO,
	RASTEJANDO,
	COLHENDO,
	CORTANDO,
	MINERANDO,
	COMENDO,
	BEBENDO,
	OPERANDO,
	MONTADO,
	MONTADO_CORRENDO,
]
