--- Issue #10's fluid half. "Rotating" a building with several fluid inputs is rotation and
--- mirroring; there is no separate cycling in vanilla. Rotation already worked. Mirroring
--- was decided by a hardcoded list of four entity names, which missed most of the game --
--- a mirrored foundry kept its inputs on the original side.
local world = require("test.ft.world")

--- signal-S negative is a mirror bitmask: 1 = across the Y axis, 2 = across the X axis.
local MIRROR_X = -1

describe("mirroring a building with fluid inputs", function()
    it("mirrors an entity the old hardcoded list knew about", function()
        local patch = world.patch{ symmetry = MIRROR_X }
        local placed = patch.build({ x = 6, y = 0 }, "chemical-plant")
        local mirrored = 0
        for _, copy in pairs(patch.copies("chemical-plant")) do
            if copy ~= placed and copy.mirroring then mirrored = mirrored + 1 end
        end
        assert(mirrored == 1, "expected the chemical plant copy to be mirrored")
    end)

    it("mirrors one it did not: the foundry", function()
        local patch = world.patch{ symmetry = MIRROR_X }
        -- A crafting machine only has fluid connections once its recipe calls for them,
        -- so mirroring is meaningless until a fluid recipe is set.
        local placed = patch.build_blueprint({ x = 8, y = 0 }, "foundry",
            function(e) e.set_recipe("casting-iron") end)
        local copies, mirrored = 0, 0
        for _, copy in pairs(patch.copies("foundry")) do
            if copy ~= placed then
                copies = copies + 1
                if copy.mirroring then mirrored = mirrored + 1 end
            end
        end
        local proto = prototypes.entity["foundry"]
        local detail = ("use_mirroring=%s source.mirroring=%s copies=%d mirrored=%d")
            :format(tostring(proto.use_mirroring), tostring(placed.mirroring), copies, mirrored)
        assert(copies == 1, "expected one foundry copy, found " .. copies .. "; " .. detail)
        assert(mirrored == 1, "the foundry copy was not mirrored; " .. detail)
    end)

    it("leaves an entity that cannot be mirrored alone", function()
        local patch = world.patch{ symmetry = MIRROR_X }
        local placed = patch.build({ x = 6, y = 0 }, "centrifuge")
        for _, copy in pairs(patch.copies("centrifuge")) do
            if copy ~= placed then
                assert(not copy.mirroring,
                    "a centrifuge cannot be mirrored, but the copy claims to be")
            end
        end
    end)
end)
