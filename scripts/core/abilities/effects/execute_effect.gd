class_name ExecuteEffect
extends AbilityEffect

## EXECUÇÃO — mata na hora quem está abaixo de um limiar de vida.
##
## O original tem `ImpactStatType: Die` em 22 impactos, sem valor nenhum: mata
## e pronto. Expressar isso como "dano de 999999" quase funciona e erra em
## dois lugares que importam: escudo absorveria, e resistência a dano
## reduziria. Execução não é dano grande, é uma regra diferente.
##
## O limiar transforma a mesma peça em duas mecânicas: 1.0 é o `Die` do
## original (mata sempre), e 0.2 é o remate clássico de MOBA — só fecha quem
## já está caindo, o que dá contrajogo a quem recua.

## Fração da vida máxima abaixo da qual o alvo morre. 1.0 mata sempre.
@export_range(0.0, 1.0) var health_threshold: float = 1.0

## Se ignora escudo. Ligado por padrão: um alvo com 5 de vida e 400 de escudo
## não está "caindo", e executá-lo passaria por cima da defesa que ele montou.
## Desligar faz a execução olhar só a barra vermelha.
@export var respects_shield: bool = true

## Se pode executar campeão. Desligado é o modo "remate de mob": limpa selva
## sem virar um botão de matar jogador, que é como o original usa a maioria
## dos `Die`.
@export var affects_champions: bool = true

func apply(cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive() or target.is_invulnerable():
		return
	if not affects_champions and target.nature == Unit.Nature.CHAMPION:
		return
	if respects_shield and target.health.shield > 0.0:
		return
	if target.health.fraction() > health_threshold:
		return

	# O golpe sai como dano VERDADEIRO do tamanho exato da vida restante, e
	# não como uma atribuição direta a `health.current`. É o que faz a morte
	# passar pelos mesmos caminhos de sempre: o sinal `died`, o gatilho de
	# abate de quem executou, a contabilidade da partida. Zerar a vida na mão
	# mataria o alvo sem ninguém ficar sabendo.
	target.receive_damage(
		cast.caster, target.health.current, Damage.Type.TRUE, Damage.Source.ABILITY
	)

func describe() -> String:
	if health_threshold >= 1.0:
		return "execução"
	return "executa abaixo de %.0f%% de vida" % (health_threshold * 100.0)
