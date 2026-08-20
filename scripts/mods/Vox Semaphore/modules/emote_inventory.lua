local mod = get_mod("Vox Semaphore")

local EMOTE_SLOTS = {
	"slot_animation_emote_1",
	"slot_animation_emote_2",
	"slot_animation_emote_3",
	"slot_animation_emote_4",
	"slot_animation_emote_5",
}

local M = {}

local data = {
	character_id = nil,
	ready = false,
	fetching = false,
	failed = false,
	by_event = {},
	order = {},
}

M.data = data

local generation = 0
local EMPTY_VARIANTS = {}

local function local_player()
	local player_manager = Managers.player

	if not (player_manager and player_manager.local_player_safe) then
		return nil
	end

	return player_manager:local_player_safe(1)
end

local function item_label(item)
	local display_name = item and item.display_name

	if type(display_name) ~= "string" or display_name == "" then
		return nil
	end

	local localization = Managers.localization

	if not localization then
		return display_name
	end

	return localization:localize(display_name)
end

local function suits_breed(item, breed_name)
	local breeds = item and item.breeds

	if not breed_name or type(breeds) ~= "table" then
		return false
	end

	for _, name in pairs(breeds) do
		if name == breed_name then
			return true
		end
	end

	return false
end

local function accept_inventory(items)
	local by_event = {}
	local order = {}

	for _, item in pairs(items) do
		local event = item and item.animation_event

		if type(event) == "string" and event ~= "" then
			local existing = by_event[event]

			if not existing then
				existing = {
					event = event,
					variants = {},
				}
				by_event[event] = existing
				order[#order + 1] = event
			end

			existing.variants[#existing.variants + 1] = item
		end
	end

	table.sort(order)

	data.by_event = by_event
	data.order = order
	data.resolved_for = nil
	data.ready = true
	data.failed = false
	data.fetching = false
end

function M.prefetch()
	if data.fetching then
		return false
	end

	local player = local_player()
	local character_id = player and player.character_id and player:character_id()

	if type(character_id) ~= "string" or character_id == "" then
		return false
	end

	if data.ready and data.character_id == character_id then
		return false
	end

	local data_service = Managers.data_service
	local gear = data_service and data_service.gear

	if not (gear and gear.fetch_inventory) then
		return false
	end

	generation = generation + 1

	local this_generation = generation

	data.character_id = character_id
	data.fetching = true
	data.ready = false
	data.failed = false
	data.by_event = {}
	data.order = {}

	local promise = gear:fetch_inventory(character_id, EMOTE_SLOTS)

	if not (promise and promise.next) then
		data.fetching = false

		return false
	end

	local chained = promise:next(function(items)
		if this_generation ~= generation then
			return
		end

		if type(items) ~= "table" then
			data.fetching = false
			data.ready = true
			data.failed = true

			mod:warning("emote inventory fetch returned nothing; the wheel will be empty")

			return
		end

		accept_inventory(items)
	end)

	if chained and chained.catch then
		chained:catch(function()
			if this_generation ~= generation then
				return
			end

			data.fetching = false
			data.ready = true
			data.failed = true

			mod:warning("emote inventory fetch failed; the wheel will be empty")
		end)
	end

	return true
end

function M.resolve(breed_name)
	if data.resolved_for == breed_name then
		return false
	end

	data.resolved_for = breed_name

	for _, record in pairs(data.by_event) do
		local variants = record.variants or EMPTY_VARIANTS
		local chosen, suited = variants[1], false

		for i = 1, #variants do
			if suits_breed(variants[i], breed_name) then
				chosen, suited = variants[i], true

				break
			end
		end

		record.item = chosen
		record.suited = suited
		record.icon = chosen and chosen.icon
		record.label = (chosen and item_label(chosen)) or record.event
	end

	return true
end

function M.clear()
	generation = generation + 1

	data.character_id = nil
	data.ready = false
	data.failed = false
	data.fetching = false
	data.by_event = {}
	data.order = {}
	data.resolved_for = nil
end

local function local_breed_name()
	local player = local_player()
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) then
		return nil
	end

	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
	local breed_name = unit_data and unit_data:breed_name()

	return type(breed_name) == "string" and breed_name or nil
end

function M.ensure_resolved()
	if data.resolved_for then
		return true
	end

	local breed_name = local_breed_name()

	if not breed_name then
		return false
	end

	M.resolve(breed_name)

	return true
end

function M.face_event_for(event_name)
	M.ensure_resolved()

	local record = data.by_event and data.by_event[event_name]
	local item = record and record.item

	return item and item.face_animation_event
end

function M.equipped_events()
	local player = local_player()
	local profile = player and player.profile and player:profile()
	local loadout = profile and profile.loadout

	if not loadout then
		return nil
	end

	local excluded = {}

	for i = 1, #EMOTE_SLOTS do
		local item = loadout[EMOTE_SLOTS[i]]
		local event = item and item.animation_event

		if event then
			excluded[event] = true
		end
	end

	return excluded
end

return M
