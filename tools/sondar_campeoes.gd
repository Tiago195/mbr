extends SceneTree

## Percorre todos os campeões na CENA DE VERDADE, e conjura o kit de cada um.
##
## A suíte de `tests/` só alcança `scripts/core/` — é a parte que não conhece
## nó. `ChampionSelector`, `Combatant` e `AbilityCaster` moram em `gameplay/` e
## ficariam sem nenhuma cobertura automática. Esta sonda fecha esse buraco por
## cima: carrega `main.tscn`, troca de campeão em todos eles, conjura Q, W, E e
## R de cada um, e falha se alguma coisa quebrar.
##
## Não substitui olho humano — ela não sabe se ficou divertido, nem se a
## telegrafia está BONITA. O que ela sabe é se quebrou, e onde cada marca foi
## parar.
##
## **Ela depende de `_process` NÃO rodar, e isso é hipótese, não acidente.**
## Tudo acontece dentro de um único `process_frame`, então nó nenhum recebe
## `_process` e nenhuma marca expira. É isso que faz o par `antes`/`depois`
## fechar. No dia em que esta sonda avançar quadros de verdade, as marcas vão
## sumir sozinhas (vivem 0,45s) e a contagem vai dar zero em todo lugar — o que
## pareceria "nada foi desenhado" em vez de "a sonda mudou de premissa".
##
## Rodar:
##     godot --headless --path . --script res://tools/sondar_campeoes.gd

const CENA: String = "res://scenes/main.tscn"

## Onde o conjurador é posto, e para onde ele mira.
##
## Nenhum dos dois é o eixo nem a origem, e a razão é medida: com o jogador em
## (0,0) mirando para -Z, toda âncora e toda direção saíam iguais, e a
## conferência de lugar e lado ficava cega por falta de variedade no fixture,
## não por falta de código.
const POSICAO_DA_SONDA := Vector3(3.0, 1.0, 1.5)
const DESLOCAMENTO_DA_MIRA := Vector3(1.8, 0.0, -2.4)

## Quanto a mira gira de um espaço para o outro.
##
## Sem isto, Q, W, E e R são todos mirados na MESMA direção, e a conferência de
## orientação fica sem variedade para distinguir: `_lado` devolvendo constante
## produzia exatamente o mesmo resultado que a verdade. Foi o mesmo defeito da
## posição, uma rodada antes — fixture degenerado, não código faltando.
const GIRO_POR_ESPACO_EM_GRAUS: float = 50.0

## A cadência de ataque plantada antes de cada conjuração, em segundos.
##
## Existe para a conferência do reset de auto-ataque não ser degenerada. Se a
## cadência já estivesse em zero, "zerou" e "não mexeu" seriam a MESMA leitura,
## e a mutação que zera tudo seria um no-op literal — foi o que já aconteceu
## com posição, direção e carga. Valor esquisito de propósito: 0,37 não é
## intervalo de ataque de ninguém.
const CADENCIA_DA_SONDA: float = 0.37

## O salto que o conjurador dá entre a conjuração e os golpes atrasados saírem.
##
## Sem ele a conferência da perseguição seria degenerada: com o conjurador
## parado, "a âncora acompanhou" e "a âncora ficou congelada" são a mesma
## leitura, e a mutação que desliga a perseguição vira no-op — o mesmo defeito
## que já pegou posição, direção, carga e cadência neste projeto.
##
## É um salto ÚNICO, e não um passo por tique, por duas razões medidas: um
## passo por tique acumulava 72 m ao longo dos 1200 tiques do orçamento, e
## vazava de um espaço para o outro até as coordenadas passarem de mil — e aí
## a assinatura das marcas passou a divergir na quarta casa decimal, o que
## reprovava a conferência de telegrafia por erro de arredondamento.
##
## No eixo X, longe do -Z para onde a sonda mira, para o salto não se confundir
## com o alcance da forma.
##
## **30 metros, e o tamanho é medido.** A comparação é por distância relativa —
## "a âncora ficou mais perto de onde ele está ou de onde conjurou?" —, e por
## isso ela cega quando o deslocamento do pulso passa de meio salto. Com 4 m,
## forçar TODOS os pulsos a perseguir era flagrado em 156 dos 160 que deviam
## ficar; com 12 m, em 159; com 30 m, em 160. Quatro casos passando por um
## estado quebrado é o tipo de folga que este projeto já pagou caro.
const SALTO_ENTRE_GOLPES := Vector3(30.0, 0.0, 0.0)

## O salto que o ALVO dá, no mesmo instante. Eixo DIFERENTE do salto do
## conjurador de propósito: com os dois no mesmo eixo, "acompanhou o alvo" e
## "acompanhou quem conjurou" ficariam indistinguíveis.
const SALTO_DO_ALVO := Vector3(0.0, 0.0, 26.0)

## Tudo que a assinatura de uma marca precisa distinguir.
##
## Cada uma custou uma rodada de revisão adversarial para entrar: a lista
## nasceu com "existe um nó" e cresceu propriedade por propriedade, sempre pelo
## mesmo caminho — alguém mexia numa que não estava nela e nada acusava. Está
## aqui, explícita, e `_dimensoes_que_a_chave_distingue` prova uma a uma.
## Onde a cobaia do autoteste nasce: longe de qualquer marca de habilidade.
const LUGAR_DA_COBAIA := Vector3(60.0, 0.0, 60.0)

const DIMENSOES_DA_CHAVE: Array[String] = [
	"o lugar", "a escala", "a orientação", "a visibilidade",
	"as camadas de render", "a vida", "a malha",
]

var _raiz: Node

## O que a engine anunciou ter resolvido no espaço em curso. Alimentado pelo
## sinal `AbilityCaster.resolved`; esvaziado a cada tentativa.
var _resolvidos: Array[CastResult] = []

func _anotar(result: CastResult) -> void:
	_resolvidos.append(result)

## Montar e sondar são quadros DIFERENTES, e têm que ser.
##
## `add_child()` dentro do `_init()` de um `SceneTree` não chama `_ready()` na
## hora — ele fica para o começo do primeiro quadro. A primeira versão desta
## sonda reprovava com "os catálogos não carregaram", e o `_ready()` que os
## carrega imprimia DEPOIS do veredito.
func _init() -> void:
	var cena: PackedScene = load(CENA) as PackedScene
	if cena != null:
		_raiz = cena.instantiate()
		root.add_child(_raiz)
		# `current_scene` é o que a telegrafia usa como pai. Montando a cena à
		# mão ele fica nulo, e nada é desenhado — a primeira versão desta
		# conferência acusou "0 de 1 marcas" em todos os campeões por isso.
		current_scene = _raiz
	process_frame.connect(_rodar, CONNECT_ONE_SHOT)

func _rodar() -> void:
	# `Variant` e não `Array[String]` de propósito: erro em tempo de execução
	# aborta só a função onde ocorreu e devolve nulo a quem chamou. Se o
	# estouro derrubasse TAMBÉM esta função, o `quit()` nunca aconteceria — e
	# um `SceneTree` headless sem `quit` roda para sempre.
	var falhas: Variant = _sondar()
	print("")
	if not falhas is Array:
		print("  [FALHOU] a sonda estourou (veja SCRIPT ERROR acima)")
		quit(1)
		return
	var lista: Array = falhas as Array
	if lista.is_empty():
		print("  [ok] todos os campeões trocaram e conjuraram sem erro")
	else:
		for falha: String in lista:
			print("  [FALHOU] %s" % falha)
		print("")
		print("  %d FALHA(S)." % lista.size())
	quit(1 if not lista.is_empty() else 0)

