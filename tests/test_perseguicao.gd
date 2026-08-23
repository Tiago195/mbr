extends TestCase

## A âncora que ACOMPANHA alguém, em vez de ficar onde foi plantada.
##
## `FollowTarget` do original — e a coluna **não é booleana**, que foi o que
## deixou a lacuna mal descrita por três documentos: ela vale `None` em 1552
## impactos, `User` em 353 e `Target` em 62. A maioria esmagadora acompanha o
## CONJURADOR, não o alvo.
##
## **Só muda alguma coisa em pulso ATRASADO.** Num pulso instantâneo a âncora
## já é calculada no lugar certo, e perseguir por zero segundo é um no-op — é
## por isso que a lacuna vale para 27 dos 127 espaços de campeão e não para os
## 41 que declaram a coluna.
##
## O que estes testes protegem, dos dois lados:
##
## 1. Que quem declara `follow` PERSEGUE. Sem isso, o segundo golpe de um combo
##    em que o personagem andou 1,8 m no meio sai de onde ele estava.
## 2. Que quem NÃO declara continua congelado. Área no chão não persegue
##    ninguém, e transformar todas em perseguidoras seria uma regressão que a
##    metade de cima destes testes não veria.

func _unit(posicao: Vector3 = Vector3.ZERO, equipe: int = 0) -> Unit:
	var stats := Stats.new()
	stats.set_bases({Stat.Id.MAX_HEALTH: 1000.0, Stat.Id.ABILITY_POWER: 100.0})
	var unit := Unit.new(stats, equipe)
	unit.position = posicao
	return unit

## Uma habilidade com um pulso atrasado, de raio pequeno, que só acerta quem
## estiver bem em cima da âncora. O raio pequeno é o ponto: é ele que
## transforma "a âncora foi para o lugar certo" em "acertou ou não acertou".
func _atrasada(perseguicao: AbilityPulse.Follow) -> Ability:
	var ability := Ability.new()
	ability.id = &"atrasada"
	ability.aim = Ability.Aim.POINT
	ability.cooldown = 0.0
	ability.cast_range = 0.0
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.origin = AbilityPulse.Origin.CASTER
	pulse.radius = 1.0
	pulse.delay = 0.5
	pulse.follow = perseguicao
	var dano := DamageEffect.new()
	dano.base_damage = 100.0
	dano.damage_type = Damage.Type.TRUE
	pulse.effects = [dano]
	return ability

## Conjura, anda com o conjurador, deixa o pulso vencer, e devolve a âncora com
## que ele saiu.
func _ancora_depois_de_andar(
		perseguicao: AbilityPulse.Follow,
		passo: Vector3,
		origem: AbilityPulse.Origin = AbilityPulse.Origin.CASTER
) -> Vector3:
	var caster: Unit = _unit(Vector3(1.0, 0.0, 2.0))
	var ability: Ability = _atrasada(perseguicao)
	ability.pulses[0].origin = origem
	var alvo: Unit = _unit(Vector3(9.0, 0.0, 9.0), 1)

	var book := AbilityBook.new()
	var mira: AbilityCast = AbilityCast.at_point(caster, caster.position)
	mira.unit_target = alvo
	AbilityEngine.cast(book, ability, mira, [caster, alvo])

	caster.position += passo
	alvo.position += passo * 2.0
	book.advance_time(0.5, caster)
	var saidas: Array[CastResult] = AbilityEngine.resolve_scheduled(
		book, [caster, alvo]
	)
	assert_eq(saidas.size(), 1, "o pulso atrasado não saiu")
	return saidas[0].anchor

# --------------------------------------------------- quem NÃO persegue

func test_sem_perseguicao_a_ancora_fica_onde_foi_plantada() -> void:
	# 940 dos 1198 pulsos atrasados do corpus são assim, e continuam sendo.
	var ancora: Vector3 = _ancora_depois_de_andar(
		AbilityPulse.Follow.NONE, Vector3(5.0, 0.0, 0.0)
	)
	assert_almost_eq(ancora.x, 1.0, "a área andou junto sem ter o direito")
	assert_almost_eq(ancora.z, 2.0)

# ------------------------------------------------------ quem persegue

func test_perseguindo_o_conjurador_a_ancora_acompanha() -> void:
	var ancora: Vector3 = _ancora_depois_de_andar(
		AbilityPulse.Follow.CASTER, Vector3(5.0, 0.0, 0.0)
	)
	assert_almost_eq(ancora.x, 6.0, "a área não acompanhou quem conjurou")
	assert_almost_eq(ancora.z, 2.0)

func test_perseguindo_o_alvo_a_ancora_acompanha_o_alvo() -> void:
	# O alvo anda o DOBRO do conjurador no fixture: se a perseguição pegasse a
	# pessoa errada, o número sairia diferente em vez de coincidir.
	var ancora: Vector3 = _ancora_depois_de_andar(
		AbilityPulse.Follow.TARGET, Vector3(5.0, 0.0, 0.0),
		AbilityPulse.Origin.TARGET_UNIT
	)
	assert_almost_eq(ancora.x, 19.0, "a área não acompanhou o alvo")
	assert_almost_eq(ancora.z, 9.0)

