class_name ActorCatalog
extends RefCounted

## Carrega os personagens traduzidos e devolve `ActorProfile` de verdade.
##
## Terceiro catálogo, mesmo desenho de `AbilityCatalog` e `ItemCatalog` — e o
## que fecha o circuito: os outros dois descrevem peças, este diz quem as usa.
##
## Não carrega sozinho na inicialização. Quem quer um campeão, chama.
##
## O corpus é referência de design, não conteúdo do jogo. Por isso o
## `display_name` é o identificador em inglês do original (`leo`, `bella`), e
## nunca o nome coreano — que é conteúdo (`docs/01-visao-e-escopo.md`).

const CAMINHO_PADRAO: String = "res://data/traducao/atores.json"

## Perfis por id.
var by_id: Dictionary = {}
## Ids agrupados por `UsageType` do original: `Player`, `Monster`, `AIPlayer`...
var by_usage: Dictionary = {}

var loaded: int = 0
var skipped: int = 0

func load_from(path: String = CAMINHO_PADRAO) -> bool:
	by_id.clear()
	by_usage.clear()
	loaded = 0
	skipped = 0
	EffectFactory.clear_unknown()

	if not FileAccess.file_exists(path):
		push_warning("ActorCatalog: %s não existe. Rode tools/traducao/traduzir.py" % path)
		return false

	var raiz: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raiz is Dictionary:
		push_warning("ActorCatalog: %s não é um JSON de objeto" % path)
		return false

	for entry: Variant in (raiz as Dictionary).get("atores", []):
		if not entry is Dictionary:
			continue
		var profile: ActorProfile = build(entry)
		if profile == null:
			skipped += 1
			continue
		by_id[profile.id] = profile
		loaded += 1
		if not by_usage.has(profile.usage):
			by_usage[profile.usage] = []
		(by_usage[profile.usage] as Array).append(profile)
	return true

func get_profile(id: StringName) -> ActorProfile:
	return by_id.get(id, null) as ActorProfile

## Os campeões jogáveis, em ordem de id do original.
##
## "Jogável" é mais estreito que `UsageType == Player`, e a diferença importa:
## a tabela tem 40 linhas de jogador e só 33 delas têm as três habilidades.
## As outras são bonecos de tutorial e cascas de teste, e entregá-las numa
## lista de escolha daria ao jogador um campeão sem kit.
func champions() -> Array[ActorProfile]:
	var achados: Array[ActorProfile] = []
	for profile: ActorProfile in (by_usage.get(&"Player", []) as Array):
		if profile.is_champion():
			achados.append(profile)
	achados.sort_custom(
		func(a: ActorProfile, b: ActorProfile) -> bool:
			return a.source_id < b.source_id
	)
	return achados

## Todos os perfis de um `UsageType`, jogáveis ou não.
func with_usage(usage: StringName) -> Array[ActorProfile]:
	var achados: Array[ActorProfile] = []
	for profile: ActorProfile in (by_usage.get(usage, []) as Array):
		achados.append(profile)
	return achados

# ---------------------------------------------------------------- construção

static func build(data: Dictionary) -> ActorProfile:
	var profile := ActorProfile.new()
	profile.id = StringName(data.get("id", ""))
	if profile.id.is_empty():
		return null
	profile.source_id = int(data.get("source_id", 0))
	profile.display_name = String(data.get("display_name", profile.id))
	profile.usage = StringName(data.get("usage", ""))
	profile.nature = _nature(data.get("nature")) as Unit.Nature
	profile.role = StringName(data.get("role", ""))
	profile.enabled = bool(data.get("enabled", true))
	profile.base_level = maxi(int(data.get("base_level", 1)), 1)

	profile.base_stats = _stats(data.get("base_stats", {}))
	profile.growth = _stats(data.get("growth", {}))

	profile.basic_attack_group = StringName(data.get("basic_attack_group", ""))
	var grupos: Array[StringName] = []
	for grupo: Variant in data.get("ability_groups", []):
		grupos.append(StringName(grupo))
	profile.ability_groups = grupos
	profile.ultimate_group = StringName(data.get("ultimate_group", ""))
	profile.ultimate_uses_charge = bool(data.get("ultimate_uses_charge", false))
	profile.ultimate_cooldown = float(data.get("ultimate_cooldown", 0.0))

	profile.passive_effects = EffectFactory.build_all(
		data.get("passive_effects", [])
	)
	profile.stamp_passives()

	profile.body_radius = float(data.get("body_radius", 0.5))
	profile.body_height = float(data.get("body_height", 2.0))
	profile.damageable = bool(data.get("damageable", true))
	profile.targetable = bool(data.get("targetable", true))
	profile.able_combat = bool(data.get("able_combat", true))
	profile.ai_profile = StringName(data.get("ai_profile", ""))
	profile.max_summons = int(data.get("max_summons", 0))

	profile.on_spawn_group = StringName(data.get("on_spawn_group", ""))
	profile.on_death_group = StringName(data.get("on_death_group", ""))
	profile.on_combat_start_group = StringName(
		data.get("on_combat_start_group", "")
	)
	profile.on_return_group = StringName(data.get("on_return_group", ""))
	return profile

## `{"max_health": 2000.0}` -> `{Stat.Id.MAX_HEALTH: 2000.0}`.
##
## Nome que não existe no catálogo de atributos é REGISTRADO, não engolido.
## Mesma razão de `EffectFactory`: um atributo que some em silêncio deixa o
## personagem com o valor padrão, e um campeão com a vida padrão de 100 parece
## um campeão frágil em vez de um campeão mal carregado.
static func _stats(raw: Variant) -> Dictionary:
	var valores: Dictionary = {}
	if not raw is Dictionary:
		return valores
	for nome: Variant in (raw as Dictionary):
		var id: int = Stat.from_name(StringName(nome))
		if id < 0:
			EffectFactory.note_unknown("stat", nome)
			continue
		valores[id] = float((raw as Dictionary)[nome])
	return valores

static func _nature(value: Variant) -> int:
	if value == null:
		return Unit.Nature.MONSTER
	var nomes: Dictionary = Unit.Nature
	if not nomes.has(String(value)):
		EffectFactory.note_unknown("nature", value)
		return Unit.Nature.MONSTER
	return int(nomes[String(value)])
