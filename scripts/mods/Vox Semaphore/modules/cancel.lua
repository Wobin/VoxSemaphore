local mod = get_mod("Vox Semaphore")

local GRACE = 0.5

local CANCEL_INPUTS = {
	"action_one_hold",
	"action_two_hold",
	"jump",
	"interact_hold",
	"grenade_ability_hold",
}

local TURN_LIMIT = math.pi * 25 / 180
local math_pi = math.pi
local math_abs = math.abs
local math_atan2 = math.atan2

local M = {}

local watched = {}

local function look_yaw(unit_data)
	local component = unit_data.read_component and unit_data:read_component("first_person")
	local rotation = component and component.rotation

	if not rotation then
		return nil
	end

	local forward = Quaternion.forward(rotation)

	return math_atan2(Vector3.y(forward), Vector3.x(forward))
end

local function yaw_delta(a, b)
	local d = a - b

	while d > math_pi do
		d = d - math_pi * 2
	end

	while d < -math_pi do
		d = d + math_pi * 2
	end

	return math_abs(d)
end

function M.watch(unit, now)
	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")

	if not unit_data then
		return false
	end

	local baseline = {}
	local input = ScriptUnit.has_extension(unit, "input_system")

	if input then
		for i = 1, #CANCEL_INPUTS do
			local name = CANCEL_INPUTS[i]

			baseline[name] = not not input:get(name)
		end
	end

	watched[unit] = {
		state_name = unit_data:read_component("character_state").state_name,
		grace_until = now + GRACE,
		baseline = baseline,
		look_yaw = look_yaw(unit_data),
	}

	return true
end

function M.forget(unit)
	watched[unit] = nil
end

function M.should_cancel(unit, now)
	local record = watched[unit]

	if not record then
		return false
	end

	if not Unit.alive(unit) then
		return true, "unit died"
	end

	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")

	if not unit_data then
		return true, "lost unit data"
	end

	local state_name = unit_data:read_component("character_state").state_name

	if state_name ~= record.state_name then
		return true, "character state changed to " .. tostring(state_name)
	end

	if now < record.grace_until then
		return false
	end

	local camera = mod.camera

	if record.look_yaw and camera and camera.mode and camera.mode() == "facing" then
		local yaw = look_yaw(unit_data)

		if yaw then
			local since_start = yaw_delta(yaw, record.look_yaw)
			local body = Quaternion.forward(Unit.world_rotation(unit, 1))
			local vs_body = yaw_delta(yaw, math_atan2(Vector3.y(body), Vector3.x(body)))

			if not record.next_turn_trace or now >= record.next_turn_trace then
				record.next_turn_trace = now + 0.5

				mod.trace("facing turn: since_start=%.0f vs_body=%.0f (limit %.0f)",
					math.deg(since_start), math.deg(vs_body), math.deg(TURN_LIMIT))
			end

			if since_start > TURN_LIMIT then
				return true, string.format("turned %.0f degrees from the facing camera",
					math.deg(since_start))
			end
		end
	end

	local input = ScriptUnit.has_extension(unit, "input_system")

	if not input then
		return false
	end

	local move = input:get("move")

	if move and Vector3.length_squared(move) > 0 then
		return true, "moved"
	end

	local baseline = record.baseline or {}

	for i = 1, #CANCEL_INPUTS do
		local name = CANCEL_INPUTS[i]
		local held = not not input:get(name)

		if held and not baseline[name] then
			return true, name
		end

		if not held then
			baseline[name] = false
		end
	end

	return false
end

function M.clear()
	watched = {}
end

return M
