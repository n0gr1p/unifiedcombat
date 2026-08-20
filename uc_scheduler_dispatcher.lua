local M = {}
local recovery_hold = require('uc_recovery_hold')

-- Scheduler-owned side effects cross this contract exactly once. Callers supply
-- the concrete Windower/packet adapter as an injected dependency; there is no
-- direct fallback when validation or dependency execution is rejected.
-- revalidate runs immediately before execution, and on_executed runs exactly
-- once after successful execution so pending/action state can commit atomically.

local function as_string(v)
    if v == nil then
        return ""
    end
    return tostring(v)
end

local function as_number(v)
    return tonumber(v) or 0
end

local function has_number(v)
    return tonumber(v) ~= nil
end

local function normalize_kind(kind)
    local k = as_string(kind)
    if k == "" then
        return "none"
    end
    return k
end

local function build_payload(intent)
    local payload = intent.payload
    if type(payload) ~= "table" then
        payload = {}
    end

    local run_x_raw = payload.run_x
    if run_x_raw == nil then
        run_x_raw = intent.run_x
    end

    local run_y_raw = payload.run_y
    if run_y_raw == nil then
        run_y_raw = intent.run_y
    end

    local heading_raw = payload.heading
    if heading_raw == nil then
        heading_raw = intent.heading
    end

    local command_raw = payload.command
    if command_raw == nil then
        command_raw = intent.command
    end

    local target_id_raw = payload.target_id
    if target_id_raw == nil then
        target_id_raw = intent.target_id
    end

    return {
        command = as_string(command_raw),
        run_x = tonumber(run_x_raw),
        run_y = tonumber(run_y_raw),
        heading = tonumber(heading_raw),
        target_id = as_number(target_id_raw),
        _run_x_present = run_x_raw ~= nil,
        _run_y_present = run_y_raw ~= nil,
        _run_x_numeric = has_number(run_x_raw),
        _run_y_numeric = has_number(run_y_raw),
    }
end

local function normalize_intent_internal(intent)
    intent = intent or {}
    local payload = build_payload(intent)
    local meta = intent.meta
    if type(meta) ~= "table" then
        meta = {}
    end

    return {
        kind = normalize_kind(intent.kind),
        reason = as_string(intent.reason),
        meta = {
            heading = tonumber(meta.heading),
        },
        payload = payload,
        _validation = {
            run_x_present = payload._run_x_present,
            run_y_present = payload._run_y_present,
            run_x_numeric = payload._run_x_numeric,
            run_y_numeric = payload._run_y_numeric,
        },
    }    
end

function M.normalize_intent(intent)
    local n = normalize_intent_internal(intent)
    n.payload._run_x_present = nil
    n.payload._run_y_present = nil
    n.payload._run_x_numeric = nil
    n.payload._run_y_numeric = nil
    n._validation = nil
    return n
end

local function scrub_validation_fields(normalized)
    if type(normalized) ~= "table" then
        return normalized
    end
    if type(normalized.payload) == "table" then
        normalized.payload._run_x_present = nil
        normalized.payload._run_y_present = nil
        normalized.payload._run_x_numeric = nil
        normalized.payload._run_y_numeric = nil
    end
    normalized._validation = nil
    return normalized
end

function M.validate_intent(intent)
    local n
    if type(intent) == "table" and type(intent._validation) == "table" then
        n = intent
    else
        n = normalize_intent_internal(intent)
    end
    local kind = n.kind

    if kind == "none" then
        return false, "invalid_kind"
    end

    if kind == "send_command" then
        if n.payload.command == "" then
            return false, "missing_command"
        end
        return true, ""
    end

    if kind == "run" then
        if not n._validation.run_x_present then
            return false, "missing_run_x"
        end
        if not n._validation.run_y_present then
            return false, "missing_run_y"
        end
        if not n._validation.run_x_numeric then
            return false, "invalid_run_x"
        end
        if not n._validation.run_y_numeric then
            return false, "invalid_run_y"
        end
        return true, ""
    end

    if kind == "run_stop" then
        return true, ""
    end

    if kind == "run_forward" then
        return true, ""
    end

    if kind == "turn" then
        if n.payload.heading == nil then
            return false, "missing_heading"
        end
        return true, ""
    end

    if kind == "select_target" or kind == "set_target"
        or kind == "engage" or kind == "switch_target"
        or kind == "move_towards" or kind == "move_away_from" then
        if n.payload.target_id <= 0 then
            return false, "invalid_target_id"
        end
        return true, ""
    end

    if kind == "disengage" then
        return true, ""
    end

    return false, "unsupported_kind"
end

local function require_dep_fn(deps, key)
    local fn = deps[key]
    if type(fn) ~= "function" then
        return nil, "missing_dep:" .. key
    end
    return fn, ""
end

local function run_commit_validation(normalized, hooks)
    local revalidate = hooks.revalidate
    if revalidate == nil then
        return true, ""
    end
    if type(revalidate) ~= "function" then
        error("uc_scheduler_dispatcher hooks.revalidate must be a function")
    end
    local ok, reason = revalidate(normalized)
    if ok ~= true then
        return false, tostring(reason or "commit_rejected")
    end
    return true, ""
end

