extends TestCase

## Os personagens traduzidos, carregados e ARMADOS.
##
## Mesmo critério do teste do corpus: provar que o JSON tem 384 entradas não
## prova nada — um tradutor quebrado também produz 384. O que prova é montar
## o `Unit` de cada campeão, abastecer o `AbilityBook` dele e ver quatro
## habilidades com pulso saindo do outro lado.
##
## É também onde as duas traduções se encontram. O perfil cita GRUPOS de
## habilidade; se um grupo citado não existir no `AbilityCatalog`, o campeão
## nasce com um espaço vazio e nada acusa. Aqui acusa.

var _atores: ActorCatalog
var _habilidades: AbilityCatalog

func _actors() -> ActorCatalog:
	if _atores == null:
		_atores = ActorCatalog.new()
		_atores.load_from()
	return _atores

func _abilities() -> AbilityCatalog:
	if _habilidades == null:
		_habilidades = AbilityCatalog.new()
		_habilidades.load_from()
	return _habilidades

# ---------------------------------------------------------------- carga

func test_o_catalogo_carrega() -> void:
	var catalogo: ActorCatalog = _actors()
	assert_true(catalogo.loaded > 0, "nenhum ator carregado")
	assert_eq(catalogo.skipped, 0, "entradas descartadas na carga")

func test_nenhum_nome_de_atributo_ficou_desconhecido() -> void:
	# `ActorCatalog._stats` converte nome de atributo em `Stat.Id`. Um nome que
	# não existe cairia fora em silêncio e o campeão herdaria o padrão da
	# classe — 100 de vida em vez de 2000, sem erro nenhum.
	_actors()
	assert_eq(
		EffectFactory.unknown_values.size(), 0,
		"valores desconhecidos na carga dos atores: %s"
			% str(EffectFactory.unknown_values)
	)

func test_todo_id_e_unico_e_nao_vazio() -> void:
	var catalogo: ActorCatalog = _actors()
	var vazios: int = 0
	for id: StringName in catalogo.by_id:
		if String(id).is_empty():
			vazios += 1
	assert_eq(vazios, 0, "ator com id vazio")
	# `by_id` é dicionário: id repetido teria sobrescrito silenciosamente, e a
	# contagem denunciaria.
	assert_eq(
		catalogo.by_id.size(), catalogo.loaded,
		"ids repetidos sobrescreveram perfis"
	)

# ---------------------------------------------------------------- campeões

func test_os_campeoes_do_original_estao_la() -> void:
	var campeoes: Array[ActorProfile] = _actors().champions()
	assert_true(
		campeoes.size() >= 30,
		"esperava ao menos 30 campeões com kit, vieram %d" % campeoes.size()
	)

func test_todo_grupo_citado_existe_no_catalogo_de_habilidades() -> void:
	# O elo entre as duas traduções. Um grupo órfão daria um espaço vazio no
	# livro do campeão, e um espaço vazio é indistinguível de uma habilidade
	# que o jogador ainda não aprendeu.
	var habilidades: AbilityCatalog = _abilities()
	var orfaos: Array[String] = []
	for profile: ActorProfile in _actors().by_id.values():
		for grupo: StringName in profile.all_groups():
			if not habilidades.by_group.has(grupo):
				orfaos.append("%s -> %s" % [profile.id, grupo])
	assert_eq(orfaos.size(), 0, "grupos órfãos: %s" % str(orfaos.slice(0, 5)))

func test_a_maioria_dos_campeoes_arma_quatro_espacos() -> void:
	var habilidades: AbilityCatalog = _abilities()
	var completos: int = 0
	for profile: ActorProfile in _actors().champions():
		var unit: Unit = profile.build_unit(9)
		var book := AbilityBook.new()
		if profile.equip_book(book, habilidades, unit, 9) >= 4:
			completos += 1
	# 28 dos 33. Os cinco que faltam estão nomeados no `RELATORIO.md` e o teste
	# seguinte prova POR QUE cada um falta — o número solto aqui só serviria
	# para acusar regressão, e sem a causa não daria para distinguir "a
	# tradução piorou" de "o original é assim".
	assert_true(
		completos >= 28,
		"só %d campeões armaram Q/W/E/R" % completos
	)