func _sondar() -> Array[String]:
	var falhas: Array[String] = []

	if _raiz == null:
		return ["%s não carregou" % CENA] as Array[String]

	var selector: ChampionSelector = _achar(_raiz) as ChampionSelector
	if selector == null:
		return ["a cena não tem ChampionSelector"] as Array[String]
	if selector.actors == null or selector.abilities == null:
		return ["os catálogos não carregaram"] as Array[String]

	var caster: AbilityCaster = selector.caster()
	caster.resolved.connect(_anotar)
	var combatant: Combatant = selector.combatant()
	if caster == null or combatant == null or combatant.unit == null:
		return ["o seletor não achou Combatant ou AbilityCaster"] as Array[String]
	var unit: Unit = combatant.unit

	# **O fixture não pode ser degenerado.** O jogador de `main.tscn` nasce na
	# ORIGEM do mundo, e a mira genérica apontava para o eixo -Z. Com isso 17
	# das 20 âncoras davam (0,0) e 100% das direções davam `FORWARD` — uma
	# conferência de lugar e de lado não distinguiria nada, e uma mutação que
	# plantasse toda marca na origem seria literalmente um no-op.
	var corpo: Node3D = combatant.body()
	if corpo != null:
		corpo.global_position = POSICAO_DA_SONDA
	unit.position = POSICAO_DA_SONDA

	# O primeiro campeão da roda também precisa ter o que zerar: sem isto ele é
	# o único que a conferência de troca nunca alcança. Vale para a carga da
	# suprema e para a cadência do ataque, pelo mesmo motivo.
	unit.ultimate_charge.current = maxf(unit.ultimate_charge.maximum(), 1.0)
	unit.attack_cooldown = CADENCIA_DA_SONDA

	# Onde cada combatente da cena começa. É o que a normalização de cada
	# espaço restaura — inclusive os alvos, que a conferência da perseguição
	# move de propósito.
	var lugares_originais: Dictionary = {}
	for outro: Unit in Combatant.all_units(self):
		lugares_originais[outro] = outro.position

	var campeoes: Array[ActorProfile] = selector.actors.champions()
	print("")
	print("  sondando %d campeões" % campeoes.size())

	# Censo das tentativas. Existe porque a versão anterior desta sonda
	# alcançava 41 dos 119 espaços e não dizia nada: uma habilidade com
	# `cast_time > 0` devolvia CASTING, o `_pending` do livro nunca era
	# resolvido, e daí em diante TUDO era recusado com BUSY — em silêncio, no
	# ramo que trata recusa como resposta legítima. O poder de detecção caía
	# junto: uma regressão que deveria dar 52 falhas dava 19.
	var censo: Dictionary = {}
	var conferidos: int = 0
	var comparacoes: int = 0
	## Os lugares e os lados DISTINTOS que apareceram em assinatura.
	##
	## São a autodefesa das duas dimensões que a conferência acrescentou por
	## último. `_lugar` ou `_lado` devolvendo constante não muda o número de
	## comparações — o piso de trabalho não via nada —, mas colapsa estes dois
	## conjuntos para um elemento.
	var lugares: Dictionary = {}
	var lados: Dictionary = {}
	## Espaços que zeraram a cadência do ataque básico, e espaços que a
	## mantiveram. Os DOIS são piso: se um deles zerar, a conferência virou
	## tautologia — ou nada zera, ou tudo zera, e nos dois casos ela passa.
	var zeraram: int = 0
	var mantiveram: int = 0
	## Golpes atrasados que acompanharam o conjurador, e golpes atrasados que
	## ficaram onde foram plantados. Os DOIS são piso, pelo mesmo motivo do par
	## da cadência: se um zerar, a conferência virou tautologia.
	var perseguiram: int = 0
	var ficaram: int = 0
	## Golpes atrasados de conjuração COM TEMPO, que a conferência da
	## perseguição não alcança. Publicado, e não silencioso: cobertura que
	## encolhe sem avisar é o sintoma que este projeto mais persegue.
	var pulados: int = 0
	## Golpes atrasados que perseguem o ALVO. Separados em dois porque a mira
	## genérica da sonda não aponta unidade em todos os espaços, e sem essa
	## separação "conferido" e "não alcançado" virariam o mesmo número.
	var alvo_seguido: int = 0
	var alvo_sem_mira: int = 0
	## Todo golpe atrasado que chegou à conferência da âncora.
	##
	## Existe para a soma FECHAR. `Follow.TARGET` ficou de fora de todos os
	## ramos numa revisão — nem conferido, nem publicado —, e nenhum piso viu:
	## os que existiam contavam categorias, e o que escapava não estava em
	## categoria nenhuma. Conferir o TOTAL pega qualquer valor novo do enum que
	## alguém acrescente sem tratar, e não só este.
	var atrasados_vistos: int = 0

	for profile: ActorProfile in campeoes:
		if not selector.select(profile.id):
			falhas.append("%s: não selecionou" % profile.id)
			continue

		# **Trocar de campeão tem que zerar a carga da suprema.** Sem isto,
		# quem trocar com a carga cheia entrega a suprema instantânea ao
		# próximo — o oposto do que o sistema faz. A conferência vem ANTES de
		# a sonda encher a carga para testar os espaços de suprema; feita
		# depois, ela se enganaria com o próprio fixture.
		if unit.ultimate_charge.current > 0.0:
			falhas.append(
				("%s: nasceu com %.0f de carga de suprema; trocar de campeão "
				+ "tem que zerar") % [profile.id, unit.ultimate_charge.current]
			)

		# E a cadência do ataque, pela mesma razão: trocar de campeão é
		# renascer. Sem esta conferência, a linha que a zera em
		# `Combatant.adopt_profile` podia ser apagada em silêncio — a sonda
		# replanta a sentinela antes de cada conjuração e nunca veria a falta.
		if not is_zero_approx(unit.attack_cooldown):
			falhas.append(
				("%s: nasceu com %.2fs de cadência de ataque; trocar de "
				+ "campeão tem que zerar") % [profile.id, unit.attack_cooldown]
			)

		# O painel é o único lugar onde o jogador vê a carga, e o critério desta
		# feature é visual. A conferência é fraca de propósito — ela olha se o
		# número aparece, não se está bonito —, mas apagar a linha ou o sinal
		# que a atualiza passava verde em tudo.
		if unit.ultimate_charge.maximum() > 0.0:
			var painel: String = selector.panel_text()
			if not painel.contains("suprema"):
				falhas.append(
					"%s: o painel não mostra a carga da suprema" % profile.id
				)
			elif not painel.contains("%.0f" % unit.ultimate_charge.maximum()):
				falhas.append(
					"%s: o painel não mostra o custo da suprema (%.0f)"
						% [profile.id, unit.ultimate_charge.maximum()]
				)

		var vida: float = unit.stats.get_value(Stat.Id.MAX_HEALTH)
		if vida <= 100.0:
			falhas.append(
				"%s: nasceu com %.0f de vida — os atributos não foram aplicados"
					% [profile.id, vida]
			)
		# O perfil do original NÃO declara chance de crítico nem poder de
		# habilidade: os dois vêm do Inspector da cena. Uma primeira versão
		# trocava o conjunto inteiro de atributos e apagava os dois em
		# silêncio — vida e ataque continuavam certos, e nada acusava.
		if unit.stats.get_value(Stat.Id.CRIT_CHANCE) <= 0.0:
			falhas.append(
				"%s: a chance de crítico do Inspector sumiu na troca" % profile.id
			)
		if unit.stats.get_value(Stat.Id.ABILITY_POWER) <= 0.0:
			falhas.append(
				"%s: o poder de habilidade do Inspector sumiu na troca" % profile.id
			)

		# Mana e recarga zeradas a cada conjuração: o que se sonda é se a
		# habilidade EXECUTA, não se o custo é justo.
		for slot: AbilityBook.Slot in [
			AbilityBook.Slot.Q, AbilityBook.Slot.W,
			AbilityBook.Slot.E, AbilityBook.Slot.R,
		]:
			var ability: Ability = caster.book.ability_in(slot)
			if ability == null:
				continue

			# **O fixture é normalizado no COMEÇO de cada espaço.**
			#
			# A primeira versão restaurava as posições no fim, depois do laço
			# de tiques — e vazava: medido, o conjurador chegava ao último
			# campeão em x=1293 em vez de x=3, ou seja, 43 saltos de 30 m que
			# alguém não desfez. Com coordenadas dessa ordem a assinatura das
			# marcas passa a divergir na terceira casa decimal e a telegrafia
			# reprova por arredondamento.
			#
			# Restaurar no fim depende de TODO caminho de saída restaurar.
			# Normalizar no começo não depende de nada: é o mesmo motivo pelo
			# qual `adopt_profile` zera o estado ao trocar de campeão em vez de
			# confiar em quem sai limpar.
			unit.position = POSICAO_DA_SONDA
			for outro: Unit in Combatant.all_units(self):
				if lugares_originais.has(outro):
					outro.position = lugares_originais[outro]
			caster.book.clear_cooldowns()
			unit.mana.current = unit.mana.maximum()
			# A carga da suprema também: sem isto os 31 espaços de suprema saem
			# com `NO_CHARGE` e a conferência de marcas perde um quarto do que
			# deveria olhar. Foi o piso de espaços alcançados que acusou.
			#
			# `restore()` e não `current = ...`: atribuir direto NÃO emite
			# `changed`, e é o sinal que mantém o painel acompanhando a carga
			# encher. É a API certa — mas **não é ela que pega o sinal
			# apagado**, e a versão anterior deste comentário dizia que era.
			# Medido: com a atribuição de volta E o sinal apagado, a sonda
			# reprova igual. Quem pega é a conferência do painel logo abaixo,
			# porque sem o sinal ele fica mostrando `0/1000`.
			unit.ultimate_charge.restore(unit.ultimate_charge.maximum())
			if unit.ultimate_charge.maximum() > 0.0:
				var cheio: String = "%.0f/%.0f" % [
					unit.ultimate_charge.maximum(),
					unit.ultimate_charge.maximum(),
				]
				if not selector.panel_text().contains(cheio):
					falhas.append(
						("%s %s: o painel não acompanhou a carga encher "
						+ "(esperava `%s`)") % [
							profile.id, AbilityBook.Slot.keys()[slot], cheio
						]
					)
			# NÃO há `book.interrupt()` aqui, e a ausência é medida: quem
			# desatolava o livro era o tratamento de CASTING abaixo, não a
			# interrupção. Uma versão anterior tinha as duas coisas e um
			# comentário dizendo que a interrupção era o que consertava —
			# afirmação que a medição desmentiu.
			# A cadência é plantada num valor NÃO-ZERO logo antes de conjurar:
			# é o que separa "zerou" de "já estava zerada".
			unit.attack_cooldown = CADENCIA_DA_SONDA
			var mira: AbilityCast = _mirar(ability, unit, int(slot))
			var resultado: CastResult = AbilityEngine.cast(
				caster.book, ability, mira, Combatant.all_units(self)
			)
			if resultado == null:
				falhas.append("%s %s: a engine não devolveu resultado" % [
					profile.id, AbilityBook.Slot.keys()[slot]
				])
				continue

			var nome_do_status: String = CastResult.Status.keys()[resultado.status]
			censo[nome_do_status] = int(censo.get(nome_do_status, 0)) + 1

			# **O reset de auto-ataque.** Conferido AQUI, antes dos tiques, por
			# duas razões: o tique faz a cadência andar sozinha, e uma
			# conjuração recusada nunca chega ao fim do laço — e é justamente
			# a recusa que não pode zerar nada.
			#
			# Os dois contadores contam o que foi MEDIDO na cadência, e não o
			# que a habilidade declarava. Contar a declaração fazia o piso
			# mentir: se o motor parasse de zerar, `zeraram` continuaria em 44
			# e a mensagem "o reset parou de disparar" nunca sairia — ela
			# estaria descrevendo o corpus, não o jogo.
			var saiu_mesmo: bool = resultado.succeeded() or resultado.started()
			var devia_zerar: bool = saiu_mesmo and ability.resets_attack_cooldown
			if is_zero_approx(unit.attack_cooldown):
				zeraram += 1
			else:
				mantiveram += 1
			var esperada: float = 0.0 if devia_zerar else CADENCIA_DA_SONDA
			if not is_equal_approx(unit.attack_cooldown, esperada):
				falhas.append(
					("%s %s (%s): a cadência do ataque ficou em %.2fs e devia "
					+ "ficar em %.2fs (a habilidade %s zera, e a conjuração %s)")
						% [
							profile.id, AbilityBook.Slot.keys()[slot],
							ability.display_name, unit.attack_cooldown, esperada,
							"" if ability.resets_attack_cooldown else "não",
							"saiu" if saiu_mesmo else "foi recusada",
						]
				)

			if resultado.status == CastResult.Status.CANNOT_CAST:
				falhas.append("%s %s: recusada — o campeão anterior deixou um controle?" % [
					profile.id, AbilityBook.Slot.keys()[slot]
				])
				continue
			if resultado.status == CastResult.Status.BUSY:
				falhas.append("%s %s: BUSY — o livro ficou preso numa conjuração" % [
					profile.id, AbilityBook.Slot.keys()[slot]
				])
				continue
			# Recusa por mira é resposta legítima: a mira genérica da sonda fica
			# fora do alcance de algumas e não aponta unidade para as de alvo
			# único. Cobrar marca de conjuração recusada seria cobrar desenho de
			# algo que não aconteceu.
			if not resultado.succeeded() and not resultado.started():
				continue

			# CASTING não é recusa: o efeito sai depois. Desenhar o aviso e
			# ticar até resolver é o que traz as 54 habilidades com tempo de
			# conjuração para dentro desta conferência.
			# A linha de base é tirada DEPOIS do aviso: ele é uma marca que
			# `_assinaturas_esperadas` não prevê, e contá-lo junto dava uma
			# folga de +1 que pagava um golpe faltante. É o mesmo mascaramento
			# que a esfera do projétil causava, de volta dentro do código
			# escrito para consertá-lo.
			_resolvidos.clear()
			var antes: Dictionary = {}
			if resultado.succeeded():
				antes = _assinaturas(_raiz)
				caster.draw_result(resultado)
			elif resultado.started():
				# O aviso de uma conjuração longa tem que durar a conjuração
				# inteira. São 54 habilidades acima dos 0,45s padrão da marca,
				# até 5 segundos: o aviso sumia no meio e quem estava na área
				# deixava de ver o motivo para sair dela.
				var aviso: AbilityTelegraph = caster.draw_warning(ability, mira)
				antes = _assinaturas(_raiz)
				if aviso != null and aviso.lifetime < ability.cast_time:
					falhas.append(
						"%s %s (%s): o aviso dura %.2fs numa conjuração de %.2fs"
							% [
								profile.id, AbilityBook.Slot.keys()[slot],
								ability.display_name, aviso.lifetime,
								ability.cast_time
							]
					)

			# Deixa a conjuração terminar, os golpes atrasados saírem e os
			# projéteis voarem — pelo tique de verdade do `AbilityCaster`, e não
			# chamando a engine na mão. É o que faz esta conferência enxergar o
			# desenho dos golpes SEGUINTES, que é a lacuna dos 61.
			# O orçamento inclui o VOO. Sem o termo de projétil, quase metade
			# dos espaços terminava com projétil ainda no ar, e a esfera dele
			# entrava na conta do espaço SEGUINTE. Foi essa guarda que revelou
			# os quatro projéteis de velocidade zero da suprema do Kaiba.
			var tiques: int = int(ceil((
				ability.cast_time + ability.total_pulse_time() + _voo(ability)
			) * 60.0)) + 120
			# **O conjurador SALTA depois de conjurar**, antes de qualquer golpe
			# atrasado sair. É o que faz a perseguição da âncora ser
			# observável: parado, a âncora que persegue e a congelada caem no
			# mesmo ponto.
			var onde_conjurou: Vector3 = unit.position
			unit.position += SALTO_ENTRE_GOLPES
			var onde_esta: Vector3 = unit.position
			# **O alvo salta também, e por um vetor DIFERENTE.** Os 11 pulsos
			# `TARGET` do corpus são `Origin.TARGET_UNIT` com deslocamento
			# zero, então a âncora congelada já nasce em cima do alvo: mexendo
			# só no conjurador, "acompanhou o alvo" e "ficou congelada" dão a
			# mesma leitura, e a conferência aprovaria a perseguição desligada.
			# É o mesmo fixture degenerado que o salto do conjurador resolve na
			# outra metade — e ele já tinha sido cometido aqui.
			var alvo_da_mira: Unit = mira.unit_target if mira != null else null
			var alvo_onde_conjurou := Vector3.ZERO
			var alvo_onde_esta := Vector3.ZERO
			if alvo_da_mira != null:
				alvo_onde_conjurou = alvo_da_mira.position
				alvo_da_mira.position += SALTO_DO_ALVO
				alvo_onde_esta = alvo_da_mira.position
			for _passo: int in mini(tiques, 1200):
				unit.advance_time(1.0 / 60.0)
				caster.tick(1.0 / 60.0)

			if caster.book.is_casting():
				falhas.append("%s %s: a conjuração não terminou em %d tiques" % [
					profile.id, AbilityBook.Slot.keys()[slot], tiques
				])
				continue
			if not caster.book.projectiles.is_empty():
				falhas.append("%s %s: sobrou projétil no ar depois de %d tiques" % [
					profile.id, AbilityBook.Slot.keys()[slot], tiques
				])
				continue
			if caster.book.has_scheduled():
				falhas.append("%s %s: sobrou golpe agendado depois de %d tiques" % [
					profile.id, AbilityBook.Slot.keys()[slot], tiques
				])
				continue

			# Todo golpe com forma desenhável tem que virar marca na tela, com a
			# GEOMETRIA do pulso, NO LUGAR dele e apontando PARA O LADO dele —
			# e nenhuma marca a mais.
			conferidos += 1
			# Uma conjuração instantânea traz as partes no próprio resultado;
			# uma com tempo resolve DENTRO do tique e chega pelo sinal. As duas
			# entram na mesma conta.
			var saidas: Array[CastResult] = _resolvidos.duplicate()
			if resultado.succeeded():
				saidas.append(resultado)

			# **A perseguição da âncora.** Um golpe atrasado que declara
			# `Follow.CASTER` tem que sair de onde o conjurador ESTÁ, e não de
			# onde ele estava quando conjurou. As duas metades são conferidas:
			# quem persegue tem que ter andado junto, e quem não persegue tem
			# que ter ficado — sem a segunda, marcar tudo como perseguidor
			# passaria.
			for saida: CastResult in saidas:
				if saida.pulse == null or saida.pulse.delay <= 0.0:
					continue
				atrasados_vistos += 1
				# **Conjuração com TEMPO fica de fora, e o motivo é medido.**
				# Nela as âncoras nascem quando o canto TERMINA — ou seja,
				# depois do salto —, então "onde conjurou" não é o ponto que a
				# âncora congelada guardaria. Comparar assim acusava 13 golpes
				# de 2 campeões de perseguir sem declarar, e o defeito era da
				# conferência, não deles.
				if not resultado.succeeded():
					pulados += 1
					continue
				var longe_de_onde_conjurou: float = (
					saida.anchor - onde_conjurou
				).length()
				var longe_de_onde_esta: float = (
					saida.anchor - onde_esta
				).length()
				if saida.pulse.follow == AbilityPulse.Follow.CASTER:
					perseguiram += 1
					# Comparação ESTRITA, e é o que obriga o salto a existir:
					# com salto zero as duas distâncias empatam, `<` é falso, e
					# a conferência acusa em vez de passar por empate. Uma
					# versão com `>` invertido passava verde sem salto nenhum —
					# fixture degenerado se disfarçando de aprovação.
					if not (longe_de_onde_esta < longe_de_onde_conjurou):
						falhas.append(
							("%s %s (%s): o golpe atrasado devia acompanhar o "
							+ "conjurador e saiu a %.2fm de onde ele está, "
							+ "contra %.2fm de onde conjurou") % [
								profile.id, AbilityBook.Slot.keys()[slot],
								ability.display_name, longe_de_onde_esta,
								longe_de_onde_conjurou
							]
						)
				elif saida.pulse.follow == AbilityPulse.Follow.TARGET:
					# **A outra metade do recurso, e ela quase ficou fora.**
					# Sem este ramo os golpes `TARGET` caíam entre o `CASTER` e
					# o `NONE` e não entravam em conta nenhuma: nem conferidos
					# nem publicados. Uma conferência que cobre metade do que
					# diz cobrir é indistinguível de uma que cobre tudo.
					# `CastResult` NÃO carrega a mira — só o pulso, a âncora e a
					# direção. A mira em escopo é a mesma que a engine usou.
					if alvo_da_mira != null:
						alvo_seguido += 1
						# Contra ONDE O ALVO ESTAVA, e não contra a posição do
						# conjurador: a âncora congelada desses pulsos já nasce
						# em cima do alvo, então comparar com o conjurador
						# aprova a perseguição desligada.
						var longe_do_alvo: float = (
							saida.anchor - alvo_onde_esta
						).length()
						var longe_de_onde_o_alvo_estava: float = (
							saida.anchor - alvo_onde_conjurou
						).length()
						if not (longe_do_alvo < longe_de_onde_o_alvo_estava):
							falhas.append(
								("%s %s (%s): o golpe atrasado devia acompanhar "
								+ "o alvo e saiu a %.2fm de onde ele está, "
								+ "contra %.2fm de onde ele estava") % [
									profile.id, AbilityBook.Slot.keys()[slot],
									ability.display_name, longe_do_alvo,
									longe_de_onde_o_alvo_estava
								]
							)
					else:
						# Sem unidade apontada, `anchor_when_fired` devolve a
						# âncora congelada — e é isso que tem que acontecer.
						alvo_sem_mira += 1
						if not (longe_de_onde_conjurou < longe_de_onde_esta):
							falhas.append(
								("%s %s (%s): golpe `TARGET` sem alvo apontado "
								+ "devia ficar na âncora congelada e saiu a "
								+ "%.2fm dela") % [
									profile.id, AbilityBook.Slot.keys()[slot],
									ability.display_name, longe_de_onde_conjurou
								]
							)
				elif saida.pulse.follow == AbilityPulse.Follow.NONE:
					ficaram += 1
					if not (longe_de_onde_conjurou < longe_de_onde_esta):
						falhas.append(
							("%s %s (%s): o golpe atrasado NÃO devia acompanhar "
							+ "ninguém e saiu a %.2fm de onde conjurou "
							+ "[origem=%s atraso=%.2f repete=%d]") % [
								profile.id, AbilityBook.Slot.keys()[slot],
								ability.display_name, longe_de_onde_conjurou,
								AbilityPulse.Origin.keys()[saida.pulse.origin],
								saida.pulse.delay, saida.pulse.repeat_count()
							]
						)

			# **A comparação mora AQUI, e não numa função própria.** Enquanto
			# ela era `_conferir_marcas() -> {problemas, comparacoes}`, dava
			# para zerar o veredito devolvendo `problemas` vazio com o piso de
			# `comparacoes` plenamente satisfeito: uma linha, e a conferência
			# inteira parava de decidir sem uma linha de ruído. Quem junta o
			# dado não decide; quem decide é este laço, e o piso é sobre o
			# mesmo dado que ele lê.
			var depois: Dictionary = _assinaturas(_raiz)
			var esperado: Dictionary = _assinaturas_esperadas(saidas)
			var chaves: Dictionary = {}
			for chave: String in depois:
				chaves[chave] = true
			for chave: String in esperado:
				chaves[chave] = true

			for chave: String in chaves:
				comparacoes += 1
				var lugar: String = _lugar_da_chave(chave)
				if not lugar.is_empty():
					lugares[lugar] = true
				var lado: String = _lado_da_chave(chave)
				if not lado.is_empty():
					lados[lado] = true

				var saiu: int = int(depois.get(chave, 0)) - int(antes.get(chave, 0))
				var devia: int = int(esperado.get(chave, 0))
				if saiu == devia:
					continue
				falhas.append("%s %s (%s): %d marcas `%s`, esperava %d" % [
					profile.id, AbilityBook.Slot.keys()[slot],
					ability.display_name, saiu, _encurtar(chave), devia
				])

		# A carga fica NÃO-ZERO ao sair deste campeão, para o próximo ter o que
		# zerar. Sem isto a conferência de "trocar de campeão zera a carga" não
		# distingue nada: a suprema é o último espaço testado, e conjurá-la já
		# deixa a carga em zero — o fixture entregava a resposta certa pelo
		# motivo errado.
		#
		# E é `maxf(maximo, 1)`, não `maximo`: dois atores da roda têm carga
		# máxima ZERO, e encher "até o máximo" gravava zero neles. Quem vinha
		# depois desses dois não era conferido — três dos 33 escapavam, e eram
		# justamente os vizinhos dos casos de borda do sistema.
		unit.ultimate_charge.current = maxf(
			unit.ultimate_charge.maximum(), 1.0
		)
		unit.attack_cooldown = CADENCIA_DA_SONDA

	var tentativas: int = 0
	for chave: String in censo:
		tentativas += int(censo[chave])
	# Os dois números são DIFERENTES e já coincidiram por acidente — 124 de um
	# lado e 124 do outro, querendo dizer coisas distintas, o que passou por
	# confirmação cruzada numa revisão. Ficam rotulados.
	print("  espaços de campeão tentados: %d" % tentativas)
	print("  ...que passaram da mira e foram conferidos: %d" % conferidos)
	print("  status: %s" % str(censo))

	# **Limite publicado, não silencioso.** Uma conferência que cobre um terço
	# do que diz cobrir é indistinguível de uma que cobre tudo — foi assim que
	# 41 de 119 passaram por completos.
	print("  assinaturas comparadas: %d" % comparacoes)
	print("  lugares distintos: %d   lados distintos: %d" % [
		lugares.size(), lados.size()
	])
	print("  cadência do ataque medida: %d espaços zeraram, %d mantiveram" % [
		zeraram, mantiveram
	])
	# Os parênteses importam: `"a" + "b" % [...]` aplica o `%` só à SEGUNDA
	# parte, e a Godot reclama no stderr sem derrubar nada. A suíte deste
	# projeto trata stderr não-vazio como falha, e foi assim que este apareceu.
	print(("  âncora de golpe atrasado: %d seguiram o conjurador, %d seguiram "
		+ "o alvo, %d ficaram") % [perseguiram, alvo_seguido, ficaram])
	print(("  ...e fora de alcance: %d de conjuração com tempo, %d `TARGET` "
		+ "sem unidade apontada") % [pulados, alvo_sem_mira])

	# **O fixture é afirmado, não só impresso.** Uma mira que deixe de apontar
	# unidade devolve os `NO_TARGET` e tira `Origin.TARGET_UNIT` de exercício —
	# e a versão anterior anunciava esse ganho sem nada o defender.
	if int(censo.get("NO_TARGET", 0)) > 0:
		falhas.append(
			"%d conjurações recusadas por falta de alvo; a mira da sonda parou "
			% int(censo.get("NO_TARGET", 0))
			+ "de apontar unidade e TARGET_UNIT saiu de exercício"
		)
	# Pisos das duas dimensões mais novas da assinatura. Medido na árvore
	# limpa: **67 lugares e 4 lados** — o comentário dizia 9 e 3, números de
	# uma versão da chave anterior à esfera do projétil e à altura entrarem
	# nela. Comentário com número envelhece igual a documento.
	if lugares.size() < 5:
		falhas.append(
			("as marcas saíram em só %d lugares distintos; a conferência de "
			+ "POSIÇÃO parou de distinguir") % lugares.size()
		)
	if lados.size() < 3:
		falhas.append(
			("as marcas saíram em só %d lados distintos; a conferência de "
			+ "ORIENTAÇÃO parou de distinguir") % lados.size()
		)
	# Pisos das duas metades do reset de auto-ataque. Medido na árvore limpa:
	# **44 zeram e 83 mantêm**, e os 44 são exatamente os espaços que DECLARAM
	# o reset — nenhum deles foi recusado pela mira genérica da sonda. Os pisos
	# ficam bem abaixo disso porque a mira pode passar a recusar mais; o que
	# eles pegam é o sistema parar de disparar, ou passar a disparar sempre.
	if zeraram < 20:
		falhas.append(
			("só %d espaços zeraram a cadência do ataque; o reset de "
			+ "auto-ataque parou de disparar") % zeraram
		)
	if mantiveram < 50:
		falhas.append(
			("só %d espaços mantiveram a cadência; algo está zerando o ataque "
			+ "básico sem ter o direito") % mantiveram
		)
	# Pisos das duas metades da perseguição. Medidos na árvore limpa e postos
	# bem abaixo: o que eles pegam é o sistema parar de disparar, ou passar a
	# disparar sempre.
	if perseguiram < 10:
		falhas.append(
			("só %d golpes atrasados acompanharam o conjurador; a perseguição "
			+ "da âncora parou de disparar") % perseguiram
		)
	# **A soma tem que fechar.** É esta conferência, e não os pisos por
	# categoria, que pega um caso caindo fora de todos os ramos.
	var somados: int = (
		perseguiram + alvo_seguido + alvo_sem_mira + ficaram + pulados
	)
	if somados != atrasados_vistos:
		falhas.append(
			("%d golpes atrasados chegaram à conferência da âncora e só %d "
			+ "entraram em alguma conta; há caso caindo fora de todos os ramos")
				% [atrasados_vistos, somados]
		)

	# **O piso do `TARGET` é publicado mesmo valendo zero.** São 11 pulsos no
	# corpus e 3 espaços de campeão, e nos três a mira genérica da sonda não
	# aponta unidade — então a metade `TARGET` do recurso tem cobertura de cena
	# ZERO hoje, e quem lê a saída precisa saber disso em vez de deduzir do
	# silêncio. Quem a cobre é `tests/test_perseguicao.gd`.
	# **O piso é sobre a metade que CONFERE, não sobre o total.** Ele já foi
	# `alvo_seguido + alvo_sem_mira`, e assim ficava satisfeito por golpes que
	# a sonda só contava — `alvo_seguido` podia cair a zero sem ninguém ver.
	if alvo_seguido < 3:
		falhas.append(
			("só %d golpes atrasados de `Follow.TARGET` foram conferidos com "
			+ "alvo apontado; eram 3") % alvo_seguido
		)
	if ficaram < 20:
		falhas.append(
			("só %d golpes atrasados ficaram onde foram plantados; algo está "
			+ "fazendo área de chão perseguir") % ficaram
		)
	if conferidos < 100:
		falhas.append(
			("a conferência de marcas alcançou só %d espaços; algo está "
			+ "recusando conjuração em massa") % conferidos
		)
	# **Piso sobre o TRABALHO, e não só sobre o alcance.** `_conferir_marcas`
	# devolvendo lista vazia zerava a conferência inteira sem uma linha de
	# ruído — a mesma cegueira que a simetria consertou uma camada abaixo,
	# ainda cabendo uma camada acima.
	if comparacoes < 150:
		falhas.append(
			("a conferência comparou só %d assinaturas; ela está passando "
			+ "por cima do que deveria olhar") % comparacoes
		)

	# **A chave se testa antes de julgar qualquer coisa.**
	#
	# Piso por dimensão não serve aqui: `_estado` devolvendo sempre "visível"
	# não muda contagem nenhuma, e um piso sobre "quantas visibilidades
	# distintas apareceram" seria satisfeito por um jogo em que tudo é visível
	# — que é o caso normal. O que prova que a chave distingue uma dimensão é
	# mexer nela e ver a chave mudar.
	#
	# Quem decide é este laço, e não a função que monta o dado — a lição do
	# `_conferir_marcas`, que dava para esvaziar sem ruído.
	var lidas: Array[String] = _assinaturas_do_autoteste()
	if lidas.size() != DIMENSOES_DA_CHAVE.size() + 1:
		falhas.append(
			("o autoteste da chave devolveu %d leituras e a lista de dimensões "
			+ "pede %d: uma das duas encolheu") % [
				lidas.size(), DIMENSOES_DA_CHAVE.size() + 1
			]
		)
	else:
		for indice: int in DIMENSOES_DA_CHAVE.size():
			if lidas[indice + 1] != lidas[0]:
				continue
			falhas.append(
				("a chave não distingue %s: mexer nessa propriedade da marca "
				+ "não muda a assinatura, e a conferência fica cega para ela")
					% DIMENSOES_DA_CHAVE[indice]
			)

	# A área que persiste: a função entrega as assinaturas que a conjuração
	# criou, e a decisão é aqui. Devolvendo lista vazia ela se anularia em
	# silêncio — o piso de comparações só conta o laço principal.
	var marcas_da_area: Array[String] = _marcas_de_area_persistente(caster, unit)
	var durou: bool = false
	for chave: String in marcas_da_area:
		if chave.contains("~%.2f" % DURACAO_DA_AREA_DE_SONDA):
			durou = true
	if marcas_da_area.is_empty():
		falhas.append(
			"a conjuração de área persistente da sonda não produziu marca nenhuma"
		)
	elif not durou:
		falhas.append(
			("a marca de uma área de %.1fs não durou %.1fs — o ramo que estica "
			+ "a vida da marca pela duração do pulso parou de disparar")
				% [DURACAO_DA_AREA_DE_SONDA, DURACAO_DA_AREA_DE_SONDA]
		)

	if campeoes.is_empty():
		return ["o catálogo não tem campeão nenhum"] as Array[String]

	# Passar por todos não pode deixar bônus acumulado. Cada campeão aplica a
	# passiva dele; se a anterior não saísse, o último herdaria todas.
	var ultimo: ActorProfile = campeoes[campeoes.size() - 1]
	selector.select(ultimo.id)
	var do_zero: float = ultimo.build_unit(selector.level).stats.get_value(
		Stat.Id.MAX_HEALTH
	)
	var na_cena: float = unit.stats.get_value(Stat.Id.MAX_HEALTH)
	if absf(na_cena - do_zero) > 1.0:
		falhas.append(
			("passar por %d campeões deixou resíduo: %.0f de vida na cena, "
			+ "contra %.0f montando o mesmo campeão do zero")
				% [campeoes.size(), na_cena, do_zero]
		)

	return falhas

