class_name ChampionSelector
extends Node

## Faz o jogador ser um campeão do original, com o kit dele.
##
## É o fio que faltava. `AbilityCatalog` e `ActorCatalog` existiam e não eram
## citados por nada fora de `scripts/core/` — a tradução estava provada por
## teste e invisível em jogo. Este nó pega um perfil, escreve os atributos no
## `Combatant` irmão e o kit no `AbilityCaster` irmão.
##
## **Não conhece regra de combate.** Ele lê catálogo e chama dois métodos. Toda
## a decisão continua em `core/`, que é o que permite o servidor headless fazer
## a mesma coisa sem cena.
##
## `Page Down` e `Page Up` trocam de campeão em jogo. É provisório e é de
## propósito: a Fase 1 não tem tela de seleção, e sem um jeito de trocar
## testar 28 campeões exigiria 28 edições da cena.

## Qual campeão. Vazio deixa o kit do Inspector do `AbilityCaster` valendo.
@export var champion_id: StringName = &"leo"

## Nível do personagem. 9 é onde todo ranque de habilidade do original está
## disponível (`LevelRequirement` 1, 3, 5, 7, 9).
@export_range(1, 18) var level: int = 9

## Só os campeões com as quatro habilidades conjuráveis entram na roda.
##
## Cinco dos 33 têm um espaço que cai numa lacuna da tradução — o `RELATORIO.md`
## os nomeia. Eles continuam no catálogo e continuam selecionáveis por
## `champion_id`; o que não faz sentido é a roda de teste parar num campeão com
## um botão morto sem o testador saber por quê.
@export var cycle_only_complete: bool = true

## Painel de canto com o campeão, os atributos e o kit.
@export var show_hud: bool = true

var actors: ActorCatalog
var abilities: AbilityCatalog

## O perfil em uso. Nulo quando nenhum campeão foi carregado.
var current: ActorProfile

var _combatant: Combatant
var _caster: AbilityCaster
var _wheel: Array[ActorProfile] = []
var _index: int = -1
var _label: Label

func _ready() -> void:
	_combatant = Combatant.of(get_parent())
	_caster = _find_caster()
	if _combatant == null or _caster == null:
		push_warning("ChampionSelector sem Combatant ou AbilityCaster irmão.")
		return
	_combatant.ensure_ready()
	_caster.ensure_ready()

	if show_hud:
		_build_hud()

	actors = ActorCatalog.new()
	if not actors.load_from():
		_show("sem data/traducao/atores.json — rode tools/traducao/traduzir.py")
		return
	abilities = AbilityCatalog.new()
	if not abilities.load_from():
		_show("sem data/traducao/habilidades.json")
		return

	_wheel = _build_wheel()
	if champion_id.is_empty():
		_show("kit do Inspector (nenhum campeão do original)")
		return
	select(champion_id)

## Os dois irmãos que este nó escreve. Públicos porque a sonda de
## `tools/sondar_campeoes.gd` precisa deles, e ler `_caster` de fora seria
## depender de um nome que o sublinhado promete não ser estável.
func caster() -> AbilityCaster:
	return _caster

func combatant() -> Combatant:
	return _combatant

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"champion_next"):
		_step(1)
	elif event.is_action_pressed(&"champion_prev"):
		_step(-1)

# ---------------------------------------------------------------- seleção

## Troca para um campeão pelo id. Devolve se conseguiu.
func select(id: StringName) -> bool:
	if actors == null:
		return false
	var profile: ActorProfile = actors.get_profile(id)
	if profile == null:
		_show("campeão `%s` não existe no catálogo" % id)
		return false
	_adopt(profile)
	_index = _wheel.find(profile)
	return true

func _step(direction: int) -> void:
	if _wheel.is_empty():
		return
	# `posmod` e não `%`: em GDScript o resto de um negativo é negativo, e
	# voltar do primeiro campeão daria índice -1.
	_index = posmod(_index + direction, _wheel.size())
	_adopt(_wheel[_index])

