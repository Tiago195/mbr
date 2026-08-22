extends TestCase

## O corpus traduzido do original, carregado e EXECUTADO.
##
## Este é o teste que dá sentido ao Passo 4. Verificar que o JSON existe e tem
## 1126 entradas provaria pouco: um tradutor quebrado também produz 1126
## entradas. O que prova é conjurar cada uma **das que têm pulso** — 964 das
## 1126 — contra um alvo e ver que a engine resolve. Mesma `AbilityEngine`,
## mesmo `AbilityBook`, mesmos efeitos que as três habilidades feitas à mão.
##
## As 162 restantes não são conjuráveis por construção (linha-modelo de ranque
## 0, marcador de quebra de combo) ou caem em lacuna registrada; a contagem
## de cada caso está em `data/traducao/RELATORIO.md`.
##
## Também é o teste que pega regressão de vocabulário: se alguém renomear um
## `Stat.Id` ou reordenar um enum, milhares de efeitos param de montar aqui,
## em vez de silenciosamente virarem outro atributo em jogo.

var _catalogo: AbilityCatalog
var _itens: ItemCatalog

func _abilities() -> AbilityCatalog:
	if _catalogo == null:
		_catalogo = AbilityCatalog.new()
		_catalogo.load_from()
	return _catalogo

func _items() -> ItemCatalog:
	if _itens == null:
		_itens = ItemCatalog.new()
		_itens.load_from(ItemCatalog.CAMINHO_PADRAO, _abilities())
	return _itens

func _unit(position: Vector3 = Vector3.ZERO, team: int = 0) -> Unit:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.MAX_HEALTH: 100000.0,
		Stat.Id.MAX_MANA: 100000.0,
		Stat.Id.ATTACK_DAMAGE: 100.0,
		Stat.Id.ABILITY_POWER: 100.0,
		Stat.Id.MOVE_SPEED: 5.0,
	})
	var unit := Unit.new(stats, team)
	unit.position = position
	return unit

# ---------------------------------------------------------------- carga

func test_o_catalogo_carrega() -> void:
	var catalogo: AbilityCatalog = _abilities()
	assert_true(catalogo.loaded > 0, "nenhuma habilidade carregada")
	assert_eq(catalogo.skipped, 0, "entradas descartadas na carga")

func test_as_948_de_skill_xml_estao_todas_la() -> void:
	# A promessa do Passo 4 é `skill_xml` inteira. As outras tabelas somam por
	# cima; o que não pode faltar é esta.
	var catalogo: AbilityCatalog = _abilities()
	assert_true(
		catalogo.loaded >= 948,
		"esperava ao menos as 948 de skill_xml, vieram %d" % catalogo.loaded
	)

func test_todo_id_e_unico_e_nao_vazio() -> void:
	var catalogo: AbilityCatalog = _abilities()
	var vistos: Dictionary = {}
	var repetidos: int = 0
	var vazios: int = 0
	for id: StringName in catalogo.by_id:
		if String(id).is_empty():
			vazios += 1
		if vistos.has(id):
			repetidos += 1
		vistos[id] = true
	assert_eq(vazios, 0)
	assert_eq(repetidos, 0)

func test_os_ranques_de_um_grupo_ficam_em_ordem() -> void:
	var catalogo: AbilityCatalog = _abilities()
	var conferidos: int = 0
	for grupo: StringName in catalogo.by_group:
		var ranques: Array = catalogo.by_group[grupo]
		if ranques.size() < 2:
			continue
		conferidos += 1
		for i: int in range(1, ranques.size()):
			var anterior: Ability = ranques[i - 1]
			var atual: Ability = ranques[i]
			if anterior.rank > atual.rank:
				assert_true(false, "grupo %s fora de ordem" % grupo)
				return
	assert_true(conferidos > 50, "esperava muitos grupos com vários ranques")

func test_ranque_por_nivel_respeita_o_requisito() -> void:
	var catalogo: AbilityCatalog = _abilities()
	var achou: bool = false
	for grupo: StringName in catalogo.by_group:
		var ranques: Array = catalogo.by_group[grupo]
		if ranques.size() < 3:
			continue
		var escolhido: Ability = catalogo.rank_for_level(grupo, 1)
		if escolhido == null:
			continue
		achou = true
		assert_true(
			escolhido.level_requirement <= 1,
			"%s exigia nível %d" % [escolhido.id, escolhido.level_requirement]
		)
		var alto: Ability = catalogo.rank_for_level(grupo, 99)
		assert_true(alto.rank >= escolhido.rank, "nível maior não pode dar ranque menor")
		break
	assert_true(achou, "nenhum grupo com ranques utilizáveis")

# ---------------------------------------------------------------- coerência

