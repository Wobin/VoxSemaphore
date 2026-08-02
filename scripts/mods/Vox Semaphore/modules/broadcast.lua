local mod = get_mod("Vox Semaphore")

local protocol = mod.protocol

if not protocol then
	mod:error("broadcast loaded before protocol; check module load order")

	return {
		announce = function() return false, "protocol missing" end,
		current = function() return nil end,
		shutdown = function() end,
		debug_state = function() return {} end,
	}
end

local M = {}

local state = mod:persistent_table("broadcast", {
	seq = 0,
})

if type(state.seq) ~= "number" then
	state.seq = 0
end

local payload = nil
local warned_mark_dirty = false

local function consumer_id()
	local id = mod.vox_id

	if type(id) ~= "string" or id == "" then
		mod:error("broadcast: mod.vox_id is not set; check the main script")

		return nil
	end

	return id
end

local function vox_api()
	local vox = mod.vox
	local api = vox and vox.api

	if not api or type(api.mark_dirty) ~= "function" then
		return nil
	end

	return api
end

function M.announce(event_name)
	if type(event_name) ~= "string" or event_name == "" then
		return false, "no event name"
	end

	if #event_name > protocol.MAX_EVENT_LENGTH then
		return false, "event name too long"
	end

	if not string.find(event_name, protocol.EVENT_PATTERN) then
		return false, "event name is not receivable: " .. event_name
	end

	local id = consumer_id()

	if not id then
		return false, "no consumer id"
	end

	local seq = state.seq + 1

	if seq > protocol.SEQ_WRAP then
		seq = 1
	end

	state.seq = seq

	local codec = mod.emote_codec
	local code = codec and codec.encode(event_name) or event_name

	payload = {
		[protocol.KEY_VERSION] = protocol.PAYLOAD_VERSION,
		[protocol.KEY_EVENT] = code,
		[protocol.KEY_SEQUENCE] = seq,
	}

	mod.trace("send %s (code %s, seq %d)", event_name, tostring(code), seq)

	local api = vox_api()

	if not api then
		mod.trace("send not published: no manifold (self only)")

		return true
	end

	if not api.mark_dirty(id) and not warned_mark_dirty then
		warned_mark_dirty = true

		mod:warning("broadcast: Vox Manifold does not know %s; nothing will be published", id)
	end

	return true
end

function M.announce_stop()
	local id = consumer_id()

	if not id then
		return false, "no consumer id"
	end

	local seq = state.seq + 1

	if seq > protocol.SEQ_WRAP then
		seq = 1
	end

	state.seq = seq

	payload = {
		[protocol.KEY_VERSION] = protocol.PAYLOAD_VERSION,
		[protocol.KEY_SEQUENCE] = seq,
	}

	mod.trace("send stop (seq %d)", seq)

	local api = vox_api()

	if api then
		api.mark_dirty(id)
	end

	return true
end

function M.current()
	return payload
end

function M.shutdown()
	payload = nil
end

function M.debug_state()
	return {
		mode = mod.mode,
		seq = state.seq,
		payload = payload ~= nil,
	}
end

return M