func _adopt(profile: ActorProfile) -> void:
	# A passiva do campeão anterior sai ANTES de a nova entrar. Sem isto,
	# passear pela roda somaria a passiva de todos por onde se passou.
	if current != null and _combatant.unit != null:
		current.remove_passives(_combatant.unit)

	current = profile
	_combatant.adopt_profile(profile, level)
	var espacos: int = _caster.adopt_kit(profile, abilities, level)
	profile.apply_passives(_combatant.unit)

	var texto: String = _describe(profile, espacos)
	print("[campeão] %s" % texto.replace("\n", " | "))
	_show(texto)

## Os campeões que a roda percorre.
func _build_wheel() -> Array[ActorProfile]:
	var roda: Array[ActorProfile] = []
	for profile: ActorProfile in actors.champions():
		# `rc_actor_*` é ator sem `LootPreset` — casca de tutorial e de teste do
		# original, não campeão. Um deles tem 278 de armadura e 216 de ataque,
		# e cair nele girando a roda pareceria bug de tradução em vez de dado.
		# Continua selecionável por `champion_id`, que é onde faz sentido.
		if String(profile.id).begins_with("rc_actor_"):
			continue
		if cycle_only_complete and not _is_complete(profile):
			continue
		roda.append(profile)
	return roda

## Verdadeiro quando os quatro espaços têm ranque conjurável no nível atual.
func _is_complete(profile: ActorProfile) -> bool:
	if profile.ultimate_group.is_empty():
		return false
	if profile.ability_groups.size() < 3:
		return false
	for grupo: StringName in profile.ability_groups:
		if ActorProfile.ability_for(abilities, grupo, level) == null:
			return false
	return ActorProfile.ability_for(abilities, profile.ultimate_group, level) != null

# ---------------------------------------------------------------- painel

func _describe(profile: ActorProfile, espacos: int) -> String:
	var stats: Stats = _combatant.stats
	var linhas: Array[String] = []
	linhas.append("%s  (%s, nível %d)" % [
		String(profile.id).capitalize(),
		String(profile.role) if not profile.role.is_empty() else "?",
		level,
	])
	linhas.append("vida %.0f   ataque %.0f   armadura %.0f/%.0f" % [
		stats.get_value(Stat.Id.MAX_HEALTH),
		stats.get_value(Stat.Id.ATTACK_DAMAGE),
		stats.get_value(Stat.Id.ARMOR),
		stats.get_value(Stat.Id.MAGIC_RESIST),
	])
	linhas.append("alcance %.1fm   %.2f atq/s   passo %.1f   mana %.0f" % [
		stats.get_value(Stat.Id.ATTACK_RANGE),
		stats.get_value(Stat.Id.ATTACK_SPEED),
		stats.get_value(Stat.Id.MOVE_SPEED),
		stats.get_value(Stat.Id.MAX_MANA),
	])
	if espacos < 4:
		linhas.append("(%d de 4 espaços — ver data/traducao/RELATORIO.md)" % espacos)
	for slot: AbilityBook.Slot in [
		AbilityBook.Slot.Q, AbilityBook.Slot.W,
		AbilityBook.Slot.E, AbilityBook.Slot.R,
	]:
		var ability: Ability = _caster.book.ability_in(slot)
		var nome: String = AbilityBook.Slot.keys()[slot]
		if ability == null:
			linhas.append("%s  —" % nome)
			continue
		linhas.append("%s  %s   %.1fs   %.0f mana" % [
			nome, ability.display_name, ability.cooldown, ability.mana_cost
		])
	linhas.append("PgDn/PgUp trocam de campeão (%d na roda)" % _wheel.size())
	return "\n".join(linhas)

func _build_hud() -> void:
	var camada := CanvasLayer.new()
	camada.name = "ChampionHUD"
	add_child(camada)

	var fundo := ColorRect.new()
	fundo.color = Color(0.0, 0.0, 0.0, 0.55)
	fundo.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fundo.offset_left = 8.0
	fundo.offset_top = 8.0
	fundo.size = Vector2(360, 190)
	# Sem isto o retângulo come o clique do botão direito e o personagem para
	# de andar quando o cursor passa por cima do painel.
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(fundo)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 10.0
	_label.offset_top = 6.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fundo.add_child(_label)

func _show(texto: String) -> void:
	if _label != null:
		_label.text = texto

func _find_caster() -> AbilityCaster:
	var host: Node = get_parent()
	if host == null:
		return null
	for child: Node in host.get_children():
		if child is AbilityCaster:
			return child
	return null
