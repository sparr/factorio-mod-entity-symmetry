--- Issue #13: a player without the materials gets ghost copies, and removing the original
--- leaves them behind. The removal path filters candidates by the removed entity's own
--- name, and a ghost is named entity-ghost with the real name in ghost_name, so a real
--- entity never matches its ghost copies.
local world = require("test.ft.world")

describe("copies placed as ghosts", function()
    it("appear when the player cannot pay for them", function()
        local patch = world.patch{ symmetry = 4, cheat = false }
        patch.build{ x = 5, y = 0 }
        assert(#patch.ghosts() == 3,
            "expected 3 ghost copies, found " .. #patch.ghosts())
    end)

    it("are removed along with the entity that produced them", function()
        local patch = world.patch{ symmetry = 4, cheat = false }
        local placed = patch.build{ x = 5, y = 0 }
        assert(#patch.ghosts() == 3, "setup: expected 3 ghosts")
        patch.mine(placed)
        local left = patch.ghosts()
        assert(#left == 0, "expected the ghost copies to go too, " .. #left .. " remain")
    end)

    it("are removed for a symmetry that is not a quarter turn either", function()
        local patch = world.patch{ symmetry = 6, cheat = false }
        local placed = patch.build{ x = 5, y = 0 }
        assert(#patch.ghosts() == 5, "setup: expected 5 ghosts, got " .. #patch.ghosts())
        patch.mine(placed)
        assert(#patch.ghosts() == 0, "ghost copies remain after removal")
    end)
end)
