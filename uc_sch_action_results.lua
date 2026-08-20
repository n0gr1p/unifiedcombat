local capabilities = require('uc_sch_capabilities')

local M = {}

local VALID_OUTCOMES = {
	success = true,
	failure = true,
	no_effect = true,
	resist = true,
	interrupted = true,
}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_non_empty_string(value, name)
	if type(value) ~= 'string' or value == '' then
		error(name .. ' must be a non-empty string')
	end
	return value
end

local function require_non_negative_integer(value, name)
	if type(value) ~= 'number' or value < 0 or value % 1 ~= 0 then
		error(name .. ' must be a non-negative integer')
	end
	return value
end

local function require_positive_integer(value, name)
	local number_value = require_non_negative_integer(value, name)
	if number_value == 0 then
		error(name .. ' must be positive')
	end
	return number_value
end

local function validate_array(values, name, allow_empty)
	require_table(values, name)
	if not allow_empty and #values == 0 then
		error(name .. ' must not be empty')
	end
	for key in pairs(values) do
		if type(key) ~= 'number' or key < 1 or key > #values or key % 1 ~= 0 then
			error(name .. ' must be a contiguous array')
		end
	end
	return values
end

function M.model_key(action_type, action_name)
	if action_type ~= 'spell' and action_type ~= 'job_ability' then
		error('Scholar action-result type must be spell or job_ability')
	end
	require_non_empty_string(action_name, 'Scholar action-result name')
	return action_type .. '|' .. action_name
end

function M.production_catalog(action_type, action_name)
	local model_key = M.model_key(action_type, action_name)
	local exact_rules = {
		['job_ability|Light Arts'] = {
			{ message_id = 100, param = 0, outcome = 'success' },
		},
		['job_ability|Addendum: White'] = {
			{ message_id = 100, param = 0, outcome = 'success' },
		},
		['job_ability|Accession'] = {
			{ message_id = 100, param = 366, outcome = 'success' },
		},
		['job_ability|Penury'] = {
			{ message_id = 100, param = 360, outcome = 'success' },
		},
		['job_ability|Rapture'] = {
			{ message_id = 100, param = 364, outcome = 'success' },
		},
		['job_ability|Perpetuance'] = {
			{ message_id = 100, param = 469, outcome = 'success' },
		},
		['job_ability|Sublimation'] = {
			{ message_id = 100, param = 0, outcome = 'success' },
			{ message_id = 451, param = 'any', outcome = 'success' },
		},
	}
	local storms = {
		['Sandstorm II'] = 592,
		['Rainstorm II'] = 594,
		['Windstorm II'] = 591,
		['Firestorm II'] = 589,
		['Hailstorm II'] = 590,
		['Thunderstorm II'] = 593,
		['Voidstorm II'] = 596,
		['Aurorastorm II'] = 595,
	}
	local cures = {
		['Cure'] = true,
		['Cure II'] = true,
		['Cure III'] = true,
		['Cure IV'] = true,
	}
	local status_removal = {
		Erase = true, Blindna = true, Paralyna = true, Poisona = true,
		Silena = true, Stona = true, Cursna = true, Viruna = true,
	}
	local resource_backed_action = action_type == 'job_ability'
		and (action_name == 'Penury' or action_name == 'Rapture')
	local maintenance_spell = action_type == 'spell'
		and capabilities.accession_maintenance_spell(action_name) or nil
	if maintenance_spell ~= nil then
		exact_rules[model_key] = {
			{ message_id = 230, param = maintenance_spell.status_id, outcome = 'success' },
			{ message_id = 266, param = maintenance_spell.status_id, outcome = 'success' },
		}
	elseif action_type == 'spell' and cures[action_name] then
		exact_rules[model_key] = {
			{ message_id = 7, param = 'any', outcome = 'success' },
			{ message_id = 75, param = 'any', outcome = 'no_effect' },
			{ message_id = 16, param = 'any', outcome = 'interrupted' },
		}
	elseif action_type == 'spell' and status_removal[action_name] then
		exact_rules[model_key] = {
			{ message_id = 64, param = 'any', outcome = 'success' },
			{ message_id = 83, param = 'any', outcome = 'success' },
			{ message_id = 75, param = 'any', outcome = 'no_effect' },
			{ message_id = 16, param = 'any', outcome = 'interrupted' },
		}
	end
	if action_type == 'spell' and storms[action_name] ~= nil then
		exact_rules[model_key] = {
			{ message_id = 230, param = storms[action_name], outcome = 'success' },
		}
	end
	if exact_rules[model_key] ~= nil then
		return {
			confidence = 'confirmed',
			model_key = model_key,
			source = (maintenance_spell ~= nil or cures[action_name] or status_removal[action_name]
				or resource_backed_action)
				and 'windower_resources:action_messages'
				or 'sch_capture:Nyoourke_solo_phase1_20260820T104827Z',
			rules = exact_rules[model_key],
		}
	end
	return {
		confidence = 'unknown',
		model_key = model_key,
		reason = 'action_result_not_captured_for_exact_action',
		rules = {},
	}