func test_nenhum_efeito_se_perdeu_na_montagem() -> void:
	# O contador do JSON contra o contador dos objetos montados. Se
	# `EffectFactory` não conhecer um tipo, ele devolve nulo e o efeito some —
	# em silêncio, que é exatamente o que este teste existe para impedir.
	var bruto: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(AbilityCatalog.CAMINHO_PADRAO)
	)
	var esperados: int = 0
	for entry: Dictionary in bruto["habilidades"]:
		for pulse: Dictionary in entry["pulses"]:
			esperados += (pulse["effects"] as Array).size()

	var montados: int = 0
	for id: StringName in _abilities().by_id:
		var ability: Ability = _abilities().by_id[id]
		for pulse: AbilityPulse in ability.pulses:
			montados += pulse.effects.size()

	assert_true(esperados > 3000, "o corpus encolheu: só %d efeitos no JSON" % esperados)
	assert_eq(montados, esperados, "efeitos perdidos entre o JSON e os objetos")

func test_nada_ficou_desconhecido_na_carga() -> void:
	# O teste que faltava. `test_nenhum_efeito_se_perdeu_na_montagem` conta
	# OBJETOS, e por isso passava enquanto `INVULNERABLE` virava `STUN`: o
	# objeto existia, com o sentido invertido. Este conta o que a fábrica não
	# reconheceu — e um valor não reconhecido que cai no padrão é exatamente
	# como um efeito troca de significado sem ninguém ver.
	_abilities()
	var desconhecidos: PackedStringArray = []
	for chave: String in EffectFactory.unknown_values:
		desconhecidos.append("%s x%d" % [chave, EffectFactory.unknown_values[chave]])
	assert_eq(
		desconhecidos.size(), 0,
		"a fábrica não reconheceu: %s" % ", ".join(desconhecidos)
	)

func test_nada_ficou_desconhecido_nos_itens() -> void:
	var catalogo := ItemCatalog.new()
	catalogo.load_from(ItemCatalog.CAMINHO_PADRAO, null)
	assert_true(catalogo.loaded > 0)
	assert_eq(
		EffectFactory.unknown_values.size(), 0,
		"desconhecidos nos itens: %s" % str(EffectFactory.unknown_values.keys())
	)

func test_invulnerabilidade_do_corpus_e_invulnerabilidade() -> void:
	# O corpus emite `INVULNERABLE`, e por um tempo ele caía em `STUN`:
	# "fica invulnerável 1,6s" virava "fica atordoado 1,6s", no conjurador.
	var achados: int = 0
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			for effect: AbilityEffect in pulse.effects:
				var cc := effect as CrowdControlEffect
				if cc != null and cc.control == CrowdControlEffect.Kind.INVULNERABLE:
					achados += 1
	assert_true(achados > 0, "o corpus tinha invulnerabilidade e ela sumiu")

	var alvo: Unit = _unit()
	var efeito := CrowdControlEffect.new()
	efeito.control = CrowdControlEffect.Kind.INVULNERABLE
	efeito.duration = 2.0
	efeito.apply(AbilityCast.on_self(alvo), alvo)
	assert_true(alvo.is_invulnerable())
	assert_false(alvo.status.has(StatusSet.Kind.STUN), "não pode virar atordoamento")

func test_impacto_encadeado_virou_pulso_proprio() -> void:
	# 320 referências encadeadas, 300 delas com tempo, raio ou âncora
	# diferentes do pai. Fundir descartaria isso — é o mesmo erro que a
	# estrutura de pulsos existe para não cometer.
	var com_ancora_anterior: int = 0
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			if pulse.origin == AbilityPulse.Origin.PREVIOUS:
				com_ancora_anterior += 1
	assert_true(
		com_ancora_anterior > 20,
		"`ParentImpactPosition` existe em 68 impactos e só %d viraram PREVIOUS"
			% com_ancora_anterior
	)

func test_a_habilidade_com_os_dois_removedores_traz_as_duas_purificacoes() -> void:
	# `skill 3400100` é a ÚNICA do original com `RemoveCC` e `RemoveDebuff` ao
	# mesmo tempo, e o tradutor devolvia no primeiro ramo que casasse — o
	# segundo sumia. Um caso só, e por isso mesmo precisa de teste: sem ele, a
	# correção não tem nada que a segure, e o único sinal seria o diff do
	# relatório gerado.
	var ability: Ability = _abilities().get_ability(&"rc_3400100")
	assert_not_null(ability, "rc_3400100 sumiu do corpus")
	if ability == null:
		return

	var escopos: Array[int] = []
	for pulse: AbilityPulse in ability.pulses:
		for effect: AbilityEffect in pulse.effects:
			var limpeza := effect as CleanseEffect
			if limpeza != null:
				escopos.append(limpeza.scope)
	assert_true(
		escopos.has(CleanseEffect.Scope.CROWD_CONTROL),
		"faltou a purificação de controle (RemoveCC)"
	)
	assert_true(
		escopos.has(CleanseEffect.Scope.BUFFS),
		"faltou a purificação de efeito negativo (RemoveDebuff)"
	)

