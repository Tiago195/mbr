class_name AbilityEffect
extends Resource

## Peça do vocabulário de efeitos — Fase 3.1.
##
## Estende `Resource`, não `RefCounted`, para poder ser salvo em `.tres` e
## editado no Inspector. É o que permite uma habilidade ser **declarada** em
## arquivo em vez de programada (decisão 9 em `docs/02-decisoes-tecnicas.md`).
## `Resource` não é nó: continua rodando headless e em teste.
##
## A regra do projeto: habilidade nova NÃO escreve classe nova. Só um efeito
## genuinamente inédito entra aqui — e quando entra, passa a fazer parte do
## vocabulário para todas as habilidades seguintes.

## Aplica o efeito a um alvo. `target` pode ser o próprio conjurador.
##
## Sobrescrever. A base não faz nada de propósito: efeito não implementado
## deve ser inofensivo, não estourar no meio de uma luta.
func apply(_cast: AbilityCast, _target: Unit) -> void:
	push_warning("AbilityEffect.apply() não sobrescrito em %s" % _script_name())

## Falso para efeitos que agem no ponto do chão em vez de num combatente —
## invocação, armadilha. A engine usa isto para não descartar a conjuração
## quando a forma não pegou ninguém.
func needs_target() -> bool:
	return true

## Texto curto para log de combate e para depuração.
func describe() -> String:
	return _script_name()

func _script_name() -> String:
	var script: Script = get_script() as Script
	if script == null:
		return "AbilityEffect"
	return script.resource_path.get_file().get_basename()