## Mexe numa propriedade de cada vez e devolve as assinaturas LIDAS.
##
## É o teste de mutação da própria chave, rodado a cada execução. Índice 0 é a
## marca intacta; cada índice seguinte é a mesma marca com UMA propriedade
## mexida, na ordem de `DIMENSOES_DA_CHAVE`.
##
## **Devolve a medição, não o veredito.** Uma função que devolve "distingue
## tudo" pode mentir com uma linha e ninguém ver; uma que devolve as leituras
## brutas, não — quem compara é `_sondar`, e o tamanho da lista amarra o
## autoteste à lista de dimensões, então encurtar qualquer um dos dois acusa.
## É a mesma lição de `_conferir_marcas`, que dava para esvaziar sem ruído.
##
## A cobaia é uma FAIXA, e não um disco: ela é assimétrica, então girá-la muda
## a caixa no mundo. Um disco passaria por simetria em vez de por acerto.
func _assinaturas_do_autoteste() -> Array[String]:
	var lidas: Array[String] = []
	var marca: AbilityTelegraph = AbilityTelegraph.line(
		_raiz, LUGAR_DA_COBAIA, Vector3.FORWARD, 8.0, 1.5, Color.WHITE
	)
	if marca == null:
		return lidas
	var instancia: MeshInstance3D = _instancia_de(marca)
	if instancia == null:
		return lidas

	lidas.append(_assinatura_da_marca(marca))

	instancia.position.y += 50.0
	lidas.append(_assinatura_da_marca(marca))
	instancia.position.y -= 50.0

	instancia.scale = Vector3(0.01, 0.01, 0.01)
	lidas.append(_assinatura_da_marca(marca))
	instancia.scale = Vector3.ONE

	instancia.rotation.y = deg_to_rad(90.0)
	lidas.append(_assinatura_da_marca(marca))
	instancia.rotation.y = 0.0

	instancia.visible = false
	lidas.append(_assinatura_da_marca(marca))
	instancia.visible = true

	instancia.layers = 0
	lidas.append(_assinatura_da_marca(marca))
	instancia.layers = AbilityTelegraph.CAMADAS_DE_RENDER

	var vida: float = marca.lifetime
	marca.lifetime = vida + 9.0
	lidas.append(_assinatura_da_marca(marca))
	marca.lifetime = vida

	var malha: Mesh = instancia.mesh
	instancia.mesh = AbilityTelegraph.disc_mesh(2.0)
	lidas.append(_assinatura_da_marca(marca))
	instancia.mesh = malha

	# A cobaia sai da cena. Medido: mantê-la não muda contagem nenhuma, porque
	# ela nasce longe e ANTES da primeira linha de base — mas cinto e
	# suspensório custam uma linha.
	marca.free()
	return lidas

