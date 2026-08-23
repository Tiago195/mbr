extends TestCase

## A cadência do ataque básico, e a habilidade que a zera.
##
## `ResetAttackCoolTime` no original: conjurar solta o próximo ataque básico na
## hora, em vez de esperar a velocidade de ataque. É o que dá ritmo ao corpo a
## corpo — encaixar a habilidade entre dois golpes é a jogada, e sem isso o
## kit vira uma lista de botões que se aperta enquanto se espera.
##
## Duas coisas são testadas aqui, e a segunda é a que importa:
##
## 1. Que a cadência EXISTE em `core/`. Ela morava num `float` de `player.gd`,
##    fora do alcance de `AbilityEngine` — que é estática, roda no servidor
##    headless e não conhece nó.
## 2. Que ela só é zerada por quem tem o direito. Uma conjuração RECUSADA não
##    pode zerar nada: seria um reset de graça, sem gastar recarga nem mana.

const VELOCIDADE: float = 2.0
## 1 / 2.0 ataques por segundo.
const CADENCIA: float = 0.5

func _unit(equipe: int = 0) -> Unit:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.MAX_HEALTH: 1000.0,
		Stat.Id.ATTACK_DAMAGE: 50.0,
		Stat.Id.ATTACK_SPEED: VELOCIDADE,
	})
	return Unit.new(stats, equipe)

## Uma habilidade instantânea que cura o conjurador — o conteúdo não importa,
## o que importa é ela sair.
func _habilidade(zera: bool, recarga: float = 0.0, mana: float = 0.0) -> Ability:
	var ability := Ability.new()
	ability.id = &"teste"
	ability.aim = Ability.Aim.SELF
	ability.cooldown = recarga
	ability.mana_cost = mana
	ability.resets_attack_cooldown = zera
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 3.0
	pulse.hits_self = true
	var cura := HealEffect.new()
	cura.recipient = AbilityEffect.Recipient.CASTER
	cura.base_heal = 1.0
	pulse.effects = [cura]
	return ability

# ------------------------------------------------------------- a cadência

func test_a_cadencia_nasce_vencida() -> void:
	# Quem entra em combate bate no primeiro tique, não espera meio segundo.
	var unit: Unit = _unit()
	assert_true(unit.attack_is_ready())
	assert_almost_eq(unit.attack_cooldown, 0.0)

func test_atacar_gasta_a_cadencia() -> void:
	var atacante: Unit = _unit()
	var alvo: Unit = _unit(1)
	atacante.basic_attack(alvo)
	assert_false(atacante.attack_is_ready(), "bateu duas vezes no mesmo tique")
	assert_almost_eq(atacante.attack_cooldown, CADENCIA)

func test_a_cadencia_sai_da_velocidade_de_ataque() -> void:
	# Não é uma constante: velocidade de ataque é atributo, e item e buff
	# mexem nele. Sem esta ligação, `attack_speed` não faria nada visível.
	var atacante: Unit = _unit()
	var alvo: Unit = _unit(1)
	atacante.stats.set_base(Stat.Id.ATTACK_SPEED, 4.0)
	atacante.basic_attack(alvo)
	assert_almost_eq(atacante.attack_cooldown, 0.25)

func test_a_cadencia_vence_com_o_tempo() -> void:
	var atacante: Unit = _unit()
	var alvo: Unit = _unit(1)
	atacante.basic_attack(alvo)

	atacante.advance_time(CADENCIA * 0.5)
	assert_false(atacante.attack_is_ready(), "venceu na metade do prazo")
	assert_almost_eq(atacante.attack_cooldown, CADENCIA * 0.5)

	atacante.advance_time(CADENCIA * 0.5)
	assert_true(atacante.attack_is_ready(), "não venceu no prazo")

func test_a_cadencia_nao_fica_negativa() -> void:
	# Um tique gordo não pode dar crédito para o ataque seguinte.
	var atacante: Unit = _unit()
	var alvo: Unit = _unit(1)
	atacante.basic_attack(alvo)
	atacante.advance_time(10.0)
	assert_almost_eq(atacante.attack_cooldown, 0.0)

