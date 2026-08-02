local mod = get_mod("Vox Semaphore")

local WeaponTemplate = require("scripts/utilities/weapon/weapon_template")
local WeaponTemplates = require("scripts/settings/equipment/weapon_templates/weapon_templates")

local suppression = mod.suppression
local cancel = mod.cancel
local camera = mod.camera

if not (suppression and cancel and camera) then
	mod:error("emote module loaded before its dependencies; check module load order")

	return {
		is_emoting = function() return false end,
		start = function() return false, "dependencies missing" end,
		stop = function() return false end,
		update = function() end,
		stop_all = function() end,
	}
end

local durations_defaults = mod.durations
local DEFAULT_DURATION = durations_defaults and durations_defaults.DEFAULT_DURATION or 2.5
local MAX_DURATION = durations_defaults and durations_defaults.MAX_ACCEPT or 30.0

local MIN_CLIP = 0.2
local MAX_LAYERS = 8
local LENGTH_EPSILON = 0.01

local CAMERA_LEAD = 1.0
local MAX_HOLD = 120.0
local CAMERA_FLOOR = 0.6

local M = {}

local active = {}

local state_scratch = {}

local function layer_lengths(unit, into)
	if type(Unit.animation_layer_info) ~= "function" then
		return nil, 0
	end

	if type(Unit.has_animation_state_machine) ~= "function" or not Unit.has_animation_state_machine(unit) then
		return nil, 0
	end

	local _, count = Unit.animation_get_state(unit, state_scratch)

	if type(count) ~= "number" or count < 1 then
		return nil, 0
	end

	if count > MAX_LAYERS then
		count = MAX_LAYERS
	end

	for i = 1, count do
		local _, length = Unit.animation_layer_info(unit, i)

		into[i] = type(length) == "number" and length or -1
	end

	return into, count
end

local function clip_length_from_diff(before, before_count, after, after_count)
	local count = before_count < after_count and before_count or after_count

	for i = 1, count do
		local now = after[i]

		if now and before[i] and now >= MIN_CLIP and now <= MAX_DURATION then
			local delta = now - before[i]

			if delta < 0 then
				delta = -delta
			end

			if delta > LENGTH_EPSILON then
				return now, i
			end
		end
	end

	return nil
end

local function layer_progress(unit, layer)
	if type(Unit.animation_layer_info) ~= "function" then
		return nil
	end

	if type(Unit.has_animation_state_machine) ~= "function" or not Unit.has_animation_state_machine(unit) then
		return nil
	end

	local elapsed, length = Unit.animation_layer_info(unit, layer)

	if type(elapsed) ~= "number" or type(length) ~= "number" then
		return nil
	end

	if length < MIN_CLIP or length > MAX_DURATION then
		return nil
	end

	return elapsed, length
end

local function trimmed_hold(duration)
	local early = duration - CAMERA_LEAD
	local floor = duration * CAMERA_FLOOR

	if early < floor then
		early = floor
	end

	return early
end

local function gameplay_time()
	local time_manager = Managers.time

	if time_manager and time_manager:has_timer("gameplay") then
		return time_manager:time("gameplay")
	end

	return nil
end

local function plan_duration(event_name)
	local durations = mod.durations

	if durations and durations.duration_for then
		local seconds = durations.duration_for(event_name)

		if type(seconds) == "number" and seconds > 0 then
			return seconds
		end
	end

	return DEFAULT_DURATION
end

local function trigger_face_event(unit, event_name)
	if not event_name then
		return
	end

	local visual_loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")

	if not (visual_loadout and visual_loadout.unit_3p_from_slot) then
		return
	end

	local face_unit = visual_loadout:unit_3p_from_slot("slot_body_face")

	if not (face_unit and Unit.has_animation_state_machine(face_unit)) then
		return
	end

	if not Unit.has_animation_event(face_unit, event_name) then
		return
	end

	Unit.animation_event(face_unit, event_name)
end

local function hub_template_for(breed_name)
	if breed_name == "ogryn" then
		return WeaponTemplates.unarmed_hub_ogryn
	end

	return WeaponTemplates.unarmed_hub_human
end

local function hold_state_machine_against_correction(animation)
	local weapon_action_component = animation._weapon_action_component

	if not weapon_action_component then
		return false
	end

	local real_template = WeaponTemplate.current_weapon_template(weapon_action_component)

	if not (real_template and real_template.name) then
		return false
	end

	animation._local_wielded_weapon_template = real_template.name

	return true
end

local function local_player_unit()
	local player_manager = Managers.player

	if not (player_manager and player_manager.local_player_safe) then
		return nil
	end

	local player = player_manager:local_player_safe(1)

	return player and player.player_unit
end

function M.is_emoting(unit)
	return active[unit] ~= nil
end

