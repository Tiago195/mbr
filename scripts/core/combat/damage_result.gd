class_name DamageResult
extends RefCounted

## O que saiu de uma resolução de dano — Fase 2.2.
##
## Carrega o suficiente para a camada visual desenhar (número flutuante, cor de
## crítico, estilhaço de escudo) sem precisar recalcular nada, e para a rede
## transmitir o resultado em vez da fórmula.

## Dano bruto que entrou, antes de qualquer etapa.
var raw_damage: float = 0.0

## Depois de crítico e de mitigação por defesa, antes do escudo.
## É sobre este valor que roubo de vida incide.
var final_damage: float = 0.0

## Quanto o escudo comeu.
var absorbed_by_shield: float = 0.0

## Quanto efetivamente saiu da vida.
var damage_to_health: float = 0.0

var shield_after: float = 0.0
var health_after: float = 0.0

var was_critical: bool = false
var killed: bool = false

## Cura devolvida ao atacante por roubo de vida ou spell vamp.
var lifesteal_healed: float = 0.0

func _to_string() -> String:
	var crit: String = " CRIT" if was_critical else ""
	var kill: String = " KILL" if killed else ""
	return "DamageResult(%.1f -> %.1f%s, escudo %.1f, vida %.1f%s)" % [
		raw_damage, final_damage, crit, absorbed_by_shield, health_after, kill
	]
