local mod = get_mod("Vox Semaphore")

local GUARDED = {
	"rpc_player_anim_event",
	"rpc_player_anim_event_variable_float",
	"rpc_player_anim_event_variable_floats",
	"rpc_player_anim_event_variable_int",
	"rpc_sync_anim_state",
}

local TAKES_LEVEL_UNIT = {
	rpc_sync_anim_state = true,
}

local M = {}

local suppressed = {}
local hooked = false
local enabled = false

M.dropped = 0
M.faulted = 0

function M.is_suppressed(unit)
	return suppressed[unit] == true
end

function M.suppress(unit)
	suppressed[unit] = true
end

function M.release(unit)
	suppressed[unit] = nil
end

function M.count()
	local n = 0
	for _ in pairs(suppressed) do
		n = n + 1
	end
	return n
end

function M.install()
	enabled = true

	if hooked then
		return false
	end

	for i = 1, #GUARDED do
		local name = GUARDED[i]
		local takes_level_unit = TAKES_LEVEL_UNIT[name]

		mod:hook("AnimationSystem", name, function(func, self, channel_id, unit_id, fourth, ...)
			if not enabled then
				return func(self, channel_id, unit_id, fourth, ...)
			end

			local unit_spawner = Managers.state and Managers.state.unit_spawner
			local unit = unit_spawner and (takes_level_unit
				and unit_spawner:unit(unit_id, fourth)
				or unit_spawner:unit(unit_id))

			if unit and suppressed[unit] then
				M.dropped = M.dropped + 1

				return
			end

			local ok, a, b, c = pcall(func, self, channel_id, unit_id, fourth, ...)

			if not ok then
				M.faulted = M.faulted + 1

				if M.faulted <= 5 then
					mod:warning("dropped a replicated anim event: %s", tostring(a))
				end

				return
			end

			return a, b, c
		end)
	end

	hooked = true

	return true
end

function M.remove()
	local held = M.count()

	if held > 0 then
		mod:warning("keeping anim suppression armed for %d unrestored unit(s)", held)

		return false
	end

	enabled = false
	suppressed = {}

	return true
end

return M