## Quanto dura a área que a sonda constrói. Medido: das 40 vidas de esfera
## distintas do corpus, nenhuma vale 3,00 — então a busca por `~3.00` não
## colide com marca de outra origem.
const DURACAO_DA_AREA_DE_SONDA: float = 3.0

## As assinaturas que uma área que PERSISTE produz.
##
## A habilidade é montada AQUI, à mão, e não sai do corpus — de propósito. Dos
## 1687 pulsos traduzidos, os 5 que declaram duração valem 0,1s, abaixo dos
## 0,45s da marca padrão: o ramo que estica a vida da marca nunca dispara com o
## dado do original, e apagá-lo passava verde em tudo.
##
## Quando o dado não exercita a regra, o jeito de conferi-la é construir o caso
## — não é o mesmo que ter cobertura pelo corpus, e por isso está separado.
func _marcas_de_area_persistente(
		caster: AbilityCaster, unit: Unit
) -> Array[String]:
	var ability := Ability.new()
	ability.id = &"sonda_area_persistente"
	ability.aim = Ability.Aim.POINT
	ability.cast_range = 50.0
	var pulse := AbilityPulse.new()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 2.0
	pulse.duration = DURACAO_DA_AREA_DE_SONDA
	pulse.effects = [DamageEffect.new()]
	ability.pulses = [pulse]

	var antes: Dictionary = _assinaturas(_raiz)
	var resultado: CastResult = AbilityEngine.cast(
		caster.book, ability, AbilityCast.at_point(unit, unit.position),
		Combatant.all_units(self)
	)
	if not resultado.succeeded():
		return [] as Array[String]
	caster.draw_result(resultado)

	var novas: Array[String] = []
	var depois: Dictionary = _assinaturas(_raiz)
	for chave: String in depois:
		if int(depois[chave]) > int(antes.get(chave, 0)):
			novas.append(chave)
	return novas

