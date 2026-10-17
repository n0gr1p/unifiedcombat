package.path = './?.lua;' .. package.path

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
end

local function assert_contains(source, needle, message)
	if not source:find(needle, 1, true) then
		error(message or ('missing text: ' .. needle))
	end
end

local function assert_not_contains(source, needle, message)
	if source:find(needle, 1, true) then
		error(message or ('unexpected text: ' .. needle))
	end
end

local function read_all(path)
	local fh = assert(io.open(path, 'rb'))
	local source = fh:read('*a')
	fh:close()
	return source
end

local previous_engine = rawget(_G, 'Start_Engine')
local saved_active = package.loaded.uc_active_config
local saved_brd = package.loaded.uc_brd_maintenance
local saved_positioning = package.loaded.uc_brd_positioning
local saved_song_state = package.loaded.uc_brd_party_song_state
local saved_camp = package.loaded.uc_camp_anchor

local observed = {}

package.loaded.uc_active_config = {
	get_path = function(path)
		error('BRD runtime must not reach global active config: ' .. tostring(path))
	end,
}

package.loaded.uc_brd_maintenance = {
	propose = function(config)
		observed.brd_config = config
		if config.enabled ~= true then
			return nil
		end
		return {
			action_type = 'ja',
			action_name = 'Nightingale',
			reason_code = 'brd_authority_test',
			urgency = 0.75,
			detail = {},
		}
	end,
	take_scheduler_failure = function()
		return nil
	end,
	note_positioning_block = function() end,
	defer_positioning = function() end,
}

package.loaded.uc_brd_positioning = {
	prepare = function(args)
		observed.positioning = args
		return true, 'BRD_REPOSITION_READY'
	end,
	status = function()
		return { phase = 'idle' }
	end,
}

package.loaded.uc_brd_party_song_state = {
	in_recovery_range = function(member, radius)
		observed.recovery_radius = radius
		return true, 3.0
	end,
}

package.loaded.uc_camp_anchor = {
	resolve_current_anchor = function()
		return { x = 10, y = 20 }
	end,
}

package.loaded.uc_provider_maintenance = nil
local provider_module = require('uc_provider_maintenance')

local function brd_config(enabled, radius, reposition)
	return {
		enabled = enabled == true,
		songs = { 'Honor March', 'Victory March' },
		dummy_songs = { "Army's Paeon", "Army's Paeon II" },
		recovery_range_yalms = radius,
		recovery_ignore_names = { 'Ignored Ally' },
		reposition_for_party_songs = reposition == true,
		use_nitro = true,
		use_soul_voice = false,
		use_clarion_call = false,
		use_marcato = false,
		marcato_song = '',
		targeted_songs = {},
	}
end

local function new_provider()
	local phase1 = { maintenance_next_at = {} }
	return provider_module.new({
		bool_setting = function(value, default)
			if value == nil then return default end
			return value == true
		end,
		log_def_sched = function() end,
		is_city_zone = function() return false end,
		ensure_buff_cache = function() end,
		number = function(value, default)
			local n = tonumber(value)
			if n == nil then return default end
			return n
		end,
		clamp_urgency = function(value) return tonumber(value) or 0 end,
		action_timeline_action_state_summary = function() return '' end,
		action_timeline_log = function() end,
		cor_propose = function() return nil end,
		get_party_members = function()
			return {
				{ id = 100, name = 'Bard', is_self = true, buffs = {} },
			}
		end,
		action_ready = function() return true, '', 'ja' end,
		clear_local_brd_spell_failure = function() end,
		pending_mark_failed = function() end,
		count_matching_buffs = function() return 0 end,
		phase1 = phase1,
		maintenance_buff_cache = {},
		action_timeline_state = {},
		brd_maintenance_priority = 200,
	})
end

