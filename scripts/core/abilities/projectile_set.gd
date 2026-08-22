class_name ProjectileSet
extends RefCounted

## Projéteis em voo — a peça que faltava para "acertar" querer dizer alguma coisa.
##
## Até aqui um projétil resolvia a forma no instante do clique e a esfera na
## tela era enfeite. O comentário em `ability_caster.gd` admitia: *"o dano já
## saiu quando a esfera parte. É mentira visual"*. Isso torna mira irrelevante —
## quem estava na linha no milissegundo do clique levava dano mesmo saindo de
## lá, e quem entrou depois não levava nada.
##
## Aqui o projétil anda. A cada tique ele avança `projectile_speed * delta`, e
## quem estiver no caminho **daquele trecho** é atingido.
##
## Continua em `core/`: `RefCounted`, sem nó, sem física. É o que permite o
## servidor headless resolver o voo e o teste medir o tempo até o impacto.
##
## **O que ele NÃO faz, e é decisão:** parar em parede. `core/` não conhece
## colisor, e resolver isso exigiria a camada de gameplay devolver a resposta a
## cada tique. `ThroughObstacle` já é lacuna registrada do original; o projétil
## entra nela em vez de inventar meia solução.

## Um projétil no ar.
##
## Guarda o `cast` porque o efeito precisa saber quem lançou — dano escala com
## o atributo do conjurador. Guardar não cria ciclo: o `Unit` não conhece o
## livro de habilidades, então a referência só aponta para um lado.
class Projectile extends RefCounted:
	var ability: Ability
	var pulse: AbilityPulse
	var cast: AbilityCast
	## Onde está agora, no plano do chão.
	var position: Vector3 = Vector3.ZERO
	## Normalizada e achatada. Um projétil não sobe nem desce.
	var direction: Vector3 = Vector3.FORWARD
	## Quanto já voou. Compara com `pulse.length`, que é o alcance.
	var travelled: float = 0.0
	## Quem este projétil já atingiu. Sem isto, um projétil perfurante que
	## atravessa alguém devagar bate nele a cada tique.
	var hits: Array[Unit] = []
	## Acabou: acertou (sem perfurar) ou chegou ao fim do alcance.
	var spent: bool = false
	## Identidade estável. A camada visual segue a esfera por ela.
	var id: int = 0

	func remaining_range() -> float:
		return maxf(pulse.length - travelled, 0.0)

	func flight_time() -> float:
		return pulse.length / maxf(pulse.projectile_speed, 0.01)

## Um projétil acertando alguém, num tique.
class Impact extends RefCounted:
	var projectile: Projectile
	var targets: Array[Unit] = []

var _flying: Array[Projectile] = []
var _next_id: int = 1

# ---------------------------------------------------------------- lançar

## Põe um projétil no ar. Devolve-o, para quem quiser desenhá-lo.
##
## Direção achatada e normalizada aqui, uma vez: deixar isso para o passo do
## voo repetiria a conta 60 vezes por segundo e abriria espaço para um vetor
## nulo virar `NAN` no meio do caminho.
func launch(
		ability: Ability,
		pulse: AbilityPulse,
		cast: AbilityCast,
		origin: Vector3,
		direction: Vector3
) -> Projectile:
	if pulse == null or cast == null:
		return null
	var plana: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if plana.length_squared() <= 0.000001:
		# Sem direção não há voo. Cair no `Vector3.FORWARD` mandaria o projétil
		# para o norte do mundo, que é pior que não sair.
		return null

	var shot := Projectile.new()
	shot.ability = ability
	shot.pulse = pulse
	shot.cast = cast
	shot.position = Vector3(origin.x, 0.0, origin.z)
	shot.direction = plana.normalized()
	shot.id = _next_id
	_next_id += 1
	_flying.append(shot)
	return shot

# ---------------------------------------------------------------- voar

## Avança todos os projéteis e devolve os impactos deste tique.
##
## Quem chama aplica os efeitos. Este objeto resolve GEOMETRIA e nada mais —
## mesmo desenho de `AbilityShape`, e pelo mesmo motivo: separar quem decide de
## quem executa é o que deixa os dois testáveis sozinhos.
func advance_time(delta: float, candidates: Array) -> Array[Impact]:
	var impacts: Array[Impact] = []
	if _flying.is_empty() or delta <= 0.0:
		return impacts

	var kept: Array[Projectile] = []
	for shot: Projectile in _flying:
		var atingidos: Array[Unit] = _step(shot, delta, candidates)
		if not atingidos.is_empty():
			var impact := Impact.new()
			impact.projectile = shot
			impact.targets = atingidos
			impacts.append(impact)
		if not shot.spent:
			kept.append(shot)
	_flying = kept
	return impacts

