class_name EffectFactory
extends RefCounted

## Monta um `AbilityEffect` a partir de um dicionário.
##
## É a ponte entre o corpus traduzido do original (`data/traducao/*.json`) e as
## classes de verdade. Sem ela a tradução seria um documento; com ela, as 948
## habilidades do original são objetos que a engine conjura.
##
## O dicionário nomeia as NOSSAS peças — `"type": "damage"`, `"control":
## "STUN"`, `"stat": "attack_damage"`. Não há nenhum nome do original aqui: o
## que traduz é o `tools/traducao/traduzir.py`, e o que este arquivo lê já está
## traduzido. Se um nome do original aparecesse aqui, seria sinal de que a
## tradução vazou para dentro do jogo.
##
## Campo que falta usa o padrão da classe. Campo desconhecido é ignorado em
## silêncio de propósito: o corpus é gerado por ferramenta e pode ganhar
## colunas antes de o carregador aprender a lê-las, e derrubar o jogo por isso
## seria pior que ignorar.

## Nome do tipo -> construtor.
##
## `match` explícito e não tabela de despacho: GDScript não deixa chamar
## `call()` numa classe sem instância, e uma fábrica que precisasse ser
## instanciada para montar um `Resource` seria cerimônia sem ganho. O `match`
## também é o que faz um tipo novo quebrar aqui em tempo de compilação em vez
## de sumir em silêncio.
##
## Devolve nulo quando o tipo é desconhecido — quem chama decide se conta como
## lacuna ou erro.
static func build(data: Dictionary) -> AbilityEffect:
	var effect: AbilityEffect = null
	match StringName(data.get("type", "")):
		&"damage": effect = _damage(data)
		&"heal": effect = _heal(data)
		&"shield": effect = _shield(data)
		&"stat_mod": effect = _stat_mod(data)
		&"crowd_control": effect = _crowd_control(data)
		&"displacement": effect = _displacement(data)
		&"periodic": effect = _periodic(data)
		&"trigger": effect = _trigger(data)
		&"summon": effect = _summon(data)
		&"execute": effect = _execute(data)
		&"resource": effect = _resource(data)
		&"cleanse": effect = _cleanse(data)
		&"mark": effect = _mark(data)
		&"cooldown": effect = _cooldown(data)
	if effect != null:
		effect.recipient = _recipient(data)
	return effect

## Monta uma lista, descartando o que não soube montar. Devolve também quantos
## caíram, por quem chama poder contar.
static func build_all(entries: Array) -> Array[AbilityEffect]:
	var effects: Array[AbilityEffect] = []
	for entry: Variant in entries:
		if entry is Dictionary:
			var effect: AbilityEffect = build(entry)
			if effect != null:
				effects.append(effect)
	return effects

# ---------------------------------------------------------------- auxiliares

static func _recipient(data: Dictionary) -> AbilityEffect.Recipient:
	return AbilityEffect.Recipient.CASTER if data.get("recipient", "TARGETS") == "CASTER" \
		else AbilityEffect.Recipient.TARGETS

static func _f(data: Dictionary, key: String, fallback: float = 0.0) -> float:
	var value: Variant = data.get(key)
	return float(value) if value != null else fallback

static func _i(data: Dictionary, key: String, fallback: int = 0) -> int:
	var value: Variant = data.get(key)
	return int(value) if value != null else fallback

static func _b(data: Dictionary, key: String, fallback: bool = false) -> bool:
	var value: Variant = data.get(key)
	return bool(value) if value != null else fallback

static func _tag(data: Dictionary, fallback: StringName = &"traduzido") -> StringName:
	var value: Variant = data.get("source_tag")
	return StringName(value) if value != null else fallback

## Nome de atributo -> `Stat.Id`. Nome desconhecido cai no padrão em vez de
## estourar: um corpus com um atributo que ainda não existe deve carregar com
## aquele efeito enfraquecido, não derrubar o catálogo inteiro.
static func _stat(data: Dictionary, key: String, fallback: Stat.Id) -> Stat.Id:
	var value: Variant = data.get(key)
	if value == null:
		return fallback
	var id: int = Stat.from_name(StringName(value))
	return id as Stat.Id if id >= 0 else fallback

