local geometry = require("lib.geometry")

local N, NE, E, SE, S, SW, W, NW = 0, 2, 4, 6, 8, 10, 12, 14
local NNE, NNW = 1, 15

describe("orientation and direction conversion", function()
    it("round-trips every direction", function()
        for dir = 0, 15 do
            assert.equal(dir, geometry.orientation_to_direction(geometry.direction_to_orientation[dir]))
        end
    end)

    it("maps the cardinals to quarter turns", function()
        assert.equal(0.00, geometry.direction_to_orientation[N])
        assert.equal(0.25, geometry.direction_to_orientation[E])
        assert.equal(0.50, geometry.direction_to_orientation[S])
        assert.equal(0.75, geometry.direction_to_orientation[W])
    end)

    it("rounds to the nearest direction", function()
        assert.equal(E, geometry.orientation_to_direction(0.25 + 0.01))
        assert.equal(E, geometry.orientation_to_direction(0.25 - 0.01))
    end)
end)

describe("flip_h", function()
    it("mirrors east and west and leaves north and south alone", function()
        assert.equal(W, (geometry.flip_h(E, 0.25, false)))
        assert.equal(E, (geometry.flip_h(W, 0.75, false)))
        assert.equal(N, (geometry.flip_h(N, 0.00, false)))
        assert.equal(S, (geometry.flip_h(S, 0.50, false)))
    end)

    it("mirrors the diagonals", function()
        assert.equal(NW, (geometry.flip_h(NE, 0.125, false)))
        assert.equal(SW, (geometry.flip_h(SE, 0.375, false)))
    end)

    it("is its own inverse", function()
        for dir = 0, 15 do
            local d2, o2 = geometry.flip_h(dir, geometry.direction_to_orientation[dir], false)
            local d3 = geometry.flip_h(d2, o2, false)
            assert.equal(dir, d3)
        end
    end)
end)

describe("flip_v", function()
    it("mirrors north and south and leaves east and west alone", function()
        assert.equal(S, (geometry.flip_v(N, 0.00, false)))
        assert.equal(N, (geometry.flip_v(S, 0.50, false)))
        assert.equal(E, (geometry.flip_v(E, 0.25, false)))
        assert.equal(W, (geometry.flip_v(W, 0.75, false)))
    end)

    it("mirrors the diagonals", function()
        assert.equal(SE, (geometry.flip_v(NE, 0.125, false)))
        assert.equal(NW, (geometry.flip_v(SW, 0.625, false)))
    end)

    it("is its own inverse", function()
        for dir = 0, 15 do
            local d2, o2 = geometry.flip_v(dir, geometry.direction_to_orientation[dir], false)
            local d3 = geometry.flip_v(d2, o2, false)
            assert.equal(dir, d3)
        end
    end)
end)

describe("orient_position_relative", function()
    local centre = { x = 0, y = 0 }

    it("leaves a position alone at orientation 0", function()
        local p = geometry.orient_position_relative(centre, { x = 3, y = 4 }, 0)
        assert.equal(3, p.x); assert.equal(4, p.y)
    end)

    it("turns a quarter clockwise: east becomes south", function()
        local p = geometry.orient_position_relative(centre, { x = 1, y = 0 }, 0.25)
        assert.near(0, p.x, 1e-9); assert.near(1, p.y, 1e-9)
    end)

    it("turns a half: a point ends up opposite", function()
        local p = geometry.orient_position_relative(centre, { x = 2, y = 3 }, 0.5)
        assert.near(-2, p.x, 1e-9); assert.near(-3, p.y, 1e-9)
    end)

    it("orbits around a centre that is not the origin", function()
        local p = geometry.orient_position_relative({ x = 10, y = 10 }, { x = 11, y = 10 }, 0.5)
        assert.near(9, p.x, 1e-9); assert.near(10, p.y, 1e-9)
    end)

    it("does not mutate the position it was given", function()
        local pos = { x = 5, y = 6 }
        geometry.orient_position_relative(centre, pos, 0.25)
        assert.equal(5, pos.x); assert.equal(6, pos.y)
    end)
end)
