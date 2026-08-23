-- Puppetmaster automation defaults.
--
-- This file is intentionally static/offline-readable so every multibox client
-- has the same deterministic PUP policy without requiring live game state.
-- Maneuver names must be exact Windower resource names.
return {
	enabled = true,
	activate_if_missing = true,
	deploy_on_combat_start = true,
	maneuvers = {
		enabled = true,
		pattern = {
			'Fire Maneuver',
			'Fire Maneuver',
			'Light Maneuver',
		},

		-- Activate and zoning place elemental burden near the overload threshold.
		-- Holding for two minutes lets the conservative burden model fully drain
		-- before automatic maneuver maintenance begins.
		post_activate_quiet_seconds = 120,

		-- Non-dark maneuvers are modeled at the documented worst-case 20 burden
		-- (Dark at 15) with one burden decaying every three seconds. Staying at or
		-- below 30 leaves margin beneath the ~32-33 overload threshold.
		safe_burden_ceiling = 30,
	},
}
