from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected exactly one match, found {count}: {old!r}')
    p.write_text(text.replace(old, new, 1))

# The actual issue #4 behavior change: reactive tank-enmity recovery outranks
# routine configured tank JAs. DPS configured JAs remain at their existing band.
replace_once('uc_provider_tank_enmity.lua', '\t\tlocal prio = 96\n', '\t\tlocal prio = 99\n')
replace_once('uc_provider_combat.lua', 'local priority_band = tank_mode and 99 or 70', 'local priority_band = tank_mode and 96 or 70')

# Update the focused starvation/ordering regression to encode the corrected order.
p = Path('tests/replay/harness/selftest_tank_configured_ja_starvation.lua')
text = p.read_text()
repls = {
    'local ordered = collect_ordered_abilities(ctx.settings, 6)': "local ordered = require('uc_run_ownership').filter_generic_abilities(",
    'local priority_band = tank_mode and 99 or 70': 'local priority_band = tank_mode and 96 or 70',
    "'tank-mode configured JAs must use the safer higher band without changing DPS baseline'": "'tank-mode configured JAs must stay below reactive tank-enmity recovery without changing DPS baseline'",
    'local prio = 96': 'local prio = 99',
    "'tank-enmity lane must keep the higher tank priority band'": "'tank-enmity lane must outrank routine tank configured JAs'",
    'priority_band = 99,\n        urgency = 0.35,': 'priority_band = 96,\n        urgency = 0.35,',
    'priority_band = 96,\n        urgency = 0.60,': 'priority_band = 99,\n        urgency = 0.60,',
    'priority_band = 96,\n        urgency = 0.95,': 'priority_band = 99,\n        urgency = 0.95,',
    "assert_true(score(tank_configured_ja) > score(low_urgency_tank_enmity), 'tank-mode configured JAs must outrank low-urgency tank-enmity actions')": "assert_true(score(low_urgency_tank_enmity) > score(tank_configured_ja), 'tank-enmity recovery must outrank routine tank-mode configured JAs')",
    "assert_true(score(urgent_tank_enmity) > score(tank_configured_ja), 'urgent tank-enmity actions must still outrank tank-mode configured JAs')": "assert_true(score(urgent_tank_enmity) > score(tank_configured_ja), 'urgent tank-enmity actions must outrank tank-mode configured JAs')",
}
for old, new in repls.items():
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'selftest_tank_configured_ja_starvation.lua: expected one match for {old!r}, found {count}')
    text = text.replace(old, new, 1)
p.write_text(text)

# Provider contract regression.
replace_once(
    'tests/replay/harness/selftest_scheduler_providers_phase3.lua',
    'assert_equal(proposal.priority_band, 96, "tank priority")',
    'assert_equal(proposal.priority_band, 99, "tank priority")',
)

# Keep the live tracker accurate now that #3 passed in-game and #4 is implemented.
p = Path('docs/zerde_uc_issue_tracker.md')
text = p.read_text()
text = text.replace(
    '| 3 | RUN Foil dispatch + no-TP RUN mode | READY FOR REVIEW | Fixes Foil self-spell dispatch, corrects Gambit/Rayke engagement semantics, and adds optional engaged-facing-away no-TP mode. |',
    '| 3 | RUN Foil dispatch + no-TP RUN mode | COMPLETE | In-game validation passed: Foil, Gambit, Rayke, and engaged-facing-away back-tanking all worked as intended. |',
    1,
)
text = text.replace(
    '| 4 | Tank enmity priority inversion | OPEN | Reactive tank enmity recovery is priority 96 while generic configured tank JAs are priority 99. |',
    '| 4 | Tank enmity priority inversion | READY FOR REVIEW | Reactive tank enmity recovery is now priority 99; routine tank-mode configured JAs are priority 96; DPS configured JAs remain 70. |',
    1,
)
text = text.replace('## 4. Tank enmity priority inversion\n\n### Problem', '## 4. Tank enmity priority inversion\n\n### Status\n\n**READY FOR REVIEW**\n\n### Problem', 1)
text = text.replace(
    'Reactive tank enmity recovery currently runs at priority band 96 while generic configured tank JAs in tank mode run at priority band 99. This lets routine configured JAs outrank a detected hate-loss recovery.',
    'Reactive tank enmity recovery ran at priority band 96 while generic configured tank JAs in tank mode ran at priority band 99. This let routine configured JAs outrank a detected hate-loss recovery.',
    1,
)
needle = '### Acceptance criteria\n\n- A ready Flash/Provoke-style recovery wins over a routine configured tank JA when both are eligible.'
replacement = '### Fix\n\nSwap only the two tank priority bands: reactive tank-enmity recovery `96 -> 99`, routine tank-mode configured JAs `99 -> 96`. Non-tank configured JAs remain at 70. No scheduler arbitration mechanics change.\n\n### Acceptance criteria\n\n- A ready Flash/Provoke-style recovery wins over a routine configured tank JA when both are eligible.'
if needle not in text:
    raise SystemExit('tracker #4 acceptance anchor not found')
text = text.replace(needle, replacement, 1)
p.write_text(text)

# Update the focused diagnostic, but keep historical T3.6 discussion intact except
# for the statements describing the current intended ordering.
p = Path('docs/tank_configured_ja_starvation_diagnostic.md')
text = p.read_text()
text = text.replace('tank-enmity lane uses `priority_band = 96`', 'tank-enmity lane uses `priority_band = 99`')
text = text.replace('tank-mode configured JAs to `priority_band = 99`', 'tank-mode configured JAs to `priority_band = 96`')
p.write_text(text)

print('Zerde issue #4 priority patch applied')
