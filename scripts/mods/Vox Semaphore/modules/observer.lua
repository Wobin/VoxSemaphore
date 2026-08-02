local mod = get_mod("Vox Semaphore")

local emote = mod.emote
local suppression = mod.suppression

if not (emote and suppression and mod.protocol) then
	mod:error("observer module loaded before its dependencies; check module load order")

	return {
		CONSUMER_ID = "wobin.vox_semaphore",
		PAYLOAD_VERSION = 2,
		KEY_VERSION = "pv",
		KEY_EVENT = "e",
		KEY_SEQUENCE = "i",
		decode = function() return nil, "dependencies missing" end,
		install = function() return false end,
		uninstall = function() return false end,
		update = function() end,
		reset = function() end,
		set_enabled = function() end,
		is_enabled = function() return false end,
		poll_now = function() end,
		stats = function() return {} end,
	}
end

local math_floor = math.floor
local math_huge = math.huge
local string_find = string.find
local ScriptUnit = ScriptUnit
local Unit = Unit

local CONSUMER_ID = "wobin.vox_semaphore"

local function consumer_id()
	local id = mod.vox_id

	if type(id) == "string" and id ~= "" then
		return id
	end

	return CONSUMER_ID
end
local protocol = mod.protocol

local PAYLOAD_VERSION = protocol.PAYLOAD_VERSION
local KEY_VERSION = protocol.KEY_VERSION
local KEY_EVENT = protocol.KEY_EVENT
local KEY_SEQUENCE = protocol.KEY_SEQUENCE

local SAFETY_SWEEP = 5.0
local RETRY_WINDOW = 2.0
local MAX_EVENT_LENGTH = protocol.MAX_EVENT_LENGTH
local MAX_TOKEN_LENGTH = MAX_EVENT_LENGTH + 1
local EVENT_PATTERN = protocol.EVENT_PATTERN
local NO_ACCOUNT_ID = "no_account_id"

local PLAYABLE_STATES = {
	walking = true,
	sprinting = true,
	hub_jog = true,
}

local M = {}

M.CONSUMER_ID = CONSUMER_ID
M.PAYLOAD_VERSION = PAYLOAD_VERSION
M.KEY_VERSION = KEY_VERSION
M.KEY_EVENT = KEY_EVENT
M.KEY_SEQUENCE = KEY_SEQUENCE

local enabled = true
local dirty = false
local next_sweep = 0

local seen = {}
local primed = {}
local pending = {}
local done = {}

local DONE_LIMIT = 32

local function combo_key(event_name, sequence)
	return tostring(event_name) .. "#" .. tostring(sequence)
end

local function is_done(account, key)
	local record = done[account]

	return record ~= nil and record.keys[key] == true
end

local function mark_done(account, key)
	local record = done[account]

	if not record then
		record = { keys = {}, order = {}, count = 0 }
		done[account] = record
	end

	if record.keys[key] then
		return
	end

	record.count = record.count + 1
	record.keys[key] = true
	record.order[record.count] = key

	if record.count > DONE_LIMIT then
		local oldest = record.order[record.count - DONE_LIMIT]

		if oldest then
			record.keys[oldest] = nil
			record.order[record.count - DONE_LIMIT] = nil
		end
	end
end
local reported = {}

local stats = {
	sweeps = 0,
	decoded = 0,
	played = 0,
	stopped = 0,
	primed = 0,
	skipped = 0,
	last_skip_reason = nil,
}

function M.decode(payload)
	if type(payload) ~= "table" then
		return nil, "payload not a table"
	end

	if payload[KEY_VERSION] ~= PAYLOAD_VERSION then
		return nil, "payload version " .. tostring(payload[KEY_VERSION])
	end

	local sequence = payload[KEY_SEQUENCE]

	if type(sequence) ~= "number" then
		return nil, "sequence not a number"
	end

	if sequence ~= sequence or sequence == math_huge or sequence == -math_huge then
		return nil, "sequence not finite"
	end

	if sequence ~= math_floor(sequence) then
		return nil, "sequence not an integer"
	end

	local token = payload[KEY_EVENT]

	if token == nil then
		return false, sequence
	end

	if type(token) ~= "string" then
		return nil, "event not a string"
	end

	if #token > MAX_TOKEN_LENGTH then
		return nil, "event too long"
	end

	local codec = mod.emote_codec
	local event_name = codec and codec.decode(token) or token

	if type(event_name) ~= "string" or event_name == "" then
		return nil, "unknown emote code " .. tostring(token)
	end

	if #event_name > MAX_EVENT_LENGTH then
		return nil, "event too long"
	end

	if not string_find(event_name, EVENT_PATTERN) then
		return nil, "event name rejected"
	end

	return event_name, sequence
