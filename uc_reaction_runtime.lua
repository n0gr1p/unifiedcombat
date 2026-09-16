-- Legacy reaction implementation remains in uc_reaction_runtime_base.lua,
-- including the generic Kei rule response = 'move_to_range'.
-- Clearing uc_reaction_runtime has historically produced a fresh runtime in tests
-- and reload paths, so clear all implementation layers when this facade reloads.
package.loaded.uc_reaction_runtime_base = nil
package.loaded.uc_reaction_sequence_runtime = nil
package.loaded.uc_reaction_party_sequence_runtime = nil
package.loaded.uc_reaction_once_runtime = nil
package.loaded.uc_party_action_event = nil
local base = require('uc_reaction_runtime_base')
local sequence = require('uc_reaction_sequence_runtime').extend(base)
local party_sequence = require('uc_reaction_party_sequence_runtime').extend(sequence)
return require('uc_reaction_once_runtime').extend(party_sequence)
