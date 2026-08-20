--[[
Name: Vox Semaphore
Author: Wobin
Date: 19/08/2026
Repository: https://github.com/Wobin/VoxSemaphore
--]]

local mod = get_mod("Vox Semaphore")
mod.version = mod.get_metadata and mod:get_metadata("version") or "unknown"

local MODULE_PATH = "Vox Semaphore/scripts/mods/Vox Semaphore/modules/"

local VOX_MANIFOLD_ID = "wobin.vox_semaphore"

local WHEEL_ENABLED = true

mod.vox_id = VOX_MANIFOLD_ID

mod.mode = "uninitialised"
mod.settings = {
	self_camera = "over_shoulder",
	show_others = true,
	announce_users = false,
	debug_log = false,
}

mod.trace = function(fmt, ...)
	if mod.settings.debug_log then
		mod:info(fmt, ...)
	end
end

local function cache_settings()
	mod.settings.self_camera = mod:get("self_camera") or "over_shoulder"
	mod.settings.show_others = mod:get("show_others") ~= false
	mod.settings.announce_users = mod:get("announce_users") == true
	mod.settings.debug_log = mod:get("debug_log") == true

	if mod.observer then
		mod.observer.set_enabled(mod.settings.show_others)
	end
end

local function load_modules()
	mod.protocol = mod:io_dofile(MODULE_PATH .. "protocol")
	mod.id_codec = mod:io_dofile(MODULE_PATH .. "id_codec")
	mod.emote_codec = mod:io_dofile(MODULE_PATH .. "emote_codec")
	mod.emote_inventory = mod:io_dofile(MODULE_PATH .. "emote_inventory")
	mod.suppression = mod:io_dofile(MODULE_PATH .. "suppression")
	mod.anim_guard = mod:io_dofile(MODULE_PATH .. "anim_guard")
	mod.cancel = mod:io_dofile(MODULE_PATH .. "cancel")
	mod.camera = mod:io_dofile(MODULE_PATH .. "camera")
	mod.durations = mod:io_dofile(MODULE_PATH .. "durations")
	mod.emote = mod:io_dofile(MODULE_PATH .. "emote")
	mod.broadcast = mod:io_dofile(MODULE_PATH .. "broadcast")
	mod.observer = mod:io_dofile(MODULE_PATH .. "observer")
	mod.roster = mod:io_dofile(MODULE_PATH .. "roster")
	mod.slice_art = mod:io_dofile(MODULE_PATH .. "slice_art")
	mod.wheel = mod:io_dofile(MODULE_PATH .. "wheel")
	mod.hub_driver = mod:io_dofile(MODULE_PATH .. "hub_driver")
end

local function connect_vox_manifold()
	local vox = get_mod("Vox Manifold")

	if not vox or not vox.api or not vox.api.register then
		return false
	end

	local ok, err = vox.api.register(VOX_MANIFOLD_ID, mod, function()
		return mod.broadcast and mod.broadcast.current()
	end)

	if not ok then
		mod:warning("Vox Manifold rejected registration (%s); running self only", tostring(err))

		return false
	end

	mod.vox = vox

	return true
end

local function ensure_connected()
	if mod.mode == "networked" then
		return true
	end

	if not connect_vox_manifold() then
		mod.mode = "self_only"

		return false
	end

	mod.mode = "networked"

	mod:info("Vox Manifold found; broadcasting as %s", VOX_MANIFOLD_ID)

	if mod.observer then
		mod.observer.install()
		mod.observer.set_enabled(mod.settings.show_others)
	end

	return true
end

mod.play_self_emote = function(event_name)
	local player_manager = Managers.player
	local player = player_manager and player_manager.local_player_safe and player_manager:local_player_safe(1)
	local unit = player and player.player_unit

	if not unit then
		return false, "no local player unit"
	end

	if mod.emote.is_emoting(unit) then
		mod.emote.stop(unit)
	end

	local ok, err = mod.emote.start(unit, event_name, mod.settings.self_camera)

	if ok and mod.broadcast then
		local sent, reason = mod.broadcast.announce(event_name)

		if not sent then
			mod:warning("emote played locally but not broadcast: %s", tostring(reason))
		end
	end

	return ok, err