## Quanto tempo o projétil mais lento desta habilidade leva para cair.
func _voo(ability: Ability) -> float:
	var maior: float = 0.0
	for pulse: AbilityPulse in ability.pulses:
		if pulse == null or pulse.form != AbilityPulse.Form.PROJECTILE:
			continue
		maior = maxf(maior, pulse.length / maxf(pulse.projectile_speed, 0.01))
	return maior

## O que está desenhado na cena: forma, ONDE e PARA QUE LADO.
##
## Três rodadas de revisão adversarial para chegar aqui, e cada uma derrubou
## uma versão mais fraca desta função:
##
## 1. **Contar marcas** deixava passar cone desenhado como faixa.
## 2. **Comparar a CLASSE da malha** deixava passar cone com o raio do círculo
##    e um ângulo qualquer — continua sendo `ArrayMesh`.
## 3. **Comparar a geometria da malha** deixa passar marca no lugar errado e
##    apontando para o lado errado: a malha vive em espaço LOCAL, e posição e
##    rotação moram no `transform`, ao lado dela.
##
## A terceira é a pior das três. Toda marca plantada na origem do mapa, ou todo
## cone apontando para o mesmo lado independentemente da mira, passava verde —
## e é literalmente o defeito que o comentário de `AbilityTelegraph._plant()`
## registra ter custado uma sessão: base transposta, tela cinza, `errors: []`.
func _assinaturas(node: Node) -> Dictionary:
	var contagem: Dictionary = {}
	_somar_assinaturas(node, contagem)
	return contagem