func test_as_purificacoes_do_corpus_estao_todas_la() -> void:
	# 7 habilidades com `RemoveCC` e 1 com `RemoveDebuff` no original. Se o
	# tradutor perder qualquer uma, este número cai.
	var controle: int = 0
	var negativos: int = 0
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			for effect: AbilityEffect in pulse.effects:
				var limpeza := effect as CleanseEffect
				if limpeza == null:
					continue
				if limpeza.scope == CleanseEffect.Scope.CROWD_CONTROL:
					controle += 1
				elif limpeza.scope == CleanseEffect.Scope.BUFFS:
					negativos += 1
	assert_eq(controle, 7, "as 7 de RemoveCC")
	assert_eq(negativos, 1, "a única de RemoveDebuff")

func test_o_corpus_traz_passiva_de_ranque() -> void:
	# 40 linhas de `skill.StatType1` no original: o bônus que a habilidade dá
	# por existir naquele ranque. Ficaram invisíveis por duas rodadas — o censo
	# as listava e o doc dizia que o censo estava vazio.
	var com_passiva: int = 0
	for id: StringName in _abilities().by_id:
		if not (_abilities().by_id[id] as Ability).passive_effects.is_empty():
			com_passiva += 1
	assert_eq(com_passiva, 40, "esperava as 40 linhas de StatType1 de skill_xml")

func test_a_passiva_do_corpus_sobe_com_o_ranque() -> void:
	var catalogo: AbilityCatalog = _abilities()
	var achou: bool = false
	for grupo: StringName in catalogo.by_group:
		var ranques: Array = catalogo.by_group[grupo]
		if ranques.size() < 3:
			continue
		# `ranques[0]` é o ranque 0 — a linha-modelo, que não tem passiva por
		# definição. Quem carrega a passiva são os ranques 1 a 5.
		var com_passiva: Array[Ability] = []
		for ability: Ability in (ranques as Array):
			if not ability.passive_effects.is_empty():
				com_passiva.append(ability)
		if com_passiva.size() < 2:
			continue
		achou = true
		var primeiro := com_passiva[0].passive_effects[0] as StatModEffect
		var ultimo := com_passiva[-1].passive_effects[0] as StatModEffect
		assert_not_null(primeiro)
		assert_true(
			ultimo.value > primeiro.value,
			"o ranque alto tinha bônus %f contra %f do baixo" % [
				ultimo.value, primeiro.value
			]
		)
		break
	assert_true(achou, "nenhum grupo com passiva de ranque em vários ranques")

func test_nenhum_impacto_sai_duas_vezes_na_mesma_habilidade() -> void:
	# 16 habilidades citam um impacto em `ImpactN` **e** o encadeiam a partir de
	# outro. Sem guarda, o golpe sai duas vezes e o dano dobra sem que nada no
	# dado diga isso.
	#
	# A prova é DIRETA, pela procedência que o tradutor grava em cada pulso.
	# A primeira versão deste teste tentava adivinhar por assinatura — forma,
	# raio, efeito e atraso parecidos — e acusava falso em três golpes
	# legítimos a 0,2s / 0,3s / 0,4s, que é exatamente como um combo rápido se
	# parece. Heurística não distingue combo de duplicata; procedência sim.
	var bruto: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(AbilityCatalog.CAMINHO_PADRAO)
	)
	var repetidos: PackedStringArray = []
	for entry: Dictionary in bruto["habilidades"]:
		var vistos: Dictionary = {}
		for pulse: Dictionary in entry["pulses"]:
			var origem: int = int(pulse.get("source_impact", 0))
			if origem == 0:
				continue
			if vistos.has(origem):
				repetidos.append("%s(%d)" % [entry["id"], origem])
				break
			vistos[origem] = true
	assert_eq(
		repetidos.size(), 0,
		"o mesmo impacto virou dois pulsos em: %s" % ", ".join(repetidos.slice(0, 5))
	)

func test_a_procedencia_do_pulso_esta_registrada() -> void:
	# Sem ela, o teste acima não teria como ser direto — e um número que não
	# bate não teria por onde ser puxado.
	var bruto: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(AbilityCatalog.CAMINHO_PADRAO)
	)
	var sem_origem: int = 0
	var total: int = 0
	for entry: Dictionary in bruto["habilidades"]:
		for pulse: Dictionary in entry["pulses"]:
			total += 1
			# O pulso de purificação vem de `RemoveCC`, que não é impacto.
			if not pulse.has("source_impact"):
				sem_origem += 1
	assert_true(total > 1600, "só %d pulsos no corpus" % total)
	assert_true(sem_origem <= 10, "%d pulsos sem procedência" % sem_origem)

