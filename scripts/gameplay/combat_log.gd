class_name CombatLog
extends Node

## O que acabou de acontecer, escrito na tela.
##
## Existe por um veredito do usuário, em 23/08/2026: *"não consigo testar, não
## sei se estou usando a mesma habilidade ou se são habilidades diferentes,
## tudo que vejo são formas"*.
##
## O diagnóstico é exato, e a causa não é falta de arte: é que a tela não
## dizia nada. `AbilityCaster._report` já contava tudo — **no console**, que
## quem está jogando não vê. Isto é o mesmo relato, no lugar onde ele serve.
##
## O que cada linha responde, e por que:
##
## - **Qual espaço** (Q/W/E/R), porque quatro formas parecidas na tela não
##   dizem qual tecla as fez sair
## - **Qual habilidade**, pelo nome do corpus, porque é o que distingue uma
##   conjuração da seguinte
## - **Se veio da corrente de combo**, porque é literalmente impossível de ver:
##   a habilidade é OUTRA e nada na tela avisa
## - **O que aconteceu** — acertou quantos, quanto de dano, ou por que foi
##   recusada
##
## É camada visual pura: observa sinais e desenha, nunca decide. Mesmo
## princípio de `CombatFeedback`.

## Quantas linhas ficam na tela.
@export var linhas_visiveis: int = 9

## Segundos até uma linha sumir. Zero = não somem.
@export var vida_da_linha: float = 12.0

@export_group("Cores")
## Uma cor por espaço, e é a metade visual da resposta: com Q, W, E e R
## saindo todos laranja, "é a mesma habilidade?" não tinha como ser
## respondido olhando.
@export var cor_q: Color = Color(0.45, 0.70, 1.00)
@export var cor_w: Color = Color(0.55, 0.95, 0.60)
@export var cor_e: Color = Color(1.00, 0.85, 0.35)
@export var cor_r: Color = Color(1.00, 0.45, 0.45)
@export var cor_combo: Color = Color(0.95, 0.55, 1.00)
@export var cor_recusa: Color = Color(0.70, 0.70, 0.72)

var _caster: AbilityCaster
var _rotulo: RichTextLabel
var _linhas: Array[Dictionary] = []

func _ready() -> void:
	_caster = _achar_caster()
	if _caster == null:
		push_warning("CombatLog sem AbilityCaster irmão em '%s'." % get_parent().name)
		return
	_caster.cast_attempted.connect(_ao_conjurar)
	_montar_hud()
	# O dano de TODO combatente da cena, e não só o de quem eu bato: levar
	# porrada também é informação, e é a única maneira de ver um mob revidando
	# quando houver mob que revide.
	for node: Node in get_tree().get_nodes_in_group(Combatant.GROUP):
		var combatant := node as Combatant
		if combatant != null:
			combatant.damaged.connect(_ao_causar_dano.bind(combatant))

func _process(delta: float) -> void:
	if vida_da_linha <= 0.0 or _linhas.is_empty():
		return
	var mudou: bool = false
	for linha: Dictionary in _linhas:
		linha["restante"] = float(linha["restante"]) - delta
	while not _linhas.is_empty() and float(_linhas[0]["restante"]) <= 0.0:
		_linhas.remove_at(0)
		mudou = true
	if mudou:
		_redesenhar()

# ---------------------------------------------------------------- eventos

func _ao_conjurar(
		slot: AbilityBook.Slot, pedida: Ability, result: CastResult
) -> void:
	var tecla: String = AbilityBook.Slot.keys()[slot]
	if pedida == null:
		_escrever(cor_recusa, "%s  —  espaço vazio" % tecla)
		return
	if result == null:
		return

	# **A troca da corrente é o que mais precisa aparecer.** Quando o combo
	# entrega outro elo, o que sai é uma habilidade DIFERENTE, com outro dano e
	# outra forma, e nada na tela avisava. Comparar o que foi pedido com o que
	# saiu é a única maneira de o jogador saber que apertou no tempo certo.
	var saiu: Ability = result.ability
	var virou_combo: bool = saiu != null and saiu.id != pedida.id
	var cor: Color = cor_combo if virou_combo else _cor_do_espaco(slot)
	var cabeca: String = "%s ▸ COMBO" % tecla if virou_combo else tecla
	var nome: String = saiu.display_name if saiu != null else pedida.display_name

	match result.status:
		CastResult.Status.SUCCESS:
			var desfecho: String
			if result.in_flight():
				desfecho = "%d projétil(is) no ar" % result.launched
			elif result.targets.is_empty():
				desfecho = "não pegou ninguém"
			else:
				desfecho = "%d alvo(s)" % result.targets.size()
			_escrever(cor, "%s  %s  →  %s" % [cabeca, nome, desfecho])
		CastResult.Status.CASTING:
			_escrever(cor, "%s  %s  →  conjurando…" % [cabeca, nome])
		CastResult.Status.ON_COOLDOWN:
			_escrever(cor_recusa, "%s  %s  ✕  recarga %.1fs" % [
				tecla, nome, result.cooldown_remaining
			])
		CastResult.Status.NO_CHARGE:
			_escrever(cor_recusa, "%s  %s  ✕  falta %.0f de carga" % [
				tecla, nome, result.charge_missing
			])
		_:
			_escrever(cor_recusa, "%s  %s  ✕  %s" % [
				tecla, nome, _motivo(result.status)
			])

