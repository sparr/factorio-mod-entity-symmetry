local orbit = require("lib.orbit")

--- The same survey the round-trip spec runs, but asking whether lib/orbit recovers the
--- orbit rather than whether naive recomputation does. 17 angles, not 16, so the sample is
--- not dominated by the quarter turns that already worked.

local CENTRE = { x = 0.5, y = 0.5 }
local snap = orbit.snapper(1, 1)
local ANGLES = 17
local geometry = require("lib.geometry")

local function seed_at(dist, ang)
    return snap(geometry.orient_position_relative(
        CENTRE, { x = CENTRE.x + dist, y = CENTRE.y }, ang / ANGLES))
end

local function set_of(positions)
    local s = {}
    for _, p in ipairs(positions) do s[orbit.key(p)] = true end
    return s
end

--- occupancy backed by a plain table of position keys
local function occupancy(keys)
    return function(p) return keys[orbit.key(p)] end
end

describe("recovering an orbit from one of its members", function()
    it("is exact for every symmetry when the siblings are all present", function()
        local checked = 0
        for _, degree in ipairs{ 2, 3, 4, 5, 6, 7, 8, 12 } do
            for dist = 2, 15 do
                for ang = 0, ANGLES - 1 do
                    local created = orbit.positions(CENTRE, seed_at(dist, ang), degree, snap)
                    local created_set = set_of(created)
                    local distinct = 0
                    for _ in pairs(created_set) do distinct = distinct + 1 end
                    if distinct == degree then
                        for k = 1, degree do
                            local target = created[k]
                            local present = {}
                            for _, p in ipairs(created) do
                                if orbit.key(p) ~= orbit.key(target) then
                                    present[orbit.key(p)] = true
                                end
                            end
                            local found = orbit.choose(
                                CENTRE, target, degree, snap, occupancy(present))
                            local found_set = set_of(found)
                            for key in pairs(created_set) do
                                assert.is_true(found_set[key] ~= nil,
                                    ("S=%d dist=%d ang=%d target=%s lost %s")
                                        :format(degree, dist, ang, orbit.key(target), key))
                            end
                            for key in pairs(found_set) do
                                assert.is_true(created_set[key] ~= nil,
                                    ("S=%d dist=%d ang=%d target=%s invented %s")
                                        :format(degree, dist, ang, orbit.key(target), key))
                            end
                            checked = checked + 1
                        end
                    end
                end
            end
        end
        assert.is_true(checked > 10000, "expected a broad survey, only did " .. checked)
    end)

    it("still finds the survivors when some siblings are already gone", function()
        for _, degree in ipairs{ 5, 6, 7 } do
            for dist = 3, 12 do
                local created = orbit.positions(CENTRE, seed_at(dist, 3), degree, snap)
                local target = created[1]
                -- keep only every other sibling
                local present, expected = {}, {}
                for n = 2, degree, 2 do
                    present[orbit.key(created[n])] = true
                    expected[orbit.key(created[n])] = true
                end
                local found = set_of(orbit.choose(
                    CENTRE, target, degree, snap, occupancy(present)))
                for key in pairs(expected) do
                    assert.is_true(found[key] ~= nil,
                        ("S=%d lost surviving sibling %s"):format(degree, key))
                end
            end
        end
    end)

    it("falls back to the target alone when nothing else is there", function()
        local target = seed_at(6, 1)
        local found = orbit.choose(CENTRE, target, 7, snap, function() return nil end)
        assert.is_true(#found >= 1)
    end)
end)

describe("the placement grid", function()
    it("centres odd-sized entities on a tile and even-sized ones on a corner", function()
        local odd, even = orbit.snapper(1, 1), orbit.snapper(2, 2)
        assert.equal(3.5, odd({ x = 3.4, y = 0 }).x)
        assert.equal(3.0, even({ x = 3.4, y = 0 }).x)
    end)
end)
