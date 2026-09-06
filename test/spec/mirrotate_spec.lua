local geometry = require("lib.geometry")
local mirrotate = geometry.get_mirrotated_entity_dir_ori

local N, NE, E, SE, S, SW, W, NW = 0, 2, 4, 6, 8, 10, 12, 14

--- Signature reminder:
---   (entity_type, can_mirror, dir, ori, sym_x, sym_y, sym_diag_1, sym_diag_2, reori)
--- returns dir, ori, flip
local function plain(entity_type, dir, opts)
    opts = opts or {}
    return mirrotate(entity_type, opts.can_mirror or false, dir,
        geometry.direction_to_orientation[dir] or 0,
        opts.x or false, opts.y or false, opts.d1 or false, opts.d2 or false,
        opts.reori or 0)
end

describe("entities the mod does not know how to orient", function()
    it("returns a neutral result rather than guessing", function()
        local dir, ori, flip = plain("wooden-chest", N)
        assert.equal(0, dir); assert.equal(0, ori); assert.is_false(flip)
    end)
end)

describe("a four-way entity (inserter)", function()
    it("rotates a quarter turn clockwise", function()
        assert.equal(E, (plain("inserter", N, { reori = 0.25 })))
        assert.equal(S, (plain("inserter", E, { reori = 0.25 })))
        assert.equal(W, (plain("inserter", S, { reori = 0.25 })))
        assert.equal(N, (plain("inserter", W, { reori = 0.25 })))
    end)

    it("comes back to where it started after four quarter turns", function()
        local dir = N
        for _ = 1, 4 do dir = plain("inserter", dir, { reori = 0.25 }) end
        assert.equal(N, dir)
    end)

    it("mirrors across the Y axis", function()
        assert.equal(W, (plain("inserter", E, { x = true })))
        assert.equal(E, (plain("inserter", W, { x = true })))
        assert.equal(N, (plain("inserter", N, { x = true })))
    end)

    it("mirrors across the X axis", function()
        assert.equal(S, (plain("inserter", N, { y = true })))
        assert.equal(E, (plain("inserter", E, { y = true })))
    end)

    it("is unchanged by mirroring both ways twice", function()
        for _, dir in ipairs{ N, E, S, W } do
            local once = plain("inserter", dir, { x = true, y = true })
            local twice = plain("inserter", once, { x = true, y = true })
            assert.equal(dir, twice)
        end
    end)
end)

describe("a smoothly-rotating entity (car)", function()
    it("keeps a direction of zero and rotates the orientation", function()
        local dir, ori = mirrotate("car", "car", 0, 0.1, false, false, false, false, 0.25)
        assert.equal(0, dir)
        assert.near(0.35, ori, 1e-9)
    end)

    it("wraps past north", function()
        local _, ori = mirrotate("car", "car", 0, 0.9, false, false, false, false, 0.25)
        assert.near(0.15, ori, 1e-9)
    end)
end)

describe("a two-way entity (storage tank)", function()
    it("folds its direction into half a turn", function()
        for _, dir in ipairs{ N, E, S, W } do
            local out = plain("storage-tank", dir)
            assert.is_true(out < 8, "expected a direction below 8, got " .. tostring(out))
        end
    end)

    it("treats opposite directions as the same", function()
        assert.equal((plain("storage-tank", N)), (plain("storage-tank", S)))
        assert.equal((plain("storage-tank", E)), (plain("storage-tank", W)))
    end)
end)

describe("the flip flag", function()
    it("is set for a mirrorable entity mirrored once", function()
        local _, _, flip = plain("assembling-machine", N, { can_mirror = true, x = true })
        assert.is_true(flip)
    end)

    it("is clear for a mirrorable entity mirrored twice", function()
        local _, _, flip = plain("assembling-machine", N, { can_mirror = true, x = true, y = true })
        assert.is_false(flip)
    end)

    it("is clear for an entity that cannot be mirrored", function()
        local _, _, flip = plain("inserter", N, { x = true })
        assert.is_false(flip)
    end)
end)

describe("rail signals", function()
    it("turn around when mirrored, since a mirrored signal faces the other way", function()
        -- a signal is 16-way and mirrorable-by-rotation: mirroring once should not leave it
        -- pointing the same way it started
        local before = E
        local after = plain("rail-signal", before, { x = true })
        assert.not_equal(before, after)
    end)
end)
