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
}

## Os gestos de habilidade — os que `GestoDeConjuracao` escolhe pela forma.
const GESTOS: Array[StringName] = [
	ESTOCADA, GIRO, SALTO, ERGUER, PREPARO,
]

## Tudo que o boneco sabe fazer: os verbos universais mais os gestos.
## `conferir_numeros.py` exige que esta lista seja exatamente a união das duas
## de cima, e que ela seja a mesma que o gerador produz e que o `.glb` tem.
const TODOS: Array[StringName] = [
	PARADO, ANDANDO, CORRENDO,
	LEVOU_DANO,
	ATORDOADO,
	ESTOCADA, GIRO, SALTO, ERGUER, PREPARO,
	MORTE,
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
]
