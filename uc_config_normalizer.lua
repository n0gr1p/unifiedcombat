local base = require('uc_config_normalizer_base')
local sequence = require('uc_config_normalizer_sequence').wrap(base)
return require('uc_config_normalizer_cor').wrap(sequence)