## Chave de enum -> valor. `Damage.Type` e companhia são dicionários em tempo
## de execução, então a busca é direta.
static func _enum(names: Dictionary, data: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = data.get(key)
	if value == null:
		return fallback
	return int(names.get(String(value), fallback))

# ---------------------------------------------------------------- construtores

static func _damage(data: Dictionary) -> AbilityEffect:
	var effect := DamageEffect.new()
	effect.base_damage = _f(data, "base_damage")
	effect.scaling_stat = _stat(data, "scaling_stat", Stat.Id.ABILITY_POWER)
	effect.scaling_stat_alt = _stat(data, "scaling_stat_alt", effect.scaling_stat)
	effect.scaling_ratio = _f(data, "scaling_ratio")
	effect.damage_type = _enum(
		Damage.Type, data, "damage_type", Damage.Type.MAGIC
	) as Damage.Type
	effect.percent_of_target_max_health = _f(data, "percent_of_target_max_health")
	effect.monster_damage_cap = _f(data, "monster_damage_cap")
	effect.restriction = _enum(
		DamageEffect.Restriction, data, "restriction", DamageEffect.Restriction.ANY
	) as DamageEffect.Restriction
	return effect

static func _heal(data: Dictionary) -> AbilityEffect:
	var effect := HealEffect.new()
	effect.base_heal = _f(data, "base_heal")
	effect.scaling_stat = _stat(data, "scaling_stat", Stat.Id.ABILITY_POWER)
	effect.scaling_ratio = _f(data, "scaling_ratio")
	effect.percent_of_max_health = clampf(_f(data, "percent_of_max_health"), 0.0, 1.0)
	return effect

static func _shield(data: Dictionary) -> AbilityEffect:
	var effect := ShieldEffect.new()
	effect.base_shield = _f(data, "base_shield")
	effect.scaling_stat = _stat(data, "scaling_stat", Stat.Id.ABILITY_POWER)
	effect.scaling_ratio = _f(data, "scaling_ratio")
	effect.duration = _f(data, "duration", 3.0)
	return effect

static func _stat_mod(data: Dictionary) -> AbilityEffect:
	var effect := StatModEffect.new()
	effect.stat = _stat(data, "stat", Stat.Id.ATTACK_DAMAGE)
	effect.kind = _enum(
		StatModifier.Kind, data, "kind", StatModifier.Kind.FLAT
	) as StatModifier.Kind
	effect.value = _f(data, "value")
	effect.duration = _f(data, "duration", 5.0)
	effect.stacks = _b(data, "stacks")
	effect.max_stacks = _i(data, "max_stacks")
	effect.source_tag = _tag(data)
	return effect

static func _crowd_control(data: Dictionary) -> AbilityEffect:
	var effect := CrowdControlEffect.new()
	effect.control = _enum(
		CrowdControlEffect.Kind, data, "control", CrowdControlEffect.Kind.STUN
	) as CrowdControlEffect.Kind
	effect.duration = _f(data, "duration", 1.0)
	effect.slow_amount = clampf(_f(data, "slow_amount", 0.3), 0.0, 1.0)
	effect.ignores_tenacity = _b(data, "ignores_tenacity")
	effect.source_tag = _tag(data)
	return effect

static func _displacement(data: Dictionary) -> AbilityEffect:
	var effect := DisplacementEffect.new()
	effect.mode = _enum(
		DisplacementEffect.Mode, data, "mode", DisplacementEffect.Mode.ALONG_AIM
	) as DisplacementEffect.Mode
	effect.distance = _f(data, "distance", 4.0)
	effect.ignores_root = _b(data, "ignores_root")
	return effect

static func _periodic(data: Dictionary) -> AbilityEffect:
	var effect := PeriodicEffect.new()
	effect.interval = maxf(_f(data, "interval", 1.0), 0.01)
	effect.duration = _f(data, "duration", 3.0)
	effect.ticks_on_apply = _b(data, "ticks_on_apply")
	effect.refreshes = _b(data, "refreshes", true)
	effect.source_tag = _tag(data)
	effect.effects = build_all(data.get("effects", []))
	return effect

static func _trigger(data: Dictionary) -> AbilityEffect:
	var effect := TriggerEffect.new()
	effect.event = _enum(
		TriggerSet.Event, data, "event", TriggerSet.Event.BASIC_ATTACK_HIT
	) as TriggerSet.Event
	effect.charges = _i(data, "charges")
	effect.duration = _f(data, "duration", -1.0)
	effect.source_tag = _tag(data)
	effect.effects = build_all(data.get("effects", []))
	effect.on_expire = build_all(data.get("on_expire", []))
	return effect

static func _summon(data: Dictionary) -> AbilityEffect:
	var effect := SummonEffect.new()
	effect.actor_id = StringName(data.get("actor_id", ""))
	effect.lifetime = _f(data, "lifetime", 10.0)
	effect.origin = _enum(
		SummonEffect.Origin, data, "origin", SummonEffect.Origin.AIM_POINT
	) as SummonEffect.Origin
	effect.forward_offset = _f(data, "forward_offset")
	effect.inherits_caster_team = _b(data, "inherits_caster_team", true)
	effect.explicit_team = _i(data, "explicit_team")
	return effect

static func _execute(data: Dictionary) -> AbilityEffect:
	var effect := ExecuteEffect.new()
	effect.health_threshold = clampf(_f(data, "health_threshold", 1.0), 0.0, 1.0)
	effect.respects_shield = _b(data, "respects_shield", true)
	effect.affects_champions = _b(data, "affects_champions", true)
	return effect

static func _resource(data: Dictionary) -> AbilityEffect:
	var effect := ResourceEffect.new()
	effect.amount = _f(data, "amount")
	effect.percent_of_max = clampf(_f(data, "percent_of_max"), -1.0, 1.0)
	return effect

static func _cleanse(data: Dictionary) -> AbilityEffect:
	var effect := CleanseEffect.new()
	effect.scope = _enum(
		CleanseEffect.Scope, data, "scope", CleanseEffect.Scope.CROWD_CONTROL
	) as CleanseEffect.Scope
	effect.only_source = StringName(data.get("only_source", ""))
	effect.strips_shield = _b(data, "strips_shield")
	return effect

static func _mark(data: Dictionary) -> AbilityEffect:
	var effect := MarkEffect.new()
	effect.mark = StringName(data.get("mark", ""))
	effect.mode = _enum(
		MarkEffect.Mode, data, "mode", MarkEffect.Mode.APPLY
	) as MarkEffect.Mode
	effect.duration = _f(data, "duration", 5.0)
	effect.max_stacks = maxi(_i(data, "max_stacks", 1), 1)
	effect.amount = maxi(_i(data, "amount", 1), 1)
	return effect

static func _cooldown(data: Dictionary) -> AbilityEffect:
	var effect := CooldownEffect.new()
	var grupos: Array[StringName] = []
	for raw: Variant in data.get("group_ids", []):
		grupos.append(StringName(raw))
	effect.group_ids = grupos
	effect.seconds = _f(data, "seconds", -1.0)
	effect.proportional = _b(data, "proportional")
	return effect
