extends SceneTree

## O RITMO do ataque básico, medido com quadros de física de verdade.
##
## Existe por um buraco que uma revisão adversarial abriu: dava para apagar a
## trava de cadência de `player.gd` — trocar `if unit.attack_is_ready()` por
## `if true` — e **as três ferramentas continuavam verdes**. A suíte não
## alcança `gameplay/`, e `sondar_campeoes.gd` roda tudo dentro de um único
## `process_frame` de propósito, então `_physics_process` nunca é chamado lá.
## O comportamento real sob essa mutação: **120 golpes** em dois segundos no
## lugar de 3 — um por quadro de física. O número é o que esta sonda imprime;
## a primeira versão deste comentário dizia 119, copiado de uma medição
## descartada, e ficou divergindo do `CLAUDE.md` e da decisão 18 dentro do
## arquivo escrito para consertar exatamente esse tipo de erro.
##
## O buraco ficou mais perigoso depois que a cadência mudou de lugar (decisão
## 18): quem PERGUNTA se pode bater mora em `Player._physics_process`, e quem
## faz o contador andar mora em `Combatant._physics_process`. São duas metades
## que precisam continuar se encontrando, e nada as via juntas.
##
## Esta sonda avança quadros de física de verdade e conta golpes. É a única
## conferência automática do projeto que exercita o laço de combate como o
## jogo o roda.
##
## Rodar:
##     godot --headless --path . --script res://tools/sondar_ritmo.gd

const CENA: String = "res://scenes/main.tscn"

## Quantos segundos de combate observar. Curto o bastante para a sonda ser
## barata, longo o bastante para caber mais de um golpe — com um golpe só,
## "respeitou a cadência" e "bateu uma vez e travou" seriam a mesma leitura.
const JANELA: float = 2.0

## Vida dada ao boneco durante a medição.
##
## **Não é para a mutação não se esconder.** Com os 3000 do boneco de verdade
## ela ainda dá umas três dezenas de golpes e reprova em quatro frentes — o
## total exato VARIA (27 a 32 em catorze execuções) porque o crítico muda
## quantos golpes o boneco aguenta, e por isso aqui vai a faixa e não uma
## amostra. Número que sorteia não é afirmação; escrever "28" fazia parecer
## que era.
##
## O motivo real é o contrário: é contra FALSO POSITIVO. Um boneco que morre
## no meio da janela some da camada de colisão, `player.gd` solta o alvo, o
## personagem para de bater, e aí as duas conferências ponta a ponta do reset
## acusam falha por um motivo que nada tem a ver com o reset.
##
## A primeira versão deste comentário dava o motivo oposto e errado, e a
## segunda consertou o motivo mas gravou a amostra como se fosse constante.
## Justificativa gravada é afirmação: ela sobrevive a quem a escreveu, e manda
## o próximo leitor investigar o lugar errado.
const VIDA_DE_TESTE: float = 1.0e9

var _raiz: Node
var _golpes: int = 0

## Em que quadro de física cada golpe caiu.
##
## A contagem sozinha não fecha a classe: dá para acertar o TOTAL com o ritmo
## errado. A mutação que prova esta conferência, e a única que a alcança, é
## `unit.advance_time(delta * 0.5)` em `Combatant`: saem **2 golpes**, que é um
## número ACEITO pela faixa da contagem, nos quadros `[0, 91]` — e é só o vão
## de 91 onde se esperavam 45 que denuncia.
##
## `advance_time(0.0)` NÃO exercita isto, ao contrário do que dizia a primeira
## versão deste comentário: com um golpe só não existe vão nenhum para medir, e
## quem o pega é a faixa da contagem. Nomear a mutação errada faz quem for
## reconferir ver a conferência ao lado disparar e concluir a coisa errada.
var _quadros_de_golpe: Array[int] = []
var _quadro: int = 0

func _init() -> void:
	var cena: PackedScene = load(CENA) as PackedScene
	if cena != null:
		_raiz = cena.instantiate()
		root.add_child(_raiz)
		current_scene = _raiz
	process_frame.connect(_rodar, CONNECT_ONE_SHOT)

