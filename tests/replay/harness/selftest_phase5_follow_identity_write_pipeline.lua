package.path = './?.lua;' .. package.path

local function assert_true(value, message)
    if value ~= true then error(message or ('expected true, got ' .. tostring(value))) end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then error(message or ('missing text: ' .. needle)) end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then error(message or ('unexpected text: ' .. needle)) end
end

local function read_all(path)
    local fh, err = io.open(path, 'rb')
    if not fh then error('failed to open ' .. tostring(path) .. ': ' .. tostring(err)) end
    local source = fh:read('*a')
    fh:close()
    return source
end

local function extract(source, start_marker, end_marker)
    local start_pos = source:find(start_marker, 1, true)
    if not start_pos then error('missing source block start: ' .. start_marker) end
    local end_pos = source:find(end_marker, start_pos + #start_marker, true)
    if not end_pos then error('missing source block end: ' .. end_marker) end
    return source:sub(start_pos, end_pos - 1)
end

local previous_windower = rawget(_G, 'windower')
local previous_active = rawget(_G, 'UC_ACTIVE_PROFILE')
local previous_active_module = package.loaded.uc_active_config
local previous_follow_module = package.loaded.uc_follow_config

local party = {
    p0 = { mob = { id = 10, name = 'Tester' } },
    p1 = { mob = { id = 101, name = 'PartyLeader' } },
    p2 = { mob = { id = 202, name = 'FightLeader' } },
    p3 = { mob = { id = 303, name = 'PartnerOne' } },
    p4 = { mob = { id = 404, name = 'Puller' } },
}

rawset(_G, 'windower', {
    ffxi = {
        get_party = function() return party end,
        -- A non-party name deliberately resolves here. Durable follow identity
        -- resolution must still ignore it because only the current party roster
        -- is authoritative for runtime member IDs.
        get_mob_by_name = function(name)
            if name == 'OfflineGhost' then return { id = 909, name = name } end
            return nil
        end,
    },
})

package.loaded.uc_active_config = nil
package.loaded.uc_follow_config = nil
local active_config = require('uc_active_config')
local follow_config = require('uc_follow_config')

rawset(_G, 'UC_ACTIVE_PROFILE', {
    version = 2,
    profile = {
        schema_version = 2,
        engine = 'UC',
        character = 'Tester',
        main_job = 'WAR',
        sub_job = 'DNC',
        source = 'SELFTEST',
    },
    config = {
        follow = {
            enabled = true,
            party = {
                enabled = true,
                leader_name = 'OldParty',
                leader_id = 991,
                min = 0.5,
                max = 50,
            },
            fight = {
                leader = true,
                leader_name = 'OldFight',
                leader_id = 992,
                min = 3,
                hold_s = 8,
            },
            partner = {
                enabled = true,
                secondary_enabled = true,
                names = { 'OldPartner' },
                ids = { 993 },
                puller = true,
                puller_name = 'OldPuller',
                puller_id = 994,
                leash_source = 'player',
                engage_range = 6,
                puller_distance_only = false,
            },
        },
    },
})

local ok, err = pcall(function()
    local runtime_config = active_config.get_path('config')
    local follow = active_config.get_path('config.follow')
    assert_true(type(runtime_config) == 'table', 'active root config missing')
    assert_true(type(follow) == 'table', 'active follow config missing')

    local changed, reason = active_config.replace_name(
        'config.follow.party.leader_name',
        ' PartyLeader '
    )
    assert_true(changed, 'party leader canonical edit should succeed')
    assert_equal(reason, 'REPLACED', 'party leader canonical edit reason')
    assert_equal(follow.party.leader_name, 'PartyLeader', 'party leader name must trim')
    assert_equal(follow.party.leader_id, 0, 'party leader edit must clear stale legacy id')

    changed, reason = active_config.replace_name(
        'config.follow.fight.leader_name',
        ' FightLeader '
    )
    assert_true(changed, 'fight leader canonical edit should succeed')
    assert_equal(follow.fight.leader_name, 'FightLeader', 'fight leader name must trim')
    assert_equal(follow.fight.leader_id, 0, 'fight leader edit must clear stale legacy id')

    changed, reason = active_config.replace_name(
        'config.follow.partner.puller_name',
        ' Puller '
    )
    assert_true(changed, 'puller canonical edit should succeed')
    assert_equal(follow.partner.puller_name, 'Puller', 'puller name must trim')
    assert_equal(follow.partner.puller_id, 0, 'puller edit must clear stale legacy id')

    follow.partner.ids = { 995 }
    changed, reason = active_config.replace_string_list(
        'config.follow.partner.names',
        { ' PartnerOne ', 'partnerone', 'Offline Partner' }
    )
    assert_true(changed, 'partner canonical list edit should succeed')
    assert_equal(reason, 'REPLACED', 'partner canonical list edit reason')
    assert_equal(#follow.partner.names, 2, 'partner names must case-insensitively dedupe')
    assert_equal(follow.partner.names[1], 'PartnerOne', 'partner name must trim')
    assert_equal(follow.partner.names[2], 'Offline Partner', 'offline durable partner must survive')
    assert_equal(#follow.partner.ids, 0, 'partner name edit must clear stale legacy ids')

    assert_equal(follow.party.leader_name, 'PartyLeader', 'durable party leader name remains canonical')
    assert_equal(follow.fight.leader_name, 'FightLeader', 'durable fight leader name remains canonical')
    assert_equal(follow.partner.puller_name, 'Puller', 'durable puller name remains canonical')
    assert_equal(follow_config.party_leader_id(runtime_config), 101, 'party leader id resolves from current party')
    assert_equal(follow_config.fight_leader_id(runtime_config), 202, 'fight leader id resolves from current party')
    assert_equal(follow_config.puller_id(runtime_config), 404, 'puller id resolves from current party')
    assert_equal(follow_config.partner_ids(runtime_config)[1], 303, 'partner id resolves from current party')

    -- A configured but currently unresolved durable name must beat stale legacy IDs.
    follow.party.leader_name = 'OfflineGhost'
    follow.party.leader_id = 701
    follow.fight.leader_name = 'OfflineFight'
    follow.fight.leader_id = 702
    follow.partner.names = { 'OfflinePartner' }
    follow.partner.ids = { 703 }
    follow.partner.puller_name = 'OfflinePuller'
    follow.partner.puller_id = 704

    assert_equal(follow.party.leader_name, 'OfflineGhost',
        'offline durable party leader name must survive')
    assert_equal(follow.fight.leader_name, 'OfflineFight',
        'offline durable fight leader name must survive')
    assert_equal(follow.partner.puller_name, 'OfflinePuller',
        'offline durable puller name must survive')

    assert_equal(follow_config.party_leader_id(runtime_config), 0,
        'follow runtime adapter must ignore non-party get_mob_by_name fallback')
    assert_equal(follow_config.fight_leader_id(runtime_config), 0,
        'follow runtime adapter must not use stale fight leader id when a name is configured')
    assert_equal(follow_config.puller_id(runtime_config), 0,
        'follow runtime adapter must not use stale puller id when a name is configured')
    assert_equal(#follow_config.partner_ids(runtime_config), 0,
        'follow runtime adapter must preserve offline names without stale partner ids')

    -- Legacy IDs remain compatibility fallback only when durable names are absent.
    follow.party.leader_name = ''
    follow.party.leader_id = 711
    follow.fight.leader_name = ''
    follow.fight.leader_id = 712
    follow.partner.names = {}
    follow.partner.ids = { 713, 714 }
    follow.partner.puller_name = ''
    follow.partner.puller_id = 715
    follow.partner.leash_source = 'player'

    assert_equal(follow_config.party_leader_id(runtime_config), 711, 'follow adapter party legacy fallback')
    assert_equal(follow_config.fight_leader_id(runtime_config), 712, 'follow adapter fight legacy fallback')
    assert_equal(follow_config.puller_id(runtime_config), 715, 'follow adapter puller legacy fallback')
    assert_equal(follow_config.partner_ids(runtime_config)[1], 713, 'follow adapter partner legacy fallback')

    follow.partner.leash_source = 'camp'
    assert_equal(follow_config.puller_id(runtime_config), 0, 'camp leash must never expose a player puller id')
end)

rawset(_G, 'UC_ACTIVE_PROFILE', previous_active)
rawset(_G, 'windower', previous_windower)
package.loaded.uc_active_config = previous_active_module
package.loaded.uc_follow_config = previous_follow_module

if not ok then error(err, 0) end

local bridge = read_all('remote_bridge.lua')
local ui = read_all('UnifiedCombatWinForms/MainForm.ParityLogic.cs')
local writer = read_all('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')
local follow_source = read_all('uc_follow_config.lua')
local active_source = read_all('uc_active_config.lua')

local bridge_identity = extract(
    bridge,
    "if op == 'set_partner' then",
    "elseif op == 'set_abilities' then"
)
assert_not_contains(bridge_identity, 'UC_SETTINGS',
    'follow identity compatibility handlers must not mutate flat settings')
assert_not_contains(bridge_identity, 'uc_partner_list',
    'partner compatibility handlers must not use legacy flat partner-list writer')
assert_contains(bridge_identity, "'config.follow.partner.puller_name'",
    'puller bridge compatibility path must edit canonical durable name')
assert_contains(bridge_identity, "'config.follow.fight.leader_name'",
    'fight leader bridge compatibility path must edit canonical durable name')
assert_contains(bridge_identity, "'config.follow.party.leader_name'",
    'party follow bridge compatibility path must edit canonical durable name')
assert_contains(bridge_identity, "'config.follow.partner.names'",
    'partner bridge compatibility path must edit canonical durable names')

local bridge_replace = extract(
    bridge,
    "elseif op == 'partner_replace_names' then",
    "elseif op == 'no_skillchain_target_replace_names' then"
)
assert_not_contains(bridge_replace, 'UC_SETTINGS',
    'partner replace compatibility handler must not mutate flat settings')
assert_contains(bridge_replace, "'replace_string_list'",
    'partner replace compatibility handler must edit canonical name list')

local puller_handler = extract(
    ui,
    '    private void OnPullerSelected()',
    '    private void OnFightLeaderSelected()'
)
assert_not_contains(puller_handler, 'Forward(', 'puller selector must be local-only')
assert_contains(puller_handler, 'CaptureWorkingProfileFromUi(sid);',
    'puller selector must capture working Profile V2')

local fight_handler = extract(
    ui,
    '    private void OnFightLeaderSelected()',
    '    private void OnPartyFollowSelected()'
)
assert_not_contains(fight_handler, 'Forward(', 'fight leader selector must be local-only')
assert_contains(fight_handler, 'CaptureWorkingProfileFromUi(sid);',
    'fight leader selector must capture working Profile V2')

local party_handler = extract(
    ui,
    '    private void OnPartyFollowSelected()',
    '    private void OnPartyFollowDistanceChanged()'
)
assert_not_contains(party_handler, 'Forward(', 'party-follow leader selector must be local-only')
assert_contains(party_handler, 'CaptureWorkingProfileFromUi(sid);',
    'party-follow leader selector must capture working Profile V2')

local partner_handlers = extract(
    ui,
    '    private void PartnerAddByName()',
    '    private void TargetIgnAddByName()'
)
assert_not_contains(partner_handlers, 'Forward(', 'partner list edits must be local-only')
assert_contains(partner_handlers, 'CurrentRuntimeTargetName()',
    'partner Add Current must consume runtime observation rather than issue a durable bridge write')
assert_contains(partner_handlers, 'CaptureWorkingProfileFromUi(sid);',
    'partner list edits must capture working Profile V2')

local full_push = extract(
    ui,
    '    private void PushFullFormState(string sid)',
    '    private void PushDefensiveThresholdsForSid(string sid)'
)
assert_not_contains(full_push, '"partner_replace_names"', 'full form push must not send partner durable policy')
assert_not_contains(full_push, '"set_partner"', 'full form push must not send puller durable identity')
assert_not_contains(full_push, '"set_fight_leader"', 'full form push must not send fight leader durable identity')
assert_not_contains(full_push, '"set_party_follow"', 'full form push must not send party-follow durable identity')

local writer_follow = extract(
    writer,
    '    private static StructuredProfileNode BuildFollow(JsonObject flatProfile)',
    '    private static StructuredProfileNode? BuildNyzul(JsonObject flatProfile)'
)
assert_contains(writer_follow, '.Add("names", partnerNames)',
    'structured writer must persist durable partner names')
assert_contains(writer_follow, 'partner.Add("puller_name", pullerName);',
    'structured writer must persist durable puller name')
assert_contains(writer_follow, '.Add("leader_name", ReadString(flatProfile, "party_follow_selected", ""))',
    'structured writer must persist durable party-follow leader name')
assert_not_contains(writer_follow, '.Add("ids"', 'structured writer must not persist partner runtime ids')
assert_not_contains(writer_follow, '.Add("puller_id"', 'structured writer must not persist puller runtime id')
assert_not_contains(writer_follow, '.Add("leader_id"', 'structured writer must not persist follow runtime leader ids')

assert_contains(writer, 'fight.Add("leader_name", ResolveFightLeaderName(flatProfile));',
    'structured writer must persist durable fight leader name')
assert_contains(follow_source, "if durable_name ~= '' then",
    'follow adapter must prefer configured durable names over legacy ids')
assert_not_contains(
    extract(follow_source, 'function M.resolve_party_member_id_by_name(name)', 'local function configured_id(name, id)'),
    'get_mob_by_name',
    'follow runtime identity resolution must be constrained to current party state'
)
assert_contains(active_source, 'function M.replace_name(path, value)',
    'active config must expose canonical scalar-name editing')
assert_contains(active_source, "partner.ids = {}",
    'active partner-name edits must clear stale compatibility ids')

print('selftest_phase5_follow_identity_write_pipeline: OK (durable names + current-party runtime IDs)')