func _somar_assinaturas(node: Node, contagem: Dictionary) -> void:
	var marca := node as AbilityTelegraph
	if marca != null:
		var chave: String = _assinatura_da_marca(marca)
		contagem[chave] = int(contagem.get(chave, 0)) + 1
	for child: Node in node.get_children():
		_somar_assinaturas(child, contagem)

## A esfera do projétil entra na conta com TAMANHO e LUGAR, como toda marca.
##
## Ela foi a última a virar só uma contagem — a string `"esfera"`, sem raio e
## sem posição. E é a única telegrafia que os 78 pulsos de projétil dos kits
## produzem, porque `_draw_pulse` recusa `Form.PROJECTILE` de propósito. Esfera
## nascendo na origem do mapa, com raio fixo, ou virando um cubo: as três
## passavam verdes, e nem o número de comparações se mexia.
##
## **A posição dela quer dizer sim alguma coisa aqui.** Quem move a esfera é
## `_process_shot`, chamada de `_process`, e esta sonda depende de `_process`
## não rodar — ver o cabeçalho. Dentro dela a esfera fica exatamente onde
## `follow()` a plantou, que é a âncora de lançamento. Medido: 15 lugares de
## esfera, 15 âncoras de projétil, correspondência exata.
##
## Sem LADO: uma esfera não aponta para lugar nenhum.
func _assinatura_da_marca(marca: AbilityTelegraph) -> String:
	# **O nó lido é o `MeshInstance3D`, não o `AbilityTelegraph`.** É ele que
	# renderiza, e o transform dele, a visibilidade dele e as camadas dele são
	# a última perna entre o dado e o pixel. Lendo o pai, cinco quebras
	# passavam verdes: malha 50m acima, malha a 1% do tamanho, malha girada 90°,
	# malha fora de toda camada, malha invisível com o pai visível.
	#
	# E é o lado para onde a orientação escrita do projeto empurra as
	# mudanças: o `CLAUDE.md` manda mexer na GEOMETRIA, não em `scale`/
	# `position` do nó.
	#
	# `is_visible_in_tree()` e não `visible`: ele compõe a cadeia inteira, então
	# subsome a visibilidade do pai em vez de exigir um termo a mais.
	var instancia: MeshInstance3D = _instancia_de(marca)
	if instancia == null:
		return "sem malha"
	var estado: String = _estado(
		instancia.is_visible_in_tree(), marca.lifetime, instancia.layers
	)
	var geometria: String = _assinatura_de_malha(
		instancia.mesh, instancia.global_transform
	)
	if marca.follows_projectile():
		return "%s@%s%s" % [
			geometria, _lugar(instancia.global_position), estado
		]
	if geometria.begins_with("CylinderMesh"):
		# Disco não tem lado: `circle()` nem gira o nó, e cobrar orientação
		# dele faria toda marca circular divergir. A regra é pela CLASSE da
		# malha; testar prefixo de um rótulo inventado já quebrou uma vez,
		# quando o rótulo mudou de `disco:` para o nome da classe.
		return "%s@%s%s" % [geometria, _lugar(instancia.global_position), estado]
	return "%s@%s#%s%s" % [
		geometria,
		_lugar(instancia.global_position),
		_lado(-instancia.global_transform.basis.z),
		estado,
	]

