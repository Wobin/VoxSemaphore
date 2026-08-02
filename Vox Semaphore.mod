return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Vox Semaphore` encountered an error loading the Darktide Mod Framework.")

		new_mod("Vox Semaphore", {
			mod_script       = "Vox Semaphore/scripts/mods/Vox Semaphore/Vox Semaphore",
			mod_data         = "Vox Semaphore/scripts/mods/Vox Semaphore/Vox Semaphore_data",
			mod_localization = "Vox Semaphore/scripts/mods/Vox Semaphore/Vox Semaphore_localization",
		})
	end,
	version = "1.2",
	packages = {},
	load_after = { "SimpleAssets" },
}