func _rodar() -> void:
	# `Variant`, e o `quit()` fora da função que pode estourar: erro em tempo
	# de execução aborta só a função onde ocorreu, e um `SceneTree` headless
	# sem `quit` roda para sempre.
	var falhas: Variant = await _sondar()
	print("")
	if not falhas is Array:
		print("  [FALHOU] a sonda de ritmo estourou (veja SCRIPT ERROR acima)")
		quit(1)
		return
	var lista: Array = falhas as Array
	if lista.is_empty():
		print("  [ok] o ataque básico respeita a cadência, e a habilidade a zera")
		quit(0)
		return
	for falha: String in lista:
		print("  [FALHOU] %s" % falha)
	quit(1)

func _sondar() -> Array[String]:
	var falhas: Array[String] = []
	if _raiz == null:
		return ["%s não carregou" % CENA] as Array[String]

	# Um quadro para os `_ready()` rodarem. `add_child` dentro do `_init` de um
	# `SceneTree` não os chama na hora.
	await physics_frame

	var jogador: CharacterBody3D = _achar_jogador(_raiz)
	if jogador == null:
		return ["a cena não tem jogador"] as Array[String]
	var meu: Combatant = Combatant.of(jogador)
	var boneco: Combatant = _achar_boneco()
	if meu == null or boneco == null:
		return ["a cena não tem Combatant do jogador ou boneco de treino"] as Array[String]

	var unit: Unit = meu.unit
	# O boneco encostado no jogador, e imortal pela duração da medição.
	var corpo: Node3D = boneco.body()
	corpo.global_position = jogador.global_position + Vector3(1.0, 0.0, 0.0)
	boneco.unit.position = corpo.global_position
	boneco.unit.stats.set_base(Stat.Id.MAX_HEALTH, VIDA_DE_TESTE)
	boneco.unit.health.reset()
	boneco.damaged.connect(func(_r: DamageResult) -> void:
		_golpes += 1
		_quadros_de_golpe.append(_quadro)
	)

	# `_target` é privado por convenção, não por linguagem. Escrevê-lo é o que
	# substitui o clique do botão direito, que não existe em headless.
	jogador.set("_target", boneco)

	var intervalo: float = unit.attack_interval()
	if intervalo <= 0.0:
		return ["o intervalo de ataque deu %f" % intervalo] as Array[String]
	var esperados: float = JANELA / intervalo
	# **Fixture não-degenerado.** Com menos de dois golpes esperados, a
	# conferência não distingue "respeitou a cadência" de "bateu e travou".
	if esperados < 2.0:
		falhas.append(
			("a janela de %.1fs só cabe %.1f golpes a %.2f atq/s; a medição "
			+ "não distingue cadência de travamento") % [
				JANELA, esperados, unit.stats.get_value(Stat.Id.ATTACK_SPEED)
			]
		)

	_golpes = 0
	_quadros_de_golpe.clear()
	var por_segundo: int = Engine.physics_ticks_per_second
	var quadros: int = int(round(JANELA * por_segundo))
	for passo: int in quadros:
		_quadro = passo
		await physics_frame
	var observados: int = _golpes

	print("")
	print("  cadência: %.3fs (%.2f atq/s)" % [
		intervalo, unit.stats.get_value(Stat.Id.ATTACK_SPEED)
	])
	print("  em %.2fs: %d golpes; esperados ~%.2f" % [JANELA, observados, esperados])
	print("  quadros dos golpes: %s (um a cada %.1f)" % [
		str(_quadros_de_golpe), intervalo * por_segundo
	])

	# A janela começa com a cadência vencida, então cabem `floor(N)` ou
	# `floor(N)+1` golpes, e nada mais. A primeira versão dava uma folga de um
	# golpe para BAIXO também, e com isso um `advance_time(0.0)` — que faz o
	# personagem bater uma vez e travar para sempre — passava verde com 1
	# golpe onde se esperavam 2,66. Folga generosa é o mesmo que não conferir.
	var piso: int = maxi(int(floor(esperados)), 1)
	var teto: int = piso + 1
	if observados < piso or observados > teto:
		falhas.append(
			("em %.1fs saíram %d golpes e a cadência de %.3fs permite %d ou %d "
			+ "— o laço de ataque parou de respeitar a velocidade de ataque")
				% [JANELA, observados, intervalo, piso, teto]
		)

	# **E o espaçamento, que é o que fecha a classe.** Contagem certa com ritmo
	# errado é possível — dois golpes colados no começo e nada depois somam
	# dois. Conferir o intervalo ENTRE golpes não depende de enumerar os modos
	# de falha.
	var passo_esperado: float = intervalo * por_segundo
	for indice: int in range(1, _quadros_de_golpe.size()):
		var vao: int = _quadros_de_golpe[indice] - _quadros_de_golpe[indice - 1]
		if absf(float(vao) - passo_esperado) <= 1.5:
			continue
		falhas.append(
			("dois golpes seguidos saíram com %d quadros de intervalo, e a "
			+ "cadência de %.3fs pede %.1f") % [vao, intervalo, passo_esperado]
		)
		break

	# ------------------------------------------------- o reset, ponta a ponta
	#
	# Daqui para baixo é a mecânica da decisão 18 atravessando as três camadas:
	# `AbilityEngine` (core) zera o contador do `Unit` (core), e o laço de
	# `Player` (gameplay) enxerga isso no quadro seguinte. Nenhuma das duas
	# sondas anteriores via essa junta.
	var antes: int = _golpes
	AbilityEngine.cast(
		AbilityBook.new(), _habilidade(true),
		AbilityCast.on_self(unit), Combatant.all_units(self)
	)
	if not is_zero_approx(unit.attack_cooldown):
		falhas.append(
			"conjurar a habilidade que zera deixou a cadência em %.3fs"
				% unit.attack_cooldown
		)
	await physics_frame
	if _golpes == antes:
		falhas.append(
			"a habilidade zerou a cadência e mesmo assim nenhum golpe saiu no "
			+ "quadro seguinte — o laço de ataque não lê `attack_is_ready`"
		)

	# E o par que impede a conferência de cima de ser tautologia: sem o reset,
	# o quadro seguinte NÃO pode ter golpe. Se tivesse, o golpe de cima não
	# provaria nada sobre o reset.
	antes = _golpes
	AbilityEngine.cast(
		AbilityBook.new(), _habilidade(false),
		AbilityCast.on_self(unit), Combatant.all_units(self)
	)
	if is_zero_approx(unit.attack_cooldown):
		falhas.append(
			"a habilidade que NÃO zera deixou a cadência em zero mesmo assim"
		)
	await physics_frame
	if _golpes != antes:
		falhas.append(
			("saiu golpe no quadro seguinte a uma habilidade que não zera a "
			+ "cadência; o par de controle não distingue nada")
		)

	# ------------------------------------------- o gesto de caminhada
	#
	# O corpo tem que se MEXER enquanto anda, em vez de deslizar. Não foi
	# conferido quando entrou, e o usuário reportou que continuava parado —
	# escrever a animação e presumir que ela funciona é a mesma classe de
	# defeito que a sonda de conjuração existe para pegar.
	falhas.append_array(await _conferir_caminhada(jogador, meu))

	# ------------------------------------------- o gesto de conjuração
	#
	# O corpo tem que FAZER alguma coisa ao conjurar, e voltar ao repouso
	# depois. É a única conferência automática do gesto: as duas sondas
	# chamam `AbilityEngine.cast` direto, e o gesto pende de
	# `cast_attempted`, que só `_try_cast` emite — ou seja, sem apertar a
	# tecla de verdade ele não roda, e um erro nele passaria em silêncio.
	falhas.append_array(await _conferir_gesto(jogador, meu))

	return falhas