func test_espaco_vazio_e_sempre_habilidade_sem_traducao() -> void:
	# O teste que importa. Um espaço vazio tem duas causas possíveis e elas
	# são muito diferentes: ou o grupo citado NÃO EXISTE — elo quebrado entre
	# as duas traduções, defeito nosso — ou ele existe e nenhum ranque dele
	# saiu com pulso, que é uma lacuna já registrada do original.
	#
	# Sem separar as duas, "28 de 33" seria um número que tanto pode ser o
	# dado quanto um bug.
	var habilidades: AbilityCatalog = _abilities()
	var inexplicados: Array[String] = []
	for profile: ActorProfile in _actors().champions():
		var citados: Array[StringName] = profile.ability_groups.duplicate()
		if not profile.ultimate_group.is_empty():
			citados.append(profile.ultimate_group)
		for grupo: StringName in citados:
			if ActorProfile.ability_for(habilidades, grupo, 9) != null:
				continue
			var ranques: Variant = habilidades.by_group.get(grupo)
			if not ranques is Array or (ranques as Array).is_empty():
				inexplicados.append("%s: grupo %s não existe" % [profile.id, grupo])
				continue
			for ability: Ability in (ranques as Array):
				if ability.has_pulses():
					inexplicados.append(
						"%s: grupo %s tinha ranque com pulso e não armou"
							% [profile.id, grupo]
					)
					break
	assert_eq(
		inexplicados.size(), 0,
		"espaços vazios sem explicação: %s" % str(inexplicados.slice(0, 5))
	)

func test_toda_habilidade_armada_tem_pulso() -> void:
	# A armadilha específica desta tradução: a tabela de atores aponta para a
	# LINHA-MODELO do grupo (`Rank 0`), que não referencia impacto nenhum.
	# Guardar aquele id daria um Q que aperta, gasta mana e não faz nada — sem
	# uma linha de erro. É por isso que o perfil guarda o grupo, não o id.
	var habilidades: AbilityCatalog = _abilities()
	var vazias: Array[String] = []
	for profile: ActorProfile in _actors().champions():
		var unit: Unit = profile.build_unit(9)
		var book := AbilityBook.new()
		profile.equip_book(book, habilidades, unit, 9)
		for ability: Ability in book.known_abilities():
			if not ability.has_pulses():
				vazias.append("%s: %s" % [profile.id, ability.id])
	assert_eq(
		vazias.size(), 0,
		"habilidades armadas sem pulso: %s" % str(vazias.slice(0, 5))
	)

func test_o_ranque_sobe_com_o_nivel() -> void:
	# `LevelRequirement` do original: ranque 1 no nível 1, ranque 5 no 9.
	var habilidades: AbilityCatalog = _abilities()
	var leo: ActorProfile = _actors().get_profile(&"leo")
	assert_not_null(leo, "o Leo sumiu do catálogo")
	if leo == null:
		return
	var grupo: StringName = leo.ability_groups[0]
	var nivel_1: Ability = ActorProfile.ability_for(habilidades, grupo, 1)
	var nivel_9: Ability = ActorProfile.ability_for(habilidades, grupo, 9)
	assert_not_null(nivel_1, "sem ranque no nível 1")
	assert_not_null(nivel_9, "sem ranque no nível 9")
	if nivel_1 == null or nivel_9 == null:
		return
	assert_true(
		nivel_9.rank > nivel_1.rank,
		"o ranque não subiu: %d -> %d" % [nivel_1.rank, nivel_9.rank]
	)

# ---------------------------------------------------------------- atributos

func test_o_campeao_nasce_com_os_atributos_do_original() -> void:
	var leo: ActorProfile = _actors().get_profile(&"leo")
	assert_not_null(leo, "o Leo sumiu do catálogo")
	if leo == null:
		return
	var unit: Unit = leo.build_unit(1)
	assert_almost_eq(unit.stats.get_value(Stat.Id.MAX_HEALTH), 2000.0)
	assert_almost_eq(unit.stats.get_value(Stat.Id.ATTACK_DAMAGE), 120.0)
	assert_almost_eq(unit.stats.get_value(Stat.Id.MAX_MANA), 700.0)
	assert_eq(unit.nature, Unit.Nature.CHAMPION)
	# `Health` nasce cheio a partir do `Stats` — 2000, não os 100 do padrão.
	assert_almost_eq(unit.health.current, 2000.0)

