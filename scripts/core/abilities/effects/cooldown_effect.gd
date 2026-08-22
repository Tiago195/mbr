class_name CooldownEffect
extends AbilityEffect

## RECARGA — encurta (ou estende) a recarga de habilidades.
##
## **21 buffs** do original o declaram, por `AdjustCDSkillIds` + `AdjustCDTime`:
## acertar a habilidade tal reduz 2 segundos da investida. O efeito sai 104
## vezes na tradução, porque vários desses buffs são referenciados por mais de
## uma habilidade.
##
## É um dos laços de decisão mais fortes que o original tem, e sem esta peça ele
## desaparecia inteiro na tradução.
##
## **Pede, não executa.** O `AbilityBook` não mora no `Unit` — é decisão da
## Fase 3.2, e por bom motivo: mob e estrutura têm vida e atributos sem ter
## livro de habilidades. Então o efeito enfileira o pedido em
## `Unit.pending_cooldown_adjustments` e quem tem o livro atende. É o mesmo
## contrato do deslocamento e da invocação, e a razão é a mesma: `core/` não
## alcança o que não possui.

## Que habilidades o ajuste alcança. Vazio = todas.
##
## O valor é `Ability.group_id`, não `id`: um ajuste que citasse o id atingiria
## um ranque só, e ninguém quer "reduz a recarga do seu Q, mas só no nível 3".
@export var group_ids: Array[StringName] = []

## Segundos. Negativo encurta — que é o caso usual.
@export var seconds: float = -1.0

## Se verdadeiro, `seconds` é lido como FRAÇÃO da recarga total em vez de
## segundos absolutos. -0.5 devolve metade. Existe porque reduzir 2 segundos
## de uma habilidade de 4 e de uma de 40 são coisas muito diferentes.
@export var proportional: bool = false

func apply(_cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive() or seconds == 0.0:
		return
	var pedido := Unit.CooldownRequest.new()
	pedido.group_ids = group_ids
	pedido.seconds = seconds
	pedido.proportional = proportional
	target.pending_cooldown_adjustments.append(pedido)

func describe() -> String:
	var alcance: String = "todas" if group_ids.is_empty() \
		else ", ".join(PackedStringArray(group_ids))
	if proportional:
		return "recarga %+.0f%% (%s)" % [seconds * 100.0, alcance]
	return "recarga %+.1fs (%s)" % [seconds, alcance]
