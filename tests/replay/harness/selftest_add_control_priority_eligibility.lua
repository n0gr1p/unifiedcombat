local active_priority_names = {}
local old_target_ignore = package.loaded['uc_target_ignore']
local old_runtime_overrides = package.loaded['uc_runtime_overrides']
local old_add_priority = package.loaded['uc_add_priority']

local function read_file(path)
	local file = assert(io.open(path, 'r'))
	local content = file:read('*a')
	file:close()
	return content
end

package.loaded['uc_target_ignore'] = {
	is_mob_blocked = function()
		return false
	end,
}

package.loaded['uc_runtime_overrides'] = {
	fight_leader_enabled = function(settings)
		return settings.fight_leader == true
	end,
	add_priority_names = function()
		return active_priority_names
	end,
}

package.loaded['uc_add_priority'] = nil
local add_control = dofile('uc_add_control.lua')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function distance(yalms)
	return {
		sqrt = function()
			return yalms
		end,
	}
end

local function mob(id, name, yalms, hpp)
	return {
		id = id,
		name = name,
		distance = distance(yalms),
		hpp = hpp or 100,
		claim_id = 100,
		spawn_type = 16,
		status = 1,
		valid_target = true,
	}
end

local settings = {
	add_control = true,
	fight_leader = true,
}
local claims = { 100 }
local leader_mid = 1

active_priority_names = {}
assert_equal(
	add_control.pick(settings, claims, { mob(2, 'Unlisted Mob', 2) }, leader_mid),
	0,
	'empty priority list must not override the fight leader target'
)

active_priority_names = { 'Priority Mob' }
assert_equal(
	add_control.pick(settings, claims, {
		mob(2, 'Unlisted Mob', 1),
		mob(3, 'Priority Mob', 20),
	}, leader_mid),
	3,
	'listed mob must win even when an unlisted mob is closer'
)

active_priority_names = { 'High Priority', 'Low Priority' }
assert_equal(
	add_control.pick(settings, claims, {
		mob(2, 'Low Priority', 1),
		mob(3, 'High Priority', 20),
	}, leader_mid),
	3,
	'configured priority order must be preserved among eligible mobs'
)

active_priority_names = { 'Priority Mob' }
assert_equal(
	add_control.pick(settings, claims, {
		mob(2, 'Unlisted Mob', 1),
		mob(3, 'Priority Mob', 2, 0),
	}, leader_mid),
	0,
	'unlisted mobs must remain ignored when every listed mob is invalid'
)

assert_equal(
	add_control.pick(settings, claims, { mob(leader_mid, 'Priority Mob', 1) }, leader_mid),
	0,
	'leader target must not be treated as an add even when its name is listed'
)

local core_source = read_file('unified_combat_core.lua')
if not core_source:find('if engaged and allow_engaged_retarget then', 1, true) then
	error('engaged add control must block the ordinary unlisted candidate scan')
end
if not core_source:find('function core.add_control_enabled_for_scheduler(settings)', 1, true) then
	error('scheduler must use the shared add-control enablement policy')
end
if not core_source:find('elseif leader_mid and leader_mid > 0 then', 1, true) then
	error('engaged add control must return to the resolved fight-leader target when no configured add remains')
end

local scheduler_source = read_file('unified_scheduler.lua')
local target_provider_source = read_file('uc_provider_target_control.lua')
local combat_provider_source = read_file('uc_provider_combat.lua')
if not target_provider_source:find('local add_control_retarget = engaged and add_control_enabled(ctx.settings)', 1, true)
	or not target_provider_source:find('if engaged and not add_control_retarget and not death_switch then', 1, true) then
	error('scheduler must allow engaged target control only for add control or explicit death switch')
end
if not scheduler_source:find("kind = 'switch_target'", 1, true)
	or not scheduler_source:find('switch_target = uc_attack.switch_target', 1, true) then
	error('scheduler engaged add control must dispatch the attack switch-target primitive')
end
if not combat_provider_source:find("if bool_setting(add_control_enabled(ctx.settings), false) then", 1, true) then
	error('fight-leader engage must defer while engaged add control owns target switching')
end

package.loaded['uc_target_ignore'] = old_target_ignore
package.loaded['uc_runtime_overrides'] = old_runtime_overrides
package.loaded['uc_add_priority'] = old_add_priority

io.stdout:write('selftest_add_control_priority_eligibility: OK\n')