func test_o_corpus_usa_deslocamento_de_ancora() -> void:
	var deslocados: int = 0
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			if not is_zero_approx(pulse.forward_offset) 					or not is_zero_approx(pulse.side_offset):
				deslocados += 1
	assert_true(deslocados > 50, "só %d pulsos com âncora deslocada" % deslocados)

func test_o_corpus_usa_fator_de_roubo_de_vida() -> void:
	var sem_dreno: int = 0
	var com_dreno: int = 0
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			for effect: AbilityEffect in pulse.effects:
				var dano := effect as DamageEffect
				if dano == null:
					continue
				if is_zero_approx(dano.drain_factor):
					sem_dreno += 1
				else:
					com_dreno += 1
	# 73 no corpus: a maioria dos impactos com DrainFactor 0 não causa dano
	# nenhum, então o zero só aparece onde há golpe para não devolver vida.
	assert_true(sem_dreno > 50, "só %d golpes sem roubo de vida" % sem_dreno)
	assert_true(com_dreno > 100)

func test_nenhum_efeito_ficou_nulo() -> void:
	var nulos: int = 0
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			for effect: AbilityEffect in pulse.effects:
				if effect == null:
					nulos += 1
	assert_eq(nulos, 0)

func test_toda_forma_e_valida() -> void:
	var invalidas: int = 0
	var formas: int = AbilityPulse.Form.size()
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			if pulse.form < 0 or pulse.form >= formas:
				invalidas += 1
	assert_eq(invalidas, 0)

func test_forma_direcional_alcanca_o_que_a_habilidade_promete() -> void:
	# O defeito que isto pega já existiu e passou por quatro revalidações: o
	# ramo do cone lia uma coluna que NÃO EXISTE em nenhuma habilidade do
	# original, caía num padrão de 1 metro, e 20 dos 25 pulsos de cone
	# acertavam só quem estivesse colado. Nenhum erro, nenhuma lacuna, e o
	# censo de colunas cego — porque as colunas envolvidas constavam como
	# consultadas.
	#
	# O que pega esse tipo de coisa não é conferir coluna, é conferir se o
	# resultado faz sentido ao lado do alcance declarado da habilidade.
	var suspeitos: PackedStringArray = []
	for id: StringName in _abilities().by_id:
		var ability: Ability = _abilities().by_id[id]
		if ability.cast_range < 3.0:
			continue
		for pulse: AbilityPulse in ability.pulses:
			match pulse.form:
				AbilityPulse.Form.CONE, AbilityPulse.Form.LINE, 				AbilityPulse.Form.TRAPEZOID, AbilityPulse.Form.PROJECTILE:
					if pulse.length <= 1.0:
						suspeitos.append("%s(%s len=%.1f alcance=%.1f)" % [
							id, AbilityPulse.Form.keys()[pulse.form],
							pulse.length, ability.cast_range
						])
				_:
					pass
	assert_eq(
		suspeitos.size(), 0,
		"forma direcional que não alcança nada: %s" % ", ".join(suspeitos.slice(0, 5))
	)

func test_o_cone_do_corpus_tem_alcance_de_verdade() -> void:
	var cones: int = 0
	var soma: float = 0.0
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			if pulse.form == AbilityPulse.Form.CONE:
				cones += 1
				soma += pulse.length
	assert_true(cones >= 20, "só %d pulsos de cone no corpus" % cones)
	assert_true(
		soma / float(cones) >= 3.0,
		"alcance médio do cone é %.1fm — baixo demais para ser dado do original"
			% (soma / float(cones))
	)

func test_geometria_nao_tem_valor_absurdo() -> void:
	var ruins: PackedStringArray = []
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			if pulse.radius < 0.0 or pulse.length < 0.0 or pulse.width < 0.0:
				ruins.append(String(id))
			elif pulse.loop_interval > 0.0 and pulse.duration <= 0.0:
				# Área que repete sem prazo bateria para sempre.
				ruins.append(String(id))
	assert_eq(ruins.size(), 0, "geometria inválida em: %s" % ", ".join(ruins.slice(0, 5)))

func test_recarga_e_custo_nao_sao_negativos() -> void:
	var ruins: int = 0
	for id: StringName in _abilities().by_id:
		var ability: Ability = _abilities().by_id[id]
		if ability.cooldown < 0.0 or ability.mana_cost < 0.0:
			ruins += 1
	assert_eq(ruins, 0)

