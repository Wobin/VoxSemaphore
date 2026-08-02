local MasterItems = require("scripts/backend/master_items")

local DEFAULT_DURATION = 2.5
local MIN_ACCEPT = 0.5
local MAX_ACCEPT = 30.0

local M = {}

local item_index = nil
local item_index_version = nil

local function clamp(seconds)
	if seconds < MIN_ACCEPT then
		return MIN_ACCEPT
	end

	if seconds > MAX_ACCEPT then
		return MAX_ACCEPT
	end

	return seconds
end

local function backend_ready()
	local backend = Managers.backend
	local interfaces = backend and backend.interfaces

	return interfaces ~= nil and interfaces.master_data ~= nil
end

local function ensure_item_index()
	if not backend_ready() then
		return nil
	end

	if not (MasterItems.has_data and MasterItems.has_data()) then
		return nil
	end

	local version = MasterItems.get_cached_version and MasterItems.get_cached_version()

	if item_index and version == item_index_version then
		return item_index
	end

	local items = MasterItems.get_cached()

	if type(items) ~= "table" then
		return nil
	end

	local index = {}

	for _, item in pairs(items) do
		if type(item) == "table" then
			local event_name = item.animation_event
			local duration = item.animation_duration

			if type(event_name) == "string" and event_name ~= "" and type(duration) == "number" and duration > 0 then
				local best = index[event_name]

				if not best or duration > best then
					index[event_name] = duration
				end
			end
		end
	end

	item_index = index
	item_index_version = version

	return item_index
end

function M.init()
	ensure_item_index()

	return true
end

function M.duration_for(event_name)
	if type(event_name) ~= "string" or event_name == "" then
		return DEFAULT_DURATION, "default"
	end

	local index = ensure_item_index()
	local from_item = index and index[event_name]

	if from_item then
		return clamp(from_item), "item"
	end

	return DEFAULT_DURATION, "default"
end

function M.on_unload()
	item_index = nil
	item_index_version = nil
end

M.DEFAULT_DURATION = DEFAULT_DURATION
M.MAX_ACCEPT = MAX_ACCEPT

return M
