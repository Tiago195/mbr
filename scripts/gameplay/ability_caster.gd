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

## Emitido a cada conjuração RESOLVIDA: a instantânea, a que tinha tempo de
## conjuração, e cada golpe atrasado que sai depois.
##
## É a única forma de saber o que aconteceu sem reimplementar o tique. HUD, log
## de combate e som vão pendurar aqui; hoje quem usa é
## `tools/sondar_campeoes.gd`, para conferir que cada golpe virou marca na tela
## no lugar certo — uma conjuração com tempo resolve DENTRO do tique, e sem
## este sinal ela não tinha como dizer o que saiu.
signal resolved(result: CastResult)

## Habilidades por slot. Arraste os `.tres` de `data/abilities/` no Inspector.
##
## São o kit PADRÃO. Um `ChampionSelector` irmão substitui os quatro espaços
## pelo kit de um campeão do original — e quando não houver seletor nenhum,
## estas continuam valendo. As duas fontes passam pelo mesmo `AbilityBook`.
@export var ability_q: Ability
@export var ability_w: Ability
@export var ability_e: Ability
@export var ability_r: Ability

@export_group("Telegrafia")
@export var color_area: Color = Color(0.95, 0.55, 0.15)
@export var color_line: Color = Color(0.45, 0.70, 1.0)
@export var color_dash: Color = Color(0.65, 0.95, 0.55)

var book: AbilityBook

var _combatant: Combatant


## Maior id de projétil que já ganhou esfera na tela.
##
## É assim que a camada visual descobre o que é novo sem a engine avisar: todo
## caminho que lança — conjuração direta, conjuração com tempo, pulso atrasado
## — deixa o projétil na mesma lista, e um contador crescente basta.
var _last_drawn_shot: int = 0

func _ready() -> void:
	ensure_ready()

## Monta o livro se ainda não existir.
##
## Público e idempotente pelo mesmo motivo de `Combatant.ensure_ready()`: o
## `ChampionSelector` precisa do livro dentro do `_ready()` dele, e a ordem em
## que a Godot chama `_ready()` entre irmãos depende da ordem na cena.
## Depender disso é receita para um bug que só aparece quando alguém arrasta
## um nó no editor.
func ensure_ready() -> void:
	if book != null:
		return
	_combatant = Combatant.of(get_parent())
	if _combatant == null:
		push_warning("AbilityCaster sem Combatant irmão.")
		return
	_combatant.ensure_ready()

	book = AbilityBook.new()
	var owner_unit: Unit = _combatant.unit
	book.learn(AbilityBook.Slot.Q, ability_q, owner_unit)
	book.learn(AbilityBook.Slot.W, ability_w, owner_unit)
	book.learn(AbilityBook.Slot.E, ability_e, owner_unit)
	book.learn(AbilityBook.Slot.R, ability_r, owner_unit)

## Troca os quatro espaços pelo kit de um campeão do original.
##
## Devolve quantos espaços foram preenchidos. Esquecer vem de graça: o `learn`
## do `AbilityBook` já desfaz a passiva de ranque da habilidade anterior, que é
## o que impede o bônus de dois campeões se somar ao trocar.
func adopt_kit(profile: ActorProfile, catalog: AbilityCatalog, level: int) -> int:
	ensure_ready()
	if book == null or profile == null:
		return 0
	# A recarga é de quem tinha o livro, não de quem tem agora. Sem limpar,
	# trocar de campeão herdaria a recarga do anterior num espaço que agora
	# tem outra habilidade.
	book.clear_cooldowns()
	book.clear_scheduled()
	return profile.equip_book(book, catalog, _combatant.unit, level)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ability_q"):
		_try_cast(AbilityBook.Slot.Q)
	elif event.is_action_pressed(&"ability_w"):
		_try_cast(AbilityBook.Slot.W)
	elif event.is_action_pressed(&"ability_e"):
		_try_cast(AbilityBook.Slot.E)
	elif event.is_action_pressed(&"ability_r"):
		_try_cast(AbilityBook.Slot.R)

func _physics_process(delta: float) -> void:
	tick(delta)