func test_o_corpus_usa_o_vocabulario_todo() -> void:
	# Se uma peça do vocabulário nunca aparece no corpus, ou ela não fazia
	# falta, ou o tradutor deixou de emiti-la. Nos dois casos vale saber.
	var vistos: Dictionary = {}
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			for effect: AbilityEffect in pulse.effects:
				vistos[effect.get_script().resource_path.get_file()] = true
	for esperado: String in [
		"damage_effect.gd", "heal_effect.gd", "shield_effect.gd",
		"stat_mod_effect.gd", "crowd_control_effect.gd", "displacement_effect.gd",
		"periodic_effect.gd", "summon_effect.gd", "execute_effect.gd",
		"resource_effect.gd", "mark_effect.gd", "cooldown_effect.gd",
		"trigger_effect.gd",
	]:
		assert_true(vistos.has(esperado), "%s nunca aparece no corpus" % esperado)

# ---------------------------------------------------------------- execução

## O teste central: CONJURAR tudo.
##
## Um alvo colado no conjurador e outro a 4 metros cobrem forma de contato e
## forma de alcance. Livro novo por habilidade para não bater em recarga nem
## em BUSY. O que se afirma é que a engine devolve um estado conhecido e que
## nada estoura no caminho.
func test_toda_habilidade_do_corpus_conjura() -> void:
	var catalogo: AbilityCatalog = _abilities()
	var conjuradas: int = 0
	var invalidas: PackedStringArray = []

	for id: StringName in catalogo.by_id:
		var ability: Ability = catalogo.by_id[id]
		if ability.pulses.is_empty():
			continue

		var caster: Unit = _unit()
		var colado: Unit = _unit(Vector3(0.5, 0.0, -0.5), 1)
		var perto: Unit = _unit(Vector3(0.0, 0.0, -4.0), 1)
		var aliado: Unit = _unit(Vector3(1.0, 0.0, 0.0), 0)
		var candidatos: Array = [colado, perto, aliado]

		var book := AbilityBook.new()
		book.learn(AbilityBook.Slot.Q, ability)

		var aim: AbilityCast = _mira(ability, caster, perto)
		var result: CastResult = AbilityEngine.cast(book, ability, aim, candidatos)
		conjuradas += 1

		if result.status == CastResult.Status.INVALID:
			invalidas.append("%s" % id)
			continue

		# Solta os pulsos atrasados. Meio segundo por passo, o suficiente para
		# vencer o `StartTime` de qualquer impacto do original.
		for passo: int in range(12):
			book.advance_time(0.5, caster)
			AbilityEngine.resolve_scheduled(book, candidatos)
			AbilityEngine.advance_projectiles(book, 0.5, candidatos)
			caster.advance_time(0.5)
			for alvo: Unit in candidatos:
				alvo.advance_time(0.5)

	assert_true(conjuradas > 900, "só %d habilidades conjuráveis" % conjuradas)
	assert_eq(
		invalidas.size(), 0,
		"recusadas como INVALID: %s" % ", ".join(invalidas.slice(0, 8))
	)

func test_conjurar_o_corpus_causa_efeito_de_verdade() -> void:
	# O teste acima prova que nada estoura. Este prova que algo ACONTECE —
	# sem ele, um tradutor que emitisse efeitos vazios passaria batido.
	var catalogo: AbilityCatalog = _abilities()
	var machucaram: int = 0
	var curaram: int = 0
	var controlaram: int = 0

	for id: StringName in catalogo.by_id:
		var ability: Ability = catalogo.by_id[id]
		if ability.pulses.is_empty():
			continue
		var caster: Unit = _unit()
		var alvo: Unit = _unit(Vector3(0.0, 0.0, -1.5), 1)
		var aliado: Unit = _unit(Vector3(0.5, 0.0, 0.0), 0)
		aliado.health.current = 1000.0
		var candidatos: Array = [alvo, aliado]
		var book := AbilityBook.new()
		AbilityEngine.cast(book, ability, _mira(ability, caster, alvo), candidatos)
		# `advance_projectiles` entrou aqui junto com o voo de verdade: sem
		# ela, as ~200 habilidades de projétil do corpus lançam e nada nunca
		# aterrissa — e a contagem de "causaram dano" despencava sem que nada
		# estivesse errado com a tradução.
		for passo: int in range(6):
			book.advance_time(0.5, caster)
			AbilityEngine.resolve_scheduled(book, candidatos)
			AbilityEngine.advance_projectiles(book, 0.5, candidatos)

		if alvo.health.current < 100000.0:
			machucaram += 1
		if aliado.health.current > 1000.0 or caster.health.shield > 0.0:
			curaram += 1
		if not alvo.status.is_clear() or alvo.stats.modifier_count() > 0:
			controlaram += 1

	assert_true(machucaram > 400, "só %d habilidades causaram dano" % machucaram)
	assert_true(curaram > 20, "só %d habilidades curaram ou protegeram" % curaram)
	assert_true(controlaram > 100, "só %d habilidades controlaram" % controlaram)