function M.stop(unit)
	local record = active[unit]

	if not record then
		return false
	end

	local alive = Unit.alive(unit)
	local restored = not alive or record.native == true

	if alive and not record.native then
		local visual_loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
		local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
		local animation = ScriptUnit.has_extension(unit, "animation_system")

		if visual_loadout and record.hidden_slot then
			visual_loadout:set_force_hide_wieldable_slot(record.hidden_slot, false, false)
		end

		if visual_loadout and unit_data and animation then
			local slot = unit_data:read_component("inventory").wielded_slot
			local template = visual_loadout:weapon_template_from_slot(slot) or record.template

			animation:inventory_slot_wielded(template)

			restored = not (record.event and Unit.has_animation_event(unit, record.event))
		end
	end

	if alive then
		trigger_face_event(unit, "pose_neutral")
	end

	active[unit] = nil

	if record.is_local then
		camera.exit()
		cancel.forget(unit)

		if mod.broadcast and mod.broadcast.announce_stop then
			mod.broadcast.announce_stop()
		end
	end

	if not record.suppressed then
		return true
	end

	if restored then
		suppression.release(unit)
	else
		mod:warning("could not restore the state machine; holding suppression on this unit")
	end

	return true
end

function M.start(unit, event_name, camera_mode)
	if not Unit.alive(unit) then
		return false, "unit not alive"
	end

	if active[unit] then
		return false, "already emoting"
	end

	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
	local visual_loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
	local animation = ScriptUnit.has_extension(unit, "animation_system")

	if not (unit_data and visual_loadout and animation) then
		return false, "not a player unit"
	end

	local now = gameplay_time()

	if not now then
		return false, "no gameplay timer"
	end

	local slot = unit_data:read_component("inventory").wielded_slot
	local template = visual_loadout:weapon_template_from_slot(slot)

	if not template then
		return false, "no weapon template for " .. tostring(slot)
	end

	local breed_name = unit_data:breed_name()
	local hub_template = hub_template_for(breed_name)

	if not hub_template then
		return false, "no hub template for breed " .. tostring(breed_name)
	end

	local duration = plan_duration(event_name)

	local native = Unit.has_animation_event(unit, event_name)
	local hidden_slot = nil

	if not native then
		suppression.suppress(unit)
		animation:inventory_slot_wielded(hub_template)

		if not Unit.has_animation_event(unit, event_name) then
			animation:inventory_slot_wielded(template)
			suppression.release(unit)

			return false, "state machine has no event " .. tostring(event_name)
		end

		if visual_loadout.set_force_hide_wieldable_slot then
			visual_loadout:set_force_hide_wieldable_slot(slot, false, true)

			hidden_slot = slot
		end

		hold_state_machine_against_correction(animation)
	end

	local before = {}
	local before_lengths, before_count = layer_lengths(unit, before)

	Unit.animation_event(unit, event_name)

	local inventory = mod.emote_inventory

	if inventory and inventory.face_event_for then
		trigger_face_event(unit, inventory.face_event_for(event_name))
	end

	local is_local = unit == local_player_unit()

	active[unit] = {
		template = template,
		event = event_name,
		native = native,
		suppressed = not native,
		hidden_slot = hidden_slot,
		started = now,
		expires = now + (is_local and MAX_HOLD or trimmed_hold(duration)),
		is_local = is_local,
		before = before_lengths,
		before_count = before_count,
		resolve_length = before_lengths ~= nil,
	}

	if is_local then
		camera.enter(unit, camera_mode)
		cancel.watch(unit, now)
	end

	return true
end

function M.update()
	if not next(active) then
		return
	end

	local now = gameplay_time()

	for unit, record in pairs(active) do
		if record.resolve_length and now and Unit.alive(unit) then
			record.resolve_length = false

			local after = {}
			local after_lengths, after_count = layer_lengths(unit, after)

			if after_lengths then
				local clip, layer = clip_length_from_diff(record.before, record.before_count, after_lengths, after_count)

				if clip then
					record.layer = layer

					if not record.is_local then
						record.expires = record.started + trimmed_hold(clip)
					end
				end
			end

			record.before = nil
		end

		if record.layer and not record.is_local and now and Unit.alive(unit) then
			local elapsed, length = layer_progress(unit, record.layer)

			if elapsed and length then
				local remaining = length - elapsed

				if remaining > 0 then
					local candidate = now + remaining - CAMERA_LEAD
					local ceiling = record.started + MAX_DURATION

					if candidate > ceiling then
						candidate = ceiling
					end

					if candidate > record.expires then
						record.expires = candidate
					end
				end
			end
		end

		local finished = not Unit.alive(unit) or not now or now >= record.expires

		if not finished and record.is_local then
			camera.hold(unit)

			if camera.mode() == "facing" then
				camera.update_facing(unit)
			end

			finished = cancel.should_cancel(unit, now)
		end

		if finished then
			M.stop(unit)
		end
	end
end

function M.stop_all()
	for unit, _ in pairs(active) do
		M.stop(unit)
	end
end

return M