## O corpo se mexe enquanto ANDA.
func _conferir_caminhada(jogador: CharacterBody3D, meu: Combatant) -> Array[String]:
	var falhas: Array[String] = []
	var boneco: Boneco = null
	for filho: Node in jogador.get_children():
		if filho is Boneco:
			boneco = filho as Boneco
	if boneco == null:
		return ["a cena não tem Boneco"] as Array[String]

	# Solta o alvo e manda andar para longe. `_target` e `target_position` são
	# privados por convenção, não por linguagem.
	jogador.set("_target", null)
	jogador.set("target_position", jogador.global_position + Vector3(0.0, 0.0, -12.0))

	var com_membros: bool = boneco.tem_membros()
	# **Terceiro corpo possível: o de ESQUELETO.** Quique e bamboleio foram
	# escritos para uma malha sem osso; com esqueleto quem anda é o clipe, e
	# medir `position.y` do nó dá zero com a passada perfeita. O termo que serve
	# aos três é `Boneco.pontos()`, que devolve pontos no mundo.
	var com_esqueleto: bool = boneco.esqueleto() != null
	var base_y: float = boneco.position.y
	var repouso: Dictionary = {}
	for membro: Node3D in boneco.membros():
		repouso[membro] = membro.rotation

	# **Amplitude da OSCILAÇÃO, e não desvio do repouso.**
	#
	# A primeira versão media a distância até o repouso e ficava satisfeita com
	# a inclinação, que é CONSTANTE enquanto se anda: 10 graus dão 0,17 rad e
	# passavam por qualquer piso, mesmo com o quique zerado. Três mutações —
	# amplitude invisível, fase congelada, repouso não devolvido — passaram
	# verdes por causa disso. O que distingue animação de postura é a variação
	# ao longo do tempo.
	var andou: float = 0.0
	var mexidos: Dictionary = {}
	var comeco: Vector3 = jogador.global_position
	var min_y: float = INF
	var max_y: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	var amplitude_de_membro: float = 0.0
	var extremos: Dictionary = {}
	var caixa_min := PackedVector3Array()
	var caixa_max := PackedVector3Array()
	for _passo: int in 60:
		await physics_frame
		await process_frame
		andou = maxf(andou, jogador.global_position.distance_to(comeco))
		if com_esqueleto:
			# **Relativo ao corpo**, senão a translação de andar entraria na
			# conta e a conferência aprovaria um boneco rígido deslizando.
			var aqui: PackedVector3Array = boneco.pontos()
			for i in range(aqui.size()):
				var p: Vector3 = aqui[i] - jogador.global_position
				if i >= caixa_min.size():
					caixa_min.append(p)
					caixa_max.append(p)
				else:
					caixa_min[i] = caixa_min[i].min(p)
					caixa_max[i] = caixa_max[i].max(p)
		elif com_membros:
			for membro: Node3D in boneco.membros():
				var x: float = membro.rotation.x
				var par: Vector2 = extremos.get(membro.name, Vector2(INF, -INF))
				extremos[membro.name] = Vector2(minf(par.x, x), maxf(par.y, x))
				if membro.rotation.distance_to(repouso[membro]) > 0.01:
					mexidos[membro.name] = true
		else:
			min_y = minf(min_y, boneco.position.y)
			max_y = maxf(max_y, boneco.position.y)
			min_z = minf(min_z, boneco.rotation.z)
			max_z = maxf(max_z, boneco.rotation.z)
	for nome: String in extremos:
		var par: Vector2 = extremos[nome]
		amplitude_de_membro = maxf(amplitude_de_membro, par.y - par.x)

	# **Metro e radiano são conferidos SEPARADO.** Juntá-los num `maxf` faz o
	# maior mascarar o outro: com 7 graus de bamboleio (0,24 rad) o piso
	# passava mesmo com o quique reduzido a 4,5 cm, que é a amplitude
	# invisível que o usuário reportou. Foi o mesmo erro de unidade que já
	# tinha deixado a inclinação constante mascarar a oscilação inteira.
	var amplitude_de_osso: float = 0.0
	for i in range(caixa_min.size()):
		amplitude_de_osso = maxf(
			amplitude_de_osso, caixa_min[i].distance_to(caixa_max[i])
		)
	var quique: float = 0.0 if (com_membros or com_esqueleto) else max_y - min_y
	var balanco_lateral: float = 0.0 if (com_membros or com_esqueleto) else max_z - min_z
	var mexeu: float = quique
	if com_esqueleto:
		mexeu = amplitude_de_osso
	elif com_membros:
		mexeu = amplitude_de_membro
	print(("  gesto de caminhada: andou %.2f m, corpo %s, oscilação %.3f"
		+ ", quique %.3f m, balanço %.3f rad, %d membros")
		% [andou, _tipo_de_corpo(com_membros, com_esqueleto), mexeu,
		   quique, balanco_lateral, mexidos.size()])
	if andou < 0.5:
		return ["o personagem não andou (%.2f m); a conferência da caminhada "
			% andou + "não teve o que medir"] as Array[String]
	# **Um piso de amplitude, e não só "mexeu".** O primeiro valor que escrevi
	# dava 4,5 cm de quique num corpo de 1,8 m — 2,5%, invisível na tela. Uma
	# animação que a conferência aprova e o olho não vê não é animação.
	# 0,10 de AMPLITUDE é o piso do que se vê — 10 cm de quique num corpo de
	# 1,8 m, ou 6 graus de balanço. Abaixo disso o corpo se mexe no papel e não
	# na tela.
	if mexeu < 0.10:
		falhas.append(
			("andando %.2f m o corpo oscilou só %.4f: a caminhada não é "
			+ "visível") % [andou, mexeu]
		)
	# O balanço tem piso PRÓPRIO, e é o que impede um componente de cobrir o
	# outro. 0,06 rad ≈ 3,5 graus.
	if not com_membros and not com_esqueleto and balanco_lateral < 0.06:
		falhas.append(
			("o balanço lateral foi de só %.3f rad; sobe-e-desce sozinho lê "
			+ "como flutuação, não como passo") % balanco_lateral
		)
	if com_membros and mexidos.size() < 2:
		falhas.append(
			("a caminhada mexeu só %d membro(s); passada precisa de perna E "
			+ "braço") % mexidos.size()
		)

	# E o corpo tem que voltar ao lugar quando o personagem para.
	#
	# **Testado em VÁRIAS fases**, e não numa só: parando no fundo do quique o
	# `y` coincide com o repouso por acaso, e a conferência aprovava um
	# `_repousar` que não restaurava nada. Fixture degenerado — a mesma classe
	# que já custou rodadas na perseguição da âncora e na cadência.
	var pior_fora: float = 0.0
	for tentativa: int in 4:
		jogador.set(
			"target_position", jogador.global_position + Vector3(0.0, 0.0, -4.0)
		)
		# Passos diferentes a cada volta, para parar em fases diferentes.
		for _passo: int in 7 + tentativa * 3:
			await physics_frame
			await process_frame
		jogador.set("target_position", jogador.global_position)
		jogador.velocity = Vector3.ZERO
		for _passo: int in 10:
			await physics_frame
			await process_frame
		if not com_membros and not com_esqueleto:
			pior_fora = maxf(pior_fora, absf(boneco.position.y - base_y))
			pior_fora = maxf(pior_fora, absf(boneco.rotation.z))
	if pior_fora > 0.001:
		falhas.append(
			("parado, o corpo ficou %.3f fora do repouso da caminhada (pior "
			+ "de 4 fases)") % pior_fora
		)

	# **A ordem importa, e custou uma mutação escapando.** O gesto de
	# conjuração restaura a posição do corpo ao terminar, então conjurar ANTES
	# desta conferência mascarava um `_repousar` da caminhada que não
	# restaurava nada — uma conferência apagando o rastro que a outra procura.
	# **Conjurar ENQUANTO anda.** É o único jeito de ver as duas animações
	# disputando o mesmo corpo, e a conferência do gesto não alcança isso:
	# ela para o personagem antes, de propósito. Sem isto, a caminhada podia
	# largar o corpo inclinado no meio do golpe e ninguém veria.
	var caster_andando: AbilityCaster = null
	for filho: Node in jogador.get_children():
		if filho is AbilityCaster:
			caster_andando = filho as AbilityCaster
	if caster_andando != null:
		caster_andando.book.clear_cooldowns()
		meu.unit.mana.current = meu.unit.mana.maximum()
		caster_andando.call("_try_cast", AbilityBook.Slot.Q)
		var fora_do_lugar: float = 0.0
		for _passo: int in 40:
			await physics_frame
			await process_frame
			if not com_membros and not com_esqueleto:
				fora_do_lugar = maxf(fora_do_lugar, absf(boneco.rotation.z))
		# Enquanto o golpe corre, a caminhada não pode estar torcendo o corpo.
		if fora_do_lugar > 0.02:
			falhas.append(
				("conjurando em movimento, a caminhada continuou torcendo o "
				+ "corpo em %.3f rad") % fora_do_lugar
			)

	return falhas