func test_o_cego_gasta_a_cadencia_do_mesmo_jeito() -> void:
	# É o que separa CEGAR de DESARMAR: o ataque sai, erra, e o tempo foi
	# gasto. O ramo do cego sai cedo de `basic_attack`, e esquecer a cadência
	# ali daria um cego que ataca todo tique.
	var atacante: Unit = _unit()
	var alvo: Unit = _unit(1)
	atacante.status.apply(StatusSet.Kind.BLIND, 5.0)

	var result: DamageResult = atacante.basic_attack(alvo)
	assert_true(result.missed, "o cego acertou")
	assert_almost_eq(
		atacante.attack_cooldown, CADENCIA, "o cego não gastou a cadência"
	)

# ------------------------------------------------------------- o reset

func test_habilidade_que_zera_libera_o_proximo_ataque() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(1)
	caster.basic_attack(alvo)
	assert_false(caster.attack_is_ready())

	var result := AbilityEngine.cast(
		AbilityBook.new(), _habilidade(true), AbilityCast.on_self(caster), [caster]
	)
	assert_true(result.succeeded())
	assert_true(caster.attack_is_ready(), "conjurou e a cadência continuou correndo")
	assert_almost_eq(caster.attack_cooldown, 0.0)

func test_habilidade_que_nao_zera_deixa_a_cadencia_intacta() -> void:
	# A metade que prova que o campo é LIDO. Sem este par, marcar todas as
	# habilidades como zeradoras passaria no teste de cima.
	var caster: Unit = _unit()
	var alvo: Unit = _unit(1)
	caster.basic_attack(alvo)
	caster.advance_time(0.2)
	var antes: float = caster.attack_cooldown

	AbilityEngine.cast(
		AbilityBook.new(), _habilidade(false), AbilityCast.on_self(caster), [caster]
	)
	assert_almost_eq(caster.attack_cooldown, antes, "zerou sem ter o direito")
	assert_false(caster.attack_is_ready())

func test_o_padrao_e_nao_zerar() -> void:
	assert_false(Ability.new().resets_attack_cooldown)

func test_zerar_com_a_cadencia_ja_vencida_nao_atrapalha() -> void:
	var caster: Unit = _unit()
	AbilityEngine.cast(
		AbilityBook.new(), _habilidade(true), AbilityCast.on_self(caster), [caster]
	)
	assert_true(caster.attack_is_ready())
	assert_almost_eq(caster.attack_cooldown, 0.0)

# --------------------------------------- quem NÃO tem o direito de zerar

func test_conjuracao_recusada_por_recarga_nao_zera() -> void:
	# O caso mais perigoso: apertar Q com Q em recarga não pode virar um reset
	# de auto-ataque de graça. Seria dano grátis por apertar botão inútil.
	var caster: Unit = _unit()
	var alvo: Unit = _unit(1)
	var book := AbilityBook.new()
	var ability: Ability = _habilidade(true, 10.0)

	AbilityEngine.cast(book, ability, AbilityCast.on_self(caster), [caster])
	caster.basic_attack(alvo)
	var antes: float = caster.attack_cooldown

	var segunda := AbilityEngine.cast(
		book, ability, AbilityCast.on_self(caster), [caster]
	)
	assert_eq(segunda.status, CastResult.Status.ON_COOLDOWN)
	assert_almost_eq(caster.attack_cooldown, antes, "a recusa zerou a cadência")

func test_conjuracao_recusada_por_mana_nao_zera() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(1)
	caster.stats.set_base(Stat.Id.MAX_MANA, 10.0)
	caster.mana.current = 0.0
	caster.basic_attack(alvo)
	var antes: float = caster.attack_cooldown

	var result := AbilityEngine.cast(
		AbilityBook.new(), _habilidade(true, 0.0, 50.0),
		AbilityCast.on_self(caster), [caster]
	)
	assert_eq(result.status, CastResult.Status.NO_RESOURCE)
	assert_almost_eq(caster.attack_cooldown, antes)