func _ao_causar_dano(dano: DamageResult, alvo: Combatant) -> void:
	if dano == null or alvo == null:
		return
	if dano.missed:
		_escrever(cor_recusa, "        errou em %s" % alvo.body().name)
		return
	if dano.damage_to_health <= 0.0 and dano.absorbed_by_shield <= 0.0:
		return
	var texto: String = "        −%.0f em %s" % [
		dano.damage_to_health + dano.absorbed_by_shield, alvo.body().name
	]
	if dano.was_critical:
		texto += "  CRÍTICO"
	if dano.killed:
		texto += "  MORREU"
	_escrever(Color(1.0, 0.92, 0.80), texto)

# ---------------------------------------------------------------- desenho

func _escrever(cor: Color, texto: String) -> void:
	_linhas.append({"cor": cor, "texto": texto, "restante": vida_da_linha})
	while _linhas.size() > linhas_visiveis:
		_linhas.remove_at(0)
	_redesenhar()

func _redesenhar() -> void:
	if _rotulo == null:
		return
	var partes: PackedStringArray = []
	for linha: Dictionary in _linhas:
		partes.append("[color=#%s]%s[/color]" % [
			(linha["cor"] as Color).to_html(false), linha["texto"]
		])
	_rotulo.text = "\n".join(partes)

func _cor_do_espaco(slot: AbilityBook.Slot) -> Color:
	match slot:
		AbilityBook.Slot.Q: return cor_q
		AbilityBook.Slot.W: return cor_w
		AbilityBook.Slot.E: return cor_e
		_: return cor_r

## O motivo da recusa em palavras. `match` explícito e não uma tabela: assim,
## quando alguém acrescentar um status novo ao enum, o compilador não deixa
## esquecer deste lugar.
static func _motivo(status: CastResult.Status) -> String:
	match status:
		CastResult.Status.NO_RESOURCE: return "sem mana"
		CastResult.Status.OUT_OF_RANGE: return "longe demais"
		CastResult.Status.NO_TARGET: return "sem alvo"
		CastResult.Status.CANNOT_CAST: return "sob controle de grupo"
		CastResult.Status.BUSY: return "conjurando outra"
		CastResult.Status.DEAD: return "morto"
		CastResult.Status.INVALID: return "inválida"
		_: return "recusada"

func _montar_hud() -> void:
	var camada := CanvasLayer.new()
	camada.name = "CombatLogHUD"
	add_child(camada)

	var fundo := ColorRect.new()
	fundo.color = Color(0.0, 0.0, 0.0, 0.55)
	fundo.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	fundo.offset_left = 8.0
	fundo.offset_top = -206.0
	fundo.offset_bottom = -8.0
	fundo.offset_right = 468.0
	# Sem isto o retângulo come o clique do botão direito e o personagem para
	# de andar quando o cursor passa por cima — já aconteceu com o painel do
	# campeão.
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(fundo)

	_rotulo = RichTextLabel.new()
	_rotulo.bbcode_enabled = true
	_rotulo.scroll_active = false
	_rotulo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rotulo.offset_left = 10.0
	_rotulo.offset_top = 6.0
	_rotulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fundo.add_child(_rotulo)

func _achar_caster() -> AbilityCaster:
	var host: Node = get_parent()
	if host == null:
		return null
	for child: Node in host.get_children():
		if child is AbilityCaster:
			return child
	return null
