from pathlib import Path
root = Path(__file__).resolve().parents[1]
p = root / "src/battle/battle_engine.gd"
s = p.read_text(encoding="utf-8")
start = s.index('\t\t\tvar pressure := int(intent.get("pressure", 0))')
end = s.index('\t\t\tvar times :=', start)
body = s[start:end]
body = '\n'.join(line[2:] if line.startswith('\t\t') else line for line in body.split('\n'))
body = body.replace('ruleset_result.data', 'rules')
method = '''func intent_pressure(state: BattleState, task: Dictionary, rules: Dictionary = {}) -> int:
	if rules.is_empty():
		var loaded := _loaded_ruleset()
		if not loaded.ok:
			return 0
		rules = loaded.data
	var intent: Dictionary = task.get("intent_snapshot", {})
	var task_id := str(task.get("task_id", ""))
	var pressure_rules: Dictionary = rules.statuses.get("extra_requirements", {})
	var brainstorm_rules: Dictionary = rules.statuses.get("brainstorm", {})
''' + body + '\treturn pressure\n\n\n'
s = s[:start] + '\t\t\tvar pressure := intent_pressure(state, task, ruleset_result.data)\n' + s[end:]
s = s.replace('func _execute_intent_skill(', method + 'func _execute_intent_skill(', 1)
p.write_text(s, encoding="utf-8")
print("Intent preview and resolution now share the same calculation")