## O corpo se mexe ao conjurar, e volta ao lugar depois.
func _conferir_gesto(jogador: CharacterBody3D, meu: Combatant) -> Array[String]:
	var falhas: Array[String] = []
	var caster: AbilityCaster = null
	var gesto: Node = null
	# **O personagem para antes**: a conferência anterior o deixou andando, e
	# a caminhada mexe o mesmo corpo que o gesto — as duas se atrapalhavam.
	jogador.set("target_position", jogador.global_position)
	jogador.velocity = Vector3.ZERO
	for _passo: int in 12:
		await physics_frame
		await process_frame

	var boneco: Boneco = null
	for filho: Node in jogador.get_children():
		if filho is AbilityCaster:
			caster = filho as AbilityCaster
		elif filho is Boneco:
			boneco = filho as Boneco
		elif filho.get_script() != null 				and filho.get_script().resource_path.ends_with("gesto_de_conjuracao.gd"):
			gesto = filho
	if caster == null or gesto == null or boneco == null:
		return ["a cena não tem AbilityCaster, GestoDeConjuracao ou Boneco"] as Array[String]

	# **O desvio é medido nos MEMBROS quando eles existem**, e não no corpo
	# inteiro: é justamente essa a diferença que o usuário pediu — braço
	# golpeando em vez de cápsula deslizando, e medir o corpo daria zero num
	# gesto perfeito de braço.
	#
	# Mas o corpo pode ser uma malha externa inteiriça (o andaime de
	# malha externa sem esqueleto), e aí o gesto move o corpo todo.
	# A sonda tem que passar nos DOIS casos: no repositório limpo há o boneco
	# de caixas, e na máquina de quem importou há a malha.
	var com_membros: bool = boneco.tem_membros()
	var com_esqueleto: bool = boneco.esqueleto() != null
	var repouso: Dictionary = {}
	for membro: Node3D in boneco.membros():
		repouso[membro] = membro.rotation
	var repouso_do_corpo := Transform3D(boneco.transform)
	# Recarga limpa e mana cheia: o que se confere é o gesto, não o custo.
	caster.book.clear_cooldowns()
	meu.unit.mana.current = meu.unit.mana.maximum()
	meu.unit.ultimate_charge.restore(meu.unit.ultimate_charge.maximum())

	# Aperta a tecla de verdade — é `_try_cast` que emite `cast_attempted`.
	# O status é conferido junto: um gesto que não sai porque a conjuração foi
	# RECUSADA é comportamento certo, e acusá-lo seria acusar o alvo errado.
	# **Array e não variável solta**: lambda em GDScript captura por VALOR, e
	# reatribuir de dentro não tem efeito nenhum lá fora. Está registrado em
	# `CLAUDE.md` entre as armadilhas já pagas, e eu caí nela de novo aqui —
	# a conferência acusou `INVALID` numa conjuração que dera `SUCCESS`.
	var visto: Array[int] = [CastResult.Status.INVALID]
	caster.cast_attempted.connect(
		func(_slot: AbilityBook.Slot, _pedida: Ability, r: CastResult) -> void:
			if r != null:
				visto[0] = int(r.status)
	)
	caster.call("_try_cast", AbilityBook.Slot.Q)
	var status: int = visto[0]
	if status != int(CastResult.Status.SUCCESS) 			and status != int(CastResult.Status.CASTING):
		return ["a conjuração da sonda do gesto foi recusada (%s); ela precisa "
			% CastResult.Status.keys()[status]
			+ "sair para o gesto ter o que conferir"] as Array[String]

	# **O desvio MÁXIMO ao longo do gesto, e não o do primeiro quadro.**
	# A antecipação começa em zero — é o que faz o gesto ter peso — e medir
	# logo no primeiro quadro dá desvio nulo com o gesto funcionando. Foi
	# exatamente o que esta conferência acusou na primeira execução.
	var maior: float = 0.0
	var mexidos: Dictionary = {}
	var antes := PackedVector3Array()
	for _passo: int in 90:
		await physics_frame
		await process_frame
		if com_esqueleto:
			var aqui: PackedVector3Array = boneco.pontos()
			for i in range(aqui.size()):
				var p: Vector3 = aqui[i] - jogador.global_position
				if i >= antes.size():
					antes.append(p)
				else:
					maior = maxf(maior, antes[i].distance_to(p))
		elif com_membros:
			for membro: Node3D in boneco.membros():
				var desvio: float = membro.rotation.distance_to(repouso[membro])
				if desvio > 0.01:
					mexidos[membro.name] = true
				maior = maxf(maior, desvio)
		else:
			maior = maxf(maior, boneco.position.distance_to(repouso_do_corpo.origin))
			maior = maxf(maior, boneco.scale.distance_to(repouso_do_corpo.basis.get_scale()))
			maior = maxf(maior, absf(boneco.rotation.y))
	if maior <= 0.01:
		falhas.append(
			"conjurar não mexeu o corpo em quadro nenhum: o gesto não disparou"
		)
	# **Pelo menos dois membros**, e é o que separa gesto de espasmo: um braço
	# sozinho subindo lê como falha de animação. Todos os cinco gestos movem
	# tronco ou perna junto com o braço. Só se aplica ao corpo articulado — a
	# malha externa não tem membro nenhum, e cobrá-la seria cobrar o que ela
	# não tem como fazer.
	if com_membros and mexidos.size() < 2:
		falhas.append(
			("o gesto mexeu só %d membro(s) (%s); um membro sozinho não lê "
			+ "como golpe") % [mexidos.size(), ", ".join(mexidos.keys())]
		)
	print("  gesto de conjuração: corpo %s, %d membros mexidos, desvio máximo %.2f"
		% [_tipo_de_corpo(com_membros, com_esqueleto), mexidos.size(), maior])
	if com_esqueleto:
		# O clipe leva o corpo para onde a animação quiser e a pose de repouso
		# volta pelo próprio `idle`; cobrar aqui a volta ao repouso seria cobrar
		# do esqueleto uma regra que era do gesto procedural.
		return falhas
	if com_membros:
		for membro: Node3D in boneco.membros():
			if membro.rotation.distance_to(repouso[membro]) > 0.001:
				falhas.append(
					"o membro `%s` não voltou ao repouso depois do gesto (%s)"
						% [membro.name, str(membro.rotation)]
				)
	elif boneco.position.distance_to(repouso_do_corpo.origin) > 0.001 			or absf(boneco.rotation.y) > 0.001:
		falhas.append(
			"o corpo não voltou ao repouso depois do gesto (%s)"
				% str(boneco.position)
		)
	return falhas

