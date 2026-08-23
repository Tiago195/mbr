class_name Ability
extends Resource

## Uma habilidade declarada como dado — Fase 3.2, reestruturada na tradução do
## original (`docs/10-traducao-do-original.md`).
##
## Nada aqui é comportamento: é a combinação de peças de um vocabulário
## fechado. Habilidade nova deve ser um `.tres` novo, sem uma linha de código
## de sistema. Se uma habilidade exigir classe nova, o sistema está errado —
## generalize antes de continuar (`03-sistemas-de-jogo.md`).
##
## **O que mudou na tradução:** forma, filtro e efeitos saíram daqui e foram
## para `AbilityPulse`. Uma habilidade agora é *ativação + mira + uma lista de
## pulsos*. O motivo está em `ability_pulse.gd`: uma habilidade do original tem
## até 12 golpes com tempo, forma e alvos independentes — e cada golpe ainda
## pode encadear outro. Uma forma só não expressa isso.
##
## Habilidade de golpe único continua sendo um `.tres` com um pulso. Não ficou
## mais cara — ficou capaz.
##
## Nomes dos enums escolhidos para não colidir com classe embutida da Godot:
## `Aim` e não `Target`. Ver a armadilha registrada em `CLAUDE.md`.

## Como o jogador aponta.
enum Aim {
	## Sem mira. Age no próprio conjurador.
	SELF,
	## Um ponto do chão.
	POINT,
	## Uma direção a partir do conjurador.
	DIRECTION,
	## Um combatente escolhido a dedo.
	UNIT,
}

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Ativação")
## Segundos de recarga, antes de redução de recarga.
@export var cooldown: float = 6.0
## Segundos parado antes do efeito sair. 0 = instantânea.
@export var cast_time: float = 0.0
## Se falso, conjurar prende o personagem no lugar.
@export var can_move_while_casting: bool = false
## Se falso, nem o próprio jogador cancela depois de começar.
@export var cancelable: bool = true
## Mana cobrada ao conjurar. O original cobra em 684 das 948 habilidades.
## Quem não tem mana máxima conjura de graça — ver `ResourcePool`.
@export var mana_cost: float = 0.0

## Quando verdadeiro, conjurar esta habilidade ZERA a cadência do ataque
## básico — o próximo golpe sai na hora em vez de esperar a velocidade de
## ataque.
##
## `ResetAttackCoolTime` do original: **259** dizem verdadeiro e **262**
## dizem falso. O censo do tradutor contava 521 porque contava outra coisa: a
## COLUNA presente, e `"False"` é string não-vazia, então ele soma as duas
## metades. É a mesma armadilha que deu 123 `FollowTarget` em 124.
##
## Pelo caminho que o jogo percorre são **44 dos 127 espaços de campeão** —
## **22 campeões** têm ao menos um.
##
## **Ao conjurar, não ao acertar** — mesma leitura, e pelo mesmo motivo, de
## `ultimate_charge_gain`: a coluna é da habilidade e não do impacto, e o
## original não tem onde declarar "só se acertar". Ver a decisão 18.
@export var resets_attack_cooldown: bool = false

@export_group("Alvo")
@export var aim: Aim = Aim.POINT
## Distância máxima do ponto ou alvo mirado. 0 = sem limite.
@export var cast_range: float = 8.0

@export_group("Pulsos")
## Os golpes, em ordem. Cada um com sua forma, seu tempo e seus efeitos.
@export var pulses: Array[AbilityPulse] = []

@export_group("Passiva do ranque")
## Efeitos aplicados ao APRENDER esta habilidade neste ranque, e removidos ao
## esquecê-la ou ao trocar de ranque.
##
## Vem de `skill_xml`, que tem `StatType1`/`StatValue1` em 8 grupos de
## habilidade — 40 linhas ao todo. Não é o que a habilidade FAZ ao ser
## conjurada: é o que ela dá por existir. O Q do Rody, por exemplo, dá
## 2%/4%/6%/8%/10% de redução de recarga conforme o ranque.
##
## É o mesmo vocabulário de `Item.passive_effects`, e pela mesma razão de
## sempre: passiva de habilidade e passiva de item não são dois sistemas.
##
## Convenção idêntica à do item: a `source_tag` de cada efeito é o `id` desta
## habilidade, porque é por ela que esquecer encontra o que remover.
@export var passive_effects: Array[AbilityEffect] = []

@export_group("Carga de suprema")
## Quanta carga esta habilidade rende ao ser conjurada com sucesso.
##
## `UltimateCharge` do original: **517 habilidades** declaram, de **33 a 600**.
## O ataque básico rende 200 e a suprema rende 0 — ela consome.
##
## **Ao conjurar, não ao acertar.** A coluna é da habilidade, não do impacto: o
## original não tem granularidade por acerto, e "só enche se acertar" seria
## invenção. O ataque básico é a exceção, e por um motivo de dado, não de
## gosto: ele não passa por aqui, e `Unit.basic_attack` sabe se errou.
@export var ultimate_charge_gain: float = 0.0

## Quando verdadeiro, esta habilidade EXIGE carga cheia e a gasta inteira.
##
## Marcado por `ActorProfile.ultimate_for()` na cópia que ele entrega, e não no
## dado do corpus: "ser a suprema" é papel no kit de um campeão, não
## propriedade da habilidade. A mesma habilidade emprestada a um mob não seria
## suprema de ninguém.
@export var uses_ultimate_charge: bool = false

