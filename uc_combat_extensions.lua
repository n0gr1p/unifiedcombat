local base = require('uc_combat_extensions_base')
local sequence = require('uc_combat_extensions_sequence').wrap(base)
return require('uc_combat_extensions_once').wrap(sequence)
