package.loaded['uc_hb_buff_maint'] = nil

windower = windower or {}
windower.addon_path = './'

package.loaded['resources'] = {
	buffs = {
		[101] = { en = 'Protect' },
		[200] = { en = 'March' },
	},
}

local hb_buff_maint = dofile('uc_hb_buff_maint.lua')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	if not value then
		error(message or 'assert_true failed')
	end
end

local function make_helpers()
	return {
		bool_setting = function(value, default)
			if value == nil then
				return default
			end
			return value == true
		end,
		in_party_cast_range = function()
			return true
		end,
		action_ready = function(action_name)
			if action_name == 'Honor March' or action_name == 'Victory March' or action_name == 'Protect' then
				return true, nil, 'spell'
			end
			return false, 'UNREADY', 'spell'
		end,
		get_spell_resource = function(action_name)
			if action_name == 'Honor March' then
				return { id = 420, type = 'BardSong', status = 200 }
			end
			if action_name == 'Victory March' then
				return { id = 421, type = 'BardSong', status = 200 }
			end
			if action_name == 'Protect' then
				return { id = 1, type = 'WhiteMagic', status = 101 }
			end
			return nil
		end,
		get_ja_resource = function()
			return nil
		end,
		is_bard_song = function(action_name)
			return action_name == 'Honor March' or action_name == 'Victory March'
		end,
		attempt_allowed = function()
			return true
		end,
		member_priority = function(member)
			return member.is_self and 1 or 5
		end,
		pri_default = function(member_prio, buff_prio)
			return tonumber(member_prio) + (tonumber(buff_prio) or 0) / 10
		end,
		buff_priority = {
			['Honor March'] = 1,
			['Victory March'] = 2,
			Protect = 3,
		},
		last_overwrite = {},
		log_debug = nil,
	}
end

local function make_members(buff_ids)
	return {
		{
			name = 'Terrasjr',
			is_self = true,
			buffs = buff_ids or {},
		},
	}
end

local function buff_config(list)
	return {
		defensive = {
			buffs = {
				enabled = true,
				list = list or '',
				targeted = {},
				self_only = true,
				overwrite_enabled = false,
				overwrite_interval = 150,
			},
		},
		maintenance = {
			brd = { enabled = false },
		},
	}
end

local function pick_spell(settings, buff_ids)
	local picked = hb_buff_maint.choose(settings, make_members(buff_ids), make_helpers())
	return picked and picked.spell or nil
end

local function main()
	hb_buff_maint._reset_test_state()

	local duo_settings = buff_config('Honor March|Victory March')

	local single_settings = buff_config('Honor March')

	local nonsong_settings = buff_config('Protect')

	assert_equal(pick_spell(duo_settings, {}), 'Honor March', 'first configured March should be chosen when none are active')

	local now = os.time()
	assert_true(
		hb_buff_maint.mark_bard_song_success('Terrasjr', 'Honor March', now, now + 120),
		'Honor March success should be recorded'
	)
	assert_equal(
		pick_spell(duo_settings, { 200 }),
		'Victory March',
		'confirmed Honor March plus one live March family effect should request the other March, not recast Honor March'
	)

	assert_true(
		hb_buff_maint.mark_bard_song_success('Terrasjr', 'Victory March', now + 1, now + 121),
		'Victory March success should be recorded'
	)
	assert_equal(
		pick_spell(duo_settings, { 200, 200 }),
		nil,
		'two live March family effects plus confirmed Honor/Victory identities should satisfy dual March maintenance'
	)

	hb_buff_maint._reset_test_state()
	assert_equal(
		pick_spell(duo_settings, { 200 }),
		'Honor March',
		'failed or interrupted Honor March must not be marked satisfied'
	)

	hb_buff_maint._reset_test_state()
	assert_true(
		hb_buff_maint.mark_bard_song_success('Terrasjr', 'Honor March', now - 10, now - 1),
		'expired Honor March cache entry should still record for test setup'
	)
	assert_true(
		pick_spell(duo_settings, { 200 }) ~= nil,
		'expired song identity must not suppress same-family recast eligibility'
	)

	hb_buff_maint._reset_test_state()
	assert_equal(
		pick_spell(single_settings, { 200 }),
		nil,
		'single March-family song must keep existing generic-family behavior'
	)

	hb_buff_maint._reset_test_state()
	assert_equal(
		pick_spell(nonsong_settings, {}),
		'Protect',
		'non-song buff maintenance must remain unaffected'
	)

	local scheduler_source = io.open('unified_scheduler.lua', 'r')
	local scheduler_text = scheduler_source:read('*a')
	scheduler_source:close()
	assert_true(
		scheduler_text:find("hb_buff_maint.mark_bard_song_success", 1, true) == nil,
		'scheduler must not synthesize Bard duration through defensive maintenance'
	)
	assert_true(
		scheduler_text:find("message_id == 17 and message_param == 0", 1, true) == nil,
		'scheduler must not treat message 17 (unable to cast) as Bard song success'
	)

	io.stdout:write('selftest_bard_song_identity_tracking: OK\n')
end

main()