@export_group("Progressão")
## Nível da habilidade, 1 a 5. O original guarda cada ranque como uma linha
## separada de `skill_xml` compartilhando o mesmo `SkillGroupID` — quer dizer,
## ranque não é um multiplicador aplicado em cima, é outro conjunto de números.
## Copiamos essa decisão: cada ranque é um `.tres` próprio.
@export var rank: int = 1
## Identificador comum aos ranques da mesma habilidade.
@export var group_id: StringName = &""
## Nível de personagem exigido para subir a este ranque.
@export var level_requirement: int = 0

## Recarga já com a redução do conjurador aplicada.
func cooldown_for(caster: Unit) -> float:
	if caster == null:
		return cooldown
	# O teto sai do atributo, não de uma constante: o original tem
	# `MaxCDReductionRatio` como atributo próprio, e isso permite um item
	# ELEVAR o teto em vez de só chegar mais perto dele. O padrão continua
	# sendo 0.9, agora declarado em `Stat.DEFAULTS`.
	var cap: float = maxf(caster.stats.get_value(Stat.Id.COOLDOWN_REDUCTION_CAP), 0.0)
	var reduction: float = clampf(
		caster.stats.get_value(Stat.Id.COOLDOWN_REDUCTION), 0.0, cap
	)
	return cooldown * (1.0 - reduction)

## O pulso principal — o primeiro. É o que a telegrafia desenha e o que a IA
## usa para estimar alcance. Nulo numa habilidade sem pulso, que é dado
## inválido e a engine recusa.
func primary_pulse() -> AbilityPulse:
	return pulses[0] if not pulses.is_empty() else null

## O pulso único, criando-o se ainda não houver.
##
## Existe para declarar habilidade de um golpe só sem duas linhas de cerimônia.
## Em `.tres` a lista vem preenchida do disco e isto nunca cria nada; em código
## — teste e ferramenta de tradução — é o atalho.
func single_pulse() -> AbilityPulse:
	if pulses.is_empty():
		pulses = [AbilityPulse.new()]
	return pulses[0]

## Aplica a passiva do ranque a quem aprendeu. Chamado por `AbilityBook.learn`.
func apply_passives(owner: Unit) -> void:
	if owner == null or passive_effects.is_empty():
		return
	var cast: AbilityCast = AbilityCast.on_self(owner)
	for effect: AbilityEffect in passive_effects:
		if effect != null:
			effect.apply(cast, owner)

## Desfaz a passiva do ranque. Chamado ao esquecer ou ao trocar de ranque.
func remove_passives(owner: Unit) -> void:
	if owner == null or passive_effects.is_empty():
		return
	owner.stats.remove_source(&"buff:%s" % id)
	owner.periodic.remove_source(&"periodico:%s" % id)
	owner.triggers.remove_source(&"gatilho:%s" % id)

## Carimba a etiqueta de toda passiva com o id da habilidade. Mesmo contrato de
## `Item.stamp_passives()`, e pelo mesmo motivo: sem a etiqueta certa, esquecer
## a habilidade não acha o bônus e ele fica para sempre.
func stamp_passives() -> void:
	for effect: AbilityEffect in passive_effects:
		if effect != null and &"source_tag" in effect:
			effect.set(&"source_tag", id)

func has_pulses() -> bool:
	for pulse: AbilityPulse in pulses:
		if pulse != null and not pulse.effects.is_empty():
			return true
	return false

## Verdadeiro quando TODO efeito de TODO pulso depende de acertar alguém.
##
## Basta um efeito no conjurador — o escudo de uma investida — para a resposta
## ser falsa: aí a conjuração tem o que fazer mesmo sem pegar ninguém.
func requires_target() -> bool:
	var any: bool = false
	for pulse: AbilityPulse in pulses:
		if pulse == null or pulse.effects.is_empty():
			continue
		any = true
		if not pulse.requires_target():
			return false
	return any

## Verdadeiro quando não acertar ninguém deve RECUSAR a conjuração, em vez de
## gastá-la.
##
## Só vale para alvo único: aí não há comando a emitir, e recusar é o certo.
##
## Skillshot — POINT e DIRECTION — **gasta mesmo errando**. Errar é parte do
## jogo, e devolver a recarga de quem errou tornaria mira irrelevante. Isto já
## foi ao contrário: habilidade instantânea era devolvida e habilidade com
## tempo de conjuração não, porque a recarga da segunda começa ao iniciar.
## Dois comportamentos para a mesma situação, sem motivo.
func refuses_without_target() -> bool:
	return aim == Aim.UNIT and requires_target()

## Quanto tempo, depois do fim da conjuração, até o último pulso sair.
## Serve para a camada visual saber quanto tempo manter a telegrafia.
func total_pulse_time() -> float:
	var last: float = 0.0
	for pulse: AbilityPulse in pulses:
		if pulse == null:
			continue
		last = maxf(last, pulse.delay + maxf(pulse.duration, 0.0))
	return last

func describe() -> String:
	var parts: PackedStringArray = []
	for pulse: AbilityPulse in pulses:
		if pulse != null:
			parts.append(pulse.describe())
	return "%s [%s] %s" % [
		display_name if not display_name.is_empty() else String(id),
		Aim.keys()[aim].to_lower(),
		" | ".join(parts),
	]
