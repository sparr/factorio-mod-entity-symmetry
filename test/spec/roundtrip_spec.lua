local geometry = require("lib.geometry")

--- Why issue #2 cannot be fixed by widening the position comparison.
---
--- The mod does not remember which entities it created. When one is removed it recomputes
--- where the others should be, by rotating the removed entity's position about the centre.
--- But a copy was placed by rotating and then snapping to the entity's placement grid, and
--- rotate-then-snap is not a group operation: rotating a snapped copy and snapping again
--- can land in a different tile than the original.
---
--- So the set of positions computed from copy k need not equal the set that was created
--- from the original. These tests measure how far apart they can get, which is what rules
--- a tolerance out: the drift reaches a full diagonal tile, and matching anything that far
--- away would start deleting unrelated entities that merely happen to be adjacent.

--- A 1x1 entity sits in the middle of its tile.
local function snap(p) return { x = math.floor(p.x) + 0.5, y = math.floor(p.y) + 0.5 } end
local CENTRE = { x = 0.5, y = 0.5 }

local function copy_set(seed, s)
    local set = {}
    for r = 0, s - 1 do
        set[#set + 1] = snap(geometry.orient_position_relative(CENTRE, seed, r / s))
    end
    return set
end

local function key(p) return ("%.3f,%.3f"):format(p.x, p.y) end
local function same_set(a, b)
    if #a ~= #b then return false end
    local seen = {}
    for _, p in ipairs(a) do seen[key(p)] = true end
    for _, p in ipairs(b) do if not seen[key(p)] then return false end end
    return true
end

--- Worst case over a spread of distances and angles: how often does mining a copy produce
--- a different set, and how far is the nearest recomputed position from a real one?
local function survey(s)
    local cases, mismatches, worst = 0, 0, 0
    for dist = 1, 20 do
        for ang = 0, 15 do
            local seed = snap(geometry.orient_position_relative(
                CENTRE, { x = CENTRE.x + dist, y = CENTRE.y }, ang / 16))
            local original = copy_set(seed, s)
            for k = 1, #original do
                cases = cases + 1
                local recomputed = copy_set(original[k], s)
                if not same_set(original, recomputed) then mismatches = mismatches + 1 end
                for _, p in ipairs(original) do
                    local nearest = math.huge
                    for _, q in ipairs(recomputed) do
                        local d = ((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2) ^ 0.5
                        if d < nearest then nearest = d end
                    end
                    if nearest > worst then worst = nearest end
                end
            end
        end
    end
    return cases, mismatches, worst
end

describe("recomputing the copy set from a copy", function()
    it("is exact for the symmetries built from quarter turns", function()
        for _, s in ipairs{ 2, 4 } do
            local _, mismatches, worst = survey(s)
            assert.equal(0, mismatches)
            assert.equal(0, worst)
        end
    end)

    it("drifts for every other symmetry, by up to a full diagonal tile", function()
        for _, s in ipairs{ 3, 5, 6, 7, 8, 12 } do
            local cases, mismatches, worst = survey(s)
            assert.is_true(mismatches > 0,
                ("S=%d unexpectedly round-tripped cleanly"):format(s))
            assert.is_true(worst >= 1.0,
                ("S=%d drift was only %.3f"):format(s, worst))
            assert.is_true(worst <= 1.5,
                ("S=%d drift was %.3f, larger than assumed"):format(s, worst))
            assert.is_true(cases > 0)
        end
    end)

    it("is worst for S=7, which is why that report saw nothing removed at all", function()
        local cases, mismatches = survey(7)
        assert.is_true(mismatches / cases > 0.5)
    end)

    it("rules out a tolerance: the drift exceeds the spacing of neighbouring tiles", function()
        -- anything matched within 1.414 tiles would also match an unrelated entity placed
        -- one tile away, so widening the comparison trades missed removals for wrong ones
        local _, _, worst = survey(7)
        assert.is_true(worst > 1.0)
    end)
end)
