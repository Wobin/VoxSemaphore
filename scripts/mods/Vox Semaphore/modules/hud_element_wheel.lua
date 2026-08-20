local mod = get_mod("Vox Semaphore")

local Definitions = require("scripts/ui/hud/elements/smart_tagging/hud_element_smart_tagging_definitions")
local Settings = require("scripts/ui/hud/elements/smart_tagging/hud_element_smart_tagging_settings")
local EmoteDefinitions = require("scripts/ui/hud/elements/emote_wheel/hud_element_emote_wheel_definitions")
local UIWidget = require("scripts/managers/ui/ui_widget")

local math_pi = math.pi
local math_sin = math.sin
local math_cos = math.cos
local math_min = math.min
local math_max = math.max
local math_smoothstep = math.smoothstep

local START_ANGLE = math_pi * 0.5
local BASE_SPACING = math_pi * 2 / 8
local MIN_PETAL_SCALE = 0.55

local BASE_MATERIAL = "content/ui/materials/base/ui_default_base"
local EMPTY_ICON = "content/ui/textures/icons/emotes/empty"

local SLICE_ROLES = {
	["content/ui/materials/hud/communication_wheel/slice_eighth"] = "fill",
	["content/ui/materials/hud/communication_wheel/slice_eighth_line"] = "line",
	["content/ui/materials/hud/communication_wheel/slice_eighth_highlight"] = "highlight",
}

local HudElementVoxSemaphoreWheel = class("HudElementVoxSemaphoreWheel", "HudElementBase")

local function icon_cache()
	local cache = mod:persistent_table("icon_cache")

	cache.loads = cache.loads or {}
	cache.ready = cache.ready or {}

	return cache
end

HudElementVoxSemaphoreWheel._request_icon = function(self, item)
	if not item.name then
		return false
	end

	local key = tostring(item.name) .. "|" .. tostring(item.icon)

	if self._icon_ready[key] then
		return true
	end

	if self._icon_loads[key] then
		return false
	end

	local ready = self._icon_ready

	self._icon_loads[key] = Managers.ui:load_item_icon(item, function()
		ready[key] = true
	end)

	return false
end

HudElementVoxSemaphoreWheel._release_all_icons = function(self, ui_renderer)
	local entries = self._entries or {}

	for i = 1, #entries do
		local widget = entries[i].widget
		local icon_style = widget and widget.style and widget.style.icon
		local values = icon_style and icon_style.material_values

		if values then
			values.texture_map = EMPTY_ICON
			values.use_placeholder_texture = 1
		end

		if widget and ui_renderer then
			UIWidget.set_visible(widget, ui_renderer, false)
		end
	end

	local held = 0

	for _ in pairs(self._icon_loads) do
		held = held + 1
	end

	if held > 0 then
		mod:info("kept %d emote icons loaded for reuse across reloads", held)
	end
end

HudElementVoxSemaphoreWheel.init = function(self, parent, draw_layer, start_scale)
	HudElementVoxSemaphoreWheel.super.init(self, parent, draw_layer, start_scale, Definitions)

	local cache = icon_cache()

	self._entries = {}
	self._entry_count = 0
	self._progress = 0
	self._icon_loads = cache.loads
	self._icon_ready = cache.ready
end

HudElementVoxSemaphoreWheel._setup_entries = function(self, num_entries)
	local entries = self._entries

	if entries then
		for i = 1, #entries do
			local record = entries[i]

			if record.widget then
				self:_unregister_widget_name(record.widget.name)
			end
		end
	end

	local created = {}
	local definition = EmoteDefinitions.entry_widget_definition or Definitions.entry_widget_definition

	for i = 1, num_entries do
		local widget = self:_create_widget("vox_semaphore_entry_" .. i, definition)
		local base = {}

		for key, style in pairs(widget.style) do
			if type(style) == "table" and type(style.size) == "table" then
				base[key] = { style.size[1], style.size[2] }
			end
		end

		created[i] = {
			widget = widget,
			base_size = base,
			slices = self:_find_slice_passes(widget),
			bound_rank = nil,
		}
	end

	self._entries = created
	self._entry_count = num_entries
end

HudElementVoxSemaphoreWheel._find_slice_passes = function(self, widget)
	local found = {}
	local passes = widget.passes

	if not passes then
		return found
	end

	for i = 1, #passes do
		local pass = passes[i]
		local value_id = pass.value_id

		if value_id then
			local role = SLICE_ROLES[widget.content[value_id]]

			if role then
				found[role] = { value_id = value_id, style_id = pass.style_id }
			end
		end
	end

	return found
end

local art_state = {}