local function context(canonical_brd, canonical_leash, compatibility_brd)
	return {
		now = 10,
		config = {
			maintenance = {
				brd = canonical_brd,
			},
			combat = {
				pulling = {
					enabled = true,
					leash_yalms = canonical_leash,
				},
			},
		},
		settings = {
			maintenance_brd = compatibility_brd,
			brd_maintenance_enabled = compatibility_brd.enabled,
			brd_recovery_range_yalms = compatibility_brd.recovery_range_yalms,
			camp_pulling = {
				enabled = true,
				leash_yalms = 2,
			},
		},
		player_present = true,
		player = {
			id = 100,
			name = 'Bard',
			main_job = 'BRD',
			sub_job = 'WHM',
			status = 1,
			buffs = {},
		},
		me = { id = 100, x = 10, y = 20, z = 0 },
		mobs_by_id = {},
	}
end

local function reset_observed()
	observed = {}
end

local function test_enabled_authority()
	reset_observed()
	local canonical = brd_config(true, 14.5, true)
	local compatibility = brd_config(false, 4.0, false)
	local provider = new_provider()
	local out = {}
	provider.collect(context(canonical, 37, compatibility), out)

	assert_equal(observed.brd_config, canonical, 'BRD proposal must receive canonical subtree by identity')
	assert_equal(#out, 1, 'canonical BRD enabled must beat compatibility disabled')
	assert_equal(out[1].provider, 'maintenance_brd', 'BRD provider id')
	assert_equal(out[1].action_name, 'Nightingale', 'BRD canonical proposal')
	assert_equal(observed.recovery_radius, 14.5, 'BRD recovery radius must be canonical')
	assert_true(type(observed.positioning) == 'table', 'BRD positioning arguments')
	assert_equal(observed.positioning.enabled, true, 'BRD reposition policy must be canonical')
	assert_equal(observed.positioning.radius, 14.5, 'BRD positioning radius must be canonical')
	assert_equal(observed.positioning.ignore_names, canonical.recovery_ignore_names,
		'BRD ignore list must be canonical by identity')
	assert_equal(observed.positioning.camp_leash_yalms, 37,
		'BRD positioning leash must come from tick-stable canonical pulling config')
end

local function test_disabled_authority()
	reset_observed()
	local canonical = brd_config(false, 15.0, false)
	local compatibility = brd_config(true, 5.0, true)
	local provider = new_provider()
	local out = {}
	provider.collect(context(canonical, 44, compatibility), out)

	assert_equal(observed.brd_config, canonical, 'canonical disabled BRD config must reach proposal')
	assert_equal(#out, 0, 'canonical BRD disabled must beat compatibility enabled')
	assert_equal(observed.recovery_radius, 15.0, 'disabled BRD still uses canonical recovery geometry')
end

local function test_static_boundary()
	local provider_source = read_all('uc_provider_maintenance.lua')
	assert_not_contains(provider_source, "require('uc_active_config')",
		'BRD maintenance provider must not bypass scheduler context via active config')
	assert_not_contains(provider_source, "get_path('config.maintenance.brd')",
		'BRD maintenance must not resample global Profile V2')
	assert_not_contains(provider_source, "get_path('config.combat.pulling')",
		'BRD positioning must not resample global pulling policy')
	assert_contains(provider_source, "require_table(ctx.config, 'ctx.config')",
		'BRD provider must require canonical tick config')
	assert_contains(provider_source, "require_table(maintenance_config.brd, 'ctx.config.maintenance.brd')",
		'BRD provider must read canonical maintenance.brd')
	assert_contains(provider_source, "require_table(combat_config.pulling, 'ctx.config.combat.pulling')",
		'BRD positioning must read canonical combat.pulling')
end

rawset(_G, 'Start_Engine', true)
local ok, err = pcall(function()
	test_enabled_authority()
	test_disabled_authority()
	test_static_boundary()
end)

rawset(_G, 'Start_Engine', previous_engine)
package.loaded.uc_active_config = saved_active
package.loaded.uc_brd_maintenance = saved_brd
package.loaded.uc_brd_positioning = saved_positioning
package.loaded.uc_brd_party_song_state = saved_song_state
package.loaded.uc_camp_anchor = saved_camp
package.loaded.uc_provider_maintenance = nil

if not ok then
	error(err, 0)
end

print('selftest_phase4_brd_authority: OK (BRD config + positioning authority)')
