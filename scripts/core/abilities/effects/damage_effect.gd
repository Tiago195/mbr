class_name DamageEffect
extends AbilityEffect

## DAMAGE — dano com escalonamento por atributo.
##
## `base + atributo * proporção` é a forma canônica de MOBA: um valor fixo que
## domina cedo, mais uma fração de um atributo que domina tarde. Manter os dois
## separados é o que permite balancear início e fim de partida de forma
## independente.
##
## Os três campos abaixo do escalonamento vieram da tradução do original, e
## cada um existe porque uma coluna de `impact_xml` não cabia no que havia:
## `PhysicalAttackPerTargetMaxHp`, `MaxPhysicalDamageForMonster` e
## `SiegeDamage`.

@export var base_damage: float = 0.0

## De qual atributo do CONJURADOR o dano escala.
@export var scaling_stat: Stat.Id = Stat.Id.ABILITY_POWER

## Quanto do atributo entra. 0.6 = 60% do poder de habilidade.
@export var scaling_ratio: float = 0.0

@export var damage_type: Damage.Type = Damage.Type.MAGIC

@export_group("Escalonamento pelo alvo")
## Fração da vida MÁXIMA DO ALVO que entra no dano bruto. 0.05 = 5%.
##
## É o oposto do escalonamento normal: aquele lê o conjurador, este lê quem
## apanha. É o que faz uma habilidade continuar relevante contra um tanque de
## 4000 de vida — e o que exige o teto contra mob logo abaixo, senão farmar
## selva vira trivial.
@export_range(0.0, 1.0) var percent_of_target_max_health: float = 0.0

@export_group("Limites")
## Teto de dano quando o alvo é mob neutro. 0 = sem teto.
##
## O original tem essa coluna em 46 impactos, e o motivo é claro: sem ela,
## habilidade que escala com a vida do alvo transforma o mob de 5000 de vida
## na forma mais rápida de encher o bolso.
@export var monster_damage_cap: float = 0.0

## Contra que espécie de alvo este dano vale.
enum Restriction {
	## Qualquer um.
	ANY,
	## Só mob neutro.
	MONSTERS_ONLY,
	## Só estrutura. É o `SiegeDamage` do original — dano de cerco, que existe
	## separado justamente para uma habilidade poder derrubar porta sem ser
	## boa contra gente.
	STRUCTURES_ONLY,
	## Só campeão.
	CHAMPIONS_ONLY,
}

@export var restriction: Restriction = Restriction.ANY

func apply(cast: AbilityCast, target: Unit) -> void:
	if target == null or not target.is_alive():
		return
	if not _allows(target):
		return
	target.receive_damage(
		cast.caster, _raw_for(cast.caster, target), damage_type, Damage.Source.ABILITY
	)

func _allows(target: Unit) -> bool:
	match restriction:
		Restriction.MONSTERS_ONLY:
			return target.nature == Unit.Nature.MONSTER
		Restriction.STRUCTURES_ONLY:
			return target.nature == Unit.Nature.STRUCTURE
		Restriction.CHAMPIONS_ONLY:
			return target.nature == Unit.Nature.CHAMPION
		_:
			return true

## O teto entra sobre o dano BRUTO, antes de defesa e amplificação. É a leitura
## que casa com o original — lá a coluna vive no impacto, junto do
## escalonamento, e não no fim do cálculo. Também é a que faz sentido: um teto
## aplicado depois da armadura mudaria de valor conforme a build do mob.
func _raw_for(caster: Unit, target: Unit) -> float:
	var raw: float = base_damage
	if caster != null and scaling_ratio != 0.0:
		raw += caster.stats.get_value(scaling_stat) * scaling_ratio
	if percent_of_target_max_health != 0.0:
		raw += target.health.maximum() * percent_of_target_max_health
	if monster_damage_cap > 0.0 and target.nature == Unit.Nature.MONSTER:
		raw = minf(raw, monster_damage_cap)
	return raw

func describe() -> String:
	var parts: PackedStringArray = []
	if base_damage != 0.0 or scaling_ratio == 0.0:
		parts.append("%.0f" % base_damage)
	if scaling_ratio != 0.0:
		parts.append("%.0f%% de %s" % [
			scaling_ratio * 100.0, Stat.name_of(scaling_stat)
		])
	if percent_of_target_max_health != 0.0:
		parts.append("%.1f%% da vida do alvo" % (percent_of_target_max_health * 100.0))
	return "dano %s" % " + ".join(parts)
