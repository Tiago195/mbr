class_name StatusSet
extends RefCounted

## Controles de grupo ativos num combatente — Fase 3.1, ampliado na tradução
## do original (`docs/10-traducao-do-original.md`).
##
## Só os estados **booleanos** moram aqui. Lentidão (`slow`) NÃO é um deles:
## é um modificador percentual de `move_speed`, aplicado pelo mesmo sistema de
## `StatModifier` que os itens usam. `03-sistemas-de-jogo.md` é explícito sobre
## não construir um segundo sistema paralelo, e lentidão é literalmente um
## atributo reduzido por um tempo.
##
## O critério para um controle merecer um `Kind` próprio é **comportamento
## distinto**, não tema. O original tem 13 tipos em `crowd_control_xml`, e
## vários deles fazem a mesma coisa com nome diferente: `HardStun` e `Freeze`
## atordoam igual a `Stun`, `ThrowUp` e `Airborne` são o mesmo arremesso.
## Espelhar os 13 daria cinco caminhos para o mesmo `can_move() == false`, e
## cada regra de interação teria que lembrar dos cinco. A tabela de
## equivalência está no doc da tradução.

enum Kind {
	## Não anda, não ataca, não conjura.
	STUN,
	## Não anda. Ataca e conjura normalmente.
	ROOT,
	## Não conjura. Anda e ataca.
	SILENCE,
	## Não ataca. Anda e conjura.
	DISARM,

	# --- A partir daqui, o que a tradução do original exigiu ---------------
	# Valor novo entra no FIM: o `Kind` de `CrowdControlEffect` é exportado
	# para `.tres` como inteiro, e inserir no meio trocaria o controle de toda
	# habilidade já salva sem erro nenhum.

	## Ataca, mas o ataque básico erra. Diferente de DISARM: o personagem
	## continua atacando, gastando tempo e cadência, e não acerta.
	BLIND,

	## Perde o controle e anda na direção de quem aplicou. Não ataca, não
	## conjura. `Charmed` do original.
	CHARM,

	## Perde o controle do alvo: só consegue atacar quem provocou. Anda —
	## em direção ao provocador — e não conjura.
	TAUNT,

	## Arremessado ao ar. Faz tudo que STUN faz, e ainda assim é um estado
	## separado por dois motivos concretos: tenacidade normalmente não o
	## encurta, e ele acompanha um deslocamento vertical que a camada visual
	## precisa distinguir de um atordoamento em pé.
	AIRBORNE,

	## Vira outra coisa. Anda, não ataca e não conjura.
	POLYMORPH,

	## Não sofre dano nenhum. `IsInvincibility` e `DamageImmunity` do original.
	## Não é controle — é o oposto — mas mora aqui pelo mesmo motivo que os
	## outros: é um estado booleano com prazo, e o sistema de expiração já
	## existe. Um segundo relógio para um único estado seria a duplicação que
	## `03-sistemas-de-jogo.md` manda evitar.
	INVULNERABLE,
}

signal applied(kind: Kind, duration: float)
signal expired(kind: Kind)

## Controles que tiram o controle do personagem das mãos de quem joga.
## A camada de gameplay usa isto para saber quando ignorar a ordem de
## movimento em vez de tratar cada `Kind` na mão.
const LOSES_CONTROL: Array[Kind] = [
	Kind.STUN, Kind.AIRBORNE, Kind.CHARM, Kind.TAUNT,
]

var _remaining: Dictionary = {}

## Aplica um controle. Reaplicar não soma duração: prevalece a **maior
## restante**. É a convenção de MOBA — dois stuns de 1s seguidos não viram um
## de 2s, senão foco de time viraria prisão perpétua.
func apply(kind: Kind, duration: float) -> void:
	if duration <= 0.0:
		return
	var current: float = _remaining.get(kind, 0.0)
	if duration <= current:
		return
	_remaining[kind] = duration
	applied.emit(kind, duration)

func has(kind: Kind) -> bool:
	return _remaining.get(kind, 0.0) > 0.0

func remaining(kind: Kind) -> float:
	return _remaining.get(kind, 0.0)

func is_clear() -> bool:
	return _remaining.is_empty()

## Verdadeiro se QUALQUER um da lista está ativo. Evita encadear `has()` em
## toda regra de estado.
func has_any(kinds: Array[Kind]) -> bool:
	for kind: Kind in kinds:
		if has(kind):
			return true
	return false

func clear(kind: Kind) -> void:
	if _remaining.erase(kind):
		expired.emit(kind)

func clear_all() -> void:
	for kind: Kind in _remaining.keys():
		expired.emit(kind)
	_remaining.clear()

## Avança as durações. Devolve quantos expiraram.
func advance_time(delta: float) -> int:
	if _remaining.is_empty():
		return 0
	var done: Array = []
	for kind: Kind in _remaining:
		_remaining[kind] -= delta
		if _remaining[kind] <= 0.0:
			done.append(kind)
	for kind: Kind in done:
		_remaining.erase(kind)
		expired.emit(kind)
	return done.size()