end

local function manifold_api()
	local vox = mod.vox

	if not (vox and vox.api) then
		return nil
	end

	local api = vox.api

	if type(api.members) ~= "function" or type(api.get) ~= "function" or type(api.is_myself) ~= "function" then
		return nil
	end

	return api
end

local function now()
	local time_manager = Managers and Managers.time

	if time_manager and time_manager:has_timer("main") then
		return time_manager:time("main")
	end

	return nil
end

local function in_mission()
	local state = Managers and Managers.state
	local game_mode = state and state.game_mode

	if not game_mode then
		return false
	end

	if type(game_mode.is_social_hub) ~= "function" or type(game_mode.is_prologue_hub) ~= "function" then
		return false
	end

	if game_mode:is_social_hub() or game_mode:is_prologue_hub() then
		return false
	end

	return true
end

local function local_player_unit()
	local player_manager = Managers and Managers.player

	if not player_manager then
		return nil
	end

	local player = nil

	if type(player_manager.local_player_safe) == "function" then
		player = player_manager:local_player_safe(1)
	else
		player = nil
	end

	return player and player.player_unit
end

local function players_by_account()
	local player_manager = Managers and Managers.player

	if not player_manager then
		return nil
	end

	local players = player_manager:players()

	if type(players) ~= "table" then
		return nil
	end

	local by_account = {}

	for _, player in pairs(players) do
		if type(player.account_id) == "function" and type(player.is_human_controlled) == "function" and player:is_human_controlled() then
			local account = player:account_id()

			if type(account) == "string" and account ~= "" and account ~= NO_ACCOUNT_ID then
				by_account[account] = player
			end
		end
	end

	return by_account
end

local function aim_extension_allows(unit)
	local aim = ScriptUnit.has_extension(unit, "aim_system")

	if not aim then
		return true
	end

	return aim.__class_name == "PlayerHuskAimExtension"
end

local function note_skip(account, reason)
	local text = tostring(reason)

	stats.skipped = stats.skipped + 1
	stats.last_skip_reason = text

	local key = tostring(account) .. "|" .. text

	if not reported[key] then
		reported[key] = true

		mod:info("observer skipped %s (%s)", tostring(account), text)
	end
end

local function apply(account, record, by_account)
	local player = by_account[account]

	if not player then
		return false, "no player for account"
	end

	local unit = player.player_unit

	if not unit then
		return false, "no player unit"
	end

	if not Unit.alive(unit) then
		return false, "unit not alive"
	end

	if unit == local_player_unit() then
		return false, "local player unit"
	end

	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
	local visual_loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
	local animation = ScriptUnit.has_extension(unit, "animation_system")

	if not (unit_data and visual_loadout and animation) then
		return false, "not a player unit"
	end

	local health = ScriptUnit.has_extension(unit, "health_system")

	if health and type(health.is_alive) == "function" and not health:is_alive() then
		return false, "unit is dead"
	end

	if not aim_extension_allows(unit) then
		return false, "unsupported aim extension"
	end

	if record.event == false then
		if emote.stop(unit) then
			stats.stopped = stats.stopped + 1
		end

		return true
	end

	if emote.is_emoting(unit) then
		return false, "already emoting"
	end

	local character_state = unit_data:read_component("character_state")
	local state_name = character_state and character_state.state_name

	if not PLAYABLE_STATES[state_name] then
		return false, "character state " .. tostring(state_name)
	end

	suppression.install()

	local started, err = emote.start(unit, record.event, nil)

	if not started then
		return false, tostring(err)
	end

	stats.played = stats.played + 1

	mod:info("%s -> %s", tostring(account), tostring(record.event))

	return true
end

local function prune(present)
	for account in pairs(seen) do
		if not present[account] then
			seen[account] = nil
		end
	end

	for account in pairs(primed) do
		if not present[account] then
			primed[account] = nil
		end
	end

	for account in pairs(pending) do
		if not present[account] then
			pending[account] = nil
		end
	end

	for account in pairs(done) do
		if not present[account] then
			done[account] = nil
		end
	end
