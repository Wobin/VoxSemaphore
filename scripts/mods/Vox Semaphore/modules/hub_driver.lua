local mod = get_mod("Vox Semaphore")

local M = {}

function M.equipped_events()
	local inventory = mod.emote_inventory

	return inventory and inventory.equipped_events()
end

local hooked = false

function M.install()
	if hooked then
		return true
	end

	if not (CLASS and CLASS.HudElementEmoteWheel) then
		return false
	end

	hooked = true

	mod:hook("HudElementEmoteWheel", "_is_wheel_entry_hovered", function(func, self, t)
		local wheel = mod.wheel

		if wheel and wheel.hub_has_hover and wheel.hub_has_hover() then
			return nil
		end

		return func(self, t)
	end)

	mod:hook_safe("HudElementEmoteWheel", "_on_wheel_start", function()
		local wheel = mod.wheel

		if wheel and wheel.prefetch then
			wheel.prefetch()
		end
	end)

	mod:hook("HudElementEmoteWheel", "_update_wheel_presentation", function(func, self, ...)
		local wheel = mod.wheel

		if not (wheel and wheel.hub_has_hover and wheel.hub_has_hover()) then
			return func(self, ...)
		end

		local entries = self._entries or {}

		for i = 1, #entries do
			local content = entries[i].widget and entries[i].widget.content

			if content and content.hotspot then
				content.hotspot.force_hover = false
			end
		end

		local background = self._widgets_by_name and self._widgets_by_name.wheel_background

		if background then
			background.content.text = ""
			background.content.force_hover = false

			local mark = background.style and background.style.mark

			if mark and mark.color then
				mark.color[1] = 0
			end
		end
	end)

	mod:hook_safe("HudElementEmoteWheel", "_on_wheel_stop", function()
		local wheel = mod.wheel

		if wheel and wheel.hub_commit then
			wheel.hub_commit()
		end
	end)

	mod:hook_safe("HudElementEmoteWheel", "update", function(self)
		local wheel = mod.wheel

		if not (wheel and wheel.hub_sync) then
			return
		end

		wheel.hub_sync(self._wheel_active and true or false, M.equipped_events)
	end)

	return true
end

function M.status()
	local wheel = mod.wheel
	local excluded = M.equipped_events()
	local count = 0

	for _ in pairs(excluded or {}) do
		count = count + 1
	end

	return string.format("hub_driver excluded=%d wheel_open=%s", count,
		tostring(wheel and wheel.is_open and wheel.is_open()))
end

return M
