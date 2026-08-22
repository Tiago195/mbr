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

## Quem recebe este efeito.
##
## Sem isto, "dash com escudo" — a terceira habilidade que
## `03-sistemas-de-jogo.md` sugere — seria inexpressável: o escudo cairia em
## quem a forma pegou, ou seja, no inimigo. Declarar o destinatário por efeito
## é o que permite uma habilidade só machucar quem está na frente e proteger
## quem a conjurou.
enum Recipient {
	## Cada combatente que a forma atingiu.
	TARGETS,
	## O conjurador, uma vez só, mesmo que a forma não pegue ninguém.
	CASTER,
}

@export var recipient: Recipient = Recipient.TARGETS

## Aplica o efeito a um combatente. Quem é esse combatente vem de `recipient`,
## e quem decide isso é a engine — não este método.
##
## Sobrescrever. A base não faz nada de propósito: efeito não implementado
## deve ser inofensivo, não estourar no meio de uma luta.
func apply(_cast: AbilityCast, _target: Unit) -> void:
	push_warning("AbilityEffect.apply() não sobrescrito em %s" % _script_name())

## Verdadeiro quando o efeito depende da forma ter pegado alguém. A engine usa
## isto para decidir se uma conjuração que não acertou ninguém é recusada ou
## sai assim mesmo — um dash não pode ser recusado por não acertar ninguém.
func needs_target() -> bool:
	return recipient == Recipient.TARGETS

## Texto curto para log de combate e para depuração.
func describe() -> String:
	return _script_name()

func _script_name() -> String:
	var script: Script = get_script() as Script
	if script == null:
		return "AbilityEffect"
	return script.resource_path.get_file().get_basename()
