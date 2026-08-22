class_name AbilityCaster
extends Node

## Liga o motor de habilidade ao jogador — Fases 3.3 e 3.4.
##
## Traduz tecla e cursor em `AbilityCast`, chama a engine, e desenha a
## telegrafia do que aconteceu. Nenhuma regra de combate mora aqui: quem decide
## é `AbilityEngine`, e esta camada só pergunta e mostra.
##
## Hoje só o jogador conjura. Quando os mobs ganharem IA (Fase 6), a mira deixa
## de vir do cursor e passa a vir da decisão da IA — o `AbilityBook` e a engine
## continuam os mesmos.

## Habilidades por slot. Arraste os `.tres` de `data/abilities/` no Inspector.
@export var ability_q: Ability
@export var ability_w: Ability
@export var ability_e: Ability

@export_group("Telegrafia")
@export var color_area: Color = Color(0.95, 0.55, 0.15)
@export var color_line: Color = Color(0.45, 0.70, 1.0)
@export var color_dash: Color = Color(0.65, 0.95, 0.55)

var book: AbilityBook

var _combatant: Combatant

## Guardada porque a telegrafia de uma conjuração com tempo precisa da mira
## original quando o efeito sai, muitos frames depois da tecla.
var _last_cast: AbilityCast

func _ready() -> void:
	_combatant = Combatant.of(get_parent())
	if _combatant == null:
		push_warning("AbilityCaster sem Combatant irmão.")
		return
	_combatant.ensure_ready()

	book = AbilityBook.new()
	book.learn(AbilityBook.Slot.Q, ability_q)
	book.learn(AbilityBook.Slot.W, ability_w)
	book.learn(AbilityBook.Slot.E, ability_e)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ability_q"):
		_try_cast(AbilityBook.Slot.Q)
	elif event.is_action_pressed(&"ability_w"):
		_try_cast(AbilityBook.Slot.W)
	elif event.is_action_pressed(&"ability_e"):
		_try_cast(AbilityBook.Slot.E)

func _physics_process(delta: float) -> void:
	if book == null or _combatant == null or _combatant.unit == null:
		return
	book.advance_time(delta, _combatant.unit)
	if book.cast_is_ready():
		var pending: Ability = book.casting_ability()
		var result: CastResult = AbilityEngine.resolve_pending(
			book, Combatant.all_units(get_tree())
		)
		_report(pending, result)
		if result.succeeded():
			_draw(pending, _last_cast)

# ---------------------------------------------------------------- conjuração

func _try_cast(slot: AbilityBook.Slot) -> void:
	var ability: Ability = book.ability_in(slot)
	if ability == null:
		return

	var cast: AbilityCast = _aim(ability)
	if cast == null:
		return
	_last_cast = cast

	var result: CastResult = AbilityEngine.cast(
		book, ability, cast, Combatant.all_units(get_tree())
	)
	_report(ability, result)

	# A telegrafia da conjuração com tempo sai no início, não no fim: é ela que
	# avisa o adversário que algo vem vindo, e avisar depois do impacto não
	# serve para nada.
	if result.succeeded() or result.started():
		_draw(ability, cast)

## Monta a mira a partir do cursor, conforme o tipo de alvo da habilidade.
func _aim(ability: Ability) -> AbilityCast:
	var unit: Unit = _combatant.unit
	match ability.aim:
		Ability.Aim.SELF:
			return AbilityCast.on_self(unit)
		Ability.Aim.DIRECTION:
			var toward: Variant = _ground_under_cursor()
			if not toward is Vector3:
				return null
			return AbilityCast.toward(unit, (toward as Vector3) - unit.position)
		_:
			# POINT e UNIT compartilham a conversão; mira em unidade específica
			# entra quando houver habilidade que precise dela.
			var point: Variant = _ground_under_cursor()
			if not point is Vector3:
				return null
			return AbilityCast.at_point(unit, point as Vector3)

## Mesmo raycast contra plano que o movimento usa. Devolve nulo quando o cursor
## aponta acima da linha do horizonte.
func _ground_under_cursor() -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var screen: Vector2 = get_viewport().get_mouse_position()
	var ground := Plane(Vector3.UP, _combatant.unit.position.y)
	return ground.intersects_ray(
		camera.project_ray_origin(screen), camera.project_ray_normal(screen)
	)

# ---------------------------------------------------------------- visual

func _draw(ability: Ability, cast: AbilityCast) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null or cast == null:
		return

	match ability.form:
		Ability.Form.CIRCLE:
			AbilityTelegraph.circle(scene_root, cast.point, ability.radius, color_area)
		Ability.Form.PROJECTILE:
			# O dano já saiu quando a esfera parte. É mentira visual, e é
			# consciente: projétil que viaja de verdade precisa resolver
			# colisão ao longo do voo, o que muda o momento em que o servidor
			# decide o acerto. Fica para a Fase 4, junto do netcode.
			AbilityTelegraph.projectile(
				scene_root, cast.caster.position,
				cast.caster.position + cast.direction * ability.length,
				ability.projectile_speed, color_line
			)
		Ability.Form.CONE, Ability.Form.LINE:
			AbilityTelegraph.line(
				scene_root, cast.caster.position, cast.direction,
				ability.length, ability.width, color_dash
			)
		_:
			pass

## Console em vez de HUD: a Fase 1 não tem UI, e a recusa precisa ser visível
## para dar para testar. Vira ícone acinzentado e aviso na tela na Fase 6.
func _report(ability: Ability, result: CastResult) -> void:
	if ability == null or result == null:
		return
	match result.status:
		CastResult.Status.SUCCESS:
			var mine: String = ""
			if _combatant.health.shield > 0.0:
				mine = "  escudo %.0f" % _combatant.health.shield
			if result.targets.is_empty():
				print("[hab] %s errou%s" % [ability.display_name, mine])
			else:
				print("[hab] %s acertou %d alvo(s)%s" % [
					ability.display_name, result.targets.size(), mine
				])
		CastResult.Status.CASTING:
			print("[hab] %s conjurando (%.2fs)" % [ability.display_name, ability.cast_time])
		CastResult.Status.ON_COOLDOWN:
			print("[hab] %s em recarga (%.1fs)" % [ability.display_name, result.cooldown_remaining])
		CastResult.Status.OUT_OF_RANGE:
			print("[hab] %s fora de alcance" % ability.display_name)
		CastResult.Status.NO_TARGET:
			print("[hab] %s não pegou ninguém" % ability.display_name)
		CastResult.Status.CANNOT_CAST:
			print("[hab] %s bloqueada (atordoado ou silenciado)" % ability.display_name)
		CastResult.Status.BUSY:
			print("[hab] %s recusada: já conjurando" % ability.display_name)
		_:
			print("[hab] %s -> %s" % [
				ability.display_name, CastResult.Status.keys()[result.status]
			])