func test_o_alcance_do_ataque_basico_separa_atirador_de_corpo_a_corpo() -> void:
	# Nem alcance nem cadência estão em `StatType_N`: os dois vêm da habilidade
	# de ataque básico (`AI_SkillRange` e `CoolTime`). Sem lê-los de lá, todo
	# campeão cairia no padrão de `Stat.DEFAULTS` e a atiradora do original
	# viraria corpo a corpo — sem erro em lugar nenhum.
	var catalogo: ActorCatalog = _actors()
	var leo: ActorProfile = catalogo.get_profile(&"leo")
	var bella: ActorProfile = catalogo.get_profile(&"bella")
	assert_not_null(leo)
	assert_not_null(bella)
	if leo == null or bella == null:
		return
	assert_true(
		bella.stat_at(Stat.Id.ATTACK_RANGE, 1)
			> leo.stat_at(Stat.Id.ATTACK_RANGE, 1) * 2.0,
		"a atiradora não alcança mais longe que o guerreiro: %.1f vs %.1f" % [
			bella.stat_at(Stat.Id.ATTACK_RANGE, 1),
			leo.stat_at(Stat.Id.ATTACK_RANGE, 1),
		]
	)

func test_todo_campeao_tem_alcance_e_cadencia_proprios() -> void:
	var faltando: Array[String] = []
	for profile: ActorProfile in _actors().champions():
		if not profile.base_stats.has(Stat.Id.ATTACK_RANGE):
			faltando.append("%s: alcance" % profile.id)
		if not profile.base_stats.has(Stat.Id.ATTACK_SPEED):
			faltando.append("%s: cadência" % profile.id)
	assert_eq(
		faltando.size(), 0,
		"campeões no padrão da classe: %s" % str(faltando.slice(0, 5))
	)

func test_o_crescimento_por_nivel_e_aplicado() -> void:
	var leo: ActorProfile = _actors().get_profile(&"leo")
	if leo == null:
		assert_true(false, "o Leo sumiu do catálogo")
		return
	var vida_1: float = leo.stat_at(Stat.Id.MAX_HEALTH, 1)
	var vida_10: float = leo.stat_at(Stat.Id.MAX_HEALTH, 10)
	var por_nivel: float = leo.growth.get(Stat.Id.MAX_HEALTH, 0.0)
	assert_true(por_nivel > 0.0, "o Leo não cresce em vida")
	assert_almost_eq(vida_10, vida_1 + por_nivel * 9.0)

func test_abaixo_do_nivel_base_o_atributo_nao_encolhe() -> void:
	# Mob do original nasce num nível maior que 1. Interpolar para baixo daria
	# um lobo de nível 5 com vida negativa ao ser pedido no nível 1.
	var perfil := ActorProfile.new()
	perfil.base_level = 5
	perfil.base_stats = {Stat.Id.MAX_HEALTH: 1000.0}
	perfil.growth = {Stat.Id.MAX_HEALTH: 100.0}
	assert_almost_eq(perfil.stat_at(Stat.Id.MAX_HEALTH, 1), 1000.0)
	assert_almost_eq(perfil.stat_at(Stat.Id.MAX_HEALTH, 5), 1000.0)
	assert_almost_eq(perfil.stat_at(Stat.Id.MAX_HEALTH, 7), 1200.0)

# ---------------------------------------------------------------- suprema

func test_a_suprema_ganha_recarga_no_lugar_da_carga() -> void:
	# 31 das 32 supremas do original têm `CoolTime = 0` porque enchem batendo.
	# Copiar o zero daria uma suprema disparável a cada quadro.
	var habilidades: AbilityCatalog = _abilities()
	var sem_recarga: Array[String] = []
	for profile: ActorProfile in _actors().champions():
		if profile.ultimate_group.is_empty():
			continue
		var suprema: Ability = profile.ultimate_for(habilidades, 9)
		if suprema != null and suprema.cooldown <= 0.0:
			sem_recarga.append(String(profile.id))
	assert_eq(
		sem_recarga.size(), 0,
		"supremas sem recarga nenhuma: %s" % str(sem_recarga.slice(0, 5))
	)