func test_conjuracao_recusada_por_controle_nao_zera() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(1)
	caster.basic_attack(alvo)
	var antes: float = caster.attack_cooldown
	caster.status.apply(StatusSet.Kind.SILENCE, 5.0)

	var result := AbilityEngine.cast(
		AbilityBook.new(), _habilidade(true), AbilityCast.on_self(caster), [caster]
	)
	assert_eq(result.status, CastResult.Status.CANNOT_CAST)
	assert_almost_eq(caster.attack_cooldown, antes)

func test_suprema_sem_carga_nao_zera() -> void:
	var caster: Unit = _unit()
	var alvo: Unit = _unit(1)
	caster.stats.set_base(Stat.Id.MAX_ULTIMATE_CHARGE, 1000.0)
	caster.ultimate_charge.current = 0.0
	caster.basic_attack(alvo)
	var antes: float = caster.attack_cooldown

	var suprema: Ability = _habilidade(true)
	suprema.uses_ultimate_charge = true
	var result := AbilityEngine.cast(
		AbilityBook.new(), suprema, AbilityCast.on_self(caster), [caster]
	)
	assert_eq(result.status, CastResult.Status.NO_CHARGE)
	assert_almost_eq(caster.attack_cooldown, antes)

# ------------------------------------------ conjuração com tempo de canto

func test_conjuracao_com_tempo_zera_ao_comecar() -> void:
	# Mesma regra da mana e da recarga: o custo sai ao iniciar, e quem for
	# interrompido no meio não recupera nada. O reset segue junto porque é o
	# mesmo instante — o instante em que a conjuração deixou de poder ser
	# recusada.
	var caster: Unit = _unit()
	var alvo: Unit = _unit(1)
	caster.basic_attack(alvo)

	var ability: Ability = _habilidade(true)
	ability.cast_time = 1.0
	var book := AbilityBook.new()
	var result := AbilityEngine.cast(
		book, ability, AbilityCast.on_self(caster), [caster]
	)
	assert_eq(result.status, CastResult.Status.CASTING)
	assert_true(caster.attack_is_ready(), "esperou o canto terminar para zerar")

func test_conjuracao_com_tempo_nao_zera_de_novo_ao_terminar() -> void:
	# Zerar duas vezes é inofensivo hoje; deixa de ser no dia em que o reset
	# virar "devolve X segundos". O que se protege é o reset ser UM evento por
	# conjuração, e não um por etapa.
	var caster: Unit = _unit()
	var alvo: Unit = _unit(1)
	var ability: Ability = _habilidade(true)
	ability.cast_time = 1.0
	var book := AbilityBook.new()

	AbilityEngine.cast(book, ability, AbilityCast.on_self(caster), [caster])
	book.advance_time(1.0)
	# Bate DEPOIS do reset de início e ANTES de a conjuração concluir: se o
	# fim zerasse de novo, esta cadência sumiria.
	caster.basic_attack(alvo)
	var antes: float = caster.attack_cooldown
	assert_almost_eq(antes, CADENCIA)

	var result := AbilityEngine.resolve_pending(book, [caster])
	assert_true(result.succeeded())
	assert_almost_eq(caster.attack_cooldown, antes, "o fim do canto zerou de novo")

# ------------------------------------------------------------- o corpus

func test_o_catalogo_le_o_campo() -> void:
	var zera: Ability = AbilityCatalog.build({
		"id": "x", "resets_attack_cooldown": true,
	})
	assert_true(zera.resets_attack_cooldown)
	var nao: Ability = AbilityCatalog.build({"id": "y"})
	assert_false(nao.resets_attack_cooldown, "sem o campo, virou verdadeiro")

func test_a_copia_da_suprema_leva_o_campo() -> void:
	# `ActorProfile.ultimate_for()` entrega uma CÓPIA da habilidade do catálogo.
	# Se o campo deixasse de ser `@export`, `duplicate()` o perderia em
	# silêncio — e a suprema de 22 campeões pararia de resetar sem erro nenhum.
	var original: Ability = _habilidade(true)
	var copia: Ability = original.duplicate() as Ability
	assert_true(copia.resets_attack_cooldown)
