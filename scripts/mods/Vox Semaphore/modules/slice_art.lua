local mod = get_mod("Vox Semaphore")

local geometry = mod:io_dofile("Vox Semaphore/scripts/mods/Vox Semaphore/modules/slice_geometry")

local ASSET_ROOT = "mods/Vox Semaphore/assets/"
local ROLES = { "fill", "line", "highlight" }

local M = {}

M.geometry = geometry

local textures = {}
local state = "idle"
local generation = 0

function M.status()
	return state
end

function M.generation()
	return generation
end

function M.is_ready()
	return state == "ready"
end

function M.get(rank)
	return textures[rank]
end

function M.size(rank)
	local entry = geometry[rank]

	return entry and entry.size
end

function M.rank_for_radius(radius)
	if type(radius) ~= "number" then
		return "rank1"
	end

	local best, best_delta = nil, nil

	for key, entry in pairs(geometry) do
		local delta = math.abs(entry.radius - radius)

		if not best_delta or delta < best_delta then
			best, best_delta = key, delta
		end
	end

	return best or "rank1"
end

local function requested_paths()
	local paths, lookup = {}, {}

	for rank, entry in pairs(geometry) do
		for i = 1, #ROLES do
			local role = ROLES[i]
			local file = entry[role]

			if file then
				local path = ASSET_ROOT .. file

				paths[#paths + 1] = path
				lookup[path] = { rank = rank, role = role }
			end
		end
	end

	return paths, lookup
end

local function store(lookup, path, result)
	local slot = lookup[path]

	if not (slot and type(result) == "table" and result.texture) then
		return false
	end

	local set = textures[slot.rank]

	if not set then
		set = {}
		textures[slot.rank] = set
	end

	set[slot.role] = result.texture

	return true
end

local function complete(loaded, wanted)
	if loaded == wanted then
		state = "ready"
		generation = generation + 1

		mod:info("petal art loaded (%d textures)", loaded)
	else
		state = "partial"
		generation = generation + 1

		mod:info("petal art not ready (%d of %d); will retry when the wheel opens", loaded, wanted)
	end
end

function M.ensure()
	if state == "loading" or state == "ready" then
		return false
	end

	if state == "unavailable" or state == "partial" then
		state = "idle"
	end

	M.load()

	return true
end

function M.load()
	if state == "loading" or state == "ready" then
		return
	end

	local SimpleAssets = get_mod("SimpleAssets")

	if not (SimpleAssets and type(SimpleAssets.load_textures) == "function") then
		state = "unavailable"

		mod:error("SimpleAssets is required for the emote wheel petal art but was not found")

		return
	end

	local paths, lookup = requested_paths()

	if #paths == 0 then
		state = "unavailable"

		return
	end

	state = "loading"

	local promise = SimpleAssets.load_textures(paths)

	if not (promise and type(promise.next) == "function") then
		state = "unavailable"

		mod:error("SimpleAssets.load_textures did not return a promise")

		return
	end

	promise:next(function(results)
		local loaded = 0

		if type(results) == "table" then
			for i = 1, #paths do
				if store(lookup, paths[i], results[paths[i]]) then
					loaded = loaded + 1
				end
			end
		end

		complete(loaded, #paths)
	end):catch(function(err)
		state = "unavailable"
		generation = generation + 1

		mod:error("petal art failed to load: %s", tostring(err))
	end)
end

function M.reset()
	textures = {}
	state = "idle"
	generation = generation + 1
end

return M
