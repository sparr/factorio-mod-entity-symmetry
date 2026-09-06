--- The slice of the Factorio runtime that lib/geometry.lua needs: the direction defines
--- and table.deepcopy. Nothing here models game state -- anything that needs the real
--- engine belongs in the integration tier, not in a spec.

if not defines then
    local d = {}
    local names = {
        "north", "northnortheast", "northeast", "eastnortheast",
        "east",  "eastsoutheast",  "southeast", "southsoutheast",
        "south", "southsouthwest", "southwest", "westsouthwest",
        "west",  "westnorthwest",  "northwest", "northnorthwest",
    }
    for i, name in ipairs(names) do d[name] = i - 1 end
    defines = { direction = d }
end

if not table.deepcopy then
    function table.deepcopy(t)
        if type(t) ~= "table" then return t end
        local copy = {}
        for k, v in pairs(t) do copy[k] = table.deepcopy(v) end
        return copy
    end
end

--- Lua 5.3+ dropped math.atan2; Factorio runs 5.2, where it exists.
if not math.atan2 then math.atan2 = function(y, x) return math.atan(y, x) end end

return true
