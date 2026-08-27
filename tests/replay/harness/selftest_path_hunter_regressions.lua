local function assert_true(condition, message)
    if not condition then
        error(message or 'assertion failed')
    end
end

local function read_file(path)
    local fh, err = io.open(path, 'r')
    if not fh then
        error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
    end
    local content = fh:read('*a')
    fh:close()
    return content
end

local writer = read_file('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')
assert_true(
    writer:find('.Add("hunter_targets", ParseNameList(ReadString(flatProfile, "path_hunter_entries", "")))', 1, true) ~= nil,
    'profile-v2 writer must persist path hunter target names'
)
assert_true(
    writer:find('.Add("hunter_targets", EmptyList())', 1, true) == nil,
    'profile-v2 writer must not hard-code an empty hunter target list'
)

local pathing = read_file('uc_pathing.lua')
local recovery = "if type(s.path_points) ~= 'table' or #s.path_points == 0 then"
local recover_pos = assert(pathing:find(recovery, 1, true), 'recording OFF must recover route points after profile reload')
local read_pos = assert(pathing:find('read_path_file(s)', recover_pos, true))
local classify_pos = assert(pathing:find('classify_route(s)', read_pos, true))
local write_pos = assert(pathing:find('write_path_file(s)', classify_pos, true))
assert_true(read_pos < classify_pos and classify_pos < write_pos, 'route recovery must happen before final classification/write')

local parity = read_file('UnifiedCombatWinForms/MainForm.ParityLogic.cs')
local add_start = assert(parity:find('private void OnPathHunterAdd()', 1, true))
local remove_start = assert(parity:find('private void OnPathHunterRemove()', add_start, true))
local next_section = assert(parity:find('private static string NormalizeTankEnmityEntry', remove_start, true))
local add_section = parity:sub(add_start, remove_start - 1)
local remove_section = parity:sub(remove_start, next_section - 1)
assert_true(add_section:find('CaptureWorkingProfileFromUi(sid);', 1, true) ~= nil, 'Hunter add must capture the working profile before a snapshot can erase the local row')
assert_true(remove_section:find('CaptureWorkingProfileFromUi(sid);', 1, true) ~= nil, 'Hunter remove must capture the working profile before a snapshot can restore the removed row')

local scheduler = read_file('unified_scheduler.lua')
assert_true(
    scheduler:find("scheduler.p1_pending_mark_complete(ctx.now, ('pull_no_send:%s')", 1, true) ~= nil,
    'path pull no-send completion must call scheduler pending wrapper'
)
assert_true(
    scheduler:find("\n\t\tp1_pending_mark_complete(ctx.now, ('pull_no_send:%s')", 1, true) == nil,
    'path pull must not call stale global p1_pending_mark_complete'
)

print('path hunter regression guards: PASS')