local function run_executed_hook(normalized, result, hooks)
    local on_executed = hooks.on_executed
    if on_executed == nil then
        return
    end
    if type(on_executed) ~= "function" then
        error("uc_scheduler_dispatcher hooks.on_executed must be a function")
    end
    local ok, reason = on_executed(normalized, result)
    if ok == false then
        error("uc_scheduler_dispatcher execution hook failed: " .. tostring(reason or "unknown"))
    end
end

function M.dispatch_intent(intent, deps, hooks)
    if type(deps) ~= "table" then
        error("uc_scheduler_dispatcher deps must be a table")
    end
    if hooks == nil then
        hooks = {}
    elseif type(hooks) ~= "table" then
        error("uc_scheduler_dispatcher hooks must be a table")
    end
    local normalized = normalize_intent_internal(intent)
    local ok, reason = M.validate_intent(normalized)
    if not ok then
        scrub_validation_fields(normalized)
        return {
            ok = false,
            reason = reason,
            executed = false,
            normalized_intent = normalized,
        }
    end

    if deps.execute ~= true then
        scrub_validation_fields(normalized)
        return {
            ok = true,
            reason = "dry_run",
            executed = false,
            normalized_intent = normalized,
        }
    end

    local recovery_release_allowed = hooks.allow_during_recovery_hold == true
        and normalized.kind == "run_stop"
        and as_string(intent and intent.source):match(":release$") ~= nil
    if not recovery_release_allowed and recovery_hold.current() then
        scrub_validation_fields(normalized)
        return {
            ok = false,
            reason = recovery_hold.BLOCK_REASON,
            executed = false,
            normalized_intent = normalized,
        }
    end

    local commit_ok, commit_reason = run_commit_validation(normalized, hooks)
    if not commit_ok then
        scrub_validation_fields(normalized)
        return {
            ok = false,
            reason = commit_reason,
            executed = false,
            normalized_intent = normalized,
        }
    end

    local kind = normalized.kind
    local err = ""
    local dep_result = nil
    local dep_reason = nil

    if kind == "send_command" then
        local fn
        fn, err = require_dep_fn(deps, "send_command")
        if not fn then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = err,
                executed = false,
                normalized_intent = normalized,
            }
        end
        fn(normalized.payload.command)
    elseif kind == "run" then
        local fn
        fn, err = require_dep_fn(deps, "run")
        if not fn then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = err,
                executed = false,
                normalized_intent = normalized,
            }
        end
        fn(normalized.payload.run_x, normalized.payload.run_y)
    elseif kind == "run_stop" then
        local fn
        fn, err = require_dep_fn(deps, "run")
        if not fn then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = err,
                executed = false,
                normalized_intent = normalized,
            }
        end
        fn(false)
    elseif kind == "run_forward" then
        local fn
        fn, err = require_dep_fn(deps, "run_forward")
        if not fn then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = err,
                executed = false,
                normalized_intent = normalized,
            }
        end
        fn()
    elseif kind == "turn" then
        local fn
        fn, err = require_dep_fn(deps, "turn")
        if not fn then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = err,
                executed = false,
                normalized_intent = normalized,
            }
        end
        fn(normalized.payload.heading)
    elseif kind == "select_target" or kind == "set_target" then
        local fn
        fn, err = require_dep_fn(deps, "set_target")
        if not fn then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = err,
                executed = false,
                normalized_intent = normalized,
            }
        end
        dep_result, dep_reason = fn(normalized.payload.target_id)
    elseif kind == "engage" then
        local fn
        fn, err = require_dep_fn(deps, "engage_target")
        if not fn then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = err,
                executed = false,
                normalized_intent = normalized,
            }
        end
        dep_result, dep_reason = fn(normalized.payload.target_id)
    elseif kind == "switch_target" then
        local fn
        fn, err = require_dep_fn(deps, "switch_target")
        if not fn then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = err,
                executed = false,
                normalized_intent = normalized,
            }
        end
        dep_result, dep_reason = fn(normalized.payload.target_id)
    elseif kind == "disengage" then
        local fn
        fn, err = require_dep_fn(deps, "disengage")
        if not fn then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = err,
                executed = false,
                normalized_intent = normalized,
            }
        end
        dep_result, dep_reason = fn()
    elseif kind == "move_towards" or kind == "move_away_from" then
        local fn
        fn, err = require_dep_fn(deps, kind)
        if not fn then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = err,
                executed = false,
                normalized_intent = normalized,
            }
        end
        fn(normalized.payload.target_id)
    else
        scrub_validation_fields(normalized)
        return {
            ok = false,
            reason = "unsupported_kind",
            executed = false,
            normalized_intent = normalized,
        }
    end

    if kind == "select_target" or kind == "set_target"
        or kind == "engage" or kind == "switch_target" or kind == "disengage" then
        if dep_result ~= true then
            scrub_validation_fields(normalized)
            return {
                ok = false,
                reason = tostring(dep_reason or "dependency_rejected"),
                executed = false,
                dep_result = dep_result,
                dep_reason = dep_reason,
                normalized_intent = normalized,
            }
        end
    end

    scrub_validation_fields(normalized)
    local result = {
        ok = true,
        reason = "executed",
        executed = true,
        dep_result = dep_result,
        dep_reason = dep_reason,
        normalized_intent = normalized,
    }
    run_executed_hook(normalized, result, hooks)
    return result
end

return M