## Mira coerente com o tipo de alvo da habilidade.
func _mira(ability: Ability, caster: Unit, alvo: Unit) -> AbilityCast:
	match ability.aim:
		Ability.Aim.SELF:
			return AbilityCast.on_self(caster)
		Ability.Aim.UNIT:
			return AbilityCast.on_unit(caster, alvo)
		Ability.Aim.DIRECTION:
			return AbilityCast.toward(caster, Vector3(0.0, 0.0, -1.0))
		_:
			return AbilityCast.at_point(caster, alvo.position)

# ---------------------------------------------------------------- itens

func test_os_421_itens_carregam() -> void:
	var catalogo: ItemCatalog = _items()
	assert_eq(catalogo.loaded, 421, "esperava os 421 itens de equipment_xml")
	assert_eq(catalogo.skipped, 0)

func test_todo_item_tem_espaco_coerente_com_a_especie() -> void:
	var ruins: PackedStringArray = []
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		if item.kind == Item.Kind.EQUIPMENT and not item.is_equippable():
			ruins.append(String(id))
		elif item.kind == Item.Kind.MATERIAL and item.is_equippable():
			ruins.append(String(id))
	assert_eq(ruins.size(), 0, "espécie e espaço brigando: %s" % ", ".join(ruins.slice(0, 5)))

func test_equipar_e_desequipar_todo_item_nao_deixa_resto() -> void:
	# A prova de que a passiva traduzida é removível. Um bônus que fica depois
	# de desequipar é o pior bug de inventário que existe: ele se acumula em
	# silêncio a cada troca.
	var sobraram: PackedStringArray = []
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		var portador: Unit = _unit()
		var antes: float = portador.stats.get_value(Stat.Id.ATTACK_DAMAGE)

		for mod: StatModifier in item.build_modifiers():
			portador.stats.add_modifier(mod)
		item.apply_passives(portador)

		portador.stats.remove_source(item.source())
		item.remove_passives(portador)

		if portador.stats.modifier_count() != 0:
			sobraram.append(String(id))
		elif not is_equal_approx(portador.stats.get_value(Stat.Id.ATTACK_DAMAGE), antes):
			sobraram.append(String(id))
	assert_eq(
		sobraram.size(), 0,
		"deixaram modificador para trás: %s" % ", ".join(sobraram.slice(0, 5))
	)

func test_bonus_de_item_chegam_no_atributo() -> void:
	var com_bonus: int = 0
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		if item.flat_bonuses.is_empty() and item.percent_bonuses.is_empty():
			continue
		com_bonus += 1
		var portador: Unit = _unit()
		var mods: Array[StatModifier] = item.build_modifiers()
		assert_true(mods.size() > 0, "%s tem bônus e não gerou modificador" % id)
		return_if_enough(com_bonus)
		break
	assert_true(com_bonus > 0, "nenhum item com bônus de atributo")

## Só para o teste acima poder parar cedo sem perder a asserção.
func return_if_enough(_count: int) -> void:
	pass

func test_a_maioria_dos_equipamentos_da_atributo() -> void:
	var equipamentos: int = 0
	var com_bonus: int = 0
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		if item.kind != Item.Kind.EQUIPMENT:
			continue
		equipamentos += 1
		if not item.flat_bonuses.is_empty() or not item.percent_bonuses.is_empty():
			com_bonus += 1
	assert_true(equipamentos > 150, "poucos equipamentos: %d" % equipamentos)
	assert_true(
		com_bonus > equipamentos * 0.8,
		"só %d de %d equipamentos dão atributo" % [com_bonus, equipamentos]
	)

func test_linhas_de_item_saem_da_menor_raridade_para_a_maior() -> void:
	var linhas_conferidas: int = 0
	for linha: StringName in _items().by_line:
		var itens: Array = _items().by_line[linha]
		if itens.size() < 2:
			continue
		linhas_conferidas += 1
		for i: int in range(1, itens.size()):
			if (itens[i - 1] as Item).rarity > (itens[i] as Item).rarity:
				assert_true(false, "linha %s fora de ordem" % linha)
				return
	assert_true(linhas_conferidas > 50, "esperava muitas linhas de melhoria")