end

local function read_member(api, member, present, t)
	if type(member) ~= "table" or type(member.account_id) ~= "function" then
		return
	end

	if api.is_myself(member) then
		return
	end

	local account = member:account_id()

	if type(account) ~= "string" or account == "" or account == NO_ACCOUNT_ID then
		return
	end

	present[account] = true

	local payload = api.get(member, consumer_id())

	if payload == nil then
		return
	end

	if type(payload) ~= "table" then
		primed[account] = true

		return
	end

	local event_name, sequence = M.decode(payload)

	if event_name == nil then
		mod.trace("recv %s rejected: %s", tostring(account), tostring(sequence))
		note_skip(account, sequence)

		return
	end

	stats.decoded = stats.decoded + 1

	mod.trace("recv %s event=%s seq=%s", tostring(account), tostring(event_name), tostring(sequence))

	if not primed[account] then
		primed[account] = true
		seen[account] = sequence
		stats.primed = stats.primed + 1

		mod.trace("recv %s primed at seq %s (not played)", tostring(account), tostring(sequence))

		return
	end

	local key = combo_key(event_name, sequence)

	if is_done(account, key) then
		return
	end

	if sequence ~= seen[account] then
		local existing = pending[account]

		if not (existing and existing.seq == sequence) then
			pending[account] = {
				seq = sequence,
				event = event_name,
				key = key,
				expires = t + RETRY_WINDOW,
			}
		end
	end
end

local function sweep(api, t)
	stats.sweeps = stats.sweeps + 1

	if not in_mission() then
		M.reset()

		return
	end

	local members = api.members()

	if type(members) ~= "table" then
		return
	end

	local present = {}

	for i = 1, #members do
		read_member(api, members[i], present, t)
	end

	prune(present)
end

local function flush(t)
	if not next(pending) then
		return
	end

	local by_account = players_by_account()

	if not by_account then
		return
	end

	for account, record in pairs(pending) do
		local applied, reason = apply(account, record, by_account)

		if applied then
			seen[account] = record.seq
			pending[account] = nil

			mod.trace("recv %s applied %s", tostring(account), tostring(record.event))

			if record.key then
				mark_done(account, record.key)
			end
		elseif t >= record.expires then
			mod.trace("recv %s gave up on %s: %s", tostring(account), tostring(record.event), tostring(reason))
			seen[account] = record.seq
			pending[account] = nil

			if record.key then
				mark_done(account, record.key)
			end

			note_skip(account, reason)
		end
	end
end

function M.update()
	if not enabled then
		return
	end

	if mod.mode ~= "networked" then
		return
	end

	local api = manifold_api()

	if not api then
		return
	end

	local t = now()

	if not t then
		return
	end

	if dirty or t >= next_sweep then
		dirty = false
		next_sweep = t + SAFETY_SWEEP

		sweep(api, t)
	end

	flush(t)
end

function M.reset()
	seen = {}
	primed = {}
	pending = {}
	done = {}
	reported = {}
	dirty = false
end

function M.install()
	local state = mod:persistent_table("observer")

	if state.unsubscribe then
		state.unsubscribe()

		state.unsubscribe = nil
	end

	M.reset()

	next_sweep = 0

	if mod.mode ~= "networked" then
		return false
	end

	local api = manifold_api()

	if not (api and type(api.on_update) == "function") then
		return false
	end

	state.unsubscribe = api.on_update(function()
		dirty = true
	end)

	return true
end

function M.uninstall()
	local state = mod:persistent_table("observer")

	if state.unsubscribe then
		state.unsubscribe()

		state.unsubscribe = nil
	end

	M.reset()

	return true
end

function M.set_enabled(value)
	enabled = value ~= false
end

function M.is_enabled()
	return enabled
end

function M.poll_now()
	dirty = true
end

function M.stats()
	return {
		sweeps = stats.sweeps,
		decoded = stats.decoded,
		played = stats.played,
		stopped = stats.stopped,
		primed = stats.primed,
		skipped = stats.skipped,
		last_skip_reason = stats.last_skip_reason,
		pending = next(pending) ~= nil,
		suppression_dropped = suppression.dropped,
	}
end

return M
