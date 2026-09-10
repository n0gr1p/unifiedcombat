from pathlib import Path

path = Path('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')
text = path.read_text()

old = 'response == "move_to_range" || response == "use_action"))'
new = 'response == "move_to_range" || response == "use_action" || response == "use_sequence"))'
if text.count(old) != 1:
    raise SystemExit(f'expected one response validation anchor, found {text.count(old)}')
text = text.replace(old, new, 1)

start = text.find('            else if (response == "use_action")\n')
if start < 0:
    raise SystemExit('use_action branch not found')
marker = '            list.Add(serialized);\n'
insert_at = text.find(marker, start)
if insert_at < 0:
    raise SystemExit('reaction list append not found')

block = '''            else if (response == "use_sequence")
            {
                var sequence = ReactionSequenceProfileCodec.ParseRule(rule);
                var steps = new List<object?>(sequence.Steps.Count);
                foreach (var step in sequence.Steps)
                {
                    steps.Add(
                        new StructuredProfileNode()
                            .Add("action_type", step.ActionType)
                            .Add("action_name", step.ActionName)
                            .Add("target", step.Target)
                            .Add("optional", step.Optional)
                    );
                }
                serialized.Add("steps", steps);
            }
'''

path.write_text(text[:insert_at] + block + text[insert_at:])
