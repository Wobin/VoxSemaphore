local mod = get_mod("Vox Semaphore")

local UISoundEvents = require("scripts/settings/ui/ui_sound_events")
local WeaponTemplates = require("scripts/settings/equipment/weapon_templates/weapon_templates")

local ELEMENT_CLASS = "HudElementVoxSemaphoreWheel"
local ELEMENT_FILE = "Vox Semaphore/scripts/mods/Vox Semaphore/modules/hud_element_wheel"
local HUB_HUD_ELEMENTS = "scripts/ui/hud/hud_elements_player_hub"

local suppression = mod.suppression
local emote = mod.emote
local emote_inventory = mod.emote_inventory

if not (suppression and emote and emote_inventory) then
	mod:error("wheel module loaded before its dependencies; check module load order")

	return {
		ELEMENT_CLASS = ELEMENT_CLASS,
		ELEMENT_FILE = ELEMENT_FILE,
		install = function() return false end,
		on_unload = function() end,
		toggle = function() end,
		open = function() return false, "dependencies missing" end,
		close = function() return false end,
		is_open = function() return false end,
		update_presentation = function() end,
		presentation = function() return nil end,
		notify_element_destroyed = function() end,
		refresh = function() end,
		prefetch = function() return false end,
		blocks_smart_tag = function() return false end,
		status = function() return "dependencies missing" end,
	}
end

local CURSOR_NAME = "VoxSemaphoreWheel"

local KNOWN_CATEGORIES = {
	greeting = true,
	affirmative = true,
	negative = true,
	personality = true,
	ogryn = true,
	cryptic = true,
	veteran = true,
}

local CATEGORY_HEAD = {
	"greeting",
	"affirmative",
	"negative",
	"personality",
}

local SHARED_CATEGORIES = {
	greeting = true,
	affirmative = true,
	negative = true,
	personality = true,
}

local TOP_ANGLE = math.pi
local SLICE_SPACING = math.pi * 2 / 8
local L2_TIGHTEN = 0.7

local DEAD_ZONE = 120
local L1_RADIUS = 190
local DESCEND_FALLBACK = 259
local L2_RADIUS = 320
local MAX_ENTRIES = 12
local DIM_ALPHA = 0.5
local HUB_ARC_SPACING = math.pi * 2 / 8 * 3 / 5
local HUB_BOTTOM_ANGLE = math.pi * 2
local HUB_SAFE_HALF = math.pi * 2 / 360 * (90 - 26)
local SMART_TAG_GRACE = 0.25
local START_ANGLE = math.pi / 2

local math_pi = math.pi
local math_angle = math.angle
local math_distance_2d = math.distance_2d
local math_radians_to_degrees = math.radians_to_degrees

local M = {}

M.ELEMENT_CLASS = ELEMENT_CLASS
M.ELEMENT_FILE = ELEMENT_FILE

local EMPTY = {}

local inventory = emote_inventory.data

local probed = {}

local state = {
	open = false,
	level = 1,
	hovered = nil,
	category = nil,
	frames_open = 0,
	cursor_pushed = false,
	camera_locked = false,
	block_until = nil,
	warned = false,
}

local model = nil
local view = nil

local presentation_table = {
	level = 1,
	radius = L1_RADIUS,
	hovered = nil,
	center_text = "",
	breadcrumb = "",
	count = 0,
	entries = EMPTY,
	cursor_angle = 0,
}

-- ────────────────────────────────────────────────────────────────────────────
-- Inventory
-- ────────────────────────────────────────────────────────────────────────────

local function local_player()
	local player_manager = Managers.player

	if not (player_manager and player_manager.local_player_safe) then
		return nil
	end

	return player_manager:local_player_safe(1)
end

local function local_player_unit()
	local player = local_player()

	return player and player.player_unit
end

function M.prefetch()
	return emote_inventory.prefetch()
end

function M.refresh()
	emote_inventory.clear()

	probed = {}
	model = nil
	view = nil

	return emote_inventory.prefetch()
end

-- ────────────────────────────────────────────────────────────────────────────
-- Breed playability probe
-- ────────────────────────────────────────────────────────────────────────────

