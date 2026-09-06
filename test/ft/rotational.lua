--- Rotational symmetry: what the mod builds, and what it removes again.
--- Issue #2 says removal works for S=2 and S=4 but not for S=6 or S=7.
local world = require("test.ft.world")

describe("rotational symmetry", function()
    for _, degree in ipairs{ 2, 4, 6, 7 } do
        it("builds " .. degree .. " copies for S=" .. degree, function()
            local patch = world.patch{ symmetry = degree }
            patch.build{ x = 5, y = 0 }
            local copies = patch.copies()
            assert(#copies == degree,
                ("S=%d should leave %d entities, found %d"):format(degree, degree, #copies))
        end)

        it("removes every copy again for S=" .. degree, function()
            local patch = world.patch{ symmetry = degree }
            local placed = patch.build{ x = 5, y = 0 }
            assert(#patch.copies() == degree, "setup: wrong number built")
            patch.mine(placed)
            local left = patch.copies()
            assert(#left == 0,
                ("S=%d should remove all %d, but %d remain"):format(degree, degree, #left))
        end)
    end
end)
