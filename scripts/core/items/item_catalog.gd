class_name ItemCatalog
extends RefCounted

## Carrega o corpus traduzido de itens e devolve `Item` de verdade.
##
## Mesmo papel de `AbilityCatalog`, e a mesma razão: sem isto os 421 itens do
## original seriam uma tabela lida por humanos; com isto eles equipam, dão
## atributos, rodam passiva e — quando o original manda — conjuram.
##
## Os itens de uso ativo apontam para uma habilidade do corpus. Por isso o
## catálogo de itens aceita um de habilidades: passar um resolve as ativas,
## não passar deixa `active_ability` nulo e o item vira só bônus. As duas
## situações são legítimas, e falhar quando falta o catálogo de habilidades
## impediria de olhar os itens sem carregar 2 MB.

const CAMINHO_PADRAO: String = "res://data/traducao/itens.json"

var by_id: Dictionary = {}
## Itens agrupados por `line_id`: a mesma espada em Uncommon, Rare e Epic.
var by_line: Dictionary = {}

var loaded: int = 0
var skipped: int = 0
## Quantas ativas ficaram sem habilidade porque não havia catálogo, ou porque
## a habilidade citada não estava nele.
var unresolved_actives: int = 0

func load_from(
		path: String = CAMINHO_PADRAO, abilities: AbilityCatalog = null
) -> bool:
	by_id.clear()
	by_line.clear()
	loaded = 0
	skipped = 0
	unresolved_actives = 0
	# Zerar antes de carregar: o contador é da carga, não da sessão.
	EffectFactory.clear_unknown()

	if not FileAccess.file_exists(path):
		push_warning("ItemCatalog: %s não existe. Rode tools/traducao/traduzir.py" % path)
		return false

	var raiz: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raiz is Dictionary:
		push_warning("ItemCatalog: %s não é um JSON de objeto" % path)
		return false

	for entry: Variant in (raiz as Dictionary).get("itens", []):
		if not entry is Dictionary:
			continue
		var item: Item = build(entry, abilities)
		if item == null:
			skipped += 1
			continue
		if item.get_meta(&"active_pendente", false):
			unresolved_actives += 1
		by_id[item.id] = item
		loaded += 1
		var linha: StringName = item.line_id
		if not by_line.has(linha):
			by_line[linha] = []
		(by_line[linha] as Array).append(item)

	for linha: StringName in by_line:
		# Da raridade mais baixa para a mais alta: é a ordem de melhoria, e é
		# a única que interessa a quem olha uma linha.
		(by_line[linha] as Array).sort_custom(
			func(a: Item, b: Item) -> bool: return a.rarity < b.rarity
		)
	return true

func get_item(id: StringName) -> Item:
	return by_id.get(id, null) as Item

## O degrau IMEDIATAMENTE acima na mesma linha, ou nulo se já é o topo.
##
## "Imediatamente" importa: 79 linhas do corpus têm três degraus ou mais, e uma
## tem nove. Devolver o topo em vez do próximo transformaria "melhorar o item"
## em "pular direto para o melhor", que é outro jogo.
##
## A lista vem ordenada por raridade de `load_from`, então o primeiro que
## superar já é o próximo — mas dois itens podem dividir raridade, e por isso a
## busca é pelo MENOR acima, não pelo primeiro encontrado.
func upgrade_of(item: Item) -> Item:
	if item == null:
		return null
	var linha: Variant = by_line.get(item.line_id)
	if not linha is Array:
		return null
	var melhor: Item = null
	for candidato: Item in (linha as Array):
		if candidato.rarity <= item.rarity:
			continue
		if melhor == null or candidato.rarity < melhor.rarity:
			melhor = candidato
	return melhor

# ---------------------------------------------------------------- construção

static func build(data: Dictionary, abilities: AbilityCatalog = null) -> Item:
	var item := Item.new()
	item.id = StringName(data.get("id", ""))
	if item.id.is_empty():
		return null
	item.display_name = String(data.get("display_name", item.id))
	item.kind = _enum(Item.Kind, data.get("kind"), Item.Kind.EQUIPMENT) as Item.Kind
	item.slot = _enum(Item.Slot, data.get("slot"), Item.Slot.NONE) as Item.Slot
	item.rarity = _enum(Item.Rarity, data.get("rarity"), Item.Rarity.COMMON) as Item.Rarity
	item.max_stack = maxi(int(data.get("max_stack", 1)), 1)
	item.line_id = StringName(data.get("line_id", item.id))
	item.sockets = int(data.get("sockets", 0))
	item.charges = int(data.get("charges", 0))

	item.flat_bonuses = _bonuses(data.get("flat_bonuses", {}))
	item.percent_bonuses = _bonuses(data.get("percent_bonuses", {}))

	item.passive_effects = EffectFactory.build_all(data.get("passive_effects", []))
	# Carimba a etiqueta com o id do item: é o que faz desequipar achar o que
	# remover. Sem isto, o bônus da passiva ficaria para sempre.
	item.stamp_passives()

	var construido: Array[StringName] = []
	for raw: Variant in data.get("built_from", []):
		construido.append(StringName(raw))
	item.built_from = construido

	var ativa: StringName = StringName(data.get("active_ability_id", ""))
	if not ativa.is_empty():
		if abilities != null:
			item.active_ability = abilities.get_ability(ativa)
		if item.active_ability == null:
			item.set_meta(&"active_pendente", true)
			item.set_meta(&"active_ability_id", ativa)

	item.set_meta(&"source_id", int(data.get("source_id", 0)))
	item.set_meta(&"enabled", bool(data.get("enabled", true)))
	return item

## `{"attack_damage": 25}` -> `{Stat.Id.ATTACK_DAMAGE: 25.0}`.
## Atributo desconhecido é descartado: melhor um item com um bônus a menos que
## um dicionário com a chave -1, que somaria em nada e confundiria a depuração.
static func _bonuses(raw: Variant) -> Dictionary:
	var saida: Dictionary = {}
	if not raw is Dictionary:
		return saida
	for nome: Variant in (raw as Dictionary):
		var id: int = Stat.from_name(StringName(nome))
		if id < 0:
			EffectFactory.note_unknown("bonus", nome)
			continue
		saida[id] = float((raw as Dictionary)[nome])
	return saida

static func _enum(names: Dictionary, value: Variant, fallback: int) -> int:
	if value == null:
		return fallback
	if not names.has(String(value)):
		EffectFactory.note_unknown("enum", value)
		return fallback
	return int(names[String(value)])