local function hub_template_for(breed_name)
	if breed_name == "ogryn" then
		return WeaponTemplates.unarmed_hub_ogryn
	end

	return WeaponTemplates.unarmed_hub_human
end

local function ensure_probe(unit)
	if not Unit.alive(unit) then
		return nil
	end

	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
	local visual_loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
	local animation = ScriptUnit.has_extension(unit, "animation_system")

	if not (unit_data and visual_loadout and animation) then
		return nil
	end

	local breed_name = unit_data:breed_name()

	if type(breed_name) ~= "string" then
		return nil
	end

	local known = probed[breed_name]

	if not known then
		known = {}
		probed[breed_name] = known
	end

	local order = inventory.order
	local pending = {}

	for i = 1, #order do
		local event = order[i]

		if known[event] == nil then
			pending[#pending + 1] = event
		end
	end

	if #pending == 0 or emote.is_emoting(unit) then
		return breed_name, known
	end

	local slot = unit_data:read_component("inventory").wielded_slot
	local template = visual_loadout:weapon_template_from_slot(slot)

	if not template then
		return breed_name, nil
	end

	local hub_template = hub_template_for(breed_name)

	if not hub_template then
		return breed_name, nil
	end

	suppression.suppress(unit)
	animation:inventory_slot_wielded(hub_template)

	for i = 1, #pending do
		local event = pending[i]

		known[event] = Unit.has_animation_event(unit, event) and true or false
	end

	animation:inventory_slot_wielded(template)
	suppression.release(unit)

	return breed_name, known
end

-- ────────────────────────────────────────────────────────────────────────────
-- Categories
-- ────────────────────────────────────────────────────────────────────────────

local function category_of(event)
	local key = string.match(event, "^emote_(%a+)_%d+$")

	if not key then
		key = string.match(event, "^emote_(%a+)_")
	end

	if not key or key == "" then
		return "other"
	end

	if not SHARED_CATEGORIES[key] then
		return "personality"
	end

	return key
end

local function category_label(key)
	if type(key) ~= "string" or key == "" then
		return ""
	end

	if KNOWN_CATEGORIES[key] then
		local text = mod:localize("wheel_category_" .. key)

		if type(text) == "string" and text ~= "" then
			return text
		end
	end

	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

local function build_model(unit, excluded)
	local breed_name, playable = ensure_probe(unit)

	if breed_name then
		emote_inventory.resolve(breed_name)
	end

	local order = inventory.order
	local by_category = {}
	local seen = {}
	local keys = {}

	for i = 1, #order do
		local event = order[i]
		local record = inventory.by_event[event]
		local allowed = record ~= nil

		if playable and playable[event] == false then
			allowed = false
		end

		if excluded and excluded[event] then
			allowed = false
		end


		if allowed then
			local key = category_of(event)
			local bucket = by_category[key]

			if not bucket then
				bucket = {}
				by_category[key] = bucket
				seen[key] = true
				keys[#keys + 1] = key
			end

			bucket[#bucket + 1] = inventory.by_event[event]
		end
	end

	local ordered = {}
	local used = {}

	for i = 1, #CATEGORY_HEAD do
		local key = CATEGORY_HEAD[i]

		if seen[key] and not used[key] then
			ordered[#ordered + 1] = key
			used[key] = true
		end
	end

	local rest = {}

	for i = 1, #keys do
		local key = keys[i]

		if not used[key] then
			rest[#rest + 1] = key
		end
	end

	table.sort(rest)

	for i = 1, #rest do
		ordered[#ordered + 1] = rest[i]
	end

	return {
		categories = ordered,
		by_category = by_category,
		probed = playable ~= nil,
	}
end

-- ────────────────────────────────────────────────────────────────────────────
-- View
-- ────────────────────────────────────────────────────────────────────────────

local function trim_entries(entries)
	if #entries <= MAX_ENTRIES then
		return entries
	end

	if not state.warned then
		state.warned = true

		mod:warning("emote wheel holds %d entries; only the first %d are shown", #entries, MAX_ENTRIES)
	end

	for i = #entries, MAX_ENTRIES + 1, -1 do
		entries[i] = nil
	end

	return entries
end

local function layout_angles(entries, clustered, center, spacing_override)
	local count = #entries

	if count < 1 then
		return nil
	end

	local spacing = spacing_override or (clustered and SLICE_SPACING or (math_pi * 2 / count))
	local middle = center or TOP_ANGLE
	local first = clustered and (middle - (count - 1) * spacing * 0.5) or START_ANGLE

	for i = 1, count do
		entries[i].angle = first + (i - 1) * spacing
	end

	return spacing
end

local function stamp_rank(entries, rank, radius, spacing, alpha, into)
	for i = 1, #entries do
		local entry = entries[i]

		entry.rank = rank
		entry.radius = radius
		entry.spacing = spacing
		entry.alpha = alpha

		into[#into + 1] = entry
	end
end

local function rebuild_view()
	local categories = {}
	local emotes = {}

	if model then
		local keys = model.categories

		for i = 1, #keys do
			local key = keys[i]
			local bucket = model.by_category[key]
			local sample = bucket[1]

			categories[#categories + 1] = {
				key = key,
				label = category_label(key),
				count = #bucket,
				icon = sample and sample.icon,
				item = sample and sample.item,
			}
		end

		local bucket = state.category and model.by_category[state.category]

		if bucket then
			for i = 1, #bucket do
				emotes[#emotes + 1] = {
					event = bucket[i].event,
					label = bucket[i].label,
					icon = bucket[i].icon,
					item = bucket[i].item,
				}
			end
		end
	end

	categories = trim_entries(categories)
	emotes = trim_entries(emotes)

	local hub = state.hub
	local cat_rank = hub and "hub_category" or "rank1"
	local cat_spacing = layout_angles(categories, true,
		hub and HUB_BOTTOM_ANGLE or nil,
		hub and HUB_ARC_SPACING or nil)
	local emote_spacing = nil

	if #emotes > 0 then
		local spacing = SLICE_SPACING * (L1_RADIUS / L2_RADIUS) * L2_TIGHTEN
		local centre = state.category_angle

		if hub and centre then
			local limit = HUB_SAFE_HALF - (#emotes - 1) * spacing * 0.5
			local offset = centre - HUB_BOTTOM_ANGLE

			if limit > 0 then
				if offset > limit then
					centre = HUB_BOTTOM_ANGLE + limit
				elseif offset < -limit then
					centre = HUB_BOTTOM_ANGLE - limit
				end
			else
				centre = HUB_BOTTOM_ANGLE
			end
		end

		emote_spacing = layout_angles(emotes, true, centre, spacing)
	end

	local on_emotes = state.level == 2
	local flat = {}

	stamp_rank(categories, cat_rank, L1_RADIUS, cat_spacing, on_emotes and DIM_ALPHA or 1, flat)
	stamp_rank(emotes, "rank2", L2_RADIUS, emote_spacing, on_emotes and 1 or DIM_ALPHA, flat)

	view = {
		entries = flat,
	}
end

local function ensure_model(unit)
	if model then
		return
	end

	if not (inventory.ready and unit) then
		return
	end

	local built = build_model(unit, state.excluded)

	if not (built and built.probed) then
		return
	end

	model = built

	rebuild_view()
end

local function play_sound(event_name)
	local ui_manager = Managers.ui

	if ui_manager and ui_manager.play_2d_sound and event_name then
		ui_manager:play_2d_sound(event_name)
	end
end

local function set_hovered(entry)
	if state.hovered == entry then
		return
	end

	state.hovered = entry

	if entry then
		play_sound(UISoundEvents.emote_wheel_entry_hover)
	end
end

local function set_level(level, category)
	if state.level == level and state.category == category then
		return
	end

	state.level = level
	state.category = category
	state.hovered = nil

	if not category then
		state.category_angle = nil
	end

	rebuild_view()
end

local function descend_radius()
	local art = mod.slice_art
	local geometry = art and art.geometry
	local first = geometry and geometry.rank1
	local second = geometry and geometry.rank2

	if first and second and first.outer and second.inner then
		return (first.outer + second.inner) * 0.5
	end

	return DESCEND_FALLBACK
end

local function pick_in_rank(cursor_degrees, entries, rank)
	for i = 1, (entries and #entries or 0) do
		local entry = entries[i]

		if entry.rank == rank and entry.angle and entry.spacing then
			local half = math_radians_to_degrees(entry.spacing) * 0.5
			local entry_degrees = (-math_radians_to_degrees(entry.angle)) % 360
			local diff = (entry_degrees - cursor_degrees + 180 + 360) % 360 - 180

			if diff <= half and diff >= -half then
				return entry
			end
		end
	end

	return nil
end

-- ────────────────────────────────────────────────────────────────────────────
-- Cursor and camera lock
-- ────────────────────────────────────────────────────────────────────────────

local function push_cursor()
	if state.cursor_pushed then
		return
	end

	local input_manager = Managers.input

	if not (input_manager and input_manager.push_cursor) then
		return
	end

	input_manager:push_cursor(CURSOR_NAME)

	state.cursor_pushed = true

	if input_manager.set_cursor_position then
		input_manager:set_cursor_position(CURSOR_NAME, Vector3(0.5, 0.5, 0))
	end
end

local function pop_cursor()
	if not state.cursor_pushed then
		return
	end

	state.cursor_pushed = false

	local input_manager = Managers.input

	if input_manager and input_manager.pop_cursor then
		input_manager:pop_cursor(CURSOR_NAME)
	end
end

local function set_camera_lock(locked)
	if state.camera_locked == locked then
		return
	end

	local event_manager = Managers.event

	if not (event_manager and event_manager.trigger) then
		return
	end

	state.camera_locked = locked

	event_manager:trigger("event_set_emote_wheel_state", locked and "camera_lock" or "inactive")
end

-- ────────────────────────────────────────────────────────────────────────────
-- Public surface
-- ────────────────────────────────────────────────────────────────────────────

function M.is_open()
	return state.open == true
end

function M.blocks_smart_tag(t)
	if state.open then
		if type(t) == "number" then
			state.block_until = t + SMART_TAG_GRACE
		end

		return true
	end

	local block_until = state.block_until

	if block_until and type(t) == "number" and t < block_until then
		return true
	end

	state.block_until = nil

	return false
end

local function ensure_art()
	local art = mod.slice_art

	if art and art.ensure and not art.is_ready() then
		art.ensure()
	end
end

local function open_wheel(hub, excluded_provider)
	ensure_art()

	if state.open then
		return false, "already open"
	end

	if not mod:is_enabled() then
		return false, "mod is disabled"
	end

	local unit = local_player_unit()

	if not (unit and Unit.alive(unit)) then
		return false, "no living local player unit"
	end

	if not hub then
		if M.vanilla_wheel_present() then
			return false, "the vanilla emote wheel is present here"
		end

		local ui_manager = Managers.ui

		if not (ui_manager and ui_manager._hud) then
			return false, "no mission hud"
		end

		if ui_manager.using_input and ui_manager:using_input() then
			return false, "a menu is using input"
		end
	end

	M.prefetch()

	state.hub = hub
	state.excluded = excluded_provider and excluded_provider() or nil
	state.open = true
	state.level = 1
	state.category = nil
	state.hovered = nil
	state.frames_open = 0
	state.warned = false
	state.category_angle = nil
	model = nil
	view = nil

	ensure_model(unit)

	if not view then
		rebuild_view()
	end

	if not hub then
		push_cursor()
		set_camera_lock(true)
		play_sound(UISoundEvents.emote_wheel_open)
	end

	return true
end

function M.open()
	return open_wheel(false, nil)
end

function M.hub_sync(active, excluded)
	if active then
		if not state.open then
			open_wheel(true, excluded)
		end

		return
	end

	if state.open and state.hub then
		M.close(false)
	end
end

function M.hub_has_hover()
	return state.open and state.hub and state.hovered ~= nil
end

function M.hub_commit()
	if state.open and state.hub then
		M.close(true)
	end
end

function M.model_for(unit, excluded)
	if not (inventory.ready and unit) then
		return nil
	end

	local built = build_model(unit, excluded)

	if not (built and built.probed) then
		return nil
	end

	return built
end

M.layout_angles = layout_angles
M.pick_in_rank = pick_in_rank
M.category_label = category_label
M.HUB_ARC_SPACING = HUB_ARC_SPACING
M.L1_RADIUS = L1_RADIUS
M.L2_RADIUS = L2_RADIUS
M.L2_SPACING = SLICE_SPACING * (L1_RADIUS / L2_RADIUS) * L2_TIGHTEN

function M.vanilla_wheel_present()
	local mission_manager = Managers.state and Managers.state.mission

	if not (mission_manager and mission_manager.mission_name) then
		return false
	end

	local templates = require("scripts/settings/mission/mission_templates")
	local settings = templates and templates[mission_manager:mission_name()]

	return settings ~= nil and settings.hud_elements == HUB_HUD_ELEMENTS
end

function M.close(commit)
	if not state.open then
		pop_cursor()
		set_camera_lock(false)

		return false
	end

	local chosen = nil

	if commit and state.hovered then
		chosen = state.hovered.event
	end

	local hub = state.hub

	state.hub = false
	state.excluded = nil
	state.open = false
	state.level = 1
	state.category = nil
	state.hovered = nil
	state.frames_open = 0
	state.category_angle = nil
	model = nil
	view = nil

	if not hub then
		pop_cursor()
		set_camera_lock(false)
		play_sound(chosen and UISoundEvents.emote_wheel_entry_select or UISoundEvents.emote_wheel_close)
	end

	if chosen then
		if type(mod.play_self_emote) == "function" then
			local ok, err = mod.play_self_emote(chosen)

			if not ok then
				mod:info("emote %s not played: %s", tostring(chosen), tostring(err))
			end
		else
			mod:error("mod.play_self_emote is missing; the wheel cannot fire an emote")
		end
	end

	return true
end

function M.toggle(is_pressed)
	if is_pressed then
		local ok, reason = M.open()

		if not ok and reason then
			mod:info("emote wheel not opened: %s", tostring(reason))
		end

		return
	end

	if state.hub then
		return
	end

	M.close(true)
end

function M.update_presentation(input_service, render_settings)
	if not state.open then
		return
	end

	ensure_model(local_player_unit())

	state.frames_open = state.frames_open + 1

	if state.frames_open < 2 then
		return
	end

	if not (input_service and input_service.get and render_settings) then
		return
	end

	local resolution = RESOLUTION_LOOKUP

	if not resolution then
		return
	end

	local cursor = input_service:get("cursor")

	if not cursor then
		return
	end

	local scale = render_settings.scale or 1
	local center_x = resolution.width * 0.5
	local center_y = resolution.height * 0.5
	local distance = math_distance_2d(center_x, center_y, cursor[1], cursor[2])

	if distance <= DEAD_ZONE * scale then
		set_level(1, nil)
		set_hovered(nil)

		return
	end

	local angle = math_angle(center_x, center_y, cursor[1], cursor[2]) - math_pi * 0.5

	state.cursor_angle = angle

	local degrees = math_radians_to_degrees(angle) % 360
	local entries = view and view.entries

	if not entries or #entries == 0 then
		set_hovered(nil)

		return
	end

	local cat_rank = state.hub and "hub_category" or "rank1"
	local want = distance > descend_radius() * scale and 2 or 1
	local entry = pick_in_rank(degrees, entries, want == 2 and "rank2" or cat_rank)

	if want == 1 then
		local key = entry and entry.key

		if key and key ~= state.category then
			state.category_angle = entry.angle
		end

		if state.level ~= 1 or (key and key ~= state.category) then
			set_level(1, key or state.category)

			entry = pick_in_rank(degrees, view and view.entries, cat_rank)
		end

		set_hovered(entry)

		return
	end

	if not entry then
		local category = pick_in_rank(degrees, entries, cat_rank)

		if category and category.key then
			state.category_angle = category.angle

			set_level(2, category.key)

			entry = pick_in_rank(degrees, view and view.entries, "rank2")
		end
	elseif state.level ~= 2 then
		set_level(2, state.category)

		entry = pick_in_rank(degrees, view and view.entries, "rank2")
	end

	set_hovered(entry)
end

local function center_text()
	if not inventory.ready then
		return mod:localize("wheel_loading")
	end

	if not model or #model.categories == 0 then
		return mod:localize("wheel_no_emotes")
	end

	if state.hovered then
		return state.hovered.label
	end

	if state.level == 2 then
		return category_label(state.category)
	end

	return ""
end

function M.presentation()
	if not state.open then
		return nil
	end

	local entries = view and view.entries or EMPTY
	local hovered = nil

	for i = 1, #entries do
		if entries[i] == state.hovered then
			hovered = i

			break
		end
	end

	presentation_table.level = state.level
	presentation_table.hovered = hovered
	presentation_table.count = #entries
	presentation_table.entries = entries
	presentation_table.center_text = center_text()
	presentation_table.cursor_angle = state.cursor_angle or 0

	if state.level == 2 then
		presentation_table.radius = L2_RADIUS
		presentation_table.breadcrumb = category_label(state.category)
	else
		presentation_table.radius = L1_RADIUS
		presentation_table.breadcrumb = ""
	end

	return presentation_table
end

function M.notify_element_destroyed()
	if state.open then
		M.close(false)

		return
	end

	pop_cursor()
	set_camera_lock(false)
end

function M.install()
	local persistent = mod:persistent_table("wheel")

	local UIHudSettings = require("scripts/settings/ui/ui_hud_settings")
	local layers = UIHudSettings and UIHudSettings.element_draw_layers

	if layers and not layers[ELEMENT_CLASS] then
		layers[ELEMENT_CLASS] = layers.HudElementEmoteWheel or 451
	end

	if not persistent.registered then
		local registered = mod:register_hud_element({
			class_name = ELEMENT_CLASS,
			filename = ELEMENT_FILE,
			visibility_groups = { "alive", "emote_wheel" },
			use_hud_scale = false,
			use_retained_mode = false,
		})

		if registered then
			persistent.registered = true
		else
			mod:error("could not register the emote wheel hud element")
		end
	end

	if not persistent.hooked then
		persistent.hooked = true

		mod:hook("HudElementSmartTagging", "_handle_input", function(func, self, t, dt, ui_renderer, render_settings)
			local wheel = mod.wheel

			if not (wheel and wheel.blocks_smart_tag and wheel.blocks_smart_tag(t)) then
				return func(self, t, dt, ui_renderer, render_settings)
			end

			local tag_context = self._tag_context

			if tag_context then
				tag_context.input_start_time = nil
			end

			local wheel_context = self._com_wheel_context

			if wheel_context then
				wheel_context.input_start_time = nil
				wheel_context.single_tap_location_tag = nil
			end

			if self._on_wheel_closed then
				self:_on_wheel_closed()
			end
		end)
	end

	M.prefetch()

	return persistent.registered == true
end

function M.on_unload()
	M.close(false)
	pop_cursor()
	set_camera_lock(false)

	state.block_until = nil

	local persistent = mod:persistent_table("wheel")

	persistent.registered = nil
	persistent.hooked = nil
end

function M.status()
	local owned = #inventory.order
	local breeds = 0
	local playable = 0

	for breed_name, events in pairs(probed) do
		breeds = breeds + 1

		if breed_name and events then
			for _, allowed in pairs(events) do
				if allowed then
					playable = playable + 1
				end
			end
		end
	end

	local categories = 0

	if model then
		categories = #model.categories
	end

	local fetch_state = "idle"

	if inventory.fetching then
		fetch_state = "fetching"
	elseif inventory.failed then
		fetch_state = "failed"
	elseif inventory.ready then
		fetch_state = "ready"
	end

	return string.format(
		"open=%s level=%d character=%s inventory=%s owned=%d probed_breeds=%d playable=%d categories=%d cursor=%s camera_lock=%s",
		tostring(state.open),
		state.level,
		tostring(inventory.character_id),
		fetch_state,
		owned,
		breeds,
		playable,
		categories,
		tostring(state.cursor_pushed),
		tostring(state.camera_locked)
	)
end

return M
