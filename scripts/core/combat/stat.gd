class_name Stat
extends RefCounted

## Catálogo de atributos — Fase 2.1, ampliado na tradução do original
## (`docs/10-traducao-do-original.md`).
##
## Nada em `scripts/core/` pode importar nó da engine. Esta classe estende
## RefCounted, não Node, de propósito: ela roda em teste unitário e no servidor
## headless sem árvore de cena.
##
## O identificador é um enum, não uma string: erro de digitação vira erro de
## compilação em vez de atributo silenciosamente zerado. Para arquivos de
## configuração de item e habilidade, que precisam nomear atributos em texto,
## `from_name()` faz a ponte.
##
## **Nunca inserir valor no meio deste enum.** `@export var stat: Stat.Id`
## serializa o enum como INTEIRO no `.tres`. Inserir no meio renumera tudo que
## vem depois e troca, em silêncio, o atributo de toda habilidade e todo item
## já salvos. Valor novo entra no fim, sempre.

enum Id {
	MAX_HEALTH,
	HEALTH_REGEN,
	ATTACK_DAMAGE,
	ABILITY_POWER,
	ARMOR,
	MAGIC_RESIST,
	ATTACK_SPEED,
	ATTACK_RANGE,
	MOVE_SPEED,
	CRIT_CHANCE,
	CRIT_DAMAGE,
	LIFESTEAL,
	SPELL_VAMP,
	COOLDOWN_REDUCTION,
	# Penetração não está na tabela de `03-sistemas-de-jogo.md`, mas o passo 4
	# do cálculo de dano depende dela. Adicionada aqui para não precisar de um
	# canal paralelo de atributos depois.
	ARMOR_PEN_FLAT,
	ARMOR_PEN_PERCENT,
	MAGIC_PEN_FLAT,
	MAGIC_PEN_PERCENT,

	# --- A partir daqui, atributos que a tradução do original exigiu -------
	# Cada um existe porque uma tabela do original concede o valor e sem ele o
	# dado não é traduzível. Quais já têm consumidor e quais ainda são inertes
	# está em `docs/10-traducao-do-original.md`.

	## Recurso de conjuração. `CostType` do original é sempre `ManaCost`.
	MAX_MANA,
	MANA_REGEN,

	## Teto de escudo acumulado, e a regeneração dele. 0 = sem teto.
	##
	## Cuidado com o falso amigo: o `MaxShield` do original NÃO é isto. Lá ele
	## é o TAMANHO do escudo que um buff concede, e no nosso vocabulário isso
	## já é `ShieldEffect`. O teto é conceito nosso, e existe porque escudo
	## empilhável sem limite é a via mais curta para um tanque imortal.
	SHIELD_CAP,
	SHIELD_REGEN,
	## Multiplica escudo RECEBIDO, não concedido. Fica no alvo.
	SHIELD_RECEIVED_AMP,

	## Amplificação de dano causado, por tipo. Multiplica depois da defesa —
	## é o que diferencia de simplesmente somar poder de ataque.
	PHYSICAL_DAMAGE_AMP,
	MAGIC_DAMAGE_AMP,

	## Acerto e esquiva. O original usa `Accuracy` com valor 1 em quase todo
	## impacto, e `CriticalRatio: -9999` para dizer "esta habilidade não
	## critita" — que é exatamente a convenção da decisão 8.
	ACCURACY,
	DODGE,
	## `Flexibility`: chance de o crítico sofrido virar acerto normal.
	CRIT_AVOIDANCE,
	CRIT_DAMAGE_REDUCTION,

	## Resistências a controle. `SLOW_RESIST` corta só lentidão;
	## `TENACITY` (`Toughness`) corta a duração dos controles duros.
	SLOW_RESIST,
	TENACITY,

	## Cura concedida × cura recebida. São dois lados e não se confundem.
	HEAL_POWER,
	HEAL_RECEIVED_AMP,
	HEALTH_REGEN_AMP,

	## Alcance de visão. É o que sustenta névoa de guerra e arbusto.
	SIGHT_RANGE,

	## "Groggy" do original: uma segunda barra que, esvaziada, atordoa.
	MAX_STAGGER,

	## Tetos. O original tem `MaxCDReductionRatio`, `MaxAttackSpeedRate` e
	## `MaxMoveSpeed` como atributos próprios, o que permite um item elevar o
	## teto em vez de só chegar mais perto dele.
	COOLDOWN_REDUCTION_CAP,
	ATTACK_SPEED_CAP,
	MOVE_SPEED_CAP,
	## Recarga de item consumível, separada da recarga de habilidade.
	ITEM_COOLDOWN_REDUCTION,

	## Regeneração fora de combate. Num battle royale isso é o que decide se
	## dá para escapar e voltar, ou se a luta perdida é definitiva.
	OUT_OF_COMBAT_HEALTH_REGEN,
	OUT_OF_COMBAT_MANA_REGEN,

	## Massa. Resiste a empurrão e puxão proporcionalmente.
	WEIGHT,

	## Corta todo dano SOFRIDO, de qualquer tipo, depois da defesa.
	##
	## `AllDamageReduce` do original. É diferente de armadura em dois pontos
	## que importam: pega dano verdadeiro também, e não tem retornos
	## decrescentes — 0.2 tira sempre um quinto. Por isso os valores dele são
	## pequenos, e os nossos devem ser também.
	DAMAGE_TAKEN_REDUCTION,