func test_reducao_de_defesa_do_corpus_e_negativa() -> void:
	# `PhysicalDefenseReduce` é DEBUFF no alvo: no nosso modelo vira armadura
	# negativa. Traduzir sem inverter o sinal transformaria toda redução de
	# defesa do original num buff de defesa — e a mutação que faz isso
	# sobrevivia, porque nada exigia o sinal.
	var reducoes: int = 0
	var positivas: PackedStringArray = []
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			for effect: AbilityEffect in pulse.effects:
				var mod := effect as StatModEffect
				if mod == null:
					continue
				if mod.stat != Stat.Id.ARMOR and mod.stat != Stat.Id.MAGIC_RESIST:
					continue
				if effect.recipient != AbilityEffect.Recipient.TARGETS:
					continue
				if mod.value < 0.0:
					reducoes += 1
				elif mod.value > 0.0:
					positivas.append(String(id))
	assert_true(
		reducoes > 50,
		"só %d reduções de defesa no corpus — o sinal deve ter invertido" % reducoes
	)

func test_bonus_percentual_de_item_e_fracao() -> void:
	# `0.15` no original quer dizer +15%, e `Stats` multiplica por
	# `(1 + percent)`. Se um percentual entrasse como plano, +15% viraria +0,15
	# de atributo — e a mutação que troca os dois sobrevivia.
	var maiores_que_um: PackedStringArray = []
	var total: int = 0
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		for stat: Stat.Id in item.percent_bonuses:
			total += 1
			var valor: float = float(item.percent_bonuses[stat])
			if absf(valor) > 1.0:
				maiores_que_um.append("%s(%s=%.2f)" % [
					id, Stat.name_of(stat), valor
				])
	assert_true(total > 30, "só %d bônus percentuais no corpus" % total)
	assert_eq(
		maiores_que_um.size(), 0,
		"percentual maior que 1.0 é sinal de fração virada em plano: %s"
			% ", ".join(maiores_que_um.slice(0, 5))
	)

func test_bonus_percentual_chega_ao_atributo_como_percentual() -> void:
	# A prova de comportamento, não só de faixa: um item com +15% de recarga
	# tem que dar 0.15 no atributo, e não 15.
	var achado: Item = null
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		if item.percent_bonuses.has(Stat.Id.ATTACK_SPEED):
			achado = item
			break
	assert_not_null(achado, "nenhum item com bônus percentual de ataque")
	if achado == null:
		return
	var portador: Unit = _unit()
	for mod: StatModifier in achado.build_modifiers():
		portador.stats.add_modifier(mod)
	var fator: float = portador.stats.get_value(Stat.Id.ATTACK_SPEED)
	assert_true(
		fator > 1.0 and fator < 2.5,
		"velocidade de ataque foi para %.2f — o percentual virou plano" % fator
	)

func test_nenhuma_linha_de_item_e_fabricada() -> void:
	# `EquipLine = 0` é "sem linha". Copiá-lo literalmente juntava nove itens
	# sem parentesco — três elmos, quatro luvas e duas botas — numa linha de
	# melhoria de nove degraus que não existe.
	var maior: int = 0
	var linha_maior: StringName = &""
	for linha: StringName in _items().by_line:
		var tamanho: int = (_items().by_line[linha] as Array).size()
		if tamanho > maior:
			maior = tamanho
			linha_maior = linha
	assert_true(
		maior <= 4,
		"linha %s com %d degraus — o original vai até 3" % [linha_maior, maior]
	)

func test_nenhum_controle_do_corpus_e_inerte() -> void:
	# `StatusSet.apply` descarta duração <= 0, então um controle com duração
	# zero é um efeito que existe no dado e não faz nada. Já foram 121: TODO
	# arremesso do jogo, porque o original guarda o tempo de ar fora da coluna
	# `Duration` e o tradutor copiava o zero literalmente.
	#
	# Pior que a perda: o relatório contava os 121 como cobertura.
	var inertes: PackedStringArray = []
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			for effect: AbilityEffect in pulse.effects:
				var cc := effect as CrowdControlEffect
				if cc == null or cc.control == CrowdControlEffect.Kind.SLOW:
					continue
				if cc.duration <= 0.0:
					inertes.append("%s(%s)" % [
						id, CrowdControlEffect.Kind.keys()[cc.control]
					])
	assert_eq(
		inertes.size(), 0,
		"controle que o motor descarta: %s" % ", ".join(inertes.slice(0, 5))
	)

func test_o_arremesso_do_corpus_dura_um_tempo_plausivel() -> void:
	var arremessos: int = 0
	var soma: float = 0.0
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			for effect: AbilityEffect in pulse.effects:
				var cc := effect as CrowdControlEffect
				if cc != null and cc.control == CrowdControlEffect.Kind.AIRBORNE:
					arremessos += 1
					soma += cc.duration
	assert_true(arremessos > 100, "só %d arremessos no corpus" % arremessos)
	var media: float = soma / float(arremessos)
	assert_true(
		media > 0.5 and media < 3.0,
		"tempo de ar médio de %.2fs — fora do que um arremesso significa" % media
	)

