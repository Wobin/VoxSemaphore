local mod = get_mod("Vox Semaphore")

local GRACE = 0.5

local CANCEL_INPUTS = {
	"action_one_hold",
	"action_two_hold",
	"jump",
	"interact_hold",
	"grenade_ability_hold",
}

local M = {}

local watched = {}

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