end

local function expected_recipients(values)
	validate_array(values, 'Scholar action-result expected_recipients', false)
	local out = {}
	local by_id = {}
	for i = 1, #values do
		local value = require_table(values[i], 'Scholar action-result expected recipient')
		local id = require_positive_integer(value.id, 'Scholar action-result expected recipient id')
		if by_id[id] ~= nil then
			error('Scholar action-result expected recipient ids must be unique')
		end
		if type(value.name) ~= 'string' then
			error('Scholar action-result expected recipient name must be a string')
		end
		local recipient = { id = id, name = value.name }
		out[i] = recipient
		by_id[id] = recipient
	end
	return out, by_id
end

local function raw_targets(values)
	validate_array(values, 'Scholar action-result raw_targets', false)
	local out = {}
	local seen_target_ids = {}
	for target_index = 1, #values do
		local target = require_table(values[target_index], 'Scholar action-result raw target')
		local target_id = require_positive_integer(
			target.id,
			'Scholar action-result raw target id'
		)
		if seen_target_ids[target_id] then
			error('Scholar action-result raw target ids must be unique')
		end
		seen_target_ids[target_id] = true
		local actions = validate_array(
			target.actions,
			'Scholar action-result raw target actions',
			false
		)
		local copied = { id = target_id, actions = {} }
		for action_index = 1, #actions do
			local action = require_table(actions[action_index], 'Scholar action-result raw action')
			local row = {
				message = require_non_negative_integer(
					action.message,
					'Scholar action-result message'
				),
				param = require_non_negative_integer(
					action.param,
					'Scholar action-result param'
				),
			}
			local optional_fields = {
				'add_effect_message',
				'add_effect_param',
				'spike_effect_message',
				'spike_effect_param',
			}
			for field_index = 1, #optional_fields do
				local field = optional_fields[field_index]
				if action[field] ~= nil then
					row[field] = require_non_negative_integer(
						action[field],
						'Scholar action-result ' .. field
					)
				end
			end
			copied.actions[action_index] = row
		end
		out[target_index] = copied
	end
	return out
end

local function validated_catalog(catalog, model_key)
	require_table(catalog, 'Scholar action-result catalog')
	if catalog.model_key ~= model_key then
		error('Scholar action-result catalog model_key does not match the exact action')
	end
	local rules = validate_array(catalog.rules, 'Scholar action-result catalog rules', true)
	if catalog.confidence == 'unknown' then
		require_non_empty_string(catalog.reason, 'Scholar unknown action-result reason')
		if #rules ~= 0 or catalog.source ~= nil then
			error('Scholar unknown action-result catalog must not claim rules or a source')
		end
		return {
			confidence = 'unknown',
			reason = catalog.reason,
			source = '',
			by_message = {},
		}
	end
	if catalog.confidence ~= 'confirmed' then
		error('Scholar action-result catalog confidence must be unknown or confirmed')
	end
	local source = require_non_empty_string(
		catalog.source,
		'Scholar confirmed action-result source'
	)
	if catalog.reason ~= nil then
		error('Scholar confirmed action-result catalog must not include an unknown reason')
	end
	if #rules == 0 then
		error('Scholar confirmed action-result catalog must contain rules')
	end
	local by_message = {}
	for i = 1, #rules do
		local rule = require_table(rules[i], 'Scholar action-result rule')
		local message_id = require_non_negative_integer(
			rule.message_id,
			'Scholar action-result rule message_id'
		)
		if not VALID_OUTCOMES[rule.outcome] then
			error('Scholar action-result rule outcome is invalid')
		end
		local param_key
		if rule.param == 'any' then
			param_key = 'any'
		else
			param_key = tostring(require_non_negative_integer(
				rule.param,
				'Scholar action-result rule param'
			))
		end
		by_message[message_id] = by_message[message_id] or {}
		if by_message[message_id][param_key] ~= nil then
			error('Scholar action-result rules must have unique message/param keys')
		end
		by_message[message_id][param_key] = rule.outcome
	end
	return {
		confidence = 'confirmed',
		reason = '',
		source = source,
		by_message = by_message,
	}
