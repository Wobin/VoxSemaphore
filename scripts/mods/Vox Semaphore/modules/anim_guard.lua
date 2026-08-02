local mod = get_mod("Vox Semaphore")

local M = {}

local hooked = false
local enabled = false

M.cancelled = 0
M.blocked = 0

local CLASSES = {
	"PlayerUnitAnimationExtension",
	"AuthoritativePlayerUnitAnimationExtension",
	"PlayerHuskAnimationExtension",
}

local METHODS = {
	{ name = "anim_event", first_person = false },
	{ name = "anim_event_with_variable_float", first_person = false },
	{ name = "anim_event_with_variable_floats", first_person = false },
	{ name = "anim_event_with_variable_int", first_person = false },
	{ name = "anim_event_1p", first_person = true },
	{ name = "anim_event_with_variable_float_1p", first_person = true },
	{ name = "anim_event_with_variable_floats_1p", first_person = true },
}

local function playable(unit, event_name)
	return unit
		and Unit.alive(unit)
		and Unit.has_animation_state_machine(unit)
		and Unit.has_animation_event(unit, event_name)
end

local function make_guard(first_person)
	return function(func, self, event_name, ...)
		if not enabled or type(event_name) ~= "string" then
			return func(self, event_name, ...)
		end

		local emote = mod.emote
		local unit = self._unit

		if not (emote and unit and emote.is_emoting(unit)) then
			return func(self, event_name, ...)
		end

		local target = first_person and self._first_person_unit or unit

		if not target or not Unit.alive(target) or not Unit.has_animation_state_machine(target) then
			return func(self, event_name, ...)
		end

		if playable(target, event_name) then
			return func(self, event_name, ...)
		end

		emote.stop(unit)

		M.cancelled = M.cancelled + 1

		if not playable(target, event_name) then
			M.blocked = M.blocked + 1

			if M.blocked <= 5 then
				mod:warning("dropped anim event %s; the state machine could not be restored", tostring(event_name))
			end

			return
		end

		return func(self, event_name, ...)
	end
end

function M.install()
	enabled = true

	if hooked then
		return false
	end

	for i = 1, #CLASSES do
		for j = 1, #METHODS do
			local method = METHODS[j]

			mod:hook(CLASSES[i], method.name, make_guard(method.first_person))
		end
	end

	hooked = true

	return true
end

function M.remove()
	enabled = false

	return true
end

return M
