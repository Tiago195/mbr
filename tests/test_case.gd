class_name TestCase
extends RefCounted

## Arnês mínimo de teste unitário — Fase 2.
##
## A Godot não traz runner nativo. O GUT resolveria, mas é uma dependência
## externa e um addon a versionar; para lógica pura em RefCounted, descobrir
## métodos por reflexão e contar falhas cobre o caso. Se a suíte crescer a
## ponto de precisar de fixtures, mocks ou testes parametrizados, trocar por
## GUT é barato — os testes em si mudam pouco.
##
## Um teste é um método sem argumentos cujo nome começa com `test_`.

const EPSILON: float = 0.0001

var _failures: Array[String] = []
var _assertions: int = 0
var _current: StringName = &""

## Executa todos os métodos `test_` desta instância.
## Devolve { "suite": String, "tests": int, "assertions": int, "failures": Array }
func run() -> Dictionary:
	var seen: Dictionary = {}
	var count: int = 0
	for method: Dictionary in get_method_list():
		var method_name: StringName = method["name"]
		if not String(method_name).begins_with("test_"):
			continue
		if seen.has(method_name):
			continue
		seen[method_name] = true
		_current = method_name
		count += 1
		call(method_name)
	return {
		"suite": _suite_name(),
		"tests": count,
		"assertions": _assertions,
		"failures": _failures,
	}

func _suite_name() -> String:
	var script: Script = get_script() as Script
	if script == null:
		return "TestCase"
	return script.resource_path.get_file().get_basename()

# ---------------------------------------------------------------- asserções

func assert_true(condition: bool, message: String = "") -> void:
	_assertions += 1
	if not condition:
		_fail("esperava verdadeiro" if message.is_empty() else message)

func assert_false(condition: bool, message: String = "") -> void:
	assert_true(not condition, message if not message.is_empty() else "esperava falso")

func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	_assertions += 1
	if actual != expected:
		_fail("esperava %s, veio %s%s" % [expected, actual, _suffix(message)])

## Comparação de float. Usar sempre esta para resultado de fórmula — comparar
## float com `==` passa hoje e quebra quando alguém reordenar uma multiplicação.
func assert_almost_eq(
		actual: float,
		expected: float,
		message: String = "",
		epsilon: float = EPSILON
) -> void:
	_assertions += 1
	if absf(actual - expected) > epsilon:
		_fail("esperava %.6f, veio %.6f%s" % [expected, actual, _suffix(message)])

func assert_null(value: Variant, message: String = "") -> void:
	assert_true(value == null, message if not message.is_empty() else "esperava nulo")

func assert_not_null(value: Variant, message: String = "") -> void:
	assert_true(value != null, message if not message.is_empty() else "esperava não-nulo")

func _suffix(message: String) -> String:
	return "" if message.is_empty() else " (%s)" % message

func _fail(description: String) -> void:
	_failures.append("%s: %s" % [_current, description])