end

local function classify_action(action, catalog)
	local rules = catalog.by_message[action.message]
	if rules == nil then
		return 'unknown'
	end
	local exact = rules[tostring(action.param)]
	if exact ~= nil then
		return exact
	end
	if rules.any ~= nil then
		return rules.any
	end
	return 'unknown'
end

local function sorted_ids(set)
	local out = {}
	for id in pairs(set) do
		out[#out + 1] = id
	end
	table.sort(out)
	return out
end

function M.classify(input)
	require_table(input, 'Scholar action-result input')
	local model_key = M.model_key(input.action_type, input.action_name)
	local expected, expected_by_id = expected_recipients(input.expected_recipients)
	local targets = raw_targets(input.raw_targets)
	local catalog = validated_catalog(input.catalog, model_key)
	local result = {
		state = 'unclassified',
		outcome = 'unknown',
		blocker = '',
		action_type = input.action_type,
		action_name = input.action_name,
		model_key = model_key,
		catalog_confidence = catalog.confidence,
		catalog_source = catalog.source,
		target_results = {},
		successful_recipients = {},
		missing_expected_recipient_ids = {},
		unexpected_recipient_ids = {},
		unknown_message_ids = {},
		interrupted = false,
	}
	local observed_target_ids = {}
	local unexpected = {}
	local unknown_messages = {}
	local has_unclassified_target = false
	local successful_targets = {}
	local non_success_count = 0
	for target_index = 1, #targets do
		local target = targets[target_index]
		observed_target_ids[target.id] = true
		if expected_by_id[target.id] == nil then
			unexpected[target.id] = true
		end
		local target_result = {
			target_id = target.id,
			outcome = nil,
			actions = {},
		}
		local first_outcome = nil
		local mixed = false
		for action_index = 1, #target.actions do
			local action = target.actions[action_index]
			local outcome = catalog.confidence == 'confirmed'
				and classify_action(action, catalog)
				or 'unknown'
			target_result.actions[action_index] = {
				message = action.message,
				param = action.param,
				outcome = outcome,
			}
			if outcome == 'unknown' then
				unknown_messages[action.message] = true
			end
			if first_outcome == nil then
				first_outcome = outcome
			elseif first_outcome ~= outcome then
				mixed = true
			end
		end
		target_result.outcome = mixed and 'mixed' or first_outcome
		if target_result.outcome == 'unknown' or target_result.outcome == 'mixed' then
			has_unclassified_target = true
		elseif target_result.outcome == 'success' then
			successful_targets[#successful_targets + 1] = target.id
		else
			non_success_count = non_success_count + 1
			if target_result.outcome == 'interrupted' then
				result.interrupted = true
			end
		end
		result.target_results[target_index] = target_result
	end
	local missing = {}
	for i = 1, #expected do
		if not observed_target_ids[expected[i].id] then
			missing[expected[i].id] = true
		end
	end
	result.missing_expected_recipient_ids = sorted_ids(missing)
	result.unexpected_recipient_ids = sorted_ids(unexpected)
	result.unknown_message_ids = sorted_ids(unknown_messages)
	if catalog.confidence ~= 'confirmed' then
		result.blocker = catalog.reason
		return result
	end
	if has_unclassified_target then
		result.blocker = 'action_result_unclassified'
		return result
	end
	result.state = 'classified'
	for i = 1, #successful_targets do
		local id = successful_targets[i]
		local expected_recipient = expected_by_id[id]
		result.successful_recipients[i] = {
			id = id,
			name = expected_recipient and expected_recipient.name or '',
		}
	end
	if #successful_targets == 0 then
		result.outcome = 'failure'
	elseif non_success_count > 0 or #result.missing_expected_recipient_ids > 0 then
		result.outcome = 'partial_success'
	else
		result.outcome = 'success'
	end
	return result
end

return M