## Um projétil, um tique. Devolve quem ele acertou no trecho percorrido.
func _step(shot: Projectile, delta: float, candidates: Array) -> Array[Unit]:
	var atingidos: Array[Unit] = []
	var restante: float = shot.remaining_range()
	if restante <= 0.0:
		shot.spent = true
		return atingidos

	# O passo é limitado pelo alcance que sobrou. Sem isso, um projétil rápido
	# passaria do alcance dentro do próprio tique e acertaria alguém que estava
	# fora dele.
	var passo: float = minf(
		maxf(shot.pulse.projectile_speed, 0.01) * delta, restante
	)
	var de: Vector3 = shot.position
	var para: Vector3 = de + shot.direction * passo

	# **Varredura, não amostra.** Testar só a posição final faria um projétil
	# rápido atravessar alvo estreito sem tocá-lo: a 25 m/s, um tique de 60 Hz
	# anda 0,42 m, e um alvo de meio metro cabe inteiro no meio do salto.
	# É o defeito clássico de projétil, e ele não dá erro nenhum — o tiro
	# simplesmente passa direto.
	var no_caminho: Array[Unit] = _sweep(shot, de, para, candidates)
	if no_caminho.is_empty():
		shot.position = para
		shot.travelled += passo
		if shot.remaining_range() <= 0.0:
			shot.spent = true
		return atingidos

	var teto: int = shot.pulse.effective_max_targets()
	for unit: Unit in no_caminho:
		if teto > 0 and shot.hits.size() >= teto:
			break
		shot.hits.append(unit)
		atingidos.append(unit)
		if not shot.pulse.pierces:
			break

	if not shot.pulse.pierces or (teto > 0 and shot.hits.size() >= teto):
		# Parou em quem acertou: a esfera na tela tem que morrer ali, e não no
		# fim do alcance.
		var ate: float = _along(atingidos[0].position, de, para).y
		shot.position = de + shot.direction * ate
		shot.travelled += ate
		shot.spent = true
		return atingidos

	shot.position = para
	shot.travelled += passo
	if shot.remaining_range() <= 0.0:
		shot.spent = true
	return atingidos

## Quem está a menos de meia largura do trecho `de -> para`, do mais próximo do
## início ao mais distante. Já filtrado por time e sem repetir quem levou.
func _sweep(
		shot: Projectile, de: Vector3, para: Vector3, candidates: Array
) -> Array[Unit]:
	var achados: Array[Unit] = []
	var distancias: Array[float] = []
	var meia_largura: float = maxf(shot.pulse.width, 0.1) * 0.5
	var caster: Unit = shot.cast.caster

	for candidate: Variant in candidates:
		var unit := candidate as Unit
		if unit == null or not unit.is_alive():
			continue
		if shot.hits.has(unit):
			continue
		if caster == null or not AbilityShape.accepts(shot.pulse, caster, unit):
			continue
		var medida: Vector2 = _along(unit.position, de, para)
		if medida.x > meia_largura:
			continue
		achados.append(unit)
		distancias.append(medida.y)

	# Ordenar por avanço ao longo do trecho, e não por distância à origem do
	# tiro: é quem o projétil encontra PRIMEIRO que para o voo.
	for i: int in range(1, achados.size()):
		var unit: Unit = achados[i]
		var chave: float = distancias[i]
		var j: int = i - 1
		while j >= 0 and distancias[j] > chave:
			achados[j + 1] = achados[j]
			distancias[j + 1] = distancias[j]
			j -= 1
		achados[j + 1] = unit
		distancias[j + 1] = chave
	return achados

## `Vector2(distância perpendicular, avanço ao longo do trecho)`.
##
## Devolve `Vector2` e não `Dictionary` de propósito: isto roda por candidato
## por projétil por tique, e um dicionário por chamada seria lixo alocado num
## laço quente para carregar dois floats.
static func _along(ponto: Vector3, de: Vector3, para: Vector3) -> Vector2:
	var eixo: Vector3 = _flat(para - de)
	var ao_alvo: Vector3 = _flat(ponto - de)
	var comprimento: float = eixo.length()
	if comprimento <= 0.000001:
		return Vector2(ao_alvo.length(), 0.0)
	var direcao: Vector3 = eixo / comprimento
	var avanco: float = clampf(ao_alvo.dot(direcao), 0.0, comprimento)
	return Vector2((ao_alvo - direcao * avanco).length(), avanco)

static func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)

# ---------------------------------------------------------------- consulta

func flying() -> Array[Projectile]:
	return _flying

func count() -> int:
	return _flying.size()

func is_empty() -> bool:
	return _flying.is_empty()

## Derruba tudo que está no ar. Devolve quantos caíram.
##
## **Não** é chamado quando o conjurador morre, e a omissão é a mesma decisão
## de `AbilityBook.interrupt()`: a flecha que já saiu do arco segue seu curso.
## Serve para fim de partida e para teste.
func clear() -> int:
	var quantos: int = _flying.size()
	_flying.clear()
	return quantos