func test_mexer_na_suprema_de_um_nao_mexe_na_do_catalogo() -> void:
	# `AbilityCatalog` entrega a MESMA instância a todo mundo. Escrever a
	# recarga nela mudaria a suprema de todos os campeões do grupo — e de
	# qualquer teste que rodasse depois.
	# Catálogo PRÓPRIO, não o compartilhado da suíte. Com o compartilhado o
	# teste passava mesmo com o defeito: um teste anterior já havia chamado
	# `ultimate_for` para todo campeão, então a recarga do catálogo já estava
	# alterada quando este teste lia o "antes". Um teste de mutação foi quem
	# mostrou isso — a suíte estava verde com a cópia removida.
	var habilidades := AbilityCatalog.new()
	habilidades.load_from()
	var leo: ActorProfile = _actors().get_profile(&"leo")
	if leo == null:
		assert_true(false, "o Leo sumiu do catálogo")
		return
	var original: Ability = habilidades.rank_for_level(leo.ultimate_group, 9)
	assert_not_null(original, "a suprema do Leo sumiu")
	if original == null:
		return
	var antes: float = original.cooldown
	var minha: Ability = leo.ultimate_for(habilidades, 9)
	assert_true(minha.cooldown > 0.0, "a cópia saiu sem recarga")
	assert_almost_eq(
		original.cooldown, antes,
		"a suprema do catálogo foi alterada"
	)

# ---------------------------------------------------------------- passiva

func test_a_passiva_do_campeao_carimba_a_origem() -> void:
	# Sem carimbo, trocar de campeão deixa o bônus do anterior colado para
	# sempre: `remove_source` procura por uma etiqueta que ninguém escreveu.
	var com_passiva: ActorProfile = null
	for profile: ActorProfile in _actors().champions():
		if not profile.passive_effects.is_empty():
			com_passiva = profile
			break
	assert_not_null(com_passiva, "nenhum campeão tem passiva")
	if com_passiva == null:
		return
	var esperado: String = "actor:%s" % com_passiva.id
	var errados: int = 0
	for effect: AbilityEffect in com_passiva.passive_effects:
		if &"source_tag" in effect and String(effect.get(&"source_tag")) != esperado:
			errados += 1
	assert_eq(errados, 0, "efeito de passiva sem a etiqueta `%s`" % esperado)

func test_a_passiva_sai_quando_o_campeao_e_trocado() -> void:
	var perfil := ActorProfile.new()
	perfil.id = &"teste"
	var bonus := StatModEffect.new()
	bonus.recipient = AbilityEffect.Recipient.CASTER
	bonus.stat = Stat.Id.ATTACK_DAMAGE
	bonus.kind = StatModifier.Kind.FLAT
	bonus.value = 50.0
	bonus.duration = -1.0
	perfil.passive_effects = [bonus]
	perfil.stamp_passives()

	var stats := Stats.new()
	stats.set_bases({Stat.Id.ATTACK_DAMAGE: 100.0})
	var unit := Unit.new(stats, 0)

	perfil.apply_passives(unit)
	assert_almost_eq(unit.stats.get_value(Stat.Id.ATTACK_DAMAGE), 150.0)
	perfil.remove_passives(unit)
	assert_almost_eq(unit.stats.get_value(Stat.Id.ATTACK_DAMAGE), 100.0)

# ---------------------------------------------------------------- natureza

func test_a_natureza_separa_campeao_de_bau() -> void:
	var catalogo: ActorCatalog = _actors()
	var naturezas: Dictionary = {}
	for profile: ActorProfile in catalogo.by_id.values():
		naturezas[profile.nature] = int(naturezas.get(profile.nature, 0)) + 1
	assert_true(
		int(naturezas.get(Unit.Nature.CHAMPION, 0)) > 0, "nenhum campeão"
	)
	assert_true(
		int(naturezas.get(Unit.Nature.MONSTER, 0)) > 0, "nenhum mob"
	)
	assert_true(
		int(naturezas.get(Unit.Nature.STRUCTURE, 0)) > 0, "nenhuma estrutura"
	)
	# Só campeão conta como abate. Um baú que contasse encerraria a partida.
	for profile: ActorProfile in catalogo.champions():
		assert_eq(profile.nature, Unit.Nature.CHAMPION)

func test_o_campeao_luta_mesmo_sem_a_coluna_dizer() -> void:
	# `AbleCombat` está ausente em todo `Player`. O padrão literal (`false`)
	# faria os 100 personagens jogáveis do original nascerem incapazes.
	for profile: ActorProfile in _actors().champions():
		assert_true(profile.able_combat, "%s não luta" % profile.id)