local function note_art(rank, ok, detail)
	local key = tostring(rank)

	if art_state[key] == ok then
		return
	end

	art_state[key] = ok

	if ok then
		mod.trace("petal art: %s bound (%s)", key, tostring(detail))

		return
	end

	mod.trace("petal art: %s MISSING (%s) - those petals keep the previously bound rank's size, "
		.. "so they draw too wide and overlap, while the clickable wedge stays at the correct "
		.. "spacing and is much smaller than it looks. Check SimpleAssets is installed and that "
		.. "assets/slice_%s*.png shipped.", key, tostring(detail), key)
end

HudElementVoxSemaphoreWheel._bind_slice_art = function(self, record, rank)
	local art = mod.slice_art

	if not art then
		note_art(rank, false, "slice_art module not loaded")

		return false
	end

	local set = art.get(rank)
	local size = art.size(rank)

	if not (set and size) then
		note_art(rank, false, string.format("textures=%s size=%s ready=%s",
			tostring(set ~= nil), tostring(size ~= nil), tostring(art.is_ready and art.is_ready())))

		return false
	end

	note_art(rank, true, string.format("%dx%d", size[1], size[2]))

	local widget = record.widget

	for role, pass in pairs(record.slices) do
		local texture = set[role]
		local style = pass.style_id and widget.style[pass.style_id]

		if texture and style then
			widget.content[pass.value_id] = BASE_MATERIAL

			local values = style.material_values

			if not values then
				values = {}
				style.material_values = values
			end

			values.texture_map = texture
			values.use_placeholder_texture = 0
		end
	end

	record.bound_rank = rank
	record.slice_size = size

	return true
end

HudElementVoxSemaphoreWheel._drawn_radius = function(self, target_radius)
	local progress = math_smoothstep(self._progress, 0, 1)
	local outer = target_radius or Settings.max_radius

	return Settings.min_radius + progress * (outer - Settings.min_radius)
end

HudElementVoxSemaphoreWheel._mark_target = function(self, hovered_entry, fallback_radius)
	local art = mod.slice_art
	local geometry = art and art.geometry
	local base = geometry and geometry.rank1
	local band = geometry and hovered_entry and hovered_entry.rank and geometry[hovered_entry.rank]

	if band and band.inner and base and base.inner then
		return band.inner + (self._mark_reach - base.inner)
	end

	local radius = (hovered_entry and hovered_entry.radius) or fallback_radius or Settings.max_radius

	return radius * self._mark_reach / Settings.max_radius
end

HudElementVoxSemaphoreWheel._layout_entries = function(self, source)
	local entries = self._entries
	local count = #entries

	if count == 0 then
		return
	end

	local fallback = math_pi * 2 / count
	local art = mod.slice_art
	local base_radius = (art and art.geometry.rank1 and art.geometry.rank1.radius) or Settings.max_radius
	local base_chord = base_radius * math_sin(BASE_SPACING * 0.5)
	local generation = art and art.generation()

	for i = 1, count do
		local record = entries[i]
		local widget = record.widget
		local entry = source and source[i]
		local target_radius = (entry and entry.radius) or Settings.max_radius
		local radius = self:_drawn_radius(target_radius)
		local spacing = (entry and entry.spacing) or fallback
		local rank = (entry and entry.rank) or (art and art.rank_for_radius(target_radius))
		local rank_radius = rank and art and art.geometry[rank] and art.geometry[rank].radius
		local grow = (rank_radius and rank_radius > 0) and (radius / rank_radius) or 1

		if grow > 1 then
			grow = 1
		end

		local chord = radius * math_sin(spacing * 0.5) / base_chord

		if chord > 1 then
			chord = 1
		elseif chord < MIN_PETAL_SCALE then
			chord = MIN_PETAL_SCALE
		end

		local angle = (entry and entry.angle) or (START_ANGLE + (i - 1) * fallback)
		local offset = widget.offset

		widget.content.angle = angle
		offset[1] = math_sin(angle) * radius
		offset[2] = math_cos(angle) * radius

		if rank and (record.bound_rank ~= rank or record.bound_generation ~= generation) then
			if self:_bind_slice_art(record, rank) then
				record.bound_generation = generation
			end
		end

		local slice_size = record.slice_size

		if slice_size then
			for _, pass in pairs(record.slices) do
				local style = pass.style_id and widget.style[pass.style_id]

				if style and style.size then
					local w = slice_size[1] * grow
					local h = slice_size[2] * grow

					style.size[1] = w
					style.size[2] = h

					local pivot = style.pivot

					if not pivot then
						pivot = {}
						style.pivot = pivot
					end

					pivot[1] = w * 0.5
					pivot[2] = h * 0.5
				end
			end
		end

		local icon_style = widget.style.icon
		local icon_base = record.base_size.icon

		if icon_style and icon_style.size and icon_base then
			local factor = record.hide_icon and 0 or chord

			icon_style.size[1] = icon_base[1] * factor
			icon_style.size[2] = icon_base[2] * factor
		end
	end
end