## Uma habilidade instantânea e inofensiva, zeradora ou não.
func _habilidade(zera: bool) -> Ability:
	var ability := Ability.new()
	ability.id = &"sonda_de_ritmo"
	ability.aim = Ability.Aim.SELF
	ability.cooldown = 0.0
	ability.resets_attack_cooldown = zera
	var pulse: AbilityPulse = ability.single_pulse()
	pulse.form = AbilityPulse.Form.CIRCLE
	pulse.radius = 1.0
	pulse.hits_self = true
	pulse.hits_enemies = false
	var cura := HealEffect.new()
	cura.recipient = AbilityEffect.Recipient.CASTER
	cura.base_heal = 1.0
	pulse.effects = [cura]
	return ability

func _achar_jogador(node: Node) -> CharacterBody3D:
	if node is CharacterBody3D and Combatant.of(node) != null:
		return node as CharacterBody3D
	for filho: Node in node.get_children():
		var achado: CharacterBody3D = _achar_jogador(filho)
		if achado != null:
			return achado
	return null

## O primeiro boneco hostil e vivo da cena. Varre o grupo dos combatentes, e
## por isso não recebe raiz nenhuma.
func _achar_boneco() -> Combatant:
	for unit_node: Node in get_nodes_in_group(Combatant.GROUP):
		var combatant := unit_node as Combatant
		if combatant == null or combatant.unit == null:
			continue
		if combatant.team != 0 and combatant.is_alive():
			return combatant
	return null


## Como chamar o corpo que a cena montou, para o relatório dizer qual foi.
func _tipo_de_corpo(com_membros: bool, com_esqueleto: bool) -> String:
	if com_esqueleto:
		return "com esqueleto (malha externa)"
	if com_membros:
		return "articulado"
	return "inteiriço (malha externa)"
