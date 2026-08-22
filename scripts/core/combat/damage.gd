class_name Damage
extends RefCounted

## Cálculo de dano — Fase 2.2. Função pura: entra situação, sai número.
##
## Não toca em nó, não sorteia nada fora do RNG que recebe, não altera os
## `Stats` que recebe. O mesmo código roda no cliente e no servidor headless,
## que é o que impede as duas implementações de divergirem.
##
## Aplicar o resultado à vida do alvo é responsabilidade de quem chama —
## Fase 2.3.

enum Type {
	## Reduzido por `armor`.
	PHYSICAL,
	## Reduzido por `magic_resist`.
	MAGIC,
	## Ignora ambas as defesas.
	TRUE,
}

enum Source {
	## Ataque básico. Pode crititar, devolve `lifesteal`.
	BASIC_ATTACK,
	## Habilidade. Não critita por padrão, devolve `spell_vamp`.
	ABILITY,
	## Zona, queda, veneno de mapa. Sem crítico e sem cura de retorno.
	ENVIRONMENT,
}

## Resolve uma instância de dano.
##
## `attacker` pode ser nulo — é o caso do dano de zona, que não tem dono.
## `rng` só é usado para o sorteio de crítico; passar um RNG semeado torna a
## simulação reproduzível.
static func resolve(
		attacker: Stats,
		target: Stats,
		target_health: float,
		target_shield: float,
		raw_damage: float,
		type: Type,
		source: Source = Source.BASIC_ATTACK,
		rng: RandomNumberGenerator = null
) -> DamageResult:
	var result := DamageResult.new()
	result.raw_damage = raw_damage
	result.shield_after = target_shield
	result.health_after = target_health

	if raw_damage <= 0.0:
		return result

	var amount: float = raw_damage

	# --- 2. Crítico -------------------------------------------------------
	# Convenção fixada: só ataque básico critita. Habilidade que deva crititar
	# é exceção declarada no efeito, não regra geral. É a convenção do LoL, e
	# evita que todo escalonamento de habilidade tenha que ser balanceado
	# contra a variância do crítico.
	if attacker != null and source == Source.BASIC_ATTACK:
		var chance: float = attacker.get_value(Stat.Id.CRIT_CHANCE)
		if chance > 0.0:
			var roll: float = rng.randf() if rng != null else randf()
			if roll < chance:
				result.was_critical = true
				amount *= attacker.get_value(Stat.Id.CRIT_DAMAGE)

	# --- 3 e 4. Penetração e redução por defesa ---------------------------
	if type != Type.TRUE:
		var defense: float = _effective_defense(attacker, target, type)
		amount *= _defense_multiplier(defense)

	result.final_damage = amount

	# --- 6. Escudo primeiro, depois vida ----------------------------------
	var absorbed: float = minf(target_shield, amount)
	result.absorbed_by_shield = absorbed
	result.shield_after = target_shield - absorbed

	var to_health: float = amount - absorbed
	result.damage_to_health = to_health
	result.health_after = target_health - to_health
	result.killed = result.health_after <= 0.0

	# --- Roubo de vida ----------------------------------------------------
	# Incide sobre o dano final pós-mitigação, INCLUSIVE a parte comida pelo
	# escudo. `03-sistemas-de-jogo.md` diz "sobre o dano final aplicado, não
	# sobre o bruto" — o contraste que ele estabelece é com o bruto, e a
	# convenção de MOBA é que bater num escudo ainda cura.
	result.lifesteal_healed = _lifesteal_for(attacker, source, amount)

	return result

## Defesa que sobra depois da penetração do atacante.
## Percentual primeiro, flat depois, sem descer abaixo de zero — a ordem
## importa e é a convenção usual.
static func _effective_defense(attacker: Stats, target: Stats, type: Type) -> float:
	var defense: float
	var pen_percent: float = 0.0
	var pen_flat: float = 0.0

	if type == Type.PHYSICAL:
		defense = target.get_value(Stat.Id.ARMOR)
		if attacker != null:
			pen_percent = attacker.get_value(Stat.Id.ARMOR_PEN_PERCENT)
			pen_flat = attacker.get_value(Stat.Id.ARMOR_PEN_FLAT)
	else:
		defense = target.get_value(Stat.Id.MAGIC_RESIST)
		if attacker != null:
			pen_percent = attacker.get_value(Stat.Id.MAGIC_PEN_PERCENT)
			pen_flat = attacker.get_value(Stat.Id.MAGIC_PEN_FLAT)

	# Penetração não transforma defesa positiva em negativa.
	if defense <= 0.0:
		return defense
	return maxf(0.0, defense * (1.0 - pen_percent) - pen_flat)

## Retornos decrescentes, sem nunca chegar a imunidade.
## Defesa negativa — possível com redução de armadura — amplifica o dano, mas
## também com retornos decrescentes, em vez de explodir.
static func _defense_multiplier(defense: float) -> float:
	if defense >= 0.0:
		return 100.0 / (100.0 + defense)
	return 2.0 - 100.0 / (100.0 - defense)

static func _lifesteal_for(attacker: Stats, source: Source, dealt: float) -> float:
	if attacker == null:
		return 0.0
	match source:
		Source.BASIC_ATTACK:
			return dealt * attacker.get_value(Stat.Id.LIFESTEAL)
		Source.ABILITY:
			return dealt * attacker.get_value(Stat.Id.SPELL_VAMP)
		_:
			return 0.0
