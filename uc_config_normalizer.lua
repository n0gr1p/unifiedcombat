local base = require('uc_config_normalizer_base')
local sequence = require('uc_config_normalizer_sequence').wrap(base)
local once = require('uc_config_normalizer_once').wrap(sequence)
return require('uc_config_normalizer_cor').wrap(once)