## Um tique de gameplay: recargas, conjuração em curso, golpes atrasados e
## voo de projétil — cada um com o desenho que lhe corresponde.
##
## Separado de `_physics_process` para `tools/sondar_campeoes.gd` poder
## exercitar ESTE caminho em vez de reimplementá-lo. A sonda que chamava a
## engine direto não passava por `_draw_pulse`, e por isso não notava um
## golpe atrasado que parasse de aparecer na tela.
func tick(delta: float) -> void:
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
			draw_result(result)
			resolved.emit(result)

	# Pulsos atrasados. Uma habilidade de golpe único nunca marca nada e isto
	# custa uma comparação — mas sem a chamada, o segundo golpe de qualquer
	# habilidade traduzida do original simplesmente nunca sairia.
	for late: CastResult in AbilityEngine.resolve_scheduled(
			book, Combatant.all_units(get_tree())
	):
		if late.ability != null and not late.targets.is_empty():
			print("[hab] %s (golpe seguinte) acertou %d alvo(s)" % [
				late.ability.display_name, late.targets.size()
			])
		# O golpe atrasado é desenhado AGORA, quando sai, e não na
		# conjuração. Anunciar todos de uma vez entregaria ao adversário
		# onde o segundo cai — que é o que se aprende jogando contra.
		_draw_pulse(late)
		resolved.emit(late)

	# A esfera nasce ANTES do voo, e a ordem é o conserto de um defeito real:
	# um projétil rápido que acerta dentro do próprio tique em que nasce era
	# removido da lista antes de alguém desenhá-lo, e ficava invisível. Eram
	# justamente os de curto alcance e alta velocidade — os que mais parecem
	# "não fez nada".
	_draw_new_projectiles()

	# O voo. Sem esta chamada, o que sai do arco nunca chega.
	for hit: CastResult in AbilityEngine.advance_projectiles(
			book, delta, Combatant.all_units(get_tree())
	):
		if hit.ability != null:
			print("[hab] %s ACERTOU %d alvo(s)" % [
				hit.ability.display_name, hit.targets.size()
			])
		# O impacto de projétil também anuncia. Ele não carrega pulso nem
		# âncora — quem desenha projétil é a esfera que o segue —, mas carrega
		# a habilidade e quem levou, que é o que um log de combate precisa. Sem
		# esta emissão o sinal perderia TODO acerto de projétil, e o texto dele
		# promete ser a única forma de saber o que aconteceu.
		resolved.emit(hit)

# ---------------------------------------------------------------- conjuração

func _try_cast(slot: AbilityBook.Slot) -> void:
	if book == null:
		return
	var ability: Ability = book.ability_in(slot)
	if ability == null:
		print("[hab] %s vazio" % AbilityBook.Slot.keys()[slot])
		return

	var cast: AbilityCast = _aim(ability)
	if cast == null:
		return

	var result: CastResult = AbilityEngine.cast(
		book, ability, cast, Combatant.all_units(get_tree())
	)
	_report(ability, result)

	# A telegrafia da conjuração com tempo sai no início, não no fim: é ela que
	# avisa o adversário que algo vem vindo, e avisar depois do impacto não
	# serve para nada.
	if result.succeeded():
		draw_result(result)
		resolved.emit(result)
	elif result.started():
		# Ainda não há pulso resolvido: o efeito não saiu. O aviso é da
		# habilidade toda, e vale o pulso principal.
		draw_warning(ability, cast)

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

## Desenha TODOS os pulsos que saíram nesta conjuração.
##
## Antes desenhava só `primary_pulse()`. Dos **127 espaços de campeão** do
## original, **79 têm vários golpes** — e do segundo em diante nada aparecia na
## tela. A habilidade funcionava e parecia quebrada, que foi o relato do
## usuário ao testar os campeões.
##
## O que NÃO mudou: golpe atrasado é desenhado quando SAI, não na conjuração.
##
## Pública porque `tools/sondar_campeoes.gd` conta as marcas que aparecem na
## cena — é o único jeito automático de provar que os golpes seguintes
## deixaram de ser invisíveis, já que a suíte de `tests/` não vê nó.
func draw_result(result: CastResult) -> void:
	for part: CastResult in result.parts:
		_draw_pulse(part)

## Um pulso, na âncora dele, em cada direção do leque.
##
## O leque é desenhado inteiro: três flechas viajam de verdade e cada uma
## acerta a sua, então mostrar só a do meio esconderia duas das três.
func _draw_pulse(part: CastResult) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null or part == null or part.pulse == null:
		return
	var pulse: AbilityPulse = part.pulse
	# Projétil não entra aqui: quem o desenha é `_draw_new_projectiles()`, que
	# segue o objeto de verdade. Desenhar na conjuração era o que permitia a
	# esfera e o dano discordarem.
	if pulse.form == AbilityPulse.Form.PROJECTILE:
		return

	# Área que persiste fica na tela enquanto durar.
	#
	# Medido: HOJE isto nunca dispara. Dos **1687 pulsos** do corpus, só
	# **5 declaram duração**, e valem 0,1s — abaixo dos 0,45s padrão da marca.
	# Fica porque é a regra certa e uma habilidade nossa pode declarar área
	# longa; o que não dá é dizer que está coberto por teste, porque não há
	# dado que o exercite.
	var vida: float = maxf(pulse.duration, 0.0)
	# Medido no corpus: dos **6 pulsos com leque**, **0 não são projétil** — e
	# projétil não passa por aqui. Então hoje este laço roda uma vez sempre, e
	# fica porque um `.tres` feito à mão pode declarar um cone em leque e o
	# custo de estar certo é uma iteração. O que NÃO dá para dizer é que ele
	# está coberto por teste: não há dado que o exercite.
	for direction: Vector3 in pulse.spread_directions(part.direction):
		var marca: AbilityTelegraph = _draw_form(
			scene_root, pulse, part.anchor, direction
		)
		if marca != null and vida > marca.lifetime:
			marca.lifetime = vida

