class_name AbilityCatalog
extends RefCounted

## Carrega o corpus traduzido do original e devolve `Ability` de verdade.
##
## É o que torna a tradução **executável**. Sem isto, `data/traducao/*.json`
## seria documentação: 948 habilidades descritas e nenhuma conjurável. Com
## isto, qualquer uma delas entra num `AbilityBook` e passa pela mesma
## `AbilityEngine` que as três habilidades feitas à mão.
##
## Não carrega sozinho na inicialização do jogo. São 2 MB de JSON e ~3200
## efeitos, e o protótipo usa três habilidades — pagar esse custo a cada
## partida para nada seria caro pelo motivo errado. Quem quer, chama.
##
## O corpus é referência de design, não conteúdo do jogo: os números e a
## estrutura entram, nome e descrição do original não (`docs/01-visao-e-escopo.md`).
## Por isso o `display_name` de cada entrada é o identificador do ícone, em
## inglês, e não o texto localizado.

const CAMINHO_PADRAO: String = "res://data/traducao/habilidades.json"

## Habilidades por id. Vazio até `load_from()` rodar.
var by_id: Dictionary = {}

## Ids agrupados por `group_id` — os ranques de uma mesma habilidade.
var by_group: Dictionary = {}

## Diagnóstico do carregamento. Quem chama decide se um número diferente de
## zero em `sem_efeito` é problema; no corpus do original, não é.
var loaded: int = 0
var skipped: int = 0

## Carrega e devolve verdadeiro se o arquivo existia e era JSON válido.
##
## Falha silenciosa seria pior aqui do que em qualquer outro lugar: um catálogo
## vazio parece um catálogo sem entradas úteis, e a causa real — arquivo
## ausente — nunca apareceria.
func load_from(path: String = CAMINHO_PADRAO) -> bool:
	by_id.clear()
	by_group.clear()
	loaded = 0
	skipped = 0
	# Zerar antes de carregar: o contador é da carga, não da sessão.
	EffectFactory.clear_unknown()

	if not FileAccess.file_exists(path):
		push_warning("AbilityCatalog: %s não existe. Rode tools/traducao/traduzir.py" % path)
		return false

	var texto: String = FileAccess.get_file_as_string(path)
	var raiz: Variant = JSON.parse_string(texto)
	if not raiz is Dictionary:
		push_warning("AbilityCatalog: %s não é um JSON de objeto" % path)
		return false

	for entry: Variant in (raiz as Dictionary).get("habilidades", []):
		if not entry is Dictionary:
			continue
		var ability: Ability = build(entry)
		if ability == null:
			skipped += 1
			continue
		by_id[ability.id] = ability
		loaded += 1
		var grupo: StringName = ability.group_id
		if not by_group.has(grupo):
			by_group[grupo] = []
		(by_group[grupo] as Array).append(ability)

	for grupo: StringName in by_group:
		# Ordenar por ranque aqui, uma vez, poupa quem for escolher o ranque
		# certo de ordenar toda vez.
		(by_group[grupo] as Array).sort_custom(
			func(a: Ability, b: Ability) -> bool: return a.rank < b.rank
		)
	return true

func get_ability(id: StringName) -> Ability:
	return by_id.get(id, null) as Ability

## O ranque mais alto de um grupo que o nível do personagem permite.
##
## É como o original organiza progressão: `LevelRequirement` por ranque, e cada
## ranque é uma linha própria. Devolve nulo quando o grupo não existe ou o
## nível não alcança nem o primeiro.
func rank_for_level(group_id: StringName, level: int) -> Ability:
	var ranques: Variant = by_group.get(group_id)
	if not ranques is Array:
		return null
	var escolhido: Ability = null
	for ability: Ability in (ranques as Array):
		if ability.level_requirement <= level and not ability.pulses.is_empty():
			escolhido = ability
	return escolhido

## Todas as habilidades de um dono (`owner` do corpus: `leo`, `sonya`...).
func by_owner(owner: StringName) -> Array[Ability]:
	var achadas: Array[Ability] = []
	for id: StringName in by_id:
		var ability: Ability = by_id[id]
		if ability.get_meta(&"owner", &"") == owner:
			achadas.append(ability)
	return achadas

# ---------------------------------------------------------------- construção

