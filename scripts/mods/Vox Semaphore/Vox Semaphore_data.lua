local mod = get_mod("Vox Semaphore")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,

	options = {
		widgets = {
			{
				setting_id = "self_camera",
				type = "dropdown",
				default_value = "over_shoulder",
				options = {
					{ text = "camera_over_shoulder", value = "over_shoulder" },
					{ text = "camera_facing", value = "facing" },
				},
			},
			{
				setting_id = "show_others",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "announce_users",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "debug_log",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "emote_wheel_keybind",
				type = "keybind",
				default_value = { "middle", "left alt" },
				keybind_trigger = "held",
				keybind_type = "function_call",
				function_name = "toggle_emote_wheel",
			},
			{
				setting_id = "test_emote_keybind",
				type = "keybind",
				default_value = {},
				keybind_trigger = "pressed",
				keybind_type = "function_call",
				function_name = "test_emote",
			},
		},
	},
}
