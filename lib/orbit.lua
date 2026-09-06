--- Working out which entities are the rotational copies of a given one.
---
--- The mod records nothing, so when an entity is removed it has to rediscover its
--- siblings. It cannot do that by rotating the removed entity's position and matching
--- exactly: a copy was placed by rotating and then snapping to the placement grid, and
--- rotate-then-snap is not a group operation, so the positions recomputed from a copy need
--- not be the positions that were created from the original. Outside quarter turns the two
--- differ by up to a full diagonal tile -- see test/spec/roundtrip_spec.lua.
---
--- Instead: enumerate every placement that *could* have produced the removed entity under
--- the current symmetry, and pick the one whose orbit best matches the entities actually
--- present. With the siblings intact that identifies the orbit exactly, and when some have
--- already gone it still finds the ones that remain.

local geometry = require("lib.geometry")

local orbit = {}

--- Positions are compared as keys rather than floats, at a resolution far finer than the
--- placement grid but far coarser than the noise from a sin/cos round trip.
---@param p MapPosition
---@return string
function orbit.key(p)
    return string.format("%.4f,%.4f", p.x, p.y)
end

--- The placement grid an entity of this tile size sits on: odd sizes centre on a tile,
--- even sizes centre on a corner.
---@param tile_width integer
---@param tile_height integer
---@return fun(p: MapPosition): MapPosition
function orbit.snapper(tile_width, tile_height)
    local ox = (tile_width % 2 == 1) and 0.5 or 0
    local oy = (tile_height % 2 == 1) and 0.5 or 0
    return function(p)
        return {
            x = math.floor(p.x - ox + 0.5) + ox,
            y = math.floor(p.y - oy + 0.5) + oy,
        }
    end
end

--- Where the copies of `seed` land, in order, including `seed` itself at index 1.
---@param centre MapPosition
---@param seed MapPosition
---@param degree integer rotational symmetry
---@param snap fun(p: MapPosition): MapPosition
---@return MapPosition[]
function orbit.positions(centre, seed, degree, snap)
    local out = {}
    for r = 0, degree - 1 do
        out[r + 1] = snap(geometry.orient_position_relative(centre, seed, r / degree))
    end
    return out
end

--- Every placement that, rotated by some multiple of the symmetry, lands exactly on
--- `target`. Searching a small neighbourhood of each preimage is enough: the snap moves a
--- point by at most half a diagonal, so a seed cannot be further than that from the
--- rotation of the target back through the same angle.
---@param centre MapPosition
---@param target MapPosition
---@param degree integer
---@param snap fun(p: MapPosition): MapPosition
---@param search integer? tiles either side, default 2
---@return MapPosition[]
function orbit.candidate_seeds(centre, target, degree, snap, search)
    search = search or 2
    local target_key = orbit.key(target)
    local seen, seeds = {}, {}
    for j = 0, degree - 1 do
        local approx = geometry.orient_position_relative(centre, target, -j / degree)
        local base = snap(approx)
        for dx = -search, search do
            for dy = -search, search do
                local seed = { x = base.x + dx, y = base.y + dy }
                if orbit.key(snap(geometry.orient_position_relative(centre, seed, j / degree)))
                    == target_key
                then
                    local k = orbit.key(seed)
                    if not seen[k] then
                        seen[k] = true
                        seeds[#seeds + 1] = seed
                    end
                end
            end
        end
    end
    return seeds
end

--- The orbit through `target` that best explains what is actually on the ground.
--- `occupied(position)` returns a truthy value -- normally the entity -- when a sibling
--- sits there. Scored by how many orbit positions are occupied; ties go to the orbit
--- sitting closest to the ideal continuous rotation, which keeps the choice stable in a
--- crowded area.
---@param centre MapPosition
---@param target MapPosition
---@param degree integer
---@param snap fun(p: MapPosition): MapPosition
---@param occupied fun(p: MapPosition): any
---@return MapPosition[] positions
---@return integer score how many of them were occupied by a sibling
function orbit.choose(centre, target, degree, snap, occupied)
    local target_key = orbit.key(target)
    local best, best_score, best_drift
    for _, seed in ipairs(orbit.candidate_seeds(centre, target, degree, snap)) do
        local positions = orbit.positions(centre, seed, degree, snap)
        local index
        for n, p in ipairs(positions) do
            if orbit.key(p) == target_key then index = n break end
        end
        if index then
            local score, drift, counted = 0, 0, {}
            for n, p in ipairs(positions) do
                local k = orbit.key(p)
                if k ~= target_key and not counted[k] and occupied(p) then
                    counted[k] = true
                    score = score + 1
                end
                local ideal = geometry.orient_position_relative(
                    centre, target, (n - index) / degree)
                drift = drift + ((p.x - ideal.x) ^ 2 + (p.y - ideal.y) ^ 2) ^ 0.5
            end
            if best_score == nil or score > best_score
                or (score == best_score and drift < best_drift)
            then
                best, best_score, best_drift = positions, score, drift
            end
        end
    end
    return best or { target }, best_score or 0
end

return orbit