func test_perseguir_muda_quem_leva_o_golpe() -> void:
	# A conferência que interessa não é a coordenada: é o dano. Uma âncora
	# certa no papel e um alvo errado na prática seria cobertura falsa.
	var caster: Unit = _unit(Vector3.ZERO)
	var parado: Unit = _unit(Vector3(0.2, 0.0, 0.0), 1)
	var longe: Unit = _unit(Vector3(8.0, 0.0, 0.0), 1)

	var book := AbilityBook.new()
	var ability: Ability = _atrasada(AbilityPulse.Follow.CASTER)
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, caster.position),
		[caster, parado, longe]
	)
	# O conjurador anda até o segundo alvo antes de o golpe sair.
	caster.position = Vector3(8.0, 0.0, 0.0)
	book.advance_time(0.5, caster)
	AbilityEngine.resolve_scheduled(book, [caster, parado, longe])

	assert_almost_eq(parado.health.current, 1000.0, "acertou quem ficou para trás")
	assert_almost_eq(longe.health.current, 900.0, "não acertou quem estava no destino")

# ------------------------------------------------------- casos de borda

func test_o_deslocamento_e_reaplicado_sobre_a_base_nova() -> void:
	# Sem isto, a explosão que nasce dois metros à frente perde esses dois
	# metros no instante em que passa a perseguir.
	var caster: Unit = _unit(Vector3.ZERO)
	var ability: Ability = _atrasada(AbilityPulse.Follow.CASTER)
	ability.pulses[0].forward_offset = 2.0

	var book := AbilityBook.new()
	# Mira para -Z, que é a frente na convenção da Godot.
	AbilityEngine.cast(
		book, ability, AbilityCast.at_point(caster, Vector3(0.0, 0.0, -5.0)),
		[caster]
	)
	caster.position = Vector3(0.0, 0.0, -10.0)
	book.advance_time(0.5, caster)
	var saidas: Array[CastResult] = AbilityEngine.resolve_scheduled(book, [caster])
	assert_eq(saidas.size(), 1)
	assert_almost_eq(saidas[0].anchor.z, -12.0, "o deslocamento sumiu ao perseguir")

func test_pulso_instantaneo_nao_muda_de_lugar_por_perseguir() -> void:
	# 342 dos 343 pulsos `User` do corpus são instantâneos. Para eles a
	# perseguição é um no-op, e tem que continuar sendo — senão o número da
	# lacuna (27 espaços) estaria errado pelo outro lado.
	var caster: Unit = _unit(Vector3(3.0, 0.0, 4.0))
	var ability: Ability = _atrasada(AbilityPulse.Follow.CASTER)
	ability.pulses[0].delay = 0.0

	var resultado := AbilityEngine.cast(
		AbilityBook.new(), ability,
		AbilityCast.at_point(caster, caster.position), [caster]
	)
	assert_true(resultado.succeeded())
	# A âncora vive nas PARTES, e não no resultado que as junta — foi assim
	# que a lacuna 1 (vários golpes) a deixou, porque uma conjuração de doze
	# golpes tem doze âncoras e nenhuma delas é "a" âncora.
	assert_eq(resultado.parts.size(), 1)
	assert_almost_eq(resultado.parts[0].anchor.x, 3.0)
	assert_almost_eq(resultado.parts[0].anchor.z, 4.0)

func test_perseguir_o_conjurador_ausente_usa_a_ancora_congelada() -> void:
	var pulse := AbilityPulse.new()
	pulse.follow = AbilityPulse.Follow.CASTER
	var congelada := Vector3(7.0, 0.0, 7.0)
	assert_eq(pulse.anchor_when_fired(null, congelada), congelada)

func test_perseguir_alvo_inexistente_usa_a_ancora_congelada() -> void:
	# Habilidade de ponto, sem unidade apontada: `unit_target` é nulo, e a
	# âncora congelada é a melhor resposta que existe.
	var caster: Unit = _unit()
	var pulse := AbilityPulse.new()
	pulse.follow = AbilityPulse.Follow.TARGET
	var congelada := Vector3(7.0, 0.0, 7.0)
	assert_eq(
		pulse.anchor_when_fired(AbilityCast.at_point(caster, Vector3.ZERO), congelada),
		congelada
	)

# ------------------------------------------------------------- o corpus

func test_o_padrao_e_nao_perseguir() -> void:
	assert_eq(AbilityPulse.new().follow, AbilityPulse.Follow.NONE)

func test_o_catalogo_le_o_campo() -> void:
	var ability: Ability = AbilityCatalog.build({
		"id": "x",
		"pulses": [{"form": "CIRCLE", "follow": "CASTER", "effects": []}],
	})
	assert_eq(ability.pulses[0].follow, AbilityPulse.Follow.CASTER)
	var sem: Ability = AbilityCatalog.build({
		"id": "y", "pulses": [{"form": "CIRCLE", "effects": []}],
	})
	assert_eq(sem.pulses[0].follow, AbilityPulse.Follow.NONE)

## **Não há teste de valor desconhecido aqui, e a ausência é medida.**
## `_enum` cai no padrão E registra o desconhecido com `push_warning`, que vai
## para o stderr — e o critério da suíte deste projeto é stderr de ZERO bytes.
## Um teste que exercite esse caminho reprova a suíte inteira pelo motivo
## errado. Quem cobre a contagem de desconhecidos é `test_catalogo_traduzido`,
## que a afirma sobre o corpus real.
