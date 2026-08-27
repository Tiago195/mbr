class_name SpawnerDeMobs
extends Node3D

## Põe mobs na cena a partir do catálogo de atores.
##
## É o primeiro consumidor real de `AIPath`: `ActorProfile.ai_profile` estava
## guardado desde a tradução ("nada lê isto ainda; é o que a IA de mob vai
## consumir") e é aqui que ele vira comportamento — `playeraggressive` caça,
## qualquer outro perfil só revida.
##
## Mesmo desenho do `ChampionSelector`: carrega o catálogo uma vez no
## `_ready`, não decide regra de combate nenhuma, e escreve o perfil no
## `Combatant` de cada mob por `adopt_profile`.
##
## **Sempre `adopt_profile`, nunca `build_unit`.** Os mobs do original não
## declaram `attack_range`, e `Stat.DEFAULTS` também não o tem — um `Unit`
## montado só do perfil nasceria com alcance ZERO e nunca bateria em nada.
## `adopt_profile` usa os exports do Inspector do `Combatant` como piso
## (`combatant.gd`), e é esse piso que dá o alcance.

const CENA_DO_MOB: PackedScene = preload("res://scenes/mob.tscn")

## Qual ator do catálogo cada mob é. O padrão é um monstro simples do corpus:
## `playeraggressive`, com ataque básico e sem kit.
@export var actor_id: StringName = &"rc_actor_2000101"

## Nível dos mobs. Zero usa o `base_level` do perfil — os mobs do original
## nascem prontos num nível maior que 1, e é esse bloco que os atributos base
## descrevem.
@export var level: int = 0

## Onde spawnar quando não há `Marker3D` filhos. Com marcadores, são eles que
## mandam — dá para arrastar pontos no editor sem tocar neste array.
@export var posicoes: Array[Vector3] = [Vector3(8.0, 1.0, 8.0)]

## Segundos até renascer no mesmo ponto depois de morrer. <= 0 não renasce.
## Renascer é instância NOVA — ver o cabeçalho de `bot.gd`.
@export var respawn: float = 0.0

var _actors: ActorCatalog
var _profile: ActorProfile

func _ready() -> void:
	_actors = ActorCatalog.new()
	if not _actors.load_from():
		push_warning(
			"SpawnerDeMobs: sem data/traducao/atores.json — "
			+ "rode tools/traducao/traduzir.py"
		)
		return
	_profile = _actors.get_profile(actor_id)
	if _profile == null:
		push_warning("SpawnerDeMobs: ator `%s` não existe no catálogo." % actor_id)
		return
	for ponto: Vector3 in _pontos_de_spawn():
		_spawn(ponto)

func _pontos_de_spawn() -> Array[Vector3]:
	var pontos: Array[Vector3] = []
	for filho: Node in get_children():
		if filho is Marker3D:
			pontos.append((filho as Marker3D).global_position)
	if pontos.is_empty():
		for ponto: Vector3 in posicoes:
			pontos.append(ponto)
	return pontos

func _spawn(ponto: Vector3) -> void:
	var mob: Mob = CENA_DO_MOB.instantiate() as Mob
	if mob == null:
		return
	# A posição vai ANTES de `add_child`: o `_ready` do mob roda dentro do
	# `add_child` e é lá que ele captura a âncora do leash — posicionar depois
	# amarraria todo mob à origem do spawner.
	mob.position = to_local(ponto)
	add_child(mob)

	var combatente: Combatant = Combatant.of(mob)
	if combatente == null:
		push_warning("SpawnerDeMobs: a cena do mob veio sem Combatant.")
		return
	combatente.ensure_ready()
	var nivel: int = level if level > 0 else _profile.base_level
	combatente.adopt_profile(_profile, nivel)
	# AIPath vira comportamento aqui, pela primeira vez.
	mob.agressivo = _profile.ai_profile == &"playeraggressive"

	if respawn > 0.0:
		combatente.died.connect(_agendar_respawn.bind(ponto))

func _agendar_respawn(ponto: Vector3) -> void:
	get_tree().create_timer(respawn).timeout.connect(_spawn.bind(ponto))
