local M = {}

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

    if kind == "turn" then
        if n.payload.heading == nil then
            return false, "missing_heading"
        end
        return true, ""
    end

    if kind == "set_target" then
        if n.payload.target_id <= 0 then
            return false, "invalid_target_id"
        end
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

function M.dispatch_intent(intent, deps)
    deps = deps or {}
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

    local kind = normalized.kind
    local err = ""

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
    elseif kind == "set_target" then
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

    scrub_validation_fields(normalized)
    return {
        ok = true,
        reason = "executed",
        executed = true,
        normalized_intent = normalized,
    }
end

return M