func _instancia_de(marca: AbilityTelegraph) -> MeshInstance3D:
	for child: Node in marca.get_children():
		var instancia := child as MeshInstance3D
		if instancia != null and instancia.mesh != null:
			return instancia
	return null

## Tipo, CAIXA NO MUNDO e — quando a malha é construída — os vértices.
##
## `global_transform * mesh.get_aabb()` e não `mesh.get_aabb()`: a caixa da
## MALHA é a mesma em qualquer escala, e a escala do nó era a última parte do
## transform que a chave descartava — `_lado` normaliza e a joga fora. Um disco
## de 2,5 m encolhido para 2,5 cm passava verde. É a classe de defeito que o
## `CLAUDE.md` registra ter custado uma sessão neste projeto, na barra de vida
## da Fase 2.4: **a escala sumindo sem erro no console**.
##
## A caixa no mundo captura posição, rotação e escala num termo só — o mesmo
## movimento que a caixa da malha fez pelas propriedades da malha, aplicado ao
## nó.
##
## A caixa (`get_aabb().size`) entrou no lugar de uma lista de propriedades
## escolhidas a dedo: `top_radius` do cilindro, `size.x`/`size.z` da caixa,
## `radius` da esfera. Essa lista rendeu um achado por rodada de revisão, e
## sempre o mesmo formato — uma propriedade que não estava nela. As duas
## últimas foram a espessura (faixa virando muro de 8 metros) e a altura do
## cilindro (disco virando tubo), as duas invisíveis e as duas quebra visual de
## verdade.
##
## A caixa é as TRÊS dimensões, então fecha a classe em vez de fechar um caso.
## O que ela sabidamente não distingue é cone de cilindro de mesmo envelope —
## e numa câmera isométrica travada, com 6 cm de espessura, os dois leem igual.
func _assinatura_de_malha(mesh: Mesh, onde: Transform3D) -> String:
	var caixa: AABB = onde * mesh.get_aabb()
	var chave: String = "%s:%.3f,%.3f,%.3f" % [
		mesh.get_class(), caixa.size.x, caixa.size.y, caixa.size.z
	]
	var construida := mesh as ArrayMesh
	if construida != null:
		# A caixa de duas cunhas de aberturas diferentes pode coincidir; os
		# vértices não.
		chave += ":%s" % _assinatura_de_vertices(construida)
	return chave

func _assinatura_de_vertices(mesh: ArrayMesh) -> String:
	if mesh.get_surface_count() == 0:
		return "vazia"
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var partes: PackedStringArray = []
	for v: Vector3 in vertices:
		partes.append("%.3f,%.3f" % [v.x, v.z])
	return "|".join(partes)

## Visibilidade e vida.
##
## Nenhuma das duas é geometria, e nenhuma das duas era lida: marca invisível e
## marca que pisca por um milésimo são as duas indistinguíveis de marca
## nenhuma — o mesmo desfecho do defeito original, por outro caminho.
##
## Vem no fim da chave, depois do lado, para o corte de `_encurtar` continuar
## preservando lugar e orientação na mensagem de falha.
func _estado(visivel: bool, vida: float, camadas: int) -> String:
	return "%s~%.2f^%d" % ["!vis" if visivel else "!oculta", vida, camadas]

