local mod = get_mod("Vox Semaphore")

local MasterItems = require("scripts/backend/master_items")

local id_codec = mod.id_codec

if not id_codec then
	mod:error("emote_codec loaded before id_codec; check module load order")

	return {
		get = function() return nil end,
		encode = function(event) return event end,
		decode = function(token) return token end,
		reset = function() end,
		info = function() return "id_codec missing" end,
	}
end

local EMOTE_PATH = "/emotes/"

local M = {}

local codec = nil
local built_version = nil

local function master_version()
	if MasterItems.get_cached_version then
		return MasterItems.get_cached_version()
	end

	return true
end

local function build()
	local items = MasterItems.get_cached()

	if not items then
		return nil
	end

	local seen = {}
	local ids = {}

	for name, item in pairs(items) do
		local event = item.animation_event

		if type(event) == "string" and event ~= "" and not seen[event] and string.find(name, EMOTE_PATH, 1, true) then
			seen[event] = true
			ids[#ids + 1] = event
		end
	end

	if #ids == 0 then
		return nil
	end

	table.sort(ids)

	return id_codec.build(ids), #ids
end

function M.get()
	local version = master_version()

	if codec and built_version == version then
		return codec
	end

	local built, count = build()

	if not built then
		return nil
	end

	codec = built
	built_version = version

	mod:info("emote codec built: %d events, width %d, %d collisions", count, built.width, #built.collisions)

	return codec
end

function M.encode(event)
	local active = M.get()

	if not active then
		return event
	end

	return active.encode(event)
end

function M.decode(token)
	local active = M.get()

	if not active then
		return token
	end

	return active.decode(token)
end

function M.reset()
	codec = nil
	built_version = nil
end

function M.info()
	local active = M.get()

	if not active then
		return "codec unavailable"
	end

	return string.format("width=%d collisions=%d", active.width, #active.collisions)
end

return M
