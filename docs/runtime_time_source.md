# UnifiedCombat runtime time source

UnifiedCombat runtime/gameplay timing has one canonical clock domain: `uc_time.now()`, backed by LuaSocket `socket.gettime`.

This applies to scheduler timestamps, action state, cooldown/settle windows, movement/follow holds, reactions, skillchain state, magic-burst windows, pending actions, retries, deadlines, and other elapsed runtime decisions.

Do not use `os.clock()` for runtime decisions. Do not call `socket.gettime()` directly from runtime modules. Code that needs LuaSocket for networking may still require the module, but its time reads must go through `uc_time`.

Tests should inject fake/deterministic `now` functions where supported. This keeps replay tests deterministic without creating a second production clock domain.

## Why this is enforced

The scheduler already used LuaSocket time while the skillchain runtime historically used `os.clock`. Magic-burst state inherited the skillchain timestamp, then `uc_combat_extensions.lua` compared that expiry directly with scheduler `ctx.now`. The incompatible domains made every valid burst window appear expired and prevented `combat.magic_burst` proposals.

The fix is architectural rather than a subtraction workaround: skillchain and scheduler timestamps now share `uc_time`, so `magic_burst_expires_at - ctx.now` is a valid same-domain duration.

`tests/replay/harness/selftest_time_source_contract.lua` is the regression guard for this invariant.