## Centímetro, e nas TRÊS dimensões.
##
## A altura entrou porque sem ela um disco plantado a 50 metros do chão, ou uma
## esfera a 100 metros abaixo dele, passavam verdes — invisibilidade pura, que
## é o mesmo efeito do defeito original: a habilidade funciona e parece
## quebrada.
##
## Mais fino que o centímetro viraria ruído de ponto flutuante; mais grosso
## deixaria passar meio metro de erro.
func _lugar(ponto: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [ponto.x, ponto.y, ponto.z]

func _lado(direcao: Vector3) -> String:
	var plana := Vector3(direcao.x, 0.0, direcao.z)
	if plana.length_squared() <= 0.000001:
		return "-"
	plana = plana.normalized()
	return "%.2f,%.2f" % [plana.x, plana.z]

## As assinaturas que ESTA conjuração deveria produzir, e quantas de cada.
##
## As âncoras vêm da ENGINE, nunca recalculadas aqui: cada golpe que sai
## anuncia, pelo sinal `AbilityCaster.resolved`, qual pulso era e onde ele se
## plantou. Recalcular a âncora nesta sonda seria conferir a conta contra ela
## mesma.
##
## As malhas de cone e trapézio saem das MESMAS funções que o desenho usa,
## alimentadas pelos parâmetros do pulso: parâmetro errado diverge.
func _assinaturas_esperadas(saidas: Array[CastResult]) -> Dictionary:
	var esperado: Dictionary = {}
	for saida: CastResult in saidas:
		if not saida.parts.is_empty():
			for part: CastResult in saida.parts:
				_somar_esperada(esperado, part.pulse, part.anchor, part.direction)
			continue
		# Resultado por pulso — é assim que chega todo golpe atrasado.
		_somar_esperada(esperado, saida.pulse, saida.anchor, saida.direction)
	return esperado

func _somar_esperada(
		esperado: Dictionary,
		pulse: AbilityPulse,
		anchor: Vector3,
		direction: Vector3
) -> void:
	if pulse == null or pulse.effects.is_empty():
		return
	if pulse.form == AbilityPulse.Form.PROJECTILE:
		# Uma esfera por direção do leque, todas saindo da mesma âncora, com o
		# raio que `AbilityTelegraph` calcula — a MESMA função que o desenho
		# usa, para a conferência não concordar com uma cópia.
		var onde := Vector3(
			anchor.x, AbilityTelegraph.ALTURA_DO_VOO, anchor.z
		)
		# `follow()` dá à esfera a vida do voo mais uma margem — a margem é
		# guarda contra esfera órfã, não o relógio do projétil.
		var vida_da_esfera: float = (
			pulse.length / maxf(pulse.projectile_speed, 0.01)
		) + 0.5
		var chave_da_esfera: String = "%s@%s%s" % [
			_assinatura_de_malha(
				AbilityTelegraph.sphere_mesh(
					AbilityTelegraph.sphere_radius(pulse)
				),
				Transform3D(Basis.IDENTITY, onde)
			),
			_lugar(onde), _estado(true, vida_da_esfera, AbilityTelegraph.CAMADAS_DE_RENDER),
		]
		var quantas: int = pulse.spread_directions(direction).size()
		esperado[chave_da_esfera] = int(
			esperado.get(chave_da_esfera, 0)
		) + quantas
		return
	if pulse.form == AbilityPulse.Form.SINGLE:
		# Sem área: o alvo foi escolhido a dedo e o número de dano é o retorno.
		return

	for lado: Vector3 in pulse.spread_directions(direction):
		var chave: String = _chave_esperada(pulse, anchor, lado)
		if chave.is_empty():
			continue
		esperado[chave] = int(esperado.get(chave, 0)) + 1

## A assinatura que uma forma deveria produzir, incluindo onde o nó vai parar.
##
## O lugar do nó NÃO é sempre a âncora: `AbilityTelegraph.line()` planta a
## faixa pelo CENTRO dela, meio comprimento à frente. Copiar a âncora aqui daria
## divergência em toda faixa do jogo — e é o tipo de detalhe que faz uma
## conferência nova nascer reprovando o que está certo.
func _chave_esperada(
		pulse: AbilityPulse, anchor: Vector3, lado: Vector3
) -> String:
	var no_chao := Vector3(
		anchor.x, AbilityTelegraph.ALTURA_DO_CHAO, anchor.z
	)
	# Vida esperada de uma marca de pulso: `_draw_pulse` estica a padrão pela
	# duração da área, quando ela persiste.
	var vida: float = maxf(
		AbilityTelegraph.VIDA_PADRAO, maxf(pulse.duration, 0.0)
	)
	match pulse.form:
		AbilityPulse.Form.CIRCLE:
			# Disco não é girado: transform de translação pura.
			return "%s@%s%s" % [
				_assinatura_de_malha(
					AbilityTelegraph.disc_mesh(pulse.radius),
					Transform3D(Basis.IDENTITY, no_chao)
				),
				_lugar(no_chao), _estado(true, vida, AbilityTelegraph.CAMADAS_DE_RENDER),
			]
		AbilityPulse.Form.LINE:
			var centro := Vector3(
				anchor.x + _plano(lado).x * pulse.length * 0.5,
				AbilityTelegraph.ALTURA_DO_CHAO,
				anchor.z + _plano(lado).z * pulse.length * 0.5
			)
			return "%s@%s#%s%s" % [
				_assinatura_de_malha(
					AbilityTelegraph.strip_mesh(pulse.width, pulse.length),
					_pousada(centro, lado)
				),
				_lugar(centro), _lado(lado), _estado(true, vida, AbilityTelegraph.CAMADAS_DE_RENDER),
			]
		AbilityPulse.Form.CONE:
			return "%s@%s#%s%s" % [
				_assinatura_de_malha(
					AbilityTelegraph.wedge_mesh(pulse.length, pulse.cone_angle),
					_pousada(no_chao, lado)
				),
				_lugar(no_chao), _lado(lado), _estado(true, vida, AbilityTelegraph.CAMADAS_DE_RENDER),
			]
		AbilityPulse.Form.TRAPEZOID:
			return "%s@%s#%s%s" % [
				_assinatura_de_malha(
					AbilityTelegraph.trapezoid_mesh(
						pulse.near_distance, pulse.near_width,
						pulse.length, pulse.far_width
					),
					_pousada(no_chao, lado)
				),
				_lugar(no_chao), _lado(lado), _estado(true, vida, AbilityTelegraph.CAMADAS_DE_RENDER),
			]
		_:
			return ""

## O transform que `AbilityTelegraph._plant` produz: -Z apontando para `lado`.
##
## Montado com `Basis.looking_at`, que é a mesma conta de `Node3D.look_at`.
## Escrever a matriz à mão já custou uma sessão a este projeto — e aqui daria o
## pior dos mundos, uma expectativa transposta reprovando desenho correto.
func _pousada(origem: Vector3, lado: Vector3) -> Transform3D:
	var plana: Vector3 = _plano(lado)
	return Transform3D(Basis.looking_at(plana, Vector3.UP), origem)

## O trecho de lugar de uma assinatura (`...@x,z...`), ou vazio.
func _lugar_da_chave(chave: String) -> String:
	var arroba: int = chave.rfind("@")
	if arroba < 0:
		return ""
	var resto: String = chave.substr(arroba + 1)
	var cerquilha: int = resto.find("#")
	return resto if cerquilha < 0 else resto.substr(0, cerquilha)

## O trecho de lado de uma assinatura (`...#dx,dz`), ou vazio.
func _lado_da_chave(chave: String) -> String:
	var cerquilha: int = chave.rfind("#")
	return "" if cerquilha < 0 else chave.substr(cerquilha + 1)

func _plano(direcao: Vector3) -> Vector3:
	var plana := Vector3(direcao.x, 0.0, direcao.z)
	if plana.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return plana.normalized()

## Assinatura de malha construída é enorme. Na mensagem de falha o que importa
## é qual forma divergiu, não os 48 vértices dela — mas o lugar e o lado ficam,
## porque são o que distingue "não apareceu" de "apareceu no lugar errado".
func _encurtar(chave: String) -> String:
	var arroba: int = chave.rfind("@")
	if arroba <= 0:
		return chave
	var cabeca: String = chave.substr(0, arroba)
	if cabeca.length() > 28:
		cabeca = cabeca.substr(0, 25) + "..."
	return cabeca + chave.substr(arroba)

## Mira coerente com o tipo de alvo, e FORA do eixo.
##
## `UNIT` recebe alvo de verdade: sem ele a conjuração é recusada com
## `NO_TARGET` e `Origin.TARGET_UNIT` nunca é exercitado.
func _mirar(ability: Ability, unit: Unit, espaco: int) -> AbilityCast:
	var desvio: Vector3 = DESLOCAMENTO_DA_MIRA.rotated(
		Vector3.UP, deg_to_rad(GIRO_POR_ESPACO_EM_GRAUS * float(espaco))
	)
	var ponto: Vector3 = unit.position + desvio
	var mira: AbilityCast
	match ability.aim:
		Ability.Aim.SELF:
			mira = AbilityCast.on_self(unit)
		Ability.Aim.DIRECTION:
			mira = AbilityCast.toward(unit, ponto - unit.position)
		Ability.Aim.UNIT:
			var alvo: Unit = _inimigo_mais_perto(unit)
			mira = (
				AbilityCast.at_point(unit, ponto) if alvo == null
				else AbilityCast.on_unit(unit, alvo)
			)
		_:
			mira = AbilityCast.at_point(unit, ponto)

	# **Habilidade de PONTO também pode ter golpe que precisa de unidade.**
	# O gancho do Chao e a salvação do Odri miram no chão e têm pulso de
	# `Origin.TARGET_UNIT` com `Follow.TARGET`; sem unidade apontada eles caem
	# no ponto mirado, e a metade `TARGET` da perseguição nunca é exercitada.
	# Preencher `unit_target` aqui não muda a mira — muda o que os golpes que
	# dependem de alvo encontram.
	if mira.unit_target == null and _precisa_de_unidade(ability):
		mira.unit_target = _inimigo_mais_perto(unit)
	return mira

## Verdadeiro quando algum golpe da habilidade só faz sentido com uma unidade
## apontada.
static func _precisa_de_unidade(ability: Ability) -> bool:
	for pulse: AbilityPulse in ability.pulses:
		if pulse == null:
			continue
		if pulse.origin == AbilityPulse.Origin.TARGET_UNIT:
			return true
		if pulse.follow == AbilityPulse.Follow.TARGET:
			return true
	return false

func _inimigo_mais_perto(unit: Unit) -> Unit:
	var achado: Unit = null
	var menor: float = INF
	for candidato: Variant in Combatant.all_units(self):
		var outro := candidato as Unit
		if outro == null or outro == unit or not outro.is_alive():
			continue
		if not unit.is_hostile_to(outro):
			continue
		var distancia: float = unit.ground_distance_to(outro)
		if distancia < menor:
			menor = distancia
			achado = outro
	return achado

func _achar(node: Node) -> Node:
	if node is ChampionSelector:
		return node
	for child: Node in node.get_children():
		var achado: Node = _achar(child)
		if achado != null:
			return achado
	return null