## Monta uma `Ability` a partir de uma entrada do corpus.
##
## Estática para poder ser usada sem catálogo — teste e ferramenta constroem
## uma habilidade avulsa sem carregar 2 MB.
static func build(data: Dictionary) -> Ability:
	var ability := Ability.new()
	ability.id = StringName(data.get("id", ""))
	if ability.id.is_empty():
		return null
	ability.display_name = String(data.get("display_name", ability.id))
	ability.group_id = StringName(data.get("group_id", ability.id))
	ability.rank = int(data.get("rank", 1))
	ability.level_requirement = int(data.get("level_requirement", 0))
	ability.cooldown = float(data.get("cooldown", 0.0))
	ability.cast_time = float(data.get("cast_time", 0.0))
	ability.can_move_while_casting = bool(data.get("can_move_while_casting", false))
	ability.cancelable = bool(data.get("cancelable", true))
	ability.mana_cost = float(data.get("mana_cost", 0.0))
	ability.aim = _enum(Ability.Aim, data.get("aim"), Ability.Aim.POINT) as Ability.Aim
	ability.cast_range = float(data.get("cast_range", 0.0))

	var pulsos: Array[AbilityPulse] = []
	for entry: Variant in data.get("pulses", []):
		if entry is Dictionary:
			var pulse: AbilityPulse = build_pulse(entry)
			if pulse != null:
				pulsos.append(pulse)
	ability.pulses = pulsos

	ability.passive_effects = EffectFactory.build_all(data.get("passive_effects", []))
	# Carimba com o id: é o que faz esquecer a habilidade achar o bônus.
	ability.stamp_passives()

	# Dono e tabela de origem viajam como metadado, e não como campo exportado:
	# são procedência da tradução, não vocabulário de habilidade. Um campo
	# `owner` em `Ability` obrigaria toda habilidade nossa a responder de que
	# personagem do ORIGINAL ela veio, que é uma pergunta sem sentido.
	ability.set_meta(&"owner", StringName(data.get("owner", "")))
	ability.set_meta(&"source_id", int(data.get("source_id", 0)))
	return ability

static func build_pulse(data: Dictionary) -> AbilityPulse:
	var pulse := AbilityPulse.new()
	pulse.form = _enum(
		AbilityPulse.Form, data.get("form"), AbilityPulse.Form.CIRCLE
	) as AbilityPulse.Form
	pulse.origin = _enum(
		AbilityPulse.Origin, data.get("origin"), AbilityPulse.Origin.AIM_POINT
	) as AbilityPulse.Origin
	pulse.delay = float(data.get("delay", 0.0))
	pulse.duration = float(data.get("duration", 0.0))
	pulse.loop_interval = float(data.get("loop_interval", 0.0))
	pulse.radius = float(data.get("radius", 2.5))
	pulse.length = float(data.get("length", 8.0))
	pulse.width = float(data.get("width", 1.5))
	pulse.cone_angle = float(data.get("cone_angle", 60.0))
	pulse.projectile_speed = float(data.get("projectile_speed", 18.0))
	pulse.pierces = bool(data.get("pierces", false))
	pulse.direction_offset = float(data.get("direction_offset", 0.0))
	pulse.spread_count = maxi(int(data.get("spread_count", 1)), 1)
	pulse.spread_angle = float(data.get("spread_angle", 0.0))
	pulse.forward_offset = float(data.get("forward_offset", 0.0))
	pulse.side_offset = float(data.get("side_offset", 0.0))
	pulse.near_distance = float(data.get("near_distance", 1.0))
	pulse.near_width = float(data.get("near_width", 1.0))
	pulse.far_width = float(data.get("far_width", 4.0))
	pulse.hits_enemies = bool(data.get("hits_enemies", true))
	pulse.hits_allies = bool(data.get("hits_allies", false))
	pulse.hits_self = bool(data.get("hits_self", false))
	pulse.max_targets = int(data.get("max_targets", 0))
	pulse.effects = EffectFactory.build_all(data.get("effects", []))
	return pulse

## Valor presente e irreconhecível é REGISTRADO, não engolido. Ver o comentário
## de `EffectFactory`: silêncio que cai no padrão pode inverter o sentido.
static func _enum(names: Dictionary, value: Variant, fallback: int) -> int:
	if value == null:
		return fallback
	if not names.has(String(value)):
		EffectFactory.note_unknown("enum", value)
		return fallback
	return int(names[String(value)])
