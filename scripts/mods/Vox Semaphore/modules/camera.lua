local mod = get_mod("Vox Semaphore")

local FACE_DISTANCE = 3.0
local EYE_HEIGHT = 1.7

local M = {}

local restore = nil

local function global_camera()
	local free_flight = Managers.free_flight

	if not free_flight or not free_flight._free_flight_cameras then
		return nil, nil
	end

	return free_flight, free_flight._free_flight_cameras.global
end

local PERSPECTIVES_REASON = "vox_semaphore_emote"

local function perspectives()
	local other = get_mod("Perspectives")

	if other and other.autoswitch and other.clear_reason then
		return other
	end

	return nil
end

local function force_third_person(unit, enabled)
	local other = perspectives()

	if other then
		if enabled then
			other.autoswitch(PERSPECTIVES_REASON, true, true)
		else
			other.clear_reason(PERSPECTIVES_REASON)
		end

		return "perspectives"
	end

	local first_person = ScriptUnit.has_extension(unit, "first_person_system")

	if not first_person then
		return false
	end

	first_person._force_third_person_mode = enabled

	return "direct"
end

local function free_flight_owner()
	local other = get_mod("camera_freeflight")

	if other and other.persistent_table then
		return other
	end

	return nil
end

local function enter_facing()
	local free_flight, camera_data = global_camera()

	if not (free_flight and camera_data) then
		return false
	end

	restore.free_flight = free_flight

	local owner = free_flight_owner()

	if owner then
		local data = owner:persistent_table("freeflight_data")

		restore.owner = owner
		restore.previous_enable = data.enable_freeflight
		restore.previous_ready = data.ready
		data.ready = true
		data.enable_freeflight = true

		return true
	end

	if not camera_data.active then
		free_flight:_enter_global_free_flight(camera_data)

		if not camera_data.active then
			restore.free_flight = nil

			return false
		end

		restore.entered_free_flight = true
	end

	return true
end

function M.hold(unit)
	if not restore or restore.applied_via ~= "direct" then
		return false
	end

	if not unit or not Unit.alive(unit) then
		return false
	end

	local first_person = ScriptUnit.has_extension(unit, "first_person_system")

	if not first_person then
		return false
	end

	if first_person._force_third_person_mode ~= true then
		M.reasserts = (M.reasserts or 0) + 1

		if M.reasserts <= 3 then
			mod.trace("camera: third person flag was cleared by something else; re-applying")
		end
	end

	first_person._force_third_person_mode = true

	return true
end

function M.update_facing(unit)
	if not (restore and restore.free_flight) or not Unit.alive(unit) then
		return false
	end

	local free_flight, camera_data = global_camera()

	if not (free_flight and camera_data and camera_data.active) then
		return false
	end

	local position = Unit.world_position(unit, 1)
	local rotation = Unit.world_rotation(unit, 1)
	local forward = Quaternion.forward(rotation)
	local flat = Vector3.normalize(Vector3(Vector3.x(forward), Vector3.y(forward), 0))
	local head = position + Vector3(0, 0, EYE_HEIGHT)
	local camera_position = head + flat * FACE_DISTANCE
	local look = Quaternion.look(Vector3.normalize(head - camera_position), Vector3.up())

	free_flight:teleport_camera("global", camera_position, look)

	return true
end

function M.enter(unit, mode)
	if restore then
		return false
	end

	restore = {
		unit = unit,
	}

	local first_person = ScriptUnit.has_extension(unit, "first_person_system")

	if first_person then
		restore.previous_force = first_person._force_third_person_mode
	end

	if mode == "facing" and enter_facing() then
		restore.mode = "facing"
	else
		if mode == "facing" then
			mod:info("facing camera unavailable; using over the shoulder")
		end

		restore.mode = "over_shoulder"
	end

	restore.applied_via = force_third_person(unit, true)

	local first_person = ScriptUnit.has_extension(unit, "first_person_system")

	mod.trace("camera enter mode=%s via=%s forced3p=%s",
		tostring(restore.mode), tostring(restore.applied_via),
		tostring(first_person and first_person._force_third_person_mode))

	return true
end

function M.exit()
	if not restore then
		return false
	end

	local unit = restore.unit

	if unit and Unit.alive(unit) then
		if restore.applied_via == "perspectives" then
			force_third_person(unit, false)
		else
			local first_person = ScriptUnit.has_extension(unit, "first_person_system")

			if first_person then
				first_person._force_third_person_mode = restore.previous_force
			end
		end
	end

	local free_flight = restore.free_flight

	if restore.owner then
		local data = restore.owner:persistent_table("freeflight_data")

		data.enable_freeflight = restore.previous_enable or false
		data.ready = restore.previous_ready or false
	end

	if free_flight and restore.entered_free_flight then
		local _, camera_data = global_camera()

		if camera_data and camera_data.active then
			local world_manager = Managers.world
			local world_name = camera_data.viewport_world_name
			local world = world_manager and world_name and world_manager:world(world_name)

			if world then
				free_flight:_exit_global_free_flight(camera_data)
			else
				camera_data.active = false
				camera_data.viewport_world_name = nil
			end
		end
	end

	restore = nil

	return true
end

function M.mode()
	return restore and restore.mode or nil
end

return M
