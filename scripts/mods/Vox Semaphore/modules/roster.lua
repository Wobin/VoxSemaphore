local mod = get_mod("Vox Semaphore")

local M = {}

local SETTLE_DELAY = 8.0

local due = nil
local dirty = false
local announced = {}

local function now()
	local time_manager = Managers and Managers.time

	if time_manager and time_manager:has_timer("gameplay") then
		return time_manager:time("gameplay")
	end

	return nil
end

local function manifold_api()
	local vox = mod.vox
	local api = vox and vox.api

	if not (api and type(api.members) == "function" and type(api.has_mod) == "function") then
		return nil
	end

	return api
end

local function name_by_account()
	local player_manager = Managers and Managers.player

	if not player_manager then
		return nil
	end

	local players = player_manager:players()

	if type(players) ~= "table" then
		return nil
	end

	local names = {}

	for _, player in pairs(players) do
		if type(player.account_id) == "function" and type(player.name) == "function" then
			local account = player:account_id()

			if type(account) == "string" and account ~= "" then
				names[account] = player:name()
			end
		end
	end

	return names
end

local function unsubscribe()
	local state = mod:persistent_table("roster")

	if state.unsubscribe then
		state.unsubscribe()

		state.unsubscribe = nil
	end
end

local function subscribe()
	unsubscribe()

	local api = manifold_api()

	if not (api and type(api.on_update) == "function") then
		return false
	end

	local state = mod:persistent_table("roster")

	state.unsubscribe = api.on_update(mod.vox_id, function()
		dirty = true
	end)

	return true
end

function M.arm()
	local t = now()

	announced = {}
	dirty = false
	due = t and (t + SETTLE_DELAY) or nil

	subscribe()
end

function M.cancel()
	due = nil
	dirty = false
	announced = {}

	unsubscribe()
end

function M.report()
	local api = manifold_api()

	if not api then
		return nil
	end

	local names = name_by_account() or {}
	local members = api.members()

	if type(members) ~= "table" then
		return nil
	end

	local users = {}
	local accounts = {}
	local me = Managers.player and Managers.player.local_player_safe and Managers.player:local_player_safe(1)

	if me and type(me.name) == "function" then
		users[#users + 1] = tostring(me:name()) .. " (you)"
	end

	for i = 1, #members do
		local member = members[i]

		if type(member) == "table" and type(member.account_id) == "function" and not api.is_myself(member) then
			local version = api.has_mod(member, mod.vox_id)

			if version then
				local account = member:account_id()
				local name = names[account] or tostring(account):sub(1, 8)
				local label = string.format("%s (%s)", tostring(name), tostring(version))

				users[#users + 1] = label
				accounts[account] = label
			end
		end
	end

	return users, accounts
end

function M.update()
	if not due and not dirty then
		return
	end

	if due then
		local t = now()

		if not t or t < due then
			return
		end

		due = nil
		dirty = false

		local users, accounts = M.report()

		if not users then
			return
		end

		announced = accounts or {}

		if not mod.settings.announce_users then
			return
		end

		if #users > 1 then
			mod:echo("Vox Semaphore: " .. table.concat(users, ", "))
		else
			mod:echo("Vox Semaphore: nobody else in the party is running it")
		end

		return
	end

	dirty = false

	local _, accounts = M.report()

	if not accounts then
		return
	end

	if mod.settings.announce_users then
		for account, label in pairs(accounts) do
			if not announced[account] then
				mod:echo("Vox Semaphore: " .. tostring(label) .. " joined running it")
			end
		end
	end

	announced = accounts
end

return M
