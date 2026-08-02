local type = type
local floor = math.floor
local concat = table.concat
local str_byte = string.byte
local str_sub = string.sub

local PRIME = 2147483647
local MULT = 131
local SEED = 2166136261 % PRIME

local ALPH = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local RAW = "!"
local MIN_WIDTH = 3
local MAX_WIDTH = 6

local function hash(s)
    local h = SEED
    for i = 1, #s do
        h = (h * MULT + str_byte(s, i)) % PRIME
    end
    return h
end

local function code_of(h, width)
    local c = {}
    for i = width, 1, -1 do
        local r = h % 62
        c[i] = str_sub(ALPH, r + 1, r + 1)
        h = floor(h / 62)
    end
    return concat(c)
end

local function clashes_at(hashes, width)
    local seen = {}
    for _, h in pairs(hashes) do
        local code = code_of(h, width)
        if seen[code] then
            return true
        end
        seen[code] = true
    end
    return false
end

local M = {}

function M.build(ids)
    local hashes = {}
    for i = 1, #ids do
        local id = ids[i]
        if type(id) == "string" then
            hashes[id] = hash(id)
        end
    end

    local width = MIN_WIDTH
    while width < MAX_WIDTH and clashes_at(hashes, width) do
        width = width + 1
    end

    local counts = {}
    for _, h in pairs(hashes) do
        local code = code_of(h, width)
        counts[code] = (counts[code] or 0) + 1
    end

    local to_code, by_code, collisions = {}, {}, {}
    for id, h in pairs(hashes) do
        local code = code_of(h, width)
        if counts[code] == 1 then
            to_code[id] = code
            by_code[code] = id
        else
            collisions[#collisions + 1] = id
        end
    end

    local codec = { width = width, collisions = collisions }

    function codec.encode(id)
        if type(id) ~= "string" then
            return nil
        end
        local code = to_code[id]
        if code then
            return code
        end
        return RAW .. id
    end

    function codec.decode(token)
        if type(token) ~= "string" then
            return nil
        end
        if str_sub(token, 1, 1) == RAW then
            return str_sub(token, 2)
        end
        return by_code[token]
    end

    return codec
end

return M
