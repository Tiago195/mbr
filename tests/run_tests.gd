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
]

func _init() -> void:
	var total_tests: int = 0
	var total_assertions: int = 0
	var all_failures: Array[String] = []

	print("")
	for path: String in SUITES:
		var script: GDScript = load(path) as GDScript
		if script == null:
			all_failures.append("%s: não carregou" % path)
			continue

		var suite: TestCase = script.new() as TestCase
		if suite == null:
			all_failures.append("%s: não estende TestCase" % path)
			continue

		var report: Dictionary = suite.run()
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