HudElementVoxSemaphoreWheel._sync = function(self, dt)
	local wheel = mod.wheel
	local presentation = wheel and wheel.presentation and wheel.presentation()
	local open = presentation ~= nil
	local step = dt * (Settings.anim_speed or 25)

	if open then
		self._progress = math_min(1, self._progress + step)
	else
		self._progress = math_max(0, self._progress - step)
	end

	local background = self._widgets_by_name and self._widgets_by_name.wheel_background

	if background then
		background.visible = self._progress > 0

		if open then
			local content = background.content
			local hovered_entry = presentation.hovered and presentation.entries and presentation.entries[presentation.hovered]
			local label = hovered_entry and hovered_entry.label

			content.angle = presentation.cursor_angle or 0
			content.force_hover = label ~= nil
			content.text = label or presentation.center_text or ""

			local mark_style = background.style and background.style.mark

			if mark_style then
				if mark_style.color then
					mark_style.color[1] = label and 255 or 0
				end

				if not self._mark_reach and mark_style.offset and mark_style.pivot and mark_style.size then
					self._mark_reach = -mark_style.offset[2]
					self._mark_half = mark_style.size[2] * 0.5
				end

				if self._mark_reach then
					local reach = self:_drawn_radius(self:_mark_target(hovered_entry, presentation.radius))

					mark_style.offset[2] = -reach
					mark_style.pivot[2] = self._mark_half + reach
				end
			end
		end
	end

	if not open then
		local entries = self._entries

		for i = 1, #entries do
			entries[i].widget.visible = false
		end

		return
	end

	local count = presentation.count or 0

	if count > self._entry_count then
		self:_setup_entries(count)
	end

	local entries = self._entries
	local source = presentation.entries

	for i = 1, #entries do
		local widget = entries[i].widget
		local entry = source and source[i]
		local content = widget.content

		if entry then
			local label = entry.label or ""

			if entry.count then
				label = label .. " (" .. tostring(entry.count) .. ")"
			end

			local icon_style = widget.style and widget.style.icon
			local material_values = icon_style and icon_style.material_values

			if entry.item and entry.icon and material_values then
				content.text = ""
				entries[i].hide_icon = false

				if self:_request_icon(entry.item) then
					material_values.texture_map = entry.icon
					material_values.use_placeholder_texture = 0
				else
					material_values.use_placeholder_texture = 1
				end
			else
				content.text = label
				entries[i].hide_icon = true

				if material_values then
					material_values.use_placeholder_texture = 1
				end
			end

			widget.visible = true
			widget.alpha_multiplier = entry.alpha or 1

			local hotspot = content.hotspot

			if hotspot then
				local is_hover = presentation.hovered == i

				hotspot.is_hover = is_hover
				hotspot.anim_hover_progress = is_hover and 1 or 0
				hotspot.anim_select_progress = hotspot.anim_select_progress or 0
				hotspot.anim_focus_progress = hotspot.anim_focus_progress or 0
				hotspot.anim_input_progress = hotspot.anim_input_progress or 0
			end
		else
			widget.visible = false
		end
	end

	self:_layout_entries(source)
end

HudElementVoxSemaphoreWheel.update = function(self, dt, t, ui_renderer, render_settings, input_service)
	HudElementVoxSemaphoreWheel.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	local wheel = mod.wheel

	if wheel and wheel.update_presentation then
		local ok, err = pcall(wheel.update_presentation, input_service, render_settings)

		if not ok then
			mod:error("emote wheel update failed: " .. tostring(err))
		end
	end

	local ok, err = pcall(self._sync, self, dt)

	if not ok then
		mod:error("emote wheel sync failed: " .. tostring(err))
	end
end

HudElementVoxSemaphoreWheel._draw_entries = function(self, ui_renderer, render_settings)
	local progress = self._progress

	if progress <= 0 then
		return
	end

	render_settings.alpha_multiplier = progress

	local entries = self._entries

	for i = 1, #entries do
		local widget = entries[i].widget

		if widget.visible then
			UIWidget.draw(widget, ui_renderer)
		end
	end
end

HudElementVoxSemaphoreWheel._draw_widgets = function(self, dt, t, input_service, ui_renderer, render_settings)
	local ok, err = pcall(self._draw_entries, self, ui_renderer, render_settings)

	if not ok then
		mod:error("emote wheel draw failed: " .. tostring(err))
	end

	HudElementVoxSemaphoreWheel.super._draw_widgets(self, dt, t, input_service, ui_renderer, render_settings)
end

HudElementVoxSemaphoreWheel.destroy = function(self, ui_renderer)
	self:_release_all_icons(ui_renderer)

	HudElementVoxSemaphoreWheel.super.destroy(self, ui_renderer)

	local wheel = mod.wheel

	if wheel and wheel.notify_element_destroyed then
		wheel.notify_element_destroyed()
	end
end

return HudElementVoxSemaphoreWheel