func _draw_form(
		scene_root: Node, pulse: AbilityPulse, anchor: Vector3, direction: Vector3
) -> AbilityTelegraph:
	match pulse.form:
		AbilityPulse.Form.CIRCLE:
			return AbilityTelegraph.circle(
				scene_root, anchor, pulse.radius, color_area
			)
		AbilityPulse.Form.CONE:
			return AbilityTelegraph.cone(
				scene_root, anchor, direction,
				pulse.length, pulse.cone_angle, color_area
			)
		AbilityPulse.Form.TRAPEZOID:
			return AbilityTelegraph.trapezoid(
				scene_root, anchor, direction,
				pulse.near_distance, pulse.near_width,
				pulse.length, pulse.far_width, color_area
			)
		AbilityPulse.Form.LINE:
			return AbilityTelegraph.line(
				scene_root, anchor, direction,
				pulse.length, pulse.width, color_dash
			)
		_:
			# SINGLE não tem área: o alvo foi escolhido a dedo, e o número de
			# dano flutuante é o retorno dele.
			return null

## Aviso do que vem vindo, durante uma conjuração com tempo.
##
## Aqui ainda não há pulso resolvido — nada saiu. Vale o pulso principal, que é
## o que o adversário precisa ver para reagir.
##
## O aviso dura o TEMPO DE CONJURAÇÃO, e não os 0,45s padrão da marca. São
## **54 habilidades com conjuração longa** no corpus — acima dos 0,45s, e até 5
## segundos: o aviso sumia no meio, e quem estava dentro da área deixava de ver
## o motivo para sair dela.
## Devolve a marca criada — a sonda confere a vida dela contra `cast_time`.
func draw_warning(ability: Ability, cast: AbilityCast) -> AbilityTelegraph:
	var scene_root: Node = get_tree().current_scene
	var pulse: AbilityPulse = ability.primary_pulse()
	if scene_root == null or cast == null or pulse == null:
		return null
	var marca: AbilityTelegraph = _draw_form(
		scene_root, pulse, pulse.anchor_for(cast, cast.point), cast.direction
	)
	if marca != null and ability.cast_time > marca.lifetime:
		marca.lifetime = ability.cast_time
	return marca

## Põe uma esfera em cada projétil que entrou no ar desde o último quadro.
##
## A esfera SEGUE o projétil de `core/` em vez de fazer o próprio caminho. É a
## diferença entre mostrar o que aconteceu e mostrar algo parecido: enquanto
## eram duas viagens independentes, dava para ver a esfera passar longe de um
## alvo que tinha levado dano.
func _draw_new_projectiles() -> void:
	if book.projectiles.is_empty():
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	for shot: ProjectileSet.Projectile in book.projectiles.flying():
		if shot.id <= _last_drawn_shot:
			continue
		_last_drawn_shot = shot.id
		AbilityTelegraph.follow(scene_root, shot, color_line)

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
			if result.in_flight():
				# "Errou" seria mentira: o tiro ainda está no ar. O resultado
				# dele sai por `advance_projectiles`, quando encontrar alguém.
				print("[hab] %s lançou %d projétil(is)%s" % [
					ability.display_name, result.launched, mine
				])
			elif result.targets.is_empty():
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
		CastResult.Status.NO_RESOURCE:
			print("[hab] %s sem mana (custa %.0f)" % [
				ability.display_name, ability.mana_cost
			])
		CastResult.Status.NO_CHARGE:
			# Recusa própria, e não "em recarga": o que falta é AGIR, não
			# esperar. Dizer "em recarga" mandaria o jogador parar justamente
			# quando ele deveria bater.
			print("[hab] %s sem carga (faltam %.0f — bata ou conjure)" % [
				ability.display_name, result.charge_missing
			])
		_:
			print("[hab] %s -> %s" % [
				ability.display_name, CastResult.Status.keys()[result.status]
			])
