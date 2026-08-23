extends TestCase

## A corrente de combo: apertar o mesmo botão dentro da janela conjura OUTRA
## habilidade.
##
## `ComboSkillInfo_*` do original. O elo seguinte é uma habilidade inteira e
## diferente — `Impact1` muda em 121 dos 125 pares —, e por isso ele é um id do
## catálogo e não um modificador do primeiro.
##
## **O que faz a mecânica valer a pena é o elo seguinte NÃO esperar a recarga
## do primeiro.** Sem isso a corrente seria decorativa: o jogador apertaria de
## novo e ouviria "em recarga". Com isso, o segundo golpe é a recompensa por
## apertar no tempo certo — que é o que dá textura ao corpo a corpo.
##
## A outra metade, e é ela que os testes de baixo protegem: **quem não tem
## corrente, ou apertou fora da janela, continua conjurando o primeiro.**

func _unit() -> Unit:
	var stats := Stats.new()
	stats.set_bases({
		Stat.Id.MAX_HEALTH: 1000.0,
		Stat.Id.ABILITY_POWER: 100.0,
		Stat.Id.MAX_MANA: 1000.0,
	})
	return Unit.new(stats, 0)

## Uma habilidade de dano, identificável pelo que causa.
func _golpe(id: String, dano: float, recarga: float = 10.0) -> Ability:
	var ability := Ability.new()
	ability.id = StringName(id)
	ability.group_id = StringName("g_" + id)
	ability.aim = Ability.Aim.SELF
	ability.cooldown = recarga
	ability.cast_range = 0.0
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.origin = AbilityPulse.Origin.CASTER
	pulse.radius = 5.0
	pulse.hits_self = true
	pulse.hits_enemies = false
	var efeito := DamageEffect.new()
	efeito.base_damage = dano
	efeito.damage_type = Damage.Type.TRUE
	efeito.recipient = AbilityEffect.Recipient.CASTER
	pulse.effects = [efeito]
	return ability

## Encadeia `a` em `b`, com a janela declarada.
func _encadear(
		a: Ability, b: Ability, abre: float = 0.0, dura: float = 3.0
) -> void:
	a.combo_next_id = b.id
	a.combo_window_start = abre
	a.combo_window_length = dura

## Um livro com a corrente já ensinada, como `ActorProfile.equip_book` faz.
func _livro(a: Ability, b: Ability) -> AbilityBook:
	var book := AbilityBook.new()
	book.learn(AbilityBook.Slot.Q, a)
	book.teach_combo(a, b)
	return book

func _conjurar(book: AbilityBook, a: Ability, caster: Unit) -> CastResult:
	return AbilityEngine.cast(book, a, AbilityCast.on_self(caster), [caster])

# ----------------------------------------------------- a corrente sai

func test_apertar_de_novo_na_janela_conjura_o_elo_seguinte() -> void:
	var caster: Unit = _unit()
	var a: Ability = _golpe("a", 100.0)
	var b: Ability = _golpe("b", 250.0)
	_encadear(a, b)
	var book: AbilityBook = _livro(a, b)

	assert_true(_conjurar(book, a, caster).succeeded())
	assert_almost_eq(caster.health.current, 900.0, "o primeiro golpe não saiu")

	var segunda: CastResult = _conjurar(book, a, caster)
	assert_true(segunda.succeeded(), "a segunda conjuração foi recusada")
	assert_eq(segunda.ability.id, &"b", "saiu o primeiro golpe de novo")
	assert_almost_eq(caster.health.current, 650.0, "o elo seguinte não bateu")

func test_o_elo_seguinte_nao_espera_a_recarga_do_primeiro() -> void:
	# É o ponto da mecânica inteira. A recarga de `a` é de 10 s e nada foi
	# tickado: sem a corrente, a segunda tentativa seria ON_COOLDOWN.
	var caster: Unit = _unit()
	var a: Ability = _golpe("a", 100.0, 10.0)
	var b: Ability = _golpe("b", 250.0)
	_encadear(a, b)
	var book: AbilityBook = _livro(a, b)

	_conjurar(book, a, caster)
	assert_true(book.remaining_cooldown(a) > 0.0, "o primeiro não entrou em recarga")

	var segunda: CastResult = _conjurar(book, a, caster)
	assert_eq(segunda.status, CastResult.Status.SUCCESS)
	assert_eq(segunda.ability.id, &"b")

