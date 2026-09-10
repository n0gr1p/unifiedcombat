-- Legacy reaction implementation remains in uc_reaction_runtime_base.lua,
-- including the generic Kei rule response = 'move_to_range'.
local base = require('uc_reaction_runtime_base')
return require('uc_reaction_sequence_runtime').extend(base)
