return {
	name = "nested food with legacy flat BRD maintenance",
	input = {
		domain_maintenance_enabled = true,
		brd_maintenance_enabled = true,
		brd_songs = "Honor March|Victory March",
		brd_use_nitro = true,
		maintenance = {
			food = {
				enabled = true,
				item = "Grape Daifuku",
			},
		},
	},
	current_characterization = {
		food_enabled = true,
		food_item = "Grape Daifuku",
		brd_enabled = false,
		brd_song_count = 0,
	},
	target_after_migration = {
		food_enabled = true,
		food_item = "Grape Daifuku",
		brd_enabled = true,
		brd_songs = { "Honor March", "Victory March" },
		brd_use_nitro = true,
	},
}
