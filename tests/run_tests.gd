extends SceneTree

## Runner da suíte — Fase 2.
##
## Roda headless, sem abrir o editor nem a janela do jogo:
##
##     godot --headless --path . --script res://tests/run_tests.gd
##
## Sai com código 1 se algo falhar, para servir de portão em CI.

const SUITES: Array[String] = [
	"res://tests/test_stats.gd",
	"res://tests/test_damage.gd",
	"res://tests/test_mitigacao.gd",
	"res://tests/test_health.gd",
	"res://tests/test_effects.gd",
	"res://tests/test_efeitos_novos.gd",
	"res://tests/test_abilities.gd",
	"res://tests/test_pulsos.gd",
	"res://tests/test_projeteis.gd",
	"res://tests/test_telegrafia.gd",
	"res://tests/test_marcas_e_recarga.gd",
	"res://tests/test_catalogo_traduzido.gd",
	"res://tests/test_atores.gd",
	"res://tests/test_carga_de_suprema.gd",
	"res://tests/test_reset_de_ataque.gd",
	"res://tests/test_perseguicao.gd",
	"res://tests/test_zone.gd",
	"res://tests/test_inventory.gd",
	"res://tests/test_match.gd",
]

func _init() -> void:
	var total_tests: int = 0
	var total_assertions: int = 0
	var all_failures: Array[String] = []

	print("")
	for path: String in SUITES:
		# `_load_suite()` é função separada de propósito. Erro em tempo de
		# execução no GDScript aborta apenas a função onde ocorreu e devolve o
		# controle a quem chamou. Se o `new()` de um script com erro de sintaxe
		# fosse feito aqui dentro, o abort pularia o `quit()` lá embaixo — e
		# `SceneTree` headless sem `quit` roda para sempre. A suíte travava em
		# vez de falhar.
		var suite: TestCase = _load_suite(path)
		if suite == null:
			print("  [FALHOU] %s — não carregou (veja SCRIPT ERROR no console)" % path)
			all_failures.append("%s: não carregou" % path)
			continue

		var report: Variant = _run_suite(suite)
		if not report is Dictionary:
			print("  [FALHOU] %s — estourou durante a execução" % path)
			all_failures.append("%s: estourou durante a execução" % path)
			continue

		var failures: Array = report["failures"]
		total_tests += int(report["tests"])
		total_assertions += int(report["assertions"])

		var mark: String = "FALHOU" if not failures.is_empty() else "ok"
		print("  [%s] %s — %d testes, %d asserções" % [
			mark, report["suite"], report["tests"], report["assertions"]
		])
		for failure: String in failures:
			print("      x %s" % failure)
			all_failures.append("%s.%s" % [report["suite"], failure])

	print("")
	if all_failures.is_empty():
		print("  %d testes, %d asserções — tudo passou." % [
			total_tests, total_assertions
		])
		print("")
		quit(0)
		return

	print("  %d testes, %d asserções — %d FALHA(S)." % [
		total_tests, total_assertions, all_failures.size()
	])
	print("")
	quit(1)

## Devolve nulo se o script não carregar, não instanciar, ou estourar tentando.
func _load_suite(path: String) -> TestCase:
	var script: GDScript = load(path) as GDScript
	if script == null:
		return null
	return script.new() as TestCase

## Devolve nulo se a execução da suíte estourar no meio.
func _run_suite(suite: TestCase) -> Variant:
	return suite.run()