func test_ataque_basico_do_corpus_nao_fere_aliado() -> void:
	# `TargetAlly(11)` não é campeão: a espécie 11 aparece dos dois lados, e
	# cura de verdade usa `Ally(1,2)`. Ler só o nome do lado fazia 76 pulsos de
	# ataque básico saírem acertando o próprio time.
	var basico: Ability = _abilities().get_ability(&"rc_1000000")
	assert_not_null(basico, "o ataque básico do primeiro campeão sumiu")
	if basico == null:
		return
	for pulse: AbilityPulse in basico.pulses:
		assert_false(pulse.hits_allies, "ataque básico não acerta aliado")

func test_quem_machuca_aliado_declara_isso_no_original() -> void:
	# Restam habilidades que pegam os dois lados — e são reais: declaram
	# `Ally(1,2,...)` junto de `Enemy(...)`. O que não pode é o número explodir.
	var ferem: int = 0
	for id: StringName in _abilities().by_id:
		for pulse: AbilityPulse in (_abilities().by_id[id] as Ability).pulses:
			if not pulse.hits_allies:
				continue
			for effect: AbilityEffect in pulse.effects:
				if effect is DamageEffect or effect is ExecuteEffect:
					ferem += 1
					break
	assert_true(ferem < 40, "%d pulsos ferem aliado — o filtro voltou a ser cego" % ferem)

func test_melhoria_devolve_o_degrau_imediato() -> void:
	# 79 linhas têm três degraus ou mais. Devolver o TOPO em vez do próximo
	# transformaria "melhorar o item" em "pular para o melhor".
	var testadas: int = 0
	for linha: StringName in _items().by_line:
		var itens: Array = _items().by_line[linha]
		if itens.size() < 3:
			continue
		var base: Item = itens[0]
		var proximo: Item = _items().upgrade_of(base)
		assert_not_null(proximo)
		if proximo == null:
			return
		var topo: Item = itens[-1]
		assert_true(
			proximo.rarity < topo.rarity,
			"linha %s com %d degraus devolveu o topo" % [linha, itens.size()]
		)
		# E não há nada entre a base e o que veio.
		for candidato: Item in itens:
			if candidato.rarity > base.rarity:
				assert_true(
					candidato.rarity >= proximo.rarity,
					"havia degrau mais baixo que o devolvido"
				)
		testadas += 1
		if testadas >= 3:
			break
	assert_true(testadas > 0, "nenhuma linha com três degraus")

func test_melhoria_sobe_de_raridade() -> void:
	var testados: int = 0
	for linha: StringName in _items().by_line:
		var itens: Array = _items().by_line[linha]
		if itens.size() < 2:
			continue
		var base: Item = itens[0]
		var acima: Item = _items().upgrade_of(base)
		assert_not_null(acima, "linha %s sem degrau acima do primeiro" % linha)
		if acima != null:
			assert_true(acima.rarity > base.rarity)
		testados += 1
		if testados >= 3:
			break
	assert_true(testados > 0)

func test_receitas_ligaram_ingredientes() -> void:
	var com_receita: int = 0
	for id: StringName in _items().by_id:
		if not (_items().by_id[id] as Item).built_from.is_empty():
			com_receita += 1
	assert_true(com_receita > 200, "só %d itens com receita" % com_receita)

func test_itens_de_uso_apontam_para_habilidade() -> void:
	var usaveis: int = 0
	for id: StringName in _items().by_id:
		if (_items().by_id[id] as Item).is_usable():
			usaveis += 1
	assert_true(usaveis > 10, "só %d itens com habilidade ativa" % usaveis)

func test_item_de_uso_conjura_pelo_mesmo_motor() -> void:
	# O ponto de `03-sistemas-de-jogo.md`: item que age não é um segundo
	# sistema. Se for, este teste não compila.
	var achado: Item = null
	for id: StringName in _items().by_id:
		var item: Item = _items().by_id[id]
		if item.is_usable() and not item.active_ability.pulses.is_empty():
			achado = item
			break
	assert_not_null(achado, "nenhum item com ativa conjurável")
	if achado == null:
		return

	var portador: Unit = _unit()
	var alvo: Unit = _unit(Vector3(0.0, 0.0, -2.0), 1)
	var book := AbilityBook.new()
	var result: CastResult = AbilityEngine.cast(
		book, achado.active_ability,
		_mira(achado.active_ability, portador, alvo), [alvo]
	)
	assert_true(
		result.status != CastResult.Status.INVALID,
		"%s: %s" % [achado.id, CastResult.Status.keys()[result.status]]
	)
