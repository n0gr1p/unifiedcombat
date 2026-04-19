# One-off transform: wraps copied DD2.lua into return { ... } module (run from repo if needed).
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
src = (ROOT / "dd2_engine.lua").read_text(encoding="utf-8", errors="replace")

# Strip _addon block
src = re.sub(
    r"_addon\.name = 'DD2'.*?_addon\.commands = \{ 'DD2' \}\s*\n",
    "",
    src,
    count=1,
    flags=re.DOTALL,
)

# Remove default table (first occurrence through local settings = config.load)
start = src.find("local default = {}")
end = src.find("local settings = config.load(default)")
if start != -1 and end != -1:
    src = src[:start] + src[end:]

# Replace config.load with UC_SETTINGS proxy
src = src.replace(
    "local settings = config.load(default)",
    """local settings = setmetatable({}, {
    __index = function(_, k) return _G.UC_SETTINGS[k] end,
    __newindex = function(_, k, v) _G.UC_SETTINGS[k] = v end,
})""",
    1,
)

# Share Start_Engine global with melee
src = src.replace("local Start_Engine = false", "-- Start_Engine is global (UnifiedCombat)\n")

# register_event rewrites
replacements = [
    ("windower.register_event('incoming chunk', function(id, data)", "local function uc_dd2_incoming_chunk(id, data)"),
    ("windower.register_event('outgoing chunk', function(id, data)", "local function uc_dd2_outgoing_chunk(id, data)"),
    ("windower.register_event('addon command', function(...)", "local function uc_dd2_addon_command(...)"),
    ("windower.register_event('job change', function(job, lvl)", "local function uc_dd2_job_change(job, lvl)"),
    ("windower.register_event('zone change', function()", "local function uc_dd2_zone_change()"),
    ("windower.register_event('unload', function()", "local function uc_dd2_unload()"),
    ("windower.register_event('logout', function()", "local function uc_dd2_logout()"),
    ("windower.register_event('load', function()", "local function uc_dd2_load()"),
    ("windower.register_event('prerender', function()", "local function uc_dd2_prerender()"),
]

for old, new in replacements:
    if old not in src:
        raise SystemExit(f"Missing pattern: {old!r}")
    src = src.replace(old, new, 1)

# Fix closing end) -> end for each former register (8 handlers) — order last-to-first by position
# Each register ended with `end)` — we need `end` only. Replace unique closing patterns from bottom.
patterns_end = [
    "end)\n\nfunction GetResonatingStep",  # prerender block before GetResonatingStep
]
# prerender ends before GetResonatingStep in original
src = src.replace(
    "end)\n\nfunction GetResonatingStep",
    "end\n\nfunction GetResonatingStep",
    1,
)

# load ends before prerender in DD2 - order in file: incoming, outgoing, addon, ... job, zone, unload, logout, load, prerender
# Replace all `end)` that close register_event - risky. Use line-by-line heuristic: `end)` alone after unload/logout blocks

def fix_register_closures(text: str) -> str:
    lines = text.splitlines(keepends=True)
    out = []
    i = 0
    depth = 0
    in_reg = False
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
    return "".join(out)


# Simpler: replace known sequence of `end)` at end of specific functions — use multiline regex for each block tail

# incoming chunk: ends before `function inc_action`
src = re.sub(
    r"(local function uc_dd2_incoming_chunk\(id, data\).*?)(\nend\)\n\nfunction inc_action)",
    r"\1\nend\n\nfunction inc_action",
    src,
    count=1,
    flags=re.DOTALL,
)

# outgoing: small block
src = re.sub(
    r"(local function uc_dd2_outgoing_chunk\(id, data\).*?)(\nend\)\n\nwindower\.register_event)",
    r"\1\nend\n\nwindower.register_event",
    src,
    count=1,
    flags=re.DOTALL,
)
# After first fix, outgoing might still have end) — re-read
if "uc_dd2_outgoing_chunk" in src:
    src = re.sub(
        r"(local function uc_dd2_outgoing_chunk\(id, data\).*?)(\nend\)\n\nlocal function uc_dd2_addon_command)",
        r"\1\nend\n\nlocal function uc_dd2_addon_command",
        src,
        count=1,
        flags=re.DOTALL,
    )

# addon command — long; ends before `windower.register_event('job` or local function uc_dd2_job
src = re.sub(
    r"(local function uc_dd2_addon_command\(\.\.\.\).*?)(\nend\)\n\nlocal function uc_dd2_job_change)",
    r"\1\nend\n\nlocal function uc_dd2_job_change",
    src,
    count=1,
    flags=re.DOTALL,
)

for a, b in [
    (r"(local function uc_dd2_job_change\(job, lvl\).*?)(\nend\)\n\nlocal function uc_dd2_zone_change)", r"\1\nend\n\nlocal function uc_dd2_zone_change"),
    (r"(local function uc_dd2_zone_change\(\).*?)(\nend\)\n\nlocal function uc_dd2_unload)", r"\1\nend\n\nlocal function uc_dd2_unload"),
    (r"(local function uc_dd2_unload\(\).*?)(\nend\)\n\nlocal function uc_dd2_logout)", r"\1\nend\n\nlocal function uc_dd2_logout"),
    (r"(local function uc_dd2_logout\(\).*?)(\nend\)\n\nfunction GetResonatingStep)", r"\1\nend\n\nfunction GetResonatingStep"),
]:
    src = re.sub(a, b, src, count=1, flags=re.DOTALL)

# load before prerender
src = re.sub(
    r"(local function uc_dd2_load\(\).*?)(\nend\)\n\nlocal function uc_dd2_prerender)",
    r"\1\nend\n\nlocal function uc_dd2_prerender",
    src,
    count=1,
    flags=re.DOTALL,
)

# Remove ActionPacket.open_listener — export handler
src = src.replace("ActionPacket.open_listener(action_handler)", "-- ActionPacket listener registered by UnifiedCombat\n")

# Prepend IIFE
hdr = "---@diagnostic disable: lowercase-global, undefined-field, undefined-global, deprecated, param-type-mismatch\n"
if not src.startswith("---@"):
    pass

insert_at = 0
if src.startswith("---@"):
    nl = src.find("\n")
    insert_at = src.find("\n", nl + 1) + 1 if src.startswith("---@diagnostic") else 0

# Insert after _libs.req('queues') line
marker = "_libs.req('queues')\n"
idx = src.find(marker)
if idx == -1:
    raise SystemExit("marker not found")
idx += len(marker)
src = src[:idx] + "\nreturn (function()\n" + src[idx:]

# Append return table and close IIFE (before last line if empty)
footer = """

return {
    incoming_chunk = uc_dd2_incoming_chunk,
    outgoing_chunk = uc_dd2_outgoing_chunk,
    addon_command = uc_dd2_addon_command,
    job_change = uc_dd2_job_change,
    zone_change = uc_dd2_zone_change,
    unload = uc_dd2_unload,
    logout = uc_dd2_logout,
    load = uc_dd2_load,
    prerender = uc_dd2_prerender,
    action_handler = action_handler,
}
end)()
"""

# Remove duplicate diagnostic if doubled
src = src.rstrip() + "\n"
# Cut trailing whitespace and append footer — but file must end with end)()
if "end)()" in src:
    raise SystemExit("already wrapped")

src = src + footer

out_path = ROOT / "dd2_module.lua"
out_path.write_text(src, encoding="utf-8")
print("Wrote", out_path, "bytes", len(src))