end

mod.toggle_emote_wheel = function(is_pressed)
	if WHEEL_ENABLED and mod.wheel then
		mod.wheel.toggle(is_pressed)
	end
end

mod.test_emote = function()
	local player_manager = Managers.player
	local player = player_manager and player_manager.local_player_safe and player_manager:local_player_safe(1)
	local profile = player and player:profile()
	local loadout = profile and profile.loadout
	local item = loadout and loadout.slot_animation_emote_1
	local event_name = item and item.animation_event

	if not event_name then
		mod:echo("Vox Semaphore: no emote equipped in slot 1")

		return
	end

	local ok, err = mod.play_self_emote(event_name)

	if not ok then
		mod:echo("Vox Semaphore: " .. tostring(err))
	end
end

mod.on_all_mods_loaded = function()
	mod:info(mod.version)

	cache_settings()
	load_modules()

	mod.durations.init()
	mod.suppression.install()
	mod.anim_guard.install()

	mod.broadcast.shutdown()

	if not ensure_connected() then
		mod:info("Vox Manifold not available yet; will retry at mission start")
	end

	if WHEEL_ENABLED then
		mod.slice_art.load()
		mod.wheel.install()
		mod.hub_driver.install()
	else
		mod:info("emote wheel disabled: modules/hud_element_wheel.lua is missing")
	end
end

mod.on_setting_changed = function()
	cache_settings()
end


mod.on_settings_reset = function()
	mod.on_setting_changed()
end
mod.on_game_state_changed = function(status, state_name)
	if state_name ~= "StateGameplay" then
		return
	end

	if status == "enter" then
		ensure_connected()

		if mod.wheel and WHEEL_ENABLED then
			mod.wheel.prefetch()
			mod.hub_driver.install()
		end

		if mod.roster then
			mod.roster.arm()
		end
	elseif status == "exit" then
		if mod.observer then
			mod.observer.reset()
		end

		if mod.roster then
			mod.roster.cancel()
		end
	end
end

local function teardown()
	if mod.wheel and WHEEL_ENABLED then
		mod.wheel.on_unload()
	end

	if mod.emote then
		mod.emote.stop_all()
	end

	if mod.camera then
		mod.camera.exit()
	end

	if mod.cancel then
		mod.cancel.clear()
	end

	if mod.broadcast then
		mod.broadcast.shutdown()
	end

	if mod.roster then
		mod.roster.cancel()
	end
end

mod.on_disabled = function()
	teardown()

	if mod.anim_guard then
		mod.anim_guard.remove()
	end

	if mod.suppression then
		mod.suppression.remove()
	end
end

mod.on_enabled = function()
	if mod.suppression then
		mod.suppression.install()
	end

	if mod.anim_guard then
		mod.anim_guard.install()
	end
end

mod.update = function()
	if not mod:is_enabled() then
		return
	end

	if mod.emote then
		mod.emote.update()
	end

	if mod.observer then
		mod.observer.update()
	end

	if mod.roster then
		mod.roster.update()
	end
end

mod.on_unload = function()
	if mod.wheel then
		mod.wheel.on_unload()
	end

	if mod.observer then
		mod.observer.uninstall()
	end

	if mod.broadcast then
		mod.broadcast.shutdown()
	end

	if mod.emote then
		mod.emote.stop_all()
	end

	if mod.camera then
		mod.camera.exit()
	end

	if mod.cancel then
		mod.cancel.clear()
	end

	if mod.durations then
		mod.durations.on_unload()
	end

	if mod.roster then
		mod.roster.cancel()
	end

	if mod.anim_guard then
		mod.anim_guard.remove()
	end

	if mod.suppression then
		mod.suppression.remove()
	end

	if mod.vox and mod.vox.api and mod.vox.api.unregister then
		mod.vox.api.unregister(VOX_MANIFOLD_ID)
	end
end