func test_uma_corrente_de_tres_elos_percorre_os_tres() -> void:
	var caster: Unit = _unit()
	var a: Ability = _golpe("a", 100.0)
	var b: Ability = _golpe("b", 200.0)
	var c: Ability = _golpe("c", 300.0)
	_encadear(a, b)
	_encadear(b, c)
	var book: AbilityBook = _livro(a, b)
	book.teach_combo(b, c)

	assert_eq(_conjurar(book, a, caster).ability.id, &"a")
	assert_eq(_conjurar(book, a, caster).ability.id, &"b")
	assert_eq(_conjurar(book, a, caster).ability.id, &"c")
	assert_almost_eq(caster.health.current, 400.0, "os três elos não somaram")

# --------------------------------------------- quem NÃO recebe a corrente

func test_sem_corrente_a_segunda_tentativa_bate_na_recarga() -> void:
	# A metade que prova que a corrente é LIDA. Sem este par, encadear tudo
	# passaria nos testes de cima.
	var caster: Unit = _unit()
	var a: Ability = _golpe("a", 100.0, 10.0)
	var book := AbilityBook.new()
	book.learn(AbilityBook.Slot.Q, a)

	assert_true(_conjurar(book, a, caster).succeeded())
	assert_eq(_conjurar(book, a, caster).status, CastResult.Status.ON_COOLDOWN)

func test_fora_da_janela_a_corrente_expira() -> void:
	var caster: Unit = _unit()
	var a: Ability = _golpe("a", 100.0, 10.0)
	var b: Ability = _golpe("b", 250.0)
	_encadear(a, b, 0.0, 1.0)
	var book: AbilityBook = _livro(a, b)

	_conjurar(book, a, caster)
	book.advance_time(1.5, caster)
	assert_eq(book.combo_count(), 0, "a corrente sobreviveu à janela")
	assert_eq(_conjurar(book, a, caster).status, CastResult.Status.ON_COOLDOWN)

func test_antes_de_a_janela_abrir_sai_o_primeiro_de_novo() -> void:
	# 33 habilidades do original abrem a janela só depois de 1 segundo.
	var caster: Unit = _unit()
	var a: Ability = _golpe("a", 100.0, 0.0)
	var b: Ability = _golpe("b", 250.0)
	_encadear(a, b, 1.0, 3.0)
	var book: AbilityBook = _livro(a, b)

	_conjurar(book, a, caster)
	var cedo: CastResult = _conjurar(book, a, caster)
	assert_eq(cedo.ability.id, &"a", "o elo seguinte saiu antes de a janela abrir")

func test_a_espera_nao_encurta_a_janela() -> void:
	# Descontar o tempo de espera do prazo daria uma janela de 3 s virando 2 s
	# para quem espera 1 s. São 33 habilidades assim.
	var caster: Unit = _unit()
	var a: Ability = _golpe("a", 100.0, 0.0)
	var b: Ability = _golpe("b", 250.0)
	_encadear(a, b, 1.0, 3.0)
	var book: AbilityBook = _livro(a, b)

	_conjurar(book, a, caster)
	book.advance_time(3.5, caster)
	assert_eq(book.combo_count(), 1, "a janela fechou cedo demais")
	assert_eq(_conjurar(book, a, caster).ability.id, &"b")

func test_conjuracao_recusada_nao_arma_corrente() -> void:
	var caster: Unit = _unit()
	caster.stats.set_base(Stat.Id.MAX_MANA, 10.0)
	caster.mana.current = 0.0
	var a: Ability = _golpe("a", 100.0)
	a.mana_cost = 50.0
	var b: Ability = _golpe("b", 250.0)
	_encadear(a, b)
	var book: AbilityBook = _livro(a, b)

	assert_eq(_conjurar(book, a, caster).status, CastResult.Status.NO_RESOURCE)
	assert_eq(book.combo_count(), 0, "a recusa armou a corrente")