	## Quanta carga a suprema exige para sair.
	##
	## `LevelUpUltimateCharge` do original, e vale **1000 nos 31 campeões que
	## têm suprema** — não é por personagem, é a régua do sistema. A suprema não
	## tem recarga: ela enche agindo. Ver a decisão 17.
	##
	## Zero desliga o sistema: quem não tem carga máxima conjura a suprema como
	## qualquer outra habilidade. É a mesma convenção de `MAX_MANA`, e é o que
	## deixa mob e habilidade feita à mão fora disso sem um caso especial.
	MAX_ULTIMATE_CHARGE,
}

const NAMES: Dictionary = {
	Id.MAX_HEALTH: &"max_health",
	Id.HEALTH_REGEN: &"health_regen",
	Id.ATTACK_DAMAGE: &"attack_damage",
	Id.ABILITY_POWER: &"ability_power",
	Id.ARMOR: &"armor",
	Id.MAGIC_RESIST: &"magic_resist",
	Id.ATTACK_SPEED: &"attack_speed",
	Id.ATTACK_RANGE: &"attack_range",
	Id.MOVE_SPEED: &"move_speed",
	Id.CRIT_CHANCE: &"crit_chance",
	Id.CRIT_DAMAGE: &"crit_damage",
	Id.LIFESTEAL: &"lifesteal",
	Id.SPELL_VAMP: &"spell_vamp",
	Id.COOLDOWN_REDUCTION: &"cooldown_reduction",
	Id.ARMOR_PEN_FLAT: &"armor_pen_flat",
	Id.ARMOR_PEN_PERCENT: &"armor_pen_percent",
	Id.MAGIC_PEN_FLAT: &"magic_pen_flat",
	Id.MAGIC_PEN_PERCENT: &"magic_pen_percent",
	Id.MAX_MANA: &"max_mana",
	Id.MANA_REGEN: &"mana_regen",
	Id.SHIELD_CAP: &"shield_cap",
	Id.SHIELD_REGEN: &"shield_regen",
	Id.SHIELD_RECEIVED_AMP: &"shield_received_amp",
	Id.PHYSICAL_DAMAGE_AMP: &"physical_damage_amp",
	Id.MAGIC_DAMAGE_AMP: &"magic_damage_amp",
	Id.ACCURACY: &"accuracy",
	Id.DODGE: &"dodge",
	Id.CRIT_AVOIDANCE: &"crit_avoidance",
	Id.CRIT_DAMAGE_REDUCTION: &"crit_damage_reduction",
	Id.SLOW_RESIST: &"slow_resist",
	Id.TENACITY: &"tenacity",
	Id.HEAL_POWER: &"heal_power",
	Id.HEAL_RECEIVED_AMP: &"heal_received_amp",
	Id.HEALTH_REGEN_AMP: &"health_regen_amp",
	Id.SIGHT_RANGE: &"sight_range",
	Id.MAX_STAGGER: &"max_stagger",
	Id.COOLDOWN_REDUCTION_CAP: &"cooldown_reduction_cap",
	Id.ATTACK_SPEED_CAP: &"attack_speed_cap",
	Id.MOVE_SPEED_CAP: &"move_speed_cap",
	Id.ITEM_COOLDOWN_REDUCTION: &"item_cooldown_reduction",
	Id.OUT_OF_COMBAT_HEALTH_REGEN: &"out_of_combat_health_regen",
	Id.OUT_OF_COMBAT_MANA_REGEN: &"out_of_combat_mana_regen",
	Id.WEIGHT: &"weight",
	Id.DAMAGE_TAKEN_REDUCTION: &"damage_taken_reduction",
	Id.MAX_ULTIMATE_CHARGE: &"max_ultimate_charge",
}

## Valores neutros. Um personagem sem nenhum atributo definido não deve morrer
## de divisão por zero nem crititar sempre.
##
## `ACCURACY` começa em 1: o padrão é acertar, e esquiva é que tira disso.
## `COOLDOWN_REDUCTION_CAP` em 0.9 repete o teto que `Ability.cooldown_for`
## já aplicava fixo — agora o número mora num lugar só.
const DEFAULTS: Dictionary = {
	Id.MAX_HEALTH: 100.0,
	Id.CRIT_DAMAGE: 1.75,
	Id.ATTACK_SPEED: 1.0,
	Id.ACCURACY: 1.0,
	Id.COOLDOWN_REDUCTION_CAP: 0.9,
	Id.WEIGHT: 1.0,
	Id.SIGHT_RANGE: 12.0,
}

static func name_of(id: Id) -> StringName:
	return NAMES[id]

## Converte o nome usado em arquivo de configuração no identificador.
## Devolve -1 quando o nome não existe — quem chama decide se isso é erro
## de dado ou entrada opcional.
static func from_name(stat_name: StringName) -> int:
	for id: Id in NAMES:
		if NAMES[id] == stat_name:
			return id
	return -1

## Valor de um atributo quando ninguém o definiu.
static func default_of(id: Id) -> float:
	return DEFAULTS.get(id, 0.0)

## Todo identificador do catálogo, em ordem. Um teste usa isto para provar que
## `NAMES` não esqueceu ninguém — o modo mais barato de pegar um atributo novo
## que entrou no enum e não ganhou nome.
static func all_ids() -> Array[Id]:
	var ids: Array[Id] = []
	for id: Id in Id.values():
		ids.append(id)
	return ids
