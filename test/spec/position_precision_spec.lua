local geometry = require("lib.geometry")

--- Issue #2: "Removing items with weird Symmetry value doesn't work" -- with S=2 or S=4
--- the copies are removed, with S=6 only one or two of five are, and with S=7 none are.
---
--- The removal path in control.lua finds candidates in a 1x1 box around the expected
--- position and then requires an exact match:
---     found_entity.position.x == positions[n].x
--- Factorio stores entity positions snapped to a 1/256 grid. A rotation by a quarter turn
--- is computed by swapping and negating coordinates, so it stays exact and the comparison
--- holds. Any other rotation goes through sin/cos and lands between grid points, so the
--- recomputed float can never equal the stored position, and the copy is never matched.
---
--- That predicts exactly the reported symptom, which is what these tests pin down.

local GRID = 1 / 256
local function on_grid(v) return math.abs(v / GRID - math.floor(v / GRID + 0.5)) < 1e-9 end

local centre = { x = 0, y = 0 }
local start  = { x = 3, y = 0 }

describe("rotational symmetry and the position grid", function()
    it("keeps quarter turns exact, which is why S=2 and S=4 work", function()
        for _, s in ipairs{ 2, 4 } do
            for r = 1, s - 1 do
                local p = geometry.orient_position_relative(centre, start, r / s)
                assert.is_true(on_grid(p.x) and on_grid(p.y),
                    ("S=%d step %d landed off-grid at %.6f, %.6f"):format(s, r, p.x, p.y))
            end
        end
    end)

    it("puts most S=6 steps off the grid, which is why only some are removed", function()
        local off = 0
        for r = 1, 5 do
            local p = geometry.orient_position_relative(centre, start, r / 6)
            if not (on_grid(p.x) and on_grid(p.y)) then off = off + 1 end
        end
        -- r=3 is a half turn and stays exact; the other four do not
        assert.equal(4, off)
    end)

    it("puts every S=7 step off the grid, which is why none are removed", function()
        local off = 0
        for r = 1, 6 do
            local p = geometry.orient_position_relative(centre, start, r / 7)
            if not (on_grid(p.x) and on_grid(p.y)) then off = off + 1 end
        end
        assert.equal(6, off)
    end)

    it("shows the size of the mismatch: far below the 1x1 search box, far above equality", function()
        local p = geometry.orient_position_relative(centre, start, 1 / 7)
        local snapped_x = math.floor(p.x / GRID + 0.5) * GRID
        local drift = math.abs(p.x - snapped_x)
        assert.is_true(drift > 0, "expected the computed position to miss the grid")
        assert.is_true(drift < 0.5, "the copy is inside the search box, so only the equality test rejects it")
    end)
end)