func test_o_elo_consumido_nao_sai_duas_vezes() -> void:
	# A armadilha do `group_id`: o elo seguinte tem grupo PRÓPRIO, e apagar a
	# corrente por grupo apagaria a dele — deixando a do primeiro armada.
	# Apertar três vezes daria o segundo golpe duas.
	var caster: Unit = _unit()
	var a: Ability = _golpe("a", 100.0, 10.0)
	# **Recarga ZERO no elo seguinte, e é o que dá dente ao teste.** Com ela em
	# 10 s, "a corrente foi consumida" e "o elo está em recarga" produzem o
	# MESMO `ON_COOLDOWN`, e a mutação que apaga o consumo passa verde — foi
	# medido. Com zero, deixar a corrente armada conjura `b` de novo e a vida
	# cai; consumi-la deixa `a` em recarga e nada acontece.
	var b: Ability = _golpe("b", 250.0, 0.0)
	_encadear(a, b)
	var book: AbilityBook = _livro(a, b)

	_conjurar(book, a, caster)
	assert_eq(_conjurar(book, a, caster).ability.id, &"b")
	var terceira: CastResult = _conjurar(book, a, caster)
	assert_eq(terceira.status, CastResult.Status.ON_COOLDOWN,
			"o elo seguinte saiu duas vezes")
	assert_almost_eq(caster.health.current, 650.0, "o elo seguinte bateu de novo")

# -------------------------------------------------------- estado do livro

func test_trocar_de_kit_esquece_as_correntes() -> void:
	var caster: Unit = _unit()
	var a: Ability = _golpe("a", 100.0)
	var b: Ability = _golpe("b", 250.0)
	_encadear(a, b)
	var book: AbilityBook = _livro(a, b)
	_conjurar(book, a, caster)
	assert_eq(book.combo_count(), 1)

	book.clear_combos()
	assert_eq(book.combo_count(), 0)
	# E o elo também foi esquecido: rearmar não pode ressuscitar a corrente
	# de um kit que não está mais equipado.
	book.arm_combo(a)
	assert_eq(book.combo_count(), 0, "a corrente voltou sem ser reensinada")

func test_ensinar_nulo_apaga_a_corrente() -> void:
	var caster: Unit = _unit()
	var a: Ability = _golpe("a", 100.0)
	var b: Ability = _golpe("b", 250.0)
	_encadear(a, b)
	var book: AbilityBook = _livro(a, b)
	book.teach_combo(a, null)

	_conjurar(book, a, caster)
	assert_eq(book.combo_count(), 0, "armou uma corrente sem elo")

func test_corrente_sem_janela_nao_e_corrente() -> void:
	# `combo_window_length` zero é como o tradutor recusa uma corrente
	# inutilizável. Sem esta guarda ela armaria e fecharia no mesmo tique.
	var a: Ability = _golpe("a", 100.0)
	a.combo_next_id = &"b"
	a.combo_window_length = 0.0
	assert_false(a.has_combo())

func test_o_padrao_e_nao_encadear() -> void:
	assert_false(Ability.new().has_combo())

# ------------------------------------------------------------- o corpus

func test_o_catalogo_le_os_tres_campos() -> void:
	var ability: Ability = AbilityCatalog.build({
		"id": "x",
		"combo_next_id": "rc_9",
		"combo_window_start": 1.0,
		"combo_window_length": 3.0,
	})
	assert_eq(ability.combo_next_id, &"rc_9")
	assert_almost_eq(ability.combo_window_start, 1.0)
	assert_almost_eq(ability.combo_window_length, 3.0)
	assert_true(ability.has_combo())

	var sem: Ability = AbilityCatalog.build({"id": "y"})
	assert_false(sem.has_combo())
